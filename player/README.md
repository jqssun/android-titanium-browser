# Flash Player (dev build)

In-page video player with the control overlay of YouTube/ReVanced: it runs **inside
the page**: a chip appears when a video exists, and tapping it re-parents nothing — the
video element is restyled to fill the screen under a Shadow-DOM control layer, with the
page's own player UI covered.

Not shipped yet. This file is the source that will be baked into the browser as a
Java-injected script; nothing here is in the APK.

## Try it

Desktop Edge/Chrome (same Blink engine as the fork), on any site with a video:

1. F12 -> Sources -> Snippets -> New snippet.
2. Paste `flashplayer.js`, press Ctrl+Enter.
3. A round chip appears bottom-right (or call `__flashPlayer.setAutoOpen(true)` first).

Snippets run through the debugger, so this works even on sites with a strict CSP or
Trusted Types (YouTube). Loading the file with a `<script src>` from a remote host does
not: `script-src` rejects the host and Trusted Types rejects string sinks.

Console API: `__flashPlayer.open(video?)`, `.close()`, `.toggle()`, `.pickVideo()`,
`.setAutoOpen(b)`, `.debug()`.

A local test page with a generated 2-minute WebM lives outside the repo:
`%TEMP%\fp-test\` (`python serve.py 8765`, then http://127.0.0.1:8765/).

## Controls

Chrome follows the stock YouTube Android player (ReVanced) layout:

- Top: back chevron, title, minimize. Bare white 24 px icons in 48 px hit areas on a
  top gradient.
- Bottom: elapsed time — red 3 px progress with buffered track and a 12 px knob —
  total time. Dragging widens the track, enlarges the knob and shows a time bubble.
- Actions row: play/pause, -10 s, +10 s double chevrons (left); CC, settings,
  fullscreen (right). The center play/pause button appears only while paused.
- Fullscreen follows the video's shape: a real screen-orientation lock to landscape
  for a wide video and to portrait for a tall one. Where the page cannot enter real
  fullscreen, the orientation cannot be changed either, so a wide video on a portrait
  screen is stood up with the CSS rotation instead.
- Settings bottom sheet (`#212121`, grab handle, 12 px top radius): playback speed
  chips 0.25–2x, Loop video, Rotate screen; each row shows its current value.
- Gestures: tap toggles controls; double-tap +/-10 s with a circular ripple on that
  side; long-press 2x until lift; horizontal drag seeks (90 s span) with the target
  time in the centre HUD; vertical drag on the left 25% is brightness, on the right
  25% is volume, the middle band does neither.
- CC toggles the video's subtitle/caption tracks and turns red when active.
- Mini: a `min(380, 46% of the viewport)` wide, 16:9 floating rectangle at 58% height
  (square corners — the video is forced to `border-radius: 0`), draggable, tap to
  play/pause, double-tap to expand.
- Keys (desktop): space/k, arrows, j/l, m, f, esc.

## Verified 2026-11-04 (YouTube-style chrome)

Environment: bundled Chromium, viewport 539x448, generated VP8 WebM (120 s), page whose
player container has `transform` + `overflow:hidden` and its own overlay UI.

- layout: top bar 72 px (back/title/minimize), bottom 98 px (time | 3 px track | time,
  then the 46 px actions row); center play 104 px at the viewport center
- forward 60 -> 70 s with the right ripple; double-tap left 70 -> 60 s with the left
  ripple; time label tracks both (1:10 / 1:00)
- scrub: pointerdown at 50% shows `.drag` + bubble `1:00`, move to 75% -> `1:30`,
  release -> `currentTime` 90.0 s
- gestures: brightness drag -> `brightness(0.777)`, HUD `Brightness 78%`; volume drag
  -> 84%; long-press 700 ms -> rate 2 with HUD `2x faster`, restores the 1.5x setting
- gesture zones (539x449, 40 px vertical drag): x=10% -> `brightness(0.911)`, x=50%
  -> nothing changes, x=90% -> `volume` 0.911; horizontal drags seek from any x
- fullscreen orientation (fallback path — this browser refuses real fullscreen): wide
  640x360 video on a 539x449 viewport -> no rotation, video 539x449; the same video on
  a 412x915 viewport -> `translate(100vw, 0px) rotate(90deg)` with the Rotate row `On`,
  second click back to `none`; tall 180x320 video -> no rotation, `object-fit: contain`
- settings sheet: 8 speed chips, `1x` highlighted; picking `1.5x` sets rate 1.5, closes
  the sheet and updates the row value; CC with no tracks -> HUD `No captions`
- auto-hide: playing, controls visible at 0.5 s; top/bottom hidden at 4.1 s; center
  stays hidden while playing and appears with the Play icon on pause; tap restores
- sheet guard: open for 4 s while playing keeps the bars up; closing it re-arms the
  3.5 s hide; scrim tap closes; speed chips wrap to two rows (5 + 3) at 412 px
- mini 248x140 at (275,260), dragged to (175,180), expand returns to 539x448;
  double-tap in mini expands too
- rotate: `translate(100vw,0) rotate(90deg)`, bounding box 0,0 539x448, controls
  upright; toggling Off restores the full-viewport layout
- back chevron closes; restore leaves the video at 476x268 (24,72), page transform
  identity, body overflow visible, host and injected CSS removed, chip back
- seek while playing: preview stays at 50% for 250 ms of `timeupdate` ticks, then
  release jumps to 60.0 s and playback continues
- CC with a real WebVTT track: on -> `mode=showing`, icon `rgb(255,0,0)`,
  `aria-pressed=true`, HUD `Captions on`; off -> `disabled`, white icon
- keyboard (trusted input): Space resumes, ArrowRight sought 5 s, `m` toggles mute;
  `f` is refused by the in-app browser (no fullscreen), layout stays the CSS one;
  Escape closes and restores
- ended: at 2:00 the player pauses, shows the bars and the center Play icon
- multi-video: `pickVideo()` follows the playing video; only it is restyled and its
  inline style is restored verbatim; panel open/close x3 leaves the page style
  attributes byte-identical, one host and no injected CSS remains
- dynamic chip: removing every video hides the chip, adding one back shows it;
  removing the open video exits the player cleanly
- portrait 412x915: video fills the viewport, top 72, bottom 98 at y 817, seek
  308 px, center at (154,406), sheet 412x264 with wrapped chips
- hostile ancestors (`filter`, `contain:paint`, `clip-path`, `mask-image`,
  `opacity`, `perspective`, `isolation`, `backdrop-filter`): video fills 539x449,
  every ancestor property restored exactly on close
- real site (w3schools HTML5 video page, injected as the APK will): H.264 MP4 plays
  in the player, site chrome covered, close restores the page's own controls and
  scrolling; the only console errors are the site's own analytics CORS failures

Bugs found and fixed during this pass: rotate centring (translate order), pointer
capture on synthetic pointers, per-frame icon/DOM writes, tap-vs-controls state,
seek-preview being overwritten by `timeupdate` while dragging, seek glyph `fill`
inheriting the button's `currentColor` and turning the ring into a blob, and markup
sinks (icons were built with `innerHTML`/`DOMParser`, which YouTube's
`require-trusted-types-for 'script'` policy rejects; they are now `createElementNS`
node factories).

## Verified 2026-11-04 (YouTube watch page)

Environment: bundled Chromium, 539x449 viewport, `https://www.youtube.com/watch?v=jNQXAC9IVRw`
(19.02 s VP9/AAC over MSE), script injected into the page context — a local file served
with `Access-Control-Allow-Origin` and run through `eval` under a
`trustedTypes.createPolicy` policy. YouTube's CSP does allow `unsafe-eval`, but only a
TrustedScript gets through; without CORS the fetch itself is refused.

- load: chip appears over YouTube's page; `open()` restyles the video inside
  `html5-video-container` to 0,0 539x449 (`position: fixed`, `object-fit: contain`),
  YouTube's entire chrome covered; top bar 72 px, bottom 98 px
- title `Me at the zoo` read from `meta[name=title]` (`document.title` would read
  "(3) Me at the zoo - YouTube")
- MSE stream labels: total `0:19`, elapsed tracks playback (`0:05`, `0:07`)
- seek: drag from 10% to 60% -> bubble `0:11`, fill 60%, release -> `currentTime`
  11.41 s of 19.02, playback continues
- settings sheet 440x186 at y 263: `1.5x` -> `playbackRate` 1.5 with the chip
  re-highlighted and the row value updated; Loop video -> `video.loop` true, row `On`;
  Rotate -> `translate(100vw, 0px) rotate(90deg)`, 539x449 footprint; scrim tap closes
- CC: YouTube keeps captions outside `video.textTracks` (0 tracks) -> HUD `No captions`
- mini 248x140 at (275,260), unchanged after 1.5 s; dragged -120/-60 -> (155,200);
  expand restores 0,0 539x449
- double-tap right half: 3.87 -> 14.14 s with the right ripple
- close: host and injected CSS removed, chip back, video inline style back to YouTube's
  own `width: 373px; height: 280px; left: 75px; top: 0px`, container style attribute
  null, YouTube controls visible again, playback continues
- console: no player errors; only YouTube's own ad/DNS failures, a report-only
  `img-src` violation from its own player, and the expected "requestFullscreen ...
  user gesture" warning from the scripted pass

## Verified 2026-11-04 (watch page of a site with its own JS player)

Environment: bundled Chromium, 676x449 viewport, a `view_video.php?viewkey=…` watch page
whose player is a page-side JS object (`window.MGP.players['playerDiv_…']`), not
`<video controls>`. The script was injected with a plain `fetch` of the local file plus
`(0,eval)(code)`: this page has no Trusted Types policy and no CSP, so unlike YouTube no
policy object was needed (43,691 bytes in, `[flashplayer] 0.1.0 ready` logged).

- the page starts with 6 `<video>` elements: 4 zero-size hover previews, one hidden
  `player-html5`, and the live `mgp_videoElement` (656x369) — every one of them
  `preload=none` with an empty `<source>`, and an age-confirmation modal on top. All of
  that is still fine: `pickVideo()` returns the live element and the chip shows at
  (454,377) 54x54
- pre-roll runs through the **same** element: attached while a 30.04 s creative was
  playing (`readyState` 4), and when the site swapped in the content stream the labels
  followed to `11:17` (677.77 s) with no reopen
- layout at open: host fixed 0,0 676x449, top 72, bottom 98 at y 351, seek track
  560x3 at y 386 (buf 93, fill 43, knob 12), actions row 46 px of six 48x46 buttons at
  y 399, title 386x20 at (58,18); every on-screen control of the site's own player
  hit-tests to `#fp-host`, and the video went back to 0,133 656x369 on close
- scrub: down at 30% -> bubble `3:23`, move to 75% -> `8:28`, knob 12 -> 16 px, release
  -> `currentTime` 508.3 of 677.77 = exactly 75%
- double-tap: right half +10.2 s, left half -9.7 s, ripple at 0.92 opacity on that side
- zones (449 px high viewport): 12% down 120 px -> `brightness(0.733)`, HUD
  `Brightness 73%`; 88% down 135 px from 0.8 -> HUD `Volume 50%`, `volume` 0.5; 50%
  up 120 px -> neither the filter nor the volume moved
- surface drag +150 px horizontally -> HUD and elapsed label both `9:36 / 11:17`
- long-press 750 ms -> `playbackRate` 2 with HUD `2x faster`, back to the 1.5x setting
  on lift
- settings sheet at 150 ms: 440x186 centred at x 118, grab 32x4, 8 chips with `1x`
  active; `1.50x` -> rate 1.5, sheet closed, row reads `1.5x`
- mini: 311x175 at (349,260) = `min(380, 46% vw)` x 16:9, expand -> 0,0 676x449
- CC: this site keeps captions out of `video.textTracks` too (0 tracks) -> HUD
  `No captions`, icon white, `aria-pressed=false`
- rotate: row `Off` -> `On`, video `translate(100vw, 0px) rotate(90deg)` (intrinsic
  1280x720) with a 676x449 footprint and upright bars
- fullscreen press with a 1280x720 stream in a landscape viewport: real fullscreen
  refused, and correctly no CSS rotation was substituted (`transform: none`)
- close/restore: 0 hosts left, chip back at (591,362), injected CSS gone, the video sits
  inside the site's container again with **no** style attribute at all, and a single
  open/close leaves the video plus all 8 ancestors with byte-identical style attributes;
  the site's player carries on playing
- console for the whole pass: our ready log and the expected `requestFullscreen ...
  user gesture` warning — no player errors

## Known limits (v1)

- Main frame only. Measured: a video in a same-origin iframe is invisible to the
  top document too, so no chip appears (`pickVideo()` is null). Cross-origin embeds
  behave the same. Needs a `RenderFrameObserver` in `chrome/renderer` (v2).
- Fullscreen and orientation lock need a real user activation; the in-app test
  browser refuses `requestFullscreen()` even from a trusted key press, so only the
  CSS fallback was exercised (already pixel-identical). The lock target is chosen by
  the video's shape (`portrait` when taller than wide, else `landscape`), but the lock
  call itself can only be checked with a real tap in the fork on device.
- Page-specific overlays that are not inside the video's ancestor chain and sit at a
  higher stacking level are not hidden; the ancestor chain is raised to z-index
  2147483627 and the video to 2147483637.
- The fullscreen button recomputes the rotation from the video's shape, so pressing it
  drops an explicit `Rotate screen = On` (measured: rotate On -> fullscreen press ->
  row back to Off on a landscape stream in a landscape viewport). Unresolved design
  question, not a crash.
- Loading the script into a CSP/Trusted-Types site from a remote URL is refused by the
  page (measured on YouTube: `script-src` blocks the host, `eval` needs a TrustedScript).
  The player itself no longer uses markup sinks, and the APK route
  (`webContents.evaluateJavaScript`) is browser-initiated, so neither policy applies to
  it; on a desktop page use the Snippets panel.
