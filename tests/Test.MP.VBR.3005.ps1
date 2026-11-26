function Test-Vbr3005 {
    [MaesterTest(Id = 'MP.VBR.3005', Title = 'Configuration backup last success is recent', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.MaximumConfigurationBackupAgeHours')]
        [ValidateRange(1,8760)][int]$MaximumConfigurationBackupAgeHours = 48)
    Invoke-VbrNativeControl '3005' @{ MaximumConfigurationBackupAgeHours = $MaximumConfigurationBackupAgeHours }
}
