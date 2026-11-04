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
#
#  Colors: blue, green, purple, pink, cyan, yellow, none
#          (Italian names work too: blu, verde, viola, rosa, azzurro, giallo, nessuno)
#
#  FIRST SIGN-IN – IMPORTANT:
#    In the new app do NOT use "Continue with Google". Type your email, press
#    "Continue with email", then paste the CODE from the email into the window
#    (don't click the link, or the other Claude app will open).
#    Alternatively: quit the main Claude app (Cmd+Q) before signing in.
#
#  To remove: delete ~/Applications/<name>.app and the folders
#  ~/Library/Application Support/<name> and ~/Library/Application Support/<name> (app)
# ─────────────────────────────────────────────────────────────────────────────

set -e

# Messages follow the system language: Italian if the Mac is set to Italian, English otherwise.
LINGUA=$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' "(),\n' | cut -c1-2)
t() { if [ "$LINGUA" = "it" ]; then echo "$2"; else echo "$1"; fi; }

CLAUDE="/Applications/Claude.app"
if [ ! -d "$CLAUDE" ]; then
  t "❌ Claude not found in /Applications. Install Claude Desktop first from claude.ai/download" \
    "❌ Non trovo Claude in /Applications. Installa prima Claude Desktop da claude.ai/download"
  exit 1
fi

# ── Name and color ───────────────────────────────────────────────────────────
NOME="$1"
COLORE="$2"
if [ -z "$NOME" ]; then
  read -r -p "$(t 'Name of the new app [Claude 2]: ' 'Nome della nuova app [Claude 2]: ')" NOME < /dev/tty || true
  NOME="${NOME:-Claude 2}"
fi
if [ -z "$COLORE" ]; then
  read -r -p "$(t 'Icon color (blue, green, purple, pink, cyan, yellow, none) [blue]: ' 'Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]: ')" COLORE < /dev/tty || true
  COLORE="${COLORE:-blue}"
fi
COLORE=$(echo "$COLORE" | tr '[:upper:]' '[:lower:]')
if [[ ! "$NOME" =~ ^[A-Za-z0-9\ _-]+$ ]]; then
  t "❌ The name may only contain letters, numbers, spaces, - and _" \
    "❌ Il nome può contenere solo lettere, numeri, spazi, - e _"
  exit 1
fi

# Hue shift in degrees, starting from Claude's orange.
case "$COLORE" in
  blue|blu)        GRADI=200 ;;
  green|verde)     GRADI=110 ;;
  purple|viola)    GRADI=255 ;;
  pink|rosa)       GRADI=315 ;;
  cyan|azzurro)    GRADI=175 ;;
  yellow|giallo)   GRADI=35  ;;
  none|nessuno)    GRADI=""  ;;
  *) t "❌ Unknown color: $COLORE" "❌ Colore non riconosciuto: $COLORE"; exit 1 ;;
esac

APP="$HOME/Applications/$NOME.app"
DATI="$HOME/Library/Application Support/$NOME"          # sign-in and settings of the second account
MOTORE="$HOME/Library/Application Support/$NOME (app)"  # copy of Claude with the colored icon

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
rm -rf "$APP"
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

if ! pgrep -f "$COPIA/Contents/MacOS/" >/dev/null 2>&1; then
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

ID=$(echo "$NOME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
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
  rm -rf "$MOTORE/$NOME.app"
  ESITO=$(osascript -l JavaScript "$MOTORE/colora.js" "$CLAUDE" "$APP" "$GRADI" 2>&1 || true)
  if [ "$ESITO" != "ok" ]; then
    t "⚠️  Colored icon not applied ($ESITO). The app still works, with the regular icon." \
      "⚠️  Icona colorata non applicata ($ESITO). L'app funziona lo stesso, con l'icona normale."
  fi
fi

# ── 5. Register the new app with macOS ───────────────────────────────────────
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
killall Dock 2>/dev/null || true

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
