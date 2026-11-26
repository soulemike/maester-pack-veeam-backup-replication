function Invoke-VbrHttp {
    # Only called by the transport and the explicit authentication lifecycle.
    param($Session, [uri] $Uri, [string] $Method, $Form,
          [System.Threading.CancellationToken] $CancellationToken, [int] $MaximumBytes = 4194304)
    if ($Uri.Scheme -cne 'https' -or $Uri.GetLeftPart([System.UriPartial]::Authority) -cne
        $Session.Origin.GetLeftPart([System.UriPartial]::Authority) -or $Uri.UserInfo -or $Uri.Fragment) { throw 'VBR.UnsafeOrigin' }
    $request = $null; $response = $null; $stream = $null; $buffer = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
        $request.Headers.Add('x-api-version', '1.3-rev2')
        $request.Headers.Accept.ParseAdd('application/json')
        if ($Session.AccessToken) {
            $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Session.AccessToken)
        }
        if ($Form) {
            $pairs = [System.Collections.Generic.Dictionary[string,string]]::new()
            foreach ($key in $Form.Keys) { $pairs.Add($key, [string]$Form[$key]) }
            $request.Content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
        }
        $response = $Session.Client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $CancellationToken).GetAwaiter().GetResult()
        $status = [int]$response.StatusCode
        $retrySeconds = 0
        if ($response.Headers.RetryAfter) {
            if ($null -ne $response.Headers.RetryAfter.Delta) { $retrySeconds = ([TimeSpan]$response.Headers.RetryAfter.Delta).TotalSeconds }
            elseif ($null -ne $response.Headers.RetryAfter.Date) { $retrySeconds = ([DateTimeOffset]$response.Headers.RetryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds }
        }
        # Never read or surface an error/redirect body; it may contain secrets.
        if ($status -lt 200 -or $status -ge 300) { return @{ Status = $status; RetrySeconds = [Math]::Max(0, $retrySeconds); Bytes = $null } }
        if ($response.Content.Headers.ContentLength -gt $MaximumBytes) { throw 'VBR.ResponseLimit' }
        $stream = $response.Content.ReadAsStreamAsync($CancellationToken).GetAwaiter().GetResult()
        $buffer = [System.IO.MemoryStream]::new()
        $chunk = [byte[]]::new(16384)
        while (($read = $stream.ReadAsync($chunk, 0, $chunk.Length, $CancellationToken).GetAwaiter().GetResult()) -gt 0) {
            if ($buffer.Length + $read -gt $MaximumBytes) { throw 'VBR.ResponseLimit' }
            $buffer.Write($chunk, 0, $read)
        }
        @{ Status = $status; RetrySeconds = 0; Bytes = $buffer.ToArray() }
    } catch {
        # Do not attach the original exception, URI, token, form or response as a target/inner exception.
        if ($_.Exception.Message -eq 'VBR.ResponseLimit') { throw 'VBR.ResponseLimit' }
        throw 'VBR.TransportFailure'
    } finally {
        if ($buffer) { $buffer.Dispose() }; if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }; if ($request) { $request.Dispose() }
    }
}

function Set-VbrToken {
    param($Session, $Form, [System.Threading.CancellationToken] $CancellationToken)
    $reply = Invoke-VbrHttp $Session ([uri]::new($Session.Origin, '/api/oauth2/token')) POST $Form $CancellationToken 65536
    if ($reply.Status -ne 200) { throw 'VBR.AuthenticationFailed' }
    $token = ConvertFrom-VbrJson ([System.Text.Encoding]::UTF8.GetString($reply.Bytes))
    if ($token.access_token -isnot [string] -or -not $token.access_token -or
        $token.refresh_token -isnot [string] -or -not $token.refresh_token -or
        $token.token_type -ine 'bearer' -or ($token.expires_in -isnot [int] -and $token.expires_in -isnot [double]) -or
        $token.expires_in -lt 1 -or $token.expires_in -gt 86400) { throw 'VBR.InvalidAuthenticationResponse' }
    $Session.AccessToken = $token.access_token
    $Session.RefreshToken = $token.refresh_token
    $Session.ExpiresOn = [DateTimeOffset]::UtcNow.AddSeconds($token.expires_in)
    if ($script:VbrSession -and $script:VbrSession.Generation -eq $Session.Generation) { Set-VbrMaesterState }
}

function Update-VbrConnection {
    [CmdletBinding()]
    param()
    if (-not $script:VbrSession) { throw 'VBR.NotConnected' }
    $deadline = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
    try { Set-VbrToken $script:VbrSession @{ grant_type = 'refresh_token'; refresh_token = $script:VbrSession.RefreshToken } $deadline.Token }
    catch { Clear-VbrCache; throw 'VBR.RenewalFailed' }
    finally { $deadline.Dispose() }
    Set-VbrMaesterState
}

function Resolve-VbrOperationUri {
    param($Session, $Definition, [hashtable] $Parameters)
    $path = [string]$Definition.Path; $query = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Parameters.Keys) {
        if (-not $Definition.Parameters.Contains($name)) { throw 'VBR.InvalidParameter' }
        $rule = $Definition.Parameters[$name]; $value = $Parameters[$name]
        switch ($rule.Type) {
            Guid {
                $parsed = [guid]::Empty
                if (-not [guid]::TryParse([string]$value, [ref]$parsed) -or $parsed -eq [guid]::Empty) { throw 'VBR.InvalidParameter' }
                $encoded = $parsed.ToString('D')
            }
            Integer {
                if ($value -isnot [int] -or $value -lt $rule.Minimum -or $value -gt $rule.Maximum) { throw 'VBR.InvalidParameter' }
                $encoded = $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            String {
                if ($value -isnot [string] -or $value.Length -gt $rule.MaximumLength -or
                    -not [regex]::IsMatch($value, $rule.Pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromMilliseconds(100)) -or
                    ($rule.AllowedValues -and $value -cnotin $rule.AllowedValues) -or $value -in @('.', '..')) { throw 'VBR.InvalidParameter' }
                $encoded = [uri]::EscapeDataString($value)
            }
            Boolean {
                if ($value -isnot [bool]) { throw 'VBR.InvalidParameter' }
                $encoded = $value.ToString().ToLowerInvariant()
            }
            default { throw 'VBR.InvalidParameterContract' }
        }
        if ($rule.Location -eq 'Path') { $path = $path.Replace("{$name}", $encoded) }
        elseif ($rule.Location -eq 'Query') { $query.Add("$name=$encoded") }
        else { throw 'VBR.InvalidParameterContract' }
    }
    if ($path -notmatch '^/api/v1/[A-Za-z0-9/-]+$' -or $path.Contains('//')) { throw 'VBR.InvalidPath' }
    $suffix = if ($query.Count) { '?' + (($query | Sort-Object) -join '&') } else { '' }
    [uri]::new($Session.Origin, $path + $suffix)
}

function Invoke-VbrRestRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $OperationId, [hashtable] $Parameters = @{},
          [switch] $BypassCache, [ValidateRange(1,300)][int] $TimeoutSeconds = 60,
          [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None)
    if (-not $script:VbrSession) { throw 'VBR.NotConnected' }
    if (-not $script:VbrOperations.ContainsKey($OperationId)) { throw 'VBR.UnregisteredOperation' }
    $session = $script:VbrSession; $definition = $script:VbrOperations[$OperationId]
    $adapters = $script:VbrAdapterCommands[$OperationId]
    if (-not $adapters) { throw 'VBR.UnregisteredAdapter' }
    if ($definition.AdminOnly -and $session.Profile -ne 'ComprehensiveAdministrator') { throw 'VBR.AdminProfileRequired' }
    if ($session.Busy) { throw 'VBR.ConcurrentRequestUnsupported' }
    $session.Busy = $true
    $deadline = [System.Threading.CancellationTokenSource]::CreateLinkedTokenSource($CancellationToken)
    $deadline.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
    try {
        $uri = Resolve-VbrOperationUri $session $definition $Parameters
        # Only the live wrapper's stack may use a scope; direct native invocations are uncached.
        $scope = $script:VbrScope
        if ($scope -and (-not ((Get-PSCallStack).Command -contains 'Invoke-VbrScopedAssessment') -or
            $scope.Generation -ne $session.Generation)) { $scope = $null }
        $key = "$($session.Generation)|$($session.Principal)|$($session.Profile)|$($session.ServerIdentity)|$($uri.AbsoluteUri)|$OperationId|$($definition.Version)|$($definition.Adapter)|$($definition.AdapterVersion)|$($definition.RequestAdapter)|$($definition.Revision)|$($definition.Method)|$($definition.Representation)"
        if ($scope -and -not $BypassCache -and $scope.Entries.Contains($key)) {
            $cached = $scope.Entries[$key]
            if ([DateTimeOffset]::UtcNow -lt $cached.ExpiresOn) {
                $result = ConvertFrom-VbrJson $cached.Json; $result.CacheHit = $true
                return [pscustomobject]$result
            }
            $scope.Bytes -= $cached.Size; $scope.Entries.Remove($key)
        }
        if ($BypassCache -and $scope -and $scope.Entries.Contains($key)) {
            $scope.Bytes -= $scope.Entries[$key].Size; $scope.Entries.Remove($key)
        }
        $acquired = [DateTimeOffset]::UtcNow
        $refreshed = $false
        if ($session.ExpiresOn -lt $acquired.AddSeconds(30)) {
            Set-VbrToken $session @{ grant_type = 'refresh_token'; refresh_token = $session.RefreshToken } $deadline.Token
            $refreshed = $true
        }
        $pageState = $null; $total = -1; $aggregateBytes = 0
        $items = [System.Collections.Generic.List[object]]::new()
        $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $progress = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for ($page = 0; $page -lt 1024; $page++) {
            $deadline.Token.ThrowIfCancellationRequested()
            $pageParameters = & $adapters.Request $Parameters $pageState
            $uri = Resolve-VbrOperationUri $session $definition $pageParameters
            $attempt = 0
            while ($true) {
                $reply = Invoke-VbrHttp $session $uri GET $null $deadline.Token
                if ($reply.Status -eq 401 -and -not $refreshed) {
                    Clear-VbrCache
                    Set-VbrToken $session @{ grant_type = 'refresh_token'; refresh_token = $session.RefreshToken } $deadline.Token
                    $refreshed = $true; continue
                }
                if ($reply.Status -eq 403) { throw 'VBR.PermissionDenied' }
                if ($reply.Status -in @(429, 500, 502, 503, 504) -and $attempt -lt 2) {
                    $delay = [Math]::Max([Math]::Pow(2, $attempt), $reply.RetrySeconds)
                    if ($delay -gt $TimeoutSeconds) { throw 'VBR.RetryDeadlineExceeded' }
                    [System.Threading.Tasks.Task]::Delay([TimeSpan]::FromSeconds($delay), $deadline.Token).GetAwaiter().GetResult()
                    $attempt++; continue
                }
                if ($reply.Status -lt 200 -or $reply.Status -ge 300) { throw "VBR.HttpStatus.$($reply.Status)" }
                break
            }
            $aggregateBytes += $reply.Bytes.Length
            if ($aggregateBytes -gt 33554432) { throw 'VBR.CollectionLimit' }
            $payload = switch ($definition.Representation) {
                Json { ConvertFrom-VbrJson ([System.Text.Encoding]::UTF8.GetString($reply.Bytes)) }
                Text { [System.Text.Encoding]::UTF8.GetString($reply.Bytes) }
                Binary { ,$reply.Bytes }
            }
            $converted = & $adapters.Response $payload $definition $pageState
            if ($converted.Done -isnot [bool] -or $converted.Total -isnot [ValueType] -or $converted.Total -is [bool] -or
                $converted.Total -lt 0 -or $converted.Total % 1 -ne 0) { throw 'VBR.InvalidAdapterResult' }
            if ($converted.Total -gt 100000 -or ($total -ge 0 -and $total -ne $converted.Total)) { throw 'VBR.ChangingCollection' }
            $total = $converted.Total
            if ($definition.Paged) {
                foreach ($item in $converted.Data) {
                    $id = [string]$item[$definition.IdentityField]
                    if (-not $id -or -not $ids.Add($id)) { throw 'VBR.DuplicateIdentity' }
                    $items.Add($item)
                }
            }
            if ($converted.Done) {
                if ($definition.Paged -and $items.Count -ne $total) { throw 'VBR.IncompletePagination' }
                break
            }
            $next = ConvertTo-Json -InputObject $converted.NextState -Depth 8 -Compress
            if (-not $definition.Paged -or $null -eq $converted.NextState -or $next.Length -gt 1024 -or
                -not $progress.Add($next)) { throw 'VBR.NonProgressingPagination' }
            $pageState = $converted.NextState
        }
        if (-not $converted.Done) { throw 'VBR.PageLimit' }
        $result = [ordered]@{
            Data = $(if ($definition.Paged) { ,$items.ToArray() } else { $converted.Data })
            Complete = $true; OperationId = $OperationId; ApiRevision = '1.3-rev2'
            AcquiredAt = $acquired.ToString('o'); CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
            Profile = $session.Profile; Principal = $session.Principal; ServerIdentity = $session.ServerIdentity
            VerificationStatus = $definition.VerificationStatus; CacheHit = $false
        }
        if ($scope -and $definition.TtlSeconds -gt 0 -and $definition.Representation -eq 'Json') {
            $json = ConvertTo-Json -InputObject $result -Depth 64 -Compress
            $size = [System.Text.Encoding]::UTF8.GetByteCount($json)
            if ($size -le 33554432) {
                while ($scope.Entries.Count -ge 128 -or $scope.Bytes + $size -gt 33554432) {
                    $oldest = $scope.Entries.Keys | Select-Object -First 1
                    $scope.Bytes -= $scope.Entries[$oldest].Size; $scope.Entries.Remove($oldest)
                }
                $scope.Entries[$key] = @{ Json = $json; Size = $size; ExpiresOn = $acquired.AddSeconds($definition.TtlSeconds) }
                $scope.Bytes += $size
            }
        }
        [pscustomobject]$result
    } catch {
        Clear-VbrCache
        $message = $_.Exception.Message
        if ($message -match '^VBR\.[A-Za-z0-9.]+$') { throw $message }
        throw 'VBR.RequestFailed'
    } finally { $deadline.Dispose(); $session.Busy = $false }
}

function Invoke-VbrScopedAssessment {
    [CmdletBinding()]
    param([string[]] $TestId = @('MP.VBR.*'), [object[]] $Config,
          [string] $OutputFolder, [switch] $PassThru)
    if (-not $script:VbrSession) { throw 'VBR.NotConnected' }
    if ($script:VbrScope) { throw 'VBR.NestedAssessmentUnsupported' }
    $script:VbrScope = @{ Id = [guid]::NewGuid().ToString(); Generation = $script:VbrSession.Generation
        Entries = [ordered]@{}; Bytes = 0 }
    try {
        $arguments = @{ Pack = 'VBR'; SkipBuiltIn = $true; TestId = $TestId; NonInteractive = $true
            DisableTelemetry = $true; SkipVersionCheck = $true; PassThru = $PassThru }
        if ($PSBoundParameters.ContainsKey('Config')) { $arguments.Config = $Config }
        if ($OutputFolder) { $arguments.OutputFolder = $OutputFolder }
        Invoke-Maester @arguments
    } finally { Clear-VbrCache; $script:VbrScope = $null }
}
