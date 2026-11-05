# Security Policy

🇮🇹 Italiano più sotto.

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Use GitHub's private reporting instead: go to the [Security tab](https://github.com/andrea6687/claude-multi-account/security) and choose **Report a vulnerability**. You'll get an answer as soon as possible, usually within a week.

Examples of what to report:

- a way for the scripts to delete or overwrite files they didn't create;
- a way to run unexpected code through the app name, color or paths;
- anything that could expose the sign-in data of either Claude account.

## Supported versions

Only the latest version on the `main` branch is supported. The install commands always download the latest version.

## Running the scripts safely

The install commands download a script and run it. If you prefer to check it first:

**Mac**
```bash
curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh -o install.sh
less install.sh
bash install.sh
```

**Windows**
```powershell
irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1 -OutFile install.ps1
notepad install.ps1
powershell -ExecutionPolicy Bypass -File install.ps1
```

The scripts don't need administrator rights, don't send data anywhere, and don't modify the original Claude app.

---

## Italiano

Per i problemi di sicurezza **non aprire una issue pubblica**: usa la [scheda Security](https://github.com/andrea6687/claude-multi-account/security) → **Report a vulnerability**, che è privata.

È supportata solo l'ultima versione su `main`. Se vuoi leggere lo script prima di eseguirlo, scaricalo con i comandi qui sopra, aprilo e poi lancialo. Gli script non chiedono permessi da amministratore, non inviano dati e non modificano l'app Claude originale.
