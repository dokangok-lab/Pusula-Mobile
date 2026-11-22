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

$Home2  = Join-Path $env:LOCALAPPDATA "PusulaZebra"
$CfgPrn = Join-Path $Home2 "drucker.txt"
$CfgDir = Join-Path $Home2 "ordner.txt"
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
  try { Send-Zpl $File $printer } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Read-Host "Enter druecken" }
  exit
}

$dir = Get-DownloadDir
Write-Host ""
Write-Host "  Pusula Zebra-Druck laeuft" -ForegroundColor Cyan
Write-Host ("  Drucker : " + $printer)
Write-Host ("  Ordner  : " + $dir)
Write-Host "  Etiketten aus der App werden jetzt sofort gedruckt."
Write-Host "  Dieses Fenster offen lassen (darf minimiert sein)."
Write-Host "  Anderen Drucker waehlen: Datei drucker.txt in $Home2 loeschen und neu starten."
Write-Host ""

while ($true) {
  try {
    $files = @(Get-ChildItem -LiteralPath $dir -Filter "pusula-etikett*.zpl" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($f in $files) {
      try { Send-Zpl $f.FullName $printer }
      catch { Write-Host ((Get-Date -Format "HH:mm:ss") + "  FEHLER: " + $_.Exception.Message) -ForegroundColor Red; Start-Sleep -Seconds 3 }
    }
  } catch {}
  Start-Sleep -Milliseconds 600
}
