#!/bin/bash

mkdir -p chrome/android/java/res_titanium_base
cp $SCRIPT_DIR/res/drawable/themed_app_icon.xml chrome/android/java/res_titanium_base/drawable/themed_app_icon.xml
for icon in $(find chrome/android/java/res_titanium_base -type f -name '*.png'); do convert $icon -fill navy -tint 36 $icon && $SCRIPT_DIR/res/icon.sh $icon; done
sed -i 's|<application |<application android:extractNativeLibs="false" |' chrome/android/java/AndroidManifest.xml
# sed -i 's|Google LLC|jqssun, Google LLC|' chrome/browser/ui/android/strings/android_chrome_strings.grd

sed -i 's|private static void init(Context ctx, SpecType specType) {|private static void init(Context ctx, SpecType specType) { if (!isEligible()) { return; }|' titanium/android_config/parser/java/src/app/titanium/config/TitaniumConfParser.java
sed -i 's|if (!_omit_dex) {|if (_is_base_module \&\& !_omit_dex) {|' build/config/android/rules.gni
sed -i '/safelyRemovePreference(prefFragment/d' titanium/chromium_src/chrome/browser/language/android/java/src/org/chromium/chrome/browser/language/settings/LanguageSettingsExt.java
sed -i '/removeEntryForKey(fragmentName, "translate_switch")/d' chrome/android/java/src/org/chromium/chrome/browser/settings/search/SettingsSearchCoordinator.java
sed -i 's|if (!Intent\.ACTION_VIEW\.equals(intent\.getAction())) {|if (!Intent.ACTION_VIEW.equals(intent.getAction())\n                \|\| !android.webkit.URLUtil.isNetworkUrl(IntentHandler.getUrlFromIntent(intent))) {|' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|if (urlFromIntent == null) {|if (!android.webkit.URLUtil.isNetworkUrl(urlFromIntent)) {|' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|static Intent maybeModifyCustomTabIntents(Context context, Intent intent) {|static Intent maybeModifyCustomTabIntents(Context context, Intent intent) { if (!android.webkit.URLUtil.isNetworkUrl(IntentHandler.getUrlFromIntent(intent))) { return intent; }|' titanium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard

sed -i '/feature_overrides.EnableFeature(::features::kSkipVulkanBlocklist);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/feature_overrides.EnableFeature(::features::kDefaultANGLEVulkan);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/feature_overrides.EnableFeature(::features::kVulkanFromANGLE);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/feature_overrides.EnableFeature(::features::kDefaultPassthroughCommandDecoder);/d' chrome/browser/chrome_browser_field_trials.cc
sed -i '/BASE_FEATURE(kFallbackToSWIfGLES3NotSupported,/,/#endif/ s/base::FEATURE_ENABLED_BY_DEFAULT/base::FEATURE_DISABLED_BY_DEFAULT/' ui/gl/gl_features.cc

# dev
sed -i 's/BASE_FEATURE(kSubmenusInAppMenu, base::FEATURE_DISABLED_BY_DEFAULT);/BASE_FEATURE(kSubmenusInAppMenu, base::FEATURE_ENABLED_BY_DEFAULT);/' chrome/browser/flags/android/chrome_feature_list.cc
sed -i '/BASE_FEATURE(kTaskManagerClank,/,/);/ s/base::FEATURE_DISABLED_BY_DEFAULT/base::FEATURE_ENABLED_BY_DEFAULT/' chrome/browser/task_manager/common/task_manager_features.cc
sed -i 's/BASE_FEATURE(kAndroidDevToolsFrontend, base::FEATURE_DISABLED_BY_DEFAULT);/BASE_FEATURE(kAndroidDevToolsFrontend, base::FEATURE_ENABLED_BY_DEFAULT);/' content/public/common/content_features.cc
sed -i 's|if (!DeviceFormFactor.isNonMultiDisplayContextOnTablet(mContext)) {|if (false) {|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java
sed -i 's|boolean shouldShowDeveloperMenu() {|boolean shouldShowDeveloperMenu() { if (true) return DevToolsWindowAndroid.isDevToolsAllowedFor(getProfile(), mItemDelegate.getWebContents());|' chrome/android/java/src/org/chromium/chrome/browser/contextmenu/ChromeContextMenuPopulator.java
sed -i 's|TabUtils.isUsingDesktopUserAgent(mItemDelegate.getWebContents())|(true \|\| TabUtils.isUsingDesktopUserAgent(mItemDelegate.getWebContents()))|' chrome/android/java/src/org/chromium/chrome/browser/contextmenu/ChromeContextMenuPopulator.java

# search
sed -i 's|BASE_FEATURE(kOmniboxSiteSearch, DISABLED);|BASE_FEATURE(kOmniboxSiteSearch, ENABLED);|' components/omnibox/common/omnibox_features.cc

# playback
sed -i 's|#if BUILDFLAG(IS_ANDROID)|#if 0|' content/public/renderer/render_frame_media_playback_options.cc

# viewport
sed -i 's|constexpr gfx::Size kMinSize = {25, 25};|constexpr gfx::Size kMinSize = {256, 25};|' chrome/browser/ui/android/extensions/extension_action_popup_contents.cc
sed -i 's|<meta name="color-scheme" content="light dark">|&\n<meta name="viewport" content="width=device-width">|' chrome/browser/resources/extensions/extensions.html
sed -i 's|--extensions-card-width: 400px;|--extensions-card-width: 96%;|' chrome/browser/resources/extensions/item_list.css # card width
sed -i 's|--cr-toolbar-field-width: 680px;|--cr-toolbar-field-width: 96%;|' chrome/browser/resources/extensions/shared_vars.css # page content
sed -i 's|padding: 24px 60px 64px;|padding: 24px 0 64px;|' chrome/browser/resources/extensions/item_list.css # content wrapper

# ext: mv2
sed -i 's|uncompiled_sources_ = \[|&\n  "browser_action.json",\n  "page_action.json",|' chrome/common/extensions/api/api_sources.gni
sed -i 's/api::webstore_private::MV2DeprecationStatus::kHardDisable)));/api::webstore_private::MV2DeprecationStatus::kNone)));/' chrome/browser/extensions/api/webstore_private/webstore_private_api.cc
sed -i 's/bool g_allow_mv2_for_testing = false;/bool g_allow_mv2_for_testing = true;/' extensions/browser/manifest_v2_handler.cc

# ext: off store
sed -i '/^bool OffStoreInstallAllowedByPrefs(/a\  for (const char* d : {"addons.opera.com", "operacdn.com", "microsoftedge.microsoft.com", "edge.microsoft.com", "delivery.mp.microsoft.com"}) if (item.GetURL().DomainIs(d) || item.GetReferrerUrl().DomainIs(d)) return true;' chrome/browser/download/download_crx_util.cc
# sed -i 's/bool g_allow_offstore_install_for_testing = false;/bool g_allow_offstore_install_for_testing = true;/' chrome/browser/download/download_crx_util.cc

# ext: toolbar
sed -i '/<ViewStub/{N;N;N;N;N;N; /optional_button_stub/a\
        <ViewStub\
            android:id="@+id/extensions_toolbar_container_stub"\
            android:inflatedId="@+id/extensions_toolbar_container"\
            android:layout_width="wrap_content"\
            android:layout_height="match_parent" />
}' chrome/browser/ui/android/toolbar/java/res/layout/toolbar_phone.xml
sed -i 's|(ToolbarTablet) mToolbarLayout,|mToolbarLayout,|' chrome/android/java/src/org/chromium/chrome/browser/toolbar/ToolbarManager.java
sed -i '/\/\/ Draw the signin button if visible./i\        { View extContainer = findViewById(R.id.extensions_toolbar_container); if (extContainer != null \&\& extContainer.getVisibility() != View.GONE \&\& extContainer.getWidth() != 0) { canvas.save(); ViewUtils.translateCanvasToView(mToolbarButtonsContainer, extContainer, canvas); extContainer.draw(canvas); canvas.restore(); } }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/top/ToolbarPhone.java

# ext: popup
sed -i '/public class RecyclerViewDelegate {$/a\public View getContainerView() { return mContainer; }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListCoordinator.java
sed -i '/private void showPopupOnAnchor() {/,/private void closePopup() {/ s|if (buttonView == null) {|if (false) {|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListMediator.java # scoped to showPopupOnAnchor
sed -i 's|buttonView.setIsPressed(true);|if (buttonView != null) buttonView.setIsPressed(true);|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListMediator.java
sed -i '/[[:space:]]mWindowAndroid,/!b;n;s|[[:space:]]buttonView,|buttonView != null ? buttonView : mRecyclerViewDelegate.getContainerView(),|' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionActionListMediator.java # set popup anchor

# ext: popup keyboard
sed -i 's|private boolean handleKeyboardEvent(WebContents webContents, KeyEvent event) {|private boolean handleKeyboardEvent(WebContents webContents, KeyEvent event) { if (event == null) return false;|' chrome/browser/ui/android/extensions/java/src/org/chromium/chrome/browser/ui/extensions/ExtensionActionPopupContents.java

# ext: pin
sed -i '/Pref.PIN_EXTENSIONS_MENU_BUTTON, this::updateMenuButtonPinState);$/a\if (!mPrefService.getBoolean(Pref.PIN_EXTENSIONS_MENU_BUTTON)) { mContainer.findViewById(R.id.extensions_menu_button).setVisibility(View.GONE); }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionsToolbarCoordinatorImpl.java
sed -i '/"ExtensionsToolbarCoordinatorImpl.requestLayoutWithViewUtils()");$/a\if (!isMenuButtonPinned()) { mContainer.findViewById(R.id.extensions_menu_button).setVisibility(View.GONE); }' chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/extensions/ExtensionsToolbarCoordinatorImpl.java

# ext: incognito
sed -i 's|if (!context->IsOffTheRecord()) {|if (true) {|' extensions/browser/process_manager.cc
sed -i 's|public static boolean shouldOpenIncognitoAsWindow() {|public static boolean shouldOpenIncognitoAsWindow() { if (true) return true;|' chrome/browser/incognito/android/java/src/org/chromium/chrome/browser/incognito/IncognitoUtils.java

# ext: priority
sed -i 's|host_contents_->SetColorProviderSource(NoOpColorProviderSource::Get());|&\nhost_contents_->SetPrimaryPageImportance(content::ChildProcessImportance::IMPORTANT, content::ChildProcessImportance::NORMAL);|' extensions/browser/extension_host.cc

# ext: perms prompt
sed -i '/content::WebContents\* web_contents = show_params->GetParentWebContents();/,/DCHECK(view_android);/{/GetParentWebContents/!d}' chrome/browser/ui/android/extensions/extension_install_dialog_view_android.cc
sed -i 's|view_android->GetWindowAndroid();|show_params->GetParentWindow();|' chrome/browser/ui/android/extensions/extension_install_dialog_view_android.cc

# ext: dialog
sed -i 's|.with(ModalDialogProperties.FILTER_TOUCH_FOR_SECURITY, true)|.with(ModalDialogProperties.FILTER_TOUCH_FOR_SECURITY, false)|' chrome/browser/ui/android/extensions/java/src/org/chromium/chrome/browser/ui/extensions/ExtensionInstallDialogBridge.java

# ext: locale
sed -i 's|while (!(locale_path = locales.Next()).empty()) {|&if (locale_path.IsContentUri()) { locale_path = path.Append(locales.GetInfo().GetName()); }|' extensions/common/manifest_handlers/default_locale_handler.cc
sed -i 's|while (!(locale_folder = locales.Next()).empty()) {|&if (locale_folder.IsContentUri()) { locale_folder = locale_path.Append(locales.GetInfo().GetName()); }|' extensions/common/extension_l10n_util.cc
sed -i '/extension_l10n_util::ValidateExtensionLocales($/,/error) &&$/{s|extension_l10n_util::ValidateExtensionLocales(|(extension_path_.IsVirtualDocumentPath() \|\| &|;s|error) &&|error)) \&\&|}' extensions/browser/unpacked_installer.cc

# desktop: omnibox
sed -i 's/is_desktop_android = !!BUILDFLAG(IS_DESKTOP_ANDROID);/is_desktop_android = false;/' components/omnibox/browser/zero_suggest_verbatim_match_provider.cc
sed -i 's/is_android_mobile = is_android_any \&\& !is_android_desktop;/is_android_mobile = is_android_any \&\& is_android_desktop;/' components/omnibox/browser/autocomplete_result.cc

# tmp
sed -i 's|if (!IncognitoUtils.shouldOpenIncognitoAsWindow() \|\| isIncognitoShowing()) {|if (true) {|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java
sed -i 's|if (!separateIncognitoWindow \|\| isIncognito) {|if (true) {|' chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java
sed -i 's/BASE_FEATURE(kAndroidSearchInSettings,"SearchInSettings", base::FEATURE_DISABLED_BY_DEFAULT);/BASE_FEATURE(kAndroidSearchInSettings,"SearchInSettings", base::FEATURE_ENABLED_BY_DEFAULT);/' chrome/browser/flags/android/chrome_feature_list.cc

# crbug.com/406136787: load unpacked
sed -i 's|assert treeId.equals(documentId);|&\n if ("com.android.externalstorage.documents".equals(mAuthority)) { String fastId = mRelativePath.isEmpty() ? treeId : (treeId.endsWith(":") ? treeId + mRelativePath : treeId + "/" + mRelativePath); Uri fast = DocumentsContract.buildDocumentUriUsingTree(tree, fastId); return contentUriExists(fast) ? fast : null; }|' base/android/java/src/org/chromium/base/VirtualDocumentPath.java

# crbug.com/40831291: bottom address bar
sed -i 's@(idealFitsBelow && spaceBelowAnchor >= spaceAboveAnchor) || !idealFitsAbove;@(idealFitsBelow == idealFitsAbove) ? (spaceBelowAnchor >= spaceAboveAnchor) : idealFitsBelow;@' ui/android/java/src/org/chromium/ui/widget/PopupSpecCalculator.java

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

export PATCHED=1
