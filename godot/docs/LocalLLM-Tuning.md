# Tuning the local model — what is actually true on this box

Everything here was measured against `llama3.1-8b-instruct-q4` on the RX 7900 GRE
through NobodyWho (llama.cpp / Vulkan), not inferred. Where a claim is inherited
from someone else's benchmark it says so.

## 1. The finding that matters most: you cannot combine a grammar with a sampler

`set_sampler_config()` and `set_sampler_preset_*()` **replace each other
wholesale**. Four arms, same prompt, same schema, reading the resulting
`SamplerConfig` out of the worker log rather than guessing:

| what was called | config the worker ended up with | output |
|---|---|---|
| schema preset only | `steps:[JsonSchema], sample_step:Dist` | valid JSON |
| chain, then schema preset | `[JsonSchema]` — chain gone | valid JSON |
| schema preset, then chain | `[TopK, TopP, Temperature, Penalties]` — schema gone | markdown prose |
| chain only | `[TopK, TopP, Temperature, Penalties]` | markdown prose |

So a grammar-constrained call runs with **no top-k, no top-p, no temperature and
no repetition penalty** — pure sampling from the raw distribution. There is no
supported way to have both. `NobodyWhoSamplerBuilder` confirms it: it exposes
`top_k`, `top_p`, `min_p`, `xtc`, `typical_p`, `temperature`, `dry`, `penalties`,
`seed` and the terminals `dist`/`greedy`/`mirostat_v1`/`mirostat_v2` — and **no
grammar step at all**.

## 2. What that does, and where the cliff is

Raw-distribution sampling is fine while the model is confident and falls apart
when it is not. A three-key schema produced this, first try, 2559 ms:

> *Aquari — "Where the paths of the living converge with the peace of the
> departed."*

The world-core schema — six keys, one of them an array of 5–7 four-key objects —
produced **grammar-valid word salad** at 84 tok/s:

> *births freely Attendance ensemble span mind plague UlTouch mice coated farmer
> collapsed earners artifacts worm presidents civilized Worth Yep editorial*

Same model, same sampler, same session. The difference is how much of the answer
sits at low confidence: every nested object is another stretch where the tail of
the distribution can win, and once it derails it stays derailed.

This is not a local quirk. The literature calls it **premature serialization** —
forcing schema-compliant tokens before the model has finished reasoning — and
reports that capacity-limited models (8B and under) take a large penalty from it
while larger models absorb it. It predicts exactly what was observed: short
extractions survive, long generative asks do not.

## 3. The rule that follows

**Never ask one grammar-constrained call to both invent and serialise.**

Split it in two, and use each config for the thing it is good at:

1. **Think** — free prose, `set_sampler_config(top_k 40, top_p 0.95, temp 0.7,
   penalties 64/1.1)`. This is the arm that wrote *"Elyria's Repose — where the
   waves whisper respect to the departed"* in 1973 ms.
2. **Serialise** — `set_sampler_preset_constrain_with_json_schema(...)` over the
   prose from step 1. Extraction is a low-entropy task, which is the regime where
   `Dist` is safe, and it is what codex/quests/world-tick already do reliably.

Two calls at ~2 s each beat one call that fails at 98 s. It also sidesteps the
"cannot combine" limitation entirely rather than fighting it.

**The prose prompt must now describe the shape.** This is the part that is easy
to miss: with the schema no longer steering generation, a prompt written as
*"write `flavor`, `slots` and `names`"* is being read by a model that cannot see
what those are. Asked that way, it produced a flavor and a slots term **per
class**, twelve of each — a fair reading of the words it was given. Spelling the
answer out as *"PART 1 … PART 2 … PART 3, all twelve classes one per line, in
this order"* is what the schema used to do implicitly. Write prose prompts for a
reader, not for a serialiser.

## 4. `maxLength` is worse than useless here

A JSON-Schema `maxLength: N` is compiled to `char{0,N}` in GBNF. llama.cpp's own
grammar guide warns that large repetition counts cause *"extremely slow
sampling"*, and there are open issues where `maxLength >= ~2000` emits GBNF that
llama.cpp's **own parser then rejects** (`number of repetitions exceeds sane
defaults`).

`lore` was declared `maxLength: 1200` — a 1200-repetition rule bought for nothing,
since the answer is clamped in code anyway. Declare bounds in code, not in the
grammar. (Grammar-constrained generation is inherently slower regardless: one
reported measurement is 25.85 → 13.38 tok/s.)

## 5. Context: raising it does not fix a bad answer

`NobodyWhoChat.context_length` is per-node and settable. Structured calls need
more than conversational ones because the whole answer is one message with
nothing to evict — when it overruns, the error is misleading:

```
Error during context shift: Context shift failed: not enough messages to shift
help: The message fits in the context but there is not enough room left for the
      response. Either shorten the message or increase n_ctx.
```

That reads like "the context is too small", and it is — but only because the
model was generating garbage that never terminated. Going 8192 → 16384 turned a
98-second failure into a 180-second one. **Fix the answer, then size the context.**

## 6. Failure modes that produce no error at all

- A generation that overran its context **hung** — no `response_finished`, and
  `worker_failed` only fires for some faults. Anything awaiting a single signal
  deadlocks. Await every outcome and carry a deadline.
- `start_worker()` is **asynchronous**. Configuring the sampler before the worker
  is up logs `Worker not started, dropping sampler config` — a *warning* — and
  the call then runs **unconstrained**. Any test that does this is silently
  measuring the wrong thing.
- A wedged worker cannot be reasoned about. Free the node and rebuild it; that
  also disconnects its signals, so a late answer cannot be handed to whichever
  call is waiting next.

## 7. Settled numbers

| call | time |
|---|---|
| GM turn, warm | 3.7 s |
| campaign memory: store 3 beats / recall | 228 ms / 4 ms |
| codex extraction | 1165 ms |
| quest log extraction | 1387 ms |
| world tick | 1629 ms |
| small schema (3 keys) | 2559 ms |
| free prose, tuned chain | 1973 ms |
| `set_sampler_preset_json()` (no schema) | 4798 ms, **does not parse** — still fenced |

`set_sampler_preset_json()` is not the constraint its name suggests. Either pass
a real schema or plan to extract.
