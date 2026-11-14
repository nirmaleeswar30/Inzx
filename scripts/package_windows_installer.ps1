# Builds the Windows release (unless -SkipBuild) and packages it with Inno
# Setup into dist\windows\Inzx-Setup-<version>.exe.
#
#   scripts\package_windows_installer.ps1                # flutter build windows --release, then package
#   scripts\package_windows_installer.ps1 -SkipBuild     # package the existing Release output
#   scripts\package_windows_installer.ps1 -Flutter <path to flutter.bat>
#
# Needs Inno Setup 6 (https://jrsoftware.org/isinfo.php; ISCC_PATH may point
# at ISCC.exe) and, for the app-local VC++ runtime, Visual Studio's C++
# tools (the same ones the Windows build needs).
param(
  [switch]$SkipBuild,
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

if (-not $AppVersion) {
  $line = Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*(.+)$' | Select-Object -First 1
  $AppVersion = ($line.Matches[0].Groups[1].Value.Trim() -split '\+')[0]
}

if (-not $SkipBuild) {
  & $Flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE); no installer made." }
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
