function Invoke-VbrCapabilityTests {
BeforeAll {
    . "$PSScriptRoot/../../helpers/20.Capabilities.ps1"
    . "$PSScriptRoot/../../helpers/30.Controls.ps1"
    function Add-MtTestResultDetail { param([switch]$Investigate, [string]$Result) }
    $script:jobId = '11111111-1111-1111-1111-111111111111'
    $script:objectId = '22222222-2222-2222-2222-222222222222'
    $script:backupId = '33333333-3333-3333-3333-333333333333'
    $script:now = [DateTimeOffset]::Parse('2026-11-26T12:00:00+00:00')
}

Describe 'Common job model from synthetic documented schema shapes' {
    It 'produces equal verdicts across Agent Windows, Agent Linux, VMware and Hyper-V' {
        $verdicts = foreach ($fixture in 'agent-windows','agent-linux','vmware','hyperv') {
            $source = Get-Content "$PSScriptRoot/../fixtures/$fixture.json" -Raw | ConvertFrom-Json
            $model = ConvertTo-VbrJobCapability $source $now
            foreach ($check in 'Days','Encryption','Daily','Health') {
                (Test-VbrJobPolicy @($model) @($jobId) $check).Status
            }
        }
        $verdicts | Should -HaveCount 16
        @($verdicts | Where-Object { $_ -ne 'Pass' }) | Should -BeNullOrEmpty
    }
    It 'does not turn null, false, zero or unknown enums into missing-is-disabled passes' {
        $job = Get-Content "$PSScriptRoot/../fixtures/agent-windows.json" -Raw | ConvertFrom-Json
        $job.storage.retentionPolicy.quantity = 0
        (Test-VbrJobPolicy @((ConvertTo-VbrJobCapability $job $now)) @($jobId) Days).Status | Should -Be 'Fail'
        $job.storage.retentionPolicy.type = 'Unrecognized'
        (Test-VbrJobPolicy @((ConvertTo-VbrJobCapability $job $now)) @($jobId) Days).Status | Should -Be 'Investigate'
        $job.storage.advancedSettings.storageData.encryption.isEnabled = $false
        (Test-VbrJobPolicy @((ConvertTo-VbrJobCapability $job $now)) @($jobId) Encryption).Status | Should -Be 'Fail'
        $job.storage.advancedSettings.storageData.encryption.isEnabled = $null
        (Test-VbrJobPolicy @((ConvertTo-VbrJobCapability $job $now)) @($jobId) Encryption).Status | Should -Be 'Investigate'
        $job.type = 'WindowsAgentBackupServerPolicy'
        (Test-VbrJobPolicy @((ConvertTo-VbrJobCapability $job $now)) @($jobId) Encryption).Status | Should -Be 'Investigate'
    }
    It 'never equates 14 days with 14 restore points' {
        $job = Get-Content "$PSScriptRoot/../fixtures/hyperv.json" -Raw | ConvertFrom-Json
        $job.storage.retentionPolicy.type = 'RestorePoints'
        $model = ConvertTo-VbrJobCapability $job $now
        (Test-VbrJobPolicy @($model) @($jobId) RestorePoints).Status | Should -Be 'Pass'
        (Test-VbrJobPolicy @($model) @($jobId) Days).Status | Should -Be 'Investigate'
    }
    It 'treats empty or invisible expected inventory and missing classifications as Investigate' {
        (Test-VbrInventory @() @()).Status | Should -Be 'Investigate'
        (Test-VbrInventory @($jobId) @()).Status | Should -Be 'Investigate'
        $job = Get-Content "$PSScriptRoot/../fixtures/agent-windows.json" -Raw | ConvertFrom-Json
        (Test-VbrJobPolicy @((ConvertTo-VbrJobCapability $job $now)) @($jobId) ApplicationAware).Status | Should -Be 'Investigate'
    }
}

Describe 'Typed server and configuration evidence' {
    It 'rejects ambiguous versions and compares four-part builds' {
        (Test-VbrServerBuild @{ buildVersion = '13.1.2.56' }).Status | Should -Be 'Fail'
        (Test-VbrServerBuild @{ buildVersion = '13.1.2.57' }).Status | Should -Be 'Pass'
        (Test-VbrServerBuild @{ buildVersion = '13.1' }).Status | Should -Be 'Investigate'
    }
    It 'uses offset-aware times and exact age thresholds' {
        $config = @{ lastSuccessfulBackup = @{ lastSuccessfulTime = '2026-11-24T13:00:00+01:00' } }
        (Test-VbrConfigurationBackup $config Freshness 14 48 $now).Status | Should -Be 'Pass'
        $config.lastSuccessfulBackup.lastSuccessfulTime = '2026-11-24T12:59:59+01:00'
        (Test-VbrConfigurationBackup $config Freshness 14 48 $now).Status | Should -Be 'Fail'
        $config.lastSuccessfulBackup.lastSuccessfulTime = '2026-11-24T12:00:00'
        (Test-VbrConfigurationBackup $config Freshness 14 48 $now).Status | Should -Be 'Investigate'
    }
    It 'requires both repository limits and interprets API GB without binary conversion' {
        $repository = @{ id = '44444444-4444-4444-4444-444444444444'; isOnline = $true; isOutOfDate = $false; capacityGB = 100; freeGB = 20 }
        (Test-VbrRepositoryPolicy @($repository) @($repository.id) Capacity).Status | Should -Be 'Pass'
        $repository.capacityGB = 200
        (Test-VbrRepositoryPolicy @($repository) @($repository.id) Capacity).Status | Should -Be 'Fail'
        $repository.capacityGB = 0
        (Test-VbrRepositoryPolicy @($repository) @($repository.id) Capacity).Status | Should -Be 'Investigate'
    }
}

Describe 'Correlated operational evidence' {
    It 'requires object IDs as well as job IDs, and correlates point to backup to job' {
        $backups = @(@{ id = $backupId; jobId = $jobId })
        $points = @{ $objectId = @(@{ backupId = $backupId; creationTime = '2026-11-25T11:00:00-01:00' }) }
        (Test-VbrRestorePointFreshness $backups $points @($jobId) @() 26 $now).Status | Should -Be 'Investigate'
        (Test-VbrRestorePointFreshness $backups $points @($jobId) @($objectId) 26 $now).Status | Should -Be 'Pass'
        $points[$objectId][0].creationTime = '2026-11-25T08:59:59-01:00'
        (Test-VbrRestorePointFreshness $backups $points @($jobId) @($objectId) 26 $now).Status | Should -Be 'Fail'
        $points[$objectId][0].backupId = '55555555-5555-5555-5555-555555555555'
        (Test-VbrRestorePointFreshness $backups $points @($jobId) @($objectId) 26 $now).Status | Should -Be 'Investigate'
    }
    It 'uses the final retry of the latest chain, not the first failure' {
        $original = '66666666-6666-6666-6666-666666666666'
        $sessions = @(
            @{ id = $original; originalSessionId = $original; jobId = $jobId; sessionType = 'BackupJob'; creationTime = '2026-11-26T09:00:00Z'; endTime = '2026-11-26T09:30:00Z'; state = 'Stopped'; result = @{ result = 'Failed' } },
            @{ id = '77777777-7777-7777-7777-777777777777'; originalSessionId = $original; jobId = $jobId; sessionType = 'BackupJob'; creationTime = '2026-11-26T10:00:00Z'; endTime = '2026-11-26T10:30:00Z'; state = 'Stopped'; result = @{ result = 'Success' } }
        )
        (Test-VbrSessionPolicy $sessions @($jobId) Outcome 12 Investigate $now).Status | Should -Be 'Pass'
        $sessions[1].result.result = 'Warning'
        (Test-VbrSessionPolicy $sessions @($jobId) Outcome 12 Investigate $now).Status | Should -Be 'Investigate'
        (Test-VbrSessionPolicy $sessions @($jobId) Outcome 12 Fail $now).Status | Should -Be 'Fail'
        $sessions[1].state = 'Working'
        (Test-VbrSessionPolicy $sessions @($jobId) Outcome 12 Investigate $now).Status | Should -Be 'Investigate'
    }
}

Describe 'Native error boundary' {
    It 'refuses an admin-only operation under Reader as Investigate without a wire request' {
        Mock Get-VbrAssessmentEvidence { throw 'VBR.AdminProfileRequired' }
        Mock Add-MtTestResultDetail { }
        $result = Invoke-VbrNativeControl '2001'
        $result | Should -BeNullOrEmpty
        Should -Invoke Add-MtTestResultDetail -Exactly 1 -ParameterFilter { $Investigate }
    }
    It 'does not leak server error text in an Error exception' {
        Mock Get-VbrAssessmentEvidence { throw 'private connection secret and endpoint' }
        { Invoke-VbrNativeControl '2001' } | Should -Throw 'VBR.AssessmentError*'
    }
    It 'preserves a sanitized permission failure code for diagnosis' {
        Mock Get-VbrAssessmentEvidence { throw 'VBR.PermissionDenied' }
        { Invoke-VbrNativeControl '2001' } | Should -Throw 'VBR.AssessmentError: VBR.PermissionDenied'
    }
    It 'does not include an unrecognized session result string in evidence details' {
        $session = @{ id = $backupId; jobId = $jobId; sessionType = 'BackupJob'; creationTime = '2026-11-26T09:00:00Z'
            endTime = '2026-11-26T10:00:00Z'; state = 'Stopped'; result = @{ result = 'SENTINEL_UNTRUSTED_TEXT' } }
        $verdict = Test-VbrSessionPolicy @($session) @($jobId) Outcome 12 Investigate $now
        $verdict.Status | Should -Be 'Investigate'
        ($verdict | ConvertTo-Json -Depth 6) | Should -Not -Match 'SENTINEL_UNTRUSTED_TEXT'
    }
}
}
