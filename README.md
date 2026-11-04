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

**Windows** – open PowerShell and paste:
```powershell
irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1 | iex
```

The script asks for the app name and the icon color (blue, green, purple, pink, cyan, yellow, none). Its messages are in English, or in Italian if your computer is set to Italian.

## First sign-in (important)

In the new app **don't use "Continue with Google"**. Type your email, press **"Continue with email"** and paste the **code** you receive by email into the window. If you click the link in the email, your system opens the other Claude and the sign-in ends up there.
Alternatively: fully quit the main Claude before signing in.

## How it works

Claude Desktop accepts the `--user-data-dir` option, which sets where sign-in and settings are stored. The new app launches the same Claude with a different folder, so the two instances don't see each other and each stays signed in to its own account. Claude updates apply to both.

- **Mac:** the app is created in `~/Applications`, its data in `~/Library/Application Support/<name>`. To keep the colored icon in the Dock while the app is running, it uses an APFS "clone" copy of Claude.app in `~/Library/Application Support/<name> (app)`: it takes no extra disk space and is rebuilt automatically when Claude updates.
- **Windows:** shortcuts on the Desktop and in the Start menu, data in `%APPDATA%\<name>`. Requires Claude installed from claude.ai/download (not from the Microsoft Store).

## Limitations

- **Windows:** while the app is running, the taskbar shows Claude's regular icon; the colored one appears on the shortcut.
- **Mac:** after a Claude update, the first launch of "Claude 2" takes a few extra seconds while the copy is rebuilt.
- To remove everything, delete the app (or the shortcuts) and the data folders.

## Notes

Unofficial tool, not affiliated with Anthropic. Use your own accounts: Claude's terms of service forbid sharing an account or using multiple accounts to get around limits or bans.
