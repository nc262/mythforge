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
| `/api/chat_stream` | the GM turn, SSE | **no** — local LLM |
| `/api/characters/studio/state/*` | reads/writes **one JSON file** | **no** — `user://` |
| `/api/characters/studio/memory/{beat,recall}` | embed a beat, recall by similarity | **no** — local embeddings |
| `/api/characters/studio/generate` | portrait/scene art → ComfyUI bridge | **no** — local diffusion |
| `/api/characters/studio/{worldsmith,worldtick,codex,quests,complete_json}` | LLM calls with a JSON schema | **no** — local LLM |
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

**2. There is still a ~2x gap to Ollama on a free card** (28.5s vs 12.7s), and
it is NOT explained yet. Ruled out: the integrated GPU — forcing
`GGML_VK_VISIBLE_DEVICES=0` made it *slower*, so device 0 was already selected.
Remaining suspects, in order: Ollama using ROCm/HIP rather than Vulkan for this
workload; NobodyWho defaulting `n_ctx` to 4096 and re-processing the envelope
each turn where Ollama keeps a KV cache across a session; and the doubled BOS
token the tokenizer warns about on every call.

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
