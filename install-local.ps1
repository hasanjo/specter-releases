<#
.SYNOPSIS
  Install specter from a GitHub release (or build from local source with -Local).
.EXAMPLE
  pwsh ./scripts/install-local.ps1
  pwsh ./scripts/install-local.ps1 -Repo "your-org/specter-releases"
  pwsh ./scripts/install-local.ps1 -Local
#>

param(
    [string]$Repo  = "hasanjo/specter-releases",
    [switch]$Local
)

$ErrorActionPreference = 'Stop'
$Esc = [char]27
$Cr  = [char]13

# ── Virtual-terminal / ANSI detection ────────────────────────────────────────

function Enable-VirtualTerminalOutput {
    if ([Console]::IsOutputRedirected -or $env:TERM -eq 'dumb') { return $false }
    if ($null -ne $script:SpecterVTEnabled) { return $script:SpecterVTEnabled }
    if (-not ("ConsoleMode.NativeMethods" -as [Type])) {
        Add-Type -Namespace ConsoleMode -Name NativeMethods -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
"@
    }
    $h = [ConsoleMode.NativeMethods]::GetStdHandle(-11)
    $m = [uint32]0
    $script:SpecterVTEnabled = [ConsoleMode.NativeMethods]::GetConsoleMode($h, [ref]$m) `
        -and [ConsoleMode.NativeMethods]::SetConsoleMode($h, ($m -bor 0x0004))
    return $script:SpecterVTEnabled
}

function Test-Ansi { return Enable-VirtualTerminalOutput }

# ── Colour palette ────────────────────────────────────────────────────────────

function cc([string]$seq) { if (Test-Ansi) { return "${Esc}[${seq}m" } return "" }

$R  = cc "0"
$Bd = cc "1"
$Dm = cc "2"
$Aq = cc "38;2;0;195;255"    # aqua
$Gn = cc "38;2;80;220;100"   # green
$Or = cc "38;2;246;155;49"   # orange
$Cy = cc "38;2;71;217;250"   # lighter cyan (comet mid-trail)
$Gy = cc "38;2;110;110;110"  # grey

# ── Title ─────────────────────────────────────────────────────────────────────

function Write-SpecterTitle {
    Write-Host ""
    if (Test-Ansi) {
        [Console]::Write("${Aq}${Bd}")
        [Console]::Write("   ____  ____  ____  ___  ____  ____  ____  `n")
        [Console]::Write("  / ___||  _ \| ____/ ___||_  _||  __||  _ \ `n")
        [Console]::Write("  \___ \| |_) |  _|| |     | |  |  _| | |_) |`n")
        [Console]::Write("   ___) |  __/| |__| |___  | |  | |___|  _ < `n")
        [Console]::Write("  |____/|_|   |_____\____| |_|  |_____|_| \_\`n")
        [Console]::Write("${R}")
        [Console]::Write("  ${Gy}AI code review for your terminal  --  Powered by Genovation AI${R}`n")
    } else {
        Write-Host "  SPECTER"
        Write-Host "  AI code review for your terminal"
    }
    Write-Host ""
}

# ── Step output ───────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    if (Test-Ansi) { [Console]::Write("  ${Aq}>${R} $msg`n") }
    else           { Write-Host "  => $msg" }
}

function Write-Ok([string]$msg) {
    if (Test-Ansi) { [Console]::Write("  ${Gn}ok${R} $msg`n") }
    else           { Write-Host "  ok $msg" }
}

function Write-Warn([string]$msg) {
    if (Test-Ansi) { [Console]::Write("  ${Or}!${R} $msg`n") }
    else           { Write-Host "  warning: $msg" }
}

# ── Comet progress bar ────────────────────────────────────────────────────────

$script:LastProgressWidth = 0

function Write-SpecterProgress([int]$step, [string]$label) {
    $width = 30; $trail = 8
    $head  = $step % ($width + $trail)
    $bar   = ""
    for ($i = 0; $i -lt $width; $i++) {
        $age = $head - $i
        if ($age -ge 0 -and $age -lt $trail) {
            $bar += switch ($age) {
                { $_ -le 1 } { "${Gn}#${R}"; break }
                { $_ -le 3 } { "${Aq}#${R}"; break }
                { $_ -le 5 } { "${Cy}#${R}"; break }
                default       { "${Gy}#${R}" }
            }
        } else {
            $bar += "${Dm}-${R}"
        }
    }
    # Each bar cell is exactly 1 visible char — no need to strip ANSI sequences.
    $visible = 5 + $width + 2 + $label.Length   # "  * [" + bar + "] " + label
    $pad     = [Math]::Max(0, $script:LastProgressWidth - $visible)
    [Console]::Write("${Cr}  ${Aq}*${R} [${bar}] $label" + (" " * $pad))
    $script:LastProgressWidth = [Math]::Max($script:LastProgressWidth, $visible)
}

function Clear-SpecterProgress {
    if ($script:LastProgressWidth -gt 0) {
        [Console]::Write("${Cr}" + (" " * $script:LastProgressWidth) + "${Cr}")
    }
    $script:LastProgressWidth = 0
}

# ── PATH broadcast (tells Explorer + open shells about the registry change) ───

function Publish-EnvChange {
    if (-not ("Win32.NativeMethods" -as [Type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }
    $r = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout(
        [IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$r) | Out-Null
}

# ── Main ──────────────────────────────────────────────────────────────────────

$BinDir = Join-Path $env:USERPROFILE '.specter\bin'

Write-SpecterTitle

if ($Local) {
    Write-Step "Building specter from local source..."
    $Root    = Split-Path -Parent $PSScriptRoot
    $Project = Join-Path $Root 'src/Specter/Specter.csproj'
    $Staging = Join-Path $env:TEMP 'specter-publish'
    dotnet publish $Project -c Release -r win-x64 -o $Staging | Out-Null
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Get-Process -Name 'specter' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $Staging 'specter.exe') (Join-Path $BinDir 'specter.exe') -Force
    Remove-Item -Recurse -Force $Staging -ErrorAction SilentlyContinue
    Write-Ok "Built and installed specter"
} else {
    $arch      = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
    $assetName = "specter-win-$arch.exe"

    Write-Step "Resolving latest release from ${Repo}..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    $asset   = $release.assets | Where-Object { $_.name -eq $assetName }
    if (-not $asset) {
        Write-Host ""
        Write-Host "  error: $assetName not found in latest release of $Repo" -ForegroundColor Red
        Write-Host "  Assets: $($release.assets.name -join ', ')"
        exit 1
    }

    $version     = $release.tag_name
    $downloadUrl = $asset.browser_download_url
    Write-Ok "Found ${assetName}  ${Gy}(${version})${R}"

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $exePath = Join-Path $BinDir 'specter.exe'
    $tmpPath = "$exePath.tmp"
    Get-Process -Name 'specter' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if (Test-Ansi) {
        [Console]::Write("${Esc}[?25l")   # hide cursor during animation
        $job = Start-Job -ScriptBlock {
            param([string]$Url, [string]$Out)
            $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curlExe) { curl.exe -SfLo $Out $Url } else { Invoke-RestMethod -Uri $Url -OutFile $Out }
        } -ArgumentList $downloadUrl, $tmpPath

        Write-Host ""
        $step = 0
        while ($job.State -eq "Running") {
            Write-SpecterProgress $step "Downloading specter $version"
            $step++
            Start-Sleep -Milliseconds 80
        }
        Clear-SpecterProgress
        [Console]::Write("${Esc}[?25h")   # restore cursor
        Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $job
    } else {
        Write-Host "  Downloading $downloadUrl ..."
        Invoke-RestMethod -Uri $downloadUrl -OutFile $tmpPath
    }

    if (-not (Test-Path $tmpPath)) {
        Write-Host "  error: download failed" -ForegroundColor Red
        exit 1
    }

    Move-Item -Path $tmpPath -Destination $exePath -Force
    Write-Ok "Installed specter ${version}  ${Gy}-> ${exePath}${R}"
}

# ── PATH setup ────────────────────────────────────────────────────────────────

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
    Publish-EnvChange
    Write-Ok "Added $BinDir to your user PATH"
    Write-Warn "Open a new terminal for PATH changes to take effect"
} else {
    Write-Ok "$BinDir is already on your PATH"
}
if (";$env:Path;" -notlike "*;$BinDir;*") { $env:Path = "$env:Path;$BinDir" }

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
if (Test-Ansi) {
    [Console]::Write("  ${Gn}${Bd}Specter is installed.${R}  Run ${Aq}specter review${R} inside any git repo.`n")
} else {
    Write-Host "  Specter is installed. Run:  specter review"
}
Write-Host ""
