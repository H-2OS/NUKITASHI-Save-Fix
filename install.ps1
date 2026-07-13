<#
  NUKITASHI Save Fix - One-Click Installer
  Requires: Windows PowerShell 3.0+ (built into Windows 8+)
  Usage:    Double-click install.bat
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " NUKITASHI Save Fix Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Find game directory
# ============================================================
$gameDir = $null

# Strategy A: script is placed inside the game directory
if (Test-Path "$scriptDir\NUKITASHI.exe") {
    $gameDir = Resolve-Path "$scriptDir"
}
if (-not $gameDir -and (Test-Path "$scriptDir\..\NUKITASHI.exe")) {
    $gameDir = Resolve-Path "$scriptDir\.."
}

# Strategy B: search common Steam library paths
if (-not $gameDir) {
    $steamApps = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "C:\", "D:\", "E:\")) {
        if ($base) {
            foreach ($pattern in @(
                "$base\Steam\steamapps\common",
                "$base\Program Files (x86)\Steam\steamapps\common",
                "$base\SteamLibrary\steamapps\common",
                "$base\DeskApps\STEAM\steamapps\common"
            )) {
                foreach ($game in @("NUKITASHI", "NUKITASHI 2")) {
                    $test = "$pattern\$game"
                    if ((Test-Path "$test\NUKITASHI.exe") -or (Test-Path "$test\NUKITASHI2.exe")) {
                        $steamApps += $test
                    }
                }
            }
        }
    }
    $steamApps = $steamApps | Select-Object -Unique

    if ($steamApps.Count -eq 1) {
        $gameDir = $steamApps[0]
    } elseif ($steamApps.Count -gt 1) {
        Write-Host "Found multiple installations:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $steamApps.Count; $i++) {
            Write-Host "  [$($i+1)] $($steamApps[$i])"
        }
        $choice = Read-Host "Select number (1-$($steamApps.Count))"
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $steamApps.Count) {
            $gameDir = $steamApps[$idx]
        }
    }
}

# Strategy C: manual input
if (-not $gameDir) {
    Write-Host "Game directory not auto-detected." -ForegroundColor Yellow
    Write-Host "Enter the full path to the game folder (e.g. D:\Steam\steamapps\common\NUKITASHI)"
    $gameDir = Read-Host "Path"
}

# Validate
if (-not $gameDir) {
    Write-Host "ERROR: No game directory provided." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path "$gameDir\savedata\saveg.dat")) {
    Write-Host "ERROR: savedata\saveg.dat not found in $gameDir" -ForegroundColor Red
    Write-Host "This does not appear to be a valid NUKITASHI installation." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Game: $gameDir" -ForegroundColor Green
$savedir = "$gameDir\savedata"
$advDir = "$gameDir\system\adv"

# ============================================================
# 2. Backup existing patches (if any)
# ============================================================
Write-Host ""
Write-Host "[1/4] Backing up existing files..." -ForegroundColor Cyan
$backupDir = "$advDir\backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
if (Test-Path "$advDir\fileio.lua") {
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    Copy-Item "$advDir\fileio.lua" "$backupDir\fileio.lua" -Force
    Write-Host "  Backed up: fileio.lua" -ForegroundColor Gray
}
if (Test-Path "$advDir\fsave.lua") {
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    Copy-Item "$advDir\fsave.lua" "$backupDir\fsave.lua" -Force
    Write-Host "  Backed up: fsave.lua" -ForegroundColor Gray
}
if (-not (Test-Path $backupDir)) {
    Write-Host "  No existing patches to back up." -ForegroundColor Gray
}

# ============================================================
# 3. Build date table from PNG thumbnails
# ============================================================
Write-Host "[2/4] Reading save dates from thumbnails..." -ForegroundColor Cyan

$pngFiles = Get-ChildItem "$savedir\save[0-9][0-9][0-9][0-9].png" -ErrorAction SilentlyContinue | Sort-Object Name
$dateLines = @()
if ($pngFiles) {
    foreach ($png in $pngFiles) {
        $slot = [int]($png.BaseName.Substring(4, 4))
        $dt = $png.LastWriteTime
        $dateLines += "`t[$slot]`t= {$($dt.Year),$($dt.Month),$($dt.Day),$($dt.Hour),$($dt.Minute),$($dt.Second)},"
    }
    Write-Host "  Found $($pngFiles.Count) save thumbnails" -ForegroundColor Green
} else {
    Write-Host "  No thumbnails found, date table will be empty" -ForegroundColor Yellow
}
$dateTable = "_save_dates = {`r`n" + ($dateLines -join "`r`n") + "`r`n}"

# ============================================================
# 4. Generate fileio.lua
# ============================================================
Write-Host "[3/4] Generating fileio.lua..." -ForegroundColor Cyan

$template = Get-Content "$scriptDir\fileio_template.lua" -Raw -Encoding UTF8
$fileio_lua = $template.Replace("-- DATE_TABLE_PLACEHOLDER --", $dateTable)

if (-not (Test-Path $advDir)) { New-Item -ItemType Directory -Path $advDir -Force | Out-Null }
[System.IO.File]::WriteAllText("$advDir\fileio.lua", $fileio_lua, [System.Text.UTF8Encoding]($false))
Write-Host "  Created: $advDir\fileio.lua ($($fileio_lua.Length) bytes)" -ForegroundColor Green

# ============================================================
# 5. Copy fsave.lua
# ============================================================
Write-Host "[4/4] Deploying fsave.lua..." -ForegroundColor Cyan

$fsaveSrc = "$scriptDir\fsave.lua"
if (Test-Path $fsaveSrc) {
    Copy-Item $fsaveSrc "$advDir\fsave.lua" -Force
    Write-Host "  Created: $advDir\fsave.lua" -ForegroundColor Green
} else {
    Write-Host "  ERROR: fsave.lua not found in package" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Installation complete!" -ForegroundColor Green
Write-Host " Launch the game - the fix is now active." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "To uninstall, delete:" -ForegroundColor Gray
Write-Host "  $advDir\fileio.lua" -ForegroundColor Gray
Write-Host "  $advDir\fsave.lua" -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to exit"
