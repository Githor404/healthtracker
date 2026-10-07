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
$ErrorActionPreference = 'Stop'
$killed = @()
$skipped = 0

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
