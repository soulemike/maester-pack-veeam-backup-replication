function Test-Vbr2002 {
    [MaesterTest(Id = 'MP.VBR.2002', Title = 'Configuration backup retention meets policy', Severity = 'Medium', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.MinimumConfigurationBackupRestorePoints')]
        [ValidateRange(1,9999)][int]$MinimumConfigurationBackupRestorePoints = 14)
    Invoke-VbrNativeControl '2002' @{ MinimumConfigurationBackupRestorePoints = $MinimumConfigurationBackupRestorePoints }
}
