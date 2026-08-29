# Terminal setup

Windows Terminal dressed up: a hand-drawn pixel-art fastfetch splash, a themed
colour scheme and background, and a single switch to turn all of it off and get
the stock Windows terminal back.

![](fastfetch/alice-logo.png)

Everything is self-contained and path-independent — clone it anywhere, run
`install.ps1`, done. No administrator privileges, no Nerd Font required.

```
terminal/
├─ install.ps1            setup on a fresh machine
├─ fastfetch/             startup splash: logo, config, helper scripts
│  └─ sources/            original artwork the logo came from
├─ windows-terminal/      appearance + background image
└─ powershell/            profile.ps1, the real shell profile
```

---

## Master switch

```
customize            show current state
customize on         turn everything on
customize off        back to the stock Windows terminal
customize toggle     flip it
customize save       re-read the current Windows Terminal appearance
                     and store it as the "on" state
```

`customize off` does two things: it stops fastfetch from running at startup and
strips colour scheme, background image and font from the Windows Terminal
profile. The terminal looks exactly like a fresh Windows install. `customize on`
puts it all back.

The appearance changes **immediately**, because Windows Terminal reloads its own
`settings.json`. Fastfetch applies from the next window.

### customize save

If you change the look from Windows Terminal's own settings (scheme, background,
opacity, font) and want that to become the new "on" state, run `customize save`:
it re-reads the profile and updates `windows-terminal/appearance.json`. Without
that step, an `off` followed by an `on` would restore the previous look.

---

## fastfetch/

Prints system specs with Alice as the logo whenever a terminal opens.

| file | |
|---|---|
| `alice-logo.png` | **the pixel art, 44×46 px.** This is the file to edit |
| `alice-logo.txt` | generated from the PNG, this is what fastfetch reads. Do not hand-edit |
| `config.jsonc` | layout, colours, which modules to show |
| `logo-from-png.py` | PNG → txt, after you have redrawn the image |
| `logo-to-png.py` | txt → PNG, to pull the image back out of a logo |
| `autostart.on` | empty marker file: if it exists, fastfetch runs at startup |

### Editing the artwork

Open `alice-logo.png` in a pixel-art editor, save, then:

```powershell
cd <repo>\fastfetch
python logo-from-png.py alice-logo.png alice-logo.txt
```

The PNG → txt → PNG round trip is lossless, verified pixel by pixel: you can
iterate as often as you like without the image degrading.

**Two constraints.** Height must be even, because each terminal character holds
two vertical pixels (half blocks `▀`/`▄`): 46 px = 23 text rows. And if you
change the dimensions, the script prints the new values to copy into
`config.jsonc` under `width` and `height` — fastfetch needs them to know where
the module column starts. Leave them stale and the text either overlaps the logo
or leaves a gap.

The PNG has a transparent background: alpha below 128 means the pixel is off.

Requires `pillow` and `numpy`.

### sources/

Starting material, unused at runtime — safe to delete.

| file | |
|---|---|
| `alice_chibi.png` | the original illustration, 929×967 |
| `chibi_ascii.txt` | an older black-and-white ASCII rendering, no longer used |

The live artwork is `../alice-logo.png`; there is no copy of it here, that file
*is* the original. To activate an alternative you drop into this folder:

```powershell
cd <repo>\fastfetch
copy sources\<name>.png alice-logo.png
python logo-from-png.py alice-logo.png alice-logo.txt
```

### How it reaches the screen

Each character is a half block with the foreground colour painting the upper
pixel and the background colour the lower one: two pixels per cell, so twice the
vertical resolution of a solid glyph. The truecolor escapes are already inside
the `.txt`, which is why `config.jsonc` uses type `file-raw` and not `file` —
`file` would only substitute the nine `$1..$9` placeholders.

**No Nerd Font needed.** Half blocks and box-drawing characters are plain
Unicode, present in Cascadia Mono which Windows Terminal ships with.

### Why there is a junction

fastfetch looks for its config in `~/.config/fastfetch`. That path is a
**junction** pointing at `fastfetch/` in this repo, so the files live here while
`fastfetch` still works from any shell — PowerShell, cmd, Git Bash.

Move or rename the folder and the junction breaks. Recreate it with
`install.ps1`, or by hand:

```powershell
Remove-Item ~\.config\fastfetch -Force
New-Item -ItemType Junction -Path ~\.config\fastfetch -Target <repo>\fastfetch
```

---

## windows-terminal/

| file | |
|---|---|
| `appearance.json` | the settings `customize on` applies to Windows Terminal |
| `alice_mindscape_nobg.png` | the background image |
| `settings.json.original` | your Windows Terminal without the customizations |
| `settings.json.backup` | rolling copy, rewritten before every change |

The two `settings.json.*` files are machine-specific and stay out of version
control.

In `appearance.json` the image path uses the `{ROOT}` placeholder, swapped at
apply time for the repo's real location — that is what lets you move or clone
the folder without breaking the background.

`profileGuid` selects which Windows Terminal profile everything applies to.
`{61c54bbd-c2c6-5271-96e7-009a87ff44bf}` is the Windows PowerShell one, and it
is the same on every machine because Windows Terminal derives it deterministically.

If something goes wrong, restore by hand:

```powershell
copy <repo>\windows-terminal\settings.json.original `
     $env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

---

## powershell/

`profile.ps1` is the real shell profile. The file at
`Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` is only a loader
pointing here, so the customization lives entirely in this folder. Put your
aliases and functions in here too.

The profile derives the folder location from itself, so it contains no hardcoded
paths: move the repo wherever you want and just rerun `install.ps1` to update
the loader.

### fastfetch autostart alone

```
fastfetch auto            show state
fastfetch auto -y         on      (also: on, yes, 1)
fastfetch auto -n         off     (also: off, no, 0)
fastfetch auto toggle     flip it
```

Any other argument is forwarded straight to the binary, so `fastfetch --version`
and `fastfetch -s cpu` keep working.

The state is the `fastfetch/autostart.on` file, not a line inside the profile:
flipping it creates or deletes that file and never rewrites the script, so a bad
toggle cannot leave you without a configured shell.

The logo only runs in **interactive** sessions. The profile is loaded by
`powershell -Command "..."` too, and without that guard the logo would end up
inside the output of every script.

---

## Install

Clone or copy the folder anywhere, then:

```powershell
cd <repo>
.\install.ps1
```

No administrator privileges needed. The script is **idempotent**: rerun it as
often as you like, for instance after moving the folder.

| option | |
|---|---|
| `-NoAppearance` | leave Windows Terminal's `settings.json` untouched |
| `-NoAutostart` | install everything but keep fastfetch off at startup |

### What it does

1. **fastfetch** — if missing, offers `winget install Fastfetch-cli.Fastfetch`
2. **Python** — a check only: needed solely to regenerate the logo after
   redrawing it, not to use the setup. Warns and moves on if absent
3. **PowerShell profile** — writes the loader for Windows PowerShell 5.1 and,
   when present, PowerShell 7. An existing profile of your own is never
   overwritten: it is backed up and appended to
4. **junction** — creates `~/.config/fastfetch` pointing at this folder
5. **appearance** — applies scheme, background and font to Windows Terminal,
   after saving `windows-terminal/settings.json.original` (first run only)
6. **autostart** — turns fastfetch on

### Without Windows Terminal

Step 5 is skipped with a warning. Everything else works: fastfetch runs in any
terminal with truecolor support.

### Requirements

- Windows 10/11 with PowerShell 5.1 (ships with the OS)
- execution policy at least `RemoteSigned` for the current user. Check with
  `Get-ExecutionPolicy -List`; a profile that never loads is almost always this.
  Change it yourself — the installer does not touch security settings
- **no Nerd Font**: the stock fonts are enough

### Uninstall

```powershell
customize off                              # turn the customizations off
Remove-Item ~\.config\fastfetch -Force     # drop the junction
Remove-Item $PROFILE                       # drop the loader
```

The folder stays intact and you can reinstall whenever you want.

---

## Credits

Alice Thymefield is a character from *Zenless Zone Zero* by HoYoverse. The
artwork in `fastfetch/sources/` and `windows-terminal/` is fan material included
for personal use; all rights belong to the original creators. The scripts and
configuration are free to reuse.
