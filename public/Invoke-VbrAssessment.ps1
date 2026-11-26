function Invoke-VbrAssessment {
    [CmdletBinding()]
    param([string[]] $TestId = @('MP.VBR.*'), [object[]] $Config,
          [string] $OutputFolder, [switch] $PassThru)
    # Dot-source this entry point after installing/connecting the pack. The callback is
    # bound by the reviewed connector to its native private module, not to this caller.
    $state = Get-MtConnectionState -Service VBR.RestApi
    if (-not $state -or $state.Assess -isnot [scriptblock]) { throw 'VBR.NotConnected' }
    & $state.Assess @PSBoundParameters
}
