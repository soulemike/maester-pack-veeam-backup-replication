function Test-Vbr2010 {
    [MaesterTest(Id = 'MP.VBR.2010', Title = 'Expected jobs meet day-based retention policy', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param([MaesterParameter(Setting = 'VBR.ExpectedJobIds')][string[]]$ExpectedJobIds = @(),
        [MaesterParameter(Setting = 'VBR.MinimumRetentionDays')][ValidateRange(1,9999)][int]$MinimumRetentionDays = 14)
    Invoke-VbrNativeControl '2010' @{ ExpectedJobIds = $ExpectedJobIds; MinimumRetentionDays = $MinimumRetentionDays }
}
