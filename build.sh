#!/bin/bash
source common.sh
set_keys
export VERSION=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' vanadium/args.gn)
export CHROMIUM_SOURCE=https://chromium.googlesource.com/chromium/src.git
export DEBIAN_FRONTEND=noninteractive LC_ALL=C

# Note: APT mirror and parallel download optimization is handled by the CI workflow
# (vegardit/fast-apt-mirror.sh@v1). Keep APT configuration here minimal to avoid conflicts.
sudo apt-get update
sudo apt-get install -y sudo lsb-release file nano git curl python3 python3-pillow

# https://github.com/uazo/cromite/blob/master/tools/images/chr-source/prepare-build.sh
if [[ ! -d "depot_tools" ]]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$PWD/depot_tools:$PATH"
mkdir -p chromium/src/out/Default; cd chromium
gclient root; cd src
git init
git remote add origin $CHROMIUM_SOURCE
git fetch --depth 1 $CHROMIUM_SOURCE +refs/tags/$VERSION:chromium_$VERSION
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

gclient sync -D --no-history --nohooks --shallow -j $(nproc)
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
: << TOOLBAR_PHONE
sed -i '/<ViewStub/{N;N;N;N;N;N; /optional_button_stub/a\
\
        <ViewStub\
            android:id="@+id/extension_toolbar_container_stub"\
            android:inflatedId="@+id/extension_toolbar_container"\
            android:layout_width="wrap_content"\
            android:layout_height="match_parent" />
}' chrome/browser/ui/android/toolbar/java/res/layout/toolbar_phone.xml
sed -i 's/extension_toolbar_baseline_width">600dp/extension_toolbar_baseline_width">0dp/' chrome/browser/ui/android/extensions/java/res/values/dimens.xml
TOOLBAR_PHONE

cat > out/Default/args.gn <<EOF
chrome_public_manifest_package = "io.github.jqssun.helium"
is_desktop_android = true
target_os = "android"
target_cpu = "arm64"
is_component_build = false
is_debug = false
is_official_build = true
symbol_level = 0
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
use_login_database_as_backend = false
build_contextual_search = false
build_with_tflite_lib = true
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
generate_linker_map = false

# Build performance optimizations
use_lld = true
# NOTE: ThinLTO is intentionally disabled to significantly reduce build times
# for Chrome APK builds in this environment. This may increase the final APK
# size by ~2–3% and slightly reduce runtime performance; see CLAUDE.md line 184
# for details. This trade-off is considered acceptable for our use case.
# TODO: speed up build while using lto
use_thin_lto = true
thin_lto_enable_optimizations = true
enable_precompiled_headers = false
enable_nacl = false
use_goma = false
enable_backup_ref_ptr_support = false
enable_pointer_compression_support = true
v8_enable_pointer_compression = true
EOF
gn gen out/Default # gn args out/Default; echo 'treat_warnings_as_errors = false' >> out/Default/args.gn
autoninja -C out/Default chrome_public_apk
mkdir -p out/tmp out/release
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-arm64-v8a.apk

sed -i 's/target_cpu = "arm64"/target_cpu = "arm"/' out/Default/args.gn
autoninja -C out/Default chrome_public_apk
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-armeabi-v7a.apk

export PATH=$PWD/third_party/jdk/current/bin/:$PATH
export ANDROID_HOME=$PWD/third_party/android_sdk/public
sign_apk out/tmp/$VERSION-arm64-v8a.apk out/release/$VERSION-arm64-v8a.apk
sign_apk out/tmp/$VERSION-armeabi-v7a.apk out/release/$VERSION-armeabi-v7a.apk
rm -rf $SCRIPT_DIR/keys
