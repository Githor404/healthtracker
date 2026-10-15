# R197 -- THE FOOD DATABASE IS READ FROM THE DEVICE, AND FETCHED ONLY ON CHANGE.
#
# MEASURED BEFORE THIS GATE EXISTED, on the shipped v0.89.0:
#   first launch                     2 requests (the index and the values)
#   second launch                    the same 2 again
#   third launch, those URLs blocked ready: false, 0 rows, "coffee" finds nothing
# -- with all 7,793 rows in the device's own IndexedDB. Nothing loaded the stored
# corpus at startup, so every launch fell through to a download, and offline
# there was nothing to download. The store's own header comment said the index
# was "hydrated to RAM at boot". It never was.
#
# NO GATE SAW IT. corpus-gate installs with corpusAcquire(true) and reads back in
# the same page; offline-gate asserts the SHELL offline. Neither launches a
# SECOND time and asks whether the database is still there. That is this gate:
# it reloads the page, and the reload is the point.
#
# PRE-REGISTERED (R197 item 1): "cache it locally (offline search must work;
# version-check, download only on change). Gate: search works with network off."
#   1. first launch downloads the corpus -- once
#   2. second launch makes NO corpus request and is ready from the device
#   3. with the corpus URLs blocked, a real typed search finds rows
#   4. with the NETWORK OFF entirely, a search still finds rows and a food can be
#      picked, given an amount and logged
#   5. CONTROL: when the build expects a different corpus, it DOES download --
#      so "no request" above is a decision and not a fetch that never fires
#   6. a changed corpus that cannot be fetched leaves the stored one working,
#      and says it is stale
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8273
$Dbg = 9471
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-corpuscache-" + [System.Guid]::NewGuid().ToString('N'))
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
function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); $l.Start()
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
  Start-Sleep -Milliseconds 600
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
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $boot = Eval "typeof HT === 'object' && typeof HT.corpusIsCurrent === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or corpusIsCurrent is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Network.enable' $null | Out-Null

  $probe = @'
(function () {
  var before = HT.corpusState().ready;
  return HT.corpusEnsure().then(function (r) {
    var res = performance.getEntriesByType('resource').filter(function (e) { return e.name.indexOf('/corpus/dist/') >= 0; });
    var st = HT.corpusState();
    return { readyBefore: before, ok: !!(r && r.ok), why: (r && r.why) || '', stale: !!(r && r.stale), ready: st.ready, rows: st.rows, ns: st.ns,
             requests: res.length, names: res.map(function (e) { return e.name.split('/').pop(); }).sort().join(','),
             search: HT.matchTypeahead('coffee', 8).length };
  });
})()
'@
  # ---- 1. the first launch downloads, once --------------------------------------
  $a = EvalA $probe
  Write-Host ("  first launch : " + $a)
  $av = $a | ConvertFrom-Json
  Check (($av.ok -eq $true) -and ($av.ready -eq $true) -and ($av.rows -gt 1000)) "the first launch acquires the food database"
  Check (($av.requests -eq 2) -and ($av.names -eq ($av.ns + '.bin,' + $av.ns + '.json'))) "by exactly two requests -- its index and its values"

  # ---- 2. the second launch does not --------------------------------------------
  Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
  Start-Sleep -Milliseconds 3000
  $b = EvalA $probe
  Write-Host ("  second launch: " + $b)
  $bv = $b | ConvertFrom-Json
  Check ($bv.readyBefore -eq $false) "PRECONDITION: on a new launch nothing is in memory yet -- so what follows is read from the device or fetched, and the request count says which"
  Check ($bv.requests -eq 0) "THE SECOND LAUNCH MAKES NO REQUEST FOR THE DATABASE. Before this fix it made the same two again, on every launch"
  Check (($bv.ok -eq $true) -and ($bv.why -eq 'stored') -and ($bv.rows -eq $av.rows)) "it is ready FROM THE DEVICE, with every row it had"
  Check ($bv.search -gt 0) "and a search finds rows"

  # ---- 3. the corpus URLs blocked: a real typed search ---------------------------
  Invoke-CDP 'Network.setBlockedURLs' @{ urls = @('*corpus/dist*') } | Out-Null
  Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
  Start-Sleep -Milliseconds 3000
  [void](Eval "(function(){ HT.openSheet(); var bs = document.querySelectorAll('#sheetRoot .srbtn'); for (var i = 0; i < bs.length; i++) if (bs[i].textContent === 'Search') bs[i].click(); document.getElementById('fqQuery').focus(); return 1; })()")
  TypeText 'coffee'
  Settle
  $c = EvalJ @'
(function () {
  var box = document.getElementById('fqRows');
  var res = performance.getEntriesByType('resource').filter(function (e) { return e.name.indexOf('/corpus/dist/') >= 0; });
  return { rows: box ? box.querySelectorAll('.fqrow').length : -1, note: box ? ((box.querySelector('.fqnote') || {}).textContent || '') : '',
           fetched: res.filter(function (e) { return (e.transferSize || 0) > 0 || (e.decodedBodySize || 0) > 0; }).length, ready: HT.corpusState().ready };
})()
'@
  Write-Host ("  database URLs blocked: " + $c)
  $cv = $c | ConvertFrom-Json
  Check (($cv.rows -gt 0) -and ($cv.ready -eq $true)) "with the database's URLs BLOCKED, a search typed into the real Search pane finds rows. Before this fix: 'not on this device yet', with the database on the device"
  Check ($cv.note -eq '') "and the pane does not claim the database is missing"
  Check ($cv.fetched -eq 0) "nothing was fetched for it"

  # ---- 4. the network off entirely: search, pick, amount, log --------------------
  Invoke-CDP 'Network.emulateNetworkConditions' @{ offline = $true; latency = 0; downloadThroughput = 0; uploadThroughput = 0 } | Out-Null
  $off = EvalJ "navigator.onLine"
  [void](Eval "(function(){ var f = document.getElementById('fqQuery'); f.value = ''; f.focus(); return 1; })()")
  TypeText 'chedd'
  Settle
  $d = EvalJ @'
(function () {
  var box = document.getElementById('fqRows');
  var n = box ? box.querySelectorAll('.fqrow').length : -1;
  var day0 = (HT.state().days[HT.state().current] || { items: [] }).items.length;
  var st = HT.foodSearch(), at = -1;
  (st.rows || []).forEach(function (r, i) { if (at < 0 && r.kcal > 0) at = i; });
  if (at < 0) return { rows: n, err: 'no row with numbers' };
  box.querySelectorAll('.fqrow')[at].click();
  var g = document.getElementById('fqGrams');
  if (g) g.focus();
  return { rows: n, step: !!g, macros: st.rows[at].kcal, day0: day0 };
})()
'@
  Write-Host ("  network off (navigator.onLine = " + $off + "): " + $d)
  Check ($off -eq 'false') "PRECONDITION: the network is OFF -- navigator.onLine is false"
  Check (($d -like '*"step":true*') -and (-not ($d -like '*"rows":0*')) -and (-not ($d -like '*"rows":-1*'))) "WITH THE NETWORK OFF a new search finds rows, WITH their figures -- which are read from the device's own database, row by row -- and a row can be picked"
  TypeText '40'
  Settle
  $e = EvalJ @'
(function () {
  var b = document.querySelector('#fqLog .fqlog');
  var label = b ? b.textContent : '', enabled = !!b && !b.disabled;
  if (b) b.click();
  var day = HT.state().days[HT.state().current] || { items: [] };
  var it = day.items[day.items.length - 1] || {};
  return { enabled: enabled, label: label, logged: it.source === 'corpus' && it.grams === 40 && it.kcal > 0 && !!it.ref, n: day.items.length };
})()
'@
  Write-Host ("  network off, logged: " + $e)
  Check (($e -like '*"enabled":true*') -and ($e -like '*"label":"Log *')) "the amount step computes the calories offline"
  Check ($e -like '*"logged":true*') "and the food is LOGGED offline, with its own numbers and its citation -- OFFLINE SEARCH WORKS, end to end"
  Invoke-CDP 'Network.emulateNetworkConditions' @{ offline = $false; latency = 0; downloadThroughput = -1; uploadThroughput = -1 } | Out-Null

  # ---- 6. a CHANGED corpus that cannot be fetched: the stored one still works -----
  # The URLs are still blocked. The build is told to expect a different corpus.
  $f = EvalA @'
(function () {
  var ns = HT.corpusState().ns, real = HT.CORPUS_ASSET_HASH[ns];
  window.__realHash = real;
  HT.CORPUS_ASSET_HASH[ns] = 'ffffffffffff';
  var current = HT.corpusIsCurrent(HT.corpusMem());
  return HT.corpusEnsure().then(function (r) {
    return { current: current, ok: !!(r && r.ok), why: (r && r.why) || '', stale: !!(r && r.stale),
             ready: HT.corpusState().ready, search: HT.matchTypeahead('coffee', 8).length };
  });
})()
'@
  Write-Host ("  a changed corpus, unreachable: " + $f)
  $fv = $f | ConvertFrom-Json
  Check ($fv.current -eq $false) "when the build expects a different corpus, the stored one is NOT current -- the version check is two strings already on the device, and needs no request"
  Check (($fv.ok -eq $true) -and ($fv.stale -eq $true) -and ($fv.why -eq 'stored-stale')) "it cannot be fetched, so the stored one is KEPT and SAID to be stale -- a search on last month's table beats a search that finds nothing"
  Check (($fv.ready -eq $true) -and ($fv.search -gt 0)) "and search still works"

  # ---- 5. CONTROL: on a change, with the network back, it DOES download ----------
  Invoke-CDP 'Network.setBlockedURLs' @{ urls = @() } | Out-Null
  $g = EvalA @'
(function () {
  var n0 = performance.getEntriesByType('resource').filter(function (e) { return e.name.indexOf('/corpus/dist/') >= 0 && (e.decodedBodySize || 0) > 0; }).length;
  return HT.corpusEnsure().then(function (r) {
    var n1 = performance.getEntriesByType('resource').filter(function (e) { return e.name.indexOf('/corpus/dist/') >= 0 && (e.decodedBodySize || 0) > 0; }).length;
    var ns = HT.corpusState().ns;
    HT.CORPUS_ASSET_HASH[ns] = window.__realHash;
    var back = HT.corpusIsCurrent(HT.corpusMem());
    return HT.corpusEnsure().then(function (r2) {
      var n2 = performance.getEntriesByType('resource').filter(function (e) { return e.name.indexOf('/corpus/dist/') >= 0 && (e.decodedBodySize || 0) > 0; }).length;
      return { downloaded: n1 - n0, ok: !!(r && r.ok), restored: back, why2: (r2 && r2.why) || '', extra: n2 - n1 };
    });
  });
})()
'@
  Write-Host ("  control, a changed corpus, reachable: " + $g)
  $gv = $g | ConvertFrom-Json
  Check ($gv.downloaded -eq 2) "CONTROL: with the network back and a different corpus expected, it DOWNLOADS -- two requests. So the zero above is a decision made by the version check, not a fetch that never fires"
  Check (($gv.restored -eq $true) -and ($gv.why2 -eq 'ready') -and ($gv.extra -eq 0)) "and once the expected version is the stored one again, it is current and nothing more is fetched (the plant is put back)"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("CORPUS CACHE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "CORPUS CACHE GATE: PASS -- the food database is downloaded once, read from the"
Write-Host "  device on every later launch, fetched again only when the build expects a"
Write-Host "  different one, and search, pick and log all work with the network off."
Write-Host "GATE: PASS"
exit 0
