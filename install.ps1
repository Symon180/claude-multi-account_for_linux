# ─────────────────────────────────────────────────────────────────────────────
#  Claude Multi Account – Windows
#
#  Creates a shortcut ("Claude 2") on the Desktop and in the Start menu that
#  launches Claude Desktop with a separate login, so you can use two accounts
#  side by side. It also gets an icon in a different color.
#  The original Claude app is never modified.
#
#  Usage (paste into PowerShell):
#    irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1 | iex
#  With name and color preset:
#    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1))) "Claude 2" blue
#
#  Colors: blue, green, purple, pink, cyan, yellow, none
#          (Italian names work too: blu, verde, viola, rosa, azzurro, giallo, nessuno)
#
#  FIRST SIGN-IN – IMPORTANT:
#    In the new window do NOT use "Continue with Google". Type your email,
#    press "Continue with email" and paste the CODE you receive by email
#    (don't click the link, or the other Claude will open).
#    Alternatively: fully quit the main Claude before signing in.
#
#  To remove: delete the shortcuts and the folder %APPDATA%\<name>
# ─────────────────────────────────────────────────────────────────────────────

param(
  [string]$Nome = "",
  [string]$Colore = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# Messages follow the system language: Italian if Windows is set to Italian, English otherwise.
$it = (Get-UICulture).TwoLetterISOLanguageName -eq "it"
function T([string]$en, [string]$itText) { if ($it) { $itText } else { $en } }

# ── Find Claude ──────────────────────────────────────────────────────────────
$base = Join-Path $env:LOCALAPPDATA "AnthropicClaude"
$update = Join-Path $base "Update.exe"
if (-not (Test-Path $update)) {
  Write-Host (T "Claude Desktop not found in $base" "Non trovo Claude Desktop in $base") -ForegroundColor Red
  Write-Host (T "Install it from claude.ai/download (Windows version) and try again." "Installalo da claude.ai/download (versione per Windows) e riprova.")
  return
}
$exe = Get-ChildItem $base -Directory -Filter "app-*" |
       Sort-Object Name -Descending |
       ForEach-Object { Join-Path $_.FullName "claude.exe" } |
       Where-Object { Test-Path $_ } | Select-Object -First 1

# ── Name and color ───────────────────────────────────────────────────────────
if (-not $Nome) {
  $Nome = Read-Host (T "Name of the shortcut [Claude 2]" "Nome del collegamento [Claude 2]")
  if (-not $Nome) { $Nome = "Claude 2" }
}
if (-not $Colore) {
  $Colore = Read-Host (T "Icon color (blue, green, purple, pink, cyan, yellow, none) [blue]" "Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]")
  if (-not $Colore) { $Colore = "blue" }
}
# Hue shift in degrees, starting from Claude's orange.
$degreesByColor = @{
  blue = 200; green = 110; purple = 255; pink = 315; cyan = 175; yellow = 35; none = 0
  blu = 200; verde = 110; viola = 255; rosa = 315; azzurro = 175; giallo = 35; nessuno = 0
}
$Colore = $Colore.ToLower()
if (-not $degreesByColor.ContainsKey($Colore)) {
  Write-Host (T "Unknown color: $Colore" "Colore non riconosciuto: $Colore") -ForegroundColor Red; return
}
$gradi = $degreesByColor[$Colore]
if ($Nome -notmatch '^[A-Za-z0-9 _-]+$') {
  Write-Host (T "The name may only contain letters, numbers, spaces, - and _" "Il nome può contenere solo lettere, numeri, spazi, - e _") -ForegroundColor Red; return
}

# ── 1. Separate data folder (where the second sign-in lives) ────────────────
$dati = Join-Path $env:APPDATA $Nome
New-Item -ItemType Directory -Force -Path $dati | Out-Null
Write-Host "-> $(T 'Separate data folder' 'Cartella dati separata'): $dati"
# Short path without spaces (e.g. C:\Users\MARIOR~1\...), so the shortcut doesn't break.
try { $datiSicuro = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($dati).ShortPath }
catch { $datiSicuro = $dati }

# ── 2. Colored icon ──────────────────────────────────────────────────────────
function HslToRgb([double]$h, [double]$s, [double]$l) {
  if ($s -eq 0) { $v = [int][math]::Round($l * 255); return @($v, $v, $v) }
  $q = if ($l -lt 0.5) { $l * (1 + $s) } else { $l + $s - $l * $s }
  $p = 2 * $l - $q
  $res = foreach ($t in @(($h + 1/3), $h, ($h - 1/3))) {
    if ($t -lt 0) { $t += 1 }; if ($t -gt 1) { $t -= 1 }
    if ($t -lt 1/6) { $c = $p + ($q - $p) * 6 * $t }
    elseif ($t -lt 1/2) { $c = $q }
    elseif ($t -lt 2/3) { $c = $p + ($q - $p) * (2/3 - $t) * 6 }
    else { $c = $p }
    [int][math]::Round([math]::Min(1, [math]::Max(0, $c)) * 255)
  }
  return $res
}

$iconPath = $null
$iconFolder = Join-Path $env:LOCALAPPDATA "ClaudeMultiAccount"
New-Item -ItemType Directory -Force -Path $iconFolder | Out-Null

if ($gradi -ne 0) {
  try {
    Write-Host "-> $(T "Coloring the icon: $Colore (a few seconds...)" "Coloro l'icona: $Colore (qualche secondo...)")"
    $ico = Join-Path $base "app.ico"
    if (Test-Path $ico) {
      $bmp = (New-Object System.Drawing.Icon($ico, 256, 256)).ToBitmap()
    } else {
      $bmp = [System.Drawing.Icon]::ExtractAssociatedIcon($exe).ToBitmap()
    }
    $out = New-Object System.Drawing.Bitmap($bmp.Width, $bmp.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $bmp.Height; $y++) {
      for ($x = 0; $x -lt $bmp.Width; $x++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.A -eq 0) { continue }
        $h = (($c.GetHue() + $gradi) % 360) / 360
        $rgb = HslToRgb $h $c.GetSaturation() $c.GetBrightness()
        $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c.A, $rgb[0], $rgb[1], $rgb[2]))
      }
    }
    # Save as .ico with PNG content (keeps transparency and quality).
    $ms = New-Object System.IO.MemoryStream
    $out.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $png = $ms.ToArray()
    $iconPath = Join-Path $iconFolder "$Nome.ico"
    $fs = [System.IO.File]::Create($iconPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]1)
    $w = if ($out.Width -ge 256) { 0 } else { $out.Width }
    $hh = if ($out.Height -ge 256) { 0 } else { $out.Height }
    $bw.Write([byte]$w); $bw.Write([byte]$hh); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$png.Length); $bw.Write([UInt32]22)
    $bw.Write($png)
    $bw.Close()
  } catch {
    Write-Host (T "Colored icon not applied ($($_.Exception.Message)). Using the regular icon." "Icona colorata non applicata ($($_.Exception.Message)). Uso l'icona normale.") -ForegroundColor Yellow
    $iconPath = $null
  }
}
if (-not $iconPath) { $iconPath = $exe }

# ── 3. Shortcuts on the Desktop and in the Start menu ───────────────────────
# Goes through Update.exe so the shortcut keeps working after Claude updates.
$shell = New-Object -ComObject WScript.Shell
$targets = @(
  [Environment]::GetFolderPath("Desktop"),
  (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs")
)
foreach ($folder in $targets) {
  $lnk = $shell.CreateShortcut((Join-Path $folder "$Nome.lnk"))
  $lnk.TargetPath = $update
  $lnk.Arguments = "--processStart claude.exe --process-start-args `"--user-data-dir=$datiSicuro`""
  $lnk.WorkingDirectory = $base
  $lnk.IconLocation = "$iconPath,0"
  $lnk.Description = (T "Claude with a second account" "Claude con un secondo account")
  $lnk.Save()
}

Write-Host ""
if ($it) {
  Write-Host "Fatto! Trovi `"$Nome`" sul Desktop e nel menu Start." -ForegroundColor Green
  Write-Host ""
  Write-Host "Primo accesso: usa `"Continua con email`" e incolla il CODICE ricevuto"
  Write-Host "via email nella finestra (non cliccare il link nell'email)."
  Write-Host "Puoi poi aggiungerlo alla barra delle applicazioni con tasto destro > Aggiungi."
} else {
  Write-Host "Done! You'll find `"$Nome`" on the Desktop and in the Start menu." -ForegroundColor Green
  Write-Host ""
  Write-Host "First sign-in: use `"Continue with email`" and paste the CODE you receive"
  Write-Host "by email into the window (don't click the link in the email)."
  Write-Host "You can then pin it to the taskbar with right-click > Pin."
}
