# ==========================================
# MY PC - AUTOMATIC APP INSTALLER (Win 10/11)
# Run in a NORMAL (non-admin) PowerShell window so Spotify installs.
# ==========================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "WinGet is missing. Install 'App Installer' from the Microsoft Store first." -ForegroundColor Red
    Read-Host "Press Enter to exit"; return
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "WARNING: running as admin. Spotify's installer will fail. Re-run in a normal window." -ForegroundColor Yellow
}

# ---------- winget (community repo + Store) ----------
$apps = @(
    @{Name="7-Zip";                ID="7zip.7zip"}
    @{Name="Bloxstrap";            ID="pizzaboxer.Bloxstrap"}
    @{Name="Claude";               ID="Anthropic.Claude"}
    @{Name="Epic Games Launcher";  ID="EpicGames.EpicGamesLauncher"}
    @{Name="Firefox";              ID="Mozilla.Firefox"}
    @{Name="Modrinth";             ID="Modrinth.ModrinthApp"}
    @{Name="OBS Studio";           ID="OBSProject.OBSStudio"}
    @{Name="Parsec";               ID="Parsec.Parsec"}
    @{Name="Razer Synapse";        ID="Razer.Synapse3"}
    @{Name="Roblox";               ID="Roblox.Roblox"}
    @{Name="Spotify";              ID="Spotify.Spotify"}
    @{Name="Steam";                ID="Valve.Steam"}
    @{Name="Thorium";              ID="Alex313031.Thorium"}
    @{Name="Visual Studio Code";   ID="Microsoft.VisualStudioCode"}
    @{Name="VLC";                  ID="VideoLAN.VLC"}
    @{Name="Spicetify";            ID="Spicetify.Spicetify"}   # keep AFTER Spotify
    @{Name="ChatGPT";              ID="9NT1R1C2HH7J"; Store=$true}
    @{Name="Xbox App";             ID="9MV0B5HZVK9Z"; Store=$true}
    @{Name="Xbox Gaming Services"; ID="9MWPM2CQNLHN"; Store=$true}
    @{Name="Xbox Game Bar";        ID="9NZKPSTSNW4P"; Store=$true}
    @{Name="OP Auto Clicker";      ID="9N621DM2LVHQ"; Store=$true}
)

$success = @(); $failed = @(); $skipped = @()
$alreadyCodes = @(-1978335135, -1978335189)
$total = $apps.Count; $count = 0

foreach ($app in $apps) {
    $count++
    Write-Host "`n[$count/$total] $($app.Name)..." -ForegroundColor Yellow
    $src = if ($app.Store) { "msstore" } else { "winget" }

    winget show --id $app.ID --exact --source $src --accept-source-agreements *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "NOT FOUND: $($app.Name) ($($app.ID))" -ForegroundColor Magenta
        $skipped += "$($app.Name) ($($app.ID))"; continue
    }

    winget install --id $app.ID --exact --source $src --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity

    if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: $($app.Name)" -ForegroundColor Green; $success += $app.Name }
    elseif ($alreadyCodes -contains $LASTEXITCODE) { Write-Host "ALREADY INSTALLED: $($app.Name)" -ForegroundColor DarkGreen; $success += "$($app.Name) (already installed)" }
    else { Write-Host "FAILED: $($app.Name) (code $LASTEXITCODE)" -ForegroundColor Red; $failed += $app.Name }
}

# ---------- GitHub release downloads (MultiAlt, Yapfast) ----------
function Install-GitHubRelease {
    param($Name, $Repo, $AssetPattern, $InstallArgs)

    Write-Host "`n[GitHub] $Name..." -ForegroundColor Yellow
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "pc-installer" }
        $asset = $rel.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
        if (-not $asset) { throw "No asset matching $AssetPattern in $($rel.tag_name)" }

        # Only ever download from the project's own GitHub release
        if ($asset.browser_download_url -notlike "https://github.com/$Repo/releases/download/*") { throw "Unexpected download URL" }

        $file = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing

        # Verify SHA256 if GitHub published one for the asset
        if ($asset.digest -and $asset.digest -like "sha256:*") {
            $expected = $asset.digest.Substring(7)
            $actual = (Get-FileHash $file -Algorithm SHA256).Hash
            if ($actual -ne $expected) { Remove-Item $file -Force; throw "Hash mismatch, file deleted" }
            Write-Host "Hash verified ($($rel.tag_name))" -ForegroundColor DarkGreen
        } else {
            Write-Host "No published hash for this asset, skipping hash check" -ForegroundColor DarkYellow
        }

        if ($file -like "*.msi") { $p = Start-Process msiexec.exe -ArgumentList "/i `"$file`" /qn" -Wait -PassThru }
        else { $p = Start-Process $file -ArgumentList $InstallArgs -Wait -PassThru }

        if ($p.ExitCode -eq 0) { Write-Host "SUCCESS: $Name" -ForegroundColor Green; $script:success += "$Name $($rel.tag_name)" }
        else { throw "Installer exit code $($p.ExitCode)" }
    }
    catch {
        Write-Host "FAILED: $Name - $_" -ForegroundColor Red
        $script:failed += $Name
    }
}

# MultiAlt: per-user .msi from github.com/luanmacea/MultiAlt
Install-GitHubRelease -Name "MultiAlt" -Repo "luanmacea/MultiAlt" -AssetPattern "*.msi"

# Yapfast: per-user setup .exe from github.com/yapfast/yapfast (no admin; unsigned beta)
Install-GitHubRelease -Name "Yapfast" -Repo "yapfast/yapfast" -AssetPattern "*windows-x64-setup.exe" -InstallArgs "/S"

# ---------- report ----------
Write-Host "`n==== REPORT ====" -ForegroundColor Cyan
Write-Host "`nInstalled:" -ForegroundColor Green;  $success | ForEach-Object { Write-Host " + $_" }
Write-Host "`nFailed:" -ForegroundColor Red;       $failed  | ForEach-Object { Write-Host " - $_" }
Write-Host "`nID not found (check with 'winget search'):" -ForegroundColor Magenta; $skipped | ForEach-Object { Write-Host " ? $_" }

Write-Host "`nManual steps:" -ForegroundColor Yellow
Write-Host " * EXM Tweaks: download needs a free EXM account login, so get it from https://exmtweaks.com/en-us/download"
Write-Host " * Spicetify: open Spotify once and log in, then run:  spicetify backup apply"
Write-Host " * Yapfast: if the silent flag didn't work, run the installer from your Temp folder by hand"
Read-Host "`nPress Enter to exit"
