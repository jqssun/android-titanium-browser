# AGENTS.md — Helium Browser for Android

Guidelines for AI agents (Claude Code, Copilot, etc.) working in this repository.

> `CLAUDE.md` is a symlink to this file.

---

## Project Overview

**Helium Browser for Android** is a Chromium-based Android browser combining:
- [Helium](https://github.com/imputnet/helium) — extensions support and branding patches
- [Vanadium](https://github.com/GrapheneOS/Vanadium) — security and privacy hardening patches

Outputs: signed ARM64 + ARMv7 APKs published as GitHub Releases.

---

## Repository Structure

```
android-helium-browser/
├── build.sh                  # Main build orchestration (entry point)
├── common.sh                 # Shared helpers: set_keys(), sign_apk(), replace()
├── AGENTS.md                 # This file (CLAUDE.md is a symlink to this)
├── README.md                 # User-facing documentation
├── Chromium-Browser.md       # Future roadmap / reference projects
├── TODO.md                   # Open tasks
├── PLAN.md                   # Notes and planning references
├── renovate.json             # Renovate dependency update config
├── vanadium/                 # Git submodule — Vanadium source (patches + args.gn)
│   └── args.gn               # Build configuration template (Chromium GN flags)
├── helium/                   # Git submodule — Helium source (patches + utils)
└── .github/
    ├── workflows/build.yml   # GitHub Actions CI/CD workflow
    ├── dependabot.yml        # Dependabot config (Actions + submodules)
    └── copilot-instructions.md  # GitHub Copilot context (mirrors this file)
```

> **File discovery:** Use `rg --files` or `rg -l <pattern>` rather than `find`/`ls`.
> Examples:
> ```bash
> rg --files                         # all tracked files
> rg -l 'target_cpu'                 # files mentioning a flag
> rg 'sign_apk' --type sh            # bash files with sign_apk
> rg 'actions/cache' .github/        # cache usage in workflows
> ```

---

## Build System

### High-Level Flow

```
build.sh
  ├── common.sh → set_keys()          decode keystore secrets from env
  ├── apt-get install                 minimal build deps
  ├── clone depot_tools               if not cached
  ├── git fetch chromium@$VERSION     shallow fetch of exact tag
  ├── gclient sync                    sync Android deps (no history, no third_party cache)
  ├── apply vanadium patches          rename VANADIUM→HELIUM, apply *.patch via git am
  ├── inline sed patches              extension MV2 flags, toolbar layout, dimen fixes
  ├── gn gen out/Default              generate build files from args.gn
  ├── autoninja arm64                 compile chrome_public_apk
  ├── autoninja armeabi-v7a           reuse build dir, swap target_cpu
  └── sign_apk × 2                   sign with apksigner from Android SDK
```

### Key Build Configuration (`out/Default/args.gn` generated in `build.sh`)

| Flag | Value | Notes |
|------|-------|-------|
| `target_os` | `android` | |
| `target_cpu` | `arm64` → `arm` | switched between the two builds |
| `is_official_build` | `true` | |
| `symbol_level` | `0` | no debug symbols, faster builds |
| `use_lld` | `true` | fast linker |
| `use_thin_lto` | `true` | LTO enabled; disable to save ~30–50 min at cost of ~2–3% size |
| `use_siso` | `true` | Siso build system |
| `proprietary_codecs` | `true` | H.264/AAC support |
| `chrome_public_manifest_package` | `io.github.jqssun.helium` | app package ID |

The Chromium version is read directly from `vanadium/args.gn`:
```bash
VERSION=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' vanadium/args.gn)
```

### CI/CD Workflow (`.github/workflows/build.yml`)

Key steps in order:
1. Checkout with submodules (`filter: blob:none`, `fetch-depth: 1`)
2. Cache `depot_tools` (keyed on OS)
3. Cache `chromium/.gclient_entries` (keyed on `vanadium/args.gn` hash)
4. Optimize APT mirrors (`vegardit/fast-apt-mirror.sh@v1`)
5. Free disk space (`endersonmenezes/free-disk-space@v3`) — removes Android SDK, .NET, Haskell, etc.
6. Auto-update `vanadium` submodule to latest tag and push if changed
7. Run `build.sh` (needs `LOCAL_TEST_JKS` and `STORE_TEST_JKS` secrets)
8. Rename APKs with unix timestamp, publish via `softprops/action-gh-release@v2`

Secrets required:
- `LOCAL_TEST_JKS` — base64-encoded `local.properties` (keyAlias, keyPassword, storePassword)
- `STORE_TEST_JKS` — base64-encoded `test.jks` keystore file

---

## Development Workflow

### Branch Naming

```
claude/<task-description>-<session-id>
```

All feature work goes on a `claude/` branch. PRs target `master` (default branch for builds) or `main`.

### Typical Task Flow

1. Check out the correct branch: `git checkout claude/<task>-<id>` (create if needed)
2. Make changes; read files before editing
3. Commit with a clear message explaining *why*, not just *what*
4. Push: `git push -u origin <branch>`
5. Open PR targeting `master`

### Commit Style

- Imperative mood, present tense: `"Fix timeout in build step"`, not `"Fixed timeout"`
- Reference the affected file/component where helpful: `"build.sh: increase nproc parallelism"`

---

## Common Tasks

### Debugging Build Failures

1. Identify which phase failed: `apt-get`, `gclient sync`, `git am` (patching), `gn gen`, `autoninja`, `apksigner`
2. Check for patch conflicts — Helium and Vanadium patches may conflict after Chromium upstream changes
3. Verify `VERSION` parsed correctly from `vanadium/args.gn`
4. Check disk space (`df -h`) — build requires ~80GB free after cleanup

Quick search for errors:
```bash
rg 'ERROR|FAILED|error:' --type sh    # error patterns in build scripts
rg 'git am'                           # where patches are applied
```

### Updating Chromium Version

1. `vanadium` submodule auto-updates via CI (fetches latest tag)
2. After version bump, verify patches still apply cleanly locally
3. Check that `sed` inline patches still match source (file paths and string literals can change)
4. Update `vanadium/args.gn` version comment if needed

### Modifying Build Flags

Edit the `args.gn` heredoc inside `build.sh` (around line 82).
Always document the trade-off in a comment:
```
# NOTE: <flag> set to <value> because <reason>. Trade-off: <size/speed/features impact>.
```

### Adding/Modifying CI Steps

Edit `.github/workflows/build.yml`. Keep steps idempotent — the workflow can be re-run.
- Pin action versions to a specific tag (e.g. `@v5`, `@v3`)
- Use `|| true` on cleanup steps that may fail safely
- Avoid caching directories >10 GB (GitHub Actions cache limit is 10 GB per repo)

### Managing Disk Space

The GitHub-hosted `ubuntu-latest` runner starts with ~25 GB free. After the free-disk-space action, ~60–70 GB should be available.

To add more cleanup:
```yaml
remove_folders: "/path/to/add ..."   # space-separated, appended to existing list
remove_packages: "pkg1 pkg2 ..."
```

---

## Constraints and Safety Rules

- **Never commit secrets.** Keys live in `keys/` (gitignored). Secrets flow through GitHub Actions env vars only.
- **Never force-push to `master` or `main`.** These branches gate releases.
- **Never skip CI hooks** (`--no-verify`, `--no-gpg-sign`) unless explicitly requested.
- **Do not commit APKs or large binaries** — releases are published via GitHub Release assets.
- **Do not modify signing logic** (`common.sh:set_keys`, `common.sh:sign_apk`) without explicit approval.
- **Do not break the update step** in `build.yml` — it auto-commits submodule updates and pushes back to the branch.

---

## Debugging Quick Reference

| Symptom | First check |
|---------|-------------|
| `git am` fails | Chromium version changed; patch needs rebase |
| `autoninja` OOM | Reduce `-j` value; check available RAM |
| Build >3h / timeout | Disable `use_thin_lto`; check `enable_precompiled_headers` |
| APK signing fails | Verify secrets are correctly base64-encoded; check `keyAlias` matches |
| `gclient sync` hangs | Network issue; check GitHub Actions runner connectivity |
| Disk full mid-build | Add paths to `remove_folders` in free-disk-space step |

---

## References

- [Helium](https://github.com/imputnet/helium) — Chromium fork with extension support
- [Vanadium](https://github.com/GrapheneOS/Vanadium) — security-hardened Chromium for GrapheneOS
- [Chromium Build Docs](https://chromium.googlesource.com/chromium/src/+/main/docs/android_build_instructions.md)
- [GN Reference](https://gn.googlesource.com/gn/+/main/docs/reference.md)
- [depot_tools](https://chromium.googlesource.com/chromium/tools/depot_tools)
