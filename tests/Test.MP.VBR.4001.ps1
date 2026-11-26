function Test-Vbr4001 {
    [MaesterTest(Id = 'MP.VBR.4001', Title = 'Configuration backup encryption is enabled', Severity = 'High', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param()
    Invoke-VbrNativeControl '4001'
}
