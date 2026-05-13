// Copyright 2025 Helium Authors. All rights reserved.
// JNI bridge for synchronous VirusTotal hash lookups from native C++ code.
// Called via VtJniBridge::GetBlocking() in vt_extension_scanner.cc

package org.chromium.chrome.browser.extensions;

import android.util.Log;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

public class VtExtensionScanner {
    private static final String TAG = "VtExtensionScanner";

    /**
     * Performs a synchronous HTTP GET to the VirusTotal API v3.
     * Transmits ONLY the SHA-256 hash — no file data ever leaves the device.
     *
     * Called from native C++ via JNI. Must run on a background thread.
     *
     * @param apiUrl    Full VT URL: https://www.virustotal.com/api/v3/files/{sha256}
     * @param apiKey    VirusTotal API key (injected at build time via helium_vt_api_key GN arg)
     * @param timeoutMs HTTP connect + read timeout in milliseconds
     * @return JSON response body, or empty string on failure/timeout (triggers fail-open)
     */
    @CalledByNative
    public static String getBlocking(String apiUrl, String apiKey, int timeoutMs) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(apiUrl);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setRequestProperty("x-apikey", apiKey);
            conn.setRequestProperty("Accept", "application/json");
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setDoOutput(false);

            int status = conn.getResponseCode();

            // 404 = hash not in VT database — return sentinel so C++ maps to kUnknown
            if (status == 404) return "{\"not_found\":true}";

            // Any other non-200 → fail open (kOffline)
            if (status != 200) {
                Log.w(TAG, "VT API returned HTTP " + status + " — fail open");
                return "";
            }

            BufferedReader reader = new BufferedReader(
                new InputStreamReader(conn.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            return sb.toString();

        } catch (java.net.SocketTimeoutException e) {
            Log.d(TAG, "VT lookup timed out after " + timeoutMs + "ms — fail open");
            return "";
        } catch (Exception e) {
            Log.w(TAG, "VT lookup failed: " + e.getMessage());
            return "";
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
}
