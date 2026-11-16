param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$Platform,
    [Parameter(Mandatory)][string]$InputPath,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ErrorView = 'NormalView'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest

Write-Host "[Release build] Starting $Platform."
$SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$Release = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$Build = @($Release.builds | Where-Object platform -EQ $Platform)
if ($Build.Count -ne 1) { throw "Expected one build configuration for $Platform." }
$Build = $Build[0]
$Commit = git -C $SourcePath rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw "git rev-parse failed: $LASTEXITCODE." }
if ($Commit.Trim() -ne $Release.source_commit) { throw 'Source commit does not match release manifest.' }

$MachineArchitecture = uname -m
if ($LASTEXITCODE -ne 0) { throw "uname failed: $LASTEXITCODE." }
if ($IsMacOS -and $MachineArchitecture.Trim() -ne 'arm64') {
    throw 'The macOS build requires a native arm64 runner.'
}
Write-Host "[Release build] Host: $MachineArchitecture; target: $($Build.target); source: $Commit."
$env:HELIX_RUNTIME = Join-Path $SourcePath 'runtime'
Remove-Item Env:HELIX_DEFAULT_RUNTIME -ErrorAction SilentlyContinue
Remove-Item Env:HELIX_DISABLE_AUTO_GRAMMAR_BUILD -ErrorAction SilentlyContinue
$env:CARGO_TERM_COLOR = 'never'
$env:CARGO_BUILD_JOBS = [string][Environment]::ProcessorCount

Push-Location $SourcePath
try {
    Write-Host '[Release build] Building editor and all tree-sitter grammars in strict mode.'
    $CommandArgs = @("+$($Release.rust_toolchain)", 'build', '--release', '--locked', '--target', $Build.target)
    cargo @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed: $LASTEXITCODE." }
}
finally { Pop-Location }

$BinaryPath = Join-Path $SourcePath "target/$($Build.target)/release/hx"
if ($Build.PSObject.Properties.Name -contains 'binary_asset') {
    Write-Host '[Release build] Using the verified original binary from workflow inputs.'
    $InputPath = (Resolve-Path -LiteralPath $InputPath).Path
    $BinaryPath = Join-Path $InputPath $Build.binary_asset
    $Hash = (Get-FileHash -LiteralPath $BinaryPath -Algorithm SHA256).Hash
    if ($Hash -ne $Build.binary_sha256) { throw 'Original binary SHA256 does not match the manifest.' }
    chmod +x $BinaryPath
    if ($LASTEXITCODE -ne 0) { throw "chmod failed: $LASTEXITCODE." }
}

& (Join-Path $PSScriptRoot 'package.ps1') -SourcePath $SourcePath -BinaryPath $BinaryPath `
    -Tag $Release.tag -Platform $Platform -OutputPath $OutputPath
Write-Host "[Release build] Completed $Platform."
