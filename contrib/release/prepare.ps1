param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ErrorView = 'NormalView'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest

Write-Host '[Release inputs] Starting.'
$Release = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$env:GH_PAGER = 'cat'
$env:GH_PROMPT_DISABLED = '1'
$InputBuilds = @($Release.builds | Where-Object { $_.PSObject.Properties.Name -contains 'binary_asset' })
foreach ($Build in $InputBuilds) {
    Write-Host "[Release inputs] Downloading $($Build.binary_asset) from draft $($Release.tag)."
    $CommandArgs = @('release', 'download', $Release.tag, '--repo', $Repository)
    $CommandArgs += @('--pattern', $Build.binary_asset, '--dir', $OutputPath)
    gh @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "Draft input download failed: $LASTEXITCODE." }
    $Hash = (Get-FileHash -LiteralPath (Join-Path $OutputPath $Build.binary_asset) -Algorithm SHA256).Hash
    if ($Hash -ne $Build.binary_sha256) { throw "Draft input checksum mismatch: $($Build.binary_asset)" }
}
if ($env:GITHUB_OUTPUT) {
    $HasInputs = ($InputBuilds.Count -gt 0).ToString().ToLowerInvariant()
    "has_inputs=$HasInputs" >> $env:GITHUB_OUTPUT
}
Write-Host "[Release inputs] Verified $($InputBuilds.Count) original binaries."
