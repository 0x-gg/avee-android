[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$Tag = 'HEAD',
    [string]$OutputDirectory = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'release-source')
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & git -C $RepositoryRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($result -join "`n")"
    }
    return $result
}

$root = (Resolve-Path $RepositoryRoot).Path
$licensePath = Join-Path $root 'LICENSE'
$readmePath = Join-Path $root 'README_EN.md'
if (-not (Test-Path $licensePath)) { throw 'LICENSE is missing' }
if (-not (Test-Path $readmePath)) { throw 'README_EN.md is missing' }

$license = Get-Content -Raw $licensePath
$readme = Get-Content -Raw $readmePath
if ($license -notmatch 'GNU GENERAL PUBLIC LICENSE\s+Version 3') {
    throw 'LICENSE is not a complete GPL-3.0 license document'
}
foreach ($notice in @('GPL-3.0', 'FlClashX', 'FlClash', 'mihomo', 'Clash.Meta')) {
    if ($readme -notmatch [regex]::Escape($notice)) { throw "README attribution is missing: $notice" }
}

$resolvedTag = (Invoke-Git @('rev-parse', '--verify', "$Tag^{commit}") | Select-Object -Last 1).Trim()
$safeTag = ($Tag -replace '[^A-Za-z0-9._-]', '_')
$workDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "avee-source-$safeTag"
$archivePath = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "avee-source-$safeTag.tar.gz"
$checksumPath = "$archivePath.sha256"

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (Test-Path $workDirectory) { Remove-Item -LiteralPath $workDirectory -Recurse -Force }
if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
if (Test-Path $checksumPath) { Remove-Item -LiteralPath $checksumPath -Force }
New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null

& git -C $root archive --format=tar --prefix="avee-source-$safeTag/" $resolvedTag | tar -xf - -C $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Unable to extract the main source archive' }

$submodules = Invoke-Git @('config', '--file', '.gitmodules', '--get-regexp', '^submodule\..*\.path$')
foreach ($line in $submodules) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -ne 2) { continue }
    $submodulePath = $parts[1]
    $source = Join-Path $root $submodulePath
    if (-not (Test-Path (Join-Path $source '.git'))) {
        throw "Submodule is not checked out: $submodulePath"
    }
    $destination = Join-Path (Join-Path $OutputDirectory "avee-source-$safeTag") $submodulePath
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    & git -C $source archive --format=tar HEAD | tar -xf - -C $destination
    if ($LASTEXITCODE -ne 0) { throw "Unable to archive submodule: $submodulePath" }
}

& tar -czf $archivePath -C $OutputDirectory "avee-source-$safeTag"
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the compressed source archive' }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
"$hash  $(Split-Path -Leaf $archivePath)" | Set-Content -Encoding ascii -LiteralPath $checksumPath
Remove-Item -LiteralPath $workDirectory -Recurse -Force

Write-Host "GPL source archive: $archivePath"
Write-Host "SHA-256: $hash"
Write-Host "Source revision: $resolvedTag"
