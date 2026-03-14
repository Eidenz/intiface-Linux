#!/bin/bash
set -euo pipefail

# Build AppImage for Intiface Central
# Usage: ./packaging/build-appimage.sh [version]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-3.0.2}"
ARCH="x86_64"
BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
PKG_NAME="intiface-central"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: Build bundle not found at $BUNDLE_DIR"
    echo "Run 'flutter build linux --release' first."
    exit 1
fi

# Download appimagetool if needed
APPIMAGETOOL="$PROJECT_DIR/build/appimagetool"
if [ ! -x "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool..."
    curl -fSL -o "$APPIMAGETOOL" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

# Create AppDir structure
APPDIR="$PROJECT_DIR/build/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/share/metainfo"

# Copy entire bundle as-is (binary expects lib/ and data/ as siblings)
cp -a "$BUNDLE_DIR" "$APPDIR/app"

# Desktop file
cat > "$APPDIR/com.nonpolynomial.intiface_central.desktop" << EOF
[Desktop Entry]
Name=Intiface Central
Exec=intiface-central
Type=Application
Icon=com.nonpolynomial.intiface_central
Categories=Utility
X-AppImage-Version=${VERSION}
EOF
cp "$APPDIR/com.nonpolynomial.intiface_central.desktop" \
    "$APPDIR/usr/share/applications/"

# Icons
cp "$PROJECT_DIR/assets/icons/intiface_central_icon.png" \
    "$APPDIR/com.nonpolynomial.intiface_central.png"
cp "$PROJECT_DIR/assets/icons/intiface_central_icon.png" \
    "$APPDIR/usr/share/icons/hicolor/256x256/apps/com.nonpolynomial.intiface_central.png"
cp "$PROJECT_DIR/assets/icons/intiface_central_icon.svg" \
    "$APPDIR/usr/share/icons/hicolor/scalable/apps/com.nonpolynomial.intiface_central.svg"

# Metainfo
cp "$PROJECT_DIR/linux/com.nonpolynomial.intiface_central.metainfo.xml" \
    "$APPDIR/usr/share/metainfo/"

# AppRun script
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
SELF="$(readlink -f "$0")"
APPDIR="${SELF%/*}"
export LD_LIBRARY_PATH="${APPDIR}/app/lib:${LD_LIBRARY_PATH:-}"
cd "${APPDIR}/app"
exec "${APPDIR}/app/intiface_central" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Build AppImage
OUTPUT="$PROJECT_DIR/build/Intiface_Central-${VERSION}-${ARCH}.AppImage"
ARCH="$ARCH" "$APPIMAGETOOL" "$APPDIR" "$OUTPUT"

echo ""
echo "AppImage built successfully:"
echo "  $(basename "$OUTPUT")"
echo "  Location: $OUTPUT"
echo ""
echo "Run with: chmod +x $OUTPUT && $OUTPUT"
