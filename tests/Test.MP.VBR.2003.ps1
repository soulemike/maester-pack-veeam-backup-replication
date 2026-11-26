function Test-Vbr2003 {
    [MaesterTest(Id = 'MP.VBR.2003', Title = 'Configuration backup has a daily schedule', Severity = 'Medium', Service = 'VBR.RestApi')]
    [CmdletBinding()]
    param()
    Invoke-VbrNativeControl '2003'
}
