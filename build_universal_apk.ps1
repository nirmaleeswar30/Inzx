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
# Prefer java on PATH; otherwise fall back to JAVA_HOME or the JDK that ships
# with Android Studio (JBR) so the build works without manual PATH setup.
$javaExe = $null
$javaCommand = Get-Command java -ErrorAction SilentlyContinue
if ($javaCommand) {
    $javaExe = $javaCommand.Source
} else {
    $fallbacks = @()
    if ($env:JAVA_HOME) {
        $fallbacks += (Join-Path $env:JAVA_HOME 'bin\java.exe')
    }
    $fallbacks += "$env:ProgramFiles\Android\Android Studio\jbr\bin\java.exe"
    $fallbacks += "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\java.exe"
    $fallbacks += "${env:ProgramFiles(x86)}\Android\Android Studio\jbr\bin\java.exe"
    foreach ($cand in $fallbacks) {
        if ($cand -and (Test-Path $cand)) { $javaExe = $cand; break }
    }
}
if (-not $javaExe) {
    Write-Host "  ERROR: Java not found in PATH, JAVA_HOME, or Android Studio (JBR)." -ForegroundColor Red
    Write-Host "  Install a JDK, or set JAVA_HOME to your JDK folder." -ForegroundColor Red
    exit 1
}

# Note: `java -version` prints to stderr by design.
# Run via cmd and redirect stderr to stdout to avoid PowerShell native error wrapping.
$javaVersionOutput = & cmd /c """$javaExe"" -version 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Java command failed to run from: $javaExe" -ForegroundColor Red
    exit 1
}

$javaVersion = $javaVersionOutput | Select-Object -First 1
Write-Host "  Found: $javaVersion" -ForegroundColor Green
Write-Host "  Using: $javaExe" -ForegroundColor DarkGray

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

# Check keystore (generate a debug keystore if missing, like the shell script)
Write-Host "Checking keystore..." -ForegroundColor Yellow
if (Test-Path $keystorePath) {
    Write-Host "  Found: $keystorePath" -ForegroundColor Green
} else {
    Write-Host "  Keystore not found. Generating debug keystore..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path (Split-Path $keystorePath) | Out-Null
    $keytool = Join-Path (Split-Path $javaExe) "keytool.exe"
    if (-not (Test-Path $keytool)) { $keytool = "keytool" }
    & $keytool -genkeypair -v -keystore $keystorePath -storepass $keystorePassword `
        -alias $keyAlias -keypass $keyPassword -keyalg RSA -keysize 2048 `
        -validity 10000 -dname "C=US, O=Android, CN=Android Debug"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $keystorePath)) {
        Write-Host "  ERROR: Failed to generate debug keystore" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Generated: $keystorePath" -ForegroundColor Green
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

& $javaExe @buildArgs

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

# ── Version (from pubspec.yaml), used for the versioned universal APK name ──
$version = "unknown"
if (Test-Path "pubspec.yaml") {
    $verLine = Select-String -Path "pubspec.yaml" -Pattern '^\s*version:\s*(.+)$' |
        Select-Object -First 1
    if ($verLine) { $version = ($verLine.Matches[0].Groups[1].Value).Trim() }
}
$versionSafe = ($version -replace '[^a-zA-Z0-9.\+\-]', '_')

# Copy the universal APK to a versioned name (parity with the shell script)
$universalTarget = Join-Path $outputDir "inzx-$versionSafe-universal.apk"
Copy-Item $universalApk $universalTarget -Force

# ── Locate Android build-tools (zipalign, apksigner) ──
Write-Host ""
Write-Host "Locating Android build-tools..." -ForegroundColor Yellow
$sdkRoots = @(
    $env:ANDROID_SDK_ROOT,
    $env:ANDROID_HOME,
    "$env:LOCALAPPDATA\Android\Sdk",
    "$env:USERPROFILE\AppData\Local\Android\Sdk"
) | Where-Object { $_ }
$buildToolsDir = $null
foreach ($root in $sdkRoots) {
    $bt = Join-Path $root "build-tools"
    if (Test-Path $bt) {
        $latest = Get-ChildItem -Path $bt -Directory -ErrorAction SilentlyContinue |
            Sort-Object { try { [version]($_.Name -replace '[^0-9.].*$', '') } catch { [version]'0.0' } } |
            Select-Object -Last 1
        if ($latest) { $buildToolsDir = $latest.FullName; break }
    }
}
if (-not $buildToolsDir) {
    Write-Host "  ERROR: Android build-tools not found." -ForegroundColor Red
    Write-Host "  Set ANDROID_SDK_ROOT or install build-tools via Android Studio." -ForegroundColor Red
    exit 1
}
$zipalign = Join-Path $buildToolsDir "zipalign.exe"
$apksigner = Join-Path $buildToolsDir "apksigner.bat"
if (-not (Test-Path $zipalign) -or -not (Test-Path $apksigner)) {
    Write-Host "  ERROR: zipalign/apksigner not found in $buildToolsDir" -ForegroundColor Red
    exit 1
}
Write-Host "  Found: $buildToolsDir" -ForegroundColor Green

# apksigner.bat resolves java via JAVA_HOME / PATH; java may not be on PATH here,
# so point JAVA_HOME at the JDK we already resolved.
if (-not $env:JAVA_HOME) {
    $env:JAVA_HOME = Split-Path (Split-Path $javaExe)
}

# ── Build Standalone arm64-v8a APK (uses tool/strip_apk.py for correct ZIP STORE) ──
Write-Host ""
Write-Host "Building Standalone arm64-v8a APK (Shorebird compatible)..." -ForegroundColor Yellow

# Find Python (python3, python, or Windows registry/AppData fallback)
$pythonExe = $null
$py3 = Get-Command python3 -ErrorAction SilentlyContinue
if ($py3) { $pythonExe = $py3.Source }
if (-not $pythonExe) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) { $pythonExe = $py.Source }
}
if (-not $pythonExe) {
    $regPaths = Get-ItemProperty "HKCU:\Software\Python\PythonCore\*\InstallPath", "HKLM:\Software\Python\PythonCore\*\InstallPath" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ExecutablePath -ErrorAction SilentlyContinue
    foreach ($p in $regPaths) {
        if ($p -and (Test-Path $p)) { $pythonExe = $p; break }
    }
}
if (-not $pythonExe) {
    $common = Get-ChildItem "$env:LOCALAPPDATA\Python\pythoncore-*\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($common -and (Test-Path $common)) { $pythonExe = $common }
}
if (-not $pythonExe) {
    Write-Host "  ERROR: Python not found. Install Python 3 to build standalone APKs." -ForegroundColor Red
    exit 1
}
Write-Host "  Using Python: $pythonExe" -ForegroundColor DarkGray

$stripperScript = Join-Path $PSScriptRoot "tool\strip_apk.py"
if (-not (Test-Path $stripperScript)) {
    Write-Host "  ERROR: strip_apk.py not found at $stripperScript" -ForegroundColor Red
    exit 1
}

$strippedApk = Join-Path $outputDir "inzx-$versionSafe-unaligned.apk"
$finalArm64Apk = Join-Path $outputDir "inzx.apk"

& $pythonExe $stripperScript $universalTarget $strippedApk "arm64-v8a"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: strip_apk.py failed" -ForegroundColor Red
    exit 1
}

Write-Host "  Aligning APK..." -ForegroundColor Yellow
if (Test-Path $finalArm64Apk) { Remove-Item $finalArm64Apk -Force }
& $zipalign -f -p 4 $strippedApk $finalArm64Apk
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: zipalign failed" -ForegroundColor Red
    exit 1
}

Write-Host "  Signing APK..." -ForegroundColor Yellow
& $apksigner sign --ks $keystorePath --ks-key-alias $keyAlias `
    --ks-pass "pass:$keystorePassword" --key-pass "pass:$keyPassword" $finalArm64Apk
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: apksigner failed" -ForegroundColor Red
    exit 1
}

Remove-Item $strippedApk -Force -ErrorAction SilentlyContinue
# Remove the raw extracted universal.apk; keep the versioned copy
Remove-Item $universalApk -Force -ErrorAction SilentlyContinue

# ── Done ──
$univSize = [math]::Round((Get-Item $universalTarget).Length / 1MB, 2)
$arm64Size = [math]::Round((Get-Item $finalArm64Apk).Length / 1MB, 2)
Write-Host ""
Write-Host "=== SUCCESS ===" -ForegroundColor Green
Write-Host "Universal APK:  $universalTarget ($univSize MB)" -ForegroundColor Cyan
Write-Host "arm64-v8a APK:  $finalArm64Apk ($arm64Size MB)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Upload the APKs to GitHub Releases for Shorebird distribution." -ForegroundColor White
