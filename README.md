# Claude Multi Account

🇮🇹 [Versione italiana](README.it.md)

Use **two Claude Desktop accounts at the same time**, each with its own sign-in, on Mac or Windows.
The script creates a second app (e.g. "Claude 2") that launches Claude Desktop with a separate data folder, and gives it an icon in a different color. The original Claude app is never modified.

👉 **Page with a simple interface:** https://andrea6687.github.io/claude-multi-account/
Pick a name and a color, copy the command and paste it.

## Quick install

**Mac** – open Terminal and paste:
```bash
curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash
```
Claude Desktop must already be in `/Applications` (the app from claude.ai/download).

**Windows** – open PowerShell and paste:
```powershell
irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1 | iex
```

The script asks for the app name and the icon color (blue, green, purple, pink, cyan, yellow, none). Its messages are in English, or in Italian if your computer is set to Italian.

The name is trimmed of spaces at the ends. It can't be empty, it can't be `Claude` or `AnthropicClaude`, and it needs at least one letter or number. Only letters, numbers, spaces, `-` and `_`.

With the name and color already chosen:

**Mac**
```bash
curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash -s -- "Claude 2" blue
```

**Windows**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1))) "Claude 2" blue
```

## First sign-in (important)

In the new app **don't use "Continue with Google"**. Type your email, press **"Continue with email"** and paste the **code** you receive by email into the window. If you click the link in the email, your system opens the other Claude and the sign-in ends up there.
Alternatively: fully quit the main Claude before signing in.

## How it works

Claude Desktop accepts the `--user-data-dir` option, which sets where sign-in and settings are stored. The new app launches the same Claude with a different folder, so the two instances don't see each other and each stays signed in to its own account. Claude updates apply to both.

- **Mac:** the app is created in `~/Applications`. Sign-in and settings go in `~/Library/Application Support/ClaudeMultiAccount/<name>/`. To keep the colored icon in the Dock while the app is running, an APFS clone of Claude.app lives in `~/Library/Application Support/ClaudeMultiAccount/<name>/app/`: it takes no extra disk space and is rebuilt when Claude updates, never while that copy is running. The Dock restarts for a moment so the new icon shows up. If a launcher from an older version of this tool is already there, its data folder is kept, so you stay signed in.
- **Windows:** shortcuts on the Desktop and in the Start menu. Data in `%APPDATA%\ClaudeMultiAccount\<name>`. Colored icons in `%LOCALAPPDATA%\ClaudeMultiAccount`. Requires Claude installed from claude.ai/download (not from the Microsoft Store). An older shortcut keeps the data folder it already points to.

## Remove

Quit the second app first (on Mac, Cmd+Q). The script asks in the terminal before deleting the data folder, because that folder is the sign-in. Running it again after everything is gone does nothing.

**Mac**
```bash
curl -fsSL https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.sh | bash -s -- --uninstall "Claude 2"
```
Removes `~/Applications/<name>.app` only when it is this tool's launcher, the data folder and the clone under `ClaudeMultiAccount/<name>`, and the old folders `~/Library/Application Support/<name>` and `~/Library/Application Support/<name> (app)` when that launcher pointed at them. The Dock restarts for a moment. If an app with that name is not ours, the script stops and deletes nothing.

**Windows**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1))) -Uninstall "Claude 2"
```
`--uninstall` works as the first argument in place of `-Uninstall`. Removes the Desktop and Start menu shortcuts only when they launch AnthropicClaude's `Update.exe` with `--user-data-dir`, the data folder, the `.ico` file, and `%LOCALAPPDATA%\ClaudeMultiAccount` when it is left empty. If a shortcut with that name is not ours, the script stops and deletes nothing.

## Limitations

- **Windows:** while the app is running, the taskbar shows Claude's regular icon; the colored one appears on the shortcut.
- **Mac:** after a Claude update, the first launch of "Claude 2" takes a few extra seconds while the copy is rebuilt.

## Notes

Unofficial tool, not affiliated with Anthropic. Use your own accounts: Claude's terms of service forbid sharing an account or using multiple accounts to get around limits or bans.
