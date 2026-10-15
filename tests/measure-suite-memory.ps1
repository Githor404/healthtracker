# R221/5 -- WHAT THE SUITE HOLDS IN MEMORY, AND WHICH GATE HOLDS IT.
#
# The full sweep has been stopped by the host for low memory three releases
# running. Before anything is changed, this measures. It samples every
# $IntervalMs until the stop file appears (or $MaxMinutes pass) and writes one
# CSV row per sample:
#
#   t, freeMB, suiteMB, browserMB, psMB, nBrowser, nPs, gate
#
#   freeMB    -- the machine's free physical memory (what the host's reaper reads)
#   suiteMB   -- private bytes of every process the SUITE owns: each headless
#                browser and all its children, each gate's PowerShell and the
#                Start-Job PowerShell it spawns for its HTTP server
#   gate      -- the gate running at that moment, read off its command line
#
# THE SUITE'S PROCESSES ARE FOUND BY THEIR ROOTS, not by name: a headless
# browser (its command line says --headless), a gate (-File ...-gate.ps1) or
# the harness runner -- and then every descendant by ParentProcessId. The user's
# own Chrome is never --headless, so it is never counted as the suite's.
#
# Usage (beside a run):
#   powershell -File tests/measure-suite-memory.ps1 -Out <csv> -Stop <stopfile>
# Then: powershell -File tests/measure-suite-memory.ps1 -Summarize <csv>
param(
  [string]$Out = '',
  [string]$Stop = '',
  [int]$IntervalMs = 2000,
  [int]$MaxMinutes = 240,
  [string]$Summarize = ''
)
$ErrorActionPreference = 'Stop'

if ($Summarize) {
  $rows = Import-Csv $Summarize
  if (-not $rows) { Write-Host "no samples"; exit 2 }
  $peak = ($rows | ForEach-Object { [double]$_.suiteMB } | Measure-Object -Maximum).Maximum
  $minFree = ($rows | ForEach-Object { [double]$_.freeMB } | Measure-Object -Minimum).Minimum
  $maxBr = ($rows | ForEach-Object { [int]$_.nBrowser } | Measure-Object -Maximum).Maximum
  Write-Host ("samples: {0}   peak suite: {1} MB   lowest free: {2} MB   most browser processes at once: {3}" -f $rows.Count, [int]$peak, [int]$minFree, $maxBr)
  Write-Host "per gate (peak suite MB, lowest free MB, samples):"
  $rows | Group-Object gate | ForEach-Object {
    $p = ($_.Group | ForEach-Object { [double]$_.suiteMB } | Measure-Object -Maximum).Maximum
    $f = ($_.Group | ForEach-Object { [double]$_.freeMB } | Measure-Object -Minimum).Minimum
    [pscustomobject]@{ gate = $_.Name; peakMB = [int]$p; lowFreeMB = [int]$f; n = $_.Count }
  } | Sort-Object peakMB -Descending | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
  exit 0
}

if (-not $Out) { Write-Host "ERROR: -Out <csv> is required"; exit 2 }
"t,freeMB,suiteMB,browserMB,psMB,nBrowser,nPs,gate" | Set-Content -Path $Out -Encoding ascii
$t0 = Get-Date
while ($true) {
  if ($Stop -and (Test-Path $Stop)) { break }
  if (((Get-Date) - $t0).TotalMinutes -gt $MaxMinutes) { break }
  try {
    $procs = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine, PrivatePageCount)
    $kids = @{}
    foreach ($p in $procs) { $k = [int]$p.ParentProcessId; if (-not $kids.ContainsKey($k)) { $kids[$k] = New-Object System.Collections.ArrayList }; [void]$kids[$k].Add($p) }
    # A gate root is the POWERSHELL that runs it -- a shell whose own command line
    # merely mentions a gate (a loop that launches them) is not the suite's, and
    # counting it would count everything under it, this sampler included.
    $roots = @($procs | Where-Object {
      $cl = [string]$_.CommandLine; $nm = [string]$_.Name
      ($_.ProcessId -ne $PID) -and (
        (($nm -match '^(chrome|msedge)\.exe$') -and ($cl -match '--headless')) -or
        (($nm -match '^(powershell|pwsh)\.exe$') -and ($cl -match '-File\s+\S*-gate\.ps1')) -or
        (($nm -match '^bash\.exe$') -and ($cl -match 'run-data-layer\.sh"?\s*$'))) })
    $seen = @{}
    $stack = New-Object System.Collections.Stack
    foreach ($r in $roots) { $stack.Push($r) }
    while ($stack.Count) {
      $p = $stack.Pop(); $id = [int]$p.ProcessId
      if ($seen.ContainsKey($id) -or $id -eq $PID) { continue }
      $seen[$id] = $p
      if ($kids.ContainsKey($id)) { foreach ($c in $kids[$id]) { $stack.Push($c) } }
    }
    $br = 0.0; $ps = 0.0; $nb = 0; $np = 0; $gate = ''
    foreach ($p in $seen.Values) {
      $mb = [double]$p.PrivatePageCount / 1MB
      if ($p.Name -match '^(chrome|msedge)\.exe$') { $br += $mb; $nb++ }
      elseif ($p.Name -match '^(powershell|pwsh)\.exe$') { $ps += $mb; $np++ }
      $m = [regex]::Match([string]$p.CommandLine, '([a-z0-9-]+-gate)\.ps1')
      if ($m.Success) { $gate = $m.Groups[1].Value }
      elseif (-not $gate -and ([string]$p.CommandLine -match 'run-data-layer')) { $gate = 'harness' }
    }
    $free = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
    $line = "{0},{1},{2},{3},{4},{5},{6},{7}" -f [int]((Get-Date) - $t0).TotalSeconds, $free, [int]($br + $ps), [int]$br, [int]$ps, $nb, $np, $gate
    Add-Content -Path $Out -Value $line -Encoding ascii
  } catch { }
  Start-Sleep -Milliseconds $IntervalMs
}
exit 0
