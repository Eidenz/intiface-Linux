#!/bin/bash
set -euo pipefail

# Build RPM package for Intiface Central
# Usage: ./packaging/build-rpm.sh [version]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-3.0.2}"
RELEASE="1"
ARCH="x86_64"
BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
PKG_NAME="intiface-central"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: Build bundle not found at $BUNDLE_DIR"
    echo "Run 'flutter build linux --release' first."
    exit 1
fi

# Check for rpmbuild
if ! command -v rpmbuild &> /dev/null; then
    echo "Installing rpm-build..."
    sudo dnf install -y rpm-build
fi

# Setup RPM build tree
RPM_TOPDIR="$PROJECT_DIR/build/rpmbuild"
rm -rf "$RPM_TOPDIR"
mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Create tarball for rpmbuild
TARBALL_DIR="$RPM_TOPDIR/SOURCES/${PKG_NAME}-${VERSION}"
mkdir -p "$TARBALL_DIR"
cp -a "$BUNDLE_DIR"/. "$TARBALL_DIR/"
cp "$PROJECT_DIR/linux/com.nonpolynomial.intiface_central.desktop" "$TARBALL_DIR/"
cp "$PROJECT_DIR/linux/com.nonpolynomial.intiface_central.metainfo.xml" "$TARBALL_DIR/"
cp "$PROJECT_DIR/assets/icons/intiface_central_icon.png" "$TARBALL_DIR/"
cp "$PROJECT_DIR/assets/icons/intiface_central_icon.svg" "$TARBALL_DIR/"

# Strip invalid RPATHs from shared libraries (Flutter bakes in build-time paths)
if command -v patchelf &> /dev/null; then
    find "$TARBALL_DIR" -name "*.so" -o -name "*.so.*" | while read -r lib; do
        patchelf --remove-rpath "$lib" 2>/dev/null || true
    done
    # Also fix crashpad_handler
    patchelf --remove-rpath "$TARBALL_DIR/crashpad_handler" 2>/dev/null || true
    for f in "$TARBALL_DIR/lib/crashpad_handler" "$TARBALL_DIR/lib/"*.so "$TARBALL_DIR/lib/"*.so.*; do
        [ -f "$f" ] && patchelf --remove-rpath "$f" 2>/dev/null || true
    done
else
    echo "WARNING: patchelf not found. Install with: sudo dnf install patchelf"
    echo "RPATHs will not be cleaned, RPM build may fail."
fi

cd "$RPM_TOPDIR/SOURCES"
tar czf "${PKG_NAME}-${VERSION}.tar.gz" "${PKG_NAME}-${VERSION}"
rm -rf "${PKG_NAME}-${VERSION}"

# Write spec file
cat > "$RPM_TOPDIR/SPECS/${PKG_NAME}.spec" << 'SPECEOF'
Name:           intiface-central
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Intiface Central - Intimate Device Control Hub
License:        BSD-3-Clause
URL:            https://intiface.com
Source0:        %{name}-%{version}.tar.gz

AutoReqProv:    no

%global debug_package %{nil}

Requires:       gtk3
Requires:       libayatana-appindicator-gtk3

%description
Intiface Central is a hub for connecting intimate hardware
to applications. It provides a graphical interface for managing
device connections and server settings.

%prep
%setup -q

%install
# Application files
install -d %{buildroot}/opt/%{name}
cp -a intiface_central %{buildroot}/opt/%{name}/
cp -a lib %{buildroot}/opt/%{name}/
cp -a data %{buildroot}/opt/%{name}/
install -m 755 crashpad_handler %{buildroot}/opt/%{name}/ 2>/dev/null || true

# Launcher script
install -d %{buildroot}%{_bindir}
cat > %{buildroot}%{_bindir}/intiface-central << 'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/opt/intiface-central/lib:${LD_LIBRARY_PATH:-}
cd /opt/intiface-central
exec ./intiface_central "$@"
EOF
chmod 755 %{buildroot}%{_bindir}/intiface-central

# Desktop file (fix Exec path for system install)
install -Dm644 com.nonpolynomial.intiface_central.desktop \
    %{buildroot}%{_datadir}/applications/com.nonpolynomial.intiface_central.desktop
sed -i 's|Exec=run_intiface_central|Exec=intiface-central|' \
    %{buildroot}%{_datadir}/applications/com.nonpolynomial.intiface_central.desktop

# AppStream metainfo
install -Dm644 com.nonpolynomial.intiface_central.metainfo.xml \
    %{buildroot}%{_datadir}/metainfo/com.nonpolynomial.intiface_central.metainfo.xml

# Icons
install -Dm644 intiface_central_icon.png \
    %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/com.nonpolynomial.intiface_central.png
install -Dm644 intiface_central_icon.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/com.nonpolynomial.intiface_central.svg

%files
/opt/%{name}
%{_bindir}/intiface-central
%{_datadir}/applications/com.nonpolynomial.intiface_central.desktop
%{_datadir}/metainfo/com.nonpolynomial.intiface_central.metainfo.xml
%{_datadir}/icons/hicolor/256x256/apps/com.nonpolynomial.intiface_central.png
%{_datadir}/icons/hicolor/scalable/apps/com.nonpolynomial.intiface_central.svg

%post
update-desktop-database %{_datadir}/applications &>/dev/null || true
gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || true

%postun
update-desktop-database %{_datadir}/applications &>/dev/null || true
gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || true
SPECEOF

# Build RPM (QA_RPATHS allows empty rpaths from bundled crashpad)
QA_RPATHS=$((0x0002|0x0010)) rpmbuild --define "_topdir $RPM_TOPDIR" \
         --define "pkg_version $VERSION" \
         --define "pkg_release $RELEASE" \
         -bb "$RPM_TOPDIR/SPECS/${PKG_NAME}.spec"

# Copy result
RPM_FILE=$(find "$RPM_TOPDIR/RPMS" -name "*.rpm" -type f | head -1)
if [ -n "$RPM_FILE" ]; then
    cp "$RPM_FILE" "$PROJECT_DIR/build/"
    echo ""
    echo "RPM package built successfully:"
    echo "  $(basename "$RPM_FILE")"
    echo "  Location: $PROJECT_DIR/build/$(basename "$RPM_FILE")"
    echo ""
    echo "Install with: sudo dnf install $PROJECT_DIR/build/$(basename "$RPM_FILE")"
fi
