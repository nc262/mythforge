---
name: next
description: Take the next item off Mythforge's backlog and carry it all the way to a green gate and a commit, without asking what to do next. Use when the user says "next", "/next", "keep going", "continue", "what's next", or asks for the development loop to run itself. Also the body of `/loop /next` for unattended runs.
---

# /next — pull one item, finish it, prove it

**The point of this skill is that it does not ask.** The user does not want to
be a scheduler. Pick the work, do the work, prove the work, record the work,
pick again. Stop only for the short list in *When to actually ask* below.

## 0. Am I on the live branch?

Before reading the backlog, `git worktree list`, and for every other local
branch `git rev-list --left-right --count HEAD...<branch>`. **If another branch
is ahead, stop and say so** — its Backlog is the real one. On 2026-11-02 a
session on `master` re-fixed PL-7 and re-ran the PL-10 bisection, both solved
in August on a worktree branch 111 commits ahead and unpushed since Aug 6.
After merging one in, run the gate with `-Import`: the class cache predates the
merge and cannot see the new `class_name`s.

## 1. Pick

The queue is [godot/docs/Backlog.md](../../../godot/docs/Backlog.md) — the one
list of open work. Take the highest **P**, breaking ties with the smaller **E**.
Skip anything whose blocker is named and still true.

If the backlog is empty of P1–P3, do not invent a feature. In order:
`KnownIssues.md` → `TechnicalDebt.md` → the coverage gaps in `Testing.md`.
Those three are stocked, and each item already carries its own reason.

Say in one line which item you took and why it was next. Then go.

## 2. Work it

`DISCOVER → PLAN → CHALLENGE → EXECUTE → VERIFY → REVIEW → IMPROVE`, and the
repo's own standards apply — read the relevant `godot/docs/*.md` first, follow
[docs/code-style.md](../../../docs/code-style.md), reuse the pattern that is
already there.

**CHALLENGE is not decoration.** Before writing anything, state the one way this
change could be the wrong fix. This repo's history is mostly bugs whose filed
mechanism was wrong — eight of the last audit's rows were mis-reported, and the
only ones caught were rendered or measured rather than reasoned about.

## 3. Answer your own questions

When you hit an unknown, the default is **research, not ask**. The user has said
plainly: nineteen times out of twenty you already know, and the twentieth a
search answers better than they could.

- **Unknown about the codebase** → `Explore` agent, or just read it.
- **Unknown about the world** — an API, a format, a Blender operator, what other
  people did about this exact failure → the `researcher` agent.
- **Unknown about behaviour** → *measure it*. Render it, print it, count pixels.
  Reading the code told the wrong story five of the last dozen times.

**MEASURE FIRST — this is the one rule that is not negotiable.** Before you write
a fix, say the measurement that identifies the cause: the number, the log line,
the printed value. If you cannot name one, **getting the instrument is the task**
and the fix comes after. Then:

- **Prove the instrument runs before trusting it.** A `print()` inside a hook
  that never fires reads exactly like a hook that fires and finds nothing.
- **A fix that does not move the number is not a fix.** Revert it. Never leave it
  behind a comment claiming otherwise.
- **Do not reason from the same weak evidence twice.** One inference from a
  screenshot is a guess; two is a habit, and the second is the real mistake.
- **Write the negative result into the backlog row** before moving on.

Write the answer down where it will be found again: an RCA in
[docs/troubleshooting.md](../../../docs/troubleshooting.md) for a
symptom → cause → fix, a comment at the code for a negative result. A negative
result is worth keeping — "PROJECT produced a byte-identical .bin" saves the
next person the same afternoon.

## 4. Prove it

```bash
pwsh scripts/verify.ps1
```

That runs the offline gate, exports, and puts the exe on the Desktop. **Run it
with the sandbox disabled** — the Desktop copy writes outside the repo, and a
sandboxed run fails at the last step with the gate otherwise green. Add
`-Full` when the change touches a model call, `-Audit` when it touches anything
that renders a body. **Never** hand-run a subset and call it green.

**Leave a check behind that fails if the bug returns**, and prove it fails by
reverting the fix and watching it go red. A fix without that is not finished.
Assert what the *failure* looks like — three metrics in this repo's history
scored broken output as fine.

## 5. Record and go again

- Commit. The message says what changed and *what it now proves*, in the voice
  the log already uses.
- Update `Backlog.md`: delete the finished row (the code is the record of what
  shipped), or rewrite it with what was actually learned if it survived.
- Then **take the next item without being asked**. Keep going until a stop
  condition below fires.

## Stop conditions

Stop the loop — do not keep pulling — when any of these is true:

1. **Three failed attempts on one item.** Do not chase a fourth. Write what was
   ruled out into the backlog row and move to the next item.
2. **The gate is red and the cause is not the current change.** A pre-existing
   failure is its own item; file it and stop rather than fixing two things at
   once.
3. **The next item needs one of the answers below.**
4. Nothing left in Backlog, KnownIssues, TechnicalDebt, or the Testing gaps.

## When to actually ask

The whole list. Anything not on it, decide yourself and say what you decided.

- **Taste that cannot be measured.** Whether a silhouette, a colour, or a line
  of GM prose is *good*. A pixel count is not an opinion about art direction.
- **Anything irreversible or outward-facing** — publishing or modifying a
  release, a force-push, deleting saves, anything a stranger downloads.
- **Money, or a new dependency** — a paid service, a new runtime, a multi-GB
  model download, anything that adds a process to the machine.
- **Scope that is not on any list**, or an item whose real cost turns out to be
  many times its filed effort. Ship the small honest version and say so.
- **A windowed GPU render, and any second heavy job.** llama.cpp fixes its
  GPU/CPU split at load time and this machine has frozen once already under a
  windowed render plus a headless harness plus a Blender bake. One heavy job at
  a time, and ask before the windowed ones.
- **Killing a process you did not start.** Ever.

Ambiguity that is *not* on this list is yours to resolve: pick the reading a
careful colleague would, state the assumption in one line, and build it.

## Unattended

`/loop /next` runs this on a self-paced timer. Under `/loop`, treat every "ask"
above as a **stop** instead: park the item, write down the question, and end the
loop cleanly rather than guessing at a decision that was the user's to make.
