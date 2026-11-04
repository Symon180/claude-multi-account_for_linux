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
#  Claude Desktop must be in /Applications.
#  Data: ~/Library/Application Support/ClaudeMultiAccount/<name>/
#  Clone: ~/Library/Application Support/ClaudeMultiAccount/<name>/app/
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
    ""|"/"|"$HOME"|"$HOME/Applications"|"$HOME/Desktop"|"$HOME/Library"|"$HOME/Library/Application Support"|"$HOME/Library/Application Support/ClaudeMultiAccount")
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

# DATI= / MOTORE= lines are written with printf %q.
launcher_var() {
  local file="$1" key="$2" line="" val=""
  if [ -f "$file" ]; then
    line=$(grep -m1 "^${key}=" "$file" || true)
  fi
  case "$line" in
    "$key"=*) ;;
    *) printf '%s' ""; return 0 ;;
  esac
  # %q output is an assignment. Reject command separators and expansions.
  dollar='$'
  if [[ "$line" == *';'* || "$line" == *'|'* || "$line" == *'&'* || "$line" == *'`'* || "$line" == *"${dollar}("* || "$line" == *"${dollar}{"* ]]; then
    printf '%s' ""
    return 0
  fi
  val=$(bash --noprofile --norc -c 'eval "$1"; eval "printf %s \"\${$2}\""' _ "$line" "$key" 2>/dev/null || true)
  printf '%s' "$val"
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
  local existing_dati="" existing_motore="" removed_any=0 app_removed=0 declined=0 avvia d ans="" ans_lc=""
  local -a login_dirs=()
  avvia="$APP/Contents/MacOS/avvia"

  if [ -e "$APP" ]; then
    if ! app_is_ours "$APP"; then
      die "❌ \"$APP\" already exists and is not a Claude Multi Account launcher. Nothing was changed." \
        "❌ \"$APP\" esiste già e non è un launcher di Claude Multi Account. Non ho modificato nulla."
    fi
    existing_dati=$(launcher_var "$avvia" DATI)
    existing_motore=$(launcher_var "$avvia" MOTORE)
    rm_tree "$APP"
    removed_any=1
    app_removed=1
  fi

  if [ -d "$NEW_MOTORE" ]; then
    rm_tree "$NEW_MOTORE"
    removed_any=1
  fi
  if [ -d "$LEGACY_MOTORE" ]; then
    if [ "$existing_motore" = "$LEGACY_MOTORE" ] || [ -f "$LEGACY_MOTORE/colora.js" ]; then
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

CLAUDE="/Applications/Claude.app"
UNINSTALL=0
if [ "${1-}" = "--uninstall" ]; then
  UNINSTALL=1
  shift
fi

if [ "$UNINSTALL" -eq 0 ] && [ ! -d "$CLAUDE" ]; then
  die "❌ Claude not found in /Applications. Install Claude Desktop first from claude.ai/download" \
    "❌ Non trovo Claude in /Applications. Installa prima Claude Desktop da claude.ai/download"
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
NEW_DATI="$PREFIX/$NOME"
NEW_MOTORE="$PREFIX/$NOME/app"
LEGACY_MOTORE="$HOME/Library/Application Support/$NOME (app)"

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
MOTORE="$NEW_MOTORE"
if [ -e "$APP" ]; then
  if ! app_is_ours "$APP"; then
    die "❌ \"$APP\" already exists and is not a Claude Multi Account launcher. Nothing was changed." \
      "❌ \"$APP\" esiste già e non è un launcher di Claude Multi Account. Non ho modificato nulla."
  fi
  EXISTING_DATI=$(launcher_var "$APP/Contents/MacOS/avvia" DATI)
  if [ -n "$EXISTING_DATI" ] && path_ok "$EXISTING_DATI"; then
    DATI="$EXISTING_DATI"
  fi
  rm_tree "$APP"
fi

# ── 1. Folders ───────────────────────────────────────────────────────────────
echo "→ $(t 'Separate data folder' 'Cartella dati separata'): $DATI"
mkdir -p "$DATI" "$MOTORE" "$HOME/Applications"

# ── 2. Icon recoloring tool (used now and after every Claude update) ────────
cat > "$MOTORE/colora.js" <<'EOF'
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

LANCIATORE="$APP/Contents/MacOS/avvia"
{
  echo '#!/bin/bash'
  printf 'SRC=%q\nMOTORE=%q\nDATI=%q\nNOME=%q\nGRADI=%q\n' "$CLAUDE" "$MOTORE" "$DATI" "$NOME" "$GRADI"
  cat <<'EOF'

# No color: launch Claude directly with the separate data folder.
if [ -z "$GRADI" ]; then
  exec open -n -a "$SRC" --args --user-data-dir="$DATI"
fi

# With color: launch a copy of Claude that carries the colored icon,
# so the icon stays colored in the Dock while the app is running.
COPIA="$MOTORE/$NOME.app"
version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }

# Fixed-string match: pgrep -f is a regex, and parentheses in the path break it.
# Ignore the grep process itself so a self-match cannot block a rebuild.
if ! ps -axo command= | grep -F -- "$COPIA/Contents/MacOS/" | grep -qvF -- grep; then
  if [ ! -d "$COPIA" ] || [ "$(version "$SRC")" != "$(version "$COPIA")" ] || [ ! -e "$COPIA/Icon"$'\r' ]; then
    # First run, Claude updated, or icon lost: rebuild the copy.
    rm -rf "$COPIA"
    # "cp -c" makes an APFS clone: instant and no extra disk space.
    cp -cR "$SRC" "$COPIA" 2>/dev/null || { rm -rf "$COPIA"; cp -R "$SRC" "$COPIA"; }
    xattr -dr com.apple.quarantine "$COPIA" 2>/dev/null
    osascript -l JavaScript "$MOTORE/colora.js" "$SRC" "$COPIA" "$GRADI" >/dev/null 2>&1
  fi
fi

if [ -d "$COPIA" ]; then
  exec open -n -a "$COPIA" --args --user-data-dir="$DATI"
else
  exec open -n -a "$SRC" --args --user-data-dir="$DATI"
fi
EOF
} > "$LANCIATORE"
chmod +x "$LANCIATORE"

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
  # An older copy (previous install) will be rebuilt on next launch.
  rm -rf -- "$MOTORE/$NOME.app"
  ESITO=$(osascript -l JavaScript "$MOTORE/colora.js" "$CLAUDE" "$APP" "$GRADI" 2>&1 || true)
  if [ "$ESITO" != "ok" ]; then
    t "⚠️  Colored icon not applied ($ESITO). The app still works, with the regular icon." \
      "⚠️  Icona colorata non applicata ($ESITO). L'app funziona lo stesso, con l'icona normale."
  fi
fi

# ── 5. Register the new app with macOS ───────────────────────────────────────
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
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
