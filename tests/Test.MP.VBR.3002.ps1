function Test-Vbr3002 {
    [MaesterTest(Id = 'MP.VBR.3002', Title = 'Expected jobs have successful terminal backup sessions', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @(),
        [MaesterParameter(Setting = 'VBR.WarningHandling')][ValidateSet('Investigate','Fail')][string]$WarningHandling = 'Investigate')
    Invoke-VbrNativeControl '3002' @{ ExpectedJobIds = $ExpectedJobIds; WarningHandling = $WarningHandling }
}
