# Builds the Windows release (unless -SkipBuild) and packages it with Inno
# Setup into dist\windows\Inzx-Setup-<version>.exe.
#
#   scripts\package_windows_installer.ps1                # interactive selection (normal vs shorebird), then package
#   scripts\package_windows_installer.ps1 -BuildType shorebird # shorebird release windows, then package
#   scripts\package_windows_installer.ps1 -BuildType normal    # flutter build windows --release, then package
#   scripts\package_windows_installer.ps1 -SkipBuild     # package the existing Release output
#   scripts\package_windows_installer.ps1 -Flutter <path to flutter.bat>
#
# Needs Inno Setup 6 (https://jrsoftware.org/isinfo.php; ISCC_PATH may point
# at ISCC.exe) and, for the app-local VC++ runtime, Visual Studio's C++
# tools (the same ones the Windows build needs).
param(
  [switch]$SkipBuild,
  [ValidateSet("normal", "shorebird")]
  [string]$BuildType = "",
  [string]$Flutter = "flutter",
  [string]$SourceDir = "",
  [string]$OutputDir = "",
  # Tests only: install under another name and id, beside a real Inzx.
  [string]$DisplayName = "",
  [string]$AppId = "",
  [string]$AppVersion = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Find-Iscc {
  if ($env:ISCC_PATH -and (Test-Path $env:ISCC_PATH)) { return $env:ISCC_PATH }
  $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in @(
      "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
    if (Test-Path $c) { return $c }
  }
  throw "Inno Setup 6 not found. Install it or set ISCC_PATH to ISCC.exe."
}

# The x64 VC++ runtime DLLs from the newest Visual Studio, to ship app-local.
function Find-CrtDir {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) { return $null }
  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $vs) { return $null }
  $redist = Get-ChildItem "$vs\VC\Redist\MSVC" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d' } | Sort-Object { [version]($_.Name -replace '[^\d.]', '') } -Descending |
    Select-Object -First 1
  if (-not $redist) { return $null }
  $crt = Get-ChildItem "$($redist.FullName)\x64" -Directory -Filter "Microsoft.VC*.CRT" -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($crt) { return $crt.FullName }
  return $null
}

function Find-Shorebird {
  if ($env:SHOREBIRD_PATH -and (Test-Path $env:SHOREBIRD_PATH)) { return $env:SHOREBIRD_PATH }
  $cmd = Get-Command shorebird -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    "$env:USERPROFILE\.shorebird\bin\shorebird.ps1",
    "$env:USERPROFILE\.shorebird\bin\shorebird.bat",
    "$env:LOCALAPPDATA\Programs\shorebird\bin\shorebird.bat"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

function Verify-ShorebirdAuth {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/c shorebird apps list"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  $proc.WaitForExit()
  $appsOutput = $proc.StandardOutput.ReadToEnd() + " " + $proc.StandardError.ReadToEnd()

  if ($appsOutput -match "shorebird login" -or $appsOutput -match "rejected your stored credentials" -or $appsOutput -match "Failed to refresh credentials") {
    Write-Host ""
    Write-Host "Shorebird is not logged in or credentials have expired." -ForegroundColor Yellow
    Write-Host "Launching 'shorebird login'..." -ForegroundColor Cyan
    & cmd.exe /c shorebird login
    if ($LASTEXITCODE -ne 0) {
      throw "Shorebird login was unsuccessful. Cannot proceed with Shorebird release."
    }
  }
}

function Get-ShorebirdFlutterVersion {
  param([string]$AppVersion)
  if (-not [string]::IsNullOrWhiteSpace($env:SHOREBIRD_FLUTTER_VERSION)) {
    return $env:SHOREBIRD_FLUTTER_VERSION
  }
  try {
    $releases = & cmd.exe /c shorebird releases list 2>$null
    if ($releases) {
      $escaped = [regex]::Escape($AppVersion)
      foreach ($line in $releases) {
        if ($line -match "\b$escaped(\+\d+)?\b.*\s+(\d+\.\d+\.\d+)\s*$") {
          return $Matches[2]
        }
      }
    }
  } catch {}
  return $null
}

if (-not $AppVersion) {
  $line = Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*(.+)$' | Select-Object -First 1
  $AppVersion = ($line.Matches[0].Groups[1].Value.Trim() -split '\+')[0]
}

# Interactive selection if BuildType not specified and running in interactive terminal
if (-not $SkipBuild -and [string]::IsNullOrWhiteSpace($BuildType)) {
  if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    Write-Host ""
    Write-Host "Select Windows Release Type:" -ForegroundColor Cyan
    Write-Host "  [1] Normal Release (Standard Flutter AOT build)" -ForegroundColor Yellow
    Write-Host "  [2] Shorebird Release (Enables Over-the-Air Dart code pushes)" -ForegroundColor Green
    $selection = Read-Host "Enter choice [1 or 2] (Default: 1)"
    if ($selection -eq "2") {
      $BuildType = "shorebird"
    } else {
      $BuildType = "normal"
    }
  } else {
    $BuildType = "normal"
  }
}

if (-not $SkipBuild) {
  if ($BuildType -eq "shorebird") {
    $shorebird = Find-Shorebird
    if (-not $shorebird) {
      throw "Shorebird CLI was not found. Please install Shorebird (https://docs.shorebird.dev) to build Shorebird releases."
    }
    Write-Host "Verifying Shorebird credentials..." -ForegroundColor Yellow
    Verify-ShorebirdAuth

    $flutterVer = Get-ShorebirdFlutterVersion -AppVersion $AppVersion
    $shorebirdArgs = @("release", "windows")
    if ($flutterVer) {
      Write-Host "ℹ️ Existing Shorebird release found for $AppVersion (Flutter $flutterVer). Matching Flutter revision..." -ForegroundColor Cyan
      $shorebirdArgs += "--flutter-version=$flutterVer"
    }

    Write-Host "🦅 Building Shorebird Windows Release (OTA-enabled)..." -ForegroundColor Green
    & cmd.exe /c shorebird @shorebirdArgs
    if ($LASTEXITCODE -ne 0) { throw "shorebird release windows failed ($LASTEXITCODE); no installer made." }
  } else {
    Write-Host "🏗️ Building Standard Flutter Windows Release..." -ForegroundColor Cyan
    & $Flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE); no installer made." }
  }
}

if (-not $SourceDir) { $SourceDir = Join-Path $Root "build\windows\x64\runner\Release" }
if (-not (Test-Path (Join-Path $SourceDir "inzx.exe"))) {
  throw "No inzx.exe in $SourceDir. Build the Windows release first."
}
if (-not $OutputDir) { $OutputDir = Join-Path $Root "dist\windows" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$defines = @("/DAppVersion=$AppVersion", "/DSourceDir=$SourceDir", "/DOutputDir=$OutputDir")
if ($DisplayName) { $defines += "/DDisplayName=$DisplayName" }
if ($AppId) { $defines += "/DAppId={{$AppId}" }

$crt = Find-CrtDir
if ($crt) {
  # Only the runtime itself (no debug or OpenMP DLLs).
  $staging = Join-Path ([IO.Path]::GetTempPath()) "inzx-crt-$PID"
  New-Item -ItemType Directory -Force -Path $staging | Out-Null
  Get-ChildItem $crt -Filter *.dll | Where-Object { $_.Name -match '^(msvcp140|vcruntime140|concrt140)' } |
    Copy-Item -Destination $staging
  $defines += "/DCrtDir=$staging"
  Write-Host "Shipping the VC++ runtime from $crt"
} else {
  Write-Warning "Visual C++ redistributable DLLs not found; the installer relies on the system's."
}

$iscc = Find-Iscc
Write-Host "Packaging Inzx $AppVersion with $iscc"
& $iscc @defines (Join-Path $Root "windows\installer\inzx.iss")
$code = $LASTEXITCODE
if ($staging) { Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue }
if ($code -ne 0) { throw "Inno Setup failed ($code)." }

$name = if ($DisplayName) { $DisplayName } else { "Inzx" }
$installer = Join-Path $OutputDir "$name-Setup-$AppVersion.exe"
Write-Host ("Installer: {0} ({1:N1} MB)" -f $installer, ((Get-Item $installer).Length / 1MB)) -ForegroundColor Green

if ($BuildType -eq "shorebird") {
  $shorebirdInstaller = Join-Path $OutputDir "$name-Setup-$AppVersion-Shorebird.exe"
  Copy-Item $installer $shorebirdInstaller -Force
  Write-Host ("Shorebird Installer: {0} ({1:N1} MB)" -f $shorebirdInstaller, ((Get-Item $shorebirdInstaller).Length / 1MB)) -ForegroundColor Green
}
