// static/js/studioAmbient.js
//
// Living per-world backgrounds — a tiny canvas particle engine behind the studio.
// Kinds map to a world's `ambient`: embers (firelit fantasy pub), rain (neon
// cyberpunk downpour), motes (soft slice-of-life daylight), arcane (the default
// grimoire sparks). Subtle by design so text stays readable. Fully respects
// prefers-reduced-motion (renders nothing, no rAF).

let _canvas = null, _ctx = null, _raf = 0, _kind = 'arcane';
let _w = 0, _h = 0, _parts = [];
let _ro = null;
const _reduced = (typeof matchMedia === 'function')
  && matchMedia('(prefers-reduced-motion: reduce)').matches;

const KINDS = {
  arcane:  { n: 56, colors: ['#e8c171', '#b79cf6', '#ffffff'], mode: 'rise', speed: 0.25, size: [0.7, 1.8], alpha: 0.5 },
  embers:  { n: 70, colors: ['#f0a868', '#e8c171', '#ff8a4c'], mode: 'rise', speed: 0.55, size: [0.8, 2.2], alpha: 0.6 },
  rain:    { n: 150, colors: ['#2de2e6', '#7ef0f2', '#9fd0ff'], mode: 'rain', speed: 5.5, size: [0.6, 1.2], alpha: 0.5 },
  motes:   { n: 48, colors: ['#f0d49a', '#cfe0ff', '#ffffff'], mode: 'drift', speed: 0.18, size: [0.8, 2.0], alpha: 0.4 },
};

function _rand(a, b) { return a + (b - a) * ((Math.sin(_parts.length * 999 + performance.now() * 0.0001 + Math.random() * 6.283)) * 0.5 + 0.5); }
function _r(a, b) { return a + Math.random() * (b - a); }

function _spawn(cfg, seed) {
  const c = cfg.colors[(Math.random() * cfg.colors.length) | 0];
  if (cfg.mode === 'rain') {
    return { x: _r(0, _w), y: seed ? _r(0, _h) : -_r(0, _h), len: _r(8, 22), vy: cfg.speed * _r(0.7, 1.4), vx: -0.6, c, a: cfg.alpha * _r(0.4, 1) };
  }
  const size = _r(cfg.size[0], cfg.size[1]);
  const baseY = cfg.mode === 'rise' ? _r(0, _h) + (seed ? 0 : _h) : _r(0, _h);
  return {
    x: _r(0, _w), y: baseY, r: size, c,
    vx: (cfg.mode === 'drift') ? _r(-0.15, 0.15) : _r(-0.12, 0.12),
    vy: (cfg.mode === 'rise') ? -cfg.speed * _r(0.6, 1.5) : _r(-0.1, 0.1) * cfg.speed * 3,
    tw: _r(0, 6.28), tws: _r(0.01, 0.04), a: cfg.alpha,
  };
}

function _seed() {
  const cfg = KINDS[_kind] || KINDS.arcane;
  _parts = [];
  for (let i = 0; i < cfg.n; i++) _parts.push(_spawn(cfg, true));
}

function _resize() {
  if (!_canvas) return;
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  _w = _canvas.clientWidth; _h = _canvas.clientHeight;
  _canvas.width = Math.max(1, _w * dpr);
  _canvas.height = Math.max(1, _h * dpr);
  _ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function _frame() {
  const cfg = KINDS[_kind] || KINDS.arcane;
  _ctx.clearRect(0, 0, _w, _h);
  for (const p of _parts) {
    if (cfg.mode === 'rain') {
      p.y += p.vy; p.x += p.vx;
      if (p.y > _h + 20) { Object.assign(p, _spawn(cfg, false)); }
      _ctx.globalAlpha = p.a;
      _ctx.strokeStyle = p.c; _ctx.lineWidth = 1;
      _ctx.beginPath(); _ctx.moveTo(p.x, p.y); _ctx.lineTo(p.x + p.vx * 1.5, p.y - p.len); _ctx.stroke();
    } else {
      p.x += p.vx; p.y += p.vy; p.tw += p.tws;
      if (cfg.mode === 'rise' && p.y < -10) { Object.assign(p, _spawn(cfg, false)); }
      if (p.x < -10) p.x = _w + 10; if (p.x > _w + 10) p.x = -10;
      if (p.y > _h + 10) p.y = -10; if (p.y < -10 && cfg.mode !== 'rise') p.y = _h + 10;
      const tw = 0.6 + 0.4 * Math.sin(p.tw);
      _ctx.globalAlpha = p.a * tw;
      _ctx.fillStyle = p.c;
      _ctx.beginPath(); _ctx.arc(p.x, p.y, p.r, 0, 6.283); _ctx.fill();
    }
  }
  _ctx.globalAlpha = 1;
  _raf = requestAnimationFrame(_frame);
}

export function startAmbient(canvas, kind) {
  _canvas = canvas;
  if (!_canvas) return;
  _ctx = _canvas.getContext('2d');
  _kind = kind || 'arcane';
  _resize();
  _seed();
  if (_ro) _ro.disconnect();
  _ro = new ResizeObserver(() => { _resize(); }); _ro.observe(_canvas);
  if (_reduced) { _frameOnce(); return; }     // static field, no animation
  cancelAnimationFrame(_raf);
  _raf = requestAnimationFrame(_frame);
}

function _frameOnce() {
  // Draw one static frame for reduced-motion users.
  const cfg = KINDS[_kind] || KINDS.arcane;
  _ctx.clearRect(0, 0, _w, _h);
  for (const p of _parts) {
    _ctx.globalAlpha = (p.a || cfg.alpha) * 0.7;
    _ctx.fillStyle = p.c;
    _ctx.beginPath(); _ctx.arc(p.x, p.y, p.r || 1.2, 0, 6.283); _ctx.fill();
  }
  _ctx.globalAlpha = 1;
}

export function setAmbient(kind) {
  const next = kind || 'arcane';
  if (next === _kind || !_canvas) { _kind = next; return; }
  _kind = next;
  _resize(); _seed();
  if (_reduced) _frameOnce();
}

export function stopAmbient() {
  cancelAnimationFrame(_raf); _raf = 0;
  if (_ro) { _ro.disconnect(); _ro = null; }
  if (_ctx && _w) _ctx.clearRect(0, 0, _w, _h);
}
