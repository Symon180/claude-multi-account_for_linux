#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Antigravity Multi Account – macOS & Linux
#  Inspired by: https://github.com/andrea6687/claude-multi-account (© Andrea Sportello)
#  Repository:  https://github.com/Symon180/claude-multi-account_for_linux
#
#  Creates a second app ("Antigravity 2") that launches Google Antigravity with
#  a separate user-data profile, so you can use two accounts side by side. It
#  also gets an icon in a different color, visible in the Dock / taskbar while
#  running. The original Antigravity app is never modified.
#
#  Usage (paste into Terminal):
#    curl -fsSL https://raw.githubusercontent.com/Symon180/claude-multi-account_for_linux/main/install-antigravity.sh | bash
#  With name and color preset:
#    curl -fsSL https://raw.githubusercontent.com/Symon180/claude-multi-account_for_linux/main/install-antigravity.sh | bash -s -- "Antigravity 2" blue
#  Remove (asks before deleting the data folder, which holds the sign-in):
#    curl -fsSL https://raw.githubusercontent.com/Symon180/claude-multi-account_for_linux/main/install-antigravity.sh | bash -s -- --uninstall "Antigravity 2"
#
#  Colors: blue, green, purple, pink, cyan, yellow, none
#          (Italian names work too: blu, verde, viola, rosa, azzurro, giallo, nessuno)
#
#  macOS:
#    Antigravity is looked for in /Applications, then in ~/Applications, then
#    anywhere on the Mac with Spotlight. To point at a specific copy:
#      curl -fsSL .../install-antigravity.sh | ANTIGRAVITY_APP="/path/to/Antigravity.app" bash
#    Data: ~/Library/Application Support/AntigravityMultiAccount/<name>/
#    Clone: ~/Library/Application Support/AntigravityMultiAccount/apps/<name>.app
#
#  Linux:
#    Antigravity is looked for in standard binary paths (/opt/Antigravity_Gemini/antigravity,
#    /usr/bin/antigravity, etc.), .desktop entries, Flatpak, and AppImages. To point at a
#    specific executable:
#      curl -fsSL .../install-antigravity.sh | ANTIGRAVITY_APP="/path/to/antigravity" bash
#    Data: ~/.config/AntigravityMultiAccount/<name>/
#    Launcher & icons: ~/.local/share/AntigravityMultiAccount/
#    Desktop entry: ~/.local/share/applications/antigravity-multi-account-<id>.desktop
# ─────────────────────────────────────────────────────────────────────────────

set -e

OS_KERNEL=$(uname -s 2>/dev/null || echo "Darwin")

if [ "$OS_KERNEL" = "Darwin" ]; then
  LINGUA=$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' "(),\n' | cut -c1-2 || true)
else
  LINGUA=$(printf '%s' "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" | tr '[:upper:]' '[:lower:]' | cut -c1-2)
fi
t() { if [ "$LINGUA" = "it" ]; then echo "$2"; else echo "$1"; fi; }
die() { t "$1" "$2"; exit 1; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

bundle_id() {
  local app="$1" id="" plist="$1/Contents/Info.plist"
  if command -v defaults >/dev/null 2>&1; then
    id=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
  fi
  if [ -z "$id" ] && [ -f "$plist" ]; then
    id=$(sed -n 's/.*<key>CFBundleIdentifier<\/key><string>\([^<]*\)<\/string>.*/\1/p' "$plist" | head -n 1 || true)
  fi
  printf '%s' "$id"
}

app_is_ours() {
  local id=""
  id=$(bundle_id "$1")
  case "$id" in
    local.antigravity-launcher.*) return 0 ;;
    *) return 1 ;;
  esac
}

is_protected() {
  local p="${1%/}"
  local xdg_cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
  case "$p" in
    ""|"/"|"$HOME"|"$HOME/Applications"|"$HOME/Desktop"|"$HOME/Library"|"$HOME/Library/Application Support"|"$HOME/Library/Application Support/AntigravityMultiAccount"|"$HOME/Library/Application Support/AntigravityMultiAccount/apps"|"$HOME/.config"|"$HOME/.local"|"$xdg_cfg"|"$xdg_data"|"$xdg_cfg/AntigravityMultiAccount"|"$xdg_data/AntigravityMultiAccount"|"$xdg_data/applications")
      return 0 ;;
    *) return 1 ;;
  esac
}

path_ok() {
  local p="${1%/}"
  [ -n "$p" ] || return 1
  [ -n "$NOME" ] || return 1
  case "$p" in
    *..*) return 1 ;;
    "$HOME"/*) ;;
    *) return 1 ;;
  esac
  if is_protected "$p"; then
    return 1
  fi
  case "$p" in
    */"$NOME"|*/"$NOME"/*|*/"$NOME.app"|*/"$NOME.app"/*) return 0 ;;
    *) return 1 ;;
  esac
}

rm_tree() {
  local target="${1%/}"
  if ! path_ok "$target"; then
    die "❌ Refusing to delete an unsafe path." "❌ Rifiuto di cancellare un percorso non sicuro."
  fi
  rm -rf -- "$target"
}

read_kv() {
  local file="$1" key="$2" k v
  [ -f "$file" ] || return 0
  while IFS='=' read -r k v || [ -n "$k" ]; do
    if [ "$k" = "$key" ]; then
      printf '%s' "$v"
      return 0
    fi
  done < "$file"
  printf '%s' ""
}

launcher_setting() {
  local app="$1" key="$2" cfg=""
  cfg="$app/Contents/Resources/config"
  if [ -f "$cfg" ]; then
    read_kv "$cfg" "$key"
    return 0
  fi
}

copy_running() {
  local needle="$1"
  [ -n "$needle" ] || return 1
  # shellcheck disable=SC2009
  ps -axo command= | grep -F -- "$needle" | grep -qvF -- grep
}

require_not_running() {
  local extra_copia="${1-}" p
  local -a needles=()
  needles+=("$NEW_COPIA/Contents/MacOS/")
  if [ -n "$extra_copia" ]; then
    needles+=("${extra_copia%/}/Contents/MacOS/")
  fi
  for p in "${needles[@]}"; do
    if copy_running "$p"; then
      die "❌ Quit \"$NOME\" (Cmd+Q) and run this again." "❌ Chiudi \"$NOME\" (Cmd+Q) e rilancia."
    fi
  done
}

launch_register() {
  local reg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [ -x "$reg" ]; then
    "$reg" "$@" 2>/dev/null || true
  elif command -v lsregister >/dev/null 2>&1; then
    command lsregister "$@" 2>/dev/null || true
  fi
}

dir_empty() {
  local d="$1" f
  [ -d "$d" ] || return 1
  for f in "$d"/.[!.]* "$d"/..?* "$d"/*; do
    if [ -e "$f" ]; then
      return 1
    fi
  done
  return 0
}

stop_agent() {
  launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || launchctl unload "$AGENT_PLIST" 2>/dev/null || true
}

restart_dock() {
  echo "→ $(t 'The Dock will restart for a moment.' 'Il Dock si riavvierà per un attimo.')"
  killall Dock 2>/dev/null || true
}

add_login() {
  local p="${1%/}" d
  [ -d "$p" ] || return 0
  path_ok "$p" || return 0
  if [ "${#login_dirs[@]}" -gt 0 ]; then
    for d in "${login_dirs[@]}"; do
      [ "$d" = "$p" ] && return 0
    done
  fi
  login_dirs+=("$p")
}

do_uninstall() {
  local existing_dati="" existing_copia="" removed_any=0 app_removed=0 declined=0 d ans="" ans_lc=""
  local -a login_dirs=()

  if [ -e "$APP" ]; then
    if ! app_is_ours "$APP"; then
      die "❌ \"$APP\" already exists and is not an Antigravity Multi Account launcher. Nothing was changed." \
        "❌ \"$APP\" esiste già e non è un launcher di Antigravity Multi Account. Non ho modificato nulla."
    fi
    existing_dati=$(launcher_setting "$APP" DATI)
    existing_copia=$(launcher_setting "$APP" COPIA)
  fi
  require_not_running "$existing_copia"

  stop_agent
  if [ -f "$AGENT_PLIST" ]; then
    rm -f -- "$AGENT_PLIST"
    removed_any=1
  fi
  if [ -f "$LOGFILE" ]; then
    rm -f -- "$LOGFILE"
    rmdir -- "$PREFIX/logs" 2>/dev/null || true
  fi

  if [ -e "$APP" ]; then
    rm_tree "$APP"
    removed_any=1
    app_removed=1
  fi

  if [ -d "$NEW_COPIA" ]; then
    launch_register -u "$NEW_COPIA"
    rm_tree "$NEW_COPIA"
    removed_any=1
  fi
  if dir_empty "$APPS"; then
    rmdir -- "$APPS" || true
  fi
  if dir_empty "$NEW_DATI"; then
    rmdir -- "$NEW_DATI" || true
  fi

  add_login "$NEW_DATI"
  if [ -n "$existing_dati" ]; then
    add_login "$existing_dati"
  fi

  if [ "${#login_dirs[@]}" -gt 0 ]; then
    t "This folder holds the sign-in:" "Questa cartella contiene il login:"
    for d in "${login_dirs[@]}"; do
      echo "  $d"
    done
    read -r -p "$(t 'Delete the data folder? [y/N] ' 'Cancellare la cartella dati? [s/N] ')" ans < /dev/tty || ans=""
    ans_lc=$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')
    case "$ans_lc" in
      y|yes|s|si|sì)
        for d in "${login_dirs[@]}"; do
          rm_tree "$d"
        done
        removed_any=1
        ;;
      *)
        t "Data folder kept." "Cartella dati conservata."
        declined=1
        ;;
    esac
  fi

  if [ "$app_removed" -eq 1 ]; then
    restart_dock
  fi
  if [ "$removed_any" -eq 1 ]; then
    t "Removed." "Rimosso."
  elif [ "$declined" -eq 0 ]; then
    t "Already removed. Nothing to delete." "Già rimosso. Niente da cancellare."
  fi
}

is_real_antigravity() {
  local a="${1%/}" id=""
  [ -d "$a/Contents" ] || return 1
  case "$a" in
    */AntigravityMultiAccount/*|*/.Trash/*) return 1 ;;
  esac
  id=$(bundle_id "$a")
  case "$id" in
    local.antigravity-launcher.*|"") return 1 ;;
    *antigravity*|*Antigravity*) return 0 ;;
  esac
  [ "$(basename "$a")" = "Antigravity.app" ] && return 0
  return 1
}

find_antigravity() {
  local c=""
  if [ -n "${ANTIGRAVITY_APP-}" ]; then
    if [ -d "$ANTIGRAVITY_APP/Contents" ]; then printf '%s' "${ANTIGRAVITY_APP%/}"; fi
    return 0
  fi
  for c in "/Applications/Antigravity.app" "$HOME/Applications/Antigravity.app"; do
    if [ -d "$c/Contents" ] && ! app_is_ours "$c"; then
      printf '%s' "$c"
      return 0
    fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r c; do
      if is_real_antigravity "$c"; then
        printf '%s' "$c"
        return 0
      fi
    done < <( { mdfind "kMDItemFSName == 'Antigravity.app' && kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null; } )
  fi
  return 0
}

# ── Linux helpers ────────────────────────────────────────────────────────────
desktop_is_ours_linux() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -qE '^X-AntigravityMultiAccount-Id=|/AntigravityMultiAccount/launch-' "$f" 2>/dev/null
}

find_antigravity_linux() {
  local c="" d="" exec_line="" bin=""
  if [ -n "${ANTIGRAVITY_APP-}" ]; then
    if [ -f "$ANTIGRAVITY_APP" ] && [ -x "$ANTIGRAVITY_APP" ]; then
      printf '%s' "$ANTIGRAVITY_APP"
      return 0
    fi
    if [ -d "$ANTIGRAVITY_APP" ]; then
      for c in "$ANTIGRAVITY_APP/antigravity" "$ANTIGRAVITY_APP/agy" "$ANTIGRAVITY_APP/AppRun"; do
        if [ -f "$c" ] && [ -x "$c" ]; then
          printf '%s' "$c"
          return 0
        fi
      done
    fi
    return 0
  fi

  for c in \
    "/opt/Antigravity_Gemini/antigravity" \
    "/opt/Antigravity/antigravity" \
    "/usr/bin/antigravity" \
    "/usr/local/bin/antigravity" \
    "/usr/share/antigravity/antigravity" \
    "/snap/bin/antigravity"; do
    if [ -f "$c" ] && [ -x "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done

  if command -v antigravity >/dev/null 2>&1; then
    c=$(command -v antigravity)
    if [ -n "$c" ] && [ -x "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  fi

  for d in \
    "/usr/share/applications/antigravity.desktop" \
    "/usr/share/applications/google-antigravity.desktop" \
    "/usr/local/share/applications/antigravity.desktop" \
    "$HOME/.local/share/applications/antigravity.desktop"; do
    if [ -f "$d" ] && ! desktop_is_ours_linux "$d"; then
      exec_line=$(sed -n 's/^Exec=//p' "$d" | head -n 1)
      bin=$(printf '%s' "$exec_line" | sed -E 's/ %[a-zA-Z]//g; s/^env ([^ ]+=[^ ]+ )*//; s/^"([^"]+)".*/\1/; s/^([^ ]+).*/\1/')
      if [ -n "$bin" ]; then
        printf '%s' "$bin"
        return 0
      fi
    fi
  done

  for d in "$HOME/Applications" "$HOME/.local/bin" "$HOME/Downloads"; do
    [ -d "$d" ] || continue
    for c in "$d"/[Aa]ntigravity*.AppImage "$d"/antigravity*; do
      if [ -f "$c" ] && [ -x "$c" ]; then
        printf '%s' "$c"
        return 0
      fi
    done
  done
  return 0
}

find_antigravity_icon_linux() {
  local agy_bin="${1-}" icon="" d="" icon_key=""
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
  for d in \
    "/usr/share/applications/antigravity.desktop" \
    "/usr/share/applications/google-antigravity.desktop" \
    "/usr/local/share/applications/antigravity.desktop" \
    "$xdg_data/applications/antigravity.desktop"; do
    if [ -f "$d" ] && ! desktop_is_ours_linux "$d"; then
      icon_key=$(sed -n 's/^Icon=//p' "$d" | head -n 1)
      if [ -n "$icon_key" ] && [ -f "$icon_key" ]; then
        printf '%s' "$icon_key"
        return 0
      fi
    fi
  done

  for icon in \
    "/opt/Antigravity_Gemini/resources/app/resources/linux/code.png" \
    "/opt/Antigravity_Gemini/antigravity.png" \
    "/usr/share/icons/hicolor/512x512/apps/antigravity.png" \
    "/usr/share/icons/hicolor/256x256/apps/antigravity.png" \
    "/usr/share/icons/hicolor/128x128/apps/antigravity.png" \
    "/usr/share/icons/hicolor/scalable/apps/antigravity.svg" \
    "/usr/share/pixmaps/antigravity.png" \
    "/usr/share/icons/Papirus/64x64/apps/gemini.svg"; do
    if [ -f "$icon" ]; then
      printf '%s' "$icon"
      return 0
    fi
  done

  if [ -n "$agy_bin" ]; then
    d=$(dirname "$agy_bin")
    for icon in "$d/antigravity.png" "$d/icon.png" "$d/resources/app/resources/linux/code.png"; do
      if [ -f "$icon" ]; then
        printf '%s' "$icon"
        return 0
      fi
    done
  fi
  return 0
}

data_in_use_linux() {
  local target="${1%/}"
  [ -n "$target" ] || return 1
  # shellcheck disable=SC2009
  ps -eo args= 2>/dev/null | grep -F -- "--user-data-dir=$target" | grep -qvF -- grep
}

require_not_running_linux() {
  local p
  for p in "$@"; do
    [ -n "$p" ] || continue
    if data_in_use_linux "$p"; then
      die "❌ Quit \"$NOME\" and run this again." "❌ Chiudi \"$NOME\" e rilancia."
    fi
  done
}

refresh_desktop_linux() {
  local apps_dir="$1" icon_root="$2"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$icon_root" ]; then
    gtk-update-icon-cache -f -t "$icon_root" >/dev/null 2>&1 || true
  fi
}

do_uninstall_linux() {
  local existing_dati="" removed_any=0 declined=0 d ans="" ans_lc="" f="" left=0
  local -a login_dirs=()

  for f in "$LINUX_DESKTOP" "$LINUX_LEGACY_DESKTOP"; do
    if [ -e "$f" ] && ! desktop_is_ours_linux "$f"; then
      die "❌ \"$f\" already exists and is not an Antigravity Multi Account launcher. Nothing was changed." \
        "❌ \"$f\" esiste già e non è un launcher di Antigravity Multi Account. Non ho modificato nulla."
    fi
  done

  if [ -f "$LINUX_CFG" ]; then
    existing_dati=$(read_kv "$LINUX_CFG" DATI)
  fi
  require_not_running_linux "$NEW_DATI" "$existing_dati"

  for f in \
    "$LINUX_DESKTOP" \
    "$LINUX_LEGACY_DESKTOP" \
    "$LINUX_LAUNCHER" \
    "$LINUX_CFG" \
    "$LINUX_ICON_DIR/$ID.png" \
    "$LINUX_ICON_DIR/$ID.svg" \
    "$LINUX_HICOLOR/256x256/apps/antigravity-multi-account-$ID.png" \
    "$LINUX_HICOLOR/scalable/apps/antigravity-multi-account-$ID.svg"; do
    if [ -f "$f" ]; then
      rm -f -- "$f"
      removed_any=1
    fi
  done

  if dir_empty "$LINUX_ICON_DIR"; then
    rmdir -- "$LINUX_ICON_DIR" 2>/dev/null || true
  fi
  if [ -d "$LINUX_BASE" ]; then
    for f in "$LINUX_BASE"/launch-*.sh "$LINUX_BASE"/config-*; do
      if [ -e "$f" ]; then left=1; break; fi
    done
    if [ "$left" -eq 0 ]; then
      rm -f -- "$LINUX_COLORA"
      rmdir -- "$LINUX_BASE" 2>/dev/null || true
    fi
  fi
  if dir_empty "$NEW_DATI"; then
    rmdir -- "$NEW_DATI" 2>/dev/null || true
  fi

  add_login "$NEW_DATI"
  if [ -n "$existing_dati" ]; then
    add_login "$existing_dati"
  fi

  if [ "${#login_dirs[@]}" -gt 0 ]; then
    t "This folder holds the sign-in:" "Questa cartella contiene il login:"
    for d in "${login_dirs[@]}"; do
      echo "  $d"
    done
    read -r -p "$(t 'Delete the data folder? [y/N] ' 'Cancellare la cartella dati? [s/N] ')" ans < /dev/tty || ans=""
    ans_lc=$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')
    case "$ans_lc" in
      y|yes|s|si|sì)
        for d in "${login_dirs[@]}"; do
          rm_tree "$d"
        done
        removed_any=1
        ;;
      *)
        t "Data folder kept." "Cartella dati conservata."
        declined=1
        ;;
    esac
  fi

  if dir_empty "$PREFIX"; then
    rmdir -- "$PREFIX" 2>/dev/null || true
  fi
  refresh_desktop_linux "$LINUX_APPS_DIR" "$LINUX_HICOLOR"

  if [ "$removed_any" -eq 1 ]; then
    t "Removed." "Rimosso."
  elif [ "$declined" -eq 0 ]; then
    t "Already removed. Nothing to delete." "Già rimosso. Niente da cancellare."
  fi
}

install_linux() {
  local existing_dati="" f="" src_icon="" ext="png" out_icon="" theme_icon="" icon_value="antigravity" esito=""

  for f in "$LINUX_DESKTOP" "$LINUX_LEGACY_DESKTOP"; do
    if [ -e "$f" ] && ! desktop_is_ours_linux "$f"; then
      die "❌ \"$f\" already exists and is not an Antigravity Multi Account launcher. Nothing was changed." \
        "❌ \"$f\" esiste già e non è un launcher di Antigravity Multi Account. Non ho modificato nulla."
    fi
  done

  DATI="$NEW_DATI"
  if [ -f "$LINUX_CFG" ]; then
    existing_dati=$(read_kv "$LINUX_CFG" DATI)
    if [ -n "$existing_dati" ] && path_ok "$existing_dati"; then
      DATI="$existing_dati"
    fi
  fi
  require_not_running_linux "$DATI" "$NEW_DATI"

  if [ -f "$LINUX_LEGACY_DESKTOP" ] && [ "$LINUX_LEGACY_DESKTOP" != "$LINUX_DESKTOP" ]; then
    rm -f -- "$LINUX_LEGACY_DESKTOP"
  fi

  echo "→ $(t 'Separate data folder' 'Cartella dati separata'): $DATI"
  mkdir -p "$DATI" "$DATI/user-data" "$DATI/extensions" "$LINUX_BASE" "$LINUX_ICON_DIR" "$LINUX_APPS_DIR"

  cat > "$LINUX_COLORA" <<'EOF'
#!/usr/bin/env python3
import sys, re, struct, zlib, colorsys

def shift_rgb(r, g, b, shift):
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    if s < 0.08:
        s = 0.65
        l = max(0.35, min(0.65, l))
    nr, ng, nb = colorsys.hls_to_rgb((h + shift) % 1.0, l, s)
    return int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255))

def generate_badge_png(dst_path, degrees):
    w = h = 256
    hue = ((15.0 + float(degrees)) % 360.0) / 360.0
    r1, g1, b1 = [int(round(c * 255)) for c in colorsys.hls_to_rgb(hue, 0.52, 0.68)]
    r2, g2, b2 = [int(round(c * 255)) for c in colorsys.hls_to_rgb(hue, 0.36, 0.68)]
    out_raw = bytearray()
    rad = 56.0
    for y in range(h):
        out_raw.append(0)
        t = y / float(h - 1)
        rr = int(round(r1 * (1 - t) + r2 * t))
        gg = int(round(g1 * (1 - t) + g2 * t))
        bb = int(round(b1 * (1 - t) + b2 * t))
        for x in range(w):
            dx = max(0.0, max(rad - x, x - (w - 1 - rad)))
            dy = max(0.0, max(rad - y, y - (h - 1 - rad)))
            dist = (dx * dx + dy * dy) ** 0.5
            if dist > rad + 0.5:
                out_raw.extend((0, 0, 0, 0))
            elif dist > rad - 0.5:
                alpha = int(round(max(0.0, min(1.0, rad + 0.5 - dist)) * 255))
                out_raw.extend((rr, gg, bb, alpha))
            else:
                out_raw.extend((rr, gg, bb, 255))
    def make_chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(out_raw), 6)
    with open(dst_path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + make_chunk(b"IHDR", ihdr) + make_chunk(b"IDAT", idat) + make_chunk(b"IEND", b""))

def recolor_svg(src_path, dst_path, degrees):
    shift = (float(degrees) % 360.0) / 360.0
    with open(src_path, "r", encoding="utf-8") as f:
        svg = f.read()
    def repl_hex(m):
        hx = m.group(1)
        if len(hx) == 3:
            hx = "".join(c * 2 for c in hx)
        r, g, b = int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16)
        nr, ng, nb = shift_rgb(r, g, b, shift)
        return f"#{nr:02x}{ng:02x}{nb:02x}"
    svg = re.sub(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b", repl_hex, svg)
    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(svg)

def recolor_png(src_path, dst_path, degrees):
    shift = (float(degrees) % 360.0) / 360.0
    with open(src_path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    pos = 8
    w = h = bit_depth = color_type = 0
    plte = trns = None
    idat_chunks = []
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos+4])[0]
        tag = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+length]
        pos += 12 + length
        if tag == b"IHDR":
            w, h, bit_depth, color_type, comp, filt, interlace = struct.unpack(">IIBBBBB", chunk_data)
            if bit_depth != 8 or interlace != 0 or color_type not in (2, 3, 6):
                raise ValueError(f"unsupported PNG format (depth={bit_depth}, type={color_type})")
        elif tag == b"PLTE":
            plte = chunk_data
        elif tag == b"tRNS":
            trns = chunk_data
        elif tag == b"IDAT":
            idat_chunks.append(chunk_data)
        elif tag == b"IEND":
            break

    bpp = {2: 3, 3: 1, 6: 4}[color_type]
    raw = zlib.decompress(b"".join(idat_chunks))
    stride = w * bpp
    recon = bytearray(h * stride)
    i = 0
    for y in range(h):
        ftype = raw[i]
        i += 1
        row_start = y * stride
        prev_start = (y - 1) * stride
        for x in range(stride):
            val = raw[i]
            i += 1
            a = recon[row_start + x - bpp] if x >= bpp else 0
            b = recon[prev_start + x] if y > 0 else 0
            c = recon[prev_start + x - bpp] if (x >= bpp and y > 0) else 0
            if ftype == 1:
                val = (val + a) & 0xff
            elif ftype == 2:
                val = (val + b) & 0xff
            elif ftype == 3:
                val = (val + ((a + b) >> 1)) & 0xff
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                val = (val + pr) & 0xff
            recon[row_start + x] = val

    out_raw = bytearray()
    cache = {}
    for y in range(h):
        out_raw.append(0)
        row_start = y * stride
        for x in range(w):
            p = row_start + x * bpp
            if color_type == 6:
                r, g, b, a = recon[p], recon[p+1], recon[p+2], recon[p+3]
            elif color_type == 2:
                r, g, b, a = recon[p], recon[p+1], recon[p+2], 255
            else:
                idx = recon[p]
                r, g, b = plte[idx*3:idx*3+3]
                a = trns[idx] if (trns and idx < len(trns)) else 255
            if a == 0:
                out_raw.extend((0, 0, 0, 0))
            else:
                key = (r, g, b)
                if key not in cache:
                    cache[key] = shift_rgb(r, g, b, shift)
                nr, ng, nb = cache[key]
                out_raw.extend((nr, ng, nb, a))

    def make_chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xffffffff)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(out_raw), 6)
    with open(dst_path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + make_chunk(b"IHDR", ihdr) + make_chunk(b"IDAT", idat) + make_chunk(b"IEND", b""))

if __name__ == "__main__":
    try:
        src, dst, deg = sys.argv[1], sys.argv[2], float(sys.argv[3])
        if src == "--generate":
            generate_badge_png(dst, deg)
        elif src.lower().endswith(".svg"):
            recolor_svg(src, dst, deg)
        else:
            recolor_png(src, dst, deg)
        print("ok")
    except Exception as e:
        print(str(e))
        sys.exit(1)
EOF
  chmod +x "$LINUX_COLORA"

  src_icon=$(find_antigravity_icon_linux "$ANTIGRAVITY")
  if [ -n "$src_icon" ]; then
    icon_value="$src_icon"
  fi

  if [ -n "$GRADI" ]; then
    echo "→ $(t "Coloring the icon: $COLORE" "Coloro l'icona: $COLORE")"
    if [ -n "$src_icon" ]; then
      case "$src_icon" in
        *.svg|*.SVG) ext="svg" ;;
        *) ext="png" ;;
      esac
      out_icon="$LINUX_ICON_DIR/$ID.$ext"
      if command -v python3 >/dev/null 2>&1; then
        esito=$(python3 "$LINUX_COLORA" "$src_icon" "$out_icon" "$GRADI" 2>&1 || true)
      fi
    else
      ext="png"
      out_icon="$LINUX_ICON_DIR/$ID.png"
      if command -v python3 >/dev/null 2>&1; then
        esito=$(python3 "$LINUX_COLORA" "--generate" "$out_icon" "$GRADI" 2>&1 || true)
      else
        esito=$(t "Antigravity icon not found" "icona di Antigravity non trovata")
      fi
    fi

    if [ "$esito" = "ok" ] && [ -f "$out_icon" ]; then
      if [ "$ext" = "svg" ]; then
        theme_icon="$LINUX_HICOLOR/scalable/apps/antigravity-multi-account-$ID.svg"
      else
        theme_icon="$LINUX_HICOLOR/256x256/apps/antigravity-multi-account-$ID.png"
      fi
      mkdir -p "$(dirname "$theme_icon")"
      cp "$out_icon" "$theme_icon"
      icon_value="$out_icon"
    else
      t "⚠️  Colored icon not applied ($esito). The app still works, with the regular icon." \
        "⚠️  Icona colorata non applicata ($esito). L'app funziona lo stesso, con l'icona normale."
    fi
  fi

  echo "→ $(t 'Creating the launcher' 'Creo il lanciatore'): $LINUX_DESKTOP"
  cat > "$LINUX_CFG" <<EOF
SRC=$ANTIGRAVITY
DATI=$DATI
NOME=$NOME
ID=$ID
GRADI=$GRADI
EOF

  cat > "$LINUX_LAUNCHER" <<'EOF'
#!/bin/bash
CFG_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
ID="${SCRIPT_NAME#launch-}"
ID="${ID%.sh}"
CFG="$CFG_DIR/config-$ID"

kv() {
  local k v
  [ -f "$CFG" ] || return 0
  while IFS='=' read -r k v || [ -n "${k-}" ]; do
    if [ "$k" = "$1" ]; then
      printf '%s' "$v"
      return 0
    fi
  done < "$CFG"
}

SRC="$(kv SRC)"
DATI="$(kv DATI)"
if [ ! -x "$SRC" ]; then
  for c in \
    "/opt/Antigravity_Gemini/antigravity" \
    "/opt/Antigravity/antigravity" \
    "/usr/bin/antigravity" \
    "/usr/local/bin/antigravity" \
    "/usr/share/antigravity/antigravity" \
    "/snap/bin/antigravity"; do
    if [ -x "$c" ]; then SRC="$c"; break; fi
  done
  if [ ! -x "$SRC" ] && command -v antigravity >/dev/null 2>&1; then
    SRC="$(command -v antigravity)"
  fi
fi

mkdir -p "$DATI" "$DATI/user-data" "$DATI/extensions"
exec "$SRC" --class="antigravity-multi-account-$ID" --user-data-dir="$DATI/user-data" --extensions-dir="$DATI/extensions" "$@"
EOF
  chmod +x "$LINUX_LAUNCHER"

  cat > "$LINUX_DESKTOP" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$NOME
Comment=Google Antigravity with a second account
Comment[it]=Google Antigravity con un secondo account
Exec="$LINUX_LAUNCHER" %U
Icon=$icon_value
Terminal=false
Categories=Development;IDE;
StartupWMClass=antigravity-multi-account-$ID
X-AntigravityMultiAccount-Id=$ID
EOF
  chmod +x "$LINUX_DESKTOP" 2>/dev/null || true

  refresh_desktop_linux "$LINUX_APPS_DIR" "$LINUX_HICOLOR"

  echo ""
  if [ "$LINGUA" = "it" ]; then
    echo "✅ Fatto! Trovi \"$NOME\" nel menu delle applicazioni."
  else
    echo "✅ Done! You'll find \"$NOME\" in your applications menu."
  fi
}

ANTIGRAVITY=""
UNINSTALL=0
if [ "${1-}" = "--uninstall" ]; then
  UNINSTALL=1
  shift
fi

if [ "$UNINSTALL" -eq 0 ]; then
  if [ "$OS_KERNEL" = "Darwin" ]; then
    ANTIGRAVITY=$(find_antigravity)
  else
    ANTIGRAVITY=$(find_antigravity_linux)
  fi
  if [ -z "$ANTIGRAVITY" ]; then
    if [ -n "${ANTIGRAVITY_APP-}" ]; then
      die "❌ ANTIGRAVITY_APP does not point to an app: $ANTIGRAVITY_APP" "❌ ANTIGRAVITY_APP non indica un'app: $ANTIGRAVITY_APP"
    fi
    if [ "$OS_KERNEL" = "Darwin" ]; then
      die "❌ Antigravity not found on this Mac. Install it and open it once, or set ANTIGRAVITY_APP=/path/to/Antigravity.app." \
        "❌ Non trovo Antigravity su questo Mac. Installalo e aprilo una volta, oppure imposta ANTIGRAVITY_APP=/percorso/di/Antigravity.app."
    else
      die "❌ Antigravity not found on this system. Install Antigravity (or set ANTIGRAVITY_APP=/path/to/antigravity) and try again." \
        "❌ Non trovo Antigravity su questo sistema. Installa Antigravity (o imposta ANTIGRAVITY_APP=/percorso/di/antigravity) e riprova."
    fi
  fi
  echo "→ Antigravity: $ANTIGRAVITY"
fi

# ── Name and color ───────────────────────────────────────────────────────────
NOME="${1-}"
COLORE="${2-}"
if [ -z "$NOME" ]; then
  if [ "$UNINSTALL" -eq 1 ]; then
    read -r -p "$(t 'Name of the app to remove [Antigravity 2]: ' 'Nome della app da rimuovere [Antigravity 2]: ')" NOME < /dev/tty || true
  else
    read -r -p "$(t 'Name of the new app [Antigravity 2]: ' 'Nome della nuova app [Antigravity 2]: ')" NOME < /dev/tty || true
  fi
  if [ -z "$NOME" ]; then
    NOME="Antigravity 2"
  fi
fi
NOME=$(trim "$NOME")
if [ -z "$NOME" ]; then
  die "❌ The name is empty." "❌ Il nome è vuoto."
fi
if [[ ! "$NOME" =~ ^[A-Za-z0-9\ _-]+$ ]]; then
  die "❌ The name may only contain letters, numbers, spaces, - and _" \
    "❌ Il nome può contenere solo lettere, numeri, spazi, - e _"
fi
NOME_LC=$(printf '%s' "$NOME" | tr '[:upper:]' '[:lower:]')
case "$NOME_LC" in
  antigravity|googleantigravity|agy)
    die "❌ This name is reserved. Choose another one." "❌ Questo nome è riservato. Scegline un altro."
    ;;
esac
ID=$(printf '%s' "$NOME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
if [ -z "$ID" ]; then
  die "❌ The name needs at least one letter or number." "❌ Il nome deve contenere almeno una lettera o un numero."
fi

if [ "$OS_KERNEL" != "Darwin" ]; then
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  PREFIX="$XDG_CONFIG_HOME/AntigravityMultiAccount"
  NEW_DATI="$PREFIX/$NOME"
  LINUX_BASE="$XDG_DATA_HOME/AntigravityMultiAccount"
  LINUX_ICON_DIR="$LINUX_BASE/icons"
  LINUX_COLORA="$LINUX_BASE/colora.py"
  LINUX_CFG="$LINUX_BASE/config-$ID"
  LINUX_LAUNCHER="$LINUX_BASE/launch-$ID.sh"
  LINUX_APPS_DIR="$XDG_DATA_HOME/applications"
  LINUX_DESKTOP="$LINUX_APPS_DIR/antigravity-multi-account-$ID.desktop"
  LINUX_LEGACY_DESKTOP="$LINUX_APPS_DIR/$NOME.desktop"
  LINUX_HICOLOR="$XDG_DATA_HOME/icons/hicolor"
  if [ "$NEW_DATI" = "$PREFIX" ]; then
    die "❌ This name is reserved. Choose another one." "❌ Questo nome è riservato. Scegline un altro."
  fi
  if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall_linux
    exit 0
  fi
else
  PREFIX="$HOME/Library/Application Support/AntigravityMultiAccount"
  APP="$HOME/Applications/$NOME.app"
  APPS="$PREFIX/apps"
  NEW_DATI="$PREFIX/$NOME"
  NEW_COPIA="$APPS/$NOME.app"
  AGENT_LABEL="local.antigravity-multi-account.$ID"
  AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
  LOGFILE="$PREFIX/logs/$ID.log"
  if [ "$NEW_DATI" = "$PREFIX" ] || [ "$NEW_DATI" = "$APPS" ]; then
    die "❌ This name is reserved. Choose another one." "❌ Questo nome è riservato. Scegline un altro."
  fi
  if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall
    exit 0
  fi
fi

if [ -z "$COLORE" ]; then
  read -r -p "$(t 'Icon color (blue, green, purple, pink, cyan, yellow, none) [blue]: ' 'Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]: ')" COLORE < /dev/tty || true
  COLORE="${COLORE:-blue}"
fi
COLORE=$(printf '%s' "$COLORE" | tr '[:upper:]' '[:lower:]')
case "$COLORE" in
  blue|blu)        GRADI=200 ;;
  green|verde)     GRADI=110 ;;
  purple|viola)    GRADI=255 ;;
  pink|rosa)       GRADI=315 ;;
  cyan|azzurro)    GRADI=175 ;;
  yellow|giallo)   GRADI=35  ;;
  none|nessuno)    GRADI=""  ;;
  *) die "❌ Unknown color: $COLORE" "❌ Colore non riconosciuto: $COLORE" ;;
esac

if [ "$OS_KERNEL" != "Darwin" ]; then
  install_linux
  exit 0
fi

DATI="$NEW_DATI"
COPIA="$NEW_COPIA"
EXISTING_DATI=""
EXISTING_COPIA=""
if [ -e "$APP" ]; then
  if ! app_is_ours "$APP"; then
    die "❌ \"$APP\" already exists and is not an Antigravity Multi Account launcher. Nothing was changed." \
      "❌ \"$APP\" esiste già e non è un launcher di Antigravity Multi Account. Non ho modificato nulla."
  fi
  EXISTING_DATI=$(launcher_setting "$APP" DATI)
  EXISTING_COPIA=$(launcher_setting "$APP" COPIA)
  if [ -n "$EXISTING_DATI" ] && path_ok "$EXISTING_DATI"; then
    DATI="$EXISTING_DATI"
  fi
fi
require_not_running "$EXISTING_COPIA"
stop_agent

if [ -d "$COPIA" ]; then
  launch_register -u "$COPIA"
  rm_tree "$COPIA"
fi
if [ -e "$APP" ]; then
  rm_tree "$APP"
fi

echo "→ $(t 'Separate data folder' 'Cartella dati separata'): $DATI"
mkdir -p "$DATI" "$DATI/user-data" "$DATI/extensions" "$APPS" "$HOME/Applications" "$APP/Contents/MacOS" "$APP/Contents/Resources"

COLORA="$APP/Contents/Resources/colora.js"
cat > "$COLORA" <<'EOF'
ObjC.import('AppKit');
ObjC.import('CoreImage');

function run(argv) {
  var source = argv[0], target = argv[1], degrees = parseFloat(argv[2]);
  var S = 1024;
  var icon = $.NSWorkspace.sharedWorkspace.iconForFile(source);
  var canvas = $.NSImage.alloc.initWithSize($.NSMakeSize(S, S));
  canvas.lockFocus;
  icon.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, S, S), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  canvas.unlockFocus;
  var ci = $.CIImage.imageWithData(canvas.TIFFRepresentation);
  var filter = $.CIFilter.filterWithName('CIHueAdjust');
  filter.setValueForKey(ci, 'inputImage');
  filter.setValueForKey($.NSNumber.numberWithDouble(degrees * Math.PI / 180), 'inputAngle');
  var bitmap = $.NSBitmapImageRep.alloc.initWithCIImage(filter.valueForKey('outputImage'));
  var result = $.NSImage.alloc.initWithSize(bitmap.size);
  result.addRepresentation(bitmap);
  return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(result, target, 0) ? 'ok' : 'error';
}
EOF

echo "→ $(t 'Creating the app' "Creo l'app"): $APP"
cat > "$APP/Contents/Resources/config" <<EOF
SRC=$ANTIGRAVITY
COPIA=$COPIA
DATI=$DATI
NOME=$NOME
GRADI=$GRADI
COLORA=$COLORA
LOG=$LOGFILE
EOF

cat > "$APP/Contents/Resources/common.sh" <<'EOF'
RES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$RES/config"
kv() {
  local k v
  while IFS='=' read -r k v || [ -n "${k-}" ]; do
    if [ "$k" = "$1" ]; then
      printf '%s' "$v"
      return 0
    fi
  done < "$CFG"
}
SRC="$(kv SRC)"
if [ ! -d "$SRC" ]; then
  for c in "/Applications/Antigravity.app" "$HOME/Applications/Antigravity.app"; do
    if [ -d "$c" ]; then SRC="$c"; break; fi
  done
fi
COPIA="$(kv COPIA)"
DATI="$(kv DATI)"
GRADI="$(kv GRADI)"
COLORA="$(kv COLORA)"
LOG="$(kv LOG)"

version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }
newer() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, "."); k = (n > m) ? n : m
    for (i = 1; i <= k; i++) {
      if ((x[i] + 0) > (y[i] + 0)) exit 0
      if ((x[i] + 0) < (y[i] + 0)) exit 1
    }
    exit 1
  }'
}

fix_icon() {
  [ -n "$GRADI" ] && [ -d "$COPIA" ] || return 0
  if [ ! -e "$COPIA/Icon"$'\r' ]; then
    osascript -l JavaScript "$COLORA" "$SRC" "$COPIA" "$GRADI" >/dev/null 2>&1 || true
    touch "$COPIA"
  fi
}

launch_copy() {
  mkdir -p "$DATI/user-data" "$DATI/extensions"
  if [ -d "$COPIA" ]; then
    open -n -a "$COPIA" --args --user-data-dir="$DATI/user-data" --extensions-dir="$DATI/extensions"
  else
    open -n -a "$SRC" --args --user-data-dir="$DATI/user-data" --extensions-dir="$DATI/extensions"
  fi
}
EOF

LANCIATORE="$APP/Contents/MacOS/avvia"
cat > "$LANCIATORE" <<'EOF'
#!/bin/bash
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/Resources/common.sh"

mkdir -p "$DATI/user-data" "$DATI/extensions"
if [ -z "$GRADI" ]; then
  exec open -n -a "$SRC" --args --user-data-dir="$DATI/user-data" --extensions-dir="$DATI/extensions"
fi

if [ ! -d "$COPIA" ] || newer "$(version "$SRC")" "$(version "$COPIA")"; then
  rm -rf "$COPIA"
  cp -cR "$SRC" "$COPIA" 2>/dev/null || { rm -rf "$COPIA"; cp -R "$SRC" "$COPIA"; }
  xattr -dr com.apple.quarantine "$COPIA" 2>/dev/null
fi
fix_icon
launch_copy
EOF
chmod +x "$LANCIATORE"

ICONA=$(defaults read "$ANTIGRAVITY/Contents/Info" CFBundleIconFile 2>/dev/null || echo "")
[ -n "$ICONA" ] && [[ "$ICONA" != *.icns ]] && ICONA="$ICONA.icns"
if [ -n "$ICONA" ] && [ -f "$ANTIGRAVITY/Contents/Resources/$ICONA" ]; then
  cp "$ANTIGRAVITY/Contents/Resources/$ICONA" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NOME</string>
  <key>CFBundleDisplayName</key><string>$NOME</string>
  <key>CFBundleIdentifier</key><string>local.antigravity-launcher.$ID</string>
  <key>CFBundleExecutable</key><string>avvia</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.1</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

if [ -n "$GRADI" ]; then
  echo "→ $(t "Coloring the icon: $COLORE" "Coloro l'icona: $COLORE")"
  ESITO=$(osascript -l JavaScript "$COLORA" "$ANTIGRAVITY" "$APP" "$GRADI" 2>&1 || true)
  if [ "$ESITO" != "ok" ]; then
    t "⚠️  Colored icon not applied ($ESITO). The app still works, with the regular icon." \
      "⚠️  Icona colorata non applicata ($ESITO). L'app funziona lo stesso, con l'icona normale."
  fi
fi

touch "$APP"
launch_register -f "$APP"
restart_dock

echo ""
if [ "$LINGUA" = "it" ]; then
  echo "✅ Fatto! \"$NOME\" è in ~/Applications (la trovi anche con Spotlight)."
else
  echo "✅ Done! \"$NOME\" is in ~/Applications (you can also find it with Spotlight)."
fi
open -R "$APP"
