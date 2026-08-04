# The one-click installer

A friend downloads one `Mythforge-Setup.exe`, clicks through, and gets a
Mythforge shortcut. No terminal, no account, no service to manage.

## The pieces

| File | Role |
|------|------|
| `Mythforge-Setup.iss` | Inno Setup script → the one `.exe`. Lays down the launcher and the setup scripts, drops the shortcuts, kicks off first-run setup. |
| `bootstrap.ps1` | First-run "download & configure". Delegates the hard parts to [`scripts/install.ps1`](../scripts/install.ps1) — hardware check, the model runtime, the three models, the image engine — then downloads the game. Idempotent, so it doubles as a repair. |
| `mythforge.ps1` | The launcher, and the only thing a player runs. Self-heals (runs `bootstrap` if the game is missing), starts the image engine in the background if it is installed, opens the game, and stops what it started on quit. |

Nothing heavy is in the installer. The game, the world packages, the ~4.6 GB
narrator model and the ~6.5 GB art checkpoint are all fetched at first run.

## Why the worlds ship beside the exe, not inside it

The export used to bundle `baked/*.zip` into the pck, producing a single
**3.02 GB** executable. GitHub caps a release asset at **2 GiB**, so the game
could not be published at all — and every world added made the one file bigger.

Shipped alongside, the exe is **131 MB** and each world is its own ~500 MB
download. Same bytes, nothing near a ceiling, and world seven is a seventh
asset rather than a fatter binary. `Compiler.baked_dirs()` searches
`res://baked` (editor and harnesses) and `<exe dir>/baked` (a player), so a
player can also drop a new world in beside the game with no re-export.

**Install layout:**

```
Mythforge/
├── Mythforge.exe
└── baked/
    ├── embervale.zip  neonspire.zip  everyday.zip
    └── saltmarsh.zip  fimbulreach.zip  brasshaven.zip
```

Verify any build before publishing it — this is the one failure no harness can
catch, because they all run from source where `res://baked` exists regardless:

```
Mythforge.exe --headless --mf-worlds
```

It prints every world it can see, opens each archive, checks for `world.json`,
and exits non-zero if any of that fails. A build that finds 0 worlds is a game
with nothing to play and it looks completely normal until you click New
Adventure.

## Build it

Inno Setup **6 or 7** — nothing in the script uses a 7-only directive.

```
iscc /DClientUrl="https://github.com/nc262/mythforge/releases/download/vX/Mythforge.exe" installer\Mythforge-Setup.iss
```

→ `installer\Output\Mythforge-Setup.exe`. Publish that plus `Mythforge.exe` (the
exported Godot build) as release assets. Everything else comes from official
sources — HuggingFace for the models, GitHub for stable-diffusion.cpp and the
NobodyWho extension — so those two files are the only ones you host.

### The baked worlds are release assets too, not git

`godot/baked/*.zip` (~2.9 GB, six worlds) is **gitignored on purpose** — it is
generated output, and it is larger than the repo. Each zip is published as its
own release asset and `bootstrap.ps1` fetches all six into `baked/` beside the
exe. Rebuild locally with `tests/bake_worlds.tscn` + `scripts/bake_zip.py` (see
[AssetBake.md](../godot/docs/AssetBake.md)).

**Consequence to know:** a fresh clone has no `godot/baked/`, so the harnesses
and the editor see zero worlds until you bake them or drop the release zips into
`godot/baked/`. The exported exe no longer bundles them either way — that is the
whole point of the split — so `--mf-worlds` is the check that matters.

## What is verified, and what is not

Verified on the dev machine (AMD, Vulkan):

- Every PowerShell script parses clean.
- `scripts/install.ps1` and `scripts/check-system.ps1` are the paths actually in
  use here.
- **The installer compiles and round-trips.** 2026-08-04: compiled with Inno
  Setup 7, silent-installed to a scratch directory, inspected (21 files, the
  layout below), then uninstalled — leaving no files, no Start Menu group and no
  `HKCU` uninstall key.

Compiling it first time found four things that reading it had not:

| Found | Why it mattered |
|---|---|
| `__pycache__/*.pyc` was being packaged | `recursesubdirs` swept this box's compiled bytecode into the installer a stranger downloads |
| `{commondesktop}` under `PrivilegesRequired=lowest` | The all-users desktop needs admin this install does not ask for. Now `{autodesktop}` |
| `[UninstallDelete]` never named `baked\` | **Uninstall orphaned ~2.9 GB of worlds.** Verified by building the pre-fix script and watching it leave them behind |
| The header still said the exe carries the worlds | The release split removed exactly that |

**Still not exercised — validate before shipping wide:**

- **A full first-run `bootstrap` on a fresh box.** This is the remaining risk and
  it is the big one: ~10 GB of downloads, GPU detection, three models and the
  image engine, none of it run here so as not to disturb the dev install. What is
  proven above is the *installer*; `bootstrap.ps1` is still unproven.
- An NVIDIA card. Both engines are Vulkan, so there is no vendor branch left to
  get wrong — but "should work" is not "was run".

**Decided, not open:** the installer is shipped **unsigned**. An OV certificate
is a few hundred dollars a year and this project has no revenue, so SmartScreen's
*"Windows protected your PC"* is documented rather than removed — the top-level
[README](../README.md#install--play) tells a player to click **More info → Run
anyway**, and says why. A self-signed certificate is not an option: it does not
raise SmartScreen reputation, so it adds a build step and changes nothing a
player sees.

If the art engine does not come up on a given machine, the game is still fully
playable: the shipped worlds carry their art pre-baked.
