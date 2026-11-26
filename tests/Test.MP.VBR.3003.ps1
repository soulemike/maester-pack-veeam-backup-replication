function Test-Vbr3003 {
    [MaesterTest(Id = 'MP.VBR.3003', Title = 'Expected jobs have no overlong running sessions', Severity = 'Medium', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @(),
        [MaesterParameter(Setting = 'VBR.MaximumRunningSessionHours')][ValidateRange(1,8760)][int]$MaximumRunningSessionHours = 12)
    Invoke-VbrNativeControl '3003' @{ ExpectedJobIds = $ExpectedJobIds; MaximumRunningSessionHours = $MaximumRunningSessionHours }
}
