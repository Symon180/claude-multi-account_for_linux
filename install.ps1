# ─────────────────────────────────────────────────────────────────────────────
#  Claude Desktop – secondo account (Windows)
#
#  Crea un collegamento ("Claude 2") sul Desktop e nel menu Start che avvia
#  Claude Desktop con un login separato, così puoi usare due account insieme.
#  Gli dà anche un'icona di un altro colore. Claude originale non viene toccato.
#
#  Uso (incolla in PowerShell):
#    irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1 | iex
#  Con nome e colore già scelti:
#    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/andrea6687/claude-multi-account/main/install.ps1))) "Claude 2" blu
#
#  Colori: blu, verde, viola, rosa, azzurro, giallo, nessuno
#
#  PRIMO LOGIN – IMPORTANTE:
#    Nella nuova finestra NON usare "Continua con Google". Scrivi l'email,
#    premi "Continua con email" e incolla il CODICE ricevuto via email
#    (non cliccare il link, altrimenti si apre l'altro Claude).
#    In alternativa: chiudi del tutto il Claude principale prima di accedere.
#
#  Per rimuoverlo: cancella i collegamenti e la cartella
#  %APPDATA%\<nome>
# ─────────────────────────────────────────────────────────────────────────────

param(
  [string]$Nome = "",
  [string]$Colore = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# ── Trova Claude ─────────────────────────────────────────────────────────────
$base = Join-Path $env:LOCALAPPDATA "AnthropicClaude"
$update = Join-Path $base "Update.exe"
if (-not (Test-Path $update)) {
  Write-Host "Non trovo Claude Desktop in $base" -ForegroundColor Red
  Write-Host "Installalo da claude.ai/download (versione per Windows) e riprova."
  return
}
$exe = Get-ChildItem $base -Directory -Filter "app-*" |
       Sort-Object Name -Descending |
       ForEach-Object { Join-Path $_.FullName "claude.exe" } |
       Where-Object { Test-Path $_ } | Select-Object -First 1

# ── Nome e colore ────────────────────────────────────────────────────────────
if (-not $Nome) {
  $Nome = Read-Host "Nome del collegamento [Claude 2]"
  if (-not $Nome) { $Nome = "Claude 2" }
}
if (-not $Colore) {
  $Colore = Read-Host "Colore icona (blu, verde, viola, rosa, azzurro, giallo, nessuno) [blu]"
  if (-not $Colore) { $Colore = "blu" }
}
$gradiPerColore = @{ blu = 200; verde = 110; viola = 255; rosa = 315; azzurro = 175; giallo = 35; nessuno = 0 }
$Colore = $Colore.ToLower()
if (-not $gradiPerColore.ContainsKey($Colore)) {
  Write-Host "Colore non riconosciuto: $Colore" -ForegroundColor Red; return
}
$gradi = $gradiPerColore[$Colore]
if ($Nome -notmatch '^[A-Za-z0-9 _-]+$') {
  Write-Host "Il nome può contenere solo lettere, numeri, spazi, - e _" -ForegroundColor Red; return
}

# ── 1. Cartella dati separata (qui vive il secondo login) ───────────────────
$dati = Join-Path $env:APPDATA $Nome
New-Item -ItemType Directory -Force -Path $dati | Out-Null
Write-Host "-> Cartella dati separata: $dati"
# Percorso "corto" senza spazi (es. C:\Users\MARIOR~1\...), così il collegamento non si rompe.
try { $datiSicuro = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($dati).ShortPath }
catch { $datiSicuro = $dati }

# ── 2. Icona colorata ────────────────────────────────────────────────────────
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

$iconaPath = $null
$cartellaIcone = Join-Path $env:LOCALAPPDATA "ClaudeSecondoAccount"
New-Item -ItemType Directory -Force -Path $cartellaIcone | Out-Null

if ($gradi -ne 0) {
  try {
    Write-Host "-> Coloro l'icona di $Colore (qualche secondo...)"
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
    # Salva come .ico (contenuto PNG, mantiene trasparenza e qualità).
    $ms = New-Object System.IO.MemoryStream
    $out.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $png = $ms.ToArray()
    $iconaPath = Join-Path $cartellaIcone "$Nome.ico"
    $fs = [System.IO.File]::Create($iconaPath)
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
    Write-Host "Icona colorata non applicata ($($_.Exception.Message)). Uso l'icona normale." -ForegroundColor Yellow
    $iconaPath = $null
  }
}
if (-not $iconaPath) { $iconaPath = $exe }

# ── 3. Collegamenti su Desktop e menu Start ─────────────────────────────────
# Passa da Update.exe così il collegamento continua a funzionare dopo gli aggiornamenti.
$shell = New-Object -ComObject WScript.Shell
$destinazioni = @(
  [Environment]::GetFolderPath("Desktop"),
  (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs")
)
foreach ($cartella in $destinazioni) {
  $lnk = $shell.CreateShortcut((Join-Path $cartella "$Nome.lnk"))
  $lnk.TargetPath = $update
  $lnk.Arguments = "--processStart claude.exe --process-start-args `"--user-data-dir=$datiSicuro`""
  $lnk.WorkingDirectory = $base
  $lnk.IconLocation = "$iconaPath,0"
  $lnk.Description = "Claude con un secondo account"
  $lnk.Save()
}

Write-Host ""
Write-Host "Fatto! Trovi `"$Nome`" sul Desktop e nel menu Start." -ForegroundColor Green
Write-Host ""
Write-Host "Primo accesso: usa `"Continua con email`" e incolla il CODICE ricevuto"
Write-Host "via email nella finestra (non cliccare il link nell'email)."
Write-Host "Puoi poi aggiungerlo alla barra delle applicazioni con tasto destro > Aggiungi."
