<#
  Second-hand Laptop AUTO CHECKER v4
  Made by Mahdi

  Checks hardware, anti-theft / company locks, remote-access and spy software, crash history,
  gives PASS / WARN / FAIL for each item, a final verdict, and saves an HTML report (English + Bangla or Chinese).
  Changes nothing on the laptop (brightness is restored after its test).

  Works on: Windows 10 / 11, Intel / AMD / ARM (Snapdragon), Windows PowerShell 5.1 and
  PowerShell 7, any Windows display language, with or without Administrator.

  Run:   double-click  START-LAPTOP-CHECK.bat
    or   powershell -ExecutionPolicy Bypass -File laptop-check.ps1
  Options:
    -StressSeconds 60       CPU heat test length in seconds (0 = skip)
    -BatteryTestMinutes 3   use a QUICK light-use battery test of this length (default: FULL test until the battery drops 20%)
    -Quick                  fast mode: no heat, battery, RAM, disk scan, disk speed or ping tests
    -NoAdmin                do not ask for Administrator
    (default)               automatic tests + HAND CHECKS: the screen tells the person what to do, step by step
    -Auto                   unattended: skips the hand checks and only lists them in the report
    -NoPrompt               skip the hand checks, the battery test and the speaker test (for quick runs)
    -NoOpen                 do not open the report at the end
    -OutDir <folder>        where to save the report (default: Reports folder of the kit)
    -Lang auto|bn|zh|en     report language next to English (default auto: Chinese on Chinese Windows, else Bangla)

  Kit layout: the .bat files, README files and Tools\ sit in the kit folder; this script and lang-*.json sit in app\.
#>
param([int]$StressSeconds = 60, [int]$BatteryTestMinutes = 3, [switch]$Quick, [switch]$Auto, [switch]$NoAdmin, [switch]$NoPrompt, [switch]$NoOpen, [string]$OutDir, [ValidateSet('auto', 'bn', 'zh', 'en')][string]$Lang = 'auto')

$ErrorActionPreference = 'SilentlyContinue'
if ($Quick) { $StressSeconds = 0 }

# ---------- Relaunch in 64-bit PowerShell and as Administrator (needed for SSD wear, TPM, disk scan, disk speed) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hostExe = (Get-Process -Id $PID).Path
$relaunch = ''
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $hostExe = "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe"; $relaunch = 'open' }
if (-not $isAdmin -and -not $NoAdmin) { $relaunch = 'runas' }
if ($relaunch -and $PSCommandPath) {
  $passArgs = foreach ($k in $PSBoundParameters.Keys) {
    $v = $PSBoundParameters[$k]
    if ($v -is [switch]) { if ($v.IsPresent) { "-$k" } } else { "-$k `"$("$v".TrimEnd('\'))`"" }
  }
  # no -NoExit: an Administrator shell must not stay open on someone else's laptop; the script pauses at the end instead
  $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($passArgs -join ' ')"
  try {
    if ($relaunch -eq 'runas') {
      Write-Host "Asking for Administrator permission..." -ForegroundColor Yellow
      Start-Process $hostExe -Verb RunAs -ArgumentList $argList -ErrorAction Stop
    } else { Start-Process $hostExe -ArgumentList $argList -ErrorAction Stop }
    exit
  } catch { Write-Host "Running without Administrator - SSD wear, TPM, disk scan and disk speed will be skipped." -ForegroundColor Yellow }
}

# ---------- Kit folder, language, report folder (decided early: the battery test keeps a log in Reports) ----------
$appDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$inKit = (Split-Path $appDir -Leaf) -eq 'app'
$KitRoot = if ($inKit) { Split-Path $appDir } else { $appDir }
# a kit downloaded as a ZIP (WeChat, browser) is marked "from the internet"; unmark it so the tools open without warnings.
# Only inside the kit's own app\ and Tools\ folders: run from Downloads or Desktop, this must never touch other files.
if ($inKit) {
  foreach ($sub in 'app', 'Tools') {
    $subDir = Join-Path $KitRoot $sub
    if (Test-Path $subDir) { Get-ChildItem -LiteralPath $subDir -Recurse -File | Unblock-File }
  }
}
if ($Lang -eq 'auto') { $Lang = if ([Globalization.CultureInfo]::CurrentUICulture.Name -like 'zh*') { 'zh' } else { 'bn' } }
$tr = $null
$lf = Join-Path $appDir "lang-$Lang.json"
if ($Lang -ne 'en' -and (Test-Path $lf)) { $tr = Get-Content $lf -Raw -Encoding UTF8 | ConvertFrom-Json }
if (-not $OutDir) { $OutDir = Join-Path $KitRoot 'Reports' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
try { [IO.File]::WriteAllText((Join-Path $OutDir '.write-test'), 'x'); Remove-Item (Join-Path $OutDir '.write-test') -Force } catch { $OutDir = [Environment]::GetFolderPath('Desktop') }

# ---------- Helpers ----------
$Results = New-Object System.Collections.Generic.List[object]
$Colors = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }
$script:Sec = ''
function Add-R($cat, $status, $msg) {
  $Results.Add([PSCustomObject]@{ Section = $script:Sec; Category = $cat; Status = $status; Detail = $msg })
  Write-Host ("  [{0}] {1,-13} {2}" -f $status, $cat, $msg) -ForegroundColor $Colors[$status]
}
# overall progress: every section has a weight (about how long it takes); the % shows in the window title and section headers
$script:Weights = @{}; $script:SecNum = 0; $script:OverallPct = 0
function Update-Overall($frac = 0) {
  $tot = ($script:Weights.Values | Measure-Object -Sum).Sum
  if (-not $tot) { return }
  $before = ($script:Weights.Keys | Where-Object { $_ -lt $script:SecNum } | ForEach-Object { $script:Weights[$_] } | Measure-Object -Sum).Sum
  # 1.0 not 1: with an int first argument PowerShell picks Math.Min(int, int) and rounds 0.2 down to 0
  $script:OverallPct = [int][math]::Min(99.0, ($before + [double]$script:Weights[$script:SecNum] * [math]::Min(1.0, [double]$frac)) * 100 / $tot)
  try { $Host.UI.RawUI.WindowTitle = "Laptop Checker - $($script:OverallPct)% done - Made by Mahdi" } catch {}
}
# time per section, written to the debug log next to the report (helps when a test hangs on someone's laptop)
$script:SecLog = New-Object System.Collections.Generic.List[string]; $script:SecStart = Get-Date
function Close-SectionTime {
  if ($script:Sec) { $script:SecLog.Add(("{0,7:N1} s  {1}" -f ((Get-Date) - $script:SecStart).TotalSeconds, $script:Sec)) }
  $script:SecStart = Get-Date
}
function Section($t) {
  Close-SectionTime
  $script:Sec = $t
  if ($t -match '^(\d+)\.') { $script:SecNum = [int]$Matches[1] }
  Update-Overall 0
  Write-Host "`n>> [$($script:OverallPct)%] $t" -ForegroundColor Cyan
}
function Skip-Section($err) { Add-R "Error" INFO "Part of this check could not run here: $($err.Exception.Message)" }
function Ascii($b) { if ($b) { ([Text.Encoding]::ASCII.GetString($b)).Trim([char]0).Trim() } }
function Get-Events($filter, $max = 500) { @(Get-WinEvent -FilterHashtable $filter -MaxEvents $max -ErrorAction SilentlyContinue) }
function Get-Span($s) { try { if ("$s") { [Xml.XmlConvert]::ToTimeSpan("$s") } } catch {} }
function Format-Hours($h) { '{0}h {1:00}m' -f [int][math]::Floor($h), [int](($h % 1) * 60) }
function Get-BatState {
  $wb = Get-CimInstance Win32_Battery | Select-Object -First 1
  $bs = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus)
  [PSCustomObject]@{
    Pct  = [int]$wb.EstimatedChargeRemaining
    OnAC = if ($bs) { [bool]($bs | Where-Object PowerOnline) } else { $wb.BatteryStatus -in 2, 6, 7, 8, 9 }
    Rem  = [double]($bs | Measure-Object RemainingCapacity -Sum).Sum
    Rate = [double]($bs | Measure-Object DischargeRate -Sum).Sum
    Volt = [double]($bs | Select-Object -First 1).Voltage
    DesignVolt = [double]$wb.DesignVoltage
  }
}
function Get-Brightness { $b = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness | Select-Object -First 1; if ($b) { [int]$b.CurrentBrightness } }
function Set-Brightness($v) {
  $m = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods | Select-Object -First 1
  if ($m) { Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$v } | Out-Null; $true } else { $false }
}
# runs a block in a background job and gives up after $Seconds (some Windows parts hang on broken PCs)
function Invoke-Timeout([scriptblock]$Block, [int]$Seconds = 45) {
  $j = Start-Job -ScriptBlock $Block
  $done = Wait-Job $j -Timeout $Seconds
  $out = if ($done) { Receive-Job $j } else { $null }
  Remove-Job $j -Force
  if (-not $done) { Write-Host "  (a Windows component did not answer in $Seconds sec - skipped)" -ForegroundColor DarkGray }
  $out
}
# WMI queries give up instead of hanging forever on a PC with broken WMI
$PSDefaultParameterValues['Get-CimInstance:OperationTimeoutSec'] = 60
function Get-CpuTemp {
  $t = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation | ForEach-Object { [math]::Round($_.Temperature - 273.15) })
  if ($isAdmin) { $t += @(Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) }) }
  $t = @($t | Where-Object { $_ -gt 0 -and $_ -lt 120 })
  if ($t) { ($t | Measure-Object -Maximum).Maximum } else { 0 }
}
function Start-Burn($threads) { if ($script:Native) { [LcBurn]::Start($threads); $true } else { $false } }
function Stop-Burn { if ($script:Native) { [LcBurn]::Stop() } }

# Native helpers: real CPU load, RAM pattern test, raw disk scan, microphone level, stereo tones, key polling.
# If C# compiling is blocked on a PC, those tests fall back or are skipped.
$nativeCode = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

public static class LcBurn {
  static volatile bool run; public static double Sink;
  public static void Start(int n) {
    run = true;
    for (int i = 0; i < n; i++) {
      Thread t = new Thread(() => { double x = 0; while (run) { for (int k = 1; k < 2000000; k++) x += Math.Sqrt(k) * Math.Sin(k); } Sink = x; });
      t.IsBackground = true; t.Priority = ThreadPriority.BelowNormal; t.Start();
    }
  }
  public static void Stop() { run = false; }
}

public static class LcKeys {
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] static extern short GetKeyState(int vk);
  public static bool Hit(int vk) { return (GetAsyncKeyState(vk) & 0x8001) != 0; }
  public static bool Down(int vk) { return (GetKeyState(vk) & 0x8000) != 0; }
}

public static class LcScreen {
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}

public static class LcRam {
  public static volatile bool Running; public static long Errors, TestedMB, DoneMB;
  public static void Start(long mb) { Running = true; Errors = 0; TestedMB = 0; DoneMB = 0; Thread t = new Thread(() => Run(mb)); t.IsBackground = true; t.Start(); }
  static void Run(long mb) {
    try {
      const int n = 8 * 1024 * 1024;
      List<long[]> chunks = new List<long[]>();
      try { while (chunks.Count * 64L < mb) chunks.Add(new long[n]); } catch (OutOfMemoryException) { }
      TestedMB = chunks.Count * 64L;
      ulong[] seeds = { 0x5555555555555555UL, 0xAAAAAAAAAAAAAAAAUL, 0x0F1E2D3C4B5A6978UL };
      foreach (ulong s in seeds) {
        ulong seed = s;
        Parallel.For(0, chunks.Count, c => {
          long[] a = chunks[c]; ulong b = (ulong)c * n;
          for (int i = 0; i < a.Length; i++) a[i] = unchecked((long)(seed ^ ((b + (ulong)i) * 0x9E3779B97F4A7C15UL)));
        });
        Parallel.For(0, chunks.Count, c => {
          long[] a = chunks[c]; ulong b = (ulong)c * n; long e = 0;
          for (int i = 0; i < a.Length; i++) if (a[i] != unchecked((long)(seed ^ ((b + (ulong)i) * 0x9E3779B97F4A7C15UL)))) e++;
          if (e > 0) Interlocked.Add(ref Errors, e);
          Interlocked.Add(ref DoneMB, 64);
        });
      }
      chunks.Clear();
    } finally { GC.Collect(); Running = false; }
  }
}

public static class LcDisk {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(IntPtr h, IntPtr buf, uint n, out uint read, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFilePointerEx(IntPtr h, long dist, out long pos, uint method);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAlloc(IntPtr addr, UIntPtr size, uint type, uint protect);
  [DllImport("kernel32.dll")] static extern bool VirtualFree(IntPtr addr, UIntPtr size, uint type);
  public static volatile bool Running, Opened; public static volatile int Done; public static int Errors, Slow; public static double MaxMs, AvgMs;
  public static void Start(string path, long size, int samples, int slowMs, int maxSeconds) {
    Running = true; Opened = false; Done = 0; Errors = 0; Slow = 0; MaxMs = 0; AvgMs = 0;
    Thread t = new Thread(() => Scan(path, size, samples, slowMs, maxSeconds)); t.IsBackground = true; t.Start();
  }
  // read-only: reads 256 KB at evenly spread places over the whole disk, unbuffered, and times each read
  static void Scan(string path, long size, int samples, int slowMs, int maxSeconds) {
    IntPtr h = new IntPtr(-1); IntPtr buf = IntPtr.Zero;
    try {
      h = CreateFile(path, 0x80000000, 3, IntPtr.Zero, 3, 0x20000000, IntPtr.Zero);
      if (h.ToInt64() == -1) return;
      Opened = true;
      const int block = 262144;
      buf = VirtualAlloc(IntPtr.Zero, new UIntPtr((uint)block), 0x3000, 4);
      long span = (size - block) / 4096; double total = 0;
      Stopwatch all = Stopwatch.StartNew(); Stopwatch sw = new Stopwatch();
      for (int i = 0; i < samples && all.Elapsed.TotalSeconds < maxSeconds; i++) {
        long pos = span * i / samples * 4096; long np; uint rd;
        sw.Restart();
        bool ok = SetFilePointerEx(h, pos, out np, 0) && ReadFile(h, buf, (uint)block, out rd, IntPtr.Zero) && rd == block;
        sw.Stop(); double ms = sw.Elapsed.TotalMilliseconds; total += ms;
        if (ms > MaxMs) MaxMs = ms;
        if (!ok) Errors++; else if (ms > slowMs) Slow++;
        Done = i + 1;
      }
      AvgMs = Done > 0 ? total / Done : 0;
    } finally {
      if (buf != IntPtr.Zero) VirtualFree(buf, UIntPtr.Zero, 0x8000);
      if (h.ToInt64() != -1) CloseHandle(h);
      Running = false;
    }
  }
}

public static class LcMic {
  [StructLayout(LayoutKind.Sequential)] struct WFX { public ushort tag, ch; public uint rate, bps; public ushort align, bits, cb; }
  [StructLayout(LayoutKind.Sequential)] struct HDR { public IntPtr data; public uint len, rec; public IntPtr user; public uint flags, loops; public IntPtr next, res; }
  [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, uint dev, ref WFX f, IntPtr cb, IntPtr inst, uint flags);
  [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, uint size);
  [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, uint size);
  [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, uint size);
  [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);
  static IntPtr h = IntPtr.Zero;
  public static bool Open() {
    WFX f = new WFX(); f.tag = 1; f.ch = 1; f.rate = 16000; f.bits = 16; f.align = 2; f.bps = 32000;
    if (waveInOpen(out h, 0xFFFFFFFF, ref f, IntPtr.Zero, IntPtr.Zero, 0) != 0) { h = IntPtr.Zero; return false; }
    return waveInStart(h) == 0;
  }
  // records ms milliseconds and returns the loudest level 0-100, or -1 on error
  public static int Peak(int ms) {
    if (h == IntPtr.Zero) return -1;
    int bytes = 32 * ms; IntPtr data = Marshal.AllocHGlobal(bytes);
    int size = Marshal.SizeOf(typeof(HDR)); IntPtr hp = Marshal.AllocHGlobal(size);
    HDR hd = new HDR(); hd.data = data; hd.len = (uint)bytes; Marshal.StructureToPtr(hd, hp, false);
    int fOff = (int)Marshal.OffsetOf(typeof(HDR), "flags"); int rOff = (int)Marshal.OffsetOf(typeof(HDR), "rec");
    int peak = -1;
    try {
      if (waveInPrepareHeader(h, hp, (uint)size) != 0) return -1;
      if (waveInAddBuffer(h, hp, (uint)size) == 0) {
        DateTime end = DateTime.Now.AddMilliseconds(ms + 1500);
        while ((Marshal.ReadInt32(hp, fOff) & 1) == 0 && DateTime.Now < end) Thread.Sleep(10);
        if ((Marshal.ReadInt32(hp, fOff) & 1) == 0) { waveInReset(h); waveInStart(h); }
        else {
          int rec = Marshal.ReadInt32(hp, rOff); short[] s = new short[rec / 2]; Marshal.Copy(data, s, 0, s.Length);
          int mx = 0; foreach (short v in s) { int a = v < 0 ? -v : v; if (a > mx) mx = a; }
          peak = mx * 100 / 32768;
        }
      }
      waveInUnprepareHeader(h, hp, (uint)size);
    } finally { Marshal.FreeHGlobal(hp); Marshal.FreeHGlobal(data); }
    return peak;
  }
  public static void Close() { if (h != IntPtr.Zero) { waveInReset(h); waveInClose(h); h = IntPtr.Zero; } }
}

public static class LcTone {
  // stereo WAV with a tone on one side only (0 = left, 1 = right)
  public static byte[] Wav(int freq, double sec, int side) { return Sweep(freq, freq, sec, side); }
  // rising tone from f1 to f2 Hz; a sweep is not removed by the mic's noise suppression like a steady tone can be
  public static byte[] Sweep(int f1, int f2, double sec, int side) {
    int rate = 44100, n = (int)(rate * sec);
    MemoryStream ms = new MemoryStream(); BinaryWriter w = new BinaryWriter(ms);
    w.Write("RIFF".ToCharArray()); w.Write(36 + n * 4); w.Write("WAVEfmt ".ToCharArray()); w.Write(16);
    w.Write((short)1); w.Write((short)2); w.Write(rate); w.Write(rate * 4); w.Write((short)4); w.Write((short)16);
    w.Write("data".ToCharArray()); w.Write(n * 4);
    double ph = 0;
    for (int i = 0; i < n; i++) {
      double env = Math.Min(1.0, Math.Min(i, n - i) / 2000.0);
      ph += 2 * Math.PI * (f1 + (f2 - f1) * (double)i / n) / rate;
      short v = (short)(Math.Sin(ph) * 14000 * env);
      w.Write(side == 0 ? v : (short)0); w.Write(side == 1 ? v : (short)0);
    }
    w.Flush(); return ms.ToArray();
  }
}

// speaker volume and mute of the default output device (Windows Core Audio), so the auto test can restore them
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class LcDeviceEnumeratorCom { }
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ILcDeviceEnumerator { int EnumAudioEndpoints(); [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out ILcDevice dev); }
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ILcDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ILcEndpointVolume {
  int RegisterControlChangeNotify(); int UnregisterControlChangeNotify(); int GetChannelCount();
  int SetMasterVolumeLevel(float l, Guid c); int SetMasterVolumeLevelScalar(float l, Guid c);
  int GetMasterVolumeLevel(out float l); int GetMasterVolumeLevelScalar(out float l);
  int SetChannelVolumeLevel(); int SetChannelVolumeLevelScalar(); int GetChannelVolumeLevel(); int GetChannelVolumeLevelScalar();
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, Guid c); int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m);
}
public static class LcAudio {
  static ILcEndpointVolume Ep() {
    ILcDeviceEnumerator en = (ILcDeviceEnumerator)(new LcDeviceEnumeratorCom());
    ILcDevice dev; if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return null;
    Guid iid = typeof(ILcEndpointVolume).GUID; object o;
    if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return null;
    return (ILcEndpointVolume)o;
  }
  // -1 when there is no output device
  public static float GetVolume() { try { ILcEndpointVolume e = Ep(); if (e == null) return -1; float v; e.GetMasterVolumeLevelScalar(out v); return v; } catch { return -1; } }
  public static bool GetMute() { try { ILcEndpointVolume e = Ep(); bool m = false; if (e != null) e.GetMute(out m); return m; } catch { return false; } }
  public static void Set(float v, bool mute) { try { ILcEndpointVolume e = Ep(); if (e == null) return; e.SetMasterVolumeLevelScalar(v, Guid.Empty); e.SetMute(mute, Guid.Empty); } catch { } }
}
'@
Write-Host "Preparing tests..." -ForegroundColor DarkGray
$script:Native = [bool]('LcBurn' -as [type])
if (-not $script:Native) { try { Add-Type -TypeDefinition $nativeCode -ErrorAction Stop; $script:Native = $true } catch { $script:Native = $false } }

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   SECOND-HAND LAPTOP AUTO CHECKER v4" -ForegroundColor Cyan
Write-Host "              Made by Mahdi" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ("  PowerShell {0} | {1} | Admin: {2}" -f $PSVersionTable.PSVersion, $(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }), $(if ($isAdmin) { 'YES' } else { 'NO' })) -ForegroundColor DarkGray
if ($Auto) {
  Write-Host "`n  FULL AUTO TEST - no questions, takes about 20-50 minutes." -ForegroundColor Yellow
  Write-Host "  Keep the CHARGER CONNECTED. When the laptop BEEPS and asks, unplug it for the battery test." -ForegroundColor Yellow
  Write-Host "  Do not touch the keyboard or mouse during the test." -ForegroundColor Yellow
  # the same hint in the report language, when the console can show it (Chinese Windows can; Bangla needs a font the console lacks)
  if ($tr.console) { foreach ($line in $tr.console) { Write-Host "  $line" -ForegroundColor Yellow } }
} elseif (-not $NoPrompt) {
  Write-Host "`n  HOW IT WORKS - keep the CHARGER CONNECTED at the start:" -ForegroundColor Yellow
  Write-Host "   1) Automatic checks              about 3 min  - just wait" -ForegroundColor Yellow
  Write-Host "   2) HAND CHECKS                   about 5 min  - the screen tells you what to do, step by step" -ForegroundColor Yellow
  Write-Host "   3) Heat test                     about 1 min  - just wait" -ForegroundColor Yellow
  Write-Host "   4) Battery test                  10-40 min    - unplug the charger when it BEEPS, plug it back at the next beep" -ForegroundColor Yellow
  Write-Host "   5) Report opens. The % done is shown in the window title." -ForegroundColor Yellow
  if ($tr.consoleGuided) { foreach ($line in $tr.consoleGuided) { Write-Host "  $line" -ForegroundColor Yellow } }
}

$cs = Get-CimInstance Win32_ComputerSystem
$enclosure = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
# a UPS on a desktop also shows up as a battery, so it does not count, and a desktop case type always wins
$hasBattery = [bool](Get-CimInstance Win32_Battery | Where-Object { "$($_.Name) $($_.DeviceID)" -notmatch 'UPS|APC|CyberPower|Eaton' })
$desktopCase = [bool]($enclosure | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 24, 35 })
$isLaptop = -not $desktopCase -and ([bool]($enclosure | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }) -or $hasBattery -or $cs.PCSystemType -eq 2)
$isVM = "$($cs.Manufacturer) $($cs.Model)" -match 'VMware|VirtualBox|Virtual Machine|KVM|QEMU|Xen|Parallels'
$model = "$($cs.Manufacturer) $($cs.Model)".Trim()
$serial = ''; $biosYear = 0; $panelYear = 0; $cpuName = ''; $totalGB = 0; $gpuText = ''; $diskText = @(); $batText = ''
$batDesign = 0; $batFull = 0; $batHealth = 0; $script:hasTouch = $false
# section weights for the % done (roughly seconds / 10); parts that will not run weigh 0
1..15 | ForEach-Object { $script:Weights[$_] = 1 }
$script:Weights[3] = 3; $script:Weights[6] = 4; $script:Weights[7] = 2; $script:Weights[13] = 2
$script:Weights[16] = if (-not $NoPrompt -and -not $Auto) { 30 } else { 0 }
$script:Weights[17] = if ($StressSeconds -gt 0) { [math]::Max(1, ($StressSeconds + 30) / 10) } else { 0 }
$script:Weights[18] = if ($isLaptop -and $hasBattery -and -not $NoPrompt -and -not $Quick) { 150 } else { 0 }
$script:Weights[19] = if (-not $NoPrompt) { 2 } else { 0 }
$script:Weights[20] = 1

# ---------- 1. Model & Serial ----------
Section "1. Model & Serial"
try {
  $bios = Get-CimInstance Win32_BIOS
  $csp = Get-CimInstance Win32_ComputerSystemProduct
  # Surface etc. put garbage like "124000...D:F B: F:U" in Version; keep only readable names such as "ThinkPad T480"
  if ($csp.Version -match '^[\w \-\.\(\)]{2,40}$' -and $csp.Version -notmatch 'O\.E\.M|Default|None|^\d+$') { $model += " ($($csp.Version))" }
  $serial = "$($bios.SerialNumber)".Trim()
  Add-R "Model" INFO "$model  [$(if ($isLaptop) {'Laptop'} else {'Desktop'})]"
  if ($isVM) { Add-R "Virtual PC" WARN "This is a VIRTUAL MACHINE - hardware results are not real" }
  $bigBrand = $cs.Manufacturer -match 'Dell|HP|Hewlett|Lenovo|ASUS|Acer|Microsoft|Apple|Samsung|Toshiba|Dynabook|Fujitsu|LG|Huawei|Honor|Xiaomi|MSI|Micro-Star|Razer|Gigabyte|Panasonic|Getac|Framework'
  if ($serial -match '^(|0+|To be filled.*|Default string|System Serial Number|None|N/A|Not Specified|Not Applicable|Chassis Serial Number|123456789|Invalid)$') {
    if (-not $isLaptop) { Add-R "Serial" INFO "No serial (normal for a self-built desktop)" }
    elseif ($bigBrand) { Add-R "Serial" FAIL "Serial is '$serial' (blank) - motherboard may be REPLACED" }
    else { Add-R "Serial" WARN "Serial is '$serial' (blank) - common on cheap brands, but motherboard may be replaced" }
  } else {
    Add-R "Serial" PASS "$serial  (must match the sticker under the laptop)"
  }
  if ($bios.ReleaseDate) { $biosYear = $bios.ReleaseDate.Year }
  Add-R "BIOS" INFO ("{0}, date {1:yyyy-MM-dd}" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
  $support = switch -Regex ($cs.Manufacturer) {
    'Dell' { 'https://www.dell.com/support' }
    'HP|Hewlett' { 'https://support.hp.com/checkwarranty' }
    'Lenovo' { 'https://pcsupport.lenovo.com' }
    'ASUS' { 'https://www.asus.com/support' }
    'Acer' { 'https://www.acer.com/support' }
    'MSI|Micro-Star' { 'https://www.msi.com/support' }
    'Samsung' { 'https://www.samsung.com/support' }
    'Toshiba|Dynabook' { 'https://support.dynabook.com' }
    'Microsoft' { 'https://mybusinessservice.surface.com' }
    default { '' }
  }
  if ($support) { Add-R "Verify" INFO "Enter serial at $support to see the ORIGINAL CPU/RAM/screen and warranty" }
} catch { Skip-Section $_ }
$batLog = Join-Path $OutDir ("battery-test-{0}.log" -f $(if ($serial) { $serial -replace '[^\w\-]', '_' } else { 'unknown' }))

# ---------- 2. CPU ----------
Section "2. CPU"
try {
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $cpuName = ($cpu.Name -replace '\s+', ' ').Trim()
  Add-R "CPU" INFO ("{0} | {1} cores / {2} threads | {3:N1} GHz base" -f $cpuName, $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, ($cpu.MaxClockSpeed / 1000))
  if ($cpuName -match 'Celeron|Pentium|Atom|Athlon|A[4-9]-\d|E[12]-\d|Core\(TM\) m[357]|Core m[357]|Intel\(R\) N\d{2,3}\b|i3-N\d') {
    Add-R "CPU Level" WARN "Low-end CPU - slow for office work"
  } elseif ($cpuName -match 'i[3579]-(\d{4,5})') {
    # 4-digit numbers starting with 1 are 10th-14th gen (i7-1065G7, i5-1235U); 1st gen used 3 digits
    $n = $Matches[1]
    if ($n.Length -eq 5 -or $n.StartsWith('1')) { $gen = [int]$n.Substring(0, 2) } else { $gen = [int]$n.Substring(0, 1) }
    if ($gen -ge 8) { Add-R "CPU Gen" PASS "Intel ${gen}th Gen - Windows 11 supported" }
    else { Add-R "CPU Gen" WARN "Intel ${gen}th Gen - old, Windows 11 not officially supported" }
  } elseif ($cpuName -match 'Core.*Ultra|Core\(TM\) [3579] \d{3}') {
    Add-R "CPU Gen" PASS "Intel Core Ultra / Core Series - new generation"
  } elseif ($cpuName -match 'Ryzen AI|Ryzen \d (PRO )?\d{3}\b') {
    Add-R "CPU Gen" PASS "AMD Ryzen AI / 200 series - new generation"
  } elseif ($cpuName -match 'Ryzen \d (PRO )?(\d)\d{3}') {
    $gen = [int]$Matches[2]
    if ($gen -ge 2) { Add-R "CPU Gen" PASS "AMD Ryzen ${gen}000 series - Windows 11 supported" }
    else { Add-R "CPU Gen" WARN "AMD Ryzen 1000 series - old" }
  } elseif ($cpuName -match 'Snapdragon.*X|Oryon') {
    Add-R "CPU Gen" PASS "Snapdragon X (ARM) - fast, but some old apps / games / drivers may not run"
  } elseif ($cpuName -match 'Snapdragon|Qualcomm|Microsoft SQ') {
    Add-R "CPU Gen" WARN "Older ARM CPU - many normal Windows apps run slowly"
  } else {
    Add-R "CPU Gen" INFO "Check CPU age manually (Google the CPU name)"
  }
} catch { Skip-Section $_ }

# ---------- 3. RAM ----------
Section "3. RAM"
try {
  $ram = @(Get-CimInstance Win32_PhysicalMemory)
  $totalGB = [math]::Round((($ram | Measure-Object Capacity -Sum).Sum) / 1GB)
  if (-not $totalGB) { $totalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB) }
  $sizes = @($ram | ForEach-Object { [math]::Round($_.Capacity / 1GB) })
  $slots = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
  $speed = $ram | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Select-Object -First 1
  $memTypes = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
  $rType = if ($ram) { $memTypes[[int]$ram[0].SMBIOSMemoryType] }
  $soldered = $ram.Count -gt 0 -and -not @($ram | Where-Object FormFactor -ne 11)
  $ramText = "$totalGB GB $rType (sticks: $($sizes -join ' + ') GB, $speed MHz, slots: $slots)"
  if ($totalGB -ge 8) { Add-R "RAM" PASS $ramText } else { Add-R "RAM" WARN "$ramText - less than 8 GB, will be slow" }
  if ($ram.Count -ge 2 -and @($sizes | Select-Object -Unique).Count -gt 1) { Add-R "RAM Match" WARN "Different size sticks mixed" }
  if ($soldered) { Add-R "RAM Slot" INFO "RAM is soldered on the board - cannot be upgraded later" }
  elseif ($ram.Count -eq 1 -and $slots -gt 1) { Add-R "RAM Slot" INFO "1 empty slot - RAM can be upgraded" }
  $usableGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
  if ($totalGB -and $usableGB -lt $totalGB * 0.85) { Add-R "RAM Usable" INFO "Only $usableGB GB usable of $totalGB GB (shared with graphics, or a slot problem)" }
  $memTest = Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } 1
  if ($memTest) {
    $m = $memTest[0]
    if ($m.Message -match 'no errors' -or ($m.Id -in 1101, 1201 -and $m.Message -notmatch 'error')) { Add-R "RAM Test" PASS ("Windows Memory Diagnostic: no errors ({0:yyyy-MM-dd})" -f $m.TimeCreated) }
    elseif ($m.Message -match 'error' -or $m.Id -in 1102, 1202) { Add-R "RAM Test" FAIL ("Windows Memory Diagnostic found ERRORS ({0:yyyy-MM-dd})" -f $m.TimeCreated) }
    else { Add-R "RAM Test" INFO ("Windows Memory Diagnostic ran {0:yyyy-MM-dd} (event {1}) - check result manually" -f $m.TimeCreated, $m.Id) }
  }

  # live RAM test without restart: fill free RAM with 3 patterns and read every value back
  if ($Quick) { Add-R "RAM Live Test" INFO "Skipped (quick mode)" }
  elseif (-not $script:Native -or -not [Environment]::Is64BitProcess) { Add-R "RAM Live Test" INFO "Not available on this PC - run  mdsched.exe  (needs restart)" }
  else {
    # leave a third of the free RAM to Windows: grabbing nearly all of it makes Windows page out, and then the
    # test is slow and partly tests the page file instead of the RAM
    $freeMB = [math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
    $testMB = [math]::Min([math]::Min([math]::Floor($freeMB * 0.65), $freeMB - 1024), 24576)
    if ($testMB -lt 256) { Add-R "RAM Live Test" INFO "Not enough free RAM to test - close programs and re-run" }
    else {
      Write-Host ("  Testing {0:N1} GB of free RAM..." -f ($testMB / 1024)) -ForegroundColor DarkGray
      [LcRam]::Start($testMB)
      while ([LcRam]::Running) {
        Start-Sleep -Milliseconds 300
        $tot = [LcRam]::TestedMB * 3
        if ($tot) { Write-Progress -Activity "RAM test" -Status ("{0:N1} GB, 3 patterns" -f ([LcRam]::TestedMB / 1024)) -PercentComplete ([math]::Min(100, [LcRam]::DoneMB * 100 / $tot)) }
      }
      Write-Progress -Activity "RAM test" -Completed
      $tGB = '{0:N1}' -f ([LcRam]::TestedMB / 1024)
      if ([LcRam]::Errors -gt 0) { Add-R "RAM Live Test" FAIL "$([LcRam]::Errors) memory ERRORS found in $tGB GB - RAM is FAULTY (hangs, blue screens, corrupted files)" }
      elseif ([LcRam]::TestedMB) { Add-R "RAM Live Test" PASS "$tGB GB of free RAM tested with 3 patterns - no errors (RAM used by Windows is not covered; mdsched.exe tests all)" }
      else { Add-R "RAM Live Test" INFO "Could not reserve RAM for the test" }
    }
  }
} catch { Skip-Section $_ }

# ---------- 4. Graphics & Display ----------
Section "4. Graphics & Display"
try {
  $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Remote|Virtual|Hyper-V|Mirage|DisplayLink|Parsec|Citrix|Indirect|Meta' })
  $gpuText = ($gpus | ForEach-Object { $_.Name }) -join ' + '
  foreach ($g in $gpus) {
    $kind = if ($g.Name -match 'NVIDIA|GeForce|Quadro|RTX|GTX|Radeon.*(RX|Pro) ?\d|Arc(\(TM\))? A\d') { 'dedicated' } else { 'integrated' }
    if ($g.Name -match 'Microsoft Basic') { Add-R "GPU" WARN "Graphics driver NOT installed (Microsoft Basic Display Adapter)" }
    elseif ($g.ConfigManagerErrorCode -or $g.Status -notin 'OK', $null) { Add-R "GPU" WARN "$($g.Name) ($kind) - NOT working (error code $($g.ConfigManagerErrorCode)): disabled or faulty" }
    else { Add-R "GPU" PASS "$($g.Name) ($kind), driver $($g.DriverVersion)" }
  }
  $smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
  if (-not $smi -and (Test-Path "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) { $smi = "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe" }
  if ($smi) {
    $gt = & $smi --query-gpu=name,temperature.gpu --format=csv,noheader 2>$null | Select-Object -First 1
    if ($gt) { Add-R "GPU Temp" INFO "$gt C now (GPU heat test: open Tools\FurMark\FurMark_GUI.exe)" }
  }
  $vc = $gpus | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
  if ($vc) {
    $resText = "$($vc.CurrentHorizontalResolution) x $($vc.CurrentVerticalResolution) @ $($vc.CurrentRefreshRate) Hz"
    if ($vc.CurrentHorizontalResolution -ge 1920) { Add-R "Resolution" PASS $resText }
    else { Add-R "Resolution" WARN "$resText - not Full HD" }
    if ($vc.MaxRefreshRate -gt $vc.CurrentRefreshRate -and $vc.CurrentRefreshRate) { Add-R "Refresh" INFO "Running at $($vc.CurrentRefreshRate) Hz, graphics reports up to $($vc.MaxRefreshRate) Hz - check Display settings > Advanced display" }
  }

  $monIds = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID)
  $monConn = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams)
  $monSize = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams)
  $internalNames = @($monConn | Where-Object { $_.VideoOutputTechnology -in 6, 11, 13, 2147483648, -2147483648 } | ForEach-Object { $_.InstanceName })
  $panels = @($monIds | Where-Object { $_.InstanceName -in $internalNames })
  if (-not $panels -and -not $monConn -and $isLaptop) { $panels = @($monIds | Select-Object -First 1) }
  if ($panels) {
    foreach ($p in $panels) {
      $sz = $monSize | Where-Object InstanceName -eq $p.InstanceName | Select-Object -First 1
      $inch = if ($sz -and $sz.MaxHorizontalImageSize) { [math]::Round([math]::Sqrt([math]::Pow($sz.MaxHorizontalImageSize, 2) + [math]::Pow($sz.MaxVerticalImageSize, 2)) / 2.54, 1) } else { '?' }
      $pText = "Panel $(Ascii $p.ManufacturerName) $(Ascii $p.ProductCodeID), $inch inch, made $($p.YearOfManufacture)"
      if ($p.YearOfManufacture -gt 1990 -and (-not $panelYear -or $p.YearOfManufacture -lt $panelYear)) { $panelYear = [int]$p.YearOfManufacture }
      if ($biosYear -and $p.YearOfManufacture -gt ($biosYear + 1)) { Add-R "Panel" WARN "$pText - NEWER than laptop ($biosYear): display likely REPLACED" }
      else { Add-R "Panel" PASS "$pText - looks original (Google the code to confirm)" }
    }
  } elseif ($isLaptop) { Add-R "Panel" WARN "Built-in panel info not readable" }
  else { Add-R "Panel" INFO "No built-in panel (desktop / external monitor only)" }
} catch { Skip-Section $_ }

# ---------- 5. Battery & Charger ----------
Section "5. Battery & Charger"
try {
  # a battery test log left behind means the laptop switched off in the middle of the last test
  if (Test-Path $batLog) {
    $ll = @(Get-Content $batLog)
    $st = "$($ll | Where-Object { $_ -like 'START|*' } | Select-Object -First 1)" -split '\|'
    $lt = "$($ll | Where-Object { $_ -like 'T|*' } | Select-Object -Last 1)" -split '\|'
    if ($lt.Count -ge 4) {
      $off = Get-Events @{ LogName = 'System'; Id = 41, 6008; StartTime = [datetime]$lt[1] } 1
      $txt = "Last battery test ($($st[3]), started at $($st[2])%): the laptop TURNED OFF after $($lt[3]) min at $($lt[2])%"
      if (-not $off) { Add-R "Batt Test Log" INFO "Last battery test did not finish (stopped at $($lt[2])%)" }
      elseif ([int]$lt[2] -ge 15) { Add-R "Batt Test Log" WARN "$txt with charge still left - battery cells are WEAK, the % shown is not real" }
      else { Add-R "Batt Test Log" INFO "$txt (battery ran empty)" }
    }
    Remove-Item $batLog -Force
  }

  $xmlPath = Join-Path $env:TEMP "laptop-check-battery.xml"
  Remove-Item $xmlPath -Force
  $pcfg = Start-Process "$env:WINDIR\System32\powercfg.exe" -ArgumentList "/batteryreport /xml /output `"$xmlPath`"" -WindowStyle Hidden -PassThru
  if ($pcfg -and -not $pcfg.WaitForExit(60000)) { $pcfg.Kill(); Write-Host "  (battery report did not finish in 60 sec - skipped)" -ForegroundColor DarkGray }
  $rep = $null
  if (Test-Path $xmlPath) { $rep = ([xml](Get-Content $xmlPath -Raw)).BatteryReport; Remove-Item $xmlPath -Force }
  $bats = @($rep.Batteries.Battery | Where-Object { $_ })
  if (-not $isLaptop) { $bats = @(); $rep = $null }   # a desktop's "battery" is a UPS
  $i = 0
  foreach ($b in $bats) {
    $i++
    $label = if ($bats.Count -gt 1) { "Battery $i" } else { "Battery" }
    $design = [double]$b.DesignCapacity; $full = [double]$b.FullChargeCapacity; $cycles = [int]$b.CycleCount
    if ($design -gt 0) {
      $batDesign += $design; $batFull += $full
      $health = [math]::Round($full / $design * 100)
      $bText = ("Health $health% ({0:N1} of {1:N1} Wh), cycles $cycles, $($b.Manufacturer)" -f ($full / 1000), ($design / 1000))
      if (-not $batText) { $batText = "battery $health%" }
      # health comes from the battery's own chip, which can be reset or faked - the battery test checks it for real
      if ($health -ge 80) { Add-R $label PASS "$bText (as reported by the battery chip)" }
      elseif ($health -ge 60) { Add-R $label WARN "$bText - OK but weak" }
      else { Add-R $label WARN "$bText - needs replacement, ask for lower price" }
      if ($cycles -gt 500) { Add-R "Cycles" WARN "$cycles cycles - battery is old" }
      if ($full -gt $design * 1.03) { Add-R "Batt Chip" WARN "Battery claims MORE than its design capacity - chip reset or fake battery, health % cannot be trusted" }
      elseif ($health -ge 95 -and $cycles -ge 300) { Add-R "Batt Chip" WARN "$health% health after $cycles cycles is not realistic - chip may be reset or battery fake" }
      else {
        # batteries lose capacity with age even when unused; age from the battery date, else from the screen's build year
        $batYear = 0; try { if ("$($b.ManufactureDate)") { $batYear = ([datetime]"$($b.ManufactureDate)").Year } } catch {}
        $ageFrom = if ($batYear -gt 1990) { 'battery' } elseif ($panelYear) { $batYear = $panelYear; 'laptop' } else { '' }
        $age = (Get-Date).Year - $batYear
        if ($ageFrom -and $age -ge 4 -and $health -ge 95) {
          Add-R "Batt Chip" WARN "$health% health on a ~$age-year-old $ageFrom is not realistic - chip may be reset or battery fake$(if ($ageFrom -eq 'laptop') {' (unless the battery was replaced recently)'})"
        }
      }
      if ($design -lt 35000) { Add-R "Batt Size" INFO ("Small battery ({0:N0} Wh) - short battery life even when healthy" -f ($design / 1000)) }
    } else { Add-R $label INFO "Battery found but its capacity is not readable" }
  }
  if ($batDesign) { $batHealth = [math]::Round($batFull / $batDesign * 100) }

  # Windows' own estimate, learned from how fast the battery really drained in past use
  $estFull = Get-Span $rep.RuntimeEstimates.FullChargeCapacity.ActiveRuntime
  $estNew = Get-Span $rep.RuntimeEstimates.DesignCapacity.ActiveRuntime
  if ($estFull -and $estFull.TotalMinutes -gt 1) {
    $eText = "Windows estimate from past use: full charge lasts ~$(Format-Hours $estFull.TotalHours)"
    if ($estNew -and $estNew.TotalMinutes -gt 1) { $eText += " (new battery: ~$(Format-Hours $estNew.TotalHours))" }
    if ($estFull.TotalHours -lt 1.5) { Add-R "Batt Life" WARN "$eText - SHORT battery life" } else { Add-R "Batt Life" INFO $eText }
  }
  $hist = @($rep.History.HistoryEntry | Where-Object { $_ })
  if ($hist.Count -ge 2) {
    for ($h = 1; $h -lt $hist.Count; $h++) {
      if ([double]$hist[$h].DesignCapacity -gt 0 -and [double]$hist[$h - 1].DesignCapacity -gt 0 -and $hist[$h].DesignCapacity -ne $hist[$h - 1].DesignCapacity) {
        Add-R "Batt Change" INFO "Battery was REPLACED around $($hist[$h].LocalStartDate -replace 'T.*') (design capacity changed)"
      }
    }
    $fccs = @($hist | ForEach-Object { [double]$_.FullChargeCapacity } | Where-Object { $_ -gt 0 })
    if ($fccs.Count -ge 6 -and @($fccs | Select-Object -Unique).Count -eq 1 -and $batHealth -ge 95) {
      Add-R "Batt Chip" WARN "Capacity has stayed EXACTLY the same in $($fccs.Count) report periods - real batteries change a little; chip may be locked or fake"
    }
  }
  $wb = if ($isLaptop) { Get-CimInstance Win32_Battery | Select-Object -First 1 }
  if (-not $bats -and -not $wb) {
    if ($isLaptop) { Add-R "Battery" FAIL "No battery found / battery dead" } else { Add-R "Battery" INFO "No battery (desktop)" }
  } elseif ($wb) {
    $bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus | Where-Object { $_.Active -ne $false } | Select-Object -First 1
    $onAC = if ($bs) { [bool]$bs.PowerOnline } else { $wb.BatteryStatus -in 2, 6, 7, 8, 9 }
    $cText = "Charge $($wb.EstimatedChargeRemaining)% | Charger connected: $(if ($onAC) {'YES'} else {'NO'})"
    if ($bs -and $bs.Charging -and $bs.ChargeRate) { $cText += (" | charging at {0:N1} W" -f ($bs.ChargeRate / 1000)) }
    if ($bs -and $bs.Discharging -and $bs.DischargeRate) { $cText += (" | using {0:N1} W" -f ($bs.DischargeRate / 1000)) }
    if ($onAC -and $bs -and -not $bs.Charging -and $wb.EstimatedChargeRemaining -lt 50) { Add-R "Charging" WARN "$cText - charger connected but NOT charging (check charger, or a charge-limit setting)" }
    elseif (-not $onAC) { Add-R "Charging" INFO "$cText - plug in the charger and re-run to test charging" }
    else { Add-R "Charging" PASS $cText }
  }
} catch { Skip-Section $_ }

# ---------- 6. Storage ----------
Section "6. Storage (SSD/HDD)"
try {
  # SD / MMC bus is skipped only for removable cards: cheap laptops boot from a built-in eMMC on that bus
  $removable = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.MediaType -match 'Removable' } | ForEach-Object { "$($_.Index)" })
  $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object {
      "$($_.BusType)" -notmatch '^(USB|Virtual|File Backed Virtual|7|14|15)$' -and -not ("$($_.BusType)" -match '^(SD|MMC|12|13)$' -and "$($_.DeviceId)" -in $removable) })
  foreach ($d in $disks) {
    $gb = [math]::Round($d.Size / 1GB)
    $mt = if ("$($d.BusType)" -match '^(NVMe|17)$') { 'SSD' } elseif ("$($d.BusType)" -match '^(SD|MMC|12|13)$') { 'eMMC' } elseif ("$($d.MediaType)" -match '^(HDD|3)$') { 'HDD' } elseif ("$($d.MediaType)" -match '^(SSD|4)$') { 'SSD' } else { "$($d.MediaType)" }
    $dName = "$($d.FriendlyName) ($mt, $($d.BusType), $gb GB)"
    $diskText += "$gb GB $mt"
    if ("$($d.HealthStatus)" -notmatch '^(Healthy|0)$') { Add-R "Disk" FAIL "$dName - health: $($d.HealthStatus)" }
    elseif ($mt -eq 'HDD') { Add-R "Disk" WARN "$dName - HDD is slow, SSD recommended" }
    else { Add-R "Disk" PASS "$dName - Healthy" }
    if ($isAdmin) {
      $rc = $d | Get-StorageReliabilityCounter
      if ($rc) {
        if ($null -ne $rc.Wear -and $mt -ne 'HDD') {
          if ($rc.Wear -ge 80) { Add-R "Disk Wear" FAIL "$($rc.Wear)% used - SSD near end of life" }
          elseif ($rc.Wear -ge 20) { Add-R "Disk Wear" WARN "$($rc.Wear)% used" }
          else { Add-R "Disk Wear" PASS "$($rc.Wear)% used" }
        }
        if ($rc.PowerOnHours) {
          if ($rc.PowerOnHours -gt 15000) { Add-R "Disk Hours" WARN "$($rc.PowerOnHours) hours used - heavily used" }
          else { Add-R "Disk Hours" INFO "$($rc.PowerOnHours) hours used (~$([math]::Round($rc.PowerOnHours / 8 / 365, 1)) years of 8h/day)" }
        }
        if ($rc.Temperature -ge 70) { Add-R "Disk Temp" WARN "$($rc.Temperature) C - disk running hot" }
        # lifetime counters, and SATA drives map them from vendor-specific SMART values - so WARN; the scan below decides FAIL
        if ($rc.ReadErrorsUncorrected -gt 0 -or $rc.WriteErrorsUncorrected -gt 0) {
          Add-R "Disk Errors" WARN "Disk reports $([int64]$rc.ReadErrorsUncorrected) uncorrected read / $([int64]$rc.WriteErrorsUncorrected) write errors in its lifetime - confirm with Tools\CrystalDiskInfo\DiskInfo64.exe (Reallocated / Pending / Uncorrectable sectors)"
        }
      }
      # bad sector scan: read-only, reads 1500 spots spread over the whole disk
      if (-not $Quick -and $script:Native -and $d.Size) {
        $slowMs = if ($mt -eq 'HDD') { 800 } else { 200 }
        Write-Host "  Scanning $($d.FriendlyName) for bad areas (up to 60 sec)..." -ForegroundColor DarkGray
        [LcDisk]::Start("\\.\PhysicalDrive$($d.DeviceId)", [long]$d.Size, 1500, $slowMs, 60)
        while ([LcDisk]::Running) { Start-Sleep -Milliseconds 300; Write-Progress -Activity "Disk scan - $($d.FriendlyName)" -Status "$([LcDisk]::Done) of 1500 areas" -PercentComplete ([math]::Min(100, [LcDisk]::Done * 100 / 1500)) }
        Write-Progress -Activity "Disk scan - $($d.FriendlyName)" -Completed
        # every single read failing means the scan itself could not work here, not a dead disk
        if (-not [LcDisk]::Opened -or ([LcDisk]::Done -gt 0 -and [LcDisk]::Errors -eq [LcDisk]::Done)) { Add-R "Disk Scan" INFO "$($d.FriendlyName): disk could not be scanned on this PC" }
        else {
          $sText = "{0} areas read across the whole disk, slowest {1:N0} ms, average {2:N1} ms" -f [LcDisk]::Done, [LcDisk]::MaxMs, [LcDisk]::AvgMs
          if ([LcDisk]::Errors) { Add-R "Disk Scan" FAIL "$($d.FriendlyName): $([LcDisk]::Errors) areas could NOT be read (bad sectors) - $sText" }
          elseif ([LcDisk]::Slow -ge 5) { Add-R "Disk Scan" WARN "$($d.FriendlyName): $([LcDisk]::Slow) very slow areas (weak sectors) - $sText" }
          else { Add-R "Disk Scan" PASS "$($d.FriendlyName): no bad areas - $sText" }
        }
      }
    }
  }
  if (-not $disks) {
    foreach ($d in @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -ne 'USB' -and $_.MediaType -notmatch 'Removable' })) {
      $gb = [math]::Round($d.Size / 1GB); $diskText += "$gb GB"
      if ($d.Status -eq 'OK') { Add-R "Disk" PASS "$($d.Model) ($gb GB) - OK" } else { Add-R "Disk" FAIL "$($d.Model) ($gb GB) - status $($d.Status)" }
    }
  }
  if ($isAdmin) {
    $smart = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus | Where-Object PredictFailure)
    if ($smart) { Add-R "SMART" FAIL "Disk SMART predicts FAILURE soon - do not trust this disk" }
  } elseif (-not $Quick) { Add-R "Disk Scan" INFO "Bad sector scan skipped (needs Administrator)" }
  $cDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
  if ($cDrive.Size) { Add-R "C: Space" INFO ("{0:N0} GB free of {1:N0} GB" -f ($cDrive.FreeSpace / 1GB), ($cDrive.Size / 1GB)) }
  if ($Quick) { Add-R "Disk Speed" INFO "Skipped (quick mode)" }
  elseif ($isAdmin -and (Get-Command winsat)) {
    Write-Host "  Testing C: drive read speed (~20 sec)..." -ForegroundColor DarkGray
    $ws = winsat disk -seq -read -drive c 2>$null | Out-String
    if ($ws -match 'Read\s+([\d\.,]+)\s*MB/s') {
      $mbps = [math]::Round([double]($Matches[1] -replace ',', '.'))
      if ($mbps -ge 300) { Add-R "Disk Speed" PASS "$mbps MB/s read" }
      elseif ($mbps -ge 150) { Add-R "Disk Speed" WARN "$mbps MB/s read - slow SSD" }
      else { Add-R "Disk Speed" WARN "$mbps MB/s read - HDD-level speed, very slow" }
    } else { Add-R "Disk Speed" INFO "Speed test did not return a result" }
  } else { Add-R "Disk Speed" INFO "Skipped (needs Administrator)" }
} catch { Skip-Section $_ }

# ---------- 7. WiFi ----------
Section "7. WiFi"
try {
  $wifi = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.NdisPhysicalMedium -eq 9 -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11|WLAN' })
  if (-not $wifi) {
    if ($isLaptop) { Add-R "WiFi" FAIL "No WiFi card found" } else { Add-R "WiFi" INFO "No WiFi card (desktop)" }
  } else {
    $w = $wifi[0]
    # parse only the 802.11xx tokens so it works in every Windows language
    $drv = netsh wlan show drivers | Out-String
    $std = @([regex]::Matches($drv, '802\.11(be|ax|ac|n|g|b|a)\b') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $best = if ('be' -in $std) { 'WiFi 7' } elseif ('ax' -in $std) { 'WiFi 6/6E' } elseif ('ac' -in $std) { 'WiFi 5' } elseif ('n' -in $std) { 'WiFi 4' } else { 'old' }
    $wText = "$($w.InterfaceDescription) | $best"
    if (-not $std) { Add-R "WiFi Card" INFO "$($w.InterfaceDescription) (standard not readable)" }
    elseif ($best -match '7|6|5') { Add-R "WiFi Card" PASS $wText } else { Add-R "WiFi Card" WARN "$wText - old WiFi standard" }
    if ("$($w.Status)" -eq 'Disabled') { Add-R "WiFi" WARN "WiFi adapter is DISABLED in Windows - enable it and re-run" }
    elseif ("$($w.Status)" -eq 'Up') {
      $inf = netsh wlan show interfaces | Out-String
      if ($inf -match ':\s*(\d{1,3})\s*%') {
        $signal = [int]$Matches[1]
        $rate = if ($inf -match '\(Mbps\)\s*:\s*([\d\.]+)') { $Matches[1] } else { '?' }
        if ($signal -ge 70) { Add-R "WiFi Signal" PASS "$signal% signal, $rate Mbps link" }
        else { Add-R "WiFi Signal" WARN "$signal% signal, $rate Mbps link - go near router and re-test" }
      } else { Add-R "WiFi Signal" INFO "Signal not readable (Windows 11: Settings > Privacy > Location > allow desktop apps)" }
      if ($Quick) { Add-R "WiFi Ping" INFO "Skipped (quick mode)" }
      else {
        Write-Host "  Ping test (~15 sec)..." -ForegroundColor DarkGray
        $png = New-Object Net.NetworkInformation.Ping
        # Google and Cloudflare are blocked in some countries (China), so fall back to AliDNS and 114DNS
        $target = '8.8.8.8'
        foreach ($cand in '8.8.8.8', '1.1.1.1', '223.5.5.5', '114.114.114.114') {
          try { if ($png.Send($cand, 1500).Status -eq 'Success') { $target = $cand; break } } catch {}
        }
        $ok = 0; $ms = @()
        for ($k = 0; $k -lt 20; $k++) {
          try { $rep2 = $png.Send($target, 1500); if ($rep2.Status -eq 'Success') { $ok++; $ms += $rep2.RoundtripTime } } catch {}
          Start-Sleep -Milliseconds 500
        }
        $loss = [math]::Round((20 - $ok) / 20 * 100)
        $avgMs = if ($ms) { [math]::Round(($ms | Measure-Object -Average).Average) } else { 0 }
        if ($ok -eq 0) { Add-R "WiFi Ping" WARN "No internet reply - check connection and re-run" }
        elseif ($loss -eq 0) { Add-R "WiFi Ping" PASS "0% packet loss, avg $avgMs ms" }
        else { Add-R "WiFi Ping" WARN "$loss% packet loss, avg $avgMs ms - WiFi card/antenna problem?" }
      }
    } else { Add-R "WiFi Signal" INFO "Not connected - connect to WiFi and re-run for signal/ping test" }
  }
} catch { Skip-Section $_ }

# ---------- 8. Bluetooth ----------
Section "8. Bluetooth"
try {
  $bt = @(Get-PnpDevice -PresentOnly -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^(USB|PCI|ACPI|UART|SDIO|BTH\\MS_BTHBRB)' -and $_.FriendlyName -notmatch 'Enumerator|RFCOMM' })
  if ($bt) {
    $bad = @($bt | Where-Object Status -ne 'OK')
    if ($bad) { Add-R "Bluetooth" WARN "$($bt[0].FriendlyName) - status $($bad[0].Status)" }
    else { Add-R "Bluetooth" PASS "$($bt[0].FriendlyName) - OK (pair your phone to confirm)" }
  } elseif ($isLaptop) { Add-R "Bluetooth" FAIL "No Bluetooth adapter found (or turned off)" }
  else { Add-R "Bluetooth" INFO "No Bluetooth adapter (desktop)" }
} catch { Skip-Section $_ }

# ---------- 9. Camera / Audio ----------
Section "9. Camera & Audio"
try {
  $cam = @(Get-PnpDevice -PresentOnly -Class Camera, Image -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -notmatch '\bIR\b|Infrared|Depth' })
  if ($cam) { Add-R "Webcam" $(if ($cam[0].Status -eq 'OK') { 'PASS' } else { 'WARN' }) "$($cam[0].FriendlyName) - $($cam[0].Status)" }
  elseif ($isLaptop) { Add-R "Webcam" WARN "No webcam found" }
  $snd = @(Get-CimInstance Win32_SoundDevice | Where-Object Status -eq 'OK')
  if ($snd) { Add-R "Sound" PASS "$($snd[0].Name)" } else { Add-R "Sound" WARN "No working sound device" }
  $mic = @(Get-PnpDevice -PresentOnly -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Microphone|Mic' -and $_.Status -eq 'OK' })
  if ($mic) { Add-R "Microphone" PASS $mic[0].FriendlyName } elseif ($isLaptop) { Add-R "Microphone" WARN "No working microphone found" }
} catch { Skip-Section $_ }

# ---------- 10. Touch, fingerprint, face unlock, SD, LTE, NFC ----------
Section "10. Touch, Fingerprint, Face & Extras"
try {
  $pnp = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)
  function Report-Part($cat, $devs, $what) {
    $okDev = @($devs | Where-Object Status -eq 'OK')
    if ($okDev) { Add-R $cat PASS "$($okDev[0].FriendlyName) - OK" }
    elseif ($devs) { Add-R $cat WARN "$($devs[0].FriendlyName) - status $($devs[0].Status): $what not working" }
    else { Add-R $cat INFO "No $what" }
  }
  $touchMax = if ($script:Native) { [LcScreen]::GetSystemMetrics(95) } else { 0 }
  $touch = @($pnp | Where-Object { $_.FriendlyName -match 'touch ?screen' })
  if ($touch -or $touchMax -gt 0) {
    $script:hasTouch = $true
    $tName = if ($touch) { $touch[0].FriendlyName } else { 'Touchscreen' }
    $tBad = @($touch | Where-Object Status -ne 'OK')
    if ($tBad -and -not @($touch | Where-Object Status -eq 'OK')) { Add-R "Touchscreen" WARN "$tName - status $($tBad[0].Status): touchscreen not working" }
    else { Add-R "Touchscreen" PASS "$tName$(if ($touchMax -gt 0) { " - $touchMax touch points" })" }
  } else { Add-R "Touchscreen" INFO "No touchscreen" }
  Report-Part "Fingerprint" @($pnp | Where-Object { $_.Class -eq 'Biometric' -or $_.FriendlyName -match 'Fingerprint' }) 'fingerprint reader'
  Report-Part "Face Unlock" @($pnp | Where-Object { $_.Class -in 'Camera', 'Image' -and $_.FriendlyName -match '\bIR\b|Infrared|Depth|Hello' }) 'face-unlock (Windows Hello IR) camera'
  Report-Part "SD Reader" @($pnp | Where-Object { $_.Class -eq 'SDHost' -or $_.FriendlyName -match 'Card ?Reader|SD Host|SD Card|SDXC|Media Reader' }) 'SD card reader'
  $wwan = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.NdisPhysicalMedium -eq 8 -or $_.InterfaceDescription -match 'Mobile Broadband|\bWWAN\b|\bLTE\b|\b5G\b|Fibocom|Quectel|Sierra Wireless' })
  if ($wwan) { Add-R "LTE/SIM" PASS "$($wwan[0].InterfaceDescription) - SIM slot present, insert a SIM to test" } else { Add-R "LTE/SIM" INFO "No LTE / SIM modem" }
  Report-Part "NFC" @($pnp | Where-Object { $_.Class -eq 'Proximity' -or $_.FriendlyName -match '\bNFC\b|Near Field' }) 'NFC'
} catch { Skip-Section $_ }

# ---------- 11. Drivers / devices ----------
Section "11. Devices"
try {
  $badDev = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -in 'Error', 'Degraded' })
  if ($badDev) { $badDev | Select-Object -First 8 | ForEach-Object { Add-R "Device" WARN "$($_.FriendlyName) ($($_.Class)) - $($_.Status)" } }
  else { Add-R "Devices" PASS "All devices working" }
} catch { Skip-Section $_ }

# ---------- 12. Windows & Security ----------
Section "12. Windows & Security"
try {
  $os = Get-CimInstance Win32_OperatingSystem
  Add-R "Windows" INFO ("{0} {1} ({2}), installed {3:yyyy-MM-dd}" -f $os.Caption, $os.Version, $os.OSArchitecture, $os.InstallDate)
  if ($os.Caption -match 'Windows 10') { Add-R "Windows Ver" WARN "Windows 10 support ended Oct 2025 - upgrade to Windows 11 if the laptop supports it" }
  elseif ($os.Caption -match 'Windows (7|8)') { Add-R "Windows Ver" WARN "Very old Windows - no security updates" }
  $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'" | Where-Object LicenseStatus -eq 1 | Select-Object -First 1
  if ($lic) { Add-R "Activation" PASS "Windows activated" } else { Add-R "Activation" WARN "Windows NOT activated" }

  $sbKey = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
  if ($null -eq $sbKey) { Add-R "Boot Mode" WARN "Legacy BIOS mode (no UEFI) - Windows 11 needs UEFI" }
  elseif ($sbKey.UEFISecureBootEnabled -eq 1) { Add-R "Boot Mode" PASS "UEFI + Secure Boot ON" }
  else { Add-R "Boot Mode" INFO "UEFI, Secure Boot OFF (can be turned on in BIOS)" }

  if ($isAdmin) {
    $tpm = Get-CimInstance -Namespace root\cimv2\Security\MicrosoftTpm -ClassName Win32_Tpm
    if ($tpm) {
      $tpmVer = [double](("$($tpm.SpecVersion)" -split ',')[0].Trim())
      if (-not $tpm.IsEnabled_InitialValue) { Add-R "TPM" WARN "TPM $tpmVer found but DISABLED in BIOS" }
      elseif ($tpmVer -ge 2) { Add-R "TPM" PASS "TPM $tpmVer - Windows 11 ready" }
      else { Add-R "TPM" WARN "TPM $tpmVer - Windows 11 needs TPM 2.0" }
    } else { Add-R "TPM" WARN "No TPM found (or turned off in BIOS) - Windows 11 needs TPM 2.0" }
  } else { Add-R "TPM" INFO "Skipped (needs Administrator)" }

  $bl = $null
  if ($isAdmin) {
    $vol = Get-CimInstance -Namespace root\cimv2\Security\MicrosoftVolumeEncryption -ClassName Win32_EncryptableVolume -Filter "DriveLetter='C:'"
    if ($vol) { $bl = $vol.ProtectionStatus -eq 1 }
  }
  if ($null -eq $bl) {
    $blp = (New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection')
    if ($blp -in 1, 3, 5, 6) { $bl = $true } elseif ($blp -eq 2) { $bl = $false }
  }
  if ($bl) { Add-R "BitLocker" INFO "C: is encrypted (BitLocker / Device Encryption) - before buying, seller must remove their Microsoft account or give the recovery key" }
  elseif ($bl -eq $false) { Add-R "BitLocker" INFO "C: is not encrypted" }
} catch { Skip-Section $_ }

# ---------- 13. Remote access, spyware, cracks, antivirus ----------
Section "13. Remote Access, Spyware & Antivirus"
try {
  $apps = @(foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    Get-ItemProperty $k | Where-Object DisplayName | ForEach-Object { "$($_.DisplayName)" }
  }) | Select-Object -Unique
  $procs = @(Get-Process | ForEach-Object { "$($_.ProcessName) $($_.Path)" })
  $svcs = @(Get-CimInstance Win32_Service | ForEach-Object { [PSCustomObject]@{ Text = "$($_.Name) $($_.DisplayName) $($_.PathName)"; Auto = $_.StartMode -eq 'Auto' } })
  $remote = [ordered]@{
    'AnyDesk' = 'AnyDesk'; 'TeamViewer' = 'TeamViewer'; 'RustDesk' = 'RustDesk'; 'UltraViewer' = 'UltraViewer'
    'Chrome Remote Desktop' = 'Chrome Remote Desktop|remoting_host'; 'Splashtop' = 'Splashtop'; 'Radmin' = 'Radmin'; 'VNC' = 'VNC'
    'LogMeIn' = 'LogMeIn'; 'Ammyy' = 'Ammyy'; 'Supremo' = 'Supremo'; 'ScreenConnect' = 'ScreenConnect|ConnectWise Control'
    'NoMachine' = 'NoMachine|nxservice'; 'DWService' = 'DWAgent|DWService'; 'Zoho Assist' = 'Zoho Assist'; 'Remote Utilities' = 'Remote Utilities|rutserv'
    'AeroAdmin' = 'AeroAdmin'; 'MeshCentral' = 'MeshAgent|MeshCentral'; 'Parsec' = 'Parsec'; 'HopToDesk' = 'HopToDesk'
    'NinjaOne' = 'NinjaRMM|NinjaOne'; 'Atera' = 'AteraAgent|Atera Networks'; 'Action1' = 'Action1'; 'GoTo Resolve' = 'GoTo Resolve|GoToAssist'
  }
  $found = 0
  foreach ($name in $remote.Keys) {
    $pat = $remote[$name]
    $inst = @($apps | Where-Object { $_ -match $pat }); $run = @($procs | Where-Object { $_ -match $pat }); $svc = @($svcs | Where-Object { $_.Text -match $pat })
    if ($inst -or $run -or $svc) {
      $found++
      $how = @(); if ($inst) { $how += 'installed' }; if ($run) { $how += 'RUNNING now' }; if ($svc | Where-Object Auto) { $how += 'starts with Windows' }
      Add-R "Remote Tool" WARN "$name ($($how -join ', ')) - the previous owner may still be able to control this laptop; uninstall it after buying"
    }
  }
  if (-not $found) { Add-R "Remote Tool" PASS "No remote-control software (AnyDesk, TeamViewer, UltraViewer, RustDesk...) found" }

  $spyPat = 'Spyrix|Refog|Revealer Keylogger|Kidlogger|Ardamax|Elite Keylogger|Actual Keylogger|Spytech|SpyAgent|Hoverwatch|FlexiSPY|WebWatcher|Wolfeye|Best Free Keylogger|StaffCop|Teramind|ActivTrak|Veriato|njRAT|DarkComet|AsyncRAT|Remcos'
  $spy = @(@($apps) + @($procs) + @($svcs | ForEach-Object { $_.Text }) | ForEach-Object { if ($_ -match $spyPat) { $Matches[0] } } | Select-Object -Unique)
  if ($spy) { Add-R "Spyware" FAIL "Spy / keylogger / remote-trojan software found: $($spy -join ', ') - it can record everything you type" }
  else { Add-R "Spyware" PASS "No known spy / keylogger software found" }

  # Defender and the task list can hang for minutes on some PCs (e.g. Defender switched off by another antivirus), so they get a time limit
  Write-Host "  Checking Defender and scheduled tasks..." -ForegroundColor DarkGray
  $sec13 = Invoke-Timeout {
    $mp = Get-MpComputerStatus
    [PSCustomObject]@{
      HaveMp = [bool]$mp
      Rt     = [bool]$mp.RealTimeProtectionEnabled
      Thr    = @(Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-180) }).Count
      Active = @(Get-MpThreat | Where-Object IsActive | ForEach-Object { $_.ThreatName } | Select-Object -First 4)
      Tasks  = @(Get-ScheduledTask | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
    }
  } 45

  $kmsPat = 'KMSELDI|KMSAuto|AutoKMS|KMSpico|SECOH-QAD|AutoPico|KMS_VL|Activation-Renewal'
  $kms = @(@($svcs | Where-Object { $_.Text -match $kmsPat }) + @($sec13.Tasks | Where-Object { $_ -match $kmsPat }))
  $kmsFiles = @("$env:WINDIR\KMSAutoS", "$env:ProgramData\KMSAutoS", "$env:ProgramFiles\KMSpico", "$env:WINDIR\SECOH-QAD.exe", "$env:WINDIR\System32\SppExtComObjHook.dll", "$env:WINDIR\System32\SppExtComObjPatcher.exe") | Where-Object { Test-Path $_ }
  # $lic is the Windows license found in section 12 (that query is slow, so it is not repeated)
  $kmsChannel = "$($lic.Description)" -match 'VOLUME_KMSCLIENT' -and -not $cs.PartOfDomain
  if ($kms -or $kmsFiles -or $kmsChannel) { Add-R "Crack" WARN "Windows looks activated with a KMS crack - not genuine; cracks often come with malware (reinstall Windows or ask for a real license)" }

  $avs = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct)
  $avOn = @($avs | Where-Object { ([int]$_.productState -band 0x1000) -ne 0 })
  if ($avOn) {
    Add-R "Antivirus" PASS "Antivirus ON: $(($avOn | ForEach-Object { $_.displayName }) -join ', ')"
    if (@($avOn | Where-Object { ([int]$_.productState -band 0x10) -ne 0 })) { Add-R "Antivirus" INFO "Antivirus definitions are out of date - update it" }
  } elseif ($sec13.Rt) { Add-R "Antivirus" PASS "Microsoft Defender ON" }
  else { Add-R "Antivirus" WARN "No antivirus is turned on" }
  if ($isAdmin -and $sec13.HaveMp) {
    if ($sec13.Active) { Add-R "Threats" WARN "Virus / malware still ACTIVE: $($sec13.Active -join ', ') - run a full scan or reinstall Windows" }
    elseif ($sec13.Thr) { Add-R "Threats" INFO "Defender found and removed $($sec13.Thr) threat(s) in the last 6 months" }
  }
  $hosts = @(Get-Content "$env:WINDIR\System32\drivers\etc\hosts" | Where-Object { $_ -match '^\s*[0-9a-fA-F\.:]+\s+\S' -and $_ -notmatch '\slocalhost\b' })
  if ($hosts) {
    if (@($hosts | Where-Object { $_ -match 'microsoft|windowsupdate|adobe|autodesk|kms|activation|licen' })) { Add-R "Hosts File" WARN "hosts file blocks $($hosts.Count) sites (Microsoft / Adobe activation) - sign of cracked software" }
    else { Add-R "Hosts File" INFO "hosts file has $($hosts.Count) custom entries" }
  }
} catch { Skip-Section $_ }

# ---------- 14. Anti-theft & company locks ----------
Section "14. Anti-theft & Company Locks"
try {
  $ctSvc = @(Get-Service | Where-Object { $_.Name -match '^(rpcnet|rpcnetp|CTESPS|CTES)$' -or $_.DisplayName -match 'Absolute|Computrace' })
  $ctFile = (Test-Path "$env:WINDIR\System32\rpcnet.exe") -or (Test-Path "$env:WINDIR\System32\rpcnetp.exe")
  if ($ctSvc -or $ctFile) { Add-R "Computrace" FAIL "Computrace / Absolute anti-theft agent is ACTIVE - laptop may be tracked or locked by its owner" }
  else { Add-R "Computrace" PASS "No Computrace / Absolute agent running in Windows" }

  $tenant = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot').CloudAssignedTenantDomain
  $ds = "$(Invoke-Timeout { dsregcmd /status 2>$null | Out-String } 30)"
  $managed = @()
  if ($ds -match 'AzureAdJoined\s*:\s*YES') { $managed += 'Azure AD / Entra' }
  if ($cs.PartOfDomain) { $managed += "domain $($cs.Domain)" }
  $mdm = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.ProviderID -and $_.UPN })
  if ($mdm) { $managed += "MDM ($($mdm[0].UPN))" }
  if ($tenant) { Add-R "Autopilot" FAIL "Registered to company '$tenant' (Windows Autopilot) - after a reset it will ask for COMPANY login" }
  if ($managed) { Add-R "Company PC" WARN "Managed by an organization: $($managed -join ', ') - may be company property, ask for release proof" }
  elseif (-not $tenant) { Add-R "Company PC" PASS "Not linked to any company or school" }
} catch { Skip-Section $_ }

# ---------- 15. History log ----------
Section "15. History log (what happened before)"
try {
  $since = (Get-Date).AddDays(-180)
  $oldest = Get-WinEvent -LogName System -Oldest -MaxEvents 1
  if ($oldest) {
    $days = [math]::Round(((Get-Date) - $oldest.TimeCreated).TotalDays)
    if ($days -lt 7) { Add-R "Log Age" WARN ("Log starts {0:yyyy-MM-dd} (only $days days) - Windows was reset, old history HIDDEN" -f $oldest.TimeCreated) }
    else { Add-R "Log Age" PASS ("Log history from {0:yyyy-MM-dd} ($days days)" -f $oldest.TimeCreated) }
  }
  $cleared = Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Eventlog'; Id = 104 } 1
  if ($cleared -and $cleared[0].TimeCreated -gt (Get-Date).AddDays(-30)) { Add-R "Log Cleared" WARN ("Log was CLEARED on {0:yyyy-MM-dd} - recent, history may be hidden" -f $cleared[0].TimeCreated) }

  # bugcheck codes as hex strings: big codes like 0xC000021A do not fit in [int]
  $bugReason = @{ '1A' = 'RAM'; '50' = 'RAM'; '4E' = 'RAM'; '7A' = 'SSD'; '77' = 'SSD'; 'F4' = 'SSD'; '7B' = 'SSD'; '133' = 'SSD driver'
                  '124' = 'CPU/Hardware'; '101' = 'CPU/Hardware'; '9C' = 'CPU/Hardware'; '116' = 'GPU'; '117' = 'GPU'
                  '9F' = 'Driver'; 'D1' = 'Driver'; '3B' = 'Driver'; '7E' = 'Driver'; '1E' = 'Driver' }
  $why = @{}
  foreach ($e in (Get-Events @{ LogName = 'System'; Id = 41; StartTime = $since })) {
    $ed = @{}; ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $ed[$_.Name] = $_.'#text' }
    $code = [int64]$ed.BugcheckCode
    if ($code -ne 0) { $hex = '{0:X}' -f $code; $r = $bugReason[$hex]; if (-not $r) { $r = "BSOD 0x$hex" } }
    elseif ([int64]$ed.PowerButtonTimestamp -ne 0) { $r = 'Power button forced' }
    else { $r = 'Sudden power off' }
    $why[$r]++
  }
  if ($why.Count -eq 0) { Add-R "Shutdowns" PASS "No unexpected shutdown in last 6 months" }
  foreach ($k in $why.Keys) {
    $c = $why[$k]
    if ($k -in 'RAM', 'SSD', 'CPU/Hardware', 'GPU') { Add-R "Crash Cause" FAIL "$c crash(es) caused by $k in last 6 months" }
    elseif ($k -eq 'Sudden power off') {
      if ($c -ge 5) { Add-R "Power Off" WARN "$c sudden power-offs in 6 months - battery/charger/OVERHEAT/load-shedding" }
      else { Add-R "Power Off" INFO "$c sudden power-off(s) in 6 months - power cut / battery empty" }
    }
    elseif ($k -eq 'Power button forced') { Add-R "Forced Off" INFO "$c time(s) power button held - laptop froze?" }
    else { Add-R "Crash Cause" WARN "$c crash(es) by $k in 6 months (usually fixed by Windows reinstall)" }
  }

  $whea = Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since }
  # judge by event level (Critical/Error vs Warning=corrected) instead of IDs, which mean different things on different PCs
  $wErr = @($whea | Where-Object { $_.Level -in 1, 2 })
  $wCorr = @($whea | Where-Object { $_.Level -eq 3 })
  $wCpu = @($wCorr | Where-Object Id -eq 19).Count
  $wRam = @($wCorr | Where-Object Id -eq 47).Count
  $wPci = @($wCorr | Where-Object Id -eq 17).Count
  $comp = ($wErr | ForEach-Object { if ($_.Message -match 'Component:\s*([^\r\n]+)') { $Matches[1].Trim() } } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
  $compText = if ($comp) { " (mostly: $comp)" } else { '' }
  $hwCrash = [int]$why['CPU/Hardware']
  if ($wErr -and $hwCrash) { Add-R "HW Errors" FAIL "$($wErr.Count) serious hardware errors and $hwCrash hardware crash(es) in 6 months$compText" }
  elseif ($wErr) { Add-R "HW Errors" WARN ("$($wErr.Count) hardware error reports in 6 months$compText, but no crash from them - last {0:yyyy-MM-dd}; check that part works" -f $wErr[0].TimeCreated) }
  elseif ($wCpu -ge 3 -or $wRam -ge 3 -or $wPci -ge 20) { Add-R "HW Errors" WARN "Corrected errors in 6 months: CPU=$wCpu, RAM=$wRam, PCIe(SSD/WiFi)=$wPci" }
  else { Add-R "HW Errors" PASS "No serious hardware errors in last 6 months" }

  $diskBad = @(Get-Events @{ LogName = 'System'; ProviderName = 'disk'; Id = 7, 51; StartTime = $since }).Count
  $diskRetry = @(Get-Events @{ LogName = 'System'; ProviderName = 'disk', 'stornvme', 'storahci', 'iaStorA', 'iaStorAC', 'iaStorVD'; Id = 129, 153; StartTime = $since }).Count
  if ($diskBad) { Add-R "Disk Log" FAIL "$diskBad bad-block/paging errors in 6 months - SSD/HDD failing" }
  elseif ($diskRetry -ge 3) { Add-R "Disk Log" WARN "$diskRetry disk reset/retry events in 6 months" }
  else { Add-R "Disk Log" PASS "No disk errors in last 6 months" }

  $throttle = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = (Get-Date).AddDays(-30) }).Count
  if ($throttle -ge 20) { Add-R "Throttling" WARN "CPU slowed by firmware $throttle times in 30 days - heat/charger issue" }
  $dumps = @(Get-ChildItem "$env:WINDIR\Minidump" -Filter *.dmp).Count
  if ($dumps) { Add-R "Crash Dumps" INFO "$dumps crash dump file(s) in $env:WINDIR\Minidump" }
} catch { Skip-Section $_ }

# ---------- Helpers for the hand checks ----------
function Show-KeyboardTest {
  # each key: label, virtual-key code (hex), width in key units; the last row is optional
  $rows = @(
    @('Esc:1B', 'F1:70', 'F2:71', 'F3:72', 'F4:73', 'F5:74', 'F6:75', 'F7:76', 'F8:77', 'F9:78', 'F10:79', 'F11:7A', 'F12:7B', 'PrtSc:2C', 'Del:2E'),
    @('`:C0', '1:31', '2:32', '3:33', '4:34', '5:35', '6:36', '7:37', '8:38', '9:39', '0:30', '-:BD', '=:BB', 'Backspace:08:2'),
    @('Tab:09:1.5', 'Q:51', 'W:57', 'E:45', 'R:52', 'T:54', 'Y:59', 'U:55', 'I:49', 'O:4F', 'P:50', '[:DB', ']:DD', '\:DC:1.5'),
    @('Caps:14:1.8', 'A:41', 'S:53', 'D:44', 'F:46', 'G:47', 'H:48', 'J:4A', 'K:4B', 'L:4C', ';:BA', "':DE", 'Enter:0D:2.2'),
    @('Shift:A0:2.3', 'Z:5A', 'X:58', 'C:43', 'V:56', 'B:42', 'N:4E', 'M:4D', ',:BC', '.:BE', '/:BF', 'Shift:A1:2.7'),
    @('Ctrl:A2:1.5', 'Win:5B:1.2', 'Alt:A4:1.2', 'Space:20:6', 'Alt:A5:1.2', 'Ctrl:A3:1.5', 'Left:25', 'Up:26', 'Down:28', 'Right:27'),
    @('Home:24', 'End:23', 'PgUp:21', 'PgDn:22', 'Ins:2D', 'Menu:5D', 'NumLk:90')
  )
  # event handlers only see script-scope variables reliably (Windows PowerShell 5.1), so the state lives there
  $u = 60
  $script:kbForm = New-Object Windows.Forms.Form
  $script:kbForm.Text = 'Keyboard & touchpad test - press EVERY key, click left / right, scroll with 2 fingers, then close this window'
  $script:kbForm.Width = 16 * $u + 40; $script:kbForm.Height = 8 * $u + 110; $script:kbForm.StartPosition = 'CenterScreen'
  $script:kbForm.TopMost = $true; $script:kbForm.BackColor = [Drawing.Color]::White; $script:kbForm.KeyPreview = $true
  $script:kbInfo = New-Object Windows.Forms.Label
  $script:kbInfo.SetBounds(10, 8, 15 * $u, 40); $script:kbInfo.Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)
  $script:kbForm.Controls.Add($script:kbInfo)
  $script:kbLabels = @{}; $script:kbRequired = @{}; $script:kbHit = @{}; $script:kbClicks = @{ Left = 0; Right = 0; Scroll = 0 }
  $y = 56
  for ($r = 0; $r -lt $rows.Count; $r++) {
    $x = 10
    foreach ($k in $rows[$r]) {
      $parts = $k -split ':'; $vk = [Convert]::ToInt32($parts[1], 16); $wU = if ($parts.Count -ge 3) { [double]$parts[2] } else { 1 }
      $lb = New-Object Windows.Forms.Label
      $lb.SetBounds($x, $y, [int]($wU * $u) - 4, $u - 4); $lb.Text = $parts[0]; $lb.TextAlign = 'MiddleCenter'; $lb.BorderStyle = 'FixedSingle'
      $lb.Font = New-Object Drawing.Font('Segoe UI', 10); $lb.BackColor = $(if ($r -eq 6) { [Drawing.Color]::WhiteSmoke } else { [Drawing.Color]::Gainsboro })
      $script:kbForm.Controls.Add($lb)
      if (-not $script:kbLabels.ContainsKey($vk)) { $script:kbLabels[$vk] = @() }
      $script:kbLabels[$vk] += $lb
      if ($r -lt 6) { $script:kbRequired[$vk] = $parts[0] }
      $x += [int]($wU * $u)
    }
    $y += $u + $(if ($r -eq 5) { 14 } else { 0 })
  }
  $script:kbShow = {
    $n = @($script:kbHit.Keys | Where-Object { $script:kbRequired.ContainsKey($_) }).Count
    $script:kbInfo.Text = "Keys: $n of $($script:kbRequired.Count) pressed   |   Touchpad: left $($script:kbClicks.Left), right $($script:kbClicks.Right), scroll $($script:kbClicks.Scroll)   (grey row = optional)"
  }
  $script:kbMark = { param($vk)
    if ($script:kbLabels.ContainsKey($vk) -and -not $script:kbHit.ContainsKey($vk)) {
      $script:kbHit[$vk] = $true
      foreach ($lb in $script:kbLabels[$vk]) { $lb.BackColor = [Drawing.Color]::LimeGreen; $lb.ForeColor = [Drawing.Color]::White }
      & $script:kbShow
    }
  }
  & $script:kbShow
  # key events catch fast taps; Shift / Ctrl / Alt are split into left and right with the real key state
  $script:kbForm.Add_KeyDown({ param($s, $e)
    $vk = [int]$e.KeyCode
    $pairs = @{ 16 = 0xA0, 0xA1; 17 = 0xA2, 0xA3; 18 = 0xA4, 0xA5 }
    if ($pairs.ContainsKey($vk)) { foreach ($side in $pairs[$vk]) { if ([LcKeys]::Down($side)) { & $script:kbMark $side } } }
    else { & $script:kbMark $vk }
    $e.Handled = $true; $e.SuppressKeyPress = $true
  })
  # polling catches keys that never reach the window (Win, PrtSc)
  $script:kbTimer = New-Object Windows.Forms.Timer; $script:kbTimer.Interval = 15
  $script:kbTimer.Add_Tick({ foreach ($vk in @($script:kbLabels.Keys)) { if (-not $script:kbHit.ContainsKey($vk) -and [LcKeys]::Hit($vk)) { & $script:kbMark $vk } } })
  $click = { param($s, $e) if ($e.Button -eq 'Left') { $script:kbClicks.Left++ } elseif ($e.Button -eq 'Right') { $script:kbClicks.Right++ }; & $script:kbShow }
  $script:kbForm.Add_MouseDown($click); foreach ($c in $script:kbForm.Controls) { $c.Add_MouseDown($click) }
  $script:kbForm.Add_MouseWheel({ $script:kbClicks.Scroll++; & $script:kbShow })
  # read every key once before the window opens: GetAsyncKeyState remembers presses since the last read,
  # so the ENTER that started this step (or an S typed earlier) would otherwise turn green without being tested
  foreach ($vk in @($script:kbLabels.Keys)) { [void][LcKeys]::Hit($vk) }
  $script:kbTimer.Start()
  [void]$script:kbForm.ShowDialog()
  $script:kbTimer.Stop()
  $missing = @($script:kbRequired.Keys | Where-Object { -not $script:kbHit.ContainsKey($_) } | ForEach-Object { $script:kbRequired[$_] })
  $pad = "touchpad clicks left $($script:kbClicks.Left) / right $($script:kbClicks.Right), scroll $($script:kbClicks.Scroll)"
  if (-not $missing) { Add-R "Key Test" PASS "All $($script:kbRequired.Count) keys work; $pad" }
  else { Add-R "Key Test" INFO "$($script:kbRequired.Count - $missing.Count) of $($script:kbRequired.Count) keys pressed; NOT pressed: $($missing -join ' ') ; $pad" }
}
function Show-SimpleKeyTest {
  $script:keys = New-Object 'System.Collections.Generic.HashSet[string]'
  $kf = New-Object Windows.Forms.Form
  $kf.Text = 'Keyboard test - press EVERY key, then close this window'
  $kf.Width = 1000; $kf.Height = 420; $kf.StartPosition = 'CenterScreen'; $kf.TopMost = $true; $kf.KeyPreview = $true
  $script:kl = New-Object Windows.Forms.Label
  $script:kl.Dock = 'Fill'; $script:kl.Font = New-Object Drawing.Font('Consolas', 13); $script:kl.Text = 'Press keys...'
  $kf.Controls.Add($script:kl)
  $kf.Add_KeyDown({ param($s, $e) [void]$script:keys.Add("$($e.KeyCode)"); $e.Handled = $true; $e.SuppressKeyPress = $true; $script:kl.Text = "Keys pressed: $($script:keys.Count)`n`n" + (($script:keys | Sort-Object) -join '  ') })
  [void]$kf.ShowDialog()
  Add-R "Key Test" INFO "$($script:keys.Count) different keys pressed"
}
function Show-TouchTest {
  $f = New-Object Windows.Forms.Form
  $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'; $f.TopMost = $true; $f.BackColor = [Drawing.Color]::Black; $f.KeyPreview = $true
  $lb = New-Object Windows.Forms.Label
  $lb.Text = 'Draw lines with your finger over the WHOLE screen. Gaps in a line = dead touch area. Press Esc to finish.'
  $lb.ForeColor = [Drawing.Color]::White; $lb.Font = New-Object Drawing.Font('Segoe UI', 14); $lb.AutoSize = $true; $lb.Location = New-Object Drawing.Point(20, 20)
  $f.Controls.Add($lb)
  $script:tPen = New-Object Drawing.Pen ([Drawing.Color]::Lime), 6
  $script:tLast = $null
  $f.Add_MouseDown({ param($s, $e) $script:tLast = $e.Location })
  $f.Add_MouseMove({ param($s, $e) if ($e.Button -ne 'None' -and $script:tLast) { $g = $s.CreateGraphics(); $g.DrawLine($script:tPen, $script:tLast, $e.Location); $g.Dispose(); $script:tLast = $e.Location } })
  $f.Add_MouseUp({ $script:tLast = $null })
  $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $s.Close() } })
  [void]$f.ShowDialog()
}

# dims to 10%, brightens to 100%, restores; true when the screen has a brightness control
function Test-Brightness {
  $brOld = Get-Brightness
  if ($null -eq $brOld) { Add-R "Brightness" WARN "Brightness control not available - display driver missing, or not a built-in screen"; return $false }
  [void](Set-Brightness 10); Start-Sleep -Milliseconds 1500; $b1 = Get-Brightness
  [void](Set-Brightness 100); Start-Sleep -Milliseconds 1500; $b2 = Get-Brightness
  [void](Set-Brightness $brOld)
  if ($b1 -le 20 -and $b2 -ge 90) { Add-R "Brightness" PASS "Brightness control works (10% -> 100%, restored to $brOld%)" }
  else { Add-R "Brightness" WARN "Brightness did not change as asked (read $b1% / $b2%) - driver or panel problem" }
  $true
}
# plays a rising tone on the left, then the right speaker while the microphone listens:
# if the mic hears it, both speaker and mic work - no person needed. Volume and mute are restored after.
function Test-SpeakerMic {
  $vol = [LcAudio]::GetVolume(); $mute = [LcAudio]::GetMute()
  if ($vol -lt 0) { Add-R "Speaker/Mic" WARN "No speaker / sound output device found"; return }
  [LcAudio]::Set(0.8, $false)
  $heard = @{}; $base = -1
  try {
    if ([LcMic]::Open()) {
      $base = 0
      for ($k = 0; $k -lt 5; $k++) { $p = [LcMic]::Peak(200); if ($p -gt $base) { $base = $p } }
    }
    foreach ($side in 0, 1) {
      Write-Host "  Playing test tone: $(if ($side -eq 0) { 'LEFT' } else { 'RIGHT' }) speaker" -ForegroundColor DarkGray
      $player = New-Object System.Media.SoundPlayer (New-Object IO.MemoryStream (, [LcTone]::Sweep(700, 3000, 1.6, $side)))
      $player.Play()
      $mx = 0; $t0 = Get-Date
      while (((Get-Date) - $t0).TotalSeconds -lt 1.6) { if ($base -ge 0) { $p = [LcMic]::Peak(150); if ($p -gt $mx) { $mx = $p } } else { Start-Sleep -Milliseconds 150 } }
      $player.Stop(); $heard[$side] = $mx; Start-Sleep -Milliseconds 300
    }
  } finally { [LcMic]::Close(); [LcAudio]::Set($vol, $mute) }
  if ($base -lt 0) { Add-R "Speaker/Mic" INFO "Test tones played, but there is no working microphone to check the speakers automatically"; return }
  $need = [math]::Max($base * 2, $base + 6)
  $l = $heard[0] -ge $need; $r = $heard[1] -ge $need
  $txt = "mic heard left $($heard[0])%, right $($heard[1])%, room noise $base%"
  if ($l -and $r) { Add-R "Speaker/Mic" PASS "Speakers and microphone work - $txt" }
  elseif ($l -or $r) { Add-R "Speaker/Mic" WARN "$(if ($l) { 'RIGHT' } else { 'LEFT' }) speaker may be dead or weak - $txt" }
  else { Add-R "Speaker/Mic" WARN "Microphone did not hear the speakers - speaker or mic is broken (or headphones are plugged in, or room too noisy) - $txt" }
}

function Show-ColourTest {
  $script:ctColors = 'White', 'Black', 'Red', 'Lime', 'Blue', 'Gray'
  $script:ci = 0
  $form = New-Object Windows.Forms.Form
  $form.FormBorderStyle = 'None'; $form.WindowState = 'Maximized'; $form.TopMost = $true; $form.KeyPreview = $true
  $form.BackColor = [Drawing.Color]::FromName($script:ctColors[0])
  $next = { param($s, $e)
    if ($e.KeyCode -eq 'Escape') { $s.Close(); return }
    $script:ci++
    if ($script:ci -ge $script:ctColors.Count) { $s.Close() } else { $s.BackColor = [Drawing.Color]::FromName($script:ctColors[$script:ci]) } }
  $form.Add_KeyDown($next); $form.Add_MouseClick($next)
  [Windows.Forms.Cursor]::Hide(); [void]$form.ShowDialog(); [Windows.Forms.Cursor]::Show()
}
# watches for USB devices and external displays being plugged in, until ENTER (max 5 min)
function Test-Ports {
  function Get-UsbIds { @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID*' -and $_.InstanceId -notmatch '&MI_' } | ForEach-Object { $_.InstanceId }) }
  $known = Get-UsbIds
  $monKnown = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams | ForEach-Object { $_.InstanceName })
  $ports = [ordered]@{}; $video = @()
  Write-Host "   Waiting for devices... press ENTER when all ports are done." -ForegroundColor Yellow
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalMinutes -lt 5) {
    try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { break } } catch {}
    $now = Get-UsbIds
    foreach ($id in $now) {
      if ($id -in $known) { continue }
      $loc = "$((Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data)"
      $key = if ($loc -match 'Port_#0*(\d+)\.Hub_#0*(\d+)') { "port $($Matches[1]) on hub $($Matches[2])" } else { $loc }
      if (-not $key) { $key = $id }
      if (-not $ports.Contains($key)) {
        $ports[$key] = (Get-PnpDevice -InstanceId $id).FriendlyName
        Write-Host "   + USB OK: $key  ($($ports[$key]))" -ForegroundColor Green
      }
    }
    # forget unplugged devices, so the same device is detected again in the next port
    $known = @($known | Where-Object { $_ -in $now }) + @($now | Where-Object { $_ -notin $known })
    foreach ($m in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams)) {
      if ($m.InstanceName -in $monKnown) { continue }
      $monKnown += $m.InstanceName
      $tech = switch ($m.VideoOutputTechnology) { 5 { 'HDMI' } 10 { 'DisplayPort / USB-C' } 4 { 'DVI' } 0 { 'VGA' } default { "type $($m.VideoOutputTechnology)" } }
      $video += $tech
      Write-Host "   + Display output OK: $tech" -ForegroundColor Green
    }
    Start-Sleep -Milliseconds 700
  }
  if ($ports.Count) { Add-R "USB Ports" PASS "$($ports.Count) USB port(s) worked: $($ports.Keys -join '; ') - any port you tried that never showed 'USB OK' is dead" }
  else { Add-R "USB Ports" WARN "No USB device was detected - the ports may not work (or nothing was plugged in)" }
  if ($video) { Add-R "Video Port" PASS "External display detected on: $(($video | Select-Object -Unique) -join ', ')" }
}
# shows what the person has to do (English, plus Chinese on Chinese Windows); ENTER starts, S skips
function Show-Step($title, [string[]]$how, $key) {
  $script:stepNo++
  Write-Host "`n  ===== STEP $($script:stepNo) - $title =====" -ForegroundColor Cyan
  foreach ($l in $how) { Write-Host "   $l" }
  if ($key -and $tr.steps.$key) { foreach ($l in $tr.steps.$key) { Write-Host "   $l" -ForegroundColor DarkCyan } }
  if ($tr.ui.enter) { Write-Host "   $($tr.ui.enter)" -ForegroundColor DarkCyan }
  (Read-Host "   Press ENTER to start  (S + ENTER = skip)") -notmatch '^\s*[sS]'
}

# ---------- 16. Hand checks: a person does them, the script says how and records what it can measure ----------
$hand = @{}; $script:stepNo = 0
if (-not $NoPrompt -and -not $Auto) {
  Section "16. Hand checks - follow the steps"
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  Write-Host "  These steps need a person (about 5 minutes). Read each step, press ENTER, then do it." -ForegroundColor Yellow

  if (Show-Step 'SCREEN' @(
      'A full-screen colour test opens: white, black, red, green, blue, grey.',
      'Look closely for dots that stay one colour, lines, spots, or light leaking at the edges.',
      'Click or press any key for the next colour. Esc = stop.') 'screen') {
    Show-ColourTest; $hand.Screen = $true
  }
  Update-Overall 0.2
  if ($script:hasTouch -and (Show-Step 'TOUCHSCREEN' @(
      'Draw lines with your finger over the WHOLE screen.',
      'A gap in a line = dead touch area. Press Esc when finished.') 'touch')) {
    Show-TouchTest; $hand.Touch = $true
  }
  Update-Overall 0.3
  if (Show-Step 'KEYBOARD & TOUCHPAD' @(
      'A keyboard picture opens. Press EVERY key once - it turns green.',
      'If F1-F12 change volume / brightness instead, hold Fn while pressing them.',
      'Click left and right on the touchpad, and scroll with two fingers.',
      'Close the window (X) when finished. Keys that stay grey do not work (or are not on this laptop).') 'keyboard') {
    if ($script:Native) { Show-KeyboardTest } else { Show-SimpleKeyTest }
    $hand.Keyboard = $true
  }
  Update-Overall 0.6
  if (Show-Step 'USB / HDMI PORTS' @(
      'You need a mouse or a USB stick. (If you use this pendrive, plug it back in before the end.)',
      'Plug it into EACH USB and Type-C port, one by one. Every working port shows "USB OK".',
      'Have an HDMI cable and a TV / monitor? Connect it too.',
      'Press ENTER when all ports are done.') 'ports') {
    Test-Ports; $hand.Ports = $true
  }
  Update-Overall 0.85
  if (Show-Step 'WEBCAM' @(
      'The Camera app opens. Check that the picture is clear and not dark or blurry.',
      'Close the Camera app, then come back here.') 'webcam') {
    try { Start-Process 'microsoft.windows.camera:' -ErrorAction Stop } catch { Write-Host "   Camera app not available - test the webcam in any video app." -ForegroundColor DarkGray }
    [void](Read-Host "   Press ENTER when you have looked at the picture")
    $hand.Webcam = $true
  }
  Write-Host "`n  Hand steps done. The rest runs by itself - you will hear a BEEP when the charger must be unplugged." -ForegroundColor Green
}

# ---------- 17. CPU heat / stress test ----------
if ($StressSeconds -gt 0) {
  Section "17. CPU heat test ($StressSeconds sec) - connect the CHARGER"
  Write-Host "  If the laptop turns OFF during this test = OVERHEAT = do NOT buy." -ForegroundColor Yellow
  $wbNow = Get-CimInstance Win32_Battery | Select-Object -First 1
  $onBattery = $wbNow -and $wbNow.BatteryStatus -notin 2, 6, 7, 8, 9
  if ($onBattery) { Write-Host "  Running on BATTERY - CPU speed results will be lower than normal." -ForegroundColor Yellow }
  $idleTemp = Get-CpuTemp
  # Windows often cannot read laptop CPU temperature; open HWMonitor from the pendrive to watch it
  $hwm = Join-Path $KitRoot 'Tools\HWMonitor\HWMonitor_x64.exe'
  if (-not $idleTemp -and (Test-Path $hwm)) {
    Write-Host "  Opening HWMonitor - watch the CPU 'Max' temperature during the test." -ForegroundColor Yellow
    Start-Process $hwm
  }
  # 100% load on every core; background jobs are the fallback if C# compiling is blocked
  $jobs = @()
  if (-not (Start-Burn ([Environment]::ProcessorCount))) {
    $burn = { param($s) $end = [DateTime]::Now.AddSeconds($s); $x = 0.0; while ([DateTime]::Now -lt $end) { for ($i = 0; $i -lt 200000; $i++) { $x += [Math]::Sqrt($i) } } }
    $jobs = @(1..[Environment]::ProcessorCount | ForEach-Object { Start-Job -ScriptBlock $burn -ArgumentList ($StressSeconds + 60) })
  }
  try {
    # wait until all cores are busy (max 30 sec) before measuring
    $w0 = Get-Date
    do {
      Start-Sleep -Seconds 2
      $l = (Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'").PercentProcessorTime
      Write-Progress -Activity "CPU heat test" -Status "Starting load on all cores... $l%"
    } while ($l -lt 85 -and ((Get-Date) - $w0).TotalSeconds -lt 30)
    $maxTemp = 0; $perf = @(); $load = @()
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $StressSeconds) {
      $pInfo = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
      $tNow = Get-CpuTemp
      if ($tNow -gt $maxTemp) { $maxTemp = $tNow }
      if ($pInfo) { $perf += $pInfo.PercentProcessorPerformance; $load += $pInfo.PercentProcessorTime }
      # PowerShell names ignore case: naming this "sec" would overwrite the section title in $script:Sec
      $elapsedSec = [int]((Get-Date) - $t0).TotalSeconds
      Update-Overall ($elapsedSec / $StressSeconds)
      Write-Progress -Activity "CPU heat test" -Status ("Load {0}% | Speed {1}% | Temp {2}" -f $pInfo.PercentProcessorTime, $pInfo.PercentProcessorPerformance, $(if ($tNow) { "$tNow C" } else { 'n/a' })) -PercentComplete ([math]::Min(100, $elapsedSec * 100 / $StressSeconds))
      Start-Sleep -Seconds 2
    }
  } finally {
    Write-Progress -Activity "CPU heat test" -Completed
    Stop-Burn
    if ($jobs) { $jobs | Stop-Job; $jobs | Remove-Job -Force }
  }
  $avgLoad = if ($load) { [math]::Round(($load | Measure-Object -Average).Average) } else { 0 }
  $minPerf = if ($perf) { ($perf | Measure-Object -Minimum).Minimum } else { 0 }
  $avgPerf = if ($perf) { [math]::Round(($perf | Measure-Object -Average).Average) } else { 0 }
  Add-R "Stress Load" INFO "Average CPU load $avgLoad% for $StressSeconds sec - laptop stayed ON"
  if ($maxTemp -ge 95) { Add-R "CPU Temp" FAIL "Max $maxTemp C (idle $idleTemp C) - OVERHEATING (fan/thermal paste)" }
  elseif ($maxTemp -ge 90) { Add-R "CPU Temp" WARN "Max $maxTemp C (idle $idleTemp C) - hot, needs cleaning + thermal paste" }
  elseif ($maxTemp -gt 0) { Add-R "CPU Temp" PASS "Max $maxTemp C (idle $idleTemp C, approx. sensor)" }
  else { Add-R "CPU Temp" INFO "Temperature sensor not readable - use HWMonitor" }
  if ($perf) {
    if ($minPerf -lt 50) { Add-R "CPU Speed" WARN "Speed dropped to $minPerf% under load (avg $avgPerf%) - THROTTLING: $(if ($onBattery) {'running on battery'} else {'heat or weak charger'})" }
    else { Add-R "CPU Speed" PASS "Speed stayed $minPerf-$(($perf | Measure-Object -Maximum).Maximum)% of base clock under load" }
  }
}

# ---------- 18. Battery test (real battery backup, not what the chip claims) ----------
if ((-not $NoPrompt -or $Auto) -and -not $Quick -and $isLaptop -and $hasBattery) {
  Section "18. Battery test - REAL battery backup"
  # FULL POWER test (all cores + full brightness until the battery drops 20%); -BatteryTestMinutes N gives a quick light-use test
  $fullTest = -not $PSBoundParameters.ContainsKey('BatteryTestMinutes')
  $waitSec = 180
  Write-Host "  >>> UNPLUG the charger now <<<  (waiting up to $waitSec sec)" -ForegroundColor Yellow
  $w0 = Get-Date; $beep = 0
  do {
    if (($beep++ % 5) -eq 0) { [Console]::Beep(1000, 300); [Console]::Beep(1400, 300) }
    Start-Sleep -Seconds 2; $st = Get-BatState
  } while ($st.OnAC -and ((Get-Date) - $w0).TotalSeconds -lt $waitSec)
  if ($st.OnAC) { Add-R "Drain Test" INFO "Charger was not unplugged - test skipped" }
  elseif ($fullTest -and $st.Pct -lt 30) { Add-R "Drain Test" INFO "Battery is at $($st.Pct)% - charge it above 30% first for the full power test" }
  else {
    Start-Sleep -Seconds 8
    $idleW = (Get-BatState).Rate / 1000
    $brOld = Get-Brightness
    if ($fullTest -and $null -ne $brOld) { [void](Set-Brightness 100) }
    # full test: every core; quick test: a quarter of the cores, like browser / office use
    $threads = if ($fullTest) { [Environment]::ProcessorCount } else { [math]::Max(1, [int]([Environment]::ProcessorCount / 4)) }
    $burning = Start-Burn $threads
    $limitMin = if ($fullTest) { 40 } else { $BatteryTestMinutes }
    $stuckPct = $false
    try {
      Start-Sleep -Seconds 10
      $s0 = Get-BatState; $t0 = Get-Date; $rates = @(); $s1 = $s0; $lastLog = [datetime]::MinValue
      $lastPct = $s0.Pct; $lastPctTime = Get-Date
      # if the laptop dies during the test this log stays behind, and the next run reports it
      Set-Content $batLog "START|$(Get-Date -Format s)|$($s0.Pct)|$(if ($fullTest) { 'full power' } else { 'quick' })"
      Write-Host "  Battery test running (up to $limitMin min) - keep the charger UNPLUGGED. Press Q to stop early." -ForegroundColor Yellow
      while (((Get-Date) - $t0).TotalMinutes -lt $limitMin) {
        Start-Sleep -Seconds 5
        try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Q') { Write-Host "  Stopped by Q - using the data so far." -ForegroundColor Yellow; break } } catch {}
        $s1 = Get-BatState
        if ($s1.OnAC) { Write-Host "  Charger plugged in - test ends here." -ForegroundColor Yellow; break }
        if ($s1.Rate -gt 0) { $rates += $s1.Rate }
        $el = ((Get-Date) - $t0).TotalMinutes
        $drop = $s0.Pct - $s1.Pct
        # some batteries never update their %; do not wait the whole time for nothing
        if ($s1.Pct -ne $lastPct) { $lastPct = $s1.Pct; $lastPctTime = Get-Date }
        elseif (((Get-Date) - $lastPctTime).TotalMinutes -ge 10) { $stuckPct = $true; Write-Host "  Battery % has not changed for 10 min - stopping." -ForegroundColor Yellow; break }
        if ($fullTest -and ($drop -ge 20 -or $s1.Pct -le 8)) { break }
        $pc = if ($fullTest) { [math]::Min(100, [math]::Max(0, $drop) * 5) } else { [math]::Min(100, $el * 100 / $limitMin) }
        $left = if ($fullTest -and $drop -gt 0) { [math]::Max(0, $el / $drop * (20 - $drop)) } else { $limitMin - $el }
        $stText = "{0:N0} min | battery {1}% (started {2}%, dropped {3}{4}) | about {5:N0} min left" -f $el, $s1.Pct, $s0.Pct, $drop, $(if ($fullTest) { ' of 20%' } else { '%' }), $left
        if ($s1.Rate) { $stText += " | using {0:N1} W" -f ($s1.Rate / 1000) }
        Write-Progress -Activity "Battery test - keep the charger UNPLUGGED (Q = stop)" -Status $stText -PercentComplete $pc
        Update-Overall ($pc / 100)
        # a plain line every 30 sec too: the progress bar is hidden in some consoles, and then the test looks frozen
        if (((Get-Date) - $lastLog).TotalSeconds -ge 30) {
          Add-Content $batLog ("T|{0}|{1}|{2:N0}" -f (Get-Date -Format s), $s1.Pct, $el); $lastLog = Get-Date
          Write-Host "  [$($script:OverallPct)% of all tests] $stText"
        }
      }
    } finally {
      Write-Progress -Activity "Battery test - keep the charger UNPLUGGED (Q = stop)" -Completed
      if ($burning) { Stop-Burn }
      if ($fullTest -and $null -ne $brOld) { [void](Set-Brightness $brOld) }
      Remove-Item $batLog -Force
    }
    Write-Host "  >>> Done - plug the charger back in <<<" -ForegroundColor Green
    [Console]::Beep(1400, 300); [Console]::Beep(1000, 300)
    $mins = ((Get-Date) - $t0).TotalMinutes
    $dropPct = $s0.Pct - $s1.Pct
    $avgW = if ($rates) { ($rates | Measure-Object -Average).Average / 1000 } else { 0 }
    # fraction of a full charge used: from the chip's mWh counter (finer) or from the % shown
    $frac = if ($s0.Rem -gt $s1.Rem -and $batFull) { ($s0.Rem - $s1.Rem) / $batFull } else { $dropPct / 100 }
    $cat = if ($fullTest) { 'Batt Backup' } else { 'Real Battery' }
    if ($stuckPct) { Add-R "Batt Chip" WARN "Battery % did not change for 10 minutes while unplugged and under load - the battery gauge is stuck or fake" }
    if ($s1.OnAC -and $mins -lt 1) { Add-R "Drain Test" INFO "Charger was plugged back too early - test skipped" }
    elseif ($frac -le 0) { if (-not $stuckPct) { Add-R "Drain Test" INFO ("Battery did not drop in {0:N0} min - good sign; run the full power test for an exact result" -f $mins) } }
    else {
      $hours = ($mins / 60) / $frac
      $dText = "Dropped $dropPct% in {0:N0} min{1} -> full charge lasts about $(Format-Hours $hours) $(if ($fullTest) { 'at FULL power' } else { 'at light use' })" -f $mins, $(if ($avgW) { ' using {0:N1} W' -f $avgW } else { '' })
      $short = if ($fullTest) { $hours -lt 0.75 } else { $hours -lt 2 }
      if ($short) { Add-R $cat WARN "$dText - SHORT" } else { Add-R $cat PASS $dText }
      $normW = $idleW * 1.5
      if ($fullTest -and $idleW -gt 0 -and $normW -lt $avgW) {
        Add-R $cat INFO ("Normal use (browsing / office, about {0:N0} W): about $(Format-Hours ($hours * $avgW / $normW))" -f $normW)
      }
      # real capacity = energy really used / fraction of the charge it took; needs a big enough drop to be accurate
      if ($avgW -gt 0 -and $frac -ge 0.02 -and $batDesign) {
        $realWh = ($avgW * $mins / 60) / $frac
        $realHealth = [math]::Round($realWh * 1000 / $batDesign * 100)
        if ($batHealth -and $realHealth -lt $batHealth - 25) { Add-R "Real Health" WARN ("Chip says $batHealth% health but real test shows about $realHealth% ({0:N0} Wh) - battery chip is WRONG (fake / reset / uncalibrated). Treat as a WEAK battery" -f $realWh) }
        else { Add-R "Real Health" INFO ("Real test capacity about {0:N0} Wh (~$realHealth% health) - matches the chip" -f $realWh) }
      }
    }
    # voltage cannot be faked like capacity: weak cells sag below what the shown % should have
    $cells = if ($s1.DesignVolt -gt 0) { [math]::Round($s1.DesignVolt / 3800) } else { 0 }
    if ($s1.Volt -gt 0 -and $cells -ge 1 -and $cells -le 6) {
      $vCell = $s1.Volt / 1000 / $cells
      $vMin = if ($s1.Pct -ge 80) { 3.75 } elseif ($s1.Pct -ge 50) { 3.55 } elseif ($s1.Pct -ge 25) { 3.45 } else { 0 }
      $vText = "{0:N2} V per cell at $($s1.Pct)% under load ($cells cells)" -f $vCell
      if ($vMin -and $vCell -lt $vMin) { Add-R "Batt Voltage" WARN "$vText - TOO LOW for this charge %: cells are weak, the % is not real and the laptop may shut down early" }
      elseif ($vMin) { Add-R "Batt Voltage" PASS "$vText - normal" }
    }
  }
}

# ---------- 19-20. Tests that need no person, then what only a person can check ----------
if (-not $NoPrompt) {
  Section "19. Automatic screen & sound checks"
  if ($isLaptop) { [void](Test-Brightness) }
  if ($script:Native) { Test-SpeakerMic } else { Add-R "Speaker/Mic" INFO "Automatic speaker test not available on this PC" }
}
Section "20. Still to check by hand"
Add-R "Do by Hand" INFO $(if ($hand.Screen) { "Screen: any dot, line or spot you saw in the colour test is a defect - ask for a lower price" } else { "Screen: look for dead pixels, lines, spots or flicker" })
if ($hand.Touch) { Add-R "Do by Hand" INFO "Touchscreen: any gap in the lines you drew is a dead touch area" }
Add-R "Do by Hand" INFO $(if ($hand.Keyboard) { "Keyboard: see 'Key Test' above - keys that stayed grey do not work (or are not on this laptop)" } else { "Keyboard & touchpad: press every key, click and scroll" })
Add-R "Do by Hand" INFO $(if ($hand.Ports) { "Ports: also try the headphone jack, SD slot and charging port" } else { "Ports: plug something into every USB / Type-C / HDMI / audio port and the charger port" })
Add-R "Do by Hand" INFO $(if ($hand.Webcam) { "Webcam: a dark or blurry picture is a defect" } else { "Webcam: open the Camera app, the picture must be clear" })
Add-R "Do by Hand" INFO "Serial sticker under the laptop must be: $serial"
Add-R "Do by Hand" INFO "BIOS: restart, press F2 / Del / F10 / Esc at power on - it must open WITHOUT a password"
Add-R "Do by Hand" INFO "Body: no crack, broken hinge, swollen battery (case or touchpad lifting), missing screws or water marks"
Add-R "Do by Hand" INFO "Fan: during the heat test the fan must spin up without grinding or rattling noise"
Update-Overall 1
try { $Host.UI.RawUI.WindowTitle = "Laptop Checker - 100% done - Made by Mahdi" } catch {}
Write-Host "`n>> [100%] All tests finished" -ForegroundColor Green
[Console]::Beep(1000, 200); [Console]::Beep(1300, 200); [Console]::Beep(1600, 300)

# ---------- Final result ----------
$fail = @($Results | Where-Object Status -eq 'FAIL')
$warn = @($Results | Where-Object Status -eq 'WARN')
$pass = @($Results | Where-Object Status -eq 'PASS')
$score = [math]::Max(0, 100 - 15 * $fail.Count - 5 * $warn.Count)
if ($fail) { $verdict = 'NOT RECOMMENDED - serious problem found (see FAIL)'; $vKey = 'FAIL'; $vColor = 'Red'; $vHex = '#d93025' }
elseif ($warn) { $verdict = 'OK TO BUY - but bargain price for the WARN items'; $vKey = 'WARN'; $vColor = 'Yellow'; $vHex = '#c98a00' }
else { $verdict = 'GOOD - laptop looks healthy'; $vKey = 'GOOD'; $vColor = 'Green'; $vHex = '#188038' }

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "   FINAL RESULT" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ("  PASS: {0}   WARN: {1}   FAIL: {2}   SCORE: {3}/100" -f $pass.Count, $warn.Count, $fail.Count, $score)
Write-Host "  VERDICT: $verdict" -ForegroundColor $vColor
if ($fail) { Write-Host "`n  Serious problems:" -ForegroundColor Red; $fail | ForEach-Object { Write-Host "   x $($_.Category): $($_.Detail)" -ForegroundColor Red } }
if ($warn) { Write-Host "`n  Bargain points:" -ForegroundColor Yellow; $warn | ForEach-Object { Write-Host "   ! $($_.Category): $($_.Detail)" -ForegroundColor Yellow } }

# ---------- HTML report (English + Bangla or Chinese from app\lang-*.json) ----------
function HtmlEnc($s) { [Net.WebUtility]::HtmlEncode("$s") }
# $bn holds the second report language (Bangla or Chinese, loaded at the start)
$bn = $tr
function Get-Bn($group, $key) { if ($bn) { $p = $bn.$group.PSObject.Properties["$key"]; if ($p) { $p.Value } } }
function Get-BnCat($c) { Get-Bn 'cat' ($c -replace ' \d+$') }
function Bn-Div($s, $cls = 'bn') { if ($s) { "<div class='$cls'>$(HtmlEnc $s)</div>" } }

if (-not (Test-Path $OutDir)) { $OutDir = [Environment]::GetFolderPath('Desktop') }
$safeModel = ($cs.Model -replace '[^\w\-]', '_')
$report = Join-Path $OutDir ("laptop-report_{0}_{1:yyyyMMdd-HHmmss}.html" -f $safeModel, (Get-Date))
$badge = @{ PASS = '#188038'; WARN = '#c98a00'; FAIL = '#d93025'; INFO = '#80868b' }
$rows = foreach ($g in ($Results | Group-Object Section)) {
  $num = if ($g.Name -match '^(\d+)\.') { $Matches[1] }
  $secBn = Get-Bn 'sections' $num
  "<tr class='h'><td colspan='3'>$(HtmlEnc $g.Name)$(if ($secBn) { " &middot; $(HtmlEnc $secBn)" })</td></tr>"
  foreach ($r in $g.Group) {
    $cb = Get-BnCat $r.Category
    $tip = if ($cb -and $r.Status -in 'WARN', 'FAIL') { Bn-Div $cb[1] 'tip' }
    "<tr><td>$(HtmlEnc $r.Category)$(if ($cb) { Bn-Div $cb[0] })</td><td><span class='b' style='background:$($badge[$r.Status])'>$($r.Status)</span>$(Bn-Div (Get-Bn 'status' $r.Status))</td><td>$(HtmlEnc $r.Detail)$tip</td></tr>"
  }
}
$problems = foreach ($r in @($fail) + @($warn)) {
  $cb = Get-BnCat $r.Category
  "<li><b style='color:$($badge[$r.Status])'>$($r.Status)</b> $(HtmlEnc $r.Category): $(HtmlEnc $r.Detail)$(if ($cb) { Bn-Div $cb[1] 'tip' })</li>"
}
$specs = @($cpuName, "$totalGB GB RAM", $gpuText, ($diskText -join ' + '), $batText) | Where-Object { $_ }
$html = @"
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Laptop Report - $(HtmlEnc $model)</title>
<style>
:root{--bg:#f4f6f8;--card:#fff;--fg:#202124;--mute:#5f6368;--line:#eee;--soft:#f1f3f4;--tip:#a35200}
@media (prefers-color-scheme:dark){:root{--bg:#121416;--card:#1e2124;--fg:#e8eaed;--mute:#9aa0a6;--line:#2d3135;--soft:#2a2e32;--tip:#f6ae5b}}
body{font-family:'Segoe UI','Nirmala UI','Microsoft YaHei','PingFang SC',Arial,sans-serif;background:var(--bg);color:var(--fg);margin:0;padding:16px}
.c{max-width:960px;margin:auto;background:var(--card);border-radius:12px;padding:20px;box-shadow:0 1px 4px #0003}
h1{margin:0 0 4px;font-size:22px}.m{color:var(--mute);font-size:14px}
.v{margin:16px 0;padding:14px;border-radius:10px;color:#fff;font-size:18px;font-weight:600;background:$vHex}.v .bn{color:#fff;font-size:16px;margin-top:4px}
.s{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:12px}.s div{flex:1;min-width:90px;background:var(--soft);border-radius:8px;padding:10px;text-align:center;font-size:13px}
.s b{display:block;font-size:22px}table{width:100%;border-collapse:collapse;font-size:14px}
td{padding:8px;border-bottom:1px solid var(--line);vertical-align:top}td:first-child{white-space:nowrap;font-weight:600}
tr.h td{background:var(--soft);font-weight:700;padding-top:12px}
.b{color:#fff;border-radius:4px;padding:2px 8px;font-size:12px;font-weight:700}
.bn{font-size:12px;color:var(--mute);font-weight:400;margin-top:2px}.tip{color:var(--tip);font-size:13px;margin-top:4px}
ul{padding-left:20px;font-size:14px}li{margin:6px 0}
button{float:right;border:0;border-radius:6px;padding:6px 12px;background:var(--soft);color:var(--fg);cursor:pointer}
@media print{button{display:none}body{background:#fff}.c{box-shadow:none}}
</style></head><body><div class="c">
<button onclick="print()">Print / Save PDF</button>
<h1>$(HtmlEnc $model)</h1>
<div class="m">Serial: $(HtmlEnc $serial) &middot; Checked $(Get-Date -Format 'yyyy-MM-dd HH:mm')$(if (-not $isAdmin) {' &middot; without Administrator (some checks skipped)'})</div>
<div class="m">$(HtmlEnc ($specs -join '  |  '))</div>
<div class="v">$verdict$(Bn-Div (Get-Bn 'verdict' $vKey))</div>
<div class="s"><div><b>$score</b>Score /100</div><div><b style="color:#188038">$($pass.Count)</b>PASS</div><div><b style="color:#c98a00">$($warn.Count)</b>WARN</div><div><b style="color:#d93025">$($fail.Count)</b>FAIL</div></div>
$(if ($problems) { "<h3>Problems / bargain points$(if ($bn) { ' &middot; ' + (HtmlEnc (Get-Bn 'ui' 'problems')) })</h3><ul>$($problems -join "`n")</ul>" })
<h3>All checks$(if ($bn) { ' &middot; ' + (HtmlEnc (Get-Bn 'ui' 'all')) })</h3>
<table>$($rows -join "`n")</table>
<p class="m">FAIL = do not buy &middot; WARN = bargain price &middot; PASS = OK &middot; INFO = for your information</p>
$(if ($bn) { "<p class='m'>$(HtmlEnc (Get-Bn 'ui' 'legend'))</p>" })
<p class="m" style="text-align:center;margin-top:20px">Laptop Auto Checker v4 &middot; Made by <b>Mahdi</b></p>
</div></body></html>
"@
$html | Out-File -FilePath $report -Encoding utf8
Write-Host "`n  Report saved: $report" -ForegroundColor Green

# debug log: what ran, how long each part took, and the errors that were hidden on screen
Close-SectionTime
$hidden = @($Error | Where-Object { $_.InvocationInfo.ScriptName -eq $PSCommandPath } | ForEach-Object { "line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message } | Select-Object -Unique -First 150)
@(
  "Laptop Checker v4 debug log - $(Get-Date -Format s)"
  "Model: $model | PowerShell $($PSVersionTable.PSVersion) $(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }) | Admin: $isAdmin | Native helpers: $($script:Native) | Language: $Lang"
  "Windows: $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version) | UI culture: $([Globalization.CultureInfo]::CurrentUICulture.Name)"
  "Options: $(($PSBoundParameters.Keys | ForEach-Object { "-$_" }) -join ' ')"
  ''
  '--- time per section'
  $script:SecLog
  ''
  "--- hidden errors ($($hidden.Count)) - most are normal (a part this laptop does not have)"
  $hidden
) | Out-File -FilePath ([IO.Path]::ChangeExtension($report, '.log')) -Encoding utf8
if (-not $NoOpen) { Start-Process $report }
if (-not $NoPrompt -and $Host.Name -eq 'ConsoleHost') { Read-Host "`n  Press Enter to close" | Out-Null }
