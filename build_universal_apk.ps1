# Build Universal APK from AAB using bundletool
# Usage: .\build_universal_apk.ps1

$ErrorActionPreference = "Stop"

# Configuration
$bundletoolPath = "C:\tools\bundletool.jar"
$aabPath = "build\app\outputs\bundle\release\app-release.aab"
$apksPath = "build\app\outputs\bundle\release\app-release.apks"
$outputDir = "build\app\outputs\bundle\release\apks"

# Debug keystore (default Android debug signing)
$keystorePath = "$env:USERPROFILE\.android\debug.keystore"
$keyAlias = "androiddebugkey"
$keystorePassword = "android"
$keyPassword = "android"

Write-Host "=== Universal APK Builder ===" -ForegroundColor Cyan
Write-Host ""

# Check Java
Write-Host "Checking Java..." -ForegroundColor Yellow
try {
    $javaVersion = java -version 2>&1 | Select-Object -First 1
    Write-Host "  Found: $javaVersion" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Java not found. Please install Java JDK." -ForegroundColor Red
    exit 1
}

# Check bundletool
Write-Host "Checking bundletool..." -ForegroundColor Yellow
if (Test-Path $bundletoolPath) {
    Write-Host "  Found: $bundletoolPath" -ForegroundColor Green
} else {
    Write-Host "  Bundletool not found. Downloading..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path (Split-Path $bundletoolPath) | Out-Null
    Invoke-WebRequest -Uri "https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar" -OutFile $bundletoolPath
    Write-Host "  Downloaded to: $bundletoolPath" -ForegroundColor Green
}

# Check AAB file
Write-Host "Checking AAB file..." -ForegroundColor Yellow
if (Test-Path $aabPath) {
    $aabSize = [math]::Round((Get-Item $aabPath).Length / 1MB, 2)
    Write-Host "  Found: $aabPath ($aabSize MB)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: AAB not found at $aabPath" -ForegroundColor Red
    Write-Host "  Run 'shorebird release android' first." -ForegroundColor Red
    exit 1
}

# Check keystore
Write-Host "Checking keystore..." -ForegroundColor Yellow
if (Test-Path $keystorePath) {
    Write-Host "  Found: $keystorePath" -ForegroundColor Green
} else {
    Write-Host "  ERROR: Debug keystore not found at $keystorePath" -ForegroundColor Red
    exit 1
}

# Build APK set
Write-Host ""
Write-Host "Building APK set (universal mode)..." -ForegroundColor Yellow
$buildArgs = @(
    "-jar", $bundletoolPath,
    "build-apks",
    "--bundle=$aabPath",
    "--output=$apksPath",
    "--mode=universal",
    "--ks=$keystorePath",
    "--ks-key-alias=$keyAlias",
    "--ks-pass=pass:$keystorePassword",
    "--key-pass=pass:$keyPassword",
    "--overwrite"
)

java @buildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to build APK set" -ForegroundColor Red
    exit 1
}
Write-Host "  APK set created: $apksPath" -ForegroundColor Green

# Extract universal APK
Write-Host ""
Write-Host "Extracting universal APK..." -ForegroundColor Yellow

# Remove existing output directory
if (Test-Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse -Force
}

# .apks is a ZIP file, rename and extract
$tempZip = "$apksPath.zip"
Copy-Item $apksPath $tempZip -Force
Expand-Archive -Path $tempZip -DestinationPath $outputDir -Force
Remove-Item $tempZip

$universalApk = Join-Path $outputDir "universal.apk"
if (Test-Path $universalApk) {
    $apkSize = [math]::Round((Get-Item $universalApk).Length / 1MB, 2)
    Write-Host "  Extracted: $universalApk ($apkSize MB)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: universal.apk not found in extracted files" -ForegroundColor Red
    exit 1
}

# Done
Write-Host ""
Write-Host "=== SUCCESS ===" -ForegroundColor Green
Write-Host "Universal APK: $universalApk" -ForegroundColor Cyan
Write-Host "Size: $apkSize MB" -ForegroundColor Cyan
Write-Host ""
Write-Host "Upload this file to GitHub Releases for Shorebird patch distribution." -ForegroundColor White
