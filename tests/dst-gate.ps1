# R301 -- DURATIONS ARE REAL TIME, ACROSS A CLOCK CHANGE.
#
# THE RULING: a night from 23:00 to 07:00 across the night the clocks go back
# (1 Nov 2026, 02:00 -> 01:00) is 9 h, not 8. The same for fast lengths, the 12 h and
# 48 h fasting rules, the glucose windows, the strip's 3 h and the 04:00 close.
# Times are SHOWN on the wall clock.
#
# THE ZONE IS FIXED HERE, NOT TAKEN FROM THE MACHINE. Emulation.setTimezoneOverride puts
# the page in America/Toronto before the app loads, so the gate checks the change on any
# machine, any day of the year; if the override does not take (1 Nov is not 25 hours
# long in the page) the gate is exit 2, not a pass.
#
# PRE-REGISTERED (DECISIONS R301): a sleep and a fast spanning the change report the
# real duration; the 12 h and 48 h lines read real time; the wake time and the ring stay
# on the wall clock; the 04:00 close happens at local 04:00; the strip's 3 h are real;
# a glucose reading sits at its real moment. Each figure is chosen so the old wall-clock
# arithmetic gives a different answer.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8411
$Dbg = 9611
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-dst-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Emulation.setTimezoneOverride' @{ timezoneId = 'America/Toronto' } | Out-Null   # R301: a zone whose clocks go back on 1 Nov
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }


  $boot = Eval "typeof HT === 'object' && typeof HT.wallMs === 'function' && typeof HT.sleepSpan === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R301 helpers are not on HT"; Cleanup; exit 2 }
  $tz = Eval "Intl.DateTimeFormat().resolvedOptions().timeZone + ' ' + ((new Date('2026-11-02T00:00:00') - new Date('2026-11-01T00:00:00')) / 3600000)"
  Write-Host ("  zone: " + $tz)
  if ($tz -ne 'America/Toronto 25') { Write-Host "ERROR: the zone override did not take, so 1 Nov is not a 25-hour day here and nothing below would mean anything"; Cleanup; exit 2 }

  # ---- sleep ---------------------------------------------------------------------------
  $sl = EvalJ @'
(function () {
  var at = function (s) { return new Date(s).getTime(); };
  var T = 0; localStorage.clear(); HT.boot(); HT.setClock(function () { return T; });
  var out = {};
  // 1. ended with Now: in bed 23:00 on 31 Oct, Now at 07:00 on 1 Nov
  T = at('2026-10-31T23:00:00'); HT.laneOn('sleep');
  T = at('2026-11-01T07:00:00');
  var r = HT.laneOff('sleep');
  out.nowVal = r.record ? r.record.value : null;
  out.nowMin = r.minutes;
  out.wake = HT.minutesToHHMM(HT.sleepWakeMin(r.record, '2026-11-01'));
  out.series = HT.seriesSummary(HT.signalSeries('sleep_hours', 'all')).latest;
  var arcs = HT.rhythmModel('2026-11-01', { live: false }).arcs.filter(function (a) { return a.cat === 'sleep' && !a.ref; });
  out.arc = arcs.map(function (a) { return a.startMin + '-' + a.endMin + ' ' + a.label; }).join('|');
  out.row = HT.sleepRowLabel(r.record, '2026-11-01');
  // 2. ended by a typed time: in bed 23:00, "Woke at 07:00" told at 08:00
  localStorage.clear(); HT.boot();
  T = at('2026-10-31T23:00:00'); HT.laneOn('sleep');
  T = at('2026-11-01T08:00:00');
  var r2 = HT.resolveLaneOpen('sleep', '07:00', 'typed');
  out.typedVal = r2.record ? r2.record.value : null;
  // 3. an open sleep: the 11 h "did you forget?" line is real time too
  localStorage.clear(); HT.boot();
  T = at('2026-10-31T20:30:00'); HT.laneOn('sleep');
  T = at('2026-11-01T06:29:00'); var s1 = HT.sleepOpenState();
  T = at('2026-11-01T06:31:00'); var s2 = HT.sleepOpenState();
  out.open = [s1.minutes, s1.pending, s2.minutes, s2.pending];
  HT.setClock(null);
  return out;
})()
'@
  Write-Host ("  sleep: " + $sl)
  $s = $sl | ConvertFrom-Json
  Check (($s.nowVal -eq 9) -and ($s.nowMin -eq 540)) "a night from 23:00 on 31 Oct to 07:00 on 1 Nov, ended with Now, is 9 h (540 min) -- the wall clock says 8"
  Check ($s.typedVal -eq 9) "the same night ended by typing 'Woke at 07:00' is 9 h"
  Check (($s.wake -eq '07:00') -and ($s.row -eq 'Sleep (woke 07:00)')) "its wake time is still SHOWN on the wall clock: 07:00 ('$($s.row)')"
  Check ($s.series -eq 9) "Trends' sleep hours read 9 for the night"
  Check ($s.arc -eq '0-420 sleep 9h') "the ring draws it on the wall clock, midnight to 07:00 on 1 Nov, and labels it 9 h ('$($s.arc)')"
  Check ((($s.open -join ',') -eq '659,False,661,True')) "an open sleep from 20:30 counts real minutes: 659 at 06:29 (not yet the 11 h line), 661 at 06:31 (past it) -- the wall clock would say 599 and 601"

  # ---- fasts ---------------------------------------------------------------------------
  $fs = EvalJ @'
(function () {
  var at = function (s) { return new Date(s).getTime(); };
  var T = at('2026-11-01T12:00:00'); localStorage.clear(); HT.boot(); HT.setClock(function () { return T; });
  var food = function (time) { return { name: 'Gate stew', meal: 'dinner', time: time, kcal: 300, protein_g: 10, fat_g: 10, carb_g: 30, fiber_g: 2, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }; };
  var day = function (dk, times) { HT.state().days[dk] = { status: 'in_progress', water_l: 0, items: times.map(food) }; };
  var out = {};
  // 1. 19:00 on 31 Oct to 08:00 on 1 Nov
  day('2026-10-31', ['19:00']); day('2026-11-01', ['08:00']); HT.resave();
  out.len = HT.fastsClosed().map(function (g) { return g.mins + '/' + g.hours; }).join('|');
  // 2. the 12 h rule: 21:00 to 08:30 is 11.5 h on the wall and 12.5 h in fact
  day('2026-10-31', ['21:00']); day('2026-11-01', ['08:30']); HT.resave();
  out.rule12 = HT.fastGaps(null).map(function (g) { return g.mins + '/' + g.fast; }).join('|');
  // 3. the 48 h line: 07:30 on 30 Oct to 07:00 on 1 Nov is 47.5 h on the wall and 48.5 h in fact
  HT.state().days = {}; day('2026-10-30', ['07:30']); day('2026-11-01', ['07:00']); HT.resave();
  out.rule48 = HT.fastGaps(null).map(function (g) { return g.mins + '/' + g.fast + '/' + g.unlogged; }).join('|');
  // 4. running now: last food 19:00 on 31 Oct, now 06:30 on 1 Nov
  HT.state().days = {}; day('2026-10-31', ['19:00']); HT.resave();
  T = at('2026-11-01T06:30:00');
  var o = HT.fastOpenNow();
  out.open = o ? [o.mins, o.fast, HT.openFastLabel(o.mins, '', false)] : null;
  HT.setClock(null);
  return out;
})()
'@
  Write-Host ("  fasts: " + $fs)
  $f = $fs | ConvertFrom-Json
  Check ($f.len -eq '840/14') "a fast from 19:00 on 31 Oct to 08:00 on 1 Nov is 14 h (840 min) -- the wall clock says 13"
  Check ($f.rule12 -eq '750/True') "the 12 h rule reads real time: 21:00 to 08:30 across the change is 12.5 h, a fast (the wall clock's 11.5 h would not be)"
  Check ($f.rule48 -eq '2910/False/True') "the 48 h line reads real time: 07:30 on 30 Oct to 07:00 on 1 Nov is 48.5 h, an unlogged gap and not a fast (47.5 h on the wall)"
  Check (($f.open.Count -eq 3) -and ($f.open[0] -eq 750) -and ($f.open[1] -eq $true) -and ($f.open[2] -like 'fasting 12*')) "a fast running since 19:00 on 31 Oct reads 12.5 h at 06:30 on 1 Nov -- '$($f.open[2])'"

  # ---- the 04:00 close, the strip, glucose ---------------------------------------------
  $ot = EvalJ @'
(function () {
  var at = function (s) { return new Date(s).getTime(); };
  var T = 0; localStorage.clear(); HT.boot(); HT.setClock(function () { return T; });
  var out = {};
  T = at('2026-11-01T03:59:00'); out.c359 = HT.dayClosedByRule('2026-10-31');
  T = at('2026-11-01T04:00:00'); out.c400 = HT.dayClosedByRule('2026-10-31');
  var cm = new Date(HT.dayCloseMs('2026-10-31'));
  out.closeAt = cm.getHours() + ':' + String(cm.getMinutes()).padStart(2, '0');
  out.closeAfterMidnightH = (HT.dayCloseMs('2026-10-31') - HT.dayKeyMs('2026-11-01')) / 3600000;
  // the strip: 3 h of real time from 23:30 on 31 Oct, i.e. to 01:30 the SECOND time round
  T = at('2026-10-31T23:30:00');
  HT.state().days['2026-10-31'] = { status: 'in_progress', water_l: 0, items: [{ name: 'Gate stew', meal: 'dinner', time: '23:30', kcal: 300, protein_g: 10, fat_g: 10, carb_g: 30, fiber_g: 2, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }] };
  HT.resave();
  HT.ctxNoteSet({ kind: 'food', dk: '2026-10-31', items: [{ i: 0, name: 'Gate stew', time: '23:30' }] });
  var t0 = T;
  T = t0 + 179 * 60000; out.s179 = HT.ctxStripCompute().kind;
  T = t0 + 181 * 60000; out.s181 = HT.ctxStripCompute().kind;
  out.s179wall = HT.minutesToHHMM(new Date(t0 + 179 * 60000).getHours() * 60 + new Date(t0 + 179 * 60000).getMinutes());
  // glucose: a reading every 15 min of real time, 22:00 on 31 Oct to 06:00 on 1 Nov
  var rows = [], g0 = at('2026-10-31T22:00:00'), g1 = at('2026-11-01T06:00:00');
  for (var t = g0; t <= g1; t += 15 * 60000) rows.push({ t: new Date(t).toISOString(), v: 5.5, unit: 'mmol/L' });
  HT.glucoseIngest(rows, { source: 'gate' });
  var pts = HT.glucoseSeries(g0 - 1, g1 + 1);
  var p3 = pts.filter(function (p) { var d = new Date(p.t); return d.getDate() === 1 && d.getHours() === 3 && d.getMinutes() === 0; })[0];
  var p0 = pts.filter(function (p) { var d = new Date(p.t); return d.getDate() === 1 && d.getHours() === 0 && d.getMinutes() === 0; })[0];
  out.g03 = p3 ? (p3.t === at('2026-11-01T03:00:00')) : null;
  out.g0to3h = (p3 && p0) ? (p3.t - p0.t) / 3600000 : null;
  out.mealWin = (HT.wallMs('2026-11-01', 180) - HT.wallMs('2026-11-01', 0)) / 3600000;
  // REPORTED, not passed: the readings the store keeps for the repeated hour
  out.sent = rows.length; out.kept = pts.length;
  out.moments = pts.map(function (p) { return p.t; }).filter(function (t, i, l) { return l.indexOf(t) === i; }).length;
  HT.glucoseIngest(rows, { source: 'gate' });
  out.kept2 = HT.glucoseSeries(g0 - 1, g1 + 1).length;
  HT.setClock(null);
  return out;
})()
'@
  Write-Host ("  other: " + $ot)
  $o = $ot | ConvertFrom-Json
  Check (($o.c359 -eq $false) -and ($o.c400 -eq $true) -and ($o.closeAt -eq '4:00') -and ($o.closeAfterMidnightH -eq 5)) "the day of 31 Oct closes at 04:00 LOCAL on 1 Nov -- open at 03:59, closed at 04:00 -- which is 5 real hours after midnight that night"
  Check (($o.s179 -eq 'food') -and ($o.s181 -eq 'quiet')) "the strip's 3 h are real time: a food logged at 23:30 on 31 Oct still shows at 2 h 59 ($($o.s179wall) on the wall) and is gone at 3 h 01"
  Check (($o.g03 -eq $true) -and ($o.g0to3h -eq 4) -and ($o.mealWin -eq 4)) "a glucose reading at 03:00 on 1 Nov sits at its real moment, 4 real hours after midnight; a window measured on the wall clock there is real time too"
  Write-Host ("  REPORTED (storage, not changed here): " + $o.sent + " readings sent across the night; one import keeps " + $o.kept + " at " + $o.moments + " distinct moments, and importing the same night again keeps " + $o.kept2 + " -- the repeated 01:00-01:59 hour is stored by its wall-clock minute, so the second time round sits on, then replaces, the first")

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("DST GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "DST GATE: PASS -- across the night the clocks go back, every duration is real time"
Write-Host "  (sleep 9 h, a fast 14 h, the 12 h and 48 h lines, the strip's 3 h) and every time"
Write-Host "  shown is the wall clock (woke 07:00, the 04:00 close)."
Write-Host "GATE: PASS"
exit 0
