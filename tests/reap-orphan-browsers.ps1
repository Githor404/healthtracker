# REAP ORPHANED GATE BROWSERS -- a killed suite leaves them holding their ports.
#
# WHY THIS EXISTS. A suite killed mid-run (this machine kills it for memory) leaves
# headless browsers alive. They keep their --remote-debugging-port, and the next run
# of that gate attaches CDP to the CORPSE instead of to its own browser. The probe
# then reports "HT is not defined", which reads exactly like the module-init defect
# this project hit on D158 -- a false result wearing the face of a code failure.
#
# Measured: overlay-gate failed that way with its port 9415 held by an orphan whose
# profile was `ht-overlay-...`.
#
# AND WHY THE PATTERN IS `ht-*`, NOT `ht-*gate-*`. The gates use 24 distinct profile
# prefixes and only EIGHT of them end in "gate" -- ht-overlay-, ht-chart-,
# ht-import-, ht-jargon-, ht-outcome-, ht-upd- and so on. Every sweep done with
# `ht-*gate-*` could therefore see at most a third of them, which is why orphans
# survived repeated cleanups and kept poisoning ports.
#
# THE CONDITIONS ARE NARROW ENOUGH TO BE PROVABLY SAFE. All three must hold:
#   1. the process is a HEADLESS chrome/msedge
#   2. its command line names a `ht-*` user-data-dir (every gate's own temp profile)
#   3. its PARENT PROCESS NO LONGER EXISTS
# Nothing a person could be using matches all three: a real browser is not
# headless, does not run from a ht-* temp profile, and has a living parent.
#
# This is a separate FILE rather than PowerShell inlined into the bash runner,
# because the first attempt was inlined and the nested quoting mangled it silently:
# the conditions were all true, nothing was killed, and `2>/dev/null || true` ate
# the error. A helper that cannot report its own failure is worse than none.
#
# R239 -- -Stale: THE START-OF-RUN SWEEP (and the runner's own stop). A gate whose
# run was stopped can keep its browser alive through a LIVING parent -- the gate
# script itself -- and the rule above, rightly, never touches that. Measured: one
# gate script and nine browsers survived a reaper stop. At the start of a run there
# is no gate that should already be running, so -Stale removes every gate script,
# gate launcher and headless ht-* browser, and SAYS so -- unless another runner,
# outside this run's own process tree, is alive, in which case it stands down and
# says that instead (-SelfPid is this runner's Windows PID).
param([switch]$Stale, [int]$SelfPid = 0)
$ErrorActionPreference = 'Stop'
$killed = @()
$skipped = 0

if ($Stale) {
  try { $all = @(Get-CimInstance Win32_Process -ErrorAction Stop) } catch { Write-Host "  reap: could not enumerate processes ($($_.Exception.Message))"; exit 0 }
  $byId = @{}; foreach ($q in $all) { $byId[[int]$q.ProcessId] = $q }
  $inMine = {
    param($proc)
    $seen = 0; $cur = $proc
    while ($cur -and $seen -lt 64) {
      if ($SelfPid -gt 0 -and [int]$cur.ProcessId -eq $SelfPid) { return $true }
      $cur = $byId[[int]$cur.ParentProcessId]; $seen++
    }
    return $false
  }
  # ...and not this run's own ANCESTORS either: the shell that launched it names
  # run-all-gates.sh on its command line too, and would read as "another run".
  $mineUp = @{}
  $cur = $byId[$SelfPid]; $seen = 0
  while ($cur -and $seen -lt 64) { $mineUp[[int]$cur.ProcessId] = 1; $cur = $byId[[int]$cur.ParentProcessId]; $seen++ }
  $others = @($all | Where-Object { $_.Name -eq 'bash.exe' -and $_.CommandLine -like '*run-all-gates.sh*' -and -not $mineUp.ContainsKey([int]$_.ProcessId) -and -not (& $inMine $_) })
  if ($others.Count -gt 0) {
    Write-Host ("  reap: another run is live (pid {0}) -- the start-of-run sweep stood down" -f (($others | ForEach-Object { $_.ProcessId }) -join ', '))
  } else {
    $gates = @($all | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -and ($_.CommandLine -like '*-gate.ps1*' -or $_.CommandLine -like '*gate-launch.ps1*') -and [int]$_.ProcessId -ne $PID })
    $browsers = @($all | Where-Object { $_.Name -in 'chrome.exe', 'msedge.exe' -and $_.CommandLine -like '*--headless*' -and $_.CommandLine -like '*\ht-*' })
    $said = @()
    foreach ($g in $gates) {
      $nm = if ($g.CommandLine -match '([a-z0-9-]+-gate\.ps1)') { $Matches[1] } else { 'gate-launch' }
      & taskkill.exe /T /F /PID $g.ProcessId 2>$null | Out-Null
      $said += ("$nm (pid $($g.ProcessId))")
    }
    $nb = 0
    foreach ($b in $browsers) {
      if (Get-Process -Id $b.ProcessId -ErrorAction SilentlyContinue) { try { Stop-Process -Id $b.ProcessId -Force -ErrorAction Stop; $nb++ } catch { } }
    }
    if ($said.Count -gt 0 -or $nb -gt 0) {
      Write-Host ("  reap: removed leftovers of a stopped run -- {0} gate script(s){1}, {2} gate browser process(es)" -f $said.Count, ($(if ($said.Count) { ': ' + ($said -join ', ') } else { '' })), $nb)
    }
  }
  exit 0
}

try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction Stop
} catch {
  Write-Host "  reap: could not enumerate processes ($($_.Exception.Message))"
  exit 0
}

foreach ($p in $procs) {
  $cl = $p.CommandLine
  if (-not $cl) { continue }
  if ($cl -notlike '*--headless*') { continue }
  if ($cl -notlike '*\ht-*') { continue }
  $parent = $null
  try { $parent = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $p.ParentProcessId) -ErrorAction SilentlyContinue } catch { }
  if ($parent) { $skipped++; continue }      # a LIVE run owns it; never touch that
  $tag = if ($cl -match 'ht-[a-z0-9-]+') { $Matches[0] } else { 'ht-?' }
  try {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
    $killed += ("$tag (pid $($p.ProcessId))")
  } catch {
    # ALREADY GONE IS SUCCESS, NOT A FAILURE. The enumeration above is a snapshot,
    # and a child browser process routinely exits between the snapshot and the
    # kill -- reporting that as "would not stop" is noise that trains the reader
    # to ignore this line, which is the one thing it must not do.
    if (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue) {
      Write-Host "  reap: pid $($p.ProcessId) ($tag) would NOT stop -- $($_.Exception.Message)"
    }
  }
}

if ($killed.Count -gt 0) {
  Write-Host ("  reaped {0} orphaned gate browser(s) from a previous killed run: {1}" -f $killed.Count, ($killed -join ', '))
}
if ($skipped -gt 0) {
  Write-Host ("  reap: left {0} gate browser(s) alone -- their parent run is still alive" -f $skipped)
}
exit 0
