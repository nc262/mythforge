# Security Policy

Mythforge is a single-player desktop game. It has no server, no accounts, no
sessions and no database, and it does not listen on any port. Its whole attack
surface is one outbound HTTP call to `127.0.0.1:8189` — the image engine, on
loopback.

That is a deliberately small surface, not an accident of scope. Nothing about
the game should ever be exposed to a network, and there is nothing in it that
would benefit from being.

## What the game touches

| | |
|---|---|
| Reads | `user://models/*.gguf` · `user://saves/` · `user://worlds/` · `user://session.cfg` |
| Writes | the same, all under `user://` — nothing in the install directory |
| Network | `POST http://127.0.0.1:8189/v1/images/generations`, and nothing else |

CI enforces the last line: an `"/api/` string in any `.gd` file fails the build.

## Supported versions

Security fixes land on the default branch.

## Running it safely

- **Do not expose `:8189`.** stable-diffusion.cpp is meant for loopback. It has
  no authentication because it is not supposed to need any.
- **Models are code-adjacent.** A `.gguf` is data, but it is data that decides
  what your Game Master says. Get them from official sources — the installer
  pulls from HuggingFace's canonical repos.
- **Saves are plain JSON** and contain whatever you typed at the table. They are
  not encrypted; treat them like any other document.

## Before publishing a fork

```bash
git status --short
git grep -n -I -E "(sk-[A-Za-z0-9_-]{20,}|xox[baprs]-|AIza[0-9A-Za-z_-]{20,}|Bearer [A-Za-z0-9._~+/-]{20,})"
```

Source, docs, tests and shipped game data belong in git. Models, baked world
zips, the NobodyWho binary, exports and anything under `user://` do not — they
are all gitignored, and two of them are over GitHub's per-file limit anyway.

## Reporting

Report vulnerabilities privately via GitHub security advisories if available, or
by opening a minimal issue that does not disclose exploit details.
