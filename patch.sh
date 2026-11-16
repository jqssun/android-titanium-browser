#!/bin/bash

mkdir -p chrome/android/java/res_titanium_base
cp $SCRIPT_DIR/res/drawable/themed_app_icon.xml chrome/android/java/res_titanium_base/drawable/themed_app_icon.xml
# icon: app mark
# Every PNG under res_titanium_base is overwritten, not tinted: that art is
# stock Titanium and the fork carries its own mark in res/app_icon.png. The
# file is a 1024px square already cropped to the centre of the mark and
# carrying its own background, so covering each density is the whole
# transformation. The adaptive foreground is left opaque — with both layers
# showing the same artwork, the launcher mask can crop or zoom without ever
# exposing a seam.
for icon in $(find chrome/android/java/res_titanium_base -type f -name '*.png'); do
  geometry=$(identify -format '%wx%h' "$icon")
  convert "$SCRIPT_DIR/res/app_icon.png" -resize "${geometry}^" -gravity center -extent "$geometry" "$icon"
done
sed -i 's|<application |<application android:extractNativeLibs="false" |' chrome/android/java/AndroidManifest.xml
sed -i 's|<data android:mimeType="message/rfc822"/>|<data android:mimeType="message/rfc822"/><data android:mimeType="application/pdf"/>|' chrome/android/java/AndroidManifest.xml
sed -i '/com.google.ar.core.min_apk_version/d' third_party/arcore-android-sdk-client/AndroidManifest_basesplit.xml
# sed -i 's|Google LLC|jqssun, Google LLC|' chrome/browser/ui/android/strings/android_chrome_strings.grd

# brand: display name
# Display-only rebranding to Flash Browser. Internal `titanium` paths, package
# ids and class names are deliberately left unchanged so the build graph and
# the bundled extension keep resolving. "Titanium Extension" is the name of the
# separate upstream extension project, so it is preserved verbatim.
brand_string_roots=(chrome components ui)
find "${brand_string_roots[@]}" -type f \( -name '*.grd' -o -name '*.grdp' -o -name '*.xtb' \) -exec sed -i \
  -e 's/Titanium Extension/__FLASH_EXTENSION_NAME__/g' \
  -e 's/Titanium Browser/Flash Browser/g' \
  -e 's/\bTitanium\b/Flash Browser/g' \
  -e 's/__FLASH_EXTENSION_NAME__/Titanium Extension/g' {} +
sed -i 's/\bTitanium\b/Flash Browser/g' chrome/android/java/res_titanium_base/values/channel_constants.xml

# links: stay in browser
# allowExternalNavigationForHttpProtocols() answers true for a phone, because its
# only gate is the Desktop-Android link-capturing feature, so a navigation that
# matches an installed app's verified link leaves Flash Browser for that app.
# Answer false for every http(s) URL and the page always loads in a tab. The
# caller keeps two exemptions of its own (ExternalNavigationHandler
# shouldBlockExternalNavigationForHttpProtocols): a Custom Tab returning its auth
# result to the app that opened it, and Play Store links, still leave the browser.
sed -i 's#return !OpenInAppUtils.isOpenInAppAvailable() || !UrlUtilities.isHttpOrHttps(url);#if (UrlUtilities.isHttpOrHttps(url)) return false;\n        return !OpenInAppUtils.isOpenInAppAvailable() || !UrlUtilities.isHttpOrHttps(url);#' chrome/android/java/src/org/chromium/chrome/browser/externalnav/ExternalNavigationDelegateImpl.java
grep -qF 'if (UrlUtilities.isHttpOrHttps(url)) return false;' chrome/android/java/src/org/chromium/chrome/browser/externalnav/ExternalNavigationDelegateImpl.java || { echo "links: patch did not apply; ExternalNavigationDelegateImpl changed upstream" >&2; exit 1; }

# player: ship the in-page video overlay as a bundled extension
# player/flashplayer.js reaches pages as a content script declared with
# "world": "MAIN" and "all_frames": true, which is how it keeps the behaviour that
# was measured by hand in the console: it runs in the page's own world, in every
# frame, and a page CSP that refuses a remote script cannot refuse this one. The
# crx in player/dist is packed by player/repack.sh (the signing key lives outside
# this repository, beside the release keystore), and its manifest version is
# stamped from the packing time, so a repack is always a version increase and the
# browser reinstalls instead of keeping the previous copy.
# Registered through the same bundle.py the Titanium Extension is fetched with, so
# the id, bundled.json and the asset list stay derived from the crx rather than
# hardcoded here. A file:// URL points it at the committed artifact.
python3 $SCRIPT_DIR/extensions/bundle.py $SCRIPT_DIR/extensions/dist flash-player "file://$SCRIPT_DIR/player/dist/flash-player.crx"
grep -qF '"external_crx": "flash-player.crx",' $SCRIPT_DIR/extensions/dist/bundled.json || { echo "player: the overlay is not in bundled.json, so nothing installs it" >&2; exit 1; }
grep -qF '"extensions/flash-player.crx",' $SCRIPT_DIR/extensions/dist/BUILD.gn || { echo "player: flash-player.crx is not staged as an APK asset" >&2; exit 1; }
# A packed artifact goes stale the moment someone edits the script and forgets to
# repack, so compare the bytes inside the crx against the source instead of
# trusting the file that happens to be committed.
python3 - "$SCRIPT_DIR/player/dist/flash-player.crx" "$SCRIPT_DIR/player/flashplayer.js" "$SCRIPT_DIR/player/extension/manifest.json" <<'PY' || { echo "player: dist/flash-player.crx is stale against player/; run player/repack.sh" >&2; exit 1; }
import base64, hashlib, json, struct, sys, zipfile

crx, script, template = sys.argv[1], sys.argv[2], sys.argv[3]
archive = zipfile.ZipFile(crx)
assert sorted(archive.namelist()) == ["flashplayer.js", "manifest.json"], archive.namelist()
assert archive.read("flashplayer.js") == open(script, "rb").read()

manifest = json.loads(archive.read("manifest.json"))
source = json.load(open(template))
source.pop("version")
packed = dict(manifest)
packed.pop("version")
assert packed == source, "manifest drifted from player/extension/manifest.json"

# The manifest key pins the extension id, so it has to be the key the crx was
# actually signed with, or the build records one id and Chromium installs another.
data = open(crx, "rb").read()
assert data[:4] == b"Cr24", "not a CRX file"
header = data[12:12 + struct.unpack("<I", data[8:12])[0]]


def varint(buf, i):
    value = shift = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return value, i


i = 0
while i < len(header):
    key, i = varint(header, i)
    length, i = varint(header, i)
    if key >> 3 == 10000:
        break
    i += length
signed = header[i + 2:i + 18]
assert len(signed) == 16, "no signing key in the crx header"
assert hashlib.sha256(base64.b64decode(manifest["key"])).digest()[:16] == signed, \
    "manifest key and signing key disagree"
print("player: bundled script, manifest and signing key all match the source")
PY

cp -r $SCRIPT_DIR/extensions/dist titanium/
cp $SCRIPT_DIR/extensions/stage_bundled_extensions.inc titanium/dist/
sed -i 's|"//components/privacy_sandbox/privacy_sandbox_attestations/preload:privacy_sandbox_attestations_assets",|&"//titanium/dist:extension_assets",|' chrome/android/BUILD.gn
sed -i 's|if (!base::PathService::Get(base::DIR_MODULE, \&cur)) {|if (!base::PathService::Get(chrome::DIR_USER_DATA, \&cur)) {|' chrome/common/chrome_paths.cc
sed -i 's|#include "extensions/buildflags/buildflags.h"|&\n#include "titanium/dist/stage_bundled_extensions.inc"|' chrome/browser/extensions/external_pref_loader.cc
sed -i 's|ReadStandaloneExtensionPrefFiles(prefs);|&StageBundledExtensions(base_path_id_, base_path_, prefs);|' chrome/browser/extensions/external_pref_loader.cc
sed -i 's|if (extension.location() == mojom::ManifestLocation::kCommandLine) {|if (extension.location() == mojom::ManifestLocation::kExternalPref) return false;\n&|' chrome/browser/extensions/extension_safety_check_utils.cc

sed -i '/android_apk_or_module_srcjar_deps_common/{n;s|if (!_omit_dex) {|if (_is_base_module \&\& !_omit_dex) {|}' build/config/android/rules.gni
sed -i '/safelyRemovePreference(prefFragment/d' titanium/chromium_src/chrome/browser/language/android/java/src/org/chromium/chrome/browser/language/settings/LanguageSettingsExt.java # language
sed -i '/safelyRemovePreference($/{N;/PREF_JAVASCRIPT_OPTIMIZER/d}' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettingsExt.java # optimizer
sed -i 's|if (!Intent\.ACTION_VIEW\.equals(intent\.getAction())) {|if (!Intent.ACTION_VIEW.equals(intent.getAction()) \|\| !android.webkit.URLUtil.isNetworkUrl(IntentHandler.getUrlFromIntent(intent))) {|' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|if (urlFromIntent == null) {|if (!android.webkit.URLUtil.isNetworkUrl(urlFromIntent)) {|' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|static void maybeModifyCustomTabIntents(Intent intent) {|& if (!android.webkit.URLUtil.isNetworkUrl(IntentHandler.getUrlFromIntent(intent))) { return; }|' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|readBoolean(getSettingsPreferenceKey(moduleType), true)|readBoolean(getSettingsPreferenceKey(moduleType), !HomeModulesUtils.belongsToEducationalTipModule(moduleType))|' chrome/browser/magic_stack/android/java/src/org/chromium/chrome/browser/magic_stack/HomeModulesConfigManager.java # ntp
sed -i 's|private static boolean verifyPackage(Context ctx, String pkgName, byte\[\] sha256CertDigestBytes) {|& if (true) return false; |' titanium/android_config/parser/java/src/app/titanium/config/TitaniumConfParser.java # config parser
sed -i 's|static boolean isSupported() {|& if (android.os.Build.VERSION.SDK_INT < 31) return false;|;s|LocationManager locationManager, LocationListener listener) {|& if (android.os.Build.VERSION.SDK_INT < 31) return false;|' titanium/chromium_src/services/downstream/device/geolocation/android/java/src/org/chromium/device/geolocation/CoarseLocationRequests.java # api

# sed -i 's|int ExpirationMilestoneForFlag(const char\* flag) {|int ExpirationMilestoneForFlag(const char* flag) { if ((true)) return -1;|' chrome/browser/unexpire_flags.cc
for flag in "align-wakeups" "android-bottom-bar" "cct-open-in-browser-button-if-allowed-by-embedder" "darken-websites-checkbox-in-themes-setting" "enable-accessibility-sequential-focus" "enforce-incognito-isolation" "inline-pdf-v2" "jump-start-omnibox" "lock-controls-on-tablets-v2" "offline-auto-fetch" "use-fullscreen-insets-api"; do
    sed -i "/\"name\": \"$flag\"/,/}/ s/\"expiry_milestone\": [0-9]\+/\"expiry_milestone\": -1/" chrome/browser/flag-metadata.json
done
sed -i 's|newFlag(OmniboxFeatureList.OMNIBOX_SITE_SEARCH, FeatureState.ENABLED_IN_TEST);|newFlag(OmniboxFeatureList.OMNIBOX_SITE_SEARCH, FeatureState.ENABLED_IN_PROD);|' components/omnibox/common/android/java/src/org/chromium/components/omnibox/OmniboxFeatures.java # search
sed -i 's|BASE_FEATURE(kOmniboxSiteSearch, DISABLED);|BASE_FEATURE(kOmniboxSiteSearch, ENABLED);|' components/omnibox/common/omnibox_features.cc # search

sed -i '/#if BUILDFLAG(IS_DESKTOP_ANDROID)/{
a\
feature_overrides.EnableFeature(chrome::android::kSubmenusInAppMenu);\
feature_overrides.EnableFeature(features::kAndroidDevToolsFrontend);\
feature_overrides.EnableFeature(kAndroidMediaPicker);\
feature_overrides.EnableFeature(features::kUserMediaScreenCapturing);\
feature_overrides.EnableFeature(media::kAndroidEnableBackgroundMediaCapturing);\
feature_overrides.EnableFeature(media::kAutoPictureInPictureAndroid);\
feature_overrides.EnableFeature(chrome::android::kLoadAllTabsAtStartup);\
feature_overrides.EnableFeature(chrome::android::kChromeNativeUrlOverriding);\
feature_overrides.EnableFeature(download::features::kEnableDownloadSaveAsContextMenu);\
#if 0
d}' chrome/browser/chrome_browser_field_trials.cc

# accessibility
sed -i 's|ChromeAccessibilityUtil.get().isAccessibilityEnabled()|org.chromium.ui.accessibility.AccessibilityState.isComplexUserInteractionServiceEnabled() \|\| org.chromium.ui.accessibility.AccessibilityState.isTouchExplorationEnabled()|' chrome/android/java/src/org/chromium/chrome/browser/tab/TabStateBrowserControlsVisibilityDelegate.java
sed -i 's|AccessibilityState.isPerformGesturesEnabled()|(AccessibilityState.isComplexUserInteractionServiceEnabled() \|\| AccessibilityState.isTouchExplorationEnabled())|' chrome/browser/ui/messages/android/java/src/org/chromium/chrome/browser/ui/messages/snackbar/SnackbarManager.java

# dev
# sed -i '0,/modelList.add(buildSettingsItem());/s//modelList.add(mMoreToolsItemBuilder.buildTaskManagerItem());modelList.add(mMoreToolsItemBuilder.buildDevToolsItem());&/' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java
sed -i '/BASE_FEATURE(kTaskManagerClank,/,/);/ s/base::FEATURE_DISABLED_BY_DEFAULT/base::FEATURE_ENABLED_BY_DEFAULT/' chrome/browser/task_manager/common/task_manager_features.cc
if version_lt "$VERSION" "156.0.8060.0"; then
sed -i 's|!DeviceFormFactor.isNonMultiDisplayContextOnTablet(mContext)|(false \&\& &)|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/MoreToolsItemBuilder.java
sed -i 's|boolean shouldShowDeveloperMenu() {|boolean shouldShowDeveloperMenu() { if (true) return DevToolsWindowAndroid.isDevToolsAllowedFor(getProfile(), mItemDelegate.getWebContents());|' chrome/android/java/src/org/chromium/chrome/browser/contextmenu/ChromeContextMenuPopulator.java
else
sed -i 's|DeviceFormFactor.isNonMultiDisplayContextOnTablet(context)|(true \|\| &)|' chrome/browser/devtools/android/java/src/org/chromium/chrome/browser/devtools/DevToolsWindowAndroid.java
fi
sed -i 's|TabUtils.isUsingDesktopUserAgent(mItemDelegate.getWebContents())|(true \|\| TabUtils.isUsingDesktopUserAgent(mItemDelegate.getWebContents()))|' chrome/android/java/src/org/chromium/chrome/browser/contextmenu/ChromeContextMenuPopulator.java

# dev: incognito
sed -i 's|intent.putExtra(DevToolsActivity.WEB_CONTENTS_KEY, webContents);|&intent.putExtra("org.chromium.chrome.browser.devtools.DevTools.Incognito", webContents.isIncognito());|' chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsActivity.java
sed -i 's|TabModel tabModel = getTabModelSelector().getModel(false);|TabModel tabModel = getTabModelSelector().getModel(getIntentDataProvider().isOffTheRecord());|' chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsActivity.java
sed -i 's|import org.chromium.chrome.browser.flags.ActivityType;|&\nimport org.chromium.chrome.browser.flags.CustomTabProfileType;|' chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsIntentDataProvider.java
sed -i '/^public class DevToolsIntentDataProvider extends BrowserServicesIntentDataProvider {$/a\ @Override public @CustomTabProfileType int getCustomTabMode() { return mIntent.getBooleanExtra("org.chromium.chrome.browser.devtools.DevTools.Incognito", false) ? CustomTabProfileType.INCOGNITO : CustomTabProfileType.REGULAR; }' chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsIntentDataProvider.java
sed -i 's|case CustomTabProfileType.INCOGNITO:|& if (getIntentDataProvider().getActivityType() == ActivityType.DEV_TOOLS) return null;|' chrome/android/java/src/org/chromium/chrome/browser/customtabs/BaseCustomTabActivity.java

# dev: viewport
sed -i 's|<meta charset="utf-8">|&\n<meta name="viewport" content="width=device-width">|' third_party/devtools-frontend/src/front_end/entrypoint_template.html
sed -i '$a@media (max-width: 600px) { .settings-window-title, .tabbed-pane-header-tab-title { display: none; } .tabbed-pane-shadow.vertical-tab-layout .tabbed-pane-header-tabs { width: auto; } }' third_party/devtools-frontend/src/front_end/panels/settings/settingsScreen.css
sed -i 's|document_->GetSettings() ? |document_->GetSettings() \&\& !document_->IsViewSource() ? |' third_party/blink/renderer/core/css/resolver/viewport_style_resolver.cc
sed -i 's|kViewSourceLineWrappingEnabled, false|kViewSourceLineWrappingEnabled, true|' chrome/browser/prefs/browser_prefs.cc

# playback
sed -i 's|#if BUILDFLAG(IS_ANDROID)|#if 0|' content/public/renderer/render_frame_media_playback_options.cc

# ext: viewport
sed -i 's|<meta name="color-scheme" content="light dark">|&\n<meta name="viewport" content="width=device-width">|' chrome/browser/resources/extensions/extensions.html
sed -i 's|--extensions-card-width: 400px;|--extensions-card-width: 96%;|' chrome/browser/resources/extensions/item_list.css # card width
sed -i 's|--cr-toolbar-field-width: 680px;|--cr-toolbar-field-width: 96%;|' chrome/browser/resources/extensions/shared_vars.css # page content
sed -i 's|padding: 24px 60px 64px;|padding: 24px 0 64px;|' chrome/browser/resources/extensions/item_list.css # content wrapper
sed -i 's|touch-action: none;|touch-action: pan-y;|' chrome/browser/resources/extensions/toggle_row.css # scroll

# ext: mv2
sed -i 's|uncompiled_sources_ = \[|&\n  "browser_action.json",\n  "page_action.json",|' chrome/common/extensions/api/api_sources.gni
sed -i 's/api::webstore_private::MV2DeprecationStatus::kHardDisable)));/api::webstore_private::MV2DeprecationStatus::kNone)));/' extensions/browser/api/webstore_private/webstore_private_api.cc
sed -i 's/bool g_allow_mv2_for_testing = false;/bool g_allow_mv2_for_testing = true;/' extensions/browser/manifest_v2_handler.cc

# ext: off store
sed -i '/^bool OffStoreInstallAllowedByPrefs(/a\if (const auto\& o = item.GetRequestInitiator(); o \&\& o->scheme() == "chrome-extension") return true; for (const char* d : {"addons.opera.com", "operacdn.com", "microsoftedge.microsoft.com", "edge.microsoft.com", "delivery.mp.microsoft.com"}) if (item.GetURL().DomainIs(d) || item.GetReferrerUrl().DomainIs(d)) return true;' chrome/browser/download/download_crx_util.cc
# sed -i 's/bool g_allow_offstore_install_for_testing = false;/bool g_allow_offstore_install_for_testing = true;/' chrome/browser/download/download_crx_util.cc
sed -i 's|public static void maybeDefaultEnableWindowSetting(Activity activity, Profile profile) {$|&WebsitePreferenceBridge.setContentSettingCustomScope(profile, ContentSettingsType.REQUEST_DESKTOP_SITE, "[*.]chromewebstore.google.com", SITE_WILDCARD, ContentSetting.ALLOW);|' chrome/browser/ui/android/desktop_site/java/src/org/chromium/chrome/browser/desktop_site/DesktopSiteUtils.java # desktop

# ext: toolbar
sed -i '/<ViewStub/{N;N;N;N;N;N; /optional_button_stub/a\
        <ViewStub\
            android:id="@+id/extensions_toolbar_container_stub"\
            android:inflatedId="@+id/extensions_toolbar_container"\
            android:layout_width="wrap_content"\
            android:layout_height="?attr/toolbarButtonHeight"\
            android:layout_marginVertical="?attr/toolbarButtonMarginVertical" />
}' chrome/browser/ui/android/toolbar/java/res/layout/toolbar_phone.xml
sed -i 's|(ToolbarTablet) mToolbarLayout,|mToolbarLayout,|' chrome/android/java/src/org/chromium/chrome/browser/toolbar/ToolbarManager.java
sed -i '/\/\/ Draw the signin button if visible./i\        { View extContainer = findViewById(R.id.extensions_toolbar_container); if (extContainer != null \&\& extContainer.getVisibility() != View.GONE \&\& extContainer.getWidth() != 0) { canvas.save(); ViewUtils.translateCanvasToView(mToolbarButtonsContainer, extContainer, canvas); extContainer.draw(canvas); canvas.restore(); } }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/top/ToolbarPhone.java

# ext: popup
sed -i '/public class RecyclerViewDelegate {$/a\public View getContainerView() { return mContainer; }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListCoordinator.java
sed -i '/private void showPopupOnAnchor() {/,/private void closePopup() {/ s|if (buttonView == null) {|if (false) {|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListMediator.java # scoped to showPopupOnAnchor
sed -i 's|buttonView.setIsPressed(true);|if (buttonView != null) buttonView.setIsPressed(true);|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListMediator.java
sed -i '/[[:space:]]mWindowAndroid,/!b;n;s|[[:space:]]buttonView,|buttonView != null ? buttonView : mRecyclerViewDelegate.getContainerView(),|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListMediator.java # set popup anchor

# ext: fullscreen
sed -i 's|#include "base/android/jni_string.h"|&\n#include "ui/base/device_form_factor.h"|' chrome/browser/ui/android/extensions/extension_action_popup_contents.cc
sed -i 's|render_frame_host->GetView()->EnableAutoResize(kMinSize, kMaxSize);|if (ui::GetDeviceFormFactor() == ui::DEVICE_FORM_FACTOR_PHONE) return;\n&|' chrome/browser/ui/android/extensions/extension_action_popup_contents.cc
sed -i '/^void ExtensionActionPopupContents::OnLoaded() {$/,/^}$/ s|^}$|if (ui::GetDeviceFormFactor() == ui::DEVICE_FORM_FACTOR_PHONE) Java_ExtensionActionPopupContents_resizeDueToAutoResize(AttachCurrentThread(), java_object_, 100000, 100000);\n}|' chrome/browser/ui/android/extensions/extension_action_popup_contents.cc
sed -i 's|mPopupWindowAndroid =$|{ View decor = activity.getWindow().getDecorView(); webContents.setSize(decor.getWidth(), decor.getHeight()); }\n&|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionPopup.java

# ext: pin
sed -i '/Pref.PIN_EXTENSIONS_MENU_BUTTON, this::updateMenuButtonPinState);$/a\if (!mPrefService.getBoolean(Pref.PIN_EXTENSIONS_MENU_BUTTON)) { mContainer.findViewById(R.id.extensions_menu_button).setVisibility(View.GONE); }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionsToolbarCoordinatorImpl.java
sed -i '/"ExtensionsToolbarCoordinatorImpl.requestLayoutWithViewUtils()");$/a\if (!isMenuButtonPinned()) { mContainer.findViewById(R.id.extensions_menu_button).setVisibility(View.GONE); }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionsToolbarCoordinatorImpl.java

# ext: incognito
sed -i 's|if (!context->IsOffTheRecord()) {|if (true) {|' extensions/browser/process_manager.cc
sed -i 's|public static boolean shouldOpenIncognitoAsWindow() {|public static boolean shouldOpenIncognitoAsWindow() { if (true) return true;|' chrome/browser/incognito/android/java/src/org/chromium/chrome/browser/incognito/IncognitoUtils.java

# ext: priority
sed -i 's|private @ChildProcessImportance int mEffectiveImportance;$|&private final boolean mIsExtensionProcess;|' content/public/android/java/src/org/chromium/content/browser/ChildProcessLauncherHelperImpl.java
sed -i 's|^ *if (!ApplicationStatus.isInitialized()) return;$|mIsExtensionProcess = Arrays.asList(commandLine).contains("--extension-process"); if (mIsExtensionProcess) mEffectiveImportance = ChildProcessImportance.IMPORTANT;&|' content/public/android/java/src/org/chromium/content/browser/ChildProcessLauncherHelperImpl.java
sed -i 's|@ChildProcessImportance int importance) {$|&if (mIsExtensionProcess) importance = ChildProcessImportance.IMPORTANT;|' content/public/android/java/src/org/chromium/content/browser/ChildProcessLauncherHelperImpl.java

# ext: settings
sed -i 's|"platforms": \["win", "mac"\]|"platforms": ["win", "mac", "desktop_android"]|' chrome/common/extensions/api/_manifest_features.json

# ext: dialog
sed -i 's|.with(ModalDialogProperties.FILTER_TOUCH_FOR_SECURITY, true)|.with(ModalDialogProperties.FILTER_TOUCH_FOR_SECURITY, false)|' chrome/browser/ui/android/extensions/java/src/org/chromium/chrome/browser/ui/extensions/ExtensionInstallDialogBridge.java

# ext: locale
sed -i 's|while (!(locale_path = locales.Next()).empty()) {|&if (locale_path.IsContentUri()) { locale_path = path.Append(locales.GetInfo().GetName()); }|' extensions/common/manifest_handlers/default_locale_handler.cc
sed -i 's|while (!(locale_folder = locales.Next()).empty()) {|&if (locale_folder.IsContentUri()) { locale_folder = locale_path.Append(locales.GetInfo().GetName()); }|' extensions/common/extension_l10n_util.cc
sed -i '/extension_l10n_util::ValidateExtensionLocales($/,/error) &&$/{s|extension_l10n_util::ValidateExtensionLocales(|(extension_path_.IsVirtualDocumentPath() \|\| &|;s|error) &&|error)) \&\&|}' extensions/browser/unpacked_installer.cc

# ext: ntp
sed -i 's|if (isTabNtp \&\& !currentTab.isNativePage() \&\& !isTabWebUiNtp) {|if (isTabNtp \&\& !currentTab.isNativePage() \&\& !isTabWebUiNtp \&\& !UrlOverrideUtils.isNtpOverrideEnabled()) {|' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java

# ext: app
sed -i 's|^  "app": {$|&\n    "platforms": ["chromeos", "linux", "mac", "win"],|' chrome/common/extensions/api/_api_features.json

# desktop: omnibox
sed -i 's/is_desktop_android = !!BUILDFLAG(IS_DESKTOP_ANDROID);/is_desktop_android = false;/' components/omnibox/browser/zero_suggest_verbatim_match_provider.cc
sed -i 's/is_android_mobile = is_android_any \&\& !is_android_desktop;/is_android_mobile = is_android_any \&\& is_android_desktop;/' components/omnibox/browser/autocomplete_result.cc
# sed -i 's|OmniboxCapabilities.hasDesktopExperience(context)|true|g' chrome/browser/ui/android/omnibox/java/src/org/chromium/chrome/browser/omnibox/FuseboxSessionState.java

# desktop: menu
sed -i 's|if (!IncognitoUtils.shouldOpenIncognitoAsWindow() \|\| is|if (!shouldShowNewIncognitoWindow() \|\| is|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java
sed -i 's|if (!separateIncognitoWindow \|\| is|if (!shouldShowNewIncognitoWindow() \|\| is|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java
sed -i 's|<item type="id" name="manage_all_windows_menu_id" />|&<item type="id" name="incognito_toggle_menu_id" />|' chrome/android/java/res/values/ids.xml # regular
sed -i 's|modelList.add(buildManageWindowsItem());$|&if (isIncognito \&\& MultiWindowUtils.isMultiInstanceApi31Enabled()) modelList.add(new ListItem(AppMenuHandler.AppMenuItemType.STANDARD, AppMenuItemUtils.buildModelForStandardMenuItem(mContext, getAppMenuItemTheme(), R.id.incognito_toggle_menu_id, R.string.accessibility_tabstrip_btn_incognito_toggle_incognito, R.drawable.ic_open_in_browser, false)));|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java # regular
sed -i 's|if (id == R.id.manage_all_windows_menu_id) {|if (id == R.id.incognito_toggle_menu_id) { int w = MultiWindowUtils.getLastAccessedWindowIdExcludingSelf(mInstanceId, PersistedInstanceType.REGULAR); if (w != INVALID_WINDOW_ID) openWindow(w, NewWindowAppSource.WINDOW_MANAGER); else openNewWindow(false); return true; } &|' chrome/android/java/src/org/chromium/chrome/browser/multiwindow/MultiInstanceManagerApi31.java # regular

# crbug.com/406136787: load unpacked
sed -i 's|assert treeId.equals(documentId);|&\n if ("com.android.externalstorage.documents".equals(mAuthority)) { String fastId = mRelativePath.isEmpty() ? treeId : (treeId.endsWith(":") ? treeId + mRelativePath : treeId + "/" + mRelativePath); Uri fast = DocumentsContract.buildDocumentUriUsingTree(tree, fastId); return contentUriExists(fast) ? fast : null; }|' base/android/java/src/org/chromium/base/VirtualDocumentPath.java

# crbug.com/445475304: incognito back
sed -i 's|private void onTabChanged(@Nullable Tab tab) {|private void onTabChanged(@Nullable Tab tab) { if (tab != null \&\& tab.isIncognitoBranded()) { mSystemBackPressSupplier.set(true); return; }|' chrome/browser/back_press/android/java/src/org/chromium/chrome/browser/back_press/MinimizeAppAndCloseTabBackPressHandler.java

# crbug.com/431004500: incognito uaf
sed -i '/for (int i = 0; i < tab_list->GetTabCount(); ++i) {/i if (!tab_list) { continue; }' chrome/browser/extensions/api/tabs/tabs_api.cc

# crbug.com/40274462: incognito uaf
sed -i '/CONTENT_EXPORT static WebContents\* FromRenderFrameHost(RenderFrameHost\* rfh);/a\CONTENT_EXPORT static bool HasLiveWebContentsForBrowserContext(BrowserContext* browser_context);' content/public/browser/web_contents.h
sed -i '/^WebContentsImpl::WebContentsImpl(BrowserContext\* browser_context)/i\ bool WebContents::HasLiveWebContentsForBrowserContext(BrowserContext* browser_context) { for (WebContentsImpl* web_contents : WebContentsImpl::GetAllWebContents()) { if (web_contents->GetBrowserContext() == browser_context) { return true; } } return false; }' content/browser/web_contents/web_contents_impl.cc
sed -i '/#include "content\/public\/browser\/render_process_host.h"/a#include "content/public/browser/web_contents.h"' chrome/browser/profiles/profile_destroyer.cc
sed -i '/^void ProfileDestroyer::DestroyOTRProfileWhenAppropriateWithTimeout($/,/MaybeSendDestroyedNotification/{/  profile->MaybeSendDestroyedNotification();/i\
if (content::WebContents::HasLiveWebContentsForBrowserContext(profile)) { return; }
}' chrome/browser/profiles/profile_destroyer.cc

# crbug.com/444024982: api 31
sed -i 's/|| mSupportedProfileType == SupportedProfileType.REGULAR) {/|| mSupportedProfileType == SupportedProfileType.REGULAR || mSupportedProfileType == SupportedProfileType.MIXED) {/' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java
sed -i 's/|| mSupportedProfileType == SupportedProfileType.OFF_THE_RECORD) {/|| mSupportedProfileType == SupportedProfileType.OFF_THE_RECORD || mSupportedProfileType == SupportedProfileType.MIXED) {/' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java

# update: offer the newest release of this repository from inside the browser
# The latest version is read from the Location header a HEAD request to /releases/latest answers,
# which names the tag of the newest non-prerelease, non-draft release. That keeps the release REST
# API out of it (60 unauthenticated requests per hour per IP, from every user's own address) and it
# means a `titanium-<version>-unsigned` prerelease can never be offered as an update. The asset name
# is the version plus the ABI build.sh produces, so the download URL needs no release lookup either.
mkdir -p titanium/chromium_src/chrome/android/java/src/app/titanium/update
cp $SCRIPT_DIR/updater/java/src/app/titanium/update/FlashUpdateChecker.java titanium/chromium_src/chrome/android/java/src/app/titanium/update/FlashUpdateChecker.java
# chrome_java_ext_sources.gni is the downstream sources list that the "Extend //chrome/android java
# targets sources and deps" patch of the Vanadium series already imports into //chrome/android:
# chrome_java, so a new class costs one list entry instead of a new build target.
sed -i 's|^chrome_java_ext_rel_path_sources = \[$|&\n  "java/src/app/titanium/update/FlashUpdateChecker.java",|' titanium/chromium_src/chrome/android/chrome_java_ext_sources.gni
grep -qF '"java/src/app/titanium/update/FlashUpdateChecker.java",' titanium/chromium_src/chrome/android/chrome_java_ext_sources.gni || { echo "update: chrome_java_ext_sources.gni changed shape; the new class would not be compiled" >&2; exit 1; }
# The series keeps its own strings in android_chrome_ext_strings.grdp, which is already included in
# //chrome/browser/ui/android/strings, so these reach org.chromium.chrome.R as lowercase ids. The
# brand sed above does not walk titanium/, so the product name is written out here.
sed -i 's|^</grit-part>$|  <message name="IDS_FLASH_UPDATE_CHECK_TITLE" desc="About screen row that starts a manual check for a newer Flash Browser release">Check for updates</message>\n  <message name="IDS_FLASH_UPDATE_AVAILABLE_TITLE" desc="Title of the dialog offering a newer Flash Browser release">Update available</message>\n  <message name="IDS_FLASH_UPDATE_AVAILABLE_BODY" desc="Body of the dialog offering a newer Flash Browser release. $1 is the newest version, $2 the installed one.">Flash Browser <ph name="NEWER_VERSION">$1</ph> is available. You are running <ph name="INSTALLED_VERSION">$2</ph>. Download and install it now?</message>\n  <message name="IDS_FLASH_UPDATE_ACTION" desc="Button that starts downloading the newer Flash Browser release">Download</message>\n  <message name="IDS_FLASH_UPDATE_NOT_NOW" desc="Button that closes the update dialog without doing anything">Not now</message>\n  <message name="IDS_FLASH_UPDATE_NO_MORE" desc="Button that stops the update dialog from appearing on this version">Do not ask again</message>\n  <message name="IDS_FLASH_UPDATE_LATEST" desc="Shown when a manual check finds no newer Flash Browser release. $1 is the installed version.">You have the latest version (<ph name="INSTALLED_VERSION">$1</ph>).</message>\n  <message name="IDS_FLASH_UPDATE_FAILED" desc="Shown when the release page could not be reached">Could not reach the release page. Check the connection and try again.</message>\n  <message name="IDS_FLASH_UPDATE_STARTED" desc="Shown after the newer release download has been started">Download started. A notification appears when it finishes.</message>\n</grit-part>|' titanium/chromium_src/chrome/browser/ui/android/strings/android_chrome_ext_strings.grdp
grep -qF 'IDS_FLASH_UPDATE_AVAILABLE_BODY' titanium/chromium_src/chrome/browser/ui/android/strings/android_chrome_ext_strings.grdp || { echo "update: android_chrome_ext_strings.grdp changed shape; the dialog has no strings" >&2; exit 1; }
# grit rejects a $N formatter that is not wrapped in <ph> (PlaceholderNotInsidePhNode), and it only
# says so when the strings target is built — 2m34s into the compile that hit it, 21 minutes into
# the session once the tree has been restored. Read the part file back here instead so a bad copy
# stops the session in its first minute.
python3 - titanium/chromium_src/chrome/browser/ui/android/strings/android_chrome_ext_strings.grdp <<'PY' || { echo "update: a placeholder in the new strings sits outside a <ph> element, which grit refuses" >&2; exit 1; }
import re, sys, xml.etree.ElementTree as ET

def outside_ph(node):
    text = node.text or ''
    for child in node:
        if child.tag != 'ph':
            text += outside_ph(child)
        text += child.tail or ''
    return text

for message in ET.parse(sys.argv[1]).getroot().iter('message'):
    if re.search(r'\$\d', outside_ph(message)):
        raise SystemExit('%s carries a bare placeholder' % message.get('name'))
PY
# Two one-line hooks, both into a method that already exists in the built tree: the About screen
# gets its manual entry next to the OS version row, and the startup check rides on
# ChromeTabbedActivity.onDeferredStartup(), just after its own isFinishing-or-destroyed guard, so
# the work lands after first paint and a slow or offline release page cannot delay boot.
sed -i 's|p.setSummary(AboutSettingsBridge.getOSVersion());|&\n        app.titanium.update.FlashUpdateChecker.addSettingsRow(this, p);|' chrome/android/java/src/org/chromium/chrome/browser/about_settings/AboutChromeSettings.java
grep -qF 'FlashUpdateChecker.addSettingsRow(this, p);' chrome/android/java/src/org/chromium/chrome/browser/about_settings/AboutChromeSettings.java || { echo "update: AboutChromeSettings changed upstream" >&2; exit 1; }
sed -i 's|Activity activity = ChromeTabbedActivity.this;|&\n        app.titanium.update.FlashUpdateChecker.maybeCheckFromStartup(activity);|' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java
grep -qF 'FlashUpdateChecker.maybeCheckFromStartup(activity);' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java || { echo "update: ChromeTabbedActivity.onDeferredStartup changed upstream" >&2; exit 1; }

export PATCHED=1
