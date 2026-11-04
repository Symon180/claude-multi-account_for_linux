#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Claude Desktop – secondo account (macOS)
#
#  Crea una seconda app ("Claude 2") che avvia Claude Desktop con un login
#  separato, così puoi usare due account insieme. Le dà anche un'icona di
#  un altro colore, visibile anche nel Dock mentre l'app è aperta.
#  L'app Claude originale non viene modificata: per l'icona colorata viene
#  usata una copia "clone" di Claude.app, che non occupa spazio in più e viene
#  riallineata da sola quando Claude si aggiorna.
#
#  Uso (incolla nel Terminale):
#    curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash
#  Con nome e colore già scelti:
#    curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash -s -- "Claude 2" blu
#
#  Colori: blu, verde, viola, rosa, azzurro, giallo, nessuno
#
#  PRIMO LOGIN – IMPORTANTE:
#    Nella nuova app NON usare "Continua con Google". Scrivi l'email e premi
#    "Continua con email", poi copia il CODICE dall'email nella finestra
#    (non cliccare il link, altrimenti si apre l'altra app Claude).
#    In alternativa: chiudi l'app Claude principale (Cmd+Q) prima di accedere.
#
#  Per rimuoverla: cancella ~/Applications/<nome>.app e le cartelle
#  ~/Library/Application Support/<nome> e ~/Library/Application Support/<nome> (app)
# ─────────────────────────────────────────────────────────────────────────────

set -e

CLAUDE="/Applications/Claude.app"
if [ ! -d "$CLAUDE" ]; then
  echo "❌ Non trovo Claude in /Applications. Installa prima Claude Desktop da claude.ai/download"
  exit 1
fi

# ── Nome e colore ────────────────────────────────────────────────────────────
NOME="$1"
COLORE="$2"
if [ -z "$NOME" ]; then
  read -r -p "Nome della nuova app [Claude 2]: " NOME < /dev/tty || true
  NOME="${NOME:-Claude 2}"
fi
if [ -z "$COLORE" ]; then
  read -r -p "Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]: " COLORE < /dev/tty || true
  COLORE="${COLORE:-blu}"
fi
COLORE=$(echo "$COLORE" | tr '[:upper:]' '[:lower:]')
if [[ ! "$NOME" =~ ^[A-Za-z0-9\ _-]+$ ]]; then
  echo "❌ Il nome può contenere solo lettere, numeri, spazi, - e _"; exit 1
fi

# Spostamento di tonalità in gradi, partendo dall'arancio di Claude.
case "$COLORE" in
  blu)     GRADI=200 ;;
  verde)   GRADI=110 ;;
  viola)   GRADI=255 ;;
  rosa)    GRADI=315 ;;
  azzurro) GRADI=175 ;;
  giallo)  GRADI=35  ;;
  nessuno) GRADI=""  ;;
  *) echo "❌ Colore non riconosciuto: $COLORE"; exit 1 ;;
esac

APP="$HOME/Applications/$NOME.app"
DATI="$HOME/Library/Application Support/$NOME"          # login e impostazioni del secondo account
MOTORE="$HOME/Library/Application Support/$NOME (app)"  # copia di Claude con l'icona colorata

# ── 1. Cartelle ──────────────────────────────────────────────────────────────
echo "→ Cartella dati separata: $DATI"
mkdir -p "$DATI" "$MOTORE" "$HOME/Applications"

# ── 2. Strumento che colora l'icona (usato ora e a ogni aggiornamento) ──────
cat > "$MOTORE/colora.js" <<'EOF'
ObjC.import('AppKit');
ObjC.import('CoreImage');

// Uso: osascript -l JavaScript colora.js <app di origine> <app da colorare> <gradi>
function run(argv) {
  var originale = argv[0], destinazione = argv[1], gradi = parseFloat(argv[2]);
  var S = 1024;

  var icona = $.NSWorkspace.sharedWorkspace.iconForFile(originale);
  var tela = $.NSImage.alloc.initWithSize($.NSMakeSize(S, S));
  tela.lockFocus;
  icona.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, S, S), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  tela.unlockFocus;

  var ci = $.CIImage.imageWithData(tela.TIFFRepresentation);
  var filtro = $.CIFilter.filterWithName('CIHueAdjust');
  filtro.setValueForKey(ci, 'inputImage');
  filtro.setValueForKey($.NSNumber.numberWithDouble(gradi * Math.PI / 180), 'inputAngle');
  var bitmap = $.NSBitmapImageRep.alloc.initWithCIImage(filtro.valueForKey('outputImage'));
  var nuova = $.NSImage.alloc.initWithSize(bitmap.size);
  nuova.addRepresentation(bitmap);

  return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(nuova, destinazione, 0) ? 'ok' : 'errore';
}
EOF

# ── 3. App di avvio ──────────────────────────────────────────────────────────
echo "→ Creo l'app: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

LANCIATORE="$APP/Contents/MacOS/avvia"
{
  echo '#!/bin/bash'
  printf 'SRC=%q\nMOTORE=%q\nDATI=%q\nNOME=%q\nGRADI=%q\n' "$CLAUDE" "$MOTORE" "$DATI" "$NOME" "$GRADI"
  cat <<'EOF'

# Senza colore: avvia direttamente Claude con la cartella dati separata.
if [ -z "$GRADI" ]; then
  exec open -n -a "$SRC" --args --user-data-dir="$DATI"
fi

# Con colore: usa una copia di Claude con l'icona colorata, così l'icona
# resta colorata anche nel Dock mentre l'app è aperta.
COPIA="$MOTORE/$NOME.app"
versione() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }

if ! pgrep -f "$COPIA/Contents/MacOS/" >/dev/null 2>&1; then
  if [ ! -d "$COPIA" ] || [ "$(versione "$SRC")" != "$(versione "$COPIA")" ] || [ ! -e "$COPIA/Icon"$'\r' ]; then
    # Prima volta, Claude aggiornato o icona persa: ricrea la copia.
    rm -rf "$COPIA"
    # "cp -c" crea un clone APFS: istantaneo e senza spazio in più.
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

# ── 4. Icona colorata sull'app di avvio (la copia viene colorata al primo avvio) ─
if [ -n "$GRADI" ]; then
  echo "→ Coloro l'icona di $COLORE"
  # Se esiste una copia vecchia (installazione precedente), la si ricrea al prossimo avvio.
  rm -rf "$MOTORE/$NOME.app"
  ESITO=$(osascript -l JavaScript "$MOTORE/colora.js" "$CLAUDE" "$APP" "$GRADI" 2>&1 || true)
  if [ "$ESITO" != "ok" ]; then
    echo "⚠️  Icona colorata non applicata ($ESITO). L'app funziona lo stesso, con l'icona normale."
  fi
fi

# ── 5. Fa conoscere la nuova app a macOS ─────────────────────────────────────
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
killall Dock 2>/dev/null || true

echo ""
echo "✅ Fatto! \"$NOME\" è in ~/Applications (la trovi anche con Spotlight)."
echo ""
echo "   Se \"$NOME\" è già aperta, chiudila (Cmd+Q) e riaprila per vedere la nuova icona."
echo "   Il primo avvio può richiedere qualche secondo in più."
echo ""
echo "   Primo accesso: usa \"Continua con email\" e incolla il CODICE ricevuto"
echo "   via email nella finestra (non cliccare il link nell'email)."
open -R "$APP"
