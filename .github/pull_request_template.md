## Summary

<!-- One paragraph: what changed and why. "Fixed bug" and "Added feature" are not summaries. -->

## Linked issue

<!-- Fixes #NNN  |  Part of #NNN  |  Closes #NNN -->

Fixes #

## Type of change

- [ ] Bug fix (non-breaking — fixes a confirmed issue)
- [ ] New feature (non-breaking — adds new behaviour)
- [ ] Breaking change (changes or removes existing behaviour)
- [ ] Refactor / cleanup (behaviour unchanged)
- [ ] Documentation only
- [ ] CI / tooling / configuration

## Harnesses

Paste the last line of each run. Say so if you could not run one.

- [ ] `self_check` → `SELF-CHECK OK`
- [ ] `click_driver` → `CLICKDRIVE OK`
- [ ] `ui_playthrough` → `PLAYTHROUGH OK`
- [ ] `local_stack` / `bench_gm` — **required if this touches a model call**
- [ ] Re-exported the exe and played it. A stale Desktop build gets tested by mistake.

```
<paste harness output here>
```

## How to test

<!-- Step-by-step instructions a reviewer can follow. Do not leave this empty. -->

1.
2.
3.

## Visual changes — REQUIRED if you touched anything that renders

The harnesses assert screens are *reachable*. They do not assert a screen is
*right*. If this changes what the game looks like, all of the following:

- [ ] **Screenshot** of the change in the running game, attached below.
- [ ] **Tokens only** — colours, spacing and radii come from `Ui`. No new literals.
- [ ] **No emoji.** Functional glyphs come from `ui/myth_icon.gd`.
- [ ] **No parallel component.** Extend the `Myth*` one that already exists.
- [ ] Reduce-motion still has an out.

If you are unsure whether a change is visual, it is.

### Screenshots

<!-- Drag and drop here. -->

## The rules this change did not break

- [ ] The model still cannot state a roll, an HP total or a success — every
      mechanical effect goes through a typed tag handler.
- [ ] No new fallback path. A missing model fails honestly and loudly.
- [ ] No model call both invents and serialises.
