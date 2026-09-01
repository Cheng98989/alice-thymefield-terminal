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
#  ---- PHAETHON ---------------------------------------------------------------
#      phaethon auto [-y | -n | toggle]   run it at startup, or stop doing that
#      phaethon theme                     show which character/picture is in use
#      phaethon theme <file.png>          convert an image and install it
#      phaethon theme <file.txt>          install a ready-made logo
#      phaethon modules                   show which info fields are on or off
#
#  "fastfetch" still works too - it is the same function under its old name,
#  kept so nothing that already types "fastfetch theme ..." breaks.
#
#  Setting an icon also writes the new width and height into config.jsonc: the
#  step that is easy to forget, and that leaves the text column in the wrong
#  place when it is skipped.
#
#  The individual info fields (CPU, GPU, uptime...) are toggled by hand in
#  fastfetch\modules.jsonc rather than through a command - it is a flat,
#  commented on/off list, so editing it directly is the whole interface.
#
#  Any argument phaethon does not recognise is forwarded straight to
#  fastfetch.exe, so "phaethon --version" and "phaethon -s cpu" keep working.
#
#  No state is ever written into this script: the autostart is an empty marker
#  file, the appearance lives in Windows Terminal's settings.json. Flipping a
#  switch never rewrites this profile, so it cannot leave you without a shell.
# =============================================================================

# Derived from this file's own location (we sit in <setup>\powershell), so the
# folder can be moved or cloned anywhere without editing a single path.
$script:SetupHome = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot }
                    else { Join-Path $HOME 'Documents\Customization\Phaethon-Terminal' }

$script:FastfetchDir     = Join-Path $script:SetupHome 'fastfetch'
$script:CharactersDir    = Join-Path $script:SetupHome 'fastfetch\characters'
# Both dimensions, in pixels. A logo is as wide in columns as the picture is in
# pixels and half as tall in rows, so much past this the information column gets
# pushed off the right edge and the prompt scrolls away. "-force" overrides it.
$script:IconMaxPixels    = 64
$script:FastfetchFlag    = Join-Path $script:SetupHome 'fastfetch\autostart.on'
$script:ModulesFile      = Join-Path $script:SetupHome 'fastfetch\modules.jsonc'
$script:AppearanceFile   = Join-Path $script:SetupHome 'windows-terminal\appearance.json'
$script:TerminalSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'

# fastfetch's own module type names, exactly as modules.jsonc and config.jsonc
# use them. The picture, title and colour dots aren't here on purpose - they
# are the character's look (fastfetch theme icon/background), not information
# to trim.
$script:KnownModules = @('host', 'cpu', 'gpu', 'memory', 'swap', 'disk', 'display',
                          'os', 'wm', 'shell', 'terminal', 'locale', 'users',
                          'sound', 'uptime', 'datetime')

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

function Set-LogoBlock([string]$Source, [int]$Width, [int]$Height) {
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
    # "none" is fastfetch's own way of drawing no logo at all, which is what a
    # theme that carries only a background needs.
    $type = if ($Source) { 'file-raw' } else { 'none' }
    $block = [regex]::Replace($block, '"type"\s*:\s*"[^"]*"', '"type": "' + $type + '"', 1)
    if ($Source) {
        $block = [regex]::Replace($block, '"source"\s*:\s*"[^"]*"', '"source": "' + $Source + '"')
        # Left alone when the logo is off: fastfetch validates these even for
        # type "none" and rejects a zero, so the old values simply stay.
        $block = [regex]::Replace($block, '"width"\s*:\s*\d+',  '"width": '  + $Width)
        $block = [regex]::Replace($block, '"height"\s*:\s*\d+', '"height": ' + $Height)
    }
    Write-Utf8NoBom $file ($text.Substring(0, $start) + $block + $text.Substring($end))
    return $true
}

function Get-LogoSource {
    # The source string is left in place even when the logo is switched off
    # (Set-LogoBlock's comment explains why), so it must not be trusted alone -
    # a caller also needs Get-LogoType to know whether it is actually drawn.
    $file = Join-Path $script:FastfetchDir 'config.jsonc'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $m = [regex]::Match($text, '"source"\s*:\s*"([^"]*)"')
    if ($m.Success) { $m.Groups[1].Value } else { $null }
}

function Get-LogoType {
    $file = Join-Path $script:FastfetchDir 'config.jsonc'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $start = $text.IndexOf('"logo"')
    if ($start -lt 0) { return $null }
    $end = $text.IndexOf('"display"')
    if ($end -lt $start) { $end = $text.Length }
    $m = [regex]::Match($text.Substring($start, $end - $start), '"type"\s*:\s*"([^"]*)"')
    if ($m.Success) { $m.Groups[1].Value } else { $null }
}

function Get-Characters {
    if (-not (Test-Path -LiteralPath $script:CharactersDir)) { return @() }
    Get-ChildItem -LiteralPath $script:CharactersDir -Directory | ForEach-Object {
        # A character is just a folder. The picture and the logo inside can be
        # named anything, so a redraw does not have to be renamed to fit.
        $txt = Get-ChildItem -LiteralPath $_.FullName -Filter *.txt -File |
                   Where-Object { $_.Name -ne 'name.txt' } | Select-Object -First 1
        $png = Get-ChildItem -LiteralPath $_.FullName -Filter *.png -File | Select-Object -First 1
        [pscustomobject]@{
            Name = $_.Name
            Dir  = $_.FullName
            Txt  = if ($txt) { $txt.FullName } else { $null }
            Png  = if ($png) { $png.FullName } else { $null }
        }
    }
}

function Get-ImageSize($Path) {
    # Read the header only, so an oversized picture is refused before Python is
    # even started - and never keep the file locked afterwards.
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $img = [System.Drawing.Image]::FromFile($Path)
        try { [pscustomobject]@{ Width = $img.Width; Height = $img.Height } }
        finally { $img.Dispose() }
    } catch { $null }
}

function Test-IconSize([int]$Width, [int]$Height, [bool]$Force, [string]$What) {
    $max = $script:IconMaxPixels
    if ($Force -or ($Width -le $max -and $Height -le $max)) { return $true }
    Write-Host ""
    Write-Host "  $What is $Width x $Height pixels, past the $max x $max limit." -ForegroundColor Red
    Write-Host "  The logo takes one column per pixel across and one row per two" -ForegroundColor DarkGray
    Write-Host "  down, so bigger than this pushes the information column off the" -ForegroundColor DarkGray
    Write-Host "  screen and scrolls the prompt away." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Resize it, or repeat the command with -force." -ForegroundColor DarkGray
    Write-Host ""
    return $false
}

function Get-CharacterDisplayName([string]$Name) {
    if (-not $Name) { return $null }
    # A name.txt inside the folder wins, for when the folder ended up called
    # something like "char-v2-final" because that is what the file was called.
    $override = Join-Path (Join-Path $script:CharactersDir $Name) 'name.txt'
    if (Test-Path -LiteralPath $override) {
        $first = @(Get-Content -LiteralPath $override -Encoding UTF8)[0]
        if ($first -and $first.Trim()) { return $first.Trim() }
    }
    # Otherwise the folder name, tidied: "yeshunguang" -> "Yeshunguang".
    $words = $Name -split '[-_\s]+' | Where-Object { $_ }
    ($words | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ' '
}

function Set-TitleCharacter([string]$NewName) {
    # The title names the character, and fastfetch format strings have no
    # placeholder for it, so the text has to be rewritten on every switch.
    # What it currently says is recorded in a "// character:" comment next to
    # the module rather than derived from the folder name: a display name can
    # change - renaming the folder, adding a name.txt - and the title would then
    # hold a string nothing matches, leaving it stuck with no way to correct it.
    if (-not $NewName) { return }
    $file = Join-Path $script:FastfetchDir 'config.jsonc'
    if (-not (Test-Path -LiteralPath $file)) { return }
    $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8

    $m = [regex]::Match($text, '//[ ]*character:[ ]*(.+)')
    if (-not $m.Success) { return }          # marker removed on purpose: leave the title alone
    $current = $m.Groups[1].Value.Trim()
    if (-not $current -or $current -eq $NewName) { return }

    # Only proceed if the title really contains what the marker claims.
    # Advancing the marker after a substitution that matched nothing lets the
    # two drift apart, and the next switch then replaces a partial name: with
    # the marker reading "Yeshunguang" while the title said "Yeshunguang Chibi",
    # selecting Alice produced "Alice Chibi".
    $titleRx = '(?s)("type"\s*:\s*"title".*?"format"\s*:\s*")([^"]*)(")'
    $tm = [regex]::Match($text, $titleRx)
    if (-not $tm.Success -or -not $tm.Groups[2].Value.Contains($current)) { return }

    $text = [regex]::Replace($text, $titleRx, {
        param($x)
        $x.Groups[1].Value + $x.Groups[2].Value.Replace($current, $NewName) + $x.Groups[3].Value
    }, 1)
    $text = [regex]::Replace($text, '(//[ ]*character:)[ ]*(.+)', {
        param($x) $x.Groups[1].Value + ' ' + $NewName
    }, 1)
    Write-Utf8NoBom $file $text
}

function Get-ModuleToggles {
    # A missing or unreadable file means nothing is hidden - the shipped
    # layout is exactly what a fresh install already draws, so there is
    # nothing to migrate for anyone who never touches modules.jsonc.
    if (-not (Test-Path -LiteralPath $script:ModulesFile)) { return @{} }
    $raw = Get-Content -LiteralPath $script:ModulesFile -Raw -Encoding UTF8
    # The file is JSONC for the person editing it by hand, not something
    # ConvertFrom-Json understands - strip // comments first.
    $stripped = [regex]::Replace($raw, '(?m)//.*$', '')
    try { $j = $stripped | ConvertFrom-Json } catch { return @{} }
    $out = @{}
    foreach ($p in $j.PSObject.Properties) {
        if ($script:KnownModules -contains $p.Name) { $out[$p.Name] = [bool]$p.Value }
    }
    $out
}

function Get-DisabledModules {
    $toggles = Get-ModuleToggles
    @($toggles.Keys | Where-Object { -not $toggles[$_] })
}

function Show-ModuleToggles {
    $toggles = Get-ModuleToggles
    Write-Host ""
    Write-Host "  modules" -ForegroundColor DarkGray
    foreach ($m in $script:KnownModules) {
        $on = if ($toggles.ContainsKey($m)) { $toggles[$m] } else { $true }
        Write-Host "    $(if ($on) { 'on ' } else { 'off' })  $m" -ForegroundColor $(if ($on) { 'Green' } else { 'DarkGray' })
    }
    Write-Host ""
    Write-Host "  edit fastfetch\modules.jsonc to change these" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-FastfetchIcon {
    $current = if ((Get-LogoType) -eq 'none') { $null } else { Get-LogoSource }
    $chars   = @(Get-Characters)
    $curName = Get-CurrentCharacterName
    Write-Host ""
    if ($current) {
        $leaf = Split-Path -Leaf $current
        $active = $chars | Where-Object { $_.Txt -and (Split-Path -Leaf $_.Txt) -eq $leaf } | Select-Object -First 1
        Write-Host "  character  " -NoNewline
        Write-Host $(if ($active) { $active.Name } else { $leaf }) -ForegroundColor Green
        $file = Join-Path $script:FastfetchDir (($current -split 'fastfetch/', 2)[-1])
        if (Test-Path -LiteralPath $file) {
            $m = Get-LogoMetrics $file
            Write-Host "  size       $($m.Width) x $($m.Height) characters  ($($m.Width) x $($m.Height * 2) pixels)"
        } else {
            Write-Host "  file       missing: $current" -ForegroundColor Red
        }
    } elseif (Test-ThemeHidden $curName 'icon') {
        Write-Host "  character  " -NoNewline
        Write-Host "$curName" -NoNewline -ForegroundColor Green
        Write-Host "  (icon hidden - " -NoNewline -ForegroundColor DarkGray
        Write-Host "phaethon theme icon on" -NoNewline -ForegroundColor DarkGray
        Write-Host " to show it)" -ForegroundColor DarkGray
    } else {
        Write-Host "  no logo configured" -ForegroundColor Red
    }

    $bgFile = Get-ThemeBackgroundFile $curName
    Write-Host "  background " -NoNewline
    if ($bgFile -and (Test-ThemeHidden $curName 'background')) {
        Write-Host "$(Split-Path -Leaf $bgFile) (hidden)" -ForegroundColor DarkGray
    } elseif ($bgFile) {
        Write-Host (Split-Path -Leaf $bgFile) -ForegroundColor Green
    } else {
        Write-Host "none" -ForegroundColor DarkGray
    }

    if ($chars.Count) {
        Write-Host ""
        Write-Host "  available"
        foreach ($c in $chars) {
            $bits = @()
            if (-not $c.Txt -and $c.Png) { $bits += 'converts on first use' }
            if (-not $c.Txt -and -not $c.Png) { $bits += 'no icon' }
            if (Test-ThemeHidden $c.Name 'icon') { $bits += 'icon hidden' }
            $bg = Get-ThemeBackgroundFile $c.Name
            if ($bg -and (Test-ThemeHidden $c.Name 'background')) { $bits += 'background hidden' }
            elseif ($bg) { $bits += 'background' }
            $note = if ($bits.Count) { "  (" + ($bits -join ', ') + ")" } else { "" }
            Write-Host "    $($c.Name)$note" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  phaethon theme <name>               switch theme" -ForegroundColor DarkGray
    Write-Host "  phaethon theme <file.png>           import a new one" -ForegroundColor DarkGray
    Write-Host "  phaethon theme icon <file|on|off>   set or hide this theme's picture" -ForegroundColor DarkGray
    Write-Host "  phaethon theme background <file|on|off>  and its wallpaper" -ForegroundColor DarkGray
    Write-Host "  phaethon theme remove <name>        delete one" -ForegroundColor DarkGray
    Write-Host ""
}

function Convert-CharacterPng($Png, [bool]$Force) {
    $size = Get-ImageSize $Png
    if ($size -and -not (Test-IconSize $size.Width $size.Height $Force (Split-Path -Leaf $Png))) { return $null }
    # Writes the logo next to the picture it came from, so each character folder
    # holds its own pair and nothing overwrites anything else.
    $py = Get-PythonExe
    if (-not $py) {
        Write-Host "  converting a .png needs Python." -ForegroundColor Red
        Write-Host "  Install it from python.org, then:  python -m pip install pillow" -ForegroundColor DarkGray
        return $null
    }
    $txt = [IO.Path]::ChangeExtension($Png, '.txt')
    $tmp = [IO.Path]::GetTempFileName()
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $py (Join-Path $script:FastfetchDir 'logo-from-png.py') $Png $tmp 2>&1 | Out-String
    $failed = $LASTEXITCODE -ne 0
    $ErrorActionPreference = $previous
    if ($failed -or -not (Test-Path -LiteralPath $tmp) -or (Get-Item $tmp).Length -eq 0) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        # A missing library is the common failure on a fresh Python, and a raw
        # traceback is a poor way to say "run one pip command".
        if ($out -match "No module named '?(\w+)") {
            $module = $matches[1]
            $package = if ($module -eq 'PIL') { 'pillow' } else { $module }
            Write-Host ""
            Write-Host "  Python is missing the $package library." -ForegroundColor Red
            Write-Host "  Install it with:" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "      python -m pip install $package" -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host "  conversion failed:" -ForegroundColor Red
            Write-Host ($out.Trim()) -ForegroundColor DarkGray
        }
        return $null
    }
    Move-Item -LiteralPath $tmp -Destination $txt -Force
    return $txt
}

function Use-Character($TxtPath, $Label, [bool]$Force, [bool]$CheckSize) {
    # Switching to a character whose icon is hidden must not silently reveal
    # it again - draw the empty logo instead, same as if it had no picture.
    if (Test-ThemeHidden $Label 'icon') { Use-EmptyIcon $Label; return }
    $newName = Get-CharacterDisplayName $Label

    $m = Get-LogoMetrics $TxtPath
    # Only on the way in: a character already installed stays selectable, or
    # forcing one past the limit would strand it.
    if ($CheckSize -and -not (Test-IconSize $m.Width ($m.Height * 2) $Force (Split-Path -Leaf $TxtPath))) { return }
    if ($m.Width -eq 0) {
        Write-Host "  that logo has no printable content" -ForegroundColor Red
        return
    }
    # Relative to the fastfetch folder, behind the junction: stays correct
    # wherever the repository was cloned.
    $rel = $TxtPath.Substring($script:FastfetchDir.Length).TrimStart('\', '/').Replace('\', '/')
    if (Set-LogoBlock "%USERPROFILE%/.config/fastfetch/$rel" $m.Width $m.Height) {
        Set-TitleCharacter $newName
        # The background belongs to the theme, so switching has to reapply the
        # appearance - but only when it is on, or this would turn it back on.
        if (Test-AppearanceApplied) { Set-TerminalAppearance $true | Out-Null }
        Write-Host ""
        Write-Host "  character  " -NoNewline; Write-Host $newName -ForegroundColor Green
        Write-Host "  logo       $TxtPath"
        Write-Host "  size       $($m.Width) x $($m.Height) characters, written into config.jsonc"
        Write-Host "  visible in the next window" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Reset-FastfetchConfig([bool]$Force) {
    # config.default.jsonc is the shipped copy, kept beside the live one rather
    # than pulled from git: most people arrive here through a downloaded zip and
    # have no repository to restore from.
    $file    = Join-Path $script:FastfetchDir 'config.jsonc'
    $default = Join-Path $script:FastfetchDir 'config.default.jsonc'
    if (-not (Test-Path -LiteralPath $default)) {
        Write-Host "  config.default.jsonc is missing, nothing to restore from" -ForegroundColor Red
        return
    }
    if (-not $Force) {
        Write-Host ""
        Write-Host "  this replaces config.jsonc with the shipped default" -ForegroundColor Yellow
        Write-Host "  colours, module list, selected character - all back to how" -ForegroundColor DarkGray
        Write-Host "  they started. The autostart and the Windows Terminal theme" -ForegroundColor DarkGray
        Write-Host "  are not touched." -ForegroundColor DarkGray
        if ((Read-Host "  type y to confirm") -notmatch '^[yY]') {
            Write-Host "  left alone" -ForegroundColor DarkGray
            return
        }
    }
    # Keep what is being replaced: a reset is easy to regret.
    if (Test-Path -LiteralPath $file) {
        Copy-Item -LiteralPath $file -Destination "$file.backup" -Force
    }
    Copy-Item -LiteralPath $default -Destination $file -Force
    Write-Host "  config.jsonc restored" -ForegroundColor Green
    Write-Host "  the version it replaced is kept as config.jsonc.backup" -ForegroundColor DarkGray

    # The default names a character that this machine may not have any more.
    $name = Get-CurrentCharacterName
    $have = @(Get-Characters)
    if ($name -and -not ($have | Where-Object { $_.Name -eq $name })) {
        $next = $have | Where-Object { $_.Txt } | Select-Object -First 1
        if ($next) {
            Write-Host "  the default character '$name' is not here, using $($next.Name)" -ForegroundColor DarkGray
            Use-Character $next.Txt $next.Name $false $false
        } else {
            Write-Host "  no characters installed: add one with  phaethon icon <file.png>" -ForegroundColor Yellow
        }
    }
}

function Get-CurrentCharacterName {
    $src = Get-LogoSource
    if ($src -and $src -match 'characters/([^/]+)/') { $matches[1] } else { $null }
}

function Remove-CharacterFolder($Name, [bool]$Force) {
    $c = @(Get-Characters) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $c) {
        Write-Host "  no character called '$Name'" -ForegroundColor Red
        $names = @(Get-Characters | ForEach-Object { $_.Name })
        if ($names.Count) { Write-Host "  available: $($names -join ', ')" -ForegroundColor DarkGray }
        return
    }
    $isCurrent = (Get-CurrentCharacterName) -eq $Name

    if (-not $Force) {
        $files = @(Get-ChildItem -LiteralPath $c.Dir -Recurse -File).Count
        Write-Host ""
        Write-Host "  about to delete  $($c.Dir)" -ForegroundColor Yellow
        Write-Host "  containing       $files file(s), including the picture" -ForegroundColor DarkGray
        if ($isCurrent) { Write-Host "  this is the one currently showing" -ForegroundColor DarkGray }
        if ((Read-Host "  type y to confirm") -notmatch '^[yY]') {
            Write-Host "  left alone" -ForegroundColor DarkGray
            return
        }
    }

    Remove-Item -LiteralPath $c.Dir -Recurse -Force
    Write-Host "  removed characters\$Name" -ForegroundColor Green

    if (-not $isCurrent) { return }
    # Deleting the one in use would leave the config pointing at nothing and the
    # terminal opening on an error, so move to whatever else is there.
    $next = @(Get-Characters) | Where-Object { $_.Txt } | Select-Object -First 1
    if ($next) {
        Write-Host "  it was the active one, switching to $($next.Name)" -ForegroundColor DarkGray
        Use-Character $next.Txt $next.Name $false $false
    } else {
        Write-Host ""
        Write-Host "  that was the last character: the splash has no logo now." -ForegroundColor Yellow
        Write-Host "  Add one with:  phaethon icon <file.png>" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Use-EmptyIcon($Name) {
    # A theme can carry only a background. fastfetch draws nothing, the
    # information column starts at the left margin.
    if (Set-LogoBlock $null 0 0) {
        Set-TitleCharacter (Get-CharacterDisplayName $Name)
        if (Test-AppearanceApplied) { Set-TerminalAppearance $true | Out-Null }
        Write-Host ""
        Write-Host "  theme      " -NoNewline
        Write-Host (Get-CharacterDisplayName $Name) -ForegroundColor Green
        Write-Host "  icon       none - the splash draws no picture"
        Write-Host "  visible in the next window" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Set-ThemeBackground($Arg) {
    $name = Get-CurrentCharacterName
    if (-not $name) { Write-Host "  no theme is active" -ForegroundColor Red; return }
    $dir = Join-Path $script:CharactersDir $name

    if ("$Arg" -in 'off', 'none', 'clear', '-clear') {
        if (-not (Get-ThemeBackgroundFile $name)) { Write-Host "  $name has no background" -ForegroundColor DarkGray; return }
        if (Test-ThemeHidden $name 'background') { Write-Host "  $name's background is already hidden" -ForegroundColor DarkGray; return }
        Set-ThemeVisibility $name 'background' $false
        Write-Host "  background hidden for $name" -ForegroundColor Green
    } elseif ("$Arg" -in 'on', 'show') {
        if (-not (Get-ThemeBackgroundFile $name)) { Write-Host "  $name has no background to show" -ForegroundColor DarkGray; return }
        if (-not (Test-ThemeHidden $name 'background')) { Write-Host "  $name's background is already visible" -ForegroundColor DarkGray; return }
        Set-ThemeVisibility $name 'background' $true
        Write-Host "  background shown for $name" -ForegroundColor Green
    } else {
        if (-not (Test-Path -LiteralPath $Arg)) {
            Write-Host "  no such file: $Arg" -ForegroundColor Red; return
        }
        $src = (Resolve-Path -LiteralPath $Arg).Path
        $ext = [IO.Path]::GetExtension($src).ToLower()
        if ($ext -notin '.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp') {
            Write-Host "  '$ext' is not an image Windows Terminal will show" -ForegroundColor Red; return
        }
        # One background per theme, so any previous one goes whatever its
        # extension was - otherwise two would sit there and the older might win.
        Get-ThemeBackgroundFile $name | ForEach-Object { Remove-Item -LiteralPath $_ -Force }
        Copy-Item -LiteralPath $src -Destination (Join-Path $dir "background$ext") -Force
        Set-ThemeVisibility $name 'background' $true
        Write-Host "  background of $name set from $(Split-Path -Leaf $src)" -ForegroundColor Green
    }

    if (Test-AppearanceApplied) {
        Set-TerminalAppearance $true | Out-Null
        Write-Host "  applied now" -ForegroundColor DarkGray
    } else {
        Write-Host "  the theming is off; it will show with  customize on" -ForegroundColor DarkGray
    }
}

function Set-ThemeIcon($Arg, [bool]$Force) {
    $name = Get-CurrentCharacterName
    if (-not $name) { Write-Host "  no theme is active" -ForegroundColor Red; return }
    $c = @(Get-Characters) | Where-Object { $_.Name -eq $name } | Select-Object -First 1

    if ("$Arg" -in 'off', 'none', 'clear', '-clear') {
        if (-not $c -or (-not $c.Txt -and -not $c.Png)) { Write-Host "  $name has no icon" -ForegroundColor DarkGray; return }
        if (Test-ThemeHidden $name 'icon') { Write-Host "  $name's icon is already hidden" -ForegroundColor DarkGray; return }
        Set-ThemeVisibility $name 'icon' $false
        Use-EmptyIcon $name
        return
    }
    if ("$Arg" -in 'on', 'show') {
        if (-not $c -or (-not $c.Txt -and -not $c.Png)) { Write-Host "  $name has no icon to show" -ForegroundColor DarkGray; return }
        if (-not (Test-ThemeHidden $name 'icon')) { Write-Host "  $name's icon is already visible" -ForegroundColor DarkGray; return }
        Set-ThemeVisibility $name 'icon' $true
        Set-FastfetchIcon $name $Force
        return
    }
    Set-ThemeVisibility $name 'icon' $true
    Set-FastfetchIcon $Arg $Force
}

function Set-FastfetchIcon($Arg, [bool]$Force) {
    # A bare name selects one of the folders under characters/.
    $existing = @(Get-Characters) | Where-Object { $_.Name -eq $Arg } | Select-Object -First 1
    if ($existing) {
        if ($existing.Txt) { Use-Character $existing.Txt $existing.Name $Force $false; return }
        if ($existing.Png) {
            Write-Host "  converting $($existing.Name)..." -ForegroundColor DarkGray
            $txt = Convert-CharacterPng $existing.Png $Force
            if ($txt) { Use-Character $txt $existing.Name $Force $false }
            return
        }
        Write-Host "  '$Arg' has no .png or .txt in it" -ForegroundColor Red
        return
    }

    if (-not (Test-Path -LiteralPath $Arg)) {
        Write-Host "  no character or file called '$Arg'" -ForegroundColor Red
        $names = @(Get-Characters | ForEach-Object { $_.Name })
        if ($names.Count) { Write-Host "  available: $($names -join ', ')" -ForegroundColor DarkGray }
        return
    }

    $src = (Resolve-Path -LiteralPath $Arg).Path
    $ext = [IO.Path]::GetExtension($src).ToLower()
    if ($ext -ne '.png' -and $ext -ne '.txt') {
        Write-Host "  unsupported file type '$ext'. Give it a .png to convert," -ForegroundColor Red
        Write-Host "  a .txt that is already a logo, or the name of a character." -ForegroundColor DarkGray
        return
    }

    # Already inside characters/? Then use it where it lies instead of copying.
    if ($src.StartsWith($script:CharactersDir, [StringComparison]::OrdinalIgnoreCase)) {
        $name = (Split-Path -Leaf (Split-Path -Parent $src))
        if ($ext -eq '.png') {
            $txt = Convert-CharacterPng $src $Force
            if ($txt) { Use-Character $txt $name $Force $false }
        } else {
            Use-Character $src $name $Force $true
        }
        return
    }

    # Check the size before anything is created: refusing after having made a
    # folder and copied the picture into it leaves litter behind.
    if ($ext -eq '.png') {
        $size = Get-ImageSize $src
        if ($size -and -not (Test-IconSize $size.Width $size.Height $Force (Split-Path -Leaf $src))) { return }
    } else {
        $m = Get-LogoMetrics $src
        if (-not (Test-IconSize $m.Width ($m.Height * 2) $Force (Split-Path -Leaf $src))) { return }
    }

    # Coming from outside: give it a folder of its own, named after the file.
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $dir  = Join-Path $script:CharactersDir $name
    $isNew = -not (Test-Path -LiteralPath $dir)
    if ($isNew) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dest = Join-Path $dir (Split-Path -Leaf $src)
    Copy-Item -LiteralPath $src -Destination $dest -Force
    Write-Host "  $(if ($isNew) { 'added' } else { 'updated' }) characters\$name" -ForegroundColor DarkGray

    if ($ext -eq '.png') {
        $txt = Convert-CharacterPng $dest $Force
        if ($txt) {
            Use-Character $txt $name $Force $false
        } elseif ($isNew) {
            # The folder only existed for this import: leaving it behind after a
            # failure litters the character list with something unusable.
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  removed characters\$name again" -ForegroundColor DarkGray
        }
    } else {
        Use-Character $dest $name $Force $false
    }
}

function phaethon {
    if ($args.Count -ge 1 -and "$($args[0])" -eq 'reset') {
        $f = $args -contains '-force' -or $args -contains '-y' -or $args -contains '-f'
        Reset-FastfetchConfig $f
        return
    }
    # "icon" stays as an alias so the older spelling keeps working.
    if ($args.Count -ge 1 -and "$($args[0])" -in 'theme', 'icon') {
        $force = $false
        $words = @()
        if ($args.Count -ge 2) {
            foreach ($a in $args[1..($args.Count - 1)]) {
                if ("$a" -in '-force', '--force', '-f', '-y') { $force = $true }
                else { $words += "$a" }
            }
        }
        $verb = if ($words.Count -ge 1) { $words[0].ToLower() } else { '' }
        switch ($verb) {
            'reset'  { Reset-FastfetchConfig $force }
            'remove' {
                if ($words.Count -ge 2) { Remove-CharacterFolder $words[1] $force }
                else { Write-Host "  usage: phaethon theme remove <name>" }
            }
            'background' {
                if ($words.Count -ge 2) { Set-ThemeBackground $words[1] }
                else { Write-Host "  usage: phaethon theme background <file | on | off>" }
            }
            'icon' {
                if ($words.Count -ge 2) { Set-ThemeIcon $words[1] $force }
                else { Write-Host "  usage: phaethon theme icon <file | on | off>" }
            }
            ''       { Show-FastfetchIcon }
            default  { Set-FastfetchIcon $words[0] $force }
        }
        return
    }
    if ($args.Count -ge 1 -and "$($args[0])" -eq 'modules') {
        Show-ModuleToggles
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
                Write-Host "usage: phaethon auto [-y | -n | toggle]"
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
    # Only the bare splash call gets modules.jsonc applied automatically -
    # anyone typing real fastfetch flags is using the actual binary directly
    # and gets exactly what they asked for, untouched.
    if ($args.Count -eq 0) {
        $disabled = @(Get-DisabledModules)
        if ($disabled.Count) {
            & $exe --structure-disabled ($disabled -join ':')
            return
        }
    }
    & $exe @args
}

# The old name, kept working so nothing that already types "fastfetch theme
# ..." breaks - it is just phaethon under another name.
function fastfetch { phaethon @args }

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

# Every Windows Terminal setting this profile owns. Applying works through this
# list in both directions - a key the merged theme does not define is removed
# rather than left behind, which is what lets a theme without a background
# actually clear the previous one.
$script:ManagedKeys = @('colorScheme', 'backgroundImage', 'backgroundImageOpacity',
                        'backgroundImageStretchMode', 'backgroundImageAlignment',
                        'font', 'opacity', 'useAcrylic', 'cursorShape')

function Get-HiddenMarker($Name, $What) {
    Join-Path (Join-Path $script:CharactersDir $Name) "$What.hidden"
}

function Test-ThemeHidden($Name, $What) {
    if (-not $Name) { return $false }
    Test-Path -LiteralPath (Get-HiddenMarker $Name $What)
}

function Set-ThemeVisibility($Name, $What, [bool]$Visible) {
    # "off" never deletes the picture, only this marker - so undoing it is a
    # matter of showing it again, not re-importing the file.
    $marker = Get-HiddenMarker $Name $What
    if ($Visible) {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    } else {
        Write-Utf8NoBom $marker "Delete this file to show the $What again."
    }
}

function Get-ThemeBackgroundFile($Name) {
    # The background picture regardless of whether it is currently shown - the
    # marker itself has BaseName "background" too, so it must be excluded here
    # or "off" would make Get-ChildItem pick the marker up as the picture.
    if (-not $Name) { return $null }
    $dir = Join-Path $script:CharactersDir $Name
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq 'background' -and $_.Extension -ne '.hidden' } |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-ThemeBackground($Name) {
    if (Test-ThemeHidden $Name 'background') { return $null }
    Get-ThemeBackgroundFile $Name
}

function Get-ThemeLayer($Name) {
    # What the active character contributes on top of appearance.json: its
    # background, plus anything an optional theme.json in the folder overrides.
    $out = [ordered]@{}
    if (-not $Name) { return $out }
    $bg = Get-ThemeBackground $Name
    if ($bg) {
        $out['backgroundImage'] = $bg
        $out['backgroundImageOpacity'] = 0.1
        $out['backgroundImageStretchMode'] = 'uniformToFill'
    }
    $manifest = Join-Path (Join-Path $script:CharactersDir $Name) 'theme.json'
    if (Test-Path -LiteralPath $manifest) {
        $j = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $j.PSObject.Properties) { $out[$prop.Name] = $prop.Value }
    }
    $out
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
    if (-not $spec) { Write-Warning "windows-terminalppearance.json is missing"; return $false }
    $j = Get-WTSettings
    $guid = Resolve-WTProfileGuid $j $spec
    $p = Get-WTTargetProfile $j $guid
    if (-not $p) {
        Write-Warning "profile $guid not found in Windows Terminal"
        return $false
    }

    # appearance.json holds what every theme shares; the active character layers
    # its own background and whatever its theme.json overrides on top.
    $merged = [ordered]@{}
    if ($On) {
        Add-MissingSchemes $j
        foreach ($prop in $spec.settings.PSObject.Properties) {
            $v = $prop.Value
            if ($v -is [string]) {
                # The placeholder is what makes the folder movable and portable.
                $v = $v.Replace('{ROOT}', $script:SetupHome).Replace('/', [char]92)
            }
            $merged[$prop.Name] = $v
        }
        foreach ($entry in (Get-ThemeLayer (Get-CurrentCharacterName)).GetEnumerator()) {
            $merged[$entry.Key] = $entry.Value
        }
    }

    foreach ($key in $script:ManagedKeys) {
        if (-not $merged.Contains($key)) {
            # Walking the whole list, not just what is defined, is what lets a
            # theme with no background clear the one the previous theme set.
            $p.PSObject.Properties.Remove($key)
            continue
        }
        $v = $merged[$key]
        # Never write a scheme name that has no definition: an unusable value
        # here is what triggers the error dialog at every startup.
        if ($key -eq 'colorScheme' -and (Get-WTSchemeNames $j) -notcontains $v) {
            Write-Warning "colour scheme '$v' is not defined; keeping the current one"
            continue
        }
        $p | Add-Member -NotePropertyName $key -NotePropertyValue $v -Force
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

# ------------------------------------------------------ tab completion ------

function New-Completion($Text, $Tooltip) {
    # Names with a space in them have to come back quoted or the shell would
    # read them as two arguments.
    $insert = if ($Text -match '\s') { "'" + $Text.Replace("'", "''") + "'" } else { $Text }
    [System.Management.Automation.CompletionResult]::new(
        $insert, $Text, 'ParameterValue', $(if ($Tooltip) { $Tooltip } else { $Text }))
}

# -Native rather than -ParameterName: the fastfetch function takes $args so that
# everything it does not recognise reaches the real binary untouched, and there
# are no declared parameters for a completer to attach to. Registering it as
# native still fires for a function that shadows a command of the same name.
Register-ArgumentCompleter -Native -CommandName phaethon, fastfetch -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokens = @($commandAst.CommandElements | ForEach-Object { "$_" })
    # The partial word is already in the element list; drop it to see what came
    # before, which is what decides the kind of completion.
    if ($wordToComplete -and $tokens.Count -gt 1) { $tokens = @($tokens[0..($tokens.Count - 2)]) }
    $sub = if ($tokens.Count -ge 2) { $tokens[1].ToLower() } else { '' }

    $suggestions = switch ($sub) {
        { $_ -in 'theme', 'icon' } {
            if ($tokens.Count -ge 3 -and $tokens[2].ToLower() -in 'icon', 'background') {
                @(New-Completion 'off' 'hide it, without deleting the file'),
                @(New-Completion 'on'  'show it again')
            }
            elseif ($tokens.Count -ge 3 -and $tokens[2].ToLower() -eq 'remove') {
                @(Get-Characters | ForEach-Object { New-Completion $_.Name 'delete this character' })
            }
            elseif ($tokens.Count -ge 3) {
                @(New-Completion '-force' 'use a picture past the size limit')
            } else {
                @(Get-Characters | ForEach-Object {
                    $note = if ($_.Txt) { 'character' } else { 'character (converts on first use)' }
                    New-Completion $_.Name $note
                }) + @(
                    (New-Completion 'icon'       "set this theme's picture"),
                    (New-Completion 'background' "set this theme's wallpaper"),
                    (New-Completion 'remove'     'delete a theme')
                )
            }
        }
        'auto' {
            @(New-Completion '-y' 'run fastfetch at startup'),
            @(New-Completion '-n' 'do not run it at startup'),
            @(New-Completion 'toggle' 'flip it') | ForEach-Object { $_ }
        }
        default {
            @(New-Completion 'auto'    'control the startup splash'),
            @(New-Completion 'theme'   'show or change the theme'),
            @(New-Completion 'modules' 'show which info fields are on'),
            @(New-Completion 'reset'   'restore config.jsonc to the default') | ForEach-Object { $_ }
        }
    }
    $suggestions | Where-Object { $_.ListItemText -like "$wordToComplete*" }
}

Register-ArgumentCompleter -Native -CommandName customize -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    @(New-Completion 'status' 'show what is on'),
    @(New-Completion 'on'     'turn everything on'),
    @(New-Completion 'off'    'back to the stock terminal'),
    @(New-Completion 'toggle' 'flip it'),
    @(New-Completion 'save'   'remember the current look') |
        ForEach-Object { $_ } |
        Where-Object { $_.ListItemText -like "$wordToComplete*" }
}

# ---------------------------------------------------------------- startup ----

if ((Test-Path -LiteralPath $script:FastfetchFlag) -and (Test-FastfetchInteractive)) {
    phaethon
}
