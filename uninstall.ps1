# =============================================================================
#  Remove this terminal setup from the machine.
#
#      cd <terminal folder>
#      .\uninstall.ps1
#
#  Undoes exactly what install.ps1 did and nothing else. It never deletes this
#  folder, never touches your artwork, and never removes fastfetch unless you
#  ask. Answering no to everything leaves the machine as it is.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$RemoveFastfetch
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

function Step($n, $t) { Write-Host ""; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    $t" -ForegroundColor Green }
function Info($t)     { Write-Host "    $t" -ForegroundColor DarkGray }
function Warn($t)     { Write-Host "    $t" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  removing the terminal setup -> $Root" -ForegroundColor White

# -------------------------------------------------- 1. Windows Terminal look
Step 1 "Windows Terminal appearance"
$profileScript = Join-Path $Root 'powershell\profile.ps1'
if (Test-Path -LiteralPath $profileScript) {
    . $profileScript
    if (Set-TerminalAppearance $false) {
        Ok "colour scheme, background and font removed from your profile"
        Info "the palette itself stays in your scheme list, harmless and unused"
    } else {
        Info "nothing to undo"
    }
} else {
    Warn "powershell\profile.ps1 not found, skipping"
}

# ---------------------------------------------------------- 2. autostart flag
Step 2 "fastfetch at startup"
$flag = Join-Path $Root 'fastfetch\autostart.on'
if (Test-Path -LiteralPath $flag) {
    Remove-Item -LiteralPath $flag -Force
    Ok "turned off"
} else {
    Info "already off"
}

# ----------------------------------------------------------------- 3. junction
Step 3 "junction at ~/.config/fastfetch"
$link = Join-Path $HOME '.config\fastfetch'
$item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
if (-not $item) {
    Info "not there"
} elseif ($item.LinkType -eq 'Junction') {
    # Delete the reparse point itself. "Remove-Item -Recurse" on a junction asks
    # an alarming question about child items - and those children are the real
    # files on the other side, in this very folder. Deleting the link directly
    # cannot touch them.
    $item.Delete()
    Ok "link removed (your files were not touched)"
} else {
    Warn "$link is a real folder, not our link: leaving it alone"
}

# ------------------------------------------------------- 4. profile loader
Step 4 "PowerShell profile loader"
$targets = @(
    Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
)
foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t)) { continue }
    $content = Get-Content -LiteralPath $t -Raw
    if ($content -notmatch 'CustomizationProfile') {
        Info "$(Split-Path -Leaf (Split-Path -Parent $t)): not ours, untouched"
        continue
    }
    # Strip only our block, so a profile that also holds your own aliases keeps
    # them. What is left over is deleted only when it is genuinely empty.
    $cleaned = [regex]::Replace(
        $content,
        '(?ms)^\s*#\s*=+\s*\r?\n(?:^#.*\r?\n)*?^#\s*=+\s*\r?\n\s*\$CustomizationProfile\s*=.*?^\}\s*',
        '')
    if ($cleaned.Trim().Length -eq 0) {
        Remove-Item -LiteralPath $t -Force
        Ok "$(Split-Path -Leaf (Split-Path -Parent $t)): removed"
    } elseif ($cleaned -ne $content) {
        Set-Content -LiteralPath $t -Value $cleaned.TrimEnd() -Encoding UTF8
        Ok "$(Split-Path -Leaf (Split-Path -Parent $t)): our part removed, the rest kept"
    } else {
        Warn "$(Split-Path -Leaf (Split-Path -Parent $t)): could not identify our block"
        Info "open it and delete the lines mentioning CustomizationProfile:"
        Info $t
    }
}

# ---------------------------------------------------------------- 5. fastfetch
Step 5 "fastfetch itself"
if ($RemoveFastfetch) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { winget uninstall --id Fastfetch-cli.Fastfetch 2>&1 | Out-String | Write-Host }
    catch { Warn "winget said: $_" }
    finally { $ErrorActionPreference = $previous }
} else {
    Info "left installed. Pass -RemoveFastfetch to uninstall it too,"
    Info "or run:  winget uninstall Fastfetch-cli.Fastfetch"
}

Write-Host ""
Write-Host "  Done. Open a new window and you are back to a stock terminal." -ForegroundColor Green
Write-Host "  This folder was left untouched - delete it whenever you like." -ForegroundColor DarkGray
Write-Host ""
