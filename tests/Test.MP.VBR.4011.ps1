function Test-Vbr4011 {
    [MaesterTest(Id = 'MP.VBR.4011', Title = 'Classified application jobs use application-aware processing', Severity = 'Medium', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @(),
        [MaesterParameter(Setting = 'VBR.ClassifiedApplicationJobIds')][string[]]$ClassifiedApplicationJobIds = @())
    Invoke-VbrNativeControl '4011' @{ ExpectedJobIds = $ExpectedJobIds; ClassifiedApplicationJobIds = $ClassifiedApplicationJobIds }
}
