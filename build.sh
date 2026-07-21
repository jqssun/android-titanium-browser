#!/bin/bash
source common.sh
set_keys

# Fail loudly instead of silently shipping a mobile-UA / no-extensions APK when
# an upstream Chromium anchor no longer matches.
set -o pipefail
die() { echo "[build.sh] FATAL: $*" >&2; exit 1; }
export VERSION=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' vanadium/args.gn)
export CHROMIUM_SOURCE=https://chromium.googlesource.com/chromium/src.git # https://github.com/chromium/chromium.git
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y sudo lsb-release file nano git curl python3 python3-pillow

# https://github.com/uazo/cromite/blob/master/tools/images/chr-source/prepare-build.sh
git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"
mkdir -p chromium/src/out/Default; cd chromium
gclient root; cd src
git init
git remote add origin $CHROMIUM_SOURCE
git fetch --depth 2 $CHROMIUM_SOURCE +refs/tags/$VERSION:chromium_$VERSION
git checkout $VERSION
export COMMIT=$(git show-ref -s $VERSION | head -n1)
cat > ../.gclient <<EOF
solutions = [
  {
    "name": "src",
    "url": "$CHROMIUM_SOURCE@$COMMIT",
    "deps_file": "DEPS",
    "managed": False,
    "custom_vars": {
      "checkout_android_prebuilts_build_tools": True,
      "checkout_telemetry_dependencies": False,
      "codesearch": "Debug",
    },
  },
]
target_os = ["android"]
EOF
git submodule foreach git config -f ./.git/config submodule.$name.ignore all
git config --add remote.origin.fetch '+refs/tags/*:refs/tags/*'

# https://grapheneos.org/build#browser-and-webview
rm -rf $SCRIPT_DIR/vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "HELIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Helium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "helium"
git am --whitespace=nowarn --keep-non-patch $SCRIPT_DIR/vanadium/patches/*.patch

gclient sync -D --no-history --nohooks
gclient runhooks
rm -rf third_party/angle/third_party/VK-GL-CTS/
./build/install-build-deps.sh --no-prompt

# https://github.com/imputnet/helium-linux/blob/main/scripts/shared.sh
# python3 "${SCRIPT_DIR}/helium/utils/name_substitution.py" --sub -t .
# python3 "${SCRIPT_DIR}/helium/utils/helium_version.py" --tree "${SCRIPT_DIR}/helium" --chromium-tree .
# python3 "${SCRIPT_DIR}/helium/utils/generate_resources.py" "${SCRIPT_DIR}/helium/resources/generate_resources.txt" "${SCRIPT_DIR}/helium/resources"
# python3 "${SCRIPT_DIR}/helium/utils/replace_resources.py" "${SCRIPT_DIR}/helium/resources/helium_resources.txt" "${SCRIPT_DIR}/helium/resources" .

sed -i 's/BASE_FEATURE(kExtensionManifestV2Unsupported, base::FEATURE_ENABLED_BY_DEFAULT);/BASE_FEATURE(kExtensionManifestV2Unsupported, base::FEATURE_DISABLED_BY_DEFAULT);/' extensions/common/extension_features.cc
sed -i 's/BASE_FEATURE(kExtensionManifestV2Disabled, base::FEATURE_ENABLED_BY_DEFAULT);/BASE_FEATURE(kExtensionManifestV2Disabled, base::FEATURE_DISABLED_BY_DEFAULT);/' extensions/common/extension_features.cc
sed -i '/feature_overrides.EnableFeature(::features::kSkipVulkanBlocklist);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/feature_overrides.EnableFeature(::features::kDefaultANGLEVulkan);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/feature_overrides.EnableFeature(::features::kVulkanFromANGLE);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/feature_overrides.EnableFeature(::features::kDefaultPassthroughCommandDecoder);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/<ViewStub/{N;N;N;N;N;N; /optional_button_stub/a\
\
        <ViewStub\
            android:id="@+id/extensions_toolbar_container_stub"\
            android:inflatedId="@+id/extensions_toolbar_container"\
            android:layout_width="wrap_content"\
            android:layout_height="match_parent" />
}' chrome/browser/ui/android/toolbar/java/res/layout/toolbar_phone.xml
sed -i 's|(ToolbarTablet) mToolbarLayout,|mToolbarLayout,|' chrome/android/java/src/org/chromium/chrome/browser/toolbar/ToolbarManager.java

# Verify the phone-toolbar ViewStub injection actually landed; otherwise the
# extensions puzzle-piece icon can never appear and the build should abort.
grep -q 'extensions_toolbar_container_stub' \
  chrome/browser/ui/android/toolbar/java/res/layout/toolbar_phone.xml \
  || die "toolbar_phone.xml ViewStub injection failed — Chromium layout changed"

# =============================================================================
# Fix 1 — Desktop User-Agent
# Strip "Android" and "Mobile" tokens from the UA so the Chrome Web Store
# serves the desktop install flow without requiring the user to enable
# "Desktop site" mode manually.
# Targets: UserAgentBuilder in chrome/browser/net/profile_network_context_service.cc
# and the embedder UA string in content/common/user_agent.cc
# =============================================================================

# Remove "Mobile" token from the UA brand list so navigator.userAgent and
# the HTTP User-Agent header both look like desktop Chrome on Linux.
[ -f components/embedder_support/user_agent_utils.cc ] \
  || die "components/embedder_support/user_agent_utils.cc missing — Chromium layout changed"
if grep -q 'brands.push_back({"Chromium", version});' components/embedder_support/user_agent_utils.cc; then
  echo "[UA brands] already applied — skipping"
elif grep -q 'brands.push_back({"Not/A)Brand", "99"});' components/embedder_support/user_agent_utils.cc; then
  sed -i 's/brands\.push_back({"Not\/A)Brand", "99"});/brands.push_back({"Not\/A)Brand", "99"});\n  brands.push_back({"Chromium", version});\n  brands.push_back({"Google Chrome", version});/' \
    components/embedder_support/user_agent_utils.cc
else
  die "UA brand anchor not found in user_agent_utils.cc — Chromium changed"
fi

# Force the UA platform string to Linux x86_64 for is_desktop_android builds.
# This is the primary gate the Chrome Web Store checks at the HTTP layer.
python3 - <<'PYEOF' || die "Fix 1 (desktop User-Agent) failed"
import re, pathlib, sys

# --- user_agent.cc: replace Android platform token with Linux ---
# This is the primary HTTP-layer gate the Chrome Web Store checks, so a genuine
# miss here MUST abort the build rather than silently ship a mobile UA.
ua_cc = pathlib.Path("content/common/user_agent.cc")
if not ua_cc.exists():
    sys.exit("[UA fix] FATAL: content/common/user_agent.cc not found — Chromium layout changed")
src = ua_cc.read_text()
if "(X11; Linux x86_64" in src:
    print("[UA fix] user_agent.cc already patched — skipping")
else:
    src = re.sub(
        r'(base::StringPrintf\([^)]*"Mozilla/5\.0 \()Linux; Android[^)]*\)',
        lambda m: m.group(0).replace(
            '(Linux; Android', '(X11; Linux x86_64'
        ).replace('Mobile ', ''),
        src
    )
    src = src.replace(' Mobile Safari/', ' Safari/')
    if "(X11; Linux x86_64" not in src:
        sys.exit("[UA fix] FATAL: platform-token anchor not found in user_agent.cc — Chromium changed")
    ua_cc.write_text(src)
    print("[UA fix] Patched content/common/user_agent.cc")

# --- embedder_support/user_agent_utils.cc: drop mobile brand hints ---
ua_utils = pathlib.Path("components/embedder_support/user_agent_utils.cc")
if not ua_utils.exists():
    sys.exit("[UA fix] FATAL: components/embedder_support/user_agent_utils.cc not found — Chromium changed")
src = ua_utils.read_text()
new = re.sub(r'"Android"', '"Linux"', src)
new = re.sub(r'(IsMobileDevice\(\)|is_mobile_device)[^;]*;', 'false;', new)
if new == src:
    sys.exit("[UA fix] FATAL: no Client-Hints mobile anchors matched in user_agent_utils.cc — Chromium changed")
ua_utils.write_text(new)
print("[UA fix] Patched components/embedder_support/user_agent_utils.cc")
PYEOF

# =============================================================================
# Fix 2 — Inflate extensions_toolbar_container_stub in phone toolbar
# The ViewStub is declared in toolbar_phone.xml (existing patch above) but
# never inflated at runtime on phone builds. This wires the inflate() call
# into ToolbarManager so the extensions puzzle-piece icon appears without
# any user action.
# =============================================================================

python3 - <<'PYEOF' || die "Fix 2 (toolbar stub inflate) failed"
import re, pathlib, sys

tm = pathlib.Path(
    "chrome/android/java/src/org/chromium/chrome/browser/toolbar/ToolbarManager.java"
)
if not tm.exists():
    sys.exit("[Toolbar fix] FATAL: ToolbarManager.java not found — Chromium changed")

src = tm.read_text()

# Inflate the stub immediately after the toolbar layout is set so the
# ExtensionsToolbarContainer view exists in the hierarchy before any
# coordinator tries to find it by ID.
inflate_block = """\n        // Helium: inflate extensions toolbar stub on phone layout
        View extensionsStub = mToolbarLayout.getRootView()
                .findViewById(R.id.extensions_toolbar_container_stub);
        if (extensionsStub instanceof ViewStub) {
            ((ViewStub) extensionsStub).inflate();
        }\n"""

anchor = 'mToolbarLayout = (ToolbarLayout) toolbarView;'
if 'extensions_toolbar_container_stub' in src:
    print("[Toolbar fix] already applied — skipping")
elif anchor in src:
    src = src.replace(anchor, anchor + inflate_block)
    tm.write_text(src)
    print("[Toolbar fix] Inserted ViewStub inflate() in ToolbarManager.java")
else:
    sys.exit("[Toolbar fix] FATAL: anchor 'mToolbarLayout = (ToolbarLayout) toolbarView;' not found — Chromium changed")
PYEOF

# =============================================================================
# Fix 3 — Wire ExtensionsToolbarCoordinator for phone (is_desktop_android)
# On tablet builds, ExtensionsToolbarCoordinator is initialized inside the
# ToolbarManager tablet-specific branch. For phone+is_desktop_android builds
# the coordinator is never constructed, so extension popups and badge counts
# don't work. This patch promotes the coordinator init out of the tablet guard.
# =============================================================================

python3 - <<'PYEOF' || die "Fix 3 (ExtensionsToolbarCoordinator phone wiring) failed"
import re, pathlib, sys

tm = pathlib.Path(
    "chrome/android/java/src/org/chromium/chrome/browser/toolbar/ToolbarManager.java"
)
if not tm.exists():
    sys.exit("[ExtCoord fix] FATAL: ToolbarManager.java not found — Chromium changed")

src = tm.read_text()

# Pattern: the coordinator is constructed inside an `if (mToolbarLayout instanceof ToolbarTablet)`
# block. We duplicate the constructor call outside that block, guarded instead by a
# null-check on the inflated container view, so it runs for any layout that has the
# extensions container (i.e., our patched phone toolbar).
marker = "init ExtensionsToolbarCoordinator on phone+is_desktop_android"
coord_init_pattern = re.compile(
    r'(mExtensionsToolbarCoordinator\s*=\s*new\s+ExtensionsToolbarCoordinator\([^;]+;)',
    re.DOTALL
)

if marker in src:
    print("[ExtCoord fix] already applied — skipping")
else:
    match = coord_init_pattern.search(src)
    if not match:
        sys.exit("[ExtCoord fix] FATAL: ExtensionsToolbarCoordinator init not found — Chromium changed")
    coord_call = match.group(1)
    phone_guard = (
        "\n        // Helium: " + marker +
        "\n        if (mExtensionsToolbarCoordinator == null) {"
        "\n            View extContainer = mToolbarLayout.getRootView()"
        "\n                    .findViewById(R.id.extensions_toolbar_container);"
        "\n            if (extContainer != null) {"
        "\n                " + coord_call +
        "\n            }"
        "\n        }\n"
    )
    src = coord_init_pattern.sub(coord_call + phone_guard, src, count=1)
    tm.write_text(src)
    print("[ExtCoord fix] Wired ExtensionsToolbarCoordinator for phone layout")
PYEOF

# =============================================================================
# Fix 4 — Suppress Chrome Web Store JS navigator.userAgent gate
# The CWS runs a JS check on navigator.userAgent in the page context that is
# separate from the HTTP UA header. Even with Fix 1 the CWS may still show
# the "only available on desktop" interstitial. We inject a content script
# via a built-in component extension that overrides navigator.userAgent and
# navigator.userAgentData.mobile in the main world for chromewebstore.google.com.
# =============================================================================

mkdir -p chrome/browser/resources/helium_cws_shim
cat > chrome/browser/resources/helium_cws_shim/manifest.json <<'JSONEOF'
{
  "manifest_version": 3,
  "name": "Helium CWS Desktop Shim",
  "version": "1.0",
  "description": "Presents a desktop UA to the Chrome Web Store so extensions install natively.",
  "content_scripts": [
    {
      "matches": ["https://chromewebstore.google.com/*"],
      "js": ["shim.js"],
      "run_at": "document_start",
      "world": "MAIN"
    }
  ]
}
JSONEOF

cat > chrome/browser/resources/helium_cws_shim/shim.js <<'JSEOF'
// Helium CWS Desktop Shim
// Overrides navigator.userAgent and userAgentData.mobile in the page's main
// world so the Chrome Web Store treats this as a desktop browser install.
(function () {
  'use strict';

  const desktopUA =
    navigator.userAgent
      .replace(/\(Linux; Android[^)]*\)/, '(X11; Linux x86_64)')
      .replace(/ Mobile\/[\w]+/, '')
      .replace(/ Mobile /, ' ');

  // Override navigator.userAgent
  try {
    Object.defineProperty(navigator, 'userAgent', {
      get: () => desktopUA,
      configurable: true,
    });
  } catch (e) {}

  // Override NavigatorUAData.mobile (Sec-CH-UA-Mobile)
  try {
    if (navigator.userAgentData) {
      Object.defineProperty(navigator.userAgentData, 'mobile', {
        get: () => false,
        configurable: true,
      });
    }
  } catch (e) {}

  // Suppress the CWS "desktop only" interstitial by patching the check
  // the CWS JS bundle performs on DOMContentLoaded.
  document.addEventListener(
    'DOMContentLoaded',
    function removeMobileInterstitial() {
      const selectors = [
        '[data-desktop-only-interstitial]',
        '.desktop-only-message',
        // CWS uses dynamic class names; also target by text content
      ];
      selectors.forEach((sel) => {
        document.querySelectorAll(sel).forEach((el) => el.remove());
      });
      // Remove any overlay that blocks the Add to Chrome button
      document.querySelectorAll('[role="dialog"]').forEach((dialog) => {
        const text = dialog.innerText || '';
        if (
          text.includes('only available on desktop') ||
          text.includes('Chrome Web Store is only available')
        ) {
          dialog.remove();
        }
      });
    },
    { once: true }
  );
})();
JSEOF

# Register the shim as a component extension so it loads at browser startup
# without requiring user interaction. We append it to the list of built-in
# component extensions in chrome/browser/extensions/component_extensions_allowlist/allowlist.cc
ALLOWLIST=chrome/browser/extensions/component_extensions_allowlist/allowlist.cc
[ -f "$ALLOWLIST" ] || die "$ALLOWLIST missing — cannot register CWS shim component extension"
if grep -q 'helium_cws_shim' "$ALLOWLIST"; then
  echo "[CWS shim] allowlist already patched — skipping"
elif grep -q '// End of component extension IDs' "$ALLOWLIST"; then
  sed -i '/\/\/ End of component extension IDs/i \
  // Helium CWS Desktop Shim\n  "helium_cws_shim",' "$ALLOWLIST"
else
  die "allowlist anchor '// End of component extension IDs' not found — Chromium changed"
fi

# Wire the shim directory into the GN build so it is packaged into the APK
cat >> chrome/browser/resources/BUILD.gn <<'GNEOF'

# Helium: CWS desktop shim component extension
grit("helium_cws_shim_resources") {
  source = "helium_cws_shim/manifest.json"
  outputs = [
    "grit/helium_cws_shim_resources.h",
    "helium_cws_shim_resources.pak",
  ]
  resource_ids = "//tools/gritsettings/resource_ids"
  output_dir = "$root_gen_dir/chrome"
}
GNEOF

sudo dpkg --add-architecture i386; sudo apt-get update; sudo apt-get install -y libgcc-s1:i386
cat > out/Default/args.gn <<EOF
chrome_public_manifest_package = "io.github.jqssun.helium"
is_desktop_android = true
target_os = "android"
target_cpu = "arm"
is_component_build = false
is_debug = false
is_official_build = true
symbol_level = 1
disable_fieldtrial_testing_config = true
ffmpeg_branding = "Chrome"
proprietary_codecs = true
enable_vr = false
enable_arcore = false
enable_openxr = false
enable_cardboard = false
enable_remoting = false
enable_reporting = false
google_api_key = "x"
google_default_client_id = "x"
google_default_client_secret = "x"

use_siso = true
use_login_database_as_backend = true
build_contextual_search = false
dcheck_always_on = false
enable_iterator_debugging = false
exclude_unwind_tables = false
icu_use_data_file = true
rtc_build_examples = false
use_errorprone_java_compiler = false
use_rtti = false
enable_av1_decoder = true
enable_dav1d_decoder = true
include_both_v8_snapshots = false
include_both_v8_snapshots_android_secondary_abi = false
generate_linker_map = true
EOF

gn gen out/Default # gn args out/Default; echo 'treat_warnings_as_errors = false' >> out/Default/args.gn
mkdir -p out/tmp out/release
autoninja -C out/Default chrome_public_apk
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-armeabi-v7a.apk

sed -i 's/target_cpu = "arm"/target_cpu = "arm64"/' out/Default/args.gn
autoninja -C out/Default chrome_public_apk
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-arm64-v8a.apk

export PATH=$PWD/third_party/jdk/current/bin/:$PATH
export ANDROID_HOME=$PWD/third_party/android_sdk/public
sign_apk out/tmp/$VERSION-armeabi-v7a.apk out/release/$VERSION-armeabi-v7a.apk
sign_apk out/tmp/$VERSION-arm64-v8a.apk out/release/$VERSION-arm64-v8a.apk
rm -rf $SCRIPT_DIR/keys
