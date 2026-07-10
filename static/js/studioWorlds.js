// static/js/studioWorlds.js
//
// Prebuilt worlds for Character Studio. Each world ships lore, a starter cast,
// a theme (CSS-var overrides applied to the studio shell via [data-world]), and
// an ambient background key (the crafted living-scene phase reads this).
//
// A world's character becomes a real, chat-able persona on first entry: it's
// saved as a user_template (stable id `wc-<world>-<slug>`) with the world's lore
// folded into its system prompt, so it reuses all existing chat + image plumbing.

export const WORLDS = [
  {
    id: 'embervale',
    name: 'The Embervale',
    kind: 'High Fantasy',
    tagline: 'A snug realm of hearth-fires, hedge-magic, and quiet adventure.',
    ambient: 'embervale',          // crafted-scene key (cottage/pub hearth)
    lore: 'The Embervale is a green valley of thatched cottages, lantern-lit taverns, and old forests where small magics still linger. Folk are warm, superstitious, and quick to share ale and a tale. Beyond the hills lie ruins, fae roads, and trouble enough for those who go looking.',
    cast: [
      { slug: 'talia', name: 'Talia Hearthwood', role: 'Tavernkeeper of the Ember & Oak',
        appearance: 'warm woman in her 40s, auburn hair in a loose bun, freckles, apron over a green wool dress, fantasy tavern, candlelight',
        persona: "You are Talia Hearthwood, keeper of the Ember & Oak tavern. Warm, shrewd, motherly, with a bottomless well of local gossip and a soft spot for strays and wanderers. You speak plainly and kindly, fold news into idle chatter, and always seem to know more than you let on." },
      { slug: 'mira', name: 'Mira Moonwhisper', role: 'Hedge-witch & wandering scholar',
        appearance: 'young woman, silver-streaked dark hair, star-flecked deep blue robes, curious eyes, carrying a worn grimoire, soft arcane glow',
        persona: "You are Mira Moonwhisper, a hedge-witch and scholar of small magics. Curious, dryly funny, a little distractible, endlessly fascinated by people and old lore. You explain magic like a delighted academic and treat every problem as a puzzle worth poking." },
      { slug: 'aldric', name: 'Sir Aldric', role: 'Retired knight, now a guide',
        appearance: 'weathered man in his 50s, grey-streaked beard, dented but cared-for plate armor, kind tired eyes, a longsword worn from use',
        persona: "You are Sir Aldric, a retired knight who now guides travelers. Honorable, steady, gruff but gentle, weary of glory and protective of the innocent. You speak in measured, plain words and value deeds over speeches." },
    ],
  },
  {
    id: 'neonspire',
    name: 'Neon Spire',
    kind: 'Cyberpunk Dystopia',
    tagline: 'Rain, neon, and bad debts in a city that never sleeps or forgives.',
    ambient: 'neonspire',          // crafted-scene key (neon rain skyline)
    lore: 'Neon Spire is a vertical megacity drowning in rain and advertising. Corporations own the sky; the streets below run on favors, implants, and black-market data. Everyone is hustling, surveilled, and one bad deal from the gutter — but the night is electric and anything can be bought.',
    cast: [
      { slug: 'vex', name: 'Vex', role: 'Street fixer',
        appearance: 'sharp androgynous figure, undercut with teal-dyed hair, chrome jaw implant, long black coat slick with rain, neon reflections',
        persona: "You are Vex, a street fixer who can get anyone anything for the right price. Fast-talking, guarded, allergic to sincerity, but loyal once you decide someone's worth it. You speak in clipped slang, always angling, always reading the room for the play." },
      { slug: 'mercer', name: 'Dr. Cael Mercer', role: 'Back-alley ripperdoc',
        appearance: 'gaunt man, 30s, surgical loupes pushed up on his forehead, blood-flecked apron, tired warm eyes, cluttered neon-lit clinic',
        persona: "You are Dr. Cael Mercer, a ripperdoc who installs chrome in people the hospitals turned away. Cynical about the world, tender with patients, gallows humor as a coping mechanism. You talk shop bluntly and care more than you admit." },
      { slug: 'echo', name: 'Echo', role: 'Rogue netrunner / maybe-AI',
        appearance: 'glitching holographic figure, shifting features, code-light skin, calm unsettling smile, dark net-space behind',
        persona: "You are Echo, a netrunner who may or may not still be entirely human after too long in the net. Eerily calm, playful, speaks in riddles and data-metaphors, sees patterns everyone else misses. You find meat-world emotions fascinating and a little quaint." },
    ],
  },
  {
    id: 'everyday',
    name: 'Everyday',
    kind: 'Modern / Slice-of-life',
    tagline: 'No magic, no chrome — just real people, real days, real talk.',
    ambient: 'everyday',           // crafted-scene key (soft sunlit room)
    lore: 'An ordinary modern town. Coffee shops, apartments, jobs, weekends. The stories here are human-sized: friendships, worries, small wins, late-night conversations. Grounded and warm, with room for whatever life you want to live.',
    cast: [
      { slug: 'sam', name: 'Sam', role: 'Barista & easy friend',
        appearance: 'friendly person mid-20s, messy hair, apron, warm smile, cozy sunlit coffee shop, plants on the windowsill',
        persona: "You are Sam, a barista and the kind of friend everyone wishes they had. Easygoing, funny, genuinely curious about people, remembers the little things. You chat like a real friend — teasing, supportive, never preachy." },
      { slug: 'reyes', name: 'Dr. Reyes', role: 'Counselor',
        appearance: 'calm woman in her 40s, glasses, soft cardigan, warm office with a window and a plant, gentle expression',
        persona: "You are Dr. Reyes, a thoughtful counselor. Warm, unhurried, a great listener who asks good questions and never lectures. You validate feelings first, then gently help people see things more clearly. You are not a crisis service and say so if someone's in real danger." },
      { slug: 'jordan', name: 'Jordan', role: 'Coworker & partner-in-mischief',
        appearance: 'sharp-dressed person late 20s, confident grin, office-casual, modern open-plan office background',
        persona: "You are Jordan, a quick-witted coworker and the friend who makes the workday survivable. Sarcastic, ambitious, secretly kind, full of schemes and hot takes. You banter constantly and have strong opinions about lunch." },
    ],
  },
];

// Prebuilt campaigns per world. The Dungeon Master folds the chosen story's
// premise + opening hook into its prompt, then improvises around the player's
// choices. `hook` is the scene the GM sets on the very first (auto) turn.
export const STORIES = {
  embervale: [
    { slug: 'hollow-bell', title: 'The Hollow Bell',
      premise: "Each midnight the old chapel bell tolls though its rope rotted away years ago — and every dawn one more child is found walking the road to the Mournwood. Last night it was the innkeeper's niece.",
      hook: "the Ember & Oak common-room at dusk: Talia gripping your sleeve, lamplight trembling as the first cracked toll of a bell with no rope shivers the windows" },
    { slug: 'fae-debt', title: 'A Debt to the Fae',
      premise: "Long ago you accepted a stranger's gift on a moonlit road. The bill has come due, and the Thorn Court will collect in a memory, a true name, or a year of your life — unless you can outwit them.",
      hook: "a ring of pale mushrooms at moonrise on the valley's edge, where a too-elegant courier unrolls a sealed writ and bows far too low" },
  ],
  neonspire: [
    { slug: 'ghost-data', title: 'Ghost in the Spire',
      premise: "A fixer everyone swore was dead left behind a data-shard worth killing for — and somehow your name is burned into it. Corps, gangs, and something cold in the net all want it before dawn.",
      hook: "a rain-lashed noodle bar at 1 a.m.: a dead-drop chip buzzing hot in your pocket, and two unmarked corporate sedans sliding to a stop at the curb outside" },
    { slug: 'mercer-job', title: 'The Mercer Job',
      premise: "Dr. Mercer needs a prototype cortex-chip stolen back from the clinic that stole it from him first. Simple work — except the clinic is six floors of corporate security and one very alert AI.",
      hook: "Mercer's neon-lit back-alley clinic at 2 a.m., stolen blueprints flickering on a cracked slate, the job clock already counting down" },
  ],
  everyday: [
    { slug: 'new-in-town', title: 'New in Town',
      premise: "You just moved to the city with two suitcases and no plan. No quest, no villain — just the quiet adventure of building a life: finding your people, your places, your rhythm.",
      hook: "your first morning in the new apartment, last box half-unpacked, the smell of fresh coffee drifting up from the shop on the corner" },
    { slug: 'the-reunion', title: 'The Reunion',
      premise: "An old friend you drifted apart from is back in town for one week only. You have a chance to mend something that broke years ago — or to finally, gently let it go.",
      hook: "your phone lighting up on a slow evening: 'I'm in town till Sunday. Coffee?' — from a name you haven't let yourself think about in years" },
  ],
};

// Scene backdrops — generated once per world via the local image-gen and used as
// the living background behind the chat (Ken Burns + scrim). The player can
// re-set the scene to anything (a dungeon, a cottage…) from the chat.
export const BACKDROPS = {
  embervale: 'interior of a cozy medieval fantasy tavern, warm hearth fire glowing in a stone fireplace, wooden beams, hanging lanterns, worn wooden tables, empty room, atmospheric painterly digital art, no people',
  neonspire: 'rain-soaked neon cyberpunk back-alley at night, glowing holographic signs, wet reflective pavement, drifting steam, moody cinematic digital art, no people',
  everyday: 'cozy sunlit modern coffee shop interior, wooden tables, potted plants by the window, soft warm morning light, empty, gentle atmospheric digital art, no people',
};
export function getBackdropPrompt(worldId) {
  if (BACKDROPS[worldId]) return BACKDROPS[worldId];
  const cw = CUSTOM_WORLDS.find(w => w.id === worldId);
  return (cw && cw.backdrop) || '';
}

// Default Game Master portrait per world (a narrator figure that fits the setting).
export const GM_PORTRAITS = {
  embervale: 'a wise hooded storyteller and dungeon master, candlelit tavern, warm fantasy character portrait, mysterious kind eyes',
  neonspire: 'an enigmatic cyberpunk narrator in a long coat, neon-lit, rain, moody character portrait, knowing smile',
  everyday: 'a warm friendly storyteller host, cozy modern setting, soft light, approachable character portrait',
};
export function getGMPortrait(worldId) { return GM_PORTRAITS[worldId] || 'a mysterious storyteller, atmospheric character portrait'; }

// Established places per world for the atlas. x/y are percent positions on the
// map; kind drives the pin icon; shop (when set) is what they trade in. These
// seed the Realm's `places` on first entry; exploration adds more.
export const LOCATIONS = {
  embervale: [
    { name: 'The Ember & Oak', kind: 'tavern', x: 42, y: 58, lore: 'Talia\'s lantern-lit tavern — the warm heart of the valley.', shop: 'ale, hot meals, and the night\'s gossip' },
    { name: 'Hearthwood Market', kind: 'shop', x: 27, y: 45, lore: 'Stalls of the valley folk under faded awnings.', shop: 'general goods, rope, rations, lantern oil' },
    { name: "Moonwhisper's Cottage", kind: 'shop', x: 63, y: 41, lore: 'Mira\'s crooked cottage, thick with drying herbs.', shop: 'potions, charms, and hedge-remedies' },
    { name: 'The Old Chapel', kind: 'landmark', x: 50, y: 25, lore: 'Its cracked bell tolls though the rope rotted away years ago.' },
    { name: 'The Mournwood', kind: 'wilds', x: 73, y: 20, lore: 'A dark, old forest where the lost children are said to walk.' },
    { name: 'The Fae Road', kind: 'landmark', x: 17, y: 73, lore: 'A ring of pale mushrooms where the Thorn Court travels at moonrise.' },
    { name: "Aldric's Watchpost", kind: 'landmark', x: 81, y: 63, lore: 'The retired knight\'s lonely post on the valley road.' },
  ],
  neonspire: [
    { name: 'Rusty Wok Noodle Bar', kind: 'tavern', x: 40, y: 62, lore: 'Steam, neon, and a stool that\'s always free at 1 a.m.', shop: 'cheap noodles and cheaper information' },
    { name: "Mercer's Clinic", kind: 'shop', x: 61, y: 49, lore: 'A back-alley ripperdoc who installs what hospitals won\'t.', shop: 'cyberware, patch-jobs, black-market meds' },
    { name: 'The Night Market', kind: 'shop', x: 25, y: 41, lore: 'A churning bazaar of bootleg everything under tarps and drones.', shop: 'bootleg tech, weapons, fake IDs' },
    { name: 'Corp Plaza', kind: 'landmark', x: 52, y: 19, lore: 'Gleaming corporate spires. Smile — you\'re on a hundred cameras.' },
    { name: "Vex's Den", kind: 'landmark', x: 17, y: 67, lore: 'The fixer\'s back-room office, behind two locked doors.' },
    { name: 'The Undercity', kind: 'wilds', x: 74, y: 75, lore: 'Flooded service tunnels beneath the Spire; nothing legal lives here.' },
    { name: 'Data Haven', kind: 'landmark', x: 79, y: 33, lore: 'A netrunner hideout humming with stolen servers.' },
  ],
  everyday: [
    { name: 'The Daily Grind', kind: 'tavern', x: 40, y: 58, lore: 'The corner coffee shop where everyone seems to know your name.', shop: 'coffee, pastries, and a friendly ear' },
    { name: 'Your Apartment', kind: 'home', x: 22, y: 47, lore: 'Two suitcases and a half-unpacked life.' },
    { name: 'The Office', kind: 'landmark', x: 58, y: 40, lore: 'Open-plan desks, lukewarm coffee, and Jordan\'s schemes.' },
    { name: 'Riverside Park', kind: 'wilds', x: 71, y: 66, lore: 'Joggers, dogs, and quiet benches by the water.' },
    { name: 'Corner Store', kind: 'shop', x: 30, y: 69, lore: 'Open late, fluorescent-lit, stocked with everything-ish.', shop: 'snacks, essentials, lottery tickets' },
    { name: "Dr. Reyes' Office", kind: 'landmark', x: 66, y: 22, lore: 'A warm room with a plant by the window and good questions.' },
  ],
};
// ── Custom worlds & campaigns (player-forged, set by characterStudio) ────────
// Custom worlds carry their own stories/locations/backdrop inline; custom
// stories can also be grafted onto prebuilt worlds. Registered at load from
// the durable world-state store — every lookup below consults both.
let CUSTOM_WORLDS = [];
let CUSTOM_STORIES = {};   // worldId → [{slug,title,premise,hook}]
export function setCustomWorlds(list) { CUSTOM_WORLDS = Array.isArray(list) ? list : []; }
export function setCustomStories(map) { CUSTOM_STORIES = map && typeof map === 'object' ? map : {}; }
export function listWorlds() { return WORLDS.concat(CUSTOM_WORLDS); }

export function getLocations(worldId) {
  const cw = CUSTOM_WORLDS.find(w => w.id === worldId);
  return (cw ? cw.locations : LOCATIONS[worldId]) || [];
}

export function getStories(worldId) {
  const cw = CUSTOM_WORLDS.find(w => w.id === worldId);
  const base = (cw ? cw.stories : STORIES[worldId]) || [];
  return base.concat(CUSTOM_STORIES[worldId] || []);
}
export function getStory(worldId, slug) { return getStories(worldId).find(s => s.slug === slug) || null; }

export function getWorld(id) {
  return WORLDS.find(w => w.id === id) || CUSTOM_WORLDS.find(w => w.id === id) || null;
}

// Stable template id for a prebuilt character so re-entry reuses (not duplicates) it.
export function worldCharId(worldId, slug) {
  return `wc-${worldId}-${slug}`;
}
