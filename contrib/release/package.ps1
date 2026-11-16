param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$BinaryPath,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Platform,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ErrorView = 'NormalView'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest

Write-Host "[Release package] Starting $Platform."
$SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$BinaryPath = (Resolve-Path -LiteralPath $BinaryPath).Path
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$Commit = git -C $SourcePath rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw "git rev-parse failed: $LASTEXITCODE." }
$Version = & $BinaryPath --version
if ($LASTEXITCODE -ne 0) { throw "Native binary execution failed: $LASTEXITCODE." }
if ($Version -notmatch [regex]::Escape($Commit.Substring(0, 8))) {
    throw 'Binary version does not match the source commit.'
}
$BinaryType = file $BinaryPath
if ($LASTEXITCODE -ne 0) { throw "file failed: $LASTEXITCODE." }
if ($IsMacOS -and $BinaryType -notmatch 'Mach-O 64-bit executable arm64') {
    throw "Expected macOS arm64 binary: $BinaryType"
}
if ($IsLinux -and $BinaryType -notmatch 'ELF 64-bit.*x86-64') {
    throw "Expected Linux x86-64 binary: $BinaryType"
}
Write-Host "[Release package] $Version; $BinaryType"
$GrammarExtension = if ($IsMacOS) { '*.dylib' } else { '*.so' }
$Grammars = @(Get-ChildItem -LiteralPath (Join-Path $SourcePath 'runtime/grammars') -Filter $GrammarExtension -File)
if ($Grammars.Count -eq 0) { throw 'No compiled tree-sitter grammars were found.' }
Write-Host "[Release package] Including $($Grammars.Count) native grammars."

$PackageName = "helix-$Tag-$Platform"
$StagingPath = Join-Path $OutputPath 'staging'
$PackagePath = Join-Path $StagingPath $PackageName
New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
Copy-Item -LiteralPath $BinaryPath -Destination (Join-Path $PackagePath 'hx')
Copy-Item -LiteralPath (Join-Path $SourcePath 'LICENSE'), (Join-Path $SourcePath 'README.md') -Destination $PackagePath
New-Item -ItemType Directory -Path (Join-Path $PackagePath 'contrib') | Out-Null
Copy-Item -LiteralPath (Join-Path $SourcePath 'contrib/completion') -Destination (Join-Path $PackagePath 'contrib') -Recurse

$RuntimeArchive = Join-Path $StagingPath 'runtime.tar'
$CommandArgs = @('-cf', $RuntimeArchive, '--exclude=runtime/grammars/sources', '-C', $SourcePath, 'runtime')
tar @CommandArgs
if ($LASTEXITCODE -ne 0) { throw "Runtime archive failed: $LASTEXITCODE." }
$CommandArgs = @('-xf', $RuntimeArchive, '-C', $PackagePath)
tar @CommandArgs
if ($LASTEXITCODE -ne 0) { throw "Runtime extraction failed: $LASTEXITCODE." }
chmod +x (Join-Path $PackagePath 'hx')
if ($LASTEXITCODE -ne 0) { throw "chmod failed: $LASTEXITCODE." }

$Info = [ordered]@{
    source_commit = $Commit.Trim()
    platform = $Platform
    version = $Version.Trim()
    binary_sha256 = (Get-FileHash -LiteralPath $BinaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    grammar_count = $Grammars.Count
}
$Info | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PackagePath 'BUILD-INFO.json')
$ArchivePath = Join-Path $OutputPath "$PackageName.tar.xz"
$CommandArgs = @('-cJf', $ArchivePath, '-C', $StagingPath, $PackageName)
tar @CommandArgs
if ($LASTEXITCODE -ne 0) { throw "Package archive failed: $LASTEXITCODE." }
$Hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  $PackageName.tar.xz" | Set-Content -LiteralPath "$ArchivePath.sha256"
Remove-Item -LiteralPath $StagingPath -Recurse
Write-Host "[Release package] Completed: $ArchivePath; SHA256: $Hash"
