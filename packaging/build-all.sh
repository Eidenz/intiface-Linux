#!/bin/bash
set -euo pipefail

# Full build pipeline for Intiface Central on Fedora/Nobara
# Builds Flutter+Rust, applies patches, and packages as RPM + AppImage
# Usage: ./packaging/build-all.sh [version]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-3.0.2}"

export JAVA_HOME=/usr/lib/jvm/java-17-temurin-jdk
export PATH="$HOME/.cargo/bin:$HOME/flutter/bin:$PATH"

echo "=== Intiface Central build pipeline v${VERSION} ==="
echo ""

# --- Check dependencies ---
echo "[1/6] Checking dependencies..."
MISSING=()
command -v flutter &>/dev/null || MISSING+=("flutter (install from https://flutter.dev)")
command -v cargo &>/dev/null   || MISSING+=("cargo/rustup (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh)")
command -v rpmbuild &>/dev/null || MISSING+=("rpm-build (sudo dnf install rpm-build)")
command -v patchelf &>/dev/null || MISSING+=("patchelf (sudo dnf install patchelf)")
pkg-config --exists gtk+-3.0 2>/dev/null || MISSING+=("gtk3-devel (sudo dnf install gtk3-devel)")
pkg-config --exists ayatana-appindicator3-0.1 2>/dev/null || MISSING+=("libayatana-appindicator-gtk3-devel (sudo dnf install libayatana-appindicator-gtk3-devel)")
[ -d "$JAVA_HOME" ] || MISSING+=("java-17-openjdk-devel or temurin-17-jdk (set JAVA_HOME)")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: Missing dependencies:"
    for dep in "${MISSING[@]}"; do
        echo "  - $dep"
    done
    exit 1
fi
echo "  All dependencies found."

# --- Apply tray_manager patches ---
echo ""
echo "[2/6] Patching tray_manager plugin..."
TRAY_DIR="$HOME/.pub-cache/hosted/pub.dev/tray_manager-0.5.2/linux"

if [ -f "$TRAY_DIR/CMakeLists.txt" ]; then
    if ! grep -q "Wno-deprecated-declarations" "$TRAY_DIR/CMakeLists.txt"; then
        sed -i '/apply_standard_settings(${PLUGIN_NAME})/a target_compile_options(${PLUGIN_NAME} PRIVATE -Wno-deprecated-declarations)' \
            "$TRAY_DIR/CMakeLists.txt"
        echo "  Patched CMakeLists.txt: added -Wno-deprecated-declarations"
    else
        echo "  CMakeLists.txt already patched."
    fi
else
    echo "  WARNING: tray_manager CMakeLists.txt not found. Run 'flutter pub get' first."
fi

if [ -f "$TRAY_DIR/tray_manager_plugin.cc" ]; then
    if ! grep -q "setToolTip" "$TRAY_DIR/tray_manager_plugin.cc"; then
        sed -i '/strcmp(method, "setContextMenu") == 0/,/^  } else {/{
            /^  } else {/i\
  } else if (strcmp(method, "setToolTip") == 0) {\
    // setToolTip is not supported by AppIndicator on Linux, silently succeed\
    response = FL_METHOD_RESPONSE(\
        fl_method_success_response_new(fl_value_new_bool(true)));
            /^  } else {/!b
        }' "$TRAY_DIR/tray_manager_plugin.cc"
        echo "  Patched tray_manager_plugin.cc: added setToolTip stub"
    else
        echo "  tray_manager_plugin.cc already patched."
    fi
else
    echo "  WARNING: tray_manager_plugin.cc not found. Run 'flutter pub get' first."
fi

# --- Flutter pub get ---
echo ""
echo "[3/6] Getting Flutter dependencies..."
cd "$PROJECT_DIR"
flutter pub get

# --- Flutter build ---
echo ""
echo "[4/6] Building Flutter + Rust (release)..."
rm -rf build/linux
flutter build linux --release

echo ""
echo "[5/6] Building RPM..."
"$SCRIPT_DIR/build-rpm.sh" "$VERSION"

echo ""
echo "[6/6] Building AppImage..."
"$SCRIPT_DIR/build-appimage.sh" "$VERSION"

echo ""
echo "=== Build complete ==="
echo ""
echo "Outputs in $PROJECT_DIR/build/:"
ls -lh "$PROJECT_DIR/build/"*.rpm "$PROJECT_DIR/build/"*.AppImage 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
