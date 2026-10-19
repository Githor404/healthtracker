# R239 -- RUN ONE GATE INSIDE A JOB THAT DIES WITH ITS LAUNCHER.
#
# REPORTED: a run stopped by the host's low-memory reaper left 1 gate script and
# 9 headless Chrome processes alive. The runner noticed its caller was gone and
# killed its bash jobs, but on Windows that does not reach the native PowerShell
# the job had started, nor the browser that PowerShell started. And the orphan
# sweep left that browser alone, rightly by its own rule: its PARENT (the gate
# script) was still alive.
#
# THE FIX IS A WINDOWS JOB OBJECT WITH KILL-ON-CLOSE. This launcher puts ITSELF in
# a new job before it starts the gate, so the gate and every process the gate
# starts -- its test server, its browser, the browser's children -- inherit the
# job. When this launcher exits for ANY reason (the gate finished, the leash timed
# out and killed it, the runner is gone, a reaper or Ctrl-C took it), its handle to
# the job closes and Windows kills everything still inside. No race: nothing is
# assigned after it has started; it is born in the job.
#
# It also WATCHES the runner and the runner's own caller (-Watch, Windows PIDs).
# The reaper kills the shell that started a run, not the run; the runner checks
# that only between gates. Watching here ends a gate within a second of either
# going away, instead of letting it run to its end on memory nobody wants.
#
# Usage (from run-all-gates.sh): powershell -File tests/gate-launch.ps1 -Gate <x-gate.ps1> -Watch "123,456"
param([Parameter(Mandatory = $true)][string]$Gate, [string]$Watch = '')
$ErrorActionPreference = 'Stop'

if (-not ('HtGateJob' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HtGateJob {
  [StructLayout(LayoutKind.Sequential)] struct BASIC { public long a; public long b; public uint LimitFlags; public UIntPtr c; public UIntPtr d; public uint e; public UIntPtr f; public uint g; public uint h; }
  [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a; public ulong b; public ulong c; public ulong d; public ulong e; public ulong f; }
  [StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC Basic; public IO Io; public UIntPtr p1; public UIntPtr p2; public UIntPtr p3; public UIntPtr p4; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr a, string n);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr j, int c, ref EXT i, uint l);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  static IntPtr job;
  public static string Enter() {
    job = CreateJobObject(IntPtr.Zero, null);
    if (job == IntPtr.Zero) return "CreateJobObject " + Marshal.GetLastWin32Error();
    EXT e = new EXT(); e.Basic.LimitFlags = 0x2000;   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if (!SetInformationJobObject(job, 9, ref e, (uint)Marshal.SizeOf(typeof(EXT)))) return "SetInformationJobObject " + Marshal.GetLastWin32Error();
    if (!AssignProcessToJobObject(job, GetCurrentProcess())) return "AssignProcessToJobObject " + Marshal.GetLastWin32Error();
    return "";
  }
}
'@
}
$err = [HtGateJob]::Enter()
if ($err) {
  # Said, never silent: without the job the gate still runs, but a stop can orphan it.
  Write-Host "  gate-launch: NO JOB ($err) -- this gate runs unguarded"
}

$watchPids = @()
foreach ($w in ($Watch -split ',')) { $n = 0; if ([int]::TryParse($w.Trim(), [ref]$n) -and $n -gt 0) { $watchPids += $n } }

$p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Gate) -NoNewWindow -PassThru
[void]$p.Handle                       # cache the handle, or ExitCode reads back empty
while (-not $p.HasExited) {
  foreach ($w in $watchPids) {
    if (-not (Get-Process -Id $w -ErrorAction SilentlyContinue)) {
      Write-Host ("  gate-launch: STOPPED -- pid {0} (the run, or what started it) is gone; the job takes the gate and its browser with it" -f $w)
      exit 3
    }
  }
  Start-Sleep -Milliseconds 700
}
$p.WaitForExit()
exit $p.ExitCode
