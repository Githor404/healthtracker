# R262 + R265.1 -- THE WEEKLY REVIEW, AND THE DAY RING'S TWO STATES. By real taps at 390 px.
#
#   "This week" under the 7-day row opens a Monday-to-Sunday review; a step goes
#   back a week. Its rings and numbers are checked against a fixture: one clean
#   noon meal a day rising 3.0 last week and 1.0 in the ten days before, so the
#   calculated probability is 100 % "higher than typical" with its n; fasting by
#   the 12 h rule (noon to noon, 24 h); alcohol-free 2 of 7, not gold with rewards
#   off; sleep hidden with no sleep data. The basis is behind a 44 px info button;
#   every word is 16 px or more and nothing runs off the side; opening, stepping
#   and closing write nothing. Then the day ring: the running span orange, the
#   key naming eating (green) and fasting (orange).
#
# Synthetic data only. Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8337
$Dbg = 9543
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-weekly-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set WEEKLY_SHOTS=1 to save 390px screenshots to %TEMP%\weekly-shots.
$shots = $null
if ($env:WEEKLY_SHOTS) { $shots = Join-Path $env:TEMP 'weekly-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.weekReviewHTML === 'function' && typeof HT.openWeek === 'function' && typeof HT.fastGaps === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R262/R265.1 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: LAST WEEK (Mon-Sun) one clean noon meal a day, a rise of 3.0;
  # the 10 days before it a rise of 1.0; two "No alcohol today" marks. Saved, reloaded.
  [void](Eval @'
(function () {
  var S = HT.state();
  var mon = HT.shiftDate(HT.weekMonday(HT.todayKey()), -7);
  var G = {};
  var day = function (dk, R) {
    var t = [], v = [];
    for (var m = 0; m < 1440; m += 5) { t.push(m); v.push(m < 720 || m > 900 ? 5.0 : (m <= 780 ? 5.0 + R * (m - 720) / 60 : 5.0 + R * (900 - m) / 120)); }
    G[dk] = { u: 'mmol/L', t: t, v: v };
    S.days[dk] = { status: 'complete', water_l: 0, items: [{ name: 'Gate noon', meal: 'lunch', time: '12:00', kcal: 500, protein_g: 20, fat_g: 15, carb_g: 60, fiber_g: 5, soluble_fiber_g: 1, confidence: 'eyeballed', source: 'manual', notes: '' }] };
  };
  for (var i = 0; i < 7; i++) day(HT.shiftDate(mon, i), 3.0);
  for (var j = 1; j <= 10; j++) day(HT.shiftDate(mon, -j), 1.0);
  HT.glucoseWrite(G);
  HT.resave();
  HT.addSignal({ type: 'no_alcohol', value: 0, unit: 'drinks', source: 'quick', date: HT.shiftDate(mon, 5), time: '20:00' });
  HT.addSignal({ type: 'no_alcohol', value: 0, unit: 'drinks', source: 'quick', date: HT.shiftDate(mon, 6), time: '20:00' });
  return 1;
})()
'@)
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  WaitBoot
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  Settle

  # A REAL TAP: scroll the element into view, press and release at its centre.
  function TapSel([string]$sel) {
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, h: Math.round(r.height), w: Math.round(r.width) }; })()")
    $pv = $p | ConvertFrom-Json
    if (-not $pv) { return $null }
    Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $pv.x; y = $pv.y; button = 'left'; clickCount = 1 } | Out-Null
    Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $pv.x; y = $pv.y; button = 'left'; clickCount = 1 } | Out-Null
    Settle
    return $pv
  }
  $snap0 = Eval "JSON.stringify(Object.keys(localStorage).sort().map(function (k) { return k + '=' + localStorage.getItem(k); }))"

  # ---- 1. "This week" under the 7-day row opens the review ------------------------------
  $l = TapSel '#rhythmGrid .weeklink'
  $o1 = EvalJ @'
(function () {
  var p = document.getElementById('weekPanel'), t = document.querySelector('#weekBody .wktitle');
  return { shown: !!p && getComputedStyle(p).display !== 'none', title: t ? t.textContent : '', want: 'Week of ' + HT.fmtDateSmart(HT.weekMonday(HT.todayKey()), false),
           locked: HT.overlaySync().locked, grid: !!document.querySelector('#rhythmGrid .weeklink') && !!document.querySelector('#rhythmGrid .rgrid') &&
             document.querySelector('#rhythmGrid .weeklink').getBoundingClientRect().top >= document.querySelector('#rhythmGrid .rgrid').getBoundingClientRect().bottom - 1 };
})()
'@
  Write-Host ("  open: " + $o1)
  $o1v = $o1 | ConvertFrom-Json
  Check ($l -and ($l.h -ge 44) -and $o1v.shown -and ($o1v.title -eq $o1v.want) -and $o1v.locked -and $o1v.grid) "R262 GATE: the 'This week' link sits UNDER the 7-day row, is 44 px tall, and one real tap opens this week's review ('$($o1v.title)') over a locked page"

  # ---- 2. back one week: the rings and the numbers ------------------------------------------
  [void](TapSel '#weekBody .wkstep[aria-label="previous week"]')
  $o2 = EvalJ @'
(function () {
  var mon = HT.shiftDate(HT.weekMonday(HT.todayKey()), -7);
  var cells = Array.prototype.slice.call(document.querySelectorAll('#weekBody .wkcell'));
  var box = function (e) { var r = e.querySelector('.wkringbox').getBoundingClientRect(); return { w: Math.round(r.width), top: Math.round(r.top), left: Math.round(r.left) }; };
  var txt = function (sel) { var e = document.querySelector(sel); return e ? e.innerText.replace(/\s+/g, ' ').trim() : ''; };
  return { title: txt('#weekBody .wktitle'), want: 'Week of ' + HT.fmtDateSmart(mon, false),
           rings: cells.map(function (c) { return c.getAttribute('data-ring'); }), boxes: cells.map(box),
           meal: txt('#weekBody [data-ring="meals"] .wkcentre'), fast: txt('#weekBody [data-ring="fasting"] .wkcentre'), af: txt('#weekBody [data-ring="alcohol"] .wkcentre'),
           mealSub: txt('#weekBody [data-ring="meals"] .wksub'), afSub: txt('#weekBody [data-ring="alcohol"] .wksub'),
           head: txt('#weekBody .wkhead'), cov: txt('#weekBody .wkcov'), prob: txt('#weekBody [data-card="meals"] .wkprob'),
           fastCard: txt('#weekBody [data-card="fasting"] .wkline'), fastItems: document.querySelectorAll('#weekBody .wkfasts li').length,
           unlogged: txt('#weekBody .wkunlogged'),
           runH: (Date.now() - new Date(HT.shiftDate(HT.weekMonday(HT.todayKey()), -1) + 'T12:00:00').getTime()) / 3600000,
           curves: [document.querySelectorAll('#weekBody .wkcurve .wkthis').length, document.querySelectorAll('#weekBody .wkcurve .wktyp').length],
           afStroke: (function () { var a = document.querySelector('#weekBody [data-ring="alcohol"] .wkarc'); return a ? getComputedStyle(a).stroke : ''; })(),
           gold: (function () { var d = document.createElement('div'); d.style.color = 'var(--gold)'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; })(),
           foot: txt('#weekBody .wkfoot') };
})()
'@
  Write-Host ("  last week: " + $o2)
  $o2v = $o2 | ConvertFrom-Json
  Check (($o2v.title -eq $o2v.want) -and ((@($o2v.rings) -join ',') -eq 'meals,fasting,alcohol')) "R262 GATE: the step button goes back one week ('$($o2v.title)'); three rings -- meal responses, fasting, alcohol-free -- and SLEEP HIDDEN with no sleep data"
  $b = @($o2v.boxes)
  Check (($b.Count -eq 3) -and ($b[0].top -eq $b[1].top) -and ($b[2].top -gt $b[0].top) -and (@($b | Where-Object { $_.w -lt 120 -or $_.w -gt 150 }).Count -eq 0)) ("R262: the rings sit two to a row, each 120-150 px (" + ((@($b) | ForEach-Object { $_.w }) -join ',') + ")")
  Check (($o2v.meal -eq '3 mmol/L median rise') -and ($o2v.mealSub -eq '7 of 7 meals measured') -and ($o2v.prob -like 'A meal this week rose more than a typical meal 100% of the time (calculated; n 7 this week, 10 typical)*higher than typical.')) "R260 GATE: meal responses -- median 3 against the typical days, and the probability is CALCULATED, of one stated thing, with its n and its word ('$($o2v.prob)')"
  # R269 #2: the span after the fixture's last meal (last Sunday noon) runs to now. Under
  # 48 h it is the fast still running; from 48 h it is an UNLOGGED GAP, listed apart and
  # not counted -- which of the two depends on the day the gate runs, so both are checked.
  if ([double]$o2v.runH -lt 48) {
    Check (($o2v.fast -eq '24h longest fast') -and ($o2v.fastCard -like '7 fasts of 12 h or more, and one still running*') -and ($o2v.fastItems -eq 8) -and (-not $o2v.unlogged)) "R265.1 GATE: fasting by the 12 h rule -- noon to noon, longest 24 h, seven listed start to end plus the span still running (listed 'so far'), nothing asked ('$($o2v.fastCard)')"
  } else {
    Check (($o2v.fast -eq '24h longest fast') -and ($o2v.fastCard -like '7 fasts of 12 h or more*') -and ($o2v.fastCard -notlike '*still running*') -and ($o2v.fastItems -eq 8) -and ($o2v.unlogged -like 'One gap of 48 h or more with no food logged*not counted as fasting.')) "R265.1 + R269 GATE: fasting by the 12 h rule -- noon to noon, longest 24 h, seven fasts listed; the span since the last meal is past 48 h, so it is an UNLOGGED GAP, listed apart and not counted ('$($o2v.fastCard)' / '$($o2v.unlogged)')"
  }
  Check (($o2v.af -eq '2 days') -and ($o2v.afSub -eq '2 of 7 days') -and ($o2v.afStroke -ne $o2v.gold)) "R226/R262: alcohol-free 2 of 7 -- and with rewards OFF the ring is NOT gold and shows no run"
  Check (($o2v.head -like '*: food logged 7 of 7 days, glucose 7 of 7; 7 meals with a measured rise; 2 alcohol-free days; longest fast 24 h.') -and ($o2v.cov -eq ('food logged 7 of 7 days ' + [char]0x00b7 + ' glucose 7 of 7')) -and ((@($o2v.curves) -join ',') -eq '1,1')) "R262: the headline and the coverage line are assembled from the numbers; the meal card draws this week solid and typical dashed"
  Check (($o2v.foot -eq 'Your own data, computed on this phone. No scores.') -and -not ($o2v.head + $o2v.prob + $o2v.fastCard -match '(?i)\bshould\b|\bgood\b|\bbad\b|well done|great')) "R260: no 'should', no verdict word; the footer says no scores"
  Shot 'week-last'

  # ---- 3. the information button, and the page at 390 px --------------------------------------
  [void](TapSel '#weekBody [data-card="meals"] .wkinfosum')
  $o3 = EvalJ @'
(function () {
  var s = document.querySelector('#weekBody [data-card="meals"] .wkinfosum'), b = document.querySelector('#weekBody [data-card="meals"] .wkinfobody');
  var all = Array.prototype.slice.call(document.querySelectorAll('#weekPanel *')).filter(function (e) { var r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && Array.prototype.some.call(e.childNodes, function (n) { return n.nodeType === 3 && n.textContent.trim(); }); });
  var small = all.filter(function (e) { return parseFloat(getComputedStyle(e).fontSize) < 16; }).map(function (e) { return e.tagName + '.' + e.className + ':' + getComputedStyle(e).fontSize; });
  var svgT = Array.prototype.map.call(document.querySelectorAll('#weekPanel svg text'), function (t) { return t.getBoundingClientRect().height; });
  var btns = Array.prototype.map.call(document.querySelectorAll('#weekPanel button, #weekPanel summary'), function (e) { var r = e.getBoundingClientRect(); return Math.round(Math.min(r.height, Math.max(r.width, 44))); });
  var wrap = document.querySelector('#weekPanel .wrap');
  return { h: Math.round(s.getBoundingClientRect().height), seen: b.getBoundingClientRect().height > 0, text: b.textContent,
           small: small, btnMin: Math.min.apply(null, btns), wide: wrap.scrollWidth - wrap.clientWidth, pageWide: document.documentElement.scrollWidth - document.documentElement.clientWidth };
})()
'@
  Write-Host ("  info and layout: " + $o3)
  $o3v = $o3 | ConvertFrom-Json
  Check (($o3v.h -ge 44) -and $o3v.seen -and ($o3v.text -like '*every pair*no evidence grade*5 or more meals on each side*no clear change*Main uncertainty*')) "R260 GATE: the info button (44 px) opens the basis -- what the probability is OF, own data with no grade, the n 5 floor, the 40-60 % words, the main uncertainty"
  Check ((@($o3v.small).Count -eq 0) -and ($o3v.btnMin -ge 44) -and ($o3v.wide -le 0) -and ($o3v.pageWide -le 0)) ("R262: at 390 px every word is 16 px or more, every control 44 px, and nothing runs off the side (small: " + (@($o3v.small) -join ';') + ")")
  Shot 'week-info'

  # ---- 4. close: nothing was written --------------------------------------------------------------
  [void](TapSel '#weekPanel .sheetx')
  $o4 = EvalJ "(function(){ var p = document.getElementById('weekPanel'); return { hidden: getComputedStyle(p).display === 'none', locked: HT.overlaySync().locked }; })()"
  $snap1 = Eval "JSON.stringify(Object.keys(localStorage).sort().map(function (k) { return k + '=' + localStorage.getItem(k); }))"
  $o4v = $o4 | ConvertFrom-Json
  Check ($o4v.hidden -and -not $o4v.locked -and ($snap0 -eq $snap1)) "R262 GATE: closed, the page is unlocked -- and opening, stepping, the info button and closing wrote NOTHING to storage"

  # ---- 5. the day ring: eating green, fasting orange, named in the key ------------------------
  [void](Eval "(function(){ var d = new Date(Date.now() - 14 * 3600000), p = function (n) { return ('0' + n).slice(-2); }; var dk = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()); var S = HT.state(); S.days[dk] = S.days[dk] || { status: 'in_progress', water_l: 0, items: [] }; S.days[dk].items.push({ name: 'Gate supper', meal: 'dinner', time: p(d.getHours()) + ':' + p(d.getMinutes()), kcal: 600, protein_g: 30, fat_g: 20, carb_g: 60, fiber_g: 6, soluble_fiber_g: 1, confidence: 'eyeballed', source: 'manual', notes: '' }); HT.resave(); HT.goToDay(HT.todayKey()); HT.refresh(); return 1; })()")
  Settle
  [void](TapSel '#dayView .ringkeybtn')
  $o5 = EvalJ @'
(function () {
  var hue = function (v) { var d = document.createElement('div'); d.style.color = 'var(' + v + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; };
  var open = document.querySelector('#dayView path.ra-open');
  var openDash = open ? getComputedStyle(open).strokeDasharray : ''; var openOp = open ? getComputedStyle(open).opacity : '';
  var keys = Array.prototype.map.call(document.querySelectorAll('#dayView .rlkey'), function (k) { return { t: k.textContent.trim(), sw: getComputedStyle(k.querySelector('.rlswatch')).backgroundColor }; });
  var k = function (t) { return (keys.filter(function (x) { return x.t === t; })[0] || {}).sw || ''; };
  return { openDash: openDash, openOp: openOp, open: open ? getComputedStyle(open).stroke : '', fasting: hue('--lane-fasting'), eating: hue('--lane-eat'), kEat: k('eating'), kFast: k('fasting'),
           centre: (document.querySelector('#dayView .rcline') || {}).textContent || '' };
})()
'@
  Write-Host ("  day ring: " + $o5)
  $o5v = $o5 | ConvertFrom-Json
  Check (($o5v.open -eq $o5v.fasting) -and ($o5v.openDash -eq 'none') -and ($o5v.openOp -eq '1') -and ($o5v.kFast -eq $o5v.fasting) -and ($o5v.kEat -eq $o5v.eating) -and ($o5v.fasting -ne $o5v.eating) -and ($o5v.centre -match 'fasting')) "R265.1 GATE: 14 h after the last food the running span is drawn SOLID ORANGE and the centre says fasting; the key names 'eating' in green and 'fasting' in orange"
  Shot 'day-ring'
  if ($shots) { Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null; Settle; Shot 'day-ring-light'; [void](Eval "HT.openWeek(HT.shiftDate(HT.weekMonday(HT.todayKey()), -7))"); Settle; Shot 'week-light' }

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("WEEKLY GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "WEEKLY GATE: PASS -- 'This week' under the 7-day row opens a Monday-to-Sunday review; the rings"
Write-Host "  and numbers match a fixture, the probability is calculated with its n and basis, sleep is hidden"
Write-Host "  without data, nothing is written, the page fits 390 px; the day ring is green and orange, named."
Write-Host "GATE: PASS"
exit 0
