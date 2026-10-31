# R304 -- THE LANDING PAGE: meal rings, the fast line under the date, the declutter.
#
# PRE-REGISTERED (DECISIONS R304): the 2x2 grid at 390 and 360 in light and dark
# (screenshots kept in the rings-shots folder under TEMP); rings inside their cells, at most 150 px and
# about 125 at 360, nothing sideways; a meal not logged is a faint ring and logging it
# moves nothing; segments by grams; a real tap opens the list full width under that
# ring's row and a second closes it, one ring at a time; no micronutrient table above the
# meals; one glucose summary; the fast line under the date and not under the ring; the
# strip at rest shows glucose only, shorter; close and clear are text links and clear
# still asks.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8413
$Dbg = 9613
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-rings-" + [System.Guid]::NewGuid().ToString('N'))
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


  $boot = Eval "typeof HT === 'object' && typeof HT.mealRingTap === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the meal rings are not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  function TapAt([double]$x, [double]$y) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap' }
  function TapSel([string]$sel) {
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + Math.min(r.height / 2, 60) }; })()")
    if ($p -eq 'null' -or -not $p) { return $false }
    $q = $p | ConvertFrom-Json; TapAt $q.x $q.y; return $true }
  # ---- the fixture: a day with breakfast, two lunch sittings, dinner, NO snack; glucose,
  #      a weight, a labelled micronutrient; the clock that evening.
  $fx = EvalJ @'
(function () {
  localStorage.clear(); HT.boot();
  var T = new Date('2026-10-28T21:30:00').getTime(); HT.setClock(function () { return T; });
  window.confirm = function () { window.__asked = (window.__asked || 0) + 1; return false; };
  var dk = '2026-10-28';
  var f = function (name, meal, time, k, c, p, fa, fi, extra) { var it = { name: name, meal: meal, time: time, kcal: k, carb_g: c, protein_g: p, fat_g: fa, fiber_g: fi, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }; if (extra) for (var x in extra) it[x] = extra[x]; return it; };
  HT.state().days[dk] = { status: 'in_progress', water_l: 0, items: [
    f('Gate eggs', 'breakfast', '08:10', 200, 2, 14, 15, 0, { micros: { iron_mg: 2 } }),
    f('Gate soup', 'lunch', '11:46', 300, 30, 12, 10, 6),
    f('Gate bread', 'lunch', '11:50', 150, 28, 5, 2, 3),
    f('Gate apple', 'lunch', '15:18', 95, 25, 0, 0, 4),
    f('Gate stew', 'dinner', '19:00', 600, 40, 45, 25, 8) ] };
  HT.state().current = dk;
  HT.state().timeline[dk] = [HT.normalizeSignal({ type: 'weight', kind: 'biometric', time: '07:30', value: 80, unit: 'kg', source: 'manual' })];
  var rows = [];
  for (var m = 0; m < 12 * 60; m += 5) rows.push({ t: new Date(new Date(dk + 'T08:00:00').getTime() + m * 60000).toISOString(), v: 5.5 + (m % 60) / 60, unit: 'mmol/L' });
  HT.glucoseIngest(rows, { source: 'gate' });
  HT.resave(); HT.closeSheet(); HT.refresh();
  return { ok: true, items: HT.state().days[dk].items.length };
})()
'@
  Write-Host ("  fixture: " + $fx)
  $shotDir = Join-Path $env:TEMP 'rings-shots'
  New-Item -ItemType Directory -Force $shotDir | Out-Null

  foreach ($w in @(390, 360)) {
    foreach ($scheme in @('light', 'dark')) {
      Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
      Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = $scheme }) } | Out-Null
      $null = EvalJ "(function(){ HT.refresh(); window.scrollTo(0, 0); return 1; })()"
      WaitQuiet 'layout'
      $g = EvalJ @'
(function () {
  var grid = document.querySelector('#dayView .mrings');
  if (!grid) return { err: 'no ring grid' };
  var cells = Array.prototype.slice.call(grid.querySelectorAll(':scope > .mring'));
  var r = cells.map(function (c) { var b = c.getBoundingClientRect(), s = c.querySelector('svg').getBoundingClientRect();
    return { k: c.getAttribute('data-kind'), top: Math.round(b.top), left: Math.round(b.left), w: Math.round(b.width), h: Math.round(b.height),
             d: Math.round(s.width), inside: s.left >= b.left - 0.5 && s.right <= b.right + 0.5, tap: b.height >= 44 && b.width >= 44 }; });
  var gb = grid.getBoundingClientRect();
  return { kinds: r.map(function (x) { return x.k; }).join(','), rows: [r[0].top === r[1].top, r[2].top === r[3].top, r[2].top > r[0].top],
           cols: [r[0].left === r[2].left, r[1].left === r[3].left, r[1].left > r[0].left],
           dmax: Math.max.apply(null, r.map(function (x) { return x.d; })), inside: r.every(function (x) { return x.inside; }), tap: r.every(function (x) { return x.tap; }),
           page: document.documentElement.scrollWidth - window.innerWidth, gridW: Math.round(gb.width) };
})()
'@
      Write-Host ("  grid@" + $w + " " + $scheme + ": " + $g)
      $gg = $g | ConvertFrom-Json
      Check (($gg.kinds -eq 'breakfast,lunch,dinner,snack') -and (($gg.rows -join ',') -eq 'True,True,True') -and (($gg.cols -join ',') -eq 'True,True,True')) ("R304/1: four rings in a 2x2 grid, breakfast, lunch / dinner, snack -- at " + $w + " " + $scheme)
      $dOk = if ($w -eq 390) { $gg.dmax -le 150 } else { ($gg.dmax -le 135) -and ($gg.dmax -ge 115) }
      Check ($dOk -and ($gg.inside -eq $true) -and ($gg.page -eq 0) -and ($gg.tap -eq $true)) ("each ring inside its cell, " + $gg.dmax + " px across (at most 150; about 125 at 360), nothing sideways, every ring a 44 px target -- at " + $w + " " + $scheme)
      $r = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png'; captureBeyondViewport = $true; clip = @{ x = 0; y = 0; width = $w; height = 1500; scale = 1 } }
      [IO.File]::WriteAllBytes((Join-Path $shotDir ("rings-" + $w + "-" + $scheme + ".png")), [Convert]::FromBase64String($r.result.data))
    }
  }
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null

  # ---- the faint ring, and a stable layout ----------------------------------------------
  $fa = EvalJ @'
(function () {
  HT.refresh();
  var box = function () { return Array.prototype.map.call(document.querySelectorAll('#dayView .mrings > .mring'), function (c) { var b = c.getBoundingClientRect(); return [Math.round(b.top), Math.round(b.left), Math.round(b.width)].join('/'); }).join(' '); };
  var sn = document.querySelector('#dayView .mring[data-kind="snack"]');
  var out = { faint: !!(sn && sn.classList.contains('mrempty') && sn.querySelector('.mrfaint')), words: sn ? sn.textContent : '', before: box(),
              gridH: Math.round(document.querySelector('#dayView .mrings').getBoundingClientRect().height) };
  HT.state().days['2026-10-28'].items.push({ name: 'Gate nuts', meal: 'snack', time: '21:00', kcal: 180, carb_g: 6, protein_g: 6, fat_g: 15, fiber_g: 3, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' });
  HT.resave(); HT.refresh();
  out.after = box(); out.gridH2 = Math.round(document.querySelector('#dayView .mrings').getBoundingClientRect().height);
  out.filled = !document.querySelector('#dayView .mring[data-kind="snack"]').classList.contains('mrempty');
  HT.state().days['2026-10-28'].items.pop(); HT.resave(); HT.refresh();
  return out;
})()
'@
  Write-Host ("  faint: " + $fa)
  $f = $fa | ConvertFrom-Json
  Check (($f.faint -eq $true) -and ($f.words -like '*not logged*Snack*')) "a meal not logged is a faint dashed ring saying 'not logged'"
  Check (($f.filled -eq $true) -and ($f.before -eq $f.after) -and ($f.gridH -eq $f.gridH2)) "logging that meal fills its ring and nothing moves: every ring keeps its place and the grid its height ($($f.gridH) px)"

  # ---- segments by grams --------------------------------------------------------------------
  $sg = EvalJ @'
(function () {
  HT.refresh();
  var ring = document.querySelector('#dayView .mring[data-kind="lunch"]');
  var segs = {}; Array.prototype.forEach.call(ring.querySelectorAll('.mrseg'), function (c) { segs[c.getAttribute('class').split(' ')[1]] = parseFloat(c.getAttribute('stroke-dasharray')) + 2; });
  var items = HT.state().days['2026-10-28'].items.filter(function (x) { return x.meal === 'lunch'; });
  var t = HT.dayTotals({ items: items });
  var g = { mrc: t.carb_g, mrp: t.protein_g, mrf: t.fat_g, mrb: t.fiber_g };
  var sg = 0, ss = 0; Object.keys(g).forEach(function (k) { sg += g[k]; ss += segs[k] || 0; });
  var worst = 0; Object.keys(g).forEach(function (k) { worst = Math.max(worst, Math.abs((segs[k] || 0) / ss - g[k] / sg)); });
  return { worst: Math.round(worst * 1000) / 1000, caption: ring.querySelector('.mrg').textContent, grams: [Math.round(t.carb_g), Math.round(t.protein_g), Math.round(t.fat_g), Math.round(t.fiber_g)].join(','),
           kcal: ring.querySelector('.mrkcal').textContent, kcalWant: Math.round(t.kcal) };
})()
'@
  Write-Host ("  grams: " + $sg)
  $s = $sg | ConvertFrom-Json
  Check (($s.worst -le 0.01) -and ($s.caption -eq ('carbs ' + ($s.grams -split ',')[0] + ' gprotein ' + ($s.grams -split ',')[1] + ' gfat ' + ($s.grams -split ',')[2] + ' gfibre ' + ($s.grams -split ',')[3] + ' g'))) "segments are by GRAMS: each one's share of the ring is its share of the lunch's eaten carbs, protein, fat and fibre (worst $($s.worst)), and the caption says the grams ($($s.grams))"
  Check ([int]$s.kcal -eq [int]$s.kcalWant) "the centre is the meal's calories ($($s.kcal))"

  # ---- tap to expand: a real touch --------------------------------------------------------
  $null = EvalJ "(function(){ HT.refresh(); return 1; })()"
  $t1 = TapSel '#dayView .mring[data-kind=\"lunch\"]'
  $ex = EvalJ @'
(function () {
  var list = document.querySelector('#dayView .mrlist');
  if (!list) return { open: false };
  var grid = document.querySelector('#dayView .mrings');
  var cells = grid.querySelectorAll(':scope > .mring');
  var lb = list.getBoundingClientRect(), gb = grid.getBoundingClientRect(), row1 = cells[1].getBoundingClientRect(), row2 = cells[2].getBoundingClientRect();
  var names = Array.prototype.map.call(list.querySelectorAll('.mname'), function (e) { return e.textContent; });
  return { open: true, kind: list.getAttribute('data-kind'), full: Math.abs(lb.width - gb.width) <= 1, belowRow: lb.top >= row1.bottom - 1, aboveNext: lb.bottom <= row2.top + 1,
           groups: list.querySelectorAll('.mgrp').length, names: names.join(','), expanded: document.querySelector('#dayView .mring[data-kind="lunch"]').getAttribute('aria-expanded') };
})()
'@
  Write-Host ("  tapped lunch: " + $ex)
  $e = $ex | ConvertFrom-Json
  Check ($t1 -and ($e.open -eq $true) -and ($e.kind -eq 'lunch') -and ($e.full -eq $true) -and ($e.belowRow -eq $true) -and ($e.aboveNext -eq $true)) "a real tap on the lunch ring opens its list full width, under its row and above the next"
  Check (($e.groups -eq 2) -and ($e.names -eq 'Gate soup,Gate bread,Gate apple') -and ($e.expanded -eq 'true')) "the list is the lunch's foods -- both sittings, each its own group ($($e.names))"
  $t2 = TapSel '#dayView .mring[data-kind=\"dinner\"]'
  $one = EvalJ "(function(){ return Array.prototype.map.call(document.querySelectorAll('#dayView .mrlist'), function (l) { return l.getAttribute('data-kind'); }).join(','); })()"
  $t3 = TapSel '#dayView .mring[data-kind=\"dinner\"]'
  $none = EvalJ "(function(){ return document.querySelectorAll('#dayView .mrlist').length; })()"
  Check ($t2 -and $t3 -and ($one -eq '"dinner"') -and ($none -eq '0')) "one ring at a time: tapping dinner closes lunch and opens dinner ($one); a second tap closes it"
  $t4 = TapSel '#dayView .mring[data-kind=\"snack\"]'
  $wr = EvalJ "(function(){ var open = !!document.querySelector('#sheetRoot') && getComputedStyle(document.getElementById('entrySheet')).display !== 'none'; var n = HT.state().days['2026-10-28'].items.length; HT.closeSheet(); return { sheet: open, items: n }; })()"
  Check ($t4 -and ($wr -like '*"sheet":true*') -and ($wr -like '*"items":5*')) "the faint ring opens + Log at that meal and writes nothing"

  # ---- the declutter ----------------------------------------------------------------------------
  $dc = EvalJ @'
(function () {
  HT.closeSheet(); HT.refresh(); window.scrollTo(0, 0);
  var dv = document.getElementById('dayView');
  var html = dv.innerHTML;
  var rings = dv.querySelector('.mrings');
  var microAbove = Array.prototype.some.call(dv.querySelectorAll('.summary, .sumhead'), function (e) { return rings && (e.compareDocumentPosition(rings) & Node.DOCUMENT_POSITION_FOLLOWING); });
  var bio = dv.querySelector('.bgrp');
  var glu = (dv.textContent.match(/avg \d+(\.\d+)?/g) || []).length;
  var nav = dv.querySelector('.daynav'), fl = dv.querySelector('.dfast');
  var under = Array.prototype.some.call(dv.querySelectorAll('.rcline'), function (e) { return /since last logged food|fasting/.test(e.textContent); });
  HT.renderCtxStrip();
  var cs = document.getElementById('ctxStrip');
  var close = dv.querySelector('.dayclose'), clr = dv.querySelector('.clrday');
  window.__asked = 0; if (clr) clr.click();
  return { labeledTable: html.indexOf('labeled intake only') >= 0, microAbove: microAbove,
           bio: bio ? bio.textContent : '', glucoseAvgs: glu,
           fast: fl ? fl.textContent : '', fastUnderDate: !!(nav && fl && nav.nextElementSibling === fl), fastUnderRing: under,
           strip: cs.getAttribute('data-kind'), stripH: cs.offsetHeight, stripText: cs.textContent, gage: (dv.querySelector('.gage') || {}).textContent || '',
           closeLink: !!close && close.classList.contains('linklike') && !close.classList.contains('btn'), clearLink: !!clr && getComputedStyle(clr).textDecorationLine.indexOf('underline') >= 0,
           asked: window.__asked, itemsAfter: HT.state().days['2026-10-28'].items.length };
})()
'@
  Write-Host ("  declutter: " + $dc)
  $d = $dc | ConvertFrom-Json
  Check (($d.labeledTable -eq $false) -and ($d.microAbove -eq $false)) "R304/4a: no micronutrient table above the meals"
  Check (($d.glucoseAvgs -eq 1) -and (-not ($d.bio -match 'glucose')) -and ($d.bio -like '*weight 80 kg*')) "R304/4b: ONE glucose summary on the day; Biometrics keeps the weight and no longer repeats glucose ($($d.bio))"
  Check (($d.fastUnderDate -eq $true) -and ($d.fast -like '*since last logged food*') -and ($d.fastUnderRing -eq $false)) "R304/2: the fast line sits just under the date ('$($d.fast)') and not under the ring"
  # R308.1 (re-pointed): the latest glucose moved to the Glucose section; at rest the box shows only what is pertinent --
  # here a 2.5 h gap since food, a reading 1 h 35 min old, one weight: nothing, so no box
  Check (($d.strip -eq 'none') -and ($d.stripH -eq 0) -and ($d.gage -like ('last reading this day ' + [char]0x2014 + ' 6.4 mmol/L ' + [char]0x00B7 + ' 1 h 35 min ago'))) "R308.1: the Glucose section carries the last reading with its age ('$($d.gage)'), and with nothing pertinent the box at the top is not shown"
  Check (($d.closeLink -eq $true) -and ($d.clearLink -eq $true) -and ($d.asked -eq 1) -and ($d.itemsAfter -eq 5)) "R304/4c-d: 'Close this day' and 'Clear this day' are text links, and Clear still asks first (declined: nothing cleared)"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("RINGS GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "RINGS GATE: PASS -- the meals are four rings, a tap opens their foods, and the top of the day is decluttered as ruled"
Write-Host "GATE: PASS"
exit 0
