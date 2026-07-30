# The World Forge — why it feels cookie-cutter, and what to do instead

## What it does today

`scenes/forge/world_forge.gd`, four stages:

1. **The Spark** — a name `LineEdit` and an idea `TextEdit`, both blank.
2. **The Pillars** — 8 theme cards, then 5 fixed axes: *Magic system, Technology,
   Era & timeline, Beast variants, Tone*, each with 4–6 fixed options.
3. **The Forging** — strike, refine, seal.
4. **The Atlas** — reveal.

The bones are good — staged, themed, no modal soup. Two things make every world
come out feeling like a sibling of the last one.

**The blank box asks for the hardest thing first.** "Describe your world" in an
empty text area is the blank-page problem in its purest form. Most players type a
genre label — *"dark fantasy with dragons"* — which carries almost no information
the theme card did not already carry.

**The five axes never change.** Every world, forever, is defined by the same five
questions with the same options. That is a *taxonomy*, and a taxonomy has a fixed
number of leaves — 6 × 5 × 5 × 5 × 4 = 3,000 combinations, most of which produce
near-identical prompts. Worse, the axes are the same whether you picked Pirates or
Steampunk, so "Beast variants" offers *Dragons & their kin* to a cyberpunk world.

## The principle: constraint is not the enemy of creativity, blankness is

Structured worldbuilding tools exist precisely to beat worldbuilder's block, and
guided prompt flows are the recommended answer to the blank page rather than a
compromise with it. Meanwhile, cold-start preference elicitation — the same
problem Spotify solves at signup — has a consistent finding: **forced choice
beats free text**, eliciting preferences over *attributes* beats eliciting them
over whole items, and **pairwise comparison carries more signal than rating a
single thing**. The counterweight is equally consistent: ask too many questions
and people bail.

So the goal is not "more questions." It is **fewer, sharper, and different every
time.**

## Six changes, in the order I would do them

**1, 2 and 4 have shipped** (`scenes/forge/world_questions.gd`, and the Spark and
Pillars stages of `world_forge.gd`). 3, 5 and 6 are still open. `self_check`
guards the behaviour, not the wording: that two different worlds get asked
different things, that a drowned world is asked about water and a starfaring one
is not, that the conflict pair always leads, that a premise ruling out magic is
never asked what magic costs, and that every option states a rule.

### 1. Invert the Spark — choose before you describe ✅

Do not open with a blank box. Open with **six concrete, specific world premises**,
plus *"none of these — I'll describe my own."*

*Shipped as an authored pool of 18 with a "↻ different six" button, not as
generated text: generating six costs a model call at the exact moment the forge
opens, and the blank page is a latency problem as much as a creative one.
Generating a further row in the background is a later change that does not alter
the interaction.*

Not genre labels. Actual premises, the length of the placeholder text that is
already in the box:

> *A drowned Venice of sky-whales and salvage guilds, melancholy but hopeful*

Picking one is a real choice that carries more signal than most typed sentences.
Rejecting all six is also signal, and the player who wanted the blank box still
has it — one click away, now primed by six examples of the *level of specificity*
you want. This alone fixes the most common failure: a two-word idea.

### 2. Make the questions come from the answers ✅

Replace the fixed five axes with a **question pool tagged by relevance**. Each
question declares what makes it apply:

```
{ id: "magic_cost", asks_when: {magic: ["any"]},        ... }
{ id: "void_law",   asks_when: {tech: ["starfaring"]},  ... }
{ id: "what_drowned", asks_when: {premise_has: ["drowned","sunken","tide"]}, ... }
```

Ask 4–5, drawn from those that apply, and **never ask a question the premise has
already answered**. A pirate world gets asked what the sea takes; a steampunk
world gets asked what the machines cost; a cyberpunk world is never offered
dragons. Same interaction budget, radically different session.

Two questions should always be in the pool regardless of theme, because they
generate conflict rather than colour:

- **What is scarce here?** (water, iron, memory, daylight, trust, names)
- **Who decides, and who resents it?**

Those two do more for a playable world than *Technology: Medieval* ever will.

### 3. Ask for a judgement, not a category — OPEN

The highest-signal question type is **A or B, both attractive**. Not "pick your
tone from four options" — *"Which is worse: the thing in the water, or the people
who feed it?"* The player is not classifying their world, they are **making a
ruling about it**, and a ruling is a fact the GM can hold you to later.

Two or three of these are worth more than all five current axes, and they are
faster to answer.

### 4. Show the cost of every choice ✅

Each option should say what it *does*, not just what it is. `Magic system:
Forbidden & feared` is a label. *"Casting in public gets you reported"* is a rule
the player can picture and the GM can enforce. Same click, and the world arrives
already carrying consequences.

This also quietly fixes prompt quality: the option text becomes the prompt text,
so the model is handed rules rather than adjectives.

### 5. Let the forge ask ONE question back — OPEN

After the first strike, the smith should ask a single question about the thing it
was least sure of — and it genuinely knows which, because it just wrote it:

> *"I gave the tide-wardens authority over the dead. Are they trusted, or merely
> obeyed?"*

That is the moment the world stops being a form the player filled in and starts
being something they are in conversation with. One question, one round, skippable.
It is also cheap — a small extraction call over prose that already exists, which
is the regime the local model is reliable in
([LocalLLM-Tuning.md](LocalLLM-Tuning.md)).

### 6. Reveal progressively, and let it be edited in place — OPEN

The Atlas currently arrives all at once. Reveal it as it is built — name and
tagline first, then locations, then cast, then bestiary — and make each card
**click-to-reject**: *"not this one, give me another."* Rejection is the cheapest
high-signal input there is, and per-card regeneration is a small call, not another
whole world.

## What NOT to do

- **Do not add more axes.** The problem is not that five is too few, it is that
  five fixed ones are always the same five.
- **Do not make it longer.** Four to six interactions total, same as now. The
  gain comes from what is asked, not how much.
- **Do not remove the blank box.** Some players know exactly what they want and
  every gate between them and it is friction. Demote it, do not delete it.
- **Do not let the model ask open questions.** *"Tell me more about your world"*
  hands the blank page back. If the forge asks, it asks a closed question with
  two named options.

## Where this touches the code

| change | file |
|---|---|
| premise cards instead of a blank Spark | ✅ `world_forge.gd:_stage_spark` |
| question pool + relevance tags | ✅ `scenes/forge/world_questions.gd` |
| consequence text on options | ✅ options are `{pick, rule}`; the rule is what reaches the prompt |
| the smith's one question | `autoload/worldsmith.gd`, new small extraction call |
| progressive reveal, per-card reject | `scenes/forge/world_forge.gd:_stage_atlas` |

`_smith_guide()` is gone. `WorldQuestions.pick(idea, theme)` replaced it, and
the answers stored in `draft["fields"]` are now RULES rather than labels — so
what reaches the model is "casting in public gets you reported" instead of
"Magic system: Forbidden & feared".

## Note on the campaign and character forges

`campaign_forge.gd` shares this shape and would inherit the same fixes. The
character forge is a different problem — there the taxonomy is *load-bearing*,
because class and heritage have mechanical consequences. Do not "fix" it the same
way.
