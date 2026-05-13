// Copyright 2025 Helium Authors. All rights reserved.

// STEP 2 — PREF REGISTRATION REMINDER
// Before building, add to chrome/browser/prefs/browser_prefs.cc
// inside RegisterProfilePrefs():
//
//   registry->RegisterDictionaryPref("helium.vt_scan_cache");
//
// Also add to chrome/browser/extensions/BUILD.gn sources:
//   "vt_extension_scanner.cc",
//   "vt_extension_scanner.h",

#include "chrome/browser/extensions/vt_extension_scanner.h"

#include "base/files/file_util.h"
#include "base/json/json_reader.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/stringprintf.h"
#include "chrome/browser/profiles/profile.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "crypto/sha2.h"

// GN build arg: helium_vt_api_key
// Default empty string disables VT lookup (kOffline for all installs).
#ifndef HELIUM_VT_API_KEY
#define HELIUM_VT_API_KEY ""
#endif

namespace extensions {

namespace {
constexpr char kVtCachePref[] = "helium.vt_scan_cache";
constexpr int64_t kCacheTtlSeconds = 7 * 24 * 3600;  // 7 days
constexpr int kTimeoutSeconds = 3;
}  // namespace

VtExtensionScanner::VtExtensionScanner(Profile* profile)
    : profile_(profile) {}

VtScanResult VtExtensionScanner::ScanBlocking(
    const base::FilePath& crx_path) {
  std::string sha256 = ComputeSha256(crx_path);
  if (sha256.empty())
    return VtScanResult{VtRiskLevel::kOffline};

  VtScanResult cached = CheckCache(sha256);
  if (!cached.sha256.empty())
    return cached;

  if (std::string(HELIUM_VT_API_KEY).empty())
    return VtScanResult{VtRiskLevel::kOffline, sha256};

  VtScanResult result = QueryVirusTotal(sha256);

  if (result.risk_level != VtRiskLevel::kOffline)
    WriteCache(result);

  return result;
}

std::string VtExtensionScanner::ComputeSha256(
    const base::FilePath& path) {
  std::string contents;
  if (!base::ReadFileToString(path, &contents))
    return std::string();
  std::array<uint8_t, crypto::kSHA256Length> hash =
      crypto::SHA256Hash(base::as_byte_span(contents));
  return base::HexEncode(hash);
}

VtScanResult VtExtensionScanner::CheckCache(const std::string& sha256) {
  const base::Value::Dict& cache =
      profile_->GetPrefs()->GetDict(kVtCachePref);
  const base::Value::Dict* entry = cache.FindDict(sha256);
  if (!entry) return VtScanResult{VtRiskLevel::kOffline};

  std::optional<double> ts = entry->FindDouble("timestamp");
  if (!ts) return VtScanResult{VtRiskLevel::kOffline};
  double age = base::Time::Now().InSecondsFSinceUnixEpoch() - *ts;
  if (age > kCacheTtlSeconds) return VtScanResult{VtRiskLevel::kOffline};

  VtScanResult r;
  r.sha256          = sha256;
  r.detection_count = entry->FindInt("detections").value_or(0);
  r.total_engines   = entry->FindInt("total").value_or(0);
  const std::string* pl = entry->FindString("permalink");
  r.permalink       = pl ? *pl : "";
  int rl = entry->FindInt("risk_level")
               .value_or(static_cast<int>(VtRiskLevel::kOffline));
  r.risk_level = static_cast<VtRiskLevel>(rl);
  return r;
}

void VtExtensionScanner::WriteCache(const VtScanResult& result) {
  ScopedDictPrefUpdate update(profile_->GetPrefs(), kVtCachePref);
  base::Value::Dict entry;
  entry.Set("risk_level", static_cast<int>(result.risk_level));
  entry.Set("detections", result.detection_count);
  entry.Set("total",      result.total_engines);
  entry.Set("permalink",  result.permalink);
  entry.Set("timestamp",  base::Time::Now().InSecondsFSinceUnixEpoch());
  update->Set(result.sha256, std::move(entry));
}

VtScanResult VtExtensionScanner::QueryVirusTotal(
    const std::string& sha256) {
  VtScanResult result;
  result.sha256 = sha256;

  std::string url = std::string(kVtApiBase) + sha256;

  // Synchronous HTTP GET via Android JNI bridge (VtExtensionScanner.java).
  std::string json_response =
      VtJniBridge::GetBlocking(url, HELIUM_VT_API_KEY, kTimeoutSeconds);

  if (json_response.empty()) {
    result.risk_level = VtRiskLevel::kOffline;
    return result;
  }

  auto parsed = base::JSONReader::Read(json_response);
  if (!parsed || !parsed->is_dict()) {
    result.risk_level = VtRiskLevel::kUnknown;
    return result;
  }

  const base::Value::Dict& root = parsed->GetDict();

  // 404 sentinel from Java layer
  if (root.FindBool("not_found").value_or(false)) {
    result.risk_level = VtRiskLevel::kUnknown;
    return result;
  }

  const base::Value::Dict* data  = root.FindDict("data");
  const base::Value::Dict* attrs = data ? data->FindDict("attributes") : nullptr;
  const base::Value::Dict* stats =
      attrs ? attrs->FindDict("last_analysis_stats") : nullptr;

  if (!stats) {
    result.risk_level = VtRiskLevel::kUnknown;
    return result;
  }

  result.detection_count = stats->FindInt("malicious").value_or(0) +
                           stats->FindInt("suspicious").value_or(0);
  result.total_engines   = stats->FindInt("harmless").value_or(0)  +
                           stats->FindInt("malicious").value_or(0) +
                           stats->FindInt("suspicious").value_or(0) +
                           stats->FindInt("undetected").value_or(0);

  const std::string* link = data->FindString("links.self");
  result.permalink = link ? *link : "";

  if      (result.detection_count == 0) result.risk_level = VtRiskLevel::kClean;
  else if (result.detection_count <= 2) result.risk_level = VtRiskLevel::kLowRisk;
  else                                   result.risk_level = VtRiskLevel::kHighRisk;

  return result;
}

}  // namespace extensions
