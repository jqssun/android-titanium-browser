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
- Settings bottom sheet (`#212121`, grab handle, 12 px top radius): playback speed
  chips 0.25–2x, Loop video, Rotate screen; each row shows its current value.
- Gestures: tap toggles controls; double-tap +/-10 s with a circular ripple on that
  side; long-press 2x until lift; horizontal drag seeks (90 s span) with the same
  time bubble; left-half vertical drag is brightness, right-half is volume.
- CC toggles the video's subtitle/caption tracks and turns red when active.
- Mini: rounded floating player with expand/close, draggable, tap to play/pause,
  double-tap to expand.
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
inheriting the button's `currentColor` and turning the ring into a blob.

## Known limits (v1)

- Main frame only. Measured: a video in a same-origin iframe is invisible to the
  top document too, so no chip appears (`pickVideo()` is null). Cross-origin embeds
  behave the same. Needs a `RenderFrameObserver` in `chrome/renderer` (v2).
- Fullscreen and orientation lock need a real user activation; the in-app test
  browser refuses `requestFullscreen()` even from a trusted key press, so only the
  CSS full-viewport fallback was exercised (already pixel-identical). A real tap on
  the fullscreen button in the fork is the activation path to check on device.
- Page-specific overlays that are not inside the video's ancestor chain and sit at a
  higher stacking level are not hidden; the ancestor chain is raised to z-index
  2147483627 and the video to 2147483637.
