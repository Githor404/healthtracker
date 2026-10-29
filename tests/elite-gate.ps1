# E-LITE -- glucose rises with no food logged before them, marked and answerable.
#
# RULED (R194, R197): flag rises not explained by logged food, on the eaten
# basis; offer what it was, in a ruled order; store every answer as a label for
# the model that comes later. PASSIVE -- a mark on the chart and a line under it,
# never a prompt, never a count. Stress is NEVER inferred: there is no heart rate
# on the device, and the surface says so.
#
# WHY A GATE AND NOT ONLY THE HARNESS BLOCK. The harness holds the rule, the
# order and the stored label on series it builds itself. It cannot hold what
# "passive" means on a screen -- that nothing about a rise is anywhere until the
# user opens the glucose row -- nor that the answers are tappable, nor that steps
# really arrive through the Apple Health file the user picks.
#
# PRE-REGISTERED (DECISIONS, E-lite section 5, with R197's additions):
#   1. an Apple Health file brings glucose AND steps -- steps only, and only for
#      the days glucose covers (ruled D)
#   2. PASSIVE: with the glucose row closed there is no block, no mark, no count
#      and no word about a rise anywhere on the page (ruled C)
#   3. opened: a mark on the chart at each flagged rise, a line under it, and
#      none for the rise that has food before it
#   4. the answers in the ruled order -- sensor artifact FIRST after a sudden
#      drop or in a sensor's first day, then asleep, then food, stress, other
#   5. a real click stores the answer, shows it, and can be undone and changed;
#      "not sure" is stored too
#   6. the stored answer reads in plain words on the timeline, never by its
#      storage name
#   7. no probability, no badge, no inferred stress; the heart-rate inputs are
#      wired, empty, and said to be
#   8. 16px, 44px, no sideways scroll, at 390 and 360
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8275
$Dbg = 9473
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-elite-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.eliteDay === 'function' && typeof HT.stepsIn === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or E-lite is not on HT"; Cleanup; exit 2 }

  # ---- 1. an Apple Health file, through the import the user actually uses ----------
  # Built in the page, in the device's own offset, for TODAY -- the day the app is
  # showing. One reading every five minutes; three climbs; steps; one step record
  # for a day glucose does not cover; one heart-rate record that must not be read.
  $imp = EvalA @'
(function () {
  var dk = HT.state().current;
  var off = -new Date(dk + 'T12:00:00').getTimezoneOffset();
  var tz = (off < 0 ? '-' : '+') + String(Math.floor(Math.abs(off) / 60)).padStart(2, '0') + String(Math.abs(off) % 60).padStart(2, '0');
  var at = function (d, m) { return d + ' ' + String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0') + ':00 ' + tz; };
  var v = {};
  for (var m = 0; m < 1440; m += 5) v[m] = 5.5;
  var ramp = function (m0, a, b, mins) { for (var k = 0; k <= mins; k += 5) v[m0 + k] = a + (b - a) * k / mins; };
  v[165] = 6.4; v[170] = 6.4; v[175] = 6.4;      // a little high...
  ramp(180, 5.0, 8.0, 30);                       // ...then 03:00 from a sudden drop, up to 8.0
  ramp(540, 5.5, 7.5, 40);                       // 09:00, half an hour after breakfast
  ramp(900, 5.5, 9.0, 40);                       // 15:00, hours after it
  var lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<!DOCTYPE HealthData [', ']>', '<HealthData locale="en_CA">'];
  Object.keys(v).forEach(function (m) {
    lines.push(' <Record type="HKQuantityTypeIdentifierBloodGlucose" sourceName="Dexcom G7" unit="mmol&lt;180.1558800000541&gt;/L" creationDate="' + at(dk, +m) + '" startDate="' + at(dk, +m) + '" endDate="' + at(dk, +m) + '" value="' + v[m] + '"/>');
  });
  [[886, 100], [890, 120], [895, 90]].forEach(function (s) {
    lines.push(' <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count" startDate="' + at(dk, s[0]) + '" endDate="' + at(dk, s[0] + 4) + '" value="' + s[1] + '"/>');
  });
  lines.push(' <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Watch" unit="count" startDate="' + at(dk, 887) + '" endDate="' + at(dk, 889) + '" value="40"/>');
  lines.push(' <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count" startDate="' + at('2026-01-02', 600) + '" endDate="' + at('2026-01-02', 605) + '" value="500"/>');
  lines.push(' <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" startDate="' + at(dk, 886) + '" endDate="' + at(dk, 886) + '" value="72"/>');
  lines.push('</HealthData>');
  window.__dk = dk; window.__base = HT.dayKeyMs(dk);
  // A breakfast at 08:30, logged the ordinary way, before the import.
  HT.addManualEntry({ name: 'Gate breakfast', meal: 'breakfast', time: '08:30', kcal: 400, grams: 300 });
  var before = { block: !!document.querySelector('.elblock') };
  return HT.glucoseImportFile(new File([lines.join('\n')], 'export.xml', { type: 'text/xml' })).then(function (r) {
    var g = HT.glucoseRead(), st = HT.stepsRead();
    return { ok: !!(r && r.ok), read: r && r.read, glucoseDays: Object.keys(g).length, readings: g[dk] ? g[dk].t.length : 0,
             stepDays: Object.keys(st).join(','), stepSrc: st[dk] ? st[dk].src : '', steps: st[dk] ? st[dk].n.reduce(function (a, b) { return a + b; }, 0) : -1,
             heart: HT.eliteInputs().heartRate.days, today: dk };
  });
})()
'@
  Write-Host ("  import: " + $imp)
  $im = $imp | ConvertFrom-Json
  Check (($im.ok -eq $true) -and ($im.readings -eq 288)) "an Apple Health file read through the app's own import brings the day's 288 glucose readings"
  Check (($im.stepDays -eq $im.today) -and ($im.steps -eq 310) -and ($im.stepSrc -eq 'iPhone')) "RULED D: and its STEPS -- for the day glucose covers and NO other (a January day in the same file is not kept), from one source (the larger; the two are never summed)"
  Check ($im.heart -eq 0) "nothing else is read from that file: the heart-rate record in it is not imported, and the heart-rate input stays empty"

  # ---- 2. PASSIVE: with the glucose row closed, nothing ----------------------------
  $closed = EvalJ @'
(function () {
  // The import opens the row to show what arrived; close it, as it would be on
  // any later visit to the day.
  var h = document.querySelector('#dayView .ghead');
  if (h && h.getAttribute('aria-expanded') === 'true') h.click();
  var txt = document.body.innerText || '';
  return { flagged: HT.eliteDay(window.__dk).length, block: !!document.querySelector('.elblock'),
           marks: document.querySelectorAll('.tmark[data-kind="rise"]').length,
           words: /rise|no food logged|what was it/i.test(txt), badge: /\b\d+\s+(rise|rises|unexplained)\b/i.test(txt),
           toast: (document.getElementById('toast') || {}).className.indexOf('show') >= 0 && /rise/i.test(document.getElementById('toast').textContent) };
})()
'@
  Write-Host ("  closed: " + $closed)
  $cl = $closed | ConvertFrom-Json
  Check ($cl.flagged -eq 2) "PRECONDITION: two rises on the day ARE flagged -- so the silence asserted next is silence about something"
  Check (($cl.block -eq $false) -and ($cl.marks -eq 0) -and ($cl.words -eq $false)) "PASSIVE (ruled C): with the glucose row closed there is NO block, NO mark and NO word about a rise anywhere on the page"
  Check (($cl.badge -eq $false) -and ($cl.toast -eq $false)) "and no count and no prompt -- nothing is said until it is asked for"

  # ---- 3 + 4. opened ------------------------------------------------------------------
  $open = EvalJ @'
(function () {
  document.querySelector('#dayView .ghead').click();
  var b = document.querySelector('.elblock');
  if (!b) return { err: 'no block in the opened glucose row' };
  var rises = b.querySelectorAll('.elrise');
  var read = function (r) { return { line: (r.querySelector('.elline') || {}).textContent, ctx: (r.querySelector('.elctx') || {}).textContent,
    offers: Array.prototype.map.call(r.querySelectorAll('.elbtn'), function (x) { return x.textContent; }).join('|'),
    unsure: !!r.querySelector('.elunsure') }; };
  var notes = Array.prototype.map.call(b.querySelectorAll('.elnote'), function (n) { return n.textContent; }).join(' || ');
  var txt = b.innerText || '';
  var chart = document.querySelector('.gbody');
  return { n: rises.length, a: read(rises[0]), b: read(rises[1]), head: (b.querySelector('.elhead') || {}).textContent, notes: notes,
           marks: document.querySelectorAll('.tmark[data-kind="rise"]').length, inRow: !!chart && chart.contains(b),
           belowChart: b.getBoundingClientRect().top >= (document.querySelector('.tchartbox') || b).getBoundingClientRect().bottom - 1,
           infers: /probab|likel|%|\bscore\b|caus|trigger/i.test(txt) };
})()
'@
  Write-Host ("  opened: " + $open)
  $op = $open | ConvertFrom-Json
  Check (($op.n -eq 2) -and ($op.inRow -eq $true) -and ($op.belowChart -eq $true)) "a real click opens the glucose row, and UNDER THE CHART are the two flagged rises -- and not the 09:00 one, which has breakfast before it"
  Check ($op.marks -ge 1) "the chart carries a MARK for a flagged rise (ruled C)"
  Check ($op.a.line -like '03:00 * 5 * 8 mmol/L in 30 min') "the first line says when it started, how far it went and in how long: 03:00, 5 to 8 mmol/L in 30 min"
  Check (($op.a.ctx -like '*began right after a sudden drop*') -and ($op.a.ctx -like '*in the small hours, with no sleep logged*')) "and what is known about that moment -- it began right after a sudden drop, in the small hours with no sleep logged"
  Check ($op.a.offers -eq ('sensor artifact|while asleep|food I didn' + [char]0x2019 + 't log|stress|something else')) "RULED B, the order: SENSOR ARTIFACT first (a sudden drop), then WHILE ASLEEP, then food, stress, something else"
  Check (($op.b.line -like '15:00 * 5.5 * 9 mmol/L in 40 min') -and ($op.b.offers -eq ('food I didn' + [char]0x2019 + 't log|stress|something else'))) "the 15:00 rise, by day: FOOD I DIDN'T LOG first, then stress, then something else"
  Check (($op.b.ctx -like '*6.5 h after the last food logged*') -and ($op.b.ctx -like '*moving*310 steps*') -and ($op.a.ctx -like '*still*0 steps*')) "its line carries the covariates that exist: hours since food, and STEPS -- moving at 15:00, still at 03:00"
  Check (($op.a.unsure -eq $true) -and ($op.b.unsure -eq $true)) "'not sure' is offered beside the answers"
  Check (($op.notes -like '*Marked by one rule: up 1.5 mmol/L or more inside an hour, with no food logged in the 4 hours before.*') -and ($op.notes -like '*does not weigh how much was eaten*')) "the block states WHICH RULE marked them, and what the rule does not do (ruled A: 'explained' is binary)"
  Check ($op.notes -like '*No heart rate or heart-rate variability is held on this device, so nothing here works out stress.*') "and says the heart-rate inputs are empty, so stress is never worked out -- only answered"
  Check ($op.infers -eq $false) "NO probability, likelihood, percentage, score or cause is on it"

  # ---- 4 (again). a sensor's first day ----------------------------------------------
  $sens = EvalJ @'
(function () {
  HT.state().settings.sensorDevice = 'dexcom-g7';
  HT.addSignal({ type: 'sensor', source: 'quick', date: window.__dk, time: '14:00', variant: 'left arm', device: 'dexcom-g7' });
  var rises = document.querySelectorAll('.elblock .elrise');
  var out = { second: Array.prototype.map.call(rises[1].querySelectorAll('.elbtn'), function (x) { return x.textContent; })[0],
              ctx: rises[1].querySelector('.elctx').textContent,
              first: Array.prototype.map.call(rises[0].querySelectorAll('.elbtn'), function (x) { return x.textContent; }).length };
  var tl = HT.state().timeline[window.__dk];
  tl.splice(tl.length - 1, 1); HT.resave(); HT.refresh();
  return out;
})()
'@
  Write-Host ("  a new sensor at 14:00: " + $sens)
  Check (($sens -like '*"second":"sensor artifact"*') -and ($sens -like '*in the first day of a new sensor*')) "RULED B: with a sensor changed an hour before it, the 15:00 rise offers SENSOR ARTIFACT first and says it is in the sensor's first day"

  # ---- 5. answering, by real clicks ----------------------------------------------------
  $ans = EvalJ @'
(function () {
  var rise = document.querySelectorAll('.elblock .elrise')[1];
  var b = null;
  Array.prototype.forEach.call(rise.querySelectorAll('.elbtn'), function (x) { if (x.textContent.indexOf('food') === 0) b = x; });
  if (!b) return { err: 'no food answer' };
  var open0 = document.querySelector('#dayView .ghead').getAttribute('aria-expanded');
  b.click();
  var recs = (HT.state().timeline[window.__dk] || []).filter(function (r) { return r.type === HT.ELITE_TYPE; });
  rise = document.querySelectorAll('.elblock .elrise')[1];
  var t = document.getElementById('toast');
  return { stored: recs.length, variant: recs[0] && recs[0].variant, time: recs[0] && recs[0].time, value: recs[0] && recs[0].value,
           said: rise ? ((rise.querySelector('.elsaid') || {}).textContent || '') : '', buttons: rise ? rise.querySelectorAll('.elbtn').length : -1,
           change: rise ? !!rise.querySelector('.elchange') : false, stillOpen: document.querySelector('#dayView .ghead').getAttribute('aria-expanded') === 'true' && open0 === 'true',
           toast: t.textContent, undo: !!t.querySelector('.tundo'), marks: document.querySelectorAll('.tmark[data-kind="rise"]').length };
})()
'@
  Write-Host ("  answered: " + $ans)
  $an = $ans | ConvertFrom-Json
  Check (($an.stored -eq 1) -and ($an.variant -eq 'food') -and ($an.time -eq '15:00') -and ($an.value -eq 3.5)) "a real click on an answer STORES it -- one label, carrying the rise it answers: its start and its size"
  Check (($an.said -like 'You said: food*') -and ($an.buttons -eq 0) -and ($an.change -eq $true)) "the rise then shows the answer in place of the question, with a way to change it"
  Check (($an.stillOpen -eq $true) -and ($an.marks -ge 1)) "the row stays open and the mark stays on the chart -- an answered rise is still a rise"
  Check (($an.toast -like 'Glucose rise*food*Undo') -and ($an.undo -eq $true)) "and it can be undone"
  $chg = EvalJ @'
(function () {
  var rise = document.querySelectorAll('.elblock .elrise')[1];
  rise.querySelector('.elchange').click();
  rise = document.querySelectorAll('.elblock .elrise')[1];
  var n = rise.querySelectorAll('.elbtn').length;
  var b = null;
  Array.prototype.forEach.call(rise.querySelectorAll('.elbtn'), function (x) { if (x.textContent === 'stress') b = x; });
  b.click();
  var recs = (HT.state().timeline[window.__dk] || []).filter(function (r) { return r.type === HT.ELITE_TYPE; });
  var u = document.querySelector('#toast .tundo'); if (u) u.click();
  var back = (HT.state().timeline[window.__dk] || []).filter(function (r) { return r.type === HT.ELITE_TYPE; });
  document.querySelectorAll('.elblock .elrise')[0].querySelector('.elunsure').click();
  var all = (HT.state().timeline[window.__dk] || []).filter(function (r) { return r.type === HT.ELITE_TYPE; });
  return { reoffered: n, afterChange: recs.length + ':' + (recs[0] && recs[0].variant), afterUndo: back.length + ':' + (back[0] && back[0].variant),
           unsure: all.map(function (r) { return r.time + '=' + r.variant; }).sort().join(','),
           first: (document.querySelectorAll('.elblock .elrise')[0].querySelector('.elsaid') || {}).textContent || '' };
})()
'@
  Write-Host ("  changed, undone, dismissed: " + $chg)
  $cg = $chg | ConvertFrom-Json
  Check (($cg.reoffered -eq 3) -and ($cg.afterChange -eq '1:stress')) "'change' offers the answers again, and choosing another REPLACES the label -- one rise, one answer; and 'stress' is storable, as the user's own word"
  Check ($cg.afterUndo -eq '1:food') "a real click on Undo puts the earlier answer back"
  Check (($cg.unsure -eq '03:00=unsure,15:00=food') -and ($cg.first -like 'You said: not sure')) "'not sure' is STORED too -- a dismissal is a label, so a rise that was waved away is never read later as one that was not seen"

  # ---- 6. on the timeline, in plain words ----------------------------------------------
  $tl = EvalJ @'
(function () {
  var head = document.querySelector('#dayView .bghead');
  if (head && head.getAttribute('aria-expanded') !== 'true') head.click();
  var names = Array.prototype.map.call(document.querySelectorAll('#dayView .bgline .mginame'), function (n) { return n.textContent; });
  var page = document.body.innerText || '';
  return { names: names, raw: page.indexOf('glucose_rise') >= 0 };
})()
'@
  Write-Host ("  timeline: " + $tl)
  Check (($tl.Contains('Glucose rise')) -and ($tl -like '*"raw":false*')) "the stored answers read 'Glucose rise . ...' in the day's own list, and the storage name appears NOWHERE on the page"

  # ---- 8. measured at both widths ---------------------------------------------------------
  foreach ($w in @(390, 360)) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    WaitQuiet 'after a step'
    $sz = EvalJ @'
(function () {
  HT.refresh();
  var h = document.querySelector('#dayView .ghead');
  if (h && h.getAttribute('aria-expanded') !== 'true') h.click();
  var b = document.querySelector('.elblock');
  if (!b) return { err: 'no block' };
  var first = document.querySelectorAll('.elblock .elrise')[1].querySelector('.elchange'); if (first) first.click();
  b = document.querySelector('.elblock');
  var small = [], short = [], n = 0;
  Array.prototype.forEach.call(b.querySelectorAll('.elhead, .elline, .elctx, .elq, .elsaid, .elnote, .elbtn, .elunsure, .elchange'), function (e) {
    n++;
    var fs = parseFloat(getComputedStyle(e).fontSize); if (fs < 16) small.push(e.className + ' ' + fs);
    if (e.tagName === 'BUTTON' && e.offsetHeight < 44) short.push(e.className + ' ' + e.offsetHeight); });
  return { n: n, small: small, short: short, overflow: b.scrollWidth - b.clientWidth, page: document.documentElement.scrollWidth - window.innerWidth,
           buttons: b.querySelectorAll('.elbtn').length };
})()
'@
    Write-Host ("  sizes@" + $w + ": " + $sz)
    Check ($sz.Contains('"small":[]')) ("every word of the block is >= 16px at " + $w)
    Check ($sz.Contains('"short":[]') -and (-not ($sz -like '*"buttons":0*'))) ("every answer and link in it is >= 44px tall at " + $w + ", with answers on screen to measure")
    Check (($sz -like '*"overflow":0*') -and ($sz -like '*"page":0*')) ("and neither it nor the page scrolls sideways at " + $w)
  }
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null

  # ---- no dead control, with a plant, and D146 ------------------------------------------
  $dead = EvalJ @'
(function () {
  var scan = function () { var bad = [], n = 0;
    Array.prototype.forEach.call(document.querySelectorAll('.elblock [onclick]'), function (b) {
      var a = (b.getAttribute('onclick') || '').replace(/^event\.stopPropagation\(\);?/, '');
      if (!a) return;
      n++;
      var fn = (a.match(/^([A-Za-z0-9_$.]+)\s*\(/) || [])[1];
      if (!fn) { bad.push('unparsed: ' + a); return; }
      if (typeof window[fn] !== 'function') bad.push(fn);
    }); return { n: n, bad: bad }; };
  var a = scan();
  var keep = window.eliteLabel; window.eliteLabel = undefined;
  var planted = scan().bad.indexOf('eliteLabel') >= 0;
  window.eliteLabel = keep;
  // D146: log food before both remaining rises and the block must be gone entirely.
  HT.addManualEntry({ name: 'Late snack', meal: 'snack', time: '00:30', kcal: 100 });
  HT.addManualEntry({ name: 'Lunch', meal: 'lunch', time: '13:00', kcal: 500 });
  var h = document.querySelector('#dayView .ghead');
  if (h && h.getAttribute('aria-expanded') !== 'true') h.click();
  return { controls: a.n, dead: a.bad, planted: planted, restored: typeof window.eliteLabel === 'function',
           flagged: HT.eliteDay(window.__dk).length, block: !!document.querySelector('.elblock'),
           marks: document.querySelectorAll('.tmark[data-kind="rise"]').length };
})()
'@
  Write-Host ("  controls, and a day with food before every rise: " + $dead)
  Check ($dead.Contains('"dead":[]') -and (-not ($dead -like '*"controls":0*'))) "every control in the block resolves to a function that EXISTS"
  Check (($dead -like '*"planted":true*') -and ($dead -like '*"restored":true*')) "PLANT: with one handler taken away the scan names it, and it is put back"
  Check (($dead -like '*"flagged":0*') -and ($dead -like '*"block":false*') -and ($dead -like '*"marks":0*')) "D146, and the eaten basis by real logging: once food is logged before each rise, NOTHING is flagged and the block and its marks are gone -- not an empty heading, not the note about heart rate"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("E-LITE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "E-LITE GATE: PASS -- rises with no food before them are marked only where the"
Write-Host "  user looks, offered in the ruled order, answered by a tap and stored; steps"
Write-Host "  arrive through the Apple Health file; and nothing on it infers stress."
Write-Host "GATE: PASS"
exit 0
