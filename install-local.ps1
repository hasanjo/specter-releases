<#
.SYNOPSIS
  Install specter from a GitHub release URL or build from local source.

.DESCRIPTION
  By default downloads the latest win-x64 specter.exe from a GitHub release.
  Use -Local to build and install from the local source tree.

  Examples:
    pwsh ./scripts/install-local.ps1
    pwsh ./scripts/install-local.ps1 -Repo "your-org/specter"
    pwsh ./scripts/install-local.ps1 -Local
#>

param(
    [string]$Repo = "hasanjo/specter-releases",
    [switch]$Local
)

$ErrorActionPreference = 'Stop'

$BinDir = Join-Path $env:USERPROFILE '.specter\bin'

if ($Local) {
    # ── Build from local source ──────────────────────────────────────
    $Root    = Split-Path -Parent $PSScriptRoot
    $Project = Join-Path $Root 'src/Specter/Specter.csproj'
    $Staging = Join-Path $env:TEMP 'specter-publish'

    Write-Host "=> Publishing specter from source..." -ForegroundColor Cyan
    dotnet publish $Project -c Release -r win-x64 -o $Staging | Out-Null

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Get-Process -Name 'specter' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $Staging 'specter.exe') (Join-Path $BinDir 'specter.exe') -Force
    Remove-Item -Recurse -Force $Staging -ErrorAction SilentlyContinue
} else {
    # ── Download from GitHub release ─────────────────────────────────
    $releasesUrl = "https://api.github.com/repos/$Repo/releases/latest"
    Write-Host "=> Fetching latest release from $Repo..." -ForegroundColor Cyan

    $release = Invoke-RestMethod -Uri $releasesUrl -UseBasicParsing

    # Pick the right asset for this machine.
    $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
    $assetName = "specter-win-$arch.exe"
    $asset = $release.assets | Where-Object { $_.name -eq $assetName }
    if (-not $asset) {
        Write-Error "No $assetName found in the latest release of $Repo. Assets: $($release.assets.name -join ', ')"
        exit 1
    }

    $downloadUrl = $asset.browser_download_url
    Write-Host "=> Downloading $downloadUrl ..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $exePath = Join-Path $BinDir 'specter.exe'

    # Kill any running specter process so the file is not locked during overwrite.
    Get-Process -Name 'specter' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $tmpPath = "$exePath.tmp"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpPath -UseBasicParsing
    Move-Item -Path $tmpPath -Destination $exePath -Force
    Write-Host "=> Installed to $exePath" -ForegroundColor Cyan
}

# Add to user PATH if not already present.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
    Write-Host "=> Added $BinDir to your user PATH." -ForegroundColor Cyan
    Write-Host "warning: open a NEW terminal for PATH changes to take effect." -ForegroundColor Yellow
} else {
    Write-Host "=> $BinDir already on PATH." -ForegroundColor Cyan
}

# Add to this session too.
if (";$env:Path;" -notlike "*;$BinDir;*") { $env:Path = "$env:Path;$BinDir" }

Write-Host ""
Write-Host "Done. From any directory:  specter review" -ForegroundColor Green
