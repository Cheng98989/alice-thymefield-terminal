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
$script:CharactersDir    = Join-Path $script:SetupHome 'fastfetch\characters'
# Both dimensions, in pixels. A logo is as wide in columns as the picture is in
# pixels and half as tall in rows, so much past this the information column gets
# pushed off the right edge and the prompt scrolls away. "-force" overrides it.
$script:IconMaxPixels    = 64
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
    $block = [regex]::Replace($block, '"source"\s*:\s*"[^"]*"', '"source": "' + $Source + '"')
    $block = [regex]::Replace($block, '"width"\s*:\s*\d+',  '"width": '  + $Width)
    $block = [regex]::Replace($block, '"height"\s*:\s*\d+', '"height": ' + $Height)
    Write-Utf8NoBom $file ($text.Substring(0, $start) + $block + $text.Substring($end))
    return $true
}

function Get-LogoSource {
    $file = Join-Path $script:FastfetchDir 'config.jsonc'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $m = [regex]::Match($text, '"source"\s*:\s*"([^"]*)"')
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

function Show-FastfetchIcon {
    $current = Get-LogoSource
    $chars   = @(Get-Characters)
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
    } else {
        Write-Host "  no logo configured" -ForegroundColor Red
    }

    if ($chars.Count) {
        Write-Host ""
        Write-Host "  available"
        foreach ($c in $chars) {
            $mark = if (-not $c.Txt) { "  (no logo yet - selecting it will convert)" } else { "" }
            Write-Host "    $($c.Name)$mark" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  fastfetch icon <name>       switch character" -ForegroundColor DarkGray
    Write-Host "  fastfetch icon <file.png>   import a new one" -ForegroundColor DarkGray
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
        Write-Host "  Install it from python.org, then:  python -m pip install pillow numpy" -ForegroundColor DarkGray
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
        Write-Host "  conversion failed:" -ForegroundColor Red
        Write-Host ($out.Trim()) -ForegroundColor DarkGray
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return $null
    }
    Move-Item -LiteralPath $tmp -Destination $txt -Force
    return $txt
}

function Use-Character($TxtPath, $Label, [bool]$Force, [bool]$CheckSize) {
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
        Write-Host ""
        Write-Host "  character  " -NoNewline; Write-Host $newName -ForegroundColor Green
        Write-Host "  logo       $TxtPath"
        Write-Host "  size       $($m.Width) x $($m.Height) characters, written into config.jsonc"
        Write-Host "  visible in the next window" -ForegroundColor DarkGray
        Write-Host ""
    }
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
        if ($txt) { Use-Character $txt $name $Force $false }
    } else {
        Use-Character $dest $name $Force $false
    }
}

function fastfetch {
    if ($args.Count -ge 1 -and "$($args[0])" -eq 'icon') {
        $force = $false
        $target = $null
        if ($args.Count -ge 2) {
            foreach ($a in $args[1..($args.Count - 1)]) {
                if ("$a" -in '-force', '--force', '-f') { $force = $true }
                elseif (-not $target) { $target = "$a" }
            }
        }
        if ($target) { Set-FastfetchIcon $target $force } else { Show-FastfetchIcon }
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
Register-ArgumentCompleter -Native -CommandName fastfetch -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokens = @($commandAst.CommandElements | ForEach-Object { "$_" })
    # The partial word is already in the element list; drop it to see what came
    # before, which is what decides the kind of completion.
    if ($wordToComplete -and $tokens.Count -gt 1) { $tokens = @($tokens[0..($tokens.Count - 2)]) }
    $sub = if ($tokens.Count -ge 2) { $tokens[1].ToLower() } else { '' }

    $suggestions = switch ($sub) {
        'icon' {
            if ($tokens.Count -ge 3) {
                @(New-Completion '-force' 'use a picture past the size limit')
            } else {
                @(Get-Characters | ForEach-Object {
                    $note = if ($_.Txt) { 'character' } else { 'character (converts on first use)' }
                    New-Completion $_.Name $note
                })
            }
        }
        'auto' {
            @(New-Completion '-y' 'run fastfetch at startup'),
            @(New-Completion '-n' 'do not run it at startup'),
            @(New-Completion 'toggle' 'flip it') | ForEach-Object { $_ }
        }
        default {
            @(New-Completion 'auto' 'control the startup splash'),
            @(New-Completion 'icon' 'show or change the character') | ForEach-Object { $_ }
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
    fastfetch
}
