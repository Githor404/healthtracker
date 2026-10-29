# R239 -- A STOPPED RUN LEAVES NOTHING BEHIND. Re-runnable; run it whenever
# run-all-gates.sh, gate-launch.ps1 or reap-orphan-browsers.ps1 changes.
#
# NOT a *-gate.ps1, on purpose: the runner runs every *-gate.ps1, and this script
# starts a runner -- named like a gate, it would run itself.
#
# Three stops, each MID-GATE (after the gate's own browser is up), each followed by
# a count of what is left -- gate scripts, gate launchers, and headless browsers on
# a gate's temp profile (ht-*):
#   A. the RUNNER is killed outright (what a low-memory reaper or a crash does --
#      no trap runs);
#   B. the shell that STARTED the runner is killed (what this host's reaper did:
#      the runner itself survives and only notices between gates);
#   C. the start-of-run sweep: leftovers planted by killing a LAUNCHER's watcher
#      would be gone already, so a bare gate script is started by hand and left
#      running, and the next run must remove it and say so.
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bash = (Get-Command bash.exe -ErrorAction SilentlyContinue).Source
if (-not $bash) { Write-Host "ERROR: bash.exe not found"; exit 2 }
$fails = @()
function Check([bool]$ok, [string]$name) {
  if ($ok) { Write-Host ("  PASS  " + $name) } else { Write-Host ("  FAIL  " + $name); $script:fails += $name } }
function Leftovers([string]$tag) {
  @(Get-CimInstance Win32_Process | Where-Object {
      $cl = $_.CommandLine
      ($cl -and (($_.Name -in 'chrome.exe', 'msedge.exe' -and $cl -like '*--headless*' -and $cl -like ('*\' + $tag + '*')) -or
                 ($_.Name -eq 'powershell.exe' -and ($cl -like '*-gate.ps1*' -or $cl -like '*gate-launch.ps1*'))))
  })
}
function WaitFor([scriptblock]$cond, [int]$sec) {
  for ($i = 0; $i -lt ($sec * 4); $i++) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return $false
}
$gate = 'sensor-gate.ps1'; $tag = 'ht-sensor-'
if ((Leftovers $tag).Count -gt 0) { Write-Host "ERROR: gate processes are already running -- run this alone"; exit 2 }

function StartRun {
  # The runner in single-gate mode, started the way this host starts it: from a
  # bash -c wrapper, which is the process a low-memory reaper kills (case B).
  $env:ONLY_GATES = $gate
  $sh = ($repo -replace '\\', '/') + '/tests/run-all-gates.sh'
  $p = Start-Process -FilePath $bash -ArgumentList @('-c', ('"bash ' + $sh + ' > /tmp/ht-stopclean.log 2>&1"')) -WindowStyle Hidden -PassThru
  Remove-Item Env:\ONLY_GATES
  return $p
}
function RunnerUnder($wrapPid) {
  # the RUNNER, not the wrapper (-c) and not one of its own subshells, which carry
  # the same command line: the earliest-started non-wrapper bash running the file
  Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'bash.exe' -and $_.CommandLine -like '*run-all-gates.sh*' -and $_.CommandLine -notlike '* -c *' } |
    Sort-Object CreationDate | Select-Object -First 1
}

# ---- A. the runner killed outright, mid-gate ---------------------------------
$cmd = StartRun
$up = WaitFor { (Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like ('*\' + $tag + '*') }).Count -gt 0 } 90
Check $up "A: the gate's own browser came up under the runner (precondition)"
$run = RunnerUnder $cmd.Id
if ($run) { Stop-Process -Id $run.ProcessId -Force -ErrorAction SilentlyContinue }
$clean = WaitFor { (Leftovers $tag).Count -eq 0 } 20
$left = Leftovers $tag
Check $clean ("A: RUNNER KILLED mid-gate -> no gate script, launcher or gate browser remains (" + $left.Count + " left)")
try { Stop-Process -Id $cmd.Id -Force -ErrorAction SilentlyContinue } catch { }
$left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
[void](WaitFor { -not (Get-Process -Id $cmd.Id -ErrorAction SilentlyContinue) } 20)   # R283: was a fixed 3 s

# ---- B. the runner's CALLER killed, mid-gate ---------------------------------
$cmd = StartRun
$up = WaitFor { (Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like ('*\' + $tag + '*') }).Count -gt 0 } 90
Check $up "B: the gate's own browser came up under the runner (precondition)"
Stop-Process -Id $cmd.Id -Force -ErrorAction SilentlyContinue
$clean = WaitFor { (Leftovers $tag).Count -eq 0 } 20
$left = Leftovers $tag
Check $clean ("B: the runner's CALLER killed mid-gate (the reaper's shape) -> nothing remains (" + $left.Count + " left)")
$left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'bash.exe' -and $_.CommandLine -like '*run-all-gates.sh*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
[void](WaitFor { @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'bash.exe' -and $_.CommandLine -like '*run-all-gates.sh*' }).Count -eq 0 } 20)   # R283: was a fixed 3 s

# ---- C. the start-of-run sweep removes a leftover, and says so ---------------
$orphan = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repo ('tests\' + $gate))) -WindowStyle Hidden -PassThru
$up = WaitFor { (Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like ('*\' + $tag + '*') }).Count -gt 0 } 60
Check $up "C: a bare gate left running outside any run (planted leftover)"
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tests\reap-orphan-browsers.ps1') -Stale -SelfPid 0
$said = ($out -join ' ')
$clean = WaitFor { (Leftovers $tag).Count -eq 0 } 15
Check ($clean -and ($said -match 'leftover')) ("C: the START-OF-RUN sweep removed it and SAID so ('" + $said + "')")
(Leftovers $tag) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host ""
if ($fails.Count -eq 0) { Write-Host "STOP-CLEANUP CHECK: PASS -- a runner killed, its caller killed, or a leftover found at the start: no gate script and no gate browser survives"; Write-Host "GATE: PASS"; exit 0 }
Write-Host ("STOP-CLEANUP CHECK: FAIL -- " + $fails.Count + " check(s)"); Write-Host "GATE: FAIL"; exit 1
