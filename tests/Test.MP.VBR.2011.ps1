function Test-Vbr2011 {
    [MaesterTest(Id = 'MP.VBR.2011', Title = 'Expected jobs meet restore-point-count retention policy', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @(),
        [MaesterParameter(Setting = 'VBR.MinimumRestorePoints')][ValidateRange(1,9999)][int]$MinimumRestorePoints = 14)
    Invoke-VbrNativeControl '2011' @{ ExpectedJobIds = $ExpectedJobIds; MinimumRestorePoints = $MinimumRestorePoints }
}
