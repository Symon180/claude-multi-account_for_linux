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
#  Remove (asks before deleting the data folder, which holds the sign-in):
#    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1))) -Uninstall "Claude 2"
#    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1))) --uninstall "Claude 2"
#
#  Colors: blue, green, purple, pink, cyan, yellow, none
#          (Italian names work too: blu, verde, viola, rosa, azzurro, giallo, nessuno)
#
#  Data: %APPDATA%\ClaudeMultiAccount\<name>
#  Icons: %LOCALAPPDATA%\ClaudeMultiAccount
#
#  FIRST SIGN-IN – IMPORTANT:
#    In the new window do NOT use "Continue with Google". Type your email,
#    press "Continue with email" and paste the CODE you receive by email
#    (don't click the link, or the other Claude will open).
#    Alternatively: fully quit the main Claude before signing in.
# ─────────────────────────────────────────────────────────────────────────────

& {
param(
  [Parameter(Position = 0)]
  [string]$Nome = "",
  [Parameter(Position = 1)]
  [string]$Colore = "",
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

if ($Nome -eq "--uninstall") {
  $Uninstall = $true
  $Nome = $Colore
  $Colore = ""
}

# Messages follow the system language: Italian if Windows is set to Italian, English otherwise.
$it = (Get-UICulture).TwoLetterISOLanguageName -eq "it"
function T([string]$en, [string]$itText) { if ($it) { $itText } else { $en } }

# ── Find Claude ──────────────────────────────────────────────────────────────
$base = $null
if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
  $base = Join-Path $env:LOCALAPPDATA "AnthropicClaude"
}
$update = $null
if ($base) { $update = Join-Path $base "Update.exe" }
$exe = $null
if ($update -and (Test-Path -LiteralPath $update)) {
  $exe = Get-ChildItem -LiteralPath $base -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "claude.exe" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
}
if (-not $Uninstall) {
  if (-not $update -or -not (Test-Path -LiteralPath $update)) {
    $where = if ($base) { $base } else { "%LOCALAPPDATA%\AnthropicClaude" }
    Write-Host (T "Claude Desktop not found in $where" "Non trovo Claude Desktop in $where") -ForegroundColor Red
    Write-Host (T "Install it from claude.ai/download (Windows version) and try again." "Installalo da claude.ai/download (versione per Windows) e riprova.")
    return
  }
  if (-not $exe) {
    Write-Host (T "No claude.exe found under $base (no app-* folder)." "Nessun claude.exe in $base (nessuna cartella app-*).") -ForegroundColor Red
    return
  }
}

# ── Name and color ───────────────────────────────────────────────────────────
if ([string]::IsNullOrEmpty($Nome)) {
  if ($Uninstall) {
    $Nome = Read-Host (T "Name of the app to remove [Claude 2]" "Nome della app da rimuovere [Claude 2]")
  } else {
    $Nome = Read-Host (T "Name of the shortcut [Claude 2]" "Nome del collegamento [Claude 2]")
  }
  if ([string]::IsNullOrEmpty($Nome)) { $Nome = "Claude 2" }
}
if ($null -eq $Nome) { $Nome = "" }
$Nome = $Nome.Trim()
if ([string]::IsNullOrWhiteSpace($Nome)) {
  Write-Host (T "The name is empty." "Il nome è vuoto.") -ForegroundColor Red
  return
}
if ($Nome -notmatch '^[A-Za-z0-9 _-]+$') {
  Write-Host (T "The name may only contain letters, numbers, spaces, - and _" "Il nome può contenere solo lettere, numeri, spazi, - e _") -ForegroundColor Red
  return
}
if ($Nome -match '^(claude|anthropicclaude)$') {
  Write-Host (T "This name is reserved. Choose another one." "Questo nome è riservato. Scegline un altro.") -ForegroundColor Red
  return
}
$id = ([regex]::Replace($Nome, '[^A-Za-z0-9]', '')).ToLowerInvariant()
if ([string]::IsNullOrEmpty($id)) {
  Write-Host (T "The name needs at least one letter or number." "Il nome deve contenere almeno una lettera o un numero.") -ForegroundColor Red
  return
}

if (-not $Uninstall) {
  if ([string]::IsNullOrEmpty($Colore)) {
    $Colore = Read-Host (T "Icon color (blue, green, purple, pink, cyan, yellow, none) [blue]" "Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]")
    if ([string]::IsNullOrEmpty($Colore)) { $Colore = "blue" }
  }
  $Colore = $Colore.Trim().ToLowerInvariant()
  # Hue shift in degrees, starting from Claude's orange.
  $degreesByColor = @{
    blue = 200; green = 110; purple = 255; pink = 315; cyan = 175; yellow = 35; none = 0
    blu = 200; verde = 110; viola = 255; rosa = 315; azzurro = 175; giallo = 35; nessuno = 0
  }
  if (-not $degreesByColor.ContainsKey($Colore)) {
    Write-Host (T "Unknown color: $Colore" "Colore non riconosciuto: $Colore") -ForegroundColor Red
    return
  }
  $gradi = $degreesByColor[$Colore]
}

if ([string]::IsNullOrEmpty($env:APPDATA) -or [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
  Write-Host (T "APPDATA or LOCALAPPDATA is not set." "APPDATA o LOCALAPPDATA non è impostata.") -ForegroundColor Red
  return
}

$prefix = Join-Path $env:APPDATA "ClaudeMultiAccount"
$newData = Join-Path $prefix $Nome
$iconFolder = Join-Path $env:LOCALAPPDATA "ClaudeMultiAccount"

function Test-SafeDataPath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $false }
  if ($path -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
  try { $full = [IO.Path]::GetFullPath($path).TrimEnd('\', '/') } catch { return $false }
  if (-not [IO.Path]::IsPathRooted($full)) { return $false }
  if ($full -match '^[A-Za-z]:$') { return $false }
  $banned = New-Object System.Collections.Generic.List[string]
  foreach ($root in @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA)) {
    if ([string]::IsNullOrEmpty($root)) { continue }
    try { [void]$banned.Add([IO.Path]::GetFullPath($root).TrimEnd('\', '/')) } catch {}
  }
  try { [void]$banned.Add([IO.Path]::GetFullPath((Join-Path $env:APPDATA "ClaudeMultiAccount")).TrimEnd('\', '/')) } catch {}
  try { [void]$banned.Add([IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "ClaudeMultiAccount")).TrimEnd('\', '/')) } catch {}
  foreach ($b in $banned) {
    if ([string]::Equals($full, $b, [StringComparison]::OrdinalIgnoreCase)) { return $false }
  }
  $norm = $full.Replace("/", "\")
  $underAppData = $false
  if (-not [string]::IsNullOrEmpty($env:APPDATA)) {
    try {
      $app = [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\', '/').Replace("/", "\")
      if ($norm.StartsWith($app + "\", [StringComparison]::OrdinalIgnoreCase)) { $underAppData = $true }
    } catch {}
  }
  # Short paths (C:\Users\NAME~1\AppData\Roaming\...) still contain AppData\Roaming.
  if (-not $underAppData -and $norm -notlike "*\AppData\Roaming\*" -and $norm -notlike "*\ClaudeMultiAccount\*") {
    return $false
  }
  return $true
}

function Test-OurLauncher($lnk) {
  $target = [string]$lnk.TargetPath
  $work = [string]$lnk.WorkingDirectory
  $arguments = [string]$lnk.Arguments
  if ($arguments -notlike "*--user-data-dir=*") { return $false }
  if ([IO.Path]::GetFileName($target) -ne "Update.exe") { return $false }
  $targetNorm = $target.Replace("/", "\")
  $workNorm = $work.Replace("/", "\")
  if ($targetNorm -like "*\AnthropicClaude\Update.exe") { return $true }
  if ($workNorm -like "*\AnthropicClaude") { return $true }
  return $false
}

function Get-LauncherDataDir([string]$arguments) {
  $m = [regex]::Match($arguments, '--process-start-args\s+"--user-data-dir=([^"]*)"')
  if ($m.Success) { return $m.Groups[1].Value }
  $m = [regex]::Match($arguments, '--user-data-dir="([^"]*)"')
  if ($m.Success) { return $m.Groups[1].Value }
  $m = [regex]::Match($arguments, '--user-data-dir=([^\s"]+)')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

$folders = @()
$desktop = [Environment]::GetFolderPath("Desktop")
if (-not [string]::IsNullOrEmpty($desktop)) { $folders += $desktop }
$folders += (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs")

$shell = $null
$existingData = $null
$lnkPaths = @()
foreach ($folder in $folders) {
  if ([string]::IsNullOrEmpty($folder)) { continue }
  $lnkPath = Join-Path $folder "$Nome.lnk"
  if (-not (Test-Path -LiteralPath $lnkPath)) { continue }
  if ($null -eq $shell) {
    try { $shell = New-Object -ComObject WScript.Shell }
    catch {
      Write-Host (T "Could not read the shortcut: $($_.Exception.Message)" "Impossibile leggere il collegamento: $($_.Exception.Message)") -ForegroundColor Red
      return
    }
  }
  $lnk = $shell.CreateShortcut($lnkPath)
  if (-not (Test-OurLauncher $lnk)) {
    Write-Host (T "$lnkPath already exists and is not our shortcut. Nothing was changed." "$lnkPath esiste già e non è un nostro collegamento. Non ho modificato nulla.") -ForegroundColor Red
    return
  }
  $lnkPaths += $lnkPath
  if (-not $existingData) {
    $parsed = Get-LauncherDataDir ([string]$lnk.Arguments)
    if (Test-SafeDataPath $parsed) { $existingData = $parsed }
  }
}

$dati = if ($existingData) { $existingData } else { $newData }

if ($Uninstall) {
  $removed = $false
  foreach ($lnkPath in $lnkPaths) {
    Remove-Item -LiteralPath $lnkPath -Force
    $removed = $true
  }
  $ico = Join-Path $iconFolder "$Nome.ico"
  if (Test-Path -LiteralPath $ico) {
    $icoFull = [IO.Path]::GetFullPath($ico)
    $iconRoot = [IO.Path]::GetFullPath($iconFolder).TrimEnd('\', '/')
    if ($icoFull.StartsWith($iconRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $icoFull.StartsWith($iconRoot + "\", [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $icoFull -Force
      $removed = $true
    }
  }
  if (Test-Path -LiteralPath $iconFolder) {
    $iconRoot = [IO.Path]::GetFullPath($iconFolder).TrimEnd('\', '/')
    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "ClaudeMultiAccount")).TrimEnd('\', '/')
    $left = @(Get-ChildItem -Force -LiteralPath $iconFolder -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0 -and [string]::Equals($iconRoot, $expected, [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $iconFolder -Force
    }
  }

  $dataDirs = New-Object System.Collections.Generic.List[string]
  foreach ($candidate in @($dati, $newData)) {
    if (-not (Test-SafeDataPath $candidate)) { continue }
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    $full = [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
    $seen = $false
    foreach ($have in $dataDirs) {
      if ([string]::Equals($have, $full, [StringComparison]::OrdinalIgnoreCase)) { $seen = $true }
    }
    # Old layout only if the shortcut pointed there. The new folder is always ours.
    $isNew = [string]::Equals($full, ([IO.Path]::GetFullPath($newData).TrimEnd('\', '/')), [StringComparison]::OrdinalIgnoreCase)
    $pointed = $existingData -and [string]::Equals($full, ([IO.Path]::GetFullPath($existingData).TrimEnd('\', '/')), [StringComparison]::OrdinalIgnoreCase)
    if (-not $seen -and ($isNew -or $pointed)) { [void]$dataDirs.Add($full) }
  }

  if ($dataDirs.Count -gt 0) {
    Write-Host (T "This folder holds the sign-in:" "Questa cartella contiene il login:")
    foreach ($dir in $dataDirs) { Write-Host "  $dir" }
    $ans = Read-Host (T "Delete the data folder? [y/N]" "Cancellare la cartella dati? [s/N]")
    if ($ans -match '^(y|yes|s|si|sì)$') {
      foreach ($dir in $dataDirs) {
        Remove-Item -LiteralPath $dir -Recurse -Force
      }
      $removed = $true
    } else {
      Write-Host (T "Data folder kept." "Cartella dati conservata.")
    }
  }
  if ($removed) {
    Write-Host (T "Removed." "Rimosso.") -ForegroundColor Green
  } elseif ($dataDirs.Count -eq 0) {
    Write-Host (T "Already removed. Nothing to delete." "Già rimosso. Niente da cancellare.")
  }
  return
}

# ── 1. Separate data folder (where the second sign-in lives) ────────────────
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
New-Item -ItemType Directory -Force -Path $iconFolder | Out-Null

if ($gradi -ne 0) {
  try {
    Add-Type -AssemblyName System.Drawing
    Write-Host "-> $(T "Coloring the icon: $Colore (a few seconds...)" "Coloro l'icona: $Colore (qualche secondo...)")"
    $ico = Join-Path $base "app.ico"
    if (Test-Path -LiteralPath $ico) {
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
if ($null -eq $shell) {
  try { $shell = New-Object -ComObject WScript.Shell }
  catch {
    Write-Host (T "Could not create the shortcut: $($_.Exception.Message)" "Impossibile creare il collegamento: $($_.Exception.Message)") -ForegroundColor Red
    return
  }
}
foreach ($folder in $folders) {
  if ([string]::IsNullOrEmpty($folder)) { continue }
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
} @args
