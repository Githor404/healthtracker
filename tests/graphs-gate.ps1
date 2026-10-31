# R309 -- SCROLLABLE GRAPHS, AND THE USER'S OWN GOAL LINES.
#
# PRE-REGISTERED (DECISIONS R309): at 390 px every Trends chart and the BP chart zoom to
# 8x by real taps and scroll sideways with the value axis pinned (the scroll kept across a
# redraw); the glucose chart pans by a real drag on its own time-window zoom; a set goal
# draws as a NEUTRAL dashed line (the muted colour) labelled with its value, a band as two
# lines; no goal, no line; removing a goal removes it; no words about the data against
# it; goals survive export and restore byte-identically; the Settings form sets and
# removes by real taps, 44 px.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8416
$Dbg = 9616
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-graphs-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Emulation.setTimezoneOverride' @{ timezoneId = 'America/Toronto' } | Out-Null   # a fixed zone, so the fixture's times mean the same on any machine
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }


  $boot = Eval "typeof HT === 'object' && typeof HT.trendZoom === 'function' && typeof HT.graphGoalSet === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or R309 is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  function TapAt([double]$x, [double]$y) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap' }
  function TapSel([string]$sel) {
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()")
    if ($p -eq 'null' -or -not $p) { return $false }
    $q = $p | ConvertFrom-Json; TapAt $q.x $q.y; return $true }

  # ---- the fixture: two weeks of weight, sleep, bowel type, BP, calories, and a day of glucose ----
  $fx = EvalJ @'
(function () {
  localStorage.clear(); HT.boot();
  var T = new Date('2026-10-28T20:00:00').getTime(); HT.setClock(function () { return T; });
  var S = HT.state();
  var sig = function (dk, rec) { (S.timeline[dk] = S.timeline[dk] || []).push(HT.normalizeSignal(rec)); };
  for (var i = 14; i >= 1; i--) {
    var dk = HT.shiftDate('2026-10-28', -i);
    sig(dk, { type: 'weight', kind: 'biometric', time: '07:30', value: 82 - i * 0.1, unit: 'kg', source: 'manual' });
    sig(dk, { type: 'sleep_hours', kind: 'biometric', time: '07:00', value: 6.5 + (i % 3) * 0.5, unit: 'h', source: 'manual' });
    sig(dk, { type: 'bm', kind: 'biometric', time: '08:00', value: 3 + (i % 3), unit: 'type', source: 'manual' });
    sig(dk, { type: 'bp_systolic', kind: 'biometric', time: '08:10', value: 120 + (i % 5), unit: 'mmHg', source: 'manual' });
    sig(dk, { type: 'bp_diastolic', kind: 'biometric', time: '08:10', value: 78 + (i % 4), unit: 'mmHg', source: 'manual' });
    S.days[dk] = { status: 'complete', water_l: 0, items: [{ name: 'Gate meal', meal: 'dinner', time: '18:00', kcal: 1800 + i * 20, protein_g: 90, fat_g: 70, carb_g: 180, fiber_g: 25, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }] };
  }
  // BP over 28 days, the span of the user's own chart, where the dates crowded (the 31 Oct report)
  for (var j = 28; j > 14; j--) {
    var dj = HT.shiftDate('2026-10-28', -j);
    sig(dj, { type: 'bp_systolic', kind: 'biometric', time: '08:10', value: 124, unit: 'mmHg', source: 'manual' });
    sig(dj, { type: 'bp_diastolic', kind: 'biometric', time: '08:10', value: 80, unit: 'mmHg', source: 'manual' });
  }
  var rows = [], g0 = new Date('2026-10-28T00:00:00').getTime();
  for (var m = 0; m < 19 * 60; m += 5) rows.push({ t: new Date(g0 + m * 60000).toISOString(), v: 5.2 + (m % 120) / 100, unit: 'mmol/L' });
  HT.glucoseIngest(rows, { source: 'gate' });
  S.current = '2026-10-28'; HT.resave(); HT.setTrendWindow(30); HT.refresh();
  document.querySelector('[data-card] details, details') && 0;
  Array.prototype.forEach.call(document.querySelectorAll('.card details'), function (d) { if (/Trends/.test((d.querySelector('summary') || {}).textContent || '')) d.open = true; });
  return { ok: true, charts: document.querySelectorAll('#trends .tchartwrap').length, bp: !!document.getElementById('bpWrap') };
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"ok":true*')) { Write-Host "ERROR: fixture"; Cleanup; exit 2 }

  # ---- every Trends chart, and the BP chart: zoom to 8x by real taps, scroll, axis pinned --------
  $keys = (EvalJ "(function(){ return Array.prototype.map.call(document.querySelectorAll('#trends .tchartwrap'), function (w) { return w.getAttribute('data-key'); }); })()") | ConvertFrom-Json
  Write-Host ("  Trends charts: " + ($keys -join ', '))
  Check ((@($keys).Count -ge 4) -and ($keys -contains 'weight') -and ($keys -contains 'sleep_hours') -and ($keys -contains 'bm') -and ($keys -contains 'kcal')) "R309: the Trends charts drawn here are weight, sleep, bowel type and calories ($(@($keys).Count))"
  # ---- the dates under each chart never run into each other (the user, 31 Oct: "fix the BP date crowding") ----
  $cr = EvalJ @'
(function () {
  var out = {};
  Array.prototype.forEach.call(document.querySelectorAll('#bpChart svg.bpchart, #trends svg.trendchart'), function (svg, i) {
    var name = svg.closest('#bpChart') ? 'bp' : (svg.closest('.tchartwrap') || {}).getAttribute ? svg.closest('.tchartwrap').getAttribute('data-key') : 'chart' + i;
    var boxes = Array.prototype.map.call(svg.querySelectorAll('.txaxis text'), function (t) { return t.getBoundingClientRect(); });
    var overlaps = 0;
    for (var k = 1; k < boxes.length; k++) if (boxes[k].left < boxes[k - 1].right + 2) overlaps++;
    out[name] = { labels: boxes.length, overlaps: overlaps, ticks: svg.querySelectorAll('.txaxis line').length };
  });
  return out;
})()
'@
  Write-Host ("  date labels: " + $cr)
  $crv = $cr | ConvertFrom-Json
  $bad = @($crv.PSObject.Properties | Where-Object { $_.Value.overlaps -gt 0 -or $_.Value.labels -lt 2 })
  Check (($crv.bp.labels -ge 2) -and ($crv.bp.ticks -ge $crv.bp.labels) -and ($bad.Count -eq 0)) "at the whole-window view no two dates under the BP chart or any Trends chart overlap, each still has at least two dates, and every tick mark stays ($(($bad | ForEach-Object { $_.Name }) -join ','))"

  foreach ($k in @($keys) + @('bp')) {
    $wrapSel = if ($k -eq 'bp') { '#bpWrap' } else { "#trends .tchartwrap[data-key=$k]" }
    $btnSel = if ($k -eq 'bp') { '#bpChart .zin' } else { "#trends .tzoomrow[data-key=$k] .zin" }
    for ($i = 0; $i -lt 3; $i++) { [void](TapSel $btnSel) }
    $zjs = @'
(function(){ var w = document.querySelector('WRAPSEL'); if (!w) return { err: 'no wrap' };
  var lab = w.previousElementSibling ? w.previousElementSibling.textContent : '';
  var max = w.scrollWidth - w.clientWidth; w.scrollLeft = Math.round(max / 2); w.dispatchEvent(new Event('scroll'));
  var ax = w.querySelector('.bpyaxis'), wr = w.getBoundingClientRect(), ar = ax ? ax.getBoundingClientRect() : null;
  return { lab: lab, scrolls: max > 0, mid: w.scrollLeft, pinned: !!ar && Math.abs(ar.left - wr.left) <= 1, page: document.documentElement.scrollWidth - window.innerWidth }; })()
'@
    $z = EvalJ ($zjs.Replace('WRAPSEL', $wrapSel))
    $zz = $z | ConvertFrom-Json
    Check (($zz.lab -like ('*8' + [char]0x00D7 + ' wide*')) -and ($zz.scrolls -eq $true) -and ($zz.pinned -eq $true) -and ($zz.page -eq 0)) ("R309: '" + $k + "' zooms to 8x by real taps, scrolls sideways with the value axis pinned at the left, and the page itself does not scroll sideways")
  }
  $kept = EvalJ "(function(){ var w = document.querySelector('#trends .tchartwrap[data-key=weight]'); var before = w.scrollLeft; HT.refresh(); var w2 = document.querySelector('#trends .tchartwrap[data-key=weight]'); return { before: before, after: w2.scrollLeft }; })()"
  Check (($kept | ConvertFrom-Json).before -gt 0 -and [Math]::Abs((($kept | ConvertFrom-Json).before) - (($kept | ConvertFrom-Json).after)) -le 2) "the scroll is kept across a redraw ($kept)"

  # ---- the glucose chart pans (its own zoom, R309: kept) ---------------------------------------------
  $g1 = EvalJ "(function(){ HT.glucoseToggle && HT.glucoseToggle('2026-10-28'); HT.chartPreset('6 h'); var s = document.querySelector('#dayView svg.tchart'); if (!s) return null; s.scrollIntoView({ block: 'center' }); var r = s.getBoundingClientRect(); return { x: r.left + r.width * 0.7, y: r.top + r.height / 2, from: HT.chartWindow().from }; })()"
  $gp = $g1 | ConvertFrom-Json
  if ($gp) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $gp.x; y = $gp.y }) } | Out-Null
    for ($k2 = 1; $k2 -le 6; $k2++) { Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchMove'; touchPoints = @(@{ x = ($gp.x - 0 + 15 * $k2); y = $gp.y }) } | Out-Null }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'pan'
  }
  $g2 = Eval "HT.chartWindow().from"
  Check ($gp -and ([double]$g2 -lt [double]$gp.from)) "the glucose chart pans by a real sideways drag (its window moved back in time), and keeps its own time-window zoom"

  # ---- goal lines -------------------------------------------------------------------------------------
  $gl = EvalJ @'
(function () {
  var muted = getComputedStyle(document.body).getPropertyValue('--muted').trim();
  var probe = document.createElement('span'); probe.style.color = 'var(--muted)'; document.body.appendChild(probe); var mutedRgb = getComputedStyle(probe).color; probe.remove();
  var lines = function (sel) { return Array.prototype.map.call(document.querySelectorAll(sel + ' .tgoal'), function (g) {
    return { label: g.getAttribute('data-goal'), lines: g.querySelectorAll('.tgoalline').length, band: g.querySelectorAll('.tgoalband').length,
             stroke: getComputedStyle(g.querySelector('.tgoalline')).stroke, dash: getComputedStyle(g.querySelector('.tgoalline')).strokeDasharray, text: (g.querySelector('text') || {}).textContent }; }); };
  var out = { mutedRgb: mutedRgb, none: document.querySelectorAll('.tgoal').length };
  HT.graphGoalSet('weight', 80); HT.graphGoalSet('sleep_hours', 7, 8); HT.graphGoalSet('bp', 80, 120); HT.graphGoalSet('glucose', 3.9, 7.8);
  HT.refresh(); HT.chartPreset('24 h');
  out.weight = lines('#trends .tchartwrap[data-key=weight]'); out.sleep = lines('#trends .tchartwrap[data-key=sleep_hours]');
  out.bp = lines('#bpChart'); out.glucose = lines('#dayView .grow');
  out.kcal = lines('#trends .tchartwrap[data-key=kcal]');
  out.words = /on track|off track|too high|too low|well done/i.test(document.getElementById('trends').textContent);
  HT.graphGoalRemove('weight'); HT.refresh();
  out.afterRemove = lines('#trends .tchartwrap[data-key=weight]').length;
  return out;
})()
'@
  Write-Host ("  goals: " + $gl)
  $g = $gl | ConvertFrom-Json
  Check ($g.none -eq 0) "no goal, no line: before any goal is set, no graph draws one"
  Check ((@($g.weight).Count -eq 1) -and ($g.weight[0].lines -eq 1) -and ($g.weight[0].band -eq 0) -and ($g.weight[0].text -eq 'goal 80 kg') -and ($g.weight[0].stroke -eq $g.mutedRgb) -and ($g.weight[0].dash -ne 'none')) "a set goal draws as ONE neutral dashed line, the muted colour, labelled with its value ('goal 80 kg')"
  Check ((@($g.sleep).Count -eq 1) -and ($g.sleep[0].lines -eq 2) -and ($g.sleep[0].band -eq 1) -and ($g.sleep[0].text -like ('goal 7' + [char]0x2013 + '8 h'))) "a band draws as two lines with a faint fill between, labelled 'goal 7-8 h'"
  Check ((@($g.bp).Count -eq 1) -and (@($g.glucose).Count -eq 1) -and ($g.bp[0].stroke -eq $g.mutedRgb) -and ($g.glucose[0].stroke -eq $g.mutedRgb)) "the BP chart and the glucose chart draw their goals the same way, neutral"
  Check ((@($g.kcal).Count -eq 0) -and ($g.words -eq $false) -and ($g.afterRemove -eq 0)) "a graph with no goal has none; no 'on track' or other words about the data; removing a goal removes the line"

  # ---- the backup round trip ----------------------------------------------------------------------------
  $bk = EvalJ "(function(){ var before = JSON.stringify(HT.state().settings.graphGoals); var txt = HT.exportJSON(); window.confirm = function () { return true; }; window.__confirm = true; localStorage.clear(); HT.boot(); var r = HT.restore(txt); return { ok: r.ok, inBackup: !!JSON.parse(txt).settings.graphGoals, same: JSON.stringify(HT.state().settings.graphGoals) === before, keys: Object.keys(HT.state().settings.graphGoals || {}).join(',') }; })()"
  Write-Host ("  backup: " + $bk)
  Check (($bk -like '*"ok":true*') -and ($bk -like '*"inBackup":true*') -and ($bk -like '*"same":true*')) "goals go into the backup and come back byte-identical on restore ($(($bk | ConvertFrom-Json).keys))"

  # ---- the Settings form -----------------------------------------------------------------------------------
  $null = EvalJ "(function(){ HT.openSettings(); var d = document.getElementById('goalsDetails'); if (d) d.open = true; document.getElementById('graphGoals').scrollIntoView({ block: 'center' }); return 1; })()"
  $f1 = EvalJ "(function(){ var k = document.getElementById('ggKey'); k.value = 'weight'; document.getElementById('ggLow').value = '79.5'; document.getElementById('ggHigh').value = ''; return 1; })()"
  $t1 = TapSel '#graphGoals .ggset'
  $f2 = EvalJ "(function(){ var g = HT.state().settings.graphGoals.weight; var rm = document.querySelector('#graphGoals .ggrow[data-key=weight] .ggrm'); var set = document.querySelector('#graphGoals .ggset'); return { low: g ? g.low : null, rmH: rm ? Math.round(rm.getBoundingClientRect().height) : 0, setH: Math.round(set.getBoundingClientRect().height) }; })()"
  $t2 = TapSel '#graphGoals .ggrow[data-key=weight] .ggrm'
  $f3 = Eval "!(HT.state().settings.graphGoals || {}).weight"
  Write-Host ("  settings: " + $f2 + " removed=" + $f3)
  Check ($t1 -and ($f2 -like '*"low":79.5*') -and ($f2 -like '*"rmH":4[4-9]*' -or $f2 -like '*"rmH":[5-9][0-9]*') -and $t2 -and ($f3 -eq $true)) "in Settings -> Goals a real tap sets a line and another removes it; both controls are 44 px"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("GRAPHS GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "GRAPHS GATE: PASS -- every graph zooms and scrolls, and the user's own goals draw as neutral lines that survive a backup"
Write-Host "GATE: PASS"
exit 0
