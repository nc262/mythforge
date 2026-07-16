# Ritual: Opening the Journal

*U4a — the quest journal. Emotions: purpose · history · mystery.*

## 1. Experience

A handwritten manuscript — your chronicler's record of the tale so far.
Quests are sworn in wax: an unbroken red seal for the open ones, a gray
broken seal struck through for the finished. The people you've met sit
beside their painted faces like a portrait gallery in the margins. Closed
chapters end with a fleuron, the way old books close their sections.
Reading it should feel like discovering the history of your own story.

## 2. Beats

Anticipation: the shared window ritual (world dims). Reveal: the manuscript
on parchment. Focal point: open quests, wax-red, first. Interaction: tabs
(All / Quests / People / Chapters) + search that cuts across everything.
Reward: recognizing your own history assembled. Exit: close the journal.

## 3. UX flow

- Tabs are radio GhostButtons; search filters within the active tab.
- Quest entry: wax seal ◉ (danger red = open, dim + strikethrough = done),
  title in serif weight, description as indented italic prose.
- People: painted portrait (the codex art) beside name · role, note beneath.
- Chapters: ❦ fleuron + chapter title + its opening lines.
- Empty search: "the story hasn't written that yet."

## 4. Wireframe

```
┌── 📖 The Journal ───────────────────────────┐
│ [All][Quests][People][Chapters]  [search…]  │
│  ────  ✦  QUESTS  ✦  ────                   │
│  ◉  The Hollow Bell Tolls                   │
│      find who rings the drowned chapel bell │
│  ◉̶  ~~Rats in the Cellar~~        (done)    │
│  ────  ✦  PEOPLE  ✦  ────                   │
│  (🙂) Talia · innkeeper                      │
│       keeps the Ember & Oak, knows everyone │
│  ────  ✦  CHAPTERS  ✦  ────                 │
│  ❦ Chapter One — the bell at midnight…      │
└─────────────────────────────────────────────┘
```
