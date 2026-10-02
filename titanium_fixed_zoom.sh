#!/bin/bash
# Titanium Browser: fixed web-page zoom by Android display mode.
#
# Smartphone / normal Android: 100% (Chromium zoom level 0.00)
# Android desktop mode (including Samsung DeX): 67% (Chromium zoom level -2.20)
#
# The zoom is selected at runtime from Android's UI_MODE_TYPE_DESK value.

set -e

ZOOM_IMPL="content/public/android/java/src/org/chromium/content/browser/HostZoomMapImpl.java"

python3 - "$ZOOM_IMPL" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "Titanium fixed DeX zoom" in text:
    raise SystemExit("Titanium fixed DeX zoom patch is already applied")

package = "package org.chromium.content.browser;\n"
imports = (
    package
    + "\n"
    + "import android.content.res.Configuration;\n"
    + "import android.content.res.Resources;\n"
)

if package not in text:
    raise SystemExit("Expected Chromium package declaration was not found")

text = text.replace(package, imports, 1)

pattern = re.compile(
    r"(?ms)(    @CalledByNative\s+"
    r"public static double getAdjustedZoomLevel\(double zoomLevel\)\s*\{)"
    r".*?"
    r"(\n    \})"
)

replacement = r"""\1
        // Titanium fixed DeX zoom: 67% in Android desktop mode,
        // 100% on normal smartphone/tablet mode.
        int uiModeType =
                Resources.getSystem().getConfiguration().uiMode
                        & Configuration.UI_MODE_TYPE_MASK;
        if (uiModeType == Configuration.UI_MODE_TYPE_DESK) {
            return -2.20;
        }
        return 0.00;\2"""

text, count = pattern.subn(replacement, text, count=1)

if count != 1:
    raise SystemExit("Expected Chromium getAdjustedZoomLevel method was not found")

path.write_text(text)
PY
