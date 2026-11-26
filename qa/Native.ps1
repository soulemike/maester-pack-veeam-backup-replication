function Invoke-VbrNativeValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Bundle)
    $root = Split-Path $PSScriptRoot -Parent
    $run = Join-Path $root ('.tools/native/' + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $run -Force
    $oldHome = $env:MAESTER_PACK_HOME; $oldTelemetry = $env:MAESTER_DISABLE_TELEMETRY
    $module = $null
    Push-Location $run
    try {
        $env:MAESTER_PACK_HOME = Join-Path $run 'packs'; $env:MAESTER_DISABLE_TELEMETRY = '1'
        $lock = Join-Path $run 'maester-packs.lock.json'
        $null = Install-MtPack -Source $Bundle -Scope Project -PackLock $lock -AcceptRisk High -NonInteractive -IncludeRecent
        # Introspection is QA-only: exercise the same installed private module and
        # native loader used by Connect-Maester and Invoke-Maester, without live login.
        $module = & (Get-Module Maester) {
            param($lock)
            $set = @(Initialize-MtPackSet -PackLock $lock)
            $pack = $set | Where-Object Id -EQ 'soulemike.veeam-backup-replication'
            if (-not $pack -or $pack.Status -ne 'Ready') { throw 'Installed pack is not Ready.' }
            Import-MtPackModule -Pack $pack -PackSet $set
        } $lock
        Add-Type -Path (Join-Path $PSScriptRoot 'MockHttp.cs')
        & $module {
            Initialize-VbrCatalog
            $script:handler = [VbrMockHttpHandler]::new()
            $script:VbrSession = @{ Origin = [uri]'https://vbr.example.net:9419'; Client = [Net.Http.HttpClient]::new($script:handler)
                Principal = 'synthetic-account'; Profile = 'ComprehensiveAdministrator'; Generation = [guid]::NewGuid().ToString()
                ServerIdentity = 'synthetic-server'; AccessToken = 'SENTINEL_ACCESS'; RefreshToken = 'SENTINEL_REFRESH'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Busy = $false }
            Set-VbrMaesterState
        }
        $invoke = @{ Pack = 'VBR'; SkipBuiltIn = $true; PackLock = $lock; NonInteractive = $true
            PassThru = $true; DisableTelemetry = $true; SkipVersionCheck = $true; OutputFolder = (Join-Path $run 'reports') }
        & $module { $script:handler.Enqueue(200,'{"vbrId":"11111111-1111-1111-1111-111111111111","buildVersion":"13.1.2.57"}') }
        $pass = Invoke-Maester @invoke -TestId MP.VBR.1001 -Config @{}
        & $module { $script:handler.Enqueue(200,'{"isEnabled":false}') }
        $fail = Invoke-Maester @invoke -TestId MP.VBR.2001 -Config @{}
        & $module { $script:VbrSession.Profile = 'OperationalReader' }
        $investigate = Invoke-Maester @invoke -TestId MP.VBR.2001 -Config @{}
        & $module { $script:VbrSession.Profile = 'ComprehensiveAdministrator'; $script:handler.Enqueue(403,'SENTINEL_PASSWORD') }
        $errorResult = Invoke-Maester @invoke -TestId MP.VBR.2001 -Config @{}
        $notRun = Invoke-Maester @invoke -TestId MP.VBR.2001 -Config @{} -DryRun
        Clear-MtConnectionState -Service VBR.RestApi
        $skipped = Invoke-Maester @invoke -TestId MP.VBR.2001 -Config @{}
        $actual = @(
            ($pass.Tests | Where-Object Id -EQ 'MP.VBR.1001').Result
            ($fail.Tests | Where-Object Id -EQ 'MP.VBR.2001').Result
            ($investigate.Tests | Where-Object Id -EQ 'MP.VBR.2001').Result
            ($errorResult.Tests | Where-Object Id -EQ 'MP.VBR.2001').Result
            ($skipped.Tests | Where-Object Id -EQ 'MP.VBR.2001').Result
            ($notRun.Tests | Where-Object Id -EQ 'MP.VBR.2001').Result
        )
        $expected = @('Passed','Failed','Investigate','Error','Skipped','NotRun')
        if (($actual -join ',') -ne ($expected -join ',')) { throw "Native outcome mismatch: $($actual -join ',')" }

        # Parameter precedence must be the engine's, not a pack-side overlay implementation.
        & $module { Set-VbrMaesterState; $script:handler.Enqueue(200,'{"vbrId":"11111111-1111-1111-1111-111111111111","buildVersion":"13.1.2.57"}') }
        $overlay = Invoke-Maester @invoke -TestId MP.VBR.1001 -Config @{ GlobalSettings = @{ 'VBR.MinimumServerBuild' = '13.1.2.58' } }
        if (($overlay.Tests | Where-Object Id -EQ 'MP.VBR.1001').Result -ne 'Failed') { throw 'Native GlobalSettings binding was not applied.' }
        & $module { $script:handler.Enqueue(200,'{"vbrId":"11111111-1111-1111-1111-111111111111","buildVersion":"13.1.2.57"}') }
        $runtime = Invoke-MtTest -Id MP.VBR.1001 -Parameter @{ MinimumServerBuild = '13.1.2.57' } -Config @{ GlobalSettings = @{ 'VBR.MinimumServerBuild' = '13.1.2.58' } }
        if ($runtime.Result -ne 'Passed') { throw 'Native runtime parameter precedence was not applied.' }
        & $module {
            $script:handler.Requests.Clear()
            $script:handler.Enqueue(200,'{"isEnabled":true,"encryption":{"isEnabled":true}}')
            Set-VbrMaesterState
        }
        . (Join-Path $root 'public/Invoke-VbrAssessment.ps1')
        $cached = Invoke-VbrAssessment -TestId MP.VBR.2001,MP.VBR.4001 -Config @{} -OutputFolder (Join-Path $run 'cache-report') -PassThru
        $requests = & $module { $script:handler.Requests.Count }
        if ($requests -ne 1 -or @($cached.Tests | Where-Object { $_.Id -in @('MP.VBR.2001','MP.VBR.4001') -and $_.Result -ne 'Passed' }).Count) { throw 'Native wrapper cache did not span the selected tests.' }
        & $module { $script:handler.Enqueue(200,'{"isEnabled":true,"encryption":{"isEnabled":true}}') }
        $second = Invoke-VbrAssessment -TestId MP.VBR.2001,MP.VBR.4001 -Config @{} -OutputFolder (Join-Path $run 'cache-report-2') -PassThru
        if ((& $module { $script:handler.Requests.Count }) -ne 2) { throw 'A second native assessment reused stale cache.' }
        & $module { $script:handler.Enqueue(200,'{"isEnabled":true}'); $script:handler.Enqueue(200,'{"isEnabled":true}') }
        $null = Invoke-MtTest -Id MP.VBR.2001 -Config @{}
        $null = Invoke-MtTest -Id MP.VBR.2001 -Config @{}
        if ((& $module { $script:handler.Requests.Count }) -ne 4) { throw 'Direct native calls used implicit caching.' }
        foreach ($file in Get-ChildItem -Path $run -Recurse -File | Where-Object Extension -In '.json','.html','.md') {
            if ([IO.File]::ReadAllText($file.FullName) -match 'SENTINEL_(ACCESS|REFRESH|PASSWORD)') { throw 'Synthetic secret appeared in native artifacts.' }
        }
        $description = & $module { Get-VbrConnectionDescription | ConvertTo-Json }
        $state = Get-MtConnectionState -Service VBR.RestApi | ConvertTo-Json -Depth 5
        if (($description + $state) -match 'SENTINEL_') { throw 'Synthetic secret appeared in connection metadata.' }
        [pscustomobject]@{ NativeOutcomes = $actual; CacheRequestsAcrossTwoRuns = 2
            DirectCallsUncached = $true; NativePrecedence = $true; Artifacts = $run; LiveVerified = $false }
    } finally {
        if ($module) { & $module { if ($script:VbrSession) { $script:VbrSession.Client.Dispose() }; $script:VbrSession = $null; Clear-VbrCache; $script:VbrScope = $null } }
        Clear-MtConnectionState -Service VBR.RestApi -ErrorAction SilentlyContinue
        $env:MAESTER_PACK_HOME = $oldHome; $env:MAESTER_DISABLE_TELEMETRY = $oldTelemetry
        Pop-Location
    }
}
