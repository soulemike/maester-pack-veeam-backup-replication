# Offline, schema-contract-backed normalization. This is not target-build or live qualification.
function Get-VbrField {
    param($Value, [string[]]$Path)
    foreach ($part in $Path) {
        if ($null -eq $Value) { return $null }
        if ($Value -is [System.Collections.IDictionary]) {
            if (-not $Value.Contains($part)) { return $null }
            $Value = $Value[$part]
        } else {
            $prop = $Value.PSObject.Properties[$part]
            if ($null -eq $prop) { return $null }
            $Value = $prop.Value
        }
    }
    return $Value
}

function Test-VbrGuid {
    param($Value)
    $parsed = [guid]::Empty
    return ($Value -is [string] -and [guid]::TryParse($Value, [ref]$parsed) -and $parsed -ne [guid]::Empty)
}

function Get-VbrTypedBoolean {
    param($Value)
    if ($Value -is [bool]) { return [pscustomobject]@{ State = 'Supported'; Value = $Value } }
    return [pscustomobject]@{ State = 'Unknown'; Value = $null }
}

function Get-VbrTypedNumber {
    param($Value)
    if ($Value -is [byte] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        $number = [double]$Value
        if (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -ge 0) {
            return [pscustomobject]@{ State = 'Supported'; Value = $number }
        }
    }
    return [pscustomobject]@{ State = 'Unknown'; Value = $null }
}

function Get-VbrTimestamp {
    param($Value)
    $stamp = [DateTimeOffset]::MinValue
    # An offset is mandatory; never interpret an offsetless local timestamp as UTC.
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [string] -and $Value -match '(Z|[+-]\d{2}:\d{2})$' -and
        [DateTimeOffset]::TryParse($Value, [cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$stamp)) { return $stamp }
    return $null
}

function ConvertTo-VbrJobCapability {
    param([Parameter(Mandatory)]$Job, [Parameter(Mandatory)]$AcquiredAt)
    $kind = Get-VbrField $Job @('type')
    $family = switch -CaseSensitive ($kind) {
        'WindowsAgentBackup' { 'AgentWindows' }
        'LinuxAgentBackup' { 'AgentLinux' }
        'VSphereBackup' { 'VMware' }
        'HyperVBackup' { 'HyperV' }
        default { 'Unknown' }
    }
    $retention = Get-VbrField $Job @('storage', 'retentionPolicy')
    $unit = Get-VbrField $retention @('type')
    $quantity = Get-VbrField $retention @('quantity')
    $r = [pscustomobject]@{ State = 'Unknown'; Unit = $null; Value = $null }
    if (($unit -ceq 'Days' -or $unit -ceq 'RestorePoints') -and
        ($quantity -is [int] -or $quantity -is [long]) -and $quantity -ge 0) {
        $r = [pscustomobject]@{ State = 'Supported'; Unit = $unit; Value = $quantity }
    }
    $encryption = Get-VbrTypedBoolean (Get-VbrField $Job @('storage', 'advancedSettings', 'storageData', 'encryption', 'isEnabled'))
    $health = Get-VbrTypedBoolean (Get-VbrField $Job @('storage', 'advancedSettings', 'backupHealth', 'isEnabled'))
    $daily = Get-VbrTypedBoolean (Get-VbrField $Job @('schedule', 'daily', 'isEnabled'))
    $dailyKind = Get-VbrField $Job @('schedule', 'daily', 'dailyKind')
    if ($daily.State -eq 'Supported' -and $daily.Value) {
        if ($dailyKind -ceq 'Everyday') { }
        elseif ($dailyKind -ceq 'WeekDays') { $daily.Value = $false }
        elseif ($dailyKind -ceq 'SelectedDays') {
            $days = @(Get-VbrField $Job @('schedule', 'daily', 'days'))
            $daily.Value = (@('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') | Where-Object { $_ -notin $days }).Count -eq 0
        } else { $daily.State = 'Unknown'; $daily.Value = $null }
    }
    $auto = Get-VbrTypedBoolean (Get-VbrField $Job @('schedule', 'runAutomatically'))
    $disabled = Get-VbrTypedBoolean (Get-VbrField $Job @('isDisabled'))
    # The four supported job discriminators reference distinct models with the same common paths.
    # Unsupported is reserved for documented non-applicability, never a missing property.
    return [pscustomobject]@{
        Id = $(Get-VbrField $Job @('id')); Family = $family; JobType = $kind
        Schema = $(if ($family -eq 'Unknown') { 'Unknown' } else { 'JobModel/1.3-rev2' })
        SourceOperation = 'GetJob'; EvidenceType = 'DocSchemaContract'
        Qualification = 'SwaggerVerifiedPublicSchema;TargetBuildPending;LivePending'
        AcquiredAt = $AcquiredAt
        Retention = $r; Encryption = $encryption; Health = $health
        Daily = $daily; Automatic = $auto; Disabled = $disabled
        ApplicationAware = Get-VbrTypedBoolean (Get-VbrField $Job @('guestProcessing', 'appAwareProcessing', 'isEnabled'))
    }
}
