# R344 (a) -- EXPORT.ZIP READ AS IT IS, on the same tap as export.xml.
#
# The probe (R339.1) read the user's real export.zip in Safari and in the Home Screen
# app; this release makes that the import route for what the import reads today
# (glucose, steps), with a summary per source app. This gate drives it the way the
# phone does: files handed to the real file input with DOM.setFileInputFiles, nothing
# ingested from JavaScript.
#
# PRE-REGISTERED (DECISIONS, R344 release (a)):
#   1  the same glucose readings, values, units and moments, and the same steps days,
#      as the export.xml route on the same text -- store compared to store -- for a zip
#      deflated under a folder, one stored at the root, and a Zip64 one;
#   2  the same zip again adds nothing; the steps store is byte-identical;
#   3  the summary: each source with its counts and dates, the types not imported with
#      theirs, read as rendered at 390 px;
#   4  refused by name, stores unchanged: no export.xml, method 12, a truncated zip, a
#      page with DecompressionStream removed;
#   5  the budget (F13, measure amended by the user 2026-11-16): a 64 MB zip KEEPS under
#      64 MB of heap after a full collection (the peak printed beside a bare unzip's), and no stretch
#      of the import's own work over 200 ms between yields.
#
# FIXTURE-SYNTHETIC: tests/fixtures/make-ah-zip.py writes every file at run time
# (sources "Sample Apple Watch", "Sample iPhone", "Oura", "Dexcom G7"). The 64 MB zip
# is cached in TEMP by the script's hash, never committed.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8437
$Dbg = 9637
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-zip-" + [System.Guid]::NewGuid().ToString('N'))
$fixdir = Join-Path $env:TEMP ("ht-zipfix-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None
$fails = @()
function Chk([bool]$cond, [string]$msg) { if (-not $cond) { $script:fails += $msg } }

function Find-Browser {
  foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 262144
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count); if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$m, [hashtable]$p) {
  $script:cid++; $pl = @{ id = $script:cid; method = $m }; if ($p) { $pl.params = $p }
  $bv = [Text.Encoding]::UTF8.GetBytes(($pl | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bv), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $g = 0
  while ($true) {
    if (++$g -gt 6000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
# ---- R283: every wait is a wait ON A CONDITION (tests/lib/quiet.js) -------------------
$HT_QUIET_JS = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'lib\quiet.js'))
function WaitFail([string]$why) { Write-Host ("  FAIL  " + $why); Write-Host "GATE: FAIL"; try { Cleanup } catch { }; exit 1 }
function WaitQuiet([string]$why) {
  $qr = Invoke-CDP 'Runtime.evaluate' @{ expression = "(window.__htQuiet ? window.__htQuiet(10000).then(function () { return 'quiet'; }, function (e) { return String(e && e.message || e); }) : Promise.resolve('no quiet marker on this page'))"; awaitPromise = $true; returnByValue = $true }
  $v = $qr.result.result.value
  if ($v -ne 'quiet') { WaitFail ("the page did not settle (" + $why + "): " + $v) }
  $ms = (Invoke-CDP 'Runtime.evaluate' @{ expression = 'window.__htQuietLastMs + " ms, waiting on: " + window.__htQuietWaitedOn'; returnByValue = $true }).result.result.value
  if ([double]($ms -replace ' ms.*', '') -gt 3000) { Write-Host ("  NOTE  settling took " + $ms + " (" + $why + ")") } }
function WaitServer([string]$url) {
  for ($sw = 0; $sw -lt 300; $sw++) { try { $null = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2; return } catch { Start-Sleep -Milliseconds 100 } }
  Write-Host "ERROR: test server did not start within 30 s"; try { Cleanup } catch { }; exit 2 }
function MarkOld { try { [void](Invoke-CDP 'Runtime.evaluate' @{ expression = 'window.__htOld = 1'; returnByValue = $true }) } catch { } }
function WaitBoot {
  for ($bw = 0; $bw -lt 300; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "!window.__htOld && typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { WaitQuiet 'boot'; return }; Start-Sleep -Milliseconds 100 }
  WaitFail "the app did not boot within 30 s" }
function Eval([string]$e) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value
}
function Pick-File([string]$selector, [string]$path) {
  $doc = Invoke-CDP 'DOM.getDocument' @{ depth = 1 }
  $nid = (Invoke-CDP 'DOM.querySelector' @{ nodeId = $doc.result.root.nodeId; selector = $selector }).result.nodeId
  if (-not $nid) { throw "no node for $selector" }
  Invoke-CDP 'DOM.setFileInputFiles' @{ files = @($path); nodeId = $nid } | Out-Null
}
function Import-Seq { return [int](Eval "(function(){var p=HT.glucoseImportProgress();return p?p.seq:0;})()") }
# WAIT ON THIS IMPORT (its seq), NOT ON A CLOCK: a stale `done` would pass the
# re-import check while testing nothing.
function Wait-Import([int]$after, [int]$maxMs = 60000) {
  $t0 = [Environment]::TickCount
  while (([Environment]::TickCount - $t0) -lt $maxMs) {
    $p = (Eval "JSON.stringify(HT.glucoseImportProgress())") | ConvertFrom-Json
    if ($p -and ([int]$p.seq) -gt $after -and $p.done) { return $p }
    Start-Sleep -Milliseconds 120
  }
  return $null
}
$STORES = "JSON.stringify({g: localStorage.getItem('healthtracker-glucose') || '', s: localStorage.getItem('healthtracker-steps') || ''})"
function Stores { return (Eval $STORES) }
function ClearStores { [void](Eval "HT.glucoseClear(); HT.stepsWrite({}); localStorage.removeItem('healthtracker-steps'); 1") }
function Import([string]$path, [int]$maxMs = 60000) {
  $s0 = Import-Seq
  Pick-File '#gImport_settings' $path
  $p = Wait-Import $s0 $maxMs
  WaitQuiet 'after an import'
  return $p
}

# ---------------- the fixtures, written at run time ------------------------
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { Write-Host "ERROR: python not found (the fixtures are written by tests/fixtures/make-ah-zip.py)"; exit 2 }
$maker = Join-Path $PSScriptRoot 'fixtures\make-ah-zip.py'
New-Item -ItemType Directory -Path $fixdir -Force | Out-Null
& python -I $maker $fixdir | ForEach-Object { Write-Host ("  fixture " + $_) }
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: the fixture script failed"; exit 2 }
$F = @{}
foreach ($n in @('export.xml', 'deflate-folder.zip', 'stored-root.zip', 'zip64.zip', 'noexport.zip', 'method12.zip', 'truncated.zip')) {
  $F[$n] = Join-Path $fixdir $n
  if (-not (Test-Path $F[$n])) { Write-Host "ERROR: fixture $n was not written"; exit 2 }
}
# The 64 MB zip: cached by the script's own hash, so a changed script makes a new one.
$mh = (Get-FileHash -Algorithm SHA256 -LiteralPath $maker).Hash.Substring(0, 12)
$bigdir = Join-Path $env:TEMP ("ht-zipbig-" + $mh)
$BIG = Join-Path $bigdir 'big-64mb.zip'
if (-not (Test-Path $BIG)) {
  Get-ChildItem -Path $env:TEMP -Directory -Filter 'ht-zipbig-*' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $bigdir } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  $tb = [Environment]::TickCount
  & python -I $maker $bigdir --big 64 | ForEach-Object { Write-Host ("  fixture " + $_) }
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $BIG)) { Write-Host "ERROR: the 64 MB fixture was not written"; exit 2 }
  Write-Host ("  the 64 MB zip took {0:N1} s to write (cached for later runs)" -f (([Environment]::TickCount - $tb) / 1000))
}
$bigMB = [Math]::Round((Get-Item $BIG).Length / 1MB, 1)
Write-Host "  budget fixture: $bigMB MB zipped"

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome or Edge found"; exit 2 }
$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $portv)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$portv/"); $l.Start()
  $mimes = @{ '.html'='text/html'; '.js'='application/javascript'; '.json'='application/json';
              '.png'='image/png'; '.svg'='image/svg+xml'; '.css'='text/css'; '.bin'='application/octet-stream' }
  while ($l.IsListening) {
    try { $ctx = $l.GetContext() } catch { break }
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
      if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
      $full = Join-Path $repo $rel
      if (Test-Path $full -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        $ext = [System.IO.Path]::GetExtension($full).ToLower()
        if ($mimes.ContainsKey($ext)) { $ctx.Response.ContentType = $mimes[$ext] }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      } else { $ctx.Response.StatusCode = 404 }
    } catch { }
    try { $ctx.Response.Close() } catch { }
  }
}
function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  # R221/5: kill the server job's process, then remove the job.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
  try { if (Test-Path $fixdir) { Remove-Item $fixdir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  WaitServer "$origin/index.html"
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "--enable-precise-memory-info", "--js-flags=--expose-gc", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'DOM.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 745; deviceScaleFactor = 1; mobile = $true } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  [void](Eval "HT.setClock(function () { return Date.parse('2026-09-06T10:00:00-04:00'); }); HT.refresh(); 1")
  WaitQuiet 'clock set'

  # ========== 1. THE BASELINE: the same text by the export.xml route =========
  ClearStores
  $px = Import $F['export.xml']
  if ($null -eq $px) { WaitFail "the export.xml import never finished" }
  Chk ([string]::IsNullOrEmpty($px.error)) "the export.xml route refused the fixture: $($px.error)"
  Chk ($px.format -eq 'apple') "the export.xml fixture sniffed as '$($px.format)'"
  $base = Stores
  $baseObj = $base | ConvertFrom-Json
  Chk ($baseObj.g.Length -gt 100 -and $baseObj.s.Length -gt 50) "the export.xml route stored nothing to compare against (glucose $($baseObj.g.Length) chars, steps $($baseObj.s.Length))"
  $gcount = [int](Eval "HT.glucoseCount()")
  Write-Host "  baseline (export.xml): $gcount readings, added $($px.added)"
  Chk ($gcount -eq 864) "the export.xml route holds $gcount readings, expected the fixture's 864"
  $sumX = ($px.summary | ConvertTo-Json -Depth 8 -Compress)

  # ========== 1b. three zips, each the same as the baseline ===================
  $sumZ = $null
  foreach ($z in @('deflate-folder.zip', 'stored-root.zip', 'zip64.zip')) {
    ClearStores
    $pz = Import $F[$z]
    if ($null -eq $pz) { Chk $false "$z never finished importing"; continue }
    Write-Host ("  {0}: format {1}, added {2}, error '{3}', zip {4}" -f $z, $pz.format, $pz.added, $pz.error, $pz.zip)
    Chk ([string]::IsNullOrEmpty($pz.error)) "$z was refused: $($pz.error)"
    Chk ($pz.format -eq 'zip' -and $pz.zip) "$z was not read as a zip (format '$($pz.format)')"
    Chk ($pz.added -eq 864) "$z added $($pz.added) readings, expected 864"
    $now = Stores
    Chk ($now -eq $base) "$z left different stores from the export.xml route on the same text (glucose and steps compared as stored)"
    $sz = ($pz.summary | ConvertTo-Json -Depth 8 -Compress)
    Chk ($sz -eq $sumX) "$z's summary differs from the export.xml route's on the same text"
    if ($z -eq 'deflate-folder.zip') { $sumZ = $pz.summary }
  }

  # ========== 2. the same zip again adds nothing ==============================
  $before = Stores
  $pr = Import $F['deflate-folder.zip']
  Chk ($null -ne $pr) "the re-import never finished"
  if ($null -ne $pr) {
    Chk ($pr.added -eq 0) "importing the same zip again added $($pr.added) readings, expected 0"
    $g2 = @($pr.summary.sources | Where-Object { $_.name -eq 'Dexcom G7' })
    Chk ($g2.Count -eq 1 -and [int]$g2[0].glucose.held -eq 864 -and [int]$g2[0].glucose.added -eq 0) "the re-import's summary does not read '0 new, 864 already held' for Dexcom G7"
  }
  $after = Stores
  Chk ($after -eq $before) "the re-import changed a store (glucose or steps not byte-identical)"

  # ========== 3. the summary: counts, as computed and as rendered =============
  if ($sumZ) {
    $S = @{}; foreach ($x in $sumZ.sources) { $S[$x.name] = $x }
    Chk ($S.Count -eq 4) "the summary lists $($S.Count) sources, expected 4 (Dexcom G7, Oura, Sample Apple Watch, Sample iPhone)"
    $d = $S['Dexcom G7']
    Chk ($d -and [int]$d.glucose.n -eq 864 -and [int]$d.glucose.added -eq 864 -and $d.glucose.first -eq '2026-09-01' -and $d.glucose.last -eq '2026-09-03') "Dexcom G7's glucose summary is wrong: $($d | ConvertTo-Json -Compress -Depth 5)"
    $w = $S['Sample Apple Watch']; $o = $S['Oura']; $ph = $S['Sample iPhone']
    Chk ($w -and [int]$w.steps.days -eq 2 -and [int]$w.steps.kept -eq 2) "the Watch's steps summary is wrong (expected 2 days, 2 kept): $($w | ConvertTo-Json -Compress -Depth 5)"
    Chk ($o -and [int]$o.steps.days -eq 4 -and [int]$o.steps.kept -eq 1) "Oura's steps summary is wrong (expected 4 days, 1 kept): $($o | ConvertTo-Json -Compress -Depth 5)"
    Chk ($ph -and [int]$ph.steps.days -eq 4 -and [int]$ph.steps.kept -eq 0 -and $ph.steps.last -eq '2026-09-05') "the iPhone's steps summary is wrong (expected 4 days to 5 Sep, 0 kept): $($ph | ConvertTo-Json -Compress -Depth 5)"
    $Types = @{}; foreach ($x in $sumZ.other) { $Types[$x.words] = $x }
    $want = @{ 'Heart rate' = @(700, 2); 'Active energy' = @(300, 1); 'Sleep' = @(40, 1); 'Respiratory rate' = @(30, 1); 'HRV (SDNN)' = @(20, 1) }
    Chk ($Types.Count -eq 5) "the summary lists $($Types.Count) types not imported, expected 5: $(@($sumZ.other | ForEach-Object { $_.words }) -join ', ')"
    foreach ($k in $want.Keys) {
      $tt = $Types[$k]
      Chk ($tt -and [int]$tt.total -eq $want[$k][0] -and @($tt.bySrc).Count -eq $want[$k][1]) "type '$k' counted wrong: expected $($want[$k][0]) records from $($want[$k][1]) source(s), got $($tt | ConvertTo-Json -Compress -Depth 5)"
    }
    Chk (-not $Types.ContainsKey('Blood Glucose') -and -not $Types.ContainsKey('Step Count')) "glucose or steps are listed as not imported"
  } else { Chk $false "no summary from the deflate-folder zip" }

  # As rendered, in Settings, at 390 px: the one line, then opened.
  [void](Eval "(function(){ HT.openSettings(); var c = document.querySelector('[data-setting=glucose-import]'); c && c.scrollIntoView(); return 1; })()")
  WaitQuiet 'settings shown'
  $line = Eval "(function(){ var s = document.querySelector('[data-setting=glucose-import] .gsum summary'); return s ? s.textContent : ''; })()"
  Write-Host "  summary line: $line"
  Chk ($line -match '^4 sources read') "the summary's one line reads '$line', expected it to begin '4 sources read'"
  [void](Eval "(function(){ var d = document.querySelector('[data-setting=glucose-import] .gsum'); if (d) { d.open = true; d.dispatchEvent(new Event('toggle')); } return 1; })()")
  WaitQuiet 'summary opened'
  $txt = Eval "(function(){ var d = document.querySelector('[data-setting=glucose-import] .gsum'); return d ? d.textContent.replace(/\s+/g, ' ') : ''; })()"
  Write-Host "  summary opened: $txt"
  foreach ($must in @('Dexcom G7', 'Glucose: 864 readings', 'Sample Apple Watch', 'Steps: 2 days in the file', 'Not imported in this version', 'Heart rate', 'HRV (SDNN)', 'Nothing of theirs was stored')) {
    Chk ($txt.Contains($must)) "the opened summary does not show '$must'"
  }
  $ov = [int](Eval "document.documentElement.scrollWidth")
  Chk ($ov -le 390) "the page scrolls sideways with the summary open (scrollWidth $ov)"
  $shotDir = $env:HT_SHOT_DIR
  if ($shotDir) {
    [void](Eval "(function(){ var d = document.querySelector('[data-setting=glucose-import]'); d && d.scrollIntoView(); return 1; })()")
    $shot = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png' }
    [IO.File]::WriteAllBytes((Join-Path $shotDir 'zip-summary-390.png'), [Convert]::FromBase64String($shot.result.data))
    Write-Host "  screenshot written to $shotDir"
  }

  # ========== 4. refusals by name, stores unchanged ===========================
  $held = Stores
  $refuse = @(
    @('noexport.zip', 'no export\.xml in it'),
    @('method12.zip', 'method 12'),
    @('truncated.zip', 'not a complete zip')
  )
  foreach ($r in $refuse) {
    $pf = Import $F[$r[0]]
    if ($null -eq $pf) { Chk $false "$($r[0]) never finished"; continue }
    Write-Host ("  {0}: {1}" -f $r[0], $pf.error)
    Chk ($pf.error -match $r[1]) "$($r[0]) was not refused by name (expected /$($r[1])/): '$($pf.error)'"
    Chk ($pf.error -match 'nothing was changed') "$($r[0])'s refusal does not say nothing was changed: '$($pf.error)'"
    Chk ((Stores) -eq $held) "$($r[0]) changed a store"
  }
  [void](Eval "window.DecompressionStream = undefined; 1")
  $pd = Import $F['deflate-folder.zip']
  if ($null -eq $pd) { Chk $false "the import with DecompressionStream removed never finished" }
  else {
    Write-Host ("  no DecompressionStream: " + $pd.error)
    Chk ($pd.error -match 'cannot unzip it' -and $pd.error -match 'Unzip it in Files') "with DecompressionStream removed the zip was not refused with the unzip route named: '$($pd.error)'"
    Chk ((Stores) -eq $held) "the refused import (no DecompressionStream) changed a store"
  }
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  WaitBoot
  [void](Eval "HT.setClock(function () { return Date.parse('2026-09-06T10:00:00-04:00'); }); HT.refresh(); 1")
  WaitQuiet 'reloaded'

  # ========== 5. the budget (F13) =============================================
  ClearStores
  [void](Eval "(window.gc && window.gc(), 1)")
  $heap0 = [double](Eval "performance.memory ? performance.memory.usedJSHeapSize : 0")
  $tb = [Environment]::TickCount
  $pb = Import $BIG 300000
  $secs = ([Environment]::TickCount - $tb) / 1000
  [void](Eval "(window.gc && window.gc(), 1)")
  $heapGc = [double](Eval "performance.memory ? performance.memory.usedJSHeapSize : 0")
  Write-Host ("  after the import and a full collection the heap holds {0:N1} MB (what the import kept, garbage excluded)" -f ($heapGc / 1MB))
  # THE MEASURE, AS RULED (R344, F13 amended 2026-11-16): what the import KEEPS -- the
  # heap after a full collection, against before. The peak is printed, not judged: the
  # browser's own unzip-and-decode, with no app code, peaked at 172-242 MB of garbage
  # not yet collected on this zip (measured), so a peak budget measured the browser.
  # The bare pipeline is drained here, in the same page, so the two peaks sit side by side.
  $drainJs = @'
(async function () {
  const f = document.getElementById('ztmp').files[0];
  const tail = Math.min(f.size, 65557), dv = new DataView(await f.slice(f.size - tail).arrayBuffer());
  let at = -1; for (let i = tail - 22; i >= 0; i--) if (dv.getUint32(i, true) === 0x06054b50) { at = i; break; }
  const cdOff = dv.getUint32(at + 16, true), cdSize = dv.getUint32(at + 12, true);
  const cd = new DataView(await f.slice(cdOff, cdOff + cdSize).arrayBuffer());
  let p = 0, e = null;
  while (p + 46 <= cd.byteLength) { const nl = cd.getUint16(p + 28, true); e = { comp: cd.getUint32(p + 20, true), loc: cd.getUint32(p + 42, true) }; p += 46 + nl + cd.getUint16(p + 30, true) + cd.getUint16(p + 32, true); }
  const lh = new DataView(await f.slice(e.loc, e.loc + 30).arrayBuffer());
  const s0 = e.loc + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
  const rd = f.slice(s0, s0 + e.comp).stream().pipeThrough(new DecompressionStream('deflate-raw')).pipeThrough(new TextDecoderStream()).getReader();
  if (window.gc) gc();
  const h0 = performance.memory.usedJSHeapSize; let peak = h0, last = performance.now();
  for (;;) { const r = await rd.read(); if (r.done) break; const now = performance.now(); if (now - last > 50) { peak = Math.max(peak, performance.memory.usedJSHeapSize); await new Promise(function (res) { setTimeout(res, 0); }); last = performance.now(); } }
  return JSON.stringify({ h0: h0, peak: peak });
})()
'@
  [void](Eval "(function(){ var i = document.createElement('input'); i.type = 'file'; i.id = 'ztmp'; i.style.display = 'none'; document.body.appendChild(i); return 1; })()")
  Pick-File '#ztmp' $BIG
  $dr = (Invoke-CDP 'Runtime.evaluate' @{ expression = $drainJs; awaitPromise = $true; returnByValue = $true }).result.result.value
  [void](Eval "(function(){ var i = document.getElementById('ztmp'); i && i.remove(); window.gc && gc(); return 1; })()")
  $bare = if ($dr) { $dr | ConvertFrom-Json } else { $null }
  $barePeakMB = if ($bare) { [Math]::Round(([double]$bare.peak - [double]$bare.h0) / 1MB, 1) } else { -1 }
  if ($null -eq $pb) { Chk $false "the $bigMB MB zip never finished importing within 300 s" }
  else {
    $peakMB = [Math]::Round(([double]$pb.heapPeak - $heap0) / 1MB, 1)
    $keptMB = [Math]::Round(($heapGc - $heap0) / 1MB, 1)
    Write-Host ("  budget: {0} MB zipped in {1:N1} s; KEPT {2} MB after a full collection (ruled under 64); peak +{3} MB, not judged (the bare unzip-and-decode in this page: +{4} MB); longest stretch without yielding {5} ms; readings {6}; error '{7}'" -f $bigMB, $secs, $keptMB, $peakMB, $barePeakMB, $pb.maxGapMs, $pb.readings, $pb.error)
    Chk ([string]::IsNullOrEmpty($pb.error)) "the $bigMB MB zip was refused: $($pb.error)"
    Chk ($bigMB -ge 64) "the budget fixture is $bigMB MB, under the ruled 64 MB"
    Chk ($heap0 -gt 0 -and $heapGc -gt 0 -and [double]$pb.heapPeak -gt 0) "no heap figure (performance.memory is missing), so the budget is not measured"
    Chk ($keptMB -lt 64) "the import kept $keptMB MB of heap after a full collection on the $bigMB MB zip, over the ruled 64 MB"
    Chk ([int]$pb.maxGapMs -gt 0 -and [int]$pb.maxGapMs -lt 200) "the import's longest stretch without giving the page back was $($pb.maxGapMs) ms (ruled under 200 ms; 0 means not measured)"
  }

  if ($fails.Count) {
    Write-Host "ZIP GATE: FAIL"
    foreach ($fl in $fails) { Write-Host "  - $fl" }
    Cleanup
    exit 1
  }
  Write-Host "ZIP GATE: PASS -- export.zip read through the real file input, deflated under a folder, stored at the root and Zip64, each leaving the same glucose and steps stores as the export.xml route on the same text and the same summary; the same zip again added nothing; the summary counts each of four sources and five types not imported, and renders at 390 px; a zip with no export.xml, method 12, a truncated zip and a page without DecompressionStream are each refused by name with the stores unchanged; the $bigMB MB zip kept under 64 MB of heap after a full collection (the ruled measure) and never held the page longer than 200 ms."
  Write-Host "  WHAT THIS GATE CANNOT SEE: the fixture is synthetic, and this is Chrome on a PC. The user's real export.zip on the phone (Safari, then the Home Screen app) is the check that counts; the probe read it there in 2.3 s."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
