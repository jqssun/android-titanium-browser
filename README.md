# Flash Browser for Android

[![Stars](https://img.shields.io/github/stars/jqssun/android-titanium-browser?label=Stars&logo=GitHub)](https://github.com/jqssun/android-titanium-browser)
[![GitHub](https://img.shields.io/github/downloads/jqssun/android-titanium-browser/total?label=GitHub&logo=GitHub)](https://github.com/jqssun/android-titanium-browser/releases)
[![license](https://img.shields.io/badge/License-GPLv2-blue.svg)](https://github.com/jqssun/android-titanium-browser/blob/main/LICENSE)
[![automation](https://img.shields.io/badge/automation-upstream%20sync%20%2B%20release-1d76db)](.github/automation/README.md)
[![release](https://img.shields.io/github/v/release/jqssun/android-titanium-browser)](https://github.com/jqssun/android-titanium-browser/releases)

Flash Browser is a rebranded fork of [**Titanium Browser for Android**](https://github.com/jqssun/android-titanium-browser), a secure and fully open-source, Chromium-based web browser with support for extensions. Titanium is based on [Vanadium](https://github.com/GrapheneOS/Vanadium) by [GrapheneOS](https://github.com/GrapheneOS). To maintain a fast and native experience for everyone, advanced features are modularized into [**Titanium Extension for Android**](https://github.com/jqssun/android-titanium-extension).

The upstream Titanium builds are published in the [**Titanium Releases**](https://github.com/jqssun/android-titanium-browser/releases/latest). Builds from this fork are produced by its own release workflow.

[<img height="48" alt="Get it on Google Play" src="https://jqssun.github.io/images/badges/google-play-store.svg">](https://play.google.com/store/apps/details?id=io.github.jqssun.helium)
[<img height="48" alt="Get it on GitHub" src="https://jqssun.github.io/images/badges/github.svg">](https://github.com/jqssun/android-titanium-browser/releases/latest)

<img alt="Flash Browser for Android" src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" />

## Usage

### Installing Extensions

You can install extensions from the following sources:
- [Chrome Web Store (Recommended)](https://chromewebstore.google.com/)
- [Opera Add-ons](https://addons.opera.com/)
- [Microsoft Edge Add-ons](https://microsoftedge.microsoft.com/addons/)

You can also install from local CRX (or ZIP) file in the options page of the built-in [**Titanium Extension for Android**](https://github.com/jqssun/android-titanium-extension). 

Additionally, you can load an unpacked extension manually for testing purposes by navigating to [`chrome://extensions`](chrome://extensions). Enable **Developer mode**, select **Load unpacked**, and choose the folder containing the extension in the Storage Access Framework (SAF) picker. It may take a moment for the extension to load.

### Using Extensions

To run an extension in Incognito (OTR) mode, go to **Manage extensions**, find the extension you want to use in Incognito mode, select **Details**, and turn on **Allow in Incognito**.

For advanced features including external download manager, enhanced dark mode, and additional privacy options, you can use the built-in [**Titanium Extension for Android**](https://github.com/jqssun/android-titanium-extension).

### Debug URLs

To view and access the debug URLs, use [`chrome://chrome-urls`](chrome://chrome-urls). For **Experiments**, use [`chrome://flags`](chrome://flags).

### WebRTC IP Policy

The option is available by using the menu button <kbd>⋮</kbd> in the top right corner, then selecting **Settings**, **Privacy and security**. If you experience issues with WebRTC due to IPs being shielded by default (e.g. [Discord Voice](https://discord.com/blog/how-discord-handles-two-and-half-million-concurrent-voice-users-using-webrtc)), try changing it to **Default public interface only**, or **Default**.

## Implementation

> [!WARNING]
> [Flash Browser for Android](#flash-browser-for-android) only attempts to improve security and privacy where possible. For better protection on Android, you should instead use [GrapheneOS](https://grapheneos.org) with [Vanadium](https://vanadium.app), which additionally integrates patches into Android System WebView and provides significant kernel and memory management hardening on the OS level.

```mermaid
---
config:
  layout: dagre
---
flowchart TD
 subgraph s1["Additional Patches"]
        n5["Feature Overrides"]
        n6["UI Overrides"]
        n7["Manifest V2 + Secure Off Store Install Support"]
        n8["Miscellaneous Fixes + Improvements"]
  end
 subgraph s2["Vanadium"]
        n9["Generic Patches<small><br>patches/*.patch</small>"]
        n10["Subprojects Patches<small><br>subprojects_patches/**/*.patch</small>"]
  end
 subgraph s3["Flash Browser for Android"]
        n11["GN Build Configuration<small><br>args.gn</small>"]
        n12["Signed Release"]
  end
    n1["Chromium"] --> s1 & s2
    n5 --> n6
    n6 --> n7
    n7 --> n8
    s1 --> s3
    s2 --> s3
    n11 --> n12
    n5@{ shape: subproc}
    n6@{ shape: subproc}
    n7@{ shape: subproc}
    n8@{ shape: subproc}
    n9@{ shape: subproc}
    n10@{ shape: subproc}
    n11@{ shape: subproc}
    n12@{ shape: subproc}
    n1@{ shape: rounded}
    classDef Aqua stroke-width:1px, stroke-dasharray:none, stroke:#46EDC8, fill:#DEFFF8, color:#378E7A
    style n5 stroke:#FF6D00
    style n7 stroke:#FF6D00
```

### In-app update check

`updater/java/src/app/titanium/update/FlashUpdateChecker.java` is compiled into
the browser by the `update:` block in [`patch.sh`](patch.sh), which copies it
into `titanium/chromium_src/chrome/android/java/src/…`, adds it to
`chrome_java_ext_rel_path_sources` in `chrome_java_ext_sources.gni`, and inserts
nine `IDS_FLASH_UPDATE_*` strings into `android_chrome_ext_strings.grdp`. Both
files are created by the Vanadium patch series, so no new GN target is needed.

The "latest version" comes from this repository's GitHub releases and needs no
token, JSON endpoint or rate limit: a `HEAD` request to
`https://github.com/jasav24/android-titanium-browser/releases/latest` with
redirects disabled returns a `Location` ending
`/releases/tag/titanium-<version>`. That tag form is only produced by the
signed path of the [chained build](#building); the unsigned fallback is published
as a prerelease (`titanium-<version>-unsigned`), and `releases/latest` excludes
prereleases, so an unsigned build can never be offered as an update. The APK is
then taken from the conventional asset path
`releases/latest/download/<version>-arm64-v8a.apk`.

Two entry points are wired in:

- `ChromeTabbedActivity.onDeferredStartup()` — runs after the first frame, and
  only prompts when the current version is neither the one already offered nor
  the one dismissed with **Do not ask again**, and at least three days have
  passed since the previous check.
- **Settings → About Flash Browser** — a `Check for updates` row added next to
  the OS-version row, which always queries.

The dialog's **Download** action hands the APK to `android.app.DownloadManager`,
so the progress and resume notification are the system's own; when the download
completes an internal receiver opens the package installer on the downloaded
file. `REQUEST_INSTALL_PACKAGES` is already declared in
`chrome/android/java/AndroidManifest.xml`, and a `SecurityException` falls back
to the per-app **Install unknown apps** screen.

Limits worth knowing before testing:

- Android gives no silent self-update for a normally installed APK, so the
  system install sheet always needs a tap; the browser cannot finish the update
  by itself.
- **Do not ask again** is stored against the currently installed version, so it
  stops applying as soon as an update is installed.
- If the process dies during a download, the file and its notification are
  owned by the system Downloads UI, which can be resumed and opened from there.

### In-page video player

[`player/`](player/README.md) is shipped as a bundled extension rather than injected
from Java. The `# player:` block in [`patch.sh`](patch.sh) registers
`player/dist/flash-player.crx` through the same `extensions/bundle.py` the Titanium
Extension is fetched with, so the id and version come from the packed artifact itself,
and it installs on first run as an external-pref extension next to it. Its manifest is
Manifest V3 with one content script over `http`/`https`, `world: "MAIN"` and
`all_frames: true`, which is what lets the same script that was measured as a console
snippet also run inside iframe players and survive a page's `script-src`.
`player/repack.sh` re-packs it, and the build refuses a crx whose contents have drifted
from `player/flashplayer.js` or `player/extension/manifest.json`.

## Building

The [**Chained build**](.github/workflows/chained-build.yml) workflow compiles
the ARM64 `chrome_public_apk` across several dispatched jobs, carrying the
prepared checkout and `out/Default` between them on the `build-cache` release.
Start it once with `action=continue` and `auto_chain=true`: each session that
runs out of time queues the next one, and the chain stops when an APK exists.

The build job compiles with `SIGN_RELEASE=false`, so the release key never enters
a six-hour unattended job. A session that ends with an APK uploads it as the
`titanium-arm64-unsigned` artifact, and the short `publish` job — which runs only
when that artifact exists — signs it and creates the GitHub release.

Signing material goes to the `release` environment as `RELEASE_KEYSTORE_B64`
(base64 of the PKCS12 keystore) and `RELEASE_LOCAL_PROPERTIES_B64` (base64 of a
`local.properties` defining `storePassword`, `keyPassword` and `keyAlias`); the
keystore itself is never committed. `vars.RELEASE_CERT_SHA256` is optional and
makes the job refuse an APK whose signer certificate does not match it;
`vars.KEYSTORE_TYPE` defaults to `PKCS12`. Until both secrets exist the job
publishes the unsigned build instead, as the prerelease
`titanium-<version>-unsigned`; with them the tag is `titanium-<version>` and the
APK installs as-is. Required reviewers on that environment make every signature a
manual approval.

Runner labels, environments and the complete setup checklist are in
[the automation guide](.github/automation/README.md#setup).

If a chain finished and left only the unsigned APK behind, dispatch
`action=sign`: it skips the build job entirely, takes the APK from the newest
`titanium-<version>-unsigned` release, signs it and publishes `titanium-<version>`.
The session that completes a build also saves its cache generation, so a later
`action=continue` restores a tree that already contains the APK and goes straight
to publishing instead of replaying the last few hours of compilation.

Current releases can be attested using [GitHub CLI](https://github.com/cli/cli):

```shell
gh attestation verify *.apk -R jasav24/android-titanium-browser
```

This repository also provides `build.sh` to compile on Linux (the latest Ubuntu
is the supported CI baseline). Upstream synchronization, protected-UI review,
full-build gating and release/rollback procedures are documented in
[`.github/automation/`](.github/automation/README.md).

## Credits

This project would not have been possible without the huge community contributions from [Vanadium](https://github.com/GrapheneOS/Vanadium), and without the privacy-focused, open-source approach shared by various other Chromium projects. All credit goes to the original authors and contributors. This project started around the same time as [Helium Browser for Linux](https://github.com/imputnet/helium-linux) but it is not affiliated with the desktop Helium project.