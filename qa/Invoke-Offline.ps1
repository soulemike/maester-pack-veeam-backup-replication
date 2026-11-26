function New-VbrValidationBundle {
    [CmdletBinding()]
    param([string] $Root = (Split-Path $PSScriptRoot -Parent))
    # Validate a clean distributable, not local downloaded dependencies or test result directories.
    $bundle = Join-Path $Root ('.tools/validation/' + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $bundle -Force
    foreach ($item in @('helpers','connectors','tests','catalog','public','docs','README.md','LICENSE','maester-pack.json','maester-pack.guide.json')) {
        Copy-Item -LiteralPath (Join-Path $Root $item) -Destination $bundle -Recurse -Force
    }
    $bundle
}

function Invoke-VbrOfflineValidation {
    [CmdletBinding()]
    param()
    $root = Split-Path $PSScriptRoot -Parent
    if (-not (Get-Module Maester)) { throw 'Import the pinned Maester module before validation.' }
    if (-not (Get-Module Pester)) { throw 'Import pinned Pester 5.7.1 before validation.' }
    $bundle = New-VbrValidationBundle -Root $root
    $pack = Test-MtPack -Path $bundle
    if (-not $pack.IsValid) { $pack.Errors | Format-Table -AutoSize | Out-String | Write-Host; throw 'Native pack validation failed.' }
    $container = New-PesterContainer -ScriptBlock {
        . "$root/qa/unit/Capabilities.Tests.ps1"
        . "$root/qa/unit/Transport.Tests.ps1"
        Invoke-VbrCapabilityTests
        Invoke-VbrTransportTests
    } -Data @{ root = $root }
    $result = Invoke-Pester -Container $container -Output Detailed -PassThru
    if ($result.Result -ne 'Passed') { throw 'Offline unit/contract tests failed.' }
    [pscustomobject]@{ PackValid = $pack.IsValid; NativeTestCount = $pack.TestIds.Count
        UnitPassed = $result.PassedCount; UnitFailed = $result.FailedCount; Bundle = $bundle
        LiveVerified = $false; AzureProvisioned = $false }
}
