function Test-Vbr1002 {
    [MaesterTest(Id = 'MP.VBR.1002', Title = 'Expected repositories are online and current', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedRepositoryIds')][string[]]$ExpectedRepositoryIds = @())
    Invoke-VbrNativeControl '1002' @{ ExpectedRepositoryIds = $ExpectedRepositoryIds }
}
