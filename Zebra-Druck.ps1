# Pusula Mobile - Zebra-Druck (Waechter)
# Druckt pusula-etikett*.zpl aus dem Download-Ordner sofort und ohne Druckfenster
# direkt (RAW) auf den Zebra-Etikettdrucker. Kein Freigeben, kein Zusatzprogramm.
param([string]$File = "")
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Pusula Zebra-Druck"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class PusulaRaw {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public class DOCINFO {
    [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
  }
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);
  [DllImport("winspool.drv", SetLastError = true)]
  public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFO di);
  [DllImport("winspool.drv", SetLastError = true)]
  public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError = true)]
  public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError = true)]
  public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError = true)]
  public static extern bool WritePrinter(IntPtr hPrinter, byte[] pBytes, int dwCount, out int dwWritten);
  public static void Send(string printer, byte[] data) {
    IntPtr h;
    if (!OpenPrinter(printer, out h, IntPtr.Zero)) throw new Exception("Drucker nicht gefunden: " + printer);
    try {
      DOCINFO di = new DOCINFO();
      di.pDocName = "Pusula Etikett";
      di.pDataType = "RAW";
      if (StartDocPrinter(h, 1, di) == 0) throw new Exception("Druckauftrag konnte nicht gestartet werden");
      StartPagePrinter(h);
      int written;
      bool ok = WritePrinter(h, data, data.Length, out written);
      EndPagePrinter(h);
      EndDocPrinter(h);
      if (!ok || written != data.Length) throw new Exception("Daten konnten nicht gesendet werden");
    } finally { ClosePrinter(h); }
  }
}
"@

Add-Type -AssemblyName System.Drawing
$Home2  = Join-Path $env:LOCALAPPDATA "PusulaZebra"
$CfgPrn = Join-Path $Home2 "drucker.txt"
$CfgDir = Join-Path $Home2 "ordner.txt"
$CfgCard = Join-Path $Home2 "kartendrucker.txt"
if (!(Test-Path $Home2)) { New-Item -ItemType Directory -Path $Home2 | Out-Null }

function Get-ZebraPrinter {
  if (Test-Path $CfgPrn) { $n = (Get-Content $CfgPrn -Raw).Trim(); if ($n) { return $n } }
  $all = @(Get-CimInstance Win32_Printer)
  $z = @($all | Where-Object { $_.DriverName -match "ZDesigner|Zebra" -or $_.Name -match "Zebra|ZDesigner|Etikett" })
  if ($z.Count -eq 0) {
    Write-Host ""
    Write-Host "Kein Zebra-Drucker automatisch gefunden. Installierte Drucker:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ("  [" + ($i + 1) + "] " + $all[$i].Name) }
    $k = Read-Host "Nummer des Etikettdruckers eingeben"
    $n = $all[[int]$k - 1].Name
  } elseif ($z.Count -gt 1) {
    Write-Host ""
    Write-Host "Mehrere Etikettdrucker gefunden:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $z.Count; $i++) { Write-Host ("  [" + ($i + 1) + "] " + $z[$i].Name) }
    $k = Read-Host "Nummer eingeben"
    $n = $z[[int]$k - 1].Name
  } else { $n = $z[0].Name }
  Set-Content -Path $CfgPrn -Value $n -Encoding UTF8
  return $n
}

function Get-CardPrinter {
  if (Test-Path $CfgCard) { $n = (Get-Content $CfgCard -Raw).Trim(); if ($n) { return $n } }
  $all = @(Get-CimInstance Win32_Printer)
  $c = @($all | Where-Object { ($_.Name + " " + $_.DriverName) -match "Smart|IDP|Evolis|Card|Karte|Datacard|Magicard|Fargo|Seaory|Pointman|Entrust|Zenius|Primacy|Badgy" -and $_.DriverName -notmatch "ZDesigner" })
  if ($c.Count -eq 1) { $n = $c[0].Name }
  else {
    $list = if ($c.Count -gt 1) { $c } else { $all }
    Write-Host ""
    Write-Host "Welcher Drucker ist der KARTENDRUCKER?" -ForegroundColor Yellow
    for ($i = 0; $i -lt $list.Count; $i++) { Write-Host ("  [" + ($i + 1) + "] " + $list[$i].Name) }
    Write-Host ("  [" + ($list.Count + 1) + "] Keiner - Kartendrucker nicht vorhanden / nicht in der Liste")
    $k = Read-Host "Nummer eingeben"
    $num = 0
    if (-not [int]::TryParse(($k + "").Trim(), [ref]$num) -or $num -lt 1 -or $num -gt $list.Count) {
      Write-Host ""
      Write-Host "  Karte kann NICHT gedruckt werden: kein Kartendrucker ausgewaehlt bzw. nicht vorhanden." -ForegroundColor Red
      Write-Host "  Bitte zuerst den Treiber des Kartendruckers installieren (Windows > Drucker & Scanner)." -ForegroundColor Yellow
      Write-Host "  Beim naechsten Kartendruck wird erneut gefragt." -ForegroundColor Yellow
      Write-Host ""
      return $null
    }
    $n = $list[$num - 1].Name
  }
  Set-Content -Path $CfgCard -Value $n -Encoding UTF8
  return $n
}

function Send-Card([string]$path) {
  $bytes = $null
  for ($t = 0; $t -lt 20 -and $null -eq $bytes; $t++) {
    try { $bytes = [System.IO.File]::ReadAllBytes($path) } catch { Start-Sleep -Milliseconds 250 }
  }
  if ($null -eq $bytes -or $bytes.Length -eq 0) { return }
  $ms = New-Object System.IO.MemoryStream(,$bytes)
  $img = [System.Drawing.Image]::FromStream($ms)
  $cardPrn = Get-CardPrinter
  if (-not $cardPrn) { $img.Dispose(); $ms.Dispose(); Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; return }
  $doc = New-Object System.Drawing.Printing.PrintDocument
  $doc.DocumentName = "Pusula Karte"
  $doc.PrinterSettings.PrinterName = $cardPrn
  if (-not $doc.PrinterSettings.IsValid) { $img.Dispose(); throw ("Kartendrucker nicht gefunden: " + $cardPrn) }
  $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
  $doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0,0,0,0)
  $best = $null
  foreach ($ps in $doc.PrinterSettings.PaperSizes) {
    $a = [Math]::Max($ps.Width, $ps.Height); $b = [Math]::Min($ps.Width, $ps.Height)
    if ([Math]::Abs($a - 337) -le 12 -and [Math]::Abs($b - 213) -le 12) { $best = $ps; break }
  }
  if ($best) { $doc.DefaultPageSettings.PaperSize = $best }
  $cur = $doc.DefaultPageSettings.PaperSize
  $doc.DefaultPageSettings.Landscape = ($cur.Width -lt $cur.Height)
  $script:cardImg = $img
  $doc.add_PrintPage({
    param($sender, $e)
    $e.Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $pb = $e.PageBounds
    $hx = $e.PageSettings.HardMarginX; $hy = $e.PageSettings.HardMarginY
    $e.Graphics.DrawImage($script:cardImg, [single](-$hx), [single](-$hy), [single]$pb.Width, [single]$pb.Height)
    $e.HasMorePages = $false
  })
  try { $doc.Print() } finally { $img.Dispose(); $ms.Dispose(); $doc.Dispose() }
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  Write-Host ((Get-Date -Format "HH:mm:ss") + "  Karte gedruckt auf " + $cardPrn) -ForegroundColor Green
}

function Get-DownloadDir {
  if (Test-Path $CfgDir) { $d = (Get-Content $CfgDir -Raw).Trim(); if ($d -and (Test-Path $d)) { return $d } }
  try {
    $v = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")."{374DE290-123F-4565-9164-39C4925E467B}"
    if ($v) { $d = [Environment]::ExpandEnvironmentVariables($v); if (Test-Path $d) { return $d } }
  } catch {}
  return (Join-Path $env:USERPROFILE "Downloads")
}

function Send-Zpl([string]$path, [string]$printer) {
  $bytes = $null
  for ($t = 0; $t -lt 20 -and $null -eq $bytes; $t++) {
    try { $bytes = [System.IO.File]::ReadAllBytes($path) } catch { Start-Sleep -Milliseconds 250 }
  }
  if ($null -eq $bytes -or $bytes.Length -eq 0) { return }
  [PusulaRaw]::Send($printer, $bytes)
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  Write-Host ((Get-Date -Format "HH:mm:ss") + "  gedruckt: " + (Split-Path $path -Leaf)) -ForegroundColor Green
}

# --- einmalig: nach %LOCALAPPDATA%\PusulaZebra kopieren und in den Autostart legen
$me = $MyInvocation.MyCommand.Path
$myDir = Split-Path $me
if ($myDir -ne $Home2) {
  Copy-Item -LiteralPath $me -Destination (Join-Path $Home2 "Zebra-Druck.ps1") -Force
  $bat = Join-Path $myDir "Zebra-Druck.bat"
  if (Test-Path $bat) { Copy-Item -LiteralPath $bat -Destination (Join-Path $Home2 "Zebra-Druck.bat") -Force }
}
try {
  $startup = [Environment]::GetFolderPath("Startup")
  $lnk = Join-Path $startup "Pusula Zebra-Druck.lnk"
  if (!(Test-Path $lnk)) {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = "powershell.exe"
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"" + (Join-Path $Home2 "Zebra-Druck.ps1") + "`""
    $s.WindowStyle = 7
    $s.WorkingDirectory = $Home2
    $s.Save()
    Write-Host "Autostart eingerichtet: startet ab jetzt automatisch mit Windows." -ForegroundColor Cyan
  }
} catch { Write-Host "Autostart konnte nicht eingerichtet werden (nicht schlimm)." -ForegroundColor Yellow }

$printer = Get-ZebraPrinter

# --- Einzeldatei (z. B. per Doppelklick / Oeffnen mit)
if ($File) {
  try { if ($File -match "\.png$") { Send-Card $File } else { Send-Zpl $File $printer } } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Read-Host "Enter druecken" }
  exit
}

# --- alte, noch laufende Waechter beenden (nach einem Update)
if (-not $File) { try {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match "Zebra-Druck\.ps1" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {} }

$dir = Get-DownloadDir
Write-Host ""
Write-Host "  Pusula Zebra-Druck laeuft" -ForegroundColor Cyan
Write-Host ("  Drucker : " + $printer)
Write-Host ("  Ordner  : " + $dir)
Write-Host "  Etiketten (Zebra) und Zertifikatskarten (Kartendrucker) aus der App"
Write-Host "  werden jetzt sofort gedruckt."
Write-Host "  Dieses Fenster offen lassen (darf minimiert sein)."
Write-Host "  Anderen Drucker waehlen: drucker.txt (Zebra) bzw. kartendrucker.txt"
Write-Host "  in $Home2 loeschen und neu starten."
Write-Host ""

while ($true) {
  try {
    $files = @(Get-ChildItem -LiteralPath $dir -Filter "pusula-etikett*.zpl" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($f in $files) {
      try { Send-Zpl $f.FullName $printer }
      catch { Write-Host ((Get-Date -Format "HH:mm:ss") + "  FEHLER: " + $_.Exception.Message) -ForegroundColor Red; Start-Sleep -Seconds 3 }
    }
    $cards = @(Get-ChildItem -LiteralPath $dir -Filter "pusula-karte*.png" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($f in $cards) {
      try { Send-Card $f.FullName }
      catch { Write-Host ((Get-Date -Format "HH:mm:ss") + "  FEHLER Karte: " + $_.Exception.Message) -ForegroundColor Red; Start-Sleep -Seconds 3 }
    }
  } catch {}
  Start-Sleep -Milliseconds 600
}
