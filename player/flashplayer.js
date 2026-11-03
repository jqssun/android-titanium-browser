/* Flash Player - UC-style in-page video player.
 *
 * Dev build: load as a script (or paste into the console) in any Blink browser.
 * It adds a chip when a video exists; the chip opens the player over the page's
 * own video element. No extension, no build step.
 *
 *   __flashPlayer.open(video?)   open on a video (default: the playing/largest one)
 *   __flashPlayer.close()        restore the page
 *   __flashPlayer.toggle()
 *   __flashPlayer.setAutoOpen(b) open by itself whenever a video starts playing
 *   __flashPlayer.pickVideo()    the video open() would choose
 *
 * The video element is never moved in the DOM: only its inline styles (and those
 * of its ancestors, which may form a stacking/containing block) are rewritten and
 * saved, then restored on close.
 */
(() => {
  'use strict';

  const VERSION = '0.1.0';
  const ZMAX = 2147483647;

  if (window.__flashPlayer) {
    try { window.__flashPlayer.chip(true); } catch (_) {}
    return;
  }

  const cfg = {
    autoOpen: false,
    seekSpan: 90,
    hideDelay: 3500,
    longPress: 600,
    dblTap: 300
  };

  const SVGNS = 'http://www.w3.org/2000/svg';

  /* Icons are created as SVG nodes rather than assigned as markup: pages under a
     require-trusted-types-for 'script' policy (YouTube) reject innerHTML, DOMParser
     and eval of strings, but attribute sets are not sinks. Each entry is a factory
     so a node is never shared between two parents. */
  function node(tag, attrs, kids) {
    const n = document.createElementNS(SVGNS, tag);
    if (attrs) for (const k in attrs) n.setAttribute(k, attrs[k]);
    if (kids) for (const c of kids) n.appendChild(c);
    return n;
  }

  const tri = (d) => () => node('svg', { viewBox: '0 0 24 24' }, [node('path', { d })]);
  const SVG = {
    play: () => node('svg', { viewBox: '0 0 24 24' }, [node('path', { d: 'M8 5v14l11-7z' })]),
    pause: () => node('svg', { viewBox: '0 0 24 24' }, [node('path', { d: 'M6 5h4v14H6zm8 0h4v14h-4z' })]),
    back: tri('M15.7 7.4 14.3 6 8.3 12l6 6 1.4-1.4L11.1 12z'),
    replay: tri('M11 18V6l-8.5 6 8.5 6zm.5-6 8.5 6V6l-8.5 6z'),
    forward: () => node('svg', { viewBox: '0 0 24 24' }, [
      node('g', { transform: 'translate(24,0) scale(-1,1)' },
        [node('path', { d: 'M11 18V6l-8.5 6 8.5 6zm.5-6 8.5 6V6l-8.5 6z' })])
    ]),
    cc: () => node('svg', { viewBox: '0 0 24 24' }, [
      node('rect', { x: '2.5', y: '5', width: '19', height: '14', rx: '2.2',
        fill: 'none', stroke: 'currentColor', 'stroke-width': '1.5' }),
      node('text', { x: '12', y: '15.2', 'font-size': '7', 'font-weight': '700',
        'text-anchor': 'middle', fill: 'currentColor', 'font-family': 'Roboto,system-ui,sans-serif' },
        [document.createTextNode('CC')])
    ]),
    gear: tri('M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.48.48 0 0 0-.48.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.48.48 0 0 0 .12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.48-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.48.48 0 0 0-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z'),
    fs: tri('M4 9V4h5v2H6v3zm16 0V4h-5v2h3v3zM4 15v5h5v-2H6v-3zm16 0v5h-5v-2h3v-3z'),
    fsExit: tri('M9 4v5H4V7h3V4zm6 0v5h5V7h-3V4zM9 20v-5H4v2h3v3zm6 0v-5h5v2h-3v3z'),
    mini: tri('M3 5h18v14H3V5zm11 8h5v4h-5v-4z'),
    close: () => node('svg', { viewBox: '0 0 24 24' }, [
      node('path', { d: 'M6 6l12 12M18 6L6 18', stroke: 'currentColor',
        'stroke-width': '2.2', fill: 'none', 'stroke-linecap': 'round' })
    ]),
    rotate: tri('M12 5V2L7 6l5 4V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7z'),
    loop: tri('M7 7h10v3l4-4-4-4v3H5v6h2zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2z'),
    speed: () => node('svg', { viewBox: '0 0 24 24' }, [
      node('path', { d: 'M12 4a8 8 0 1 0 8 8h-2a6 6 0 1 1-6-6V4z' }),
      node('path', { d: 'M16.4 7.6 12 12l1.4 1.4 4.4-4.4z' })
    ])
  };

  const CSS = `
*{box-sizing:border-box}
.surface{position:absolute;inset:0;pointer-events:auto;touch-action:none;-webkit-tap-highlight-color:transparent}
.layer{position:absolute;left:0;right:0;pointer-events:none;transition:opacity .25s ease}
.layer>*{pointer-events:auto}
.off{opacity:0!important;pointer-events:none!important}
.off *{pointer-events:none!important}
.grow{flex:1}
.btn{-webkit-appearance:none;appearance:none;border:0;background:transparent;color:#fff;cursor:pointer;
  display:flex;align-items:center;justify-content:center;width:48px;height:48px;border-radius:50%;
  padding:0;-webkit-tap-highlight-color:transparent;transition:background .15s,opacity .15s}
.btn:active{background:#ffffff26}
.btn:disabled{opacity:.35;pointer-events:none}
.btn svg{width:24px;height:24px;display:block;fill:currentColor;filter:drop-shadow(0 1px 2px #0005)}
.top{top:0;display:flex;align-items:center;gap:2px;
  padding:calc(4px + env(safe-area-inset-top)) 6px 20px 4px;background:linear-gradient(#000c,#0000)}
.title{font-size:14px;font-weight:500;line-height:20px;color:#fff;text-shadow:0 1px 2px #0009;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:58%;margin-left:4px}
.bottom{bottom:0;padding:22px 6px calc(4px + env(safe-area-inset-bottom));
  background:linear-gradient(#0000,#000c 62%)}
.tr{display:flex;align-items:center;gap:2px;padding:0 8px}
.t{font-size:12px;line-height:16px;color:#fff;font-variant-numeric:tabular-nums;white-space:nowrap;
  text-shadow:0 1px 2px #0009;min-width:36px;text-align:center}
.seek{position:relative;flex:1;height:28px;display:flex;align-items:center;touch-action:none;
  cursor:pointer;padding:0 6px}
.track{position:relative;flex:1;height:3px;border-radius:2px;background:#ffffff42;transition:height .12s}
.seek.drag .track{height:5px}
.buf,.fil{position:absolute;left:0;top:0;bottom:0;border-radius:2px}
.buf{background:#ffffff66}
.fil{background:#f00}
.knob{position:absolute;top:50%;left:0;width:12px;height:12px;margin:-6px 0 0 -6px;border-radius:50%;
  background:#f00;transition:width .12s,height .12s,margin .12s,box-shadow .12s}
.seek.drag .knob{width:16px;height:16px;margin:-8px 0 0 -8px;box-shadow:0 0 0 8px #f002}
.tip{position:absolute;bottom:16px;left:0;transform:translateX(-50%);background:#212121;color:#fff;
  font-size:12px;line-height:16px;padding:4px 8px;border-radius:4px;white-space:nowrap;
  opacity:0;transition:opacity .12s;pointer-events:none}
.seek.drag .tip{opacity:1}
.actions{display:flex;align-items:center;gap:0;padding:0 4px;margin-top:-2px}
.actions .btn{width:48px;height:46px}
.center{top:0;bottom:0;display:flex;align-items:center;justify-content:center}
.center .btn{width:104px;height:104px;background:transparent}
.center .btn:active{background:transparent}
.center .btn svg{width:66px;height:66px;filter:drop-shadow(0 2px 10px #0007)}
.ripple{position:absolute;top:50%;width:112px;height:112px;margin-top:-56px;border-radius:50%;
  background:#00000070;display:flex;align-items:center;justify-content:center;color:#fff;
  opacity:0;pointer-events:none}
.ripple svg{width:44px;height:44px;fill:#fff}
.ripple.left{left:12%}
.ripple.right{right:12%}
.ripple.show{animation:rip .6s ease-out}
@keyframes rip{0%{opacity:0;transform:scale(.6)}15%{opacity:.92;transform:scale(1)}
  70%{opacity:.92;transform:scale(1)}100%{opacity:0;transform:scale(1.08)}}
.hud{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);background:#212121e6;color:#fff;
  padding:9px 14px;border-radius:8px;font-size:14px;font-weight:500;opacity:0;
  transition:opacity .18s;pointer-events:none;white-space:nowrap}
.hud.on{opacity:1}
.mini-ctl{top:calc(6px + env(safe-area-inset-top));right:4px;display:none;justify-content:flex-end;gap:0}
.mini-ctl .btn{width:40px;height:40px;background:#0007}
.mini-ctl .btn svg{width:20px;height:20px}
:host(.mini) .top,:host(.mini) .center,:host(.mini) .bottom,:host(.mini) .sheet-wrap{display:none}
:host(.mini) .mini-ctl{display:flex}
:host(.mini) .surface{cursor:move}
.sheet-wrap{position:absolute;inset:0;display:none;pointer-events:none}
.sheet-wrap.open{display:block}
.sheet-bg{position:absolute;inset:0;background:#0008;pointer-events:auto;opacity:0;transition:opacity .2s}
.sheet-wrap.open .sheet-bg{opacity:1}
.sheet{position:absolute;left:50%;bottom:0;width:min(440px,100%);background:#212121;color:#fff;
  border-radius:12px 12px 0 0;padding:6px 0 calc(10px + env(safe-area-inset-bottom));
  transform:translateX(-50%) translateY(102%);transition:transform .24s cubic-bezier(.2,.8,.2,1);
  pointer-events:auto;box-shadow:0 -10px 30px #000a}
.sheet-wrap.open .sheet{transform:translateX(-50%) translateY(0)}
.grab{width:32px;height:4px;border-radius:2px;background:#5f5f5f;margin:4px auto 6px}
.srow{display:flex;align-items:center;gap:16px;width:100%;height:52px;padding:0 18px;
  background:none;border:0;color:#fff;font:400 15px/1 "Roboto",system-ui,sans-serif;
  cursor:pointer;text-align:left;-webkit-tap-highlight-color:transparent}
.srow:active{background:#ffffff14}
.srow svg{width:24px;height:24px;fill:#fff;flex:none}
.srow .val{margin-left:auto;color:#aaa;font-size:13px}
.sgrid{display:none;flex-wrap:wrap;gap:8px;padding:2px 18px 10px 58px}
.sgrid.open{display:flex}
.chip{background:#ffffff1f;color:#fff;border:0;border-radius:16px;padding:8px 14px;
  font:500 13px/1 "Roboto",system-ui,sans-serif;cursor:pointer}
.chip.on{background:#f00}
`;

  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };

  function setIcon(box, make) { box.replaceChildren(make()); }

  const fmt = (t) => {
    if (!isFinite(t) || t < 0) t = 0;
    t = Math.floor(t);
    const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s).padStart(2, '0');
  };

  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

  const cap = (e, id) => { try { e.setPointerCapture(id); } catch (_) {} };

  const S = {
    video: null, host: null, root: null, chipHost: null,
    saved: new Map(), hideCss: null,
    active: false, mini: false, rotated: false, brightness: 1, controls: true,
    hideTimer: 0, raf: 0, tapTimer: 0, lastTap: 0, held: false, holdTimer: 0,
    hudTimer: 0, g: null, seekPreview: -1, savedRate: 1, miniRect: null,
    ui: {}, ac: null, pausedIcon: null, timeText: '', durText: '', bufWidth: '', fileWidth: '',
    flashUntil: 0, centerShown: null, sheetOpen: false, seeking: false
  };

  /* ---------- page state save / restore ---------- */

  function store(e) {
    if (!S.saved.has(e)) S.saved.set(e, e.getAttribute('style'));
  }

  function restore() {
    for (const [e, css] of S.saved) {
      if (css == null) e.removeAttribute('style');
      else e.setAttribute('style', css);
    }
    S.saved.clear();
  }

  /* ---------- video selection ---------- */

  function pickVideo() {
    let best = null, bestArea = 0;
    const vs = document.querySelectorAll('video');
    for (const v of vs) {
      if (S.active && v === S.video) continue;
      if (v.closest('#fp-host')) continue;
      const r = v.getBoundingClientRect();
      const area = Math.max(1, r.width) * Math.max(1, r.height);
      if (!v.paused && v.readyState > 0 && area > 4000) return v;
      if (area > bestArea) { bestArea = area; best = v; }
    }
    return best;
  }

  /* ---------- geometry ---------- */

  function applyVideoFull() {
    const v = S.video, s = v.style;
    const set = (p, val) => s.setProperty(p, val, 'important');
    set('position', 'fixed');
    set('z-index', String(ZMAX - 10));
    set('inset', '0');
    set('left', '0'); set('top', '0'); set('right', '0'); set('bottom', '0');
    set('width', '100vw'); set('height', '100vh');
    set('max-width', 'none'); set('max-height', 'none');
    set('min-width', '0'); set('min-height', '0');
    set('margin', '0'); set('padding', '0');
    set('transform', 'none');
    set('object-fit', 'contain');
    set('background', '#000');
    set('visibility', 'visible'); set('opacity', '1'); set('display', 'block');
    set('filter', 'brightness(' + S.brightness + ')');
    set('border-radius', '0');
    set('box-shadow', 'none');
    set('outline', 'none');
  }

  function applyRotate(on) {
    const s = S.video.style;
    if (on) {
      s.setProperty('inset', 'auto', 'important');
      s.setProperty('right', 'auto', 'important');
      s.setProperty('bottom', 'auto', 'important');
      s.setProperty('left', '0', 'important');
      s.setProperty('top', '0', 'important');
      s.setProperty('width', '100vh', 'important');
      s.setProperty('height', '100vw', 'important');
      s.setProperty('transform-origin', '0 0', 'important');
      s.setProperty('transform', 'translate(100vw,0) rotate(90deg)', 'important');
    } else {
      applyVideoFull();
    }
  }

  function hostFull() {
    const h = S.host.style;
    h.left = '0'; h.top = '0'; h.right = '0'; h.bottom = '0';
    h.inset = '0';
    h.width = 'auto'; h.height = 'auto';
  }

  function hostRect(r) {
    const h = S.host.style;
    h.inset = 'auto';
    h.left = r.left + 'px'; h.top = r.top + 'px';
    h.right = 'auto'; h.bottom = 'auto';
    h.width = r.w + 'px'; h.height = r.h + 'px';
  }

  function applyMini() {
    const r = S.miniRect, v = S.video, s = v.style;
    s.setProperty('inset', 'auto', 'important');
    s.setProperty('right', 'auto', 'important');
    s.setProperty('bottom', 'auto', 'important');
    s.setProperty('left', r.left + 'px', 'important');
    s.setProperty('top', r.top + 'px', 'important');
    s.setProperty('width', r.w + 'px', 'important');
    s.setProperty('height', r.h + 'px', 'important');
    s.setProperty('transform', 'none', 'important');
    s.setProperty('border-radius', '10px', 'important');
    s.setProperty('box-shadow', '0 10px 30px #000a', 'important');
    hostRect(r);
  }

  /* ---------- UI ---------- */

  function btn(cls, markup, label) {
    const b = el('button', 'btn ' + cls);
    b.type = 'button';
    if (markup) b.appendChild(markup());
    if (label) b.setAttribute('aria-label', label);
    return b;
  }

  function srow(markup, label, val) {
    const b = el('button', 'srow');
    b.type = 'button';
    const v = el('span', 'val', val);
    b.append(markup(), el('span', null, label), v);
    return b;
  }

  function buildUI() {
    S.host = document.createElement('div');
    S.host.id = 'fp-host';
    S.host.style.cssText = 'all:initial;display:block;position:fixed;inset:0;z-index:' + ZMAX +
      ';pointer-events:none;-webkit-tap-highlight-color:transparent;' +
      'font:500 14px/1.2 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#fff';
    S.root = S.host.attachShadow({ mode: 'open' });
    const style = document.createElement('style');
    style.textContent = CSS;
    S.root.appendChild(style);

    const surface = el('div', 'surface');
    const hud = el('div', 'hud');
    const ripL = el('div', 'ripple left');
    const ripR = el('div', 'ripple right');
    ripL.appendChild(SVG.replay());
    ripR.appendChild(SVG.forward());
    S.root.append(surface, hud, ripL, ripR);

    const top = el('div', 'layer top');
    const back = btn('', SVG.back, 'Back');
    const title = el('span', 'title');
    const mini = btn('', SVG.mini, 'Minimize');
    top.append(back, title, el('span', 'grow'), mini);

    const center = el('div', 'layer center');
    const main = btn('', SVG.play, 'Play');
    center.append(main);

    const bottom = el('div', 'layer bottom');
    const tr = el('div', 'tr');
    const time = el('span', 't', '0:00');
    const dur = el('span', 't', '0:00');
    const seek = el('div', 'seek');
    const track = el('div', 'track');
    const buf = el('div', 'buf');
    const fil = el('div', 'fil');
    const knob = el('div', 'knob');
    const tip = el('div', 'tip', '0:00');
    track.append(buf, fil, knob, tip);
    seek.appendChild(track);
    tr.append(time, seek, dur);

    const actions = el('div', 'actions');
    const play = btn('', SVG.play, 'Play');
    const rew = btn('', SVG.replay, 'Rewind 10 seconds');
    const fwd = btn('', SVG.forward, 'Forward 10 seconds');
    const cc = btn('', SVG.cc, 'Captions');
    const gear = btn('', SVG.gear, 'Settings');
    const fs = btn('', SVG.fs, 'Fullscreen');
    actions.append(play, rew, fwd, el('span', 'grow'), cc, gear, fs);
    bottom.append(tr, actions);

    const miniCtl = el('div', 'layer mini-ctl');
    const expand = btn('', SVG.fs, 'Expand');
    const closeMini = btn('', SVG.close, 'Close player');
    miniCtl.append(expand, closeMini);

    const sheetWrap = el('div', 'sheet-wrap');
    const sheetBg = el('div', 'sheet-bg');
    const sheet = el('div', 'sheet');
    const rowSpeed = srow(SVG.speed, 'Playback speed', '1x');
    const grid = el('div', 'sgrid');
    for (const r of [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]) {
      const c = el('button', 'chip', (Number.isInteger(r) ? r : r.toFixed(2)) + 'x');
      c.type = 'button';
      c.dataset.rate = String(r);
      grid.appendChild(c);
    }
    const rowLoop = srow(SVG.loop, 'Loop video', 'Off');
    const rowRot = srow(SVG.rotate, 'Rotate screen', 'Off');
    for (const b of [rowSpeed, rowLoop, rowRot]) b.type = 'button';
    sheet.append(el('div', 'grab'), rowSpeed, grid, rowLoop, rowRot);
    sheetWrap.append(sheetBg, sheet);

    S.root.append(top, center, bottom, miniCtl, sheetWrap);

    Object.assign(S.ui, {
      surface, hud, ripL, ripR, top, back, title, mini, center, main, bottom, tr,
      time, dur, seek, track, buf, fil, knob, tip, actions, play, rew, fwd, cc, gear, fs,
      miniCtl, expand, closeMini, sheetWrap, sheetBg, sheet, rowSpeed, grid, rowLoop, rowRot,
      valSpeed: rowSpeed.querySelector('.val'),
      valLoop: rowLoop.querySelector('.val'),
      valRot: rowRot.querySelector('.val')
    });

    (document.body || document.documentElement).appendChild(S.host);

    const on = (t, ty, fn, o) => t.addEventListener(ty, fn, Object.assign({ signal: S.ac.signal }, o || {}));

    on(main, 'click', togglePlay);
    on(play, 'click', togglePlay);
    on(back, 'click', () => {
      if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
      else close();
    });
    on(rew, 'click', () => seekBy(-10));
    on(fwd, 'click', () => seekBy(10));
    on(cc, 'click', toggleCC);
    on(gear, 'click', () => { if (S.sheetOpen) closeSheet(); else openSheet(); });
    on(fs, 'click', toggleFs);
    on(mini, 'click', () => setMini(true));
    on(expand, 'click', () => setMini(false));
    on(closeMini, 'click', () => close());
    on(sheetBg, 'click', closeSheet);
    on(rowSpeed, 'click', () => S.ui.grid.classList.toggle('open'));
    on(rowLoop, 'click', () => { S.video.loop = !S.video.loop; syncLoop(); });
    on(rowRot, 'click', () => toggleRotate());
    on(grid, 'click', (e) => {
      const c = e.target.closest ? e.target.closest('.chip') : null;
      if (!c || !c.dataset.rate) return;
      S.video.playbackRate = Number(c.dataset.rate);
      closeSheet();
    });
    bindSeek();
    bindGestures();
    bindKeys();
    on(document, 'fullscreenchange', syncFsIcon);

    const tracks = S.video.textTracks;
    if (tracks) {
      for (const ty of ['addtrack', 'removetrack', 'change']) {
        try { tracks.addEventListener(ty, syncCC, { signal: S.ac.signal }); } catch (_) {}
      }
    }

    applyVideoFull();
    syncFsIcon();
  }

  function syncFsIcon() {
    const onFs = !!document.fullscreenElement;
    setIcon(S.ui.fs, onFs ? SVG.fsExit : SVG.fs);
    if (!onFs) {
      try { screen.orientation && screen.orientation.unlock && screen.orientation.unlock(); } catch (_) {}
    }
  }

  async function toggleFs() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else {
        await document.documentElement.requestFullscreen({ navigationUI: 'hide' });
        try { await screen.orientation.lock('landscape'); } catch (_) {}
      }
    } catch (_) {}
    applyVideoFull();
    syncFsIcon();
  }

  function togglePlay() {
    const v = S.video;
    if (!v) return;
    S.flashUntil = performance.now() + 450;
    if (v.paused) v.play().catch(() => {});
    else v.pause();
    syncCenter();
  }

  function seekBy(d) {
    const v = S.video;
    v.currentTime = clamp(v.currentTime + d, 0, (v.duration || 1e9) - 0.05);
    showRipple(d < 0 ? 'left' : 'right');
    sync();
  }

  function showRipple(side) {
    const r = side === 'left' ? S.ui.ripL : S.ui.ripR;
    if (!r) return;
    r.classList.remove('show');
    void r.offsetWidth;
    r.classList.add('show');
    clearTimeout(r._ripTimer);
    r._ripTimer = setTimeout(() => r.classList.remove('show'), 640);
  }

  function previewSeek(t) {
    const v = S.video;
    const p = v.duration ? clamp(t / v.duration, 0, 1) : 0;
    const w = (p * 100).toFixed(3) + '%';
    S.seeking = true;
    S.ui.fil.style.width = w;
    S.ui.knob.style.left = w;
    S.ui.time.textContent = fmt(t);
    showHud(fmt(t) + ' / ' + fmt(v.duration || 0), 0);
  }

  function toggleRotate() {
    if (S.mini) setMini(false);
    S.rotated = !S.rotated;
    applyRotate(S.rotated);
    syncRot();
    closeSheet();
  }

  function openSheet() {
    if (!S.ui.sheetWrap || S.sheetOpen) return;
    S.sheetOpen = true;
    S.ui.sheetWrap.classList.add('open');
    syncRate();
    syncLoop();
    syncRot();
    showControls();
  }

  function closeSheet() {
    if (!S.ui.sheetWrap) return;
    S.sheetOpen = false;
    S.ui.sheetWrap.classList.remove('open');
    S.ui.grid.classList.remove('open');
    scheduleHide();
  }

  function ccShowing() {
    const list = S.video && S.video.textTracks;
    if (!list) return false;
    for (let i = 0; i < list.length; i++) if (list[i].mode === 'showing') return true;
    return false;
  }

  function syncCC() {
    if (!S.ui.cc) return;
    const on = ccShowing();
    S.ui.cc.style.color = on ? '#f00' : '';
    S.ui.cc.setAttribute('aria-pressed', on ? 'true' : 'false');
  }

  function toggleCC() {
    const list = S.video && S.video.textTracks;
    if (!list || !list.length) { showHud('No captions', 900); return; }
    const on = !ccShowing();
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (t.kind !== 'subtitles' && t.kind !== 'captions') continue;
      t.mode = on ? 'showing' : 'disabled';
    }
    syncCC();
    showHud(on ? 'Captions on' : 'Captions off', 700);
  }

  function setMini(on) {
    if (!S.video) return;
    if (on === S.mini) return;
    if (on) {
      closeSheet();
      if (S.rotated) { S.rotated = false; applyRotate(false); syncRot(); }
      const w = Math.min(380, Math.round(innerWidth * 0.46));
      const h = Math.round(w * 9 / 16);
      S.miniRect = { w, h, left: innerWidth - w - 16, top: Math.round(innerHeight * 0.58) };
      S.mini = true;
      S.host.classList.add('mini');
      applyMini();
      showControls();
    } else {
      S.mini = false;
      S.host.classList.remove('mini');
      hostFull();
      applyVideoFull();
      showControls();
    }
  }

  function showHud(text, ms) {
    clearTimeout(S.hudTimer);
    S.ui.hud.textContent = text;
    S.ui.hud.classList.add('on');
    if (ms !== 0) S.hudTimer = setTimeout(() => S.ui.hud.classList.remove('on'), ms || 900);
  }

  function hideHud() {
    clearTimeout(S.hudTimer);
    S.ui.hud.classList.remove('on');
  }

  function syncCenter() {
    if (!S.ui.center) return;
    const show = !!(S.video && (S.video.paused || performance.now() < S.flashUntil));
    if (show === S.centerShown) return;
    S.centerShown = show;
    S.ui.center.classList.toggle('off', !show);
  }

  function showControls() {
    if (!S.ui.top) return;
    S.controls = true;
    S.ui.top.classList.remove('off');
    S.ui.bottom.classList.remove('off');
    syncCenter();
    scheduleHide();
  }

  function hideControls() {
    if (!S.ui.top || S.sheetOpen) return;
    S.controls = false;
    S.ui.top.classList.add('off');
    S.ui.bottom.classList.add('off');
    S.ui.center.classList.add('off');
    S.centerShown = false;
    clearTimeout(S.hideTimer);
  }

  function scheduleHide() {
    clearTimeout(S.hideTimer);
    if (S.mini || S.sheetOpen) return;
    S.hideTimer = setTimeout(() => {
      if (S.video && !S.video.paused && S.controls && !S.g) hideControls();
    }, cfg.hideDelay);
  }

  /* ---------- sync ---------- */

  function sync() {
    const v = S.video;
    if (!v || !S.ui.fil) return;
    const d = v.duration || 0, c = v.currentTime || 0;
    if (!S.seeking) {
      const p = d ? clamp(c / d, 0, 1) : 0;
      const w = (p * 100).toFixed(3) + '%';
      if (w !== S.fileWidth) {
        S.fileWidth = w;
        S.ui.fil.style.width = w;
        S.ui.knob.style.left = w;
      }
      const tc = fmt(c);
      if (tc !== S.timeText) { S.timeText = tc; S.ui.time.textContent = tc; }
    }
    const td = d ? fmt(d) : '0:00';
    if (td !== S.durText) { S.durText = td; S.ui.dur.textContent = td; }
    if (S.pausedIcon !== v.paused) {
      S.pausedIcon = v.paused;
      const ic = v.paused ? SVG.play : SVG.pause;
      const label = v.paused ? 'Play' : 'Pause';
      S.ui.main.setAttribute('aria-label', label);
      S.ui.play.setAttribute('aria-label', label);
      setIcon(S.ui.main, ic);
      setIcon(S.ui.play, ic);
    }
    syncCenter();
  }

  function syncBuffered() {
    const v = S.video;
    if (!v || !S.ui.buf) return;
    const d = v.duration || 0;
    if (!d || !v.buffered || !v.buffered.length) { S.ui.buf.style.width = '0%'; return; }
    let end = 0;
    for (let i = 0; i < v.buffered.length; i++) end = Math.max(end, v.buffered.end(i));
    const w = (clamp(end / d, 0, 1) * 100).toFixed(2) + '%';
    if (w !== S.bufWidth) { S.bufWidth = w; S.ui.buf.style.width = w; }
  }

  function syncRate() {
    const r = S.video ? S.video.playbackRate : 1;
    const label = (Number.isInteger(r) ? r : r.toFixed(2).replace(/0$/, '')) + 'x';
    if (S.ui.valSpeed && S.ui.valSpeed.textContent !== label) S.ui.valSpeed.textContent = label;
    if (S.ui.grid) {
      for (const c of S.ui.grid.children) {
        c.classList.toggle('on', Math.abs(Number(c.dataset.rate) - r) < 0.001);
      }
    }
  }

  function syncLoop() {
    if (S.ui.valLoop) S.ui.valLoop.textContent = S.video && S.video.loop ? 'On' : 'Off';
  }

  function syncRot() {
    if (S.ui.valRot) S.ui.valRot.textContent = S.rotated ? 'On' : 'Off';
  }

  function bindMedia() {
    const v = S.video;
    const on = (ty, fn) => v.addEventListener(ty, fn, { signal: S.ac.signal });
    on('timeupdate', sync);
    on('progress', syncBuffered);
    on('durationchange', () => { sync(); syncBuffered(); });
    on('loadedmetadata', () => { sync(); syncBuffered(); syncLoop(); });
    on('play', () => { sync(); scheduleHide(); });
    on('pause', () => { sync(); showControls(); });
    on('ratechange', syncRate);
    on('ended', () => { sync(); showControls(); });
    on('seeked', () => { sync(); syncBuffered(); });
  }

  /* ---------- seek bar ---------- */

  function bindSeek() {
    const seek = S.ui.seek, track = S.ui.track;
    let dragging = false, wasPlaying = false;

    const ratio = (e) => {
      const r = track.getBoundingClientRect();
      return r.width ? clamp((e.clientX - r.left) / r.width, 0, 1) : 0;
    };
    const paint = (p) => {
      const d = S.video.duration || 0;
      const w = (p * 100).toFixed(3) + '%';
      S.seeking = true;
      S.ui.fil.style.width = w;
      S.ui.knob.style.left = w;
      S.ui.tip.style.left = w;
      S.ui.tip.textContent = fmt(p * d);
      S.ui.time.textContent = fmt(p * d);
    };
    const on = (t, ty, fn, o) => t.addEventListener(ty, fn, Object.assign({ signal: S.ac.signal }, o || {}));

    on(seek, 'pointerdown', (e) => {
      if (e.button) return;
      dragging = true;
      wasPlaying = !S.video.paused;
      seek.classList.add('drag');
      cap(seek, e.pointerId);
      paint(ratio(e));
      showControls();
    });
    on(seek, 'pointermove', (e) => { if (dragging) paint(ratio(e)); });
    on(seek, 'pointerup', (e) => {
      if (!dragging) return;
      dragging = false;
      S.seeking = false;
      seek.classList.remove('drag');
      const d = S.video.duration || 0;
      S.video.currentTime = ratio(e) * d;
      S.timeText = '';
      if (wasPlaying) S.video.play().catch(() => {});
      sync();
      scheduleHide();
    });
    on(seek, 'pointercancel', () => {
      dragging = false;
      S.seeking = false;
      seek.classList.remove('drag');
      S.timeText = '';
      sync();
    });
  }

  /* ---------- gestures ---------- */

  function bindGestures() {
    const sf = S.ui.surface;
    const on = (t, ty, fn, o) => t.addEventListener(ty, fn, Object.assign({ signal: S.ac.signal }, o || {}));

    on(sf, 'pointerdown', (e) => {
      if (e.button) return;
      const v = S.video;
      let d;
      if (S.mini) {
        const r = S.miniRect;
        d = { id: e.pointerId, x0: e.clientX, y0: e.clientY, x: e.clientX, y: e.clientY,
              t0: Date.now(), mini: true, moved: false, l: r.left, t: r.top };
      } else {
        d = { id: e.pointerId, x0: e.clientX, y0: e.clientY, x: e.clientX, y: e.clientY,
              t0: Date.now(), mode: '', moved: false,
              startT: v.currentTime, startV: v.volume, startB: S.brightness };
      }
      S.g = d;
      cap(sf, e.pointerId);
      clearTimeout(S.hideTimer);
      d.wasControls = S.controls;
      if (!S.mini) {
        clearTimeout(S.holdTimer);
        S.holdTimer = setTimeout(() => {
          if (!S.g || S.g.moved || S.g.mode || S.mini) return;
          S.held = true;
          S.savedRate = v.playbackRate;
          v.playbackRate = 2;
          showHud('2x  faster', 0);
        }, cfg.longPress);
      }
    });

    on(sf, 'pointermove', (e) => {
      const g = S.g;
      if (!g || g.id !== e.pointerId) return;
      const v = S.video;
      const dx = e.clientX - g.x0, dy = e.clientY - g.y0;
      g.x = e.clientX; g.y = e.clientY;

      if (S.mini) {
        if (!g.moved && Math.hypot(dx, dy) < 6) return;
        g.moved = true;
        const r = S.miniRect;
        const w = r.w, h = r.h;
        S.miniRect = {
          w, h,
          left: clamp(g.l + dx, 0, innerWidth - w),
          top: clamp(g.t + dy, 0, innerHeight - h)
        };
        applyMini();
        return;
      }

      if (!g.moved && Math.hypot(dx, dy) < 10) return;
      g.moved = true;
      clearTimeout(S.holdTimer);
      showControls();
      if (!g.mode) {
        if (Math.abs(dx) > Math.abs(dy)) g.mode = 'seek';
        else {
          const f = g.x0 / Math.max(1, innerWidth);
          g.mode = f < 0.25 ? 'light' : f > 0.75 ? 'vol' : 'none';
        }
      }
      if (g.mode === 'seek') {
        const span = clamp(v.duration || 60, 15, cfg.seekSpan);
        const t = clamp(g.startT + (dx / Math.max(1, innerWidth)) * span, 0, v.duration || 0);
        S.seekPreview = t;
        previewSeek(t);
        showControls();
      } else if (g.mode === 'light') {
        S.brightness = clamp(g.startB - dy / Math.max(1, innerHeight), 0.15, 1);
        v.style.setProperty('filter', 'brightness(' + S.brightness.toFixed(3) + ')', 'important');
        showHud('Brightness ' + Math.round(S.brightness * 100) + '%', 0);
      } else if (g.mode === 'vol') {
        v.volume = clamp(g.startV - dy / Math.max(1, innerHeight), 0, 1);
        v.muted = false;
        showHud('Volume ' + Math.round(v.volume * 100) + '%', 0);
      }
    });

    const finish = (e) => {
      const g = S.g;
      if (!g || g.id !== e.pointerId) return;
      clearTimeout(S.holdTimer);
      const v = S.video;
      const tap = !g.moved && Date.now() - g.t0 < 400;
      S.g = null;

      if (S.held) {
        v.playbackRate = S.savedRate || 1;
        S.held = false;
        hideHud();
        return;
      }

      if (g.mini) {
        if (tap) handleTap(g);
        return;
      }

      if (g.mode === 'seek') {
        if (S.seekPreview >= 0) v.currentTime = S.seekPreview;
        S.seekPreview = -1;
        S.seeking = false;
        S.timeText = '';
        hideHud();
        sync();
        scheduleHide();
      } else if (g.mode) {
        hideHud();
        scheduleHide();
      } else if (tap) {
        handleTap(g);
      }
    };

    on(sf, 'pointerup', finish);
    on(sf, 'pointercancel', (e) => {
      const g = S.g;
      if (g && g.id === e.pointerId) {
        S.g = null;
        S.seeking = false;
        clearTimeout(S.holdTimer);
        if (S.held) { S.video.playbackRate = S.savedRate || 1; S.held = false; }
        hideHud();
      }
    });
  }

  function handleTap(g) {
    const now = Date.now();
    const v = S.video;
    if (now - S.lastTap < cfg.dblTap) {
      clearTimeout(S.tapTimer);
      S.lastTap = 0;
      if (S.mini) { setMini(false); return; }
      const side = g.x0 < innerWidth / 2 ? -1 : 1;
      v.currentTime = clamp(v.currentTime + side * 10, 0, (v.duration || 1e9) - 0.05);
      showRipple(side < 0 ? 'left' : 'right');
      sync();
      return;
    }
    S.lastTap = now;
    clearTimeout(S.tapTimer);
    S.tapTimer = setTimeout(() => {
      if (S.mini) { if (v.paused) v.play().catch(() => {}); else v.pause(); return; }
      if (g.wasControls) hideControls(); else showControls();
    }, cfg.dblTap);
  }

  /* ---------- keyboard ---------- */

  function bindKeys() {
    const on = (t, ty, fn, o) => t.addEventListener(ty, fn, Object.assign({ signal: S.ac.signal }, o || {}));
    on(window, 'keydown', (e) => {
      const v = S.video;
      if (!v) return;
      if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
      const k = e.key;
      let used = true;
      if (k === ' ' || k === 'k') { if (v.paused) v.play().catch(() => {}); else v.pause(); }
      else if (k === 'ArrowLeft') seekBy(-5);
      else if (k === 'ArrowRight') seekBy(5);
      else if (k === 'j') seekBy(-10);
      else if (k === 'l') seekBy(10);
      else if (k === 'm') v.muted = !v.muted;
      else if (k === 'f') toggleFs();
      else if (k === 'Escape') { if (!document.fullscreenElement) close(); else used = false; }
      else used = false;
      if (used) { e.preventDefault(); e.stopPropagation(); }
    }, { capture: true });
  }

  /* ---------- open / close ---------- */

  function savePage() {
    const de = document.documentElement, b = document.body;
    store(de); store(b);
    de.style.setProperty('overflow', 'hidden', 'important');
    b.style.setProperty('overflow', 'hidden', 'important');
    b.style.setProperty('overscroll-behavior', 'none', 'important');

    const st = document.createElement('style');
    st.id = 'fp-css';
    st.textContent = 'video::-webkit-media-controls,video::-webkit-media-controls-enclosure,' +
      'video::-webkit-media-controls-panel,video::-webkit-media-controls-overlay-play-button{' +
      'display:none!important;visibility:hidden!important}';
    (document.head || de).appendChild(st);
    S.hideCss = st;
  }

  function applyAncestors() {
    const de = document.documentElement, b = document.body;
    let a = S.video.parentElement;
    while (a) {
      store(a);
      const cs = getComputedStyle(a);
      if (cs.position === 'static') a.style.setProperty('position', 'relative', 'important');
      a.style.setProperty('z-index', String(ZMAX - 20), 'important');
      a.style.setProperty('transform', 'none', 'important');
      a.style.setProperty('translate', 'none', 'important');
      a.style.setProperty('scale', 'none', 'important');
      a.style.setProperty('rotate', 'none', 'important');
      a.style.setProperty('filter', 'none', 'important');
      a.style.setProperty('perspective', 'none', 'important');
      a.style.setProperty('clip-path', 'none', 'important');
      a.style.setProperty('mask', 'none', 'important');
      a.style.setProperty('-webkit-mask', 'none', 'important');
      a.style.setProperty('contain', 'none', 'important');
      a.style.setProperty('will-change', 'auto', 'important');
      a.style.setProperty('opacity', '1', 'important');
      a.style.setProperty('isolation', 'auto', 'important');
      a.style.setProperty('mix-blend-mode', 'normal', 'important');
      a.style.setProperty('backdrop-filter', 'none', 'important');
      if (a === de || a === b) {
        a.style.setProperty('overflow', 'hidden', 'important');
      } else {
        a.style.setProperty('overflow', 'visible', 'important');
      }
      if (a === de) break;
      a = a.parentElement;
    }
  }

  function open(video) {
    let v = video || pickVideo();
    if (!v) return false;
    if (S.active) {
      if (S.video === v) return true;
      close();
      v = video || pickVideo();
      if (!v) return false;
    }

    S.video = v;
    S.brightness = 1;
    S.rotated = false;
    S.mini = false;
    S.controls = true;
    S.seekPreview = -1;
    S.seeking = false;
    S.sheetOpen = false;
    S.flashUntil = 0;
    S.centerShown = null;
    S.pausedIcon = null;
    S.timeText = '';
    S.durText = '';
    S.bufWidth = '';
    S.fileWidth = '';
    S.ac = new AbortController();

    store(v);
    savePage();
    applyAncestors();
    buildUI();
    bindMedia();
    sync();
    syncBuffered();
    syncRate();
    syncLoop();
    syncRot();
    syncCC();
    /* YouTube puts the clip name in <meta name=title>; document.title carries a
       " - YouTube" suffix and, with pending notifications, a "(3) " prefix. */
    const metaTitle = document.querySelector('meta[name="title"]');
    S.ui.title.textContent = ((metaTitle && metaTitle.content) || document.title || '').trim() ||
      v.currentSrc.split('/').pop() || 'Video';
    S.active = true;
    chip(false);
    showControls();
    if (v.paused) v.play().catch(() => {});
    tick();
    return true;
  }

  function close() {
    if (!S.active) return;
    S.active = false;
    cancelAnimationFrame(S.raf);
    clearTimeout(S.hideTimer);
    clearTimeout(S.tapTimer);
    clearTimeout(S.holdTimer);
    clearTimeout(S.hudTimer);
    try { S.ac.abort(); } catch (_) {}
    if (document.fullscreenElement) { document.exitFullscreen().catch(() => {}); }
    try { screen.orientation && screen.orientation.unlock && screen.orientation.unlock(); } catch (_) {}
    if (S.host && S.host.parentNode) S.host.parentNode.removeChild(S.host);
    if (S.hideCss && S.hideCss.parentNode) S.hideCss.parentNode.removeChild(S.hideCss);
    S.host = null; S.root = null; S.hideCss = null; S.ui = {};
    restore();
    S.video = null;
    S.mini = false;
    S.rotated = false;
    S.brightness = 1;
    S.controls = true;
    S.miniRect = null;
    S.g = null;
    S.seeking = false;
    S.sheetOpen = false;
    S.flashUntil = 0;
    S.centerShown = null;
    chip(!!pickVideo());
  }

  function toggle() {
    if (S.active) close(); else open();
  }

  function tick() {
    if (!S.active) return;
    if (!S.video || !S.video.isConnected) { close(); return; }
    sync();
    syncBuffered();
    S.raf = requestAnimationFrame(tick);
  }

  /* ---------- detection chip ---------- */

  function buildChip() {
    const host = document.createElement('div');
    host.id = 'fp-chip';
    host.style.cssText = 'all:initial;position:fixed;z-index:' + ZMAX +
      ';right:16px;bottom:calc(18px + env(safe-area-inset-bottom));display:block;';
    const root = host.attachShadow({ mode: 'open' });
    const st = document.createElement('style');
    st.textContent = `
      button{-webkit-appearance:none;appearance:none;border:0;width:54px;height:54px;border-radius:50%;
        background:linear-gradient(135deg,#ff5a3c,#ff2d55);color:#fff;display:flex;align-items:center;
        justify-content:center;cursor:pointer;box-shadow:0 6px 20px #0007,0 0 0 1px #fff2 inset;
        transition:transform .12s}
      button:active{transform:scale(.92)}
      svg{width:24px;height:24px;fill:#fff;margin-left:2px}
    `;
    const b = document.createElement('button');
    b.setAttribute('aria-label', 'Open video player');
    b.append(SVG.play());
    b.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); open(); });
    root.append(st, b);
    (document.body || document.documentElement).appendChild(host);
    S.chipHost = host;
  }

  function chip(show) {
    if (!show) {
      if (S.chipHost) S.chipHost.style.display = 'none';
      return;
    }
    if (!S.chipHost || !S.chipHost.isConnected) buildChip();
    S.chipHost.style.display = 'block';
  }

  function scan() {
    if (!S.active) chip(!!pickVideo());
  }

  /* ---------- init ---------- */

  let scanQueued = false;
  function queueScan() {
    if (scanQueued) return;
    scanQueued = true;
    requestAnimationFrame(() => { scanQueued = false; scan(); });
  }

  document.addEventListener('play', (e) => {
    const t = e.target;
    if (!t || t.tagName !== 'VIDEO' || t.closest('#fp-host')) return;
    if (S.active) return;
    if (cfg.autoOpen) open(t); else chip(true);
  }, true);

  document.addEventListener('pointerdown', (e) => {
    const t = e.target;
    if (!t || t.tagName !== 'VIDEO' || S.active) return;
    clearTimeout(S.holdTimer);
    S.holdTimer = setTimeout(() => open(t), cfg.longPress);
  }, { capture: true, passive: true });

  for (const ty of ['pointerup', 'pointercancel', 'pointermove', 'scroll', 'dragstart']) {
    document.addEventListener(ty, () => {
      if (S.g) return;
      clearTimeout(S.holdTimer);
    }, { capture: true, passive: true });
  }

  new MutationObserver(queueScan).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['src', 'style', 'class']
  });

  window.addEventListener('popstate', queueScan);
  window.__flashPlayer = {
    version: VERSION,
    open,
    close,
    toggle,
    chip,
    pickVideo,
    setAutoOpen(b) { cfg.autoOpen = !!b; if (b) scan(); return cfg.autoOpen; },
    get autoOpen() { return cfg.autoOpen; },
    config: cfg,
    debug() {
      return { active: S.active, mini: S.mini, controls: S.controls, held: S.held,
        g: S.g && { id: S.g.id, mode: S.g.mode, moved: S.g.moved, mini: !!S.g.mini },
        holdTimer: S.holdTimer, rate: S.video && S.video.playbackRate,
        hostClass: S.host && S.host.className, brightness: S.brightness };
    }
  };

  scan();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan, { once: true });
  }
  console.log('[flashplayer] ' + VERSION + ' ready — __flashPlayer.open()');
})();
