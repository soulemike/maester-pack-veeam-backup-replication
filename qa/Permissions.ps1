function Update-VbrPermissionMatrix {
    [CmdletBinding()]
    param()
    $root = Split-Path $PSScriptRoot -Parent
    $catalog = Get-Content (Join-Path $root 'catalog/endpoints.json') -Raw | ConvertFrom-Json
    $permissions = Get-Content (Join-Path $root 'catalog/permissions.json') -Raw | ConvertFrom-Json
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Permission matrix')
    $lines.Add('')
    $lines.Add('Generated from `catalog/permissions.json` and `catalog/endpoints.json`. Public schema verification is not a live RBAC probe. Custom permission IDs and edition/visibility behavior remain unverified.')
    $lines.Add('')
    $lines.Add('All assessment operations below are GET reads. Backup Administrator is nevertheless a privileged, writable account role. Its use requires explicit opt-in; a GET-only pack does not make that account read-only.')
    $lines.Add('')
    $lines.Add('| Test | Profile | GET operations | Required visibility |')
    $lines.Add('| --- | --- | --- | --- |')
    foreach ($test in $permissions.Tests) {
        $operations = foreach ($id in $test.Operations) {
            $operation = $catalog.Operations | Where-Object Id -EQ $id
            if (-not $operation) { throw "Unregistered permission operation: $id" }
            "$id (``$($operation.Path)``)"
        }
        $lines.Add("| $($test.TestId) | $($test.Profile) | $($operations -join '<br>') | $($test.Scope) |")
    }
    $lines.Add('')
    $lines.Add('OperationalReader maps to documented Backup Viewer access for these common reads. ComprehensiveAdministrator maps to Backup Administrator. These are pack profile labels. Neither profile nor permission metadata is a substitute for live object-visibility verification.')
    $lines.Add('')
    $lines.Add('Reader mode does not send administrator-only requests: those controls return Investigate. An actual required GET returning 403 is Error. No role fallback, credential merging, or privilege elevation occurs.')
    [IO.File]::WriteAllText((Join-Path $root 'docs/permissions.md'), (($lines -join "`n") + "`n"))
}
