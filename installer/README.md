# The one-click installer

A friend downloads one `Mythforge-Setup.exe`, clicks through, and gets a
Mythforge shortcut. No terminal, no account, no service to manage.

## The pieces

| File | Role |
|------|------|
| `Mythforge-Setup.iss` | Inno Setup script → the one `.exe`. Lays down the launcher and the setup scripts, drops the shortcuts, kicks off first-run setup. |
| `bootstrap.ps1` | First-run "download & configure". Delegates the hard parts to [`scripts/install.ps1`](../scripts/install.ps1) — hardware check, the model runtime, the three models, the image engine — then downloads the game. Idempotent, so it doubles as a repair. |
| `mythforge.ps1` | The launcher, and the only thing a player runs. Self-heals (runs `bootstrap` if the game is missing), starts the image engine in the background if it is installed, opens the game, and stops what it started on quit. |

Nothing heavy is in the installer. The game (~1.6 GB, carrying the pre-baked
worlds), the ~4.6 GB narrator model and the ~6.5 GB art checkpoint are all
fetched at first run.

## Build it

```
iscc /DClientUrl="https://github.com/<you>/mythforge/releases/download/vX/Mythforge.exe" installer\Mythforge-Setup.iss
```

→ `installer\Output\Mythforge-Setup.exe`. Publish that plus `Mythforge.exe` (the
exported Godot build) as release assets. Everything else comes from official
sources — HuggingFace for the models, GitHub for stable-diffusion.cpp and the
NobodyWho extension — so those two files are the only ones you host.

### The baked worlds are release assets too, not git

`godot/baked/*.zip` (~1.4 GB, six worlds) is **gitignored on purpose**. The exe
bundles them at export time, so players get them inside `Mythforge.exe` and a
clone never needs them. Rebuild locally with `tests/bake_worlds.tscn` +
`scripts/bake_zip.py` (see [AssetBake.md](../godot/docs/AssetBake.md)), or attach
them to the release if you want them downloadable on their own.

**Consequence to know:** a fresh clone has no `godot/baked/`, so an export from
it produces an exe with **no pre-baked worlds** until you either bake them or
drop the release zips into `godot/baked/`.

## What is verified, and what is not

Verified on the dev machine (AMD, Vulkan):

- Every PowerShell script parses clean.
- `scripts/install.ps1` and `scripts/check-system.ps1` are the paths actually in
  use here.

**Not exercised on a clean machine — validate before shipping wide:**

- A full first-run `bootstrap` on a fresh box (it pulls ~10 GB; not run here so
  as not to disturb the dev install).
- An NVIDIA card. Both engines are Vulkan, so there is no vendor branch left to
  get wrong — but "should work" is not "was run".
- Compiling the `.iss` — needs Inno Setup 6 installed.
- Windows SmartScreen: an unsigned installer shows a warning. Code-sign
  `Mythforge-Setup.exe`, or document the "More info → Run anyway" click.

If the art engine does not come up on a given machine, the game is still fully
playable: the shipped worlds carry their art pre-baked.
