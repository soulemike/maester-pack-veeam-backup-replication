function Test-Vbr4010 {
    [MaesterTest(Id = 'MP.VBR.4010', Title = 'Expected managed backup jobs have encryption enabled', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @())
    Invoke-VbrNativeControl '4010' @{ ExpectedJobIds = $ExpectedJobIds }
}
