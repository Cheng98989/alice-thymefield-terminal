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
#  ---- FASTFETCH ------------------------------------------------------------
#      fastfetch auto [-y | -n | toggle]   run it at startup, or stop doing that
#      fastfetch icon                      show which picture is in use
#      fastfetch icon <file.png>           convert an image and install it
#      fastfetch icon <file.txt>           install a ready-made logo
#
#  Setting an icon also writes the new width and height into config.jsonc: the
#  step that is easy to forget, and that leaves the text column in the wrong
#  place when it is skipped.
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

$script:FastfetchDir     = Join-Path $script:SetupHome 'fastfetch'
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

function Write-Utf8NoBom($Path, $Text) {
    # Set-Content -Encoding UTF8 writes a BOM in PowerShell 5.1, and fastfetch
    # rejects that outright: "UTF-8 byte order mark (BOM) is not supported".
    # So every file written here goes out as plain UTF-8, byte for byte.
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Get-PythonExe {
    # Entries under WindowsApps are the Microsoft Store alias: a stub that only
    # tells you to go install Python, not an interpreter.
    Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
        Select-Object -First 1 -ExpandProperty Source
}

function Get-LogoMetrics($TxtPath) {
    # Width is the printable width: the colour escapes in the file take no
    # columns on screen, so they must not be counted.
    $strip = [regex]"$([char]27)\[[0-9;]*m"
    $lines = @(Get-Content -LiteralPath $TxtPath -Encoding UTF8)
    $w = 0
    foreach ($l in $lines) {
        $len = $strip.Replace($l, '').TrimEnd().Length
        if ($len -gt $w) { $w = $len }
    }
    [pscustomobject]@{ Width = $w; Height = $lines.Count }
}

function Set-LogoMetrics([int]$Width, [int]$Height) {
    # config.jsonc carries comments, so it must never go through a JSON parser -
    # that would silently strip them. And "width" appears again under display,
    # so the edit is confined to the text of the logo block.
    $file = Join-Path $script:FastfetchDir 'config.jsonc'
    if (-not (Test-Path -LiteralPath $file)) { Write-Warning "config.jsonc not found"; return $false }
    $text  = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $start = $text.IndexOf('"logo"')
    if ($start -lt 0) { Write-Warning "no logo block in config.jsonc"; return $false }
    $end = $text.IndexOf('"display"')
    if ($end -lt $start) { $end = $text.Length }

    $block = $text.Substring($start, $end - $start)
    $block = [regex]::Replace($block, '"width"\s*:\s*\d+',  '"width": '  + $Width)
    $block = [regex]::Replace($block, '"height"\s*:\s*\d+', '"height": ' + $Height)
    Write-Utf8NoBom $file ($text.Substring(0, $start) + $block + $text.Substring($end))
    return $true
}

function Show-FastfetchIcon {
    $txt = Join-Path $script:FastfetchDir 'alice-logo.txt'
    $png = Join-Path $script:FastfetchDir 'alice-logo.png'
    Write-Host ""
    if (Test-Path -LiteralPath $txt) {
        $m = Get-LogoMetrics $txt
        Write-Host "  icon    " -NoNewline; Write-Host $txt -ForegroundColor Green
        Write-Host "  size    $($m.Width) x $($m.Height) characters  ($($m.Width) x $($m.Height * 2) pixels)"
    } else {
        Write-Host "  icon    " -NoNewline; Write-Host "missing: $txt" -ForegroundColor Red
    }
    if (Test-Path -LiteralPath $png) {
        Write-Host "  source  $png"
    }
    Write-Host ""
    Write-Host "  fastfetch icon <file.png>   draw a new one from an image" -ForegroundColor DarkGray
    Write-Host "  fastfetch icon <file.txt>   install a ready-made logo" -ForegroundColor DarkGray
    Write-Host ""
}

function Backup-CurrentIcon($Incoming) {
    # Setting an icon overwrites the editable PNG, and trying icons out is
    # exactly what this command invites - so the one being replaced is kept in a
    # single slot. Not versioned: it is a per-machine undo, not repository
    # content.
    $png  = Join-Path $script:FastfetchDir 'alice-logo.png'
    $prev = Join-Path $script:FastfetchDir 'alice-logo.previous.png'
    if (-not (Test-Path -LiteralPath $png)) { return }
    # Restoring FROM the backup slot is the obvious way to undo, and backing up
    # first would overwrite the very file about to be installed.
    if ($Incoming -and (Resolve-Path -LiteralPath $Incoming).Path -eq $prev) { return }
    Copy-Item -LiteralPath $png -Destination $prev -Force
}

function Set-FastfetchIcon($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  no such file: $Path" -ForegroundColor Red
        return
    }
    $src = (Resolve-Path -LiteralPath $Path).Path
    $ext = [IO.Path]::GetExtension($src).ToLower()
    $txt = Join-Path $script:FastfetchDir 'alice-logo.txt'
    $png = Join-Path $script:FastfetchDir 'alice-logo.png'

    if ($ext -eq '.png') {
        $py = Get-PythonExe
        if (-not $py) {
            Write-Host "  a .png has to be converted, and that needs Python." -ForegroundColor Red
            Write-Host "  Install it from python.org, then:  python -m pip install pillow numpy" -ForegroundColor DarkGray
            Write-Host "  Or pass an already converted .txt instead." -ForegroundColor DarkGray
            return
        }
        # Write to a temporary file first: a conversion that fails must not be
        # able to leave a half-written logo behind, nor touch config.jsonc.
        $tmp = [IO.Path]::GetTempFileName()
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = & $py (Join-Path $script:FastfetchDir 'logo-from-png.py') $src $tmp 2>&1 | Out-String
        $failed = $LASTEXITCODE -ne 0
        $ErrorActionPreference = $previous
        if ($failed -or -not (Test-Path -LiteralPath $tmp) -or (Get-Item $tmp).Length -eq 0) {
            Write-Host "  conversion failed:" -ForegroundColor Red
            Write-Host ($out.Trim()) -ForegroundColor DarkGray
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            return
        }
        Move-Item -LiteralPath $tmp -Destination $txt -Force
        # Keep the editable PNG next to the logo it produced, so the two never
        # drift apart and a later redraw starts from what is actually on screen.
        if ((Resolve-Path -LiteralPath $src).Path -ne $png) {
            Backup-CurrentIcon $src
            Copy-Item -LiteralPath $src -Destination $png -Force
        }
    }
    elseif ($ext -eq '.txt') {
        $m = Get-LogoMetrics $src
        if ($m.Width -eq 0) {
            Write-Host "  that .txt has no printable content" -ForegroundColor Red
            return
        }
        Backup-CurrentIcon $src
        Copy-Item -LiteralPath $src -Destination $txt -Force
        # Refresh the editable PNG from the logo, so "the .png is the source of
        # the .txt" keeps being true after installing a ready-made one.
        $py = Get-PythonExe
        if ($py) {
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $py (Join-Path $script:FastfetchDir 'logo-to-png.py') $txt $png 2>&1 | Out-Null
            $ErrorActionPreference = $previous
        }
    }
    else {
        Write-Host "  unsupported file type '$ext'. Give it a .png to convert," -ForegroundColor Red
        Write-Host "  or a .txt that is already a logo." -ForegroundColor DarkGray
        return
    }

    $m = Get-LogoMetrics $txt
    if (Set-LogoMetrics $m.Width $m.Height) {
        Write-Host ""
        Write-Host "  icon set" -ForegroundColor Green
        Write-Host "  from    $src"
        Write-Host "  size    $($m.Width) x $($m.Height) characters, written into config.jsonc"
        Write-Host "  visible in the next window" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function fastfetch {
    if ($args.Count -ge 1 -and "$($args[0])" -eq 'icon') {
        if ($args.Count -ge 2) { Set-FastfetchIcon "$($args[1])" } else { Show-FastfetchIcon }
        return
    }
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
    Write-Utf8NoBom $script:TerminalSettings ($Json | ConvertTo-Json -Depth 32)
}

function Get-WTTargetProfile($Json, $Guid) {
    if (-not $Json) { return $null }
    $Json.profiles.list | Where-Object { $_.guid -eq $Guid } | Select-Object -First 1
}

function Get-AppearanceSpec {
    if (-not (Test-Path -LiteralPath $script:AppearanceFile)) { return $null }
    Get-Content -LiteralPath $script:AppearanceFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-WTProfileGuid($Json, $Spec) {
    # "default" means: whichever profile this machine actually opens. Pinning a
    # GUID would theme a profile the user may never look at - the built-in
    # Windows PowerShell one is identical on every machine, so it is portable in
    # the literal sense, but plenty of people run PowerShell 7, WSL or the
    # command prompt as their default and would see fastfetch appear with no
    # theming and no clue why. Put a real GUID in appearance.json to pin it.
    if ($Spec -and $Spec.profileGuid -and $Spec.profileGuid -ne 'default') {
        return $Spec.profileGuid
    }
    $Json.defaultProfile
}

function Test-AppearanceApplied {
    $spec = Get-AppearanceSpec
    if (-not $spec) { return $false }
    $j = Get-WTSettings
    $p = Get-WTTargetProfile $j (Resolve-WTProfileGuid $j $spec)
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
    $guid = Resolve-WTProfileGuid $j $spec
    $p = Get-WTTargetProfile $j $guid
    if (-not $p) {
        Write-Warning "profile $guid not found in Windows Terminal"
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
    $guid = Resolve-WTProfileGuid $j $spec
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
    # Write "default" back unless a specific profile was pinned on purpose:
    # baking this machine's GUID in would make the file machine-specific again.
    $stored = if ($spec -and $spec.profileGuid -and $spec.profileGuid -ne 'default') { $guid } else { 'default' }
    $out = [ordered]@{ profileGuid = $stored; settings = $snap }
    $dir = Split-Path -Parent $script:AppearanceFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-Utf8NoBom $script:AppearanceFile ($out | ConvertTo-Json -Depth 16)
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
