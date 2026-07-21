# Build & Export (Windows)

## The export

```bash
godot --headless --path godot --import                                   # once after new assets
godot --headless --path godot --export-release "Windows Desktop" ../dist/Mythforge.exe
cp dist/Mythforge.exe ~/Desktop/Mythforge.exe                            # standing rule: the Desktop copy is the one played
```

A running instance **locks** `Desktop\Mythforge.exe` — close the game before
copying, or the copy fails with `Device or resource busy`. Never skip the
Desktop copy silently; a stale Desktop build gets playtested by mistake.

## The exe's icon and metadata (rcedit)

Windows exe resources can only be rewritten by a Microsoft-format tool, so
Godot shells out to **rcedit**. Without it the export still succeeds but the
binary keeps the stock Godot robot icon and "Godot Engine" file properties.

Setup (once per machine):

1. Download `rcedit-x64.exe` from https://github.com/electron/rcedit/releases
   into `tools/` (gitignored — a downloaded tool, not vendored source).
2. Point Godot at it: `export/windows/rcedit` in
   `%APPDATA%\Godot\editor_settings-4.7.tres`.

What the preset stamps (`godot/export_presets.cfg`):

| Field | Value |
|---|---|
| `application/icon` | `res://icon.ico` |
| `application/product_name` / `company_name` | Mythforge |
| `application/file_description` | Mythforge — a local Game Master with real dice |
| `application/file_version` / `product_version` | 0.1.0.0 / 0.1.0 |

Verify after export:

```bash
tools/rcedit-x64.exe dist/Mythforge.exe --get-version-string ProductName
powershell -Command "Add-Type -AssemblyName System.Drawing; [System.Drawing.Icon]::ExtractAssociatedIcon('...\dist\Mythforge.exe').Width"
```

## The icon art

`godot/icon.ico` is generated, not hand-drawn — the MDL night plate with the
double gold ring and the **anvil** from the game's own icon library
(`ui/icons/glyph/anvil.png`), so the desktop badge and the in-game Forge-a-Hero
plate wear the same mark. `icon_src.png` is the 256px master. Regenerate by
re-running the bake in `scripts/` if the palette or glyph ever changes.

**Windows caches icons.** After a re-export the Desktop may keep showing the
old badge; `ie4uinit.exe -show` (or a re-login) clears the cache.
