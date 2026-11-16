# Flash Player

In-page video player with the control overlay of YouTube/ReVanced: it runs **inside
the page**: a chip appears when a video exists, and tapping it re-parents nothing — the
video element is restyled to fill the screen under a Shadow-DOM control layer, with the
page's own player UI covered.

Shipped as a bundled extension: `extension/manifest.json` plus the packed
`dist/flash-player.crx`, registered by the `# player:` block in `../patch.sh`. See
[Shipping it](#shipping-it) for the mechanism, the id and what the build verifies.

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

## Shipping it

The script is not compiled into Java and not fetched at runtime. It is packaged as a
Chromium extension and installed by the browser itself at startup, through the same
bundling path the Titanium Extension uses:

- `extension/manifest.json` is the template. Manifest V3, one `content_scripts` entry
  matching `http://*/*` and `https://*/*` with `all_frames: true`, `world: "MAIN"` and
  `run_at: "document_idle"`, and a `key` that pins the extension id.
- `dist/flash-player.crx` is the packed artifact, produced by `./repack.sh`.
- `../patch.sh`'s `# player:` block registers that crx with `../extensions/bundle.py`
  (the script the Titanium Extension is fetched with) from a local `file://` URL, which
  derives the id and version from the crx, records them in `bundled.json`, and lists the
  crx as an `android_assets` entry. The build stages it into the APK, and
  `StageBundledExtensions` turns it into an external-pref install on first run.

Why a content script rather than a Java-injected string: `world: "MAIN"` is the page's
own world, which is exactly what the snippet route above measures, a manifest content
script is not subject to the page's `script-src`, `all_frames` covers players that live
in an iframe, and no upstream Java file needs a new anchor — `TabImpl.java` at this
version has no page-load hook to hang an injection on, so the Java route would have
meant guessing at a second integration point.

Measured on Chrome 157.0.8103.51 with the staged folder loaded through CDP
`Extensions.loadUnpacked`: the returned id is `ofmgkoigejimknamjdjgakdelpmhnjhf`, the
same value derived independently from the signing key and from the manifest `key`, and
on a two-frame HTTP page `window.__flashPlayer` (version `0.1.0`) was live in the main
world of **both** frames. The packed crx was then confirmed to contain exactly
`flashplayer.js` and `manifest.json`, byte-identical script, manifest identical to the
template apart from `version`.

### Repacking

```sh
./repack.sh            # writes dist/flash-player.crx
```

The signing key is deliberately **not** in this repository: it lives beside the release
keystore at `/f/flash-player-extension-key.pem` (override with `FLASH_PLAYER_EXT_KEY`),
and `player/extension/manifest.json` carries only its public half. Back it up with the
keystore. If it is lost, generate a new one and replace the `key` value with the new
SPKI base64 — the extension then gets a new id, and the build follows automatically
because `bundle.py` reads the id from the crx rather than from anything hardcoded.

`repack.sh` stamps `version` as `1.<seconds-since-epoch>`, so every repack is strictly
higher than the last and Chromium reinstalls the extension instead of keeping the copy
it already installed. Packing a repack is required whenever `flashplayer.js` or the
manifest template changes; the build refuses to ship otherwise:

```
player: dist/flash-player.crx is stale against player/; run player/repack.sh
```

Three failure modes were exercised against the block in a scratch tree, each aborting
with exit 1: script edited without repacking, manifest template edited without
repacking, and (by construction, since the manifest `key` is compared with the key
recorded in the crx header) a template whose key no longer matches the signing key.

### What this means on a device

- The player shows up as a normal row in `chrome://extensions` ("Flash Player") and can
  be turned off there.
- A chip appears in **every** frame that has a playing video larger than 4000 px, so a
  video inside an ad or embed iframe gets its own chip. Narrowing that to the top frame
  is a one-word manifest change (`all_frames: false`), not a code change.
- An incognito tab only runs it if the extension is allowed in incognito, which is the
  ordinary per-extension switch; not yet checked on an APK build.

## Controls

Chrome follows the stock YouTube Android player (ReVanced) layout:

- Top: back chevron, title, minimize. Bare white 24 px icons in 48 px hit areas on a
  top gradient.
- Bottom: elapsed time — red 3 px progress with buffered track and a 12 px knob —
  total time. Dragging widens the track, enlarges the knob and shows a time bubble.
  Coloured segment bands sit between the buffered bar and the red progress, so the
  played part stays red and the unplayed part shows the segments. They come from the
  video's own `kind="chapters"` track, or from the host app through
  `__flashPlayer.setSegments([{start, end, label, color}])`.
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
- Mini: a `min(380, 46% of the viewport)` wide, 16:9 floating card with 10 px rounded
  corners (the video gets the radius inline, the overlay layer is clipped by a
  document-level `#fp-host.mini` rule, which is the only thing that can beat the host's
  inline `all:initial`), draggable. Its only controls are the expand (fullscreen) glyph
  dead-centre and the cross at the top right, both plain icons with no disc behind them.
  A tap shows them and they auto-hide again after the same 3.5 s; a drag moves the card
  and re-arms the timer; double-tap expands. There is no play/pause in mini — pausing
  means expanding first.
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
- mini corners (local harness, 675x449 viewport): the video gets `border-radius: 10px`
  inline and the host is clipped to the same arc (`border-radius: 10px`,
  `overflow: hidden`) — host and video boxes coincide at
  348,260 311x175; dragged to (228,160), expand gives 0,0 675x449 with the clip released
  back to `0px`/`visible`, close leaves no `#fp-host` and no `#fp-css` and no `style`
  attribute on the video at all
- mini controls: expand box 486,330 36x36 — centre (504,348) is the card centre, cross at
  621,262 with its right edge 2 px inside the card, both `background: rgba(0,0,0,0)`;
  layer opacity 0 with class `off` 4.2 s after entering mini, 0.98 after a single tap
  (which left `paused` false, i.e. tap no longer plays/pauses), 0 again 4.2 s later; a
  drag to 268,220 left them hidden; double-tap 90 ms apart expanded to 675x449 and the
  cross closed the player cleanly
- track segments (local harness, 517x448 viewport, 120 s clip with a 4-cue
  `kind="chapters"` WebVTT at 0/20/55/90 s): first open paints 4 bands 0.28 s after
  `open()`; layer order inside the track is `buf, segs, fil, knob, tip`, so the red
  progress covers the played part of every band; on a 401 px track the bands are
  `0% +16.667%` (0,67 px), `16.667% +29.167%` (67,117), `45.833% +29.167%` (184,117),
  `75% +25%` (301,100), all 3 px tall — the cue boundaries divided by the 120 s duration
  exactly — in `rgb(142,36,170) rgb(0,137,123) rgb(244,81,30) rgb(57,73,171)`
- a chapters track is only parsed by Chrome once it is `showing`, so `wakeChapters()`
  raises the mode for the read and `close()` puts it back: `disabled` -> `showing` while
  open -> `disabled` after close, measured; reopening re-detects (4 bands again)
- `setSegments()` with 5 entries keeps the 3 valid ones (a reversed range and a
  non-numeric range are dropped), honours an explicit `#e91e63` and fills the rest from
  the palette (`0%+25%`, `50%+12.5%`, `66.667%+16.667%`), and overrides the auto-detected
  chapters without the retry loop stealing them back
- with segments on the track the rest of the chrome is unchanged: scrub 25% -> 65% shows
  `.drag`, bubble `1:18`, fill 65%, release lands on 78.19 s of a wanted 78 s (playback
  keeps running) and the 4 bands survive; CC still reports `No captions` although the
  chapters track sits at `showing`; mini hides the bottom layer entirely (`display: none`)
  so no bands show in the card; 4 open/close cycles (2 of them through mini) leave zero
  `style` attributes on html, body and both page containers, 6 attributes on the video,
  no `#fp-host`, no `#fp-css`, and the only console line is our own ready log
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

From the segment work: `for (const t of video.textTracks)` throws — `TextTrackList` has
no `Symbol.iterator`, and the exception inside `open()` left a half-built player — so
every walk is indexed; cues never appear while the track is `disabled` and its `load`
event can fire before a listener attaches, so detection polls instead of listening;
`toggleCC()` counted track *number* and then treated a chapters track as captions;
and `restore()` used to write an empty `style=""` back onto nodes that had none, which
Blink re-serialises after `removeAttribute` while the overlay's inline mutations are
still flushing — it now verifies the node is clean, so a page never keeps an attribute
we created.

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

## Verified 2026-11-04 (xnxx: HLS.js `blob:` stream plus a 0x0 decoy `<video>`)

Environment: bundled Chromium, **540x448** viewport, a `/video-…/<id>/…` watch page whose
stream is fed by HLS.js into a `blob:` src. No CSP `meta`, but the **response header**
carries one: `default-src 'self' data: 'unsafe-inline' 'unsafe-eval' blob: …`, so
`fetch('http://127.0.0.1:8765/flashplayer.js')` was refused — `connect-src` falls back to
`default-src`, and the console logged both the directive error and
`Refused to connect because it violates the document's Content Security Policy`.
`eval` itself is allowed, so delivery is the only problem: the source was handed to the
page as a **text payload read in-page** (48,515 chars in, all 11
`__flashPlayer` keys, `[flashplayer] 0.1.0 ready`). This is exactly the APK path — the
injector supplies the source, it never fetches it.

- the page has **2** `<video>` elements: index 0 is a 0x0 ad node (`duration` 0.63,
  `readyState` 4, `paused`), index 1 the live stream (524x427, 689.29 s, `blob:`).
  `pickVideo()` returned index 1. Any probe that uses `document.querySelector('video')`
  measures the ad node instead — identity has to be taken from the z-index the overlay
  writes
- 0 `textTracks`, so auto-detection gives 0 bands, as on the other sites
- layout at open: host fixed 540x448 covering the viewport, video 540x448 with the
  overlay's 559-char inline style, video z 2147483637 inside host z 2147483647, seek
  track 424 px with children in order `buf, segs, fil, knob, tip`
- nothing fights us for the element: 8 samples over 28 s — style length constant at 559,
  `100vw` still present, video and host width constant 540, and the centre hit-test
  returned `#fp-host` in every sample. `currentTime` advanced 149 -> 156 s unattended
- segments: `setSegments()` of 5 bands over 689.289 s -> first `left 0% width 17.409%`
  (= 120/689.289) with the explicit `#e91e63`, last `left 81.243% width 18.757%` on the
  palette default, `debug().segments` 5
- scrub: `currentTime` 344.64 of 689.289 = 50.0% -> knob and fill both `49.999%`. The tab
  was `document.hidden`, so rAF was frozen and only the seek/pause event path repainted —
  reading immediately shows the pre-seek `23.095%`, re-reading shows the truth
- mini: 248x140 at (275,260) — `min(380, 46% x 540)` x 16:9, right-inset 16, 58% down;
  `border-radius: 10px`, mini row `display:block`; expand -> host 539 px again
- close/restore: this site writes its **own** style on the video, and writes it oddly —
  the attribute literally contains quote characters, `"transform: scaleX(1);"`. It came
  back byte-identical after every cycle. Three cycles (open/close, open/mini/close,
  reopen with the site style already restored) all leave the video plus 8 ancestors
  byte-identical, 0 `#fp-host`, no `#fp-css`, and the site's player carried on (345 ->
  387 s)
- console for the whole pass: 260 logs of the site's own HLS.js/ad-SDK chatter, **0
  warnings, 2 errors, both my localhost fetch probe**

## Verified 2026-11-04 (sexvid: splash-gated player, one `<video>` reused for the ad)

Environment: bundled Chromium, **539x448** viewport, watch page `/…-…-….html` that
canonicalizes to the bare slug. Player is `#kt_player`; no CSP `meta`,
`window.trustedTypes` present but not enforced. Same in-page text-payload injection as
above (48,515 chars).

- the page loads with **no player at all**: `#kt_player.is-splash` and a
  `Resume watching` button. Only a same-origin ad iframe (`native_code`, 504x150) holds
  2 videos — invisible to us, which is the documented main-frame limit
- after the gate: exactly **1** main-frame `<video>`, first a 30.0 s pre-roll creative,
  then the **same element** carrying the content stream (`duration` 874 s) — the labels
  followed without a reopen, as on the other ad site. 0 `textTracks`
- layout at open: host and video 539x448, overlay style 593 chars, track 423 px, order
  `buf, segs, fil, knob, tip`
- the site did not take the element back: over the sampler run the style stayed 593 chars
  with `100vw`, centre hit-test `#fp-host`, and a synthetic `window` `resize` event left
  the style byte-for-byte unchanged (593 -> 593)
- segments: `setSegments()` of 4 bands over 874 s -> `0% / 10.296%`, `10.296% / 24.025%`,
  `34.321% / 34.321%`, `68.643% / 31.347%` — contiguous, explicit `#00e5ff` honoured
- scrub: `currentTime` 437 of 874 = 50.0% -> knob and fill `49.995%`
- mini: 248x140 at (275,260), **exactly** the formula values, radius 10 px, expand -> 539
- close/restore: the video had **no** style attribute before open and none after
  (`[style=""]` count 0 on the whole document); the 10-node chain came back
  byte-identical, only `#fp-chip` (54x54, bottom-right, `display:block`) remains, and the
  site's player resumed at 437 -> 438.2 s with `#kt_player` still 504 px wide
- chip reopen verified here: clicking the chip's shadow button (the listener is on the
  inner `button`, not on `#fp-chip`) re-opens to 539x448 and hides the chip; closing with
  `Close player` restores byte-identically a second time
- console for the whole pass: **0 errors**; 5 warnings, all `ads.exoclick.com ... Failed
  to execute 'write' on 'Document'` from the site's own ad SDK, plus our single ready log

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
- Track segments are bands only: no chapter name on hover and no jump-to-next-chapter.
  Automatic detection reads `video.textTracks` with `kind="chapters"`, which is empty on
  every site tested so far — YouTube, the JS-player site, xnxx and sexvid all measured at
  0 tracks — so on those sites the bands appear only when the APK pushes `setSegments()`;
  the detection polls up to 8 times (first at 250 ms, then 1 s apart) and gives up after
  that.
- Loading the script into a CSP/Trusted-Types site from a remote URL is refused by the
  page (measured on YouTube: `script-src` blocks the host, `eval` needs a TrustedScript;
  measured on xnxx: no `meta` but a response-header `default-src 'self' … 'unsafe-eval'`,
  under which `connect-src` falls back and blocks even a localhost `fetch`, while `eval`
  is allowed).
  The player itself no longer uses markup sinks, and the APK route
  (`webContents.evaluateJavaScript`) is browser-initiated, so neither policy applies to
  it; on a desktop page use the Snippets panel.
