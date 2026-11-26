function Test-Vbr2001 {
    [MaesterTest(Id = 'MP.VBR.2001', Title = 'Configuration backup is enabled', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param()
    Invoke-VbrNativeControl '2001'
}
