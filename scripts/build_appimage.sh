#!/bin/bash
# Builds Inzx for Linux and packs it as dist/Inzx-<version>-x86_64.AppImage.
# Modelled on Nivio's scripts/build_appimage.sh.
#
#   scripts/build_appimage.sh              # flutter build linux --release, then pack
#   SKIP_FLUTTER_BUILD=1 scripts/build_appimage.sh
#
# Needs: flutter, libmpv (Debian/Ubuntu: libmpv-dev), python3, readelf
# (binutils), and appimagetool (downloaded on first use, or
# APPIMAGETOOL=/path).
#
# The AppImage carries its own libmpv and everything it links (FFmpeg, libass,
# ...), so a host mpv update can't change playback, and a user's ~/.config/mpv
# is never read. GPU drivers, glibc, X11/Wayland, GTK and WebKitGTK (the
# YouTube Music sign-in window) come from the host, as they must.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/version:[[:space:]]*//; s/\+.*//')"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APPDIR="$ROOT/build/appimage/Inzx.AppDir"
DIST="$ROOT/dist"
OUT="$DIST/Inzx-$VERSION-x86_64.AppImage"
APPIMAGETOOL="${APPIMAGETOOL:-/tmp/appimagetool-x86_64.AppImage}"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  echo "==> flutter build linux --release"
  flutter build linux --release
fi
[[ -x "$BUNDLE/inzx" ]] || { echo "No Linux bundle at $BUNDLE" >&2; exit 1; }

if [[ ! -x "$APPIMAGETOOL" ]]; then
  echo "==> Fetching appimagetool"
  curl -fL -o "$APPIMAGETOOL" "$APPIMAGETOOL_URL"
  chmod +x "$APPIMAGETOOL"
fi

echo "==> Staging $APPDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR" "$DIST"
cp -a "$BUNDLE/." "$APPDIR/"
mkdir -p "$APPDIR/lib"

echo "==> Bundling libmpv"
# media_kit tries "libmpv.so" before "libmpv.so.2", which on many distros is
# the host's library; both names point into the bundle instead.
find_libmpv() {
  if [[ -n "${LIBMPV_SOURCE:-}" ]]; then echo "$LIBMPV_SOURCE"; return; fi
  local c
  c="$(ldconfig -p 2>/dev/null | awk '/libmpv\.so\.2 .*x86-64/ {print $NF; exit}')"
  if [[ -n "$c" && -e "$c" ]]; then echo "$c"; return; fi
  for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib /usr/local/lib; do
    [[ -e "$d/libmpv.so.2" ]] && { echo "$d/libmpv.so.2"; return; }
  done
}
LIBMPV_SRC="$(find_libmpv || true)"
[[ -n "$LIBMPV_SRC" && -e "$LIBMPV_SRC" ]] || { echo "libmpv.so.2 not found (install libmpv-dev or set LIBMPV_SOURCE)" >&2; exit 1; }
LIBMPV_REAL="$(readlink -f "$LIBMPV_SRC")"
cp -f "$LIBMPV_REAL" "$APPDIR/lib/$(basename "$LIBMPV_REAL")"
[[ "$(basename "$LIBMPV_REAL")" == "libmpv.so.2" ]] || ln -sf "$(basename "$LIBMPV_REAL")" "$APPDIR/lib/libmpv.so.2"
ln -sf libmpv.so.2 "$APPDIR/lib/libmpv.so"
mkdir -p "$APPDIR/etc/mpv"   # empty MPV_HOME, see AppRun

echo "==> Bundling shared libraries"
APPDIR="$APPDIR" python3 - <<'PY'
import os, re, shutil, subprocess

appdir = os.environ["APPDIR"]
libdir = os.path.join(appdir, "lib")
# From the host, always: glibc, GPU/display drivers, audio and session
# daemons, X11/Wayland, the GTK/GLib stack (themes, settings) and WebKitGTK
# (its helper processes live at fixed host paths), plus the low-level
# libraries the AppImage project's excludelist keeps on the host: the C++
# runtime, compression, TLS and the like. They are ABI-stable, and a copy
# from the (older) build host would be loaded by the host's own GTK and
# WebKit too, through LD_LIBRARY_PATH, which also reaches WebKit's helper
# processes.
HOST = (
    "libc.so", "libm.so", "libmvec.so", "libpthread.so", "libdl.so", "librt.so", "ld-linux",
    "libresolv.so", "libutil.so", "libanl.so", "libnss_", "libBrokenLocale.so", "libthread_db.so",
    "libstdc++.so", "libgcc_s.so", "libatomic.so", "libgomp.so",
    "libGL.so", "libGLX.so", "libEGL.so", "libGLdispatch.so", "libOpenGL.so", "libdrm.so", "libgbm.so",
    "libvulkan.so", "libglapi.so", "libepoxy.so", "libOpenCL.so", "libva.so", "libva-drm.so",
    "libva-x11.so", "libva-wayland.so", "libvdpau.so",
    "libsystemd.so", "libudev.so", "libdbus-1.so", "libasound.so", "libpulse", "libpipewire", "libjack.so",
    "libX11.so", "libX11-xcb.so", "libXau.so", "libXdmcp.so", "libXext.so", "libXfixes.so", "libXi.so",
    "libXrender.so", "libXrandr.so", "libXcursor.so", "libXinerama.so", "libXcomposite.so",
    "libXdamage.so", "libXss.so", "libXv.so", "libXpresent.so", "libXtst.so", "libICE.so", "libSM.so",
    "libxcb", "libwayland-", "libxkbcommon",
    "libgtk-3.so", "libgdk-3.so", "libgdk_pixbuf-2.0.so", "libgio-2.0.so", "libglib-2.0.so",
    "libgobject-2.0.so", "libgmodule-2.0.so", "libgthread-2.0.so", "libpango", "libcairo", "libatk",
    "libatspi.so", "libharfbuzz", "libfontconfig.so", "libfreetype.so", "libfribidi.so", "libthai.so",
    "libdatrie.so", "libgraphite2.so", "libpixman-1.so", "libpng16.so",
    "libwebkit2gtk", "libjavascriptcoregtk", "libsoup-", "libsecret-1.so", "libgst",
    "libz.so", "libexpat.so", "libffi.so", "libpcre2-", "libmount.so", "libblkid.so", "libuuid.so",
    "libselinux.so", "libcom_err.so", "libgpg-error.so", "libgcrypt.so", "libkeyutils.so",
    "libgnutls.so", "libnettle.so", "libhogweed.so", "libgmp.so", "libtasn1.so", "libp11-kit.so",
    "libidn2.so", "libunistring.so", "libgssapi_krb5.so", "libkrb5", "libk5crypto.so",
)
host = lambda soname: soname.startswith(HOST)

def needed(path):
    """The DT_NEEDED entries of an ELF file: its direct dependencies only."""
    try:
        out = subprocess.check_output(["readelf", "-dW", path], stderr=subprocess.DEVNULL).decode()
    except subprocess.CalledProcessError:
        return []
    return re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", out)

def resolved(path):
    """Where the dynamic linker finds each library [path] loads."""
    try:
        out = subprocess.check_output(["ldd", path], stderr=subprocess.DEVNULL, env={**os.environ, "LD_LIBRARY_PATH": libdir}).decode()
    except subprocess.CalledProcessError:
        return {}
    return dict(re.findall(r"^\s*(\S+)\s+=>\s+(\S+)\s+\(", out, re.M))

# Walk direct dependencies only: a library reached solely through a host
# library (GTK's, WebKit's) is the host's business and must not be copied.
todo, seen, copy = [], set(), {}
for root, _, files in os.walk(appdir):
    for f in files:
        path = os.path.join(root, f)
        if os.path.islink(path):
            continue
        try:
            with open(path, "rb") as fh:
                if fh.read(4) == b"\x7fELF":
                    todo.append(path)
        except OSError:
            pass
while todo:
    cur = todo.pop()
    if cur in seen:
        continue
    seen.add(cur)
    where = resolved(cur)
    for soname in needed(cur):
        real = where.get(soname)
        if host(soname) or not real or not os.path.isfile(real) or real.startswith(appdir):
            continue
        if soname not in copy and not os.path.exists(os.path.join(libdir, soname)):
            copy[soname] = real
            todo.append(real)
for soname, real in copy.items():
    shutil.copy2(real, os.path.join(libdir, soname))
print(f"    bundled {len(copy)} libraries")
PY

# Everything libmpv decodes with must resolve inside the AppDir.
MPV_LDD="$(LD_LIBRARY_PATH="$APPDIR/lib" ldd "$APPDIR/lib/libmpv.so.2" 2>&1 || true)"
if grep -q "not found" <<<"$MPV_LDD"; then
  echo "Bundled libmpv has unresolved dependencies:" >&2
  grep "not found" <<<"$MPV_LDD" >&2
  exit 1
fi
for dep in libavcodec libavformat libavutil libswscale libswresample libass; do
  p="$(awk -v d="$dep" '$1 ~ "^"d"\\.so" {print $3; exit}' <<<"$MPV_LDD")"
  if [[ -n "$p" && "$p" != "$APPDIR/lib/"* ]]; then
    echo "libmpv dependency $dep resolves outside the AppDir ($p)" >&2
    exit 1
  fi
done

echo "==> Icon, desktop entry, AppRun"
ICON="$ROOT/assets/icon/logo_dark.png"
mkdir -p "$APPDIR/usr/share/icons/hicolor/512x512/apps" "$APPDIR/usr/share/applications"
cp "$ICON" "$APPDIR/inzx.png"
cp "$ICON" "$APPDIR/.DirIcon"
cp "$ICON" "$APPDIR/usr/share/icons/hicolor/512x512/apps/inzx.png"
cp "$ROOT/linux/inzx.desktop" "$APPDIR/inzx.desktop"
cp "$ROOT/linux/inzx.desktop" "$APPDIR/usr/share/applications/inzx.desktop"

cat >"$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
# Playback depends only on what ships here: media_kit (and Inzx's own libmpv
# users) load the bundled library, and mpv reads an empty, read-only config
# dir instead of the user's ~/.config/mpv.
export LIBMPV_LIBRARY_PATH="$HERE/lib/libmpv.so.2"
export MPV_HOME="$HERE/etc/mpv"
exec "$HERE/inzx" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "==> Packing $OUT"
rm -f "$OUT"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$OUT"
echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
