# Claude Multi Account

Usa **due account di Claude Desktop insieme**, ognuno con il suo login, su Mac o Windows.
Lo script crea una seconda app (es. "Claude 2") che avvia Claude Desktop con una cartella dati separata, e le dà un'icona di un altro colore. L'app Claude originale non viene modificata.

👉 **Pagina con interfaccia:** https://andrea6687.github.io/claude-multi-account/
Scegli nome e colore, copia il comando e incollalo.

## Installazione rapida

**Mac** – apri il Terminale e incolla:
```bash
curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash
```

**Windows** – apri PowerShell e incolla:
```powershell
irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1 | iex
```

Lo script chiede il nome dell'app e il colore dell'icona (blu, verde, viola, rosa, azzurro, giallo, nessuno).

## Il primo accesso (importante)

Nella nuova app **non usare "Continua con Google"**. Scrivi l'email, premi **"Continua con email"** e incolla nella finestra il **codice** che ricevi via email. Se clicchi il link nell'email, il sistema apre l'altro Claude e il login finisce lì.
In alternativa: chiudi del tutto il Claude principale prima di accedere.

## Come funziona

Claude Desktop accetta l'opzione `--user-data-dir`, che indica dove salvare login e impostazioni. La nuova app avvia lo stesso Claude con una cartella diversa, quindi le due istanze non si vedono e restano loggate ognuna con il suo account. Gli aggiornamenti di Claude valgono per entrambe.

- **Mac:** l'app viene creata in `~/Applications`, i dati in `~/Library/Application Support/<nome>`.
- **Windows:** collegamenti sul Desktop e nel menu Start, dati in `%APPDATA%\<nome>`. Serve Claude installato da claude.ai/download (non dal Microsoft Store).

## Limiti

- Con l'app aperta, il Dock / la barra delle applicazioni mostra l'icona normale di Claude: quella colorata compare solo sul collegamento.
- Per rimuovere tutto basta cancellare l'app (o i collegamenti) e la cartella dati.

## Note

Strumento non ufficiale, non affiliato ad Anthropic. Usa account tuoi: i termini d'uso di Claude vietano di condividere un account o di usare più account per aggirare limiti o blocchi.
