# =============================================================================
#  terminal / powershell / profile.ps1
#
#  Loaded by $PROFILE, which holds nothing but a pointer to this file, so the
#  whole terminal setup lives in one portable folder.
#
#  ---- MASTER SWITCH --------------------------------------------------------
#      customize              show current state
#      customize on           turn everything on
#      customize off          back to the stock Windows terminal
#      customize toggle       flip it
#      customize save         re-read the current Windows Terminal appearance
#                             and store it as the "on" state
#
#  ---- FASTFETCH AUTOSTART ONLY ---------------------------------------------
#      fastfetch auto [-y | -n | toggle]
#
#  Any other argument is forwarded straight to fastfetch.exe, so
#  "fastfetch --version" and "fastfetch -s cpu" keep working as usual.
#
#  No state is ever written into this script: the autostart is an empty marker
#  file, the appearance lives in Windows Terminal's settings.json. Flipping a
#  switch never rewrites this profile, so it cannot leave you without a shell.
# =============================================================================

# Derived from this file's own location (we sit in <setup>\powershell), so the
# folder can be moved or cloned anywhere without editing a single path.
$script:SetupHome = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot }
                    else { Join-Path $HOME 'Documents\Customization\terminal' }

$script:FastfetchFlag    = Join-Path $script:SetupHome 'fastfetch\autostart.on'
$script:AppearanceFile   = Join-Path $script:SetupHome 'windows-terminal\appearance.json'
$script:TerminalSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'

# ---------------------------------------------------------------- fastfetch --

function Get-FastfetchExe {
    # -CommandType Application is mandatory: without it Get-Command would find
    # the fastfetch function below and we would recurse forever.
    Get-Command fastfetch.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty Source
}

function Test-FastfetchInteractive {
    # Keeps the logo out of script and pipeline output: it only runs in a
    # genuinely interactive session.
    if (-not [Environment]::UserInteractive) { return $false }
    foreach ($a in [Environment]::GetCommandLineArgs()) {
        if ($a -match '^-(command|c|file|f|encodedcommand|ec)$') { return $false }
    }
    return $true
}

function Set-FastfetchAutostart([bool]$On) {
    if ($On) {
        $dir = Split-Path -Parent $script:FastfetchFlag
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        New-Item -ItemType File -Path $script:FastfetchFlag -Force | Out-Null
    } else {
        Remove-Item -LiteralPath $script:FastfetchFlag -Force -ErrorAction SilentlyContinue
    }
}

function fastfetch {
    if ($args.Count -ge 1 -and "$($args[0])" -eq 'auto') {
        $arg = if ($args.Count -ge 2) { "$($args[1])".ToLower() } else { '' }
        $on  = Test-Path -LiteralPath $script:FastfetchFlag
        $new = $on
        switch ($arg) {
            { $_ -in '-y', 'on',  'yes', '1' } { $new = $true }
            { $_ -in '-n', 'off', 'no',  '0' } { $new = $false }
            { $_ -in 'toggle', 't'           } { $new = -not $on }
            ''                                 { }
            default {
                Write-Host "usage: fastfetch auto [-y | -n | toggle]"
                return
            }
        }
        if ($new -ne $on) { Set-FastfetchAutostart $new }
        if ($new) { Write-Host "  autostart ON" -ForegroundColor Green }
        else      { Write-Host "  autostart off" -ForegroundColor DarkGray }
        if ($new -ne $on) { Write-Host "  (applies to the next window)" -ForegroundColor DarkGray }
        return
    }

    $exe = Get-FastfetchExe
    if (-not $exe) { Write-Warning 'fastfetch.exe not found in PATH'; return }
    & $exe @args
}

# ---------------------------------------------- Windows Terminal appearance --

function Get-WTSettings {
    if (-not (Test-Path -LiteralPath $script:TerminalSettings)) { return $null }
    Get-Content -LiteralPath $script:TerminalSettings -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-WTSettings($Json) {
    # Backup before every write, so next to the untouched original there is
    # always the last known-good version too.
    $bak = Join-Path $script:SetupHome 'windows-terminal\settings.json.backup'
    Copy-Item -LiteralPath $script:TerminalSettings -Destination $bak -Force -ErrorAction SilentlyContinue
    # A high -Depth is mandatory: PowerShell 5.1 truncates ConvertTo-Json at 2.
    $Json | ConvertTo-Json -Depth 32 |
        Set-Content -LiteralPath $script:TerminalSettings -Encoding UTF8
}

function Get-WTTargetProfile($Json, $Guid) {
    if (-not $Json) { return $null }
    $Json.profiles.list | Where-Object { $_.guid -eq $Guid } | Select-Object -First 1
}

function Get-AppearanceSpec {
    if (-not (Test-Path -LiteralPath $script:AppearanceFile)) { return $null }
    Get-Content -LiteralPath $script:AppearanceFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-AppearanceApplied {
    $spec = Get-AppearanceSpec
    if (-not $spec) { return $false }
    $p = Get-WTTargetProfile (Get-WTSettings) $spec.profileGuid
    if (-not $p) { return $false }
    foreach ($n in $spec.settings.PSObject.Properties.Name) {
        if ($p.PSObject.Properties.Name -contains $n) { return $true }
    }
    return $false
}

function Get-WTSchemeNames($Json) {
    if (-not $Json.PSObject.Properties.Name -contains 'schemes') { return @() }
    @($Json.schemes | ForEach-Object { $_.name })
}

function Add-MissingSchemes($Json) {
    # "colorScheme" is only a name; the palette behind it has to be defined in
    # settings.json under "schemes". Pointing a profile at a name that is not
    # defined there makes Windows Terminal show an error dialog and fall back to
    # default colours - which is what happens on any machine that never imported
    # the theme by hand. So the definition ships with the repo and gets
    # installed before anything references it.
    $file = Join-Path $script:SetupHome 'windows-terminal\schemes.json'
    if (-not (Test-Path -LiteralPath $file)) { return }
    $ours = @(Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)
    if (-not ($Json.PSObject.Properties.Name -contains 'schemes')) {
        $Json | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force
    }
    $added = @()
    foreach ($s in $ours) {
        if ((Get-WTSchemeNames $Json) -notcontains $s.name) {
            $Json.schemes = @($Json.schemes) + $s
            $added += $s.name
        }
    }
    if ($added.Count) {
        Write-Host "  colour scheme installed: $($added -join ', ')" -ForegroundColor DarkGray
    }
}

function Set-TerminalAppearance([bool]$On) {
    $spec = Get-AppearanceSpec
    if (-not $spec) { Write-Warning "windows-terminal\appearance.json is missing"; return $false }
    $j = Get-WTSettings
    $p = Get-WTTargetProfile $j $spec.profileGuid
    if (-not $p) {
        Write-Warning "profile $($spec.profileGuid) not found in Windows Terminal"
        return $false
    }

    if ($On) { Add-MissingSchemes $j }

    foreach ($prop in $spec.settings.PSObject.Properties) {
        if (-not $On) {
            $p.PSObject.Properties.Remove($prop.Name)
            continue
        }

        $v = $prop.Value
        if ($v -is [string]) {
            # The placeholder is what makes the folder movable and portable.
            $v = $v.Replace('{ROOT}', $script:SetupHome)
            $v = $v.Replace('/', [char]92)
        }

        # Never write a scheme name that has no definition: an unusable value
        # here is what triggers the error dialog at every startup.
        if ($prop.Name -eq 'colorScheme' -and (Get-WTSchemeNames $j) -notcontains $v) {
            Write-Warning "colour scheme '$v' is not defined; keeping the current one"
            continue
        }

        $p | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $v -Force
    }
    Save-WTSettings $j
    return $true
}

function Save-CurrentAppearance {
    $spec = Get-AppearanceSpec
    $j = Get-WTSettings
    if (-not $j) { Write-Warning "Windows Terminal not found"; return }
    $guid = if ($spec) { $spec.profileGuid } else { $j.defaultProfile }
    $p = Get-WTTargetProfile $j $guid
    if (-not $p) { Write-Warning "profile not found"; return }

    $keys = @('colorScheme', 'backgroundImage', 'backgroundImageOpacity',
              'backgroundImageStretchMode', 'backgroundImageAlignment',
              'font', 'opacity', 'useAcrylic', 'cursorShape')
    $snap = [ordered]@{}
    foreach ($k in $keys) {
        if ($p.PSObject.Properties.Name -contains $k) {
            $v = $p.$k
            if ($v -is [string]) {
                $v = $v.Replace($script:SetupHome, '{ROOT}')
                $v = $v.Replace([char]92, '/')
            }
            $snap[$k] = $v
        }
    }
    if ($snap.Keys.Count -eq 0) {
        Write-Warning "the profile has none of the managed settings: nothing to save"
        return
    }
    $out = [ordered]@{ profileGuid = $guid; settings = $snap }
    $dir = Split-Path -Parent $script:AppearanceFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $out | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $script:AppearanceFile -Encoding UTF8
    Write-Host "  appearance saved ($($snap.Keys.Count) settings)" -ForegroundColor Green
    foreach ($k in $snap.Keys) { Write-Host "    $k" -ForegroundColor DarkGray }
}

# ----------------------------------------------------------- master switch --

function Show-CustomizationStatus {
    $auto = Test-Path -LiteralPath $script:FastfetchFlag
    $look = Test-AppearanceApplied
    Write-Host ""
    Write-Host "  terminal appearance  " -NoNewline
    if ($look) { Write-Host "customized" -ForegroundColor Green }
    else       { Write-Host "Windows default" -ForegroundColor DarkGray }
    Write-Host "  fastfetch on startup " -NoNewline
    if ($auto) { Write-Host "on" -ForegroundColor Green }
    else       { Write-Host "off" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  customize on | off | toggle | save" -ForegroundColor DarkGray
    Write-Host ""
}

function customize {
    $arg = if ($args.Count -ge 1) { "$($args[0])".ToLower() } else { 'status' }
    $target = $null
    switch ($arg) {
        { $_ -in 'status', '' }           { Show-CustomizationStatus; return }
        'save'                            { Save-CurrentAppearance;   return }
        { $_ -in 'on', '-y', 'yes', '1' } { $target = $true }
        { $_ -in 'off', '-n', 'no', '0' } { $target = $false }
        { $_ -in 'toggle', 't' } {
            $target = -not ((Test-Path -LiteralPath $script:FastfetchFlag) -or (Test-AppearanceApplied))
        }
        default {
            Write-Host "usage: customize [status | on | off | toggle | save]"
            return
        }
    }

    Set-FastfetchAutostart $target
    $ok = Set-TerminalAppearance $target

    Write-Host ""
    if ($target) { Write-Host "  customizations ON" -ForegroundColor Green }
    else         { Write-Host "  stock Windows terminal" -ForegroundColor DarkGray }
    if ($ok) {
        Write-Host "  appearance  applied now, Windows Terminal reloads on its own" -ForegroundColor DarkGray
    }
    Write-Host "  fastfetch   applies to the next window" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------------------------------------------------------------- startup ----

if ((Test-Path -LiteralPath $script:FastfetchFlag) -and (Test-FastfetchInteractive)) {
    fastfetch
}
