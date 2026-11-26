# Verdicts are pure data until the native wrapper maps them to Maester outcomes.
function New-VbrVerdict {
    param([ValidateSet('Pass','Fail','Investigate')][string]$Status, [string]$Reason,
        [object[]]$ObjectIds = @(), $Measured = $null, $Threshold = $null, $AcquiredAt = $null)
    return [pscustomobject]@{ Status = $Status; Reason = $Reason; ObjectIds = @($ObjectIds)
        Measured = $Measured; Threshold = $Threshold; AcquiredAt = $AcquiredAt
        EvidenceType = 'DocSchemaContract'; Baseline = 'VBR.v0.1' }
}

function Test-VbrInventory {
    param([string[]]$ExpectedIds, [object[]]$Actual, [string]$IdProperty = 'Id')
    if (-not $ExpectedIds -or $ExpectedIds.Count -eq 0) { return (New-VbrVerdict Investigate 'Expected inventory is not configured.') }
    $seen = [collections.generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Actual) {
        $id = Get-VbrField $item @($IdProperty)
        if (-not (Test-VbrGuid $id) -or -not $seen.Add($id)) { return (New-VbrVerdict Investigate 'Inventory contains an invalid or duplicate identifier.') }
    }
    $missing = @($ExpectedIds | Where-Object { -not (Test-VbrGuid $_) -or -not $seen.Contains($_) })
    if ($missing.Count) { return (New-VbrVerdict Investigate 'Expected inventory is not fully visible.' $missing) }
    return (New-VbrVerdict Pass 'Expected inventory is visible.' $ExpectedIds)
}

function Test-VbrJobPolicy {
    param([object[]]$Jobs, [string[]]$ExpectedJobIds, [ValidateSet('Days','RestorePoints','Encryption','Daily','Health','ApplicationAware')]$Check,
        [int]$Minimum = 14, [string[]]$ClassifiedJobIds = @())
    $inventory = Test-VbrInventory $ExpectedJobIds $Jobs
    if ($inventory.Status -ne 'Pass') { return $inventory }
    $fail = @(); $unknown = @(); $measured = @()
    foreach ($id in $ExpectedJobIds) {
        $job = @($Jobs | Where-Object { $_.Id -eq $id })[0]
        if ($job.Family -eq 'Unknown') { $unknown += $id; continue }
        switch ($Check) {
            'Days' { $value = $job.Retention; $needed = 'Days' }
            'RestorePoints' { $value = $job.Retention; $needed = 'RestorePoints' }
            'Encryption' { $value = $job.Encryption }
            'Daily' { $value = $job.Daily }
            'Health' { $value = $job.Health }
            'ApplicationAware' { $value = $job.ApplicationAware }
        }
        if ($Check -eq 'ApplicationAware' -and $id -notin $ClassifiedJobIds) { $unknown += $id; continue }
        if ($Check -in @('Days','RestorePoints')) {
            if ($value.State -ne 'Supported' -or $value.Unit -cne $needed) { $unknown += $id; continue }
            $measured += [pscustomobject]@{ Id = $id; Value = $value.Value; Unit = $needed }
            if ($value.Value -lt $Minimum) { $fail += $id }
        } else {
            if ($value.State -ne 'Supported') { $unknown += $id; continue }
            if ($Check -eq 'Daily' -and ($job.Automatic.State -ne 'Supported' -or $job.Disabled.State -ne 'Supported')) { $unknown += $id; continue }
            $measured += [pscustomobject]@{ Id = $id; Value = $value.Value }
            if (-not $value.Value -or ($Check -eq 'Daily' -and ($job.Disabled.Value -or -not $job.Automatic.Value))) { $fail += $id }
        }
    }
    if ($fail.Count) { return (New-VbrVerdict Fail "Configured job protection is below policy; unresolved objects=$($unknown.Count)." $fail $measured $Minimum) }
    if ($unknown.Count) { return (New-VbrVerdict Investigate 'Job capability or classification is unknown; no clean result is justified.' $unknown $measured $Minimum) }
    return (New-VbrVerdict Pass 'Expected jobs meet the configured policy.' $ExpectedJobIds $measured $Minimum)
}

function Get-VbrAssessmentEvidence {
    param([Parameter(Mandatory)][string]$OperationId, [hashtable]$Parameters = @{}, [switch]$BypassCache)
    $envelope = Invoke-VbrRestRequest -OperationId $OperationId -Parameters $Parameters -BypassCache:$BypassCache
    if ($null -eq $envelope -or $envelope.Complete -isnot [bool] -or -not $envelope.Complete -or
        $envelope.ApiRevision -cne '1.3-rev2' -or $null -eq $envelope.Data -or
        $null -eq (Get-VbrTimestamp $envelope.AcquiredAt) -or $null -eq (Get-VbrTimestamp $envelope.CompletedAt)) {
        throw 'VBR.CollectionIncomplete'
    }
    return $envelope
}

function Get-VbrExpectedJobs {
    param([string[]]$ExpectedJobIds)
    $list = Get-VbrAssessmentEvidence 'GetAllJobs'
    $actual = @($list.Data)
    $inventory = Test-VbrInventory $ExpectedJobIds $actual 'id'
    if ($inventory.Status -ne 'Pass') { return [pscustomobject]@{ Verdict = $inventory; Jobs = @() } }
    $jobs = @()
    foreach ($id in $ExpectedJobIds) {
        $detail = Get-VbrAssessmentEvidence 'GetJob' @{ id = $id }
        if ($detail.Data -is [array] -or (Get-VbrField $detail.Data @('id')) -ne $id) {
            return [pscustomobject]@{ Verdict = (New-VbrVerdict Investigate 'Job detail does not match expected identifier.' @($id)); Jobs = @() }
        }
        $jobs += ConvertTo-VbrJobCapability $detail.Data $detail.AcquiredAt
    }
    return [pscustomobject]@{ Verdict = $inventory; Jobs = $jobs }
}

function Test-VbrRepositoryPolicy {
    param([object[]]$States, [string[]]$ExpectedRepositoryIds, [ValidateSet('Online','Capacity')]$Check,
        [double]$MinimumFreeSpacePercent = 15, [double]$MinimumFreeSpaceGB = 20)
    $inventory = Test-VbrInventory $ExpectedRepositoryIds $States 'id'
    if ($inventory.Status -ne 'Pass') { return $inventory }
    $fail = @(); $unknown = @(); $measured = @()
    foreach ($id in $ExpectedRepositoryIds) {
        $repo = @($States | Where-Object { $_.id -eq $id })[0]
        $online = Get-VbrTypedBoolean (Get-VbrField $repo @('isOnline'))
        $outdated = Get-VbrTypedBoolean (Get-VbrField $repo @('isOutOfDate'))
        if ($online.State -ne 'Supported' -or $outdated.State -ne 'Supported') { $unknown += $id; continue }
        if ($Check -eq 'Online') {
            $measured += [pscustomobject]@{ Id = $id; Online = $online.Value; OutOfDate = $outdated.Value }
            if (-not $online.Value -or $outdated.Value) { $fail += $id }
        } else {
            $capacity = Get-VbrTypedNumber (Get-VbrField $repo @('capacityGB'))
            $free = Get-VbrTypedNumber (Get-VbrField $repo @('freeGB'))
            if ($capacity.State -ne 'Supported' -or $free.State -ne 'Supported' -or $capacity.Value -le 0 -or $free.Value -gt $capacity.Value) { $unknown += $id; continue }
            $percent = 100 * $free.Value / $capacity.Value
            $measured += [pscustomobject]@{ Id = $id; FreeGB = $free.Value; FreePercent = $percent }
            if (-not $online.Value -or $outdated.Value -or $free.Value -lt $MinimumFreeSpaceGB -or $percent -lt $MinimumFreeSpacePercent) { $fail += $id }
        }
    }
    if ($fail.Count) { return (New-VbrVerdict Fail "Repository does not meet policy; unresolved objects=$($unknown.Count)." $fail $measured) }
    if ($unknown.Count) { return (New-VbrVerdict Investigate 'Repository state or capacity is unknown.' $unknown $measured) }
    return (New-VbrVerdict Pass 'Expected repositories meet policy.' $ExpectedRepositoryIds $measured)
}

function Test-VbrConfigurationBackup {
    param($Options, [ValidateSet('Enabled','Retention','Schedule','Encryption','Freshness')]$Check,
        [int]$MinimumRestorePoints = 14, [double]$MaximumAgeHours = 48, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    switch ($Check) {
        'Enabled' { $v = Get-VbrTypedBoolean (Get-VbrField $Options @('isEnabled')); $target = $true }
        'Encryption' { $v = Get-VbrTypedBoolean (Get-VbrField $Options @('encryption','isEnabled')); $target = $true }
        'Retention' { $v = Get-VbrTypedNumber (Get-VbrField $Options @('restorePointsToKeep')); $target = $MinimumRestorePoints }
        'Schedule' {
            $v = Get-VbrTypedBoolean (Get-VbrField $Options @('schedule','isEnabled'))
            $daily = Get-VbrTypedBoolean (Get-VbrField $Options @('schedule','daily','isEnabled'))
            if ($daily.State -ne 'Supported') { return (New-VbrVerdict Investigate 'Configuration backup daily schedule is not verifiable.') }
            $kind = Get-VbrField $Options @('schedule','daily','dailyKind')
            if ($daily.Value -and $kind -cne 'Everyday') {
                if ($kind -ceq 'WeekDays' -or $kind -ceq 'SelectedDays') { return (New-VbrVerdict Fail 'Configuration backup is not scheduled every day.') }
                return (New-VbrVerdict Investigate 'Configuration backup daily schedule kind is unknown.')
            }
            $target = $true
        }
        'Freshness' {
            $stamp = Get-VbrTimestamp (Get-VbrField $Options @('lastSuccessfulBackup','lastSuccessfulTime'))
            if ($null -eq $stamp -or $stamp -gt $Now) { return (New-VbrVerdict Investigate 'Configuration backup success time is unavailable or in the future.') }
            $age = ($Now - $stamp).TotalHours
            if ($age -gt $MaximumAgeHours) { return (New-VbrVerdict Fail 'Configuration backup last success is too old.' @() $age $MaximumAgeHours $stamp) }
            return (New-VbrVerdict Pass 'Configuration backup last success is within policy.' @() $age $MaximumAgeHours $stamp)
        }
    }
    if ($v.State -ne 'Supported') { return (New-VbrVerdict Investigate 'Configuration backup setting is unknown.') }
    if ($Check -eq 'Schedule' -and -not $daily.Value) { return (New-VbrVerdict Fail 'Configuration backup daily schedule is disabled.' @() $false $true) }
    if ($v.Value -lt $target) { return (New-VbrVerdict Fail 'Configuration backup setting is below policy.' @() $v.Value $target) }
    return (New-VbrVerdict Pass 'Configuration backup setting meets policy.' @() $v.Value $target)
}

function Test-VbrServerBuild {
    param($Server, [version]$MinimumVersion = '13.1.2.57')
    $build = Get-VbrField $Server @('buildVersion')
    if ($build -isnot [string] -or $build -cnotmatch '^\d+\.\d+\.\d+\.\d+$') { return (New-VbrVerdict Investigate 'Server build version is unknown.') }
    $parsed = $null
    if (-not [version]::TryParse($build, [ref]$parsed)) { return (New-VbrVerdict Investigate 'Server build version is unknown.') }
    if ($parsed.Major -ne 13 -or $parsed.Minor -ne 1) { return (New-VbrVerdict Investigate 'Server is outside the current VBR 13.1 qualification target.' @() $build) }
    if ($parsed -lt $MinimumVersion) { return (New-VbrVerdict Fail 'Server build is below approved minimum.' @() $build "$MinimumVersion") }
    return (New-VbrVerdict Pass 'Server build meets approved minimum.' @() $build "$MinimumVersion")
}

function Test-VbrRestorePointFreshness {
    param([object[]]$Backups, [hashtable]$PointsByObject, [string[]]$ExpectedJobIds,
        [string[]]$ExpectedProtectedObjectIds, [double]$MaximumAgeHours = 26,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    if (-not $ExpectedJobIds -or -not $ExpectedProtectedObjectIds) {
        return (New-VbrVerdict Investigate 'Expected job and protected-object inventories are both required.')
    }
    $linked = @($Backups | Where-Object { (Get-VbrField $_ @('jobId')) -in $ExpectedJobIds })
    $inventory = Test-VbrInventory $ExpectedJobIds @($linked | Group-Object jobId | ForEach-Object { $_.Group[0] }) 'jobId'
    if ($inventory.Status -ne 'Pass') { return $inventory }
    if (@($linked | Where-Object { -not (Test-VbrGuid $_.id) }).Count) {
        return (New-VbrVerdict Investigate 'Backup correlation identifier is invalid.')
    }
    $unknown = @(); $stale = @(); $measured = @(); $coveredJobs = @()
    foreach ($objectId in $ExpectedProtectedObjectIds) {
        if (-not (Test-VbrGuid $objectId)) { $unknown += $objectId; continue }
        # Object identity comes from the registered object-scoped route, not an
        # invented backupObjectId property in the restore-point response model.
        $candidates = @($PointsByObject[$objectId] | Where-Object {
            $backupId = Get-VbrField $_ @('backupId')
            @($linked | Where-Object { $_.id -eq $backupId }).Count -gt 0
        })
        if ($candidates.Count -eq 0) { $unknown += $objectId; continue }
        $times = @()
        foreach ($point in $candidates) {
            $time = Get-VbrTimestamp (Get-VbrField $point @('creationTime'))
            if ($null -eq $time -or $time -gt $Now) { $unknown += $objectId; break }
            $times += $time
            $coveredJobs += @($linked | Where-Object { $_.id -eq $point.backupId } | ForEach-Object { $_.jobId })
        }
        if ($objectId -in $unknown) { continue }
        $latest = @($times | Sort-Object -Descending)[0]
        $age = ($Now - $latest).TotalHours
        $measured += [pscustomobject]@{ Id = $objectId; AgeHours = $age; PointTime = $latest }
        if ($age -gt $MaximumAgeHours) { $stale += $objectId }
    }
    if ($stale.Count) { return (New-VbrVerdict Fail "Protected objects have stale restore points; unresolved objects=$($unknown.Count)." $stale $measured $MaximumAgeHours) }
    if (@($ExpectedJobIds | Where-Object { $_ -notin $coveredJobs }).Count) {
        return (New-VbrVerdict Investigate 'At least one expected job has no correlated expected-object restore-point evidence.' @() $measured $MaximumAgeHours)
    }
    if ($unknown.Count) { return (New-VbrVerdict Investigate 'Protected-object correlation or timestamp is incomplete.' $unknown $measured $MaximumAgeHours) }
    return (New-VbrVerdict Pass 'Each expected protected object has a recent correlated restore point.' $ExpectedProtectedObjectIds $measured $MaximumAgeHours)
}

function Test-VbrSessionPolicy {
    param([object[]]$Sessions, [string[]]$ExpectedJobIds, [ValidateSet('Outcome','Running')]$Check,
        [double]$MaximumRunningSessionHours = 12, [ValidateSet('Investigate','Fail')][string]$WarningHandling = 'Investigate',
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    if (-not $ExpectedJobIds) { return (New-VbrVerdict Investigate 'Expected job inventory is not configured.') }
    $unknown = @(); $failed = @(); $warnings = @(); $measured = @()
    foreach ($jobId in $ExpectedJobIds) {
        if (-not (Test-VbrGuid $jobId)) { $unknown += $jobId; continue }
        $jobSessions = @($Sessions | Where-Object { (Get-VbrField $_ @('jobId')) -eq $jobId })
        if ($jobSessions.Count -eq 0) { $unknown += $jobId; continue }
        $parsed = @()
        foreach ($session in $jobSessions) {
            $sessionId = Get-VbrField $session @('id')
            $created = Get-VbrTimestamp (Get-VbrField $session @('creationTime'))
            $state = Get-VbrField $session @('state')
            $kind = Get-VbrField $session @('sessionType')
            $original = Get-VbrField $session @('originalSessionId')
            $canceled = Get-VbrField $session @('result','isCanceled')
            if ($null -ne $canceled -and $canceled -isnot [bool]) { $unknown += $jobId; break }
            if (-not (Test-VbrGuid $sessionId) -or $null -eq $created -or $created -gt $Now -or
                $state -notin @('Stopped','Starting','Stopping','Working','Pausing','Resuming','WaitingTape','Idle','Postprocessing','WaitingRepository','WaitingSlot','ActionRequired') -or
                $kind -notin @('BackupJob','AgentBackup') -or ($null -ne $original -and -not (Test-VbrGuid $original))) {
                $unknown += $jobId; break
            }
            $end = Get-VbrTimestamp (Get-VbrField $session @('endTime'))
            if ($state -eq 'Stopped' -and ($null -eq $end -or $end -lt $created -or $end -gt $Now)) { $unknown += $jobId; break }
            $parsed += [pscustomobject]@{ Id = $sessionId; Chain = $(if ($original) { $original } else { $sessionId })
                Created = $created; End = $end; State = $state; Canceled = $canceled; Result = $(Get-VbrField $session @('result','result')) }
        }
        if ($jobId -in $unknown) { continue }
        if (@($parsed | Group-Object Id | Where-Object Count -gt 1).Count -or
            @($parsed | Where-Object { $_.Chain -ne $_.Id -and $_.Chain -notin @($parsed.Id) }).Count) {
            $unknown += $jobId; continue
        }
        if ($Check -eq 'Running') {
            foreach ($s in $parsed) {
                if ($s.State -eq 'Stopped') { continue }
                $age = ($Now - $s.Created).TotalHours
                $measured += [pscustomobject]@{ Id = $jobId; SessionId = $s.Id; RunningHours = $age }
                if ($age -gt $MaximumRunningSessionHours) { $failed += $jobId }
            }
            continue
        }
        # Order by start of the original chain, not the last retry's creation time.
        $chains = @($parsed | Group-Object Chain)
        $latest = @($chains | Sort-Object { ($_.Group | Sort-Object Created | Select-Object -First 1).Created } -Descending)[0]
        $chain = @($latest.Group | Sort-Object Created -Descending)
        $terminal = @($chain | Where-Object { $_.State -eq 'Stopped' })
        if ($terminal.Count -eq 0 -or $chain[0].State -ne 'Stopped' -or
            ($chain.Count -gt 1 -and $chain[0].Created -eq $chain[1].Created)) { $unknown += $jobId; continue }
        $last = $chain[0]
        if ($last.Canceled) { $failed += $jobId }
        $safeResult = if ($last.Result -cin @('Success','Failed','Warning')) { $last.Result } else { 'Unknown' }
        $measured += [pscustomobject]@{ Id = $jobId; SessionId = $last.Id; Result = $safeResult; EndTime = $last.End }
        switch -CaseSensitive ($last.Result) {
            'Success' { }
            'Failed' { $failed += $jobId }
            'Warning' { $warnings += $jobId }
            default { $unknown += $jobId }
        }
    }
    if ($failed.Count -or ($warnings.Count -and $WarningHandling -eq 'Fail')) {
        return (New-VbrVerdict Fail "Latest terminal outcome failed or running threshold exceeded; unresolved jobs=$($unknown.Count)." @($failed + $warnings) $measured $MaximumRunningSessionHours)
    }
    if ($unknown.Count) { return (New-VbrVerdict Investigate 'Session chain, result or inventory is ambiguous.' $unknown $measured) }
    if ($warnings.Count) { return (New-VbrVerdict Investigate 'Latest terminal session has warnings.' $warnings $measured) }
    return (New-VbrVerdict Pass 'Expected job sessions meet policy.' $ExpectedJobIds $measured)
}

function Complete-VbrNativeResult {
    param($Verdict)
    # Never include arbitrary API text, user names, notes, or connection secrets in results.
    $ids = @($Verdict.ObjectIds | Where-Object { Test-VbrGuid $_ })
    $detail = "$($Verdict.Reason) Baseline=$($Verdict.Baseline); EvidenceType=$($Verdict.EvidenceType); ObjectIds=$($ids -join ','); Measured=$($Verdict.Measured | ConvertTo-Json -Compress -Depth 4); Threshold=$($Verdict.Threshold | ConvertTo-Json -Compress -Depth 3)."
    if ($Verdict.Status -eq 'Investigate') { Add-MtTestResultDetail -Investigate -Result $detail; return $null }
    Add-MtTestResultDetail -Result $detail
    return ($Verdict.Status -eq 'Pass')
}

function Invoke-VbrNativeControl {
    param([string]$Control, [hashtable]$Policy = @{})
    try {
        $defaults = @{ MinimumVersion = [version]'13.1.2.57'; MinimumConfigurationBackupRestorePoints = 14
            MaximumConfigurationBackupAgeHours = 48; ExpectedRepositoryIds = @(); ExpectedJobIds = @()
            MinimumFreeSpacePercent = 15; MinimumFreeSpaceGB = 20; MinimumRetentionDays = 14
            MinimumRestorePoints = 14; ClassifiedApplicationJobIds = @(); ExpectedProtectedObjectIds = @()
            MaximumRestorePointAgeHours = 26; MaximumRunningSessionHours = 12; WarningHandling = 'Investigate' }
        foreach ($name in $defaults.Keys) { if (-not $Policy.ContainsKey($name)) { $Policy[$name] = $defaults[$name] } }
        switch ($Control) {
            '1001' { $data = Get-VbrAssessmentEvidence 'GetServerInfo'; $v = Test-VbrServerBuild $data.Data $Policy.MinimumVersion }
            { $_ -in @('2001','2002','2003','3005','4001') } {
                $data = Get-VbrAssessmentEvidence 'GetConfigBackupOptions'
                $check = @{ '2001'='Enabled'; '2002'='Retention'; '2003'='Schedule'; '3005'='Freshness'; '4001'='Encryption' }[$Control]
                $v = Test-VbrConfigurationBackup $data.Data $check $Policy.MinimumConfigurationBackupRestorePoints $Policy.MaximumConfigurationBackupAgeHours
            }
            { $_ -in @('1002','3004') } {
                $data = Get-VbrAssessmentEvidence 'GetAllRepositoriesStates'
                $check = if ($Control -eq '1002') { 'Online' } else { 'Capacity' }
                $v = Test-VbrRepositoryPolicy @($data.Data) $Policy.ExpectedRepositoryIds $check $Policy.MinimumFreeSpacePercent $Policy.MinimumFreeSpaceGB
            }
            { $_ -in @('3001','3002','3003') } {
                $jobs = Get-VbrExpectedJobs $Policy.ExpectedJobIds
                if ($jobs.Verdict.Status -ne 'Pass') { $v = $jobs.Verdict; break }
                if ($Control -eq '3001') {
                    $backups = Get-VbrAssessmentEvidence 'GetAllBackups'
                    $points = @{}
                    foreach ($objectId in $Policy.ExpectedProtectedObjectIds) {
                        $objectPoints = Get-VbrAssessmentEvidence 'GetBackupObjectRestorePointsWithFiltering' @{ id = $objectId } -BypassCache
                        $points[$objectId] = @($objectPoints.Data)
                    }
                    $v = Test-VbrRestorePointFreshness @($backups.Data) $points $Policy.ExpectedJobIds $Policy.ExpectedProtectedObjectIds $Policy.MaximumRestorePointAgeHours
                } else {
                    $sessions = @()
                    foreach ($jobId in $Policy.ExpectedJobIds) {
                        $jobSessions = Get-VbrAssessmentEvidence 'GetAllSessions' @{ jobIdFilter = $jobId } -BypassCache
                        if (@($jobSessions.Data | Where-Object { $_.jobId -ne $jobId }).Count) { throw 'VBR.UnexpectedFilterScope' }
                        $sessions += @($jobSessions.Data)
                    }
                    $check = if ($Control -eq '3002') { 'Outcome' } else { 'Running' }
                    $v = Test-VbrSessionPolicy $sessions $Policy.ExpectedJobIds $check $Policy.MaximumRunningSessionHours $Policy.WarningHandling
                }
            }
            { $_ -in @('2010','2011','2012','2013','4010','4011') } {
                $jobs = Get-VbrExpectedJobs $Policy.ExpectedJobIds
                if ($jobs.Verdict.Status -ne 'Pass') { $v = $jobs.Verdict; break }
                $check = @{ '2010'='Days'; '2011'='RestorePoints'; '2012'='Daily'; '2013'='Health'; '4010'='Encryption'; '4011'='ApplicationAware' }[$Control]
                $minimum = if ($check -eq 'Days') { $Policy.MinimumRetentionDays } else { $Policy.MinimumRestorePoints }
                $v = Test-VbrJobPolicy $jobs.Jobs $Policy.ExpectedJobIds $check $minimum $Policy.ClassifiedApplicationJobIds
            }
            default { throw 'VBR.ControlNotImplemented' }
        }
        return (Complete-VbrNativeResult $v)
    } catch {
        if ($_.Exception.Message -eq 'VBR.AdminProfileRequired') {
            Add-MtTestResultDetail -Investigate -Result 'Administrator profile required; opt in explicitly. No request was sent.'
            return $null
        }
        $code = $_.Exception.Message
        if ($code -match '^VBR\.[A-Za-z0-9.]+$') { throw "VBR.AssessmentError: $code" }
        throw 'VBR.AssessmentError: collection or evaluation failed.'
    }
}
