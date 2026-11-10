# Contributing

🇮🇹 Italiano più sotto.

Thanks for helping! Bug reports are the most useful contribution: this tool depends on how Claude Desktop is installed, and every computer is a little different.

## Reporting a bug

Open an [issue](https://github.com/andrea6687/claude-multi-account/issues/new/choose) with the bug template and include:

- your system (macOS, Windows, or Linux version);
- how Claude was installed (claude.ai/download, Microsoft Store, other);
- the exact command you ran;
- the full output of the script.

Before posting the output, remove anything private (your username in paths is fine to leave or replace with `<user>`).

## Suggesting an idea

Open an issue with the feature template and explain the problem you want to solve, not only the solution.

## Sending code

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Keep the two installers consistent: a change to `install.sh` (Mac) usually needs the same change in `install.ps1` (Windows), and the page `index.html` must keep generating valid commands.
3. Messages shown to the user must exist in English and Italian (see the `t` function in `install.sh` and `T` in `install.ps1`).
4. Never modify the original Claude app, and never delete anything the tool didn't create. Deleting the data folder must always ask first.
5. Check your changes:
   - `bash -n install.sh` and, if available, `shellcheck install.sh`;
   - for Windows, run the script on a real PC and say in the pull request what you tested.
6. Update both READMEs if the behavior changes.

## Scope

In scope: making two (or more) of your own Claude Desktop accounts usable side by side.
Out of scope: anything meant to get around Claude's usage limits, share accounts, or automate Claude without the official API.

---

## Italiano

Grazie per l'aiuto! Le segnalazioni di problemi sono il contributo più utile.

- **Problema:** apri una [issue](https://github.com/andrea6687/claude-multi-account/issues/new/choose) con il modello "bug" indicando sistema, come è installato Claude, il comando usato e tutto l'output dello script (togli eventuali dati privati).
- **Idea:** apri una issue con il modello "feature" e spiega il problema da risolvere.
- **Codice:** per modifiche non piccole apri prima una issue. Tieni allineati `install.sh` e `install.ps1`, scrivi i messaggi in inglese e italiano, non modificare mai l'app Claude originale e non cancellare nulla che lo strumento non abbia creato. Controlla con `bash -n install.sh` e prova su un computer vero.
- **Fuori tema:** qualsiasi cosa serva ad aggirare i limiti di Claude, condividere account o automatizzare Claude senza la API ufficiale.
