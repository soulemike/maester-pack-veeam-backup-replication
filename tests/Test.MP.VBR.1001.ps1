function Test-Vbr1001 {
    [MaesterTest(Id = 'MP.VBR.1001', Title = 'VBR build meets the approved minimum', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param(
        [MaesterParameter(Setting = 'VBR.MinimumServerBuild')]
        [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$MinimumServerBuild = '13.1.2.57'
    )
    Invoke-VbrNativeControl '1001' @{ MinimumVersion = [version]$MinimumServerBuild }
}
