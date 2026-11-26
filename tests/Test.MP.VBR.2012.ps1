function Test-Vbr2012 {
    [MaesterTest(Id = 'MP.VBR.2012', Title = 'Expected jobs have an enabled daily schedule', Severity = 'Medium', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @())
    Invoke-VbrNativeControl '2012' @{ ExpectedJobIds = $ExpectedJobIds }
}
