param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$Repository
)

$ErrorActionPreference = 'Stop'
$ErrorView = 'NormalView'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest

Write-Host '[Release publish] Starting.'
$Release = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$ArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path
$env:GH_PAGER = 'cat'
$env:GH_PROMPT_DISABLED = '1'
$Archives = @()
$Checksums = @()
foreach ($Build in $Release.builds) {
    $Name = "helix-$($Release.tag)-$($Build.platform).tar.xz"
    $Path = Join-Path $ArtifactPath $Name
    $Expected = (Get-Content -LiteralPath "$Path.sha256" -Raw).Trim()
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Expected -ne "$Hash  $Name") { throw "Artifact checksum mismatch: $Name" }
    $Archives += $Path
    $Checksums += "$Hash  $Name"
}
$ChecksumPath = Join-Path $ArtifactPath 'SHA256SUMS'
$Checksums | Set-Content -LiteralPath $ChecksumPath

$CommandArgs = @('release', 'view', $Release.tag, '--repo', $Repository, '--json', 'isDraft')
$State = gh @CommandArgs
if ($LASTEXITCODE -ne 0) { throw "Release inspection failed: $LASTEXITCODE." }
if (-not (($State -join "`n") | ConvertFrom-Json).isDraft) { throw 'The target release must still be a draft.' }

Write-Host '[Release publish] Uploading verified platform archives and checksums.'
$CommandArgs = @('release', 'upload', $Release.tag, '--repo', $Repository, '--clobber')
$CommandArgs += $Archives
$CommandArgs += $ChecksumPath
gh @CommandArgs
if ($LASTEXITCODE -ne 0) { throw "Release upload failed: $LASTEXITCODE." }
foreach ($Build in $Release.builds) {
    if ($Build.PSObject.Properties.Name -contains 'binary_asset') {
        $CommandArgs = @('release', 'delete-asset', $Release.tag, $Build.binary_asset, '--repo', $Repository, '--yes')
        gh @CommandArgs
        if ($LASTEXITCODE -ne 0) { throw "Temporary binary asset cleanup failed: $LASTEXITCODE." }
    }
}

Write-Host '[Release publish] Publishing the complete release.'
$CommandArgs = @('release', 'edit', $Release.tag, '--repo', $Repository, '--draft=false', '--latest')
gh @CommandArgs
if ($LASTEXITCODE -ne 0) { throw "Release publication failed: $LASTEXITCODE." }
Write-Host "[Release publish] Complete: https://github.com/$Repository/releases/tag/$($Release.tag)"
