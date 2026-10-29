# R251.2 -- BLOOD PRESSURE, ONE CHART. By real taps at 390 px.
#
#   Systolic and diastolic on one mmHg axis, each reading at its true time, the
#   pulse pressure a neutral band between them; faint reference lines at 135 and 85,
#   labelled, with Hypertension Canada 2020 cited behind an info button (and the
#   2025 edition's 130/80 said there); no verdict colours or words; the two lines
#   told apart without colour; gaps not joined; a tap reads both values and the
#   pulse pressure. The ruled gate: three readings on one day and one the next.
#
# Synthetic readings only. Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8325
$Dbg = 9531
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-bpchart-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set BPCHART_SHOTS=1 to save 390px screenshots to %TEMP%\bpchart-shots.
$shots = $null
if ($env:BPCHART_SHOTS) { $shots = Join-Path $env:TEMP 'bpchart-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.bpChartHTML === 'function' && typeof HT.bpReadings === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R251.2 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: synthetic readings, saved and reloaded --------------------------------
  # Yesterday 07:10 128/82, 13:00 141/88 (above both reference lines), 21:30 122/79;
  # today 08:10 131/84; and one six days ago, 07:00 125/80, which is a gap.
  [void](Eval @'
(function () {
  var S = HT.state();
  var key = function (dd) { var d = new Date(); d.setDate(d.getDate() + dd); return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); };
  var pair = function (dd, time, sv, dv) {
    var k = key(dd);
    (S.timeline[k] = S.timeline[k] || []).push(
      HT.normalizeSignal({ type: 'bp_systolic', value: sv, unit: 'mmHg', time: time, source: 'manual' }),
      HT.normalizeSignal({ type: 'bp_diastolic', value: dv, unit: 'mmHg', time: time, source: 'manual' }));
  };
  pair(-6, '07:00', 125, 80);
  pair(-1, '07:10', 128, 82);
  pair(-1, '13:00', 141, 88);
  pair(-1, '21:30', 122, 79);
  pair(0, '08:10', 131, 84);
  HT.resave();
  return 1;
})()
'@)
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  WaitBoot
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  [void](Eval "(function(){ var c = document.getElementById('bpChart'); if (c) c.scrollIntoView({ block: 'center' }); return 1; })()")
  Settle

  # ---- 1. ONE CHART, BOTH VALUES, TRUE TIMES ------------------------------------------------
  $c0 = EvalJ @'
(function () {
  var root = document.getElementById('trends');
  var heads = Array.prototype.map.call(root.querySelectorAll('.thead'), function (h) { return h.textContent.replace(/\s+/g, ' ').trim(); });
  var svg = document.querySelector('#bpChart svg.bpchart');
  if (!svg) return { heads: heads, svg: false };
  var cx = function (el) { var r = el.getBoundingClientRect(); return r.left + r.width / 2; };
  var sys = Array.prototype.slice.call(svg.querySelectorAll('.bpmsys')), dia = Array.prototype.slice.call(svg.querySelectorAll('.bpmdia'));
  var xs = sys.map(cx);
  return { heads: heads, svg: true, nsys: sys.length, ndia: dia.length, ratio: (xs[2] - xs[1]) / (xs[3] - xs[1]),
           band: svg.querySelectorAll('.bpband').length, lsys: svg.querySelectorAll('.bpsys').length, ldia: svg.querySelectorAll('.bpdia').length,
           scale: svg.getBoundingClientRect().width / svg.viewBox.baseVal.width };
})()
'@
  Write-Host ("  chart: " + $c0)
  $c0v = $c0 | ConvertFrom-Json
  $bpHeads = @($c0v.heads | Where-Object { $_ -like 'BP *' -or $_ -like 'Blood pressure*' })
  Check ($c0v.svg -and ($bpHeads.Count -eq 1) -and ($bpHeads[0] -eq 'Blood pressure mmHg')) "R251.2: Trends draws ONE blood pressure chart, in mmHg -- the two separate BP rows are gone"
  Check (($c0v.nsys -eq 5) -and ($c0v.ndia -eq 5) -and ([math]::Abs($c0v.ratio - (350.0 / 860.0)) -lt 0.02)) ("R251.2 GATE: three readings on one day and one the next, at TRUE TIMES -- 13:00 sits 350/860 of the way from 07:10 to 21:30 (" + [math]::Round($c0v.ratio, 3) + ")")
  Check (($c0v.band -eq 1) -and ($c0v.lsys -eq 1) -and ($c0v.ldia -eq 1)) "R251.2 GATE: the pulse-pressure BAND between the lines; the reading six days earlier is not joined to them (a gap, one line each)"

  # ---- 2. THE REFERENCE LINES, AND NO VERDICT --------------------------------------------------
  $c1 = EvalJ @'
(function () {
  var svg = document.querySelector('#bpChart svg.bpchart');
  var cs = function (el, p) { return getComputedStyle(el)[p]; };
  var uniq = function (a) { return a.filter(function (x, i) { return a.indexOf(x) === i; }); };
  var sys = Array.prototype.slice.call(svg.querySelectorAll('.bpmsys')), dia = Array.prototype.slice.call(svg.querySelectorAll('.bpmdia'));
  var refT = Array.prototype.map.call(svg.querySelectorAll('.bpref text'), function (t) { return t.textContent; });
  var y = function (sel) { var e = svg.querySelector(sel); return e ? Number(e.getAttribute('y1')) : -1; };
  var texts = Array.prototype.slice.call(svg.querySelectorAll('text'));
  var gy = function (v) { var g = svg.querySelectorAll('.bpgrid line')[(v - 40) / 20]; return g ? Number(g.getAttribute('y1')) : -1; };
  return { refs: refT, y135: y('.bpref line[data-ref="135"]'), y140: gy(140), y120: gy(120), y80: gy(80), y100: gy(100), y85: y('.bpref line[data-ref="85"]'),
           sysFill: uniq(sys.map(function (e) { return cs(e, 'fill') + '|' + cs(e, 'stroke'); })),
           diaFill: uniq(dia.map(function (e) { return cs(e, 'fill') + '|' + cs(e, 'stroke'); })),
           bandFill: cs(svg.querySelector('.bpband'), 'fill'), ink: cs(svg, 'color'),
           dashSys: cs(svg.querySelector('.bpsys'), 'strokeDasharray'), dashDia: cs(svg.querySelector('.bpdia'), 'strokeDasharray'),
           names: Array.prototype.map.call(document.querySelectorAll('#bpChart .bplegend .bpleglab'), function (t) { return t.textContent; }).slice(0, 2),
           legPx: parseFloat(getComputedStyle(document.querySelector('#bpChart .bplegend')).fontSize),
           refRight: Array.prototype.every.call(svg.querySelectorAll('.bpref text'), function (t) { return Number(t.getAttribute('x')) >= Number(svg.getAttribute('data-padl')) + Number(svg.getAttribute('data-plotw')); }),
           minPx: Math.min.apply(null, texts.map(function (t) { return parseFloat(cs(t, 'fontSize')); })),
           wide: document.documentElement.scrollWidth - document.documentElement.clientWidth };
})()
'@
  Write-Host ("  lines and ink: " + $c1)
  $c1v = $c1 | ConvertFrom-Json
  Check ((@($c1v.refs) -contains '135 ref') -and (@($c1v.refs) -contains '85 ref') -and ($c1v.y135 -gt $c1v.y140) -and ($c1v.y135 -lt $c1v.y120) -and ($c1v.y85 -gt $c1v.y100) -and ($c1v.y85 -lt $c1v.y80)) "R251.2 GATE: faint reference lines at 135 and 85, each labelled, at their place on the mmHg axis"
  Check ((@($c1v.sysFill).Count -eq 1) -and (@($c1v.diaFill).Count -eq 1) -and ($c1v.bandFill -eq $c1v.ink)) ("R251.2 GATE: NO COLOUR CHANGE -- 141/88, above both lines, is drawn in the same ink as every other reading, and the band is that ink too (" + (@($c1v.sysFill) -join ';') + ")")
  Check (($c1v.dashSys -eq 'none') -and ($c1v.dashDia -ne 'none') -and ((@($c1v.names) -join ',') -eq 'Systolic,Diastolic') -and ($c1v.legPx -ge 16) -and $c1v.refRight) "R251.2: the lines are told apart WITHOUT colour -- solid with circles, dashed with squares, named in a legend with a sample of each; the reference labels sit in their own margin, clear of the readings"
  Check (($c1v.minPx -ge 16) -and ([math]::Abs($c0v.scale - 1) -lt 0.02) -and ($c1v.wide -le 0)) "every word on the chart is 16px or more, drawn at its own size, and nothing runs off the side at 390 px"

  # ---- 3. A REAL TAP on the 13:00 reading, then the step buttons ------------------------------------------
  $pt = EvalJ "(function(){ var e = document.querySelectorAll('#bpChart .bpmsys')[2]; var r = e.getBoundingClientRect(); var h = document.querySelector('#bpChart .bphit').getBoundingClientRect(); return { x: r.left + r.width / 2 + 2, y: r.top + r.height / 2, hh: Math.round(h.height) }; })()"
  $ptv = $pt | ConvertFrom-Json
  Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $ptv.x; y = $ptv.y; button = 'left'; clickCount = 1 } | Out-Null
  Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $ptv.x; y = $ptv.y; button = 'left'; clickCount = 1 } | Out-Null
  Settle
  $c2 = EvalJ "(function(){ var d = new Date(); d.setDate(d.getDate() - 1); var M = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']; var o = document.querySelector('#bpChart .bpreadout'); return { text: o.textContent, want: '141/88 mmHg \u00b7 pulse pressure 53 \u00b7 ' + M[d.getMonth()] + ' ' + d.getDate() + ' 13:00 \u00b7 entered by hand', px: parseFloat(getComputedStyle(o).fontSize), h: Math.round(o.getBoundingClientRect().height), cross: document.querySelectorAll('#bpChart .tcross').length }; })()"
  Write-Host ("  tap: " + $c2)
  $c2v = $c2 | ConvertFrom-Json
  Check (($c2v.text -eq $c2v.want) -and ($c2v.cross -eq 1) -and ($c2v.px -ge 16) -and ($ptv.hh -ge 44)) "R251.2 GATE: A TAP SHOWS BOTH VALUES AND THE PULSE PRESSURE -- '141/88 mmHg . pulse pressure 53 . <date> 13:00 . entered by hand', from a real tap on the marker, with a crosshair"
  # Found by this gate: a tap 15 px off picked 21:30 -- on a week at 390 px the day's
  # readings are ~15 px apart. The step buttons give every reading a 44 px way in.
  $st = EvalJ "(function(){ var b = document.querySelectorAll('#bpChart .bpstep'); return Array.prototype.map.call(b, function (x) { var r = x.getBoundingClientRect(); return Math.round(Math.min(r.width, r.height)); }); })()"
  [void](Eval "document.querySelectorAll('#bpChart .bpstep')[1].click()")
  Settle
  $n1 = Eval "document.querySelector('#bpChart .bpreadout').textContent"
  [void](Eval "document.querySelectorAll('#bpChart .bpstep')[0].click()")
  Settle
  $n0 = Eval "document.querySelector('#bpChart .bpreadout').textContent"
  Write-Host ("  step: " + $st + " / next: " + $n1 + " / back: " + $n0)
  Check ((($st | ConvertFrom-Json) | Where-Object { $_ -lt 44 }).Count -eq 0 -and ($n1 -like '122/79 mmHg*21:30*') -and ($n0 -eq $c2v.want)) "R251.2: readings close together are each reached by the 44 px step buttons -- next is 21:30, back is 13:00 again"
  Shot 'bp-chart'

  # ---- 4. THE SOURCE OF THE LINES, behind the info button --------------------------------------
  [void](Eval "document.querySelector('#bpChart .bprefsum').click()")
  Settle
  $c3 = EvalJ "(function(){ var s = document.querySelector('#bpChart .bprefsum'), b = document.querySelector('#bpChart .bprefbody'); return { h: Math.round(s.getBoundingClientRect().height), seen: b.getBoundingClientRect().height > 0, text: b.textContent }; })()"
  $c3v = $c3 | ConvertFrom-Json
  Check (($c3v.h -ge 44) -and $c3v.seen -and ($c3v.text -like '*Hypertension Canada*2020 edition*Can J Cardiol 2020;36(5):596*2025*130/80*CMAJ 2025;197:E549*')) "R251.2: the info button (44 px) opens the source -- Hypertension Canada 2020, cited, and that the 2025 guideline lowered the threshold to 130/80"
  Shot 'bp-ref'

  # ---- 5. EXPAND AND SCROLL (the user's request, 28 Oct) -------------------------------------
  # Zoom in draws the chart wider than the screen in a frame that scrolls sideways,
  # opened at the newest readings, the mmHg axis pinned at the left; a tap still
  # picks the nearest reading; a redraw keeps the scroll; zoom out is the whole window.
  $zs = "(function(){ try { var w = document.getElementById('bpWrap'), svg = w.querySelector('svg.bpchart'), ax = w.querySelector('svg.bpyaxis'); var wr = w.getBoundingClientRect(); var ms = Array.prototype.slice.call(svg.querySelectorAll('.bpmsys')); var inView = function (e) { var r = e.getBoundingClientRect(); return r.left >= wr.left + 40 && r.right <= wr.right; }; var zb = Array.prototype.map.call(document.querySelectorAll('#bpChart .bpzoom'), function (b) { var r = b.getBoundingClientRect(); return Math.round(Math.min(r.width, r.height)); }); return { scroll: w.classList.contains('bpscroll'), svgW: Math.round(svg.getBoundingClientRect().width), wrapW: Math.round(wr.width), sl: Math.round(w.scrollLeft), max: w.scrollWidth - w.clientWidth, newest: inView(ms[ms.length - 1]), oldest: inView(ms[0]), axis: ax ? Math.round(ax.getBoundingClientRect().left - wr.left) : -1, axisText: ax ? ax.querySelectorAll('text').length : 0, lab: document.querySelector('#bpChart .bpzoomlab').textContent, zb: zb, page: document.documentElement.scrollWidth - document.documentElement.clientWidth }; } catch (e) { return { err: String(e && e.stack || e), html: (document.getElementById('bpChart') || {}).className || 'no bpChart' }; } })()"
  $z0 = EvalJ "(function(){ var r = document.querySelector('#bpChart svg.bpchart').getBoundingClientRect(); return Math.round(r.width); })()"
  [void](Eval "document.querySelector('#bpChart .bpzoom[aria-label=\'zoom in\']').click()")
  Settle
  $z1 = EvalJ $zs
  Write-Host ("  zoom 2x: fit width " + $z0 + " -> " + $z1)
  $z1v = $z1 | ConvertFrom-Json
  Check ($z1v.scroll -and ($z1v.svgW -ge (2 * [int]$z0 - 2)) -and ($z1v.max -gt 0) -and ($z1v.sl -ge $z1v.max - 1) -and $z1v.newest -and ($z1v.axis -eq 0) -and ($z1v.axisText -eq 9) -and ($z1v.page -le 0) -and ((@($z1v.zb) | Where-Object { $_ -lt 44 }).Count -eq 0) -and ($z1v.lab -like '2*wide*scroll sideways*')) "BP EXPAND: zoom in (44 px) draws the chart twice as wide in a frame that scrolls sideways -- opened at the newest reading, the mmHg axis pinned at the left, the page itself not wider"
  [void](Eval "document.querySelector('#bpChart .bpzoom[aria-label=\'zoom in\']').click()")
  Settle
  [void](Eval "document.querySelector('#bpChart .bpzoom[aria-label=\'zoom in\']').click()")
  Settle
  $wr = EvalJ "(function(){ var w = document.getElementById('bpWrap'); w.scrollIntoView({ block: 'center' }); var r = w.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + 120 }; })()" | ConvertFrom-Json
  # A real input event that scrolls the frame: a horizontal wheel (trackpad) on it.
  # (Emulated touch swipes in headless Chrome trigger its history back-swipe and
  # leave the page, so they cannot stand for a finger here; the frame's touch-action
  # is asserted instead -- pan-x is what lets a finger scroll it on the phone.)
  function Swipe([double]$x0, [double]$y0, [double]$dx) {
    for ($rep = 0; $rep -lt 12; $rep++) {
      Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mouseWheel'; x = $x0; y = $y0; deltaX = (-1 * $dx); deltaY = 0 } | Out-Null
      Start-Sleep -Milliseconds 60 } }
  $ta = Eval "(function(){ var s = document.querySelector('#bpWrap svg.bpchart'); return getComputedStyle(s).touchAction + ' / ' + getComputedStyle(s.querySelector('.bphit')).touchAction; })()"
  Write-Host ("  touch-action: " + $ta)
  Check ($ta -like 'pan-x pan-y*') "BP SCROLL: zoomed, the chart lets a finger pan sideways (touch-action pan-x) as well as scroll the page"
  Swipe ($wr.x - 120) $wr.y 260
  Settle
  $z2 = EvalJ $zs
  Write-Host ("  zoom 8x, swiped to the start: " + $z2)
  $z2v = $z2 | ConvertFrom-Json
  Check (($z2v.svgW -ge (8 * [int]$z0 - 8)) -and ($z2v.sl -le 1) -and $z2v.oldest -and (-not $z2v.newest) -and ($z2v.axis -eq 0) -and ($z2v.page -le 0)) "BP SCROLL: at 8x a real sideways scroll (wheel input on the frame) goes back to the oldest reading (six days ago), the newest now off screen, the axis still pinned"
  Shot 'bp-zoom-oldest'
  # back to the newest by a swipe the other way, then a real tap on the 13:00 reading
  Swipe ($wr.x + 120) $wr.y -260
  Settle
  $pz = EvalJ "(function(){ var e = document.querySelectorAll('#bpChart .bpmsys')[2]; e.scrollIntoView({ block: 'nearest', inline: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + r.width / 2 + 6, y: r.top + r.height / 2 }; })()" | ConvertFrom-Json
  Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $pz.x; y = $pz.y; button = 'left'; clickCount = 1 } | Out-Null
  Invoke-CDP 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $pz.x; y = $pz.y; button = 'left'; clickCount = 1 } | Out-Null
  Settle
  $z3 = EvalJ "(function(){ var w = document.getElementById('bpWrap'); return { text: document.querySelector('#bpChart .bpreadout').textContent, sl: Math.round(w.scrollLeft) }; })()"
  [void](Eval "HT.renderTrends()")
  Settle
  $z4 = EvalJ "(function(){ var w = document.getElementById('bpWrap'); return { sl: Math.round(w.scrollLeft), cross: document.querySelectorAll('#bpChart .tcross').length }; })()"
  Write-Host ("  zoomed tap: " + $z3 + " after a redraw: " + $z4)
  $z3v = $z3 | ConvertFrom-Json; $z4v = $z4 | ConvertFrom-Json
  Check (($z3v.text -like '141/88 mmHg*13:00*') -and ([Math]::Abs($z4v.sl - $z3v.sl) -le 2) -and ($z4v.cross -eq 1)) "BP EXPAND: zoomed, a real tap picks the 13:00 reading, and a redraw of Trends keeps where the chart was scrolled to"
  Shot 'bp-zoom-tap'
  for ($k = 0; $k -lt 3; $k++) { [void](Eval "document.querySelector('#bpChart .bpzoom[aria-label=\'zoom out\']').click()"); Settle }
  $z5 = EvalJ "(function(){ var w = document.getElementById('bpWrap'); var s = w.querySelector('svg.bpchart'); return { scroll: w.classList.contains('bpscroll'), fits: s.getBoundingClientRect().width <= w.getBoundingClientRect().width + 1, axis: !!w.querySelector('svg.bpyaxis'), out: document.querySelector('#bpChart .bpzoom[aria-label=\'zoom out\']').disabled, lab: document.querySelector('#bpChart .bpzoomlab').textContent }; })()"
  Check ($z5 -like '*"scroll":false,"fits":true,"axis":false,"out":true,"lab":"Whole window"*') ("BP EXPAND: zoom out returns to the whole window, nothing to scroll (" + $z5 + ")")

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("BP CHART GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "BP CHART GATE: PASS -- one chart, both values at true times, the pulse-pressure band,"
Write-Host "  135/85 labelled and cited, no colour change, a tap reads both values and the pulse pressure."
Write-Host "GATE: PASS"
exit 0
