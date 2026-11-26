function Initialize-VbrOfflineTools {
    [CmdletBinding()]
    param()
    $root = Split-Path $PSScriptRoot -Parent
    $versions = Get-Content (Join-Path $PSScriptRoot 'versions.json') -Raw | ConvertFrom-Json
    $tools = Join-Path $root '.tools'
    $null = New-Item -ItemType Directory -Path $tools -Force
    foreach ($name in @('Microsoft.Graph.Authentication','Maester','Pester')) {
        $pin = $versions.$name
        $archive = Join-Path $tools "$name-$($pin.Version).nupkg"
        if (-not (Test-Path -LiteralPath $archive)) {
            Invoke-WebRequest -Uri ($versions.GalleryBaseUrl + $name + '/' + $pin.Version) -OutFile $archive -TimeoutSec 60 -ErrorAction Stop
        }
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ine $pin.Sha256) { throw "Dependency hash mismatch: $name" }
        $destination = Join-Path $tools "$name-$($pin.Version)"
        if (-not (Test-Path -LiteralPath $destination)) { [IO.Compression.ZipFile]::ExtractToDirectory($archive, $destination) }
        # Reuse is allowed only while extracted bytes still match the pinned archive.
        # Do not overwrite unfamiliar modifications; fail and require operator review.
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        $sha = [Security.Cryptography.SHA256]::Create()
        $expectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        try {
            foreach ($entry in $zip.Entries) {
                if (-not $entry.Name) { continue }
                $file = Join-Path $destination $entry.FullName
                $null = $expectedFiles.Add([IO.Path]::GetFullPath($file))
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Extracted dependency missing a file: $name" }
                $original = $entry.Open(); $extracted = [IO.File]::OpenRead($file)
                try {
                    if ([Convert]::ToHexString($sha.ComputeHash($original)) -cne [Convert]::ToHexString($sha.ComputeHash($extracted))) {
                        throw "Extracted dependency integrity mismatch: $name"
                    }
                } finally { $original.Dispose(); $extracted.Dispose() }
            }
            foreach ($file in Get-ChildItem -LiteralPath $destination -Recurse -File) {
                if (-not $expectedFiles.Contains($file.FullName)) { throw "Unexpected file in extracted dependency: $name" }
            }
        } finally { $sha.Dispose(); $zip.Dispose() }
        Import-Module (Join-Path $destination "$name.psd1") -ErrorAction Stop
    }
}
