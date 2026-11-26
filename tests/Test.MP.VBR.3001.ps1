function Test-Vbr3001 {
    [MaesterTest(Id = 'MP.VBR.3001', Title = 'Expected protected objects have recent correlated restore points', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @(),
        [MaesterParameter(Setting = 'VBR.ExpectedProtectedObjectIds')][string[]]$ExpectedProtectedObjectIds = @(),
        [MaesterParameter(Setting = 'VBR.MaximumRestorePointAgeHours')][ValidateRange(1,8760)][int]$MaximumRestorePointAgeHours = 26)
    Invoke-VbrNativeControl '3001' @{ ExpectedJobIds = $ExpectedJobIds; ExpectedProtectedObjectIds = $ExpectedProtectedObjectIds; MaximumRestorePointAgeHours = $MaximumRestorePointAgeHours }
}
