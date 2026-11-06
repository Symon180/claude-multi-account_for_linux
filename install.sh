#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Claude Multi Account – macOS
#
#  Creates a second app ("Claude 2") that launches Claude Desktop with a
#  separate login, so you can use two accounts side by side. It also gets an
#  icon in a different color, visible in the Dock while the app is running.
#  The original Claude app is never modified: the colored icon lives on an
#  APFS "clone" copy of Claude.app, which takes no extra disk space and is
#  refreshed automatically when Claude updates.
#
#  Usage (paste into Terminal):
#    curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash
#  With name and color preset:
#    curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash -s -- "Claude 2" blue
#  Remove (asks before deleting the data folder, which holds the sign-in):
#    curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash -s -- --uninstall "Claude 2"
#
#  Colors: blue, green, purple, pink, cyan, yellow, none
#          (Italian names work too: blu, verde, viola, rosa, azzurro, giallo, nessuno)
#
#  Claude Desktop is looked for in /Applications, then in ~/Applications, then
#  anywhere on the Mac with Spotlight. To point at a specific copy:
#    curl -fsSL .../install.sh | CLAUDE_APP="/path/to/Claude.app" bash
#  Data: ~/Library/Application Support/ClaudeMultiAccount/<name>/
#  Clone: ~/Library/Application Support/ClaudeMultiAccount/apps/<name>.app
#  The Dock restarts for a moment so the icon updates.
#
#  FIRST SIGN-IN – IMPORTANT:
#    In the new app do NOT use "Continue with Google". Type your email, press
#    "Continue with email", then paste the CODE from the email into the window
#    (don't click the link, or the other Claude app will open).
#    Alternatively: quit the main Claude app (Cmd+Q) before signing in.
# ─────────────────────────────────────────────────────────────────────────────

set -e

# Messages follow the system language: Italian if the Mac is set to Italian, English otherwise.
LINGUA=$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' "(),\n' | cut -c1-2 || true)
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
    local.claude-launcher.*) return 0 ;;
    *) return 1 ;;
  esac
}

is_protected() {
  local p="${1%/}"
  case "$p" in
    ""|"/"|"$HOME"|"$HOME/Applications"|"$HOME/Desktop"|"$HOME/Library"|"$HOME/Library/Application Support"|"$HOME/Library/Application Support/ClaudeMultiAccount"|"$HOME/Library/Application Support/ClaudeMultiAccount/apps")
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
    */"$NOME"|*/"$NOME"/*|*/"$NOME.app"|*/"$NOME.app"/*|*/"$NOME (app)"|*/"$NOME (app)"/*) return 0 ;;
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

# Undo the backslash escapes written by printf %q, without executing the line.
unquote_q() {
  local s="$1" out="" i=0 c next len backslash=$'\134'
  if [ "${s#\$\'}" != "$s" ] && [ "${s%\'}" != "$s" ]; then
    s="${s#\$\'}"
    s="${s%\'}"
  elif [ "${s#\'}" != "$s" ] && [ "${s%\'}" != "$s" ]; then
    s="${s#\'}"
    s="${s%\'}"
  fi
  len=${#s}
  while [ "$i" -lt "$len" ]; do
    c=${s:i:1}
    if [ "$c" = "$backslash" ]; then
      i=$((i + 1))
      [ "$i" -lt "$len" ] || break
      next=${s:i:1}
      case "$next" in
        n) out="${out}"$'\n' ;;
        t) out="${out}"$'\t' ;;
        r) out="${out}"$'\r' ;;
        *) out="${out}${next}" ;;
      esac
    else
      out="${out}${c}"
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
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
  local app="$1" key="$2" cfg="" line="" raw=""
  cfg="$app/Contents/Resources/config"
  if [ -f "$cfg" ]; then
    read_kv "$cfg" "$key"
    return 0
  fi
  [ -f "$app/Contents/MacOS/avvia" ] || return 0
  line=$(grep -m1 "^${key}=" "$app/Contents/MacOS/avvia" || true)
  [ -n "$line" ] || return 0
  raw=${line#"${key}="}
  unquote_q "$raw"
}

copy_running() {
  local needle="$1"
  [ -n "$needle" ] || return 1
  # shellcheck disable=SC2009
  ps -axo command= | grep -F -- "$needle" | grep -qvF -- grep
}

require_not_running() {
  local extra_copia="${1-}" extra_motore="${2-}" p
  local -a needles=()
  needles+=("$NEW_COPIA/Contents/MacOS/")
  needles+=("$OLD_NESTED/$NOME.app/Contents/MacOS/")
  needles+=("$LEGACY_MOTORE/$NOME.app/Contents/MacOS/")
  if [ -n "$extra_copia" ]; then
    needles+=("${extra_copia%/}/Contents/MacOS/")
  fi
  if [ -n "$extra_motore" ]; then
    needles+=("${extra_motore%/}/$NOME.app/Contents/MacOS/")
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
  local existing_dati="" existing_motore="" existing_copia="" removed_any=0 app_removed=0 declined=0 d ans="" ans_lc=""
  local -a login_dirs=()

  if [ -e "$APP" ]; then
    if ! app_is_ours "$APP"; then
      die "❌ \"$APP\" already exists and is not a Claude Multi Account launcher. Nothing was changed." \
        "❌ \"$APP\" esiste già e non è un launcher di Claude Multi Account. Non ho modificato nulla."
    fi
    existing_dati=$(launcher_setting "$APP" DATI)
    existing_motore=$(launcher_setting "$APP" MOTORE)
    existing_copia=$(launcher_setting "$APP" COPIA)
  fi
  require_not_running "$existing_copia" "$existing_motore"

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
  if [ -d "$OLD_NESTED" ]; then
    launch_register -u "$OLD_NESTED/$NOME.app"
    rm_tree "$OLD_NESTED"
    removed_any=1
  fi
  if [ -d "$LEGACY_MOTORE" ]; then
    if [ "$existing_motore" = "$LEGACY_MOTORE" ] || [ -f "$LEGACY_MOTORE/colora.js" ]; then
      launch_register -u "$LEGACY_MOTORE/$NOME.app"
      rm_tree "$LEGACY_MOTORE"
      removed_any=1
    fi
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

# Is this folder the real Claude Desktop (not one of our launchers or copies)?
is_real_claude() {
  local a="${1%/}" id=""
  [ -d "$a/Contents" ] || return 1
  case "$a" in
    */ClaudeMultiAccount/*|*/.Trash/*|*" (app)/"*) return 1 ;;
  esac
  id=$(bundle_id "$a")
  case "$id" in
    local.claude-launcher.*|"") return 1 ;;
    com.anthropic.claudefordesktop) return 0 ;;
  esac
  # Another id: accept it only for an app named exactly Claude.app published by Anthropic.
  [ "$(basename "$a")" = "Claude.app" ] || return 1
  case "$id" in
    *anthropic*|*Anthropic*) return 0 ;;
  esac
  return 1
}

find_claude() {
  local c=""
  if [ -n "${CLAUDE_APP-}" ]; then
    if [ -d "$CLAUDE_APP/Contents" ]; then printf '%s' "${CLAUDE_APP%/}"; fi
    return 0
  fi
  for c in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    if [ -d "$c/Contents" ] && ! app_is_ours "$c"; then
      printf '%s' "$c"
      return 0
    fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r c; do
      if is_real_claude "$c"; then
        printf '%s' "$c"
        return 0
      fi
    done < <( { mdfind "kMDItemCFBundleIdentifier == 'com.anthropic.claudefordesktop'" 2>/dev/null
                mdfind "kMDItemFSName == 'Claude.app' && kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null; } )
  fi
  return 0
}

CLAUDE=""
UNINSTALL=0
if [ "${1-}" = "--uninstall" ]; then
  UNINSTALL=1
  shift
fi

if [ "$UNINSTALL" -eq 0 ]; then
  CLAUDE=$(find_claude)
  if [ -z "$CLAUDE" ]; then
    if [ -n "${CLAUDE_APP-}" ]; then
      die "❌ CLAUDE_APP does not point to an app: $CLAUDE_APP" "❌ CLAUDE_APP non indica un'app: $CLAUDE_APP"
    fi
    die "❌ Claude Desktop not found on this Mac. Install it from claude.ai/download and open it once." \
      "❌ Non trovo Claude Desktop su questo Mac. Installalo da claude.ai/download e aprilo una volta."
  fi
  echo "→ Claude: $CLAUDE"
fi

# ── Name and color ───────────────────────────────────────────────────────────
NOME="${1-}"
COLORE="${2-}"
if [ -z "$NOME" ]; then
  if [ "$UNINSTALL" -eq 1 ]; then
    read -r -p "$(t 'Name of the app to remove [Claude 2]: ' 'Nome della app da rimuovere [Claude 2]: ')" NOME < /dev/tty || true
  else
    read -r -p "$(t 'Name of the new app [Claude 2]: ' 'Nome della nuova app [Claude 2]: ')" NOME < /dev/tty || true
  fi
  if [ -z "$NOME" ]; then
    NOME="Claude 2"
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
  claude|anthropicclaude)
    die "❌ This name is reserved. Choose another one." "❌ Questo nome è riservato. Scegline un altro."
    ;;
esac
ID=$(printf '%s' "$NOME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
if [ -z "$ID" ]; then
  die "❌ The name needs at least one letter or number." "❌ Il nome deve contenere almeno una lettera o un numero."
fi

PREFIX="$HOME/Library/Application Support/ClaudeMultiAccount"
APP="$HOME/Applications/$NOME.app"
APPS="$PREFIX/apps"
NEW_DATI="$PREFIX/$NOME"
NEW_COPIA="$APPS/$NOME.app"
OLD_NESTED="$PREFIX/$NOME/app"
LEGACY_MOTORE="$HOME/Library/Application Support/$NOME (app)"
AGENT_LABEL="local.claude-multi-account.$ID"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
LOGFILE="$PREFIX/logs/$ID.log"
if [ "$NEW_DATI" = "$PREFIX" ] || [ "$NEW_DATI" = "$APPS" ]; then
  die "❌ This name is reserved. Choose another one." "❌ Questo nome è riservato. Scegline un altro."
fi

if [ "$UNINSTALL" -eq 1 ]; then
  do_uninstall
  exit 0
fi

if [ -z "$COLORE" ]; then
  read -r -p "$(t 'Icon color (blue, green, purple, pink, cyan, yellow, none) [blue]: ' 'Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]: ')" COLORE < /dev/tty || true
  COLORE="${COLORE:-blue}"
fi
COLORE=$(printf '%s' "$COLORE" | tr '[:upper:]' '[:lower:]')
# Hue shift in degrees, starting from Claude's orange.
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

# Keep the data folder recorded in an existing launcher so the sign-in survives.
DATI="$NEW_DATI"
COPIA="$NEW_COPIA"
EXISTING_DATI=""
EXISTING_MOTORE=""
EXISTING_COPIA=""
if [ -e "$APP" ]; then
  if ! app_is_ours "$APP"; then
    die "❌ \"$APP\" already exists and is not a Claude Multi Account launcher. Nothing was changed." \
      "❌ \"$APP\" esiste già e non è un launcher di Claude Multi Account. Non ho modificato nulla."
  fi
  EXISTING_DATI=$(launcher_setting "$APP" DATI)
  EXISTING_MOTORE=$(launcher_setting "$APP" MOTORE)
  EXISTING_COPIA=$(launcher_setting "$APP" COPIA)
  if [ -n "$EXISTING_DATI" ] && path_ok "$EXISTING_DATI"; then
    DATI="$EXISTING_DATI"
  fi
fi
require_not_running "$EXISTING_COPIA" "$EXISTING_MOTORE"
stop_agent

if [ -d "$LEGACY_MOTORE" ]; then
  if [ "$EXISTING_MOTORE" = "$LEGACY_MOTORE" ] || [ -f "$LEGACY_MOTORE/colora.js" ]; then
    launch_register -u "$LEGACY_MOTORE/$NOME.app"
    rm_tree "$LEGACY_MOTORE"
  fi
fi
if [ -d "$OLD_NESTED" ]; then
  launch_register -u "$OLD_NESTED/$NOME.app"
  rm_tree "$OLD_NESTED"
fi
if [ -d "$COPIA" ]; then
  launch_register -u "$COPIA"
  rm_tree "$COPIA"
fi
if [ -e "$APP" ]; then
  rm_tree "$APP"
fi

# ── 1. Folders ───────────────────────────────────────────────────────────────
echo "→ $(t 'Separate data folder' 'Cartella dati separata'): $DATI"
mkdir -p "$DATI" "$APPS" "$HOME/Applications" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ── 2. Icon recoloring tool (used now and after every Claude update) ────────
COLORA="$APP/Contents/Resources/colora.js"
cat > "$COLORA" <<'EOF'
ObjC.import('AppKit');
ObjC.import('CoreImage');

// Usage: osascript -l JavaScript colora.js <source app> <app to recolor> <degrees>
function run(argv) {
  var source = argv[0], target = argv[1], degrees = parseFloat(argv[2]);
  var S = 1024;

  // Draw Claude's icon at 1024x1024.
  var icon = $.NSWorkspace.sharedWorkspace.iconForFile(source);
  var canvas = $.NSImage.alloc.initWithSize($.NSMakeSize(S, S));
  canvas.lockFocus;
  icon.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, S, S), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  canvas.unlockFocus;

  // Shift the hue.
  var ci = $.CIImage.imageWithData(canvas.TIFFRepresentation);
  var filter = $.CIFilter.filterWithName('CIHueAdjust');
  filter.setValueForKey(ci, 'inputImage');
  filter.setValueForKey($.NSNumber.numberWithDouble(degrees * Math.PI / 180), 'inputAngle');
  var bitmap = $.NSBitmapImageRep.alloc.initWithCIImage(filter.valueForKey('outputImage'));
  var result = $.NSImage.alloc.initWithSize(bitmap.size);
  result.addRepresentation(bitmap);

  // Apply it as the app's custom icon.
  return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(result, target, 0) ? 'ok' : 'error';
}
EOF

# ── 3. Launcher app ──────────────────────────────────────────────────────────
echo "→ $(t 'Creating the app' "Creo l'app"): $APP"
cat > "$APP/Contents/Resources/config" <<EOF
SRC=$CLAUDE
COPIA=$COPIA
DATI=$DATI
NOME=$NOME
GRADI=$GRADI
COLORA=$COLORA
LOG=$LOGFILE
EOF

# Shared by the launcher and the guard.
cat > "$APP/Contents/Resources/common.sh" <<'EOF'
# Claude Multi Account – shared helpers (sourced, not run).
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
# Claude moved since install: look in the usual places.
if [ ! -d "$SRC" ]; then
  for c in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    if [ -d "$c" ]; then SRC="$c"; break; fi
  done
fi
COPIA="$(kv COPIA)"
DATI="$(kv DATI)"
GRADI="$(kv GRADI)"
COLORA="$(kv COLORA)"
LOG="$(kv LOG)"

log() {
  [ -n "$LOG" ] || return 0
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || return 0
  # Keep the log short.
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 300 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
}

version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }
# True if version $1 is newer than version $2 (dotted numbers).
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

# PIDs of the copy's main process, "good" = started with --user-data-dir, "bad" = without.
# Helpers live in Contents/Frameworks, so they don't match.
copy_pids() {
  local want="$1" pid cmd
  ps -axo pid=,command= | while read -r pid cmd; do
    case "$cmd" in
      "$COPIA/Contents/MacOS/"*) ;;
      *) continue ;;
    esac
    case "$cmd" in
      *--user-data-dir=*) [ "$want" = good ] && echo "$pid" ;;
      *) [ "$want" = bad ] && echo "$pid" ;;
    esac
  done
}

# Quit copies started without our data folder (after a Claude self-update,
# from a Dock icon, or reopened by macOS). They would show the main account.
stop_bad_copies() {
  local pids p i
  pids=$(copy_pids bad)
  [ -n "$pids" ] || return 1
  log "copy running without --user-data-dir (pid $(echo $pids)): restarting it"
  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  for i in $(seq 1 30); do
    [ -n "$(copy_pids bad)" ] || break
    sleep 0.5
  done
  for p in $(copy_pids bad); do kill -KILL "$p" 2>/dev/null; done
  return 0
}

fix_icon() {
  [ -n "$GRADI" ] && [ -d "$COPIA" ] || return 0
  if [ ! -e "$COPIA/Icon"$'\r' ]; then
    osascript -l JavaScript "$COLORA" "$SRC" "$COPIA" "$GRADI" >/dev/null 2>&1 && log "icon re-applied"
    touch "$COPIA"
  fi
}

launch_copy() {
  if [ -d "$COPIA" ]; then
    open -n -a "$COPIA" --args --user-data-dir="$DATI"
  else
    open -n -a "$SRC" --args --user-data-dir="$DATI"
  fi
}
EOF

LANCIATORE="$APP/Contents/MacOS/avvia"
cat > "$LANCIATORE" <<'EOF'
#!/bin/bash
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/Resources/common.sh"

# No color: launch Claude directly with the separate data folder.
if [ -z "$GRADI" ]; then
  exec open -n -a "$SRC" --args --user-data-dir="$DATI"
fi

# Already running the right way: just bring it to the front.
if [ -n "$(copy_pids good)" ]; then
  exec open -a "$COPIA"
fi
stop_bad_copies || true

# Build the copy the first time, or when the installed Claude is newer than it.
# The copy may also update itself: never replace it with an older version.
if [ ! -d "$COPIA" ] || newer "$(version "$SRC")" "$(version "$COPIA")"; then
  log "rebuilding the copy from $SRC ($(version "$SRC"))"
  rm -rf "$COPIA"
  # "cp -c" makes an APFS clone: instant and no extra disk space.
  cp -cR "$SRC" "$COPIA" 2>/dev/null || { rm -rf "$COPIA"; cp -R "$SRC" "$COPIA"; }
  xattr -dr com.apple.quarantine "$COPIA" 2>/dev/null
fi
fix_icon
launch_copy
EOF
chmod +x "$LANCIATORE"

# Guard: run every few seconds by launchd (see step 4b).
cat > "$APP/Contents/Resources/guard.sh" <<'EOF'
#!/bin/bash
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
[ -n "$GRADI" ] || exit 0
[ -d "$COPIA" ] || exit 0
if stop_bad_copies; then
  fix_icon
  launch_copy
  log "copy restarted with its own data folder"
else
  fix_icon
fi
EOF
chmod +x "$APP/Contents/Resources/guard.sh"

ICONA=$(defaults read "$CLAUDE/Contents/Info" CFBundleIconFile 2>/dev/null || echo "")
[ -n "$ICONA" ] && [[ "$ICONA" != *.icns ]] && ICONA="$ICONA.icns"
if [ -n "$ICONA" ] && [ -f "$CLAUDE/Contents/Resources/$ICONA" ]; then
  cp "$CLAUDE/Contents/Resources/$ICONA" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NOME</string>
  <key>CFBundleDisplayName</key><string>$NOME</string>
  <key>CFBundleIdentifier</key><string>local.claude-launcher.$ID</string>
  <key>CFBundleExecutable</key><string>avvia</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.1</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# ── 4. Colored icon on the launcher (the copy gets it on first launch) ───────
if [ -n "$GRADI" ]; then
  echo "→ $(t "Coloring the icon: $COLORE" "Coloro l'icona: $COLORE")"
  ESITO=$(osascript -l JavaScript "$COLORA" "$CLAUDE" "$APP" "$GRADI" 2>&1 || true)
  if [ "$ESITO" != "ok" ]; then
    t "⚠️  Colored icon not applied ($ESITO). The app still works, with the regular icon." \
      "⚠️  Icona colorata non applicata ($ESITO). L'app funziona lo stesso, con l'icona normale."
  fi
fi

# ── 4b. Guard ────────────────────────────────────────────────────────────────
# Claude updates itself during the night and then restarts without our
# --user-data-dir option, showing the main account. A small launchd job checks
# every few seconds and restarts the copy the right way.
if [ -n "$GRADI" ]; then
  echo "→ $(t 'Installing the guard that keeps the second account after Claude updates' "Installo il controllo che mantiene il secondo account dopo gli aggiornamenti di Claude")"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$APP/Contents/Resources/guard.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3</integer>
  <key>WatchPaths</key>
  <array>
    <string>$APPS</string>
  </array>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
</dict>
</plist>
EOF
  launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || launchctl load -w "$AGENT_PLIST" 2>/dev/null || true
fi

# ── 5. Register the new app with macOS ───────────────────────────────────────
touch "$APP"
launch_register -f "$APP"
restart_dock

echo ""
if [ "$LINGUA" = "it" ]; then
  echo "✅ Fatto! \"$NOME\" è in ~/Applications (la trovi anche con Spotlight)."
  echo ""
  echo "   Se \"$NOME\" è già aperta, chiudila (Cmd+Q) e riaprila per vedere la nuova icona."
  echo "   Il primo avvio può richiedere qualche secondo in più."
  echo ""
  echo "   Primo accesso: usa \"Continua con email\" e incolla il CODICE ricevuto"
  echo "   via email nella finestra (non cliccare il link nell'email)."
else
  echo "✅ Done! \"$NOME\" is in ~/Applications (you can also find it with Spotlight)."
  echo ""
  echo "   If \"$NOME\" is already open, quit it (Cmd+Q) and reopen it to see the new icon."
  echo "   The first launch may take a few extra seconds."
  echo ""
  echo "   First sign-in: use \"Continue with email\" and paste the CODE you receive"
  echo "   by email into the window (don't click the link in the email)."
fi
open -R "$APP"
