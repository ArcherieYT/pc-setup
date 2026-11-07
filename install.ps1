# ==========================================
# MY PC - AUTOMATIC APP INSTALLER (Win 10/11)
# Run in a NORMAL (non-admin) PowerShell window so Spotify installs.
# Checks each app first and skips anything already installed.
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

# ---------- app list (order matters: Spicetify after Spotify) ----------
# Type: winget | store | github
$items = @(
    @{Name="7-Zip";                Type="winget"; ID="7zip.7zip"; Match="7-Zip*"}
    @{Name="Bloxstrap";            Type="winget"; ID="pizzaboxer.Bloxstrap"; Match="Bloxstrap*"}   # Bloxstrap downloads Roblox itself on first launch
    @{Name="Claude";               Type="winget"; ID="Anthropic.Claude"; Match="Claude*"}
    @{Name="Epic Games Launcher";  Type="winget"; ID="EpicGames.EpicGamesLauncher"; Match="Epic Games Launcher*"}
    @{Name="Firefox";              Type="winget"; ID="Mozilla.Firefox"; Match="Mozilla Firefox*"}
    @{Name="Modrinth";             Type="winget"; ID="Modrinth.ModrinthApp"; Match="Modrinth*"}
    @{Name="OBS Studio";           Type="winget"; ID="OBSProject.OBSStudio"; Match="OBS Studio*"}
    @{Name="Parsec";               Type="winget"; ID="Parsec.Parsec"; Match="Parsec*"}
    @{Name="Razer Synapse";        Type="winget"; ID="RazerInc.RazerInstaller.Synapse4"; Match="Razer Synapse*"}
    @{Name="Spotify";              Type="winget"; ID="Spotify.Spotify"; Match="Spotify*"}
    @{Name="Spicetify";            Type="winget"; ID="Spicetify.Spicetify"; Exe="$env:LOCALAPPDATA\spicetify\spicetify.exe"; Cmd="spicetify"}
    @{Name="Steam";                Type="winget"; ID="Valve.Steam"; Match="Steam"}
    @{Name="Thorium";              Type="winget"; ID="Alex313031.Thorium"; Match="Thorium*"}
    @{Name="Visual Studio Code";   Type="winget"; ID="Microsoft.VisualStudioCode"; Match="Microsoft Visual Studio Code*"}
    @{Name="VLC";                  Type="winget"; ID="VideoLAN.VLC"; Match="VLC media player*"}
    @{Name="Git";                  Type="winget"; ID="Git.Git"; Match="Git"}
    @{Name="PowerToys";            Type="winget"; ID="Microsoft.PowerToys"; Match="PowerToys*"}
    @{Name="ChatGPT";              Type="store";  ID="9PLM9XGG6VKS"}
    @{Name="Xbox App";             Type="store";  ID="9MV0B5HZVK9Z"; Appx="Microsoft.GamingApp"}
    @{Name="Xbox Gaming Services"; Type="store";  ID="9MWPM2CQNLHN"; Appx="Microsoft.GamingServices"}
    @{Name="Xbox Game Bar";        Type="store";  ID="9NZKPSTSNW4P"; Appx="Microsoft.XboxGamingOverlay"}
    @{Name="OP Auto Clicker";      Type="store";  ID="9N621DM2LVHQ"}
    @{Name="MultiAlt";             Type="github"; Repo="luanmacea/MultiAlt"; Asset="*.msi"; Match="*MultiAlt*"; Folders=@("$env:LOCALAPPDATA\MultiAlt","$env:LOCALAPPDATA\Programs\MultiAlt","$env:ProgramFiles\MultiAlt")}
    @{Name="Yapfast";              Type="github"; Repo="yapfast/yapfast"; Asset="*windows-x64-setup.exe"; Args="/S"; Match="*Yapfast*"; Folders=@("$env:LOCALAPPDATA\Yapfast","$env:LOCALAPPDATA\Programs\Yapfast","$env:ProgramFiles\Yapfast")}
)

$success = @(); $already = @(); $failed = @(); $skipped = @(); $notes = @()
$alreadyCodes = @(-1978335135, -1978335189)   # winget: already installed / no upgrade available

# ---------- detection helpers ----------
function Test-WingetInstalled($id, $src) {
    winget list --id $id --exact --source $src --accept-source-agreements *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-UninstallEntry($pattern) {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $hit = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pattern }
    return [bool]$hit
}

function Test-ItemInstalled($item) {
    switch ($item.Type) {
        "winget" {
            if (Test-WingetInstalled $item.ID "winget") { return $true }
            if ($item.Match -and (Test-UninstallEntry $item.Match)) { return $true }
            if ($item.Exe -and (Test-Path $item.Exe)) { return $true }
            if ($item.Cmd -and (Get-Command $item.Cmd -ErrorAction SilentlyContinue)) { return $true }
            return $false
        }
        "store" {
            if (Test-WingetInstalled $item.ID "msstore") { return $true }
            if ($item.Appx -and (Get-AppxPackage -Name $item.Appx -ErrorAction SilentlyContinue)) { return $true }
            return $false
        }
        "github" {
            if (Test-UninstallEntry $item.Match) { return $true }
            foreach ($f in $item.Folders) { if (Test-Path $f) { return $true } }
            return $false
        }
    }
}

# ---------- install helpers ----------
function Install-Winget($item) {
    $src = if ($item.Type -eq "store") { "msstore" } else { "winget" }

    winget show --id $item.ID --exact --source $src --accept-source-agreements *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  NOT FOUND: $($item.Name) ($($item.ID))" -ForegroundColor Magenta
        $script:skipped += "$($item.Name) ($($item.ID))"; return
    }

    winget install --id $item.ID --exact --source $src --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity

    if ($LASTEXITCODE -eq 0) { Write-Host "  SUCCESS: $($item.Name)" -ForegroundColor Green; $script:success += $item.Name }
    elseif ($alreadyCodes -contains $LASTEXITCODE) { Write-Host "  ALREADY INSTALLED: $($item.Name)" -ForegroundColor DarkGreen; $script:already += $item.Name }
    else { Write-Host "  FAILED: $($item.Name) (code $LASTEXITCODE)" -ForegroundColor Red; $script:failed += $item.Name }
}

function Install-GitHub($item) {
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$($item.Repo)/releases/latest" -Headers @{ "User-Agent" = "pc-installer" }
        $asset = $rel.assets | Where-Object { $_.name -like $item.Asset } | Select-Object -First 1
        if (-not $asset) { throw "No asset matching $($item.Asset) in $($rel.tag_name)" }

        # Only ever download from the project's own GitHub release
        if ($asset.browser_download_url -notlike "https://github.com/$($item.Repo)/releases/download/*") { throw "Unexpected download URL" }

        $file = Join-Path $env:TEMP $asset.name
        Write-Host "  Downloading $($asset.name) ($($rel.tag_name))..."
        Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing

        if ($asset.digest -and $asset.digest -like "sha256:*") {
            $expected = $asset.digest.Substring(7)
            $actual = (Get-FileHash $file -Algorithm SHA256).Hash
            if ($actual -ne $expected) { Remove-Item $file -Force; throw "Hash mismatch, file deleted" }
            Write-Host "  Hash verified" -ForegroundColor DarkGreen
        } else {
            Write-Host "  No published hash for this asset, skipping hash check" -ForegroundColor DarkYellow
        }

        if ($file -like "*.msi") { $p = Start-Process msiexec.exe -ArgumentList "/i `"$file`" /qn" -Wait -PassThru }
        else { $p = Start-Process $file -ArgumentList $item.Args -Wait -PassThru }

        if ($p.ExitCode -eq 0) { Write-Host "  SUCCESS: $($item.Name) $($rel.tag_name)" -ForegroundColor Green; $script:success += "$($item.Name) $($rel.tag_name)" }
        else { throw "Installer exit code $($p.ExitCode)" }
    }
    catch {
        Write-Host "  FAILED: $($item.Name) - $_" -ForegroundColor Red
        $script:failed += $item.Name
    }
}

# ---------- Thorium helpers ----------
function Get-ThoriumPath {
    $candidates = @(
        "$env:LOCALAPPDATA\Thorium\Application\thorium.exe",
        "$env:ProgramFiles\Thorium\Application\thorium.exe",
        "${env:ProgramFiles(x86)}\Thorium\Application\thorium.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Test-ThoriumIsDefault {
    $keys = @("https","http")
    foreach ($k in $keys) {
        $prog = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$k\UserChoice" -ErrorAction SilentlyContinue).ProgId
        if ($prog -notlike "*Thorium*") { return $false }
    }
    return $true
}

function Set-ThoriumDefaultAuto {
    # Best effort using PS-SFTA (open source, MIT: github.com/DanysysTeam/PS-SFTA).
    # Pinned to a known file hash. If it doesn't match, we don't run it.
    $expected = "3eb6f6dee3fd8c91604042060b9d658f08ec85d3fd0a14769119dfd78bc30851"
    $file = Join-Path $env:TEMP "SFTA.ps1"
    try {
        Invoke-WebRequest "https://raw.githubusercontent.com/DanysysTeam/PS-SFTA/master/SFTA.ps1" -OutFile $file -UseBasicParsing
        if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $expected) { Write-Host "  SFTA file changed upstream, not running it" -ForegroundColor DarkYellow; return $false }

        # Find Thorium's registered capabilities (what shows up as options in Settings)
        $cap = $null
        foreach ($root in @("HKCU:\Software\Clients\StartMenuInternet","HKLM:\Software\Clients\StartMenuInternet","HKLM:\Software\WOW6432Node\Clients\StartMenuInternet")) {
            $k = Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*Thorium*" } | Select-Object -First 1
            if ($k) { $cap = Join-Path $k.PSPath "Capabilities"; break }
        }
        if (-not $cap -or -not (Test-Path $cap)) { Write-Host "  Couldn't find Thorium's browser registration" -ForegroundColor DarkYellow; return $false }

        . $file

        $urls  = Get-ItemProperty (Join-Path $cap "URLAssociations") -ErrorAction SilentlyContinue
        $files = Get-ItemProperty (Join-Path $cap "FileAssociations") -ErrorAction SilentlyContinue
        $skip = "PSPath","PSParentPath","PSChildName","PSDrive","PSProvider"
        if ($urls)  { $urls.PSObject.Properties  | Where-Object { $skip -notcontains $_.Name } | ForEach-Object { Set-PTA $_.Value $_.Name } }
        if ($files) { $files.PSObject.Properties | Where-Object { $skip -notcontains $_.Name } | ForEach-Object { Set-FTA $_.Value $_.Name } }
        Start-Sleep -Seconds 1
        return (Test-ThoriumIsDefault)
    }
    catch { Write-Host "  Auto-set failed: $_" -ForegroundColor DarkYellow; return $false }
}

function Set-ThoriumDefault {
    if (-not (Get-ThoriumPath)) { return }
    if (Test-ThoriumIsDefault) {
        Write-Host "  Thorium is already your default browser" -ForegroundColor DarkGreen
        return
    }

    Write-Host "  Trying to set Thorium as default browser..."
    if (Set-ThoriumDefaultAuto) {
        Write-Host "  Thorium is now your default browser" -ForegroundColor Green
        $script:success += "Thorium set as default browser"
        return
    }

    # Fallback: Windows blocked it, so open Thorium's page in Settings for a one-click finish
    Write-Host "  Couldn't set it automatically. Opening Settings (click 'Set default'). Continuing install..." -ForegroundColor Yellow
    Start-Process "ms-settings:defaultapps?registeredAppUser=Thorium"
    $script:notes += "Thorium default browser: auto-set didn't work on this Windows build, so click 'Set default' in the Settings window that opened."
}

function Open-InThorium($url) {
    $exe = Get-ThoriumPath
    if ($exe) { Start-Process $exe -ArgumentList $url }
    else { Start-Process $url }
}

# ---------- main loop ----------
$total = $items.Count; $count = 0
foreach ($item in $items) {
    $count++
    Write-Progress -Activity "Installing apps" -Status "$($item.Name) ($count/$total)" -PercentComplete (($count / $total) * 100)
    Write-Host "`n[$count/$total] $($item.Name)" -ForegroundColor Yellow
    Write-Host "  Checking if already installed..."

    if (Test-ItemInstalled $item) {
        Write-Host "  ALREADY INSTALLED: $($item.Name)" -ForegroundColor DarkGreen
        $already += $item.Name
    }
    else {
        Write-Host "  Not found, installing..."
        if ($item.Type -eq "github") { Install-GitHub $item } else { Install-Winget $item }
    }

    # Right after Thorium: offer to make it the default browser
    if ($item.Name -eq "Thorium") { Set-ThoriumDefault }
}
Write-Progress -Activity "Installing apps" -Completed

# ---------- FINAL STEP: CPU-based driver tool ----------
Write-Host "`n[FINAL STEP] Checking CPU for driver software..." -ForegroundColor Yellow
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Write-Host "  CPU: $($cpu.Name) ($($cpu.Manufacturer))"

if ($cpu.Manufacturer -like "*Intel*") {
    $drv = @{Name="Intel Driver & Support Assistant"; Type="winget"; ID="Intel.IntelDriverAndSupportAssistant"; Match="Intel*Driver*Support Assistant*"}
    Write-Host "  Intel CPU detected. Checking if $($drv.Name) is installed..."
    if (Test-ItemInstalled $drv) {
        Write-Host "  ALREADY INSTALLED: $($drv.Name)" -ForegroundColor DarkGreen
        $already += $drv.Name
    } else {
        Write-Host "  Not found, installing..."
        Install-Winget $drv
    }
}
elseif ($cpu.Manufacturer -like "*AMD*") {
    Write-Host "  AMD CPU detected."
    $gpus = (Get-CimInstance Win32_VideoController).Name -join ", "
    Write-Host "  Graphics: $gpus"
    if (Test-UninstallEntry "AMD Software*") {
        Write-Host "  ALREADY INSTALLED: AMD Software: Adrenalin Edition" -ForegroundColor DarkGreen
        $already += "AMD Software: Adrenalin Edition"
    } else {
        # AMD has no winget package and blocks direct download links, so open their official page
        Write-Host "  AMD doesn't allow scripted downloads. Opening AMD's official drivers page..." -ForegroundColor Yellow
        Open-InThorium "https://www.amd.com/en/support/download/drivers.html"
        $notes += "AMD Software: Adrenalin Edition - AMD's drivers page was opened in Thorium (or your default browser). Use the auto-detect option or pick your Radeon graphics (covers integrated Radeon on Ryzen laptops too)."
    }
}
else {
    Write-Host "  Unknown CPU vendor, skipping driver software." -ForegroundColor DarkYellow
}

# ---------- report ----------
Write-Host "`n==== REPORT ====" -ForegroundColor Cyan
Write-Host "`nNewly installed:" -ForegroundColor Green;   $success | ForEach-Object { Write-Host " + $_" }
Write-Host "`nAlready installed:" -ForegroundColor DarkGreen; $already | ForEach-Object { Write-Host " = $_" }
Write-Host "`nFailed:" -ForegroundColor Red;              $failed  | ForEach-Object { Write-Host " - $_" }
Write-Host "`nID not found (check with 'winget search'):" -ForegroundColor Magenta; $skipped | ForEach-Object { Write-Host " ? $_" }

Write-Host "`nManual steps:" -ForegroundColor Yellow
$notes | ForEach-Object { Write-Host " * $_" }
Write-Host " * EXM Tweaks: download needs a free EXM account login, get it from https://exmtweaks.com/en-us/download"
Write-Host " * Roblox: open Bloxstrap and it will download Roblox for you"
Write-Host " * Spicetify: open Spotify once and log in, then run:  spicetify backup apply"
Read-Host "`nPress Enter to exit"
