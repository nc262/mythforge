// static/js/characterStudio.js
//
// Character Studio — a magical, fantasy-RPG character creator + chat tool.
// A first-class surface (its own overlay + /studio route) with three views:
//   • Roster — your characters as a grimoire of portrait cards
//   • Forge  — guided builder: portrait + persona + world, with per-field AI sparks
//   • Chat   — roleplay with a character, on the real chat_stream engine
//
// All persistence + image plumbing reuse the verified backend
// (/api/characters/studio/{generate,describe,suggest,save,activate}). The chat
// reuses /api/chat_stream so persona voice and on-model selfies work unchanged.

import * as sessionModule from './sessions.js';
import { WORLDS, getWorld, worldCharId, getStories, getBackdropPrompt, getGMPortrait, getLocations, listWorlds, setCustomWorlds, setCustomStories } from './studioWorlds.js';
import { startAmbient, setAmbient, stopAmbient } from './studioAmbient.js';
import { BESTIARY, BESTIARY_TIERS, SPELLS, CLASS_LORE } from './studioCompendium.js';

let API_BASE = '';
let _chars = [];                 // cached character templates
let _view = 'worlds';
let _chatReturnView = 'roster';   // which menu tab "‹ back" from a chat returns to
let _busy = false;
let _world = null;               // currently-selected world (for theming + cast)

// Forge working state
let _forge = { id: null, filename: '', imageUrl: '' };

// Chat working state
let _chat = { char: null, sessionId: null, abort: null, streaming: false, playAs: '' };

const SESS_MAP_KEY = 'studio-char-sessions';

function $(id) { return document.getElementById(id); }
function _esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function _loadMap() { try { return JSON.parse(localStorage.getItem(SESS_MAP_KEY) || '{}') || {}; } catch { return {}; } }
function _saveMap(m) { try { localStorage.setItem(SESS_MAP_KEY, JSON.stringify(m)); } catch {} }
function _modelLabel() { const l = $('model-picker-label'); return l ? l.textContent.trim() : ''; }
function _initial(name) { return (name || '?').trim().charAt(0).toUpperCase(); }

// Tiny, safe roleplay formatter: escapes HTML, then renders *action* italics,
// `code`, paragraphs and line breaks. Deliberately small — no external coupling.
function _rp(text) {
  let t = _esc(text || '').trim();
  t = t.replace(/`([^`]+)`/g, (_, c) => `<code>${c}</code>`);
  t = t.replace(/\*\*([^*\n]+)\*\*/g, (_, c) => `<strong>${c}</strong>`);   // bold before italics
  t = t.replace(/\*([^*\n]+)\*/g, (_, c) => `<em>${c}</em>`);
  const paras = t.split(/\n{2,}/).map(p => p.replace(/\n/g, '<br>'));
  return paras.map(p => `<p>${p}</p>`).join('');
}

// Render a "- item" / "* item" block as a real bullet list (escaped).
function _bullets(text) {
  const lines = (text || '').split('\n').map(l => l.replace(/^[-*]\s*/, '').trim()).filter(Boolean);
  if (!lines.length) return '';
  return `<ul>${lines.map(l => `<li>${_esc(l)}</li>`).join('')}</ul>`;
}

function _fmtDate(iso) {
  try { return new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }); }
  catch { return iso || ''; }
}

// ── Open / close / view switching ──────────────────────────────────────────
export async function open(toForge, worldId) {
  const modal = $('studio-modal');
  if (!modal) return;
  modal.classList.remove('hidden');
  document.body.classList.add('studio-open');
  const cv = $('studio-bg-canvas');
  if (cv) startAmbient(cv, 'arcane');
  await loadCharacters();
  await _hydrateRel();   // global store: bonds + player-forged worlds/campaigns
  if (toForge) { openForge(null); return; }
  renderWorlds();
  switchView('worlds');
  // Deep-link from the landing portals: land directly inside the chosen world.
  if (worldId) { const w = getWorld(worldId); if (w) renderWorldDetail(w); }
}

// Title-screen "Continue": jump straight back into the most recent adventure.
const LAST_ADV_KEY = 'studio-last-adventure';
export function lastAdventure() { try { return localStorage.getItem(LAST_ADV_KEY) || ''; } catch { return ''; } }
export async function continueLast() {
  const modal = $('studio-modal'); if (!modal) return;
  modal.classList.remove('hidden');
  document.body.classList.add('studio-open');
  const cv = $('studio-bg-canvas'); if (cv) startAmbient(cv, 'arcane');
  await loadCharacters();
  await _hydrateRel();
  renderWorlds(); switchView('worlds');   // sensible back-target behind the chat
  const adventures = (_chars || []).filter(c => _isDM(c));
  if (!adventures.length) return;         // nothing to continue — worlds gallery
  const last = lastAdventure();
  const saved = adventures.find(x => x.id === last);
  // One save → straight back in. Several campaigns → pick which to resume.
  if (adventures.length === 1) return openChat(adventures[0]);
  openSaves(adventures, saved ? saved.id : '');
}

// The save-file screen: every campaign you have going, latest first.
function openSaves(adventures, lastId) {
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-saves-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-saves-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const sorted = adventures.slice().sort((a, b) => Number(b.id === lastId) - Number(a.id === lastId));
  const rows = sorted.map(c => {
    let s = {}, ck = {};
    try { s = _loadSheet(c.id) || {}; ck = _loadClock(c.id) || {}; } catch {}
    const w = c.world_id ? getWorld(c.world_id) : null;
    const bits = [w ? w.name : '', s.name ? `${s.name} · Level ${s.level || 1}` : '', ck.day ? `Day ${ck.day}` : '', s.campaignComplete ? '🏁 Complete' : '']
      .filter(Boolean).join(' · ');
    return `<button type="button" class="save-row${c.id === lastId ? ' latest' : ''}" data-save="${_esc(c.id)}">
      <span class="save-title">${_esc(c.name)}${c.id === lastId ? ' <span class="save-latest">latest</span>' : ''}</span>
      ${bits ? `<span class="save-sub">${_esc(bits)}</span>` : ''}</button>`;
  }).join('');
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Continue an adventure">
    <div class="chronicle-bar"><h2>✦ Continue an adventure</h2><button class="studio-close" id="saves-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list saves-list">${rows}</div></div>`;
  ov.style.display = 'flex';
  $('saves-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.querySelectorAll('[data-save]').forEach(b => b.addEventListener('click', () => {
    const c = _chars.find(x => x.id === b.dataset.save);
    ov.style.display = 'none';
    if (c) openChat(c);
  }));
}

// Apply a world's theme: toggle [data-world] for the CSS-var overrides AND swap
// the living-background particle kind to match the world's ambient.
function applyWorldTheme(worldId) {
  const modal = $('studio-modal');
  if (modal) {
    modal.dataset.world = worldId || '';
    // Every panel and overlay paints itself over THIS world's key art
    // (heavily scrimmed for readability) — menus live inside the world.
    let art = '';
    try { art = worldId ? (localStorage.getItem(BACKDROP_KEY(worldId)) || '') : ''; } catch {}
    if (art) modal.style.setProperty('--world-art', `url("${art}")`);
    else modal.style.removeProperty('--world-art');
  }
  const w = worldId ? getWorld(worldId) : null;
  setAmbient(w && w.ambient ? w.ambient : 'arcane');
}

// ── Scene backdrop (generated living background behind the chat) ─────────────
const BACKDROP_KEY = (wid) => `studio-backdrop-${wid}`;
function _clearBackdrop() { const el = $('studio-backdrop'); if (el) el.classList.remove('active'); }

async function _applyBackdrop(worldId, customPrompt) {
  const el = $('studio-backdrop');
  if (!el || (!worldId && !customPrompt)) return;
  const key = worldId || 'custom';
  let url = null;
  if (!customPrompt) { try { url = localStorage.getItem(BACKDROP_KEY(key)); } catch {} }
  if (url) { el.style.backgroundImage = `url("${url}")`; el.classList.add('active'); return; }
  const prompt = customPrompt || getBackdropPrompt(worldId);
  if (!prompt) return;
  try {
    const res = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, size: '1216x832' }),
    });
    const data = await res.json();
    if (data.ok && data.image_url) {
      try { localStorage.setItem(BACKDROP_KEY(key), data.image_url); } catch {}
      if (_chat.char && (_chat.char.world_id || '') === (worldId || '')) {
        el.style.backgroundImage = `url("${data.image_url}")`;
        el.classList.add('active');
      }
    }
  } catch (_) { /* backdrop is decorative — ignore failures */ }
}

function close() {
  // Refresh the title-screen save caption before leaving — level/day may have
  // moved since the adventure was opened (it used to show stale numbers).
  try {
    const last = localStorage.getItem(LAST_ADV_KEY);
    if (last && _chat.char && _chat.char.id === last && _isDM(_chat.char)) {
      const s = _loadSheet(last), ck = _loadClock(last);
      localStorage.setItem(LAST_ADV_KEY + '-meta', JSON.stringify({ title: _chat.char.name, level: s.level || 1, day: ck.day || 1, hero: s.name || '', complete: !!s.campaignComplete }));
    }
  } catch {}
  const modal = $('studio-modal');
  if (modal) modal.classList.add('hidden');
  document.body.classList.remove('studio-open');
  _partyStop();
  _stopMusic();
  stopAmbient();
  if (_chat.abort) { try { _chat.abort.abort(); } catch {} }
  _chat.streaming = false;
  // Leaving the game always lands on the title screen, not the legacy chat.
  document.body.classList.add('home-landing');
  try { window.chatModule?.showWelcomeScreen?.(); } catch {}
  try { window.refreshHomeContinue?.(); } catch {}   // save caption may have changed
}

// Close every in-chat HUD panel/overlay so none leaks over the menu views.
function _closeChatPanels() {
  document.querySelectorAll('#studio-modal .sheet-panel.open, #studio-modal .combat-panel.open, #studio-modal .inv-panel.open, #studio-modal .gm-panel.open').forEach(p => p.classList.remove('open'));
  ['studio-map-overlay', 'studio-lore-overlay', 'studio-quests-overlay', 'studio-reaction-overlay', 'studio-levelup-overlay', 'studio-skillmenu', 'studio-saves-overlay'].forEach(id => { const o = $(id); if (o) o.style.display = 'none'; });
  const more = $('studio-more-menu'); if (more) more.classList.remove('open');
}
function switchView(name) {
  _view = name;
  $('studio-worlds-view').hidden = name !== 'worlds';
  $('studio-campaigns-view').hidden = name !== 'campaigns';
  $('studio-roster-view').hidden = name !== 'roster';
  $('studio-forge-view').hidden = name !== 'forge';
  $('studio-chat-view').hidden = name !== 'chat';
  if (name !== 'chat') { _clearBackdrop(); _closeChatPanels(); _stopAmbient(); }   // scene backdrop + HUD + soundscape only behind the chat
  document.querySelectorAll('#studio-modal .studio-tab').forEach(t =>
    t.classList.toggle('active', t.dataset.view === name && name !== 'chat'));
  const vw = $(`studio-${name}-view`);
  if (vw) vw.scrollTop = 0;
}

// ── Data ────────────────────────────────────────────────────────────────────
async function loadCharacters() {
  try {
    const res = await fetch(`${API_BASE}/api/presets/templates`);
    _chars = res.ok ? (await res.json()) : [];
  } catch { _chars = []; }
}

// ── Worlds view ──────────────────────────────────────────────────────────────
function renderWorlds() {
  const root = $('studio-worlds');
  if (!root) return;
  applyWorldTheme('');   // neutral arcane theme on the gallery of worlds
  const all = listWorlds();
  const cards = all.map((w, i) => {
    // Every world gets a painted card once its backdrop has baked; until then
    // the CSS scene (prebuilt) or arcane gradient (custom) stands in.
    let bg = ''; try { bg = localStorage.getItem(BACKDROP_KEY(w.id)) || ''; } catch {}
    const bgStyle = bg ? ` style="background-image:url('${_esc(bg)}');background-size:cover;background-position:center"` : '';
    const scene = `<div class="world-card-scene ${w.custom ? 'wc-custom' : 'wc-' + _esc(w.id)}" aria-hidden="true"${bgStyle}></div>`;
    return `
    <div class="world-card" data-world="${_esc(w.id)}" role="button" tabindex="0" aria-label="Enter ${_esc(w.name)}" style="animation-delay:${i * 60}ms">
      ${scene}
      <div class="world-card-body">
        <span class="world-kind">${_esc(w.kind)}</span>
        <h3 class="world-name">${_esc(w.name)}</h3>
        <p class="world-tagline">${_esc(w.tagline)}</p>
      </div>
    </div>`;
  }).join('');
  const forge = `
    <div class="world-card world-forge" id="forge-world-card" role="button" tabindex="0" aria-label="Forge a new world" style="animation-delay:${all.length * 60}ms">
      <div class="world-card-scene wc-forge" aria-hidden="true"><span class="wf-plus">✦</span></div>
      <div class="world-card-body">
        <span class="world-kind">Worldsmith</span>
        <h3 class="world-name">Forge a new world</h3>
        <p class="world-tagline">Describe it — the AI builds the realm, its people, and its stories.</p>
      </div>
    </div>`;
  root.innerHTML = `
    <p class="studio-step">New adventure · Step 1 of 3 — <em>world</em> › campaign › hero</p>
    <h1 class="studio-h">Choose a world</h1>
    <p class="studio-sub">Step into a ready-made realm and its cast — or forge your own.</p>
    <div class="world-grid">${cards}${forge}</div>
    <p class="world-import-row"><button class="gh-link" id="world-import" type="button">⬆ Import a world file…</button><input type="file" id="world-import-file" accept=".json,application/json" style="display:none"></p>`;
  root.querySelectorAll('.world-card:not(.world-forge)').forEach(card => {
    const go = () => { const w = getWorld(card.dataset.world); if (w) renderWorldDetail(w); };
    card.addEventListener('click', go);
    card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
  });
  const fc = $('forge-world-card');
  if (fc) {
    fc.addEventListener('click', () => openWorldsmith());
    fc.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openWorldsmith(); } });
  }
  // Import a world someone exported (or you backed up).
  $('world-import')?.addEventListener('click', () => $('world-import-file')?.click());
  $('world-import-file')?.addEventListener('change', async (e) => {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    try {
      const w = JSON.parse(await f.text());
      if (!w || !w.name || !w.lore) throw new Error('not a world file');
      const world = {
        id: 'cw-' + _slugify(w.name) + '-' + Date.now().toString(36).slice(-4),
        custom: true,
        name: String(w.name).slice(0, 60), kind: String(w.kind || 'Adventure').slice(0, 40),
        tagline: String(w.tagline || '').slice(0, 160), lore: String(w.lore).slice(0, 1200),
        ambient: 'arcane', backdrop: String(w.backdrop || '').slice(0, 400),
        reskins: (w.reskins && typeof w.reskins === 'object' && w.reskins.names && typeof w.reskins.names === 'object') ? w.reskins : null,
        cast: Array.isArray(w.cast) ? w.cast.filter(c => c && c.name).map(c => ({ name: String(c.name).slice(0, 60), role: String(c.role || '').slice(0, 80), appearance: String(c.appearance || '').slice(0, 300), persona: String(c.persona || '').slice(0, 600), slug: _slugify(c.name), avatar: typeof c.avatar === 'string' ? c.avatar : '' })) : [],
        stories: Array.isArray(w.stories) ? w.stories.filter(st => st && st.title).map(st => ({ title: String(st.title).slice(0, 80), premise: String(st.premise || '').slice(0, 500), hook: String(st.hook || '').slice(0, 300), slug: _slugify(st.title) })) : [],
        locations: Array.isArray(w.locations) ? w.locations.filter(l => l && l.name).map((l, i) => ({ name: String(l.name).slice(0, 60), kind: ['tavern', 'shop', 'landmark', 'wilds', 'home'].includes(l.kind) ? l.kind : 'landmark', lore: String(l.lore || '').slice(0, 200), shop: l.shop ? String(l.shop).slice(0, 120) : undefined, x: typeof l.x === 'number' ? l.x : 14 + ((i * 29) % 70), y: typeof l.y === 'number' ? l.y : 16 + ((i * 23) % 62) })) : [],
        creatures: Array.isArray(w.creatures) ? w.creatures.filter(c => c && c.name).map(c => ({ name: String(c.name).slice(0, 60), tier: ['minor', 'standard', 'dire'].includes(c.tier) ? c.tier : 'standard', desc: String(c.desc || '').slice(0, 300), weakness: String(c.weakness || '').slice(0, 200), tactics: String(c.tactics || '').slice(0, 200), art: String(c.art || '').slice(0, 300), slug: 'wc-' + _slugify(c.name) })) : [],
      };
      _saveCWorlds(_loadCWorlds().concat([world]));
      renderWorlds();
      renderWorldDetail(world);
    } catch (err) {
      alert(`Couldn't import that file: ${err.message || err}`);
    }
    e.target.value = '';
  });
  _bakeWorldCards(all);   // paint any world card still missing its picture
}

function renderWorldDetail(world) {
  _world = world;
  _activeStyle = _loadWorldStyle(world.id);   // per-world art style rides all image gen this world
  applyWorldTheme(world.id);
  const root = $('studio-worlds');
  if (!root) return;
  const cast = world.cast.map((c, i) => `
    <div class="cast-card" data-slug="${_esc(c.slug)}" role="button" tabindex="0" aria-label="Chat with ${_esc(c.name)}" style="animation-delay:${i * 50}ms">
      <div class="cast-avatar" aria-hidden="true">${c.avatar ? `<img src="${_esc(c.avatar)}" alt="" loading="lazy">` : _esc(_initial(c.name))}</div>
      <div class="cast-body">
        <p class="cast-name">${_esc(c.name)}</p>
        <p class="cast-role">${_esc(c.role)}</p>
      </div>
    </div>`).join('');
  const stories = getStories(world.id);
  const adv = [
    `<div class="cast-card adventure-card" data-story="__free__" role="button" tabindex="0" aria-label="Free roam with a Dungeon Master">
       <div class="cast-avatar dm" aria-hidden="true">GM</div>
       <div class="cast-body"><p class="cast-name">Free Roam</p><p class="cast-role">A Game Master improvises an adventure with you, wherever you lead.</p></div>
     </div>`
  ].concat(stories.map((s, i) => `
    <div class="cast-card adventure-card" data-story="${_esc(s.slug)}" role="button" tabindex="0" aria-label="Begin ${_esc(s.title)}" style="animation-delay:${i * 50}ms">
      <div class="cast-avatar dm" aria-hidden="true">GM</div>
      <div class="cast-body"><p class="cast-name">${_esc(s.title)}</p><p class="cast-role">${_esc(s.premise)}</p></div>
    </div>`)).concat([`
    <div class="cast-card adventure-card craft-campaign" data-story="__craft__" role="button" tabindex="0" aria-label="Craft a new campaign with the AI">
      <div class="cast-avatar dm" aria-hidden="true">✦</div>
      <div class="cast-body"><p class="cast-name">Craft a campaign</p><p class="cast-role">Tell the AI the story you want to play; it drafts the premise and opening scene.</p></div>
    </div>`]).join('');

  let heroBg = '';
  if (world.custom) { try { const u = localStorage.getItem(BACKDROP_KEY(world.id)); if (u) heroBg = ` style="background-image:url('${_esc(u)}');background-size:cover;background-position:center"`; } catch {} }
  root.innerHTML = `
    <button class="chat-back" id="worlds-back" type="button">‹ All worlds</button>
    <p class="studio-step">New adventure · Step 2 of 3 — world › <em>campaign</em> › hero</p>
    <div class="world-hero ${world.custom ? 'wc-custom' : `wc-${_esc(world.id)}`}"${heroBg}>
      <div class="world-hero-text">
        <span class="world-kind">${_esc(world.kind)}</span>
        <h1 class="studio-h">${_esc(world.name)}</h1>
        <p class="world-lore">${_esc(world.lore)}</p>
      </div>
    </div>
    <div class="world-style-bar">
      <label for="world-style">✦ Art style</label>
      <select id="world-style" class="st-select" aria-label="Art style for this world"></select>
      <span class="style-note" id="world-style-note" role="status" aria-live="polite"></span>
    </div>
    <p class="section-rule">Adventures <span class="rule-hint">a Dungeon Master narrates &amp; drives the story</span></p>
    <div class="adventure-grid">${adv}</div>
    <p class="section-rule">The cast <span class="rule-hint">chat one-to-one, no Dungeon Master</span></p>
    <div class="cast-grid">${cast}</div>
    ${world.custom ? `<div class="world-admin"><button class="st-btn small ghost" id="world-export" type="button">⬇ Export world</button> <button class="st-btn small ghost" id="world-delete" type="button">Unmake this world</button></div>` : ''}`;
  root.scrollTop = 0;
  $('worlds-back').addEventListener('click', () => { renderWorlds(); });
  // Art-style picker: pick a look for this world; un-installed styles offer a
  // one-time "free style pack" download with live progress, then become active.
  (async () => {
    const sel = $('world-style'); const note = $('world-style-note');
    if (!sel) return;
    const styles = await _fetchArtStyles();
    if (!styles.length) { sel.closest('.world-style-bar')?.remove(); return; }   // image gen not set up
    const saved = _loadWorldStyle(world.id);
    // Only an INSTALLED style can be active — otherwise image gen silently falls
    // back to the bridge default while the picker claims the chosen style is on.
    const cur = styles.find(s => s.id === saved && s.installed) ? saved : (styles.find(s => s.installed)?.id || styles[0].id);
    _activeStyle = cur;
    sel.innerHTML = styles.map(s => `<option value="${_esc(s.id)}"${s.id === cur ? ' selected' : ''}>${_esc(s.label)}${s.installed ? '' : ` — download ~${s.size_gb} GB`}</option>`).join('');
    const setNote = (t) => { if (note) note.textContent = t || ''; };
    sel.addEventListener('change', async () => {
      const id = sel.value;
      const st = (await _fetchArtStyles()).find(s => s.id === id);
      if (st && !st.installed) {
        if (!confirm(`Download the "${st.label}" style pack (~${st.size_gb} GB)?\n\nIt's a free, one-time download. The game keeps playing while it fetches.`)) { sel.value = _activeStyle; return; }
        sel.disabled = true;
        setNote(`Downloading ${st.label}… 0%`);
        const ok = await _downloadStyle(id, (p) => setNote(`Downloading ${st.label}… ${p.pct || 0}%${p.total_mb ? ` (${p.mb || 0}/${p.total_mb} MB)` : ''}`));
        sel.disabled = false;
        if (!ok) { setNote('Download failed — try again.'); sel.value = _activeStyle; return; }
        // refresh option labels (drop the "download" hint on the now-installed one)
        const fresh = await _fetchArtStyles(true);
        sel.innerHTML = fresh.map(s => `<option value="${_esc(s.id)}"${s.id === id ? ' selected' : ''}>${_esc(s.label)}${s.installed ? '' : ` — download ~${s.size_gb} GB`}</option>`).join('');
        setNote(`${st.label} ready ✓`);
      } else { setNote(''); }
      _saveWorldStyle(world.id, id);
    });
  })();
  $('world-export')?.addEventListener('click', () => {
    const blob = new Blob([JSON.stringify(world, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${_slugify(world.name)}.world.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  });
  $('world-delete')?.addEventListener('click', () => {
    if (!confirm(`Unmake "${world.name}"? Its saved adventures stay recoverable in Chats, but the world leaves the gallery.`)) return;
    _saveCWorlds(_loadCWorlds().filter(w => w.id !== world.id));
    renderWorlds();
  });
  root.querySelectorAll('.cast-card:not(.adventure-card)').forEach(card => {
    const go = () => { const c = world.cast.find(x => x.slug === card.dataset.slug); if (c) enterWorldCharacter(world, c, card); };
    card.addEventListener('click', go);
    card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
  });
  root.querySelectorAll('.adventure-card').forEach(card => {
    const go = () => {
      const slug = card.dataset.story;
      if (slug === '__craft__') { openCampaignsmith(world); return; }
      const s = slug === '__free__' ? null : stories.find(x => x.slug === slug);
      startAdventure(world, s, card);
    };
    card.addEventListener('click', go);
    card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
  });
}

// ── Worldsmith: player-forged worlds & campaigns (durable, global) ───────────
const CWORLDS_KEY = 'studio-custom-worlds';
const CSTORIES_KEY = 'studio-custom-stories';
function _loadCWorlds() { try { return JSON.parse(localStorage.getItem(CWORLDS_KEY) || '[]') || []; } catch { return []; } }
function _saveCWorlds(list) { try { localStorage.setItem(CWORLDS_KEY, JSON.stringify(list)); } catch {} setCustomWorlds(list); _pushState('_global', 'cworlds', list); }
function _loadCStories() { try { return JSON.parse(localStorage.getItem(CSTORIES_KEY) || '{}') || {}; } catch { return {}; } }
function _saveCStories(map) { try { localStorage.setItem(CSTORIES_KEY, JSON.stringify(map)); } catch {} setCustomStories(map); _pushState('_global', 'cstories', map); }
function _slugify(s) { return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 32) || 'x'; }

// One picture, or null — every pregen job goes through here.
async function _genArt(prompt, size) {
  try {
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, size: size || '768x768' }),
    });
    const d = await r.json();
    return (d.ok && d.image_url) ? d.image_url : null;
  } catch { return null; }
}

// Sequential art queue with a sticky progress chip (one GPU serves everyone).
// Failures skip quietly — a half-illustrated world still plays fine, and the
// lorebook's per-entry Conjure button remains as the manual backfill.
async function _runForgeQueue(name, jobs) {
  if (!jobs.length) return;
  const modal = $('studio-modal'); if (!modal) return;
  let chip = $('studio-forge-progress');
  if (!chip) { chip = document.createElement('div'); chip.id = 'studio-forge-progress'; chip.className = 'forge-progress'; chip.setAttribute('role', 'status'); modal.appendChild(chip); }
  for (let i = 0; i < jobs.length; i++) {
    chip.textContent = `✦ Illustrating ${name} — ${i + 1}/${jobs.length}: ${jobs[i].label}`;
    try { await jobs[i].run(); } catch { /* skip and keep forging */ }
  }
  chip.remove();
  _toast(`✦ ${name} is fully illustrated — its lorebook has pictures.`);
}

// Every world deserves a picture: bake missing card art (prebuilt worlds
// included) in the background, oldest gallery first, then refresh the cards.
let _cardsBaking = false;
async function _bakeWorldCards(worlds) {
  if (_cardsBaking) return;
  _cardsBaking = true;
  try {
    for (const w of worlds) {
      let have = null; try { have = localStorage.getItem(BACKDROP_KEY(w.id)); } catch {}
      if (have) continue;
      const prompt = w.custom ? w.backdrop : getBackdropPrompt(w.id);
      if (!prompt) continue;
      const url = await _genArt(prompt, '1216x832');
      if (url) { try { localStorage.setItem(BACKDROP_KEY(w.id), url); } catch {} if (_view === 'worlds') renderWorlds(); }
    }
  } finally { _cardsBaking = false; }
}

function _smithOverlay() {
  const modal = $('studio-modal'); if (!modal) return null;
  let ov = $('studio-smith-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-smith-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  ov.style.display = 'flex';
  return ov;
}
function _smithClose() { const ov = $('studio-smith-overlay'); if (ov) ov.style.display = 'none'; }

// The guided pillars: each is optional, each has one-click suggestions, and
// everything the player picks is honored by every generation call.
const _SMITH_GUIDE = [
  ['magic system', 'Magic system', ['Forbidden & feared', 'Elemental pacts', 'Tech-grafted mods', 'Divine bargains', 'Wild & untamed', 'None — mundane grit']],
  ['technology level', 'Technology', ['Medieval', 'Steam & clockwork', 'Modern day', 'Neon cyberpunk', 'Starfaring']],
  ['era and timeline', 'Era & timeline', ['A golden age fading', 'After the cataclysm', 'Frontier boom', 'A long peace cracking', 'Under occupation']],
  ['beast variants', 'Beast variants', ['Corrupted wildlife', 'Ancient constructs', 'Spirits & shades', 'Bio-engineered horrors', 'Dragons & their kin']],
  ['tone', 'Tone', ['Grim & gritty', 'Heroic & bright', 'Whimsical', 'Noir & conspiratorial']],
];

function openWorldsmith() {
  const ov = _smithOverlay(); if (!ov) return;
  const guideRows = _SMITH_GUIDE.map(([key, label, opts], gi) => `
    <div class="smith-field">
      <label class="sf" style="margin:0">${label}<input type="text" data-smithfield="${_esc(key)}" placeholder="anything you like — or tap a suggestion"></label>
      <div class="smith-chips">${opts.map(o => `<button type="button" class="smith-chip" data-chipfor="${gi}">${_esc(o)}</button>`).join('')}</div>
    </div>`).join('');
  ov.innerHTML = `<div class="chronicle-sheet smith-sheet" role="dialog" aria-modal="true" aria-label="Forge a new world">
    <div class="chronicle-bar"><h2>✦ Forge a new world</h2><button class="studio-close" id="smith-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Describe the world you want, then set its pillars — the worldsmith builds the realm, its people, campaigns, a map, a bestiary of its own monsters, and this world's names for every class. Then it paints everything. A thorough forge takes a few minutes.</p>
      <textarea id="smith-idea" class="codex-note" rows="3" placeholder="e.g. A drowned Venice of sky-whales and salvage guilds, melancholy but hopeful…"></textarea>
      ${guideRows}
      <div class="chronicle-actions">
        <button class="st-btn primary" id="smith-go" type="button">✦ Forge it</button>
        <button class="st-btn" id="smith-surprise" type="button" title="Fill the pillars with a random combination">🎲 Surprise me</button>
      </div>
      <div id="smith-result"></div>
    </div></div>`;
  $('smith-close').addEventListener('click', _smithClose);
  ov.addEventListener('click', (e) => { if (e.target === ov) _smithClose(); });
  // Suggestion chips fill (or clear) their field; Surprise rolls all of them.
  ov.querySelectorAll('.smith-chip').forEach(ch => ch.addEventListener('click', () => {
    const gi = Number(ch.dataset.chipfor);
    const input = ov.querySelectorAll('[data-smithfield]')[gi];
    if (!input) return;
    input.value = input.value === ch.textContent ? '' : ch.textContent;
    const row = ch.closest('.smith-field');
    row.querySelectorAll('.smith-chip').forEach(c => c.classList.toggle('on', c.textContent === input.value));
  }));
  $('smith-surprise').addEventListener('click', () => {
    ov.querySelectorAll('.smith-field').forEach((row, gi) => {
      const opts = _SMITH_GUIDE[gi][2];
      const pick = opts[Math.floor(Math.random() * opts.length)];
      const input = row.querySelector('[data-smithfield]');
      input.value = pick;
      row.querySelectorAll('.smith-chip').forEach(c => c.classList.toggle('on', c.textContent === pick));
    });
  });
  const _smithFields = () => {
    const out = {};
    ov.querySelectorAll('[data-smithfield]').forEach(i => { const v = (i.value || '').trim(); if (v) out[i.dataset.smithfield] = v; });
    return out;
  };
  // One renderer for every draft — first take or a refinement.
  const showWorld = (w) => {
    const out = $('smith-result'); const btn = $('smith-go');
    out.innerHTML = `
      <div class="sheet-section"><h3>${_esc(w.name)} <span class="prof-bonus">${_esc(w.kind)}</span></h3>
        <p class="gm-hint" style="font-style:italic">${_esc(w.tagline)}</p>
        <p class="world-lore">${_esc(w.lore)}</p>
        ${w.cast.length ? `<p class="gm-hint"><strong>Cast:</strong> ${w.cast.map(c => `${_esc(c.name)} (${_esc(c.role)})`).join(' · ')}</p>` : ''}
        ${w.stories.length ? `<p class="gm-hint"><strong>Campaigns:</strong> ${w.stories.map(st => _esc(st.title)).join(' · ')}</p>` : ''}
        ${w.locations.length ? `<p class="gm-hint"><strong>Places:</strong> ${w.locations.map(l => _esc(l.name)).join(' · ')}</p>` : ''}
        ${(w.creatures || []).length ? `<p class="gm-hint"><strong>Bestiary (${w.creatures.length}):</strong> ${w.creatures.map(c => _esc(c.name)).join(' · ')}</p>` : ''}
        ${(w.reskins && w.reskins.names) ? `<p class="gm-hint"><strong>Classes here:</strong> ${['Wizard', 'Rogue', 'Cleric', 'Fighter'].filter(c => w.reskins.names[c]).map(c => `${c} → ${_esc(w.reskins.names[c])}`).join(' · ')} …</p>` : ''}
        ${(!w.cast.length || !w.stories.length) ? `<p class="gm-hint">⚠ This take came back without ${!w.cast.length && !w.stories.length ? 'a cast or campaigns' : (!w.cast.length ? 'a cast' : 'campaigns')} — refine or forge another take (you can also craft campaigns later).</p>` : ''}
      </div>
      <div class="chronicle-actions">
        <button class="st-btn primary" id="smith-create" type="button">Create this world ›</button>
        <button class="st-btn" id="smith-refine" type="button">✎ Refine…</button>
        <button class="st-btn" id="smith-retry" type="button">↻ Forge another take</button>
      </div>
      <div class="add-row" id="smith-refine-row" style="display:none"><input type="text" id="smith-refine-text" placeholder="What should change? e.g. darker tone, add a pirate faction, rename it…"><button class="st-btn small primary" id="smith-refine-go" type="button">Revise</button></div>`;
    $('smith-retry').addEventListener('click', () => { btn.disabled = false; btn.textContent = '✦ Forge it'; out.innerHTML = ''; });
    $('smith-refine').addEventListener('click', () => { $('smith-refine-row').style.display = ''; $('smith-refine-text').focus(); });
    const refine = async () => {
      const instr = ($('smith-refine-text').value || '').trim(); if (!instr) return;
      const rb = $('smith-refine-go'); rb.disabled = true; rb.textContent = 'Revising… (about a minute)';
      try {
        const rr = await fetch(`${API_BASE}/api/characters/studio/worldsmith`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ idea: instr, mode: 'world', prior: w, model: _modelLabel() }),
        });
        const rd = await rr.json();
        if (!rr.ok || !rd.ok || !rd.world) throw new Error(rd.detail || 'The revision fell flat.');
        showWorld(rd.world);
      } catch (err) {
        rb.disabled = false; rb.textContent = 'Revise';
        out.insertAdjacentHTML('beforeend', `<p class="gm-hint">⚠ ${_esc(err.message || err)}</p>`);
      }
    };
    $('smith-refine-go').addEventListener('click', refine);
    $('smith-refine-text').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); refine(); } });
    $('smith-create').addEventListener('click', () => {
      const id = 'cw-' + _slugify(w.name) + '-' + Date.now().toString(36).slice(-4);
      const world = {
        id, custom: true, name: w.name, kind: w.kind, tagline: w.tagline, lore: w.lore,
        ambient: 'arcane', backdrop: w.backdrop,
        reskins: (w.reskins && w.reskins.names) ? w.reskins : null,
        cast: w.cast.map(c => ({ ...c, slug: _slugify(c.name) })),
        stories: w.stories.map(st => ({ ...st, slug: _slugify(st.title) })),
        locations: w.locations.map((l, i) => ({ ...l, x: 14 + ((i * 29) % 70), y: 16 + ((i * 23) % 62) })),
        creatures: (w.creatures || []).map(c => ({ ...c, slug: 'wc-' + _slugify(c.name) })),
      };
      _saveCWorlds(_loadCWorlds().concat([world]));
      _smithClose();
      renderWorlds();
      renderWorldDetail(world);
      // Pre-generate the world's whole picture book (players should never have
      // to conjure lorebook art themselves): world portrait → cast faces →
      // every bestiary creature. One GPU, one queue, visible progress.
      const jobs = [];
      if (world.backdrop) jobs.push({
        label: 'world portrait',
        run: async () => {
          const gd = await _genArt(world.backdrop, '1216x832');
          if (gd) { try { localStorage.setItem(BACKDROP_KEY(id), gd); } catch {} if (_view === 'worlds') renderWorlds(); }
        },
      });
      world.cast.forEach(member => {
        if (!member.appearance && !member.role) return;
        jobs.push({
          label: `face — ${member.name}`,
          run: async () => {
            const gd = await _genArt(`character portrait, ${[member.appearance, member.role, member.name].filter(Boolean).join(', ')}, head and shoulders, dramatic lighting, no text`, '512x512');
            if (gd) {
              const list = _loadCWorlds(); const cw = list.find(x => x.id === id);
              const m = cw && (cw.cast || []).find(x => x.slug === member.slug);
              if (m) { m.avatar = gd; _saveCWorlds(list); }
            }
          },
        });
      });
      world.creatures.forEach(c => {
        jobs.push({
          label: `beast — ${c.name}`,
          run: async () => {
            const gd = await _genArt(c.art || `${c.name}, ${c.desc || 'a fearsome creature'}, in ${world.name}, creature portrait, dramatic lighting, no text`, '768x768');
            if (gd) { const m = _loadLoreArt(); m[c.slug] = gd; _saveLoreArt(m); }
          },
        });
      });
      _runForgeQueue(world.name, jobs);
    });
  };
  $('smith-go').addEventListener('click', async () => {
    const idea = ($('smith-idea').value || '').trim(); if (!idea) return;
    const btn = $('smith-go'); btn.disabled = true; btn.textContent = 'Forging… (a few minutes — beasts & classes too)';
    const out = $('smith-result'); out.innerHTML = '';
    try {
      const r = await fetch(`${API_BASE}/api/characters/studio/worldsmith`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idea, mode: 'world', fields: _smithFields(), model: _modelLabel() }),
      });
      const d = await r.json();
      if (!r.ok || !d.ok || !d.world) throw new Error(d.detail || 'The worldsmith fell silent.');
      showWorld(d.world);
    } catch (e) {
      out.innerHTML = `<p class="gm-hint">⚠ ${_esc(e.message || e)} — try again.</p>`;
      btn.disabled = false; btn.textContent = '✦ Forge it';
    }
  });
}

function openCampaignsmith(world) {
  const ov = _smithOverlay(); if (!ov) return;
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Craft a campaign">
    <div class="chronicle-bar"><h2>✦ Craft a campaign — ${_esc(world.name)}</h2><button class="studio-close" id="smith-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">What story do you want to play here? A heist, a mystery, a rivalry, a slow romance — give the AI the seed and it drafts the campaign.</p>
      <textarea id="smith-idea" class="codex-note" rows="3" placeholder="e.g. I want to infiltrate the Thorn Court masquerade and steal back a stolen name…"></textarea>
      <div class="chronicle-actions"><button class="st-btn primary" id="smith-go" type="button">✦ Draft it</button></div>
      <div id="smith-result"></div>
    </div></div>`;
  $('smith-close').addEventListener('click', _smithClose);
  ov.addEventListener('click', (e) => { if (e.target === ov) _smithClose(); });
  $('smith-go').addEventListener('click', async () => {
    const idea = ($('smith-idea').value || '').trim(); if (!idea) return;
    const btn = $('smith-go'); btn.disabled = true; btn.textContent = 'Drafting…';
    const out = $('smith-result'); out.innerHTML = '';
    try {
      const r = await fetch(`${API_BASE}/api/characters/studio/worldsmith`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idea, mode: 'story', world: { name: world.name, kind: world.kind, lore: world.lore }, model: _modelLabel() }),
      });
      const d = await r.json();
      if (!r.ok || !d.ok || !d.story) throw new Error(d.detail || 'No draft came back.');
      const s = d.story;
      out.innerHTML = `
        <div class="sheet-section"><h3>${_esc(s.title)}</h3>
          <p class="world-lore">${_esc(s.premise)}</p>
          <p class="gm-hint"><em>Opens on:</em> ${_esc(s.hook)}</p></div>
        <div class="chronicle-actions">
          <button class="st-btn primary" id="smith-add" type="button">Add to ${_esc(world.name)} ›</button>
          <button class="st-btn" id="smith-retry" type="button">↻ Another take</button>
        </div>`;
      $('smith-retry').addEventListener('click', () => { btn.disabled = false; btn.textContent = '✦ Draft it'; out.innerHTML = ''; });
      $('smith-add').addEventListener('click', () => {
        const story = { slug: 'cs-' + _slugify(s.title), title: s.title, premise: s.premise, hook: s.hook, custom: true };
        if (world.custom) {
          const list = _loadCWorlds(); const cw = list.find(x => x.id === world.id);
          if (cw) { cw.stories = (cw.stories || []).concat([story]); _saveCWorlds(list); }
        } else {
          const map = _loadCStories(); map[world.id] = (map[world.id] || []).concat([story]); _saveCStories(map);
        }
        _smithClose();
        renderWorldDetail(getWorld(world.id) || world);
        switchView('worlds');   // show the world (with its new campaign), whether forged from Worlds or the Campaigns tab
      });
    } catch (e) {
      out.innerHTML = `<p class="gm-hint">⚠ ${_esc(e.message || e)} — try again.</p>`;
      btn.disabled = false; btn.textContent = '✦ Draft it';
    }
  });
}

function _isDM(c) { return !!c && String(c.id || '').startsWith('dm-'); }

// Build the single Game-Master system prompt: world canon + chosen story + the
// cast it may voice + how to run a living, player-driven scene.
// The deeper 5e table rules, shared by every Game Master charter. These are
// GM-honored (the model runs them in fiction); the client enforces the core
// numbers (checks, HP, slots, conditions, exhaustion) mechanically.
const _DM_DEPTH_RULES = `# DEEPER TABLE RULES — honor all of these
- SURPRISE: if one side is unaware when a fight starts, say so plainly — the surprised side loses its first turn.
- FOES FIGHT DIRTY: enemies grapple, shove prone, poison, and frighten. Name the condition so it lands on the sheet. Melee attacks against a prone, restrained, stunned, or paralyzed target have advantage.
- COVER: half cover +2 AC, three-quarters +5, full cover cannot be targeted.
- OPPORTUNITY ATTACKS: leaving a foe's melee reach without Disengaging provokes one attack from it.
- WEAPON PROPERTIES: honor them — versatile (bigger die two-handed), heavy, light (two-weapon fighting), reach, thrown, loading.
- LIGHT & VISION: darkness is real. No light source and no darkvision means blind — attacks at disadvantage, sight-based checks fail. Torches burn out.
- CANTRIP SCALING: cantrip damage dice double at character level 5 and triple at level 11.
- WEAKNESS & RESISTANCE: exploiting a creature's known weakness bites hard; attacks it resists deal half. Say which is happening.
- ATTUNEMENT: a hero can be attuned to at most 3 magic items at once.
- EXHAUSTION: forced marches, sleepless nights, and starvation add exhaustion — tell the player plainly to "add a level of exhaustion" (a long rest removes one).
- TRAPS: telegraph them — passive Perception notices hints; finding is a check, disarming is a check, springing one has teeth.
- REACTION ROLLS: strangers meet the player per their disposition and reputation — friendly, wary, or hostile — not per the plot's convenience.
- DOWNTIME: in quiet stretches, offer training, carousing, crafting, and rumor-hunting; each carries small costs and rewards.
- THE PLAYER CAN PICK ANY FIGHT: never refuse or deflect combat the player starts — anyone and anything can be attacked. For a reckless or outrageous target, ask once "*Are you sure?*", then run it with real consequences (guards, reputation, retaliation). When any fight begins, announce it like a game master at the table: "*Roll for initiative!*"
- DICE DISCIPLINE: if the player rolls a die with no declared purpose, ask what it's for before honoring it. If they call the wrong ability or skill for a check (or grab the wrong die), correct them plainly and use the RIGHT one.
- NARRATION HYGIENE: never print raw dice math, roll breakdowns, or HP numbers in your prose — no "(Rolls 1d6 + STR = 5)", no "HP: 12/20", no "(300 - 4)/300 hp", no "it's the Dummy's turn". The app tracks every number and shows it in the HUD. Narrate ONLY the fiction and the visible outcome: a stagger, a spray of sparks, a blow that glances off. Numbers live on the sheet, not in the story.`;

// A forged Game Master: their personal style wrapped in the same 5e charter
// the world DMs use, minus a fixed world (they invent or follow the player).
function _composeCustomGMPrompt(name, style, setting, scene, lore) {
  return [
    `You are ${name}, a Game Master — a Dungeon Master — running a living tabletop RPG (Dungeons & Dragons 5e style). This is collaborative fiction with real rules; the player is the hero and you are the world, the rules, and every other character.`,
    style ? `# YOUR STYLE AT THE TABLE\n${style}` : '',
    setting ? `# YOUR PREFERRED SETTING\n${setting}` : '',
    lore ? `# CANON YOU CARRY\n${lore}` : '',
    scene ? `# HOW YOU LIKE TO OPEN\n${scene}` : '# OPENING\nAsk what kind of adventure the player is in the mood for, or pitch two enticing options — then open the scene.',
    `# DUNGEON MASTER RULES — run it like D&D 5e\n`
      + `- The player has a character sheet (six ability scores STR/DEX/CON/INT/WIS/CHA with modifiers, HP, level, class, inventory, conditions). When provided in the message, USE it for rules decisions.\n`
      + `- When an action's outcome is uncertain, call for an ability check: name the ability and set a Difficulty Class — Easy 10, Medium 15, Hard 20, Very Hard 25. Say it plainly, e.g. "*Make a Dexterity check (DC 15).*" Then wait for the player to roll.\n`
      + `- The player rolls a d20 with the dice tray and reports the total (with their modifier). Compare to the DC: meet or beat = success. Narrate degrees — a natural 20 is a critical triumph, a natural 1 a fumble.\n`
      + `- Use advantage/disadvantage when circumstances clearly help or hinder (the player rolls twice, keeps the higher/lower).\n`
      + `- COMBAT — when a fight starts, ANNOUNCE it plainly and name the foe so it's unmistakable, then call for initiative.\n`
      + `- Track HP for the player and foes, apply conditions, resolve a round, then hand the turn back. Make fights tense but fair.\n`
      + `- INVENTORY: reward clever use of items. When the player gains or loses something, state it clearly, e.g. "*(Added to your pack: a rusted iron key.)*". Don't invent items they don't have.`,
    _DM_DEPTH_RULES,
  ].filter(Boolean).join('\n\n');
}

function _composeDMPrompt(world, story) {
  const companions = world.cast.map(c => `- ${c.name} — ${c.role}.`).join('\n');
  const adventure = story
    ? `# THIS ADVENTURE: ${story.title}\n${story.premise}\n\nOpen on this scene: ${story.hook}.`
    : `# FREE ROAM\nThere is no fixed plot. Invent an engaging situation that fits this world, then follow the player's lead and build the story around their choices.`;
  return [
    `You are the Game Master — the Dungeon Master — running a living tabletop RPG (Dungeons & Dragons 5e style) set in ${world.name} (${world.kind}). This is collaborative fiction with real rules; the player is the hero and you are the world, the rules, and every other character.`,
    `# WORLD\n${world.lore}`,
    adventure,
    `# CHARACTERS YOU PLAY (give each a distinct voice; bring them in naturally as the scene calls for them)\n${companions}`,
    `# DUNGEON MASTER RULES — run it like D&D 5e\n`
      + `- The player has a character sheet (six ability scores STR/DEX/CON/INT/WIS/CHA with modifiers, HP, level, class, inventory, conditions). When provided in the message, USE it for rules decisions.\n`
      + `- When an action's outcome is uncertain, call for an ability check: name the ability and set a Difficulty Class — Easy 10, Medium 15, Hard 20, Very Hard 25. Say it plainly, e.g. "*Make a Dexterity check (DC 15).*" Then wait for the player to roll.\n`
      + `- The player rolls a d20 with the dice tray and reports the total (with their modifier). Compare to the DC: meet or beat = success. Narrate degrees — a natural 20 is a critical triumph, a natural 1 a fumble.\n`
      + `- Use advantage/disadvantage when circumstances clearly help or hinder (the player rolls twice, keeps the higher/lower).\n`
      + `- COMBAT — when a fight starts, ANNOUNCE it plainly and name the foe so it's unmistakable, e.g. "*An ogre bursts from the shadows and attacks!*" or "*Roll for initiative — two goblins block the path.*". Then call for initiative.\n`
      + `- On the PLAYER'S turn, let them roll their own attacks and damage. On an ENEMY'S turn, resolve its attack YOURSELF: state the foe's damage to the player as a dice expression in parentheses, e.g. "*The ogre's club slams you for (2d6+4) damage.*" or "*The goblin's blade hits you for (1d6+2).*" — the game rolls that dice and applies the HP loss automatically. Do NOT ask the player to roll a foe's damage, and do NOT just narrate a flat number — always give the foe's damage as dice in parentheses like (2d6+4).\n`
      + `- Track HP for the player and foes, apply conditions (prone, frightened, poisoned, etc.), resolve a round, then hand the turn back. Make fights tense but fair.\n`
      + `- INVENTORY: reward clever use of items. When the player gains or loses something, state it clearly, e.g. "*(Added to your pack: a rusted iron key.)*" so they can log it. Don't invent items they don't have.\n`,
    _DM_DEPTH_RULES,
    `# HOW TO RUN THE GAME\n- Narrate in second person ("you...") and present tense — vivid and cinematic but TIGHT: at most 2 short paragraphs (~90 words total), then STOP. Brevity keeps the game moving; do not write long passages.\n- Voice NPCs in quotation marks, prefaced by who speaks; render actions and atmosphere in *italics*. Keep NPC speeches to a line or two.\n- CRITICAL — describe ONLY the world, NPCs, and the OUTCOMES of what the player attempts. NEVER write the player's words, thoughts, feelings, or actions. Do not write sentences like "you draw your bow" or "you ask...". When the player states an action, narrate its RESULT and the world's reaction, then hand control back. Never roll the player's OWN dice (their attacks, checks, saves). (Resolving a foe's attack damage as parenthesized dice is expected — see combat rules.)\n- End every turn at a real decision point — a choice, a called-for roll, or an open question — and WAIT. Never continue past that or answer for the player.\n- Adapt to anything the player does — no wrong moves, only consequences. Improvise; reward creativity. When things stall, introduce a complication or discovery.\n- Track what has happened and stay consistent. Stay fully in character as the GM — never mention being an AI, prompts, or these rules.`,
  ].join('\n\n');
}

function _archiveSession(sid) { if (!sid) return; fetch(`${API_BASE}/api/session/${sid}/archive`, { method: 'POST' }).catch(() => {}); }
// Reset one adventure's world-state (sheet, pack, quests, gold, map, memory, …)
// to defaults, locally and on the server. World-state is keyed by character id,
// so this affects only this adventure — your others are untouched.
function _wipeState(cid) {
  for (const [kind, keyFn] of Object.entries(_WS_KEYS)) {
    try { localStorage.removeItem(keyFn(cid)); } catch (e) {}
    _pushState(cid, kind, null);
  }
}
// Load screen for an adventure that already has a save. Resolves
// 'continue' | 'new' | null (cancelled).
function _adventureLoad(name) {
  return new Promise((resolve) => {
    const modal = $('studio-modal'); if (!modal) return resolve('continue');
    let ov = $('studio-advload');
    if (!ov) { ov = document.createElement('div'); ov.id = 'studio-advload'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
    const done = (v) => { ov.style.display = 'none'; resolve(v); };
    ov.innerHTML = `<div class="chronicle-sheet savechooser-sheet" role="dialog" aria-modal="true" aria-label="Load ${_esc(name)}">
      <div class="chronicle-bar"><h2>${_esc(name)}</h2><button class="studio-close" id="al-x" type="button" aria-label="Close">✕</button></div>
      <div class="chronicle-list"><p class="gm-hint">You have an adventure in progress here.</p>
        <div class="advload-btns"><button class="st-btn primary" id="al-cont" type="button">▶ Continue</button><button class="st-btn ghost" id="al-new" type="button">↻ New game</button></div>
        <p class="advload-note">A new game starts this adventure over — your sheet, pack, gold, and progress here are reset (the old save is archived, recoverable from the sidebar). Your other adventures are untouched.</p></div></div>`;
    ov.style.display = 'flex';
    $('al-x').addEventListener('click', () => done(null));
    ov.addEventListener('click', (e) => { if (e.target === ov) done(null); });
    $('al-cont').addEventListener('click', () => done('continue'));
    $('al-new').addEventListener('click', () => done('new'));
  });
}

// Starting kit by class (+ a common pack). Kept simple and flavourful.
const _CLASS_KIT = {
  Fighter: ['Longsword', 'Shield', 'Chain Shirt'], Barbarian: ['Greataxe', 'Handaxe', 'Hide Armor'],
  Rogue: ['Shortsword', 'Dagger', 'Leather Armor', 'Thieves’ Tools'], Ranger: ['Longbow', 'Arrows', 'Leather Armor', 'Shortsword'],
  Monk: ['Quarterstaff', 'Darts'], Paladin: ['Longsword', 'Shield', 'Chain Mail', 'Holy Symbol'],
  Wizard: ['Quarterstaff', 'Spellbook', 'Component Pouch'], Sorcerer: ['Dagger', 'Component Pouch'],
  Cleric: ['Mace', 'Shield', 'Chain Shirt', 'Holy Symbol'], Druid: ['Wooden Shield', 'Scimitar', 'Leather Armor'],
  Bard: ['Rapier', 'Lute', 'Leather Armor'], Warlock: ['Light Crossbow', 'Dagger', 'Leather Armor'],
};
const _COMMON_KIT = ['Torch', 'Rations', 'Potion of Healing'];

// ── World-adapted classes ─────────────────────────────────────────────────────
// You always pick a standard class; each world may carry a reskin table that
// renames it and re-flavors how its magic manifests. Same rules engine —
// world-specific words everywhere the class is spoken of. Embervale is the
// classic register (no reskin). Custom worlds may ship their own `reskins`
// object ({ flavor, names: {Class: 'Name'}, slots }) via the world forge.
const CLASS_RESKINS = {
  neonspire: {
    flavor: 'Magic here is black-market augmentation: spells are cybernetic mods, casting looks like hardware firing (arm-cannon incendiaries, optic dazzlers, subdermal servos), and holy power is corporate-grade medtech.',
    slots: 'mod charges',
    names: {
      Wizard: 'Body Modder', Sorcerer: 'Wetware Prodigy', Warlock: 'Debt-Bound Operator',
      Cleric: 'Street Medic', Druid: 'Bio-Sculptor', Bard: 'Signal Jockey',
      Paladin: 'Corp Enforcer', Ranger: 'Rooftop Stalker', Rogue: 'Ghost Runner',
      Fighter: 'Aug Soldier', Barbarian: 'Pit Brawler', Monk: 'Chrome Ascetic',
    },
  },
  everyday: {
    flavor: 'A mundane modern world: "magic" is charisma, luck, gadgets, and uncanny know-how. Describe spells as skills, tools, and improbable knack — never literal sorcery.',
    slots: 'grit',
    names: {
      Wizard: 'Tinkerer', Sorcerer: 'Natural', Warlock: 'Fixer',
      Cleric: 'Counselor', Druid: 'Naturalist', Bard: 'Performer',
      Paladin: 'Do-Gooder', Ranger: 'Outdoorsy Type', Rogue: 'Hustler',
      Fighter: 'Brawler', Barbarian: 'Hothead', Monk: 'Martial Artist',
    },
  },
};
function _reskinFor(worldId) {
  if (!worldId) return null;
  if (CLASS_RESKINS[worldId]) return CLASS_RESKINS[worldId];
  const w = getWorld(worldId);
  return (w && w.reskins && w.reskins.names) ? w.reskins : null;
}
function _classSkinName(worldId, cls) {
  const r = _reskinFor(worldId);
  return (r && cls && r.names[cls]) || '';
}
// Roll 4d6, drop the lowest.
function _roll4d6() { const d = [0, 0, 0, 0].map(() => 1 + Math.floor(Math.random() * 6)).sort((a, b) => a - b); return d[1] + d[2] + d[3]; }
// Seed a fresh adventure's sheet from the player's chosen identity (name,
// abilities, class → hit die/proficiencies/HP/slots) and grant a class kit +
// starting gold if the pack is empty. Used by the adventurer editor when it
// opens as the start-of-campaign gate — no separate creator system.
function _seedAdventureSheet(cid, ident) {
  const cls = (ident && ident.cls) || '';
  const p = CLASS_PRESETS[cls];
  const s = _loadSheet(cid);
  if (ident && ident.name) s.name = ident.name;
  if (ident && ident.abilities) s.abilities = { ...s.abilities, ...ident.abilities };
  // Heritage first — its ability bonuses must land before HP is rolled from CON.
  if (ident && ident.race && HERITAGES[ident.race]) {
    const h = HERITAGES[ident.race];
    s.race = ident.race;
    Object.entries(h.abil || {}).forEach(([k, v]) => { s.abilities[k] = (s.abilities[k] || 10) + v; });
    if (h.skills) s.profSkills = Array.from(new Set([...(s.profSkills || []), ...h.skills]));
    s.speed = h.speed; s.darkvision = h.dark || 0;
  }
  if (p) {
    s.cls = cls; s.hitDie = p.hitDie; s.profSaves = [...p.saves];
    s.profSkills = Array.from(new Set([...(s.profSkills || []), ...p.skills]));
    if (p.caster) s.slots = _fullCasterSlots(s.level || 1);
    s.hpMax = Math.max(1, p.hitDie + _mod(s.abilities.CON || 10)); s.hp = s.hpMax;
    s.features = _featuresGained(cls, 0, s.level || 1).map(f => f.name);   // level-1 class features from the start
    if (p.caster) _seedSpells(s, cls);                                     // and a starting spellbook
  }
  const bg = ident && BACKGROUNDS[ident.background];
  if (bg) {
    s.background = ident.background;
    s.profSkills = Array.from(new Set([...(s.profSkills || []), ...bg.skills]));
  }
  if (ident && ident.avatar) s.avatar = ident.avatar;         // the hero's face, for chat bubbles
  if (ident && ident.backstory) s.backstory = ident.backstory; // history the GM weaves in
  // World-adapted class: carry this world's name and flavor for the class on
  // the sheet so every display and every GM prompt speaks the world's language.
  const rk = ident && ident.world ? _reskinFor(ident.world) : null;
  if (rk && cls && rk.names[cls]) {
    s.clsSkin = rk.names[cls];
    s.clsFlavor = rk.flavor || '';
    s.slotName = rk.slots || '';
  } else { delete s.clsSkin; delete s.clsFlavor; delete s.slotName; }
  const inv = _loadInv(cid); inv.items = inv.items || [];
  if (!inv.items.length) {   // first-time kit only
    s.gold = (s.gold || 0) + 25;
    (_CLASS_KIT[cls] || []).concat(_COMMON_KIT).forEach((nm) => { const it = _mkItem(nm, inv.items.length); if (/arrows|darts?/i.test(nm)) it.qty = 10; else if (/rations/i.test(nm)) it.qty = 5; inv.items.push(it); });
    // A hero arrives DRESSED: kit weapons and armor start equipped, not
    // rattling loose in the pack.
    inv.equipped = inv.equipped || {};
    for (const it of inv.items) {
      const slot = _EQUIP_SLOTS.find(sl => sl.types.includes(it.type) && !inv.equipped[sl.key]);
      if (slot && ['weapon', 'shield', 'chest', 'armor', 'head', 'hands', 'feet', 'back'].includes(it.type)) inv.equipped[slot.key] = it.id;
    }
    _saveInv(cid, inv);
  }
  _saveSheet(cid, s);
}

// Templates are per-player, but campaign ids are deterministic
// (dm-<world>-<slug>) — two players starting the same campaign would collide.
// On a cross-owner 403, retry once with a stable per-user suffix so everyone
// gets their own copy (and their own resumable save).
let _me = '';
async function _whoAmI() {
  if (_me) return _me;
  try { const d = await (await fetch(`${API_BASE}/api/auth/status`)).json(); _me = d.username || ''; } catch {}
  return _me;
}
let _saveNeedsNamespace = false;   // once a base id 403s (owned by another player), namespace up front
async function _saveTemplateNamespaced(payload) {
  const post = (p) => fetch(`${API_BASE}/api/characters/studio/save`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(p) });
  // Skip the doomed unsuffixed attempt if we already learned this account can't own base ids.
  if (_saveNeedsNamespace && payload.id && !/-p-/.test(payload.id)) {
    const me = await _whoAmI();
    payload = { ...payload, id: `${payload.id}-p-${_slugify(me || 'guest')}` };
  }
  let res = await post(payload);
  if (res.status === 403 && payload.id && !/-p-/.test(payload.id)) {
    _saveNeedsNamespace = true;
    const me = await _whoAmI();
    payload = { ...payload, id: `${payload.id}-p-${_slugify(me || 'guest')}` };
    res = await post(payload);
  }
  return { res, data: await res.json(), id: payload.id };
}

async function startAdventure(world, story, cardEl) {
  if (_busy) return;
  _busy = true;
  if (cardEl) cardEl.classList.add('loading');
  let id = `dm-${world.id}-${story ? story.slug : 'freeroam'}`;
  const name = story ? story.title : `${world.name}: Free Roam`;
  try {
    const { res, data, id: finalId } = await _saveTemplateNamespaced({
      id, name,
      personality: _composeDMPrompt(world, story),
      relationship: 'Dungeon Master',
      world_id: world.id,
    });
    id = finalId;
    if (!res.ok || !data.ok) throw new Error(data.detail || data.error || 'Could not start');
    await loadCharacters();
    const saved = _chars.find(x => x.id === id) || data.template;
    // If a live save already exists here, show a Continue / New game screen.
    const existing = _loadMap()[id];
    let fresh = !existing;   // truly new adventure → run character creation
    if (existing) {
      let alive = false;
      try { const r = await fetch(`${API_BASE}/api/history/${existing}`); alive = r.ok; } catch {}
      if (alive) {
        if (cardEl) cardEl.classList.remove('loading');
        const choice = await _adventureLoad(name);
        if (!choice) { _busy = false; return; }           // cancelled — stay on the world detail
        if (choice === 'new') {
          _archiveSession(existing);                       // keep the old save (recoverable)
          const map = _loadMap(); delete map[id]; _saveMap(map);  // _ensureSession makes a fresh session
          _wipeState(id);                                  // reset this adventure's sheet/pack/quests/gold
          fresh = true;
        }
      } else { fresh = true; }   // mapped session vanished — treat as new
    }
    if (cardEl) cardEl.classList.remove('loading');
    if (fresh) {
      // Character creation is the door into a new adventure — closing it
      // cancels the start instead of dropping you in as nobody.
      const made = await new Promise(res => openPlayerEditor({ cid: id, gate: true, world: world.id, onDone: res }));
      if (!made) return;
      await _sessionZero(id);   // then set the tone — it shapes the very first scene
    }
    openChat(saved);
    _ensurePortrait(saved, getGMPortrait(world.id));   // give the GM a face that fits the world
  } catch (e) {
    if (cardEl) cardEl.classList.remove('loading');
    console.error('Start adventure failed:', e);
  } finally {
    _busy = false;
  }
}

async function enterWorldCharacter(world, c, cardEl) {
  if (_busy) return;
  _busy = true;
  if (cardEl) cardEl.classList.add('loading');
  let id = worldCharId(world.id, c.slug);
  try {
    const { res, data, id: finalId } = await _saveTemplateNamespaced({
      id, name: c.name,
      personality: c.persona,
      appearance: c.appearance,
      setting: `${world.name} — ${world.kind}. ${world.tagline}`,
      relationship: c.role,
      world: world.lore,
      world_id: world.id,
    });
    id = finalId;
    if (!res.ok || !data.ok) throw new Error(data.detail || data.error || 'Could not enter');
    await loadCharacters();
    const saved = _chars.find(x => x.id === id) || data.template;
    openChat(saved);
    _ensurePortrait(saved);   // give the prebuilt cast a real face (lazy, ~15s)
  } catch (e) {
    if (cardEl) { cardEl.classList.remove('loading'); }
    console.error('Enter world character failed:', e);
  } finally {
    _busy = false;
  }
}

// Generate + attach a portrait for a character that has none yet, then save it as
// their avatar + IP-Adapter reference so future pictures stay on-model.
async function _ensurePortrait(char, promptOverride) {
  if (!char || char.avatar) return;
  const prompt = promptOverride || char.appearance || `character portrait of ${char.name}`;
  try {
    const g = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt }),
    });
    const gd = await g.json();
    if (!gd.ok || !gd.filename) return;
    await fetch(`${API_BASE}/api/characters/studio/save`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: char.id, name: char.name,
        personality: char.personality || '', appearance: char.appearance || '',
        setting: char.setting || '', relationship: char.relationship || '',
        world: char.world || '', world_id: char.world_id || '',
        image_filename: gd.filename,
      }),
    });
    char.avatar = gd.image_url;
    if (_chat.char && _chat.char.id === char.id) {
      _chat.char.avatar = gd.image_url;
      const fb = document.querySelector('#studio-chat .cb-portrait-fallback');
      if (fb) {
        const img = document.createElement('img');
        img.className = 'cb-portrait'; img.src = gd.image_url; img.alt = 'Portrait of ' + char.name;
        fb.replaceWith(img);
      }
    }
    await loadCharacters();
  } catch (_) { /* portrait is a nicety — ignore failures */ }
}

// ── Campaigns view ───────────────────────────────────────────────────────────
// Two sections: startable premises (across every world) + a guided forge, and
// the adventures already in motion (resume-able). A "campaign" = a story premise
// that lives in a world; ongoing tales are the DM save-personas.
function renderCampaigns() {
  const root = $('studio-campaigns'); if (!root) return;
  applyWorldTheme('');
  const worlds = listWorlds();
  const premises = [];
  worlds.forEach(w => (getStories(w.id) || []).forEach(s => premises.push({ w, s })));
  const forgeCard = `<button class="char-card new-card" data-forge-campaign="1" type="button">
      <span class="nc-rune" aria-hidden="true">✦</span><span class="nc-label">Forge a campaign</span>
    </button>`;
  const premiseCards = premises.map(({ w, s }, i) => `
    <div class="camp-card" role="button" tabindex="0" data-world="${_esc(w.id)}" data-story="${_esc(s.slug)}" aria-label="Begin ${_esc(s.title)}" style="animation-delay:${Math.min(i * 45, 360)}ms">
      <div class="camp-body">
        <p class="camp-title">${_esc(s.title)}</p>
        <p class="camp-premise">${_esc(s.premise || '')}</p>
        <p class="camp-world">🌍 ${_esc(w.name)}</p>
      </div>
    </div>`).join('');
  const adventures = (_chars || []).filter(c => _isDM(c));
  const taleCards = adventures.map((c, i) => {
    const w = c.world_id ? getWorld(c.world_id) : null;
    const cap = _esc(c.relationship || (w ? w.name : '') || 'Adventure');
    const art = c.avatar
      ? `<img class="camp-thumb" src="${_esc(c.avatar)}" alt="" loading="lazy">`
      : `<div class="camp-thumb camp-thumb-ph" aria-hidden="true">GM</div>`;
    return `<div class="camp-card tale" role="button" tabindex="0" data-resume="${_esc(c.id)}" aria-label="Resume ${_esc(c.name)}" style="animation-delay:${Math.min(i * 45, 360)}ms">
      ${art}<div class="camp-body"><p class="camp-title">${_esc(c.name)}</p><p class="camp-world">${cap}</p></div>
    </div>`;
  }).join('');

  root.innerHTML = `
    <h1 class="studio-h">Campaigns</h1>
    <p class="studio-sub">Stories to play, and the tales already in motion.</p>
    <p class="section-rule">Start a campaign <span class="rule-hint">a premise sets the stage; a Game Master runs it</span></p>
    <div class="roster-grid">${forgeCard}${premiseCards || (worlds.length ? '' : `<p class="gm-hint" style="align-self:center">Forge a world first — campaigns live inside one.</p>`)}</div>
    ${adventures.length ? `<p class="section-rule">Your ongoing tales <span class="rule-hint">pick up where you left off</span></p><div class="roster-grid">${taleCards}</div>` : ''}`;

  root.querySelector('[data-forge-campaign]')?.addEventListener('click', _forgeCampaignPickWorld);
  root.querySelectorAll('.camp-card[data-story]').forEach(card => {
    const go = () => { const w = getWorld(card.dataset.world); if (!w) return; const s = (getStories(w.id) || []).find(x => x.slug === card.dataset.story) || null; startAdventure(w, s); };
    card.addEventListener('click', go);
    card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
  });
  root.querySelectorAll('.camp-card[data-resume]').forEach(card => {
    const c = (_chars || []).find(x => x.id === card.dataset.resume);
    const go = () => { if (c) openChat(c); };
    card.addEventListener('click', go);
    card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
  });
}
// The campaign forge needs a world to set the story in — pick one, then draft.
function _forgeCampaignPickWorld() {
  const worlds = listWorlds();
  if (!worlds.length) { renderWorlds(); switchView('worlds'); return; }
  if (worlds.length === 1) { openCampaignsmith(worlds[0]); return; }
  const ov = _smithOverlay(); if (!ov) return;
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Choose a world">
    <div class="chronicle-bar"><h2>✦ Forge a campaign — in which world?</h2><button class="studio-close" id="cwpick-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list"><p class="gm-hint">Which world does this story unfold in?</p>
      <div class="roster-grid">${worlds.map(w => `<button class="char-card" data-pick="${_esc(w.id)}" type="button"><div class="char-card-body"><p class="char-card-name">${_esc(w.name)}</p><p class="char-card-tag">${_esc(w.kind || '')}</p></div></button>`).join('')}</div>
    </div></div>`;
  $('cwpick-close').addEventListener('click', _smithClose);
  ov.addEventListener('click', (e) => { if (e.target === ov) _smithClose(); });
  ov.querySelectorAll('[data-pick]').forEach(b => b.addEventListener('click', () => { const w = getWorld(b.dataset.pick); _smithClose(); if (w) openCampaignsmith(w); }));
}

// ── Roster view ──────────────────────────────────────────────────────────────
function renderRoster() {
  const root = $('studio-roster');
  if (!root) return;
  applyWorldTheme('');   // roster spans all worlds → neutral arcane theme
  const EDIT_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  const DEL_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>';
  const cardHtml = (c, i) => {
    const tag = _esc(c.relationship || c.setting || c.appearance || '');
    const art = c.avatar
      ? `<img class="char-portrait" src="${_esc(c.avatar)}" alt="Portrait of ${_esc(c.name)}" loading="lazy">`
      : `<div class="char-portrait-fallback" aria-hidden="true">${_esc(_initial(c.name))}</div>`;
    return `<div class="char-card" data-cid="${_esc(c.id)}" role="button" tabindex="0" aria-label="Open ${_esc(c.name)}" style="animation-delay:${Math.min(i * 45, 360)}ms">
      <div class="char-card-actions">
        <button class="cc-act" data-edit="${_esc(c.id)}" type="button" title="Edit" aria-label="Edit ${_esc(c.name)}">${EDIT_ICON}</button>
        <button class="cc-act danger" data-del="${_esc(c.id)}" type="button" title="Delete" aria-label="Delete ${_esc(c.name)}">${DEL_ICON}</button>
      </div>
      ${art}
      <div class="char-card-body">
        <p class="char-card-name">${_esc(c.name)}</p>
        ${tag ? `<p class="char-card-tag">${tag}</p>` : ''}
      </div>
    </div>`;
  };
  // Un-mix the roster: heroes & companions you play, Game Masters who run tales.
  // Only deliberately-forged GMs (dm-custom-*) live here; the per-adventure DMs
  // (dm-<world>-<story>) belong to Campaigns → ongoing tales, not the roster.
  const heroCards = _chars.filter(c => !_isDM(c)).map(cardHtml).join('');
  const gmCards = _chars.filter(c => _isDM(c) && /^dm-custom-/.test(c.id)).map(cardHtml).join('');
  const newHero = `<button class="char-card new-card" data-new="hero" type="button"><span class="nc-rune" aria-hidden="true">✦</span><span class="nc-label">Create new character</span></button>`;
  const newGM = `<button class="char-card new-card" data-new="gm" type="button"><span class="nc-rune" aria-hidden="true">🎲</span><span class="nc-label">Create a Game Master</span></button>`;

  root.innerHTML = `
    <h1 class="studio-h">Characters</h1>
    <p class="studio-sub">Your heroes, and the Game Masters who run their tales.</p>
    <button class="st-btn small" id="roster-you-btn" type="button" style="margin-bottom:20px">✦ Your adventurer</button>
    <button class="st-btn small" id="roster-group-btn" type="button" style="margin-bottom:20px;margin-left:8px">💬 Group chat</button>
    <p class="section-rule">Heroes &amp; companions <span class="rule-hint">who you play, and who travels with you</span></p>
    <div class="roster-grid">${newHero}${heroCards}</div>
    <p class="section-rule">Game Masters <span class="rule-hint">the voices that run your adventures</span></p>
    <div class="roster-grid">${newGM}${gmCards || '<p class="gm-hint" style="align-self:center;margin:0">No custom Game Masters yet — forge one to reuse across campaigns. (Your ongoing tales live under the Campaigns tab.)</p>'}</div>
  `;

  root.querySelectorAll('[data-new]').forEach(b => b.addEventListener('click', () => openForge(null, b.dataset.new === 'gm' ? 'gm' : 'companion')));
  $('roster-you-btn')?.addEventListener('click', () => openPlayerEditor());
  $('roster-group-btn')?.addEventListener('click', () => _openGroupPicker());
  root.querySelectorAll('.char-card[data-cid]').forEach(card => {
    const c = _chars.find(x => x.id === card.dataset.cid);
    card.addEventListener('click', (e) => {
      if (e.target.closest('.cc-act')) return;   // edit/delete handle themselves
      if (c) openChat(c);
    });
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); if (c) openChat(c); }
    });
    card.querySelector('[data-edit]')?.addEventListener('click', (e) => { e.stopPropagation(); if (c) openForge(c); });
    card.querySelector('[data-del]')?.addEventListener('click', (e) => { e.stopPropagation(); deleteCharacter(c); });
  });
}

async function deleteCharacter(c) {
  if (!c) return;
  const msg = `Delete "${c.name}"?\n\nThis removes the persona and its memories. (The chat history and any saved images are left untouched.)`;
  const ok = window.styledConfirm
    ? await window.styledConfirm(msg, { confirmText: 'Delete', danger: true })
    : window.confirm(msg);
  if (!ok) return;
  try {
    await fetch(`${API_BASE}/api/presets/templates/${encodeURIComponent(c.id)}`, { method: 'DELETE' });
    const map = _loadMap();
    if (map[c.id]) { delete map[c.id]; _saveMap(map); }
    await loadCharacters();
    renderRoster();
  } catch (e) {
    console.error('Delete character failed:', e);
  }
}

// ── Forge view ───────────────────────────────────────────────────────────────
function openForge(char, type) {
  _forge = { id: char ? char.id : null, filename: '', imageUrl: char ? (char.avatar || '') : '', type: type || 'companion' };
  renderForge(char);
  switchView('forge');
}

const _SPARK = (field) =>
  `<button class="spark-btn" data-spark="${field}" type="button" aria-label="Suggest ideas">
     <span class="sk">✦</span> Suggest</button>`;

function renderForge(char) {
  const root = $('studio-forge');
  if (!root) return;
  const v = (k) => _esc(char ? (char[k] || '') : '');
  const imgHtml = (char && char.avatar)
    ? `<img src="${_esc(char.avatar)}" alt="Portrait of ${v('name')}">`
    : `<div class="fc-empty"><span class="fc-rune" aria-hidden="true">✦</span>Describe them, then conjure a portrait.</div>`;

  root.innerHTML = `
    <button class="chat-back" id="forge-back" type="button">‹ Back to roster</button>
    <h1 class="studio-h" style="margin-top:8px">${char ? 'Edit ' + v('name') : 'Forge a character'}</h1>
    <p class="studio-sub">Conjure a face, breathe in a personality, then sketch the world they live in.</p>
    ${char ? '' : `<div class="forge-type" role="group" aria-label="What are you forging?">
      <button type="button" class="st-btn small forge-type-btn on" data-ftype="companion" aria-pressed="true">🧝 Companion — someone to talk to</button>
      <button type="button" class="st-btn small forge-type-btn" data-ftype="gm" aria-pressed="false">🎲 Game Master — someone to run your adventures</button>
    </div>`}
    <div class="forge">
      <div class="forge-stage">
        <div class="forge-canvas" id="forge-canvas">${imgHtml}</div>
        <div class="forge-actions" style="margin-top:12px">
          <button class="st-btn primary" id="forge-generate" type="button">Conjure portrait</button>
          <span class="forge-status" id="forge-status"></span>
        </div>
      </div>

      <div class="forge-fields">
        <div class="field-row">
          <label for="cs-prompt">Portrait prompt</label>
          <textarea id="cs-prompt" rows="3" placeholder="a wandering half-elf bard, silver hair, storm-grey eyes, travel-worn cloak, lantern light"></textarea>
        </div>

        <div class="field-row">
          <div class="field-head"><label for="cs-name">Name</label>${_SPARK('name')}</div>
          <input type="text" id="cs-name" maxlength="50" placeholder="Their name…" value="${v('name')}" autocomplete="off">
          <div class="chip-row" data-chips="name"></div>
        </div>

        <div class="field-row">
          <div class="field-head"><label for="cs-personality">Personality</label>${_SPARK('personality')}</div>
          <textarea id="cs-personality" rows="4" placeholder="Who are they? Temperament, voice, quirks…">${v('personality')}</textarea>
          <div class="chip-row" data-chips="personality"></div>
        </div>

        <div class="field-row">
          <div class="field-head"><label for="cs-appearance">Appearance anchor</label>${_SPARK('appearance')}</div>
          <textarea id="cs-appearance" rows="2" placeholder="Auto-filled from the portrait — keeps future pictures on-model. Editable.">${v('appearance')}</textarea>
          <div class="chip-row" data-chips="appearance"></div>
        </div>

        <p class="section-rule">World &amp; roleplay</p>

        <div class="field-row">
          <div class="field-head"><label for="cs-setting">Setting</label>${_SPARK('setting')}</div>
          <input type="text" id="cs-setting" placeholder="Where their story unfolds…" value="${v('setting')}" autocomplete="off">
          <div class="chip-row" data-chips="setting"></div>
        </div>

        <div class="field-row">
          <div class="field-head"><label for="cs-relationship">Their bond with you</label>${_SPARK('relationship')}</div>
          <input type="text" id="cs-relationship" placeholder="Companion, rival, mentor, stranger…" value="${v('relationship')}" autocomplete="off">
          <div class="chip-row" data-chips="relationship"></div>
        </div>

        <div class="field-row">
          <div class="field-head"><label for="cs-scene">Opening scene</label>${_SPARK('scene')}</div>
          <input type="text" id="cs-scene" placeholder="Where this first conversation begins…" value="${v('scene')}" autocomplete="off">
          <div class="chip-row" data-chips="scene"></div>
        </div>

        <div class="field-row">
          <div class="field-head"><label for="cs-world">Lore &amp; backstory</label>${_SPARK('world')}</div>
          <textarea id="cs-world" rows="3" placeholder="History, secrets, ties that bind — the canon they never forget.">${v('world')}</textarea>
          <div class="chip-row" data-chips="world"></div>
        </div>

        <div class="forge-actions">
          <button class="st-btn primary" id="forge-save-chat" type="button" disabled>Save &amp; enter the tale ›</button>
          <button class="st-btn ghost" id="forge-save" type="button" disabled>Save character</button>
        </div>
        <p class="forge-status" id="forge-save-status"></p>
      </div>
    </div>`;

  // If editing an existing character with a portrait, treat it as already-imaged
  // so Save is enabled without re-generating.
  if (char && char.avatar) {
    _forge.filename = (char.avatar.split('/').pop() || '');
  }

  $('forge-back').addEventListener('click', () => { renderRoster(); switchView('roster'); });
  $('forge-generate').addEventListener('click', generate);
  $('forge-save-chat').addEventListener('click', () => save(true));
  $('forge-save').addEventListener('click', () => save(false));
  $('cs-name').addEventListener('input', _syncForgeButtons);
  // Companion vs Game Master: same forge, different destiny. A GM gets the
  // full adventure HUD (sheet, dice, quests, map) instead of a plain chat.
  _forge.type = _forge.type || 'companion';
  root.querySelectorAll('.forge-type-btn').forEach(b => b.addEventListener('click', () => {
    _forge.type = b.dataset.ftype;
    root.querySelectorAll('.forge-type-btn').forEach(x => { const on = x === b; x.classList.toggle('on', on); x.setAttribute('aria-pressed', String(on)); });
    const pers = $('cs-personality'), rel = $('cs-relationship'), scene = $('cs-scene');
    if (_forge.type === 'gm') {
      if (pers) pers.placeholder = 'How they run a table — tone, pacing, favorite twists, how merciful or cruel…';
      if (rel) { rel.value = 'Dungeon Master'; rel.closest('.field-row').style.display = 'none'; }
      if (scene) scene.placeholder = 'The kind of opening scenes they love to set…';
      const sc = $('forge-save-chat'); if (sc) sc.textContent = 'Save & run an adventure ›';
    } else {
      if (pers) pers.placeholder = 'Who are they? Temperament, voice, quirks…';
      if (rel) { rel.closest('.field-row').style.display = ''; if (rel.value === 'Dungeon Master') rel.value = ''; }
      const sc = $('forge-save-chat'); if (sc) sc.textContent = 'Save & enter the tale ›';
    }
  }));
  root.querySelectorAll('.spark-btn').forEach(b =>
    b.addEventListener('click', () => suggest(b.dataset.spark, b)));
  _syncForgeButtons();
}

function _syncForgeButtons() {
  const hasName = !!($('cs-name')?.value || '').trim();
  const hasImg = !!_forge.filename;
  const ready = hasName && hasImg && !_busy;
  const s = $('forge-save-chat'); if (s) s.disabled = !ready;
  const s2 = $('forge-save'); if (s2) s2.disabled = !ready;
}

function _forgeStatus(msg, isError) {
  const el = $('forge-status');
  if (el) { el.textContent = msg || ''; el.classList.toggle('error', !!isError); }
}

async function generate() {
  if (_busy) return;
  const prompt = ($('cs-prompt')?.value || '').trim();
  if (!prompt) { _forgeStatus('Describe the character first.', true); return; }
  _busy = true; _syncForgeButtons();
  const btn = $('forge-generate');
  if (btn) { btn.disabled = true; btn.textContent = 'Conjuring…'; }
  _forgeStatus('Painting your character (~15s)…');
  try {
    const res = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt }),
    });
    const data = await res.json();
    if (!res.ok || !data.ok || !data.image_url) throw new Error(data.detail || data.error || `Generation failed (${res.status})`);
    _forge.filename = data.filename || '';
    _forge.imageUrl = data.image_url;
    const canvas = $('forge-canvas');
    if (canvas) canvas.innerHTML = `<img src="${_esc(data.image_url)}" alt="Generated portrait">`;
    _forgeStatus('Lovely. Tweak the prompt to re-roll, or fill in the rest below.');
    const appEl = $('cs-appearance');
    if (appEl && !appEl.value.trim()) _describe(prompt);
  } catch (e) {
    _forgeStatus(e.message || 'Generation failed.', true);
  } finally {
    _busy = false;
    if (btn) { btn.disabled = false; btn.textContent = 'Conjure portrait'; }
    _syncForgeButtons();
  }
}

async function _describe(prompt) {
  if (!_forge.filename) return;
  try {
    const res = await fetch(`${API_BASE}/api/characters/studio/describe`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ filename: _forge.filename, prompt }),
    });
    const data = await res.json();
    const appEl = $('cs-appearance');
    if (appEl && data.appearance && !appEl.value.trim()) appEl.value = data.appearance;
  } catch {}
}

function _gatherContext() {
  const get = (id) => ($(id)?.value || '').trim();
  const bits = [];
  const map = { 'cs-personality': 'Personality', 'cs-appearance': 'Appearance',
    'cs-setting': 'Setting', 'cs-relationship': 'Relationship', 'cs-scene': 'Opening scene', 'cs-world': 'Lore' };
  for (const [id, label] of Object.entries(map)) { const v = get(id); if (v) bits.push(`${label}: ${v}`); }
  return bits.join('\n');
}

async function suggest(field, btn) {
  if (btn.getAttribute('aria-busy') === 'true') return;
  btn.setAttribute('aria-busy', 'true');
  const orig = btn.innerHTML;
  btn.innerHTML = '<span class="sk st-spin">✦</span> …';
  const chipRow = document.querySelector(`#studio-forge .chip-row[data-chips="${field}"]`);
  try {
    const res = await fetch(`${API_BASE}/api/characters/studio/suggest`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ field, name: ($('cs-name')?.value || '').trim(), context: _gatherContext(), model: _modelLabel() }),
    });
    const data = await res.json();
    const list = (data.ok && Array.isArray(data.suggestions)) ? data.suggestions : [];
    if (chipRow) {
      chipRow.innerHTML = list.map((s, i) =>
        `<button class="chip" type="button" style="animation-delay:${i * 40}ms" data-val="${_esc(s)}">${_esc(s)}</button>`).join('');
      chipRow.querySelectorAll('.chip').forEach(chip =>
        chip.addEventListener('click', () => _applySuggestion(field, chip.dataset.val)));
    }
  } catch {
    if (chipRow) chipRow.innerHTML = `<span class="field-hint">Couldn't fetch ideas — try again.</span>`;
  } finally {
    btn.setAttribute('aria-busy', 'false');
    btn.innerHTML = orig;
  }
}

function _applySuggestion(field, val) {
  const idMap = { name: 'cs-name', personality: 'cs-personality', appearance: 'cs-appearance',
    setting: 'cs-setting', relationship: 'cs-relationship', scene: 'cs-scene', world: 'cs-world' };
  const el = $(idMap[field]);
  if (!el) return;
  if (field === 'name' || field === 'setting' || field === 'relationship' || field === 'scene') {
    el.value = val;                                 // single-value fields replace
  } else {
    el.value = el.value.trim() ? (el.value.trim() + (field === 'appearance' ? ', ' : '\n') + val) : val; // prose appends
  }
  el.focus();
  if (field === 'name') _syncForgeButtons();
}

async function save(enterChat) {
  if (_busy) return;
  const name = ($('cs-name')?.value || '').trim();
  if (!name || !_forge.filename) { _syncForgeButtons(); return; }
  _busy = true; _syncForgeButtons();
  const stat = $('forge-save-status');
  if (stat) { stat.textContent = 'Binding the character…'; stat.classList.remove('error'); }
  const get = (id) => ($(id)?.value || '').trim();
  // Editing an existing character whose portrait wasn't re-generated: don't re-send
  // the old avatar filename as a new reference (it isn't a generated-images file).
  const isExistingAvatar = _forge.id && _forge.imageUrl && !_forge.imageUrl.includes('/api/generated-image/')
    ? false : true;
  const isGM = _forge.type === 'gm' && !_forge.id;
  const payload = {
    id: _forge.id || (isGM ? `dm-custom-${_slugify(name)}-${Date.now().toString(36).slice(-4)}` : ''),
    name,
    personality: isGM ? _composeCustomGMPrompt(name, get('cs-personality'), get('cs-setting'), get('cs-scene'), get('cs-world')) : get('cs-personality'),
    appearance: get('cs-appearance'),
    setting: get('cs-setting'),
    relationship: isGM ? 'Dungeon Master' : get('cs-relationship'),
    scene: get('cs-scene'),
    world: get('cs-world'),
  };
  if (_forge.filename && _forge.imageUrl.includes('/api/generated-image/')) payload.image_filename = _forge.filename;
  else if (_forge.filename && !_forge.id) payload.image_filename = _forge.filename;
  try {
    const res = await fetch(`${API_BASE}/api/characters/studio/save`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.detail || data.error || `Save failed (${res.status})`);
    await loadCharacters();
    const saved = _chars.find(c => c.id === data.template.id) || data.template;
    if (enterChat) openChat(saved);
    else { renderRoster(); switchView('roster'); }
  } catch (e) {
    if (stat) { stat.textContent = e.message || 'Save failed.'; stat.classList.add('error'); }
  } finally {
    _busy = false; _syncForgeButtons();
  }
}

// ── Chat view ────────────────────────────────────────────────────────────────
async function openChat(char) {
  if (_view && _view !== 'chat') _chatReturnView = _view;   // remember where we came from for "‹ back"
  _chat.group = null;   // leaving any group chat
  _chat.char = char;
  _chat.playAs = '';
  if (_isDM(char)) {   // title-screen "Continue" target + its save-file caption
    try {
      localStorage.setItem(LAST_ADV_KEY, char.id);
      const s = _loadSheet(char.id), ck = _loadClock(char.id);
      localStorage.setItem(LAST_ADV_KEY + '-meta', JSON.stringify({ title: char.name, level: s.level || 1, day: ck.day || 1, hero: s.name || '', complete: !!s.campaignComplete }));
    } catch {}
  }
  await _hydrateState(char.id);   // pull durable world state into the local cache before anything reads it
  await _hydrateRel();            // and the cross-session relationship store
  if (char.world_id) { _seedLocations(char.id, char.world_id); _seedCast(char.id, char.world_id); }   // stock the atlas + track the authored cast from turn 1
  const w = char.world_id ? getWorld(char.world_id) : null;
  if (w) _world = w;
  applyWorldTheme(char.world_id || '');
  if (char.world_id) _applyBackdrop(char.world_id);
  _startMusic(char.world_id || '');   // per-world ambience (silent if no file present)
  if (_isDM(char)) _applyAmbient(char.id);   // reactive soundscape for the current scene
  switchView('chat');
  if (_isDM(char)) _seedSheetFromPlayer(char.id);   // your default hero seeds the sheet
  renderChatShell(char);
  _renderPartyChips(char.id);                       // companions ride in the banner
  _partyStart(char.id);                             // shared table? start the poll + lock
  _fxTitleCard(char.name, _isDM(char) ? (w ? w.name : 'Adventure') : (char.relationship || char.setting || ''));
  const thread = $('studio-thread');
  if (thread) thread.innerHTML = `<div class="rp-typing">Opening the gate…</div>`;
  try {
    // Activate this character as the live persona (no admin needed).
    await fetch(`${API_BASE}/api/characters/studio/activate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: char.id, name: char.name }),
    });
    await _ensureSession(char);
    await _loadChatHistory();
    // A Dungeon Master opens the scene first. On a fresh adventure (no history),
    // auto-trigger the opening narration so the player arrives mid-scene.
    if (_isDM(char) && !$('studio-thread')?.querySelector('.rp-msg')) {
      _howToPlay();   // one-time coach card for brand-new players
      _startTour();   // …and a one-time spotlight walk over the table itself
      _dmKickoff();
    }
  } catch (e) {
    if (thread) thread.innerHTML = `<div class="rp-typing">Couldn't open this chat: ${_esc(e.message || e)}</div>`;
  }
}

function renderChatShell(char) {
  const root = $('studio-chat');
  if (!root) return;
  const isDM = _isDM(char);
  const tag = isDM ? 'Dungeon Master' : _esc(char.relationship || char.setting || '');
  const art = char.avatar
    ? `<img class="cb-portrait" src="${_esc(char.avatar)}" alt="${isDM ? 'Game Master' : 'Portrait of ' + _esc(char.name)}">`
    : (isDM
        ? `<div class="cb-portrait-fallback dm-badge" aria-hidden="true">GM</div>`
        : `<div class="cb-portrait-fallback" aria-hidden="true">${_esc(_initial(char.name))}</div>`);
  // You ARE your hero; the only other voices you may speak with are the NPC
  // companions currently in your party (not other players, not the roster).
  // Who you speak/act as: yourself (the hero) + party companions + any other
  // character you've created — so "you" isn't locked to a single name.
  const _playAsOptions = () => {
    const opts = [`<option value="">${_esc(_playerName())}</option>`];
    const seen = new Set([(_playerName() || '').toLowerCase()]);
    const add = (name, group) => {
      const k = (name || '').toLowerCase(); if (!name || seen.has(k)) return; seen.add(k);
      opts.push(`<option value="${_esc(name)}"${_chat.playAs === name ? ' selected' : ''}${group ? ` data-grp="${group}"` : ''}>${_esc(name)}</option>`);
    };
    _companions(char.id).filter(c => !c.guest).forEach(c => add(c.name));
    (_chars || []).filter(t => t && !_isDM(t) && t.id !== char.id).forEach(t => add(t.name));
    return opts.join('');
  };
  const playAsOpts = _playAsOptions();
  const _mote = ({ embervale: 'rgba(232,193,113,.5)', neonspire: 'rgba(120,220,255,.5)', everyday: 'rgba(220,220,240,.32)' })[char.world_id] || 'rgba(232,193,113,.45)';
  root.innerHTML = `
    <div class="scene-motes" aria-hidden="true" style="--mote:${_mote}">${Array.from({ length: 12 }, () => '<span></span>').join('')}</div>
    <div class="chat-banner">
      <button class="chat-back" id="chat-back" type="button" aria-label="Back to roster">‹</button>
      ${art}
      <div class="chat-banner-id">
        <p class="cb-name">${_esc(char.name)}</p>
        ${tag ? `<p class="cb-tag">${tag}</p>` : ''}
        <div class="cb-chips">${isDM ? `<button type="button" id="studio-clock" class="clock-chip" title="Time of day — click to let time pass"></button>` : ''}${isDM ? `<button type="button" id="studio-objective" class="obj-chip" title="Your current objective — click for the quest log" style="display:none"></button>` : ''}${isDM ? `<button type="button" id="studio-inspiration" class="insp-chip" style="display:none"></button>` : ''}</div>
      </div>
      <div class="chat-banner-right">
        <div class="chat-actions">
          ${isDM ? `<button type="button" id="studio-sheet-btn" class="st-btn ghost small cb-act-btn" title="Character sheet & inventory">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M8 13h8"/><path d="M8 17h5"/></svg>
            Sheet
          </button>
          <button type="button" id="studio-pack-btn" class="st-btn ghost small cb-act-btn" title="Your pack — inventory & loot">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 8a4 4 0 0 0-8 0"/><path d="M5 8h14l1.5 12.5a1 1 0 0 1-1 1.1H4.5a1 1 0 0 1-1-1.1L5 8z"/></svg>
            Pack
          </button>
          <button type="button" id="studio-quests-btn" class="st-btn ghost small cb-act-btn" title="Quest log & level — your goals and XP">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/><path d="M9 7h6"/><path d="M9 11h4"/></svg>
            Quests
          </button>
          <button type="button" id="studio-combat-btn" class="st-btn ghost small cb-act-btn" title="Combat tracker — initiative, HP & turns">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14.5 17.5 3 6V3h3l11.5 11.5"/><path d="m13 19 6-6"/><path d="m16 16 4 4"/><path d="m19 21 2-2"/><path d="M14.5 6.5 18 3h3v3l-3.5 3.5"/><path d="m5 14 4 4"/><path d="m7 17-2 2"/><path d="m3 21 2-2"/></svg>
            Combat
          </button>
          <button type="button" id="studio-map-btn" class="st-btn ghost small cb-act-btn" title="Tactical battle map">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>
            Map
          </button>` : ''}
          <button type="button" id="studio-lore-btn" class="st-btn ghost small cb-act-btn" title="The Lorebook — monsters, spells, classes, and this world">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/></svg>
            Lore
          </button>
          ${!isDM ? `<button type="button" id="studio-tts-btn" class="st-btn ghost small cb-act-btn" aria-pressed="false" title="Narration — hear the story aloud">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>
            Narrate
          </button>
          <button type="button" id="studio-sfx-btn" class="st-btn ghost small cb-act-btn" title="Sound effects on/off"><span class="sfx-ico" aria-hidden="true">🔊</span> SFX</button>
          <button type="button" id="studio-look-btn" class="st-btn ghost small cb-act-btn" title="Edit the look — what stays the same in every picture (keep it person-only for open poses)">✎ Look</button>
          <button type="button" id="studio-notes-btn" class="st-btn ghost small cb-act-btn" title="Your private notes">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 0 1 3 3L12 15l-4 1 1-4z"/></svg>
            Notes
          </button>
          <button type="button" id="studio-save-snap" class="st-btn ghost small cb-act-btn" title="Save a snapshot of the story so far">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>
            Save
          </button>
          <button type="button" id="studio-chronicle" class="st-btn ghost small cb-act-btn" title="View saved snapshots">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>
            Chronicle
          </button>` : ''}
          ${isDM ? `<div class="cb-more-wrap"><button type="button" id="studio-more-btn" class="st-btn ghost small cb-act-btn" aria-haspopup="true" aria-expanded="false" title="Everything else — party, narration, GM tuning, world records, saves">⋯ More</button>
          <div class="cb-more-menu" id="studio-more-menu" hidden>
            <button type="button" id="studio-party-btn" class="cb-menu-item" title="Play together — open a table for friends">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
              Party — play with friends
            </button>
            <button type="button" id="studio-tts-btn" class="cb-menu-item" aria-pressed="false" title="Narration — hear the story aloud">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>
              Narrate the story
            </button>
            <button type="button" id="studio-sfx-btn" class="cb-menu-item" title="Sound effects on/off"><span class="sfx-ico" aria-hidden="true">🔊</span> Sound effects</button>
            <button type="button" id="studio-dice-skin-btn" class="cb-menu-item" title="Pick the dice set you roll with"><span aria-hidden="true">🎲</span> Dice skins</button>
            <button type="button" id="studio-gm-btn" class="cb-menu-item" title="Tune the Game Master">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg>
              Tune the GM
            </button>
            <button type="button" id="studio-scene-btn" class="cb-menu-item" title="Set the scene backdrop">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>
              Scene backdrop
            </button>
            <button type="button" id="studio-mem-btn" class="cb-menu-item" title="Campaign memory — what the GM remembers">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5a3 3 0 1 0-5.997.125 4 4 0 0 0-2.526 5.77 4 4 0 0 0 .556 6.588A4 4 0 1 0 12 18Z"/><path d="M12 5a3 3 0 1 1 5.997.125 4 4 0 0 1 2.526 5.77 4 4 0 0 1-.556 6.588A4 4 0 1 1 12 18Z"/></svg>
              Campaign memory
            </button>
            <button type="button" id="studio-codex-btn" class="cb-menu-item" title="Cast codex — who you've met & how they feel about you">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
              Cast — who you've met
            </button>
            <button type="button" id="studio-realm-btn" class="cb-menu-item" title="The realm — places & factions">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
              Realm — places & factions
            </button>
            <button type="button" id="studio-notes-btn" class="cb-menu-item" title="Your private notes">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 0 1 3 3L12 15l-4 1 1-4z"/></svg>
              Private notes
            </button>
            <button type="button" id="studio-save-snap" class="cb-menu-item" title="Save a snapshot of the story so far">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>
              Save a snapshot
            </button>
            <button type="button" id="studio-chronicle" class="cb-menu-item" title="View saved snapshots">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>
              Chronicle — saved snapshots
            </button>
          </div></div>` : ''}
          ${isDM ? '' : `<button type="button" id="studio-clearchat-btn" class="st-btn ghost small cb-act-btn" title="Clear this conversation and start fresh (companions are kept)">🧹 Clear chat</button>`}
        </div>
        <div class="playas-block">
          <label class="playas-label" for="studio-playas">Playing as</label>
          <div class="playas-row">
            <select id="studio-playas" class="studio-select" aria-label="Speak as yourself or a party companion" title="You, or an NPC companion in your party">${playAsOpts}</select>
          </div>
        </div>
      </div>
    </div>
    <div class="chat-scroll" id="studio-chat-scroll"><div class="chat-thread" id="studio-thread"></div></div>
    ${isDM ? `<div id="studio-roll-prompt" class="roll-prompt" hidden></div>` : ''}
    ${isDM ? `<div id="studio-loot-prompt" class="roll-prompt loot-prompt" hidden></div>` : ''}
    ${isDM ? `<div class="dice-tray" id="studio-dice">
      <span class="dice-label">Roll</span>
      ${[20, 12, 10, 8, 6, 4].map(d => `<button class="die-btn" data-die="${d}" type="button">d${d}</button>`).join('')}
      <select id="dice-mod" class="dice-mod" aria-label="Add ability modifier"><option value="">+ mod</option>${ABILITIES.map(a => `<option value="${a}">${a}</option>`).join('')}</select>
      <button class="st-btn small ghost" id="studio-skillcheck" type="button" title="Roll a skill or ability check on your own">🎲 Check</button>
    </div>` : ''}
    <div class="chat-composer">
      ${isDM ? '' : `<button class="st-btn ghost pic-btn" id="studio-seed-pic" type="button" title="Use your own photos as reference — pictures will resemble them" aria-label="Seed reference photos for ${_esc(char.name)}">🖼️</button>
      <input type="file" id="studio-ref-file" accept="image/*" multiple hidden>
      <button class="st-btn ghost pic-btn" id="studio-ask-pic" type="button" title="Ask ${_esc(char.name)} for a picture" aria-label="Ask ${_esc(char.name)} for a picture">📷</button>`}
      <button class="st-btn ghost pic-btn" id="studio-capture" type="button" title="${isDM ? 'Picture this moment — art of what\'s happening now' : `Picture what ${_esc(char.name)} is doing right now`}" aria-label="Capture the current moment as a picture">🎬</button>
      ${isDM ? `<button class="st-btn ghost pic-btn" id="studio-attempt" type="button" title="Attempt anything — the GM sets a DC and you roll the right check" aria-label="Attempt an action with a dice roll">🎲</button>` : ''}
      <textarea id="studio-composer" rows="1" placeholder="${isDM ? 'What do you do?' : `Say something to ${_esc(char.name)}…`}"></textarea>
      <button class="st-btn primary send-btn" id="studio-send" type="button">Send</button>
    </div>`;
  $('chat-back').addEventListener('click', async () => {
    await loadCharacters();
    const v = _chatReturnView || 'roster';
    if (v === 'campaigns') { renderCampaigns(); switchView('campaigns'); }
    else if (v === 'worlds') { renderWorlds(); switchView('worlds'); }
    else { renderRoster(); switchView('roster'); }
  });
  // "⋯ More" menu: everything that isn't an every-minute button.
  const moreBtn = $('studio-more-btn'), moreMenu = $('studio-more-menu');
  if (moreBtn && moreMenu) {
    moreBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const opening = moreMenu.hidden;
      moreMenu.hidden = !opening;
      moreBtn.setAttribute('aria-expanded', String(opening));
    });
    moreMenu.addEventListener('click', () => { moreMenu.hidden = true; moreBtn.setAttribute('aria-expanded', 'false'); });
    document.addEventListener('click', (e) => {
      if (!moreMenu.hidden && !e.target.closest('.cb-more-wrap')) { moreMenu.hidden = true; moreBtn.setAttribute('aria-expanded', 'false'); }
    });
  }
  const playas = $('studio-playas');
  if (playas) {
    playas.addEventListener('change', () => { _chat.playAs = playas.value; });
    // Companions join and leave mid-story — rebuild the list each time it opens.
    playas.addEventListener('mousedown', () => { playas.innerHTML = _playAsOptions(); });
  }
  _applyTimeTint(char.id);   // tint the scene to the world clock's time of day
  $('studio-save-snap')?.addEventListener('click', saveSnapshot);
  $('studio-chronicle')?.addEventListener('click', () => openChronicle());
  $('studio-notes-btn')?.addEventListener('click', openNotes);
  $('studio-lore-btn')?.addEventListener('click', () => openLorebook());
  $('studio-party-btn')?.addEventListener('click', () => openPartyPanel());
  $('studio-dice-skin-btn')?.addEventListener('click', () => openDiceSkins());
  _applyDiceSkin();
  $('studio-tts-btn')?.addEventListener('click', toggleTTS);
  $('studio-sfx-btn')?.addEventListener('click', _toggleSfx);
  _reflectTTSBtn();
  _reflectSfxBtn();
  if (isDM) {
    $('studio-mem-btn')?.addEventListener('click', openMemory);
    $('studio-codex-btn')?.addEventListener('click', toggleCodex);
    $('studio-realm-btn')?.addEventListener('click', toggleRealm);
    $('studio-quests-btn')?.addEventListener('click', toggleQuests);
    $('studio-combat-btn')?.addEventListener('click', toggleCombat);
    $('studio-map-btn')?.addEventListener('click', toggleMap);
    $('studio-pack-btn')?.addEventListener('click', toggleInventory);
    $('studio-gm-btn')?.addEventListener('click', toggleGM);
    $('studio-scene-btn')?.addEventListener('click', setScene);
    $('studio-sheet-btn')?.addEventListener('click', toggleSheet);
    $('studio-clock')?.addEventListener('click', () => { _advanceTime(_chat.char.id, 1); });
    $('studio-objective')?.addEventListener('click', () => openQuests());
    _reflectClock(); _reflectObjective(char.id);
    _inspArmed = false;
    $('studio-inspiration')?.addEventListener('click', () => _armInspiration(char.id));
    _reflectInspiration(char.id);
    root.querySelectorAll('#studio-dice .die-btn').forEach(b =>
      b.addEventListener('click', () => _rollDie(parseInt(b.dataset.die, 10))));
    $('studio-skillcheck')?.addEventListener('click', () => _skillCheckMenu(char.id));
  }
  const ta = $('studio-composer');
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendChat(); }
  });
  ta.addEventListener('input', () => { ta.style.height = 'auto'; ta.style.height = Math.min(ta.scrollHeight, 160) + 'px'; });
  $('studio-send').addEventListener('click', () => sendChat());
  $('studio-ask-pic')?.addEventListener('click', () => _askForPicture());
  $('studio-capture')?.addEventListener('click', () => _captureMoment());
  $('studio-seed-pic')?.addEventListener('click', () => _seedReferences());
  $('studio-ref-file')?.addEventListener('change', _onSeedFiles);
  $('studio-look-btn')?.addEventListener('click', () => openAppearance());
  $('studio-clearchat-btn')?.addEventListener('click', () => _clearChat());
  $('studio-attempt')?.addEventListener('click', () => _attemptAction());
  // A level earned while you were elsewhere (party play) left its ASI/feature
  // choices pending — present the modal now that you're back in this adventure.
  if (isDM) { const _pl = _loadSheet(char.id)._pendingLevelUp; if (_pl) setTimeout(() => { if (_chat.char && _chat.char.id === char.id) _openLevelUp(char.id, _pl.from, _pl.to); }, 700); }
}

// Wipe this conversation and start fresh. Companion/group chats only (DM
// adventures keep their history — that's what the Chronicle is for). Truncating
// to zero empties the session server-side so a future reopen starts clean; the
// character/companions themselves are untouched.
async function _clearChat() {
  if (_chat.streaming || _chat.groupBusy) return;
  const who = _chat.group ? 'this group chat' : `your chat with ${_chat.char?.name || 'them'}`;
  const ok = window.styledConfirm
    ? await window.styledConfirm(`Clear ${who}? The conversation is erased — this can't be undone.`, { confirmText: 'Clear chat', danger: true })
    : window.confirm(`Clear ${who}? This can't be undone.`);
  if (!ok) return;
  if (_chat.abort) { try { _chat.abort.abort(); } catch {} }
  if (_chat.sessionId) {
    try { await fetch(`${API_BASE}/api/session/${_chat.sessionId}/truncate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ keep_count: 0 }) }); } catch {}
  }
  _chat.lastFramed = null;
  const thread = $('studio-thread');
  if (thread) {
    thread.innerHTML = _chat.group
      ? `<div class="rp-typing">${_esc(_chat.group.map(c => c.name).join(', '))} are here. Say something to get them talking.</div>`
      : `<div class="rp-typing">${_chat.char?.scene ? _esc(_chat.char.scene) + ' — say something to begin.' : 'Fresh start. Say something to begin.'}</div>`;
  }
  _toast('🧹 Chat cleared.');
}

// Adventures are Game-Master ("dm-*") sessions. Tag them server-side into an
// "Adventures" folder so they're resumed from the Studio and stay out of the
// companion/chat sidebar. Idempotent + fire-and-forget: tagging on every open
// retro-tags pre-existing adventures durably (the localStorage map alone is
// per-browser and unreliable).
function _tagAdventure(char, sid) {
  if (!sid || !_isDM(char)) return;
  const fd = new FormData(); fd.append('folder', 'Adventures');
  fetch(`${API_BASE}/api/session/${sid}`, { method: 'PATCH', body: fd }).catch(() => {});
}

// Prefer a fast, fully-GPU-resident model for narration — a 14B model spilling to
// CPU makes every turn crawl. Picks the best small model actually installed.
function _narrationModel() {
  try { const saved = JSON.parse(localStorage.getItem('studio-gm-model') || 'null'); if (saved && saved.model) return saved; } catch {}   // the player's chosen GM model wins
  try {
    const items = (window.modelsModule && window.modelsModule.getCachedItems) ? window.modelsModule.getCachedItems() : [];
    const prefs = ['llama3.1:8b', 'llama3:8b', 'qwen2.5:7b', 'qwen2.5:7b-instruct', 'mistral:7b', 'gemma2:9b'];
    for (const p of prefs) for (const it of items) {
      if (it.offline) continue;
      const models = (it.models || []).concat(it.models_extra || []);
      if (models.includes(p)) return { model: p, url: it.url || it.endpoint_url || '', endpoint_id: it.endpoint_id || '' };
    }
  } catch (e) {}
  return null;
}
function _applyNarrationModel(sid) {
  if (!sid) return;
  const nm = _narrationModel(); if (!nm || !nm.url) return;
  const fd = new FormData(); fd.append('model', nm.model); fd.append('endpoint_url', nm.url); if (nm.endpoint_id) fd.append('endpoint_id', nm.endpoint_id);
  fetch(`${API_BASE}/api/session/${sid}`, { method: 'PATCH', body: fd }).catch(() => {});
}
async function _ensureSession(char) {
  const map = _loadMap();
  let sid = map[char.id];
  if (sid) {
    // Validate it still exists; if not, fall through to create a new one.
    try { const r = await fetch(`${API_BASE}/api/history/${sid}`); if (r.ok) { _chat.sessionId = sid; _tagAdventure(char, sid); _applyNarrationModel(sid); return; } } catch {}
  }
  const fd = new FormData();
  fd.append('name', char.name);
  // Endpoint + model for the new session: the fast narration pick first, the
  // current chat session as fallback. From the title screen there IS no current
  // session — relying on it alone made creation 400 and the kickoff 404.
  const nm = _narrationModel();
  let epUrl = (nm && nm.url) || '', epModel = (nm && nm.model) || '', epId = (nm && nm.endpoint_id) || '';
  if (!epUrl) {
    try {
      const sessions = sessionModule.getSessions ? sessionModule.getSessions() : [];
      const cur = sessions.find(s => s.id === (sessionModule.getCurrentSessionId ? sessionModule.getCurrentSessionId() : null))
        || sessions.find(s => s.endpoint_url);   // any session with an endpoint beats none
      if (cur) { epUrl = cur.endpoint_url || ''; epModel = epModel || cur.model || ''; epId = epId || cur.endpoint_id || ''; }
    } catch {}
  }
  // ALWAYS send the registered endpoint id when we have one — non-admin
  // players are (correctly) refused raw endpoint URLs by the server.
  if (epUrl) { fd.append('endpoint_url', epUrl); fd.append('model', epModel); if (epId) fd.append('endpoint_id', epId); fd.append('skip_validation', 'true'); }
  const res = await fetch(`${API_BASE}/api/session`, { method: 'POST', body: fd });
  const data = await res.json();
  sid = data.session_id || data.id;
  _chat.sessionId = sid;
  if (!sid) throw new Error(data.detail || 'could not create a session for this adventure');
  map[char.id] = sid; _saveMap(map); _tagAdventure(char, sid); _applyNarrationModel(sid);
}

// Remove every leading [bracketed context block] from an outgoing message,
// tolerating nested/stray brackets inside a block (depth scan, not regex).
function _stripFraming(content) {
  let s = String(content || '');
  for (;;) {
    const t = s.replace(/^\s+/, '');
    if (!t.startsWith('[')) { s = t; break; }
    let depth = 0, end = -1;
    for (let i = 0; i < t.length; i++) {
      if (t[i] === '[') depth++;
      else if (t[i] === ']') { depth--; if (depth <= 0) { end = i; break; } }
    }
    if (end < 0) { s = t; break; }   // unterminated — show as-is rather than eat everything
    s = t.slice(end + 1);
  }
  const out = s.trim();
  if (out) return out;
  // Everything was bracketed. If it's app-generated framing (kickoff / continue /
  // group / context injection), keep it hidden; otherwise it was the player's own
  // words ("[I hide in the shadows]") — show them rather than drop the message.
  const orig = String(content || '').trim();
  if (/^\[(?:we are continuing|this is a relaxed group|campaign memory|relevant past events|gm style|player character sheet|in-world time|the player is|between you and this player)/i.test(orig)) return '';
  return orig.replace(/^\[/, '').replace(/\]\s*$/, '').trim();
}

async function _loadChatHistory() {
  const thread = $('studio-thread');
  if (!thread) return;
  let history = [];
  try {
    const res = await fetch(`${API_BASE}/api/history/${_chat.sessionId}`);
    if (res.ok) history = (await res.json()).history || [];
  } catch {}
  thread.innerHTML = '';
  if (!history.length) {
    const scene = _chat.char.scene || '';
    thread.innerHTML = `<div class="rp-typing">${scene
      ? _esc(scene) + ' — say something to begin.'
      : 'The scene is set. Say something to begin.'}</div>`;
    return;
  }
  for (const m of history) {
    let content = '';
    if (typeof m.content === 'string') content = m.content;
    else if (Array.isArray(m.content)) content = m.content.filter(p => p.type === 'text').map(p => p.text).join('\n');
    const imgUrl = m.metadata && m.metadata.image_url;
    if (m.role === 'user') {
      // Hide the bracketed framing (memory, sheet, realm, play-as tags…) from
      // the transcript. A simple regex broke whenever a block contained a ']'
      // — scan with a depth counter instead, and keep eating blocks until the
      // player's actual words appear.
      const disp = _stripFraming(content);
      if (disp) _appendBubble('me', disp);
    } else if (m.role === 'assistant') {
      const wrap = _appendBubble('them', content, imgUrl, m.metadata && m.metadata._db_id);
      if (_isDM(_chat.char)) _decorateSpeech(wrap, _chat.char.id);   // speakers keep their faces on reload
    }
  }
  if (_isDM(_chat.char)) {
    _showRecap(_chat.char.id);   // "Previously on…" from the campaign memory
    const lastA = [...history].reverse().find(m => m.role === 'assistant');
    _renderRollPrompt(lastA ? _detectCheck(typeof lastA.content === 'string' ? lastA.content : '') : null);
  }
  _scrollChat();
}

function _appendBubble(side, html, imgUrl, dbId) {
  const thread = $('studio-thread');
  if (!thread) return null;
  const placeholder = thread.querySelector('.rp-typing');
  if (placeholder) placeholder.remove();
  const wrap = document.createElement('div');
  wrap.className = `rp-msg ${side === 'me' ? 'me' : 'them'}`;
  const char = _chat.char || {};
  // Your hero has a face too — the portrait from character creation rides
  // beside your own words, not just the GM's.
  let meAv = '';
  try { meAv = (_isDM(char) && _loadSheet(char.id).avatar) || (_loadPlayer() || {}).avatar || ''; } catch {}
  const avatar = side === 'me'
    ? (meAv ? `<img class="rp-avatar" src="${_esc(meAv)}" alt="">` : `<div class="rp-avatar me-av" aria-hidden="true">✦</div>`)
    : (char.avatar
        ? `<img class="rp-avatar" src="${_esc(char.avatar)}" alt="">`
        : (_isDM(char)
            ? `<div class="rp-avatar dm" aria-hidden="true">GM</div>`
            : `<div class="rp-avatar me-av" aria-hidden="true">${_esc(_initial(char.name))}</div>`));
  const photo = imgUrl ? `<img class="rp-photo" src="${_esc(imgUrl)}" alt="Shared image" loading="lazy">` : '';
  // Only our own typing-indicator placeholder is trusted raw HTML. Deciding by a
  // bare "starts with <" let any model/restored reply beginning with "<" (e.g.
  // "<gasp>" or a crafted "<img onerror=…>") inject unescaped — everything else
  // goes through _rp(), which escapes.
  const isPreHtml = typeof html === 'string' && /^<span class="rp-typing"/.test(html);
  // Group chat: label each reply with the speaker (avatars alone get ambiguous).
  // The label sits OUTSIDE .rp-bubble (streaming rewrites the bubble's innerHTML).
  const nameLbl = (_chat.group && side !== 'me' && char.name) ? `<span class="rp-speaker-name">${_esc(char.name)}</span>` : '';
  const bubbleHtml = `<div class="rp-bubble">${isPreHtml ? html : _rp(html)}${photo}</div>`;
  wrap.innerHTML = nameLbl ? `${avatar}<div class="rp-msg-col">${nameLbl}${bubbleHtml}</div>` : `${avatar}${bubbleHtml}`;
  if (!isPreHtml && typeof html === 'string') wrap.dataset.raw = html;
  if (dbId) { wrap.dataset.mid = dbId; _addBubbleActions(wrap); }
  thread.appendChild(wrap);
  return wrap;
}

// Edit / Regenerate controls on a Game Master bubble (so off-key narration can
// be fixed or re-rolled, and the corrected lore sticks going forward).
function _addBubbleActions(wrap) {
  if (!wrap || wrap.querySelector('.rp-actions')) return;
  // Edit/regenerate on any single-speaker reply (GM or companion); not in group
  // chat, where "the last reply" is ambiguous across speakers.
  if (_chat.group || !wrap.classList.contains('them')) return;
  const bar = document.createElement('div');
  bar.className = 'rp-actions';
  bar.innerHTML = `<button class="rp-act" type="button" data-act="edit" title="Edit" aria-label="Edit">✎</button>`
    + `<button class="rp-act" type="button" data-act="regen" title="Regenerate" aria-label="Regenerate">↻</button>`;
  bar.querySelector('[data-act="edit"]').addEventListener('click', () => _editBubble(wrap));
  bar.querySelector('[data-act="regen"]').addEventListener('click', () => _regenBubble(wrap));
  wrap.appendChild(bar);
}

function _editBubble(wrap) {
  const mid = wrap.dataset.mid;
  if (!mid || wrap._editing) return;
  wrap._editing = true;
  const bubble = wrap.querySelector('.rp-bubble');
  const raw = wrap.dataset.raw || bubble.textContent || '';
  const prev = bubble.innerHTML;
  bubble.innerHTML = '';
  const ta = document.createElement('textarea');
  ta.className = 'rp-edit'; ta.value = raw;
  const bar = document.createElement('div'); bar.className = 'rp-edit-bar';
  bar.innerHTML = `<button class="st-btn small primary" type="button" data-save>Save</button><button class="st-btn small" type="button" data-cancel>Cancel</button>`;
  bubble.appendChild(ta); bubble.appendChild(bar);
  ta.style.height = 'auto'; ta.style.height = Math.min(ta.scrollHeight, 320) + 'px'; ta.focus();
  bar.querySelector('[data-cancel]').addEventListener('click', () => { bubble.innerHTML = prev; wrap._editing = false; });
  bar.querySelector('[data-save]').addEventListener('click', async () => {
    const val = ta.value.trim();
    try {
      await fetch(`${API_BASE}/api/session/${_chat.sessionId}/edit-message`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ msg_id: mid, content: val }),
      });
    } catch (e) { console.error('edit-message failed', e); }
    wrap.dataset.raw = val;
    bubble.innerHTML = _rp(val);
    wrap._editing = false;
  });
}

async function _regenBubble(wrap) {
  if (_chat.streaming) return;
  // Re-rolling replays _chat.lastFramed (the newest turn), so it's only coherent
  // for the newest reply. Regenerating an older bubble would delete it and append
  // a reply to the latest prompt at the bottom — refuse it instead.
  const thread = $('studio-thread');
  const lastThem = thread ? [...thread.querySelectorAll('.rp-msg.them')].pop() : null;
  if (lastThem && wrap !== lastThem) { _toast('You can only redo the most recent reply.'); return; }
  // Delete the assistant reply AND the user turn that prompted it — re-streaming
  // re-sends that same framing, so without dropping the old user message the
  // session would accumulate a duplicate prompt on every regenerate.
  const ids = [];
  if (wrap.dataset.mid) ids.push(wrap.dataset.mid);
  try {
    const msgs = ((await (await fetch(`${API_BASE}/api/history/${_chat.sessionId}`)).json()) || {}).history || [];
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === 'user') { const uid = msgs[i].metadata && msgs[i].metadata._db_id; if (uid) ids.push(uid); break; }
    }
  } catch {}
  if (ids.length) {
    try {
      await fetch(`${API_BASE}/api/session/${_chat.sessionId}/delete-messages`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ msg_ids: ids }),
      });
    } catch (e) { console.error('delete-message failed', e); }
  }
  wrap.remove();
  if (_chat.lastFramed) _streamAssistant(_chat.lastFramed);
}

// Roll to do ANYTHING: the composer text is your declared action. Instead of the
// GM narrating a hand-waved outcome, it must set a DC and call for the exact
// ability/skill check — which _detectCheck turns into a one-tap roll prompt. This
// is the ask-the-DM → real-mechanic loop made tactile.
async function _attemptAction() {
  if (_chat.streaming || !_isDM(_chat.char)) return;
  const ta = $('studio-composer');
  let action = (ta?.value || '').trim();
  if (!action) {
    try { action = window.styledPrompt ? await window.styledPrompt('What do you attempt? (the GM will set the difficulty and you\'ll roll)', '') : window.prompt('What do you attempt?', ''); }
    catch { action = null; }
    if (action == null) return;
    action = String(action).trim();
    if (!action) return;
  } else { ta.value = ''; ta.style.height = 'auto'; }
  if (!_chat.group && !_chat.sessionId) { _toast('Still connecting — try again in a moment.'); return; }
  _appendBubble('me', `🎲 *I attempt: ${_esc(action)}*`);
  _scrollChat();
  const framed = `[I attempt this: "${action}". Adjudicate it like a fair GM — if it can just succeed, say so; if it's impossible, tell me why; otherwise decide the single most fitting ability or skill check and a DC (name both explicitly, e.g. "make a DC 14 Dexterity (Stealth) check"), then wait for my roll. Do NOT narrate the outcome yet.]`;
  await _streamAssistant(framed);
}

function _scrollChat() {
  const sc = $('studio-chat-scroll');
  if (sc) sc.scrollTop = sc.scrollHeight;
}

async function sendChat() {
  if (_chat.streaming || _chat.groupBusy) return;   // groupBusy: a multi-speaker turn spans several _streamAssistant calls that each clear .streaming
  if (_chat.dead) { _toast('Your hero has fallen — load a save or cling to life to continue.'); return; }   // game over halts play
  // At a shared table, wait your turn — someone else is mid-scene with the GM.
  if (_party && _partyBusy && _partyBusy.by) {
    _appendBubble('me', `✋ *${_esc(_partyBusy.by)} is talking to the GM — one voice at a time.*`); _scrollChat();
    return;
  }
  const ta = $('studio-composer');
  const text = (ta?.value || '').trim();
  if (!text) return;
  if (!_chat.group && !_chat.sessionId) {   // session not ready yet — tell the player and try to (re)establish it
    _toast('Still connecting to this chat — give it a moment and try again.');
    if (_chat.char) _ensureSession(_chat.char).catch(() => {});
    return;
  }
  ta.value = ''; ta.style.height = 'auto';
  _appendBubble('me', text);
  _scrollChat();
  if (_chat.group) { await _streamGroupTurn(text); return; }   // group: each character replies in turn
  // Display the raw line, but tell the model who's speaking when you're embodying
  // someone other than yourself.
  const framed = _chat.playAs ? `[I am speaking and acting in-character as ${_chat.playAs}.] ${text}` : text;
  await _streamAssistant(framed);
}

// One-time "how to play" coach card, shown at the top of a player's very first
// adventure. Dismiss once, never again.
// ── First-run tour: a guided spotlight walk over the table, once ever ────────
const _TOUR_STEPS = [
  ['studio-composer', 'Say what you do', 'Talk, sneak, bargain, swing — anything. The Game Master runs the world around your words.'],
  ['studio-dice', 'Roll when asked', 'When the GM calls for a check, a matching Roll button appears above this tray. Loose dice live here too.'],
  ['studio-sheet-btn', 'Your Sheet', 'Abilities, HP, spells, and class features you can Use — plus short and long rests.'],
  ['studio-pack-btn', 'Your Pack', 'Your gear hangs around your hero. Drag items onto the slots to equip them; trade at any vendor.'],
  ['studio-map-btn', 'The Map', "Travel the painted world — the fog lifts where you've been, and every place has its own local map."],
  ['studio-lore-btn', 'The Lorebook', 'Monsters and their weaknesses, every spell, and the rules of the table.'],
];
function _startTour() {
  try { if (localStorage.getItem('studio-tour-done')) return; localStorage.setItem('studio-tour-done', '1'); } catch {}
  const modal = $('studio-modal'); if (!modal) return;
  const ov = document.createElement('div'); ov.className = 'tour-overlay'; modal.appendChild(ov);
  let i = 0;
  const step = () => {
    while (i < _TOUR_STEPS.length && (!document.getElementById(_TOUR_STEPS[i][0]) || !document.getElementById(_TOUR_STEPS[i][0]).offsetParent)) i++;
    if (i >= _TOUR_STEPS.length) { ov.remove(); return; }
    const [id, title, body] = _TOUR_STEPS[i];
    const r = document.getElementById(id).getBoundingClientRect();
    ov.innerHTML = `
      <div class="tour-ring" style="left:${r.left - 8}px;top:${r.top - 8}px;width:${r.width + 16}px;height:${r.height + 16}px"></div>
      <div class="tour-tip" style="${r.top > innerHeight / 2 ? `bottom:${innerHeight - r.top + 14}px` : `top:${r.bottom + 14}px`};left:${Math.max(12, Math.min(innerWidth - 340, r.left))}px">
        <strong>${_esc(title)}</strong><p>${_esc(body)}</p>
        <div class="tour-btns"><button class="st-btn small ghost" data-tour="skip" type="button">Skip tour</button><button class="st-btn small primary" data-tour="next" type="button">${i === _TOUR_STEPS.length - 1 ? 'Play! ›' : 'Next ›'}</button></div>
      </div>`;
    ov.querySelector('[data-tour="next"]').addEventListener('click', () => { i++; step(); });
    ov.querySelector('[data-tour="skip"]').addEventListener('click', () => ov.remove());
  };
  step();
}

function _howToPlay() {
  try { if (localStorage.getItem('studio-howto-seen')) return; } catch (e) {}
  const thread = $('studio-thread'); if (!thread) return;
  const card = document.createElement('div');
  card.className = 'howto-card';
  card.innerHTML = `
    <div class="howto-head"><strong>How to play</strong><button class="studio-close howto-close" type="button" aria-label="Dismiss">✕</button></div>
    <ul>
      <li><strong>Say what you do</strong> — talk, sneak, swing, bargain. The GM runs the world.</li>
      <li>🎲 When asked for a check, roll from the <strong>dice tray</strong> below.</li>
      <li>📋 <strong>Sheet</strong> — your hero: HP, abilities, and class features you can <em>Use</em>.</li>
      <li>🎒 <strong>Pack</strong> — equip, drink, sell, give, or 🔨 combine items.</li>
      <li>🗺 <strong>Map</strong> — travel the world; battles get their own board.</li>
      <li>📜 <strong>Quests</strong> — goals fill in as you play; finishing them levels you up.</li>
      <li>🎚 <strong>GM</strong> — retune tone, danger, and rules anytime.</li>
      <li>⛺ Hurt? <strong>Rest</strong> from the sheet — but the night isn't always safe.</li>
    </ul>`;
  thread.prepend(card);
  card.querySelector('.howto-close').addEventListener('click', () => {
    try { localStorage.setItem('studio-howto-seen', '1'); } catch (e) {}
    card.remove();
  });
}

// Kick a Dungeon Master adventure into motion: the GM narrates the opening scene
// with no visible player turn.
async function _dmKickoff() {
  const playerLine = _chat.playAs ? ` The player is playing as ${_chat.playAs}.` : '';
  await _streamAssistant(`[Begin the adventure now. Set the opening scene vividly in second person and end by asking what I do. Do not speak or act for me.${playerLine}]`);
}

// Companion chats: ask the character to share an in-the-moment picture. Same
// image endpoint as portraits — conditioned on the character (IP-adapter, so a
// character with saved refs stays on-model) and the world's art style (threaded
// via _artFetch) — dropped in as a message from them.
// Disable both picture buttons while a shot renders (either can trigger a gen).
function _picBusy(on) {
  ['studio-ask-pic', 'studio-capture'].forEach(id => { const b = $(id); if (b) b.disabled = on; });
}

// Pull "what's happening now" out of the latest narration so a picture can show
// the current moment without the player retyping it. Skips picture/typing
// bubbles, drops spoken dialogue and markdown, and keeps the freshest sentences.
function _sceneFromNarration() {
  const bubbles = [...document.querySelectorAll('#studio-thread .rp-msg.them .rp-bubble')];
  for (let i = bubbles.length - 1; i >= 0; i--) {
    const b = bubbles[i];
    if (b.querySelector('img')) continue;            // a picture bubble, not narration
    let t = (b.innerText || '').trim();
    if (t.length < 12) continue;                     // typing indicator / stub
    t = t.replace(/[“”"][^“”"]*[“”"]/g, ' ')          // drop quoted dialogue (contractions keep their apostrophes)
         .replace(/[*_>#`~]/g, ' ')                       // drop markdown
         .replace(/\s+/g, ' ').trim();
    if (t.length < 12) continue;
    const sents = t.split(/(?<=[.!?])\s+/).filter(s => s.trim().length > 3);
    return (sents.slice(-3).join(' ') || t).slice(0, 420)
      .replace(/\s+([.,!?;:])/g, '$1')   // "console ." → "console."
      .replace(/[.\s]+$/, '').trim();     // drop trailing period so callers append cleanly
  }
  return (_chat.char && _chat.char.scene) ? String(_chat.char.scene).trim() : '';
}

// ── Picture entry points ──────────────────────────────────────────────────
// 📷 "ask for a specific picture" — the player types the scene.
async function _askForPicture() {
  if (!_chat.char || _chat.streaming) return;
  if (_chat.group && _chat.group.length >= 2) return _askGroupPicture();
  const char = _chat.char;
  const ask = `What's ${char.name} doing in the picture?\n\nLeave blank for a candid photo, or describe a scene — e.g. "doing yoga at sunrise", "riding a horse through snow", "mid-backflip in a gym", "fighting a dragon".`;
  let scene;
  try { scene = window.styledPrompt ? await window.styledPrompt(ask, '') : window.prompt(ask, ''); }
  catch { scene = null; }
  if (scene === null || scene === undefined) return;  // cancelled
  return _photoSolo(char, String(scene).trim());
}

// 🎬 "capture this moment" — no typing: derive the scene from the live story
// and picture it. Scene- and action-aware; routes by chat mode.
async function _captureMoment() {
  if (!_chat.char || _chat.streaming) return;
  const scene = _sceneFromNarration();
  if (!scene) { _toast('Nothing to picture yet — play a beat first.'); return; }
  if (_chat.group && _chat.group.length >= 2) return _photoGroup(_chat.group[0], _chat.group[1], scene);
  if (_isDM(_chat.char)) return _photoScene(scene);   // GM mode: the whole scene, not one portrait
  return _photoSolo(_chat.char, scene);
}

async function _askGroupPicture() {
  const [A, B] = _chat.group.slice(0, 2);
  const ask = `What are ${A.name} and ${B.name} doing together?\n\ne.g. "playing Twister", "cooking dinner", "arm-wrestling at a bar", "sitting on a park bench".`;
  let scene;
  try { scene = window.styledPrompt ? await window.styledPrompt(ask, '') : window.prompt(ask, ''); } catch { scene = null; }
  if (scene === null || scene === undefined) return;
  return _photoGroup(A, B, String(scene).trim() || 'together');
}

// ── Picture renderers (shared by ask + capture) ───────────────────────────
// One character. Empty scene → a candid full-body shot. IP-Adapter keeps the
// face on-model while the body takes the pose the action calls for.
async function _photoSolo(char, scene) {
  _picBusy(true);
  const wrap = _appendBubble('them', `<span class="rp-typing"><span class="dot">✦</span> ${scene ? 'setting up the shot' : 'taking a picture'}…</span>`);
  const bubble = wrap ? wrap.querySelector('.rp-bubble') : null;
  _scrollChat();
  try {
    const who = [char.name, char.role, char.blurb].filter(Boolean).join(', ');
    // Lead with the action so the model composes the whole scene at full body;
    // in scene mode we drop the role (which pulls back to their "home" setting)
    // and let identity hold via the face + physique anchor.
    const prompt = scene
      ? `${scene}. Full-body cinematic photograph, ${char.name} as the subject, natural expressive pose that fits the action, complete figure in frame, detailed environment and props, dramatic depth of field, sharp focus, highly detailed.`
      : `Candid full-body photograph of ${char.name} (${who}), relaxed natural pose, complete figure in frame, soft natural light, sharp focus, highly detailed.`;
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, character: char.name, size: '1024x1024' }),
    });
    const d = await r.json().catch(() => ({}));
    if (d && d.image_url && bubble) {
      const cap = scene ? `${_esc(char.name)} — ${_esc(scene)}` : `${_esc(char.name)} shares a picture.`;
      bubble.innerHTML = `<em>${cap}</em><img class="rp-photo" src="${_esc(d.image_url)}" alt="${_esc(char.name)}${scene ? ' ' + _esc(scene) : ''}" loading="lazy">`;
    } else if (bubble) {
      bubble.innerHTML = `<span class="rp-typing">${_esc(char.name)} couldn't get a good shot just now.</span>`;
    }
  } catch (e) {
    if (bubble) bubble.innerHTML = `<span class="rp-typing">The picture didn't come through — try again.</span>`;
  } finally { _picBusy(false); _scrollChat(); }
}

// Two characters together. Regional prompting paints each in their own half of a
// wide canvas so their looks don't bleed; overlapping zones + "solo, one person"
// suppress a spurious third figure in the seam.
async function _photoGroup(A, B, scene) {
  scene = scene || 'together';
  // Regional prompting is tuned for two subjects; a bigger group is drawn as
  // just the first two rather than silently dropping the rest without a word.
  if (_chat.group && _chat.group.length > 2) _toast(`Group photos show two at a time — picturing ${A.name} & ${B.name}.`);
  _picBusy(true);
  const wrap = _appendBubble('them', `<span class="rp-typing"><span class="dot">✦</span> setting up a photo of ${_esc(A.name)} & ${_esc(B.name)}…</span>`);
  const bubble = wrap ? wrap.querySelector('.rp-bubble') : null;
  _scrollChat();
  try {
    const look = async (c) => { try { const d = await (await fetch(`${API_BASE}/api/characters/studio/appearance/${encodeURIComponent(c.name)}`)).json(); return (d.appearance || '').trim() || c.name; } catch { return c.name; } };
    const [lookA, lookB] = await Promise.all([look(A), look(B)]);
    const regions = [
      { prompt: `solo, one person, full body of ${A.name}: ${lookA}, ${scene}`, x: 0.0, y: 0.0, w: 0.55, h: 1.0 },
      { prompt: `solo, one person, full body of ${B.name}: ${lookB}, ${scene}`, x: 0.45, y: 0.0, w: 0.55, h: 1.0 },
    ];
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: `${scene}, one cohesive scene, detailed background, warm light, wide cinematic shot`, regions, size: '1216x832' }),
    });
    const d = await r.json().catch(() => ({}));
    if (d && d.image_url && bubble) {
      bubble.innerHTML = `<em>${_esc(A.name)} & ${_esc(B.name)} — ${_esc(scene)}</em><img class="rp-photo rp-photo-wide" src="${_esc(d.image_url)}" alt="${_esc(A.name)} and ${_esc(B.name)} ${_esc(scene)}" loading="lazy">`;
    } else if (bubble) { bubble.innerHTML = `<span class="rp-typing">Couldn't get the shot — try again.</span>`; }
  } catch (e) {
    if (bubble) bubble.innerHTML = `<span class="rp-typing">The picture didn't come through — try again.</span>`;
  } finally { _picBusy(false); _scrollChat(); }
}

// GM mode: the world and its action, not one character's portrait. Optional
// `character`: anchor the scene's protagonist on that character's reference
// photos (heroes get theirs when a portrait is saved) — the bridge falls back
// to plain generation when no references exist, so passing it is always safe.
async function _photoScene(scene, character) {
  _picBusy(true);
  const wrap = _appendBubble('them', `<span class="rp-typing"><span class="dot">✦</span> capturing the scene…</span>`);
  const bubble = wrap ? wrap.querySelector('.rp-bubble') : null;
  _scrollChat();
  try {
    const prompt = `${scene}. Epic cinematic wide establishing shot, dynamic action, dramatic volumetric lighting, richly detailed fantasy illustration, sharp focus, highly detailed.`;
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, size: '1216x832', ...(character ? { character } : {}) }),
    });
    const d = await r.json().catch(() => ({}));
    if (d && d.image_url && bubble) {
      bubble.innerHTML = `<em>${_esc(scene)}</em><img class="rp-photo rp-photo-wide" src="${_esc(d.image_url)}" alt="${_esc(scene)}" loading="lazy">`;
    } else if (bubble) { bubble.innerHTML = `<span class="rp-typing">Couldn't capture that scene — try again.</span>`; }
  } catch (e) {
    if (bubble) bubble.innerHTML = `<span class="rp-typing">The picture didn't come through — try again.</span>`;
  } finally { _picBusy(false); _scrollChat(); }
}

// Seed a character's look with the user's own photos (IP-Adapter references), so
// generated pictures resemble that person. Absent references → plain gen.
function _seedReferences() { $('studio-ref-file')?.click(); }
async function _onSeedFiles(ev) {
  const files = [...(ev.target.files || [])].slice(0, 8);
  ev.target.value = '';
  if (!files.length || !_chat.char) return;
  _toast(`Adding ${files.length} reference photo${files.length > 1 ? 's' : ''}…`);
  const images = (await Promise.all(files.map(f => new Promise(res => {
    const r = new FileReader();
    r.onload = () => res({ b64: String(r.result).split(',')[1] || '', ext: (f.name.split('.').pop() || 'png').toLowerCase() });
    r.onerror = () => res(null);
    r.readAsDataURL(f);
  })))).filter(x => x && x.b64);
  if (!images.length) { _toast('Could not read those files.'); return; }
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/reference/upload`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ character: _chat.char.name, images }),
    });
    const d = await r.json().catch(() => ({}));
    _toast(d.ok ? `✓ Added ${d.saved} photo${d.saved > 1 ? 's' : ''} — pictures will resemble them now.` : 'Could not add those photos.');
  } catch { _toast('Upload failed — try again.'); }
}

// Edit the character's appearance anchor — the tokens glued onto every picture
// to keep them on-model. Person-only (build, hair, face) leaves the pose, outfit
// and scene free; setting/clothing tokens here fight action shots.
async function openAppearance() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const char = _chat.char;
  let ov = $('studio-appearance-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-appearance-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  let cur = '';
  try { const d = await (await fetch(`${API_BASE}/api/characters/studio/appearance/${encodeURIComponent(char.name)}`)).json(); cur = d.appearance || ''; } catch {}
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Appearance">
    <div class="chronicle-bar"><h2>${_esc(char.name)}'s look</h2><button class="studio-close" id="appearance-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">What stays the same in every picture — <strong>describe the person only</strong>: age, build, hair, face, distinctive features. Leave out clothing and setting so their pictures can show any pose or scene (riding a horse, a fight, a beach).</p>
      <label class="sf">Appearance<textarea id="appearance-text" rows="4" placeholder="e.g. woman in her 40s, athletic build, auburn hair in a loose bun, freckles, warm green eyes">${_esc(cur)}</textarea></label>
      <div class="chronicle-actions"><button class="st-btn" id="appearance-save" type="button">Save look</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  const close = () => { ov.style.display = 'none'; };
  $('appearance-close').addEventListener('click', close);
  ov.addEventListener('click', (e) => { if (e.target === ov) close(); });
  $('appearance-save').addEventListener('click', async () => {
    const btn = $('appearance-save'); btn.disabled = true; btn.textContent = 'Saving…';
    try {
      const r = await fetch(`${API_BASE}/api/characters/studio/appearance`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ character: char.name, appearance: $('appearance-text').value }),
      });
      const d = await r.json().catch(() => ({}));
      _toast(d.ok ? '✓ Look saved — new pictures will use it.' : 'Could not save the look.');
      if (d.ok) close();
    } catch { _toast('Save failed — try again.'); }
    btn.disabled = false; btn.textContent = 'Save look';
  });
}

// Shared streaming core: re-assert the active persona, spawn the reply bubble,
// stream tokens + any in-chat image, finalize. Used by both sendChat and the DM
// kickoff (the kickoff just passes a hidden opening instruction).
async function _streamAssistant(framed) {
  _chat.lastFramed = framed;   // remembered for "regenerate"
  _renderRollPrompt(null);     // clear any pending "roll this" prompt for the new turn
  _renderLootPrompt(null);     // and any pending loot offer
  _stopSpeech();               // hush any prior narration before this turn replies
  try {
    await fetch(`${API_BASE}/api/characters/studio/activate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: _chat.char.id, name: _chat.char.name }),
    });
  } catch {}

  const bubbleWrap = _appendBubble('them', '<span class="rp-typing"><span class="dot">✦</span><span class="dot">✦</span><span class="dot">✦</span></span>');
  const bubble = bubbleWrap.querySelector('.rp-bubble');
  if (bubble && !_fxReduced()) bubble.classList.add('rp-streaming');   // blinking caret while the tale unspools
  _scrollChat();

  // For a Dungeon Master, hand it the live character sheet so it can set DCs,
  // apply HP/conditions, and reason about inventory.
  let outgoing = framed;
  if (_isDM(_chat.char)) {
    const cid = _chat.char.id;
    const mem = _memText(cid);
    const recalled = await _recallBeats(cid, framed);   // pinpoint memory (§4.C): the past beats most relevant to this move
    const cast = _codexText(cid);
    const realm = _realmText(cid);
    const quests = _questText(cid);
    const combat = _combatContext(cid);
    const inv = _invText(cid);
    const spells = _spellText(cid);
    const clock = _clockText(cid);
    const party = _partyText(cid);
    // Companions aren't furniture: now and then, nudge the GM to give one a
    // line. Costs nothing — it rides the turn that's already happening.
    const talkers = _companions(cid).filter(c => !c.guest);
    const banter = (talkers.length && !_loadCombat(cid).active && Math.random() < 0.25)
      ? `[If it fits the moment, have ${talkers[Math.floor(Math.random() * talkers.length)].name} interject one short in-character line or gesture this turn — banter, an opinion, a worry. Keep it brief.]\n`
      : '';
    outgoing = `${mem ? `[Campaign memory so far — ${mem}]\n` : ''}${recalled ? `[Relevant past events — ${recalled}]\n` : ''}[GM style — ${_gmDirective(cid)}]\n${clock ? `[${clock}]\n` : ''}[Player character sheet — ${_sheetSummary(_loadSheet(cid), cid)}]\n${party ? `[${party}]\n` : ''}${banter}${inv ? `[${inv}]\n` : ''}${spells ? `[${spells}]\n` : ''}${quests ? `[${quests}]\n` : ''}${cast ? `[${cast}]\n` : ''}${realm ? `[${realm}]\n` : ''}${combat ? `[${combat}]\n` : ''}${framed}`;
  } else {
    // One-on-one with a known character: carry over how they feel about the
    // player from wherever else they've been met (cross-session memory).
    const rel = _relFor(_chat.char.name);
    if (rel && (rel.note || rel.disposition)) {
      outgoing = `[Between you and this player there is history: you feel ${rel.disposition || 'neutral'} toward them${rel.note ? `; ${rel.note}` : ''}. Stay true to that.]\n${framed}`;
    }
  }
  const fd = new FormData();
  fd.append('message', outgoing);
  fd.append('session', _chat.sessionId);
  fd.append('mode', 'chat');
  fd.append('preset_id', 'custom');

  _chat.streaming = true;
  _chat.abort = new AbortController();
  // Idle watchdog, not a wall-clock cap: abort only after a long GAP with no
  // tokens (a truly stalled model), rearmed on every delta — so a long reply
  // that keeps streaming is never cut off mid-sentence. First token on the slow
  // local model can be ~50s, so the gap is generous.
  let _streamTimer;
  const _armIdle = () => { clearTimeout(_streamTimer); _streamTimer = setTimeout(() => { try { _chat.abort.abort(); } catch {} }, 75000); };
  _armIdle();
  if (_party) _partySetBusy(true);   // claim the table while the GM answers you
  const sendBtn = $('studio-send'); if (sendBtn) sendBtn.disabled = true;
  let acc = '';
  try {
    const res = await fetch(`${API_BASE}/api/chat_stream`, { method: 'POST', body: fd, signal: _chat.abort.signal });
    if (!res.ok || !res.body) throw new Error(`Error ${res.status}`);
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop();
      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const payload = line.slice(6);
        if (payload === '[DONE]') continue;
        let json; try { json = JSON.parse(payload); } catch { continue; }
        if (json.delta) {
          acc += json.delta;
          bubble.innerHTML = _rp(acc);
          _scrollChat();
          _armIdle();   // tokens are flowing — reset the stall watchdog
        } else if (json.type === 'message_saved' && json.id) {
          bubbleWrap.dataset.mid = json.id;     // for edit / regenerate
        } else if (json.type === 'tool_output' && json.image_url) {
          const img = document.createElement('img');
          img.className = 'rp-photo'; img.src = json.image_url; img.alt = json.image_prompt || 'Shared image';
          bubble.appendChild(img);
          _scrollChat();
        } else if (json.type === 'error' || json.error) {
          if (!acc) bubble.innerHTML = `<span class="rp-typing">${_esc(json.error || 'Something interrupted the tale.')}</span>`;
        }
      }
    }
    if (!acc && !bubble.querySelector('.rp-photo')) {
      if (bubbleWrap && bubbleWrap.parentNode) bubbleWrap.remove();   // drop the empty turn, don't leave a dead "(no reply)" bubble
      _toast('The GM fell silent — try again or rephrase.');
    }
  } catch (e) {
    const aborted = e && (e.name === 'AbortError' || /abort/i.test(e.message || ''));
    if (!acc) {
      if (bubbleWrap && bubbleWrap.parentNode) bubbleWrap.remove();   // no dead caret bubble on timeout/error
      _toast(aborted ? 'The GM took too long — try again.' : `The connection faltered: ${e.message || e}`);
    }
  } finally {
    clearTimeout(_streamTimer);
    _chat.streaming = false;
    if (_party) { _partySetBusy(false); _partyHistLen = -1; }   // release the table; next poll re-syncs
    if (bubble) bubble.classList.remove('rp-streaming');   // stop the caret
    if (sendBtn) sendBtn.disabled = false;
    if (acc) { bubbleWrap.dataset.raw = acc; _speak(acc); }   // narrate the reply if narration is on
    _addBubbleActions(bubbleWrap);   // edit / regenerate now that it has an id
    if (_isDM(_chat.char)) {
      _renderRollPrompt(_detectCheck(acc));   // offer the exact roll the GM asked for
      const cid = _chat.char.id;
      // Lazily conjure portraits for any tracked NPC who steps on stage without one
      // yet (max 2/turn to spare the GPU), so faces fill in as the cast appears.
      _namedCodexNpcs(cid, acc).filter(n => !n.avatar && !_castPortraitTried.has(n.id)).slice(0, 2)
        .forEach(n => { _castPortraitTried.add(n.id); _genNpcPortrait(cid, n.id); });
      const faces = _npcFacesFor(cid, acc);   // show portraits of any codex NPC on stage in this beat
      if (faces.length && bubble) {
        const strip = document.createElement('div'); strip.className = 'rp-cast';
        strip.innerHTML = `<span class="rp-cast-lbl">On stage</span>` + faces.map(n => `<span class="rp-cast-npc" title="${_esc(n.name)}"><img src="${_esc(n.avatar)}" alt="" loading="lazy"><span>${_esc(n.name.split(/\s+/)[0])}</span></span>`).join('');
        bubble.appendChild(strip);
      }
      _decorateSpeech(bubbleWrap, cid);   // each speaker's face beside their spoken line
      const _upkeep = !_party || _party.role === 'host';   // one bookkeeper per table
      // Serialize the LLM extractors — firing 2-4 at once storms the single local
      // model and they time out. The queue runs them one at a time in the background.
      if (_upkeep) _storeBeat(cid, framed, acc);   // §4.C: embed this beat for recall — replaces the 5-turn LLM summary that 502'd
      if (_upkeep && _meCount() - (_loadCodex(cid).at || 0) >= 6) _enqueueExtractor(() => _updateCodex(cid));
      if (_upkeep && _meCount() - (_loadQuests(cid).at || 0) >= 3) _enqueueExtractor(() => _updateQuests(cid));
      _reflectObjective(cid);                // keep the objective chip current
      if (_upkeep && _meCount() - (_loadWorldS(cid).at || 0) >= 8) _enqueueExtractor(() => _updateWorldS(cid));
      // Auto world-state detectors. Skipped entirely on a recap turn (continuing
      // from a save point re-narrates past events — mining it would re-award old
      // loot/gold). The damage scan is skipped once right after a mechanical combat
      // hit, whose HP was already applied — otherwise the GM's "hits you for N"
      // narration would double it.
      if (_chat.recapTurn) {
        _chat.recapTurn = false;
      } else {
        const _sp = _detectLearnedSpell(acc); if (_sp) _learnSpellFromDM(cid, _sp);   // GM granted a spell → scribe it
        const _nj = _detectCompanionJoin(cid, acc); if (_nj) _joinCompanionFromDM(cid, _nj);   // GM had an NPC join → recruit them
        _renderLootPrompt(_detectLoot(acc));   // offer to pocket anything the GM handed over
        _applyDetectedGold(cid, acc);          // update the purse from any gold changing hands
        const _cs = _detectCombatStart(acc); if (_cs) _enterCombat(cid, _cs.enemy, acc);   // a fight breaks out
        if (_chat.skipDmgScan) {
          _chat.skipDmgScan = false;           // this turn narrates a hit already applied by the combat engine
        } else {
          const _inc = _detectIncomingDamageRoll(acc);
          if (_inc) { _renderRollPrompt(null); _rollIncoming(cid, _inc); }   // the GM's attack rolls itself
          else _applyPlayerDamage(cid, acc);   // or a plain-number blow lands → roll, shake, apply HP
        }
        _maybeAdvanceTime(cid);                // let the day drift forward as you play
        const _tod = _detectTimeOfDay(acc); if (_tod >= 0) _setClockTime(cid, _tod);   // keep the clock in step with the fiction
        if (_chat.skipHereScan) _chat.skipHereScan = false;   // just travelled — the destination stands; don't let the narration move it
        else _updateHereFromText(cid, acc);    // and the atlas marker in step with the scene
        _checkFinale(cid, acc);                // did the tale just reach THE END?
        // The GM awarded Inspiration for good play?
        if (/\b(gain|earn(?:ed)?|grant(?:ed|s)?|award(?:ed|s)?|receive[ds]?)\s+(?:you\s+|yourself\s+)?(?:a point of\s+|a moment of\s+)?inspiration\b|you (?:now )?have inspiration\b/i.test(acc) && !/bardic/i.test(acc)) {
          if (_grantInspiration(cid)) { _sfx('level'); _toast('✨ You gain Inspiration — spend it for advantage on a roll.'); }
        }
      }
    }
    _scrollChat();
  }
  return acc;   // the reply text (used by group chat to build the running transcript)
}

// ── Group chat: 2+ companions + you in one thread, each replying in turn ──────
// Reuses _streamAssistant per character (set _chat.char, ensure their session,
// feed the running group transcript so they react to each other and stay in
// character). No adventure machinery — just personas talking.
async function openGroupChat(chars) {
  chars = (chars || []).filter(Boolean);
  if (chars.length < 2) { _toast('Pick at least two characters for a group chat.'); return; }
  if (_view && _view !== 'chat') _chatReturnView = _view;
  const groupChar = {
    id: 'grp-' + chars.map(c => _slugify(c.name)).join('_'),
    name: chars.map(c => c.name.split(/\s+/)[0]).join(' & '),
    avatar: chars.find(c => c.avatar)?.avatar || '',
    relationship: 'a group chat', __group: true,
  };
  _chat.group = chars;
  _chat.char = groupChar;
  _chat.playAs = '';
  applyWorldTheme('');
  switchView('chat');
  renderChatShell(groupChar);
  _fxTitleCard(groupChar.name, `${chars.length} together`);
  const thread = $('studio-thread');
  if (thread) thread.innerHTML = `<div class="rp-typing">Opening the table…</div>`;
  // The group gets its OWN session (keyed on grp-…). All banter saves here and
  // NEVER into the companions' solo sessions — that cross-contamination was why
  // a group chat's text later showed up in a one-on-one. Reopening replays this
  // session, so a group is saved and can be rejoined.
  try { await _ensureSession(groupChar); } catch {}
  await _loadChatHistory();
  if (thread && !thread.querySelector('.rp-msg')) {
    thread.innerHTML = `<div class="rp-typing">${_esc(chars.map(c => c.name).join(', '))} are here. Say something to get them talking.</div>`;
  }
}

async function _streamGroupTurn(userText) {
  const group = _chat.group; if (!group || !group.length) return;
  const groupChar = _chat.char, groupSid = _chat.sessionId;
  const names = group.map(c => c.name).join(', ');
  let transcript = `You: ${_stripTags(userText)}`;
  // Persist the player's line to the GROUP session once, so a saved/rejoined
  // group shows what you said (each reply below also saves to this session).
  try { await fetch(`${API_BASE}/api/session/${groupSid}/message`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ role: 'user', content: _stripTags(userText) }) }); } catch {}
  // Each speaker's _streamAssistant flips _chat.streaming back to false in its
  // finally, so guard the whole multi-speaker turn with a separate flag that
  // sendChat also checks — otherwise a send in the gap between speakers re-enters.
  _chat.groupBusy = true;
  try {
    for (const c of group) {
      _chat.char = c;                 // switch PERSONA (voice) for this reply…
      _chat.sessionId = groupSid;     // …but keep saving to the GROUP session, not c's solo one
      const framed = `[This is a relaxed group conversation between ${names} and the player — not an adventure, just people talking. Here is what has just been said:\n${transcript}\nNow reply AS ${c.name}, fully in character and in your own voice, a few sentences. React naturally to the others and to the player. Never speak or act for anyone but ${c.name}.]`;
      let reply = '';
      try { reply = await _streamAssistant(framed); } catch {}
      if (reply && reply.trim()) transcript += `\n${c.name}: ${_stripTags(reply)}`;
      if (!_chat.group) break;   // user left mid-turn
    }
  } finally {
    _chat.char = groupChar; _chat.sessionId = groupSid;
    _chat.groupBusy = false;
  }
}

function _openGroupPicker() {
  const companions = _chars.filter(c => !_isDM(c));
  if (companions.length < 2) { _toast('Create at least two characters to start a group chat.'); return; }
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-group-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-group-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Start a group chat">
    <div class="chronicle-bar"><h2>Start a group chat</h2><button class="studio-close" id="group-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Pick two or more — they'll each reply in character and react to one another.</p>
      <ul class="group-pick">${companions.map(c => `<li><label><input type="checkbox" value="${_esc(c.id)}"><span class="gp-av">${c.avatar ? `<img src="${_esc(c.avatar)}" alt="">` : _esc(_initial(c.name))}</span><strong>${_esc(c.name)}</strong></label></li>`).join('')}</ul>
      <div class="chronicle-actions"><button class="st-btn" id="group-start" type="button">Start group chat</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  const close = () => { ov.style.display = 'none'; };
  $('group-close').addEventListener('click', close);
  ov.addEventListener('click', (e) => { if (e.target === ov) close(); });
  $('group-start').addEventListener('click', () => {
    const ids = [...ov.querySelectorAll('input:checked')].map(i => i.value);
    const chosen = companions.filter(c => ids.includes(c.id));
    if (chosen.length < 2) { _toast('Pick at least two to talk together.'); return; }
    close();
    openGroupChat(chosen);
  });
}

// ── Snapshots (the Chronicle) ───────────────────────────────────────────────
async function _fetchTranscript() {
  let history = [];
  try {
    const r = await fetch(`${API_BASE}/api/history/${_chat.sessionId}`);
    if (r.ok) history = (await r.json()).history || [];
  } catch {}
  return history.map(m => {
    const content = typeof m.content === 'string'
      ? m.content
      : (Array.isArray(m.content) ? m.content.filter(p => p.type === 'text').map(p => p.text).join('\n') : '');
    return { role: m.role, content };
  }).filter(m => (m.role === 'user' || m.role === 'assistant') && (m.content || '').trim());
}

async function saveSnapshot() {
  if (!_chat.char || !_chat.sessionId) return;
  const btn = $('studio-save-snap');
  const orig = btn ? btn.innerHTML : '';
  if (btn) { btn.disabled = true; btn.textContent = 'Saving…'; }
  try {
    const transcript = await _fetchTranscript();
    if (!transcript.length) { if (btn) { btn.innerHTML = orig; btn.disabled = false; } return; }
    const res = await fetch(`${API_BASE}/api/characters/studio/snapshot`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        character_id: _chat.char.id, character_name: _chat.char.name,
        world_id: _chat.char.world_id || '', transcript, model: _modelLabel(),
      }),
    });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.detail || data.error || 'failed');
    if (btn) { btn.innerHTML = 'Saved ✓'; setTimeout(() => { btn.innerHTML = orig; btn.disabled = false; }, 1600); }
    _toast('📖 Save point written to the Chronicle.');   // the button now lives in a menu — say it out loud
    openChronicle(data.snapshot);   // show the new save-point
  } catch (e) {
    if (btn) { btn.textContent = 'Error'; setTimeout(() => { btn.innerHTML = orig; btn.disabled = false; }, 2000); }
    _toast('⚠ Save point failed — try again in a moment.');
    console.error('Save snapshot failed:', e);
  }
}

async function openChronicle(highlight) {
  const modal = $('studio-modal');
  if (!modal || !_chat.char) return;
  let snaps = [];
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/snapshots?character_id=${encodeURIComponent(_chat.char.id)}`);
    if (r.ok) snaps = (await r.json()).snapshots || [];
  } catch {}
  let panel = $('studio-chronicle-panel');
  if (!panel) { panel = document.createElement('div'); panel.id = 'studio-chronicle-panel'; panel.className = 'chronicle-overlay'; modal.appendChild(panel); }
  const items = snaps.length ? snaps.map(s => `
    <div class="chronicle-card${highlight && highlight.id === s.id ? ' fresh' : ''}">
      <div class="chronicle-head"><h3>${_esc(s.title)}</h3><span class="chronicle-date">${_esc(_fmtDate(s.created_at))}</span></div>
      ${s.story_so_far ? `<p class="chronicle-story">${_esc(s.story_so_far)}</p>` : ''}
      ${s.world_changes ? `<div class="chronicle-changes">${_bullets(s.world_changes)}</div>` : ''}
      <div class="chronicle-actions"><button class="st-btn small" data-continue="${_esc(s.id)}">Continue from here ›</button></div>
    </div>`).join('') : `<p class="chronicle-empty">No save points yet. Hit “Save” to capture where the story stands — its recap and how the world has changed.</p>`;
  panel.innerHTML = `
    <div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Chronicle">
      <div class="chronicle-bar"><h2>Chronicle — ${_esc(_chat.char.name)}</h2><button class="studio-close" id="chronicle-close" type="button" aria-label="Close">✕</button></div>
      <div class="chronicle-list">${items}</div>
      <div class="chronicle-backup">
        <span class="chronicle-backup-hint">Back up this campaign — sheet, pack, quests, memory, map &amp; realm.</span>
        <div class="chronicle-backup-btns">
          <button class="st-btn ghost small" id="chronicle-export" type="button">⬇ Export</button>
          <button class="st-btn ghost small" id="chronicle-import" type="button">⬆ Import</button>
          <input type="file" id="chronicle-import-file" accept="application/json,.json" hidden>
        </div>
      </div>
    </div>`;
  panel.style.display = 'flex';
  $('chronicle-close').addEventListener('click', () => { panel.style.display = 'none'; });
  panel.addEventListener('click', (e) => { if (e.target === panel) panel.style.display = 'none'; });
  panel.querySelectorAll('[data-continue]').forEach(b =>
    b.addEventListener('click', () => { const s = snaps.find(x => x.id === b.dataset.continue); if (s) continueFromSnapshot(s); }));
  $('chronicle-export').addEventListener('click', () => _exportCampaign(_chat.char.id, _chat.char.name));
  const impFile = $('chronicle-import-file');
  $('chronicle-import').addEventListener('click', () => impFile.click());
  impFile.addEventListener('change', () => { if (impFile.files && impFile.files[0]) _importCampaign(_chat.char.id, impFile.files[0]); impFile.value = ''; });
}

// ── Campaign backup ─────────────────────────────────────────────────────────
// Export/import the full server-side world-state for one character (sheet, pack,
// quests, memory, battle-map, realm, clock, …). Atomic writes already protect
// against torn saves; this covers accidental loss and moving between machines.
// (The chat transcript lives in the session and isn't included — snapshots
// capture the narrative recap for that.)
function _csToast(msg) { (window.showToast || window.alert)(msg); }

async function _exportCampaign(cid, name) {
  let state = {};
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/state/${encodeURIComponent(cid)}`);
    if (r.ok) state = (await r.json()).state || {};
  } catch {}
  const payload = { odysseus_campaign: 1, character_id: cid, character_name: name || cid, exported: new Date().toISOString(), state };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const safe = (name || cid).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'save';
  const a = document.createElement('a');
  a.href = url; a.download = `campaign-${safe}-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function _importCampaign(cid, file) {
  let data;
  try { data = JSON.parse(await file.text()); } catch { _csToast('That file isn’t valid JSON.'); return; }
  if (!data || data.odysseus_campaign !== 1 || !data.state || typeof data.state !== 'object') {
    _csToast('That isn’t an Odysseus campaign export.'); return;
  }
  const kinds = Object.keys(data.state).filter(k => _WS_KEYS[k]);
  if (!kinds.length) { _csToast('Nothing to import in that file.'); return; }
  const fromName = data.character_name && data.character_name !== cid ? ` (from “${data.character_name}”)` : '';
  const ok = window.styledConfirm
    ? await window.styledConfirm(`Import will OVERWRITE this character’s current campaign — ${kinds.length} parts${fromName}. This can’t be undone. Continue?`, { confirmText: 'Import & overwrite', danger: true })
    : window.confirm('Overwrite the current campaign with the imported save?');
  if (!ok) return;
  for (const kind of kinds) {
    try {
      await fetch(`${API_BASE}/api/characters/studio/state/${encodeURIComponent(cid)}/${kind}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ value: data.state[kind] }),
      });
    } catch {}
  }
  await _hydrateState(cid);     // pull the restored state into the local cache
  const panel = $('studio-chronicle-panel'); if (panel) panel.style.display = 'none';
  renderChatShell(_chat.char);  // re-render panels/banner from the restored state
  _csToast('Campaign imported.');
}

async function continueFromSnapshot(s) {
  const char = _chat.char;
  if (!char) return;
  const panel = $('studio-chronicle-panel'); if (panel) panel.style.display = 'none';
  // Branch forward: a fresh session for this character, seeded with the recap.
  const fd = new FormData();
  fd.append('name', `${char.name} — ${s.title || 'continued'}`);
  try {
    const sessions = sessionModule.getSessions ? sessionModule.getSessions() : [];
    const cur = sessions.find(x => x.id === (sessionModule.getCurrentSessionId ? sessionModule.getCurrentSessionId() : null));
    if (cur) { fd.append('endpoint_url', cur.endpoint_url || ''); fd.append('model', cur.model || ''); fd.append('skip_validation', 'true'); }
  } catch {}
  let sid = null;
  try { const res = await fetch(`${API_BASE}/api/session`, { method: 'POST', body: fd }); const data = await res.json(); sid = data.session_id || data.id; } catch {}
  if (!sid) return;
  const map = _loadMap(); map[char.id] = sid; _saveMap(map);
  _chat.sessionId = sid;
  renderChatShell(char);
  const thread = $('studio-thread'); if (thread) thread.innerHTML = '';
  const recap = `Story so far: ${s.story_so_far || '(a tale already underway)'}\nWorld state / what has changed:\n${s.world_changes || '(unrecorded)'}`;
  _chat.recapTurn = true;   // this reply re-narrates past events — don't mine it for "new" loot/gold/damage
  await _streamAssistant(`[We are continuing a saved story. ${recap}\nPick the story up from here: re-establish the current scene and ${_isDM(char) ? 'end by asking what I do' : 'greet me in character'}. Do not speak or act for me.]`);
}

// ── Character sheet + inventory + dice (D&D 5e layer) ────────────────────────
const SHEET_KEY = (cid) => `studio-sheet-${cid}`;
const ABILITIES = ['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'];

function _defaultSheet() {
  return {
    name: '', cls: 'Adventurer', level: 1, xp: 0, hp: 10, hpMax: 10, ac: 10, gold: 0,
    abilities: { STR: 10, DEX: 10, CON: 10, INT: 10, WIS: 10, CHA: 10 },
    inventory: [], conditions: [], notes: '', spells: [], slots: {}, profSkills: [], profSaves: [], hitDie: 8,
  };
}
// Currency is one number; only its name changes per world.
function _currencyLabel(worldId) { return ({ embervale: 'gold', neonspire: 'credits', everyday: 'cash' })[worldId] || 'gold'; }
function _currency(cid) { return _currencyLabel(_chat.char && _chat.char.world_id); }
// Rough market value of an item by rarity (buy price); you sell for half.
function _itemValue(it) { const base = { common: 6, uncommon: 20, rare: 65, epic: 175, legendary: 500 }[(it && it.rarity) || 'common'] || 6; return base; }
function _sellValue(it) { return Math.max(1, Math.floor(_itemValue(it) / 2)); }
function _addGold(cid, delta) { const s = _loadSheet(cid); s.gold = Math.max(0, Math.round((s.gold || 0) + delta)); _saveSheet(cid, s); return s.gold; }
function _loadSheet(cid) {
  try {
    const s = JSON.parse(localStorage.getItem(SHEET_KEY(cid)) || 'null');
    if (s && s.abilities) {
      const sheet = { ..._defaultSheet(), ...s, abilities: { ..._defaultSheet().abilities, ...s.abilities } };
      // Self-heal: a caster with spell slots but an empty spellbook (legacy saves
      // or a creation path that seeded slots but skipped spells) gets its starting
      // spells so a "Wizard with no spells" can actually cast.
      if ((!sheet.spells || !sheet.spells.length)
          && Object.values(sheet.slots || {}).some(sl => (sl && sl.max) > 0)
          && (CLASS_SPELLS[sheet.cls] || []).length) {
        sheet.spells = CLASS_SPELLS[sheet.cls].map(([name, level]) => ({ name, level }));
        try { localStorage.setItem(SHEET_KEY(cid), JSON.stringify(sheet)); } catch {}
      }
      return sheet;
    }
  } catch {}
  return _defaultSheet();
}
function _saveSheet(cid, s) { try { localStorage.setItem(SHEET_KEY(cid), JSON.stringify(s)); } catch {} _pushState(cid, 'sheet', s); }
// GM mode (global): off = the game owns calculated stats; on = edit anything.
function _gmMode() { try { return localStorage.getItem('studio-gmmode') === '1'; } catch { return false; } }
function _setGmMode(v) { try { localStorage.setItem('studio-gmmode', v ? '1' : '0'); } catch {} }
// Class templates — set hit die, saving-throw proficiencies, suggested skills,
// and (for full casters) spell slots for the current level.
const _CASTER_SLOTS = { 1: { 1: 2 }, 2: { 1: 3 }, 3: { 1: 4, 2: 2 }, 4: { 1: 4, 2: 3 }, 5: { 1: 4, 2: 3, 3: 2 }, 6: { 1: 4, 2: 3, 3: 3 }, 7: { 1: 4, 2: 3, 3: 3, 4: 1 }, 8: { 1: 4, 2: 3, 3: 3, 4: 2 }, 9: { 1: 4, 2: 3, 3: 3, 4: 3, 5: 1 } };
function _fullCasterSlots(level) { const m = _CASTER_SLOTS[Math.max(1, Math.min(9, level || 1))] || {}; const out = {}; [1, 2, 3, 4, 5].forEach(l => { out[l] = { max: m[l] || 0, used: 0 }; }); return out; }
const CLASS_PRESETS = {
  Fighter: { hitDie: 10, saves: ['STR', 'CON'], skills: ['athletics', 'perception'], caster: false },
  Barbarian: { hitDie: 12, saves: ['STR', 'CON'], skills: ['athletics', 'survival'], caster: false },
  Rogue: { hitDie: 8, saves: ['DEX', 'INT'], skills: ['stealth', 'perception', 'acrobatics', 'sleight of hand'], caster: false },
  Ranger: { hitDie: 10, saves: ['STR', 'DEX'], skills: ['survival', 'perception', 'stealth'], caster: false },
  Monk: { hitDie: 8, saves: ['STR', 'DEX'], skills: ['acrobatics', 'stealth'], caster: false },
  Paladin: { hitDie: 10, saves: ['WIS', 'CHA'], skills: ['athletics', 'persuasion'], caster: false },
  Wizard: { hitDie: 6, saves: ['INT', 'WIS'], skills: ['arcana', 'investigation'], caster: true },
  Sorcerer: { hitDie: 6, saves: ['CON', 'CHA'], skills: ['arcana', 'deception'], caster: true },
  Cleric: { hitDie: 8, saves: ['WIS', 'CHA'], skills: ['insight', 'medicine', 'religion'], caster: true },
  Druid: { hitDie: 8, saves: ['INT', 'WIS'], skills: ['nature', 'perception', 'medicine'], caster: true },
  Bard: { hitDie: 8, saves: ['DEX', 'CHA'], skills: ['persuasion', 'performance', 'deception'], caster: true },
  Warlock: { hitDie: 8, saves: ['WIS', 'CHA'], skills: ['arcana', 'deception'], caster: true },
};
// ── Multiclassing (light-but-real) ─────────────────────────────────────────
// When a hero holds more than one class the source of truth is
//   s.classes = [{cls, levels, subclass}]
// Single-class heroes never need it: _classesOf synthesizes the array from the
// old s.cls / s.level / s.subclass fields, so every existing sheet Just Works.
function _classesOf(s) {
  if (Array.isArray(s.classes) && s.classes.length) return s.classes;
  return [{ cls: s.cls || 'Adventurer', levels: s.level || 1, subclass: s.subclass || '' }];
}
function _classLevelOf(s, cls) { const e = _classesOf(s).find(c => c.cls === cls); return e ? e.levels : 0; }
function _dieFor(cls) { return (CLASS_PRESETS[cls] || {}).hitDie || 8; }
// Effective caster level for the shared multiclass slot table: full casters
// count fully, half-casters (Ranger/Paladin) at half. ponytail: Warlock counts
// as a full caster here — our model never split out pact magic, fine for scope.
function _effCasterLevel(classes) {
  let n = 0;
  classes.forEach(c => {
    const p = CLASS_PRESETS[c.cls]; if (!p) return;
    if (p.caster) n += c.levels;
    else if (c.cls === 'Ranger' || c.cls === 'Paladin') n += Math.floor(c.levels / 2);
  });
  return n;
}
// The class whose spellcasting ability drives DC/attack — the caster class with
// the most levels (so a Fighter 5 / Wizard 1 still casts off INT).
function _casterClassOf(s) {
  const cs = _classesOf(s).filter(c => CAST_ABIL[c.cls]).sort((a, b) => b.levels - a.levels);
  return cs.length ? cs[0].cls : (s.cls || null);
}
// One representative ability for the multiclass prereq (5e wants 13 in the key
// stat to branch into a class). ponytail: single-stat gate, not the full AND/OR.
const _MC_ABILITY = { Fighter: 'STR', Barbarian: 'STR', Rogue: 'DEX', Ranger: 'DEX', Monk: 'DEX', Paladin: 'CHA', Wizard: 'INT', Sorcerer: 'CHA', Cleric: 'WIS', Druid: 'WIS', Bard: 'CHA', Warlock: 'CHA' };
function _canMulticlass(s, cls) { const a = _MC_ABILITY[cls]; return !a || (((s.abilities && s.abilities[a]) || 10) >= 13); }
// Re-derive the compat fields (level/cls/hitDie/subclass) from s.classes.
function _syncClassCompat(s) {
  const cs = _classesOf(s);
  s.level = cs.reduce((t, c) => t + c.levels, 0);
  const prim = cs.slice().sort((a, b) => b.levels - a.levels)[0];
  s.cls = prim.cls; s.hitDie = _dieFor(prim.cls); s.subclass = prim.subclass || '';
}
// How the class(es) read to the GM: single-class keeps the old phrasing; a
// multiclass hero lists every class and its subclass.
function _classLine(s) {
  const cs = _classesOf(s);
  if (cs.length === 1) {
    const c = cs[0];
    return `level ${s.level} ${s.clsSkin ? `${s.clsSkin} (${c.cls})` : c.cls}${c.subclass ? ` [${c.subclass}]` : ''}`;
  }
  return `level ${s.level} multiclass — ${cs.map(c => `${c.cls} ${c.levels}${c.subclass ? ` (${c.subclass})` : ''}`).join(' / ')}`;
}
// True if the hero has this subclass on ANY of their classes — so a multiclassed
// Fighter(Champion) still crits on 19 even when Rogue is the primary class.
function _isSubclass(s, name) { return (s.subclass === name) || _classesOf(s).some(c => c.subclass === name); }

// Starting spells per caster class — a Wizard should never begin with an empty
// spellbook. Seeded at character creation (cantrips = level 0).
const CLASS_SPELLS = {
  Wizard:   [['Fire Bolt', 0], ['Mage Hand', 0], ['Light', 0], ['Magic Missile', 1], ['Shield', 1], ['Sleep', 1]],
  Sorcerer: [['Fire Bolt', 0], ['Prestidigitation', 0], ['Ray of Frost', 0], ['Chromatic Orb', 1], ['Shield', 1]],
  Cleric:   [['Sacred Flame', 0], ['Guidance', 0], ['Cure Wounds', 1], ['Bless', 1], ['Guiding Bolt', 1]],
  Druid:    [['Produce Flame', 0], ['Guidance', 0], ['Entangle', 1], ['Cure Wounds', 1]],
  Bard:     [['Vicious Mockery', 0], ['Minor Illusion', 0], ['Healing Word', 1], ['Charm Person', 1], ['Dissonant Whispers', 1]],
  Warlock:  [['Eldritch Blast', 0], ['Mage Hand', 0], ['Hex', 1], ['Armor of Agathys', 1]],
};
function _seedSpells(s, cls) {
  if ((s.spells || []).length) return;
  s.spells = (CLASS_SPELLS[cls] || []).map(([name, level]) => ({ name, level }));
}

// Real class features by level (SRD-flavored, levels 1–10). Granted on level-up,
// shown on the sheet, and fed to the GM so the fiction honors them.
const CLASS_FEATURES = {
  Fighter:   { 1: ['Second Wind (bonus action: recover 1d10+level HP, once per rest)'], 2: ['Action Surge (one extra action, once per rest)'], 3: ['Martial Archetype'], 5: ['Extra Attack (attack twice)'], 9: ['Indomitable (reroll a failed save, once per rest)'] },
  Barbarian: { 1: ['Rage (bonus damage, resist physical, advantage on STR — 2/rest)', 'Unarmored Defense (AC = 10 + DEX + CON)'], 2: ['Reckless Attack (advantage now, enemies get it back)', 'Danger Sense (advantage on DEX saves you can see)'], 3: ['Primal Path'], 5: ['Extra Attack', 'Fast Movement'], 7: ['Feral Instinct (advantage on initiative)'], 9: ['Brutal Critical (+1 die on crits)'] },
  Rogue:     { 1: ['Sneak Attack 1d6 (advantage or ally adjacent)', "Thieves' Cant"], 2: ['Cunning Action (Dash/Disengage/Hide as bonus action)'], 3: ['Sneak Attack 2d6', 'Roguish Archetype'], 5: ['Sneak Attack 3d6', 'Uncanny Dodge (halve one hit per turn)'], 7: ['Sneak Attack 4d6', 'Evasion (DEX saves: fail = half, pass = none)'], 9: ['Sneak Attack 5d6'] },
  Ranger:    { 1: ['Favored Enemy', 'Natural Explorer'], 2: ['Fighting Style', 'Spellcasting (ranger)'], 3: ['Ranger Archetype', "Primeval Awareness"], 5: ['Extra Attack'], 8: ["Land's Stride"], 10: ['Hide in Plain Sight'] },
  Monk:      { 1: ['Martial Arts (d4 unarmed, bonus-action strike)', 'Unarmored Defense (AC = 10 + DEX + WIS)'], 2: ['Ki (Flurry of Blows, Patient Defense, Step of the Wind)'], 3: ['Monastic Tradition', 'Deflect Missiles'], 4: ['Slow Fall'], 5: ['Extra Attack', 'Stunning Strike'], 6: ['Ki-Empowered Strikes'], 7: ['Evasion', 'Stillness of Mind'] },
  Paladin:   { 1: ['Divine Sense', 'Lay on Hands (heal pool = 5×level)'], 2: ['Fighting Style', 'Divine Smite (spend a slot for +2d8 radiant)', 'Spellcasting (paladin)'], 3: ['Sacred Oath', 'Divine Health (immune to disease)'], 5: ['Extra Attack'], 6: ['Aura of Protection (+CHA to nearby saves)'], 10: ['Aura of Courage'] },
  Wizard:    { 1: ['Arcane Recovery (regain slots on a short rest, once/day)'], 2: ['Arcane Tradition'], 10: ['Arcane Tradition feature'] },
  Sorcerer:  { 1: ['Sorcerous Origin'], 2: ['Font of Magic (sorcery points)'], 3: ['Metamagic (twin, quicken…)'], 10: ['Metamagic option'] },
  Cleric:    { 1: ['Divine Domain'], 2: ['Channel Divinity (1/rest) — Turn Undead'], 5: ['Destroy Undead'], 6: ['Channel Divinity (2/rest)'], 8: ['Divine Strike / Potent Spellcasting'], 10: ['Divine Intervention'] },
  Druid:     { 2: ['Wild Shape (become a beast, 2/rest)', 'Druid Circle'], 4: ['Wild Shape improvement (swimming)'], 8: ['Wild Shape improvement (flying)'] },
  Bard:      { 1: ['Bardic Inspiration d6 (bonus action: gift a die)'], 2: ['Jack of All Trades (+half prof to everything)', 'Song of Rest'], 3: ['Bard College', 'Expertise (double prof in two skills)'], 5: ['Bardic Inspiration d8', 'Font of Inspiration (recharge on short rest)'], 6: ['Countercharm'], 10: ['Bardic Inspiration d10', 'Magical Secrets'] },
  Warlock:   { 1: ['Otherworldly Patron', 'Pact Magic (slots return on a short rest)'], 2: ['Eldritch Invocations'], 3: ['Pact Boon (blade, chain, or tome)'], 6: ['Patron feature'], 10: ['Patron feature'] },
};
// Features gained crossing from level `from` to `to` (exclusive → inclusive).
function _featuresGained(cls, from, to) {
  const tbl = CLASS_FEATURES[cls] || {}; const out = [];
  for (let l = from + 1; l <= to; l++) (tbl[l] || []).forEach(f => out.push({ level: l, name: f }));
  return out;
}

// Active class features — the headline abilities are buttons, not just text.
// Each entry: uses per rest ('short'|'long'), and an effect that returns the
// in-fiction line sent to the GM (mechanics applied to the sheet first).
const FEATURE_ACTIONS = {
  'Second Wind': { rest: 'short', uses: 1, act(cid, s) {
    const heal = 1 + Math.floor(Math.random() * 10) + (s.level || 1);
    s.hp = Math.min(s.hpMax, (s.hp || 0) + heal);
    const cc = _loadCombat(cid); if (cc.active) { const pc = cc.combatants.find(x => x.id === 'pc'); if (pc) { pc.hp = Math.min(pc.hpMax, pc.hp + heal); _saveCombat(cid, cc); } }
    _fxPotion(true);
    return `💨 *Second Wind — you steady yourself and recover **${heal} HP** (now ${s.hp}/${s.hpMax}).*`;
  } },
  'Action Surge': { rest: 'short', uses: 1, act() {
    return `⚡ *Action Surge — you push past your limits and take one extra action this turn.*`;
  } },
  'Rage': { rest: 'long', uses: 2, act(cid, s) {
    s.conditions = (s.conditions || []).concat([{ name: 'raging (adv. STR, resist phys.)', rounds: 10 }]);
    _fxShake();
    return `😤 *You RAGE — advantage on Strength, resistance to physical damage, +2 melee damage while it lasts.*`;
  } },
  'Lay on Hands': { rest: 'long', uses: 1, act(cid, s) {
    const pool = 5 * (s.level || 1);
    const heal = Math.min(pool, Math.max(0, s.hpMax - (s.hp || 0))) || pool;
    s.hp = Math.min(s.hpMax, (s.hp || 0) + heal);
    _fxPotion(true);
    return `✋ *Lay on Hands — holy warmth closes your wounds for **${heal} HP** (now ${s.hp}/${s.hpMax}).*`;
  } },
  'Bardic Inspiration': { rest: 'long', uses: 3, act() {
    return `🎶 *Bardic Inspiration — you gift an inspiring word (a d6 to add to one roll). Tell me who receives it.*`;
  } },
  'Wild Shape': { rest: 'short', uses: 2, act(cid, s) {
    s.conditions = (s.conditions || []).concat([{ name: 'wild shape' }]);
    return `🐺 *Wild Shape — your form flows into a beast. GM: ask what animal, and run my stats accordingly.*`;
  } },
  'Ki': { rest: 'short', uses: 3, act() {
    return `🌀 *You spend Ki — Flurry of Blows, Patient Defense, or Step of the Wind (I'll say which).*`;
  } },
  'Divine Sense': { rest: 'long', uses: 3, act() {
    return `✨ *Divine Sense — you open your awareness to celestial, fiendish, or undead presences nearby. GM: what do I feel?*`;
  } },
  'Channel Divinity': { rest: 'short', uses: 1, act() {
    return `🕯 *Channel Divinity — divine power floods through you (Turn Undead or your domain's rite).*`;
  } },
  'Arcane Recovery': { rest: 'long', uses: 1, act(cid, s) {
    const budget = Math.ceil((s.level || 1) / 2); let left = budget;
    [1, 2, 3, 4, 5].forEach(l => { const sl = (s.slots || {})[l]; if (sl && sl.used > 0 && left >= l) { const back = Math.min(sl.used, Math.floor(left / l)); if (back > 0) { sl.used -= back; left -= back * l; } } });
    return `📖 *Arcane Recovery — you study your spellbook and recover spent slots (up to ${budget} levels' worth).*`;
  } },
};
// Match a sheet feature string ("Rage (bonus damage…)") to its action by prefix.
function _featAction(featName) {
  const key = Object.keys(FEATURE_ACTIONS).find(k => (featName || '').toLowerCase().startsWith(k.toLowerCase()));
  return key ? { key, ...FEATURE_ACTIONS[key] } : null;
}
function _useFeature(cid, featName) {
  if (_chat.streaming) return;
  const fa = _featAction(featName); if (!fa) return;
  const s = _loadSheet(cid);
  s.featUses = s.featUses || {};
  if ((s.featUses[fa.key] || 0) >= fa.uses) return;
  s.featUses[fa.key] = (s.featUses[fa.key] || 0) + 1;
  const msg = fa.act(cid, s);
  _saveSheet(cid, s);
  _appendBubble('me', msg); _scrollChat();
  const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
  if (_isDM(_chat.char)) _streamAssistant(msg);
}
// Rest recharges: short rest returns short-rest features; long rest returns all.
// Subclass signature moves — real Use buttons with per-rest charges, granted
// when the path is chosen at level 3 (SUBCLASS_GRANTS below).
Object.assign(FEATURE_ACTIONS, {
  'Combat Maneuver': { rest: 'short', uses: 4, act() { const d = 1 + Math.floor(Math.random() * 8); return `🎖 *Superiority die spent — trip, disarm, riposte, or feint for **+${d}** to the effect. Tell the GM which maneuver.*`; } },
  'Frenzy': { rest: 'long', uses: 1, act(cid, s) { s.conditions = (s.conditions || []).concat([{ name: 'frenzied (extra melee attack each turn)', rounds: 10 }]); _fxShake(); return `🩸 *You give yourself to FRENZY — an extra melee attack every turn while raging. When it ends, add a level of exhaustion.*`; } },
  'Sacred Weapon': { rest: 'long', uses: 1, act(cid, s) { const cha = Math.max(1, _mod((s.abilities || {}).CHA || 10)); s.conditions = (s.conditions || []).concat([{ name: `sacred weapon (+${cha} to hit, sheds light)`, rounds: 10 }]); return `✨ *Your weapon ignites with holy light — **+${cha}** to attack rolls for the next minute.*`; } },
  'Vow of Enmity': { rest: 'long', uses: 1, act(cid, s) { s.conditions = (s.conditions || []).concat([{ name: 'vow of enmity (advantage vs your sworn foe)', rounds: 10 }]); return `⚔ *You swear vengeance — name your foe aloud: ADVANTAGE on every attack against them.*`; } },
  'Arcane Ward': { rest: 'long', uses: 1, act(cid, s) { const ward = 2 * (s.level || 1) + Math.max(0, _mod((s.abilities || {}).INT || 10)); s.conditions = (s.conditions || []).concat([{ name: `arcane ward (absorbs ${ward} damage)`, rounds: 99 }]); return `🛡 *A woven ward of abjuration surrounds you — it absorbs the next **${ward}** damage before your HP does.*`; } },
  'Tides of Chaos': { rest: 'long', uses: 1, act() { return `🌪 *You ride the chaos — ADVANTAGE on your next attack, check, or save. (The GM may let wild magic surge in return…)*`; } },
  'Guided Strike': { rest: 'long', uses: 1, act() { return `🎯 *Guided Strike — the divine steadies your hand: **+10** to the attack roll you just made.*`; } },
  'Cutting Words': { rest: 'long', uses: 3, act() { const d = 1 + Math.floor(Math.random() * 8); return `🎻 *Cutting Words — your mockery lands where armor doesn't: **−${d}** from an enemy's attack, check, or damage roll.*`; } },
  'Fey Presence': { rest: 'short', uses: 1, act() { return `🧚 *Fey Presence washes over everyone within 10 feet — each must save (WIS) or be CHARMED or FRIGHTENED by you until your next turn.*`; } },
  'Shadow Step': { rest: 'short', uses: 2, act() { return `🌑 *You step through shadow — teleport up to 60 ft between patches of dim light or darkness; advantage on your next melee strike.*`; } },
});
// Which Use-feature each path grants the moment it's chosen.
const SUBCLASS_GRANTS = {
  'Battle Master': 'Combat Maneuver', 'Berserker': 'Frenzy',
  'Oath of Devotion': 'Sacred Weapon', 'Oath of Vengeance': 'Vow of Enmity',
  'Abjurer': 'Arcane Ward', 'Wild Magic': 'Tides of Chaos',
  'War Domain': 'Guided Strike', 'College of Lore': 'Cutting Words',
  'The Archfey': 'Fey Presence', 'Way of Shadow': 'Shadow Step',
};

function _rechargeFeatures(cid, restKind) {
  const s = _loadSheet(cid); if (!s.featUses) return;
  Object.keys(s.featUses).forEach(k => {
    const fa = FEATURE_ACTIONS[k];
    // A long rest resets everything (even uses we don't have a table entry for,
    // which otherwise stay stuck "used" forever); a short rest only its own.
    if (restKind === 'long' || (fa && fa.rest === 'short')) delete s.featUses[k];
  });
  _saveSheet(cid, s);
}
function _applyClass(cid, name) {
  const p = CLASS_PRESETS[name]; if (!p) return;
  const s = _loadSheet(cid);
  s.cls = name; s.hitDie = p.hitDie; s.profSaves = [...p.saves];
  s.profSkills = Array.from(new Set([...(s.profSkills || []), ...p.skills]));
  if (p.caster) { s.slots = _fullCasterSlots(s.level || 1); _seedSpells(s, name); }
  _saveSheet(cid, s); renderSheetPanel();
  _appendBubble('me', `*Class set to **${name}** — d${p.hitDie} hit die, saves in ${p.saves.join(' & ')}${p.caster ? ', spellcaster' : ''}.*`); _scrollChat();
}
// Renown & treasure tiers — leveling should change how the WORLD treats you,
// not just your numbers. Fed to the GM with every turn via the sheet summary.
function _renownText(level) {
  if (level >= 10) return 'Renown: a living LEGEND — songs are sung, rulers request audiences, enemies send champions not thugs. Treasure tier: named artifacts and legendary relics are within reach.';
  if (level >= 8) return 'Renown: a famous hero — strangers know the name and deeds; factions actively court or fear them. Treasure tier: epic gear suits their exploits.';
  if (level >= 5) return 'Renown: a renowned adventurer — word travels ahead of them; folk ask for help, rivals take notice. Treasure tier: rare and finely-made magical gear appears among rewards.';
  if (level >= 3) return 'Renown: a proven adventurer locals speak of. Treasure tier: quality and uncommon gear appears among rewards.';
  return 'Renown: an unknown newcomer — nobody owes them anything yet. Treasure tier: rewards are humble — coin and simple gear.';
}
function _mod(score) { return Math.floor((Number(score || 10) - 10) / 2); }
function _modStr(score) { const m = _mod(score); return (m >= 0 ? '+' : '') + m; }
// ── Core D&D: heritage, spellcasting stats, concentration, passive senses ────
// Heritage (species) — ability bonuses, speed, darkvision, and signature
// traits. Optional (defaults to none); Human is the safe pick for any setting.
const HERITAGES = {
  Human:      { abil: { STR: 1, DEX: 1, CON: 1, INT: 1, WIS: 1, CHA: 1 }, speed: 30, dark: 0, traits: ['Versatile — a little better at everything'], line: 'adaptable and ambitious' },
  Elf:        { abil: { DEX: 2 }, speed: 30, dark: 60, skills: ['perception'], traits: ['Keen Senses (trained in Perception)', 'Fey Ancestry (advantage on saves vs charm; magic can’t put you to sleep)', 'Trance (a 4-hour rest suffices)'], line: 'graceful, long-lived, fey-touched' },
  Dwarf:      { abil: { CON: 2 }, speed: 25, dark: 60, traits: ['Dwarven Resilience (advantage on saves vs poison; resistance to poison damage)', 'Stonecunning'], line: 'hardy, stubborn, stone-wise' },
  Halfling:   { abil: { DEX: 2 }, speed: 25, dark: 0, lucky: true, traits: ['Lucky (reroll natural 1s on d20 rolls)', 'Brave (advantage on saves vs frightened)', 'Nimble'], line: 'small, brave, and improbably lucky' },
  'Half-Orc': { abil: { STR: 2, CON: 1 }, speed: 30, dark: 60, relentless: true, traits: ['Relentless Endurance (once per long rest, drop to 1 HP instead of 0)', 'Savage Attacks (an extra weapon die on melee crits)'], line: 'powerful, fierce, and hard to put down' },
  Tiefling:   { abil: { CHA: 2, INT: 1 }, speed: 30, dark: 60, traits: ['Hellish Resistance (resistance to fire damage)', 'Infernal Legacy'], line: 'infernal-blooded, charismatic, and distrusted' },
  Dragonborn: { abil: { STR: 2, CHA: 1 }, speed: 30, dark: 0, traits: ['Breath Weapon (a burst of elemental damage, once per rest)', 'Draconic Resistance'], line: 'proud, draconic, and elemental' },
  Gnome:      { abil: { INT: 2 }, speed: 25, dark: 60, traits: ['Gnome Cunning (advantage on INT/WIS/CHA saves vs magic)'], line: 'clever, curious, and tiny' },
  'Half-Elf': { abil: { CHA: 2, DEX: 1, WIS: 1 }, speed: 30, dark: 60, traits: ['Fey Ancestry (advantage on saves vs charm; no magical sleep)', 'a broad, versatile upbringing'], line: 'caught between two worlds — charming and adaptable' },
};
function _heritageOf(s) { return (s && s.race && HERITAGES[s.race]) ? { name: s.race, ...HERITAGES[s.race] } : null; }
function _heritageText(s) {
  const h = _heritageOf(s); if (!h) return '';
  return `Heritage: ${s.race} — ${h.line}. Speed ${h.speed} ft${h.dark ? `, darkvision ${h.dark} ft` : ''}. Racial traits: ${h.traits.join('; ')}. Honor these in play (e.g. advantages, resistances, darkvision).`;
}

// Spellcasting statistics — the numbers that make "make a save against my spell"
// mean something. Save DC = 8 + proficiency + casting-ability modifier.
const CAST_ABIL = { Wizard: 'INT', Sorcerer: 'CHA', Cleric: 'WIS', Druid: 'WIS', Bard: 'CHA', Warlock: 'CHA', Paladin: 'CHA', Ranger: 'WIS' };
function _castingAbility(cls) { return CAST_ABIL[cls] || null; }
function _spellSaveDC(s) { const a = _castingAbility(_casterClassOf(s)); if (!a) return null; return 8 + _profBonus(s) + _mod((s.abilities && s.abilities[a]) || 10); }
function _spellAttack(s) { const a = _castingAbility(_casterClassOf(s)); if (!a) return null; return _profBonus(s) + _mod((s.abilities && s.abilities[a]) || 10); }

// Passive Perception — what you notice without looking: 10 + WIS mod (+ prof if trained).
function _passivePerception(s) { return 10 + _mod((s.abilities && s.abilities.WIS) || 10) + ((s.profSkills || []).includes('perception') ? _profBonus(s) : 0) + (s.featObservant ? 5 : 0); }

// Concentration — you can hold only ONE concentration spell; casting a new one
// drops the old, and taking damage forces a CON save (DC 10 or half the damage,
// whichever is higher) to keep it.
const _CONC_SPELLS = new Set(SPELLS.filter(sp => sp.conc).map(sp => sp.name.toLowerCase()));
function _isConcSpell(name) { return _CONC_SPELLS.has((name || '').toLowerCase()); }
// Spells that force the target to make a saving throw (so we hand the GM the DC).
const _SAVE_SPELLS = new Set(['sacred flame', 'vicious mockery', 'charm person', 'hold person', 'entangle', 'dissonant whispers']);
function _needsSave(name) { return _SAVE_SPELLS.has((name || '').toLowerCase()); }

function _sheetSummary(s, cid) {
  const ac = cid ? _effAC(cid) : _baseAC(s, null);   // real AC (DEX + armor), not the legacy flat field
  const ab = ABILITIES.map(k => `${k} ${s.abilities[k]} (${_modStr(s.abilities[k])})`).join(', ');
  const bg = s.background && BACKGROUNDS[s.background];
  const dc = _spellSaveDC(s);
  const skinLine = s.clsSkin
    ? `In this world the ${s.cls} is known as a ${s.clsSkin} — always use that name. ${s.clsFlavor || ''}${s.slotName ? ` Call spell slots "${s.slotName}".` : ''} Same rules, this world's words. `
    : '';
  const exhLine = s.exhaustion ? `Exhaustion level ${s.exhaustion} (${_EXHAUSTION.slice(1, Math.min(6, s.exhaustion) + 1).join('; ')}) — enforce it. ` : '';
  const subLine = s.subclass ? `Subclass: ${s.subclass} — ${_subclassLine(s)} Honor its features. ` : '';
  const storyLine = s.backstory ? `Backstory (canon — weave it in, let it surface in NPCs, dreams, and stakes): ${String(s.backstory).slice(0, 400)}. ` : '';
  return `${s.name || 'the hero'}, ${s.race ? s.race + ' ' : ''}${_classLine(s)}${s.background ? ` (${s.background} background — ${bg ? bg.line : ''})` : ''}. ${skinLine}${subLine}${storyLine}${exhLine}HP ${s.hp}/${s.hpMax}, AC ${ac}, passive Perception ${_passivePerception(s)}. Purse: ${s.gold || 0} ${_currency()}. `
    + `${_renownText(s.level || 1)} `
    + (_heritageText(s) ? `${_heritageText(s)} ` : '')
    + `Abilities: ${ab}. `
    + (dc != null ? `Spell save DC ${dc}, spell attack +${_spellAttack(s)} (enemies roll saves against this; use these numbers). ` : '')
    + (s.concentration ? `Currently concentrating on ${s.concentration.name} (it ends if concentration breaks). ` : '')
    + (s.inspiration ? 'They hold Inspiration (they may spend it for advantage on a roll). ' : 'They have no Inspiration right now — you (GM) may award it for clever, brave, or in-character play by saying they "gain inspiration". ')
    + `Conditions: ${s.conditions.length ? s.conditions.map(c => typeof c === 'string' ? c : `${c.name}${c.rounds != null ? ` (${c.rounds})` : ''}`).join(', ') : 'none'}.`
    + (_conditionEffectsText(s) ? ` ${_conditionEffectsText(s)}` : '')
    + ((s.feats && s.feats.length) ? ` Feats: ${s.feats.map(f => `${f} (${(FEATS[f] || {}).desc || ''})`).join('; ').slice(0, 500)}. Honor these.` : '')
    + ((s.features && s.features.length) ? ` Class features: ${s.features.join('; ').slice(0, 500)}. Honor these in play.` : '');
}
// What's in the pack, for the GM's context (carried separately from the sheet
// so the slot inventory is the single source of truth).
function _invText(cid) {
  const inv = _loadInv(cid);
  if (!inv.items.length) return '';
  const list = inv.items.map(it => it.qty > 1 ? `${it.name} ×${it.qty}` : it.name).join(', ');
  let t = `The player's pack holds: ${list}.`;
  const eq = inv.equipped || {};
  const eqItem = (k) => { const id = eq[k]; return id ? (inv.items.find(x => x.id === id) || null) : null; };
  const wpn = eqItem('weapon'), arm = eqItem('armor'), tr = eqItem('trinket');
  const worn = [];
  if (wpn) worn.push(`wielding ${wpn.name}${wpn.dmg ? ` (${wpn.dmg} damage${wpn.atk ? `, +${wpn.atk} to hit` : ''})` : ''}`);
  if (arm) worn.push(`wearing ${arm.name}`);
  if (tr) worn.push(`bearing ${tr.name}`);
  if (worn.length) t += ` They are ${worn.join(', ')}. Effective AC ${_effAC(cid)}.`;
  if (_invWeight(inv) > _carryCap(cid)) t += ` They are over-encumbered — describe them as slowed and tiring under the weight.`;
  t += ` Only let them use items they actually carry; when they loot or are given something, name it clearly so it can be added.`;
  return t;
}

function _rollDie(sides) {
  if (_chat.streaming || !_chat.char) return;
  const s = _loadSheet(_chat.char.id);
  const stat = ($('dice-mod') && $('dice-mod').value) || '';
  const roll = 1 + Math.floor(Math.random() * sides);
  const mod = (stat && s.abilities[stat] != null) ? _mod(s.abilities[stat]) : null;
  const rp = $('studio-roll-prompt');
  const pending = !!(rp && !rp.hidden);   // the GM just called for a roll
  const send = () => {
    const text = mod != null
      ? `🎲 *rolls 1d${sides} for ${stat}* → ${roll} ${mod >= 0 ? '+' : ''}${mod} = **${roll + mod}**`
      : `🎲 *rolls 1d${sides}* → **${roll}**`;
    _appendBubble('me', text);
    _scrollChat();
    // Only spend a GM turn when the roll means something — a called-for check or
    // a chosen ability modifier. A bare, contextless tap on the tray just shows
    // the number so a stray click doesn't cost a whole (slow) turn.
    if (pending || mod != null) {
      _streamAssistant(text + (mod == null ? ' [Resolving the check you called for.]' : ''));
    } else {
      _toast("🎲 Roll noted — tell the GM what it's for to put it in play.");
    }
  };
  _animateDie(sides, roll, mod, stat, send);
}

// ── Dice skins: the set you roll with, everywhere dice appear ────────────────
const DICE_SKINS = [
  ['gold', 'Gilded'], ['ember', 'Emberglass'], ['frost', 'Frostbound'],
  ['verdant', 'Verdant'], ['void', 'Voidstone'], ['rose', 'Rosequartz'],
];
function _applyDiceSkin() {
  const m = $('studio-modal'); if (!m) return;
  let s = ''; try { s = localStorage.getItem('studio-dice-skin') || ''; } catch {}
  if (s && s !== 'gold') m.dataset.dice = s; else delete m.dataset.dice;
}
function openDiceSkins() {
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-dice-skins');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-dice-skins'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const cur = (() => { try { return localStorage.getItem('studio-dice-skin') || 'gold'; } catch { return 'gold'; } })();
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Dice skins">
    <div class="chronicle-bar"><h2>🎲 Your dice</h2><button class="studio-close" id="ds-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Pick the set you roll with — it reskins the tray and the tumbling die. Yours alone; every player at a table keeps their own.</p>
      <div class="dice-skin-grid">${DICE_SKINS.map(([k, label]) =>
        `<button type="button" class="dice-skin ds-${k}${k === cur ? ' on' : ''}" data-skin="${k}"><span class="ds-die">20</span><span class="ds-name">${label}</span></button>`).join('')}</div>
    </div></div>`;
  ov.style.display = 'flex';
  $('ds-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.querySelectorAll('[data-skin]').forEach(b => b.addEventListener('click', () => {
    try { localStorage.setItem('studio-dice-skin', b.dataset.skin); } catch {}
    _applyDiceSkin(); _sfx('dice'); openDiceSkins();
  }));
}

// Tumbling die overlay that cycles faces then lands on the result.
function _animateDie(sides, roll, mod, stat, done) {
  const modal = $('studio-modal');
  if (!modal) { done(); return; }
  let ov = $('studio-dice-roll');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-dice-roll'; ov.className = 'dice-overlay'; ov.setAttribute('aria-hidden', 'true'); modal.appendChild(ov); }
  const cap = mod != null ? `d${sides} &middot; ${stat} ${mod >= 0 ? '+' : ''}${mod}` : `d${sides}`;
  ov.innerHTML = `<div class="die3d wd-${_esc((_chat.char && _chat.char.world_id) || 'arcane')}"><span class="die-num">?</span></div><div class="die-cap">${cap}</div>`;
  ov.classList.add('show');
  const numEl = ov.querySelector('.die-num');
  const die = ov.querySelector('.die3d');
  const reduced = (typeof matchMedia === 'function') && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const land = () => {
    numEl.textContent = roll;
    die.classList.remove('tumbling'); die.classList.add('landed');
    if (roll === sides) { die.classList.add('crit'); if (sides === 20) _fxCrit(); }   // nat-20 gets the starburst
    if (roll === 1) die.classList.add('fumble');
    setTimeout(() => { ov.classList.remove('show'); done(); }, 780);
  };
  if (reduced) { land(); return; }
  _sfx('dice');
  die.classList.add('tumbling');
  const iv = setInterval(() => { numEl.textContent = 1 + Math.floor(Math.random() * sides); }, 60);
  setTimeout(() => { clearInterval(iv); land(); }, 850);
}

// ── Auto-dice: read the GM's called check and offer the exact roll ──────────
const _AB_FULL = { strength: 'STR', dexterity: 'DEX', constitution: 'CON', intelligence: 'INT', wisdom: 'WIS', charisma: 'CHA', str: 'STR', dex: 'DEX', con: 'CON', int: 'INT', wis: 'WIS', cha: 'CHA' };
const _AB_NAME = { STR: 'Strength', DEX: 'Dexterity', CON: 'Constitution', INT: 'Intelligence', WIS: 'Wisdom', CHA: 'Charisma' };
const _SKILL2AB = {
  athletics: 'STR', acrobatics: 'DEX', 'sleight of hand': 'DEX', stealth: 'DEX',
  arcana: 'INT', history: 'INT', investigation: 'INT', nature: 'INT', religion: 'INT',
  'animal handling': 'WIS', insight: 'WIS', medicine: 'WIS', perception: 'WIS', survival: 'WIS',
  deception: 'CHA', intimidation: 'CHA', performance: 'CHA', persuasion: 'CHA',
};
function _findDC(text) { const d = /\bDC\s*(\d+)/i.exec(text || ''); return d ? parseInt(d[1], 10) : null; }
function _findAC(text) { const m = /\bAC\s*(\d+)/i.exec(text || ''); return m ? parseInt(m[1], 10) : null; }
function _profBonus(s) { return 2 + Math.floor((((s && s.level) || 1) - 1) / 4); }
// Is the hero proficient in this check (a trained skill or a save)?
function _isProficient(s, check) {
  if (!check) return false;
  if (check.skill && /sav/i.test(check.skill)) return (s.profSaves || []).includes(check.ability);
  if (check.skill) { const k = check.skill.toLowerCase(); if (_SKILL2AB[k]) return (s.profSkills || []).includes(k); }
  return false;
}
// Total modifier for a (non-attack) d20 check: ability mod + proficiency when trained.
function _checkMod(s, check) {
  let mod = (check.ability && s.abilities[check.ability] != null) ? _mod(s.abilities[check.ability]) : 0;
  if (_isProficient(s, check)) mod += _profBonus(s);
  return mod;
}
function _attackMod(s, cid) {
  const str = _mod((s.abilities && s.abilities.STR) || 10);
  const dex = _mod((s.abilities && s.abilities.DEX) || 10);
  let m = Math.max(str, dex) + _profBonus(s);
  if (cid) { const w = _equippedItem(_loadInv(cid), 'weapon'); if (w && w.atk) m += w.atk; }
  return m;
}
function _advMode(text) { return /disadvantage/i.test(text || '') ? 'dis' : (/\badvantage\b/i.test(text || '') ? 'adv' : ''); }
// Roll a d20, taking the better/worse of two when at advantage/disadvantage.
function _rollD20(mode) {
  const a = 1 + Math.floor(Math.random() * 20);
  if (mode === 'adv' || mode === 'dis') { const b = 1 + Math.floor(Math.random() * 20); return { roll: mode === 'adv' ? Math.max(a, b) : Math.min(a, b), rolls: [a, b], mode }; }
  return { roll: a, rolls: [a], mode: '' };
}
function _d20Text(r) { return r.mode ? `d20 ${r.mode === 'adv' ? 'adv' : 'dis'} (${r.rolls.join('/')}→${r.roll})` : `d20 ${r.roll}`; }
// Conditions that bend the dice (5e-flavored). adv+dis on the same roll cancel.
const _CONDITION_FX = {
  poisoned: { attack: 'dis', check: 'dis' },
  frightened: { attack: 'dis', check: 'dis' },
  prone: { attack: 'dis' },
  restrained: { attack: 'dis', save: 'dis' },
  grappled: {},
  blinded: { attack: 'dis' },
  deafened: {},
  stunned: { save: 'dis' },
  paralyzed: { save: 'dis' },
  unconscious: { save: 'dis' },
  petrified: { save: 'dis' },
  incapacitated: {},
  exhausted: { check: 'dis' }, exhaustion: { check: 'dis' },
  charmed: { check: 'dis' },
  blessed: { attack: 'adv', save: 'adv' },
  inspired: { attack: 'adv', check: 'adv', save: 'adv' },
  invisible: { attack: 'adv' }, hidden: { attack: 'adv' },
  guided: { attack: 'adv', check: 'adv' },
};
// What each standard condition means, for the GM to enforce in the fiction.
// The six-step exhaustion track (5e): effects are cumulative going down.
const _EXHAUSTION = ['rested',
  'disadvantage on ability checks',
  'speed halved',
  'disadvantage on attacks & saves',
  'hit point maximum halved',
  'speed drops to 0',
  'death'];

const _CONDITION_DESC = {
  poisoned: 'disadvantage on attacks and ability checks',
  frightened: "disadvantage on attacks and checks while the source is in sight; can't willingly move closer to it",
  prone: 'disadvantage on attacks; melee attackers have advantage; must spend movement to stand',
  restrained: "speed 0; disadvantage on attacks and DEX saves; attackers have advantage",
  grappled: 'speed 0; ends if the grappler is incapacitated or you break free',
  blinded: "can't see; auto-fails sight checks; disadvantage on attacks; attackers have advantage",
  deafened: "can't hear; auto-fails hearing checks",
  stunned: "incapacitated — can't take actions; auto-fails STR and DEX saves; attackers have advantage",
  paralyzed: "incapacitated and can't move; auto-fails STR/DEX saves; attackers have advantage; melee hits are critical",
  unconscious: "incapacitated, drops what it holds, falls prone; auto-fails STR/DEX saves; melee hits are critical",
  petrified: "turned to stone — incapacitated, resistance to all damage, immune to poison/disease",
  incapacitated: "can't take actions or reactions",
  charmed: "can't attack the charmer; the charmer has advantage on social checks with you",
};
function _conditionEffectsText(s) {
  const seen = new Set(); const parts = [];
  (s.conditions || []).forEach(c => {
    const n = ((typeof c === 'string' ? c : (c && c.name)) || '').toLowerCase().trim();
    const key = Object.keys(_CONDITION_DESC).find(k => n === k || n.startsWith(k));
    if (key && !seen.has(key)) { seen.add(key); parts.push(`${key} (${_CONDITION_DESC[key]})`); }
  });
  return parts.length ? `Enforce these conditions on the player: ${parts.join('; ')}.` : '';
}
function _kindOf(check) { if (check.type === 'attack') return 'attack'; if (check.skill && /sav/i.test(check.skill)) return 'save'; return 'check'; }
function _condName(c) { return typeof c === 'string' ? c : ((c && c.name) || ''); }
// Conditions affecting the hero right now: those on the sheet PLUS those on the
// player's combat token (so a poison applied in the tracker actually bites).
function _activeConditions(cid) {
  const names = [], seen = new Set();
  const add = (c) => { const n = _condName(c).toLowerCase().trim(); if (n && !seen.has(n)) { seen.add(n); names.push(n); } };
  (_loadSheet(cid).conditions || []).forEach(add);
  const cc = _loadCombat(cid);
  if (cc.active) { const pc = (cc.combatants || []).find(x => x.id === 'pc'); (pc && pc.conditions || []).forEach(add); }
  return names;
}
function _conditionMode(cid, kind) {
  let adv = false, dis = false, why = [];
  _activeConditions(cid).forEach(n => {
    const fx = _CONDITION_FX[n];
    if (fx && fx[kind]) { if (fx[kind] === 'adv') { adv = true; why.push(n); } if (fx[kind] === 'dis') { dis = true; why.push(n); } }
  });
  if (adv && dis) return { mode: '', why: '' };          // they cancel
  return { mode: adv ? 'adv' : (dis ? 'dis' : ''), why: why.join(', ') };
}

// ── Inspiration (the DM's reward token) ──────────────────────────────────────
// Awarded by the GM for clever, brave, or in-character play; spent to gain
// advantage on one roll of your choice. In 5e you either have it or you don't.
let _inspArmed = false;
function _grantInspiration(cid) { const s = _loadSheet(cid); if (s.inspiration) return false; s.inspiration = true; _saveSheet(cid, s); _reflectInspiration(cid); return true; }
function _armInspiration(cid) {
  const s = _loadSheet(cid); if (!s.inspiration) return;
  _inspArmed = !_inspArmed;
  _reflectInspiration(cid);
  _toast(_inspArmed ? '✨ Inspiration armed — your next roll gains advantage.' : 'Inspiration held.');
}
// Fold inspiration into a roll's advantage mode, consuming the token if armed.
function _applyInspiration(cid, curMode) {
  if (!_inspArmed) return curMode;
  if (curMode === 'adv') { _toast('Already at advantage — Inspiration held for later.'); return 'adv'; }   // don't burn it for nothing
  _inspArmed = false;
  const s = _loadSheet(cid); s.inspiration = false; _saveSheet(cid, s);
  _reflectInspiration(cid); _fxSpell('Inspiration', 0);
  return curMode === 'dis' ? '' : 'adv';   // cancels a disadvantage, else grants advantage
}
function _reflectInspiration(cid) {
  const el = $('studio-inspiration'); if (!el) return;
  const has = _loadSheet(cid || (_chat.char && _chat.char.id)).inspiration;
  el.style.display = has ? '' : 'none';
  el.classList.toggle('armed', has && _inspArmed);
  el.innerHTML = `<span aria-hidden="true">✨</span>${_inspArmed ? 'Inspiration armed' : 'Inspiration'}`;
  el.title = has ? (_inspArmed ? 'Armed — your next roll gains advantage. Click to hold.' : 'You hold Inspiration — click to spend it for advantage on your next roll.') : '';
}
function _detectCheck(text) {
  if (!text) return null;
  const adv = _advMode(text);
  if (/\broll(?:ing)?\s+(?:for\s+)?initiative\b/i.test(text)) return { ability: 'DEX', skill: 'Initiative', dc: _findDC(text), adv };
  // Attack roll — "make an attack roll", "roll to hit" (d20 + attack bonus vs AC)
  if (/\b(attack roll|roll to hit|make an attack|roll an attack)\b/i.test(text)) return { type: 'attack', ac: _findAC(text), adv };
  // Damage / healing — a dice expression like "2d6 + 3" (only after combat-y framing)
  const dm = /\b(\d{1,2})d(\d{1,3})\b\s*([+-]\s*\d+)?/i.exec(text);
  if (dm && /\b(damage|dmg|healing|heal|hit points|hp)\b/i.test(text)) {
    return { type: 'damage', n: parseInt(dm[1], 10), sides: parseInt(dm[2], 10), bonus: dm[3] ? parseInt(dm[3].replace(/\s+/g, ''), 10) : 0, heal: /\b(healing|heal)\b/i.test(text) };
  }
  // "Dexterity (Sleight of Hand) check" / "Wisdom saving throw" / "DEX check"
  let m = /\b(strength|dexterity|constitution|intelligence|wisdom|charisma|str|dex|con|int|wis|cha)\b\s*(?:\(([^)]{2,40})\))?\s*(check|saving throw|save)\b/i.exec(text);
  if (m) {
    const ability = _AB_FULL[m[1].toLowerCase()];
    const skill = (m[2] || '').trim() || (/sav/i.test(m[3]) ? 'saving throw' : '');
    return { ability, skill, dc: _findDC(text), adv };
  }
  // bare skill name + check (e.g. "make a Perception check")
  m = /\b(athletics|acrobatics|sleight of hand|stealth|arcana|history|investigation|nature|religion|animal handling|insight|medicine|perception|survival|deception|intimidation|performance|persuasion)\b\s*(?:check)?/i.exec(text);
  if (m && /check|roll/i.test(text)) {
    const skill = m[1].toLowerCase();
    return { ability: _SKILL2AB[skill], skill: m[1], dc: _findDC(text), adv };
  }
  return null;
}
function _checkLabel(c) {
  const ab = _AB_NAME[c.ability] || c.ability;
  if (!c.skill) return `${ab} check`;
  if (/sav/i.test(c.skill)) return `${ab} saving throw`;
  if (c.skill === 'Initiative') return 'Initiative (Dexterity)';
  return `${ab} (${c.skill})`;
}
function _renderRollPrompt(check) {
  const bar = $('studio-roll-prompt');
  if (!bar) return;
  if (!check || (!check.ability && !check.type)) { bar.hidden = true; bar.innerHTML = ''; return; }
  const cid = _chat.char.id; const s = _loadSheet(cid);
  const cond = check.type === 'damage' ? { mode: '', why: '' } : _conditionMode(cid, _kindOf(check));
  const mode = check._mode != null ? check._mode : (check.adv || cond.mode || '');
  let promptText, btnLabel;
  if (check.type === 'attack') {
    const am = _attackMod(s, cid);
    promptText = `The Game Master calls for an <strong>attack roll</strong>${check.ac != null ? ` &middot; vs AC ${check.ac}` : ''}`;
    btnLabel = `⚔ Roll to hit d20 ${am >= 0 ? '+' : ''}${am}`;
  } else if (check.type === 'damage') {
    const expr = `${check.n}d${check.sides}${check.bonus ? (check.bonus > 0 ? ' + ' + check.bonus : ' − ' + Math.abs(check.bonus)) : ''}`;
    promptText = `The Game Master calls for <strong>${check.heal ? 'a healing roll' : 'a damage roll'}</strong> &middot; ${_esc(expr)}`;
    btnLabel = `🎲 Roll ${expr}`;
  } else {
    const mod = _checkMod(s, check); const prof = _isProficient(s, check);
    const _lbl = _checkLabel(check);
    const _art = /^[aeiou]/i.test(_lbl) ? 'an' : 'a';
    promptText = `The Game Master calls for ${_art} <strong>${_esc(_lbl)}</strong>${check.dc != null ? ` &middot; DC ${check.dc}` : ''}`;
    btnLabel = `🎲 Roll ${_esc(check.ability)} ${mod >= 0 ? '+' : ''}${mod}${prof ? ' • prof' : ''}`;
  }
  // d20-based rolls can be taken at advantage/disadvantage; damage can't.
  const advCtl = check.type === 'damage' ? '' :
    `<span class="rp-adv">${[['', 'Normal'], ['adv', 'Adv'], ['dis', 'Dis']].map(([m, l]) => `<button type="button" class="rp-adv-btn${mode === m ? ' on' : ''}" data-mode="${m}">${l}</button>`).join('')}</span>`;
  const condHint = (check._mode == null && cond.mode && cond.why) ? `<span class="rp-cond">${_esc(cond.why)} → ${cond.mode === 'adv' ? 'advantage' : 'disadvantage'}</span>` : '';
  bar.innerHTML = `<span class="rp-prompt-text">${promptText}${condHint}</span>${advCtl}`
    + `<button class="st-btn primary small" id="rp-roll-btn" type="button">${btnLabel}</button>`;
  bar.hidden = false;
  bar.querySelectorAll('.rp-adv-btn').forEach(b => b.addEventListener('click', () => { check._mode = b.dataset.mode; _renderRollPrompt(check); }));
  $('rp-roll-btn').addEventListener('click', () => { bar.hidden = true; _rollCheck(check); });
}
function _rollCheck(check) {
  if (_chat.streaming) return;
  const cid = _chat.char.id; const s = _loadSheet(cid);
  const cond = check.type === 'damage' ? { mode: '' } : _conditionMode(cid, _kindOf(check));
  let mode = check._mode != null ? check._mode : (check.adv || cond.mode || '');
  if (check.type !== 'damage') mode = _applyInspiration(cid, mode);   // spend Inspiration if armed
  if (check.type === 'attack') {
    const am = _attackMod(s, cid);
    const r = _rollD20(mode); const roll = r.roll; const total = roll + am;
    let verdict;
    if (roll === 20) verdict = ' — **critical hit!** 🎯';
    else if (roll === 1) verdict = ' — **critical miss!**';
    else if (check.ac != null) verdict = total >= check.ac ? ` — **hit!** (AC ${check.ac})` : ` — **miss** (AC ${check.ac})`;
    else verdict = '';
    const text = `⚔ *attack roll* → ${_d20Text(r)} ${am >= 0 ? '+' : ''}${am} = **${total}**${verdict}`;
    _animateDie(20, roll, am, 'hit', () => { _appendBubble('me', text); _scrollChat(); _streamAssistant(text); });
    return;
  }
  if (check.type === 'damage') {
    const rolls = Array.from({ length: check.n }, () => 1 + Math.floor(Math.random() * check.sides));
    const sum = rolls.reduce((a, b) => a + b, 0) + check.bonus;
    const total = Math.max(0, sum);
    const expr = `${check.n}d${check.sides} (${rolls.join(', ')})${check.bonus ? (check.bonus > 0 ? ' + ' + check.bonus : ' − ' + Math.abs(check.bonus)) : ''}`;
    const text = `🎲 *${check.heal ? 'healing' : 'damage'}* → ${expr} = **${total}**${check.heal ? ' healed' : ' damage'}`;
    _animateDie(check.sides, rolls[0], null, null, () => { _appendBubble('me', text); _scrollChat(); _streamAssistant(text); });
    return;
  }
  const mod = _checkMod(s, check); const prof = _isProficient(s, check);
  const r = _rollD20(mode); const roll = r.roll; const total = roll + mod;
  const verdict = check.dc != null ? (total >= check.dc ? ` — **success!** (DC ${check.dc})` : ` — **failure** (DC ${check.dc})`) : '';
  const text = `🎲 *${_checkLabel(check)}${prof ? ' (proficient)' : ''}* → ${_d20Text(r)} ${mod >= 0 ? '+' : ''}${mod} = **${total}**${verdict}`;
  _animateDie(20, roll, mod, check.ability, () => { _appendBubble('me', text); _scrollChat(); _streamAssistant(text); });
}

// Mistake recovery: the sheet as it stood when the panel opened. Undo restores it.
const _sheetSnap = {};
function toggleSheet() {
  const panel = $('studio-sheet-panel');
  if (panel && panel.classList.contains('open')) { panel.classList.remove('open'); return; }
  if (_chat.char) { try { _sheetSnap[_chat.char.id] = JSON.stringify(_loadSheet(_chat.char.id)); } catch {} }
  renderSheetPanel();
  _panelEnter('studio-sheet-panel', 'fx-sheet-in');   // parchment unfurl
}

// A readable character-sheet file (hero, stats, gear) you can print or share.
function _exportSheet(cid) {
  const s = _loadSheet(cid); const inv = _loadInv(cid);
  const mods = ABILITIES.map(a => `${a} ${s.abilities[a] || 10} (${_modStr(s.abilities[a] || 10)})`).join('  ·  ');
  const equipped = Object.entries(inv.equipped || {}).map(([k, id]) => { const it = inv.items.find(x => x.id === id); return it ? `${k}: ${it.name}` : ''; }).filter(Boolean);
  const lines = [
    `${s.name || 'Unnamed hero'} — level ${s.level || 1} ${s.race ? s.race + ' ' : ''}${_classesOf(s).length > 1 ? _classesOf(s).map(c => `${c.cls} ${c.levels}${c.subclass ? ` (${c.subclass})` : ''}`).join(' / ') : (s.clsSkin ? `${s.clsSkin} (${s.cls})` : (s.cls || 'Adventurer'))}`,
    s.background ? `Background: ${s.background}` : '',
    `HP ${s.hp}/${s.hpMax} · AC ${_effAC(cid)} · speed ${s.speed || 30} ft · passive Perception ${_passivePerception(s)}${s.exhaustion ? ` · exhaustion ${s.exhaustion}` : ''}`,
    `XP ${s.xp || 0} · purse ${s.gold || 0} ${_currency(cid)}`,
    '',
    `Abilities:  ${mods}`,
    (s.profSaves || []).length ? `Saving throws: ${s.profSaves.join(', ')}` : '',
    (s.profSkills || []).length ? `Skills: ${s.profSkills.map(_titleCase).join(', ')}` : '',
    (s.features || []).length ? `Features: ${s.features.join(', ')}` : '',
    (s.feats || []).length ? `Feats: ${s.feats.join(', ')}` : '',
    (s.spells || []).length ? `Spells: ${s.spells.map(x => x.name || x).join(', ')}` : '',
    s.conditions && s.conditions.length ? `Conditions: ${s.conditions.map(_condName).join(', ')}` : '',
    '',
    equipped.length ? `Equipped:\n  ${equipped.join('\n  ')}` : '',
    inv.items.length ? `Pack:\n  ${inv.items.map(it => `${it.name}${it.qty > 1 ? ` ×${it.qty}` : ''}`).join('\n  ')}` : 'Pack: empty',
    '',
    `— exported from Mythforge, ${new Date().toLocaleString()}`,
  ].filter(x => x !== '');
  const blob = new Blob([lines.join('\n')], { type: 'text/plain' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `${_slugify(s.name || 'hero')}-sheet.txt`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

function renderSheetPanel() {
  const modal = $('studio-modal');
  if (!modal || !_chat.char) return;
  const cid = _chat.char.id;
  const s = _loadSheet(cid);
  let panel = $('studio-sheet-panel');
  if (!panel) { panel = document.createElement('div'); panel.id = 'studio-sheet-panel'; panel.className = 'sheet-panel'; modal.appendChild(panel); }
  const abilityCells = ABILITIES.map(a => `
    <div class="ab-cell">
      <label>${a}</label>
      <input type="number" class="ab-input" data-ab="${a}" value="${_esc(s.abilities[a])}" min="1" max="30">
      <span class="ab-mod" data-abmod="${a}">${_modStr(s.abilities[a])}</span>
    </div>`).join('');
  const condRows = s.conditions.length
    ? s.conditions.map((c, i) => { const nm = _condName(c); const rd = (c && typeof c === 'object' && c.rounds != null) ? ` <em class="cond-rd">${c.rounds}</em>` : ''; return `<span class="cond-tag">${_esc(nm)}${rd}<button class="rm" data-rm-cond="${i}" type="button" aria-label="Remove">×</button></span>`; }).join('')
    : '<span class="empty">None</span>';
  panel.innerHTML = `
    <div class="sheet-head"><h2>Adventurer's Sheet</h2><button class="st-btn small ghost" id="sheet-undo" type="button" title="Restore the sheet as it was when this panel opened">↺</button><button class="st-btn small ghost" id="sheet-export" type="button" title="Download this sheet as a text file">⤓</button><button class="st-btn small gm-toggle${_gmMode() ? ' on' : ''}" id="sheet-gm" type="button" title="${_gmMode() ? 'Stats unlocked — click to lock' : 'Stats are game-managed — click for GM mode to edit'}">${_gmMode() ? '🔓 GM' : '🔒'}</button><button class="studio-close" id="sheet-close" type="button" aria-label="Close">✕</button></div>
    <div class="sheet-body">
      <div class="sheet-grid2">
        <label class="sf">Name<input type="text" id="sf-name" value="${_esc(s.name)}" placeholder="Your hero"></label>
        <label class="sf">Class<input type="text" id="sf-cls" value="${_esc(s.cls)}"></label>
      </div>
      ${s.clsSkin ? `<p class="gm-hint" style="margin:0">✦ Known in this world as a <strong>${_esc(s.clsSkin)}</strong>${s.slotName ? ` · spell slots are ${_esc(s.slotName)}` : ''}</p>` : ''}
      ${_classesOf(s).length > 1 ? `<p class="gm-hint" style="margin:0">⚔ Multiclass: ${_classesOf(s).map(c => `<strong>${_esc(c.cls)} ${c.levels}</strong>${c.subclass ? ` <em>(${_esc(c.subclass)})</em>` : ''}`).join(' · ')}</p>`
        : (s.subclass ? `<p class="gm-hint" style="margin:0" title="${_esc(_subclassLine(s))}">🛤 Path: <strong>${_esc(s.subclass)}</strong></p>` : '')}
      <div class="class-row"><label class="sf" style="flex:1">Apply a class template<select id="sf-class-tpl" class="studio-select"><option value="">— pick a class —</option>${Object.keys(CLASS_PRESETS).map(c => `<option value="${c}"${s.cls === c ? ' selected' : ''}>${c}${CLASS_PRESETS[c].caster ? ' ✦' : ''}</option>`).join('')}</select></label><span class="hitdie-note">d${s.hitDie || 8} hit die</span></div>
      <div class="sheet-grid4">
        <label class="sf">Level<input type="number" id="sf-level" value="${_esc(s.level)}" min="1" max="20"></label>
        <label class="sf">HP<input type="number" id="sf-hp" value="${_esc(s.hp)}"></label>
        <label class="sf">Max<input type="number" id="sf-hpmax" value="${_esc(s.hpMax)}"></label>
        <label class="sf">AC<input type="number" id="sf-ac" value="${_esc(_effAC(cid))}" title="10 + DEX (+ Unarmored Defense / armor). Edit in GM mode to override."></label>
      </div>
      ${(() => { const lv = s.level || 1, span = _xpForLevel(lv + 1) - _xpForLevel(lv), into = Math.max(0, Math.min(span, (s.xp || 0) - _xpForLevel(lv))); return `<div class="xp-card"><div class="xp-top"><span class="xp-level">Level ${lv}</span><span class="xp-num">${into} / ${span} XP</span></div>
        <div class="xp-bar"><div class="xp-fill" style="width:${span ? Math.round((into / span) * 100) : 0}%"></div></div></div>`; })()}
      <div class="rest-row"><button class="st-btn small" id="sf-short-rest" type="button" title="Spend a Hit Die (d${s.hitDie || 8}+CON) to heal">🌙 Short rest <em class="prof-bonus">${Math.max(0, (s.level || 1) - (s.hitDiceUsed || 0))}/${s.level || 1} HD</em></button><button class="st-btn small" id="sf-long-rest" type="button">⛺ Long rest</button><span class="rest-ac" title="Base AC plus equipped armor">Effective AC <strong>${_effAC(cid)}</strong></span></div>
      <div class="rest-row exh-row" title="Exhaustion — forced marches and sleepless nights add levels; a long rest removes one">
        <span class="exh-label">😮‍💨 Exhaustion</span>
        <button class="st-btn small ghost" id="sf-exh-dn" type="button" aria-label="Reduce exhaustion">−</button>
        <strong class="exh-num">${s.exhaustion || 0}</strong>
        <button class="st-btn small ghost" id="sf-exh-up" type="button" aria-label="Add exhaustion">+</button>
        <span class="gm-hint" style="margin:0">${_esc(_EXHAUSTION[Math.min(6, s.exhaustion || 0)] || 'rested')}</span>
      </div>
      <div class="stat-strip">${s.race ? `<span title="Heritage">🧬 ${_esc(s.race)}</span>` : ''}<span title="Walking speed">👣 ${s.speed || 30} ft</span>${s.darkvision ? `<span title="Darkvision">🌙 ${s.darkvision} ft</span>` : ''}<span title="Passive Perception — what you notice without looking">👁 PP ${_passivePerception(s)}</span></div>
      <div class="ab-grid">${abilityCells}</div>
      <div class="sheet-section"><h3>Inventory</h3>
        <button class="st-btn pack-launch" id="sf-open-pack" type="button">🎒 Open pack <span class="pack-count">${_loadInv(cid).items.length} item${_loadInv(cid).items.length === 1 ? '' : 's'}</span></button>
        <div class="purse-row"><span class="purse-ico" aria-hidden="true">🪙</span><span class="purse-label">${_titleCase(_currency(cid))}</span><button class="st-btn small ghost" id="sf-gold-dn" type="button" title="−10">−</button><input type="number" id="sf-gold" class="purse-input" value="${s.gold || 0}" min="0" aria-label="Purse"><button class="st-btn small ghost" id="sf-gold-up" type="button" title="+10">+</button></div></div>
      <div class="sheet-section"><h3>Conditions</h3><div class="cond-wrap">${condRows}</div>
        <div class="add-row"><input type="text" id="cond-add" placeholder="Add a condition…"><button id="cond-add-btn" class="st-btn small" type="button">Add</button></div></div>
      <div class="sheet-section"><h3>Party</h3>
        ${(s.companions || []).length ? `<ul class="feat-list">${s.companions.map((c, ci) => `<li class="feat-row feat-active">${c.guest ? '🎭' : '⚔'} <strong>${_esc(c.name)}</strong>&nbsp;· ${c.cls ? `lv ${c.level || 1} ${_esc(c.cls)} · ` : ''}${c.hp}/${c.hpMax} HP · AC ${c.ac || 12}<span class="feat-ctl"><button class="st-btn small ghost" data-rmcomp="${ci}" type="button">Dismiss</button></span></li>`).join('')}</ul>` : '<p class="gm-hint">No one travels with you yet — recruit companions from the Cast, or seat a second player.</p>'}
        <button class="st-btn small" id="sf-guest" type="button">🎭 Add a guest hero (hot-seat)</button></div>
      ${(s.feats && s.feats.length) ? `<div class="sheet-section"><h3>Feats</h3><ul class="feat-list">${s.feats.map(f => `<li class="feat-row" title="${_esc((FEATS[f] || {}).desc || '')}">🏅 ${_esc(f)}</li>`).join('')}</ul></div>` : ''}
      ${(s.features && s.features.length) ? `<div class="sheet-section"><h3>Class features</h3><ul class="feat-list">${s.features.map((f, fi) => {
        const fa = _featAction(f);
        if (!fa) return `<li class="feat-row">✨ ${_esc(f)}</li>`;
        const used = (s.featUses || {})[fa.key] || 0; const left = Math.max(0, fa.uses - used);
        return `<li class="feat-row feat-active">✨ ${_esc(f)} <span class="feat-ctl"><em class="prof-bonus">${left}/${fa.uses} per ${fa.rest} rest</em><button class="st-btn small${left ? ' primary' : ''}" data-usefeat="${fi}" type="button" ${left ? '' : 'disabled'}>Use</button></span></li>`;
      }).join('')}</ul></div>` : ''}
      <div class="sheet-section"><h3>Spells &amp; slots${_spellSaveDC(s) != null ? ` <span class="prof-bonus">save DC ${_spellSaveDC(s)} · atk +${_spellAttack(s)}</span>` : ''}</h3>
        ${s.concentration ? `<div class="conc-banner">🌀 Concentrating on <strong>${_esc(s.concentration.name)}</strong><button class="st-btn small ghost" id="sf-drop-conc" type="button">Drop</button></div>` : ''}
        <div class="slots-grid">${[1, 2, 3, 4, 5].map(l => { const sl = (s.slots && s.slots[l]) || { max: 0, used: 0 }; const avail = Math.max(0, (sl.max || 0) - (sl.used || 0)); const pips = (sl.max || 0) > 0 ? Array.from({ length: sl.max }, (_, i) => i < avail ? '●' : '○').join('') : '—'; return `<div class="slot-cell"><span class="slot-lvl">L${l}</span><span class="slot-pips">${pips}</span><span class="slot-ctl"><button class="slot-step" data-slot="${l}" data-d="-1" type="button">−</button><button class="slot-step" data-slot="${l}" data-d="1" type="button">+</button></span></div>`; }).join('')}</div>
        <ul class="spell-list">${(s.spells || []).length ? s.spells.map((sp, i) => `<li class="spell-row"><button class="st-btn small" data-cast="${i}" type="button">Cast</button><span class="spell-name">${_esc(sp.name)}</span><span class="spell-lvl">${sp.level ? 'L' + sp.level : 'cantrip'}</span><button class="rm" data-rmspell="${i}" type="button" aria-label="Remove">×</button></li>`).join('') : '<li class="spell-row empty">No spells known.</li>'}</ul>
        ${_gmMode()
          ? `<div class="add-row"><input type="text" id="spell-add" placeholder="Add a spell (GM)…"><input type="number" id="spell-lvl" value="1" min="0" max="9" title="Spell level (0 = cantrip)" style="width:54px"><button id="spell-add-btn" class="st-btn small" type="button">Add</button></div>`
          : `<div class="add-row">${_isDM(_chat.char) ? `<button id="spell-ask-btn" class="st-btn small ghost" type="button" title="Ask the GM to teach you a spell — they decide how">✦ Ask the GM to learn a spell…</button>` : ''}</div>`}</div>
      <div class="sheet-section"><h3>Proficiencies <span class="prof-bonus">+${_profBonus(s)} when trained</span></h3>
        <div class="prof-sub">Saving throws</div>
        <div class="prof-wrap">${ABILITIES.map(a => `<button class="prof-chip${(s.profSaves || []).includes(a) ? ' on' : ''}" data-prof-save="${a}" type="button">${a}</button>`).join('')}</div>
        <div class="prof-sub">Skills</div>
        <div class="prof-wrap">${Object.keys(_SKILL2AB).sort().map(k => `<button class="prof-chip${(s.profSkills || []).includes(k) ? ' on' : ''}" data-prof-skill="${k}" type="button">${_titleCase(k)} <em>${_SKILL2AB[k]}</em></button>`).join('')}</div></div>
      <div class="sheet-section"><h3>Notes</h3><textarea id="sf-notes" rows="3" placeholder="Anything to remember…">${_esc(s.notes)}</textarea></div>
    </div>`;
  panel.classList.add('open');
  $('sheet-close').addEventListener('click', () => panel.classList.remove('open'));
  const bind = (id, key, num) => { const el = $(id); if (el) el.addEventListener('input', () => { s[key] = num ? Number(el.value || 0) : el.value; _saveSheet(cid, s); }); };
  bind('sf-name', 'name'); bind('sf-cls', 'cls'); bind('sf-level', 'level', true);
  bind('sf-hp', 'hp', true); bind('sf-hpmax', 'hpMax', true); bind('sf-ac', 'acOverride', true); bind('sf-notes', 'notes');
  panel.querySelectorAll('.ab-input').forEach(inp => inp.addEventListener('input', () => {
    const a = inp.dataset.ab; s.abilities[a] = Number(inp.value || 10); _saveSheet(cid, s);
    const m = panel.querySelector(`[data-abmod="${a}"]`); if (m) m.textContent = _modStr(s.abilities[a]);
  }));
  const addCond = () => { const raw = ($('cond-add').value || '').trim(); if (!raw) return; const mm = /^(.*?)\s+(\d{1,2})$/.exec(raw); s.conditions.push(mm ? { name: mm[1].trim(), rounds: parseInt(mm[2], 10) } : raw); _saveSheet(cid, s); renderSheetPanel(); };
  $('sf-open-pack').addEventListener('click', () => { renderInventory(); });
  panel.querySelectorAll('[data-usefeat]').forEach(b => b.addEventListener('click', () => {
    const f = (s.features || [])[Number(b.dataset.usefeat)]; if (f) _useFeature(cid, f);
  }));
  panel.querySelectorAll('[data-rmcomp]').forEach(b => b.addEventListener('click', () => {
    const s2 = _loadSheet(cid); const c = (s2.companions || [])[Number(b.dataset.rmcomp)]; if (!c) return;
    _toggleCompanion(cid, { name: c.name, role: c.role });
    renderSheetPanel();
  }));
  $('sf-guest')?.addEventListener('click', () => _addGuestHero(cid));
  $('sf-drop-conc')?.addEventListener('click', () => { const ss = _loadSheet(cid); if (ss.concentration) { const n = ss.concentration.name; ss.concentration = null; _saveSheet(cid, ss); _appendBubble('me', `*You let your concentration on **${_esc(n)}** lapse.*`); _scrollChat(); renderSheetPanel(); } });
  $('sf-gold')?.addEventListener('change', () => { const s2 = _loadSheet(cid); s2.gold = Math.max(0, parseInt($('sf-gold').value, 10) || 0); _saveSheet(cid, s2); });
  $('sf-gold-dn')?.addEventListener('click', () => { _addGold(cid, -10); renderSheetPanel(); });
  $('sf-gold-up')?.addEventListener('click', () => { _addGold(cid, 10); renderSheetPanel(); });
  $('sf-class-tpl')?.addEventListener('change', (e) => { if (e.target.value) _applyClass(cid, e.target.value); });
  $('sf-short-rest').addEventListener('click', () => _shortRest(cid));
  $('sheet-export')?.addEventListener('click', () => _exportSheet(cid));
  $('sheet-undo')?.addEventListener('click', () => {
    const snap = _sheetSnap[cid];
    if (!snap) { _toast('Nothing to undo — the sheet is as it was.'); return; }
    try { _saveSheet(cid, JSON.parse(snap)); renderSheetPanel(); _toast('↺ Sheet restored to when you opened it.'); } catch {}
  });
  $('sf-long-rest').addEventListener('click', () => _longRest(cid));
  $('sf-exh-dn')?.addEventListener('click', () => { const s2 = _loadSheet(cid); s2.exhaustion = Math.max(0, (s2.exhaustion || 0) - 1); _saveSheet(cid, s2); renderSheetPanel(); });
  $('sf-exh-up')?.addEventListener('click', () => {
    const s2 = _loadSheet(cid); s2.exhaustion = Math.min(6, (s2.exhaustion || 0) + 1); _saveSheet(cid, s2); renderSheetPanel();
    if (s2.exhaustion >= 6) { _appendBubble('me', `💀 *Exhaustion level 6 — the body simply stops.*`); _scrollChat(); }
  });
  $('cond-add-btn').addEventListener('click', addCond);
  $('cond-add').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); addCond(); } });
  panel.querySelectorAll('[data-rm-cond]').forEach(b => b.addEventListener('click', () => { s.conditions.splice(Number(b.dataset.rmCond), 1); _saveSheet(cid, s); renderSheetPanel(); }));
  const addSpell = () => { const v = ($('spell-add').value || '').trim(); if (!v) return; const lvl = Math.max(0, Math.min(9, Number($('spell-lvl').value || 0))); s.spells = s.spells || []; s.spells.push({ name: v, level: lvl }); _saveSheet(cid, s); renderSheetPanel(); };
  $('spell-add-btn')?.addEventListener('click', addSpell);           // GM-mode free add only
  $('spell-add')?.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); addSpell(); } });
  $('spell-ask-btn')?.addEventListener('click', () => _askLearnSpell(cid));   // player: ask the GM to teach you
  panel.querySelectorAll('[data-cast]').forEach(b => b.addEventListener('click', () => _castSpell(cid, Number(b.dataset.cast))));
  panel.querySelectorAll('[data-rmspell]').forEach(b => b.addEventListener('click', () => { s.spells.splice(Number(b.dataset.rmspell), 1); _saveSheet(cid, s); renderSheetPanel(); }));
  panel.querySelectorAll('.slot-step').forEach(b => b.addEventListener('click', () => _setSlotMax(cid, Number(b.dataset.slot), Number(b.dataset.d))));
  panel.querySelectorAll('[data-prof-skill]').forEach(b => b.addEventListener('click', () => { const k = b.dataset.profSkill; s.profSkills = s.profSkills || []; const i = s.profSkills.indexOf(k); if (i >= 0) s.profSkills.splice(i, 1); else s.profSkills.push(k); _saveSheet(cid, s); renderSheetPanel(); }));
  panel.querySelectorAll('[data-prof-save]').forEach(b => b.addEventListener('click', () => { const a = b.dataset.profSave; s.profSaves = s.profSaves || []; const i = s.profSaves.indexOf(a); if (i >= 0) s.profSaves.splice(i, 1); else s.profSaves.push(a); _saveSheet(cid, s); renderSheetPanel(); }));
  $('sheet-gm').addEventListener('click', () => { _setGmMode(!_gmMode()); renderSheetPanel(); });
  // Locked by default: the game owns these calculated stats; GM mode frees them.
  if (!_gmMode()) {
    ['sf-cls', 'sf-class-tpl', 'sf-level', 'sf-hp', 'sf-hpmax', 'sf-ac'].forEach(id => { const el = $(id); if (el) el.disabled = true; });
    panel.querySelectorAll('.ab-input, .slot-step, .prof-chip').forEach(el => el.disabled = true);
  }
}

// ── Game Master tuning (saved per storyline) + scene control ────────────────
const GM_KEY = (cid) => `studio-gm-${cid}`;
const GM_KNOBS = [
  { key: 'humor', label: 'Humor', lo: 'Serious', hi: 'Comedic' },
  { key: 'spice', label: 'Romance & spice', lo: 'None', hi: 'Bold' },
  { key: 'grit', label: 'Grit & danger', lo: 'Gentle', hi: 'Brutal' },
  { key: 'pace', label: 'Pace', lo: 'Slow', hi: 'Fast' },
  { key: 'rules', label: 'Rules', lo: 'Loose', hi: 'Strict 5e' },
];
function _defaultGM() { return { humor: 40, spice: 0, grit: 50, pace: 55, rules: 50 }; }
function _loadGM(cid) { try { return { ..._defaultGM(), ...(JSON.parse(localStorage.getItem(GM_KEY(cid)) || 'null') || {}) }; } catch { return _defaultGM(); } }
function _saveGM(cid, g) { try { localStorage.setItem(GM_KEY(cid), JSON.stringify(g)); } catch {} _pushState(cid, 'gm', g); }
function _b(v, lo, mid, hi) { return v <= 25 ? lo : (v >= 75 ? hi : mid); }
// The craft of a great table, distilled from how the best actual-play GMs run
// (sensory narration, "you can try", roll only when failure is interesting,
// fail forward, escalation, consequences and callbacks, NPC ownership). Rides
// with the tone knobs on every DM turn.
const _GM_CRAFT =
  'Table craft: Narrate with the senses — turn every roll and hit into cinema (a near-miss shrieks off a helmet), never bare numbers. ' +
  'Never flatly refuse an action: say "you can try", state the stakes, set a DC — the impossible may simply fail, interestingly. ' +
  'Call for a roll ONLY when failure is interesting; let clever roleplay grant advantage or lower the DC, not skip the roll. ' +
  'Failure moves the story forward (a cost, a complication, a worse position) — never a dead "nothing happens". Let situations escalate; pile complication on complication before relief. ' +
  'Actions ripple: NPCs remember, attitudes shift, word spreads — call back to earlier deeds and let the world visibly change because of them. ' +
  'NPCs have wants, voices, and verbal tics; let the player build real relationships they co-own. Give companions moments to shine. ' +
  'Do not steer toward a "correct" choice or foreshadow your plans — keep a poker face and let genuine tension stand. ' +
  'Reward bold, creative, in-character play (Inspiration, position, an opening) — make the cool thing possible, but always through a check or a cost, never free.';
function _gmDirective(cid) {
  const g = _loadGM(cid);
  return [
    _b(g.humor, 'Keep the tone serious and grounded.', 'Mix in occasional wit.', 'Lean hard into comedy, banter, and playful absurdity.'),
    _b(g.spice, 'Keep everything clean — no romance or sexual content.', 'Allow light, tasteful romance when it fits.', 'Embrace bold romance and steamy, sensual tension between consenting adults.'),
    _b(g.grit, 'Keep danger gentle; the player is rarely truly at risk.', 'Use real but fair stakes.', 'Make it brutal and deadly — high stakes, real wounds, real consequences.'),
    _b(g.pace, 'Move slowly; savor atmosphere and detail.', 'Keep a steady, balanced pace.', 'Keep it fast and action-packed; cut straight to the exciting beats.'),
    _b(g.rules, 'Be loose with the rules; favor story over dice.', 'Use 5e rules sensibly.', 'Enforce 5e rules strictly — call for rolls often and track HP, conditions, and inventory closely.'),
    _GM_CRAFT,
  ].join(' ');
}

// Session Zero: the tone/difficulty step of the new-adventure flow. Reuses the
// exact GM knobs (same store, same directive) — this is just the moment we ask.
function _sessionZero(cid) {
  return new Promise((resolve) => {
    const modal = $('studio-modal'); if (!modal) { resolve(); return; }
    let ov = $('studio-szero-overlay');
    if (!ov) { ov = document.createElement('div'); ov.id = 'studio-szero-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
    const g = _loadGM(cid);
    const rows = GM_KNOBS.map(k => `
      <div class="gm-row">
        <div class="gm-row-head"><label for="sz-${k.key}">${k.label}</label><span class="gm-val" data-szval="${k.key}">${g[k.key]}</span></div>
        <input type="range" id="sz-${k.key}" data-sz="${k.key}" min="0" max="100" step="5" value="${g[k.key]}">
        <div class="gm-ends"><span>${k.lo}</span><span>${k.hi}</span></div>
      </div>`).join('');
    ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Session Zero">
      <div class="chronicle-bar"><h2>Session Zero</h2></div>
      <div class="chronicle-list">
        <p class="studio-step">New adventure · Step 3 of 3 — world › campaign › hero › <em>tone</em></p>
        <p class="gm-hint">Set the table before the tale begins — how funny, how deadly, how strict. You can retune anytime from the GM panel.</p>
        ${rows}
        <div class="chronicle-actions"><button class="st-btn primary" id="sz-begin" type="button">Begin the adventure ›</button></div>
      </div></div>`;
    ov.style.display = 'flex';
    ov.querySelectorAll('input[data-sz]').forEach(inp => inp.addEventListener('input', () => {
      const gg = _loadGM(cid); gg[inp.dataset.sz] = Number(inp.value); _saveGM(cid, gg);
      const v = ov.querySelector(`[data-szval="${inp.dataset.sz}"]`); if (v) v.textContent = inp.value;
    }));
    $('sz-begin').addEventListener('click', () => { ov.style.display = 'none'; resolve(); }, { once: true });
  });
}

function toggleGM() {
  const panel = $('studio-gm-panel');
  if (panel && panel.classList.contains('open')) { panel.classList.remove('open'); return; }
  renderGMPanel();
}
function renderGMPanel() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const g = _loadGM(cid);
  let panel = $('studio-gm-panel');
  if (!panel) { panel = document.createElement('div'); panel.id = 'studio-gm-panel'; panel.className = 'gm-panel'; modal.appendChild(panel); }
  const rows = GM_KNOBS.map(k => `
    <div class="gm-row">
      <div class="gm-row-head"><label for="gm-${k.key}">${k.label}</label><span class="gm-val" data-gmval="${k.key}">${g[k.key]}</span></div>
      <input type="range" id="gm-${k.key}" data-gm="${k.key}" min="0" max="100" step="5" value="${g[k.key]}">
      <div class="gm-ends"><span>${k.lo}</span><span>${k.hi}</span></div>
    </div>`).join('');
  const t = _loadTTS();
  const voiceOpts = _ttsAvailable()
    ? `<option value="">Default voice</option>` + _ttsVoices().filter(v => /en[-_]/i.test(v.lang)).map(v => `<option value="${_esc(v.name)}"${v.name === t.voice ? ' selected' : ''}>${_esc(v.name)}</option>`).join('')
    : '';
  const narration = _ttsAvailable() ? `
    <div class="gm-row gm-narrate">
      <div class="gm-row-head"><label>Narration</label><span class="gm-val">${t.on ? 'On' : 'Off'}</span></div>
      <label class="tts-toggle"><input type="checkbox" id="tts-on"${t.on ? ' checked' : ''}> Read the story aloud</label>
      <select id="tts-voice" class="studio-select" aria-label="Narration voice">${voiceOpts}</select>
      <div class="gm-row-head" style="margin-top:8px"><label for="tts-rate">Speed</label><span class="gm-val" id="tts-rate-val">${(t.rate || 1).toFixed(1)}×</span></div>
      <input type="range" id="tts-rate" min="0.6" max="1.6" step="0.1" value="${t.rate || 1}">
      <button class="st-btn small" id="tts-test" type="button" style="margin-top:8px">▶ Test voice</button>
    </div>` : '';
  panel.innerHTML = `
    <div class="gm-head"><h2>Game Master</h2><button class="studio-close" id="gm-close" type="button" aria-label="Close">✕</button></div>
    <div class="gm-body">
      <p class="gm-hint">Tune how your Game Master runs this tale. Saved with this storyline.</p>
      ${rows}
      ${narration}
    </div>`;
  panel.classList.add('open');
  $('gm-close').addEventListener('click', () => panel.classList.remove('open'));
  panel.querySelectorAll('input[data-gm]').forEach(inp => inp.addEventListener('input', () => {
    g[inp.dataset.gm] = Number(inp.value); _saveGM(cid, g);
    const v = panel.querySelector(`[data-gmval="${inp.dataset.gm}"]`); if (v) v.textContent = inp.value;
  }));
  if (_ttsAvailable()) {
    $('tts-on')?.addEventListener('change', (e) => { const tt = _loadTTS(); tt.on = e.target.checked; _saveTTS(tt); if (!tt.on) _stopSpeech(); _reflectTTSBtn(); renderGMPanel(); });
    $('tts-voice')?.addEventListener('change', (e) => { const tt = _loadTTS(); tt.voice = e.target.value; _saveTTS(tt); });
    $('tts-rate')?.addEventListener('input', (e) => { const tt = _loadTTS(); tt.rate = Number(e.target.value); _saveTTS(tt); const rv = $('tts-rate-val'); if (rv) rv.textContent = tt.rate.toFixed(1) + '×'; });
    $('tts-test')?.addEventListener('click', () => { const tt = _loadTTS(); const prev = tt.on; if (!prev) { tt.on = true; _saveTTS(tt); } _speak('The torches gutter as you step into the hall. What do you do?'); if (!prev) { tt.on = false; _saveTTS(tt); } });
  }
}

async function setScene() {
  const desc = window.styledPrompt
    ? await window.styledPrompt('Describe the scene to set the backdrop:', { placeholder: 'e.g. a torchlit dungeon of dripping stone' })
    : window.prompt('Describe the scene to set the backdrop:');
  const scene = (desc || '').trim();
  if (!scene) return;
  const btn = $('studio-scene-btn'); const orig = btn ? btn.innerHTML : '';
  if (btn) { btn.disabled = true; btn.textContent = 'Painting…'; }
  const wid = (_chat.char && _chat.char.world_id) || '';
  try { localStorage.removeItem(BACKDROP_KEY(wid || 'custom')); } catch {}
  await _applyBackdrop(wid, scene + ', atmospheric cinematic digital art, no people');
  if (btn) { btn.disabled = false; btn.innerHTML = orig; }
}

// ── Your default adventurer ("Yourself") ───────────────────────────────────
const PLAYER_KEY = 'studio-player';
function _loadPlayer() { try { return JSON.parse(localStorage.getItem(PLAYER_KEY) || 'null'); } catch { return null; } }
function _savePlayer(p) { try { localStorage.setItem(PLAYER_KEY, JSON.stringify(p)); } catch {} }
function _playerName() { const p = _loadPlayer(); return (p && p.name) ? p.name : 'Yourself'; }

// Seed a fresh adventure's sheet from your default self, so your hero carries in.
function _seedSheetFromPlayer(cid) {
  const p = _loadPlayer();
  if (!p) return;
  const s = _loadSheet(cid);
  if (!s.name && p.name) {
    s.name = p.name;
    if (p.abilities) s.abilities = { ...s.abilities, ...p.abilities };
    _saveSheet(cid, s);
  }
}

// The one adventurer editor — portrait, appearance, class, and stats. Doubles as
// the start-of-campaign gate: pass { cid, gate:true, onDone } and its Save seeds
// that adventure's sheet + starting kit, then resolves. opts is optional.
// Backgrounds — who your hero was before the adventure. Two trained skills and
// a hook the GM weaves into the story.
const BACKGROUNDS = {
  Soldier:     { skills: ['athletics', 'intimidation'], line: 'a veteran who has seen real battle and carries its discipline (and its ghosts)' },
  Criminal:    { skills: ['stealth', 'deception'], line: 'a former criminal with underworld contacts and a knack for going unnoticed' },
  Sage:        { skills: ['arcana', 'history'], line: 'a scholar who has read of things most people have never heard of' },
  Acolyte:     { skills: ['insight', 'religion'], line: 'raised in a temple, at home with rites, relics, and the faithful' },
  Outlander:   { skills: ['survival', 'athletics'], line: 'raised in the wilds; cities are stranger to you than storms' },
  Entertainer: { skills: ['performance', 'acrobatics'], line: 'a performer who can hold a crowd — and read one' },
  Merchant:    { skills: ['persuasion', 'insight'], line: 'a trader who knows what things are worth and how people bargain' },
  Urchin:      { skills: ['sleight of hand', 'stealth'], line: 'grew up on the streets; you know every shortcut and how to disappear' },
};

function openPlayerEditor(opts) {
  opts = opts || {};
  const modal = $('studio-modal'); if (!modal) { if (opts.onDone) opts.onDone(); return; }
  const p = _loadPlayer() || { name: '', appearance: '', avatar: '', cls: '', abilities: { STR: 10, DEX: 10, CON: 10, INT: 10, WIS: 10, CHA: 10 } };
  // On a fresh campaign with no rolled stats yet, start from the standard array.
  if (opts.gate && (!p.abilities || Object.values(p.abilities).every(v => (v || 10) === 10))) { const arr = [15, 14, 13, 12, 10, 8]; p.abilities = {}; ABILITIES.forEach((a, i) => p.abilities[a] = arr[i]); }
  let ov = $('studio-player-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-player-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  let avatarUrl = p.avatar || '';
  const abilityCells = ABILITIES.map(a => `<div class="ab-cell"><label>${a}</label><input type="number" class="pl-ab" data-ab="${a}" value="${_esc(p.abilities[a] != null ? p.abilities[a] : 10)}" min="1" max="30"><span class="ab-mod" data-plmod="${a}">${_modStr(p.abilities[a] != null ? p.abilities[a] : 10)}</span></div>`).join('');
  // In a reskinned world the dropdown speaks that world's language:
  // "Wizard ✦ — Body Modder here".
  const _rk = _reskinFor(opts.world);
  const classOpts = `<option value="">— pick a class —</option>` + Object.keys(CLASS_PRESETS).map(c => {
    const skin = _rk && _rk.names[c] ? ` — ${_rk.names[c]} here` : '';
    return `<option value="${c}"${p.cls === c ? ' selected' : ''}>${c}${CLASS_PRESETS[c].caster ? ' ✦' : ''}${skin}</option>`;
  }).join('');
  const art = p.avatar ? `<img src="${_esc(p.avatar)}" alt="You">` : `<div class="fc-empty"><span class="fc-rune" aria-hidden="true">✦</span>Conjure your likeness</div>`;
  // Prebuilt heroes: one click fills the whole form (still fully editable).
  const PREBUILT = [
    { name: 'Brakka Ironhide', cls: 'Fighter', race: 'Half-Orc', background: 'Soldier', appearance: 'towering half-orc woman, scarred jaw, heavy plate', arr: { STR: 15, CON: 14, DEX: 13, WIS: 12, CHA: 10, INT: 8 } },
    { name: 'Elara Venn', cls: 'Wizard', race: 'Elf', background: 'Sage', appearance: 'slender elf, silver hair, ink-stained fingers, star-charted robes', arr: { INT: 15, DEX: 14, CON: 13, WIS: 12, CHA: 10, STR: 8 } },
    { name: 'Finch', cls: 'Rogue', race: 'Halfling', background: 'Criminal', appearance: 'wiry halfling, crooked grin, patched travel leathers', arr: { DEX: 15, CHA: 14, CON: 13, INT: 12, WIS: 10, STR: 8 } },
    { name: 'Sister Maren', cls: 'Cleric', race: 'Human', background: 'Acolyte', appearance: 'weathered human woman, shaved head, sun-symbol amulet', arr: { WIS: 15, CON: 14, STR: 13, CHA: 12, INT: 10, DEX: 8 } },
  ];
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Your adventurer">
    <div class="chronicle-bar"><h2>${opts.gate ? 'Create your hero' : 'Your adventurer'}</h2><button class="studio-close" id="pl-close" type="button" aria-label="${opts.gate ? 'Cancel — back to the campaign list' : 'Close'}">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">${opts.gate ? 'This creates a <strong>new hero for this adventure</strong> — your last hero is prefilled as a starting template and is never overwritten by playing. Grab a ready-made hero, start fresh, or edit anything.' : 'This is <strong>you</strong> — your default hero. New adventures start from these stats.'}</p>
      ${opts.gate ? `<div class="prebuilt-row" role="group" aria-label="Ready-made heroes">${PREBUILT.map((h, i) => `<button type="button" class="st-btn small ghost" data-prebuilt="${i}" title="${_esc(h.race)} ${_esc(h.cls)} · ${_esc(h.background)}">⚔ ${_esc(h.name)}</button>`).join('')}<button type="button" class="st-btn small ghost" id="pl-fresh" title="Clear every field and start from nothing">✨ Start fresh</button></div>` : ''}
      <div class="forge-stage" style="max-width:230px;align-self:center"><div class="forge-canvas" id="pl-canvas">${art}</div>
        <div class="forge-actions" style="margin-top:10px"><button class="st-btn" id="pl-gen" type="button">Conjure portrait</button></div></div>
      <label class="sf">Portrait prompt <span class="gm-hint" style="display:inline;margin:0">— seeded from your picks below; make it yours (“male, balding, kind eyes…”)</span>
        <textarea id="pl-imgprompt" rows="2" placeholder="Pick a heritage and class below to seed this…"></textarea></label>
      <div class="sheet-grid2"><label class="sf">Name<input type="text" id="pl-name" value="${_esc(p.name)}" placeholder="Your hero's name"></label>
      <label class="sf">Class<select id="pl-class" class="studio-select">${classOpts}</select></label></div>
      <div class="sheet-grid2">
        <label class="sf">Heritage<select id="pl-race" class="studio-select"><option value="">— human by default —</option>${Object.keys(HERITAGES).map(r => `<option value="${r}"${p.race === r ? ' selected' : ''}>${r}</option>`).join('')}</select></label>
        <label class="sf">Background<select id="pl-bg" class="studio-select"><option value="">— who were you before? —</option>${Object.keys(BACKGROUNDS).map(b => `<option value="${b}"${p.background === b ? ' selected' : ''}>${b} · ${BACKGROUNDS[b].skills.map(_titleCase).join(' + ')}</option>`).join('')}</select></label>
      </div>
      <p class="pl-race-hint gm-hint" style="display:none;margin:0"></p>
      <p class="pl-bg-hint gm-hint" style="display:none;margin:0"></p>
      <label class="sf">Appearance<textarea id="pl-appearance" rows="2" placeholder="How you look…">${_esc(p.appearance)}</textarea></label>
      <label class="sf">Backstory <span class="gm-hint" style="display:inline;margin:0">— who you were, what haunts you; the GM weaves this into the tale</span>
        <textarea id="pl-story" rows="3" placeholder="Orphaned in the gear-mines, raised by smugglers, still looking for the airship that took her brother…">${_esc(p.backstory || '')}</textarea></label>
      <div class="cc-abtools"><span class="cc-abtitle">Abilities</span><button class="st-btn small" id="pl-roll" type="button">🎲 Roll (4d6)</button><button class="st-btn small ghost" id="pl-array" type="button">Standard array</button></div>
      <div class="ab-grid">${abilityCells}</div>
      <p class="gm-hint" style="margin:0">These are your BASE scores. Your heritage's bonuses are added on top when the adventure begins (shown above when you pick one). Backgrounds grant trained skills, not scores.</p>
      <p class="pl-kit-hint" style="display:none"></p>
      <div class="chronicle-actions"><button class="st-btn primary" id="pl-save" type="button">${opts.gate ? 'Begin adventure ›' : 'Save your adventurer'}</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  const finish = (made) => { ov.style.display = 'none'; if (opts.onDone) { const cb = opts.onDone; opts.onDone = null; cb(!!made); } };
  const setAbil = (obj) => ABILITIES.forEach(a => { const inp = ov.querySelector(`.pl-ab[data-ab="${a}"]`); if (inp) { inp.value = obj[a]; const m = ov.querySelector(`[data-plmod="${a}"]`); if (m) m.textContent = _modStr(obj[a]); } });
  const refreshKit = () => { const el = ov.querySelector('.pl-kit-hint'); const c = $('pl-class') && $('pl-class').value; if (opts.gate && c) { el.style.display = ''; el.innerHTML = `Class kit: ${_esc((_CLASS_KIT[c] || []).concat(_COMMON_KIT).join(', '))} · +25 gold`; } else if (el) el.style.display = 'none'; };
  refreshKit();
  $('pl-close').addEventListener('click', () => finish(false));
  ov.addEventListener('click', (e) => { if (e.target === ov) finish(false); });
  // The portrait prompt follows the dropdowns until the player edits it by hand.
  let _promptDirty = false;
  const _seedPrompt = () => {
    const el = $('pl-imgprompt'); if (!el || _promptDirty) return;
    const race = ($('pl-race') && $('pl-race').value) || '';
    const cls = ($('pl-class') && $('pl-class').value) || '';
    const app = ($('pl-appearance') && $('pl-appearance').value || '').trim();
    // World-adapted look: a Neon Spire Wizard seeds as "body modder", not "wizard".
    const skin = _classSkinName(opts.world, cls);
    el.value = [race.toLowerCase(), (skin || cls).toLowerCase(), app].filter(Boolean).join(' ').trim();
  };
  $('pl-imgprompt')?.addEventListener('input', () => { _promptDirty = true; });
  $('pl-appearance')?.addEventListener('input', _seedPrompt);
  $('pl-race')?.addEventListener('change', _seedPrompt);
  $('pl-class')?.addEventListener('change', _seedPrompt);
  _seedPrompt();
  // Picking a hero (prebuilt or fresh) swaps the WHOLE identity — including
  // clearing the old portrait so you never carry someone else's face.
  const _resetPortrait = () => {
    avatarUrl = '';
    const cv = $('pl-canvas'); if (cv) cv.innerHTML = `<div class="fc-empty"><span class="fc-rune" aria-hidden="true">✦</span>Conjure your likeness</div>`;
  };
  // Prebuilt heroes fill the whole form (name/class/heritage/background/stats).
  ov.querySelectorAll('[data-prebuilt]').forEach(b => b.addEventListener('click', () => {
    const h = PREBUILT[Number(b.dataset.prebuilt)]; if (!h) return;
    $('pl-name').value = h.name; $('pl-class').value = h.cls;
    if ($('pl-race')) $('pl-race').value = h.race;
    if ($('pl-bg')) $('pl-bg').value = h.background;
    $('pl-appearance').value = h.appearance;
    if ($('pl-story')) $('pl-story').value = '';
    setAbil(h.arr);
    _resetPortrait();
    _promptDirty = false; _seedPrompt();
    ['pl-class', 'pl-race', 'pl-bg'].forEach(id => $(id)?.dispatchEvent(new Event('change')));
  }));
  // Start fresh: a blank slate — no prefilled hero to hand-delete.
  $('pl-fresh')?.addEventListener('click', () => {
    ['pl-name', 'pl-appearance', 'pl-story', 'pl-imgprompt'].forEach(id => { const el = $(id); if (el) el.value = ''; });
    ['pl-class', 'pl-race', 'pl-bg'].forEach(id => { const el = $(id); if (el) { el.value = ''; el.dispatchEvent(new Event('change')); } });
    const arr = [15, 14, 13, 12, 10, 8], o = {}; ABILITIES.forEach((a, i) => o[a] = arr[i]); setAbil(o);
    _resetPortrait();
    _promptDirty = false; _seedPrompt();
    $('pl-name')?.focus();
  });
  $('pl-class')?.addEventListener('change', refreshKit);
  const refreshRace = () => { const el = ov.querySelector('.pl-race-hint'); const r = HERITAGES[($('pl-race') || {}).value]; if (el) { el.style.display = r ? '' : 'none'; if (r) { const bon = Object.entries(r.abil).map(([k, v]) => `+${v} ${k}`).join(', '); el.textContent = `${bon} · speed ${r.speed}ft${r.dark ? ` · darkvision ${r.dark}ft` : ''} · ${r.traits[0]}`; } } };
  refreshRace();
  $('pl-race')?.addEventListener('change', refreshRace);
  const refreshBg = () => { const el = ov.querySelector('.pl-bg-hint'); const b = BACKGROUNDS[($('pl-bg') || {}).value]; if (el) { el.style.display = b ? '' : 'none'; if (b) el.textContent = `${_titleCase(b.skills.join(' & '))} proficiency — ${b.line}.`; } };
  refreshBg();
  $('pl-bg')?.addEventListener('change', refreshBg);
  ov.querySelectorAll('.pl-ab').forEach(inp => inp.addEventListener('input', () => { const m = ov.querySelector(`[data-plmod="${inp.dataset.ab}"]`); if (m) m.textContent = _modStr(inp.value); }));
  $('pl-roll')?.addEventListener('click', () => { const o = {}; ABILITIES.forEach(a => o[a] = _roll4d6()); setAbil(o); });
  $('pl-array')?.addEventListener('click', () => { const arr = [15, 14, 13, 12, 10, 8], o = {}; ABILITIES.forEach((a, i) => o[a] = arr[i]); setAbil(o); });
  $('pl-gen').addEventListener('click', async () => {
    // The editable prompt field drives the portrait; fall back to the old
    // composition if it's somehow empty.
    const seeded = ($('pl-imgprompt') && $('pl-imgprompt').value || '').trim();
    const cls = ($('pl-class') && $('pl-class').value) || '';
    const desc = seeded || [($('pl-appearance').value || '').trim(), cls, ($('pl-name').value || '').trim()].filter(Boolean).join(', ');
    if (!desc) { _toast('Pick a heritage and class (or type a prompt) first.'); return; }
    const btn = $('pl-gen'); btn.disabled = true; btn.textContent = 'Conjuring…';
    try {
      const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt: desc + ', character portrait, head and shoulders' }) });
      const d = await r.json();
      if (d.ok && d.image_url) { avatarUrl = d.image_url; $('pl-canvas').innerHTML = `<img src="${_esc(d.image_url)}" alt="You">`; }
    } catch {}
    btn.disabled = false; btn.textContent = 'Conjure portrait';
  });
  $('pl-save').addEventListener('click', () => {
    const abilities = {};
    ABILITIES.forEach(a => { const inp = ov.querySelector(`.pl-ab[data-ab="${a}"]`); abilities[a] = Number(inp.value || 10); });
    const cls = ($('pl-class') && $('pl-class').value) || p.cls || '';
    const background = ($('pl-bg') && $('pl-bg').value) || p.background || '';
    const race = ($('pl-race') && $('pl-race').value) || p.race || '';
    const name = ($('pl-name').value || '').trim();
    // No nameless, classless heroes wandering into a campaign.
    if (opts.gate && (!name || !cls)) {
      _toast(!name ? 'Your hero needs a name.' : 'Pick a class before you begin.');
      (!name ? $('pl-name') : $('pl-class'))?.focus();
      return;
    }
    const backstory = ($('pl-story') && $('pl-story').value || '').trim();
    _savePlayer({ name, appearance: ($('pl-appearance').value || '').trim(), avatar: avatarUrl, cls, background, race, abilities, backstory });
    if (opts.cid) _seedAdventureSheet(opts.cid, { name, abilities, cls, background, race, world: opts.world, avatar: avatarUrl, backstory });   // pour the identity into this adventure's sheet + kit
    finish(true);
  });
}

// ── Toast + art-queue awareness ──────────────────────────────────────────────
// One GPU serves every player: when a second image is requested while one is
// still baking, say so once instead of leaving people wondering.
function _toast(msg) {
  const modal = $('studio-modal'); if (!modal) return;
  const t = document.createElement('div');
  t.className = 'studio-toast'; t.setAttribute('role', 'status'); t.textContent = msg;
  modal.appendChild(t);
  setTimeout(() => t.remove(), 4200);
}
let _artInFlight = 0, _artToastAt = 0;
// ── Art styles (per-world image checkpoint) ─────────────────────────────────
// Each world can pick an SDXL checkpoint ("Realism", "High Fantasy", …). The
// choice rides every /studio/generate call (injected in _artFetch below, so all
// ~12 call sites are covered in one place); the server maps it to a checkpoint.
let _activeStyle = '';
let _artStyleCache = null;
const _STYLE_KEY = (wid) => `studio-artstyle-${wid}`;
function _loadWorldStyle(wid) { try { return localStorage.getItem(_STYLE_KEY(wid)) || ''; } catch { return ''; } }
function _saveWorldStyle(wid, id) { try { localStorage.setItem(_STYLE_KEY(wid), id || ''); } catch {} _activeStyle = id || ''; }
async function _fetchArtStyles(force) {
  if (_artStyleCache && !force) return _artStyleCache;
  try { const d = await (await fetch(`${API_BASE}/api/characters/studio/art-styles`)).json(); _artStyleCache = d.styles || []; } catch { _artStyleCache = []; }
  return _artStyleCache;
}
// Kick a download, then poll progress until done/error. onProg(pct, mb, total).
async function _downloadStyle(id, onProg) {
  try { const r0 = await fetch(`${API_BASE}/api/characters/studio/art-styles/download`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }) }); if (!r0.ok) return false; } catch { return false; }
  const t0 = Date.now();
  return new Promise((resolve) => {
    const tick = async () => {
      let p = {};
      try { p = ((await (await fetch(`${API_BASE}/api/characters/studio/art-styles/progress/${encodeURIComponent(id)}`)).json()) || {}).progress || {}; } catch {}
      if (onProg) onProg(p);
      if (p.state === 'done') { _artStyleCache = null; resolve(true); }
      else if (p.state === 'error') { resolve(false); }
      else if (Date.now() - t0 > 45 * 60 * 1000) { resolve(false); }   // 45-min cap: a dead download must not disable the picker forever
      else setTimeout(tick, 1500);
    };
    tick();
  });
}

function _artFetch(url, opts) {
  // Thread the world's chosen art style into every image-gen call, in one place.
  if (_activeStyle && typeof url === 'string' && url.indexOf('/studio/generate') >= 0 && opts && typeof opts.body === 'string') {
    try { const b = JSON.parse(opts.body); if (b && !b.style) { b.style = _activeStyle; opts = { ...opts, body: JSON.stringify(b) }; } } catch {}
  }
  _artInFlight++;
  if (_artInFlight > 1 && Date.now() - _artToastAt > 20000) {
    _artToastAt = Date.now();
    _toast('🎨 The art forge is busy — pictures appear as they finish; the story never waits.');
  }
  const p = fetch(url, opts);
  p.finally(() => { _artInFlight = Math.max(0, _artInFlight - 1); }).catch(() => {});
  return p;
}

// ── Shared parties: play one campaign together over the network ──────────────
// The host opens a table (join code); friends join from their own accounts.
// One chat session, one world state (the host's), everyone at the same fire.
// Sync is a light poll — new messages appear, and a "table lock" keeps two
// people from talking over each other's GM turn.
const PARTY_KEY = (cid) => `studio-party-${cid}`;
let _party = null;          // { code, role: 'host'|'guest', hero, host } for the open chat
let _partyBusy = null;      // latest busy info from the poll
let _partyTimer = null;
let _partyHistLen = -1;

function _loadPartyMark(cid) { try { return JSON.parse(localStorage.getItem(PARTY_KEY(cid)) || 'null'); } catch { return null; } }
function _savePartyMark(cid, mark) { try { localStorage.setItem(PARTY_KEY(cid), JSON.stringify(mark)); } catch {} }

function _partyStop() { _voiceStop(); if (_partyTimer) { clearInterval(_partyTimer); _partyTimer = null; } _party = null; _partyBusy = null; _partyHistLen = -1; }

// ── Party voice: a WebRTC mesh over the tailnet ──────────────────────────────
// Audio is peer-to-peer; the server only ferries offer/answer/ICE envelopes
// (party/signal). No STUN needed on a tailnet — host candidates route.
let _voice = null;   // { stream, peers: Map<user, RTCPeerConnection>, timer, muted }
function _voiceSend(to, data) {
  if (!_party) return;
  fetch(`${API_BASE}/api/characters/studio/party/signal`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: _party.code, to, data }),
  }).catch(() => {});
}
function _voicePeer(user) {
  let pc = _voice.peers.get(user);
  if (pc) return pc;
  pc = new RTCPeerConnection({ iceServers: [] });
  _voice.stream.getTracks().forEach(t => pc.addTrack(t, _voice.stream));
  pc.onicecandidate = (e) => { if (e.candidate) _voiceSend(user, { type: 'ice', cand: e.candidate.toJSON() }); };
  pc.ontrack = (e) => {
    let a = document.getElementById('voice-audio-' + user);
    if (!a) { a = document.createElement('audio'); a.id = 'voice-audio-' + user; a.autoplay = true; document.body.appendChild(a); }
    a.srcObject = e.streams[0];
  };
  pc.onconnectionstatechange = () => {
    if (_voice && ['failed', 'closed'].includes(pc.connectionState)) { _voice.peers.delete(user); _reflectVoiceChip(); }
  };
  _voice.peers.set(user, pc);
  return pc;
}
async function _voiceOffer(user) {
  const pc = _voicePeer(user);
  await pc.setLocalDescription(await pc.createOffer());
  _voiceSend(user, { type: 'offer', sdp: pc.localDescription });
}
async function _voiceHandle(from, d) {
  if (!_voice || !d) return;
  try {
    if (d.type === 'hello') {
      // Deterministic initiator (no glare): the lexicographically smaller name offers.
      if ((_party.me || '') < from && !_voice.peers.has(from)) await _voiceOffer(from);
      else if ((_party.me || '') >= from) _voiceSend(from, { type: 'hello-back' });
    } else if (d.type === 'hello-back') {
      if ((_party.me || '') < from && !_voice.peers.has(from)) await _voiceOffer(from);
    } else if (d.type === 'offer') {
      const pc = _voicePeer(from);
      await pc.setRemoteDescription(d.sdp);
      await pc.setLocalDescription(await pc.createAnswer());
      _voiceSend(from, { type: 'answer', sdp: pc.localDescription });
    } else if (d.type === 'answer') {
      const pc = _voice.peers.get(from);
      if (pc && !pc.currentRemoteDescription) await pc.setRemoteDescription(d.sdp);
    } else if (d.type === 'ice') {
      const pc = _voice.peers.get(from);
      if (pc) await pc.addIceCandidate(d.cand);
    } else if (d.type === 'bye') {
      const pc = _voice.peers.get(from);
      if (pc) { try { pc.close(); } catch {} _voice.peers.delete(from); }
      document.getElementById('voice-audio-' + from)?.remove();
    }
    _reflectVoiceChip();
  } catch (e) { /* signaling is best-effort; the next hello re-bootstraps */ }
}
async function _voicePoll() {
  if (!_voice || !_party) return;
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/party/signal?code=${encodeURIComponent(_party.code)}`);
    if (!r.ok) return;
    const d = await r.json();
    for (const m of (d.signals || [])) await _voiceHandle(m.from, m.data);
  } catch {}
}
async function _voiceStart() {
  if (_voice || !_party) return;
  if (!_party.me) { try { const d = await (await fetch(`${API_BASE}/api/auth/status`)).json(); _party.me = d.username || ''; } catch {} }
  let stream;
  try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); }
  catch { _toast("🎙 Couldn't open your microphone — check browser permissions."); return; }
  _voice = { stream, peers: new Map(), muted: false, timer: setInterval(_voicePoll, 2500) };
  // Announce to everyone at the table; whoever sorts lower makes the offer.
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/party/state?code=${encodeURIComponent(_party.code)}`);
    const d = await r.json();
    [d.host].concat((d.members || []).map(m => m.user))
      .filter(u => u && u !== _party.me)
      .forEach(u => _voiceSend(u, { type: 'hello' }));
  } catch {}
  _toast('🎙 Voice on — party members who turn theirs on will connect.');
  _reflectVoiceChip();
}
function _voiceStop() {
  if (!_voice) return;
  try {
    _voice.peers.forEach((pc, u) => { _voiceSend(u, { type: 'bye' }); try { pc.close(); } catch {} document.getElementById('voice-audio-' + u)?.remove(); });
    _voice.stream.getTracks().forEach(t => t.stop());
    clearInterval(_voice.timer);
  } catch {}
  _voice = null;
  _reflectVoiceChip();
}
function _voiceMute() {
  if (!_voice) return;
  _voice.muted = !_voice.muted;
  _voice.stream.getAudioTracks().forEach(t => { t.enabled = !_voice.muted; });
  _reflectVoiceChip();
}
function _reflectVoiceChip() {
  const bar = document.querySelector('#studio-chat .cb-chips'); if (!bar) return;
  let chip = $('studio-voice-chip');
  if (!_party) { if (chip) chip.remove(); return; }
  if (!chip) {
    chip = document.createElement('button');
    chip.type = 'button'; chip.id = 'studio-voice-chip'; chip.className = 'clock-chip voice-chip';
    chip.addEventListener('click', () => { if (!_voice) _voiceStart(); else _voiceMute(); });
    chip.addEventListener('contextmenu', (e) => { e.preventDefault(); _voiceStop(); });
    bar.appendChild(chip);
  }
  chip.title = _voice ? 'Click to mute/unmute · right-click to hang up' : 'Talk to your party — live voice';
  chip.textContent = !_voice ? '🎙 Voice' : (_voice.muted ? '🔇 Muted' : `🎙 Live${_voice.peers.size ? ' · ' + _voice.peers.size : ''}`);
}

function _partyStart(cid) {
  _partyStop();
  const mark = _loadPartyMark(cid);
  if (!mark) return;
  _party = mark;
  // Know which seat is yours, so your own table lock never blocks you.
  fetch(`${API_BASE}/api/auth/status`).then(r => r.json()).then(d => { if (_party) _party.me = d.username || ''; }).catch(() => {});
  if (mark.role === 'guest' && mark.hero) {
    _chat.playAs = mark.hero;   // you speak as YOUR hero
    const sel = $('studio-playas');
    if (sel && ![...sel.options].some(o => o.value === mark.hero)) {
      const o = document.createElement('option'); o.value = mark.hero; o.textContent = `${mark.hero} (your hero)`;
      sel.appendChild(o); sel.value = mark.hero;
    } else if (sel) sel.value = mark.hero;
  }
  _reflectPartyChip();
  _partyTimer = setInterval(_partyPoll, 4000);
}

async function _partyPoll() {
  if (!_party || !_chat.sessionId) return;
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/party/state?code=${encodeURIComponent(_party.code)}`);
    if (r.ok) { const d = await r.json(); _partyBusy = d.busy || null; _reflectPartyChip(d.members || []); }
    // New messages from the other players (or the GM answering them)?
    if (!_chat.streaming) {
      const h = await fetch(`${API_BASE}/api/history/${_chat.sessionId}`);
      if (h.ok) {
        const n = ((await h.json()).history || []).length;
        if (_partyHistLen >= 0 && n > _partyHistLen && !_chat.streaming) {
          await _loadChatHistory();
          _scrollChat();
          _renderPartyChips(_chat.char && _chat.char.id);   // hp may have moved
        }
        _partyHistLen = n;
      }
    }
  } catch (e) { /* polls are best-effort */ }
}

function _reflectPartyChip(members) {
  const bar = document.querySelector('#studio-chat .cb-chips'); if (!bar) return;
  _reflectVoiceChip();   // the voice chip rides beside the party chip
  let chip = $('studio-party-chip');
  if (!chip) {
    chip = document.createElement('button');
    chip.type = 'button'; chip.id = 'studio-party-chip'; chip.className = 'clock-chip party-live';
    chip.addEventListener('click', () => openPartyPanel());
    bar.appendChild(chip);
  }
  const busyBy = _partyBusy && _partyBusy.by;
  const me = busyBy && _party && busyBy === _party.me;
  chip.innerHTML = busyBy && !me
    ? `✋ <strong>${_esc(busyBy)}</strong> is talking to the GM…`
    : `🔗 Party ${_party ? `· ${_esc(_party.code)}` : ''}`;
  chip.classList.toggle('busy', !!(busyBy && !me));
  const send = $('studio-send'); if (send && !_chat.streaming) send.disabled = !!(busyBy && !me);
}

async function _partySetBusy(on) {
  if (!_party) return;
  try {
    await fetch(`${API_BASE}/api/characters/studio/party/busy`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: _party.code, busy: !!on }),
    });
  } catch (e) {}
}

// Host: open the table — show the code, see who's seated.
async function openPartyPanel() {
  const modal = $('studio-modal'); if (!modal || !_chat.char || !_isDM(_chat.char)) return;
  const cid = _chat.char.id;
  let ov = $('studio-party-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-party-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Party table">
    <div class="chronicle-bar"><h2>🔗 Play together</h2><button class="studio-close" id="party-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list" id="party-body"><p class="gm-hint">Opening the table…</p></div></div>`;
  ov.style.display = 'flex';
  $('party-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  try {
    const r = await fetch(`${API_BASE}/api/characters/studio/party/create`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cid, sid: _chat.sessionId, name: _chat.char.name, world_id: _chat.char.world_id || '' }),
    });
    const d = await r.json();
    if (!r.ok || !d.ok) throw new Error(d.detail || 'could not open the table');
    _savePartyMark(cid, { code: d.code, role: 'host' });
    _partyStart(cid);
    const members = Object.entries(d.members || {});
    $('party-body').innerHTML = `
      <p class="gm-hint">Friends on your network join from their own account: title screen → <strong>Join a Party</strong> → this code. They play their own hero in <em>this</em> story.</p>
      <div class="party-code" aria-label="Join code">${_esc(d.code)}</div>
      <div class="chronicle-actions"><button class="st-btn small" id="party-copy" type="button">Copy code</button></div>
      <div class="sheet-section"><h3>At the table</h3>
        <ul class="feat-list"><li class="feat-row">👑 You — the host</li>
        ${members.map(([u, m]) => `<li class="feat-row">🎭 ${_esc(m.hero || u)} <em class="prof-bonus">${_esc(u)} · ${_esc(m.cls || '')}</em></li>`).join('')}</ul>
        ${members.length ? '' : '<p class="gm-hint">No one seated yet — the list fills in as they join.</p>'}</div>`;
    $('party-copy')?.addEventListener('click', () => { try { navigator.clipboard.writeText(d.code); $('party-copy').textContent = 'Copied ✔'; } catch (e) {} });
  } catch (e) {
    $('party-body').innerHTML = `<p class="gm-hint">⚠ ${_esc(e.message || e)}</p>`;
  }
}

// Guest: join a friend's table from the title screen / worlds view.
export function openJoinParty() {
  const modal = $('studio-modal'); if (!modal) return;
  modal.classList.remove('hidden');
  document.body.classList.add('studio-open');
  const cv = $('studio-bg-canvas'); if (cv) startAmbient(cv, 'arcane');
  let ov = $('studio-join-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-join-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const classOpts = Object.keys(CLASS_PRESETS).map(c => `<option value="${c}">${c}${CLASS_PRESETS[c].caster ? ' ✦' : ''}</option>`).join('');
  const p = _loadPlayer() || {};
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Join a party">
    <div class="chronicle-bar"><h2>🔗 Join a party</h2><button class="studio-close" id="join-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Your friend's table has a 6-letter code. You'll play <strong>your own hero</strong> inside <em>their</em> story — same world, same fire.</p>
      <div class="sheet-grid2">
        <label class="sf">Join code<input type="text" id="join-code" maxlength="6" placeholder="ABC123" style="text-transform:uppercase;letter-spacing:.2em"></label>
        <label class="sf">Your hero's name<input type="text" id="join-hero" value="${_esc(p.name || '')}" placeholder="Rowan"></label>
      </div>
      <label class="sf">Class<select id="join-class" class="studio-select">${classOpts}</select></label>
      <div class="chronicle-actions"><button class="st-btn primary" id="join-go" type="button">Take a seat ›</button></div>
      <div id="join-result"></div>
    </div></div>`;
  ov.style.display = 'flex';
  $('join-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  if (p.cls && CLASS_PRESETS[p.cls]) $('join-class').value = p.cls;
  $('join-go').addEventListener('click', async () => {
    const code = ($('join-code').value || '').trim().toUpperCase();
    const hero = ($('join-hero').value || '').trim();
    if (!code || !hero) return;
    const btn = $('join-go'); btn.disabled = true; btn.textContent = 'Taking a seat…';
    try {
      const r = await fetch(`${API_BASE}/api/characters/studio/party/join`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code, hero, cls: $('join-class').value }),
      });
      const d = await r.json();
      if (!r.ok || !d.ok) throw new Error(d.detail || 'No table with that code.');
      // Wire the shared campaign into this account's plumbing: a local template
      // (cosmetic — GM face/name), the shared session mapping, the party mark.
      await fetch(`${API_BASE}/api/characters/studio/save`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: d.cid, name: d.name || 'Shared adventure', personality: 'Dungeon Master (shared campaign — the host\'s Game Master runs this table).', relationship: 'Dungeon Master', world_id: d.world_id || '' }),
      });
      const map = _loadMap(); map[d.cid] = d.sid; _saveMap(map);
      _savePartyMark(d.cid, { code: d.code, role: 'guest', hero: d.hero, host: d.host });
      ov.style.display = 'none';
      await loadCharacters();
      await _hydrateRel();
      const saved = _chars.find(x => x.id === d.cid);
      renderWorlds(); switchView('worlds');
      if (saved) openChat(saved);
    } catch (e) {
      btn.disabled = false; btn.textContent = 'Take a seat ›';
      $('join-result').innerHTML = `<p class="gm-hint">⚠ ${_esc(e.message || e)}</p>`;
    }
  });
}

// ── The Lorebook: bestiary, grimoire, classes, and this world ────────────────
// A player-facing reference with conjurable art. Entry art is generated once
// and cached globally (all campaigns share one bestiary's pictures).
const LOREART_KEY = 'studio-lore-art';
function _loadLoreArt() { try { return JSON.parse(localStorage.getItem(LOREART_KEY) || '{}') || {}; } catch { return {}; } }
function _saveLoreArt(m) { try { localStorage.setItem(LOREART_KEY, JSON.stringify(m)); } catch {} _pushState('_global', 'loreart', m); }
let _loreTab = 'beasts', _loreSel = '';
const _loreArtBusy = new Set();

// Setting-specific creatures the Worldsmith forged for the current world.
function _worldCreatures() {
  const wid = (_chat.char && _chat.char.world_id) || (_world && _world.id) || '';
  const w = wid ? getWorld(wid) : null;
  return (w && w.creatures) || [];
}
function _bestiaryFor(name) {
  const n = (name || '').toLowerCase().trim(); if (!n) return null;
  const pool = _worldCreatures().concat(BESTIARY);
  // 1) exact name; 2) the foe name CONTAINS an entry name — prefer the longest
  // (most specific) so "Dire Wolf" beats "Wolf"; 3) last resort, an entry name
  // contains the foe word ("rat" → "Giant Rat").
  const exact = pool.find(e => e.name.toLowerCase() === n); if (exact) return exact;
  let best = null, len = 0;
  for (const e of pool) { const en = e.name.toLowerCase(); if (n.includes(en) && en.length > len) { best = e; len = en.length; } }
  return best || pool.find(e => e.name.toLowerCase().includes(n)) || null;
}

function openLorebook(tab, sel) {
  const modal = $('studio-modal'); if (!modal) return;
  if (tab) _loreTab = tab;
  if (sel !== undefined) _loreSel = sel;
  let ov = $('studio-lore-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-lore-overlay'; ov.className = 'map-overlay'; modal.appendChild(ov); }
  const wid = (_chat.char && _chat.char.world_id) || (_world && _world.id) || '';
  const tabs = [['beasts', '🐉 Bestiary'], ['spells', '✨ Grimoire'], ['classes', '🛡 Classes'], ['rules', '📜 Rules'], ['world', '🗺 This World']]
    .map(([k, label]) => `<button class="map-tab${_loreTab === k ? ' on' : ''}" data-loretab="${k}" type="button">${label}</button>`).join('');
  ov.innerHTML = `<div class="map-sheet lore-sheet" role="dialog" aria-modal="true" aria-label="Lorebook">
    <div class="map-bar"><div class="map-tabs">${tabs}</div><button class="studio-close" id="lore-close" type="button" aria-label="Close">✕</button></div>
    <div class="lore-body">
      <div class="lore-side">
        <input type="search" id="lore-search" class="lore-search" placeholder="Filter…" aria-label="Filter entries">
        <button type="button" class="st-btn small ghost" id="lore-illustrate" style="margin-bottom:6px" title="Queue pictures for every entry on this tab that doesn't have one yet">🎨 Illustrate all</button>
        <div class="lore-list" id="lore-list"></div>
      </div>
      <div class="lore-detail" id="lore-detail"></div>
    </div>
  </div>`;
  ov.style.display = 'flex';
  $('lore-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  ov.querySelectorAll('[data-loretab]').forEach(b => b.addEventListener('click', () => openLorebook(b.dataset.loretab, '')));
  const list = $('lore-list'), detail = $('lore-detail');
  const art = _loadLoreArt();

  // Shared art pane: cached picture, or a conjure button that bakes one.
  const artPane = (slug, prompt, alt) => art[slug]
    ? `<img class="lore-art" src="${_esc(art[slug])}" alt="${_esc(alt)}">`
    : `<div class="lore-art lore-art-empty"><button class="st-btn small" data-loreart="${_esc(slug)}" data-prompt="${_esc(prompt)}" type="button">${_loreArtBusy.has(slug) ? 'Conjuring…' : '✨ Conjure a picture'}</button></div>`;
  const wireArt = () => detail.querySelectorAll('[data-loreart]').forEach(b => b.addEventListener('click', async () => {
    const slug = b.dataset.loreart; if (_loreArtBusy.has(slug)) return;
    _loreArtBusy.add(slug); b.disabled = true; b.textContent = 'Conjuring…';
    try {
      const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt: b.dataset.prompt, size: '768x768' }),
      });
      const d = await r.json();
      if (d.ok && d.image_url) { const m = _loadLoreArt(); m[slug] = d.image_url; _saveLoreArt(m); }
    } catch (e) { /* art is decorative */ }
    _loreArtBusy.delete(slug);
    const still = $('studio-lore-overlay'); if (still && still.style.display === 'flex') openLorebook();
  }));

  if (_loreTab === 'beasts') {
    // This world's own forged creatures lead; the shared bestiary follows.
    const wc = _worldCreatures();
    const wcRows = wc.length
      ? `<p class="lore-group">Creatures of this world</p>` + wc.map(e =>
          `<button class="lore-row${_loreSel === e.slug ? ' on' : ''}" data-loresel="${_esc(e.slug)}" type="button">✦ ${_esc(e.name)}</button>`).join('')
      : '';
    const local = (e) => (e.worlds.includes(wid) || e.worlds.includes('_')) ? 0 : 1;
    const tiers = ['minor', 'standard', 'dire'];
    list.innerHTML = wcRows + tiers.map(t => {
      const rows = BESTIARY.filter(e => e.tier === t).sort((a, b) => local(a) - local(b))
        .map(e => `<button class="lore-row${_loreSel === e.slug ? ' on' : ''}${local(e) ? ' faraway' : ''}" data-loresel="${e.slug}" type="button">${_esc(e.name)}${local(e) ? ' <em>· elsewhere</em>' : ''}</button>`).join('');
      return `<p class="lore-group">${BESTIARY_TIERS[t]}</p>${rows}`;
    }).join('');
    const e = wc.find(x => x.slug === _loreSel) || BESTIARY.find(x => x.slug === _loreSel)
      || wc[0] || BESTIARY.find(x => !((x.worlds.includes(wid) || x.worlds.includes('_')) ? 0 : 1));
    if (e) {
      _loreSel = e.slug;
      detail.innerHTML = `
        ${artPane(e.slug, e.art, e.name)}
        <h3 class="lore-h">${_esc(e.name)} <span class="prof-bonus">${BESTIARY_TIERS[e.tier]}</span></h3>
        <p class="lore-p">${_esc(e.desc)}</p>
        <div class="lore-fact weak"><strong>⚠ Weakness</strong> ${_esc(e.weakness)}</div>
        <div class="lore-fact"><strong>⚔ In a fight</strong> ${_esc(e.tactics)}</div>
        <p class="gm-hint">The GM knows this page — exploit the weakness and it counts.</p>`;
    } else detail.innerHTML = '';
  } else if (_loreTab === 'spells') {
    const lvls = [[0, 'Cantrips — always ready'], [1, 'First circle'], [2, 'Second circle']];
    list.innerHTML = lvls.map(([l, label]) => {
      const rows = SPELLS.filter(s => s.level === l)
        .map(s => `<button class="lore-row${_loreSel === s.slug ? ' on' : ''}" data-loresel="${s.slug}" type="button">${_esc(s.name)}</button>`).join('');
      return `<p class="lore-group">${label}</p>${rows}`;
    }).join('');
    const s = SPELLS.find(x => x.slug === _loreSel) || SPELLS[0];
    if (s) {
      _loreSel = s.slug;
      const mine = _isDM(_chat.char) && (_loadSheet(_chat.char.id).spells || []).some(x => x.name.toLowerCase() === s.name.toLowerCase());
      detail.innerHTML = `
        ${artPane(s.slug, `fantasy spell illustration, ${s.name}, ${s.desc.split('.')[0]}, arcane energy, dramatic, no text`, s.name)}
        <h3 class="lore-h">${_esc(s.name)} <span class="prof-bonus">${s.level ? `Level ${s.level}` : 'Cantrip'} · ${_esc(s.school)}</span></h3>
        <p class="lore-p">${_esc(s.desc)}</p>
        <div class="lore-fact"><strong>🧙 Cast by</strong> ${s.classes.join(', ')}</div>
        ${mine ? '<div class="lore-fact weak"><strong>✔</strong> In your spellbook.</div>' : ''}
        ${(_isDM(_chat.char) && !mine) ? `<button class="st-btn small" id="lore-learn" type="button">＋ Add to my spellbook</button>` : ''}`;
      $('lore-learn')?.addEventListener('click', () => {
        const cid = _chat.char.id; const sh = _loadSheet(cid);
        sh.spells = (sh.spells || []).concat([{ name: s.name, level: s.level }]); _saveSheet(cid, sh);
        _appendBubble('me', `📖 *You copy **${_esc(s.name)}** into your repertoire.*`); _scrollChat();
        openLorebook();
      });
    } else detail.innerHTML = '';
  } else if (_loreTab === 'classes') {
    const names = Object.keys(CLASS_PRESETS);
    list.innerHTML = `<p class="lore-group">The twelve callings</p>` + names
      .map(n => `<button class="lore-row${_loreSel === n ? ' on' : ''}" data-loresel="${n}" type="button">${(CLASS_LORE[n] || {}).icon || ''} ${n}${CLASS_PRESETS[n].caster ? ' <em>· caster</em>' : ''}</button>`).join('');
    const n = CLASS_PRESETS[_loreSel] ? _loreSel : names[0];
    _loreSel = n;
    const p = CLASS_PRESETS[n], lore = CLASS_LORE[n] || {};
    const feats = Object.entries(CLASS_FEATURES[n] || {})
      .map(([lvl, fs]) => `<div class="lore-fact"><strong>Lv ${lvl}</strong> ${fs.map(_esc).join(' · ')}</div>`).join('');
    const spells = SPELLS.filter(s => s.classes.includes(n)).map(s => s.name).join(', ');
    detail.innerHTML = `
      ${artPane('class-' + n.toLowerCase(), `fantasy character class illustration, a heroic ${n}, full figure, dynamic pose, painterly, no text`, n)}
      <h3 class="lore-h">${lore.icon || ''} ${n} <span class="prof-bonus">d${p.hitDie} hit die · ${p.saves.join(' & ')} saves${p.caster ? ' · spellcaster' : ''}</span></h3>
      <p class="lore-p">${_esc(lore.blurb || '')}</p>
      <div class="lore-fact"><strong>🎯 Trained skills</strong> ${p.skills.map(_titleCase).join(', ')}</div>
      <div class="lore-fact"><strong>🎒 Starting kit</strong> ${(_CLASS_KIT[n] || []).join(', ') || '—'}</div>
      ${spells ? `<div class="lore-fact"><strong>✨ Signature spells</strong> ${_esc(spells)}</div>` : ''}
      <p class="lore-group" style="margin-top:12px">Features by level</p>
      ${feats || '<p class="gm-hint">A path of pure fundamentals.</p>'}`;
  } else if (_loreTab === 'rules') {
    // How the game actually works — checks, combat, conditions, rests, feats.
    const items = [['checks', '🎲 Checks & rolls'], ['combat', '⚔ Combat'], ['conditions', '💫 Conditions'], ['resting', '⛺ Resting & death'], ['feats', '🏅 Feats']];
    list.innerHTML = `<p class="lore-group">The rules of the table</p>` + items
      .map(([k, label]) => `<button class="lore-row${_loreSel === k ? ' on' : ''}" data-loresel="${k}" type="button">${label}</button>`).join('');
    const k = items.some(([x]) => x === _loreSel) ? _loreSel : 'checks';
    _loreSel = k;
    const fact = (t, b) => `<div class="lore-fact"><strong>${t}</strong> ${b}</div>`;
    if (k === 'checks') {
      detail.innerHTML = `<h3 class="lore-h">Checks & rolls <span class="prof-bonus">d20 + modifier vs DC</span></h3>
        <p class="lore-p">When an outcome is uncertain, the GM calls for a check: roll a d20, add the right ability modifier (and your proficiency bonus if you're trained), and meet or beat the Difficulty Class.</p>
        ${fact('Difficulty Classes', 'Easy 10 · Medium 15 · Hard 20 · Very Hard 25.')}
        ${fact('Advantage / disadvantage', 'Roll two d20s — take the higher (advantage) or lower (disadvantage). They don’t stack, and one of each cancels out.')}
        ${fact('Natural 20 / 1', 'A 20 is a critical triumph; a 1 is a fumble. On attacks, a 20 doubles the damage dice.')}
        ${fact('Proficiency', 'Trained skills and saving throws add your proficiency bonus (+2 at level 1, rising with level).')}
        ${fact('Inspiration', 'The GM can award Inspiration for great play — spend it for advantage on any roll.')}
        ${fact('Passive Perception', '10 + WIS modifier (+ proficiency if trained) — what you notice without looking.')}`;
    } else if (k === 'combat') {
      detail.innerHTML = `<h3 class="lore-h">Combat <span class="prof-bonus">initiative · turns · rounds</span></h3>
        <p class="lore-p">When a fight starts, everyone rolls initiative (d20 + DEX). On your turn you get a move, an action, and possibly a bonus action.</p>
        ${fact('⚔ Attack', 'd20 + ability modifier + proficiency vs the target’s Armor Class. Hit: roll your weapon’s damage dice + ability modifier.')}
        ${fact('Actions', 'Attack · Cast a spell · Dash (double move) · Disengage (leave reach safely) · Dodge (attacks on you have disadvantage) · Help (give an ally advantage) · Hide · Use an item.')}
        ${fact('🏃 Flee', 'Breaking from melee invites a hit — Disengage first, or make a DEX check to slip away clean.')}
        ${fact('Cover', 'Half cover +2 AC · three-quarters +5 · full cover can’t be targeted.')}
        ${fact('Concentration', 'One concentration spell at a time. Take damage while holding one → CON save (DC 10 or half the damage) or it drops.')}
        ${fact('Death', 'At 0 HP you fall — see Resting & death.')}`;
    } else if (k === 'conditions') {
      detail.innerHTML = `<h3 class="lore-h">Conditions <span class="prof-bonus">what ails you does this</span></h3>
        <p class="lore-p">Conditions land from spells, venom, and bad luck. They expire with time, saves, or a cure — the sheet tracks yours.</p>
        ${Object.entries(_CONDITION_DESC).map(([nm, d]) => fact(_titleCase(nm), _esc(d))).join('')}`;
    } else if (k === 'resting') {
      detail.innerHTML = `<h3 class="lore-h">Resting & death <span class="prof-bonus">recovery has a price</span></h3>
        ${fact('🌙 Short rest', 'An hour’s breather: spend Hit Dice to heal, recover short-rest features (Second Wind, Ki…). Interruptions are possible in dangerous places.')}
        ${fact('⛺ Long rest', 'A night’s sleep: full HP, half your Hit Dice back, spell slots and long-rest features restored, conditions cleared. Once per day, and the wilds may interrupt.')}
        ${fact('💀 Death saves', 'At 0 HP: roll a bare d20 each turn. 10+ is a success, three successes stabilize you; three failures are death. A natural 20 gets you up on 1 HP; a natural 1 counts twice.')}
        ${fact('Healing', 'Potions, spells, and a stabilized ally regaining 1 HP after 1d4 hours.')}`;
    } else {
      detail.innerHTML = `<h3 class="lore-h">Feats <span class="prof-bonus">2 ASI points each at a level-up</span></h3>
        <p class="lore-p">At an ability-score level (4, 8, 12, 16, 19) you can trade 2 of your 2 ASI points for a feat instead of raising scores.</p>
        ${Object.entries(FEATS).map(([nm, f]) => fact('🏅 ' + nm, _esc(f.desc))).join('')}`;
    }
  } else {
    // This world: lore, places, factions, cast, and who you can be.
    const w = wid ? getWorld(wid) : null;
    const cid = _chat.char && _chat.char.id;
    const ws = cid ? _loadWorldS(cid) : { places: [], factions: [] };
    const items = [['lore', w ? w.name : 'The world'], ['backgrounds', 'Backgrounds']];
    list.innerHTML = `<p class="lore-group">Reference</p>` + items
      .map(([k, label]) => `<button class="lore-row${_loreSel === k ? ' on' : ''}" data-loresel="${k}" type="button">${_esc(label)}</button>`).join('');
    const k = (_loreSel === 'backgrounds') ? 'backgrounds' : 'lore';
    _loreSel = k;
    if (k === 'backgrounds') {
      detail.innerHTML = `<h3 class="lore-h">Backgrounds <span class="prof-bonus">who you were before</span></h3>
        <p class="lore-p">Chosen when you create a hero. Each grants two trained skills and gives the GM a thread to pull.</p>
        ${Object.entries(BACKGROUNDS).map(([b, v]) => `<div class="lore-fact"><strong>${b}</strong> ${_titleCase(v.skills.join(' & '))} — ${_esc(v.line)}.</div>`).join('')}`;
    } else if (w) {
      let bg = ''; try { bg = localStorage.getItem(BACKDROP_KEY(wid)) || ''; } catch {}
      detail.innerHTML = `
        ${bg ? `<img class="lore-art" src="${_esc(bg)}" alt="${_esc(w.name)}">` : ''}
        <h3 class="lore-h">${_esc(w.name)} <span class="prof-bonus">${_esc(w.kind)}</span></h3>
        <p class="lore-p">${_esc(w.lore)}</p>
        ${(ws.places || []).length ? `<p class="lore-group">Known places</p>` + ws.places.map(pl => `<div class="lore-fact"><strong>${_PIN_ICON[pl.kind] || '📍'} ${_esc(pl.name)}</strong> ${_esc(pl.note || '')}${pl.shop ? ` <em>(trades: ${_esc(pl.shop)})</em>` : ''}</div>`).join('') : ''}
        ${(ws.factions || []).length ? `<p class="lore-group">Factions</p>` + ws.factions.map(f => `<div class="lore-fact"><strong>⚑ ${_esc(f.name)}</strong> <em>${_esc(f.standing || 'neutral')}</em> ${_esc(f.note || '')}</div>`).join('') : ''}
        ${(w.cast || []).length ? `<p class="lore-group">Notable folk</p>` + w.cast.map(c => `<div class="lore-fact"><strong>${_esc(c.name)}</strong> ${_esc(c.role || '')}</div>`).join('') : ''}`;
    } else {
      detail.innerHTML = `<p class="gm-hint">Enter a world and its lore gathers here.</p>`;
    }
  }
  // "Illustrate all": queue every missing picture on the current tab through
  // the forge queue (one GPU, sequential, visible progress) — no per-entry
  // clicking. Lore art caches globally, so this is a once-ever cost per tab.
  $('lore-illustrate')?.addEventListener('click', () => {
    const have = _loadLoreArt();
    let entries = [];
    if (_loreTab === 'beasts') {
      entries = _worldCreatures().map(e => ({ slug: e.slug, prompt: e.art || `${e.name}, ${e.desc || ''}, creature concept art, no text`, label: e.name }))
        .concat(BESTIARY.filter(e => e.worlds.includes(wid) || e.worlds.includes('_')).map(e => ({ slug: e.slug, prompt: e.art, label: e.name })));
    } else if (_loreTab === 'spells') {
      entries = SPELLS.map(s => ({ slug: s.slug, prompt: `fantasy spell illustration, ${s.name}, ${s.desc.split('.')[0]}, arcane energy, dramatic, no text`, label: s.name }));
    } else if (_loreTab === 'classes') {
      entries = Object.keys(CLASS_PRESETS).map(n => ({ slug: 'class-' + n.toLowerCase(), prompt: `fantasy character class illustration, a heroic ${n}, full figure, dynamic pose, painterly, no text`, label: n }));
    }
    const missing = entries.filter(e => e.slug && !have[e.slug]);
    if (!missing.length) { _toast('🎨 Every entry on this tab already has a picture.'); return; }
    _runForgeQueue('the Lorebook', missing.map(e => ({
      label: e.label,
      run: async () => {
        const url = await _genArt(e.prompt, '768x768');
        if (url) { const m = _loadLoreArt(); m[e.slug] = url; _saveLoreArt(m); }
      },
    })));
    _toast(`🎨 Illustrating ${missing.length} entr${missing.length === 1 ? 'y' : 'ies'} in the background — keep playing.`);
  });
  list.querySelectorAll('[data-loresel]').forEach(b => b.addEventListener('click', () => openLorebook(undefined, b.dataset.loresel)));
  // Live filter — hides rows (and emptied groups) without re-rendering, so the
  // box keeps focus while you type.
  const search = $('lore-search');
  if (search) search.addEventListener('input', () => {
    const q = search.value.trim().toLowerCase();
    list.querySelectorAll('.lore-row').forEach(r => { r.style.display = (!q || r.textContent.toLowerCase().includes(q)) ? '' : 'none'; });
    list.querySelectorAll('.lore-group').forEach(g => {
      let sib = g.nextElementSibling, any = false;
      while (sib && !sib.classList.contains('lore-group')) { if (sib.style.display !== 'none') any = true; sib = sib.nextElementSibling; }
      g.style.display = any ? '' : 'none';
    });
  });
  wireArt();
}

// Themed random-encounter tables — rest interruptions and road trouble pull
// from the bestiary so the lorebook is always relevant.
const ENCOUNTERS = {
  embervale: ['Goblin', 'Wolf', 'Bandit', 'Skeleton', 'Giant Spider', 'Ghoul', 'Cultist', 'Hobgoblin'],
  neonspire: ['Street Thug', 'Scav Drone', 'Gang Enforcer', 'Combat Drone', 'Bandit', 'Cultist'],
  everyday:  ['Street Thug', 'Giant Rat', 'Wolf', 'Bandit'],
  _:         ['Bandit', 'Wolf', 'Goblin', 'Cultist', 'Giant Rat', 'Street Thug'],
};
function _randEncounter() {
  const wid = (_chat.char && _chat.char.world_id) || '';
  // A forged world's own creatures haunt its nights (mixed with the classics).
  const wc = _worldCreatures().map(c => c.name);
  const list = wc.length ? wc.concat(ENCOUNTERS._ .slice(0, 2)) : (ENCOUNTERS[wid] || ENCOUNTERS._);
  return list[Math.floor(Math.random() * list.length)];
}

// ── Player notepad (handwritten) ────────────────────────────────────────────
const NOTES_KEY = (cid) => `studio-notes-${cid}`;
function _loadNotes(cid) { try { return localStorage.getItem(NOTES_KEY(cid)) || ''; } catch { return ''; } }
function _saveNotes(cid, v) { try { localStorage.setItem(NOTES_KEY(cid), v); } catch {} _pushState(cid, 'notes', v); }
function openNotes() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id;
  let ov = $('studio-notes-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-notes-overlay'; ov.className = 'notes-overlay'; modal.appendChild(ov); }
  ov.innerHTML = `<div class="notepad notebook" role="dialog" aria-modal="true" aria-label="Your notes">
    <div class="nb-rings" aria-hidden="true">${Array.from({ length: 12 }, () => '<span></span>').join('')}</div>
    <div class="notepad-top"><span class="notepad-title">📓 My Notes</span><button class="notepad-close" id="notes-close" type="button" aria-label="Close">✕</button></div>
    <textarea id="notes-area" class="notepad-area nb-lines" placeholder="Jot down clues, names, plans…">${_esc(_loadNotes(cid))}</textarea>
  </div>`;
  ov.style.display = 'flex';
  $('notes-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  const ta = $('notes-area'); ta.addEventListener('input', () => _saveNotes(cid, ta.value));
  setTimeout(() => ta.focus(), 40);
}

// ── Campaign memory / lorebook (Phase A) ────────────────────────────────────
const MEM_KEY = (cid) => `studio-mem-${cid}`;
function _loadMem(cid) { try { return { summary: '', facts: [], at: 0, ...(JSON.parse(localStorage.getItem(MEM_KEY(cid)) || 'null') || {}) }; } catch { return { summary: '', facts: [], at: 0 }; } }
function _saveMem(cid, m) { try { localStorage.setItem(MEM_KEY(cid), JSON.stringify(m)); } catch {} _pushState(cid, 'mem', m); }
function _memText(cid) {
  const m = _loadMem(cid);
  if (!m.summary && !(m.facts && m.facts.length)) return '';
  let t = m.summary || '';
  if (m.facts && m.facts.length) t += (t ? ' ' : '') + 'Key facts: ' + m.facts.map(f => '• ' + f).join(' ');
  return t.slice(0, 2000);
}
function _meCount() { return document.querySelectorAll('#studio-thread .rp-msg.me').length; }
// Serial background-extractor queue: only one LLM extraction runs at a time, so
// they don't storm the single local model into gateway timeouts.
let _extractChain = Promise.resolve();
function _enqueueExtractor(fn) {
  _extractChain = _extractChain.then(() => Promise.resolve().then(fn).catch(() => {})).catch(() => {});
  return _extractChain;
}
async function _updateMemory(cid) {
  if (!_chat.char) return;
  try {
    const transcript = await _fetchTranscript();
    if (!transcript.length) return;
    const m = _loadMem(cid);
    const res = await fetch(`${API_BASE}/api/characters/studio/memory`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ character_name: _chat.char.name, transcript, memory: _memText(cid), model: _modelLabel() }),
    });
    const d = await res.json();
    if (d.ok) {
      _saveMem(cid, { summary: d.summary || m.summary, facts: Array.isArray(d.facts) ? d.facts : (m.facts || []), at: _meCount() });
      const ov = $('studio-mem-overlay');
      if (ov && ov.style.display === 'flex') openMemory();   // refresh panel if open
    }
  } catch {}
}

// ── Pinpoint campaign memory (§4.C) ──────────────────────────────────────────
// Each turn we store the exchange as an embedded "beat" and, before the next
// turn, recall the beats most relevant to what the player just did — injected
// into the GM context so long stories stay consistent. No per-turn LLM call
// (embeddings are local + fast), so it doesn't 502 like the summary path did.
// The user-editable Key Facts (_memText) still ride alongside.
function _stripTags(s) { return (s || '').replace(/^\s*(\[[^\]]*\]\s*)+/, '').trim(); }
async function _recallBeats(cid, query) {
  const q = _stripTags(query);
  if (!q) return '';
  const ctl = new AbortController();
  const t = setTimeout(() => { try { ctl.abort(); } catch {} }, 4000);  // a cold embed model must not stall the turn
  try {
    const res = await fetch(`${API_BASE}/api/characters/studio/memory/recall`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cid, query: q, k: 5 }), signal: ctl.signal,
    });
    const d = await res.json();
    if (!d.ok || !Array.isArray(d.beats) || !d.beats.length) return '';
    return d.beats.map(b => (b.day ? `(Day ${b.day}) ` : '') + b.text).join(' | ').slice(0, 1500);
  } catch { return ''; }
  finally { clearTimeout(t); }
}
function _storeBeat(cid, framed, reply) {
  const gm = (reply || '').trim();
  if (!gm) return;
  const act = _stripTags(framed);
  const text = ((act ? `You: ${act}\n` : '') + gm).slice(0, 1500);
  fetch(`${API_BASE}/api/characters/studio/memory/beat`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ cid, text, day: (_loadClock(cid).day || 0) }),
  }).catch(() => {});
}

function openMemory() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const m = _loadMem(cid);
  let ov = $('studio-mem-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-mem-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const facts = (m.facts && m.facts.length)
    ? m.facts.map((f, i) => `<li class="mem-fact"><span>${_esc(f)}</span><button class="rm" data-rmfact="${i}" type="button" aria-label="Remove">×</button></li>`).join('')
    : '<li class="mem-fact empty">Nothing yet — facts fill in as you play, or add your own.</li>';
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Campaign memory">
    <div class="chronicle-bar"><h2>Campaign memory</h2><button class="studio-close" id="mem-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">What the Game Master remembers about your story. It updates itself as you play; edit anything to steer it.</p>
      <label class="sf">Story so far<textarea id="mem-summary" rows="4" placeholder="The running recap…">${_esc(m.summary || '')}</textarea></label>
      <div class="sheet-section"><h3>Key facts</h3><ul class="mem-facts">${facts}</ul>
        <div class="add-row"><input type="text" id="mem-add" placeholder="Add a fact the GM should remember…"><button id="mem-add-btn" class="st-btn small" type="button">Add</button></div></div>
      <div class="chronicle-actions"><button class="st-btn" id="mem-refresh" type="button">↻ Update from the story</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  $('mem-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  $('mem-summary').addEventListener('input', () => { const mm = _loadMem(cid); mm.summary = $('mem-summary').value; _saveMem(cid, mm); });
  const addFact = () => { const v = ($('mem-add').value || '').trim(); if (!v) return; const mm = _loadMem(cid); mm.facts = mm.facts || []; mm.facts.push(v); _saveMem(cid, mm); openMemory(); };
  $('mem-add-btn').addEventListener('click', addFact);
  $('mem-add').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addFact(); } });
  ov.querySelectorAll('[data-rmfact]').forEach(b => b.addEventListener('click', () => { const mm = _loadMem(cid); mm.facts.splice(Number(b.dataset.rmfact), 1); _saveMem(cid, mm); openMemory(); }));
  const rb = $('mem-refresh');
  rb.addEventListener('click', async () => { rb.disabled = true; rb.textContent = 'Updating…'; await _updateMemory(cid); rb.disabled = false; rb.textContent = '↻ Update from the story'; openMemory(); });
}

// ── Combat tracker (Phase B) ────────────────────────────────────────────────
const COMBAT_KEY = (cid) => `studio-combat-${cid}`;
function _loadCombat(cid) { try { return { active: false, round: 1, turn: 0, combatants: [], ...(JSON.parse(localStorage.getItem(COMBAT_KEY(cid)) || 'null') || {}) }; } catch { return { active: false, round: 1, turn: 0, combatants: [] }; } }
function _saveCombat(cid, c) { try { localStorage.setItem(COMBAT_KEY(cid), JSON.stringify(c)); } catch {} _pushState(cid, 'combat', c); }
function _initiative(sheet) { return 1 + Math.floor(Math.random() * 20) + _mod((sheet.abilities && sheet.abilities.DEX) || 10) + (sheet.featAlert ? 5 : 0); }
function _combatOrder(c) { return [...c.combatants].sort((a, b) => (b.init || 0) - (a.init || 0)); }
// ── Companions: recruited allies who travel and fight beside you ─────────────
// Stored on the sheet (durable with the campaign). Wounds persist between
// fights (synced back at combat end); rests heal them.
function _companions(cid) { return _loadSheet(cid).companions || []; }
function _toggleCompanion(cid, npc) {
  const s = _loadSheet(cid); s.companions = s.companions || [];
  const i = s.companions.findIndex(x => x.name.toLowerCase() === npc.name.toLowerCase());
  if (i >= 0) {
    s.companions.splice(i, 1); _saveSheet(cid, s);
    _renderPartyChips(cid);
    _appendBubble('me', `👋 *${_esc(npc.name)} parts ways with you.*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[${npc.name} leaves my party — we part ways here. Play out a brief farewell that fits our history.]`);
  } else {
    const cls = _companionClass(npc);
    const level = s.level || 1;
    const preset = CLASS_PRESETS[cls] || { hitDie: 8 };
    const hpMax = preset.hitDie + 2 * level;
    const ac = preset.hitDie >= 10 ? 14 : 12;   // martial classes wear real armor
    s.companions.push({ name: npc.name, role: npc.role || '', cls, level, ac, hpMax, hp: hpMax }); _saveSheet(cid, s);
    _renderPartyChips(cid);
    _appendBubble('me', `⚔ *${_esc(npc.name)} joins your party — a level ${level} ${cls}!*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[${npc.name} agrees to travel with me as a companion (a ${cls} by trade). From now on they are at my side: give them a voice in scenes, and they fight alongside me in combat. Play out how the partnership begins.]`);
  }
}
// Hot-seat: a second player's hero rides along as a full-statted party member.
// They act by speaking through the chat (the play-as dropdown carries their
// voice); the GM is told they're a hero, not an NPC.
function _addGuestHero(cid) {
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-guest-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-guest-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const classOpts = Object.keys(CLASS_PRESETS).map(c => `<option value="${c}">${c}${CLASS_PRESETS[c].caster ? ' ✦' : ''}</option>`).join('');
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Add a guest hero">
    <div class="chronicle-bar"><h2>🎭 A second hero joins</h2><button class="studio-close" id="guest-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Hot-seat play: a friend's hero joins your party with real stats and a combat token. They act by typing what they do — the GM treats them as a hero, never a puppet.</p>
      <div class="sheet-grid2">
        <label class="sf">Name<input type="text" id="guest-name" placeholder="Their hero's name"></label>
        <label class="sf">Class<select id="guest-class" class="studio-select">${classOpts}</select></label>
      </div>
      <div class="chronicle-actions"><button class="st-btn primary" id="guest-add" type="button">Join the party ›</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  $('guest-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  $('guest-add').addEventListener('click', () => {
    const name = ($('guest-name').value || '').trim(); if (!name) return;
    const cls = $('guest-class').value || 'Fighter';
    const s = _loadSheet(cid); s.companions = s.companions || [];
    const level = s.level || 1;
    const preset = CLASS_PRESETS[cls] || { hitDie: 8 };
    const hpMax = preset.hitDie + 2 * level;
    s.companions.push({ name, role: 'guest hero', cls, level, ac: preset.hitDie >= 10 ? 14 : 12, hpMax, hp: hpMax, guest: true });
    _saveSheet(cid, s);
    ov.style.display = 'none';
    _renderPartyChips(cid); renderSheetPanel();
    _appendBubble('me', `🎭 *${_esc(name)} the ${cls} takes a seat at the table and joins the party!*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[A second hero joins the adventure: ${name}, a level ${level} ${cls}, played by another person at the table. Treat them as a full hero — they will declare their own actions through our messages. Write them into the current scene now.]`);
  });
}

// A companion's calling, read from who they are in the fiction.
function _companionClass(npc) {
  const t = `${npc.role || ''} ${npc.goal || ''} ${npc.note || ''}`.toLowerCase();
  if (/witch|mage|wizard|scholar|arcan/.test(t)) return 'Wizard';
  if (/priest|cleric|acolyte|healer|counselor|doctor|medic/.test(t)) return 'Cleric';
  if (/thief|fixer|rogue|scoundrel|smuggler|urchin|netrunner|hacker/.test(t)) return 'Rogue';
  if (/hunter|ranger|guide|scout|tracker/.test(t)) return 'Ranger';
  if (/bard|singer|entertainer|performer|musician/.test(t)) return 'Bard';
  if (/druid|shaman|hermit/.test(t)) return 'Druid';
  return 'Fighter';
}
function _partyText(cid) {
  const party = _companions(cid);
  if (!party.length) return '';
  return `The player's party — traveling companions at their side: ${party.map(c => `${c.name}${c.cls ? ` (level ${c.level || 1} ${c.cls}${c.role ? `, ${c.role}` : ''})` : (c.role ? ` (${c.role})` : '')}, ${c.hp}/${c.hpMax} HP${c.guest ? ' — a second HERO controlled by another player at the table; let them act and speak through the player\'s messages' : ''}`).join('; ')}. Give companions voices in scenes and turns in combat, but never control the heroes.`;
}
// Wounds follow companions out of the fight; rests knit them back up.
function _syncCompanionsFromCombat(cid, combatants) {
  const s = _loadSheet(cid); if (!(s.companions || []).length) return;
  let changed = false;
  (combatants || []).forEach(m => {
    if (m.side !== 'ally' || m.id === 'pc') return;
    const c = s.companions.find(x => x.name.toLowerCase() === (m.name || '').toLowerCase());
    if (c) { c.hp = Math.max(0, Math.min(c.hpMax, m.hp)); changed = true; }   // a downed ally stays down (0 HP) until healed/rested — not silently revived
  });
  if (changed) { _saveSheet(cid, s); _renderPartyChips(cid); }
}
function _healCompanions(cid, frac) {
  const s = _loadSheet(cid); if (!(s.companions || []).length) return;
  s.companions.forEach(c => { c.hp = frac >= 1 ? c.hpMax : Math.min(c.hpMax, c.hp + Math.max(1, Math.ceil(c.hpMax * frac))); });
  _saveSheet(cid, s); _renderPartyChips(cid);
}
// Party chips in the chat banner — your companions, visible at a glance.
function _renderPartyChips(cid) {
  const bar = document.querySelector('#studio-chat .cb-chips'); if (!bar) return;
  bar.querySelectorAll('.party-chip').forEach(el => el.remove());
  if (!_isDM(_chat.char)) return;
  _companions(cid).forEach(c => {
    const pct = Math.max(0, Math.min(100, Math.round((c.hp / (c.hpMax || 1)) * 100)));
    const el = document.createElement('button');
    el.type = 'button'; el.className = 'party-chip'; el.title = `${c.name} — ${c.hp}/${c.hpMax} HP (party)`;
    el.innerHTML = `<span class="pc-name">⚔ ${_esc(c.name)}</span><span class="pc-hp"><span class="pc-hpfill${pct <= 35 ? ' low' : ''}" style="width:${pct}%"></span></span>`;
    el.addEventListener('click', openCodex);
    bar.appendChild(el);
  });
}

function _combatContext(cid) {
  const c = _loadCombat(cid);
  if (!c.active || !c.combatants.length) return '';
  const order = _combatOrder(c);
  const cur = order[c.turn % order.length];
  const condStr = (cs) => (cs || []).map(cd => typeof cd === 'string' ? cd : `${cd.name}${cd.rounds != null ? ` (${cd.rounds}r)` : ''}`).join(', ');
  const list = order.map(m => `${m.name} ${m.hp}/${m.hpMax} HP${m.ac ? ` AC${m.ac}` : ''}${m.hp <= 0 ? ' (down)' : ''}${(m.conditions && m.conditions.length) ? ` [${condStr(m.conditions)}]` : ''}`).join('; ');
  const whose = cur ? (cur.id === 'pc' ? "the player's" : `${cur.name}'s`) : '?';
  // The lorebook is canon: known beasts fight (and fall) by their entry.
  const notes = order.filter(m => m.side === 'enemy').map(m => { const e = _bestiaryFor(m.name); return e ? `${e.name} — weakness: ${e.weakness}` : null; }).filter(Boolean);
  return `Combat is active — round ${c.round}, it is ${whose} turn. Combatants: ${list}. Use these exact HP totals and the turn order; call for attack rolls (d20 vs AC) and damage rolls, and tell me when an enemy falls.${notes.length ? ` Bestiary canon (honor these if the player exploits them): ${notes.join(' | ')}.` : ''}`;
}
function toggleCombat() {
  const p = $('studio-combat-panel');
  if (p && p.classList.contains('open')) { p.classList.remove('open'); return; }
  renderCombatPanel();
  _panelEnter('studio-combat-panel', 'fx-combat-in');
}
// What kind of hurt a weapon deals — feeds the bestiary's typed defenses.
function _weaponDmgType(name) {
  const n = (name || '').toLowerCase();
  if (/mace|club|hammer|maul|staff|quarterstaff|flail|fist|bare|cudgel|baton|wrench|pipe/.test(n)) return 'bludgeoning';
  if (/dagger|spear|pike|arrow|bow|crossbow|rapier|dart|lance|pick|needle|stiletto|bolt|bullet|gun|pistol|rifle/.test(n)) return 'piercing';
  if (/torch|flame|fire|brand/.test(n)) return 'fire';
  return 'slashing';   // swords, axes, claws, and everything edged by default
}
// Weapon properties, read from the name (the item model carries a name + die).
// Drives finesse (DEX or STR), versatile (bigger die in two hands), light
// (two-weapon fighting), heavy (Small heroes swing at disadvantage), thrown/reach.
function _weaponProps(name) {
  const n = (name || '').toLowerCase();
  const ranged = /bow|crossbow|sling|dart|gun|pistol|rifle|blaster|thrown/.test(n);
  const finesse = /dagger|rapier|shortsword|whip|scimitar|blade|estoc/.test(n);
  const light = /dagger|shortsword|handaxe|hatchet|scimitar|club|sickle|knife/.test(n);
  const heavy = /greatsword|greataxe|maul|halberd|glaive|pike|claymore|heavy crossbow/.test(n);
  const twoHandedOnly = /greatsword|greataxe|maul|halberd|glaive|claymore|longbow|heavy crossbow|pike/.test(n);
  const thrown = /handaxe|hatchet|javelin|dagger|dart|trident|spear/.test(n);
  const reach = /halberd|glaive|pike|whip|lance/.test(n);
  let versatileDie = null;
  for (const [k, v] of [['longsword', '1d10'], ['battleaxe', '1d10'], ['warhammer', '1d10'], ['quarterstaff', '1d8'], ['trident', '1d8'], ['spear', '1d8'], ['staff', '1d8']]) if (n.includes(k)) { versatileDie = v; break; }
  return { die: _weaponDie(name), versatileDie, ranged, finesse, light, heavy, thrown, reach, twoHandedOnly };
}
function _isSmallRace(s) { return /halfling|gnome|goblin|kobold|imp|sprite|fairy|pixie/.test((s.race || '').toLowerCase()); }
// The hero's action economy for the current round: one Action (two attacks with
// Extra Attack), one Bonus action, one Reaction. Stored on the combat so it
// resets each round (each combatant acts once per round in this model).
function _pcBudget(cc, sheet) {
  // Extra Attack is 2 swings; a Fighter's climbs to 3 at 11th level and 4 at 20th.
  const fLvl = _classLevelOf(sheet, 'Fighter');
  const attacks = fLvl >= 20 ? 4 : fLvl >= 11 ? 3 : ((sheet.features || []).some(f => /extra attack/i.test(f)) ? 2 : 1);
  if (!cc._pcb || cc._pcb.round !== cc.round) cc._pcb = { round: cc.round, attacksLeft: attacks, attacksMax: attacks, bonusUsed: false, reactionUsed: false };
  return cc._pcb;
}
// Two-weapon fighting: a bonus-action strike with the off-hand weapon. No ability
// mod to the damage (that's the whole trade-off) unless the mod is negative.
function _offhandAttack(cid, targetId, offName) {
  const cc = _loadCombat(cid); const foe = cc.combatants.find(x => x.id === targetId);
  if (!foe || foe.hp <= 0) return;
  const s = _loadSheet(cid);
  const props = _weaponProps(offName);
  const abil = (props.finesse && _mod(s.abilities.DEX || 10) > _mod(s.abilities.STR || 10)) ? 'DEX' : 'STR';
  const mod = _mod(s.abilities[abil] || 10) + _profBonus(s);
  const roll = 1 + Math.floor(Math.random() * 20);
  const total = roll + mod, crit = roll === 20, fumble = roll === 1;
  const hit = crit || (!fumble && total >= (foe.ac || 12));
  _animateDie(20, roll, mod, `Off-hand ${_titleCase(offName)}`, () => {
    if (!hit) { _appendBubble('me', `🗡 *Off-hand ${_esc(offName)} — d20 ${roll} ${mod >= 0 ? '+' : ''}${mod} = ${total} → misses.*`); _scrollChat(); renderCombatPanel(); return; }
    const de = _diceExpr(props.die) || { n: 1, sides: 6, mod: 0 };
    let dmg = de.mod + Math.min(0, _mod(s.abilities[abil] || 10));
    for (let i = 0; i < de.n * (crit ? 2 : 1); i++) dmg += 1 + Math.floor(Math.random() * de.sides);
    dmg = Math.max(1, dmg);
    const entry = _bestiaryFor(foe.name); const dtype = _weaponDmgType(offName); let resTag = '';
    if (entry && Array.isArray(entry.vuln) && entry.vuln.includes(dtype)) { dmg *= 2; resTag = ` — **vulnerable to ${dtype}!**`; }
    else if (entry && Array.isArray(entry.resist) && entry.resist.includes(dtype)) { dmg = Math.max(1, Math.ceil(dmg / 2)); resTag = ` *(resists ${dtype})*`; }
    const cc2 = _loadCombat(cid); const f2 = cc2.combatants.find(x => x.id === targetId); if (!f2) return;
    f2.hp = Math.max(0, f2.hp - dmg);
    const fell = f2.hp <= 0; const enemies = cc2.combatants.filter(x => x.side === 'enemy');
    const won = fell && enemies.length && enemies.every(e => e.hp <= 0) && !cc2._won; if (won) cc2._won = true;
    _saveCombat(cid, cc2); _sfx(crit ? 'crit' : 'hit');
    const ohMsg = `🗡 *Off-hand ${_esc(offName)}${crit ? ' — **CRIT!**' : ''} → **${dmg} damage**${resTag}${fell ? ` — the ${_esc(f2.name)} falls!` : ` (${f2.hp}/${f2.hpMax} left)`}.*`;
    _appendBubble('me', ohMsg); _scrollChat();
    renderCombatPanel();
    if (won) { _fxVictory(); setTimeout(() => _finishCombat(cid), 1800); }
    if (_isDM(_chat.char)) {
      if (fell) {   // an off-hand finish deserves the same cinematic question as a main-hand one
        if (won) _chat.hdywtdt = true;
        _howDoYouWantToDoThis(cid, f2.name, offName, ohMsg, won);
      } else _streamAssistant(`[My off-hand ${offName} hit for ${dmg}.]`);
    }
  });
}

// ── Player combat actions: a real attack loop, not just narration ───────────
// d20 + ability mod + proficiency + weapon bonus vs the foe's AC (or a fair
// DC 12 when the GM hasn't revealed it). Hits roll the weapon's own dice,
// crits double them, damage lands on the token, victory triggers itself.
function _playerAttack(cid, targetId) {
  if (_chat.streaming) return;
  const cc = _loadCombat(cid); const foe = cc.combatants.find(x => x.id === targetId);
  if (!foe || foe.hp <= 0) return;
  const s = _loadSheet(cid); const inv = _loadInv(cid);
  // Action economy: your Attack action is spent (two swings with Extra Attack).
  const budget = _pcBudget(cc, s);
  if (budget.attacksLeft <= 0) { _toast('⚔ Your action is spent — press Next › to end your turn.'); return; }
  budget.attacksLeft -= 1; _saveCombat(cid, cc);
  const wpn = _equippedItem(inv, 'weapon');
  const off = _equippedItem(inv, 'offhand');
  const wname = wpn ? wpn.name : 'bare fists';
  const props = _weaponProps(wname);
  const ranged = props.ranged;
  const finesse = props.finesse;
  const abil = (ranged || (finesse && _mod(s.abilities.DEX || 10) > _mod(s.abilities.STR || 10))) ? 'DEX' : 'STR';
  const mod = _mod(s.abilities[abil] || 10) + _profBonus(s) + ((wpn && wpn.atk) || 0);
  // Heavy weapons are unwieldy for Small heroes → attack at disadvantage.
  const heavyPenalty = props.heavy && _isSmallRace(s);
  const r1 = 1 + Math.floor(Math.random() * 20), r2 = 1 + Math.floor(Math.random() * 20);
  const roll = heavyPenalty ? Math.min(r1, r2) : r1;
  // A versatile weapon swung in two hands (nothing in the off-hand) rolls bigger.
  const twoHanded = !off && !!props.versatileDie;
  // Two-weapon fighting: a light off-hand weapon grants a bonus-action strike
  // (only if your bonus action is still free this turn).
  const twoWeapon = !budget.bonusUsed && off && off.type === 'weapon' && props.light && _weaponProps(off.name).light;
  // Champion fighters crit on 19s too — their whole path is improved criticals.
  const total = roll + mod, crit = roll === 20 || (roll === 19 && _isSubclass(s, 'Champion')), fumble = roll === 1;
  const targetAC = foe.ac || 12;
  const hit = crit || (!fumble && total >= targetAC);
  const gripTag = twoHanded ? ' (two-handed)' : '';
  const dvTag = heavyPenalty ? ' *(disadvantage — heavy weapon)*' : '';
  _animateDie(20, roll, mod, `${_titleCase(wname)} attack`, () => {
    if (!hit) {
      const msg = `⚔ *You attack the ${_esc(foe.name)} with your ${_esc(wname)}${gripTag} — d20 ${roll} ${mod >= 0 ? '+' : ''}${mod} = **${total}**${foe.ac ? ` vs AC ${foe.ac}` : ''}${dvTag}${fumble ? ' — a FUMBLE' : ''} → a miss.*`;
      _appendBubble('me', msg); _scrollChat();
      if (twoWeapon) { const cb = _loadCombat(cid); if (cb._pcb) cb._pcb.bonusUsed = true; _saveCombat(cid, cb); setTimeout(() => _offhandAttack(cid, targetId, off.name), 700); }
      else if (_isDM(_chat.char)) _streamAssistant(msg);
      renderCombatPanel();
      return;
    }
    const de = _diceExpr(twoHanded ? props.versatileDie : ((wpn && wpn.dmg) || props.die || '1d4')) || { n: 1, sides: 4, mod: 0 };
    let dmg = de.mod + Math.max(0, _mod(s.abilities[abil] || 10));
    const nDice = de.n * (crit ? 2 : 1);   // crit doubles the dice
    for (let i = 0; i < nDice; i++) dmg += 1 + Math.floor(Math.random() * de.sides);
    // A raging Barbarian hits harder — the feature promises +2 melee damage.
    if (!ranged && (s.conditions || []).some(cd => /raging/i.test(typeof cd === 'string' ? cd : (cd.name || '')))) dmg += 2;
    // Hunter's Colossus Slayer: +1d8 against a foe that's already wounded.
    let hunterTag = '';
    if (_isSubclass(s, 'Hunter') && foe.hp < foe.hpMax) { const hx = 1 + Math.floor(Math.random() * 8); dmg += hx; hunterTag = ` +${hx} Colossus Slayer`; }
    dmg = Math.max(1, dmg);
    // Resistances and vulnerabilities are MATH now, not just lore: the
    // bestiary's typed defenses halve or double your weapon's damage type.
    const entry = _bestiaryFor(foe.name);
    const dtype = _weaponDmgType(wname);
    let resTag = '';
    if (entry && Array.isArray(entry.vuln) && entry.vuln.includes(dtype)) { dmg *= 2; resTag = ` — **vulnerable to ${dtype}!**`; }
    else if (entry && Array.isArray(entry.resist) && entry.resist.includes(dtype)) { dmg = Math.max(1, Math.ceil(dmg / 2)); resTag = ` *(resists ${dtype})*`; }
    const cc2 = _loadCombat(cid); const f2 = cc2.combatants.find(x => x.id === targetId); if (!f2) return;
    f2.hp = Math.max(0, f2.hp - dmg);
    const fell = f2.hp <= 0;
    const enemies = cc2.combatants.filter(x => x.side === 'enemy');
    const won = fell && enemies.length && enemies.every(e => e.hp <= 0) && !cc2._won;
    if (won) cc2._won = true;
    _saveCombat(cid, cc2);
    _sfx(crit ? 'crit' : 'hit');
    const msg = `⚔ *You attack the ${_esc(f2.name)} with your ${_esc(wname)}${gripTag} — d20 ${roll} ${mod >= 0 ? '+' : ''}${mod} = **${total}**${f2.ac ? ` vs AC ${f2.ac}` : ''}${dvTag}${crit ? ` — **CRITICAL HIT${roll === 19 ? ' (Champion)' : ''}!**` : ''} → **${dmg} damage**${hunterTag}${resTag}${fell ? ` — the ${_esc(f2.name)} falls!` : ` (${f2.hp}/${f2.hpMax} left)`}.*`;
    _appendBubble('me', msg); _scrollChat();
    renderCombatPanel();
    const mo = $('studio-map-overlay'); if (mo && mo.style.display === 'flex') renderMap();
    if (won) { _fxVictory(); setTimeout(() => _finishCombat(cid), 1800); }
    else if (twoWeapon && !fell) { const cb = _loadCombat(cid); if (cb._pcb) cb._pcb.bonusUsed = true; _saveCombat(cid, cb); setTimeout(() => _offhandAttack(cid, targetId, off.name), 700); }   // bonus off-hand strike
    if (_isDM(_chat.char)) {
      if (fell) {
        if (won) _chat.hdywtdt = true;   // HDYWTDT will carry the aftermath ask — _finishCombat must not stream a second one on top
        _howDoYouWantToDoThis(cid, f2.name, wname, msg, won);   // the table's favorite question
      } else _streamAssistant(msg);
    }
  });
}
// The killing blow belongs to the player: when a foe drops, ask "How do you
// want to do this?" and let them paint the finish — the GM then narrates it in
// full cinema. Skipping the prompt hands the flourish to the GM. On the blow
// that WINS the fight, the aftermath ask rides this same message (see the
// _chat.hdywtdt flag in _finishCombat).
async function _howDoYouWantToDoThis(cid, foeName, weaponName, mechMsg, won) {
  let flourish = '';
  try {
    flourish = window.styledPrompt
      ? await window.styledPrompt(`The ${foeName} is finished. How do you want to do this?`, '')
      : window.prompt(`The ${foeName} is finished. How do you want to do this?`, '');
  } catch { flourish = ''; }
  flourish = (flourish || '').trim();
  if (flourish) { _appendBubble('me', `⚔ *${_esc(flourish)}*`); _scrollChat(); }
  // The fight's emotional peak paints itself: a cinematic frame of the finish
  // renders in the background while the GM narrates (skipped while the art
  // forge is cooling down from a failure — same breaker as NPC portraits).
  if (Date.now() - _artFailAt >= 120000) {
    const hero = (_loadSheet(cid).name || '').trim();
    // Anchored on the hero's reference photos when they have them (portrait
    // saves seed those), so the finish frame shows YOUR hero landing the blow.
    _photoScene(`${hero ? hero + "'s" : 'the hero’s'} killing blow against the ${foeName}${flourish ? `: ${flourish}` : ` with ${weaponName ? 'their ' + weaponName : 'their weapon'}`}, the decisive strike landing`, hero || undefined);
  }
  const tail = won
    ? ' The fight is over — after the blow lands, narrate the aftermath and anything worth looting from the fallen or the scene; if I take something, name the item plainly.'
    : ' Then continue the scene.';
  _streamAssistant(`${mechMsg}\n[The ${foeName} falls to that blow. ${flourish
    ? `This is how I finish it: "${flourish}". Narrate my killing blow exactly as I described, in vivid slow-motion cinema — honor every detail.`
    : `Narrate my killing blow with my ${weaponName} in vivid slow-motion cinema — make the finish unforgettable.`}${tail}]`);
}
// Discretion is a valid tactic: a DEX check against DC 12 to break away.
function _playerFlee(cid) {
  if (_chat.streaming) return;
  const s = _loadSheet(cid);
  const mod = _mod(s.abilities.DEX || 10) + ((s.profSkills || []).includes('acrobatics') ? _profBonus(s) : 0);
  const roll = 1 + Math.floor(Math.random() * 20);
  const total = roll + mod, ok = roll === 20 || (roll !== 1 && total >= 12);
  _animateDie(20, roll, mod, 'Flee (DEX)', () => {
    if (ok) {
      const cc = _loadCombat(cid);
      _syncCompanionsFromCombat(cid, cc.combatants);
      _saveCombat(cid, { active: false, round: 1, turn: 0, combatants: [] });
      _portraitTried.clear();
      _exitCombatMode(cid);
      renderCombatPanel();
      const msg = `🏃 *You break away — DEX ${roll} ${mod >= 0 ? '+' : ''}${mod} = **${total}** vs DC 12. You escape the fight!*`;
      _appendBubble('me', msg); _scrollChat();
      if (_isDM(_chat.char)) _streamAssistant(`${msg}\n[I fled the fight. Narrate my escape and where I catch my breath — the foes may pursue or hold a grudge.]`);
    } else {
      const msg = `🏃 *You try to flee — DEX ${roll} ${mod >= 0 ? '+' : ''}${mod} = **${total}** vs DC 12 — but can't break away!*`;
      _appendBubble('me', msg); _scrollChat();
      if (_isDM(_chat.char)) _streamAssistant(`${msg}\n[My escape failed — the enemy gets to punish the attempt. Continue the fight.]`);
    }
  });
}

// An enemy takes its turn: d20 + attack vs your real AC, damage through the full
// sheet path (Relentless Endurance + concentration save). Attack/damage scale
// mildly with the foe's max HP as a CR proxy. ponytail: always targets the hero
// (companions are cheered on, not shielded) — per-target AI is a later upgrade.
function _enemyTurn(cid, enemy) {
  if (!enemy || enemy.hp <= 0 || enemy.side !== 'enemy') return;
  if ((enemy.conditions || []).some(cd => /stunned|paralyz|unconscious|incapacitat|prone\b.*rooted|frozen|petrif/i.test(typeof cd === 'string' ? cd : (cd.name || '')))) {
    _appendBubble('me', `😵 *The ${_esc(enemy.name)} can't act.*`); _scrollChat(); return;
  }
  const cc = _loadCombat(cid); const pc = cc.combatants.find(x => x.id === 'pc');
  if (!pc || pc.hp <= 0) return;   // don't pile onto a downed hero
  const ac = _effAC(cid);
  const atkBonus = Math.min(9, 3 + Math.floor((enemy.hpMax || 10) / 15));
  const roll = 1 + Math.floor(Math.random() * 20);
  const total = roll + atkBonus, crit = roll === 20, fumble = roll === 1;
  const hit = crit || (!fumble && total >= ac);
  if (!hit) {
    _appendBubble('me', `🗡 *The ${_esc(enemy.name)} strikes at you — d20 ${roll} +${atkBonus} = ${total} vs AC ${ac} → misses.*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[The ${enemy.name} attacked me and missed (${total} vs my AC ${ac}). Narrate the near-miss briefly.]`);
    return;
  }
  let dmg = Math.floor((enemy.hpMax || 10) / 18);
  for (let i = 0; i < (crit ? 2 : 1); i++) dmg += 1 + Math.floor(Math.random() * 6);
  dmg = Math.max(1, dmg);
  // Before the blow lands, offer a reaction (Shield / Uncanny Dodge / Parry) if
  // one is available this round; otherwise resolve immediately.
  const ccNow = _loadCombat(cid);
  const reactions = _availableReactions(cid, ccNow, { total, ac, crit });
  if (reactions.length) { _reactionOverlay(cid, enemy, { total, ac, dmg, crit }, reactions); return; }
  _resolveEnemyHit(cid, enemy, dmg, crit);
}
function _afterEnemyRender(cid) { const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) renderCombatPanel(); }
// Apply a landed enemy hit (possibly reduced by a reaction) through the sheet path.
function _resolveEnemyHit(cid, enemy, dmg, crit, note) {
  dmg = Math.max(0, Math.round(dmg));
  if (dmg <= 0) { _appendBubble('me', `🛡 *${note || 'You turn the blow aside'} — no damage gets through.*`); _scrollChat(); _afterEnemyRender(cid); return; }
  const r = _applyDamageToSheet(cid, dmg);
  const cc2 = _loadCombat(cid); const pc2 = cc2.combatants.find(x => x.id === 'pc');
  if (pc2) { pc2.hp = r.hp; if (pc2.hp <= 0) pc2.ds = pc2.ds || { s: 0, f: 0 }; _saveCombat(cid, cc2); }
  _sfx('hit'); _fxShake();
  const down = r.hp <= 0;
  _appendBubble('me', `🗡 *The ${_esc(enemy.name)} hits you${crit ? ' — **CRIT!**' : ''}${note ? ` — *${_esc(note)}*` : ''} for **${dmg} damage** (${r.hp}/${r.hpMax} left).${r.extra || ''}${r.concMsg || ''}${down ? ' — **you go down!**' : ''}*`); _scrollChat();
  _afterEnemyRender(cid);
  if (_isDM(_chat.char)) { _chat.skipDmgScan = true; _streamAssistant(`[The ${enemy.name} hit me for ${dmg} (${r.hp}/${r.hpMax} HP).${down ? ' I am down and must roll death saves.' : ''} Narrate the blow briefly.]`); }   // HP already applied — don't let the narration re-scan it
}
// An ally companion takes its turn: a straightforward strike on a random living
// foe. Attack/damage scale mildly with the companion's max HP as a rough proxy.
// ponytail: no target-priority or ability use — good enough for a sidekick.
function _companionTurn(cid, ally) {
  const cc = _loadCombat(cid);
  if ((ally.conditions || []).some(cd => /stunned|paralyz|unconscious|incapacitat|frozen|petrif/i.test(typeof cd === 'string' ? cd : (cd.name || '')))) {
    _appendBubble('me', `😵 *${_esc(ally.name)} can't act.*`); _scrollChat(); return;
  }
  const foes = cc.combatants.filter(x => x.side === 'enemy' && x.hp > 0);
  if (!foes.length) return;
  const atkBonus = 3 + Math.floor((ally.hpMax || 10) / 20);
  // Smart targeting (focus fire): finish a foe this hit can kill — a dead enemy
  // deals no damage next round — else gang up on the weakest to secure the next
  // kill, breaking ties toward the deadliest (highest max HP) foe.
  const likelyDmg = 2 + Math.floor((ally.hpMax || 10) / 16) + 4;   // ~avg of the roll below
  const killable = foes.filter(f => f.hp <= likelyDmg);
  const pool = killable.length ? killable : foes;
  const foe = pool.slice().sort((a, b) => (a.hp - b.hp) || ((b.hpMax || 0) - (a.hpMax || 0)))[0];
  const roll = 1 + Math.floor(Math.random() * 20);
  const total = roll + atkBonus, crit = roll === 20, fumble = roll === 1;
  const ac = foe.ac || 13;
  if (!(crit || (!fumble && total >= ac))) {
    _appendBubble('me', `⚔ *${_esc(ally.name)} swings at the ${_esc(foe.name)} — ${total} vs AC ${ac} → misses.*`); _scrollChat(); return;
  }
  let dmg = 2 + Math.floor((ally.hpMax || 10) / 16);
  for (let i = 0; i < (crit ? 2 : 1); i++) dmg += 1 + Math.floor(Math.random() * 6);
  foe.hp = Math.max(0, foe.hp - dmg);
  _saveCombat(cid, cc);
  const fell = foe.hp <= 0;
  _sfx('hit');
  _appendBubble('me', `⚔ *${_esc(ally.name)} strikes the ${_esc(foe.name)}${crit ? ' — **CRIT!**' : ''} for **${dmg}**${fell ? ' — it falls!' : ` (${foe.hp}/${foe.hpMax} left)`}.*`); _scrollChat();
  if (fell && !cc.combatants.some(x => x.side === 'enemy' && x.hp > 0)) _finishCombat(cid);
}
// Which reactions can the hero spend against this incoming hit? One per round,
// tracked on the per-combat budget so it resets each round AND each new fight.
let _reactionTakeHit = null;   // Escape/dismiss resolves the pending hit instead of voiding it
function _availableReactions(cid, cc, ctx) {
  const s = _loadSheet(cid);
  if (_pcBudget(cc, s).reactionUsed) return [];
  const out = [];
  const hasShield = (s.spells || []).some(sp => /^shield$/i.test((sp.name || '').trim()));
  const slotOpen = Object.keys(s.slots || {}).some(l => (s.slots[l].max || 0) > (s.slots[l].used || 0));
  if (hasShield && slotOpen && ctx.total < ctx.ac + 5) out.push({ key: 'shield', label: '🛡 Shield — +5 AC, turns this hit aside (spends a slot)' });
  if ((s.features || []).some(f => /uncanny dodge/i.test(f))) out.push({ key: 'dodge', label: '🌀 Uncanny Dodge — halve the damage' });
  const cm = _featAction('Combat Maneuver');
  if ((s.features || []).some(f => /combat maneuver/i.test(f)) && cm && ((s.featUses || {})['Combat Maneuver'] || 0) < cm.uses) out.push({ key: 'parry', label: '🎖 Parry — reduce the damage by a superiority die' });
  return out;
}
function _reactionOverlay(cid, enemy, ctx, reactions) {
  const modal = $('studio-modal'); if (!modal) { _resolveEnemyHit(cid, enemy, ctx.dmg, ctx.crit); return; }
  let ov = $('studio-reaction-overlay'); if (!ov) { ov = document.createElement('div'); ov.id = 'studio-reaction-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  ov.innerHTML = `<div class="chronicle-sheet react-sheet" role="dialog" aria-modal="true" aria-label="Reaction">
    <div class="chronicle-bar"><h2>⚡ Reaction!</h2></div>
    <div class="chronicle-list">
      <p class="gm-hint">The <strong>${_esc(enemy.name)}</strong> lands a blow — d20 total ${ctx.total} vs your AC ${ctx.ac}, <strong>${ctx.dmg} damage</strong> incoming${ctx.crit ? ' (CRIT)' : ''}. Spend your reaction?</p>
      <div class="react-btns">${reactions.map(r => `<button class="st-btn" data-react="${r.key}" type="button">${r.label}</button>`).join('')}<button class="st-btn ghost" data-react="none" type="button">Take the hit</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  // Dismissing without a choice (Escape/backdrop) must TAKE the hit, not void it.
  _reactionTakeHit = () => { _reactionTakeHit = null; ov.style.display = 'none'; _resolveEnemyHit(cid, enemy, ctx.dmg, ctx.crit); };
  const markReaction = () => { const cc = _loadCombat(cid); const sh = _loadSheet(cid); _pcBudget(cc, sh).reactionUsed = true; _saveCombat(cid, cc); };
  ov.querySelectorAll('[data-react]').forEach(b => b.addEventListener('click', () => {
    const k = b.dataset.react; _reactionTakeHit = null; ov.style.display = 'none';
    if (k === 'none') { _resolveEnemyHit(cid, enemy, ctx.dmg, ctx.crit); return; }
    markReaction();
    const s = _loadSheet(cid);
    if (k === 'shield') {
      const l = Object.keys(s.slots || {}).map(Number).sort((a, b) => a - b).find(l => (s.slots[l].max || 0) > (s.slots[l].used || 0));
      if (l != null) s.slots[l].used = (s.slots[l].used || 0) + 1;
      _saveSheet(cid, s); _sfx('loot');
      if (ctx.total < ctx.ac + 5) { _appendBubble('me', `🛡 *You cast **Shield** — a plane of force snaps up (AC ${ctx.ac} → ${ctx.ac + 5}); the ${_esc(enemy.name)}'s blow glances off!*`); _scrollChat(); _afterEnemyRender(cid); }
      else _resolveEnemyHit(cid, enemy, ctx.dmg, ctx.crit, 'Shield up, but not enough');
      return;
    }
    if (k === 'dodge') { _saveSheet(cid, s); _resolveEnemyHit(cid, enemy, Math.ceil(ctx.dmg / 2), ctx.crit, 'Uncanny Dodge, halved'); return; }
    if (k === 'parry') {
      const mod = Math.max(_mod(s.abilities.STR || 10), _mod(s.abilities.DEX || 10));
      const red = Math.max(1, 1 + Math.floor(Math.random() * 8) + mod);
      s.featUses = s.featUses || {}; s.featUses['Combat Maneuver'] = ((s.featUses || {})['Combat Maneuver'] || 0) + 1;
      _saveSheet(cid, s);
      _resolveEnemyHit(cid, enemy, ctx.dmg - red, ctx.crit, `Parry −${red}`);
      return;
    }
  }));
}

function _rollDeathSave(cid) {
  if (_chat.streaming) return;
  const cc = _loadCombat(cid); const m = cc.combatants.find(x => x.id === 'pc'); if (!m) return;
  m.ds = m.ds || { s: 0, f: 0 }; if (m.ds.stable || m.ds.dead) return;
  _fxHeartbeat();
  const roll = 1 + Math.floor(Math.random() * 20);
  let msg;
  if (roll === 20) { m.hp = 1; m.ds = { s: 0, f: 0 }; msg = `🎲 *death save → natural 20! You gasp back to life at 1 HP.*`; }
  else if (roll === 1) { m.ds.f += 2; msg = `🎲 *death save → natural 1 — two failures (${Math.min(3, m.ds.f)}/3).*`; }
  else if (roll >= 10) { m.ds.s += 1; msg = `🎲 *death save → ${roll}, a success (${Math.min(3, m.ds.s)}/3).*`; }
  else { m.ds.f += 1; msg = `🎲 *death save → ${roll}, a failure (${Math.min(3, m.ds.f)}/3).*`; }
  if (m.ds.s >= 3) { m.ds.stable = true; msg += ` **You stabilize**, clinging to life.`; }
  if (m.ds.f >= 3) { m.ds.dead = true; msg += ` **You have fallen.**`; }
  _saveCombat(cid, cc);
  const dead = m.ds.dead;
  _animateDie(20, roll, null, null, () => { _appendBubble('me', msg); _scrollChat(); renderCombatPanel(); if (dead) _gameOver(cid); else if (_isDM(_chat.char)) _streamAssistant(msg); });
}
// ── Player-initiated skill/ability checks ────────────────────────────────────
function _skillCheckMenu(cid) {
  if (_chat.streaming) return;
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-skillmenu'); if (!ov) { ov = document.createElement('div'); ov.id = 'studio-skillmenu'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const s = _loadSheet(cid);
  const skills = Object.keys(_SKILL2AB).sort().map(k => { const prof = (s.profSkills || []).includes(k); const ab = _SKILL2AB[k]; const mod = _mod(s.abilities[ab] || 10) + (prof ? _profBonus(s) : 0); return `<button class="sk-item${prof ? ' prof' : ''}" data-skill="${k}" type="button"><span>${_titleCase(k)}</span><em>${ab} ${mod >= 0 ? '+' : ''}${mod}${prof ? ' ●' : ''}</em></button>`; }).join('');
  const abils = ABILITIES.map(a => { const mod = _mod(s.abilities[a] || 10); return `<button class="sk-item" data-abil="${a}" type="button"><span>${a}</span><em>${mod >= 0 ? '+' : ''}${mod}</em></button>`; }).join('');
  ov.innerHTML = `<div class="chronicle-sheet sk-sheet" role="dialog" aria-modal="true" aria-label="Roll a check">
    <div class="chronicle-bar"><h2>Roll a check</h2><button class="studio-close" id="sk-x" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list"><p class="cc-hint">Roll on your own — the total goes to the GM to adjudicate. ● = proficient.</p>
      <div class="sk-sub">Skills</div><div class="sk-grid">${skills}</div>
      <div class="sk-sub">Raw ability</div><div class="sk-grid">${abils}</div></div></div>`;
  ov.style.display = 'flex';
  const close = () => { ov.style.display = 'none'; };
  $('sk-x').addEventListener('click', close); ov.addEventListener('click', (e) => { if (e.target === ov) close(); });
  ov.querySelectorAll('[data-skill]').forEach(b => b.addEventListener('click', () => { close(); _rollSkillCheck(cid, b.dataset.skill, false); }));
  ov.querySelectorAll('[data-abil]').forEach(b => b.addEventListener('click', () => { close(); _rollSkillCheck(cid, b.dataset.abil, true); }));
}
function _rollSkillCheck(cid, key, isAbility) {
  if (_chat.streaming) return;
  const s = _loadSheet(cid);
  const ability = isAbility ? key : _SKILL2AB[key];
  const prof = !isAbility && (s.profSkills || []).includes(key);
  const mod = _mod(s.abilities[ability] || 10) + (prof ? _profBonus(s) : 0);
  let mode = _applyInspiration(cid, _conditionMode(cid, 'check').mode);   // conditions + spent Inspiration
  const r = _rollD20(mode); const roll = r.roll; const total = roll + mod;
  const label = isAbility ? `${ability} check` : `${_titleCase(key)} check`;
  const modeWord = mode === 'adv' ? ' at advantage' : mode === 'dis' ? ' at disadvantage' : '';
  _animateDie(20, roll, mod, ability, () => {
    const note = roll === 20 ? ' — natural 20!' : roll === 1 ? ' — natural 1.' : '';
    _appendBubble('me', `🎲 *${label}${modeWord} → ${_d20Text(r)} ${mod >= 0 ? '+' : ''}${mod} = **${total}**${note}*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[I make a ${label}${modeWord}: I rolled ${total} (d20 ${roll}, ${mod >= 0 ? '+' : ''}${mod}). Narrate the outcome — set a DC if there was uncertainty.]`);
  });
}
// ── Death / game over ────────────────────────────────────────────────────────
function _gameOver(cid) {
  const modal = $('studio-modal'); if (!modal) return;
  _chat.dead = true;   // halt play until the player loads a save or clings to life
  const comp = $('studio-composer'), snd = $('studio-send');
  if (comp) { comp.disabled = true; comp.placeholder = 'Your hero has fallen…'; }
  if (snd) snd.disabled = true;
  _stopMusic(); _sfx('hit'); _fxShake();
  let ov = $('studio-gameover'); if (!ov) { ov = document.createElement('div'); ov.id = 'studio-gameover'; ov.className = 'gameover-overlay'; modal.appendChild(ov); }
  const s = _loadSheet(cid);
  ov.innerHTML = `<div class="go-card" role="dialog" aria-modal="true" aria-label="You have fallen">
    <div class="go-title">You have fallen</div>
    <div class="go-sub">${_esc(s.name || 'Your hero')}'s tale ends here — unless the story finds another way.</div>
    <div class="go-actions">
      <button class="st-btn primary" id="go-continue" type="button">↩ Load a save point</button>
      <button class="st-btn" id="go-revive" type="button">✨ Cling to life (revive at 1 HP)</button>
    </div></div>`;
  ov.style.display = 'flex';
  const _revive = () => { _chat.dead = false; const c = $('studio-composer'), sd = $('studio-send'); if (c) { c.disabled = false; c.placeholder = 'What do you do?'; } if (sd) sd.disabled = false; };
  $('go-continue').addEventListener('click', () => { _revive(); ov.style.display = 'none'; openChronicle(); });
  $('go-revive').addEventListener('click', () => {
    _revive(); ov.style.display = 'none';
    const sh = _loadSheet(cid); sh.hp = 1; _saveSheet(cid, sh);
    const cc = _loadCombat(cid); const pc = cc.combatants.find(x => x.id === 'pc'); if (pc) { pc.hp = 1; delete pc.ds; _saveCombat(cid, cc); }
    const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) renderCombatPanel();
    const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
    _appendBubble('me', `*By some mercy you cling to life at 1 HP.*`); _scrollChat();
  });
}
// ── "Previously on…" recap when resuming a story ─────────────────────────────
function _showRecap(cid) {
  const mem = _memText(cid); if (!mem || mem.length < 20) return;
  const thread = $('studio-thread'); if (!thread) return;
  const card = document.createElement('div'); card.className = 'recap-card';
  let art = ''; try { art = localStorage.getItem('studio-recap-art-' + cid) || ''; } catch {}
  card.innerHTML = `<div class="recap-veil" aria-hidden="true"></div><div class="recap-inner"><span class="recap-title">✦ Previously…</span><span class="recap-body">${_esc(mem.slice(0, 360))}</span></div>`;
  if (art) { card.style.backgroundImage = `url("${art}")`; card.classList.add('has-art'); }
  thread.insertBefore(card, thread.firstChild);
  _refreshRecapArt(cid, mem, card);   // freshen the splash in the background when the story has moved on
}
async function _refreshRecapArt(cid, mem, card) {
  if (Date.now() - _artFailAt < 120000) return;   // art forge cooling down
  const nowSig = mem.slice(0, 120);
  let sig = ''; try { sig = localStorage.getItem('studio-recap-sig-' + cid) || ''; } catch {}
  if (sig === nowSig && card.classList.contains('has-art')) return;   // unchanged since last splash
  try {
    const wid = _chat.char && _chat.char.world_id;
    const w = wid ? getWorld(wid) : null;
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: `${mem.slice(0, 220)}${w ? `, in ${w.name} (${w.kind || 'fantasy'})` : ''}. Epic cinematic wide establishing shot, moody atmospheric lighting, richly detailed fantasy illustration, no text`, size: '1216x832' }),
    });
    const d = await r.json().catch(() => ({}));
    if (d && d.image_url) {
      try { localStorage.setItem('studio-recap-art-' + cid, d.image_url); localStorage.setItem('studio-recap-sig-' + cid, nowSig); } catch {}
      if (card && card.parentNode) { card.style.backgroundImage = `url("${d.image_url}")`; card.classList.add('has-art'); }
    }
  } catch {}
}
function renderCombatPanel() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const c = _loadCombat(cid); const sheet = _loadSheet(cid);
  let panel = $('studio-combat-panel');
  if (!panel) { panel = document.createElement('div'); panel.id = 'studio-combat-panel'; panel.className = 'combat-panel'; modal.appendChild(panel); }
  let body;
  if (!c.active) {
    body = `<p class="gm-hint">Track initiative, HP, and turns when a fight breaks out. Your hero joins automatically; add foes as the GM introduces them.</p>
      <button class="st-btn primary" id="cb-start" type="button">⚔ Start combat</button>`;
  } else {
    const order = _combatOrder(c);
    const cur = order[c.turn % (order.length || 1)];
    const pip = (n) => Array.from({ length: 3 }, (_, i) => i < n ? '●' : '○').join('');
    const rows = order.map(m => {
      const pct = Math.max(0, Math.min(100, Math.round((m.hp / (m.hpMax || 1)) * 100)));
      const down = m.hp <= 0;
      const conds = (m.conditions || []).map((cd, ci) => { const nm = typeof cd === 'string' ? cd : (cd.name || ''); const rd = (cd && typeof cd === 'object' && cd.rounds != null) ? ` <em class="cond-rd">${cd.rounds}</em>` : ''; return `<span class="cond-tag">${_esc(nm)}${rd}<button class="rm" type="button" data-rmc="${m.id}:${ci}">×</button></span>`; }).join('');
      const ds = m.ds || { s: 0, f: 0 };
      const dsBlock = (m.id === 'pc' && down) ? `<div class="death-saves">
        <span class="ds-line">Death saves — <span class="ds-s">${pip(ds.s)}</span> success · <span class="ds-f">${pip(ds.f)}</span> fail</span>
        ${ds.dead ? '<span class="ds-out dead">Fallen</span>' : ds.stable ? '<span class="ds-out stable">Stable</span>' : '<button class="st-btn small primary" type="button" data-deathsave>🎲 Death save</button>'}
      </div>` : '';
      return `<div class="cb-row ${m.id === (cur && cur.id) ? 'cur' : ''} ${m.side}${down ? ' down' : ''}">
        <div class="cb-head"><span class="cb-init">${m.init}</span><span class="cb-name">${_esc(m.name)}</span>${m.ac ? `<span class="cb-ac">AC ${m.ac}</span>` : ''}<button class="rm cb-del" type="button" data-del="${m.id}" aria-label="Remove">×</button></div>
        <div class="cb-hpbar"><div class="cb-hpfill${down ? ' down' : ''}" style="width:${pct}%"></div><span class="cb-hptext">${m.hp}/${m.hpMax}</span></div>
        <div class="cb-actions">${_gmMode() ? `<button class="st-btn small" type="button" data-dmg="${m.id}">− dmg</button><input type="number" class="cb-amt" data-amt="${m.id}" value="1" min="1"><button class="st-btn small" type="button" data-heal="${m.id}">+ heal</button>` : ''}<button class="st-btn small ghost" type="button" data-addc="${m.id}">+ status</button></div>
        ${dsBlock}
        ${conds ? `<div class="cond-wrap">${conds}</div>` : ''}
      </div>`;
    }).join('');
    const turnLabel = cur ? (cur.id === 'pc' ? 'Your turn' : `<strong>${_esc(cur.name)}</strong>'s turn`) : '—';
    // Stage the foe you're facing: portrait + a big HP bar that tracks damage.
    const foe = order.find(m => m.side === 'enemy' && m.hp > 0) || order.find(m => m.side === 'enemy');
    if (foe && !foe.img && !_portraitTried.has(foe.id)) { _portraitTried.add(foe.id); _genEnemyPortrait(cid, foe.id, foe.name); }
    const foePct = foe ? Math.max(0, Math.min(100, Math.round((foe.hp / (foe.hpMax || 1)) * 100))) : 0;
    const stage = foe ? `<div class="cb-stage">
      <div class="cb-stage-art">${foe.img ? `<img src="${_esc(foe.img)}" alt="${_esc(foe.name)}">` : `<div class="cb-stage-ph"><span>${_esc(foe.name)}</span><em>… the foe takes shape …</em></div>`}</div>
      <div class="cb-stage-hp${foe.hp <= 0 ? ' down' : ''}"><div class="cb-stage-hpfill" style="width:${foePct}%"></div><span class="cb-stage-hptext">${_esc(foe.name)} · ${foe.hp}/${foe.hpMax} HP</span></div>
    </div>` : '';
    // Your turn = your move: attack with what you're wielding, or run for it.
    const livingFoes = order.filter(m => m.side === 'enemy' && m.hp > 0);
    const wpn = _equippedItem(_loadInv(cid), 'weapon');
    const isPcTurn = cur && cur.id === 'pc' && (sheet.hp || 0) > 0 && cur.hp > 0;   // downed → no actions, only death saves
    // Action economy this turn: Action (attacks left) · Bonus · Reaction.
    const budget = _pcBudget(c, sheet);
    const reactAvail = !_pcBudget(c, sheet).reactionUsed;
    const econ = isPcTurn ? `<div class="cb-econ" title="Your action economy this turn — resets each round">
        <span class="econ${budget.attacksLeft > 0 ? ' on' : ''}">⚔ Action${budget.attacksMax > 1 ? ` <em>${budget.attacksLeft}/${budget.attacksMax}</em>` : ''}</span>
        <span class="econ${!budget.bonusUsed ? ' on' : ''}">✦ Bonus</span>
        <span class="econ${reactAvail ? ' on' : ''}">⚡ Reaction</span>
      </div>` : '';
    const playerBar = isPcTurn ? `<div class="cb-playerbar">
        ${econ}
        ${livingFoes.map(f => `<button class="st-btn small primary" type="button" data-attack="${_esc(f.id)}"${budget.attacksLeft <= 0 ? ' disabled title="Action spent — press Next"' : ''}>⚔ Attack ${_esc(f.name)}</button>`).join('')}
        <button class="st-btn small ghost" type="button" id="cb-flee">🏃 Flee</button>
      </div>` : '';
    // Your kit, ALWAYS visible so you can read your loadout even between turns.
    const off = _equippedItem(_loadInv(cid), 'offhand');
    const wprops = _weaponProps(wpn ? wpn.name : 'unarmed');
    const twoH = !off && !!wprops.versatileDie;
    const wdmg = twoH ? wprops.versatileDie : ((wpn && wpn.dmg) || wprops.die || '1d4');
    const atkAbil = (wprops.ranged || (wprops.finesse && _mod(sheet.abilities.DEX || 10) > _mod(sheet.abilities.STR || 10))) ? 'DEX' : 'STR';
    const atkBonus = _mod(sheet.abilities[atkAbil] || 10) + _profBonus(sheet) + ((wpn && wpn.atk) || 0);
    const slotStr = Object.keys(sheet.slots || {}).filter(l => (sheet.slots[l].max || 0) > 0)
      .map(l => `L${l} ${Math.max(0, (sheet.slots[l].max || 0) - (sheet.slots[l].used || 0))}/${sheet.slots[l].max}`).join(' · ');
    const feats = (sheet.features || []).filter(f => /extra attack|second wind|action surge|rage|sneak attack|divine smite|ki|bardic|channel|uncanny|superiority/i.test(f)).slice(0, 3);
    const kitBar = `<div class="cb-kit">
      <span class="cb-kit-item weapon" title="Attack: d20 ${atkBonus >= 0 ? '+' : ''}${atkBonus} to hit, ${wdmg}${twoH ? ' two-handed' : ''}">⚔ ${wpn ? _esc(wpn.name) : 'Unarmed'} <em>${atkBonus >= 0 ? '+' : ''}${atkBonus} · ${_esc(wdmg)}</em></span>
      ${off ? `<span class="cb-kit-item" title="Off-hand — a bonus-action strike">🗡 ${_esc(off.name)}</span>` : ''}
      <span class="cb-kit-item">🛡 AC ${_effAC(cid)}</span>
      ${slotStr ? `<span class="cb-kit-item spells" title="Spell slots remaining — cast from your Sheet">✦ ${slotStr}</span>` : ''}
      ${feats.map(f => `<span class="cb-kit-item feat">${_esc(f.split(' (')[0])}</span>`).join('')}
    </div>`;
    body = `${stage}<div class="cb-turnbar"><span>Round ${c.round} — ${turnLabel}</span><span style="display:flex;gap:6px"><button class="st-btn small primary" id="cb-next" type="button">Next ›</button><button class="st-btn small" id="cb-end" type="button">End</button></span></div>
      ${kitBar}
      ${playerBar}
      ${_gmMode() ? '' : `<p class="cb-note">HP changes through the fight — take hits, quaff a potion, cast a spell, or rest to heal. <span class="cb-note-gm">Manual HP is in GM mode.</span></p>`}
      <div class="cb-list">${rows}</div>
      <div class="sheet-section"><h3>Add a foe</h3><div class="add-row"><input type="text" id="cb-add-name" placeholder="Goblin"><input type="number" id="cb-add-hp" placeholder="HP" style="width:62px"><input type="number" id="cb-add-ac" placeholder="AC" style="width:62px"><button class="st-btn small" id="cb-add-btn" type="button">Add</button></div></div>`;
  }
  panel.innerHTML = `<div class="sheet-head"><h2>Combat</h2><button class="studio-close" id="cb-close" type="button" aria-label="Close">✕</button></div><div class="sheet-body">${body}</div>`;
  panel.classList.add('open');
  $('cb-close').addEventListener('click', () => panel.classList.remove('open'));
  if (!c.active) {
    $('cb-start').addEventListener('click', () => {
      const player = { id: 'pc', name: sheet.name || 'You', hp: sheet.hp || 10, hpMax: sheet.hpMax || 10, ac: _effAC(cid), init: _initiative(sheet), side: 'ally', conditions: [] };
      _saveCombat(cid, { active: true, round: 1, turn: 0, combatants: [player] });
      renderCombatPanel();
    });
  } else {
    $('cb-next').addEventListener('click', () => {
      const cc = _loadCombat(cid);
      const order = _combatOrder(cc); const cur = order[cc.turn % (order.length || 1)];   // creature whose turn is ending
      if (cur && cur.conditions) {
        cur.conditions = cur.conditions
          .map(cd => (cd && typeof cd === 'object' && cd.rounds != null) ? { ...cd, rounds: cd.rounds - 1 } : cd)
          .filter(cd => !(cd && typeof cd === 'object' && cd.rounds != null && cd.rounds <= 0));
      }
      const n = cc.combatants.length || 1; cc.turn += 1; if (cc.turn >= n) { cc.turn = 0; cc.round += 1; }
      _saveCombat(cid, cc); renderCombatPanel();
      // If it's now an enemy's turn it strikes at you; an ally companion's turn
      // it strikes a foe — both resolve automatically when you press Next.
      const now = _combatOrder(cc)[cc.turn % (cc.combatants.length || 1)];
      if (now && now.hp > 0) {
        if (now.side === 'enemy') { _enemyTurn(cid, now); renderCombatPanel(); }
        else if (now.id !== 'pc') { _companionTurn(cid, now); renderCombatPanel(); }
      }
    });
    $('cb-end').addEventListener('click', () => _finishCombat(cid));
    panel.querySelectorAll('[data-attack]').forEach(b => b.addEventListener('click', () => _playerAttack(cid, b.dataset.attack)));
    $('cb-flee')?.addEventListener('click', () => _playerFlee(cid));
    $('cb-add-btn').addEventListener('click', () => {
      const nm = ($('cb-add-name').value || '').trim(); if (!nm) return;
      const hp = Number($('cb-add-hp').value || 10); const ac = Number($('cb-add-ac').value || 0);
      const cc = _loadCombat(cid);
      cc.combatants.push({ id: 'e' + (cc.combatants.length) + '_' + nm.replace(/\s+/g, ''), name: nm, hp: hp || 10, hpMax: hp || 10, ac: ac || null, init: 1 + Math.floor(Math.random() * 20), side: 'enemy', conditions: [] });
      _saveCombat(cid, cc); renderCombatPanel();
    });
    const adj = (id, delta) => {
      const cc = _loadCombat(cid); const m = cc.combatants.find(x => x.id === id);
      if (m) {
        const before = m.hp;
        // Damaging the hero routes through the full 5e path (Relentless Endurance
        // + concentration save) and keeps the sheet in lockstep with the token.
        if (m.id === 'pc' && delta < 0) {
          const r = _applyDamageToSheet(cid, -delta); m.hp = r.hp;
          const tail = `${r.extra || ''}${r.concMsg || ''}`.trim();
          if (tail) { _appendBubble('me', `*${_esc(tail)}*`); _scrollChat(); if (/breaks/.test(tail) && _isDM(_chat.char)) _streamAssistant('[My concentration just broke from that hit — the spell I was holding ends now.]'); }
        } else {
          m.hp = Math.max(0, Math.min(m.hpMax, m.hp + delta));
          if (m.id === 'pc' && delta > 0) { const ss = _loadSheet(cid); ss.hp = Math.min(ss.hpMax, (ss.hp || 0) + delta); _saveSheet(cid, ss); }   // heal the sheet too
        }
        const btn = panel.querySelector(`[data-dmg="${id}"], [data-heal="${id}"]`);
        _fxCombatFloat(btn && btn.closest('.cb-row'), m.hp - before);   // float before the re-render wipes the row
        if (m.id === 'pc') { if (m.hp <= 0) m.ds = m.ds || { s: 0, f: 0 }; else delete m.ds; }   // entering/leaving dying
        // Last foe down? Victory.
        const enemies = cc.combatants.filter(x => x.side === 'enemy');
        if (m.side === 'enemy' && m.hp <= 0 && enemies.length && enemies.every(e => e.hp <= 0) && !cc._won) { cc._won = true; _fxVictory(); setTimeout(() => _finishCombat(cid), 1800); }
      }
      _saveCombat(cid, cc); renderCombatPanel();
    };
    panel.querySelectorAll('[data-deathsave]').forEach(b => b.addEventListener('click', () => _rollDeathSave(cid)));
    panel.querySelectorAll('[data-dmg]').forEach(b => b.addEventListener('click', () => adj(b.dataset.dmg, -Number(panel.querySelector(`[data-amt="${b.dataset.dmg}"]`).value || 1))));
    panel.querySelectorAll('[data-heal]').forEach(b => b.addEventListener('click', () => adj(b.dataset.heal, Number(panel.querySelector(`[data-amt="${b.dataset.heal}"]`).value || 1))));
    panel.querySelectorAll('[data-del]').forEach(b => b.addEventListener('click', () => { const cc = _loadCombat(cid); cc.combatants = cc.combatants.filter(x => x.id !== b.dataset.del); _saveCombat(cid, cc); renderCombatPanel(); }));
    panel.querySelectorAll('[data-addc]').forEach(b => b.addEventListener('click', async () => {
      const v = window.styledPrompt ? await window.styledPrompt('Add a condition (add a number for rounds, e.g. "poisoned 3"):', { placeholder: 'e.g. prone · poisoned 3' }) : window.prompt('Add a condition (e.g. "poisoned 3"):');
      const raw = (v || '').trim(); if (!raw) return;
      const mm = /^(.*?)\s+(\d{1,2})$/.exec(raw);
      const cond = mm ? { name: mm[1].trim(), rounds: parseInt(mm[2], 10) } : raw;
      const cc = _loadCombat(cid); const m = cc.combatants.find(x => x.id === b.dataset.addc); if (m) { m.conditions = m.conditions || []; m.conditions.push(cond); }
      _saveCombat(cid, cc); renderCombatPanel();
    }));
    panel.querySelectorAll('[data-rmc]').forEach(b => b.addEventListener('click', () => { const [id, ci] = b.dataset.rmc.split(':'); const cc = _loadCombat(cid); const m = cc.combatants.find(x => x.id === id); if (m && m.conditions) m.conditions.splice(Number(ci), 1); _saveCombat(cid, cc); renderCombatPanel(); }));
  }
}

// ── NPC codex / cast (Phase C) ──────────────────────────────────────────────
const CODEX_KEY = (cid) => `studio-codex-${cid}`;
const DISPS = ['ally', 'friendly', 'neutral', 'wary', 'hostile'];
function _dispLabel(d) { return ({ ally: 'Ally', friendly: 'Friendly', neutral: 'Neutral', wary: 'Wary', hostile: 'Hostile' })[d] || 'Neutral'; }
function _loadCodex(cid) { try { return { npcs: [], at: 0, ...(JSON.parse(localStorage.getItem(CODEX_KEY(cid)) || 'null') || {}) }; } catch { return { npcs: [], at: 0 }; } }
function _saveCodex(cid, c) { try { localStorage.setItem(CODEX_KEY(cid), JSON.stringify(c)); } catch {} _pushState(cid, 'codex', c); }
// Always-on brief roster + a keyword-triggered lorebook: any NPC whose name
// shows up in the last few messages gets their full note injected, so the GM
// gets deep detail exactly when a character is on stage (cheap, no embeddings).
function _codexText(cid) {
  const c = _loadCodex(cid);
  if (!c.npcs || !c.npcs.length) return '';
  const recent = Array.from(document.querySelectorAll('#studio-thread .rp-bubble')).slice(-6).map(b => (b.textContent || '')).join(' ').toLowerCase();
  const brief = [], detailed = [];
  for (const n of c.npcs) {
    if (!n.name) continue;
    brief.push(`${n.name} (${n.role || 'NPC'}, ${n.disposition || 'neutral'})`);
    const first = n.name.toLowerCase().split(/\s+/)[0];
    if (first.length >= 3 && recent.includes(first)) {
      detailed.push(`${n.name} — ${n.note || 'no notes yet'} (${n.disposition || 'neutral'} toward the player)${n.goal ? `; right now they want: ${n.goal}` : ''}`);
    }
  }
  let t = `People the player has met: ${brief.join('; ')}.`;
  if (detailed.length) t += ` On stage right now: ${detailed.join(' ')} Play these characters as real people with their own agenda — have them act to pursue what they want, not just answer the player, while staying consistent with their disposition.`;
  return t.slice(0, 1800);
}
// When an NPC has a speaking part, their face rides beside the line: any
// paragraph containing quoted speech and a codex NPC's name gets that NPC's
// portrait floated at its head. Idempotent per paragraph.
// Screenplay labels the model emits ("**New Scene:**", "**The Environment:**",
// "**Thrain Blackiron:**") read as raw bold. Tag those leading labels so CSS can
// render them as small-caps scene beats — restyle only, never remove text.
function _styleBeats(wrap) {
  if (!wrap) return;
  wrap.querySelectorAll('.rp-bubble > p').forEach(p => {
    let n = p.firstChild;
    while (n && n.nodeType === 3 && !n.textContent.trim()) n = n.nextSibling;   // skip leading whitespace
    if (n && n.nodeName === 'STRONG') {
      const t = n.textContent.trim();
      if (/[:：]$/.test(t) && t.length >= 2 && t.length <= 32) p.classList.add('rp-beat');
    }
  });
}
function _decorateSpeech(wrap, cid) {
  _styleBeats(wrap);
  if (!wrap) return;
  const bubble = wrap.querySelector('.rp-bubble'); if (!bubble) return;
  let npcs = [];
  try { npcs = (_loadCodex(cid).npcs || []).filter(n => n.avatar && n.name); } catch {}
  if (!npcs.length) return;
  bubble.querySelectorAll('p').forEach(par => {
    if (par.querySelector('.rp-speaker')) return;
    const txt = par.textContent || '';
    if (!/["“”]/.test(txt)) return;   // only lines with actual speech
    const hit = npcs.find(n => { const first = n.name.split(/\s+/)[0]; return first.length >= 3 && txt.includes(first); });
    if (!hit) return;
    const img = document.createElement('img');
    img.className = 'rp-speaker'; img.src = hit.avatar; img.alt = hit.name; img.title = hit.name; img.loading = 'lazy';
    par.prepend(img);
  });
}

// Codex NPCs (with portraits) named in a passage — for the "on stage" strip.
function _npcFacesFor(cid, text) {
  const c = _loadCodex(cid); const t = (text || '').toLowerCase(); const out = [];
  (c.npcs || []).forEach(n => { if (!n.avatar || !n.name) return; const first = n.name.toLowerCase().split(/\s+/)[0]; if (first.length >= 3 && t.includes(first)) out.push(n); });
  return out.slice(0, 4);
}
// Codex NPCs named in a passage regardless of whether they have a portrait yet.
// A codex entry you can actually take on as a companion: a person, not a beast.
// Known bestiary monsters, monstrous names/roles, and anyone hostile are out
// (GM mode can still force-recruit past this).
function _isRecruitable(n) {
  if (!n || !n.name) return false;
  const s = (n.name + ' ' + (n.role || '')).toLowerCase();
  if (_bestiaryFor(n.name)) return false;
  if (/\b(ogre|goblin|orc|troll|dragon|drake|wyvern|wolf|wolves|bear|boar|rat|spider|snake|skeleton|zombie|ghoul|ghost|wraith|spectre|specter|revenant|lich|vampire|werewolf|bandit|brigand|thug|raider|cultist|kobold|gnoll|hobgoblin|slime|ooze|golem|construct|demon|devil|imp|fiend|elemental|beast|creature|monster|hag|harpy|minotaur|cyclops|giant|gargoyle|mimic|beholder|undead|swarm)\b/.test(s)) return false;
  if ((n.disposition || 'neutral') === 'hostile') return false;
  return true;
}
function _namedCodexNpcs(cid, text) {
  const c = _loadCodex(cid); const t = (text || '').toLowerCase();
  return (c.npcs || []).filter(n => { const first = (n.name || '').toLowerCase().split(/\s+/)[0]; return first.length >= 3 && t.includes(first); });
}
// Seed the world's authored cast into the codex on entry, so named characters
// are tracked (and get faces) from turn 1 instead of waiting for the extractor.
function _seedCast(cid, worldId) {
  const w = getWorld(worldId); if (!w || !Array.isArray(w.cast)) return;
  const c = _loadCodex(cid); c.npcs = c.npcs || [];
  let changed = false;
  w.cast.forEach(m => {
    if (!m || !m.name) return;
    if (c.npcs.some(n => (n.name || '').toLowerCase() === m.name.toLowerCase())) return;
    c.npcs.push({ id: 'npc-' + (m.slug || m.name.toLowerCase().replace(/[^a-z0-9]+/g, '-')), name: m.name, role: m.role || '', disposition: 'neutral', note: '', goal: '', appearance: m.appearance || m.look || '', avatar: m.avatar || '', prebuilt: true });
    changed = true;
  });
  if (changed) _saveCodex(cid, c);
}
const _castPortraitTried = new Set();
// Circuit breaker: after a failed image gen, stop conjuring decorative NPC
// portraits for a couple minutes so a down/slow image stack isn't hammered with
// a fresh doomed request for every new face that walks on stage.
let _artFailAt = 0;
async function _genNpcPortrait(cid, npcId) {
  if (Date.now() - _artFailAt < 120000) return;   // recent failure — give the forge a rest
  const c0 = _loadCodex(cid); const n0 = (c0.npcs || []).find(x => x.id === npcId); if (!n0 || n0.avatar) return;
  const wid = _chat.char && _chat.char.world_id;
  const style = { embervale: 'fantasy character portrait', neonspire: 'cyberpunk character portrait, neon', everyday: 'realistic portrait photo' }[wid] || 'character portrait';
  const desc = [n0.appearance, n0.role, n0.name].filter(Boolean).join(', ');
  try {
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: `${style}, ${desc}, head and shoulders, dramatic lighting, no text`, size: '512x512' }),
    });
    if (!r.ok) { _artFailAt = Date.now(); return; }   // 502/504/etc. — trip the breaker (r.ok=false doesn't throw)
    const d = await r.json();
    if (d.ok && d.image_url) { const c = _loadCodex(cid); const m = (c.npcs || []).find(x => x.id === npcId); if (m) { m.avatar = d.image_url; _saveCodex(cid, c); const cp = $('studio-codex-overlay'); if (cp && cp.style.display === 'flex') openCodex(); } }
  } catch (e) { _artFailAt = Date.now(); /* portrait is decorative */ }
}
// Returns 'ok' (NPCs found), 'empty' (model read fine but surfaced nobody),
// or 'error' (couldn't reach/parse the model). Callers decide how to react.
async function _updateCodex(cid) {
  if (!_chat.char) return 'error';
  try {
    const transcript = await _fetchTranscript();
    if (!transcript.length) return 'empty';
    const c = _loadCodex(cid);
    const res = await fetch(`${API_BASE}/api/characters/studio/codex`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ character_name: _chat.char.name, transcript, codex: c.npcs, model: _modelLabel() }),
    });
    if (!res.ok) return 'error';
    const d = await res.json();
    if (!d.ok || !Array.isArray(d.npcs)) return 'error';
    if (!d.npcs.length) return 'empty';
    const prev = {}; (c.npcs || []).forEach(n => { if (n.name) prev[n.name.toLowerCase()] = n; });
    const merged = d.npcs.map(n => {
      const p = prev[(n.name || '').toLowerCase()] || {};
      return { id: p.id || ('npc-' + (n.name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-')), avatar: p.avatar || '', ...n };
    });
    _saveCodex(cid, { npcs: merged, at: _meCount() });
    merged.forEach(n => _upsertRel(n.name, n.disposition, n.note));   // carry relationships across sessions
    return 'ok';
  } catch { return 'error'; }
}
function openCodex() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const c = _loadCodex(cid);
  let ov = $('studio-codex-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-codex-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const cards = (c.npcs && c.npcs.length) ? c.npcs.map((n, i) => {
    const art = n.avatar
      ? `<img class="codex-portrait" src="${_esc(n.avatar)}" alt="Portrait of ${_esc(n.name)}" loading="lazy">`
      : `<button class="codex-portrait codex-genface" type="button" data-genface="${i}" title="Generate a portrait">${_esc((n.name || '?').slice(0, 1).toUpperCase())}</button>`;
    const opts = DISPS.map(d => `<option value="${d}"${d === (n.disposition || 'neutral') ? ' selected' : ''}>${_dispLabel(d)}</option>`).join('');
    return `<li class="codex-card disp-${_esc(n.disposition || 'neutral')}">
      ${art}
      <div class="codex-id">
        <div class="codex-top"><span class="codex-name">${_esc(n.name)}</span><button class="rm" data-rmnpc="${i}" type="button" aria-label="Remove">×</button></div>
        <input class="codex-role" data-role="${i}" value="${_esc(n.role || '')}" placeholder="role / title">
        <select class="codex-disp" data-dispsel="${i}" aria-label="Disposition toward you">${opts}</select>
        <textarea class="codex-note" data-note="${i}" rows="2" placeholder="What you know about them…">${_esc(n.note || '')}</textarea>
        <input class="codex-goal" data-goal="${i}" value="${_esc(n.goal || '')}" placeholder="🎯 what they want…">
        ${_isDM(_chat.char) ? (() => {
            const inParty = _companions(cid).some(x => x.name.toLowerCase() === (n.name || '').toLowerCase());
            // In party → dismiss. Otherwise a player ASKS them to join (the GM
            // decides); only GM mode instantly recruits. A monster or a hostile
            // isn't offered as a companion at all (unless GM mode overrides).
            if (inParty) return `<button class="st-btn small" data-recruit="${i}" type="button">⚔ In your party — dismiss</button>`;
            if (!_isRecruitable(n)) return _gmMode() ? `<button class="st-btn small ghost" data-recruit="${i}" type="button">⚔ Recruit (GM)</button>` : '';
            return _gmMode()
              ? `<button class="st-btn small ghost" data-recruit="${i}" type="button">⚔ Recruit (GM)</button>`
              : `<button class="st-btn small ghost" data-askjoin="${i}" type="button" title="Ask them to join — the GM decides if they will">✦ Ask them to join…</button>`;
          })() : ''}
      </div></li>`;
  }).join('') : '<li class="codex-card empty">No one yet — the cast fills in as you meet people, or add someone you know.</li>';
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Cast codex">
    <div class="chronicle-bar"><h2>The cast</h2><button class="studio-close" id="codex-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Everyone you've met and how they feel about you. It fills in as you play; the GM keeps them consistent and has them react to your relationship. Tap a blank face to give them a portrait.</p>
      <ul class="codex-list">${cards}</ul>
      <div class="add-row"><input type="text" id="codex-add" placeholder="Add someone you've met…"><button id="codex-add-btn" class="st-btn small" type="button">Add</button></div>
      <div class="chronicle-actions"><button class="st-btn" id="codex-refresh" type="button">↻ Update from the story</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  $('codex-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  const addNpc = () => { const v = ($('codex-add').value || '').trim(); if (!v) return; const cc = _loadCodex(cid); cc.npcs = cc.npcs || []; cc.npcs.push({ id: 'npc-' + v.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name: v, role: '', disposition: 'neutral', note: '', goal: '', appearance: '', avatar: '' }); _saveCodex(cid, cc); openCodex(); };
  $('codex-add-btn').addEventListener('click', addNpc);
  $('codex-add').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addNpc(); } });
  ov.querySelectorAll('[data-rmnpc]').forEach(b => b.addEventListener('click', () => { const cc = _loadCodex(cid); cc.npcs.splice(Number(b.dataset.rmnpc), 1); _saveCodex(cid, cc); openCodex(); }));
  ov.querySelectorAll('[data-dispsel]').forEach(sel => sel.addEventListener('change', () => { const cc = _loadCodex(cid); const n = cc.npcs[Number(sel.dataset.dispsel)]; if (n) n.disposition = sel.value; _saveCodex(cid, cc); openCodex(); }));
  ov.querySelectorAll('[data-role]').forEach(inp => inp.addEventListener('input', () => { const cc = _loadCodex(cid); const n = cc.npcs[Number(inp.dataset.role)]; if (n) n.role = inp.value; _saveCodex(cid, cc); }));
  ov.querySelectorAll('[data-note]').forEach(ta => ta.addEventListener('input', () => { const cc = _loadCodex(cid); const n = cc.npcs[Number(ta.dataset.note)]; if (n) n.note = ta.value; _saveCodex(cid, cc); }));
  ov.querySelectorAll('[data-goal]').forEach(inp => inp.addEventListener('input', () => { const cc = _loadCodex(cid); const n = cc.npcs[Number(inp.dataset.goal)]; if (n) n.goal = inp.value; _saveCodex(cid, cc); }));
  ov.querySelectorAll('[data-recruit]').forEach(b => b.addEventListener('click', () => {
    const n = (_loadCodex(cid).npcs || [])[Number(b.dataset.recruit)]; if (!n || !n.name) return;
    _toggleCompanion(cid, n);   // GM instant-recruit, or dismiss someone already in the party
    openCodex();
  }));
  ov.querySelectorAll('[data-askjoin]').forEach(b => b.addEventListener('click', () => {
    const n = (_loadCodex(cid).npcs || [])[Number(b.dataset.askjoin)]; if (!n || !n.name) return;
    if (ov) ov.style.display = 'none';   // back to the scene to hear their answer
    _askJoinParty(cid, n);
  }));
  ov.querySelectorAll('[data-genface]').forEach(b => b.addEventListener('click', async () => {
    const i = Number(b.dataset.genface); const cc = _loadCodex(cid); const n = cc.npcs[i]; if (!n) return;
    b.disabled = true; b.textContent = '…';
    try {
      const prompt = (n.appearance || `${n.name}, ${n.role || 'character'}`) + ', character portrait';
      const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt }) });
      const gd = await r.json();
      if (gd.ok && gd.image_url) { n.avatar = gd.image_url; _saveCodex(cid, cc); }
    } catch {}
    openCodex();
  }));
  const rb = $('codex-refresh');
  rb.addEventListener('click', async () => {
    rb.disabled = true; rb.textContent = 'Updating…';
    const r = await _updateCodex(cid);
    if (r === 'ok') { openCodex(); return; }                       // re-render with the new cast
    rb.disabled = false;
    rb.textContent = r === 'empty' ? '↻ No new faces yet — try again' : "↻ Couldn't read that — try again";
    setTimeout(() => { const b = $('codex-refresh'); if (b) b.textContent = '↻ Update from the story'; }, 2800);
  });
}
function toggleCodex() { const ov = $('studio-codex-overlay'); if (ov && ov.style.display === 'flex') { ov.style.display = 'none'; return; } openCodex(); }

// ── Quest log + XP / leveling (Phase E) ─────────────────────────────────────
const QUEST_KEY = (cid) => `studio-quests-${cid}`;
function _loadQuests(cid) { try { return { quests: [], at: 0, ...(JSON.parse(localStorage.getItem(QUEST_KEY(cid)) || 'null') || {}) }; } catch { return { quests: [], at: 0 }; } }
function _saveQuests(cid, q) { try { localStorage.setItem(QUEST_KEY(cid), JSON.stringify(q)); } catch {} _pushState(cid, 'quests', q); }
// XP curve: advancing to level L+1 costs L*100 XP. Cumulative and invertible.
function _xpForLevel(lvl) { let t = 0; for (let i = 1; i < lvl; i++) t += i * 100; return t; }
function _levelForXp(xp) { let lvl = 1; while (xp >= _xpForLevel(lvl + 1)) lvl++; return lvl; }
function _questText(cid) {
  const q = _loadQuests(cid); const active = (q.quests || []).filter(x => x.status !== 'done');
  const s = _loadSheet(cid);
  let t = `The player is level ${s.level || 1}.`;
  if (active.length) t += ` Active quests: ${active.map(x => `${x.title}${x.desc ? ` — ${x.desc}` : ''}`).join('; ')}. Keep the story moving toward these.`;
  return t.slice(0, 1200);
}
function _awardXp(cid, amount, reason) {
  if (!amount) return;
  const s = _loadSheet(cid); const before = s.level || 1;
  s.xp = (s.xp || 0) + amount;
  const after = _levelForXp(s.xp);
  const conMod = _mod((s.abilities && s.abilities.CON) || 10);
  const dieAvg = Math.floor((s.hitDie || 8) / 2) + 1;   // average roll of the class hit die
  if (after > before) {
    for (let l = before; l < after; l++) s.hpMax += Math.max(1, dieAvg + conMod);  // baseline avg hit die + CON (re-rollable in the modal)
    s.level = after; s.hp = s.hpMax;                                               // a level-up restores you to full
    s._pendingLevelUp = { from: before, to: after };   // so the ASI/feature modal isn't lost if this XP was earned off-screen (party play)
  }
  _saveSheet(cid, s);
  if (_chat.char && _chat.char.id === cid) {
    _appendBubble('me', `✨ *Gained ${amount} XP — ${_esc(reason)}.*`);
    _scrollChat();
    const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
    const ov = $('studio-quests-overlay'); if (ov && ov.style.display === 'flex') openQuests();
    if (after > before) _openLevelUp(cid, before, after);   // clears _pendingLevelUp
  }
}
// A real level-up moment: the average HP is already applied; here you can roll
// the hit die instead and spend Ability Score Improvements at milestone levels.
let _luState = null;
// Which spell circle a class can reach at a level (our grimoire spans 0–2).
function _maxCircle(cls, level) {
  const preset = CLASS_PRESETS[cls];
  // Full casters climb the real 5e curve (capped at circle 5 — the slot table's ceiling).
  if (preset && preset.caster) return Math.min(5, Math.ceil(Math.min(9, Math.max(1, level)) / 2));
  if (['Ranger', 'Paladin'].includes(cls)) return level >= 9 ? 3 : level >= 5 ? 2 : level >= 2 ? 1 : 0;   // half-casters awaken at 2
  return 0;
}
// Spells this character could learn right now (class list, reachable circle, not yet known).
function _learnableSpells(s, toLevel) { return _learnableSpellsFor(s, s.cls, toLevel); }
// Same, for an explicit class advanced to an explicit class-level (multiclass).
function _learnableSpellsFor(s, cls, classLevel) {
  const circle = _maxCircle(cls, classLevel);
  if (!circle) return [];
  const known = new Set((s.spells || []).map(x => (x.name || '').toLowerCase()));
  return SPELLS.filter(sp => sp.classes.includes(cls) && sp.level <= circle && !known.has(sp.name.toLowerCase()));
}
// The HP this level-up should add above the pre-award baseline (L.hpBase):
// a fresh roll if taken, else the average hit die of the class actually chosen.
function _luChosenHp(L, s) {
  if (L.rolled) return L.rolledTotal;
  if (L.multiOK) { const d = _dieFor(L.pickClass || s.cls); return Math.max(1, Math.floor(d / 2) + 1 + L.conMod); }
  return L.appliedHp;
}
function _openLevelUp(cid, from, to) {
  const s = _loadSheet(cid);
  if (s._pendingLevelUp) { delete s._pendingLevelUp; _saveSheet(cid, s); }   // consumed — don't re-open on next chat load
  const conMod = _mod((s.abilities && s.abilities.CON) || 10);
  const die = s.hitDie || 8; const dieAvg = Math.floor(die / 2) + 1;
  const levels = to - from;
  const milestones = [4, 8, 12, 16, 19].filter(l => l > from && l <= to).length;
  const appliedHp = levels * Math.max(1, dieAvg + conMod);   // what _awardXp already added (primary die)
  const primary = _classesOf(s).slice().sort((a, b) => b.levels - a.levels)[0].cls;
  _luState = { cid, from, to, conMod, die, levels, asiBudget: milestones * 2, gains: { STR: 0, DEX: 0, CON: 0, INT: 0, WIS: 0, CHA: 0 }, avgHp: appliedHp, appliedHp, hpBase: s.hpMax - appliedHp, primary, pickClass: primary, multiOK: levels === 1, rolled: false, rolledTotal: 0, spellPicks: [], featPicks: [] };
  _fxLevelUp();
  renderLevelUp();
}
// Feats — an alternative to a +2 Ability Score Improvement at ASI levels. Each
// costs the full 2 ASI points. Mechanically-hooked ones set flags the roll/HP
// code reads; the rest are honored by the GM (fed via the sheet summary).
const FEATS = {
  Tough: { desc: '+2 hit points per level — you are simply harder to drop.', hp: 2 },
  Alert: { desc: "+5 to initiative, and you can't be surprised while conscious.", apply(s) { s.featAlert = true; } },
  'Resilient (CON)': { desc: '+1 Constitution and proficiency in Constitution saves — a boon for holding concentration.', apply(s) { s.abilities.CON = Math.min(20, (s.abilities.CON || 10) + 1); if (!(s.profSaves || []).includes('CON')) s.profSaves = [...(s.profSaves || []), 'CON']; } },
  'War Caster': { desc: 'Advantage on saving throws to maintain concentration; you can cast with your hands full.', apply(s) { s.featWarCaster = true; } },
  Observant: { desc: '+1 Wisdom and +5 to passive Perception — little escapes you.', apply(s) { s.abilities.WIS = Math.min(20, (s.abilities.WIS || 10) + 1); s.featObservant = true; } },
  Mobile: { desc: "+10 feet of speed; you ignore difficult terrain when you Dash.", apply(s) { s.speed = (s.speed || 30) + 10; } },
  Actor: { desc: '+1 Charisma; advantage on Deception & Performance to pass as someone else; mimic voices.', apply(s) { s.abilities.CHA = Math.min(20, (s.abilities.CHA || 10) + 1); } },
  Lucky: { desc: '3 luck points per long rest — reroll a d20 (yours, or an attack against you).' },
  'Great Weapon Master': { desc: 'Before a melee attack, take −5 to hit for +10 damage; a crit or kill grants a bonus attack.' },
  Sharpshooter: { desc: 'Ignore cover and long-range disadvantage; take −5 to hit for +10 damage on a ranged attack.' },
  'Magic Initiate': { desc: 'Learn two cantrips and one 1st-level spell from a class of your choice.' },
  Skilled: { desc: 'Gain proficiency in any three skills or tools of your choice.' },
};

// Subclasses: chosen once at level 3, two paths per class. The choice lands on
// the sheet and the GM honors the path's signature moves (client keeps HP/AC/
// slots as ever). Light-but-real: the CHOICE is mechanical, the flavor is canon.
const SUBCLASSES = {
  Fighter: [
    { name: 'Champion', line: 'Your weapon crits on a 19 or 20, and raw athleticism rarely fails you.' },
    { name: 'Battle Master', line: 'Combat maneuvers — trip, disarm, riposte, feint — powered by d8 superiority dice (4 per rest).' }],
  Barbarian: [
    { name: 'Berserker', line: 'Frenzy: an extra melee attack every turn while raging, paid for in exhaustion after.' },
    { name: 'Totem Warrior (Bear)', line: 'While raging you resist ALL damage except psychic.' }],
  Rogue: [
    { name: 'Thief', line: 'Fast Hands: use items, pick locks, or disarm traps as a bonus action; a legendary climber.' },
    { name: 'Assassin', line: 'Advantage against anyone who has not acted yet; hits on surprised foes are critical.' }],
  Ranger: [
    { name: 'Hunter', line: "Colossus Slayer: once per turn, +1d8 damage to a foe that's already wounded." },
    { name: 'Beast Master', line: 'A loyal animal companion fights at your command beside you.' }],
  Monk: [
    { name: 'Way of the Open Hand', line: 'Your Flurry of Blows can knock foes prone, shove them away, or deny their reactions.' },
    { name: 'Way of Shadow', line: 'Spend ki to teleport between shadows and cast darkness or silence.' }],
  Paladin: [
    { name: 'Oath of Devotion', line: 'Sacred Weapon (+CHA to hit, once per rest); allies near you cannot be charmed or frightened.' },
    { name: 'Oath of Vengeance', line: 'Vow of Enmity: swear against one foe and gain advantage on every attack against them.' }],
  Wizard: [
    { name: 'Evoker', line: 'Sculpt Spells: your allies stand safely inside your own blasts.' },
    { name: 'Abjurer', line: 'Arcane Ward: a shield of stored magic absorbs damage before your HP does.' }],
  Sorcerer: [
    { name: 'Draconic Bloodline', line: 'Scaled resilience: AC 13 + DEX unarmored, +1 HP per level.' },
    { name: 'Wild Magic', line: 'Chaos rides your casting — surges of wild magic, and Tides of Chaos grants advantage.' }],
  Cleric: [
    { name: 'Life Domain', line: 'Your healing spells restore extra HP (2 + spell level); Preserve Life mends the whole party.' },
    { name: 'War Domain', line: 'Bonus-action weapon attacks; Guided Strike turns a miss into a +10 hit.' }],
  Druid: [
    { name: 'Circle of the Land', line: 'Natural Recovery: regain spell slots on a short rest; the land grants bonus spells.' },
    { name: 'Circle of the Moon', line: 'Combat Wild Shape as a bonus action, into far stronger beasts.' }],
  Bard: [
    { name: 'College of Lore', line: 'Cutting Words: spend inspiration to shrink an enemy roll; two extra skills.' },
    { name: 'College of Valor', line: 'Your inspiration adds to allies’ damage or AC; you fight in armor with martial weapons.' }],
  Warlock: [
    { name: 'The Fiend', line: "Dark One's Blessing: temporary HP every time you drop a foe." },
    { name: 'The Archfey', line: 'Fey Presence charms or frightens everyone near you; Misty Escape teleports you when hurt.' }],
};
function _subclassLine(s) {
  const list = SUBCLASSES[s.cls] || [];
  const sc = list.find(x => x.name === s.subclass);
  return sc ? sc.line : '';
}

function renderLevelUp() {
  const modal = $('studio-modal'); const L = _luState; if (!modal || !L) return;
  const s = _loadSheet(L.cid);
  const pick = L.pickClass || s.cls;                         // the class taken this level
  const co = _classLevelOf(s, pick), cn = co + 1;            // its own level, before → after
  const pickEntry = _classesOf(s).find(c => c.cls === pick);
  const projMax = L.hpBase + _luChosenHp(L, s);             // projected new HP max, reconciled on confirm
  let ov = $('studio-levelup-overlay'); if (!ov) { ov = document.createElement('div'); ov.id = 'studio-levelup-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const spent = ABILITIES.reduce((t, a) => t + (L.gains[a] || 0), 0);
  const featCost = (L.featPicks || []).length * 2;   // each feat eats a full +2 ASI
  const remaining = L.asiBudget - spent - featCost;
  const oldProf = _profBonus({ level: L.from }), newProf = _profBonus({ level: L.to });
  const abilityRows = ABILITIES.map(a => {
    const base = s.abilities[a] || 10, add = L.gains[a] || 0, val = base + add;
    return `<div class="lu-ab"><span class="lu-ab-name">${a}</span><span class="lu-ab-val">${val}${add ? ` <em>+${add}</em>` : ''}</span>
      <span class="lu-ab-ctl"><button class="slot-step" data-lu-ab="${a}" data-d="-1" type="button" ${add <= 0 ? 'disabled' : ''}>−</button><button class="slot-step" data-lu-ab="${a}" data-d="1" type="button" ${(remaining <= 0 || val >= 20) ? 'disabled' : ''}>+</button></span></div>`;
  }).join('');
  ov.innerHTML = `<div class="chronicle-sheet levelup" role="dialog" aria-modal="true" aria-label="Level up">
    <div class="chronicle-bar"><h2>⭐ Level ${L.to}!</h2></div>
    <div class="chronicle-list">
      <p class="gm-hint">You've grown stronger — level ${L.from} → ${L.to}.</p>
      ${L.multiOK ? (() => {
        const owned = _classesOf(s);
        // The primary class was already bumped to the new level before the modal
        // opened, so show the level being FINALIZED (L.from→L.to) to match the
        // header — not c.levels→c.levels+1, which read one ahead ("Wizard 3→4").
        const chips = owned.map(c => `<button class="prof-chip lu-classpick${pick === c.cls ? ' on' : ''}" data-luclass="${_esc(c.cls)}" type="button">${c.cls === L.primary ? 'Advance' : 'Continue'} ${_esc(c.cls)} <em>${c.cls === L.primary ? `${L.from}→${L.to}` : `${c.levels}→${c.levels + 1}`}</em></button>`).join('');
        const ownedNames = new Set(owned.map(c => c.cls));
        const newOpts = Object.keys(CLASS_PRESETS).filter(c => !ownedNames.has(c))
          .map(c => { const ok = _canMulticlass(s, c); return `<option value="${c}"${pick === c ? ' selected' : ''}${ok ? '' : ' disabled'}>${c}${CLASS_PRESETS[c].caster ? ' ✦' : ''}${ok ? '' : ` — needs ${_MC_ABILITY[c]} 13`}</option>`; }).join('');
        return `<div class="sheet-section"><h3>This level's class <span class="prof-bonus">advance, or branch into a new one</span></h3>
          <div class="lu-spells">${chips}<label class="lu-mc-new">＋ Multiclass<select id="lu-mc-select" class="studio-select"><option value="">— new class —</option>${newOpts}</select></label></div>
          ${!ownedNames.has(pick) ? `<p class="gm-hint">New path: <strong>${_esc(pick)}</strong> — d${_dieFor(pick)} hit die${CLASS_PRESETS[pick] && CLASS_PRESETS[pick].caster ? ', spellcaster' : ''}. Your total level is still ${L.to}.</p>` : ''}</div>`;
      })() : ''}
      <div class="lu-card"><span>Hit points → new max <strong>${projMax}</strong> <em class="prof-bonus">d${_dieFor(pick)}</em></span>${L.rolled ? '<span class="lu-rolled">rolled</span>' : '<button class="st-btn small" id="lu-roll" type="button">🎲 Roll hit die instead</button>'}</div>
      ${newProf > oldProf ? `<div class="lu-card">Proficiency bonus rises to <strong>+${newProf}</strong>.</div>` : ''}
      ${(() => { const feats = L.multiOK ? _featuresGained(pick, co, cn) : _featuresGained(s.cls, L.from, L.to); return feats.length ? `<div class="sheet-section"><h3>New ${_esc(pick)} features</h3>${feats.map(f => `<div class="lu-card lu-feat"><span>✨ <strong>${_esc(f.name)}</strong> <em class="prof-bonus">lvl ${f.level}</em></span></div>`).join('')}</div>` : ''; })()}
      ${(() => { const opts = SUBCLASSES[pick]; const has = L.multiOK ? (pickEntry && pickEntry.subclass) : s.subclass; const reach = L.multiOK ? cn : L.to; if (!opts || has || reach < 3) return '';
        return `<div class="sheet-section"><h3>Choose your ${_esc(pick)} path <span class="prof-bonus">your subclass — this choice is forever</span></h3>
          <div class="lu-spells">${opts.map(o => `<button class="prof-chip lu-subclass${L.subclassPick === o.name ? ' on' : ''}" data-lusub="${_esc(o.name)}" type="button" title="${_esc(o.line)}">${_esc(o.name)}</button>`).join('')}</div>
          <p class="gm-hint">${L.subclassPick ? _esc((opts.find(o => o.name === L.subclassPick) || {}).line || '') : 'Hover a path for what it grants — pick one to continue.'}</p></div>`; })()}
      ${(() => { const learn = L.multiOK ? _learnableSpellsFor(s, pick, cn) : _learnableSpells(s, L.to); if (!learn.length) return '';
        const picks = L.spellPicks || [];
        return `<div class="sheet-section"><h3>Learn new spells <span class="prof-bonus">choose up to 2 — ${2 - picks.length} left</span></h3>
          <div class="lu-spells">${learn.map(sp => `<button class="prof-chip lu-spell${picks.includes(sp.name) ? ' on' : ''}" data-luspell="${_esc(sp.name)}" type="button" title="${_esc(sp.desc)}">${_esc(sp.name)} <em>${sp.level ? 'L' + sp.level : 'cantrip'}</em></button>`).join('')}</div>
          <p class="gm-hint">Hover a spell for what it does — the full grimoire lives in the 📖 Lorebook.</p></div>`; })()}
      ${L.asiBudget > 0 ? `<div class="sheet-section"><h3>Ability Score Improvement <span class="prof-bonus">${remaining} point${remaining === 1 ? '' : 's'} left</span></h3><div class="lu-abs">${abilityRows}</div></div>` : ''}
      ${L.asiBudget >= 2 ? (() => {
        const taken = new Set([...(s.feats || []), ...(L.featPicks || [])]);
        const avail = Object.keys(FEATS).filter(f => !taken.has(f) || (L.featPicks || []).includes(f));
        return `<div class="sheet-section"><h3>…or take a feat <span class="prof-bonus">each costs 2 ability points</span></h3>
          <div class="lu-spells">${avail.map(f => { const on = (L.featPicks || []).includes(f); const canAdd = on || remaining >= 2; return `<button class="prof-chip lu-feat-pick${on ? ' on' : ''}" data-lufeat="${_esc(f)}" type="button" title="${_esc(FEATS[f].desc)}" ${canAdd ? '' : 'disabled'}>${_esc(f)}</button>`; }).join('')}</div>
          <p class="gm-hint">Hover a feat for what it does.</p></div>`; })() : ''}
      <div class="chronicle-actions"><button class="st-btn primary" id="lu-confirm" type="button" ${(remaining > 0 || (L.multiOK ? (SUBCLASSES[pick] && pickEntry && !pickEntry.subclass && cn >= 3 && !L.subclassPick) : (SUBCLASSES[s.cls] && !s.subclass && L.to >= 3 && !L.subclassPick))) ? 'disabled' : ''}>Confirm</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  // Intentionally NOT closable by backdrop — the player must confirm (esp. to spend ASI).
  // Roll the actual chosen class's die; store the total — HP is reconciled from
  // L.hpBase on confirm, so nothing touches the sheet until then.
  $('lu-roll')?.addEventListener('click', () => {
    const die = L.multiOK ? _dieFor(pick) : (L.die || 8);
    let hp = 0; for (let i = 0; i < L.levels; i++) hp += Math.max(1, 1 + Math.floor(Math.random() * die) + L.conMod);
    L.rolledTotal = hp; L.rolled = true; renderLevelUp();
  });
  // Switching the class this level resets any choices that depended on it.
  const _repick = (cls) => { L.pickClass = cls; L.rolled = false; L.rolledTotal = 0; L.subclassPick = ''; L.spellPicks = []; renderLevelUp(); };
  ov.querySelectorAll('[data-luclass]').forEach(b => b.addEventListener('click', () => _repick(b.dataset.luclass)));
  const mcSel = $('lu-mc-select'); if (mcSel) mcSel.addEventListener('change', () => { if (mcSel.value) _repick(mcSel.value); });
  ov.querySelectorAll('[data-lu-ab]').forEach(b => b.addEventListener('click', () => { const a = b.dataset.luAb; L.gains[a] = Math.max(0, (L.gains[a] || 0) + Number(b.dataset.d)); renderLevelUp(); }));
  ov.querySelectorAll('[data-luspell]').forEach(b => b.addEventListener('click', () => {
    const nm = b.dataset.luspell; L.spellPicks = L.spellPicks || [];
    const i = L.spellPicks.indexOf(nm);
    if (i >= 0) L.spellPicks.splice(i, 1);
    else if (L.spellPicks.length < 2) L.spellPicks.push(nm);
    renderLevelUp();
  }));
  ov.querySelectorAll('[data-lusub]').forEach(b => b.addEventListener('click', () => {
    L.subclassPick = L.subclassPick === b.dataset.lusub ? '' : b.dataset.lusub;
    renderLevelUp();
  }));
  ov.querySelectorAll('[data-lufeat]').forEach(b => b.addEventListener('click', () => {
    const fn = b.dataset.lufeat; L.featPicks = L.featPicks || [];
    const i = L.featPicks.indexOf(fn);
    if (i >= 0) L.featPicks.splice(i, 1);                       // deselect refunds its 2 points
    else if (L.asiBudget - spent - L.featPicks.length * 2 >= 2) L.featPicks.push(fn);
    renderLevelUp();
  }));
  $('lu-confirm').addEventListener('click', () => {
    const ss = _loadSheet(L.cid); ABILITIES.forEach(a => { ss.abilities[a] = Math.min(20, (ss.abilities[a] || 10) + (L.gains[a] || 0)); });
    // Advance the chosen class. Single-level gains honor the class picker;
    // multi-level jumps (rare — a big XP dump) advance the primary class.
    let featCls, featFrom, featTo, wasNew = false;
    if (L.multiOK) {
      const cs = _classesOf(ss).map(c => ({ ...c }));   // clone so we persist a real array
      let e = cs.find(c => c.cls === pick);
      featFrom = e ? e.levels : 0;
      if (!e) { e = { cls: pick, levels: 0, subclass: '' }; cs.push(e); wasNew = true; }
      e.levels += 1;
      ss.classes = cs; _syncClassCompat(ss);
      featCls = pick; featTo = featFrom + 1;
    } else {
      featCls = ss.cls; featFrom = L.from; featTo = L.to;
      if (Array.isArray(ss.classes) && ss.classes.length) { const p = ss.classes.find(c => c.cls === ss.cls); if (p) { p.levels += (L.to - L.from); _syncClassCompat(ss); } }
    }
    // HP: reconcile from the pre-award baseline (roll or the chosen class's average).
    ss.hpMax = L.hpBase + _luChosenHp(L, ss); ss.hp = ss.hpMax;
    // Grant the features crossed for the class actually advanced.
    const feats = _featuresGained(featCls, featFrom, featTo);
    if (feats.length) ss.features = (ss.features || []).concat(feats.map(f => f.name));
    // Grow caster slots to the *combined* effective caster level across all classes.
    const eff = _effCasterLevel(_classesOf(ss));
    if (eff > 0) {
      const fresh = _fullCasterSlots(eff);
      Object.keys(fresh).forEach(l => { const old = (ss.slots || {})[l]; fresh[l].used = Math.min(old ? old.used || 0 : 0, fresh[l].max); });
      ss.slots = fresh;
    }
    // Learn the chosen spells — a level should grow the spellbook, not just the numbers.
    (L.spellPicks || []).forEach(nm => {
      const sp = SPELLS.find(x => x.name === nm);
      if (sp && !(ss.spells || []).some(x => x.name.toLowerCase() === nm.toLowerCase())) {
        ss.spells = (ss.spells || []).concat([{ name: sp.name, level: sp.level }]);
      }
    });
    // Subclass lands on the class it belongs to (each class picks at its own level 3).
    if (L.subclassPick) {
      const cs = _classesOf(ss).map(c => ({ ...c })); const e = cs.find(c => c.cls === pick);
      if (e && !e.subclass) {
        e.subclass = L.subclassPick; ss.classes = cs; _syncClassCompat(ss);   // persist so the pick survives re-sync
        const grant = SUBCLASS_GRANTS[L.subclassPick];
        if (grant && !(ss.features || []).includes(grant)) ss.features = (ss.features || []).concat([grant]);   // its Use button appears on the sheet
        if (L.subclassPick === 'Draconic Bloodline') { ss.hpMax += ss.level; ss.hp = (ss.hp || 0) + ss.level; }   // scaled resilience: +1 HP/level, retroactive
      }
    }
    // Take the chosen feats — apply their mechanical effects and record them.
    (L.featPicks || []).forEach(fn => {
      if ((ss.feats || []).includes(fn)) return;
      ss.feats = (ss.feats || []).concat([fn]);
      const F = FEATS[fn]; if (!F) return;
      if (F.hp) { const add = F.hp * ss.level; ss.hpMax += add; ss.hp = (ss.hp || 0) + add; }   // Tough: retroactive +2/level
      if (F.apply) F.apply(ss);
    });
    _saveSheet(L.cid, ss);
    const to = L.to; const learned = (L.spellPicks || []); const gotFeats = (L.featPicks || []); const gotSub = L.subclassPick || ''; _luState = null; ov.style.display = 'none';
    const mcNote = (L.multiOK && pick !== L.primary) ? ` ${wasNew ? 'Multiclassed into' : 'Advanced'} ${pick} (${featTo}).` : '';
    _appendBubble('me', `⭐ *You are now level ${to}!${mcNote}${gotSub ? ` Path chosen: ${gotSub}.` : ''}${feats.length ? ` New: ${feats.map(f => f.name.split(' (')[0]).join(', ')}.` : ''}${learned.length ? ` Learned: ${learned.join(', ')}.` : ''}${gotFeats.length ? ` Feat: ${gotFeats.join(', ')}.` : ''}*`); _scrollChat();
    const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
  });
}
// Returns 'ok' (quests surfaced), 'empty' (read fine, nothing to log), or
// 'error' (couldn't reach/parse the model).
async function _updateQuests(cid) {
  if (!_chat.char) return 'error';
  try {
    const transcript = await _fetchTranscript(); if (!transcript.length) return 'empty';
    const q = _loadQuests(cid);
    const res = await fetch(`${API_BASE}/api/characters/studio/quests`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ character_name: _chat.char.name, transcript, quests: q.quests, model: _modelLabel() }),
    });
    if (!res.ok) return 'error';
    const d = await res.json();
    if (!d.ok || !Array.isArray(d.quests)) return 'error';
    if (!d.quests.length) return 'empty';
    // Union merge — the player's manual quests are never silently dropped;
    // the LLM only updates status/desc on title matches and appends new ones.
    const byTitle = {}; (q.quests || []).forEach(x => { if (x.title) byTitle[x.title.toLowerCase()] = x; });
    let newlyDone = 0;
    d.quests.forEach(x => {
      const key = (x.title || '').toLowerCase(); if (!key) return; const p = byTitle[key];
      // `rewarded` guards XP: a quest the LLM flips done→active→done again must not
      // pay out twice.
      if (p) { const wasDone = p.status === 'done'; p.desc = x.desc || p.desc; p.status = x.status || p.status; if (p.status === 'done' && !wasDone && !p.rewarded) { newlyDone++; p.rewarded = true; } }
      else { const nq = { id: 'q-' + key.replace(/[^a-z0-9]+/g, '-'), title: x.title, desc: x.desc || '', status: x.status || 'active' }; if (nq.status === 'done') { newlyDone++; nq.rewarded = true; } byTitle[key] = nq; }
    });
    _saveQuests(cid, { quests: Object.values(byTitle), at: _meCount() });
    _reflectObjective(cid);
    if (newlyDone) _awardXp(cid, newlyDone * 75, `${newlyDone} quest${newlyDone > 1 ? 's' : ''} completed`);
    return 'ok';
  } catch { return 'error'; }
}
function openQuests() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const q = _loadQuests(cid); const s = _loadSheet(cid);
  let ov = $('studio-quests-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-quests-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const lvl = s.level || 1; const xp = s.xp || 0; const cur = _xpForLevel(lvl); const next = _xpForLevel(lvl + 1);
  const pct = Math.max(0, Math.min(100, Math.round(((xp - cur) / (next - cur)) * 100)));
  const active = (q.quests || []).filter(x => x.status !== 'done');
  const done = (q.quests || []).filter(x => x.status === 'done');
  const row = (x) => {
    const i = q.quests.indexOf(x);
    return `<li class="quest-row ${x.status === 'done' ? 'done' : ''}">
      <button class="quest-check" data-toggleq="${i}" type="button" aria-label="${x.status === 'done' ? 'Reopen quest' : 'Complete quest'}">${x.status === 'done' ? '✔' : '○'}</button>
      <div class="quest-body"><span class="quest-title">${_esc(x.title)}</span>${x.desc ? `<span class="quest-desc">${_esc(x.desc)}</span>` : ''}</div>
      <button class="rm" data-rmq="${i}" type="button" aria-label="Remove">×</button></li>`;
  };
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Quest log">
    <div class="chronicle-bar"><h2>Quest log</h2><button class="studio-close" id="quests-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <div class="xp-card"><div class="xp-top"><span class="xp-level">Level ${lvl}</span><span class="xp-num">${xp - cur} / ${next - cur} XP</span></div>
        <div class="xp-bar"><div class="xp-fill" style="width:${pct}%"></div></div></div>
      <p class="gm-hint">Goals you've taken on. It fills in as you play; the GM keeps the story pointed at your active quests. Completing a quest earns XP — enough, and you level up.</p>
      <div class="sheet-section"><h3>Active</h3><ul class="quest-list">${active.length ? active.map(row).join('') : '<li class="quest-row empty">No active quests yet.</li>'}</ul>
        <div class="add-row"><input type="text" id="quest-add" placeholder="Add a quest…"><button id="quest-add-btn" class="st-btn small" type="button">Add</button></div></div>
      ${done.length ? `<div class="sheet-section"><h3>Completed</h3><ul class="quest-list">${done.map(row).join('')}</ul></div>` : ''}
      <div class="chronicle-actions"><button class="st-btn" id="quests-refresh" type="button">↻ Update from the story</button>${s.campaignComplete
        ? '<span class="prof-bonus">🏁 THE END — this tale is told</span>'
        : (s.finaleAsked
          ? `<button class="st-btn ghost" id="quests-finale-again" type="button">↻ Continue the finale</button><button class="st-btn" id="quests-markend" type="button">🏁 Mark “THE END”</button>`
          : `<button class="st-btn ghost" id="quests-finale" type="button">🏁 Conclude the tale</button>`)}</div>
    </div></div>`;
  ov.style.display = 'flex';
  $('quests-finale')?.addEventListener('click', () => {
    if (!confirm('Bring this campaign to its ending? The GM will resolve the remaining threads and write the epilogue. You can keep playing afterward — but the tale will be told.')) return;
    ov.style.display = 'none';
    _requestFinale(cid);
  });
  $('quests-finale-again')?.addEventListener('click', () => { ov.style.display = 'none'; _requestFinale(cid); });
  $('quests-markend')?.addEventListener('click', () => {
    if (!confirm('Mark this campaign as complete? Its story archives to the Chronicle. You can still wander the epilogue afterward.')) return;
    ov.style.display = 'none';
    _appendBubble('me', `🏁 *And so the tale is told.*`); _scrollChat();
    _markComplete(cid);
  });
  $('quests-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  const addQ = () => { const v = ($('quest-add').value || '').trim(); if (!v) return; const qq = _loadQuests(cid); qq.quests = qq.quests || []; qq.quests.push({ id: 'q-' + v.toLowerCase().replace(/[^a-z0-9]+/g, '-'), title: v, desc: '', status: 'active' }); _saveQuests(cid, qq); openQuests(); };
  $('quest-add-btn').addEventListener('click', addQ);
  $('quest-add').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addQ(); } });
  ov.querySelectorAll('[data-toggleq]').forEach(b => b.addEventListener('click', () => {
    const qq = _loadQuests(cid); const x = qq.quests[Number(b.dataset.toggleq)]; if (!x) return;
    const wasDone = x.status === 'done'; x.status = wasDone ? 'active' : 'done'; _saveQuests(cid, qq);
    if (!wasDone) { _fxQuestDone(x.title); _awardXp(cid, 75, `completed “${x.title}”`); } else openQuests();
  }));
  ov.querySelectorAll('[data-rmq]').forEach(b => b.addEventListener('click', () => { const qq = _loadQuests(cid); qq.quests.splice(Number(b.dataset.rmq), 1); _saveQuests(cid, qq); openQuests(); }));
  const rb = $('quests-refresh');
  rb.addEventListener('click', async () => {
    rb.disabled = true; rb.textContent = 'Updating…';
    const r = await _updateQuests(cid);
    if (r === 'ok') { openQuests(); return; }                      // re-render with the new log
    rb.disabled = false;
    rb.textContent = r === 'empty' ? '↻ No new quests yet — try again' : "↻ Couldn't read that — try again";
    setTimeout(() => { const b = $('quests-refresh'); if (b) b.textContent = '↻ Update from the story'; }, 2800);
  });
}
function toggleQuests() { const ov = $('studio-quests-overlay'); if (ov && ov.style.display === 'flex') { ov.style.display = 'none'; return; } openQuests(); }

// ── Campaign finale: every tale deserves an ending ───────────────────────────
// The player calls for the finale; the GM resolves the open threads and writes
// an epilogue closing on "THE END" — which the post-turn watcher catches to
// mark the campaign complete (fanfare, auto-snapshot, 🏁 on the save).
function _requestFinale(cid) {
  const s = _loadSheet(cid); s.finaleAsked = true; _saveSheet(cid, s);
  const q = _loadQuests(cid);
  const active = (q.quests || []).filter(x => x.status !== 'done').map(x => x.title);
  const done = (q.quests || []).filter(x => x.status === 'done').map(x => x.title);
  const party = _companions(cid).map(c => c.name);
  _appendBubble('me', `🏁 *You steer the tale toward its ending…*`); _scrollChat();
  _streamAssistant(`[THE CAMPAIGN ENDS NOW — write its FINALE, not another normal turn. Do NOT ask what I do next; do NOT leave a cliffhanger; this is the last scene. `
    + `In two beats: (1) a cinematic climax that resolves the remaining threads${active.length ? ` (${active.join('; ')})` : ''}, honoring what came before${done.length ? ` (already resolved: ${done.join('; ')})` : ''}. `
    + `(2) an epilogue — what becomes of ${s.name || 'the hero'}${party.length ? `, of ${party.join(' and ')}` : ''}, and of the places and people this story touched. `
    + `End with the words "THE END" alone on the final line, and write nothing after them.]`);
}
// Detection (auto) and the player's manual button both route here.
function _markComplete(cid) {
  const s = _loadSheet(cid);
  if (s.campaignComplete) return;
  s.campaignComplete = true; _saveSheet(cid, s);
  _fxVictory();
  _startMusic(_chat.char && _chat.char.world_id || '');   // the world's theme returns for the credits
  _toast('🏁 Campaign complete — the tale is told. It lives on in the Chronicle.');
  try {
    const meta = JSON.parse(localStorage.getItem(LAST_ADV_KEY + '-meta') || '{}');
    meta.complete = true; localStorage.setItem(LAST_ADV_KEY + '-meta', JSON.stringify(meta));
  } catch (e) {}
  _reflectObjective(cid);
  saveSnapshot();   // the finished story archives itself
  const ov = $('studio-quests-overlay'); if (ov && ov.style.display === 'flex') openQuests();
}
// Auto-close when the GM actually cooperates and writes THE END.
function _checkFinale(cid, text) {
  const s = _loadSheet(cid);
  if (!s.finaleAsked || s.campaignComplete || !/\bTHE\s+END\b/i.test(text || '')) return;
  _markComplete(cid);
}

// ── TTS narration (Phase D) ─────────────────────────────────────────────────
const TTS_KEY = 'studio-tts';
function _ttsAvailable() { return typeof window !== 'undefined' && 'speechSynthesis' in window; }
function _loadTTS() { try { return { on: false, voice: '', rate: 1, ...(JSON.parse(localStorage.getItem(TTS_KEY) || 'null') || {}) }; } catch { return { on: false, voice: '', rate: 1 }; } }
function _saveTTS(t) { try { localStorage.setItem(TTS_KEY, JSON.stringify(t)); } catch {} }
function _speechText(raw) {
  return (raw || '')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')                                  // markdown images
    .replace(/`{1,3}[^`]*`{1,3}/g, '')                                     // code spans
    .replace(/\[[^\]]*\]/g, '')                                            // bracketed framing / labels
    .replace(/[*_#>~]/g, '')                                               // emphasis / heading marks
    .replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu, '') // emoji / dingbats
    .replace(/\s+/g, ' ').trim();
}
let _voicesCache = [];
function _ttsVoices() { if (!_ttsAvailable()) return []; const v = window.speechSynthesis.getVoices(); if (v && v.length) _voicesCache = v; return _voicesCache; }
function _pickVoice(t) {
  const voices = _ttsVoices(); if (!voices.length) return null;
  if (t.voice) { const m = voices.find(v => v.name === t.voice); if (m) return m; }
  return voices.find(v => /en[-_]/i.test(v.lang)) || voices[0];
}
function _speak(raw) {
  if (!_ttsAvailable()) return;
  const t = _loadTTS(); if (!t.on) return;
  const text = _speechText(raw); if (!text) return;
  try {
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text.slice(0, 4000));
    const v = _pickVoice(t); if (v) u.voice = v;
    u.rate = Math.max(0.5, Math.min(2, t.rate || 1));
    window.speechSynthesis.speak(u);
  } catch {}
}
function _stopSpeech() { if (_ttsAvailable()) { try { window.speechSynthesis.cancel(); } catch {} } }
function _reflectTTSBtn() {
  const b = $('studio-tts-btn'); if (!b) return;
  const t = _loadTTS();
  b.setAttribute('aria-pressed', t.on ? 'true' : 'false');
  b.classList.toggle('active', t.on);
  b.title = t.on ? 'Narration on — tap to mute' : 'Narration off — tap to hear the story aloud';
}
function toggleTTS() {
  if (!_ttsAvailable()) { _appendBubble('me', '*Narration isn\'t available in this browser.*'); return; }
  const t = _loadTTS(); t.on = !t.on; _saveTTS(t);
  if (!t.on) _stopSpeech();
  _reflectTTSBtn();
  const g = $('studio-gm-panel'); if (g && g.classList.contains('open')) renderGMPanel();
}

// ── Tactical battle-map (Phase F) ───────────────────────────────────────────
const BMAP_KEY = (cid) => `studio-bmap-${cid}`;
const MAP_COLS = 16, MAP_ROWS = 10;
function _loadBmap(cid) { try { return { pos: {}, terrain: '', ...(JSON.parse(localStorage.getItem(BMAP_KEY(cid)) || 'null') || {}) }; } catch { return { pos: {}, terrain: '' }; } }
function _saveBmap(cid, m) { try { localStorage.setItem(BMAP_KEY(cid), JSON.stringify(m)); } catch {} _pushState(cid, 'bmap', m); }
// Tokens come from the combat tracker when a fight is live, else just the hero.
function _mapTokens(cid) {
  const c = _loadCombat(cid);
  if (c.active && c.combatants && c.combatants.length) {
    return c.combatants.map(m => ({ id: m.id, name: m.name, side: m.side, hp: m.hp, hpMax: m.hpMax, down: m.hp <= 0 }));
  }
  const s = _loadSheet(cid);
  return [{ id: 'pc', name: s.name || 'You', side: 'ally', hp: s.hp, hpMax: s.hpMax, down: false }];
}
function _placeToken(el, gx, gy) { el.style.left = ((gx + 0.5) / MAP_COLS * 100) + '%'; el.style.top = ((gy + 0.5) / MAP_ROWS * 100) + '%'; }
function _wireTokenDrag(el, cid) {
  let stage = null, dragging = false;
  const move = (e) => {
    if (!dragging || !stage) return;
    const r = stage.getBoundingClientRect();
    let px = (e.clientX - r.left) / r.width * 100, py = (e.clientY - r.top) / r.height * 100;
    px = Math.max(0, Math.min(100, px)); py = Math.max(0, Math.min(100, py));
    el.style.left = px + '%'; el.style.top = py + '%';
  };
  const end = (e) => {
    if (!dragging) return; dragging = false; el.classList.remove('dragging');
    try { el.releasePointerCapture(e.pointerId); } catch {}
    const px = parseFloat(el.style.left), py = parseFloat(el.style.top);
    let gx = Math.round(px / 100 * MAP_COLS - 0.5), gy = Math.round(py / 100 * MAP_ROWS - 0.5);
    gx = Math.max(0, Math.min(MAP_COLS - 1, gx)); gy = Math.max(0, Math.min(MAP_ROWS - 1, gy));
    const m = _loadBmap(cid); m.pos[el.dataset.tok] = { gx, gy }; _saveBmap(cid, m);
    _placeToken(el, gx, gy);
  };
  el.addEventListener('pointerdown', (e) => {
    stage = $('map-stage'); dragging = true; el.classList.add('dragging');
    try { el.setPointerCapture(e.pointerId); } catch {}
    e.preventDefault();
  });
  el.addEventListener('pointermove', move);
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
}
const TERRAINS = [{ k: 'floor', label: 'Floor' }, { k: 'wall', label: 'Wall' }, { k: 'water', label: 'Water' }, { k: 'rough', label: 'Rough' }, { k: 'grass', label: 'Grass' }, { k: 'door', label: 'Door' }, { k: 'erase', label: 'Erase' }];
let _mapTab = 'world';
let _mapBrush = '';
let _painting = false;
function renderMap() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  let ov = $('studio-map-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-map-overlay'; ov.className = 'map-overlay'; modal.appendChild(ov); }
  ov.innerHTML = `<div class="map-sheet" role="dialog" aria-modal="true" aria-label="Maps">
    <div class="map-bar">
      <div class="map-tabs"><button class="map-tab${_mapTab === 'world' ? ' on' : ''}" data-mtab="world" type="button">🗺 World</button><button class="map-tab${_mapTab === 'battle' ? ' on' : ''}" data-mtab="battle" type="button">⚔ Battle</button></div>
      <div class="map-bar-right">${_mapTab === 'world' ? `<button class="st-btn small ghost" id="map-repaint" type="button" title="Paint a fresh map for this realm (clears any garbled lettering)">🎨 Repaint</button>` : ''}<button class="studio-close" id="map-close" type="button" aria-label="Close">✕</button></div>
    </div>
    <div id="map-content"></div>
  </div>`;
  ov.style.display = 'flex';
  $('map-close').addEventListener('click', () => { ov.style.display = 'none'; });
  $('map-repaint')?.addEventListener('click', () => { const wid = (_world && _world.id) || (_chat.char && _chat.char.world_id) || ''; _repaintWorldMap(wid); });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  ov.querySelectorAll('[data-mtab]').forEach(b => b.addEventListener('click', () => { _mapTab = b.dataset.mtab; renderMap(); }));
  const content = $('map-content'); const cid = _chat.char.id;
  if (_mapTab === 'world') renderAtlas(content, cid); else renderBattle(content, cid);
}
function toggleMap() { const ov = $('studio-map-overlay'); if (ov && ov.style.display === 'flex') { ov.style.display = 'none'; return; } renderMap(); _panelEnter('studio-map-overlay', 'fx-map-in'); }

// ── World atlas: travel between the world's places ──────────────────────────
const _PIN_ICON = { tavern: '🍺', shop: '🏪', landmark: '⛩', wilds: '🌲', home: '🏠', place: '📍' };
// Fog of war: only places you've stood in show their true face — the rest
// are rumors (dimmed, unlabeled marks) until you travel there.
function _markVisited(w, name) {
  if (!name) return;
  w.visited = w.visited || [];
  const n = String(name).toLowerCase();
  if (!w.visited.includes(n)) w.visited.push(n);
}
// The atlas canvas is a PAINTED region map (generated once per world).
let _worldMapBaking = false;
// Repaint on demand — clears the cached atlas (e.g. one with a garbled title
// cartouche baked in before the no-text prompt) and paints a fresh one.
async function _repaintWorldMap(wid) {
  if (!wid) return;
  try { localStorage.removeItem('studio-worldmap-' + wid); } catch {}
  _worldMapBaking = false;
  _toast('🎨 Repainting the realm — this takes a few seconds…');
  const content = $('map-content'); if (content && _mapTab === 'world' && _chat.char) renderAtlas(content, _chat.char.id);
  await _bakeWorldMap(wid);
}
async function _bakeWorldMap(wid) {
  if (!wid || _worldMapBaking) return;
  let have = null; try { have = localStorage.getItem('studio-worldmap-' + wid); } catch {}
  if (have) return;
  _worldMapBaking = true;
  try {
    const w = getWorld(wid);
    const url = await _genArt(`hand-drawn fantasy region map, ${w ? w.kind : 'high fantasy'} realm, aged cartography, mountains rivers forests and winding roads, rich muted inks, top-down view, completely unlabeled, no lettering, no writing, no title cartouche, no legend, no compass rose`, '1216x832');
    if (url) {
      try { localStorage.setItem('studio-worldmap-' + wid, url); } catch {}
      const mo = $('studio-map-overlay'); if (mo && mo.style.display === 'flex') renderMap();
    }
  } finally { _worldMapBaking = false; }
}

function renderAtlas(content, cid) {
  const w = _loadWorldS(cid); const places = w.places || [];
  const worldId = (_world && _world.id) || (_chat.char && _chat.char.world_id) || '';
  const here = (w.here || '').toLowerCase();
  if (here) { _markVisited(w, here); _saveWorldS(cid, w); }   // where you stand is known
  const visited = new Set(w.visited || []);
  let mapArt = ''; try { mapArt = localStorage.getItem('studio-worldmap-' + worldId) || ''; } catch {}
  if (!mapArt) _bakeWorldMap(worldId);   // paints in the background, re-renders when done
  const placeArt = (p) => { try { return localStorage.getItem(`studio-place-art-${worldId || cid}-${_slugify(p.name)}`) || ''; } catch { return ''; } };
  const pins = places.map((p, i) => {
    const x = p.x != null ? p.x : (12 + (i * 13) % 76); const y = p.y != null ? p.y : (16 + (i * 17) % 66);
    const isHere = here && (p.name || '').toLowerCase() === here;
    const seen = visited.has((p.name || '').toLowerCase());
    const art = seen ? placeArt(p) : '';
    const face = art
      ? `<span class="pin-art" style="background-image:url('${_esc(art)}')" aria-hidden="true"></span>`
      : `<span class="pin-ico">${seen ? (_PIN_ICON[p.kind] || '📍') : '☁'}</span>`;
    return `<button class="atlas-pin kind-${_esc(p.kind || 'place')}${isHere ? ' here' : ''}${seen ? '' : ' unseen'}" data-place="${i}" style="left:${x}%;top:${y}%" title="${_esc(p.name)}${isHere ? ' — you are here' : (seen ? '' : ' — only rumors, for now')}">${isHere ? '<span class="pin-here" aria-hidden="true"></span>' : ''}${face}<span class="pin-name">${_esc(p.name)}${isHere ? ' · you' : ''}</span></button>`;
  }).join('');
  content.innerHTML = `
    <div class="atlas-stage atlas-${_esc(worldId)}"${mapArt ? ` style="background-image:url('${_esc(mapArt)}')"` : ''}>${mapArt ? '' : '<span class="atlas-baking">🗺 The cartographer is painting this realm…</span>'}${pins || '<p class="gm-hint" style="margin:30px auto">No places known yet — explore and they\'ll appear.</p>'}</div>
    <div id="atlas-detail" class="atlas-detail" hidden></div>`;
  content.querySelectorAll('[data-place]').forEach(b => b.addEventListener('click', () => _showPlace(cid, Number(b.dataset.place))));
}
function _showPlace(cid, i) {
  const w = _loadWorldS(cid); const p = (w.places || [])[i]; const d = $('atlas-detail'); if (!d || !p) return;
  d.hidden = false;
  d.innerHTML = `<div class="ap-head"><strong>${_esc(p.name)}</strong>${p.kind ? `<span class="ap-kind">${_esc(p.kind)}</span>` : ''}</div>
    ${p.note ? `<p class="ap-lore">${_esc(p.note)}</p>` : ''}
    ${p.shop ? `<p class="ap-shop">🏪 ${_esc(p.shop)}</p>` : ''}
    <div class="ap-actions"><button class="st-btn small primary" id="ap-travel" type="button">Travel here</button>${_isVendorPlace(p) ? `<button class="st-btn small" id="ap-trade" type="button">🪙 Trade</button>` : ''}<button class="st-btn small ghost" id="ap-map" type="button" title="A drawn map of this place — its streets or rooms">🗺 Local map</button>${p.prebuilt ? '' : `<button class="st-btn small ghost" id="ap-del" type="button">Remove</button>`}</div>`;
  $('ap-travel').addEventListener('click', () => _travelTo(cid, p));
  $('ap-trade')?.addEventListener('click', () => _tradeAt(cid, p));
  $('ap-map')?.addEventListener('click', () => _openLocalMap(cid, p));
  $('ap-del')?.addEventListener('click', () => {
    // Match by name, not the render-time index — a background world update could
    // have reordered places, and a stale index would remove the wrong one.
    const ww = _loadWorldS(cid);
    const k = (ww.places || []).findIndex(x => x && (x.name || '').toLowerCase() === (p.name || '').toLowerCase());
    if (k >= 0) { ww.places.splice(k, 1); _saveWorldS(cid, ww); renderMap(); }
  });
}

// Click into a place and see ITS map — a drawn floor plan for interiors, a
// street map for settlements. Generated once per place, then cached.
async function _openLocalMap(cid, p) {
  const modal = $('studio-modal'); if (!modal || !p) return;
  const wid = (_chat.char && _chat.char.world_id) || '';
  const key = `studio-townmap-${wid || cid}-${_slugify(p.name)}`;
  let ov = $('studio-townmap-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-townmap-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const draw = (url) => {
    ov.innerHTML = `<div class="chronicle-sheet townmap-sheet" role="dialog" aria-modal="true" aria-label="Map of ${_esc(p.name)}">
      <div class="chronicle-bar"><h2>🗺 ${_esc(p.name)}</h2><button class="studio-close" id="tm-close" type="button" aria-label="Close">✕</button></div>
      <div class="chronicle-list">${url
        ? `<img class="townmap-img" src="${_esc(url)}" alt="Drawn map of ${_esc(p.name)}">`
        : `<p class="gm-hint">🖋 The cartographer is drawing ${_esc(p.name)} — a moment…</p>`}
        ${p.note ? `<p class="gm-hint">${_esc(p.note)}</p>` : ''}
        <div class="chronicle-actions"><button class="st-btn small ghost" id="tm-who" type="button" title="Ask the GM who's here right now">👥 Who's here?</button></div>
      </div></div>`;
    ov.style.display = 'flex';
    $('tm-close').addEventListener('click', () => { ov.style.display = 'none'; });
    $('tm-who')?.addEventListener('click', () => {
      ov.style.display = 'none';
      const mo = $('studio-map-overlay'); if (mo) mo.style.display = 'none';
      if (_isDM(_chat.char)) _streamAssistant(`[Who is at ${p.name} right now? Name the people present — keepers, vendors, patrons, notable locals — with one line each about what they're doing, so I know who I can approach.]`);
    });
  };
  let url = null; try { url = localStorage.getItem(key); } catch {}
  draw(url);
  if (!url) {
    const w = wid ? getWorld(wid) : null;
    const interior = ['tavern', 'shop', 'home'].includes(p.kind);
    const prompt = interior
      ? `top-down floor plan of a fantasy ${p.kind}, hand-drawn interior map with rooms, tables and counters marked, aged parchment inks, ${w ? (w.kind || 'fantasy') : 'fantasy'} style, completely unlabeled, no lettering, no writing, no title`
      : `top-down street map of a fantasy ${p.kind || 'settlement'}, hand-drawn cartography with districts, lanes and points of interest marked, aged parchment inks, ${w ? (w.kind || 'fantasy') : 'fantasy'} style, completely unlabeled, no lettering, no writing, no title`;
    const made = await _genArt(prompt, '1216x832');
    if (made) { try { localStorage.setItem(key, made); } catch {} if (ov.style.display === 'flex') draw(made); }
    else if (ov.style.display === 'flex') draw(null), _toast('⚠ The cartographer is busy — try again shortly.');
  }
}
function _travelTo(cid, p) {
  const ov = $('studio-map-overlay'); if (ov) ov.style.display = 'none';
  _fxTravel(p.name);
  const ww = _loadWorldS(cid); ww.here = p.name; _markVisited(ww, p.name); _saveWorldS(cid, ww);   // atlas "you are here" follows you; the fog lifts
  _appendBubble('me', `🧭 *You set off for **${_esc(p.name)}**.*`); _scrollChat();
  _placeBackdrop(cid, p);   // the scene behind the chat becomes THIS place
  // The road is not always safe: sometimes the journey itself becomes the scene.
  const risk = Math.random() < 0.2 ? ` On the way, run a brief encounter or striking event — perhaps ${_randEncounter().toLowerCase()}s, a traveler, or an omen — before I arrive.` : '';
  const who = ' On arrival, describe the layout of the place and NAME who is present (keepers, vendors, patrons, locals) so I know who I can talk to' + (p.shop ? ', and mention what wares are on display' : '') + '.';
  _chat.skipHereScan = true;   // you're now at p.name — don't let the arrival narration re-detect a different place
  _applyAmbient(cid);   // new place → its soundscape (tavern murmur, cave drips, forest birds…)
  if (_isDM(_chat.char)) _streamAssistant(`[I travel to ${p.name}${p.note ? ` (${p.note})` : ''}${p.shop ? `, which trades in ${p.shop}` : ''}. Narrate the journey briefly and set the scene.${who}${risk}]`);
}

// Arriving somewhere repaints the living backdrop as that location (baked once
// per place per world, then cached).
async function _placeBackdrop(cid, p) {
  const el = $('studio-backdrop'); if (!el || !p || !p.name) return;
  const wid = (_chat.char && _chat.char.world_id) || '';
  const key = `studio-place-art-${wid || cid}-${_slugify(p.name)}`;
  let url = null; try { url = localStorage.getItem(key); } catch {}
  if (!url) {
    const w = wid ? getWorld(wid) : null;
    const prompt = `${p.name}, a ${p.kind || 'place'}${p.shop ? ` trading in ${p.shop}` : ''}, ${p.note || p.lore || ''}, in ${w ? `${w.name} (${w.kind || 'fantasy'})` : 'a fantasy world'}, interior establishing shot showing the layout, atmospheric, no people, no text`;
    url = await _genArt(prompt, '1216x832');
    if (url) { try { localStorage.setItem(key, url); } catch {} }
  }
  if (url && _chat.char && _chat.char.id === cid) {
    el.style.backgroundImage = `url("${url}")`;
    el.classList.add('active');
  }
}
// Keep the atlas marker in step with the fiction: if the GM's narration names a
// known place, that's where you are now.
function _updateHereFromText(cid, text) {
  if (!text) return;
  const w = _loadWorldS(cid); const t = text.toLowerCase();
  let best = null;
  // Whole-word match, not substring — else "Well" fires on "farewell", "Ember" on "embers".
  (w.places || []).forEach(p => {
    const n = (p.name || '').toLowerCase(); if (!n || n.length <= 3) return;
    const re = new RegExp('\\b' + n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b', 'i');
    if (re.test(t) && (!best || n.length > best.length)) best = p.name;
  });
  if (best && best !== w.here) { w.here = best; _markVisited(w, best); _saveWorldS(cid, w); }
  // No named place, but the scene explicitly leaves — clear the stale marker so
  // the atlas doesn't keep you pinned to a spot you've departed.
  else if (!best && w.here && /\byou\s+(?:leave|depart|set out|set off|travel|journey|ride out|walk out|head (?:out|off|into|for))\b/i.test(t)) { w.here = ''; _saveWorldS(cid, w); }
}
// ── Vendors: a real buy/sell counter ─────────────────────────────────────────
// Wares and prices are deterministic (the UI is canon — no more "the shopkeep
// forgot the price the GM quoted"). Haggling stays a roleplay option.
const _VENDOR_STOCK = {
  weapon: [['Dagger', 8], ['Handaxe', 12], ['Shortsword', 25], ['Longsword', 40], ['Longbow', 60], ['Arrows', 3]],
  armor: [['Boots', 8], ['Helmet', 15], ['Shield', 20], ['Leather Armor', 30], ['Chain Shirt', 60]],
  potion: [['Tonic', 12], ['Antidote', 25], ['Elixir of Focus', 40], ['Potion of Healing', 50]],
  food: [['Bread', 1], ['Ale', 1], ['Meat Pie', 2], ['Cheese', 1], ['Wine', 4]],
  general: [['Torch', 1], ['Rope', 2], ['Rations', 2], ['Lantern', 6], ['Tent', 12], ['Cheap Map', 5], ['Lockpicks', 15]],
};
function _vendorCategory(shop) {
  const s = (shop || '').toLowerCase();
  if (/weapon|arms|blade|smith|gun/.test(s)) return 'weapon';
  if (/armor|armour|outfitter|gear/.test(s)) return 'armor';
  if (/potion|alchem|apothecar|remed|med/.test(s)) return 'potion';
  if (/food|tavern|inn|meal|drink|provision/.test(s)) return 'food';
  return 'general';
}
function openVendor(cid, p) {
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-vendor-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-vendor-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const cur = _currency(cid);
  const cat = _vendorCategory(_shopText(p) || p.kind);
  // A stable-but-varied shelf: the category's stock plus a couple of general goods.
  const stock = _VENDOR_STOCK[cat].concat(cat === 'general' ? [] : _VENDOR_STOCK.general.slice(0, 2));
  const render = () => {
    const s = _loadSheet(cid); const inv = _loadInv(cid);
    const wares = stock.map(([nm, price], i) =>
      `<div class="vend-row"><span class="vend-ico" aria-hidden="true">${_itemIcon(_itemType(nm), nm)}</span><span class="vend-name">${_esc(nm)}</span>
        <span class="vend-price">${price} ${_esc(cur)}</span>
        <button class="st-btn small${(s.gold || 0) >= price ? ' primary' : ''}" data-buy="${i}" type="button"${(s.gold || 0) < price ? ' disabled title="Not enough coin"' : ''}>Buy</button></div>`).join('');
    const mine = (inv.items || []).map(it =>
      `<div class="vend-row"><span class="vend-ico" aria-hidden="true">${_itemIcon(it.type, it.name)}</span><span class="vend-name">${_esc(it.name)}${it.qty > 1 ? ` ×${it.qty}` : ''}</span>
        <span class="vend-price">${_sellValue(it)} ${_esc(cur)}</span>
        <button class="st-btn small ghost" data-sell="${_esc(it.id)}" type="button">Sell</button></div>`).join('') || `<p class="gm-hint">Your pack is empty.</p>`;
    ov.innerHTML = `<div class="chronicle-sheet vendor-sheet" role="dialog" aria-modal="true" aria-label="Trade at ${_esc(p.name)}">
      <div class="chronicle-bar"><h2>🪙 ${_esc(p.name)}</h2><button class="studio-close" id="vend-close" type="button" aria-label="Close">✕</button></div>
      <div class="chronicle-list">
        <div class="pack-purse"><span aria-hidden="true">🪙</span> ${s.gold || 0} ${_esc(cur)}</div>
        <p class="vend-sub">Wares${_shopText(p) ? ` — trades in ${_esc(_shopText(p))}` : ''} <span class="gm-hint" style="display:inline;margin:0">(shops buy your goods at half value)</span></p>
        <div class="vend-list">${wares}</div>
        <p class="vend-sub">Sell from your pack</p>
        <div class="vend-list">${mine}</div>
        <div class="chronicle-actions"><button class="st-btn small ghost" id="vend-haggle" type="button" title="Talk to the keeper — roleplay a deal beyond the shelf">💬 Haggle with the keeper</button></div>
      </div></div>`;
    ov.style.display = 'flex';
    $('vend-close').addEventListener('click', () => { ov.style.display = 'none'; });
    $('vend-haggle').addEventListener('click', () => {
      ov.style.display = 'none';
      const s2 = _loadSheet(cid);
      _appendBubble('me', `🪙 *You lean on the counter at **${_esc(p.name)}**.*`); _scrollChat();
      if (_isDM(_chat.char)) _streamAssistant(`[I talk with the shopkeeper at ${p.name}${_shopText(p) ? ` (trades in ${_shopText(p)})` : ''}. I have ${s2.gold || 0} ${cur}. Their shelf stock and prices are FIXED canon: ${stock.map(([n, pr]) => `${n} ${pr} ${cur}`).join(', ')}. Haggling can move a price ~20% either way; they buy my goods at half value. When I buy, say I "pay N ${cur}" and hand me the item by name; when I sell, say I "receive N ${cur}". Play the keeper with personality.]`);
    });
    ov.querySelectorAll('[data-buy]').forEach(b => b.addEventListener('click', () => {
      const [nm, price] = stock[Number(b.dataset.buy)];
      const s2 = _loadSheet(cid);
      if ((s2.gold || 0) < price) { _toast(`Not enough ${cur}.`); return; }
      _addGold(cid, -price);
      _invAdd(cid, nm, 1);
      _fxGold(-price);
      _appendBubble('me', `🪙 *Bought ${_esc(nm)} for ${price} ${cur}.*`); _scrollChat();
      render();
    }));
    ov.querySelectorAll('[data-sell]').forEach(b => b.addEventListener('click', () => {
      _sellItem(cid, b.dataset.sell, true);
      render();
    }));
  };
  render();
}

// Browsing a shop on the map opens the vendor counter.
function _tradeAt(cid, p) {
  const ov = $('studio-map-overlay'); if (ov) ov.style.display = 'none';
  openVendor(cid, p);
}

// ── Battle map: paintable terrain tiles + tokens ────────────────────────────
function renderBattle(content, cid) {
  const m = _loadBmap(cid); const tokens = _mapTokens(cid); m.tiles = m.tiles || {};
  const c = _loadCombat(cid);
  const order = c.active && c.combatants && c.combatants.length ? _combatOrder(c) : [];
  const cur = order.length ? order[c.turn % order.length] : null;
  let ai = 0, ei = 0;
  const tokenEls = tokens.map(t => {
    let p = m.pos[t.id];
    if (!p) { if (t.side === 'enemy') { p = { gx: 4 + (ei % 8), gy: 1 + Math.floor(ei / 8) }; ei++; } else { p = { gx: 4 + (ai % 8), gy: MAP_ROWS - 2 - Math.floor(ai / 8) }; ai++; } }
    const init = (t.name || '?').slice(0, 1).toUpperCase();
    const pct = t.hpMax ? Math.max(0, Math.min(100, Math.round((t.hp / t.hpMax) * 100))) : 100;
    return `<div class="map-token side-${_esc(t.side || 'ally')}${t.down ? ' down' : ''}${cur && t.id === cur.id ? ' cur' : ''}" data-tok="${_esc(t.id)}" style="left:${(p.gx + 0.5) / MAP_COLS * 100}%;top:${(p.gy + 0.5) / MAP_ROWS * 100}%" title="${_esc(t.name)} — ${t.hp}/${t.hpMax} HP">
      <span class="mt-init">${_esc(init)}</span><span class="mt-hp"><span class="mt-hpfill" style="width:${pct}%"></span></span><span class="mt-name">${_esc(t.name)}</span></div>`;
  }).join('');
  const turnBar = c.active ? `<div class="map-turnbar"><span>⚔ Round ${c.round} — ${cur ? (cur.id === 'pc' ? '<strong>Your turn</strong>' : `<strong>${_esc(cur.name)}</strong>'s turn`) : '—'}</span><span class="map-turn-btns"><button class="st-btn small primary" id="map-next-turn" type="button">Next ›</button><button class="st-btn small" id="map-end-combat" type="button">End</button></span></div>` : '';
  let cells = '';
  for (let gy = 0; gy < MAP_ROWS; gy++) for (let gx = 0; gx < MAP_COLS; gx++) { const t = m.tiles[gx + ',' + gy]; cells += `<div class="map-cell${t ? ' t-' + t : ''}" data-cell="${gx},${gy}"></div>`; }
  // The terrain-tile painter is cosmetic (tiles carry no mechanics), so it's a
  // GM/prep tool — hidden from players, who get the auto-painted underlay +
  // draggable tokens. GM mode brings the brushes back.
  const gm = _gmMode();
  const palette = gm ? TERRAINS.map(t => `<button class="terr-btn t-${t.k}${_mapBrush === t.k ? ' on' : ''}" data-brush="${t.k}" type="button">${t.label}</button>`).join('') : '';
  content.innerHTML = `
    ${turnBar}
    <div class="map-tools">${gm ? `<span class="terr-palette">${palette}</span>` : ''}
      <button class="st-btn small ghost" id="map-terrain-btn" type="button">🖼 ${m.terrain ? 'Repaint map' : 'Paint the map'}</button>${m.terrain ? `<button class="st-btn small ghost" id="map-terrain-clear" type="button">Clear img</button>` : ''}
      ${gm ? `<button class="st-btn small ghost" id="map-tiles-clear" type="button">Clear terrain</button>` : ''}<button class="st-btn small ghost" id="map-reset" type="button">Reset tokens</button></div>
    <div class="map-stage${m.terrain ? ' has-underlay' : ''}" id="map-stage">
      ${m.terrain ? `<img class="map-terrain" src="${_esc(m.terrain)}" alt="" aria-hidden="true">` : ''}
      <div class="map-cells" id="map-cells">${cells}</div>
      ${tokenEls}
    </div>
    <p class="gm-hint">Drag tokens to move them; the cast syncs from combat.${gm ? ' Pick a terrain and drag across the grid to sketch rooms.' : ''}</p>`;
  content.querySelectorAll('.map-token').forEach(el => _wireTokenDrag(el, cid));
  content.querySelectorAll('[data-brush]').forEach(b => b.addEventListener('click', () => { _mapBrush = (_mapBrush === b.dataset.brush ? '' : b.dataset.brush); renderMap(); }));
  _wireTilePaint(cid);
  $('map-next-turn')?.addEventListener('click', () => {
    const cc = _loadCombat(cid); if (!cc.active) return;
    const ord = _combatOrder(cc); const ending = ord[cc.turn % (ord.length || 1)];
    if (ending && ending.conditions) ending.conditions = ending.conditions.map(cd => (cd && typeof cd === 'object' && cd.rounds != null) ? { ...cd, rounds: cd.rounds - 1 } : cd).filter(cd => !(cd && typeof cd === 'object' && cd.rounds != null && cd.rounds <= 0));
    const n = cc.combatants.length || 1; cc.turn += 1; if (cc.turn >= n) { cc.turn = 0; cc.round += 1; }
    _saveCombat(cid, cc); renderMap();
    const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) renderCombatPanel();
  });
  $('map-end-combat')?.addEventListener('click', () => {
    const cc = _loadCombat(cid);
    const slain = (cc.combatants || []).filter(x => x.side === 'enemy' && x.hp <= 0);
    const defeated = slain.length;
    const xpWon = slain.reduce((t, m) => t + Math.max(25, (m.hpMax || 10) * 2), 0);   // tough foes teach more
    _syncCompanionsFromCombat(cid, cc.combatants);
    _saveCombat(cid, { active: false, round: 1, turn: 0, combatants: [] });
    _portraitTried.clear(); _exitCombatMode(cid);
    const ov = $('studio-map-overlay'); if (ov) ov.style.display = 'none';
    const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) renderCombatPanel();
    if (defeated) {
      _awardXp(cid, xpWon, `${defeated} ${defeated > 1 ? 'foes' : 'foe'} defeated`);
      if (_isDM(_chat.char)) _streamAssistant(`[The fight is over — ${defeated} ${defeated > 1 ? 'foes lie' : 'foe lies'} fallen. Briefly narrate the aftermath and anything worth looting from the fallen or the scene; if I take something, name the item plainly.]`);
    }
  });
  $('map-reset')?.addEventListener('click', () => { const mm = _loadBmap(cid); mm.pos = {}; _saveBmap(cid, mm); renderMap(); });
  $('map-tiles-clear')?.addEventListener('click', () => { const mm = _loadBmap(cid); mm.tiles = {}; _saveBmap(cid, mm); renderMap(); });
  $('map-terrain-clear')?.addEventListener('click', () => { const mm = _loadBmap(cid); mm.terrain = ''; _saveBmap(cid, mm); renderMap(); });
  $('map-terrain-btn')?.addEventListener('click', async () => {
    const btn = $('map-terrain-btn'); btn.disabled = true; btn.textContent = 'Painting…';
    const mm = _loadBmap(cid); mm.terrain = ''; mm.terrainSig = ''; _saveBmap(cid, mm);   // force a fresh, scene-matched paint
    const cc = _loadCombat(cid); const foe = (cc.combatants || []).find(x => x.side === 'enemy');
    await _ensureBattleUnderlay(cid, foe ? foe.name : '', '');
    renderMap();
  });
}
// Auto-paint the battle map to look like WHERE the fight is happening (the
// current place, or the scene text) instead of a generic dungeon room. Cached by
// place so the same location reuses its map; skipped while the art forge cools.
async function _ensureBattleUnderlay(cid, enemy, sceneText) {
  if (Date.now() - _artFailAt < 120000) return;
  let here = '', note = '';
  try { const w = _loadWorldS(cid); here = w.here || ''; const p = (w.places || []).find(pp => (pp.name || '').toLowerCase() === here.toLowerCase()); note = (p && (p.note || p.kind)) || ''; } catch {}
  const scene = here ? `${here}${note ? ` — ${note}` : ''}` : (sceneText || '').replace(/\s+/g, ' ').slice(0, 120);
  const sig = (scene || 'field').toLowerCase().slice(0, 60);
  const mm = _loadBmap(cid);
  if (mm.terrain && mm.terrainSig === sig) return;   // already have this place's map
  const wid = _chat.char && _chat.char.world_id; const w = wid ? getWorld(wid) : null;
  try {
    const prompt = `top-down tabletop RPG battle map of ${scene || 'an open fighting ground'}${w ? `, ${w.kind || 'high fantasy'} world` : ''}, overhead bird's-eye view, hand-painted, muted natural colors, clear open floor for miniatures, atmospheric, no characters, no tokens, no text, no grid lines`;
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt, size: '1024x1024' }) });
    const gd = await r.json().catch(() => ({}));
    if (gd.ok && gd.image_url) { const m2 = _loadBmap(cid); m2.terrain = gd.image_url; m2.terrainSig = sig; _saveBmap(cid, m2); const ov = $('studio-map-overlay'); if (ov && ov.style.display === 'flex' && _mapTab === 'battle') renderMap(); }
  } catch {}
}
function _wireTilePaint(cid) {
  const cells = $('map-cells'); if (!cells) return;
  const paint = (el) => {
    if (!el || !el.dataset.cell || !_mapBrush) return;
    const mm = _loadBmap(cid); mm.tiles = mm.tiles || {};
    if (_mapBrush === 'erase') delete mm.tiles[el.dataset.cell]; else mm.tiles[el.dataset.cell] = _mapBrush;
    _saveBmap(cid, mm); el.className = 'map-cell' + (_mapBrush === 'erase' ? '' : ' t-' + _mapBrush);
  };
  cells.querySelectorAll('.map-cell').forEach(c => {
    c.addEventListener('pointerdown', (e) => { if (!_mapBrush) return; _painting = true; paint(c); e.preventDefault(); });
    c.addEventListener('pointerenter', () => { if (_painting) paint(c); });
  });
  document.addEventListener('pointerup', () => { _painting = false; }, { once: true });
}

// ── Slot inventory (Phase: physical pack) ───────────────────────────────────
const INV_KEY = (cid) => `studio-inv-${cid}`;
const INV_SLOTS = 24;
const _RARITY_ORD = { legendary: 0, epic: 1, rare: 2, uncommon: 3, common: 4 };
function _titleCase(s) { return (s || '').replace(/\b\w/g, c => c.toUpperCase()); }
function _itemType(name) {
  const n = (name || '').toLowerCase();
  if (/potion|elixir|tonic|vial|flask|draught|antidote|stimpak|\bstim\b|inhaler|syringe/.test(n)) return 'potion';
  if (/bread|food|meat|apple|cheese|ration|\bale\b|wine|water|meal|stew|fruit|noodle|coffee|protein bar/.test(n)) return 'food';
  // Worn gear, by body slot (checked before generic weapon/treasure).
  if (/helm|helmet|\bhat\b|\bcap\b|hood|crown|circlet|coif|visor|goggles|\bmask\b/.test(n)) return 'head';
  if (/amulet|necklace|pendant|collar|choker|gorget/.test(n)) return 'neck';
  if (/cloak|cape|mantle|trenchcoat|\bcoat\b|poncho/.test(n)) return 'back';
  if (/gauntlet|gloves|bracers|\bgrips\b|mittens/.test(n)) return 'hands';
  if (/\bbelt\b|sash|girdle|holster|bandolier/.test(n)) return 'waist';
  if (/leggings|\bpants\b|trousers|breeches|greaves|chaps|leg ?guard/.test(n)) return 'legs';
  if (/boots|sandals|\bshoes\b|sabatons|footwear/.test(n)) return 'feet';
  if (/\bring\b/.test(n)) return 'ring';
  if (/shield|buckler|aegis/.test(n)) return 'shield';
  if (/armou?r|\bmail\b|\bplate\b|breastplate|cuirass|\brobe\b|tunic|\bshirt\b|\bvest\b|jacket|jerkin|chestpiece|bodysuit/.test(n)) return 'chest';
  if (/sword|blade|dagger|axe|mace|spear|\bbow\b|staff|wand|hammer|club|knife|weapon|crossbow|pistol|rifle|\bgun\b|katana|\bbaton\b|blaster|polearm/.test(n)) return 'weapon';
  if (/charm|talisman|brooch|locket|idol|trinket/.test(n)) return 'trinket';
  if (/gold|coin|silver|copper|\bgem\b|jewel|diamond|ruby|emerald|sapphire|treasure|bullion|credits?|\bchip\b/.test(n)) return 'treasure';
  if (/\bkey\b|keyring|keycard|passcard/.test(n)) return 'key';
  if (/scroll|book|tome|\bmap\b|\bnote\b|letter|parchment|deed|writ|journal|datapad|\bdisk\b/.test(n)) return 'document';
  if (/torch|lantern|rope|\btool\b|\bkit\b|tinder|flint|shovel|\bpick\b|chain|grapple|lockpick/.test(n)) return 'tool';
  return 'misc';
}
function _itemIcon(type, name) {
  const n = (name || '').toLowerCase();
  if (/bow|crossbow/.test(n)) return '🏹'; if (/\bhat\b|\bcap\b/.test(n)) return '🎩'; if (/crown|circlet/.test(n)) return '👑';
  if (/gold|coin|bullion|credit/.test(n)) return '🪙'; if (/gem|jewel|diamond|ruby|emerald|sapphire/.test(n)) return '💎';
  if (/scroll|deed|writ|letter/.test(n)) return '📜'; if (/book|tome|journal/.test(n)) return '📖'; if (/\bmap\b/.test(n)) return '🗺️';
  if (/torch|lantern/.test(n)) return '🔥'; if (/bread|food|meat|stew|meal/.test(n)) return '🍞'; if (/ale|wine/.test(n)) return '🍺'; if (/rope|chain/.test(n)) return '🪢';
  return ({ potion: '🧪', food: '🍖', head: '🪖', neck: '📿', back: '🧥', chest: '👕', hands: '🧤', waist: '🎗️', legs: '👖', feet: '🥾', ring: '💍', shield: '🛡️', weapon: '⚔️', treasure: '💰', key: '🗝️', document: '📜', trinket: '💍', tool: '🧰', misc: '📦', armor: '🛡️' })[type] || '📦';
}
function _rarityOf(name) {
  const n = (name || '').toLowerCase();
  if (/legendary|artifact|ancient|divine|mythic|fabled/.test(n)) return 'legendary';
  if (/epic|enchanted|magic|glowing|runed|cursed/.test(n)) return 'epic';
  if (/rare|fine|masterwork|silver|ornate/.test(n)) return 'rare';
  if (/uncommon|sturdy|quality|polished/.test(n)) return 'uncommon';
  return 'common';
}
// ponytail: flat per-type weights, tuned so a full class kit sits at ~60-70%
// of a low-STR hero's capacity (kits used to over-encumber at character birth).
function _itemWeight(type) { const w = { weapon: 2, shield: 4, chest: 4, armor: 4, head: 1.5, legs: 2, feet: 1.5, back: 1.5, hands: 1, waist: 0.5, neck: 0.1, ring: 0.05, potion: 0.5, treasure: 0.1, key: 0.1, document: 0.2, food: 0.3, trinket: 0.2, tool: 1.5, misc: 1 }[type]; return w == null ? 1 : w; }
// Paper-doll slots. label is per-world (_ = default); types lists item types the slot accepts.
const _EQUIP_SLOTS = [
  { key: 'head', types: ['head'], icon: '🪖', label: { _: 'Head', embervale: 'Helm', neonspire: 'Headgear', everyday: 'Hat' } },
  { key: 'neck', types: ['neck', 'trinket'], icon: '📿', label: { _: 'Neck', embervale: 'Amulet', neonspire: 'Implant', everyday: 'Necklace' } },
  { key: 'back', types: ['back'], icon: '🧥', label: { _: 'Back', embervale: 'Cloak', neonspire: 'Trenchcoat', everyday: 'Jacket' } },
  { key: 'chest', types: ['chest', 'armor'], icon: '👕', label: { _: 'Body', embervale: 'Armor', neonspire: 'Bodywear', everyday: 'Shirt' } },
  { key: 'hands', types: ['hands'], icon: '🧤', label: { _: 'Hands', embervale: 'Gauntlets', neonspire: 'Gloves', everyday: 'Gloves' } },
  { key: 'waist', types: ['waist'], icon: '🎗️', label: { _: 'Waist', embervale: 'Belt', neonspire: 'Utility belt', everyday: 'Belt' } },
  { key: 'legs', types: ['legs'], icon: '👖', label: { _: 'Legs', embervale: 'Greaves', neonspire: 'Legwear', everyday: 'Pants' } },
  { key: 'feet', types: ['feet'], icon: '🥾', label: { _: 'Feet', embervale: 'Boots', neonspire: 'Boots', everyday: 'Shoes' } },
  { key: 'ring', types: ['ring', 'trinket'], icon: '💍', label: { _: 'Ring', embervale: 'Ring', neonspire: 'Chip', everyday: 'Ring' } },
  { key: 'weapon', types: ['weapon'], icon: '⚔️', label: { _: 'Weapon', embervale: 'Weapon', neonspire: 'Weapon', everyday: 'Tool' } },
  { key: 'offhand', types: ['shield', 'weapon'], icon: '🛡️', label: { _: 'Off-hand', embervale: 'Off-hand', neonspire: 'Off-hand', everyday: 'Off-hand' } },
];
function _slotLabel(slot, worldId) { return (slot.label && (slot.label[worldId] || slot.label._)) || slot.key; }
// Generous by design: a starting kit should sit at ~60% load, not "encumbered
// at birth". STR 8 → 20, STR 10 → 22, STR 15 → 27, STR 20 → 32.
function _carryCap(cid) { const s = _loadSheet(cid); return Math.max(14, 12 + ((s.abilities && s.abilities.STR) || 10)); }
// Worn gear carries itself: equipped items count HALF toward your load.
function _invWeight(inv) {
  const worn = new Set(Object.values(inv.equipped || {}).filter(Boolean));
  return inv.items.reduce((t, it) => t + (it.wt == null ? _itemWeight(it.type) : it.wt) * (it.qty || 1) * (worn.has(it.id) ? 0.5 : 1), 0);
}
function _weaponDie(name) {
  const n = (name || '').toLowerCase();
  if (/dagger|knife|sickle|dart/.test(n)) return '1d4';
  if (/greatsword|greataxe|maul|halberd|glaive|pike|claymore/.test(n)) return '1d12';
  if (/longsword|battleaxe|warhammer|morningstar|flail|longbow|trident|crossbow|broadsword/.test(n)) return '1d8';
  if (/shortsword|scimitar|rapier|shortbow|handaxe|mace|spear|whip|club|staff|quarterstaff/.test(n)) return '1d6';
  return '1d6';
}
function _armorAcBonus(name) {
  const n = (name || '').toLowerCase();
  if (/full plate|^plate|plate armor/.test(n)) return 6;
  if (/half.?plate|breastplate|chain ?mail|splint|banded/.test(n)) return 4;
  if (/scale|chain shirt|brigandine|ring mail|hide/.test(n)) return 3;
  if (/leather|padded|studded/.test(n)) return 2;
  if (/shield|buckler/.test(n)) return 2;
  if (/cloak|robe|cloth/.test(n)) return 1;
  return 2;
}
function _mkItem(name, slot, qty) {
  const nm = (name || 'item').trim(); const type = _itemType(nm); const rarity = _rarityOf(nm);
  const it = { id: 'it-' + Math.random().toString(36).slice(2, 9), name: nm, qty: qty || 1, type, rarity, wt: _itemWeight(type), img: '', slot: (slot == null ? -1 : slot) };
  if (type === 'weapon') { it.dmg = _weaponDie(nm); it.atk = ({ rare: 1, epic: 1, legendary: 2 })[rarity] || 0; }
  // Worn gear can ward: body uses armor value, shield +2, any magic piece +1/+2.
  const WEAR = ['head', 'neck', 'back', 'chest', 'armor', 'hands', 'waist', 'legs', 'feet', 'ring', 'shield'];
  if (WEAR.includes(type)) {
    let ac = (type === 'chest' || type === 'armor') ? _armorAcBonus(nm) : (type === 'shield') ? 2 : 0;
    ac += ({ epic: 1, legendary: 2 })[rarity] || 0;
    if (ac > 0) it.acBonus = ac;
  }
  return it;
}
function _equippedItem(inv, key) { const id = inv.equipped && inv.equipped[key]; return id ? (inv.items.find(x => x.id === id) || null) : null; }
function _hasClass(s, cls) { return _classesOf(s).some(c => c.cls === cls); }
function _hasBodyArmor(inv) { const eq = (inv && inv.equipped) || {}; return ['body', 'armor', 'chest', 'torso'].some(k => eq[k]); }
function _bodyArmorItem(inv) { for (const k of ['body', 'armor', 'chest', 'torso']) { const it = _equippedItem(inv, k); if (it) return it; } return null; }
// Base armor class = 10 + DEX, plus a class's Unarmored Defense when no body
// armor is worn (Barbarian +CON, Monk +WIS). ponytail: worn armor still adds its
// flat acBonus on top (the light additive item model) — a full armor-category
// table with a heavy-armor DEX cap is the future refinement.
function _baseAC(s, inv) {
  let dex = _mod((s.abilities && s.abilities.DEX) || 10);
  // 5e armor caps DEX: heavy ignores it, medium caps at +2. We infer the armor's
  // weight class from its flat acBonus (added on top in _effAC): plate ~+8, chain
  // shirt ~+3, leather ~+1. Light armor (and none) keeps full DEX.
  const body = _bodyArmorItem(inv);
  if (body) { const b = body.acBonus || 0; if (b >= 6) dex = 0; else if (b >= 3) dex = Math.min(dex, 2); }
  let ac = 10 + dex;
  if (!_hasBodyArmor(inv)) {
    if (_hasClass(s, 'Barbarian')) ac += Math.max(0, _mod((s.abilities && s.abilities.CON) || 10));
    else if (_hasClass(s, 'Monk')) ac += Math.max(0, _mod((s.abilities && s.abilities.WIS) || 10));
  }
  return ac;
}
function _effAC(cid) {
  const s = _loadSheet(cid); const inv = _loadInv(cid);
  if (s.acOverride != null && s.acOverride !== '') return Number(s.acOverride);   // GM mode: manual AC wins
  let ac = _baseAC(s, inv);
  Object.values(inv.equipped || {}).forEach(id => { const it = inv.items.find(x => x.id === id); if (it && it.acBonus) ac += it.acBonus; });
  return ac;
}
function _shortRest(cid) {
  const s = _loadSheet(cid);
  // Spend one Hit Die from your pool (max = level, refreshed on a long rest):
  // roll your real class die + CON. Out of dice = a breather that still recharges
  // short-rest features but heals nothing.
  const pool = s.level || 1;
  const used = s.hitDiceUsed || 0;
  const con = _mod((s.abilities && s.abilities.CON) || 10);
  let heal = 0, note;
  if (used < pool) {
    const die = s.hitDie || 8;
    heal = Math.max(1, 1 + Math.floor(Math.random() * die) + con);
    s.hp = Math.min(s.hpMax, (s.hp || 0) + heal);
    s.hitDiceUsed = used + 1;
    note = `🌙 *You take a short rest — spend a Hit Die (d${die}${con >= 0 ? '+' : ''}${con} CON) and recover **${heal} HP**, now ${s.hp}/${s.hpMax}. Hit Dice left: ${pool - s.hitDiceUsed}/${pool}.*`;
  } else {
    note = `🌙 *You rest an hour, but you're out of Hit Dice (${pool}/${pool} spent) — features recharge, but a long rest is what you need to heal.*`;
  }
  _saveSheet(cid, s);
  _rechargeFeatures(cid, 'short');
  _healCompanions(cid, 0.5);
  _advanceTime(cid, 1);
  _fxRest('short');
  _appendBubble('me', note); _scrollChat();
  const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
  if (_isDM(_chat.char)) _streamAssistant(`[I take a short rest${heal ? `, recovering ${heal} HP` : ' but I am out of Hit Dice'}. Briefly narrate the pause, then continue.]`);
}
function _spellText(cid) {
  const s = _loadSheet(cid);
  if (!s.spells || !s.spells.length) return '';
  const known = s.spells.map(sp => `${sp.name}${sp.level ? ` (lvl ${sp.level})` : ' (cantrip)'}`).join(', ');
  const slots = Object.keys(s.slots || {}).filter(l => (s.slots[l].max || 0) > 0)
    .map(l => `L${l} ${Math.max(0, (s.slots[l].max || 0) - (s.slots[l].used || 0))}/${s.slots[l].max}`).join(', ');
  let t = `The player knows these spells: ${known}.`;
  const dc = _spellSaveDC(s);
  if (dc != null) t += ` Their spell save DC is ${dc} and spell attack bonus +${_spellAttack(s)} — when a spell forces a save or an attack, use these numbers.`;
  if (slots) t += ` Spell slots remaining: ${slots}. Don't let them cast a leveled spell with no slot left.`;
  if (s.concentration) t += ` They are concentrating on ${s.concentration.name}; it ends if their concentration breaks.`;
  return t.slice(0, 900);
}
// ── Game feel: transient effects (spells, loot, gold, level-ups) ─────────────
// Every effect is decorative and self-removing; all are skipped under
// prefers-reduced-motion so the game stays fully usable without motion.
function _fxReduced() { try { return window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } }
function _fxLayer() {
  const modal = $('studio-modal'); if (!modal) return null;
  let l = $('studio-fx');
  if (!l) { l = document.createElement('div'); l.id = 'studio-fx'; l.className = 'studio-fx'; l.setAttribute('aria-hidden', 'true'); modal.appendChild(l); }
  return l;
}
function _fxSpawn(html, ms) {
  const l = _fxLayer(); if (!l) return null;
  const tmp = document.createElement('div'); tmp.innerHTML = html;
  const node = tmp.firstElementChild; if (!node) return null;
  l.appendChild(node); setTimeout(() => node.remove(), ms);
  return node;
}
// Guess a spell's "school" from its name → an accent colour + effect class.
function _spellSchool(name) {
  const n = (name || '').toLowerCase();
  if (/fire|flame|burn|scorch|ember|meteor|inferno|blaze/.test(n)) return { c: '#ff8a3d', g: '#ffd08a', k: 'fire', ico: '🔥' };
  if (/ice|frost|cold|freeze|chill|winter|snow/.test(n)) return { c: '#6fd3ff', g: '#d6f4ff', k: 'ice', ico: '❄' };
  if (/lightning|shock|thunder|storm|bolt|electric/.test(n)) return { c: '#a9b8ff', g: '#e6ecff', k: 'shock', ico: '⚡' };
  if (/heal|cure|life|bless|light|holy|radiant|restore|mend/.test(n)) return { c: '#ffe28a', g: '#fff6d6', k: 'holy', ico: '✚' };
  if (/poison|acid|necro|death|shadow|curse|drain|rot/.test(n)) return { c: '#8fe38f', g: '#d6ffd6', k: 'venom', ico: '☠' };
  if (/mind|charm|psychic|sleep|fear|illusion|dream/.test(n)) return { c: '#d29cff', g: '#f0e0ff', k: 'mind', ico: '❂' };
  return { c: '#b79cf6', g: '#e6dcff', k: 'arcane', ico: '✦' };
}
// A cast: glyph flare + expanding ring + radiating sparks, coloured by school.
function _fxSpell(name, level) {
  if (_fxReduced()) return;
  const s = _spellSchool(name);
  const sparks = Array.from({ length: 12 }, (_, i) =>
    `<span class="fx-spark" style="--a:${Math.round((i / 12) * 360)}deg;--d:${70 + Math.round(Math.random() * 80)}px;--t:${320 + Math.round(Math.random() * 360)}ms"></span>`).join('');
  _fxSpawn(`<div class="fx-cast fx-${s.k}" style="--c:${s.c};--g:${s.g}"><span class="fx-glyph">${s.ico}</span><span class="fx-ring"></span>${sparks}<span class="fx-castname">${_esc(name)}</span></div>`, 1200);
}
// A looted item flies from the loot bar up into the Pack button, which bumps.
function _fxItemGet(name, icon) {
  _sfx('loot');
  if (_fxReduced()) return;
  const target = $('studio-pack-btn') || $('studio-sheet-btn'); const l = _fxLayer(); if (!l) return;
  const lr = l.getBoundingClientRect();
  let tx = lr.width / 2, ty = lr.height * 0.12;
  if (target) { const r = target.getBoundingClientRect(); tx = r.left + r.width / 2 - lr.left; ty = r.top + r.height / 2 - lr.top; }
  const node = document.createElement('div'); node.className = 'fx-itemget';
  node.style.setProperty('--tx', tx + 'px'); node.style.setProperty('--ty', ty + 'px');
  node.innerHTML = `<span class="fx-item-ico">${icon || '🎁'}</span><span class="fx-item-name">${_esc(name)}</span>`;
  l.appendChild(node); setTimeout(() => node.remove(), 1300);
  if (target) { target.classList.add('fx-bump'); setTimeout(() => target.classList.remove('fx-bump'), 520); }
}
// Coins scatter + a floating amount near the Pack button on any gold change.
function _fxGold(amount) {
  if (amount) _sfx('gold');
  if (_fxReduced() || !amount) return;
  const anchor = $('studio-pack-btn') || $('studio-sheet-btn'); const l = _fxLayer(); if (!l) return;
  const lr = l.getBoundingClientRect(); let x = lr.width / 2, y = lr.height * 0.14;
  if (anchor) { const r = anchor.getBoundingClientRect(); x = r.left + r.width / 2 - lr.left; y = r.top + r.height / 2 - lr.top; }
  const n = Math.min(9, Math.max(3, Math.round(Math.abs(amount) / 12) + 3));
  const coins = Array.from({ length: n }, (_, i) => `<span class="fx-coin" style="--dx:${Math.round(Math.random() * 70 - 35)}px;--dl:${i * 45}ms">🪙</span>`).join('');
  _fxSpawn(`<div class="fx-gold ${amount < 0 ? 'spend' : ''}" style="left:${x}px;top:${y}px">${coins}<span class="fx-gold-amt">${amount > 0 ? '+' : ''}${amount}</span></div>`, 1300);
}
// A golden shockwave + banner on levelling up.
function _fxLevelUp() {
  _sfx('level');
  if (_fxReduced()) return;
  _fxSpawn(`<div class="fx-levelup"><span class="fx-lu-ring"></span><span class="fx-lu-ring d2"></span><span class="fx-lu-text">LEVEL&nbsp;UP</span></div>`, 2000);
}
// Floating combat text rising off a token row + a hit-flash on the row.
function _fxCombatFloat(rowEl, change) {
  if (_fxReduced() || !change || !rowEl) return;
  const l = _fxLayer(); if (!l) return;
  const r = rowEl.getBoundingClientRect(); const lr = l.getBoundingClientRect();
  const x = r.left + r.width * 0.5 - lr.left, y = r.top + 10 - lr.top;
  const heal = change > 0;
  _fxSpawn(`<div class="fx-cbfloat ${heal ? 'heal' : 'dmg'}" style="left:${x}px;top:${y}px">${heal ? '+' : ''}${change}</div>`, 1100);
  rowEl.classList.add(heal ? 'fx-flash-heal' : 'fx-flash-dmg');
  setTimeout(() => rowEl.classList.remove('fx-flash-heal', 'fx-flash-dmg'), 420);
}
// Nat-20: golden starburst + "CRITICAL!"
function _fxCrit() {
  _sfx('crit');
  if (_fxReduced()) return;
  const rays = Array.from({ length: 14 }, (_, i) => `<span class="fx-ray" style="--a:${Math.round((i / 14) * 360)}deg;--t:${420 + Math.round(Math.random() * 240)}ms"></span>`).join('');
  _fxSpawn(`<div class="fx-crit">${rays}<span class="fx-crit-text">CRITICAL!</span></div>`, 1300);
}
// Quest complete: a wax-seal stamp.
function _fxQuestDone(title) {
  _sfx('quest');
  if (_fxReduced()) return;
  _fxSpawn(`<div class="fx-questdone"><span class="fx-qd-seal">✔</span><span class="fx-qd-text">Quest Complete</span>${title ? `<span class="fx-qd-sub">${_esc(title)}</span>` : ''}</div>`, 2000);
}
// Equip: a shimmer sweep across the just-filled paper-doll slot.
function _fxEquipShimmer(slotKey) {
  if (_fxReduced() || !slotKey) return;
  const slot = document.querySelector(`[data-equip="${slotKey}"]`);
  if (!slot) return;
  slot.classList.add('fx-shimmer'); setTimeout(() => slot.classList.remove('fx-shimmer'), 720);
}
// Rest: a soft sweep across the scene — moon (short) or dawn (long).
function _fxRest(kind) {
  if (_fxReduced()) return;
  _fxSpawn(`<div class="fx-rest fx-rest-${kind}"><span class="fx-rest-ico">${kind === 'long' ? '🌅' : '🌙'}</span></div>`, 1700);
}
// Death save: a red heartbeat vignette pulse.
function _fxHeartbeat() {
  if (_fxReduced()) return;
  _fxSpawn(`<div class="fx-heartbeat"></div>`, 950);
}
// Screen shake on impact.
function _fxShake() {
  if (_fxReduced()) return;
  const root = $('studio-chat') || $('studio-modal'); if (!root) return;
  root.classList.remove('fx-shake'); void root.offsetWidth; root.classList.add('fx-shake');
  setTimeout(() => root.classList.remove('fx-shake'), 520);
}

// ── Combat mode: auto-detect fights, stage the foe, feel the blows ───────────
const _portraitTried = new Set();
function _enemyHpGuess(name) {
  const n = (name || '').toLowerCase();
  let hp;
  if (/dragon|giant|troll|ogre|golem|demon|wyvern|hydra|behemoth|titan|bear|owlbear|minotaur|elemental/.test(n)) hp = 30 + Math.floor(Math.random() * 20);
  else if (/knight|warrior|guard|bandit|mercenary|cultist|orc|gnoll|hobgoblin|zombie|ghoul|wolf|boar|construct|drone|enforcer|brute|soldier/.test(n)) hp = 14 + Math.floor(Math.random() * 12);
  else if (/goblin|kobold|rat|bat|spider|imp|sprite|thug|snake|slime|skeleton|servitor|drone|scavenger/.test(n)) hp = 6 + Math.floor(Math.random() * 7);
  else hp = 12 + Math.floor(Math.random() * 8);
  // Foes keep pace with the hero: +20% per level past 1st.
  // ponytail: flat multiplier, not a bestiary — per-world threat tables if it matters.
  const lvl = _chat.char ? (_loadSheet(_chat.char.id).level || 1) : 1;
  return Math.round(hp * (1 + 0.2 * (lvl - 1)));
}
const _COMBAT_VERBS = 'attacks?|lunges?|charges?|strikes? at you|swings? at you|springs?|pounces?|snarls?|growls?|roars?|blocks? your|bars? your|emerges?|draws? (?:a |its |his |her )?(?:weapon|blade|sword)|rushes? (?:at |toward )you|ambush(?:es)?|attacks!';
// Detect a fight kicking off + the foe's name from the GM's narration.
// A candidate foe must read like a creature, not a fragment of GM prose —
// "a spell to aid your attack" once spawned a combatant named "Spell To Aid Your".
function _plausibleFoe(n) {
  if (!n || n.length < 3) return false;
  // A foe is a short noun, not a clause. More than 3 words is a sentence
  // fragment the regex grabbed ("the mine shaft as you charge" → "mine shaft
  // as you"), so reject it outright.
  if (n.trim().split(/\s+/).length > 3) return false;
  // Rules vocabulary and abstractions read like "<Name> attacks" to the regex
  // ("an opportunity attack…" once spawned a 12 HP foe named Opportunity).
  if (/\b(?:spell|strain|attack|attempt|effort|roll|save|check|throw|note|failure|failed|aid|magic|mayhem|blow|strike|swing|turn|round|damage|scene|story|moment|option|chance|way|plan|idea|question|opportunity|reaction|advantage|disadvantage|initiative|inspiration|perception|surprise|condition|action|bonus|movement|challenge|threat|danger|risk|possibility|memory|thought|feeling|instinct|urge|impulse)\b/i.test(n)) return false;
  // Function words / pronouns betray a fragment rather than a creature name.
  if (/\b(?:your|my|this|that|these|those|to|will|would|could|can|you|i|we|as|and|but|with|into|from|near|upon|while|when|where|here|there|is|are|was|were|has|have|had|shaft|entrance|wall|floor|ceiling|corridor|chamber|doorway)\b/i.test(n)) return false;
  return true;
}
function _detectCombatStart(text) {
  if (!text) return null;
  const initiative = /\broll(?:ing)?\s+(?:for\s+)?initiative\b|combat begins|the fight is on|battle is joined/i.test(text);
  const re = new RegExp(`\\b(?:a|an|the)\\s+([a-z][a-z' -]{2,32}?)\\s+(?:${_COMBAT_VERBS})`, 'i');
  const m = re.exec(text);
  let enemy = m ? m[1].trim() : '';
  enemy = enemy.replace(/^(?:sudden|nearby|massive|huge|towering|hulking|snarling|angry|hostile|great|dark|shadowy|looming|fierce|wild)\s+/i, '').trim();
  if (!_plausibleFoe(enemy)) enemy = '';
  if (!enemy && initiative) enemy = 'Enemy';
  if (!enemy) return null;
  if (/^(?:air|wind|door|gate|voice|silence|moment|feeling|tension|figure|shape|sound|noise|smell|thought|shiver|chill|storm|world|ground|floor|realization)\b/i.test(enemy)) return initiative ? { enemy: 'Enemy' } : null;
  return { enemy: _titleCase(enemy) };
}
function _enterCombat(cid, enemy, sceneText) {
  const cc = _loadCombat(cid);
  if (cc.active) {   // already fighting — just make sure a new foe joins the board
    if (enemy && enemy !== 'Enemy' && !cc.combatants.some(x => x.side === 'enemy' && x.name.toLowerCase() === enemy.toLowerCase())) {
      // cc.turn is a position in the init-sorted order; adding a combatant re-sorts
      // it, so pin the current creature by id and restore its index after the push.
      const ord0 = _combatOrder(cc); const curId = ord0.length ? (ord0[cc.turn % ord0.length] || {}).id : null;
      const hp = _enemyHpGuess(enemy); const eid = 'e' + cc.combatants.length + '_' + enemy.replace(/\s+/g, '');
      cc.combatants.push({ id: eid, name: enemy, hp, hpMax: hp, ac: null, init: 1 + Math.floor(Math.random() * 20), side: 'enemy', conditions: [] });
      if (curId) { const idx = _combatOrder(cc).findIndex(x => x.id === curId); if (idx >= 0) cc.turn = idx; }
      _saveCombat(cid, cc); renderCombatPanel();
    }
    return;
  }
  const sheet = _loadSheet(cid), hp0 = _enemyHpGuess(enemy);
  const player = { id: 'pc', name: sheet.name || 'You', hp: sheet.hp || 10, hpMax: sheet.hpMax || 10, ac: _effAC(cid), init: _initiative(sheet), side: 'ally', conditions: [] };
  const allies = _companions(cid).map((c, i) => { const chp = (c.hp != null) ? c.hp : (c.hpMax || 1); return { id: 'cmp' + i, name: c.name, hp: Math.max(0, chp), hpMax: c.hpMax || chp || 1, ac: c.ac || 12, init: 1 + Math.floor(Math.random() * 20), side: 'ally', conditions: [] }; });
  const eid = 'e1_' + enemy.replace(/\s+/g, '');
  const foe = { id: eid, name: enemy, hp: hp0, hpMax: hp0, ac: null, init: 1 + Math.floor(Math.random() * 20), side: 'enemy', conditions: [] };
  _saveCombat(cid, { active: true, round: 1, turn: 0, combatants: [player, ...allies, foe] });
  _enterCombatMode(cid, enemy, sceneText);
  renderCombatPanel();   // auto-open the tracker
}
function _enterCombatMode(cid, enemy, sceneText) {
  const modal = $('studio-modal'); if (modal) modal.classList.add('in-combat');
  _startMusic('combat');
  _applyAmbient(cid);   // swap the soundscape to the low combat rumble
  _ensureBattleUnderlay(cid, enemy, sceneText);   // paint a map of the ACTUAL place, not a generic room
  _sfx('crit');   // a sting to mark the shift
  _appendBubble('me', `⚔️ *Combat — ${_esc(enemy)}!*`); _scrollChat();
  _combatBackdrop(cid, enemy, sceneText);
  setTimeout(() => _openBattleMap(), 700);   // pull up the tactical map with the foes placed
}
function _openBattleMap() { _mapTab = 'battle'; renderMap(); }
// Close the books on a fight: XP for the slain, companions synced, aftermath
// narrated. Runs from the End button AND automatically when the last foe falls
// (victory used to leave the fight "active" with no XP until End was pressed).
function _finishCombat(cid) {
  const cc = _loadCombat(cid);
  if (!cc.active && !(cc.combatants || []).length) return;   // already finished
  const slain = (cc.combatants || []).filter(m => m.side === 'enemy' && m.hp <= 0);
  const defeated = slain.length;
  const xpWon = slain.reduce((t, m) => t + Math.max(25, (m.hpMax || 10) * 2), 0);   // tough foes teach more
  _syncCompanionsFromCombat(cid, cc.combatants);
  _saveCombat(cid, { active: false, round: 1, turn: 0, combatants: [] });
  _portraitTried.clear();
  _exitCombatMode(cid);
  renderCombatPanel();
  if (defeated) {
    _awardXp(cid, xpWon, `${defeated} ${defeated > 1 ? 'foes' : 'foe'} defeated`);
    // The Fiend's pact pays out on a kill: temporary vitality.
    const s2 = _loadSheet(cid);
    if (_isSubclass(s2, 'The Fiend')) {
      const gain = Math.max(1, (s2.level || 1) + _mod((s2.abilities || {}).CHA || 10));
      s2.hp = Math.min(s2.hpMax, (s2.hp || 0) + gain); _saveSheet(cid, s2);
      _appendBubble('me', `🔥 *Dark One's Blessing — your patron feeds on the kill: **+${gain} HP** (now ${s2.hp}/${s2.hpMax}).*`); _scrollChat();
    }
    if (_chat.hdywtdt) _chat.hdywtdt = false;   // the killing-blow message already asked for the aftermath
    else if (_isDM(_chat.char)) _streamAssistant(`[The fight is over — ${defeated} ${defeated > 1 ? 'foes lie' : 'foe lies'} fallen. Briefly narrate the aftermath and anything worth looting from the fallen or the scene; if I take something, name the item plainly.]`);
  }
}

function _exitCombatMode(cid) {
  const modal = $('studio-modal'); if (modal) modal.classList.remove('in-combat');
  if (_chat.char) _startMusic(_chat.char.world_id || '');
  _applyAmbient(cid);   // combat over → back to the scene's ambience
  const wid = _chat.char && _chat.char.world_id;
  if (wid) { try { const u = localStorage.getItem(BACKDROP_KEY(wid)); const el = $('studio-backdrop'); if (u && el) { el.style.backgroundImage = `url("${u}")`; el.classList.add('active'); } } catch (e) {} }
}
// Regenerate the backdrop for the fight (so the scene actually changes).
function _combatBackdrop(cid, enemy, sceneText) {
  const wid = _chat.char && _chat.char.world_id; if (!wid) return;
  const locale = _sceneLocale(sceneText);
  const style = { embervale: 'painterly fantasy', neonspire: 'neon cyberpunk', everyday: 'cinematic realism' }[wid] || 'cinematic';
  _applyBackdrop(wid, `${style}, dramatic battle scene, a ${enemy}${locale ? ` in a ${locale}` : ''}, dynamic lighting, high detail, no text`);
}
function _sceneLocale(text) {
  if (!text) return '';
  const m = /\b(mine\s*shaft|mine|cave|cavern|forest|woods|dungeon|crypt|tomb|ruins?|temple|castle|keep|tower|swamp|marsh|alley|street|rooftop|warehouse|sewer|bridge|clearing|chamber|hall|throne room|market|tavern|camp|cliff|shore|beach|desert|catacombs?)\b/i.exec(text);
  return m ? m[1].toLowerCase() : '';
}
async function _genEnemyPortrait(cid, combatantId, name) {
  const wid = _chat.char && _chat.char.world_id;
  // If this foe is a known beast that already has a conjured lorebook picture,
  // reuse it — the creature you fight looks like its codex entry, no extra GPU.
  const entry = _bestiaryFor(name);
  const setImg = (url, persistSlug) => {
    const cc = _loadCombat(cid); const m = cc.combatants.find(x => x.id === combatantId);
    if (m) { m.img = url; _saveCombat(cid, cc); const p = $('studio-combat-panel'); if (p && p.classList.contains('open')) renderCombatPanel(); }
    if (persistSlug) { const la = _loadLoreArt(); if (!la[persistSlug]) { la[persistSlug] = url; _saveLoreArt(la); } }   // feed the lorebook too
  };
  if (entry && entry.slug) { const cached = _loadLoreArt()[entry.slug]; if (cached) { setImg(cached); return; } }
  const style = { embervale: 'fantasy creature concept art', neonspire: 'cyberpunk enemy concept art', everyday: 'realistic photo' }[wid] || 'concept art';
  try {
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: `${style}, a menacing ${name}, full body, dramatic, dark background, no text`, size: '768x768' }),
    });
    const d = await r.json();
    if (d.ok && d.image_url) setImg(d.image_url, entry && entry.slug);
  } catch (e) { /* portrait is decorative */ }
}
// Detect damage dealt TO the player and apply it — with a visible roll + shake.
function _detectPlayerDamage(text) {
  if (!text) return 0;
  // "3 feet", "3 times", "3 gold" aren't damage — the number must not be a unit/count.
  const NOTUNIT = '(?!\\s*(?:feet|foot|ft|inch|inches|yards?|paces?|steps?|times|seconds?|minutes?|hours?|rounds?|days?|weeks?|miles?|meters?|metres?|gold|silver|coins?|gp))';
  let a = 0, b = 0, m;
  const re1 = new RegExp(`\\byou(?:r character)?\\s+(?:take|takes|taking|suffer|suffers|sustain|sustains|lose|loses|are dealt|is dealt|receive|receives)\\s+(\\d{1,3})\\s+(?:points?\\s+of\\s+)?(?:damage|hit points?|hp)\\b`, 'gi');
  while ((m = re1.exec(text))) a += Math.min(999, parseInt(m[1], 10) || 0);
  const re2 = new RegExp(`\\b(?:hits?|strikes?|slams?|claws?|bites?|catches?|deals?)\\s+you\\s+(?:for\\s+)?(\\d{1,3})${NOTUNIT}\\b`, 'gi');
  while ((m = re2.exec(text))) b += Math.min(999, parseInt(m[1], 10) || 0);
  // ponytail: re1 ("you take N damage") and re2 ("X hits you for N") almost always
  // restate the SAME blow two ways, so take the larger — not the sum. Undercounts
  // the rare two-distinct-hits-in-one-message case, which is the player-friendly miss.
  return Math.max(a, b);
}
// Apply a chunk of damage to the hero with the real 5e trimmings: Half-Orc
// Relentless Endurance catches a killing blow once per rest, and any damage
// forces a concentration save. Returns the message tail to append.
function _applyDamageToSheet(cid, dmg) {
  const s = _loadSheet(cid);
  let raw = Math.max(0, (s.hp || 0) - dmg);
  let extra = '';
  // Relentless Endurance (Half-Orc): the first time a blow would drop you, cling on at 1.
  const h = _heritageOf(s);
  if (raw <= 0 && (s.hp || 0) > 0 && h && h.relentless && !s.relentlessUsed) {
    raw = 1; s.relentlessUsed = true;
    extra = ' — **Relentless Endurance** keeps you standing at 1 HP!';
  }
  s.hp = raw;
  // Concentration save: DC 10 or half the damage taken, whichever is higher.
  let concMsg = '';
  if (s.concentration && dmg > 0 && s.hp > 0) {
    const dc = Math.max(10, Math.floor(dmg / 2));
    const conMod = _mod((s.abilities && s.abilities.CON) || 10) + ((s.profSaves || []).includes('CON') ? _profBonus(s) : 0);
    const r1 = 1 + Math.floor(Math.random() * 20), r2 = 1 + Math.floor(Math.random() * 20);
    const roll = s.featWarCaster ? Math.max(r1, r2) : r1;   // War Caster: advantage to hold concentration
    const total = roll + conMod;
    const wc = s.featWarCaster ? ' [War Caster: adv]' : '';
    if (total < dc && roll !== 20) { concMsg = ` Concentration on ${s.concentration.name} breaks (CON save ${total} vs DC ${dc}${wc}) — the spell ends.`; s.concentration = null; }
    else { concMsg = ` You hold concentration on ${s.concentration.name} (CON save ${total} vs DC ${dc}${wc}).`; }
  }
  _saveSheet(cid, s);
  return { hp: s.hp, hpMax: s.hpMax, extra, concMsg };
}
function _applyPlayerDamage(cid, text) {
  const dmg = _detectPlayerDamage(text);
  if (!dmg) return;
  const apply = () => {
    const r = _applyDamageToSheet(cid, dmg);
    const cc = _loadCombat(cid); const pc = cc.combatants.find(x => x.id === 'pc'); if (pc) { pc.hp = r.hp; if (pc.hp <= 0) pc.ds = pc.ds || { s: 0, f: 0 }; _saveCombat(cid, cc); }
    _sfx('hit'); _fxShake();
    const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) { renderCombatPanel(); _fxCombatFloat(document.querySelector('#studio-combat-panel .cb-row.ally'), -dmg); }
    const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
    _appendBubble('me', `💥 *You take **${dmg}** damage — ${Math.max(0, r.hp)}/${r.hpMax} HP.${r.extra}${r.concMsg}*`); _scrollChat();
    if (r.concMsg && _isDM(_chat.char) && /breaks/.test(r.concMsg)) _streamAssistant(`[My concentration broke — ${text.slice(0, 60)}. The spell I was maintaining ends now.]`);
  };
  const sides = dmg < 6 ? 6 : dmg < 8 ? 8 : dmg < 10 ? 10 : dmg < 12 ? 12 : 20;   // a die big enough to show the number
  _animateDie(sides, dmg, null, null, apply);
}
// Auto-roll the GM's incoming-damage dice instead of asking the player to.
function _diceExpr(str) {
  const m = /(\d*)d(\d+)\s*([+-]\s*\d+)?/i.exec(str || '');
  if (!m) return null;
  const n = Math.min(20, Math.max(1, parseInt(m[1] || '1', 10)));
  const sides = Math.min(100, Math.max(2, parseInt(m[2], 10)));
  const mod = m[3] ? parseInt(m[3].replace(/\s+/g, ''), 10) : 0;
  return { n, sides, mod };
}
// Detect "roll for damage from the ogre (d6+4)" / "hits you for 2d6+3" etc.
function _detectIncomingDamageRoll(text) {
  if (!text) return null;
  let m = /(?:roll[^.]*?damage\s+from|damage\s+from)[^.()\n]*?\(?\s*(\d*d\d+\s*[+-]?\s*\d*)\s*\)?/i.exec(text);
  if (m && /d\d/i.test(m[1])) return _diceExpr(m[1]);
  m = /(?:hits?|strikes?|slams?|claws?|bites?|deals?)\s+you\s+(?:for\s+)?\(?\s*(\d*d\d+\s*[+-]?\s*\d*)\s*\)?/i.exec(text);
  if (m && /d\d/i.test(m[1])) return _diceExpr(m[1]);
  return null;
}
function _rollIncoming(cid, dice) {
  let first = 1 + Math.floor(Math.random() * dice.sides), total = dice.mod + first;
  for (let i = 1; i < dice.n; i++) total += 1 + Math.floor(Math.random() * dice.sides);
  total = Math.max(0, total);
  const expr = `${dice.n}d${dice.sides}${dice.mod ? (dice.mod > 0 ? '+' : '') + dice.mod : ''}`;
  const apply = () => {
    const r = _applyDamageToSheet(cid, total);   // Relentless Endurance + concentration save ride along
    const cc = _loadCombat(cid); const pc = cc.combatants.find(x => x.id === 'pc'); if (pc) { pc.hp = r.hp; if (pc.hp <= 0) pc.ds = pc.ds || { s: 0, f: 0 }; _saveCombat(cid, cc); }
    _sfx('hit'); _fxShake();
    const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) { renderCombatPanel(); _fxCombatFloat(document.querySelector('#studio-combat-panel .cb-row.ally'), -total); }
    const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
    _appendBubble('me', `💥 *Enemy attack — ${expr} → **${total}** damage. You're at ${Math.max(0, r.hp)}/${r.hpMax} HP.${r.extra}${r.concMsg}*`); _scrollChat();
  };
  _animateDie(dice.sides, first, null, null, apply);   // show the die; the bubble gives the full total
}
// A cinematic title card when you enter a chat/adventure.
function _fxTitleCard(title, sub) {
  if (_fxReduced() || !title) return;
  _fxSpawn(`<div class="fx-title"><span class="fx-title-t">${_esc(title)}</span>${sub ? `<span class="fx-title-s">${_esc(sub)}</span>` : ''}</div>`, 2600);
}
// Drinking a potion: a coloured splash + rising bubbles.
function _fxPotion(heal) {
  _sfx('potion');
  if (_fxReduced()) return;
  const bubbles = Array.from({ length: 8 }, (_, i) => `<span class="fx-bub" style="--dx:${Math.round(Math.random() * 44 - 22)}px;--dl:${i * 55}ms"></span>`).join('');
  _fxSpawn(`<div class="fx-potion ${heal ? 'heal' : ''}"><span class="fx-pot-ico">🧪</span>${bubbles}</div>`, 1300);
}
// Fast-travel: a wipe with the destination name.
function _fxTravel(name) {
  if (_fxReduced()) return;
  _fxSpawn(`<div class="fx-travel"><span class="fx-travel-t">Traveling to ${_esc(name)}…</span></div>`, 1500);
}
// One-shot panel entrance (restarts the animation each open, never on re-render
// because it's only called from the toggle openers, not renderX).
function _panelEnter(id, cls) {
  if (_fxReduced()) return;
  const el = $(id); if (!el) return;
  el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls);   // force reflow to replay
  setTimeout(() => el.classList.remove(cls), 660);
}

// ── Sound: tiny synthesized SFX via Web Audio (no asset files) ───────────────
// Independent of prefers-reduced-motion (that governs motion, not audio); gated
// by its own on/off flag. All SFX fire from click handlers, so the AudioContext
// resumes on a real user gesture and autoplay policy is satisfied.
let _audioCtx = null;
// Real CC0 samples (static/audio/sfx/<name>.<ogg|mp3|wav>) override the synth
// when present; missing files fall back to the synthesized tone below.
const _sfxBuffers = {};
let _sfxLoaded = false;
function _sfxOn() { try { return localStorage.getItem('studio-sfx') !== '0'; } catch (e) { return true; } }
function _setSfx(on) { try { localStorage.setItem('studio-sfx', on ? '1' : '0'); } catch (e) {} }
function _reflectSfxBtn() { const b = $('studio-sfx-btn'); if (!b) return; const on = _sfxOn(); b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); const ico = b.querySelector('.sfx-ico'); if (ico) ico.textContent = on ? '🔊' : '🔇'; }
function _toggleSfx() { _setSfx(!_sfxOn()); _reflectSfxBtn(); if (_sfxOn()) { _sfx('loot'); if (_chat.char) { _startMusic(_chat.char.world_id || ''); _applyAmbient(_chat.char.id); } } else { _stopMusic(); _stopAmbient(); } }
function _ac() { if (!_audioCtx) { try { _audioCtx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) {} } return _audioCtx; }
function _tone(ctx, freq, t0, dur, type, gain) {
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.type = type || 'sine'; o.frequency.setValueAtTime(freq, t0);
  g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(gain || 0.12, t0 + 0.012); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  o.connect(g); g.connect(ctx.destination); o.start(t0); o.stop(t0 + dur);
}
function _sfx(name) {
  if (!_sfxOn()) return;
  const ctx = _ac(); if (!ctx) return;
  try { if (ctx.state === 'suspended') ctx.resume(); } catch (e) {}
  if (!_sfxLoaded) { _sfxLoaded = true; _loadSfxAssets(); }   // lazy preload on first gesture
  if (_sfxBuffers[name]) {   // a real sample is loaded — play it instead of the synth
    try { const s = ctx.createBufferSource(); s.buffer = _sfxBuffers[name]; const g = ctx.createGain(); g.gain.value = 0.75; s.connect(g); g.connect(ctx.destination); s.start(); return; } catch (e) {}
  }
  const t = ctx.currentTime;
  switch (name) {
    case 'dice': {
      const buf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.2), ctx.sampleRate); const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 2);
      const s = ctx.createBufferSource(); s.buffer = buf; const g = ctx.createGain(); g.gain.value = 0.14; s.connect(g); g.connect(ctx.destination); s.start(t); break;
    }
    case 'crit': _tone(ctx, 1320, t, 0.5, 'triangle', 0.16); _tone(ctx, 1760, t + 0.05, 0.5, 'triangle', 0.1); break;
    case 'loot': _tone(ctx, 660, t, 0.12, 'sine', 0.13); _tone(ctx, 880, t + 0.09, 0.18, 'sine', 0.12); break;
    case 'gold': _tone(ctx, 1200, t, 0.07, 'square', 0.06); _tone(ctx, 1560, t + 0.05, 0.08, 'square', 0.05); break;
    case 'level': [523, 659, 784, 1047].forEach((f, i) => _tone(ctx, f, t + i * 0.09, 0.32, 'triangle', 0.13)); break;
    case 'victory': [523, 659, 784, 1047, 1319].forEach((f, i) => _tone(ctx, f, t + i * 0.11, 0.42, 'triangle', 0.14)); break;
    case 'potion': _tone(ctx, 400, t, 0.26, 'sine', 0.1); _tone(ctx, 720, t + 0.12, 0.2, 'sine', 0.08); break;
    case 'quest': _tone(ctx, 784, t, 0.28, 'triangle', 0.13); _tone(ctx, 1047, t + 0.12, 0.3, 'triangle', 0.11); break;
    case 'hit': {   // a low thud for taking a blow
      _tone(ctx, 90, t, 0.22, 'sawtooth', 0.18); _tone(ctx, 60, t + 0.02, 0.26, 'square', 0.12);
      const buf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.12), ctx.sampleRate); const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 3);
      const s = ctx.createBufferSource(); s.buffer = buf; const g = ctx.createGain(); g.gain.value = 0.12; s.connect(g); g.connect(ctx.destination); s.start(t); break;
    }
  }
}

// Fetch + decode any present CC0 sample files into buffers (once). Tries a few
// extensions; a 404 just means "use the synth for that one".
async function _loadSfxAssets() {
  const ctx = _ac(); if (!ctx) return;
  const names = ['dice', 'crit', 'loot', 'gold', 'level', 'victory', 'potion', 'quest'];
  await Promise.all(names.map(async (name) => {
    for (const ext of ['ogg', 'mp3', 'wav']) {
      try {
        const r = await fetch(`${API_BASE}/static/audio/sfx/${name}.${ext}`, { cache: 'force-cache' });
        if (!r.ok) continue;
        _sfxBuffers[name] = await ctx.decodeAudioData(await r.arrayBuffer());
        return;
      } catch (e) { /* missing/undecodable → try next ext, else synth */ }
    }
  }));
}

// Per-world looping ambience: a real file (static/audio/music/<world>.<ext>)
// when present, else a generative Web-Audio pad — so the game is never silent.
let _musicEl = null, _musicWorld = null, _synth = null;
function _stopSynthMusic() {
  if (!_synth) return;
  try { clearInterval(_synth.timer); _synth.master.gain.linearRampToValueAtTime(0, _ac().currentTime + 0.8); const nodes = _synth.oscs; setTimeout(() => nodes.forEach(o => { try { o.stop(); } catch (e) {} }), 900); } catch (e) {}
  _synth = null;
}
function _stopMusic() { if (_musicEl) { try { _musicEl.pause(); } catch (e) {} } _musicEl = null; _musicWorld = null; _stopSynthMusic(); }
// Chord palettes (Hz roots, semitone offsets) tuned per world's mood.
const _SYNTH_MOODS = {
  embervale: { root: 146.83, chords: [[0, 3, 7, 14], [-2, 2, 7, 12], [0, 5, 8, 12], [-4, 3, 7, 10]], wave: 'triangle', pace: 13000, cutoff: 900, vol: 0.05 },   // D-minor folk warmth
  neonspire: { root: 110.0, chords: [[0, 7, 12, 19], [-2, 5, 10, 17], [0, 3, 10, 15], [-5, 2, 7, 14]], wave: 'sawtooth', pace: 11000, cutoff: 520, vol: 0.035 }, // dark A fifths
  everyday:  { root: 174.61, chords: [[0, 4, 7, 11], [5, 9, 12, 16], [-3, 0, 4, 9], [2, 5, 9, 14]], wave: 'sine', pace: 15000, cutoff: 1200, vol: 0.05 },        // F-maj7 ease
  combat:    { root: 130.81, chords: [[0, 3, 7, 12], [-1, 3, 6, 12], [0, 3, 8, 11], [1, 4, 7, 13]], wave: 'sawtooth', pace: 5200, cutoff: 700, vol: 0.045 },     // C-minor tension
  custom:    { root: 138.59, chords: [[0, 3, 7, 12], [-2, 2, 7, 10], [0, 5, 8, 15], [-4, 0, 7, 12]], wave: 'triangle', pace: 13000, cutoff: 800, vol: 0.045 },   // arcane C# minor
};
function _startSynthMusic(worldId) {
  const ctx = _ac(); if (!ctx) return;
  const mood = _SYNTH_MOODS[worldId] || _SYNTH_MOODS.custom;
  _stopSynthMusic();
  try {
    const master = ctx.createGain(); master.gain.value = 0;
    const filter = ctx.createBiquadFilter(); filter.type = 'lowpass'; filter.frequency.value = mood.cutoff; filter.Q.value = 0.6;
    // A slow LFO breathes the filter so the pad never sits still.
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.05;
    const lfoGain = ctx.createGain(); lfoGain.gain.value = mood.cutoff * 0.35;
    lfo.connect(lfoGain); lfoGain.connect(filter.frequency);
    filter.connect(master); master.connect(ctx.destination);
    const oscs = [], gains = [];
    for (let i = 0; i < 4; i++) {
      const o = ctx.createOscillator(); o.type = mood.wave;
      const g = ctx.createGain(); g.gain.value = 0;
      o.detune.value = (i % 2 ? 4 : -4);   // gentle chorus shimmer
      o.connect(g); g.connect(filter); o.start();
      oscs.push(o); gains.push(g);
    }
    let ci = 0;
    const setChord = () => {
      const chord = mood.chords[ci % mood.chords.length]; ci++;
      const t = ctx.currentTime;
      chord.forEach((semi, i) => {
        const f = mood.root * Math.pow(2, semi / 12);
        oscs[i].frequency.setTargetAtTime(f, t, 2.2);          // voices glide, never jump
        gains[i].gain.setTargetAtTime(0.22 + (i === 0 ? 0.06 : 0), t, 2.2);
      });
    };
    setChord();
    const timer = setInterval(setChord, mood.pace);
    master.gain.linearRampToValueAtTime(mood.vol, ctx.currentTime + 3);
    lfo.start();
    _synth = { master, oscs: oscs.concat([lfo]), timer };
  } catch (e) { /* no audio — stay silent */ }
}
function _startMusic(worldId) {
  if (!_sfxOn() || !worldId) return;
  if (_musicWorld === worldId && (_synth || (_musicEl && !_musicEl.paused))) return;
  _stopMusic();
  _musicWorld = worldId;
  const exts = ['ogg', 'mp3', 'wav'], el = new Audio();
  let i = 0;
  const tryNext = () => {
    if (i >= exts.length) { _startSynthMusic(worldId); return; }   // no file → generative pad
    el.src = `${API_BASE}/static/audio/music/${worldId}.${exts[i++]}`;
  };
  el.loop = true; el.volume = 0; el.preload = 'auto';
  el.addEventListener('error', tryNext);   // .ogg missing → try .mp3 → synth
  tryNext();
  el.play().then(() => {
    _musicEl = el;
    const t0 = (typeof performance !== 'undefined') ? performance.now() : 0, target = 0.26;   // gentle fade-in
    const step = () => { if (_musicEl !== el) return; const k = Math.min(1, ((performance.now() - t0) / 1600)); el.volume = target * k; if (k < 1) requestAnimationFrame(step); };
    requestAnimationFrame(step);
  }).catch(() => { /* autoplay blocked — starts on the next interaction via the toggle */ });
}

// ── Reactive ambient soundscape ──────────────────────────────────────────────
// A generative bed (filtered noise + a sparse "detail" layer) that shifts with
// the scene — time of day, where you are, and combat. No audio files: everything
// is synthesized on the shared AudioContext, gated by the SFX toggle + its own
// volume, and it rides UNDER the music pad.
let _amb = null, _ambProfile = null;
function _ambOn() { try { return localStorage.getItem('studio-ambient') !== '0'; } catch { return true; } }
function _ambVol() { try { const v = parseFloat(localStorage.getItem('studio-ambient-vol')); return isNaN(v) ? 0.6 : Math.max(0, Math.min(1, v)); } catch { return 0.6; } }
const _AMB_PROFILES = {
  day:    { type: 'lowpass', cut: 520,  q: 0.6, vol: 0.09, wob: 0.06 },
  night:  { type: 'bandpass', cut: 3200, q: 5,  vol: 0.05, wob: 0.03, detail: { every: 850, freq: 4200, dur: 0.07, gain: 0.05, jit: 0.5 } },  // crickets
  rain:   { type: 'lowpass', cut: 1500, q: 0.7, vol: 0.16, wob: 0.02, detail: { every: 120, freq: 6000, dur: 0.02, gain: 0.02, jit: 1 } },   // patter
  forest: { type: 'lowpass', cut: 720,  q: 0.5, vol: 0.10, wob: 0.09, detail: { every: 2600, freq: 2800, dur: 0.05, gain: 0.03, jit: 0.9 } },// birds/rustle
  tavern: { type: 'lowpass', cut: 360,  q: 0.8, vol: 0.13, wob: 0.04, detail: { every: 1400, freq: 210, dur: 0.13, gain: 0.03, jit: 0.7 } }, // murmur
  cave:   { type: 'lowpass', cut: 230,  q: 1.2, vol: 0.12, wob: 0.02, detail: { every: 3400, freq: 950, dur: 0.03, gain: 0.05, jit: 0.9 } }, // drips
  combat: { type: 'lowpass', cut: 190,  q: 1.6, vol: 0.14, wob: 0.01, rumble: true },
};
function _noiseBuffer(ctx, secs) {
  const buf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * secs), ctx.sampleRate), d = buf.getChannelData(0);
  let last = 0;
  for (let i = 0; i < d.length; i++) { const w = Math.random() * 2 - 1; last = (last + 0.02 * w) / 1.02; d[i] = last * 3.4; }   // brown-ish noise
  return buf;
}
function _stopAmbient() {
  if (!_amb) return;
  const a = _amb; _amb = null; _ambProfile = null;
  try { const ctx = _ac(); a.master.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.6); clearInterval(a.detailTimer);
    setTimeout(() => { try { a.src.stop(); } catch {} try { a.lfo && a.lfo.stop(); } catch {} try { a.rumble && a.rumble.stop(); } catch {} }, 700);
  } catch {}
}
function _startAmbient(name) {
  const ctx = _ac(); if (!ctx) return;
  if (_ambProfile === name && _amb) return;
  const p = _AMB_PROFILES[name] || _AMB_PROFILES.day;
  _stopAmbient(); _ambProfile = name;
  try {
    if (ctx.state === 'suspended') ctx.resume();
    const master = ctx.createGain(); master.gain.value = 0; master.connect(ctx.destination);
    const filter = ctx.createBiquadFilter(); filter.type = p.type; filter.frequency.value = p.cut; filter.Q.value = p.q; filter.connect(master);
    const src = ctx.createBufferSource(); src.buffer = _noiseBuffer(ctx, 3); src.loop = true; src.connect(filter); src.start();
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.07; const lg = ctx.createGain(); lg.gain.value = p.cut * p.wob; lfo.connect(lg); lg.connect(filter.frequency); lfo.start();
    let rumble = null;
    if (p.rumble) { rumble = ctx.createOscillator(); rumble.type = 'sawtooth'; rumble.frequency.value = 46; const rg = ctx.createGain(); rg.gain.value = 0.05; rumble.connect(rg); rg.connect(master); rumble.start(); }
    let detailTimer = null;
    if (p.detail) {
      const dt = p.detail;
      detailTimer = setInterval(() => {
        if (!_amb || !_ambOn()) return;
        _tone(ctx, dt.freq * (1 + (Math.random() - 0.5) * dt.jit), ctx.currentTime, dt.dur, 'sine', dt.gain * _ambVol());
      }, dt.every * (0.6 + Math.random() * 0.8));
    }
    master.gain.linearRampToValueAtTime(p.vol * _ambVol(), ctx.currentTime + 1.5);
    _amb = { master, src, lfo, rumble, detailTimer, base: p.vol };
  } catch {}
}
// Read the current scene and pick the bed: combat > weather/place > time of day.
function _ambientProfileFor(cid) {
  if (!cid) return 'day';
  try { if (_loadCombat(cid).active) return 'combat'; } catch {}
  try {
    const w = _loadWorldS(cid), here = (w.here || '').toLowerCase();
    const place = (w.places || []).find(pp => (pp.name || '').toLowerCase() === here);
    const kind = ((place && place.kind) || '') + ' ' + here;
    if (/tavern|inn|pub|alehouse/.test(kind)) return 'tavern';
    if (/cave|mine|dungeon|crypt|tomb|cellar|catacomb|sewer/.test(kind)) return 'cave';
    if (/wood|forest|grove|wild|thicket|jungle/.test(kind)) return 'forest';
  } catch {}
  try { const c = _loadClock(cid); if (c.wx && /rain|storm|downpour|drizzle/i.test(c.wx.name || '')) return 'rain'; } catch {}
  try { const ti = _loadClock(cid).ti || 0; if (ti >= 5) return 'night'; } catch {}   // Nightfall / Deep Night
  return 'day';
}
function _applyAmbient(cid) {
  if (!_ambOn()) { _stopAmbient(); return; }   // ambient is its own switch, independent of SFX blips
  cid = cid || (_chat.char && _chat.char.id);
  if (!cid || !_isDM(_chat.char)) { _stopAmbient(); return; }   // ambience is for adventures, not one-on-one chats
  _startAmbient(_ambientProfileFor(cid));
}
function _setAmbient(on) { try { localStorage.setItem('studio-ambient', on ? '1' : '0'); } catch {} _applyAmbient(); }
function _setAmbientVol(v) {
  try { localStorage.setItem('studio-ambient-vol', String(v)); } catch {}
  if (_amb) { const p = _AMB_PROFILES[_ambProfile] || _AMB_PROFILES.day; try { _amb.master.gain.setTargetAtTime(p.vol * _ambVol(), _ac().currentTime, 0.2); } catch {} }
}

// Combat won: a "VICTORY!" banner + fanfare when the last foe falls.
function _fxVictory() {
  _sfx('victory');
  if (_fxReduced()) return;
  _fxSpawn(`<div class="fx-victory"><span class="fx-vic-ring"></span><span class="fx-vic-text">VICTORY!</span></div>`, 2200);
}

// Time-of-day tint on the scene, driven by the world clock.
function _todBucket(ti) {
  const t = TIMES[ti] || '';
  if (/Dawn|Dusk/.test(t)) return 'gloaming';
  if (/Nightfall|Deep Night/.test(t)) return 'night';
  return 'day';
}
function _applyTimeTint(cid) {
  const root = $('studio-chat'); if (!root) return;
  root.setAttribute('data-tod', _todBucket(_loadClock(cid).ti || 0));
}
// Keep the world clock honest with the fiction: snap it to whatever time-of-day
// the GM narrates (fixes "clock says Morning while the scene is at dusk").
function _detectTimeOfDay(text) {
  if (!text) return -1;
  const t = text.toLowerCase();
  if (/\b(deep night|midnight|dead of night)\b/.test(t)) return 6;
  if (/\bnightfall\b/.test(t)) return 5;
  if (/\b(nighttime|under the stars|moonlit|the dark(?:ness)?\s+(?:settles|falls|has fallen)|into the night)\b/.test(t)) return 5;
  if (/\b(dusk|sunset|twilight|evening|gloaming)\b/.test(t)) return 4;
  if (/\bafternoon\b/.test(t)) return 3;
  if (/\b(midday|noon|high sun|noonday)\b/.test(t)) return 2;
  if (/\b(morning|forenoon|early light)\b/.test(t)) return 1;
  if (/\b(dawn|daybreak|sunrise|first light|break of day)\b/.test(t)) return 0;
  return -1;
}
function _setClockTime(cid, ti) {
  const c = _loadClock(cid); if (c.ti === ti) return; c.ti = ti; _saveClock(cid, c); _reflectClock(); _applyTimeTint(cid); _applyAmbient(cid);   // day↔night shifts the bed
}

function _castSpell(cid, idx) {
  const s = _loadSheet(cid); const sp = s.spells[idx]; if (!sp) return;
  const lvl = sp.level || 0;
  if (lvl <= 0) return _castSpellAt(cid, idx, 0);   // cantrip — no slot
  // Which slot levels ≥ this spell's level still have a charge? More than one →
  // let the player choose (upcast for power, or spend the lowest to conserve).
  const avail = [];
  for (let l = lvl; l <= 9; l++) { const sl = (s.slots || {})[l]; if (sl && (sl.used || 0) < (sl.max || 0)) avail.push(l); }
  if (!avail.length) { _appendBubble('me', `*No level ${lvl}+ slots left to cast ${_esc(sp.name)}.*`); _scrollChat(); return; }
  if (avail.length === 1) return _castSpellAt(cid, idx, avail[0]);
  return _chooseCastSlot(cid, idx, sp, avail);
}
// Small chooser so casting can deliberately upcast instead of always burning the
// lowest available slot.
function _chooseCastSlot(cid, idx, sp, avail) {
  const modal = $('studio-modal'); if (!modal) { _castSpellAt(cid, idx, avail[0]); return; }
  const s = _loadSheet(cid); const lvl = sp.level || 1;
  let ov = $('studio-slotmenu'); if (!ov) { ov = document.createElement('div'); ov.id = 'studio-slotmenu'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  ov.innerHTML = `<div class="chronicle-sheet sk-sheet" role="dialog" aria-modal="true" aria-label="Choose a spell slot">
    <div class="chronicle-bar"><h2>Cast ${_esc(sp.name)}</h2><button class="studio-close" id="slot-x" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list"><p class="cc-hint">Pick a slot — a higher one upcasts for a stronger effect.</p>
      <div class="sk-grid">${avail.map(l => { const sl = (s.slots || {})[l] || {}; const left = Math.max(0, (sl.max || 0) - (sl.used || 0)); return `<button class="sk-item" data-slot="${l}" type="button"><span>Level ${l}${l > lvl ? ' · upcast' : ''}</span><em>${left} left</em></button>`; }).join('')}</div>
    </div></div>`;
  ov.style.display = 'flex';
  const close = () => { ov.style.display = 'none'; };
  $('slot-x').addEventListener('click', close);
  ov.addEventListener('click', (e) => { if (e.target === ov) close(); });
  ov.querySelectorAll('[data-slot]').forEach(b => b.addEventListener('click', () => { close(); _castSpellAt(cid, idx, parseInt(b.dataset.slot, 10)); }));
}
function _castSpellAt(cid, idx, castAt) {
  const s = _loadSheet(cid); const sp = s.spells[idx]; if (!sp) return;
  const lvl = sp.level || 0;
  if (castAt > 0) {
    const sl = (s.slots || {})[castAt];
    if (!sl || (sl.used || 0) >= (sl.max || 0)) { _appendBubble('me', `*That slot is already spent.*`); _scrollChat(); return; }
    s.slots[castAt].used = (sl.used || 0) + 1;
  }
  const upcast = castAt > lvl;
  // Concentration: a new concentration spell replaces any you were holding.
  let dropped = '';
  if (_isConcSpell(sp.name)) {
    if (s.concentration && s.concentration.name.toLowerCase() !== sp.name.toLowerCase()) dropped = s.concentration.name;
    s.concentration = { name: sp.name, level: castAt };
  }
  _saveSheet(cid, s);
  const dc = _spellSaveDC(s);
  _appendBubble('me', `✨ *You cast **${sp.name}**${castAt ? ` (level ${castAt} slot${upcast ? ` — upcast from L${lvl}` : ''})` : ' (cantrip)'}${_isConcSpell(sp.name) ? ' — concentrating' : ''}${dropped ? `; ${dropped} fades` : ''}.*`); _scrollChat();
  _fxSpell(sp.name, castAt);
  const sp2 = $('studio-sheet-panel'); if (sp2 && sp2.classList.contains('open')) renderSheetPanel();
  if (_isDM(_chat.char)) _streamAssistant(`[I cast ${sp.name}${castAt ? ` using a level ${castAt} slot${upcast ? ` (upcast from level ${lvl} — scale its effect up)` : ''}` : ''}.${dc != null && _needsSave(sp.name) ? ` If it forces a save, the DC is ${dc}.` : ''} Adjudicate its effect in the fiction.]`);
}
function _setSlotMax(cid, lvl, delta) {
  const s = _loadSheet(cid); s.slots = s.slots || {}; s.slots[lvl] = s.slots[lvl] || { max: 0, used: 0 };
  s.slots[lvl].max = Math.max(0, Math.min(9, (s.slots[lvl].max || 0) + delta));
  s.slots[lvl].used = Math.min(s.slots[lvl].used || 0, s.slots[lvl].max);
  _saveSheet(cid, s); renderSheetPanel();
}
function _longRest(cid) {
  const s = _loadSheet(cid);
  // The night is not guaranteed: 1-in-4 rests are interrupted — half the healing,
  // and the GM runs whatever came out of the dark.
  const interrupted = Math.random() < 0.25;
  if (interrupted) {
    s.hp = Math.min(s.hpMax, (s.hp || 0) + Math.max(1, Math.ceil((s.hpMax - (s.hp || 0)) / 2)));
    s.hitDiceUsed = Math.max(0, (s.hitDiceUsed || 0) - Math.ceil((s.level || 1) / 2));   // interrupted: regain half your Hit Dice
  } else {
    s.hp = s.hpMax; s.conditions = []; s.concentration = null; s.relentlessUsed = false; s.hitDiceUsed = 0;   // fresh start at dawn — all Hit Dice back
  }
  // Spell slots return whenever class features do — even an interrupted night is
  // still a rest (you wake half-healed, but your magic is back with your kit).
  Object.keys(s.slots || {}).forEach(l => { if (s.slots[l]) s.slots[l].used = 0; });
  if (s.exhaustion) s.exhaustion = Math.max(0, s.exhaustion - 1);   // one level sleeps off per night
  _saveSheet(cid, s);
  _rechargeFeatures(cid, 'long');
  _healCompanions(cid, 1);
  const c = _loadClock(cid); const steps = (c.ti || 0) === 0 ? TIMES.length : (TIMES.length - (c.ti || 0));   // forward to next dawn
  _advanceTime(cid, steps);
  _fxRest('long');
  _appendBubble('me', interrupted
    ? `⛺ *You make camp — but something finds you in the night. You wake half-rested at ${s.hp}/${s.hpMax} HP.*`
    : `⛺ *You make camp and sleep. You wake at dawn, fully restored — ${s.hpMax}/${s.hpMax} HP.*`); _scrollChat();
  const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
  if (_isDM(_chat.char)) _streamAssistant(interrupted
    ? `[My rest is interrupted in the night — run a short encounter (perhaps ${_randEncounter().toLowerCase()}s, or something fitting where I'm camped). I woke at ${s.hp}/${s.hpMax} HP, only half-rested. Open on the moment I startle awake.]`
    : `[I take a long rest through the night and wake at dawn, fully healed. Narrate the new morning and what's changed, then continue.]`);
}
function _defaultInv() { return { slots: INV_SLOTS, items: [], equipped: {} }; }
function _loadInv(cid) {
  try { const v = JSON.parse(localStorage.getItem(INV_KEY(cid)) || 'null'); if (v && Array.isArray(v.items)) return { ..._defaultInv(), ...v }; } catch {}
  // One-time migration: fold any legacy sheet.inventory strings into real slots.
  const inv = _defaultInv();
  try { const s = _loadSheet(cid); (s.inventory || []).forEach((nm, i) => inv.items.push(_mkItem(nm, i))); } catch {}
  return inv;
}
function _saveInv(cid, inv) { try { localStorage.setItem(INV_KEY(cid), JSON.stringify(inv)); } catch {} _pushState(cid, 'inv', inv); }
function _invAdd(cid, name, qty) {
  const inv = _loadInv(cid); const nm = (name || '').trim(); if (!nm) return inv;
  const ex = inv.items.find(it => it.name.toLowerCase() === nm.toLowerCase());
  let fresh = null;
  if (ex) { ex.qty += (qty || 1); }
  else {
    const used = new Set(inv.items.map(it => it.slot));
    let slot = -1; for (let i = 0; i < inv.slots; i++) { if (!used.has(i)) { slot = i; break; } }
    fresh = _mkItem(nm, slot, qty || 1); inv.items.push(fresh);
  }
  _saveInv(cid, inv);
  if (fresh) {
    _genItemArt(cid, fresh.id);   // auto-art new items as they're introduced
    if (fresh.rarity === 'epic' || fresh.rarity === 'legendary') {
      _sfx('crit');
      _toast(`⚡ ${_titleCase(fresh.rarity)} find — ${fresh.name}!`);
    }
  }
  return inv;
}
function _itemArtPrompt(it, worldId) {
  const style = { embervale: 'painterly high-fantasy item icon, ornate', neonspire: 'cyberpunk sci-fi gadget icon, neon glow, holographic', everyday: 'clean modern product icon, realistic' }[worldId] || 'fantasy RPG item icon';
  // Rarer finds LOOK rarer — the aura scales with the tier, AAA-loot style.
  const aura = { legendary: 'radiant golden aura, gleaming enchanted metal, masterwork engraving', epic: 'violet arcane glow, intricate enchanted detail', rare: 'cool sapphire shimmer, fine craftsmanship', uncommon: 'faint emerald gleam' }[it.rarity] || '';
  return `a single ${it.rarity !== 'common' ? it.rarity + ' ' : ''}${it.name}, ${it.type === 'misc' ? 'small object' : it.type}, ${style}${aura ? `, ${aura}` : ''}, dramatic rim lighting, rich material detail, painterly AAA game inventory icon, centered on a dark neutral background, no text`;
}
// BG3-style hover card: art, rarity-colored name, rarity label, type & weight —
// the pack reads like a video-game inventory, not a list with browser titles.
function _invTipShow(cid, id, x, y) {
  const inv = _loadInv(cid); const it = inv.items.find(i => i.id === id); if (!it) return;
  let tip = $('inv-tip');
  if (!tip) { tip = document.createElement('div'); tip.id = 'inv-tip'; tip.className = 'inv-tip'; ($('studio-modal') || document.body).appendChild(tip); }
  tip.innerHTML = `
    ${it.img ? `<img class="tip-art" src="${_esc(it.img)}" alt="">` : `<span class="tip-ico">${_itemIcon(it.type, it.name)}</span>`}
    <div class="tip-name rt-${it.rarity}">${_esc(it.name)}</div>
    <div class="tip-rarity rt-${it.rarity}">${_titleCase(it.rarity || 'common')}</div>
    <div class="tip-meta">${_esc(it.type)} · ${it.wt == null ? _itemWeight(it.type) : it.wt} wt${it.qty > 1 ? ` · ×${it.qty}` : ''}${it.acBonus ? ` · +${it.acBonus} AC` : ''}${it.atk ? ` · +${it.atk} atk` : ''}${it.dmg ? ` · ${_esc(it.dmg)}` : ''}</div>`;
  tip.style.display = 'block';
  _invTipMove(x, y);
}
function _invTipMove(x, y) {
  const tip = $('inv-tip'); if (!tip || tip.style.display === 'none') return;
  tip.style.left = Math.min(window.innerWidth - 240, x + 14) + 'px';
  tip.style.top = Math.min(window.innerHeight - 190, y + 12) + 'px';
}
function _invTipHide() { const tip = $('inv-tip'); if (tip) tip.style.display = 'none'; }

async function _genItemArt(cid, id) {
  const v0 = _loadInv(cid); const it = v0.items.find(x => x.id === id); if (!it) return;
  const worldId = (_world && _world.id) || (_chat.char && _chat.char.world_id) || '';
  try {
    const r = await _artFetch(`${API_BASE}/api/characters/studio/generate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt: _itemArtPrompt(it, worldId) }) });
    const gd = await r.json();
    if (gd.ok && gd.image_url) { const v = _loadInv(cid); const x = v.items.find(y => y.id === id); if (x) { x.img = gd.image_url; _saveInv(cid, v); } }
  } catch {}
  const p = $('studio-inv-panel'); if (p && p.classList.contains('open')) renderInventory();
}
function _invMove(cid, itemId, targetSlot) {
  const inv = _loadInv(cid); const it = inv.items.find(x => x.id === itemId); if (!it) return;
  const occ = inv.items.find(x => x.slot === targetSlot && x.id !== itemId);
  if (occ) occ.slot = it.slot;     // swap with whatever was there
  it.slot = targetSlot;
  _saveInv(cid, inv);
}
function _invSort(cid, by) {
  const inv = _loadInv(cid); const arr = [...inv.items];
  arr.sort((a, b) => {
    if (by === 'type') return a.type.localeCompare(b.type) || a.name.localeCompare(b.name);
    if (by === 'rarity') return (_RARITY_ORD[a.rarity] - _RARITY_ORD[b.rarity]) || a.name.localeCompare(b.name);
    return a.name.localeCompare(b.name);
  });
  arr.forEach((it, i) => { it.slot = i; });
  _saveInv(cid, inv);
}
function renderInventory() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const inv = _loadInv(cid);
  // Give any unplaced item the first free slot so the grid is always coherent.
  let changed = false; const used = new Set(inv.items.filter(i => i.slot >= 0).map(i => i.slot));
  inv.items.forEach(it => { if (it.slot == null || it.slot < 0) { for (let i = 0; i < inv.slots; i++) { if (!used.has(i)) { it.slot = i; used.add(i); changed = true; break; } } } });
  if (changed) _saveInv(cid, inv);
  if (!inv.equipped) inv.equipped = {};
  let panel = $('studio-inv-panel');
  if (!panel) { panel = document.createElement('div'); panel.id = 'studio-inv-panel'; panel.className = 'inv-panel'; modal.appendChild(panel); }
  const face = (it) => it.img ? `<img class="ii-img" src="${_esc(it.img)}" alt="">` : `<span class="ii-icon">${_itemIcon(it.type, it.name)}</span>`;
  // Equipment slots (labels adapt to the world)
  const worldId = (_world && _world.id) || (_chat.char && _chat.char.world_id) || '';
  const equipCells = _EQUIP_SLOTS.map(sl => {
    const it = inv.items.find(x => x.id === inv.equipped[sl.key]); const lbl = _slotLabel(sl, worldId);
    return `<div class="equip-slot" data-equip="${sl.key}" title="${_esc(lbl)}${it ? ': ' + _esc(it.name) : ''}">
      ${it ? `<div class="inv-item rarity-${it.rarity}" data-equipped="${_esc(it.id)}">${face(it)}</div>` : `<span class="equip-ph">${sl.icon}</span>`}
      <span class="equip-lbl">${_esc(lbl)}</span></div>`;
  }).join('');
  // Backpack grid
  const bySlot = {}; inv.items.forEach(it => { bySlot[it.slot] = it; });
  const equippedIds = new Set(Object.values(inv.equipped).filter(Boolean));
  const cells = [];
  for (let i = 0; i < inv.slots; i++) {
    const it = bySlot[i];
    cells.push(`<div class="inv-slot" data-slot="${i}">${it ? `<div class="inv-item rarity-${it.rarity}${equippedIds.has(it.id) ? ' equipped' : ''}" draggable="true" data-item="${_esc(it.id)}">${face(it)}${it.qty > 1 ? `<span class="ii-qty">${it.qty}</span>` : ''}</div>` : ''}</div>`);
  }
  const wt = Math.round(_invWeight(inv) * 10) / 10; const cap = _carryCap(cid); const over = wt > cap;
  const wpct = Math.max(0, Math.min(100, Math.round(wt / cap * 100)));
  const _sheet = _loadSheet(cid);
  const _vendPlace = (() => { try { const w = _loadWorldS(cid); return (w.places || []).find(pp => _isVendorPlace(pp) && (pp.name || '').toLowerCase() === (w.here || '').toLowerCase()) || null; } catch { return null; } })();
  panel.innerHTML = `<div class="sheet-head"><h2>Pack</h2><button class="studio-close" id="inv-close" type="button" aria-label="Close">✕</button></div>
    <div class="sheet-body">
      <div class="purse-line"><div class="pack-purse" title="Your purse"><span aria-hidden="true">🪙</span> ${_sheet.gold || 0} ${_esc(_currency(cid))}</div>
        ${_vendPlace ? `<button class="st-btn small ghost" id="pack-trade" type="button" title="Buy and sell at ${_esc(_vendPlace.name)}">🪙 Trade at ${_esc(_vendPlace.name)}</button>` : `<span class="gm-hint" style="margin:0">no vendor here — selling needs a shop</span>`}
        <button class="st-btn small ghost" id="pack-illustrate" type="button" title="Paint every item in your pack that doesn't have a picture yet">🎨 Illustrate pack</button></div>
      <div class="paper-doll">
        <div class="pd-hero" aria-hidden="true">${_sheet.avatar
          ? `<img src="${_esc(_sheet.avatar)}" alt="">`
          : `<svg viewBox="0 0 60 100" class="pd-silhouette"><circle cx="30" cy="18" r="11"/><path d="M30 30 C16 30 10 42 10 58 L14 96 L46 96 L50 58 C50 42 44 30 30 30 Z"/></svg>`}
          <span class="pd-name">${_esc(_sheet.name || 'Your hero')}</span></div>
        ${equipCells}
      </div>
      <div class="enc-card${over ? ' over' : ''}"><div class="enc-top"><span>Load</span><span>${wt} / ${cap}${over ? ' · encumbered' : ''}</span></div>
        <div class="enc-bar"><div class="enc-fill" style="width:${wpct}%"></div></div></div>
      <div class="inv-tools"><span class="gm-hint" style="flex:1;margin:0">${inv.items.length}/${inv.slots} slots · drag to arrange or onto a gear slot</span>
        <span class="inv-sort">Sort <button class="st-btn small ghost" data-sort="name" type="button">Name</button><button class="st-btn small ghost" data-sort="type" type="button">Type</button><button class="st-btn small ghost" data-sort="rarity" type="button">Rarity</button></span></div>
      <div class="inv-grid">${cells.join('')}</div>
      <div id="inv-detail" class="inv-detail" hidden></div>
      <div class="add-row"><input type="text" id="inv-additem" placeholder="Add an item to your pack…"><button class="st-btn small" id="inv-add-btn" type="button">Add</button></div>
    </div>`;
  panel.classList.add('open');
  $('inv-close').addEventListener('click', () => panel.classList.remove('open'));
  $('pack-trade')?.addEventListener('click', () => { panel.classList.remove('open'); if (_vendPlace) openVendor(cid, _vendPlace); });
  $('pack-illustrate')?.addEventListener('click', () => {
    const v = _loadInv(cid);
    const missing = (v.items || []).filter(it => !it.img);
    if (!missing.length) { _toast('🎨 Everything in your pack is already painted.'); return; }
    _runForgeQueue('your pack', missing.map(it => ({
      label: it.name,
      run: async () => { await _genItemArt(cid, it.id); const p = $('studio-inv-panel'); if (p && p.classList.contains('open')) renderInventory(); },
    })));
    _toast(`🎨 Painting ${missing.length} item${missing.length === 1 ? '' : 's'} — they'll fill in as they finish.`);
  });
  panel.querySelectorAll('[data-sort]').forEach(b => b.addEventListener('click', () => { _invSort(cid, b.dataset.sort); renderInventory(); }));
  // Hover item-card (delegated once — innerHTML re-renders wipe children, not the panel).
  panel._tipCid = cid;
  if (!panel._tipWired) {
    panel._tipWired = true;
    panel.addEventListener('mouseover', e => { const cell = e.target.closest('.inv-item'); if (!cell) return; const id = cell.dataset.item || cell.dataset.equipped; if (id) _invTipShow(panel._tipCid, id, e.clientX, e.clientY); });
    panel.addEventListener('mouseout', e => { if (e.target.closest('.inv-item')) _invTipHide(); });
    panel.addEventListener('mousemove', e => _invTipMove(e.clientX, e.clientY));
    panel.addEventListener('dragstart', _invTipHide, true);
    panel.addEventListener('click', _invTipHide, true);
  }
  const add = () => { const v = ($('inv-additem').value || '').trim(); if (!v) return; _invAdd(cid, v, 1); renderInventory(); $('inv-additem')?.focus(); };
  $('inv-add-btn').addEventListener('click', add);
  $('inv-additem').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); add(); } });
  panel.querySelectorAll('.inv-item[data-item]').forEach(el => {
    el.addEventListener('dragstart', e => { e.dataTransfer.setData('text/plain', el.dataset.item); e.dataTransfer.effectAllowed = 'move'; el.classList.add('dragging'); });
    el.addEventListener('dragend', () => el.classList.remove('dragging'));
    el.addEventListener('click', () => _showItemDetail(cid, el.dataset.item));
  });
  panel.querySelectorAll('.inv-slot').forEach(slot => {
    slot.addEventListener('dragover', e => { e.preventDefault(); slot.classList.add('over'); });
    slot.addEventListener('dragleave', () => slot.classList.remove('over'));
    slot.addEventListener('drop', e => { e.preventDefault(); slot.classList.remove('over'); const id = e.dataTransfer.getData('text/plain'); if (id) { _invMove(cid, id, Number(slot.dataset.slot)); renderInventory(); } });
  });
  panel.querySelectorAll('.equip-slot').forEach(slot => {
    slot.addEventListener('dragover', e => { e.preventDefault(); slot.classList.add('over'); });
    slot.addEventListener('dragleave', () => slot.classList.remove('over'));
    slot.addEventListener('drop', e => { e.preventDefault(); slot.classList.remove('over'); const id = e.dataTransfer.getData('text/plain'); if (id) _equipItem(cid, id, slot.dataset.equip); });
    slot.addEventListener('click', () => { const k = slot.dataset.equip; if (inv.equipped[k]) { const v = _loadInv(cid); delete v.equipped[k]; _saveInv(cid, v); renderInventory(); } });
  });
}
function _equipItem(cid, itemId, slotKey) {
  const inv = _loadInv(cid); const it = inv.items.find(x => x.id === itemId);
  const slot = _EQUIP_SLOTS.find(s => s.key === slotKey);
  if (!it || !slot) return;
  if (!slot.types.includes(it.type)) {
    // Items typed 'misc' at creation get a second look — world-flavored gear
    // ("shield module", "combat visor") often classifies correctly from the name.
    const retyped = it.type === 'misc' ? _itemType(it.name) : it.type;
    if (retyped !== it.type && slot.types.includes(retyped)) { it.type = retyped; }
    else {
      const lbl = (typeof slot.label === 'object' ? (slot.label._ || slotKey) : slot.label);
      _toast(`⚠ ${it.name} can't go in the ${String(lbl).toLowerCase()} slot.`);
      return;
    }
  }
  inv.equipped = inv.equipped || {}; inv.equipped[slotKey] = itemId;
  _saveInv(cid, inv); renderInventory(); _fxEquipShimmer(slotKey);
}
function _showItemDetail(cid, id) {
  const inv = _loadInv(cid); const it = inv.items.find(x => x.id === id); const d = $('inv-detail'); if (!d || !it) return;
  // Second-look typing: gear that landed as 'misc' re-classifies from its name.
  if (it.type === 'misc') { const t2 = _itemType(it.name); if (t2 !== 'misc') { it.type = t2; _saveInv(cid, inv); } }
  const equipSlot = _EQUIP_SLOTS.find(s => s.types.includes(it.type));
  const isEquipped = equipSlot && inv.equipped && inv.equipped[equipSlot.key] === id;
  d.hidden = false;
  d.innerHTML = `<div class="id-head">${it.img ? `<img class="ii-img big" src="${_esc(it.img)}" alt="">` : `<span class="ii-icon big">${_itemIcon(it.type, it.name)}</span>`}
      <div><div class="id-name rt-${it.rarity}">${_esc(it.name)}</div><div class="id-meta">${it.rarity} · ${it.type} · ${it.wt == null ? _itemWeight(it.type) : it.wt} wt${it.qty > 1 ? ` · ×${it.qty}` : ''}</div></div></div>
    <div class="id-actions">
      ${(it.type === 'potion' || it.type === 'food') ? `<button class="st-btn small" id="id-use" type="button">Use</button>` : ''}
      ${(it.type === 'document' && /\bmap\b|chart|atlas/i.test(it.name)) ? `<button class="st-btn small" id="id-study" type="button" title="Chart what this map reveals">🗺 Study</button>` : ''}
      ${equipSlot ? `<button class="st-btn small" id="id-equip" type="button">${isEquipped ? 'Unequip' : 'Equip'}</button>` : ''}
      ${_vendorHere(cid)
        ? `<button class="st-btn small ghost" id="id-sell" type="button">Sell (${_sellValue(it)} ${_currency(cid)})</button>`
        : `<button class="st-btn small ghost" id="id-sell" type="button" disabled title="No vendor here — travel to a shop or market to sell">Sell · no vendor here</button>`}
      ${_isDM(_chat.char) ? `<button class="st-btn small ghost" id="id-give" type="button">🤲 Give…</button><button class="st-btn small ghost" id="id-craft" type="button">🔨 Combine…</button>` : ''}
      <button class="st-btn small ghost" id="id-art" type="button">✨ Art</button>
      ${it.qty > 1 ? `<button class="st-btn small ghost" id="id-drop1" type="button">Drop one</button>` : ''}
      <button class="st-btn small ghost" id="id-dropall" type="button">Drop${it.qty > 1 ? ' all' : ''}</button>
    </div>`;
  $('id-use')?.addEventListener('click', () => _useItem(cid, id));
  $('id-study')?.addEventListener('click', () => {
    const p = $('studio-inv-panel'); if (p) p.classList.remove('open');
    _appendBubble('me', `🗺 *You unroll ${_esc(it.name)} and study it.*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[I study ${it.name} carefully. Reveal one or two NEW named locations it charts — what they're called, what's there, and roughly where they lie from here. These places become part of the known world (my map).]`);
  });
  $('id-sell')?.addEventListener('click', () => _sellItem(cid, id));
  $('id-give')?.addEventListener('click', () => _giveItem(cid, id));
  $('id-craft')?.addEventListener('click', () => _craftItem(cid, id));
  $('id-equip')?.addEventListener('click', () => { const v = _loadInv(cid); v.equipped = v.equipped || {}; if (isEquipped) { delete v.equipped[equipSlot.key]; } else { v.equipped[equipSlot.key] = id; } _saveInv(cid, v); renderInventory(); if (!isEquipped) _fxEquipShimmer(equipSlot.key); _showItemDetail(cid, id); });   // re-render the detail so the button flips Equip↔Unequip
  $('id-drop1')?.addEventListener('click', () => { const v = _loadInv(cid); const x = v.items.find(y => y.id === id); if (x) { x.qty--; if (x.qty <= 0) { v.items = v.items.filter(y => y.id !== id); Object.keys(v.equipped || {}).forEach(k => { if (v.equipped[k] === id) delete v.equipped[k]; }); } } _saveInv(cid, v); renderInventory(); });
  $('id-dropall')?.addEventListener('click', () => { const v = _loadInv(cid); v.items = v.items.filter(y => y.id !== id); Object.keys(v.equipped || {}).forEach(k => { if (v.equipped[k] === id) delete v.equipped[k]; }); _saveInv(cid, v); renderInventory(); });
  $('id-art')?.addEventListener('click', async () => {
    const btn = $('id-art'); btn.disabled = true; btn.textContent = '…';
    await _genItemArt(cid, id);
    _showItemDetail(cid, id);
  });
}
function toggleInventory() { const p = $('studio-inv-panel'); if (p && p.classList.contains('open')) { p.classList.remove('open'); return; } renderInventory(); _panelEnter('studio-inv-panel', 'fx-pack-in'); }
// Crafting: combine two items from the pack. One of each is consumed on the
// attempt; the GM adjudicates and names the result plainly so the loot detector
// pockets it — success or an interesting failure, never nothing.
function _craftItem(cid, id) {
  const inv = _loadInv(cid); const it = inv.items.find(x => x.id === id); if (!it) return;
  const others = inv.items.filter(x => x.id !== id);
  if (!others.length) { _appendBubble('me', `*You need a second ingredient to combine with the ${_esc(it.name)}.*`); _scrollChat(); return; }
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-craft-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-craft-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const picks = others.map(x => `<button class="st-btn small" data-craftwith="${_esc(x.id)}" type="button">${_itemIcon(x.type, x.name)} ${_esc(x.name)}${x.qty > 1 ? ` ×${x.qty}` : ''}</button>`).join(' ');
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Combine items">
    <div class="chronicle-bar"><h2>🔨 Combine ${_esc(it.name)} with…</h2><button class="studio-close" id="craft-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">One of each ingredient is used in the attempt. The GM decides what you make — craft near a forge, fire, or workbench for better odds.</p>
      <div class="give-picks">${picks}</div>
    </div></div>`;
  ov.style.display = 'flex';
  $('craft-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  ov.querySelectorAll('[data-craftwith]').forEach(b => b.addEventListener('click', () => {
    ov.style.display = 'none';
    const v = _loadInv(cid);
    const a = v.items.find(x => x.id === id); const c = v.items.find(x => x.id === b.dataset.craftwith);
    if (!a || !c) return;
    const nameA = a.name, nameB = c.name;
    [a, c].forEach(x => { x.qty = (x.qty || 1) - 1; });
    v.items = v.items.filter(x => (x.qty == null ? 1 : x.qty) > 0);
    Object.keys(v.equipped || {}).forEach(k => { if (!v.items.some(x => x.id === v.equipped[k])) delete v.equipped[k]; });
    _saveInv(cid, v);
    renderInventory();
    _sfx('loot');
    _appendBubble('me', `🔨 *You set to work, combining the **${_esc(nameA)}** and the **${_esc(nameB)}**…*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[I try to craft something by combining my ${nameA} with my ${nameB}. Judge what's plausible given where I am and my skills — call for a check if it's tricky. Whether it succeeds or fails interestingly, if I end up with something, say plainly that I receive it and NAME the item clearly (e.g. "you receive a Reinforced Torch").]`);
  }));
}

// Hand an item to someone in the scene: pick from the cast you've met (or name
// anyone), the item leaves the pack, and the GM plays out how it lands.
function _giveItem(cid, id) {
  const inv = _loadInv(cid); const it = inv.items.find(x => x.id === id); if (!it) return;
  const modal = $('studio-modal'); if (!modal) return;
  let ov = $('studio-give-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'studio-give-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const npcs = (_loadCodex(cid).npcs || []).map(n => n.name).filter(Boolean);
  const picks = npcs.map(n => `<button class="st-btn small" data-giveto="${_esc(n)}" type="button">${_esc(n)}</button>`).join(' ');
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="Give item">
    <div class="chronicle-bar"><h2>🤲 Give ${_esc(it.name)}</h2><button class="studio-close" id="give-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      ${picks ? `<p class="gm-hint">To someone you've met:</p><div class="give-picks">${picks}</div>` : ''}
      <div class="add-row"><input type="text" id="give-name" placeholder="…or name anyone in the scene"><button class="st-btn small primary" id="give-go" type="button">Give</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  $('give-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  const give = (who) => {
    if (!who) return;
    ov.style.display = 'none';
    const v = _loadInv(cid); const x = v.items.find(y => y.id === id); if (!x) return;
    x.qty = (x.qty || 1) - 1;
    if (x.qty <= 0) { v.items = v.items.filter(y => y.id !== id); Object.keys(v.equipped || {}).forEach(k => { if (v.equipped[k] === id) delete v.equipped[k]; }); }
    _saveInv(cid, v);
    renderInventory();
    _appendBubble('me', `🤲 *You hand the **${_esc(it.name)}** to **${_esc(who)}**.*`); _scrollChat();
    if (_isDM(_chat.char)) _streamAssistant(`[I give my ${it.name} to ${who}. Play out how they receive it — it may change how they feel about me.]`);
  };
  ov.querySelectorAll('[data-giveto]').forEach(b => b.addEventListener('click', () => give(b.dataset.giveto)));
  $('give-go').addEventListener('click', () => give(($('give-name').value || '').trim()));
  $('give-name').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); give((e.target.value || '').trim()); } });
}
// Use a consumable: healing potions restore HP (sheet + the combat token), others just get spent.
function _useItem(cid, id) {
  const v = _loadInv(cid); const it = v.items.find(x => x.id === id); if (!it) return;
  const n = it.name.toLowerCase(); let msg;
  if (it.type === 'potion' && /heal|health|cure|life|vitality|restorat/.test(n)) {
    const r1 = 1 + Math.floor(Math.random() * 4), r2 = 1 + Math.floor(Math.random() * 4), healed = r1 + r2 + 2;
    const s = _loadSheet(cid); s.hp = Math.min(s.hpMax, (s.hp || 0) + healed); _saveSheet(cid, s);
    const cc = _loadCombat(cid); if (cc.active) { const pc = cc.combatants.find(x => x.id === 'pc'); if (pc) { pc.hp = Math.min(pc.hpMax, (pc.hp || 0) + healed); if (pc.hp > 0) delete pc.ds; _saveCombat(cid, cc); } }
    msg = `🧪 *You quaff the ${it.name} — 2d4+2 (${r1}, ${r2} +2) → restored **${healed} HP** (now ${s.hp}/${s.hpMax}).*`;
    _fxPotion(true);
  } else if (it.type === 'food') {
    msg = `🍖 *You eat the ${it.name}, taking a moment to recover your strength.*`;
  } else {
    msg = `*You use the ${it.name}.*`;
    if (it.type === 'potion') _fxPotion(false);
  }
  it.qty = (it.qty || 1) - 1;
  if (it.qty <= 0) { v.items = v.items.filter(x => x.id !== id); Object.keys(v.equipped || {}).forEach(k => { if (v.equipped[k] === id) delete v.equipped[k]; }); }
  _saveInv(cid, v);
  _appendBubble('me', msg); _scrollChat();
  renderInventory();
  const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
  const cp = $('studio-combat-panel'); if (cp && cp.classList.contains('open')) renderCombatPanel();
  if (_isDM(_chat.char)) _streamAssistant(msg);
}

// ── Gold: read explicit transactions out of the GM's narration ───────────────
// Conservative — needs a transaction verb next to "N <currency>", so flavor
// like "coins glitter on the wall" is ignored. Returns a net delta (gain−spend).
function _detectGold(text) {
  if (!text) return 0;
  const CUR = '(?:gold(?:\\s+pieces?)?|gp|coins?|credits?|creds?|silver|marks?|cash|dollars?)';
  // ponytail: heuristic denylist — "20 gold teeth/ring/crown" is describing an
  // object, not paying in currency. Extend this list, don't rebuild the parser.
  const NOTOBJ = '(?!\\s+(?:teeth|tooth|fang|fangs|ring|rings|crown|crowns|statue|statues|idol|idols|chain|chains|leaf|leaves|dust|trim|plate|plated|bar|bars|nugget|nuggets|vein|veins|ore|filigree|thread|threads|embroidery|band|bands|hilt|hilts|inlay|lettering|scale|scales|eyes?|hair|mane|fur|paint|light))';
  const clamp = (s) => Math.min(99999, Math.max(0, parseInt(s, 10) || 0));
  // The transaction must be about the PLAYER — else "the merchant earned 500 gold"
  // credits your purse. Require a first/second-person pronoun near the match.
  const aboutPlayer = (idx, len) => /\b(you|your|yourself|i|me|my|we|us|our)\b/i.test(text.slice(Math.max(0, idx - 24), idx + len + 12));
  let gain = 0, spend = 0, m;
  const gainRe = new RegExp(`\\b(?:gain|receive[ds]?|find|found|earn(?:ed)?|loot(?:ed)?|award(?:ed)?|reward(?:ed)?|pocket(?:ed)?|collect(?:ed)?|are\\s+given|hands?\\s+you)\\b\\D{0,25}?(\\d{1,5})\\s*${CUR}\\b${NOTOBJ}`, 'gi');
  const spendRe = new RegExp(`\\b(?:pays?|paid|spend|spent|costs?|lose|lost|hand(?:s|ed)?\\s+over|part\\s+with|deduct(?:ed)?|charge[ds]?)\\b\\D{0,25}?(\\d{1,5})\\s*${CUR}\\b${NOTOBJ}`, 'gi');
  while ((m = gainRe.exec(text))) { if (aboutPlayer(m.index, m[0].length)) gain += clamp(m[1]); }
  while ((m = spendRe.exec(text))) { if (aboutPlayer(m.index, m[0].length)) spend += clamp(m[1]); }
  return gain - spend;
}
function _applyDetectedGold(cid, text) {
  const d = _detectGold(text);
  if (!d) return;
  const now = _addGold(cid, d);
  const cur = _currency(cid);
  _appendBubble('me', d > 0 ? `💰 *+${d} ${cur} — purse: ${now}.*` : `💸 *−${-d} ${cur} — purse: ${now}.*`);
  _fxGold(d);
  _scrollChat();
  const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
}

// You need someone to sell TO. Any shop or tavern counts as a vendor even if
// the atlas never wrote down what it trades in (forged worlds often omit it).
function _isVendorPlace(p) { return !!p && (!!p.shop || ['shop', 'tavern'].includes(p.kind)); }
function _shopText(p) { return (p && p.shop) || (p && p.kind === 'tavern' ? 'food & drink' : p && p.kind === 'shop' ? 'odds & ends' : ''); }
function _vendorHere(cid) {
  try {
    const w = _loadWorldS(cid); const here = (w.here || '').toLowerCase();
    return (w.places || []).some(p => _isVendorPlace(p) && (p.name || '').toLowerCase() === here);
  } catch { return false; }
}

// Sell one unit of an item at half its market value — at a vendor.
// `force` = the sale is already happening at a vendor counter (trade panel).
async function _sellItem(cid, id, force) {
  if (!force && !_vendorHere(cid)) { _appendBubble('me', `*There's no vendor here to buy from you — find a shop or market.*`); _scrollChat(); return; }
  const v = _loadInv(cid); const it = v.items.find(x => x.id === id); if (!it) return;
  // Selling the sword off your hip deserves a second thought.
  if (Object.values(v.equipped || {}).includes(id)) {
    const msg = `Sell your equipped ${it.name}? You'll be without it.`;
    const ok = window.styledConfirm ? await window.styledConfirm(msg, { confirmText: 'Sell it' }) : window.confirm(msg);
    if (!ok) return;
  }
  const val = _sellValue(it); const nm = it.name;
  it.qty = (it.qty || 1) - 1;
  const gone = it.qty <= 0;
  if (gone) { v.items = v.items.filter(x => x.id !== id); Object.keys(v.equipped || {}).forEach(k => { if (v.equipped[k] === id) delete v.equipped[k]; }); }
  _saveInv(cid, v);
  const now = _addGold(cid, val);
  _appendBubble('me', `🪙 *Sold ${_esc(nm)} for ${val} ${_currency(cid)} — purse: ${now}.*`); _scrollChat();
  _fxGold(val);
  const d = $('inv-detail'); if (gone && d) d.hidden = true;
  const packOpen = $('studio-inv-panel'); if (packOpen && packOpen.classList.contains('open')) renderInventory();
  const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
}

// ── Auto-loot: the GM's narration drops items into your pack ─────────────────
function _detectLoot(text) {
  if (!text) return [];
  const found = [], seen = new Set();
  const re = /\b(?:find|found|pick(?:ed)?\s+up|loot(?:ed)?|obtain(?:ed)?|receive[ds]?|are\s+given|acquire[ds]?|grab(?:bed)?|discover(?:ed)?|claim(?:ed)?|hands?\s+you|hand(?:ed|s)?\s+you|gives?\s+you|gave\s+you|offers?\s+you|passes?\s+you|slides?\s+you|hand\s+over)\s+(a|an|the|some|\d+)\s+([a-z][a-z' -]{2,40})/gi;
  let m;
  while ((m = re.exec(text))) {
    let phrase = m[2].split(/\b(?:from|in|on|that|which|and|with|to|for|as|near|beside|inside|of|lying|sitting|hidden|tucked)\b/i)[0];
    phrase = phrase.replace(/[.,;:!?'"—].*$/, '').trim().split(/\s+/).slice(0, 4).join(' ').trim();
    if (phrase.length < 3) continue;
    // Gestures aren't loot ("gives you an inquisitive wave" once landed a
    // pack item named Inquisitive Wave) — social/abstract nouns stop here.
    if (/^(yourself|your|it|them|him|her|that|this|one|way|time|rest|sight|cover|shelter|footing|trail|path|moment|chance|breath|glimpse|sense|feeling|look|view|place|spot|seat|hand|grip|hold|out|up|down|back|wave|nod|smile|grin|wink|shrug|glance|gesture|salute|bow|kiss|hug|pat|stare|frown|scowl|smirk|laugh|chuckle|sigh|welcome|greeting|farewell|blessing|warning|word|whisper|shout|story|tale|tour|lift|ride|room|bed|meal|drink|round|toast|job|task|quest|mission|offer|deal|bargain|price|discount|lesson|tip|hint|clue|answer|reply|response|promise|threat|curse|charm(?:ing)? smile|once-over|thumbs)\b/i.test(phrase)) continue;
    let qty = 1; const q = m[1].toLowerCase(); if (/^\d+$/.test(q)) qty = Math.min(99, Number(q));
    const key = phrase.toLowerCase(); if (seen.has(key)) continue; seen.add(key);
    found.push({ name: _titleCase(phrase), qty });
    if (found.length >= 5) break;
  }
  return found;
}
function _renderLootPrompt(items) {
  const bar = $('studio-loot-prompt'); if (!bar) return;
  if (!items || !items.length) { bar.hidden = true; bar.innerHTML = ''; return; }
  _lootPending = items;
  const label = items.map(i => i.qty > 1 ? `${_esc(i.name)} ×${i.qty}` : _esc(i.name)).join(', ');
  bar.innerHTML = `<span class="rp-prompt-text">🎒 You came across: <strong>${label}</strong></span>`
    + `<span style="display:flex;gap:6px"><button class="st-btn primary small" id="loot-add-btn" type="button">Add to pack</button><button class="st-btn ghost small" id="loot-skip-btn" type="button">Ignore</button></span>`;
  bar.hidden = false;
  $('loot-add-btn').addEventListener('click', () => { const cid = _chat.char.id; (_lootPending || []).forEach((i, idx) => { _invAdd(cid, i.name, i.qty); setTimeout(() => _fxItemGet(i.name, _itemIcon(_itemType(i.name), i.name)), idx * 160); }); _lootPending = null; bar.hidden = true; bar.innerHTML = ''; const p = $('studio-inv-panel'); if (p && p.classList.contains('open')) renderInventory(); const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel(); });
  $('loot-skip-btn').addEventListener('click', () => { _lootPending = null; bar.hidden = true; bar.innerHTML = ''; });
}
let _lootPending = null;

// ── Earned, not poofed: spells and companions arrive through the fiction ─────
// A player asks the GM ("I want to learn X" / "will you join me?"); the GM
// adjudicates (a scroll, a teacher, a Persuasion check, a price); and only when
// the GM GRANTS it in the narration does it become mechanical — same loop as
// loot/gold/quests. The raw "just add it" controls stay behind GM mode.

// The GM narrates a spell learned → read it back into the spellbook. Conservative:
// a learn-verb next to a real compendium spell (so "she casts fireball" is ignored).
function _detectLearnedSpell(text) {
  if (!text) return null;
  const m = /\b(?:learn(?:ed|s)?|scribe[ds]?|inscrib(?:e[ds]?|ing)|master(?:ed|s)?|copy|copied|record(?:ed)?|commit(?:ted)?\s+to\s+memory|add(?:ed)?)\b[^.\n]{0,40}?\b(?:the\s+)?(?:spell|cantrip)\s+(?:of\s+|called\s+|named\s+)?["“'‘]?([A-Za-z][A-Za-z'’ ]{2,26})["”'’]?/i.exec(text)
        || /["“'‘]?\b([A-Za-z][A-Za-z'’ ]{2,26})\b["”'’]?\s+is\s+now\s+(?:in|part of|inscribed in)\s+your\s+(?:spellbook|repertoire|grimoire|book of shadows)/i.exec(text);
  if (!m) return null;
  // The capture can run past the name ("Fireball into your book"), so match the
  // longest real compendium spell the phrase starts with — the GM can't grant vapor.
  const raw = m[1].trim().toLowerCase();
  const hit = SPELLS
    .filter(sp => raw === sp.name.toLowerCase() || raw.startsWith(sp.name.toLowerCase() + ' '))
    .sort((a, b) => b.name.length - a.name.length)[0];
  return hit ? { name: hit.name, level: hit.level || 0 } : null;
}
function _learnSpellFromDM(cid, sp) {
  const s = _loadSheet(cid);
  if ((s.spells || []).some(x => x.name.toLowerCase() === sp.name.toLowerCase())) return;
  s.spells = s.spells || []; s.spells.push({ name: sp.name, level: sp.level });
  _saveSheet(cid, s);
  _appendBubble('me', `📖 *You learn **${_esc(sp.name)}**${sp.level ? ` (level ${sp.level})` : ' (cantrip)'} — inscribed in your spellbook.*`); _scrollChat();
  _fxSpell(sp.name, sp.level); _sfx('level');
  const p = $('studio-sheet-panel'); if (p && p.classList.contains('open')) renderSheetPanel();
}
// The GM narrates an NPC throwing in with you → recruit them. Gated on: the NPC
// is someone you've MET (in the codex) and isn't already in the party.
function _detectCompanionJoin(cid, text) {
  if (!text) return null;
  const m = /\b([A-Z][A-Za-z'’]+(?:\s+[A-Z][A-Za-z'’]+)?)\s+(?:agrees?\s+to\s+(?:join|travel|accompany|come)|joins?\s+(?:you|your\s+party|the\s+party)|will\s+(?:join|travel with|accompany|come with|fight (?:alongside|beside|with))\s+you|throws?\s+in\s+(?:their|his|her)\s+lot\s+with\s+you|takes?\s+up\s+with\s+you|swears?\s+to\s+(?:follow|serve)\s+you)/i.exec(text);
  if (!m) return null;
  const name = m[1].trim();
  const codex = _loadCodex(cid);
  const npc = (codex.npcs || []).find(n => (n.name || '').toLowerCase() === name.toLowerCase() || (n.name || '').toLowerCase().startsWith(name.toLowerCase() + ' '));
  if (!npc) return null;
  if (_companions(cid).some(c => c.name.toLowerCase() === npc.name.toLowerCase())) return null;
  return npc;
}
function _joinCompanionFromDM(cid, npc) {
  const s = _loadSheet(cid); s.companions = s.companions || [];
  if (s.companions.some(x => x.name.toLowerCase() === npc.name.toLowerCase())) return;
  const cls = _companionClass(npc); const level = s.level || 1; const preset = CLASS_PRESETS[cls] || { hitDie: 8 };
  const hpMax = preset.hitDie + 2 * level; const ac = preset.hitDie >= 10 ? 14 : 12;
  s.companions.push({ name: npc.name, role: npc.role || '', cls, level, ac, hpMax, hp: hpMax });
  _saveSheet(cid, s); _renderPartyChips(cid);
  _appendBubble('me', `⚔ *${_esc(npc.name)} joins your party — a level ${level} ${cls}!*`); _scrollChat();
}
// Player-side "ask the GM": these send an adjudication request; the GM decides
// feasibility and cost, and the detectors above apply the grant if it lands.
async function _askLearnSpell(cid) {
  if (_chat.streaming || !_isDM(_chat.char)) return;
  let name;
  try { name = window.styledPrompt ? await window.styledPrompt('What spell do you hope to learn? The GM decides whether — and how — you can.', '') : window.prompt('What spell?'); } catch { return; }
  if (!name || !(name = name.trim())) return;
  _appendBubble('me', `*You seek to learn **${_esc(name)}**.*`); _scrollChat();
  _streamAssistant(`[I want to learn the spell "${name}". Adjudicate this like a Game Master: can I plausibly learn it right now — do I have access to a spell scroll, a willing teacher, or my own spellbook to study from, and am I capable of it for my class and level? If it's reasonable, describe how it happens (name any cost, downtime, or check first), and once it's done say clearly that I learn/scribe the spell. If it's out of reach, tell me exactly what I would need to learn it — don't just grant it.]`);
}
async function _askJoinParty(cid, npc) {
  if (_chat.streaming || !_isDM(_chat.char)) return;
  _appendBubble('me', `*You ask **${_esc(npc.name)}** to join you.*`); _scrollChat();
  _streamAssistant(`[I ask ${npc.name} to travel with me as a companion. Adjudicate as a Game Master: are they willing, given who they are and how they feel about me? They may want something in return, set a condition, or need convincing (a Persuasion check). Play out their answer honestly — they might refuse. Only if they truly agree, say clearly that ${npc.name} joins me.]`);
}

// ── World clock (living-world primitive) ────────────────────────────────────
const CLOCK_KEY = (cid) => `studio-clock-${cid}`;
const TIMES = ['Dawn', 'Morning', 'Midday', 'Afternoon', 'Dusk', 'Nightfall', 'Deep Night'];
function _loadClock(cid) { try { return { day: 1, ti: 1, at: 0, ...(JSON.parse(localStorage.getItem(CLOCK_KEY(cid)) || 'null') || {}) }; } catch { return { day: 1, ti: 1, at: 0 }; } }
function _saveClock(cid, c) { try { localStorage.setItem(CLOCK_KEY(cid), JSON.stringify(c)); } catch {} _pushState(cid, 'clock', c); }
function _clockText(cid) { const c = _loadClock(cid); return `In-world time: ${TIMES[c.ti] || 'Day'}, day ${c.day} of the adventure${c.wx ? `, under ${c.wx.name}` : ''}. Keep time's passage and weather consistent and let them color the scene (light, who's about, what's open).`; }
// Weather — rolled each new day, colors the GM's scene and the clock chip.
const WEATHERS = {
  embervale: [['☀️', 'clear skies'], ['🌤', 'drifting clouds'], ['🌧', 'soft valley rain'], ['🌫', 'low mist'], ['💨', 'cold wind off the hills'], ['⛈', 'a brewing storm']],
  neonspire: [['🌧', 'steady rain'], ['🌧', 'acid drizzle'], ['🌫', 'smog haze'], ['⛈', 'an electric storm'], ['🌤', 'a rare dry spell']],
  everyday:  [['☀️', 'sunshine'], ['🌤', 'partly cloudy'], ['🌧', 'light rain'], ['💨', 'a breezy day'], ['❄️', 'a cold snap']],
  _:         [['☀️', 'clear weather'], ['🌤', 'scattered clouds'], ['🌧', 'rain'], ['🌫', 'fog'], ['💨', 'strong wind'], ['⛈', 'a storm']],
};
function _rollWeather(cid, c) {
  const wid = (_chat.char && _chat.char.world_id) || '';
  const list = WEATHERS[wid] || WEATHERS._;
  const [ico, name] = list[Math.floor(Math.random() * list.length)];
  c.wx = { ico, name };
}
function _advanceTime(cid, steps) {
  const c = _loadClock(cid); const prevDay = c.day || 1;
  c.ti = (c.ti || 0) + (steps || 1);
  while (c.ti >= TIMES.length) { c.ti -= TIMES.length; c.day = (c.day || 1) + 1; }
  if (!c.wx || (c.day || 1) !== prevDay) _rollWeather(cid, c);   // fresh skies with each dawn
  c.at = _meCount(); _saveClock(cid, c); _reflectClock(); _applyTimeTint(cid);
  // Timed sheet conditions wane as in-world time passes.
  const sc = _loadSheet(cid);
  if ((sc.conditions || []).some(x => x && typeof x === 'object' && x.rounds != null)) {
    sc.conditions = sc.conditions
      .map(x => (x && typeof x === 'object' && x.rounds != null) ? { ...x, rounds: x.rounds - 1 } : x)
      .filter(x => !(x && typeof x === 'object' && x.rounds != null && x.rounds <= 0));
    _saveSheet(cid, sc);
    const sp = $('studio-sheet-panel'); if (sp && sp.classList.contains('open')) renderSheetPanel();
  }
  if ((c.day || 1) > prevDay) _worldTick(cid);   // a new day dawned — let the world move off-screen
}
function _maybeAdvanceTime(cid) { if (_meCount() - (_loadClock(cid).at || 0) >= 3) _advanceTime(cid, 1); }
// The living world breathes between days: NPCs pursue their goals and open
// threads progress off-screen, surfaced as a "Meanwhile…" aside + folded into memory.
function _appendAside(html) {
  const thread = $('studio-thread'); if (!thread) return;
  const el = document.createElement('div'); el.className = 'rp-aside'; el.innerHTML = html;
  thread.appendChild(el); _scrollChat();
}
async function _worldTick(cid) {
  if (!_chat.char) return;
  try {
    const q = _loadQuests(cid).quests || [];
    const codex = _loadCodex(cid).npcs || [];
    if (!q.some(x => x.status !== 'done') && !codex.some(n => n.goal)) return;   // nothing in motion yet
    const res = await fetch(`${API_BASE}/api/characters/studio/worldtick`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ character_name: _chat.char.name, quests: q, codex, memory: _memText(cid), day: _loadClock(cid).day, model: _modelLabel() }),
    });
    if (!res.ok) return;
    const d = await res.json();
    if (d.ok && Array.isArray(d.events) && d.events.length) {
      let aside = `<p class="aside-head">🌙 Meanwhile, as day ${_loadClock(cid).day} dawns…</p>` + d.events.map(e => `<p>${_rp(e)}</p>`).join('');
      const m = _loadMem(cid); m.facts = m.facts || []; d.events.forEach(e => m.facts.push('(offstage) ' + e)); _saveMem(cid, m);
      // A development can surface a fresh lead — drop it into the quest log.
      if (d.newQuest && d.newQuest.title) {
        const qq = _loadQuests(cid); qq.quests = qq.quests || [];
        const key = d.newQuest.title.toLowerCase();
        if (!qq.quests.some(x => (x.title || '').toLowerCase() === key)) {
          qq.quests.push({ id: 'q-' + key.replace(/[^a-z0-9]+/g, '-'), title: d.newQuest.title, desc: d.newQuest.desc || '', status: 'active' });
          _saveQuests(cid, qq);
          aside += `<p class="aside-quest">📜 New lead: <strong>${_esc(d.newQuest.title)}</strong>${d.newQuest.desc ? ` — ${_rp(d.newQuest.desc)}` : ''}</p>`;
          const ov = $('studio-quests-overlay'); if (ov && ov.style.display === 'flex') openQuests();
        }
      }
      _appendAside(aside);
    }
  } catch {}
}
function _reflectClock() { const el = $('studio-clock'); if (!el || !_chat.char) return; const c = _loadClock(_chat.char.id); el.innerHTML = `<span class="clk-ico" aria-hidden="true">${c.wx ? c.wx.ico : '🕯️'}</span>${TIMES[c.ti] || 'Day'} · Day ${c.day}`; el.title = `${TIMES[c.ti]}, day ${c.day}${c.wx ? ` — ${c.wx.name}` : ''} — click to let time pass`; }
// Persistent objective chip: the top unfinished quest, at a glance.
function _reflectObjective(cid) {
  const el = $('studio-objective'); if (!el) return;
  const id = cid || (_chat.char && _chat.char.id);
  const q = _loadQuests(id); const active = (q.quests || []).find(x => x.status !== 'done');
  const done = (q.quests || []).filter(x => x.status === 'done').length;
  const s = _loadSheet(id);
  if (s.campaignComplete) {   // the tale is told — wear it proudly
    el.style.display = ''; el.innerHTML = `<span class="obj-ico" aria-hidden="true">🏁</span>THE END`;
    el.title = 'This campaign is complete — its story lives in the Chronicle. You can still wander the epilogue.';
    return;
  }
  if (!active) {
    if (done >= 2) {   // every thread tied — offer the ending
      el.style.display = ''; el.innerHTML = `<span class="obj-ico" aria-hidden="true">🏁</span>The threads are tied — conclude the tale?`;
      el.title = 'All quests resolved — open the quest log to conclude the campaign';
      return;
    }
    el.style.display = 'none'; return;
  }
  el.style.display = ''; el.innerHTML = `<span class="obj-ico" aria-hidden="true">🎯</span>${_esc(active.title)}`;
  el.title = `Objective: ${active.title} — click for the quest log`;
}

// ── Realm: places & factions (living world) ─────────────────────────────────
const WORLD_KEY = (cid) => `studio-world-${cid}`;
function _loadWorldS(cid) { try { return { places: [], factions: [], at: 0, ...(JSON.parse(localStorage.getItem(WORLD_KEY(cid)) || 'null') || {}) }; } catch { return { places: [], factions: [], at: 0 }; } }
function _saveWorldS(cid, w) { try { localStorage.setItem(WORLD_KEY(cid), JSON.stringify(w)); } catch {} _pushState(cid, 'world', w); }
// Stock the atlas with a world's established places (once); exploration adds more.
function _seedLocations(cid, worldId) {
  const locs = getLocations(worldId); if (!locs.length) return;
  const w = _loadWorldS(cid); w.places = w.places || [];
  const have = new Set(w.places.map(p => (p.name || '').toLowerCase()));
  let added = false;
  locs.forEach(l => { if (!have.has(l.name.toLowerCase())) { w.places.push({ name: l.name, note: l.lore, kind: l.kind, shop: l.shop || '', x: l.x, y: l.y, prebuilt: true }); added = true; } });
  if (added) _saveWorldS(cid, w);
}
function _realmText(cid) {
  const w = _loadWorldS(cid); const parts = [];
  if (w.places && w.places.length) parts.push(`Known places: ${w.places.map(p => `${p.name}${p.note ? ` (${p.note})` : ''}`).join('; ')}`);
  if (w.factions && w.factions.length) parts.push(`Factions: ${w.factions.map(f => `${f.name} [${f.standing || 'neutral'} to the player]${f.note ? ` — ${f.note}` : ''}`).join('; ')}`);
  if (!parts.length) return '';
  return `The known world — ${parts.join('. ')}. Keep places and factions consistent with this.`.slice(0, 1600);
}
async function _updateWorldS(cid) {
  if (!_chat.char) return 'error';
  try {
    const transcript = await _fetchTranscript(); if (!transcript.length) return 'empty';
    const w = _loadWorldS(cid);
    const res = await fetch(`${API_BASE}/api/characters/studio/worldstate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ character_name: _chat.char.name, transcript, world: { places: w.places, factions: w.factions }, model: _modelLabel() }),
    });
    if (!res.ok) return 'error';
    const d = await res.json(); if (!d.ok) return 'error';
    const places = Array.isArray(d.places) ? d.places : [];
    const factions = Array.isArray(d.factions) ? d.factions : [];
    if (!places.length && !factions.length) return 'empty';
    // Merge: keep existing places (their map coords / prebuilt lore), update notes, scatter new finds.
    const byName = {}; (w.places || []).forEach(p => { if (p.name) byName[p.name.toLowerCase()] = p; });
    places.forEach(np => { const k = (np.name || '').toLowerCase(); if (!k) return; const ex = byName[k]; if (ex) { ex.note = np.note || ex.note; } else { byName[k] = { name: np.name, note: np.note || '', x: 10 + Math.floor(Math.random() * 80), y: 14 + Math.floor(Math.random() * 70) }; } });
    _saveWorldS(cid, { ...w, places: Object.values(byName), factions, at: _meCount() });
    const ov = $('studio-realm-overlay'); if (ov && ov.style.display === 'flex') openRealm();
    const at = $('studio-map-overlay'); if (at && at.style.display === 'flex' && _mapTab === 'world') renderMap();
    return 'ok';
  } catch { return 'error'; }
}
function openRealm() {
  const modal = $('studio-modal'); if (!modal || !_chat.char) return;
  const cid = _chat.char.id; const w = _loadWorldS(cid);
  let ov = $('studio-realm-overlay'); if (!ov) { ov = document.createElement('div'); ov.id = 'studio-realm-overlay'; ov.className = 'chronicle-overlay'; modal.appendChild(ov); }
  const placeRows = (w.places && w.places.length) ? w.places.map((p, i) => `<li class="realm-row"><div class="realm-body"><span class="realm-name">📍 ${_esc(p.name)}</span><span class="realm-note">${_esc(p.note || '')}</span></div><button class="rm" data-rmplace="${i}" type="button" aria-label="Remove">×</button></li>`).join('') : '<li class="realm-row empty">No places charted yet.</li>';
  const facRows = (w.factions && w.factions.length) ? w.factions.map((f, i) => `<li class="realm-row fac-${_esc(f.standing || 'neutral')}"><div class="realm-body"><span class="realm-name">⚑ ${_esc(f.name)} <em>${_esc(f.standing || 'neutral')}</em></span><span class="realm-note">${_esc(f.note || '')}</span></div><button class="rm" data-rmfac="${i}" type="button" aria-label="Remove">×</button></li>`).join('') : '<li class="realm-row empty">No factions known yet.</li>';
  // Bonds — the cross-session relationship store, surfaced. Read-only here;
  // dispositions are managed per-NPC in the codex.
  const bonds = Object.values((_loadRel().npcs) || {}).sort((a, b) => (b.at || 0) - (a.at || 0));
  const bondRows = bonds.length ? bonds.map(b => `<li class="realm-row bond-${_esc(b.disposition || 'neutral')}"><div class="realm-body"><span class="realm-name">🤝 ${_esc(b.name)} <em>${_esc(b.disposition || 'neutral')}</em></span>${b.note ? `<span class="realm-note">${_esc(b.note)}</span>` : ''}</div></li>`).join('') : '<li class="realm-row empty">No bonds formed yet — they carry across every world and chat.</li>';
  ov.innerHTML = `<div class="chronicle-sheet" role="dialog" aria-modal="true" aria-label="The realm">
    <div class="chronicle-bar"><h2>The realm</h2><button class="studio-close" id="realm-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list">
      <p class="gm-hint">Places you've been and the powers at work. It fills in as you explore; the GM keeps the world consistent, and the off-screen tick can stir it.</p>
      <div class="sheet-section"><h3>Places</h3><ul class="realm-list">${placeRows}</ul></div>
      <div class="sheet-section"><h3>Factions</h3><ul class="realm-list">${facRows}</ul></div>
      <div class="sheet-section"><h3>Bonds <span class="rule-hint">how people feel about you, across every story</span></h3><ul class="realm-list">${bondRows}</ul></div>
      <div class="chronicle-actions"><button class="st-btn" id="realm-refresh" type="button">↻ Update from the story</button></div>
    </div></div>`;
  ov.style.display = 'flex';
  $('realm-close').addEventListener('click', () => { ov.style.display = 'none'; });
  ov.addEventListener('click', (e) => { if (e.target === ov) ov.style.display = 'none'; });
  ov.querySelectorAll('[data-rmplace]').forEach(b => b.addEventListener('click', () => { const ww = _loadWorldS(cid); ww.places.splice(Number(b.dataset.rmplace), 1); _saveWorldS(cid, ww); openRealm(); }));
  ov.querySelectorAll('[data-rmfac]').forEach(b => b.addEventListener('click', () => { const ww = _loadWorldS(cid); ww.factions.splice(Number(b.dataset.rmfac), 1); _saveWorldS(cid, ww); openRealm(); }));
  const rb = $('realm-refresh');
  rb.addEventListener('click', async () => { rb.disabled = true; rb.textContent = 'Updating…'; const r = await _updateWorldS(cid); if (r === 'ok') { openRealm(); return; } rb.disabled = false; rb.textContent = r === 'empty' ? '↻ Nothing new yet — try again' : "↻ Couldn't read that — try again"; setTimeout(() => { const b = $('realm-refresh'); if (b) b.textContent = '↻ Update from the story'; }, 2800); });
}
function toggleRealm() { const ov = $('studio-realm-overlay'); if (ov && ov.style.display === 'flex') { ov.style.display = 'none'; return; } openRealm(); }

// ── Cross-session NPC relationships (global, keyed by name) ──────────────────
// A character met in a DM campaign should remember the player in a one-on-one
// chat, and vice versa. Codex updates feed this global store; chats read it.
const REL_KEY = 'studio-rel-global';
function _loadRel() { try { return JSON.parse(localStorage.getItem(REL_KEY) || 'null') || { npcs: {} }; } catch { return { npcs: {} }; } }
function _saveRel(r) { try { localStorage.setItem(REL_KEY, JSON.stringify(r)); } catch {} _pushState('_global', 'rel', r); }
function _relName(name) { return (name || '').trim().toLowerCase(); }
function _relFor(name) { const r = _loadRel(); return (r.npcs || {})[_relName(name)] || null; }
function _upsertRel(name, disposition, note) {
  const key = _relName(name); if (!key) return;
  const r = _loadRel(); r.npcs = r.npcs || {};
  const prev = r.npcs[key] || {};
  r.npcs[key] = { name: (name || '').trim(), disposition: disposition || prev.disposition || 'neutral', note: note || prev.note || '', at: _meCount() };
  _saveRel(r);
}
async function _hydrateRel() {
  try {
    const res = await _fetchT(`${API_BASE}/api/characters/studio/state/_global`);
    if (res.ok) {
      const st = (await res.json()).state || {};
      if (st.rel) localStorage.setItem(REL_KEY, JSON.stringify(st.rel));
      if (st.cworlds) localStorage.setItem(CWORLDS_KEY, JSON.stringify(st.cworlds));
      if (st.cstories) localStorage.setItem(CSTORIES_KEY, JSON.stringify(st.cstories));
      if (st.loreart) localStorage.setItem(LOREART_KEY, JSON.stringify(st.loreart));
    }
  } catch {}
  // Register player-forged content with the world module either way (cache-only is fine).
  setCustomWorlds(_loadCWorlds());
  setCustomStories(_loadCStories());
}

// ── Durable world state (server sync over the localStorage cache) ───────────
// localStorage stays the fast synchronous cache every _loadX reads; the server
// is the durable source of truth. On chat open we hydrate the cache from the
// server (or migrate existing local data up the first time); every _saveX
// pushes its blob back, debounced.
const _WS_KEYS = { mem: MEM_KEY, codex: CODEX_KEY, quests: QUEST_KEY, combat: COMBAT_KEY, sheet: SHEET_KEY, gm: GM_KEY, notes: NOTES_KEY, bmap: BMAP_KEY, inv: INV_KEY, clock: CLOCK_KEY, world: WORLD_KEY };
// Kinds that live only under the '_global' pseudo-cid (never per-adventure, so
// they're excluded from _hydrateState's per-cid migration sweep).
const _WS_GLOBAL = { rel: 1, cworlds: 1, cstories: 1, loreart: 1 };
const _WS_RAW = new Set(['notes']);   // stored as a plain string, not JSON
const _pushTimers = {};
const _pushPending = {};   // k -> {cid, kind, value} not yet sent to the server
function _pushState(cid, kind, value) {
  if (!cid || !(_WS_KEYS[kind] || (cid === '_global' && _WS_GLOBAL[kind]))) return;
  const k = cid + ':' + kind;
  _pushPending[k] = { cid, kind, value };
  clearTimeout(_pushTimers[k]);
  _pushTimers[k] = setTimeout(() => _pushFlushOne(k), 600);
}
function _pushFlushOne(k) {
  const p = _pushPending[k]; if (!p) return;
  delete _pushPending[k];
  // keepalive lets the request survive a tab close — a sale made just before
  // leaving used to be resurrected on the next load because its PUT died.
  fetch(`${API_BASE}/api/characters/studio/state/${encodeURIComponent(p.cid)}/${p.kind}`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ value: p.value }), keepalive: true,
  }).catch(() => {});   // best-effort: the local cache already holds the truth for this session
}
// Leaving the page flushes every debounced write immediately.
window.addEventListener('pagehide', () => { Object.keys(_pushPending).forEach(_pushFlushOne); });
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') Object.keys(_pushPending).forEach(_pushFlushOne); });
// fetch with an abort timeout — a slow/hanging endpoint must never block the UI.
function _fetchT(url, opts, ms = 4500) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  return fetch(url, { ...(opts || {}), signal: ctrl.signal }).finally(() => clearTimeout(t));
}
async function _hydrateState(cid) {
  if (!cid) return;
  let server = {};
  try {
    const r = await _fetchT(`${API_BASE}/api/characters/studio/state/${encodeURIComponent(cid)}`);   // timeout → fall back to local, still enter play
    if (r.ok) server = (await r.json()).state || {};
  } catch {}
  for (const [kind, keyFn] of Object.entries(_WS_KEYS)) {
    const key = keyFn(cid);
    if (server[kind] != null) {
      // Server wins — refresh the local cache from durable storage.
      try { localStorage.setItem(key, _WS_RAW.has(kind) ? String(server[kind]) : JSON.stringify(server[kind])); } catch {}
    } else {
      // First run for this kind: migrate any existing local data up to the server.
      const raw = localStorage.getItem(key);
      if (raw != null && raw !== '') {
        try { _pushState(cid, kind, _WS_RAW.has(kind) ? raw : JSON.parse(raw)); } catch {}
      }
    }
  }
}

// ── Init ──────────────────────────────────────────────────────────────────────
export function init(apiBase) {
  API_BASE = apiBase || '';
  try { if (localStorage.getItem('studio-reduce-motion') === '1') document.documentElement.classList.add('mf-reduce-motion'); } catch {}   // honor the saved motion pref
  if (_ttsAvailable()) { _ttsVoices(); try { window.speechSynthesis.onvoiceschanged = () => { _ttsVoices(); }; } catch {} }
  $('studio-close')?.addEventListener('click', close);
  document.querySelectorAll('#studio-modal .studio-tab').forEach(tab =>
    tab.addEventListener('click', () => {
      const v = tab.dataset.view;
      if (v === 'campaigns') { renderCampaigns(); switchView('campaigns'); }
      else if (v === 'worlds') { renderWorlds(); switchView('worlds'); }
      else { renderRoster(); switchView('roster'); }
    }));
  // Launch points: the icon-rail button and the persona-modal shortcut.
  $('rail-studio')?.addEventListener('click', () => open(false));
  $('tool-studio-btn')?.addEventListener('click', () => open(false));
  $('cs-open-btn')?.addEventListener('click', () => open(false));
  // Esc peels ONE layer: topmost overlay first, then side panels, then the
  // More menu. It never quits a live adventure (that's the ⌂ button's job) —
  // it only exits to the title screen from the menu surfaces.
  document.addEventListener('keydown', (e) => {
    const modal = $('studio-modal');
    if (e.key !== 'Escape' || !modal || modal.classList.contains('hidden')) return;
    // 0. A pending reaction prompt must resolve as "take the hit", never vanish
    //    for free — otherwise Escape dodges every attack.
    if (_reactionTakeHit) { _reactionTakeHit(); return; }
    // 1. Close the topmost visible overlay (party, saves, notes, map, lore, …).
    const overlays = [...modal.querySelectorAll('.chronicle-overlay, .map-overlay, .notes-overlay')]
      .filter(o => o.offsetHeight > 0 && o.style.display !== 'none');
    if (overlays.length) { overlays[overlays.length - 1].style.display = 'none'; return; }
    // 2. Close an open side panel.
    const panel = modal.querySelector('.sheet-panel.open, .inv-panel.open, #studio-combat-panel.open, .gm-panel.open, .codex-panel.open, .realm-panel.open, .quests-panel.open');
    if (panel) { panel.classList.remove('open'); return; }
    // 3. Close the More menu.
    const menu = $('studio-more-menu');
    if (menu && !menu.hidden) { menu.hidden = true; $('studio-more-btn')?.setAttribute('aria-expanded', 'false'); return; }
    // 4. Only the menu surfaces exit to the title; a live chat stays put.
    if (_view !== 'chat' && _view !== 'forge') close();
  });
}

// ── Game settings — the title-menu ⚙ (native to the game, not the workspace) ──
// Replaces the imported workspace settings modal (models/email/reminders/etc.)
// with only what a player needs: the GM's model, sound, motion, account, about.
export async function openSettings() {
  const host = document.body;
  let ov = document.getElementById('mf-settings-overlay');
  if (!ov) { ov = document.createElement('div'); ov.id = 'mf-settings-overlay'; ov.className = 'chronicle-overlay mf-settings-overlay'; host.appendChild(ov); }
  // Make sure the model list is loaded so the GM-model picker has options.
  try { if (window.modelsModule && window.modelsModule.refreshModels) await window.modelsModule.refreshModels(false); } catch {}
  const items = (window.modelsModule && window.modelsModule.getCachedItems) ? (window.modelsModule.getCachedItems() || []) : [];
  const online = items.filter(it => !it.offline);
  const modelOpts = [];
  let saved = null; try { saved = JSON.parse(localStorage.getItem('studio-gm-model') || 'null'); } catch {}
  const savedModel = saved && saved.model;
  online.forEach(it => {
    (it.models || []).concat(it.models_extra || []).forEach(m => {
      const sel = savedModel === m ? ' selected' : '';
      modelOpts.push(`<option value="${_esc(m)}" data-url="${_esc(it.url || it.endpoint_url || '')}" data-eid="${_esc(it.endpoint_id || '')}"${sel}>${_esc(m)}</option>`);
    });
  });
  const auto = _narrationModel();
  const tts = _loadTTS();
  const voices = (_ttsAvailable() ? window.speechSynthesis.getVoices() : []) || [];
  const rm = (() => { try { return localStorage.getItem('studio-reduce-motion') === '1'; } catch { return false; } })();
  let ver = ''; try { ver = (await (await fetch(`${API_BASE}/api/version`)).json()).version || ''; } catch {}
  const row = (label, control, hint) => `<div class="mf-set-row"><div class="mf-set-label">${label}${hint ? `<span class="mf-set-hint">${hint}</span>` : ''}</div><div class="mf-set-ctl">${control}</div></div>`;
  const toggle = (id, on) => `<button type="button" class="mf-switch${on ? ' on' : ''}" id="${id}" role="switch" aria-checked="${on}"><span></span></button>`;
  ov.innerHTML = `<div class="chronicle-sheet mf-settings-sheet" role="dialog" aria-modal="true" aria-label="Settings">
    <div class="chronicle-bar"><h2>⚙ Settings</h2><button class="studio-close" id="mf-set-close" type="button" aria-label="Close">✕</button></div>
    <div class="chronicle-list mf-settings-list">
      <div class="mf-set-group">Game Master</div>
      ${row('AI model', modelOpts.length
        ? `<select id="mf-gm-model" class="studio-select"><option value="">✨ Auto (${_esc((auto && auto.model) || 'best local')})</option>${modelOpts.join('')}</select>`
        : `<span class="mf-set-note">No models found. <a href="/workspace" target="_blank" rel="noopener">Add one ›</a></span>`, 'The brain that runs your GM &amp; companions')}

      <div class="mf-set-group">Sound &amp; motion</div>
      ${row('Sound effects', toggle('mf-sfx', _sfxOn()))}
      ${row('Ambient soundscape', toggle('mf-amb', _ambOn()), 'Wind, rain, tavern murmur, combat rumble')}
      ${row('Ambient volume', `<input type="range" id="mf-amb-vol" min="0" max="100" step="5" value="${Math.round(_ambVol() * 100)}" class="mf-range">`)}
      ${row('Narrate the story aloud', toggle('mf-tts', !!tts.on))}
      ${_ttsAvailable() && voices.length ? row('Narrator voice', `<select id="mf-tts-voice" class="studio-select"><option value="">Default</option>${voices.map(v => `<option value="${_esc(v.name)}"${tts.voice === v.name ? ' selected' : ''}>${_esc(v.name)}</option>`).join('')}</select>`) : ''}
      ${row('Reduce motion', toggle('mf-rm', rm), 'Calmer — fewer animations')}

      <div class="mf-set-group">Account</div>
      ${row('', `<button class="st-btn ghost small" id="mf-logout" type="button">Sign out</button> <a class="st-btn ghost small" href="/workspace" target="_blank" rel="noopener" style="text-decoration:none">Advanced settings ›</a>`)}

      <div class="mf-set-group">About</div>
      ${row('Mythforge', `<span class="mf-set-note">${ver ? 'v' + _esc(ver) : ''}</span>`)}
      ${row('', `<button class="st-btn ghost small danger" id="mf-shutdown" type="button">⏻ Shut down the server</button>`, 'Stops the game server on this machine')}
    </div></div>`;
  ov.style.display = 'flex';
  const close = () => { ov.style.display = 'none'; };
  ov.querySelector('#mf-set-close').addEventListener('click', close);
  ov.addEventListener('click', e => { if (e.target === ov) close(); });
  // GM model
  const mSel = ov.querySelector('#mf-gm-model');
  mSel?.addEventListener('change', () => {
    const o = mSel.selectedOptions[0];
    if (!mSel.value) { try { localStorage.removeItem('studio-gm-model'); } catch {} _toast('GM model: Auto'); return; }
    try { localStorage.setItem('studio-gm-model', JSON.stringify({ model: mSel.value, url: o.dataset.url || '', endpoint_id: o.dataset.eid || '' })); } catch {}
    _toast(`GM model → ${mSel.value}`);
    if (_chat.sessionId) _applyNarrationModel(_chat.sessionId);
  });
  // Sound & motion
  const bindSwitch = (id, get, set) => { const b = ov.querySelector('#' + id); b?.addEventListener('click', () => { const nv = !get(); set(nv); b.classList.toggle('on', nv); b.setAttribute('aria-checked', String(nv)); }); };
  bindSwitch('mf-sfx', _sfxOn, v => { _setSfx(v); _reflectSfxBtn(); if (v) { _sfx('loot'); if (_chat.char) { _startMusic(_chat.char.world_id || ''); _applyAmbient(_chat.char.id); } } else { _stopMusic(); _stopAmbient(); } });
  bindSwitch('mf-amb', _ambOn, v => _setAmbient(v));
  ov.querySelector('#mf-amb-vol')?.addEventListener('input', e => _setAmbientVol((+e.target.value) / 100));
  bindSwitch('mf-tts', () => !!_loadTTS().on, v => { const t = _loadTTS(); t.on = v; _saveTTS(t); _reflectTTSBtn && _reflectTTSBtn(); if (!v) _stopSpeech(); });
  ov.querySelector('#mf-tts-voice')?.addEventListener('change', e => { const t = _loadTTS(); t.voice = e.target.value; _saveTTS(t); });
  bindSwitch('mf-rm', () => { try { return localStorage.getItem('studio-reduce-motion') === '1'; } catch { return false; } }, v => { try { localStorage.setItem('studio-reduce-motion', v ? '1' : '0'); } catch {} document.documentElement.classList.toggle('mf-reduce-motion', v); });
  // Account
  ov.querySelector('#mf-logout')?.addEventListener('click', async () => {
    try { await fetch(`${API_BASE}/api/auth/logout`, { method: 'POST', credentials: 'same-origin' }); } catch {}
    window.location.href = '/login';
  });
  ov.querySelector('#mf-shutdown')?.addEventListener('click', async () => {
    if (!window.confirm('Shut down the Mythforge server? Anyone playing will be disconnected.')) return;
    try { const r = await fetch(`${API_BASE}/api/shutdown`, { method: 'POST' }); if (!r.ok) { window.alert('Only the host machine can shut down the server.'); return; } document.body.innerHTML = '<div style="display:grid;place-items:center;height:100vh;font:600 20px/1.6 system-ui;color:#e8c171;background:#14121f;text-align:center">✦ Mythforge is shutting down.<br><span style="font-size:14px;color:#9a93b5">You can close this tab.</span></div>'; } catch (e) { window.alert('Shutdown failed: ' + e); }
  });
}

const characterStudio = { init, open, continueLast, lastAdventure, openJoinParty, openSettings };
window.characterStudio = characterStudio;
export default characterStudio;
