# Working with Claude on Helium Browser

This document provides best practices and guidelines for collaborating with Claude Code on the Android Helium Browser project.

## Project Overview

Helium Browser is an experimental Chromium-based web browser for Android with:
- Extensions support
- Privacy and security hardening (based on Helium and Vanadium)
- Custom patches applied to Chromium source
- Automated CI/CD build pipeline using GitHub Actions
- APK signing and release management

**Key Files:**
- `build.sh` - Main build orchestration script
- `common.sh` - Shared build utilities
- `.github/workflows/build.yml` - GitHub Actions workflow
- `vanadium/args.gn` - Chromium GN build configuration

## Build System Overview

The build process involves:

1. **Dependency Setup** - Clone Chromium source with depot_tools
2. **Patch Application** - Apply Helium and Vanadium patches
3. **Build Configuration** - Set GN arguments for Android ARM64
4. **Compilation** - Use autoninja with LLD linker
5. **APK Signing** - Sign with keystore and release

### Build Configuration (args.gn)

Key optimization flags:
```
use_lld = true                      # High-performance linker
use_thin_lto = false                # Disabled for speed
enable_precompiled_headers = true   # Faster compilation
symbol_level = 0                    # No debug symbols
target_cpu = "arm64"                # ARM64 target
```

## Common Tasks

### Optimizing Build Performance

When the build is slow or timing out:

1. Check current args.gn settings - compare `use_thin_lto`, `symbol_level`, `enable_precompiled_headers`
2. Disable expensive optimizations (ThinLTO, debug symbols)
3. Enable precompiled headers
4. Increase parallelism with `-j` flag (consider `nproc + 4`)
5. Optimize CI/CD workflow:
   - Use `endersonmenezes/free-disk-space@v3` for fast cleanup
   - Add `vegardit/fast-apt-mirror.sh@v1` for faster APT downloads
   - Set explicit timeout-minutes (e.g., 180)

**Ask Claude:** "The build is timing out at X minutes. Can you analyze the bottlenecks and suggest optimizations?"

### Updating Chromium Base

When updating to a new Chromium version:

1. Check vanadium tag updates - documented in the patch process
2. Verify Helium patches still apply cleanly
3. Test build locally before pushing
4. Document breaking changes

**Ask Claude:** "How do I update Chromium to version X while maintaining our patches?"

### Modifying Build Arguments

When adjusting GN arguments:

1. Understand the trade-off (size vs. speed vs. features)
2. Test locally first if possible
3. Document the change and rationale
4. Monitor build time impact

**Ask Claude:** "What's the impact of changing [flag] to [value]? How do I test this?"

### Debugging Build Failures

When builds fail:

1. Check the error message and which phase failed (gclient sync, patching, compilation, linking, signing)
2. Isolate the issue (dependency, patch conflict, configuration)
3. Provide context about recent changes

**Ask Claude:** "The build failed at [phase] with error: [message]. What's the most likely cause?"

### Git Workflow

This project uses feature branches prefixed with `claude/`:
- Branch naming: `claude/[task-description]-[session-id]`
- Changes are committed with clear messages
- Push to the feature branch only
- PR workflow: feature branch → main

**Ask Claude:** "How do I commit these changes and push to the feature branch?"

## Build Optimization Patterns

### Disk Space Management

GitHub Actions runners have limited disk space. The workflow includes:
- Fast cleanup action (`endersonmenezes/free-disk-space@v3`)
- Removal of unnecessary packages and tools
- Docker image cleanup
- Cache strategy for large artifacts

Use the `free-disk-space` action parameters to control what gets cleaned up.

### Dependency Caching

Currently cached:
- `depot_tools` - Chromium tools
- `.gclient_entries` - Lightweight Chromium metadata (avoids caching `third_party/`)

Adding new caches:
- Define key based on file hash (use `hashFiles()`)
- Provide restore-keys for fallback
- Avoid caching large directories (>10GB)

### Parallelism

- `gclient sync` uses `-j $(nproc)`
- `autoninja` currently uses `-j $(( $(nproc) + 4 ))` by default for better core utilization on high-core machines. This can be overridden by setting the `JOBS` environment variable.

## File Structure

```
android-helium-browser/
├── build.sh                    # Main build script
├── common.sh                   # Shared utilities
├── CLAUDE.md                   # This file
├── README.md                   # Project documentation
├── vanadium/                   # Vanadium patches and args
│   └── args.gn                 # Build configuration template
├── chromium/                   # Chromium source (cloned at build time)
├── depot_tools/                # Chromium tools (cloned at build time)
└── .github/workflows/
    └── build.yml               # GitHub Actions workflow
```

## Asking Claude for Help

### Good Requests

✅ "The build timeout increased from 1h to 1.5h. What changed and how can we optimize?"
✅ "Can you update the workflow to use the endersonmenezes/free-disk-space action?"
✅ "How do I add caching for X artifact?"
✅ "What's the impact of disabling ThinLTO on APK size and build speed?"
✅ "Can you review the args.gn settings for optimization opportunities?"

### Provide Context

Include:
- Specific build errors or timeouts
- Recent changes you made
- Current resource constraints (GitHub Actions vs. self-hosted)
- Target metrics (build time, APK size)
- Error messages or logs

### What Claude Can Do

- Analyze build performance bottlenecks
- Suggest GN argument changes with trade-off analysis
- Optimize GitHub Actions workflows
- Debug build failures and suggest fixes
- Refactor scripts for clarity and efficiency
- Review configuration changes

### What Claude Cannot Do

- Modify security-sensitive code without clear authorization
- Commit and push without your explicit request
- Make breaking changes to patches without testing
- Change build targets or outputs without approval

## Recent Optimizations

The build was recently optimized to prevent 1.5h+ timeouts:

- Disabled ThinLTO (major time savings, ~2-3% size increase)
- Lowered symbol levels to 0 (removes debug symbols)
- Enabled precompiled headers
- Switched to faster disk cleanup action
- Added APT mirror optimization
- Increased build parallelism
- Set explicit 180-minute timeout

These changes brought estimated build time down by 30-50 minutes.

## Debugging Tips

**Build gets stuck at 1.5h:**
- Check if it's CPU-bound (ninja busy) or I/O-bound (disk/network)
- Run with more verbose output if available
- Consider disabling expensive optimizations
- Check available disk space

**Patches fail to apply:**
- Verify Chromium version matches patch expectations
- Check for conflicts between Helium and Vanadium patches
- Review recent changes to patched files upstream

**APK signing fails:**
- Verify keystore secrets are correctly base64-encoded
- Check keystore password and key alias are correct
- Ensure APK file was actually built

**APT package issues:**
- Network timeouts during `apt update` - retry is built in
- Missing packages - update apt mirrors or use fallback packages
- Parallel downloads failures - reduce parallelism in edge cases

## References

- [Helium Browser](https://github.com/imputnet/helium)
- [Vanadium](https://github.com/GrapheneOS/Vanadium)
- [Chromium Build Documentation](https://chromium.googlesource.com/chromium/src/+/main/docs/)
- [GN Build System](https://gn.googlesource.com/gn/)
