# PERF GATE (R282) -- one redraw of a year of logged days stays inside a budget.
#
#   The fixture is the one the R280 slowdown was measured on: 365 past days of 8 items,
#   none closed by hand. Each of 21 rounds times one full redraw (HT.refresh, with the
#   layout it forces) and, back to back, one fixed reference workload; the verdict is
#   on the RATIO of their medians, so a busy machine -- which slows both -- does not
#   fail it, and a slower redraw does. PERF_REPO=<dir> measures another build.
#
#   R298: then the SAME year again WITH CGM -- a reading every 5 minutes on every day,
#   a rise after each day's lunch -- because the year without glucose could not see
#   a redraw that read the whole glucose store back for every meal and night (10.45
#   reference workloads on the user's own log). Both are judged on the same budget.
#
# Synthetic days only. Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if ($env:PERF_REPO) { $repo = $env:PERF_REPO }   # measure another build (red-first, before/after)
# Budget: 3.0 reference workloads. Measured 2026-10-28 on this fixture (median of 21): v0.111.2
# 2.19-2.34, R280 before its fix 3.21-3.29, after the fix 2.44-2.58. 3.0 is ~20 % over the
# worst post-fix figure and below the slowdown R280 shipped with, which it fails.
$PERF_BUDGET = 3.0
$Port = 8399
$Dbg = 9599
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-perf-" + [System.Guid]::NewGuid().ToString('N'))
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
  $qr = Invoke-CDP 'Runtime.evaluate' @{ expression = "(window.__htQuiet ? window.__htQuiet(10000).then(function () { return 'quiet'; }, function (e) { return String(e && e.message || e); }) : Promise.resolve('no quiet marker on this page'))"; awaitPromise = $true; returnByValue = $true }
  $v = $qr.result.result.value
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

# (no screenshots)
$shots = $null

function Shot([string]$name) {
  if (-not $shots) { return }
  $rv = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png' }
  [IO.File]::WriteAllBytes((Join-Path $shots ($name + '.png')), [Convert]::FromBase64String($rv.result.data))
}

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

  $boot = Eval "typeof HT === 'object' && typeof HT.refresh === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or HT.refresh is not on HT"; Cleanup; exit 2 }

  # ---- the fixture: a year of days, 8 items each, none closed by hand -------------------
  [void](Eval @'
(function () {
  var S = HT.state(), t = HT.todayKey();
  var f = function (k) { return { name: 'Perf food', meal: 'lunch', time: '12:00', kcal: k, protein_g: 10, fat_g: 10, carb_g: 10, fiber_g: 1, soluble_fiber_g: 0, confidence: 'eyeballed', notes: '', source: 'manual' }; };
  for (var n = 1; n <= 365; n++) { var items = []; for (var j = 0; j < 8; j++) items.push(f(200 + j * 10 + n % 7)); S.days[HT.shiftDate(t, -n)] = { status: 'in_progress', water_l: 0, items: items }; }
  HT.resave();
  window.__perfOld = 1;
  return 1;
})()
'@)
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  for ($bw = 0; $bw -lt 120; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "!window.__perfOld && typeof HT === 'object' && document.readyState === 'complete' && Object.keys(HT.state().days).length > 365"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 250 }

  # ---- the measure: interleaved, median of many --------------------------------------------
  # Each round times ONE full redraw (HT.refresh) and ONE fixed reference workload, back to
  # back, so both see the same machine. The median of each is taken; the verdict is on
  # their RATIO, which a busy PC moves far less than it moves either number alone.
  $MEASURE_JS = @'
(function () {
  var calib = function () { var a = []; for (var i = 0; i < 120000; i++) a.push((i * 7919) % 100003); a.sort(function (x, y) { return x - y; }); var d = document.createElement('div'); var h = ''; for (var k = 0; k < 400; k++) h += '<div class="trow"><span>' + a[k] + '</span><b>' + a[k + 1] + '</b></div>'; d.innerHTML = h; document.body.appendChild(d); var hh = d.getBoundingClientRect().height; d.remove(); return hh; };
  for (var w = 0; w < 3; w++) { HT.refresh(); calib(); }
  var R = [], C = [];
  for (var i = 0; i < 21; i++) {
    var a = performance.now(); HT.refresh(); document.body.getBoundingClientRect(); var b = performance.now();
    calib(); var c = performance.now();
    R.push(b - a); C.push(c - b);
  }
  var med = function (v) { var s = v.slice().sort(function (x, y) { return x - y; }); return s[(s.length - 1) / 2]; };
  var r = med(R), cm = med(C);
  return { redrawMs: Math.round(r), calibMs: Math.round(cm), ratio: Math.round(r / cm * 100) / 100,
           spreadMs: Math.round(Math.max.apply(null, R) - Math.min.apply(null, R)), n: R.length, days: Object.keys(HT.state().days).length };
})()
'@
  $m = EvalJ $MEASURE_JS
  Write-Host ("  " + $m)
  $mv = $m | ConvertFrom-Json
  $budget = [double]$env:PERF_BUDGET_RATIO
  if (-not ($budget -gt 0)) { $budget = $PERF_BUDGET }
  Check (($mv.days -ge 366) -and ($mv.n -eq 21)) "PRECONDITION: the year-of-days fixture loaded (366 days) and 21 redraws were timed"
  Check ($mv.ratio -le $budget) ("PERF GATE: one redraw of a year of days costs " + $mv.ratio + " reference workloads (median of 21: " + $mv.redrawMs + " ms against " + $mv.calibMs + " ms) -- budget " + $budget)

  # ---- R298: the same year WITH CGM ------------------------------------------------------------
  # Written straight into the glucose store (the shape glucoseIngest keeps: per day, a unit and
  # parallel minute/value arrays), every day of the year at 5-minute steps: 5.0 mmol/L, rising
  # 2 mmol/L over the 30 min after each day's 12:00 lunch and back by 90 min, so every sitting
  # has a judged response and every night a series.
  $g = EvalJ @'
(function () {
  var S = HT.state(), store = {};
  Object.keys(S.days).forEach(function (dk) {
    var t = [], v = [];
    for (var m = 0; m < 1440; m += 5) {
      var x = m - 720, val = 5.0;
      if (x > 0 && x <= 30) val = 5.0 + 2 * x / 30; else if (x > 30 && x < 90) val = 5.0 + 2 * (90 - x) / 60;
      t.push(m); v.push(Math.round(val * 100) / 100);
    }
    store[dk] = { u: 'mmol/L', t: t, v: v };
  });
  var ok = HT.glucoseWrite(store);
  HT.refresh();
  var dk1 = HT.shiftDate(HT.todayKey(), -10);
  var ev = HT.mealEvents(dk1)[0];
  var rv = ev ? HT.mealReview(dk1, ev.mealId) : null;
  return { stored: ok, glucoseDays: Object.keys(HT.glucoseRead()).length, judged: !!(rv && rv.judged) };
})()
'@
  Write-Host ("  CGM: " + $g)
  $gv = $g | ConvertFrom-Json
  Check (($gv.stored -eq $true) -and ($gv.glucoseDays -ge 366) -and ($gv.judged -eq $true)) "PRECONDITION (R298): a year of CGM is stored (a reading every 5 min on every day) and a past lunch has a judged response"
  $m2 = EvalJ $MEASURE_JS
  Write-Host ("  with CGM: " + $m2)
  $mv2 = $m2 | ConvertFrom-Json
  Check ($mv2.n -eq 21) "PRECONDITION (R298): 21 redraws of the year with CGM were timed"
  Check ($mv2.ratio -le $budget) ("PERF GATE (R298): one redraw of a year of days WITH CGM costs " + $mv2.ratio + " reference workloads (median of 21: " + $mv2.redrawMs + " ms against " + $mv2.calibMs + " ms) -- budget " + $budget)

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("PERF GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "PERF GATE: PASS -- a redraw of a year of days, without and with CGM, is inside its budget, measured as a"
Write-Host "  median of 21 against a reference workload timed beside it."
Write-Host "GATE: PASS"
exit 0
