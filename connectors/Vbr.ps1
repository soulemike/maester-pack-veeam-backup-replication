function Connect-VbrRest {
    [CmdletBinding()]
    param([uri] $Server, [pscredential] $Credential,
          [ValidateSet('OperationalReader','ComprehensiveAdministrator')][string] $Profile = 'OperationalReader',
          [switch] $AllowAdministrator)
    if (-not $Server) { $Server = [uri](Get-MtSetting -Name 'VBR.Server') }
    if (-not $Credential) { $Credential = Get-Credential -Message 'Dedicated VBR REST account (never disable human MFA globally)' }
    if ($Profile -eq 'ComprehensiveAdministrator' -and -not $AllowAdministrator) { throw 'VBR.AdministratorOptInRequired' }
    if (-not $Server.IsAbsoluteUri -or $Server.Scheme -cne 'https' -or $Server.UserInfo -or
        $Server.AbsolutePath -ne '/' -or $Server.Query -or $Server.Fragment) { throw 'VBR.InvalidServerOrigin' }
    Disconnect-VbrRest
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false; $handler.UseCookies = $false; $handler.UseDefaultCredentials = $false
    $handler.UseProxy = $false
    $client = [System.Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    $session = @{ Origin = $Server; Client = $client; Principal = $Credential.UserName; Profile = $Profile
        Generation = [guid]::NewGuid().ToString(); AccessToken = $null; RefreshToken = $null
        ExpiresOn = [DateTimeOffset]::MinValue; ServerIdentity = ('Origin:' + $Server.AbsoluteUri); Busy = $false }
    $deadline = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
    try {
        Initialize-VbrCatalog
        $password = $Credential.GetNetworkCredential().Password
        Set-VbrToken $session @{ grant_type = 'password'; username = $Credential.UserName; password = $password } $deadline.Token
        $script:VbrSession = $session
        if ($Profile -eq 'ComprehensiveAdministrator') {
            $info = Invoke-VbrRestRequest -OperationId GetServerInfo -TimeoutSeconds 30
            $session.ServerIdentity = [string]$info.Data.vbrId
            if (-not (Test-VbrGuid $session.ServerIdentity)) { throw 'VBR.MissingServerIdentity' }
        } else {
            # /serverInfo is documented administrator-only. Never elevate for a smoke test.
            $null = Invoke-VbrRestRequest -OperationId GetAllJobs -TimeoutSeconds 30
        }
        Set-VbrMaesterState
    } catch {
        if ($session.AccessToken) {
            $script:VbrSession = $session
            Disconnect-VbrRest
        } else {
            $script:VbrSession = $null; $session.RefreshToken = $null
            $client.Dispose(); Clear-VbrCache
        }
        throw 'VBR.ConnectionFailed'
    } finally { $password = $null; $Credential = $null; $deadline.Dispose() }
}

function Set-VbrMaesterState {
    # Metadata and a bound, non-secret assessment entry point only. Never expose the
    # HttpClient, credentials, access/refresh tokens, cache, or a general module executor.
    $entryPoint = {
        param([string[]] $TestId = @('MP.VBR.*'), [object[]] $Config, [string] $OutputFolder, [switch] $PassThru)
        Invoke-VbrScopedAssessment @PSBoundParameters
    }
    Set-MtConnectionState -Service VBR.RestApi -Value @{
        Handle = $script:VbrSession.Generation; ExpiresOn = $script:VbrSession.ExpiresOn.UtcDateTime; Assess = $entryPoint
    } -Account $script:VbrSession.Principal -Tenant $script:VbrSession.ServerIdentity
}

function Test-VbrRest {
    [CmdletBinding()]
    param()
    if (-not $script:VbrSession) { return $false }
    $state = Get-MtConnectionState -Service VBR.RestApi
    if (-not $state -or $state.Handle -ne $script:VbrSession.Generation) { return $false }
    $true
}

function Disconnect-VbrRest {
    [CmdletBinding()]
    param()
    $session = $script:VbrSession
    $script:VbrSession = $null
    Clear-VbrCache
    if ($session) {
        $deadline = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(10))
        try { $null = Invoke-VbrHttp $session ([uri]::new($session.Origin, '/api/oauth2/logout')) POST $null $deadline.Token }
        catch { Write-Verbose 'VBR logout unavailable; local connection disposed.' }
        finally {
            $session.AccessToken = $null; $session.RefreshToken = $null
            $session.Client.Dispose(); $deadline.Dispose()
        }
    }
    Clear-MtConnectionState -Service VBR.RestApi
}
