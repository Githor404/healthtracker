# R198/5 -- COLD START WITH THE NETWORK OFF FROM THE FIRST REQUEST.
#
# WHAT THE OTHER TWO DO NOT ASK. offline-gate cuts the network and RELOADS a page
# in a browser that is already running; corpus-cache-gate does the same for the
# food database. Both leave the browser process, its memory cache and its live
# service worker in place. Neither answers the question a phone asks every
# morning: the app was closed, there is no signal, it is opened -- does it start?
#
# So this gate ENDS THE BROWSER and ENDS THE SERVER, and then launches again:
#   A. online, on the production (cache-first) path: the shell is precached, the
#      food database is on the device, and one item is logged
#   B. the browser is closed (asked to, not killed, so what it wrote is on disk)
#      and the test server is stopped. PRECONDITION, measured: the origin now
#      refuses a connection
#   C. a NEW browser process on the same profile, told it is offline BEFORE its
#      first navigation. Asserted on what is rendered:
#        - the app starts, at the same version, under the service worker
#        - the item logged before the close is on screen
#        - the food database is read from the device, with no request
#        - a search typed into the real Search pane finds rows, and a food can be
#          picked, given an amount and logged
#        - CONTROL: a file that is NOT part of the shell, which the server did
#          serve in A, cannot be fetched -- so "it started" is the cache
#          answering and not a network that was never really off
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8295
$Dbg = 9501
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-coldstart-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

function Find-Browser {
  foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null }
function Receive-One {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count); if ($res.EndOfMessage) { break } }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json) }
function Invoke-CDP([string]$m, [hashtable]$p) {
  $script:cid++; $pl = @{ id = $script:cid; method = $m }; if ($p) { $pl.params = $p }
  $b = [Text.Encoding]::UTF8.GetBytes(($pl | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($b), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $g = 0
  while ($true) { if (++$g -gt 3000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg } } }
# ---- R283: every wait is a wait ON A CONDITION (tests/lib/quiet.js) -------------------
# No fixed sleep stands for "long enough". The page counts its own async work in flight;
# WaitQuiet returns when none is and the DOM has been still for two frames, WaitBoot when
# the NEW page's app is up (the old page is marked first), WaitServer when the test
# server answers. Each fails the gate, by name, if its condition never holds.
$HT_QUIET_JS = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'lib\quiet.js'))
function WaitFail([string]$why) { Write-Host ("  FAIL  " + $why); Write-Host "GATE: FAIL"; try { Cleanup } catch { }; exit 1 }
function WaitQuiet([string]$why) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "(window.__htQuiet ? window.__htQuiet(10000).then(function () { return 'quiet'; }, function (e) { return String(e && e.message || e); }) : Promise.resolve('no quiet marker on this page'))"; awaitPromise = $true; returnByValue = $true }
  $v = $r.result.result.value
  if ($v -ne 'quiet') { WaitFail ("the page did not settle (" + $why + "): " + $v) }
  $ms = (Invoke-CDP 'Runtime.evaluate' @{ expression = 'window.__htQuietLastMs + " ms, waiting on: " + window.__htQuietWaitedOn'; returnByValue = $true }).result.result.value
  if ([double]($ms -replace ' ms.*', '') -gt 3000) { Write-Host ("  NOTE  settling took " + $ms + " (" + $why + ")") } }
function WaitServer([string]$url) {
  for ($sw = 0; $sw -lt 300; $sw++) { try { $null = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2; return } catch { Start-Sleep -Milliseconds 100 } }
  Write-Host "ERROR: test server did not start within 30 s"; try { Cleanup } catch { }; exit 2 }
function MarkOld { try { [void](Invoke-CDP 'Runtime.evaluate' @{ expression = 'window.__htOld = 1'; returnByValue = $true }) } catch { } }
function WaitLoaded {
  for ($bw = 0; $bw -lt 300; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "!window.__htOld && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { return }; Start-Sleep -Milliseconds 100 }
  WaitFail "the page did not load within 30 s" }
function WaitBoot {
  for ($bw = 0; $bw -lt 300; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "!window.__htOld && typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { WaitQuiet 'boot'; return }; Start-Sleep -Milliseconds 100 }
  WaitFail "the app did not boot within 30 s" }
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
# Multi-line JS goes over base64 so no quoting survives to be mangled; the result
# is stringified INSIDE the page (CDP: await the promise -- a JSON.stringify of an
# async eval returns "{}").
function EvalJ([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "JSON.stringify((function(){ return eval(decodeURIComponent(escape(atob('" + $enc + "')))); })())"; returnByValue = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }
# The async form, for anything that touches the corpus: AWAIT the promise and
# stringify INSIDE the page.
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }
# REAL TYPING, one character at a time into whatever holds the focus. Setting
# .value and calling the handler would prove the handler; it would not prove the
# field survives being typed in, which is the whole of the caret rule.
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    Start-Sleep -Milliseconds 70 } }
function Settle { WaitQuiet 'after a step' }   # R283: was a fixed 400 ms

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

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
    try { $ctx.Response.Close() } catch { } } }
function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { } }

$fails = @()
function Check([bool]$ok, [string]$name) {
  if ($ok) { Write-Host ("  PASS  " + $name) } else { Write-Host ("  FAIL  " + $name); $script:fails += $name } }

try {
  WaitServer "$origin/index.html"
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 400
    try { $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break } } catch { } }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1" } | Out-Null
  WaitBoot

  $boot = Eval "typeof HT === 'object' && typeof HT.corpusEnsure === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot"; Cleanup; exit 2 }

  # ---- A. online: the shell cached, the database stored, one item logged ----------
  $onl = EvalA @'
navigator.serviceWorker.ready.then(function () { return caches.keys(); }).then(function (keys) {
  var k = keys.filter(function (x) { return x.indexOf('healthtracker-shell-') === 0; })[0];
  var count = k ? caches.open(k).then(function (c) { return c.keys(); }).then(function (ks) { return ks.length; }) : Promise.resolve(0);
  return count.then(function (n) {
    return HT.corpusEnsure().then(function (r) {
      var res = HT.addManualEntry({ name: 'Cold start oats', meal: 'breakfast', time: '08:00', grams: 80, kcal: 300 });
      if (HT.resave) HT.resave();
      return fetch('./tests/seed-offline.html').then(function (x) { return x.status; }, function () { return -1; }).then(function (st) {
        return { shell: n, corpus: !!(r && r.ok), rows: HT.corpusState().rows, logged: !!(res && res.item),
                 version: HT.APP_VERSION, control: st };
      });
    });
  });
})
'@
  Write-Host ("  online, before the close: " + $onl)
  $onv = $onl | ConvertFrom-Json
  Check ($onv.shell -gt 3) "PRECONDITION: online, on the production path, the shell is in the service worker's cache"
  Check (($onv.corpus -eq $true) -and ($onv.rows -gt 1000)) "PRECONDITION: the food database is on the device"
  Check ($onv.logged -eq $true) "PRECONDITION: one item is logged"
  Check ($onv.control -eq 200) "PRECONDITION: a file outside the shell IS served while the server runs -- the control for step C"
  # One more load so the worker controls the page it will have to serve cold.
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
  WaitBoot

  # ---- B. close the browser, stop the server ---------------------------------------
  try { Invoke-CDP 'Browser.close' $null | Out-Null } catch { }
  try { $ws.Dispose() } catch { }
  $ws = $null
  $gone = $false
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $left = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" })
    if ($left.Count -eq 0) { $gone = $true; break } }
  Check $gone "the browser process has ENDED -- asked to close, so what it wrote is on disk; nothing of the first launch is left in memory"
  if (-not $gone) {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    # R283: wait for the forced stop to take, rather than a fixed 1.5 s
    for ($k = 0; $k -lt 300; $k++) { if (@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" }).Count -eq 0) { break }; Start-Sleep -Milliseconds 100 } }
  $chrome = $null
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  $dead = $false
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 400
    try { Invoke-WebRequest "$origin/index.html" -UseBasicParsing -TimeoutSec 3 | Out-Null } catch { $dead = $true; break } }
  Check $dead "PRECONDITION: THE SERVER IS STOPPED -- the origin refuses a connection, so from here nothing can come from the network"

  # ---- C. a new browser, offline before its first request --------------------------
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 400
    try { $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break } } catch { } }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up on the second launch"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Network.emulateNetworkConditions' @{ offline = $true; latency = 0; downloadThroughput = 0; uploadThroughput = 0 } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1" } | Out-Null
  WaitBoot

  $cold = EvalJ @'
(function () {
  var up = typeof HT === 'object' && !!HT.state;
  return { up: up, version: up ? HT.APP_VERSION : '', online: navigator.onLine,
           controlled: !!(navigator.serviceWorker && navigator.serviceWorker.controller),
           badge: ((document.getElementById('storeBadge') || {}).textContent || ''),
           shown: document.body.textContent.indexOf('Cold start oats') >= 0,
           memory: up ? HT.corpusState().ready : null };
})()
'@
  Write-Host ("  cold start, network off: " + $cold)
  if (($null -eq $cold) -or ($cold -like 'EXCEPTION*')) { $cold = '{}' }
  $cv = $cold | ConvertFrom-Json
  Check ($cv.online -eq $false) "PRECONDITION: the new browser is offline -- navigator.onLine is false"
  Check ($cv.up -eq $true) "THE APP STARTS, from nothing, with the network off from the first request"
  Check (($cv.version -eq $onv.version) -and ($cv.controlled -eq $true)) "at the same version, served by the service worker"
  Check ($cv.badge -match 'saved in this browser') "storage is the real one, and says so"
  Check ($cv.shown -eq $true) "the item logged before the close is ON SCREEN"

  if ($cv.up -eq $true) {
    $db = EvalA @'
HT.corpusEnsure().then(function (r) {
  var res = performance.getEntriesByType('resource').filter(function (e) { return e.name.indexOf('/corpus/dist/') >= 0 && ((e.transferSize || 0) > 0 || (e.decodedBodySize || 0) > 0); });
  return { ok: !!(r && r.ok), why: (r && r.why) || '', rows: HT.corpusState().rows, fetched: res.length };
})
'@
    Write-Host ("  the food database, cold: " + $db)
    $dv = $db | ConvertFrom-Json
    Check (($dv.ok -eq $true) -and ($dv.why -eq 'stored') -and ($dv.rows -eq $onv.rows) -and ($dv.fetched -eq 0)) "the food database is read FROM THE DEVICE, every row, with nothing fetched"

    [void](Eval "(function(){ HT.openSheet(); var bs = document.querySelectorAll('#sheetRoot .srbtn'); for (var i = 0; i < bs.length; i++) if (bs[i].textContent === 'Search') bs[i].click(); document.getElementById('fqQuery').focus(); return 1; })()")
    TypeText 'chedd'
    Settle
    $pick = EvalJ @'
(function () {
  var box = document.getElementById('fqRows');
  var n = box ? box.querySelectorAll('.fqrow').length : -1;
  var st = HT.foodSearch(), at = -1;
  (st.rows || []).forEach(function (r, i) { if (at < 0 && r.kcal > 0) at = i; });
  if (at < 0) return { rows: n, step: false };
  box.querySelectorAll('.fqrow')[at].click();
  var g = document.getElementById('fqGrams');
  if (g) g.focus();
  return { rows: n, step: !!g };
})()
'@
    Write-Host ("  a typed search, cold: " + $pick)
    $pv = $pick | ConvertFrom-Json
    Check (($pv.rows -gt 0) -and ($pv.step -eq $true)) "a search TYPED into the Search pane finds rows with their figures, and one can be picked"
    TypeText '40'
    Settle
    $done = EvalJ @'
(function () {
  var b = document.querySelector('#fqLog .fqlog');
  if (b && !b.disabled) b.click();
  var day = HT.state().days[HT.state().current] || { items: [] };
  var it = day.items[day.items.length - 1] || {};
  return { logged: it.source === 'corpus' && it.grams === 40 && it.kcal > 0 && !!it.ref };
})()
'@
    Write-Host ("  logged, cold: " + $done)
    Check (($done | ConvertFrom-Json).logged -eq $true) "and it is LOGGED, with its own numbers and its citation"

    $ctl = EvalA "fetch('./tests/seed-offline.html').then(function (x) { return { got: x.status }; }, function () { return { got: -1 }; })"
    Write-Host ("  control, a file outside the shell: " + $ctl)
    Check (($ctl | ConvertFrom-Json).got -ne 200) "CONTROL: a file that is not part of the shell, served in step A, CANNOT be fetched now -- so the start above is the cache answering, not a network that was never off"
  }

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("COLD START GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "COLD START GATE: PASS -- closed, the server stopped, and opened again with the"
Write-Host "  network off from the first request: the app starts, shows what was logged,"
Write-Host "  and search, pick and log all work."
Write-Host "GATE: PASS"
exit 0
