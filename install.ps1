# =============================================================================
#  Install this terminal setup on a fresh machine.
#
#      cd <terminal folder>
#      .\install.ps1
#
#  Options:
#      -NoAppearance   leave Windows Terminal's settings.json untouched
#      -NoAutostart    install everything but keep fastfetch off at startup
#
#  The folder can live anywhere: every path is derived from where this file
#  sits. Nothing here needs administrator privileges.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$NoAppearance,
    [switch]$NoAutostart
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

function Step($n, $t) { Write-Host ""; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    $t" -ForegroundColor Green }
function Info($t)     { Write-Host "    $t" -ForegroundColor DarkGray }
function Warn($t)     { Write-Host "    $t" -ForegroundColor Yellow }

function Invoke-Native {
    # PowerShell 5.1 turns anything a native program writes to stderr into an
    # ErrorRecord, and under $ErrorActionPreference = 'Stop' that aborts the
    # whole script. The Microsoft Store python.exe stub does exactly this, which
    # used to kill the install before it had done anything. Native commands go
    # through here so their noise can never take the installer down with them.
    param([scriptblock]$Command)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try     { & $Command 2>&1 | Out-String }
    catch   { "$_" }
    finally { $ErrorActionPreference = $previous }
}

function Invoke-NativeVisible {
    # Same stderr protection, but the output is deliberately NOT captured.
    # winget prints progress and can ask questions; piping that into a variable
    # buffers everything until the command ends, so a prompt would sit invisible
    # while the script looks frozen, waiting on an answer nobody was shown.
    param([scriptblock]$Command)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try     { & $Command }
    catch   { Warn "$_" }
    finally { $ErrorActionPreference = $previous }
}

Write-Host ""
Write-Host "  terminal setup -> $Root" -ForegroundColor White

# --------------------------------------------------------------- 1. fastfetch
Step 1 "fastfetch"
$ff = Get-Command fastfetch.exe -CommandType Application -ErrorAction SilentlyContinue |
      Select-Object -First 1
if ($ff) {
    Ok "already installed: $($ff.Source)"
} else {
    Info "not found."
    $r = Read-Host "    Install it now with winget? [y/N]"
    if ($r -match '^[yY]') {
        Invoke-NativeVisible {
            winget install --id Fastfetch-cli.Fastfetch --source winget `
                   --accept-package-agreements --accept-source-agreements `
                   --disable-interactivity
        }
        Info "reopen the terminal afterwards so PATH picks it up"
    } else {
        Warn "skipped. Install it later with:  winget install Fastfetch-cli.Fastfetch"
    }
}

# ------------------------------------------------------------------ 2. Python
Step 2 "Python (only needed to redraw the logo)"
# May return more than one match when PATH has several installs. Entries under
# WindowsApps are the Microsoft Store alias: a stub that is not an interpreter
# at all, it only prints a message telling you to go install Python. Skipping
# them here is what makes the difference between finding Python and finding a
# shortcut that pretends to be Python.
$py = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue |
      Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
      Select-Object -First 1
if ($py) {
    Ok "found: $($py.Source)"
    $probe = Invoke-Native { & $py.Source -c "import PIL, numpy; print('ok')" }
    if ($probe -match '\bok\b') { Ok "Pillow and numpy present" }
    else { Warn "Pillow/numpy missing:  python -m pip install pillow numpy" }
} else {
    Info "not found. Not required to use the setup, only to regenerate the logo"
    Info "after redrawing it. Install it from python.org if you want to."
}

# ------------------------------------------------------- 3. PowerShell profile
Step 3 "PowerShell profile"
$stub = @"
# =============================================================================
#  This file is only a loader.
#  The real content lives in $Root\powershell\profile.ps1.
#  If that folder disappears this profile does nothing and raises no error.
# =============================================================================

`$CustomizationProfile = '$Root\powershell\profile.ps1'
if (Test-Path -LiteralPath `$CustomizationProfile) {
    . `$CustomizationProfile
}
"@

# Windows PowerShell 5.1 and, when present, PowerShell 7: separate profiles
$targets = @(Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
if (Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1) {
    $targets += Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
}

foreach ($t in $targets) {
    $dir = Split-Path -Parent $t
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ((Test-Path -LiteralPath $t) -and -not ((Get-Content $t -Raw) -match 'CustomizationProfile')) {
        # A pre-existing profile that is not ours: never overwrite, append instead.
        Copy-Item $t "$t.backup" -Force
        Add-Content -LiteralPath $t -Value "`r`n$stub" -Encoding UTF8
        Warn "existing profile found: appended (backup in $(Split-Path -Leaf $t).backup)"
    } else {
        Set-Content -LiteralPath $t -Value $stub -Encoding UTF8
        Ok (Split-Path -Leaf (Split-Path -Parent $t))
    }
    Info $t
}

# ----------------------------------------------------------------- 4. junction
Step 4 "junction for the fastfetch config"
$link = Join-Path $HOME '.config\fastfetch'
$target = Join-Path $Root 'fastfetch'
$parent = Split-Path -Parent $link
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
if (Test-Path -LiteralPath $link) {
    $existing = Get-Item -LiteralPath $link -Force
    if ($existing.LinkType -eq 'Junction' -and $existing.Target -eq $target) {
        Ok "already present and correct"
    } else {
        Warn "$link already exists"
        $r = Read-Host "    Replace it with the junction? [y/N]"
        if ($r -match '^[yY]') {
            Remove-Item -LiteralPath $link -Recurse -Force
            New-Item -ItemType Junction -Path $link -Target $target | Out-Null
            Ok "created"
        } else { Warn "skipped: fastfetch will not find the config on its own" }
    }
} else {
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Ok "$link -> $target"
}

# ------------------------------------------------------- 5. terminal appearance
Step 5 "Windows Terminal appearance"
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if ($NoAppearance) {
    Info "skipped (-NoAppearance)"
} elseif (-not (Test-Path -LiteralPath $wt)) {
    Warn "Windows Terminal is not installed: skipping"
} else {
    # ONLY when absent: on a second run the current state is already customized,
    # and overwriting this would destroy the restore point.
    $orig = Join-Path $Root 'windows-terminal\settings.json.original'
    if (-not (Test-Path -LiteralPath $orig)) {
        Copy-Item -LiteralPath $wt -Destination $orig -Force
        Info "backup: windows-terminal\settings.json.original"
    } else {
        Info "backup already there, leaving it alone"
    }
    . (Join-Path $Root 'powershell\profile.ps1')
    if (Set-TerminalAppearance $true) { Ok "scheme, background and font applied" }
    else { Warn "not applied: check profileGuid in windows-terminal\appearance.json" }
}

# ------------------------------------------------------------- 6. autostart
Step 6 "fastfetch at startup"
$flag = Join-Path $Root 'fastfetch\autostart.on'
if ($NoAutostart) {
    Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
    Info "left off (-NoAutostart). Turn it on with:  customize on"
} else {
    New-Item -ItemType File -Path $flag -Force | Out-Null
    Ok "on"
}

Write-Host ""
Write-Host "  Done. Open a new window." -ForegroundColor Green
Write-Host "  Then:  customize        for state and switches" -ForegroundColor DarkGray
Write-Host ""
