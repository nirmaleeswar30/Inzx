#!/bin/bash
# Builds Inzx for Linux and packs it as dist/Inzx-<version>-x86_64.AppImage.
# Modelled on Nivio's scripts/build_appimage.sh.
#
#   scripts/build_appimage.sh              # flutter build linux --release, then pack
#   scripts/build_appimage.sh shorebird    # shorebird release linux, then pack
#   SKIP_FLUTTER_BUILD=1 scripts/build_appimage.sh
#
# Needs: flutter, libmpv (Debian/Ubuntu: libmpv-dev), WebKitGTK 4.1
# (libwebkit2gtk-4.1-dev) with GStreamer's base plugins, python3, readelf
# (binutils), and appimagetool (downloaded on first use, or
# APPIMAGETOOL=/path).
#
# The AppImage carries its own libmpv and everything it links (FFmpeg, libass,
# ...), so a host mpv update can't change playback, and a user's ~/.config/mpv
# is never read. It also carries WebKitGTK (the YouTube Music sign-in window)
# with its helper processes and GStreamer, as Nivio does with WPE WebKit: the
# webview plugin links it, so a host without it couldn't start Inzx at all.
# Only glibc, GPU drivers, systemd/dbus/ALSA, core X11/Wayland and the
# GTK/GLib/Pango/Cairo core come from the host (Nivio's list).
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
RUNTIME_FILE="${RUNTIME_FILE:-/tmp/runtime-x86_64}"

# Build type selection (normal vs shorebird)
BUILD_TYPE="${1:-}"
EXTRA_BUILD_ARGS=()
if [[ $# -gt 0 ]]; then
  shift
  EXTRA_BUILD_ARGS=("$@")
fi

if [[ -z "$BUILD_TYPE" ]]; then
  if [ -t 0 ]; then
    echo ""
    echo "=============================================="
    echo "       Select Linux AppImage Build Type       "
    echo "=============================================="
    echo "  1) Standard Flutter Release (no Shorebird)"
    echo "  2) Shorebird Release (OTA-enabled)"
    echo "=============================================="
    read -r -p "Enter choice [1 or 2, default: 1]: " choice
    case "${choice:-1}" in
      2|shorebird)
        BUILD_TYPE="shorebird"
        ;;
      *)
        BUILD_TYPE="normal"
        ;;
    esac
  else
    BUILD_TYPE="normal"
  fi
fi

if [[ "$BUILD_TYPE" == "shorebird" ]]; then
  echo "🦅 Target: Shorebird Linux AppImage (OTA-enabled)"
  if ! command -v shorebird &>/dev/null; then
    if [ -x "$HOME/.shorebird/bin/shorebird" ]; then
      export PATH="$HOME/.shorebird/bin:$PATH"
    else
      echo "❌ Shorebird CLI was not found. Please install Shorebird (https://docs.shorebird.dev)." >&2
      exit 1
    fi
  fi
  echo "🔍 Verifying Shorebird credentials..."
  if ! shorebird apps list >/dev/null 2>&1; then
    echo "⚠️ Shorebird is not logged in or credentials have expired."
    echo "🔑 Launching 'shorebird login'..."
    shorebird login || { echo "❌ Shorebird login was unsuccessful. Aborting." >&2; exit 1; }
  fi
else
  echo "🏗️ Target: Standard Flutter Linux AppImage"
fi

if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  if [[ "$BUILD_TYPE" == "shorebird" ]]; then
    FLUTTER_VER_ARG=""
    has_custom_flutter=0
    for arg in "${EXTRA_BUILD_ARGS[@]}"; do
      if [[ "$arg" == --flutter-version* ]]; then
        has_custom_flutter=1
        break
      fi
    done

    if [ "$has_custom_flutter" -eq 0 ]; then
      EXISTING_VER=$(shorebird releases list 2>/dev/null | grep -E "\b${VERSION//+/\\+}\b" | awk '{print $NF}' | head -n 1)
      if [ -n "$EXISTING_VER" ]; then
        echo "ℹ️ Existing Shorebird release found for $VERSION (Flutter $EXISTING_VER). Matching Flutter revision..."
        FLUTTER_VER_ARG="--flutter-version=$EXISTING_VER"
      fi
    fi

    echo "==> shorebird release linux"
    shorebird release linux ${FLUTTER_VER_ARG:+"$FLUTTER_VER_ARG"} "${EXTRA_BUILD_ARGS[@]}"
  else
    echo "==> flutter build linux --release"
    flutter build linux --release "${EXTRA_BUILD_ARGS[@]}"
  fi
fi
[[ -x "$BUNDLE/inzx" ]] || { echo "No Linux bundle at $BUNDLE" >&2; exit 1; }

if [[ ! -x "$APPIMAGETOOL" ]]; then
  echo "==> Fetching appimagetool"
  curl -fL -o "$APPIMAGETOOL" "$APPIMAGETOOL_URL"
  chmod +x "$APPIMAGETOOL"
fi

if [[ ! -f "$RUNTIME_FILE" ]]; then
  echo "==> Extracting runtime from appimagetool"
  head -c 944632 "$APPIMAGETOOL" > "$RUNTIME_FILE"
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

echo "==> Bundling WebKitGTK"
# The webview plugin (YouTube Music sign-in) links WebKitGTK 4.1, so on a
# host without it Inzx didn't start at all ("libwebkit2gtk-4.1.so.0: cannot
# open shared object file"). The library and its dependencies are bundled by
# the scan below; its helper processes (WebKitWebProcess and co.) are copied
# here, and the library is pointed at them further down.
WEBKIT_LIBDIR="$(pkg-config --variable=libdir webkit2gtk-4.1 2>/dev/null || true)"
if [[ -z "$WEBKIT_LIBDIR" || ! -d "$WEBKIT_LIBDIR/webkit2gtk-4.1" ]]; then
  for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
    [[ -d "$d/webkit2gtk-4.1" ]] && { WEBKIT_LIBDIR="$d"; break; }
  done
fi
WEBKIT_HELPERS_SRC="$WEBKIT_LIBDIR/webkit2gtk-4.1"
[[ -x "$WEBKIT_HELPERS_SRC/WebKitWebProcess" ]] || {
  echo "WebKitGTK 4.1 helper processes not found (install libwebkit2gtk-4.1-dev)" >&2
  exit 1
}
# The whole helper directory, as Nivio bundles wpe-webkit-2.0.
mkdir -p "$APPDIR/lib/webkit2gtk-4.1"
cp -a "$WEBKIT_HELPERS_SRC/." "$APPDIR/lib/webkit2gtk-4.1/"
echo "    bundled WebKitGTK helper processes from $WEBKIT_HELPERS_SRC"

# GStreamer plugins and scanner (WebKitGTK links GStreamer), the whole plugin
# directory, as Nivio bundles it. Debian/Ubuntu keep the scanner elsewhere;
# it goes beside the plugins here, where AppRun looks for it.
GST_PLUGINS_SRC="$(pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || true)"
[[ -d "$GST_PLUGINS_SRC" ]] || GST_PLUGINS_SRC="$WEBKIT_LIBDIR/gstreamer-1.0"
[[ -d "$GST_PLUGINS_SRC" ]] || GST_PLUGINS_SRC="/usr/lib/gstreamer-1.0"
if [[ -d "$GST_PLUGINS_SRC" ]]; then
  mkdir -p "$APPDIR/lib/gstreamer-1.0"
  cp -a "$GST_PLUGINS_SRC/." "$APPDIR/lib/gstreamer-1.0/"
  echo "    bundled GStreamer 1.0 plugins from $GST_PLUGINS_SRC"
fi
if [[ ! -x "$APPDIR/lib/gstreamer-1.0/gst-plugin-scanner" ]]; then
  GST_SCANNER_SRC="$(pkg-config --variable=pluginscannerdir gstreamer-1.0 2>/dev/null || true)/gst-plugin-scanner"
  [[ -x "$GST_SCANNER_SRC" ]] || GST_SCANNER_SRC="$(find "$WEBKIT_LIBDIR" -name gst-plugin-scanner -type f 2>/dev/null | head -1)"
  if [[ -x "$GST_SCANNER_SRC" ]]; then
    cp -a "$GST_SCANNER_SRC" "$APPDIR/lib/gstreamer-1.0/gst-plugin-scanner"
  fi
fi

echo "==> Bundling shared libraries"
# Nivio's dependency bundler, as is: every library the AppDir's binaries,
# libraries and plugins load (HarfBuzz-ICU, ICU, XML, codecs, GStreamer,
# ...), except the few that must come from the host.
APPDIR="$APPDIR" python3 - <<'PY'
import os, subprocess, re, shutil

appdir = os.environ.get("APPDIR")
libdir = os.path.join(appdir, "lib")

# Fundamental host / graphics driver / desktop libraries that MUST come from host OS
SYSTEM_EXCLUDES = (
    # glibc
    "libc.so", "libm.so", "libpthread.so", "libdl.so", "librt.so", "ld-linux",
    # GPU / DRM / Display hardware drivers
    "libGL.so", "libGLX.so", "libEGL.so", "libGLdispatch.so", "libdrm.so", "libgbm.so", "libvulkan.so",
    # Low-level system & audio hardware daemons
    "libsystemd.so", "libudev.so", "libdbus-1.so", "libasound.so",
    # X11 / Wayland core client protocols
    "libX11.so", "libX11-xcb.so", "libXau.so", "libXdmcp.so", "libXext.so", "libXfixes.so", "libXi.so", "libXrender.so",
    "libxcb", "libwayland-client.so", "libwayland-server.so", "libwayland-cursor.so", "libwayland-egl.so",
    # GTK / GLib core runtime (host themes & desktop settings)
    "libgtk-3.so", "libgdk-3.so", "libgdk_pixbuf-2.0.so",
    "libgio-2.0.so", "libglib-2.0.so", "libgobject-2.0.so", "libgmodule-2.0.so",
    "libpango-1.0.so", "libpangocairo-1.0.so", "libpangoft2-1.0.so", "libcairo.so", "libcairo-gobject.so"
)

def is_excluded(soname):
    return any(soname.startswith(prefix) for prefix in SYSTEM_EXCLUDES)

targets = []
# Find all ELF binaries and libraries in AppDir
for root, dirs, files in os.walk(appdir):
    for f in files:
        p = os.path.join(root, f)
        if not os.path.islink(p):
            try:
                with open(p, "rb") as fp:
                    if fp.read(4) == b"\x7fELF":
                        targets.append(p)
            except:
                pass

to_copy = {}
to_inspect = list(targets)
visited = set()

while to_inspect:
    curr = to_inspect.pop(0)
    if curr in visited:
        continue
    visited.add(curr)
    try:
        out = subprocess.check_output(["ldd", curr], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            m = re.search(r'^\s*([^\s]+)\s+=>\s+([^\s]+)\s+\(', line)
            if m:
                soname, realpath = m.group(1), m.group(2)
                if is_excluded(soname):
                    continue
                if not os.path.isfile(realpath):
                    continue
                if realpath.startswith(("/usr/lib", "/lib", "/usr/local/lib")):
                    dest = os.path.join(libdir, soname)
                    if not os.path.exists(dest) and soname not in to_copy:
                        to_copy[soname] = realpath
                        to_inspect.append(realpath)
    except Exception as e:
        pass

copied_count = 0
for soname, realpath in to_copy.items():
    dest = os.path.join(libdir, soname)
    try:
        shutil.copy2(realpath, dest)
        copied_count += 1
    except Exception as e:
        print(f"    could not copy {soname}: {e}")

print(f"    bundled {copied_count} runtime shared libraries (including HarfBuzz-ICU, codecs, GStreamer)")
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

echo "==> Pointing WebKitGTK at its bundled helper processes"
# WebKitGTK finds its helper processes and injected bundle at a directory
# compiled into the library, and (outside developer builds) ignores any
# override. As Nivio does for WPE WebKit, the bundled copy's path is
# rewritten to a short fixed one under /tmp, which AppRun links to this
# AppImage's helpers. Keep WEBKIT_HELPERS in AppRun in step with this.
WEBKIT_HELPERS_LINK="/tmp/inzx-webkitgtk"
APPDIR="$APPDIR" OLD="$WEBKIT_HELPERS_SRC" NEW="$WEBKIT_HELPERS_LINK" python3 - <<'PY'
import glob, os, sys

old, new = os.environ["OLD"].encode(), os.environ["NEW"].encode()
if len(new) > len(old):
    sys.exit(f"helper path {new!r} is longer than the compiled-in {old!r}")
pairs = [
    (old + b"\0", new + b"\0" * (len(old) - len(new) + 1)),
    (old + b"/injected-bundle/\0",
     new + b"/injected-bundle/\0" + b"\0" * (len(old) - len(new))),
]
patched = 0
for path in glob.glob(os.path.join(os.environ["APPDIR"], "lib", "libwebkit2gtk-4.1.so*")):
    if os.path.islink(path):
        continue
    data = open(path, "rb").read()
    for before, after in pairs:
        if data.count(before) != 1:
            sys.exit(f"{os.path.basename(path)}: expected {before!r} once, found {data.count(before)}")
        data = data.replace(before, after)
    open(path, "wb").write(data)
    patched += 1
if patched != 1:
    sys.exit(f"expected one bundled libwebkit2gtk-4.1, patched {patched}")
print(f"    {old.decode()} -> {new.decode()}")
PY

echo "==> Icon, desktop entry, AppRun"
ICON="$ROOT/assets/logo_transparent.png"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps" "$APPDIR/usr/share/icons/hicolor/512x512/apps" "$APPDIR/usr/share/applications"
cp "$ICON" "$APPDIR/inzx.png"
cp "$ICON" "$APPDIR/.DirIcon"
cp "$ICON" "$APPDIR/usr/share/icons/hicolor/256x256/apps/inzx.png"
cp "$ICON" "$APPDIR/usr/share/icons/hicolor/512x512/apps/inzx.png"
cp "$ROOT/linux/inzx.desktop" "$APPDIR/inzx.desktop"
cp "$ROOT/linux/inzx.desktop" "$APPDIR/usr/share/applications/inzx.desktop"

cat >"$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

# A launch carrying an inzx:// link (shared link redirect) is usually a
# short-lived second instance that only forwards the link to the running Inzx
# and exits, so it must not touch shared state or show dialogs.
URL_LAUNCH=0
for arg in "$@"; do
  case "$arg" in
    inzx://*|https://inzx.nirmaleeswar.dev/*) URL_LAUNCH=1 ;;
  esac
done

# --- Desktop Integration & CLI Options ---
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP_FILE="$XDG_DATA_HOME/applications/inzx.desktop"
ICON_DIR="$XDG_DATA_HOME/icons/hicolor"
APPLICATIONS_DIR="$HOME/Applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/inzx"
NO_INTEGRATE_FLAG="$CONFIG_DIR/.no_integrate"

install_desktop() {
  local appimage_src="${APPIMAGE:-}"
  local target_exec=""

  mkdir -p "$XDG_DATA_HOME/applications"
  mkdir -p "$ICON_DIR/512x512/apps"
  mkdir -p "$ICON_DIR/256x256/apps"

  # Copy icon to standard icon locations
  if [ -f "$HERE/inzx.png" ]; then
    cp -f "$HERE/inzx.png" "$ICON_DIR/512x512/apps/inzx.png"
    cp -f "$HERE/inzx.png" "$ICON_DIR/256x256/apps/inzx.png"
  fi

  # Determine target executable path
  if [ -n "$appimage_src" ] && [ -f "$appimage_src" ]; then
    mkdir -p "$APPLICATIONS_DIR"
    local target_appimage="$APPLICATIONS_DIR/Inzx.AppImage"
    if [ "$(readlink -f "$appimage_src")" != "$(readlink -f "$target_appimage")" ]; then
      cp -f "$appimage_src" "$target_appimage"
      chmod +x "$target_appimage"
      # Clean up source AppImage if running from Downloads, tmp, or Desktop to avoid duplicates
      case "$(readlink -f "$appimage_src")" in
        "$HOME/Downloads/"*|/tmp/*|"$HOME/Desktop/"*)
          rm -f "$appimage_src" 2>/dev/null || true
          ;;
      esac
    fi
    target_exec="$target_appimage"
  else
    target_exec="$HERE/inzx"
  fi

  cat > "$DESKTOP_FILE" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Inzx
GenericName=Music Player
Comment=Your music, beautifully unbound
Exec="$target_exec" %U
Icon=inzx
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;player;youtube;lyrics;
StartupWMClass=com.inzx.inzx
MimeType=x-scheme-handler/inzx;
StartupNotify=true
DESKTOP_EOF
  chmod +x "$DESKTOP_FILE"

  update-desktop-database "$XDG_DATA_HOME/applications" 2>/dev/null || true
  gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true
}

uninstall_desktop() {
  local target_appimage="$APPLICATIONS_DIR/Inzx.AppImage"

  rm -f "$DESKTOP_FILE"
  rm -f "$ICON_DIR/512x512/apps/inzx.png"
  rm -f "$ICON_DIR/256x256/apps/inzx.png"
  rm -f "$target_appimage"
  rm -f "$NO_INTEGRATE_FLAG"

  update-desktop-database "$XDG_DATA_HOME/applications" 2>/dev/null || true
  gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true

  echo "✓ Inzx desktop integration removed."
  exit 0
}

# Check for explicit flags
for arg in "$@"; do
  case "$arg" in
    --install)
      install_desktop
      echo "✓ Inzx installed to $APPLICATIONS_DIR/Inzx.AppImage and integrated into desktop menu."
      exit 0
      ;;
    --uninstall)
      uninstall_desktop
      ;;
  esac
done

# First-run prompt if running as an AppImage and not yet integrated
if [ "$URL_LAUNCH" = "0" ] && [ -n "${APPIMAGE:-}" ] && [ ! -f "$DESKTOP_FILE" ] && [ ! -f "$NO_INTEGRATE_FLAG" ]; then
  # If already placed in ~/Applications, integrate automatically
  if [ "$(readlink -f "$(dirname "$APPIMAGE")")" = "$(readlink -f "$APPLICATIONS_DIR")" ]; then
    install_desktop
  else
    response="no"
    if command -v python3 &>/dev/null; then
      response=$(python3 - << 'PY' 2>/dev/null
try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk

    dialog = Gtk.MessageDialog(
        modal=True,
        message_type=Gtk.MessageType.QUESTION,
        buttons=Gtk.ButtonsType.NONE,
        text="Integrate Inzx into your application menu?"
    )
    dialog.set_title("Inzx Desktop Integration")
    dialog.format_secondary_text(
        "Would you like to add Inzx to your desktop applications menu?\n\nThis will move the AppImage to ~/Applications so you can launch Inzx from your app search and pin it to your dock."
    )
    dialog.add_button("Don't Ask Again", Gtk.ResponseType.REJECT)
    dialog.add_button("Run Once", Gtk.ResponseType.NO)
    integrate_btn = dialog.add_button("Integrate", Gtk.ResponseType.YES)
    integrate_btn.get_style_context().add_class("suggested-action")
    dialog.show_all()

    res = dialog.run()
    dialog.destroy()
    while Gtk.events_pending():
        Gtk.main_iteration()

    if res == Gtk.ResponseType.YES:
        print("yes")
    elif res == Gtk.ResponseType.REJECT:
        print("never")
    else:
        print("no")
except Exception:
    print("fallback")
PY
)
    fi

    if [ "$response" = "fallback" ] || [ -z "$response" ]; then
      if command -v zenity &>/dev/null; then
        if zenity --question --title="Inzx Desktop Integration" \
          --text="Would you like to integrate Inzx into your application menu?\n\nThis will move the AppImage to ~/Applications and add it to your launcher." \
          --ok-label="Integrate" --cancel-label="Run Once" 2>/dev/null; then
          response="yes"
        else
          response="no"
        fi
      elif command -v kdialog &>/dev/null; then
        if kdialog --yesno "Would you like to integrate Inzx into your application menu?\n\nThis will move the AppImage to ~/Applications and add it to your launcher." 2>/dev/null; then
          response="yes"
        else
          response="no"
        fi
      elif [ -t 0 ]; then
        read -r -p "Would you like to integrate Inzx into your application menu? [y/N]: " cli_ans
        case "${cli_ans:-n}" in
          [yY]*) response="yes" ;;
          *) response="no" ;;
        esac
      fi
    fi

    case "$response" in
      yes)
        install_desktop
        ;;
      never)
        mkdir -p "$CONFIG_DIR"
        touch "$NO_INTEGRATE_FLAG"
        ;;
    esac
  fi
fi

export LD_LIBRARY_PATH="$HERE/lib:$HERE/lib/webkit2gtk-4.1:${LD_LIBRARY_PATH:-}"
export XDG_DATA_DIRS="$HERE/share:/usr/share:${XDG_DATA_DIRS:-}"

# WebKitGTK (the YouTube Music sign-in window) ships here, so Inzx runs where
# it isn't installed. The build pointed its compiled-in helper path at
# /tmp/inzx-webkitgtk (keep in step with WEBKIT_HELPERS_LINK in the build
# script): link that to this AppImage's helpers. A link that still works
# with this WebKit is left alone: a second launch (which hands over to the
# running Inzx and exits, taking its mount with it) must not leave the
# running one's helpers pointing at a path that's about to vanish.
WEBKIT_HELPERS=/tmp/inzx-webkitgtk
if [ ! -e "$WEBKIT_HELPERS" ] ||
  ! cmp -s "$WEBKIT_HELPERS/WebKitWebProcess" "$HERE/lib/webkit2gtk-4.1/WebKitWebProcess"; then
  if [ -L "$WEBKIT_HELPERS" ] || [ ! -e "$WEBKIT_HELPERS" ]; then
    ln -sfn "$HERE/lib/webkit2gtk-4.1" "$WEBKIT_HELPERS" 2>/dev/null || true
  fi
fi
# Configure GStreamer to use bundled plugins (as Nivio does).
export GST_PLUGIN_SYSTEM_PATH_1_0="$HERE/lib/gstreamer-1.0:${GST_PLUGIN_SYSTEM_PATH_1_0:-}"
export GST_PLUGIN_SCANNER_1_0="$HERE/lib/gstreamer-1.0/gst-plugin-scanner"

# Disable WebKit sandbox inside AppImage container (as Nivio does).
export WEBKIT_DISABLE_SANDBOX=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1

# Playback depends only on what ships here: media_kit (and Inzx's own libmpv
# users) load the bundled library, and mpv reads an empty, read-only config
# dir instead of the user's ~/.config/mpv.
export LIBMPV_LIBRARY_PATH="$HERE/lib/libmpv.so.2"
export MPV_HOME="$HERE/etc/mpv"
exec "$HERE/inzx" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "==> Packing AppImage (Version: $VERSION, Type: $BUILD_TYPE)..."
if [[ "$BUILD_TYPE" == "shorebird" ]]; then
  VERSIONED_APPIMAGE="$DIST/Inzx-Linux-Shorebird-$VERSION-x86_64.AppImage"
  GENERIC_APPIMAGE="$DIST/Inzx-Linux-Shorebird-x86_64.AppImage"
else
  VERSIONED_APPIMAGE="$DIST/Inzx-Linux-$VERSION-x86_64.AppImage"
  GENERIC_APPIMAGE="$DIST/Inzx-Linux-x86_64.AppImage"
fi

rm -f "$VERSIONED_APPIMAGE" "$GENERIC_APPIMAGE" 2>/dev/null || true

ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --runtime-file "$RUNTIME_FILE" "$APPDIR" "$VERSIONED_APPIMAGE"
chmod +x "$VERSIONED_APPIMAGE"
cp -f "$VERSIONED_APPIMAGE" "$GENERIC_APPIMAGE" 2>/dev/null || true

# Also create standard names for GitHub release / in-app updater consistency:
STANDARD_VERSIONED="$DIST/Inzx-$VERSION-x86_64.AppImage"
STANDARD_GENERIC="$DIST/Inzx-x86_64.AppImage"
if [ "$VERSIONED_APPIMAGE" != "$STANDARD_VERSIONED" ]; then
  cp -f "$VERSIONED_APPIMAGE" "$STANDARD_VERSIONED" 2>/dev/null || true
  cp -f "$VERSIONED_APPIMAGE" "$STANDARD_GENERIC" 2>/dev/null || true
fi

echo "🎉 Success! Created AppImage: $VERSIONED_APPIMAGE ($(du -h "$VERSIONED_APPIMAGE" | cut -f1))"
echo "  (Also available as: $GENERIC_APPIMAGE)"
if [ "$VERSIONED_APPIMAGE" != "$STANDARD_VERSIONED" ]; then
  echo "  (Standard release link: $STANDARD_VERSIONED)"
fi
