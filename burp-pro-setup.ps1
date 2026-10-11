<#
.SYNOPSIS
    BurpSuite Pro - Universal Windows Setup Script
    Supports: Windows 10 / 11 / Server (x64)
    Features: Winget JDK 17-26 Auto-Install | Pure Direct Download | Clean System State | Desktop & Start Menu Integration

.DESCRIPTION
    Fully automated 1-click installer and configurator for Burp Suite Professional on Windows.
    Uses native Windows tools (winget, .NET HttpClient) for all downloads and installations.
    Performs clean network inspection, installs/configures Java JDK, downloads Burp Suite Pro JAR and burploader,
    assists with offline activation, and creates CLI commands, Desktop shortcuts, and Start Menu launchers.
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# -- Colors & UI Formatting ----------------------------------------------
try {
    $Host.UI.RawUI.WindowTitle = "BurpSuite Pro - Universal Setup (Windows)"
} catch {}

function Write-Banner {
    Clear-Host
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |       BurpSuite Pro - Universal Windows Setup Script       |" -ForegroundColor Cyan
    Write-Host "  |       Direct Download * Winget Native * Clean Networking   |" -ForegroundColor Cyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor DarkBlue
    Write-Host "  $Message" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor DarkBlue
    Write-Host ""
}

function Write-Info  { param([string]$Msg) Write-Host "[INFO]  " -ForegroundColor Cyan -NoNewline; Write-Host $Msg }
function Write-Ok    { param([string]$Msg) Write-Host "[ OK ]  " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn  { param([string]$Msg) Write-Host "[ ! ]   " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err   { param([string]$Msg) Write-Host "[ X ]   " -ForegroundColor Red -NoNewline; Write-Host $Msg }

function Pause-Script {
    Write-Host ""
    Write-Host ">>  Press ENTER to continue..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
}

function Die {
    param([string]$Msg)
    Write-Err $Msg
    Pause-Script
    exit 1
}

# -- Privilege Verification & Elevation ----------------------------------
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$IS_ADMIN = Test-IsAdmin

Write-Banner

if (-not $IS_ADMIN) {
    Write-Warn "Script is running without Administrator privileges."
    Write-Host "   Administrator permissions are recommended to install JDK and verify system hosts/firewall." -ForegroundColor Yellow
    Write-Host ""
    $elevate = Read-Host "Would you like to elevate and relaunch as Administrator? [Y/n, default=Y]"
    $elevate = if ([string]::IsNullOrWhiteSpace($elevate)) { "Y" } else { $elevate }
    if ($elevate -match '^[Yy]') {
        Write-Info "Relaunching elevated PowerShell..."
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            exit
        } catch {
            Write-Warn "Elevation declined or failed. Continuing in standard user mode..."
        }
    } else {
        Write-Warn "Continuing without Administrator privileges. System-wide tasks will be skipped if restricted."
    }
}

$REAL_USER = $env:USERNAME
$REAL_HOME = $env:USERPROFILE
$OS_VERSION = [System.Environment]::OSVersion.VersionString
$ARCH = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$HAS_WINGET = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)

Write-Info "Executing User     : $REAL_USER"
Write-Info "User Home Dir      : $REAL_HOME"
Write-Info "Operating System   : $OS_VERSION"
Write-Info "Architecture       : $ARCH"
Write-Info "Administrator      : $(if ($IS_ADMIN) { 'Yes (Elevated)' } else { 'No (User Mode)' })"
Write-Info "Winget Available   : $(if ($HAS_WINGET) { 'Yes (v' + ((winget --version 2>&1) -replace 'v','') + ')' } else { 'No' })"
Write-Host ""

if ($ARCH -ne "x64") {
    Write-Warn "Burp Suite Pro and Oracle JDK 64-bit packages require an x64 operating system."
}

# ========================================================================
#  SAFEGUARD: System State & Network Cleanup
# ========================================================================
Write-Step "INSPECTION -- Restoring Clean System & Network State"

$HOSTS_FILE = "$env:SystemRoot\System32\drivers\etc\hosts"
if (Test-Path $HOSTS_FILE) {
    try {
        $hostsContent = Get-Content -Path $HOSTS_FILE -ErrorAction Stop
        $conflicts = $hostsContent | Where-Object { $_ -match 'portswigger|burpsuite' }
        if ($conflicts) {
            Write-Warn "Detected modified PortSwigger/BurpSuite entries in hosts file. Restoring clean hosts..."
            if ($IS_ADMIN) {
                $cleaned = $hostsContent | Where-Object { $_ -notmatch 'portswigger|burpsuite' }
                Set-Content -Path $HOSTS_FILE -Value $cleaned -Force -ErrorAction Stop
                Write-Ok "hosts file restored to clean state."
            } else {
                Write-Warn "Administrator rights required to modify hosts file. Skipping hosts cleanup."
            }
        } else {
            Write-Ok "hosts file is clean."
        }
    } catch {
        Write-Warn "Could not inspect hosts file: $_"
    }
}

if ($IS_ADMIN) {
    try {
        $blockedRules = Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'portswigger|burpsuite' -or $_.Description -match 'portswigger|burpsuite' }
        if ($blockedRules) {
            Write-Info "Removing conflicting outbound firewall rules for PortSwigger..."
            $blockedRules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Write-Ok "Firewall rules restored."
        } else {
            Write-Ok "No conflicting firewall rules found."
        }
    } catch {
        Write-Ok "Firewall check passed."
    }
} else {
    Write-Ok "Skipped firewall inspection (requires Admin)."
}

# ========================================================================
#  NATIVE DIRECT DOWNLOAD HELPERS
# ========================================================================
function Invoke-DirectDownload {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Activity = "Downloading"
    )

    try {
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }

        $handler = New-Object System.Net.Http.HttpClientHandler
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromMinutes(25)
        $client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $client.Dispose()
            return $false
        }

        $totalLength = $response.Content.Headers.ContentLength
        $sourceStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $destStream = [System.IO.File]::Create($OutputPath)

        $buffer = New-Object byte[] 65536
        $totalBytesRead = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUpdate = [System.DateTime]::MinValue

        while (($bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $destStream.Write($buffer, 0, $bytesRead)
            $totalBytesRead += $bytesRead

            $now = [System.DateTime]::Now
            if (($now - $lastUpdate).TotalMilliseconds -ge 500) {
                $lastUpdate = $now
                $mbRead = [Math]::Round($totalBytesRead / 1MB, 2)
                $speed = if ($stopwatch.Elapsed.TotalSeconds -gt 0) { [Math]::Round(($totalBytesRead / 1MB) / $stopwatch.Elapsed.TotalSeconds, 2) } else { 0 }
                if ($totalLength -and $totalLength -gt 0) {
                    $mbTotal = [Math]::Round($totalLength / 1MB, 2)
                    $pct = [Math]::Min(100, [int](($totalBytesRead / $totalLength) * 100))
                    Write-Progress -Activity $Activity -Status "$mbRead MB / $mbTotal MB ($pct%) - $speed MB/s" -PercentComplete $pct
                } else {
                    Write-Progress -Activity $Activity -Status "$mbRead MB downloaded - $speed MB/s"
                }
            }
        }

        Write-Progress -Activity $Activity -Completed
        $destStream.Close()
        $sourceStream.Close()
        $client.Dispose()
        return $true
    } catch {
        Write-Progress -Activity $Activity -Completed
        return $false
    }
}

function Test-ValidJar {
    param(
        [string]$FilePath,
        [long]$MinSize = 5000
    )
    if (-not (Test-Path $FilePath)) { return $false }
    $fileInfo = Get-Item $FilePath -ErrorAction SilentlyContinue
    if ($null -eq $fileInfo -or $fileInfo.Length -lt $MinSize) { return $false }

    # Check PK zip header (0x50, 0x4B)
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] 2
        $bytesRead = $stream.Read($buffer, 0, 2)
        $stream.Close()
        if ($bytesRead -lt 2 -or $buffer[0] -ne 0x50 -or $buffer[1] -ne 0x4B) {
            return $false
        }
    } catch {
        return $false
    }

    # Verify ZIP integrity using .NET ZipArchive
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $valid = ($zip.Entries.Count -ge 0)
        $zip.Dispose()
        return $valid
    } catch {
        return $false
    }
}

# ========================================================================
#  Google Drive Direct Downloader (Pure .NET)
# ========================================================================
function Get-GDriveDownload {
    param(
        [string]$FileId,
        [string]$OutputPath
    )

    $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    $gdriveUrl = "https://drive.google.com/uc?export=download&id=$FileId"

    Write-Info "Downloading burploader via direct .NET session..."
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }

    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.CookieContainer = New-Object System.Net.CookieContainer
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add("User-Agent", $ua)
        $client.Timeout = [TimeSpan]::FromSeconds(60)

        $resp = $client.GetAsync($gdriveUrl).GetAwaiter().GetResult()
        $contentBytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()

        if ($contentBytes.Length -ge 2 -and $contentBytes[0] -eq 0x50 -and $contentBytes[1] -eq 0x4B) {
            [System.IO.File]::WriteAllBytes($OutputPath, $contentBytes)
            if (Test-ValidJar -FilePath $OutputPath -MinSize 5000) {
                Write-Ok "Direct download: success"
                $client.Dispose()
                return $true
            }
        } else {
            $html = [System.Text.Encoding]::UTF8.GetString($contentBytes)
            $tokenMatch = [regex]::Match($html, 'confirm=([0-9A-Za-z_]+)')
            $token = if ($tokenMatch.Success) { $tokenMatch.Groups[1].Value } else { "t" }
            $confirmUrl = "https://drive.google.com/uc?export=download&confirm=$token&id=$FileId"
            $resp2 = $client.GetAsync($confirmUrl).GetAwaiter().GetResult()
            $contentBytes2 = $resp2.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            if ($contentBytes2.Length -ge 2 -and $contentBytes2[0] -eq 0x50 -and $contentBytes2[1] -eq 0x4B) {
                [System.IO.File]::WriteAllBytes($OutputPath, $contentBytes2)
                if (Test-ValidJar -FilePath $OutputPath -MinSize 5000) {
                    Write-Ok "Direct download (confirm token): success"
                    $client.Dispose()
                    return $true
                }
            }
        }
        $client.Dispose()
    } catch {}

    Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    return $false
}

# ========================================================================
#  STEP 01 -- Select, Install & Configure Java (JDK 17 - 26 via Winget)
# ========================================================================
Write-Step "STEP 01 -- Installing & Configuring Java Runtime (JDK 17-26)"

function Get-ActiveJavaVersion {
    $ver = 0
    $javaPath = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($javaPath) {
        $output = (& java.exe -version 2>&1) | Out-String
        if ($output -match 'version "(\d+)') {
            $ver = [int]$matches[1]
        } elseif ($output -match 'openjdk (\d+)') {
            $ver = [int]$matches[1]
        }
    }
    return $ver
}

$CURRENT_JAVA_VER = Get-ActiveJavaVersion
Write-Info "Current active system Java version: $(if ($CURRENT_JAVA_VER -gt 0) { "JDK $CURRENT_JAVA_VER" } else { "None in active PATH" })"

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "  Select Java Runtime Version (JDK 17 - 26)                  " -ForegroundColor Yellow
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "Burp Suite Pro and loaders run on modern Java runtimes (Java 17+)."
Write-Host "Choose which JDK version to configure or install:`n"
Write-Host "  17) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 17 (LTS)  " -NoNewline; Write-Host "(Stable LTS)" -ForegroundColor Yellow
Write-Host "  18) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 18"
Write-Host "  19) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 19"
Write-Host "  20) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 20"
Write-Host "  21) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 21 (LTS)  " -NoNewline; Write-Host "* Recommended LTS" -ForegroundColor Green
Write-Host "  22) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 22"
Write-Host "  23) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 23        " -NoNewline; Write-Host "* Recommended (Default - proven loader compatibility)" -ForegroundColor Green
Write-Host "  24) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 24"
Write-Host "  25) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 25"
Write-Host "  26) " -ForegroundColor Cyan -NoNewline; Write-Host "JDK 26        " -NoNewline; Write-Host "[!] NOT RECOMMENDED (Experimental / potential incompatibilities)" -ForegroundColor Red
Write-Host ""

$CHOSEN_JAVA_VER = Read-Host "Enter Java version [17-26, default=23]"
$CHOSEN_JAVA_VER = if ([string]::IsNullOrWhiteSpace($CHOSEN_JAVA_VER)) { "23" } else { $CHOSEN_JAVA_VER }

if ($CHOSEN_JAVA_VER -notmatch '^\d+$' -or [int]$CHOSEN_JAVA_VER -lt 17 -or [int]$CHOSEN_JAVA_VER -gt 26) {
    Write-Warn "Invalid choice ($CHOSEN_JAVA_VER). Defaulting to recommended JDK 23."
    $CHOSEN_JAVA_VER = 23
} else {
    $CHOSEN_JAVA_VER = [int]$CHOSEN_JAVA_VER
}

if ($CHOSEN_JAVA_VER -eq 26) {
    Write-Host ""
    Write-Warn "WARNING: Java 26 is NOT recommended!"
    Write-Host "   Java 26 is experimental and may cause bytecode incompatibility or loader crashes." -ForegroundColor Yellow
    Write-Host "   We strongly advise using Java 21 LTS or Java 23 instead." -ForegroundColor Yellow
    Write-Host ""
    $confirm26 = Read-Host "Are you sure you want to proceed with Java 26? [y/N, default=N]"
    $confirm26 = if ([string]::IsNullOrWhiteSpace($confirm26)) { "N" } else { $confirm26 }
    if ($confirm26 -notmatch '^[Yy]') {
        Write-Info "Switched to recommended Java 23."
        $CHOSEN_JAVA_VER = 23
    } else {
        Write-Warn "Proceeding with Java 26 per user selection."
    }
}

Write-Ok "Selected target Java runtime: JDK $CHOSEN_JAVA_VER"

$JDK_DIR_CANDIDATES = @(
    "C:\Program Files\Java\jdk-$CHOSEN_JAVA_VER",
    "C:\Program Files\Java\jdk-$CHOSEN_JAVA_VER.*",
    "C:\Program Files\Eclipse Adoptium\jdk-$CHOSEN_JAVA_VER*",
    "C:\Program Files\Microsoft\jdk-$CHOSEN_JAVA_VER*"
)

$FOUND_JDK_DIR = ""
foreach ($cand in $JDK_DIR_CANDIDATES) {
    $matchesDir = Get-Item $cand -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($matchesDir -and (Test-Path "$($matchesDir.FullName)\bin\java.exe")) {
        $FOUND_JDK_DIR = $matchesDir.FullName
        break
    }
}

$JDK_TARGET_INSTALLED = $false
if ($CURRENT_JAVA_VER -eq $CHOSEN_JAVA_VER) {
    Write-Ok "Java $CHOSEN_JAVA_VER is already the active system runtime."
    $JDK_TARGET_INSTALLED = $true
} elseif ($FOUND_JDK_DIR) {
    Write-Info "Found existing JDK $CHOSEN_JAVA_VER at: $FOUND_JDK_DIR"
    $JDK_TARGET_INSTALLED = $true
}

if (-not $JDK_TARGET_INSTALLED) {
    $installedViaWinget = $false
    if ($HAS_WINGET) {
        Write-Info "Installing Oracle JDK $CHOSEN_JAVA_VER via winget (Windows Package Manager)..."
        $wingetArgs = @(
            "install",
            "--id", "Oracle.JDK.$CHOSEN_JAVA_VER",
            "--exact",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements"
        )
        try {
            $wingetProc = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -Wait -PassThru
            if ($wingetProc.ExitCode -eq 0) {
                Write-Ok "winget: Oracle JDK $CHOSEN_JAVA_VER installed successfully!"
                $installedViaWinget = $true
            } else {
                Write-Warn "winget returned exit code $($wingetProc.ExitCode). Checking disk or using direct download fallback..."
            }
        } catch {
            Write-Warn "winget install encountered an issue: $_"
        }
    }

    # Direct download fallback if winget was not available or did not complete
    if (-not $installedViaWinget) {
        Write-Info "Direct downloading Oracle JDK $CHOSEN_JAVA_VER (Windows x64 installer)..."
        $javaTempDir = "$env:TEMP\burp_jdk_setup"
        New-Item -ItemType Directory -Path $javaTempDir -Force | Out-Null
        $jdkExe = "$javaTempDir\jdk-${CHOSEN_JAVA_VER}_windows-x64_bin.exe"

        function Get-OracleJdkUrl {
            param([int]$v)
            switch ($v) {
                17 { return "https://download.oracle.com/java/17/archive/jdk-17_windows-x64_bin.exe" }
                18 { return "https://download.oracle.com/java/18/archive/jdk-18_windows-x64_bin.exe" }
                19 { return "https://download.oracle.com/java/19/archive/jdk-19_windows-x64_bin.exe" }
                20 { return "https://download.oracle.com/java/20/archive/jdk-20_windows-x64_bin.exe" }
                21 { return "https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.exe" }
                22 { return "https://download.oracle.com/java/22/archive/jdk-22_windows-x64_bin.exe" }
                23 { return "https://download.oracle.com/java/23/archive/jdk-23_windows-x64_bin.exe" }
                24 { return "https://download.oracle.com/java/24/archive/jdk-24_windows-x64_bin.exe" }
                25 { return "https://download.oracle.com/java/25/latest/jdk-25_windows-x64_bin.exe" }
                26 { return "https://download.oracle.com/java/26/latest/jdk-26_windows-x64_bin.exe" }
                default { return "" }
            }
        }

        $primaryUrl = Get-OracleJdkUrl $CHOSEN_JAVA_VER
        $fallbackUrl = "https://download.oracle.com/java/${CHOSEN_JAVA_VER}/latest/jdk-${CHOSEN_JAVA_VER}_windows-x64_bin.exe"

        $dlOk = $false
        foreach ($url in @($primaryUrl, $fallbackUrl)) {
            if ([string]::IsNullOrEmpty($url)) { continue }
            Write-Info "Connecting to direct download URL: $url"
            $dlOk = Invoke-DirectDownload -Url $url -OutputPath $jdkExe -Activity "Downloading JDK $CHOSEN_JAVA_VER installer"
            if ($dlOk -and (Test-Path $jdkExe) -and (Get-Item $jdkExe).Length -gt 50000000) {
                break
            }
            Remove-Item $jdkExe -Force -ErrorAction SilentlyContinue
        }

        if (-not $dlOk) {
            Die "Failed to download JDK $CHOSEN_JAVA_VER installer. Check network connection."
        }

        Write-Info "Executing silent installer..."
        try {
            $installProc = Start-Process -FilePath $jdkExe -ArgumentList "/s" -Wait -PassThru
            if ($installProc.ExitCode -eq 0) {
                Write-Ok "Oracle JDK $CHOSEN_JAVA_VER installed!"
            }
        } catch {
            Die "Failed to run JDK installer: $_"
        } finally {
            Remove-Item $jdkExe -Force -ErrorAction SilentlyContinue
        }
    }
}

# Locate JDK directory & binary
$finalJavaBin = ""
$finalJavawBin = ""

$candidates = @(
    "C:\Program Files\Java\jdk-$CHOSEN_JAVA_VER*",
    "C:\Program Files\Eclipse Adoptium\jdk-$CHOSEN_JAVA_VER*",
    "C:\Program Files\Microsoft\jdk-$CHOSEN_JAVA_VER*"
)
foreach ($c in $candidates) {
    $dirMatch = Get-Item $c -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($dirMatch -and (Test-Path "$($dirMatch.FullName)\bin\java.exe")) {
        $finalJavaBin = "$($dirMatch.FullName)\bin\java.exe"
        $finalJavawBin = "$($dirMatch.FullName)\bin\javaw.exe"
        $FOUND_JDK_DIR = $dirMatch.FullName
        break
    }
}

if (-not $finalJavaBin) {
    $javaCmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $finalJavaBin = $javaCmd.Source
        $finalJavawBin = Join-Path (Split-Path $finalJavaBin) "javaw.exe"
    } else {
        Die "Could not locate java.exe after setup. Please check C:\Program Files\Java."
    }
}

if ($FOUND_JDK_DIR) {
    $env:JAVA_HOME = $FOUND_JDK_DIR
    $jdkBinPath = "$FOUND_JDK_DIR\bin"
    if ($env:Path -notlike "*$jdkBinPath*") {
        $env:Path = "$jdkBinPath;$env:Path"
    }
    try {
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $FOUND_JDK_DIR, [EnvironmentVariableTarget]::User)
        $userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
        if ($userPath -notlike "*$jdkBinPath*") {
            [Environment]::SetEnvironmentVariable("Path", "$jdkBinPath;$userPath", [EnvironmentVariableTarget]::User)
        }
    } catch {}
}

Write-Host ""
Write-Info "Active Java executable: $finalJavaBin"
$javaVerOutput = (& "$finalJavaBin" -version 2>&1) | Out-String
Write-Host ($javaVerOutput.Trim()) -ForegroundColor Gray
Write-Ok "JDK $CHOSEN_JAVA_VER configured successfully!"
Pause-Script

# ========================================================================
#  STEP 02 -- Download BurpSuite Pro & Loader Files (Direct Download)
# ========================================================================
Write-Step "STEP 02 -- Downloading BurpSuite Pro & Helper Files"

$BURP_DIR = Join-Path $REAL_HOME "Documents\burp"
if (-not (Test-Path $BURP_DIR)) {
    New-Item -ItemType Directory -Path $BURP_DIR -Force | Out-Null
}
Set-Location $BURP_DIR
Write-Info "Working directory: $BURP_DIR"

$GDRIVE_ID = "10JUah3Zoa1bi4qXTeQvx4phGtNxngMIZ"
$KEYGEN = "burploader.jar"
$KEYGEN_PATH = Join-Path $BURP_DIR $KEYGEN

if (Test-ValidJar -FilePath $KEYGEN_PATH -MinSize 5000) {
    Write-Ok "burploader.jar already exists and is valid - skipping download."
} else {
    Remove-Item $KEYGEN_PATH -Force -ErrorAction SilentlyContinue
    $gdriveOk = Get-GDriveDownload -FileId $GDRIVE_ID -OutputPath $KEYGEN_PATH

    if (-not $gdriveOk -or -not (Test-ValidJar -FilePath $KEYGEN_PATH -MinSize 5000)) {
        Remove-Item $KEYGEN_PATH -Force -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Err "Automated download failed. Please download it manually:"
        Write-Host "  1. Open this URL in your browser:" -ForegroundColor Yellow
        Write-Host "     https://drive.google.com/file/d/$GDRIVE_ID/view?usp=sharing" -ForegroundColor Cyan
        Write-Host "  2. Save file as:" -ForegroundColor Yellow
        Write-Host "     $KEYGEN_PATH" -ForegroundColor Cyan
        Write-Host "  3. Return here and press ENTER." -ForegroundColor Yellow
        Pause-Script
        if (-not (Test-ValidJar -FilePath $KEYGEN_PATH -MinSize 5000)) {
            Die "burploader.jar is not present or invalid."
        }
    }
}
Write-Ok "burploader.jar verified [ OK ]"

function Get-PortSwiggerProReleases {
    param([string]$targetYear)

    $versions = @()
    try {
        $url = "https://portswigger.net/burp/releases/archive?y=$targetYear"
        $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
        $html = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 12 -UseBasicParsing -ErrorAction Stop).Content
        $matches = [regex]::Matches($html, 'href=["''][^"'']*burp/releases/(?:professional(?:-community)?)-([0-9a-zA-Z\.\-]+)["'']')
        foreach ($m in $matches) {
            $v = $m.Groups[1].Value -replace '-', '.'
            if ($versions -notcontains $v) {
                $versions += $v
            }
        }
        if ($versions.Count -gt 0) { return $versions }
    } catch {}

    $fallbacks = @{
        "2026" = @("2026.9.2", "2026.9.1", "2026.9", "2026.8", "2026.7.3", "2026.6.2", "2026.5.1", "2026.4", "2026.3", "2026.2", "2026.1")
        "2025" = @("2025.12.3", "2025.12.2", "2025.12.1", "2025.11.6", "2025.10.7", "2025.9.1", "2025.8.3", "2025.7.1", "2025.6.2", "2025.5.1", "2025.4.1", "2025.3.2", "2025.2.1", "2025.1.1")
        "2024" = @("2024.12", "2024.11.2", "2024.11.1", "2024.10.3", "2024.9.4", "2024.8.5", "2024.7.6", "2024.6.4", "2024.5.5", "2024.4.1", "2024.3.1", "2024.2.2", "2024.1.3")
        "2023" = @("2023.12.1", "2023.11.1.3", "2023.10.3.7", "2023.9.4", "2023.8.2", "2023.7.3", "2023.6.2", "2023.5.3", "2023.4.4", "2023.3.5", "2023.3.3", "2023.2.1", "2023.1.2")
        "2022" = @("2022.12.5", "2022.11.3", "2022.9.6", "2022.8.5", "2022.7.1", "2022.3.9", "2022.2.5", "2022.1.1")
        "2021" = @("2021.12", "2021.10.3", "2021.8.4", "2021.6.2", "2021.5.1", "2021.4.1", "2021.2.1")
        "2020" = @("2020.12.1", "2020.11.3", "2020.9.2", "2020.8.1", "2020.5.1", "2020.4.1", "2020.2.1", "2020.1")
        "2019" = @("2.1.07", "2.1.06", "2.1.05", "2.1.04", "2.1.02", "2.1.01", "2.0.20")
        "2018" = @("2.0.13beta", "2.0.12beta", "2.0.11beta", "1.7.37", "1.7.36", "1.7.35", "1.7.34", "1.7.33", "1.7.32", "1.7.31")
        "2017" = @("1.7.30", "1.7.29", "1.7.28", "1.7.27", "1.7.26", "1.7.25", "1.7.24", "1.7.23", "1.7.22", "1.7.21", "1.7.20")
        "2016" = @("1.7.15", "1.7.14", "1.7.13", "1.7.12", "1.7.11", "1.7.10", "1.7.09", "1.7.08", "1.7.07", "1.7.06", "1.7.05")
    }

    if ($fallbacks.ContainsKey($targetYear)) {
        return $fallbacks[$targetYear]
    }
    return @()
}

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "  STEP 02b -- SELECT BURPSUITE PRO VERSION (PORTSWIGGER)     " -ForegroundColor Yellow
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "JAR files are downloaded directly from " -NoNewline
Write-Host "https://portswigger.net/burp/releases" -ForegroundColor Cyan
Write-Host "You can select popular versions or browse all Pro JAR releases from the last 10 years (2016-2026).`n"

Write-Host "  1) " -ForegroundColor Cyan -NoNewline; Write-Host "v2025.12.3  " -NoNewline; Write-Host "(Stable 2025 release)" -ForegroundColor Yellow
Write-Host "  2) " -ForegroundColor Cyan -NoNewline; Write-Host "v2023.3.3   " -NoNewline; Write-Host "(Recommended - highest loader compatibility)" -ForegroundColor Yellow
Write-Host "  3) " -ForegroundColor Cyan -NoNewline; Write-Host "v2026.9.2   " -NoNewline; Write-Host "(Latest 2026 release)" -ForegroundColor Yellow
Write-Host "  4) " -ForegroundColor Cyan -NoNewline; Write-Host "v2024.11.2  " -NoNewline; Write-Host "(Stable 2024 release)" -ForegroundColor Yellow
Write-Host "  5) " -ForegroundColor Cyan -NoNewline; Write-Host "Browse by Year  " -ForegroundColor White -NoNewline; Write-Host "(Explore last 10 years: 2026 down to 2016)" -ForegroundColor Cyan
Write-Host "  6) " -ForegroundColor Cyan -NoNewline; Write-Host "Custom Version  " -ForegroundColor White -NoNewline; Write-Host "(Enter any version manually)" -ForegroundColor Cyan
Write-Host ""

$VER_MENU_CHOICE = Read-Host "Enter choice [1-6, default=1]"
$VER_MENU_CHOICE = if ([string]::IsNullOrWhiteSpace($VER_MENU_CHOICE)) { "1" } else { $VER_MENU_CHOICE }

$BURP_VER = ""
switch ($VER_MENU_CHOICE) {
    "1" { $BURP_VER = "2025.12.3" }
    "2" { $BURP_VER = "2023.3.3" }
    "3" { $BURP_VER = "2026.9.2" }
    "4" { $BURP_VER = "2024.11.2" }
    "5" {
        $YEARS = @("2026", "2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018", "2017", "2016")
        Write-Host ""
        Write-Host "Select Release Year (Last 10 Years):" -ForegroundColor Yellow
        for ($i = 0; $i -lt $YEARS.Count; $i++) {
            Write-Host ("  {0,2}) {1}" -f ($i + 1), $YEARS[$i]) -ForegroundColor Cyan
        }
        Write-Host ""
        $YR_NUM = Read-Host "Enter year number [1-11, default=1]"
        $YR_NUM = if ([string]::IsNullOrWhiteSpace($YR_NUM)) { "1" } else { $YR_NUM }
        $selectedYear = if ($YR_NUM -match '^\d+$' -and [int]$YR_NUM -ge 1 -and [int]$YR_NUM -le $YEARS.Count) {
            $YEARS[[int]$YR_NUM - 1]
        } else {
            "2026"
        }

        Write-Info "Fetching Professional JAR releases for $selectedYear from PortSwigger..."
        $yearVersions = Get-PortSwiggerProReleases $selectedYear

        if ($yearVersions.Count -eq 0) {
            Write-Warn "No releases retrieved automatically for $selectedYear. Falling back to default."
            $BURP_VER = "2025.12.3"
        } else {
            Write-Host ""
            Write-Host "Available Burp Suite Pro releases for $selectedYear`:" -ForegroundColor Yellow
            $maxShow = [Math]::Min($yearVersions.Count, 20)
            for ($i = 0; $i -lt $maxShow; $i++) {
                Write-Host ("  {0,2}) v{1}" -f ($i + 1), $yearVersions[$i]) -ForegroundColor Cyan
            }
            Write-Host ""
            $VER_PICK = Read-Host "Enter release number [1-$maxShow, default=1]"
            $VER_PICK = if ([string]::IsNullOrWhiteSpace($VER_PICK)) { "1" } else { $VER_PICK }
            if ($VER_PICK -match '^\d+$' -and [int]$VER_PICK -ge 1 -and [int]$VER_PICK -le $maxShow) {
                $BURP_VER = $yearVersions[[int]$VER_PICK - 1]
            } else {
                $BURP_VER = $yearVersions[0]
            }
        }
    }
    "6" {
        Write-Host ""
        $customInput = Read-Host "Enter Burp Suite Pro version (e.g. 2024.11.2, 2023.3.3, 1.7.30)"
        $BURP_VER = if ([string]::IsNullOrWhiteSpace($customInput)) { "2025.12.3" } else { $customInput.Trim() }
    }
    default {
        $BURP_VER = "2025.12.3"
    }
}

$BURP_JAR = "burpsuite_pro_v${BURP_VER}.jar"
$BURP_JAR_PATH = Join-Path $BURP_DIR $BURP_JAR
Write-Ok "Selected Burp Suite Pro: v$BURP_VER"

if (Test-ValidJar -FilePath $BURP_JAR_PATH -MinSize 50000000) {
    Write-Ok "$BURP_JAR already exists and is valid - skipping download."
} else {
    Remove-Item $BURP_JAR_PATH -Force -ErrorAction SilentlyContinue
    Write-Info "Direct downloading BurpSuite Pro v$BURP_VER from PortSwigger (~600-750 MB)..."

    if ($BURP_VER -match '^202[6-9]') {
        $downloadUrls = @(
            "https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VER&type=jar",
            "https://portswigger.net/burp/releases/startdownload?product=desktop&version=$BURP_VER&type=jar",
            "https://portswigger.net/burp/releases/download?product=pro&version=$BURP_VER&type=Jar",
            "https://portswigger.net/burp/releases/startdownload?product=pro&version=$BURP_VER&type=Jar"
        )
    } else {
        $downloadUrls = @(
            "https://portswigger.net/burp/releases/download?product=pro&version=$BURP_VER&type=Jar",
            "https://portswigger.net/burp/releases/startdownload?product=pro&version=$BURP_VER&type=Jar",
            "https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VER&type=jar",
            "https://portswigger.net/burp/releases/startdownload?product=desktop&version=$BURP_VER&type=jar"
        )
    }

    $downloaded = $false
    foreach ($dlUrl in $downloadUrls) {
        Write-Info "Connecting to direct endpoint: $dlUrl"
        $dlSuccess = Invoke-DirectDownload -Url $dlUrl -OutputPath $BURP_JAR_PATH -Activity "Downloading $BURP_JAR"

        if ($dlSuccess -and (Test-ValidJar -FilePath $BURP_JAR_PATH -MinSize 50000000)) {
            $downloaded = $true
            break
        }
        Write-Warn "Endpoint did not return a valid JAR (>50 MB). Trying next endpoint..."
        Remove-Item $BURP_JAR_PATH -Force -ErrorAction SilentlyContinue
    }

    if ($downloaded) {
        Write-Ok "BurpSuite Pro v$BURP_VER downloaded successfully!"
    } else {
        Write-Host ""
        Write-Err "Automated download failed. Please download it manually:"
        Write-Host "  1. Open this URL in your browser:" -ForegroundColor Yellow
        Write-Host "     https://portswigger.net/burp/releases" -ForegroundColor Cyan
        Write-Host "  2. Locate version $BURP_VER and download the JAR file." -ForegroundColor Yellow
        Write-Host "  3. Save file as:" -ForegroundColor Yellow
        Write-Host "     $BURP_JAR_PATH" -ForegroundColor Cyan
        Write-Host "  4. Return here and press ENTER." -ForegroundColor Yellow
        Pause-Script
        if (-not (Test-ValidJar -FilePath $BURP_JAR_PATH -MinSize 50000000)) {
            Die "Downloaded BurpSuite JAR is invalid. Please check the file and re-run."
        }
    }
}

Write-Host ""
Write-Ok "Files ready in $BURP_DIR`:"
Get-ChildItem -Path $BURP_DIR | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Host
Pause-Script

# ========================================================================
#  STEP 03 -- Launch Keygen & BurpSuite
# ========================================================================
Write-Step "STEP 03 -- Application Launch & Activation Workflow"

Write-Host "====== ACTIVATION PROCEDURE ====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Keygen GUI will open -> " -ForegroundColor Cyan -NoNewline; Write-Host "Copy the License Key." -ForegroundColor White
Write-Host "  2. Click " -ForegroundColor Cyan -NoNewline; Write-Host "[ Run ] " -ForegroundColor White -NoNewline; Write-Host "in Keygen to start BurpSuite."
Write-Host "  3. In BurpSuite: Paste the License Key and click " -ForegroundColor Cyan -NoNewline; Write-Host "[ Next ]." -ForegroundColor White
Write-Host "  4. Select " -ForegroundColor Cyan -NoNewline; Write-Host "[ Manual Activation ] " -ForegroundColor White -NoNewline; Write-Host "when shown."
Write-Host "  5. Copy the " -ForegroundColor Cyan -NoNewline; Write-Host "Activation Request " -ForegroundColor White -NoNewline; Write-Host "from Burp into Keygen."
Write-Host "  6. Copy the generated " -ForegroundColor Cyan -NoNewline; Write-Host "Activation Response " -ForegroundColor White -NoNewline; Write-Host "from Keygen into Burp."
Write-Host "  7. Finish activation in BurpSuite." -ForegroundColor Cyan
Write-Host ""
Write-Host "Press ENTER to launch $KEYGEN..." -ForegroundColor Yellow
Pause-Script

$JAVA_MODULE_FLAGS = "--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED"

Write-Info "Launching $KEYGEN GUI in background (window will stay open)..."
$keygenArgs = "$JAVA_MODULE_FLAGS -jar `"$KEYGEN_PATH`""
$keygenProc = Start-Process -FilePath $finalJavaBin -ArgumentList $keygenArgs -PassThru

Write-Host ""
Write-Ok "$KEYGEN GUI is now running (PID: $($keygenProc.Id))."
Write-Host "* The Keygen window is now open on your screen - do NOT close it!" -ForegroundColor Green
Write-Host ""

$ACTIVATION_DONE = $false
while (-not $ACTIVATION_DONE) {
    Write-Host "Activation Status:" -ForegroundColor Yellow
    $actInput = Read-Host "Has Burp Suite activation finished successfully? [y/N]"
    if ($actInput -match '^[Yy]') {
        $ACTIVATION_DONE = $true
        Write-Ok "Activation completed successfully! [ OK ]"
    } else {
        Write-Host ""
        Write-Warn "Activation is not finished yet."
        $retryAct = Read-Host "Would you like to re-launch the Keygen to try again? [Y/n, default=Y]"
        $retryAct = if ([string]::IsNullOrWhiteSpace($retryAct)) { "Y" } else { $retryAct }
        if ($retryAct -match '^[Yy]') {
            Write-Info "Relaunching $KEYGEN GUI..."
            $keygenProc = Start-Process -FilePath $finalJavaBin -ArgumentList $keygenArgs -PassThru
            Write-Ok "$KEYGEN relaunched (PID: $($keygenProc.Id))."
            Write-Host "Complete the activation steps in the GUI, then return here." -ForegroundColor Cyan
        } else {
            Write-Warn "Proceeding with launcher setup..."
            $ACTIVATION_DONE = $true
        }
    }
}

# -- Step 03b: Copy Loader Command ---------------------------------------
Write-Host ""
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "  STEP 03b -- GET THE LOADER COMMAND FROM KEYGEN             " -ForegroundColor Yellow
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "  * Make sure to KEEP the Keygen loader window open!" -ForegroundColor Yellow
Write-Host "  1. Look at the 'Loader Command' field at the top of the Keygen window." -ForegroundColor Cyan
Write-Host "  2. Copy the text from that field and paste it below." -ForegroundColor Cyan
Write-Host "  3. (Or press ENTER to use the auto-detected Java command)." -ForegroundColor Cyan
Write-Host ""

$CUSTOM_LOADER_CMD = Read-Host "Paste Loader Command here [or press ENTER]"

if (-not [string]::IsNullOrWhiteSpace($CUSTOM_LOADER_CMD)) {
    $LOADER_CMD = $CUSTOM_LOADER_CMD.Trim()
} else {
    $LOADER_CMD = "`"$finalJavaBin`" $JAVA_MODULE_FLAGS -javaagent:`"$KEYGEN_PATH`" -jar `"$BURP_JAR_PATH`""
}

$LOADER_CMD_SILENT = if ($LOADER_CMD -match 'java\.exe') {
    $LOADER_CMD -replace 'java\.exe', 'javaw.exe'
} elseif ($LOADER_CMD.StartsWith("java ")) {
    $LOADER_CMD -replace '^java\s+', "`"$finalJavawBin`" "
} else {
    "`"$finalJavawBin`" $JAVA_MODULE_FLAGS -javaagent:`"$KEYGEN_PATH`" -jar `"$BURP_JAR_PATH`""
}

Write-Host ""
Write-Ok "Loader command configured:"
Write-Host "  $LOADER_CMD" -ForegroundColor Cyan
Write-Host ""

# -- Create burp.bat, burp.vbs, burp-pro.cmd -----------------------------
$BURP_BAT = Join-Path $BURP_DIR "burp.bat"
$BURP_VBS = Join-Path $BURP_DIR "burp.vbs"
$BURP_CMD = Join-Path $BURP_DIR "burp-pro.cmd"

Write-Info "Creating startup scripts at $BURP_DIR..."
$batContent = "@echo off`r`ncd /d `"%~dp0`"`r`nstart `"`" $LOADER_CMD_SILENT %*`r`n"
[System.IO.File]::WriteAllText($BURP_BAT, $batContent)
Write-Ok "Startup batch script created: $BURP_BAT"

$vbsContent = "Set WshShell = CreateObject(`"WScript.Shell`")`r`nWshShell.CurrentDirectory = `"$BURP_DIR`"`r`nWshShell.Run `"$LOADER_CMD_SILENT`", 0, False`r`n"
[System.IO.File]::WriteAllText($BURP_VBS, $vbsContent)
Write-Ok "Silent VBS launcher created: $BURP_VBS"

$cmdContent = "@echo off`r`ncd /d `"%~dp0`"`r`nstart `"`" $LOADER_CMD_SILENT %*`r`n"
[System.IO.File]::WriteAllText($BURP_CMD, $cmdContent)
Write-Ok "CLI wrapper created: $BURP_CMD"

try {
    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    if ($currentUserPath -notlike "*$BURP_DIR*") {
        Write-Info "Adding $BURP_DIR to User PATH environment variable..."
        [Environment]::SetEnvironmentVariable("Path", "$BURP_DIR;$currentUserPath", [EnvironmentVariableTarget]::User)
        $env:Path = "$BURP_DIR;$env:Path"
        Write-Ok "CLI command registered: type 'burp-pro' in any terminal to launch!"
    } else {
        Write-Ok "CLI command 'burp-pro' already in PATH."
    }
} catch {
    Write-Warn "Could not update User PATH: $_"
}

# ========================================================================
#  STEP 04 -- Create Desktop Launcher & App Icons
# ========================================================================
Write-Step "STEP 04 -- Creating Desktop & Start Menu Launchers"

$ICON_PNG = Join-Path $BURP_DIR "burpsuite.png"
$ICON_ICO = Join-Path $BURP_DIR "burpsuite.ico"

Write-Info "Configuring Burp Suite Pro icon..."
$extractedPng = $false

try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($BURP_JAR_PATH)
    $iconCandidates = @(
        "resources/Media/icon64pro.png",
        "resources/Media/icon64.png",
        "resources/Media/icon32pro.png",
        "resources/Media/icon32.png",
        "resources/Media/icon16pro.png"
    )

    foreach ($cand in $iconCandidates) {
        $entry = $zip.GetEntry($cand)
        if ($null -ne $entry) {
            $stream = $entry.Open()
            $fileStream = [System.IO.File]::Create($ICON_PNG)
            $stream.CopyTo($fileStream)
            $stream.Close()
            $fileStream.Close()
            if ((Test-Path $ICON_PNG) -and (Get-Item $ICON_PNG).Length -gt 0) {
                Write-Ok "Official icon extracted: $cand"
                $extractedPng = $true
                break
            }
        }
    }
    $zip.Dispose()
} catch {}

if (-not $extractedPng -or -not (Test-Path $ICON_PNG) -or (Get-Item $ICON_PNG).Length -eq 0) {
    Write-Info "Embedding official Burp Suite Pro 64x64 icon..."
    $base64Icon = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAnFBMVEVbT/9jV/9tYv+qo/////+6tf+Lgv/9/f90af/19f+Hfv9kWf/l5P+po/9cUP/Py//IxP+xrP/h3/9iVv+Si//y8f9vZf95cP/4+P/8/P+Ee/9nXP/r6f+hmv9dUf/W0//BvP/7+v+uqP+Ad/+ak/9/dv9sYf/v7v9gVP/c2v96cP+moP/Rzv/6+v+/uv+gmf9hVf/g3v/Hw//19P8g0/xMAAAA2klEQVR4Ae3WNXrFMBRE4XnRfczMzLbD+99bPJVTBebmS6W/n9MYJETRt0oPuRJ0wXLBFYiBsjNQqfoCtTr31QZEzZZRG6JO16gHVd9oMIRoZDSeQDSdcT9fQLRcGa0h2myNdr430PaHQEf82skKypt43vsCl6u5Are7+QJJWsjiL+2PAllaSJTAJ/ebL3C9wBXYn+ELnPBrx0CHR6MyVE9G2w1Ez0arJUSLOfezKUSTsdEIopdXoz5Ub0bdDkRto1YTokaV+/ea72usVuALlOMv7R8D+nU/ij4AkKERE6vBiJsAAAAASUVORK5CYII="
    $pngBytes = [System.Convert]::FromBase64String($base64Icon)
    [System.IO.File]::WriteAllBytes($ICON_PNG, $pngBytes)
}

try {
    $pngBytes = [System.IO.File]::ReadAllBytes($ICON_PNG)
    $icoW = if ($pngBytes.Length -gt 24 -and $pngBytes[19] -gt 0) { [int]$pngBytes[19] } else { 64 }
    $icoH = if ($pngBytes.Length -gt 24 -and $pngBytes[23] -gt 0) { [int]$pngBytes[23] } else { 64 }
    $icoByteW = if ($icoW -ge 256) { 0 } else { [byte]$icoW }
    $icoByteH = if ($icoH -ge 256) { 0 } else { [byte]$icoH }

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]1)
    $bw.Write([Byte]$icoByteW)
    $bw.Write([Byte]$icoByteH)
    $bw.Write([Byte]0)
    $bw.Write([Byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$pngBytes.Length)
    $bw.Write([UInt32]22)
    $bw.Write($pngBytes)
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($ICON_ICO, $ms.ToArray())
    $bw.Close()
    $ms.Close()
    Write-Ok "Generated Windows icon: $ICON_ICO [ OK ]"
} catch {
    Write-Warn "Could not generate .ico file: $_"
}

$DESKTOP_DIR = [Environment]::GetFolderPath('Desktop')
$START_MENU_DIR = [Environment]::GetFolderPath('Programs')

$DESKTOP_SHORTCUT = Join-Path $DESKTOP_DIR "Burp-pro.lnk"
$START_SHORTCUT = Join-Path $START_MENU_DIR "Burp-pro.lnk"

try {
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($scPath in @($DESKTOP_SHORTCUT, $START_SHORTCUT)) {
        $sc = $wsh.CreateShortcut($scPath)
        $sc.TargetPath = $finalJavawBin
        $sc.Arguments = "$JAVA_MODULE_FLAGS -javaagent:`"$KEYGEN_PATH`" -jar `"$BURP_JAR_PATH`""
        $sc.WorkingDirectory = $BURP_DIR
        $sc.Description = "BurpSuite Pro v$BURP_VER - Web Security Testing"
        if (Test-Path $ICON_ICO) {
            $sc.IconLocation = "$ICON_ICO,0"
        }
        $sc.Save()
    }
    Write-Ok "Desktop shortcut created at: $DESKTOP_SHORTCUT"
    Write-Ok "Start Menu shortcut created at: $START_SHORTCUT"
} catch {
    Write-Warn "Failed to create Windows shortcuts: $_"
}

# ========================================================================
#  STEP 05 -- System & Installation Diagnostics
# ========================================================================
Write-Step "DIAGNOSTICS -- System Summary"

$activeJavaFirstLine = ((& "$finalJavaBin" -version 2>&1) | Select-Object -First 1)

Write-Host "  +==============================================================+" -ForegroundColor Cyan
Write-Host "  |                   [ OK ] Installation Summary                |" -ForegroundColor Cyan
Write-Host "  +==============================================================+" -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "OS            : $OS_VERSION ($ARCH)") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "User          : $REAL_USER") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Active Java   : $activeJavaFirstLine") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Burp Version  : v$BURP_VER") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Directory     : $BURP_DIR") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Startup Script: $BURP_BAT") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "CLI Command   : burp-pro") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Desktop Link  : $DESKTOP_SHORTCUT") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Start Menu    : $START_SHORTCUT") -ForegroundColor Cyan
Write-Host ("  |  {0,-58}|" -f "Download Mode : Pure Direct (.NET / Winget)") -ForegroundColor Cyan
Write-Host "  +==============================================================+" -ForegroundColor Cyan

Write-Host ""
Write-Host "All set! You can launch BurpSuite Pro by:" -ForegroundColor Green
Write-Host "  1. Double-clicking " -NoNewline; Write-Host "Burp-pro" -ForegroundColor White -NoNewline; Write-Host " on your Desktop"
Write-Host "  2. Searching " -NoNewline; Write-Host "Burp-pro" -ForegroundColor White -NoNewline; Write-Host " in the Windows Start Menu"
Write-Host "  3. Typing " -NoNewline; Write-Host "burp-pro" -ForegroundColor White -NoNewline; Write-Host " in PowerShell, CMD, or Windows Terminal`n"
