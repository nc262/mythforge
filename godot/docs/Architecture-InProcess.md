# Should the game host its own AI? — research

Director's question (2026-07-29): *"why are we maintaining two front ends… why
does this even need a web interface, shouldn't this all be running inside the
game? Research this."*

Short answer: **yes, and the reason it doesn't is historical, not technical.**
Every capability the backend provides has a mature in-process equivalent that
runs on this machine's AMD card *better* than the current stack does. Nothing
here needs a server. But the migration is large and must be staged, because the
game is the small part of this repository, not the big one.

## Why there is a web interface at all

Mythforge is not a game with a backend bolted on. It is a **game bolted onto a
web application**:

| | lines |
|---|---|
| Web UI (`static/**.js` + html) | **~158,600** |
| Backend Python (`routes/`, `src/`, `core/`, `app.py`) | **~59,900** |
| **The Godot game** (`godot/**.gd`) | **21,507** |

The game is **~9%** of the codebase. `static/mythforge.html` is not leftover
cleanup after a port — it is the original client, and the Godot client is the
newcomer. That is why R8-32 found the web UI *ahead* on features: it has had
longer, and it sits next to the code it talks to.

So "remove the web interface" is the wrong shape for the task. The real task is
**extract the game from the workspace**.

## What the game actually asks the backend for

Every endpoint the Godot client calls, and whether it needs a server:

| endpoint | what it really is | needs a server? |
|---|---|---|
| ~~`/api/chat_stream`~~ | the GM turn, SSE | **gone** — `LocalGM.stream` (f4bbfa5) |
| `/api/characters/studio/state/*` | reads/writes **one JSON file** | **no** — `user://` |
| ~~`/api/characters/studio/memory/{beat,recall}`~~ | embed a beat, recall by similarity | **gone** — `LocalMemory` (cfac9fd) |
| ~~`/api/characters/studio/{codex,quests}`~~ | cast + quest extraction | **gone** — `Chronicle`, schema-constrained |
| `/api/characters/studio/generate` | portrait/scene art → sd.cpp | **no** — local diffusion |
| `/api/characters/studio/{worldsmith,worldtick,complete_json}` | LLM calls with a JSON schema | **no** — local LLM |
| `/api/models`, `/api/session`, `/api/default-chat`, `/api/history` | model + session bookkeeping | **no** — an artefact of the server |
| `/api/auth/*` | identity | **no** — single player |
| `/api/stt/transcribe` | speech to text | **no** — whisper.cpp |
| `/api/presets/templates` | static JSON | **no** — ship it |

There is no row where the answer is yes. This is a single-player desktop game;
every one of these is a local capability wearing an HTTP costume.

## What the HTTP costume has cost, measured

Not speculation — these are findings from this repo's own playtests, all traced
to the client/server split:

- **The player's saves became invisible.** Turning the login wall off removed
  the auth middleware, so `get_current_user()` returned `None` and every write
  was filed under the dict key `None` while the player's own data sat under
  their username. Three playtest reports (R8-01, R9-07, R12-01).
- **Three features silently never persisted** because the client wrote state
  kinds (`adventures`, `cast`, `lore`) that the server's allow-list did not
  accept — 400s that the fire-and-forget client never surfaced.
- **The narrator was pinned to the wrong model.** Sessions store their model
  server-side; a session born under a 14B kept it forever, and `PATCH
  /api/session` 404s because `session_manager` and the `sessions` table are
  different stores.
- **Two front-ends**, the older one ahead on features (R8-32).

Every one of those is a *distributed systems* bug in a program that runs
entirely on one machine. In-process, none of them are expressible.

## The local-LLM path

**[NobodyWho](https://github.com/nobodywho-ooo/nobodywho)** is a Godot
GDExtension over llama.cpp: streaming chat, tool calling, embeddings and RAG,
running in-process with GPU acceleration, installable from AssetLib. Licence is
EUPL-1.2 — usable from a proprietary game; modifications to the extension itself
stay open. Alternatives: [godot-llm](https://github.com/Adriankhl/godot-llm)
and [godot-llama-cpp](https://github.com/hazelnutcloud/godot-llama-cpp).

**The AMD detail matters more than anything else here.** NobodyWho accelerates
via **Vulkan**, and for llama.cpp on Radeon the reporting is consistent: Vulkan
runs on Windows, needs no toolkit install, and is often *faster than ROCm at
token generation*. It is described as the path of least resistance for Radeon
owners.

Measured on this box today, with the current stack:

| | tok/s |
|---|---|
| `llama3.1:8b` (fits in VRAM) | **86.9** |
| `qwen2.5:14b` (fits) | 46.9 |
| `qwen2.5:14b` spilled to CPU (Performance.md §1) | 6–9 |

The 90–143 s turns were never the model being slow. They were a 14B pushed onto
the CPU because ComfyUI was holding VRAM. In-process inference does not fix the
arithmetic of VRAM — but it removes the *reason* two separate processes are
fighting over it, and it removes Ollama's per-session model bookkeeping, which
is what pinned the wrong model in the first place.

## The local-image path — this is where the biggest win is

**[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)** is a
pure C/C++ ggml implementation supporting **SDXL and SDXL-Turbo** with a
**Vulkan** backend on Windows.

Read the hard-won rules in this repo's own `CLAUDE.md` and notice what they all
have in common:

> ComfyUI **MUST** launch via `zluda.exe` … `cublas64_11.dll … WinError 126`
> ZLUDA trips Windows Defender … an exclusion is required or the install
> silently breaks
> cuDNN must be **OFF** for SDXL on ZLUDA or conv2d throws
> ComfyUI's venv must be Python 3.11 (ZLUDA's patches are cp311-only)
> ComfyUI auto-update is disabled on purpose

Every one of those exists for a single reason: **ComfyUI wants CUDA and this is
an AMD card.** ZLUDA is a CUDA shim, and the whole fragile tower — the wrapper
batch file, the Defender exclusion, the pinned Python, the disabled updates, the
baked `CUDNNToggleAutoPassthrough` node — is scaffolding around that mismatch.

A Vulkan diffusion backend does not need CUDA, so it does not need ZLUDA, so
none of that scaffolding has anything to hold up. That is not a refactor; it is
a deletion.

## Recommendation

Staged, each stage shippable, in this order:

1. **Persistence first, and it is nearly free.** `studio/state/*` is a JSON file
   behind HTTP. Move it to `user://` and delete the round trip. This alone
   retires the identity bug, the state-kind contract, and
   `scripts/check_state_kinds.py` — the guard stops being necessary rather than
   being maintained.
2. **The GM turn.** NobodyWho with a GGUF ~8B, Vulkan. Keep the current
   `Api.stream()` seam so the swap is one implementation behind one interface;
   the tag pipeline, envelope and Chronicle are already client-side and do not
   move.
3. **Memory/RAG.** NobodyWho embeddings replace `memory/{beat,recall}`.
4. **Images.** stable-diffusion.cpp + Vulkan replaces bridge → ComfyUI → ZLUDA.
   Biggest deletion, so do it once the LLM path has proven the pattern.
5. **Then, and only then, retire the web app** — with the R8-32 feature list
   ported, not abandoned: Cast, Chronicle, pack load, Party, Trade.

Stage 1 is a day and pays immediately. Stages 2–4 are each a real piece of work,
and the honest headline is: **~220k lines of web application currently exist to
serve a 21.5k-line game.** Extraction is not a cleanup task, it is the roadmap.

## What would argue against

Kept for balance, because none of this is free:

- **GDExtension means native binaries** per platform, and a build/CI story this
  project does not have yet.
- **Model files are large and must ship or download.** Ollama currently hides
  that; in-process, the game owns it.
- **The web workspace has real features** — deep research, documents, email,
  agents — that the game does not use but the Director may still want *as a
  workspace*. Extraction should not mean deleting Odysseus, only cutting the
  game free of it.
- **NobodyWho is EUPL-1.2.** Fine for a proprietary game; modifications to the
  extension must stay open. Worth a deliberate decision rather than a surprise.

## Sources

- [NobodyWho — local LLM inference in Godot](https://github.com/nobodywho-ooo/nobodywho) · [docs](https://docs.nobodywho.ooo/)
- [godot-llm](https://github.com/Adriankhl/godot-llm) · [godot-llama-cpp](https://github.com/hazelnutcloud/godot-llama-cpp)
- [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
- [AMD ROCm vs RADV Vulkan for llama.cpp — Phoronix](https://www.phoronix.com/review/rocm-71-llama-cpp-vulkan)
- [llama.cpp Vulkan outperforms ROCm — ROCm issue #4883](https://github.com/ROCm/ROCm/issues/4883)
- [CUDA vs Vulkan for llama.cpp](https://llmrequirements.com/cuda-vs-vulkan-llama-cpp)
- [llama.cpp vs vLLM — Red Hat Developer](https://developers.redhat.com/articles/2026/06/15/llamacpp-vs-vllm-choosing-right-local-llm-inference-engine)

## Field note: my own tooling was lying to me

Worth recording, because it cost most of an afternoon and produced two confident
wrong diagnoses.

The agent's Bash tool runs against a **virtualised view of `%APPDATA%`**. Writes
land in a sandbox overlay: `ls` sees them, the shipped game does not. PowerShell
sees the real disk. So:

- `scripts/migrate_saves_local.py`, run through Bash, wrote eleven saves that
  existed only for the tool that wrote them. The game read an empty folder and
  correctly showed no CONTINUE.
- Probing `load_index()` through the same tool returned 11 records — from the
  sandbox — which "confirmed" the code was fine and pointed the investigation at
  the exported build instead.

And separately: **a release export does not route `print()` into the log file.**
An instrumented run came back completely blank, including a probe placed before
code that demonstrably ran. I read that silence as "never executed" and rewrote
`_refresh()` on the strength of it. The rewrite was a good change on its own
merits — the Hall should not wait on the network to show local saves — but the
reasoning behind it was wrong.

Two rules earned the hard way:

1. **Verify filesystem state with the same kind of process that will consume
   it.** For anything under `user://`, that means PowerShell, not Bash.
2. **Absence of a print is not evidence.** Trace to a FILE the game writes; a
   file append cannot be swallowed by a logging policy.

## Stage 2, measured — and the result that reshapes the roadmap

The in-process narrator works. It is also, right now, **slower than the thing it
replaces**, and the reason is the most useful thing found today.

Same 8B model, same machine, comparable prompt (~1,200–1,560 tokens in,
~340 out):

| | VRAM free to the model | wall per turn |
|---|---|---|
| In-process (NobodyWho / Vulkan), ComfyUI resident | **5,800 MiB** | 41.6s then 51.7s |
| In-process, ComfyUI stopped | **15,557 MiB** | **24.4s then 28.5s** |
| Ollama, comparable prompt | — | **12.7s** (1,208 tok prompt in 1.2s; 340 out at 44 tok/s) |

Two things fall out of that.

**1. VRAM headroom is the dominant cost, and it is measured now, not asserted.**
Simply taking ComfyUI off the card takes a turn from ~52s to ~28s — a 1.8x
speedup with no code change. `Performance.md` §1 already said idle ComfyUI holds
~7.4 GB; this is what that costs a narrator sharing the card.

**This couples Stage 2 and Stage 4.** Moving the GM in-process does not resolve
the contention — it inherits it. The narrator will not be fast until the image
stack stops holding the GPU, which is exactly what Stage 4 (stable-diffusion.cpp
in-process, no ComfyUI, no ZLUDA) is for. Stage 4 is not the last stage by
value; it is the one that makes Stage 2 pay.

**2. Part of the gap to Ollama was ours, and it is closed.** The clue was that
turn 2 cost MORE than turn 1 on a warm model, which is backwards.
`NobodyWhoChat` keeps a conversation — but this game's context does not live in
one. `Composer.envelope()` rebuilds the entire situation every turn and
Chronicle owns long-term memory, so letting the chat accumulate history sent all
of that twice and grew without bound until it passed the 4096-token context and
began re-processing. Calling `reset_context()` before each turn makes every turn
cost what the first one did:

| | turn 1 | turn 2 | turn 3 |
|---|---|---|---|
| conversational (before) | 41.6s | 51.7s | — *growing* |
| stateless (after), free card | 24.4s | 22.0s | **19.3s** |

A ~1.5x gap to Ollama remains (19.3s against 12.7s). Two suspects were chased
and both are dead ends:

- **The integrated GPU.** Forcing `GGML_VK_VISIBLE_DEVICES=0` made it *slower*,
  so device 0 was already selected.
- **The doubled BOS token.** Real — the Ollama blob has no
  `tokenizer.ggml.add_bos_token` metadata, so llama.cpp defaults to true and the
  chat template adds a second. But it is ONE token in ~1,900: 0.05%. It cannot
  be worth 1.5x, and saying so is cheaper than measuring it.

**The comparison itself is now the problem.** Asked mid-session, Ollama reported
`size=5.9GB size_vram=0.7GB` — the model almost entirely in system RAM — while
still turning in 44 tok/s. Both runtimes are competing for a card whose free
VRAM changes with whatever else is resident, so neither number is a property of
the runtime; they are properties of the machine at that instant. A clean
comparison needs the GPU to itself.

Which points back at the same conclusion the VRAM measurement already reached,
and is the honest reason to stop chasing this one: **the variable worth removing
is ComfyUI, not the last 1.5x.**

Until that is closed, the honest position is: **the local path is correct,
private, and serverless, but not yet faster.** It should not be switched on by
default on the strength of architecture alone.

### Method note

The first number measured was "8 tok/s", derived from wall-clock divided by
output tokens. That conflates model load, prompt processing and generation, and
it flattered nothing — it was simply the wrong measurement. The comparison only
became meaningful once Ollama was given a prompt of the same weight; its
headline 87 tok/s came from a 16-token prompt and was never comparable to a
1,560-token envelope.

## Resolved: ComfyUI removed, and the number re-taken

The section above ends by naming the open variable — *"the variable worth
removing is ComfyUI, not the last 1.5x"* — and says the local path is
**"correct, private, and serverless, but not yet faster."** ComfyUI is now gone
(the engine is stable-diffusion.cpp on Vulkan) and `tests/bench_gm.tscn` was
re-run twice on the same envelope (4,871 chars + 1,383 system):

| | turn 1 | turn 2 | turn 3 |
|---|---|---|---|
| conversational, ComfyUI resident | 41.6s | 51.7s | — *growing* |
| stateless, ComfyUI stopped by hand | 24.4s | 22.0s | 19.3s |
| stateless, **ComfyUI removed** | **8.3–8.7s** | **4.3s** | **3.7s** |

Reproducible to the tenth across both runs. That is **~5.2x** on the steady
state against the last recorded figure, and it settles the comparison the doc
gave up on: **3.7s against Ollama's 12.7s.** The local path is no longer "not
yet faster" — it is now the fast one, and the prediction that removing ComfyUI
was worth ~1.8x undershot by roughly 3x.

**Why it beat the prediction.** The 1.8x estimate assumed the replacement would
also sit on the card, just more cheaply — `sd.cpp holds 6.6 GB only while it is
running`, as an earlier note in this repo put it. Measured, that is wrong: idle
sd-server holds **118 MB** of dedicated VRAM with a 99 MB working set. It does
not keep the checkpoint resident at all; it loads per request and gives the
memory back. ComfyUI's ~7.4 GB idle was not the price of diffusion, it was the
price of *ComfyUI*. So the narrator does not merely get a bigger share of the
card between images — between images it gets essentially all of it.

The corollary is that `ArtCache._yield_the_card()` is deleted rather than
ported. It POSTed ComfyUI's `/free` to force an unload during a GM turn;
sd-server 404s that and exposes no unload API, so it had become a request firing
into nothing. There is no lever to replace it with and none is needed — there is
no longer an idle tenant to evict. `hold` (pausing our own queue during a
stream) still does real work and stays.

### The image side got faster too, and for an unrelated reason

Chasing why an image took ~50s exposed a genuine misconfiguration rather than a
cost of the swap:

```
sampling completed, taking 14.14s          <- 20 steps, fine
ggml_vulkan: Failed to allocate pinned memory
  (Requested buffer size exceeds device buffer size limit: ErrorOutOfDeviceMemory)
latent 1 decoded, taking 36.20s            <- the actual bill
generate_image completed in 50.42s
```

Untiled, decoding one 1024x1024 latent asks for a single Vulkan buffer past this
device's limit; ggml logs the failure and falls back to a slow path. **The
sampling was never the problem — the VAE decode was 72% of the image.**
`--vae-tiling` takes decode to **3.08s** and the image to **19.9s** cold /
**17.2s** warm, and at a fixed seed the result is compositionally identical, so
it costs nothing. It is now set in all three launch paths
(`ecosystem.config.js`, `scripts/start-image-sdcpp.ps1`,
`scripts/mythforge_supervisor.py`) and should be treated as load-bearing, not
tuning.

One flag was tried and rejected. `--steps 8` — Turbo checkpoints advertise ~8 —
does halve sampling (11.4s per image), but at 8 steps the same prompt and seed
rendered the subject tiny and near-black where 20 filled the frame. Paying ~6s
for a usable image is the right trade. Worth knowing either way: **sd-server
ignores the `steps` field in the OpenAI-shaped request body** (a request asking
for 8 ran 20/20 in the log), so steps are a launch flag or nothing.

### Supervision, and why ComfyUI kept coming back

Killing ComfyUI was not sufficient — it returned twice, from two places outside
anything this repo's code touches:

1. pm2 app `image-stack` ran `scripts/image-stack-watchdog.mjs`, a 30-second
   port poller that relaunched ComfyUI + the bridge whenever `:8188` or `:8101`
   went dark. It even got one last relaunch in mid-teardown. Deleting the pm2
   app is only half: `dump.pm2` still listed it, so the next `pm2 resurrect`
   would have restored it. **`pm2 save` is part of the fix.**
2. A logon entry, `odysseus-image-stack.vbs`, started the image stack from the
   *older* `Code/odysseus` checkout at every sign-in. Nothing done in this
   repository could have stopped it. Moved to `~/startup-disabled/`.

The watchdog is deleted rather than repointed. It existed because ComfyUI's
ZLUDA console had to stay hidden — a visible window can catch `CTRL_CLOSE` and
abort it — which ruled out running it under pm2 directly. sd-server is one
native binary with no console fragility, so pm2 supervises it as `image-engine`
and the arm's-length poller has nothing left to do. Verified: `:8188` and
`:8101` stayed dark for 120s after teardown.

**The general lesson, which cost real time twice in this project:** a process
that reappears is being *supervised*, and the supervisor is usually not in the
tree you are editing. Check pm2's saved dump and the Startup folder before
concluding a kill worked.
