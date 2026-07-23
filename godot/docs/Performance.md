# Turn latency — what's actually slow, and what to do about it

Measured 2026-07-23 on the shipped exe + the local stack. Written to be
portable: **every fix here has to work on a friend's machine**, not just on the
one AMD box this was measured on. Where a number is specific to this hardware
it says so.

Companion to [UIPolish.md](UIPolish.md) B8.

---

## 1. The one measurement that explains most of it

```
GET /api/ps  →  llama3.1:8b   size 5.86 GB   size_vram 3.96 GB   ctx 4096
                → only 67 % of the model is on the GPU
```

A third of the model is running **on the CPU**. That is why generation measures
**6–9 tok/s** on a Radeon RX 7900 GRE, a card that should do several times that
on an 8B. Everything else in this document is smaller than this.

Why it happens here: ComfyUI/ZLUDA holds the card.

```
GET :8188/system_stats → vram_total 17.2 GB, vram_free 9.5 GB
                       → the image stack is sitting on ~7.7 GB
```

Ollama decides the CPU/GPU split **once, at load time**, and keeps it for the
life of the loaded model. Our LLM loaded while the shop's icon flood had the
card busy, so it settled at 67 % and stayed there — for every turn afterwards.

**This is the portability problem in miniature.** A friend with one 8 GB card
running only Ollama has a different split than a friend with 24 GB running
Ollama and ComfyUI together. The fix cannot be a magic number; it has to be
*measured on their machine at runtime*.

## 2. Second finding: we ask for a 128 000-token context window

`src/llm_core.py:1460` — the streaming chat path builds its Ollama payload with

```python
num_ctx=get_context_length(url, model)   # → 128000 for llama3.1:8b
```

The studio's JSON calls sensibly pass `num_ctx=8192`. Only the main narration
path asks for the model's full advertised window. `num_ctx` sizes the KV cache
allocation, so a 128 k request reserves VRAM we then cannot use for weights —
which is exactly what pushes layers onto the CPU.

Ollama clamped it to 4096 here (`ctx 4096` in `/api/ps`, i.e. a server-side
`OLLAMA_CONTEXT_LENGTH`), so on **this** box we got away with it. On a machine
without that env var set, the full 128 k request stands. That is a latent
performance cliff for anyone who downloads this.

**Fix:** size the window to the conversation — measure the prompt, round up,
clamp to something sane (8–16 k). Never ask for the model's maximum.

## 3. Prefill is not the problem; generation is

Controlled A/B against Ollama directly, same prompt, same model, warm:

| num_ctx | prompt tokens | prompt_eval | eval | tok/s |
|---------|---------------|-------------|------|-------|
| 128000  | 319 | 0.11 s | 17.3 s | 8.9 |
| 8192    | 319 | 0.15 s | 36.3 s | 6.2 |
| 4096    | 319 | 0.16 s | 50.7 s | 5.9 |

Read this carefully: **the wall-clock differences here are output length, not
speed** (154 / 224 / 297 tokens) — the runs are not comparable on wall time, and
the tok/s spread is within the noise of a card being shared with ComfyUI. The
one solid conclusion is the first column: **prompt evaluation is ~0.15 s.**

So time-to-first-token is *not* being spent on the prompt. Whatever the player
waits for, it is not prefill — which means **prompt-shrinking and prefix-cache
work are not where the win is.** Worth knowing before optimising the wrong end.

## 4. Prefix caching: real, but not our bottleneck

Ollama does reuse the KV cache for a shared prompt prefix, which is the normal
multi-turn shape (history stays, one message is appended). Our history *is* a
stable prefix, so this already works for us.

One thing that would hurt it if prefill ever mattered: `Composer.envelope()`
rebuilds a large block every turn — sheet, scene, clock, inventory, spells,
chronicle recall, codex, cast, quests, protocol — and puts the volatile parts
(HP, scene, clock) near the **top**, with the big static `PROTOCOL` block at the
bottom. If we ever need prefill wins, the move is to hoist everything static
into the system message and leave only volatile state next to the player's line.
**Not worth doing today** — 0.15 s is 0.15 s.

## 5. What is left unproven

Being honest about the edge of the evidence:

- The `45.09 s` and `68.25 s` figures in UIPolish B8 come from
  `src.llm_core - LLM async call … succeeded`, which is the **non-streaming**
  helper. The narration route uses `stream_llm_with_fallback`. Those numbers may
  therefore be a background extractor, not the narration itself. **The
  narration's own timing is not yet instrumented** — that is the next thing to
  measure, not to guess at.
- The client is genuinely built to stream (`Api.sse_delta → _on_delta`) and its
  language gate opens after only 40 visible characters, so the client is not
  what withholds the reply. If the player still sees one static line for the
  whole turn, the tokens are not arriving — worth confirming against the SSE
  directly before changing anything.

## 6. The plan, in order of (win ÷ effort), all portable

**P1 — Give the LLM the card when it loads.** The single biggest lever. Ollama
fixes its GPU split at load time, so what matters is the VRAM free *at that
moment*. Free the image stack before the model loads (ComfyUI unload endpoint),
or load the LLM first and keep it resident. Verify with `/api/ps`: `size_vram`
should equal `size`. Works everywhere — the check is a ratio, not a number.

**P2 — Stop asking for the model's maximum context.** Size `num_ctx` from the
actual prompt, clamped to 8–16 k. Costs nothing on machines that were clamping
anyway; prevents a cliff on machines that were not.

**P3 — Pick the model from *free VRAM*, not from a hard-coded name.** Today
`auto_gm_model()` picks the largest model ≤9 B, which is right for this box and
wrong for an 8 GB laptop. It should ask the host what fits: read free VRAM,
subtract KV-cache headroom, choose the largest model that fits **entirely** on
the GPU, and fall back to a small one rather than half-offloading a big one.
A fully-resident 3 B beats a half-offloaded 8 B by a wide margin.

**P4 — Ship the Ollama env the stack wants.** `OLLAMA_FLASH_ATTENTION=1`,
`OLLAMA_KV_CACHE_TYPE=q8_0` (~50 % less KV memory, needs flash attention),
`OLLAMA_KEEP_ALIVE=30m`, `OLLAMA_CONTEXT_LENGTH=8192`. These help every machine
and are the standard tuning set. Must be set for the friend's install too, not
just ours — i.e. they belong in the launcher, not in one pm2 config.

**P5 — Instrument the narration path** (§5) before optimising it further. One
log line with TTFT and tok/s per turn ends all guessing.

**P6 — Cap the reply.** GM turns run 3–4 paragraphs with no `num_predict`
ceiling. At 6–9 tok/s, 300 tokens *is* the 45 seconds. Shorter beats are both
faster and better pacing — this may be the cheapest real win after P1.

**P7 — Make the wait honest.** Whatever the floor turns out to be, the player
currently gets one static grey line. Stream visibly, show elapsed time, and let
them queue the next action.

## Sources

- [Ollama Performance Tuning: Batching, KV Cache, and OOM](https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/)
- [Ollama VRAM Requirements: 2026 Guide](https://localllm.in/blog/ollama-vram-requirements-for-local-llms)
- [Optimizing Ollama VRAM Settings with KV cache quantization](https://blog.peddals.com/en/ollama-vram-fine-tune-with-kv-cache/)
- [KV Cache System — ollama/ollama (DeepWiki)](https://deepwiki.com/ollama/ollama/5.3-kv-cache-system)
- [Prefix caching — LLM Inference Handbook](https://bentoml.com/llm/inference-optimization/prefix-caching)
