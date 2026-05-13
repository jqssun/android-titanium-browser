// Copyright 2025 Helium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

// STEP 2 — PREF REGISTRATION
// In chrome/browser/prefs/browser_prefs.cc, inside RegisterProfilePrefs():
//   registry->RegisterDictionaryPref("helium.vt_scan_cache");

#ifndef CHROME_BROWSER_EXTENSIONS_VT_EXTENSION_SCANNER_H_
#define CHROME_BROWSER_EXTENSIONS_VT_EXTENSION_SCANNER_H_

#include <string>
#include "base/files/file_path.h"
#include "chrome/browser/profiles/profile.h"

namespace extensions {

enum class VtRiskLevel {
  kClean,    // 0 detections — silent pass
  kLowRisk,  // 1-2 detections — warn, allow proceed
  kHighRisk, // 3+ detections — block, require override
  kUnknown,  // Hash not in VT database
  kOffline,  // Network unavailable or timeout — fail open
};

struct VtScanResult {
  VtRiskLevel risk_level = VtRiskLevel::kOffline;
  std::string sha256;
  int detection_count = 0;
  int total_engines = 0;
  std::string permalink;  // VT report URL for user-facing dialog
};

// Performs a synchronous (blocking) VirusTotal hash lookup.
// Must be called from a background thread (MayBlock()).
// Only the SHA-256 hash is transmitted — no file content leaves the device.
class VtExtensionScanner {
 public:
  explicit VtExtensionScanner(Profile* profile);
  ~VtExtensionScanner() = default;

  // Computes SHA-256 of |crx_path|, checks local prefs cache,
  // and if not cached performs a VT API v3 hash lookup.
  // Timeout: 3 seconds. On timeout returns kOffline (fail-open).
  VtScanResult ScanBlocking(const base::FilePath& crx_path);

 private:
  std::string ComputeSha256(const base::FilePath& path);
  VtScanResult CheckCache(const std::string& sha256);
  void WriteCache(const VtScanResult& result);
  VtScanResult QueryVirusTotal(const std::string& sha256);

  Profile* profile_;  // Not owned.

  // VT API key injected at build time via GN arg: helium_vt_api_key
  // Set in args.gn: helium_vt_api_key = "YOUR_FREE_VT_API_KEY"
  static constexpr char kVtApiBase[] =
      "https://www.virustotal.com/api/v3/files/";
};

}  // namespace extensions

#endif  // CHROME_BROWSER_EXTENSIONS_VT_EXTENSION_SCANNER_H_
