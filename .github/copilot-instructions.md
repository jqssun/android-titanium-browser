# Copilot Instructions — Helium Browser for Android

## Project Summary

Android Chromium browser combining [Helium](https://github.com/imputnet/helium) (extensions support) and [Vanadium](https://github.com/GrapheneOS/Vanadium) (security/privacy patches). Outputs signed ARM64 + ARMv7 APKs via GitHub Actions.

## Key Files

| File | Purpose |
|------|---------|
| `build.sh` | Full build pipeline: deps → patch → gn → ninja → sign |
| `common.sh` | Shell helpers: `set_keys()`, `sign_apk()`, `replace()` |
| `vanadium/args.gn` | GN build flags; also contains the Chromium version string |
| `.github/workflows/build.yml` | CI/CD: cleanup → sync → build → release |

Use `rg --files` or `rg -l <pattern>` for file discovery.

## Languages & Tools

- **Shell (bash):** `build.sh`, `common.sh` — sourced with `source common.sh`
- **GN:** `vanadium/args.gn` — Chromium build configuration
- **YAML:** `.github/workflows/build.yml` — GitHub Actions
- **No application source code** — this repo orchestrates the Chromium build; patches live in the `helium/` and `vanadium/` submodules

## Shell Conventions

- Scripts use `set -e` behavior through `|| exit 1` on critical steps
- Use `$SCRIPT_DIR` (set via `realpath $(dirname $0)` in `common.sh`) for absolute paths
- Prefer `$(nproc)` for CPU count; parallelism is `$(( $(nproc) + 4 ))` for ninja
- APT installs use `DEBIAN_FRONTEND=noninteractive` and `-y` flags
- Cleanup commands use `|| true` — they must not abort the build on failure

## GN / Build Flag Conventions

- All build args go in the `args.gn` heredoc inside `build.sh` (around line 82)
- Add a comment for any non-obvious flag explaining the trade-off
- `target_cpu` is switched from `arm64` → `arm` for the second APK build using `sed -i`
- Version is extracted with: `grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' vanadium/args.gn`

## GitHub Actions Conventions

- Pin actions to semver tags (e.g. `@v5`, `@v3`), not `@main` or SHAs
- Secrets accessed via `${{ secrets.NAME }}` — never log or echo secret values
- Environment variables set with `echo "VAR=value" >> $GITHUB_ENV`
- Steps that may safely fail use `|| true`
- Cache keys follow pattern: `<name>-${{ runner.os }}-${{ hashFiles(...) }}`

## Security Rules (enforce these in suggestions)

- Never suggest committing files in `keys/` — it is gitignored and contains keystore secrets
- Secrets flow only through GitHub Actions env vars (`LOCAL_TEST_JKS`, `STORE_TEST_JKS`)
- Do not suggest changes to `set_keys()` or `sign_apk()` in `common.sh` without explicit context
- Do not suggest `--no-verify` or force-push to `master`/`main`

## What This Repo Does NOT Contain

- No Kotlin/Java/C++ application code (that lives in Chromium source, fetched at build time)
- No test suites — the build itself is the test
- No Docker files — builds run on GitHub-hosted or self-hosted Ubuntu runners

## Common Patterns

**Inline patch via sed (build.sh):**
```bash
sed -i 's/OLD_STRING/NEW_STRING/' path/to/file.cc
if ! grep -q 'EXPECTED_RESULT' path/to/file.cc; then
  echo "Error: patch verification failed" >&2
  exit 1
fi
```

**Disk-safe cache entry (workflow):**
```yaml
- uses: actions/cache@v5
  with:
    path: some/lightweight/path
    key: name-${{ runner.os }}-${{ hashFiles('relevant/file') }}
    restore-keys: |
      name-${{ runner.os }}-
```

**APK renaming pattern (workflow):**
```bash
find chromium/src/out/release -name '*.apk'  # locate built APKs
```
