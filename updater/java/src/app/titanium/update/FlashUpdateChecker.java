// Copyright 2026 The Titanium Browser Authors
// Use of this source code is governed by a GPLv2-only style license that can be
// found in the LICENSE file.

package app.titanium.update;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManager.NameNotFoundException;
import android.net.Uri;
import android.os.Environment;
import android.provider.Settings;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.preference.Preference;

import org.chromium.base.ContextUtils;
import org.chromium.base.ThreadUtils;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.about_settings.AboutChromeSettings;

import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Offers the newest GitHub release of this repository as an update. The version comes from the
 * redirect /releases/latest answers, so no API request is made and the unsigned prerelease builds,
 * which /releases/latest excludes, can never be offered.
 */
@NullMarked
public final class FlashUpdateChecker {
    private static final String RELEASE_REPO = "jasav24/android-titanium-browser";
    private static final String RELEASE_TAG_PREFIX = "titanium-";
    private static final String APK_ASSET_SUFFIX = "-arm64-v8a.apk";

    private static final String PREFS_NAME = "flash_update";
    private static final String KEY_LAST_CHECK = "last_check_ms";
    private static final String KEY_IGNORED_VERSION = "ignored_version";
    private static final String KEY_DOWNLOADED_VERSION = "downloaded_version";

    private static final long CHECK_INTERVAL_MS = 3L * 24 * 60 * 60 * 1000;

    private FlashUpdateChecker() {}

    public static void maybeCheckFromStartup(Activity activity) {
        SharedPreferences prefs = prefs();
        String current = installedVersion();
        if (current.isEmpty()) return;
        if (current.equals(prefs.getString(KEY_IGNORED_VERSION, ""))) return;
        if (current.equals(prefs.getString(KEY_DOWNLOADED_VERSION, ""))) return;
        if (System.currentTimeMillis() - prefs.getLong(KEY_LAST_CHECK, 0L) < CHECK_INTERVAL_MS) {
            return;
        }
        check(activity, /* manual= */ false);
    }

    public static void checkFromSettings(Activity activity) {
        check(activity, /* manual= */ true);
    }

    /** Adds the row that starts a manual check to the About screen, after the OS version row. */
    public static void addSettingsRow(AboutChromeSettings fragment, Preference anchor) {
        Context context = fragment.requireContext();
        Preference row = new Preference(context);
        row.setTitle(R.string.flash_update_check_title);
        row.setSummary(installedVersion());
        row.setOrder(anchor.getOrder());
        row.setOnPreferenceClickListener(
                clicked -> {
                    checkFromSettings(fragment.requireActivity());
                    return true;
                });
        if (fragment.getPreferenceScreen() != null) {
            fragment.getPreferenceScreen().addPreference(row);
        }
    }

    public static String installedVersion() {
        Context context = ContextUtils.getApplicationContext();
        try {
            PackageInfo info =
                    context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            return info.versionName == null ? "" : info.versionName;
        } catch (NameNotFoundException e) {
            return "";
        }
    }

    private static void check(Activity activity, boolean manual) {
        prefs().edit().putLong(KEY_LAST_CHECK, System.currentTimeMillis()).apply();
        new Thread(
                () -> {
                    @Nullable String latest = fetchLatestVersion();
                    String current = installedVersion();
                    ThreadUtils.runOnUiThread(
                            () -> {
                                if (activity.isFinishing() || activity.isDestroyed()) return;
                                if (latest == null) {
                                    if (manual) {
                                        showToast(activity, R.string.flash_update_failed);
                                    }
                                    return;
                                }
                                if (compareVersions(latest, current) <= 0) {
                                    if (manual) {
                                        showToast(activity, R.string.flash_update_latest, latest);
                                    }
                                    return;
                                }
                                SharedPreferences prefs = prefs();
                                if (!manual
                                        && (latest.equals(
                                                        prefs.getString(
                                                                KEY_IGNORED_VERSION, ""))
                                                || latest.equals(
                                                        prefs.getString(
                                                                KEY_DOWNLOADED_VERSION, "")))) {
                                    return;
                                }
                                showUpdateDialog(activity, latest, current);
                            });
                })
                .start();
    }

    private static void showUpdateDialog(Activity activity, String latest, String current) {
        new AlertDialog.Builder(activity)
                .setTitle(R.string.flash_update_available_title)
                .setMessage(
                        activity.getString(
                                R.string.flash_update_available_body, latest, current))
                .setPositiveButton(
                        R.string.flash_update_action,
                        (dialog, which) -> startDownload(activity, latest))
                .setNegativeButton(R.string.flash_update_not_now, null)
                .setNeutralButton(
                        R.string.flash_update_no_more,
                        (dialog, which) ->
                                prefs().edit().putString(KEY_IGNORED_VERSION, current).apply())
                .show();
    }

    private static void startDownload(Activity activity, String version) {
        Context context = ContextUtils.getApplicationContext();
        DownloadManager manager =
                (DownloadManager) context.getSystemService(Context.DOWNLOAD_SERVICE);
        if (manager == null) {
            showToast(context, R.string.flash_update_failed);
            return;
        }
        Uri apkUri =
                Uri.parse(
                        "https://github.com/"
                                + RELEASE_REPO
                                + "/releases/latest/download/"
                                + version
                                + APK_ASSET_SUFFIX);
        DownloadManager.Request request = new DownloadManager.Request(apkUri);
        request.setTitle(brandName(context) + " " + version);
        request.setDescription(version);
        request.setMimeType("application/vnd.android.package-archive");
        request.setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        request.setDestinationInExternalPublicDir(
                Environment.DIRECTORY_DOWNLOADS, version + APK_ASSET_SUFFIX);

        long downloadId;
        try {
            downloadId = manager.enqueue(request);
        } catch (SecurityException | IllegalArgumentException | IllegalStateException e) {
            showToast(context, R.string.flash_update_failed);
            return;
        }
        prefs().edit().putString(KEY_DOWNLOADED_VERSION, version).apply();

        context.registerReceiver(
                new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context receiverContext, Intent intent) {
                        if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                                != downloadId) {
                            return;
                        }
                        receiverContext.unregisterReceiver(this);
                        installDownloadedApk(receiverContext, manager, downloadId);
                    }
                },
                new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
                Context.RECEIVER_NOT_EXPORTED);
        showToast(context, R.string.flash_update_started);
    }

    private static void installDownloadedApk(
            Context context, DownloadManager manager, long downloadId) {
        Uri downloaded = manager.getUriForDownloadedFile(downloadId);
        if (downloaded == null) return;
        Intent install = new Intent(Intent.ACTION_VIEW);
        install.setDataAndType(downloaded, "application/vnd.android.package-archive");
        install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(install);
        } catch (SecurityException | ActivityNotFoundException e) {
            askForInstallPermission(context);
        }
    }

    /**
     * Without the per-app "install unknown apps" grant the installer cannot be started, so send the
     * user to that toggle instead of failing silently.
     */
    private static void askForInstallPermission(Context context) {
        Intent manage =
                new Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + context.getPackageName()));
        manage.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(manage);
        } catch (ActivityNotFoundException e) {
            showToast(context, R.string.flash_update_failed);
        }
    }

    @Nullable
    private static String fetchLatestVersion() {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            new URL("https://github.com/" + RELEASE_REPO + "/releases/latest")
                                    .openConnection();
            connection.setRequestMethod("HEAD");
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            String location = connection.getHeaderField("Location");
            if (location == null) return null;
            int marker = location.lastIndexOf("/tag/");
            if (marker < 0) return null;
            String tag = location.substring(marker + "/tag/".length());
            int end = tag.indexOf('?');
            if (end >= 0) tag = tag.substring(0, end);
            if (!tag.startsWith(RELEASE_TAG_PREFIX)) return null;
            String version = tag.substring(RELEASE_TAG_PREFIX.length());
            int dash = version.indexOf('-');
            if (dash >= 0) version = version.substring(0, dash);
            return version.isEmpty() ? null : version;
        } catch (IOException e) {
            return null;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static int compareVersions(String left, String right) {
        String[] leftParts = left.split("\\.");
        String[] rightParts = right.split("\\.");
        int count = Math.max(leftParts.length, rightParts.length);
        for (int i = 0; i < count; i++) {
            long a = versionPart(leftParts, i);
            long b = versionPart(rightParts, i);
            if (a != b) return a < b ? -1 : 1;
        }
        return 0;
    }

    private static long versionPart(String[] parts, int index) {
        if (index >= parts.length) return 0;
        try {
            return Long.parseLong(parts[index]);
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String brandName(Context context) {
        PackageManager pm = context.getPackageManager();
        return context.getApplicationInfo().loadLabel(pm).toString();
    }

    private static SharedPreferences prefs() {
        return ContextUtils.getApplicationContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    private static void showToast(Context context, int stringRes, Object... args) {
        String text =
                args.length == 0
                        ? context.getString(stringRes)
                        : context.getString(stringRes, args);
        Toast.makeText(context, text, Toast.LENGTH_LONG).show();
    }
}
