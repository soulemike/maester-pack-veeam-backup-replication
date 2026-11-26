# Private to the native pack module. Only function definitions are permitted at load.

function ConvertFrom-VbrJson {
    param([Parameter(Mandatory)][string] $Json)
    # System.Text.Json preserves timestamp strings on PowerShell 7.4 as well as 7.5.
    function ConvertElement([System.Text.Json.JsonElement] $Element) {
        switch ($Element.ValueKind.ToString()) {
            Object {
                $value = [ordered]@{}
                foreach ($property in $Element.EnumerateObject()) {
                    if ($value.Contains($property.Name)) { throw 'VBR.InvalidJson' }
                    $value[$property.Name] = ConvertElement $property.Value
                }
                return $value
            }
            Array {
                $items = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $Element.EnumerateArray()) { $items.Add((ConvertElement $item)) }
                return ,$items.ToArray()
            }
            String { return $Element.GetString() }
            Number {
                $integer = 0
                if ($Element.TryGetInt32([ref]$integer)) { return $integer }
                return $Element.GetDouble()
            }
            True { return $true }
            False { return $false }
            Null { return $null }
            default { throw 'VBR.InvalidJson' }
        }
    }
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Json)
        ConvertElement $document.RootElement
    } catch { throw 'VBR.InvalidJson' } finally { if ($document) { $document.Dispose() } }
}

function Clear-VbrCache {
    [CmdletBinding()]
    param()
    if ($script:VbrScope) { $script:VbrScope.Entries.Clear(); $script:VbrScope.Bytes = 0 }
}

function Get-VbrConnectionDescription {
    [CmdletBinding()]
    param()
    if (-not $script:VbrSession) { return $null }
    [pscustomobject]@{
        Service = 'VBR.RestApi'; Origin = $script:VbrSession.Origin.AbsoluteUri
        Principal = $script:VbrSession.Principal; Profile = $script:VbrSession.Profile
        Generation = $script:VbrSession.Generation; ApiRevision = '1.3-rev2'
        ServerIdentity = $script:VbrSession.ServerIdentity
        ExpiresOn = $script:VbrSession.ExpiresOn
        Qualification = 'PublicSchemaVerified; live verification pending'
    }
}

function Initialize-VbrCatalog {
    # No runtime path override or registration hook. Extensions ship as reviewed pack files.
    $script:VbrPackRoot = Split-Path $PSScriptRoot -Parent
    $catalog = ConvertFrom-VbrJson ([System.IO.File]::ReadAllText((Join-Path $script:VbrPackRoot 'catalog/endpoints.json')))
    $operations = @{}
    $commands = @{}
    foreach ($entry in $catalog.Operations) {
        if ($entry.Id -notmatch '^[A-Za-z][A-Za-z0-9]+$' -or $operations.ContainsKey($entry.Id) -or
            $entry.Method -cne 'GET' -or $entry.Revision -cne '1.3-rev2' -or
            $entry.Path -notmatch '^/api/v1/[A-Za-z0-9/{}]+$' -or $entry.Path.Contains('//') -or
            $entry.Version -notmatch '^\d+$' -or $entry.Adapter -notmatch '^[A-Za-z][A-Za-z0-9]+$' -or
            $entry.Representation -notin @('Json', 'Text', 'Binary') -or
            $entry.VerificationStatus -notin @('DocVerified', 'SwaggerVerified', 'LiveVerified', 'Pending') -or
            $entry.TtlSeconds -lt 0 -or $entry.TtlSeconds -gt 300) { throw 'VBR.InvalidEndpointCatalog' }
        $adapter = Get-Command "ConvertFrom-Vbr$($entry.Adapter)" -CommandType Function -ErrorAction Stop
        if ($adapter.Module -ne $ExecutionContext.SessionState.Module) { throw 'VBR.UntrustedAdapter' }
        if (-not $entry.Contains('RequestAdapter')) { $entry.RequestAdapter = if ($entry.Paged) { 'SkipLimit' } else { 'Singleton' } }
        if ($entry.RequestAdapter -notmatch '^[A-Za-z][A-Za-z0-9]+$') { throw 'VBR.UntrustedAdapter' }
        $requestAdapter = Get-Command "Get-Vbr$($entry.RequestAdapter)Parameters" -CommandType Function -ErrorAction Stop
        if ($requestAdapter.Module -ne $ExecutionContext.SessionState.Module) { throw 'VBR.UntrustedAdapter' }
        $commands[$entry.Id] = @{ Request = $requestAdapter; Response = $adapter }
        $operations[$entry.Id] = $entry
    }
    $script:VbrOperations = $operations
    $script:VbrAdapterCommands = $commands
}

function ConvertFrom-VbrSingleton {
    param($Payload, $Definition, [int] $Offset)
    if ($null -eq $Payload -or $Payload -isnot [System.Collections.IDictionary]) { throw 'VBR.InvalidSingleton' }
    foreach ($field in $Definition.RequiredFields) {
        if (-not $Payload.Contains($field) -or $null -eq $Payload[$field]) { throw 'VBR.IncompleteSchema' }
    }
    @{ Data = $Payload; Done = $true; Total = 1; NextState = $null }
}

function ConvertFrom-VbrSkipLimit {
    param($Payload, $Definition, [int] $Offset)
    if ($Payload -isnot [System.Collections.IDictionary] -or -not $Payload.Contains('data') -or
        $Payload.data -isnot [array] -or $Payload.pagination -isnot [System.Collections.IDictionary]) { throw 'VBR.InvalidCollection' }
    $pagination = $Payload.pagination
    foreach ($field in @('total', 'count')) {
        if (-not $pagination.Contains($field) -or $pagination[$field] -isnot [ValueType] -or $pagination[$field] -is [bool] -or
            $pagination[$field] -lt 0 -or $pagination[$field] % 1 -ne 0) { throw 'VBR.InvalidPagination' }
    }
    $count = $Payload.data.Count
    if (($pagination.Contains('skip') -and $pagination.skip -ne $Offset) -or $pagination.count -ne $count -or
        ($pagination.Contains('limit') -and ($pagination.limit -lt 1 -or $count -gt $pagination.limit)) -or $Offset + $count -gt $pagination.total -or
        ($count -eq 0 -and $Offset -lt $pagination.total)) { throw 'VBR.IncompletePagination' }
    foreach ($item in $Payload.data) {
        if ($item -isnot [System.Collections.IDictionary]) { throw 'VBR.IncompleteSchema' }
        foreach ($field in $Definition.RequiredFields) {
            if (-not $item.Contains($field) -or $null -eq $item[$field]) { throw 'VBR.IncompleteSchema' }
        }
    }
    @{ Data = $Payload.data; Done = ($Offset + $count -eq $pagination.total)
       Total = $pagination.total; NextState = $Offset + $count }
}

function ConvertFrom-VbrBestPractices {
    param($Payload, $Definition, [int] $Offset)
    if ($Payload -isnot [System.Collections.IDictionary] -or $Payload.items -isnot [array]) { throw 'VBR.IncompleteSchema' }
    foreach ($item in $Payload.items) {
        if ($item -isnot [System.Collections.IDictionary] -or -not $item.Contains('bestPractice') -or -not $item.Contains('status')) { throw 'VBR.IncompleteSchema' }
    }
    @{ Data = $Payload.items; Done = $true; Total = $Payload.items.Count; NextState = $null }
}

function Get-VbrSingletonParameters {
    param([hashtable] $Parameters, $PageState)
    @{} + $Parameters
}

function Get-VbrSkipLimitParameters {
    param([hashtable] $Parameters, $PageState)
    $request = @{} + $Parameters
    $request.skip = if ($null -eq $PageState) { 0 } else { [int]$PageState }
    $request.limit = 200
    $request
}
