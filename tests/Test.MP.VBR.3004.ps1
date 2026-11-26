function Test-Vbr3004 {
    [MaesterTest(Id = 'MP.VBR.3004', Title = 'Expected repositories meet both free-space thresholds', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedRepositoryIds')][string[]]$ExpectedRepositoryIds = @(),
        [MaesterParameter(Setting = 'VBR.MinimumFreeSpacePercent')][ValidateRange(1,99)][int]$MinimumFreeSpacePercent = 15,
        [MaesterParameter(Setting = 'VBR.MinimumFreeSpaceGB')][ValidateRange(1,1000000)][int]$MinimumFreeSpaceGB = 20)
    Invoke-VbrNativeControl '3004' @{ ExpectedRepositoryIds = $ExpectedRepositoryIds; MinimumFreeSpacePercent = $MinimumFreeSpacePercent; MinimumFreeSpaceGB = $MinimumFreeSpaceGB }
}
