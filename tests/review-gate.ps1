# R225 -- THE MEAL RESPONSE REVIEW (pre-registered R213/C). By real taps at 390 px.
#
# On a synthetic stream with a curve computed by hand -- baseline 5.0, a straight
# climb to 7.0 at 30 min and back to 5.0 at 90 -- so the 2 h area is known before
# the app computes it: 1/2 x 90 min x 2.0 mmol/L = 90 mmol/L.min. Three earlier
# days of the same breakfast rise 1, 2 and 3.
#
#   - reached from the meal row (depth on demand): nothing on the closed day
#   - measured figures plain; EXPECTED in its own box that LOOKS different
#     (dashed, italic) and says "Expected"
#   - at the floor: median, range and n; below it: "not enough ... (n of 3)"
#   - a meal with food within 2 h: shown, "not clean", not compared -- here a
#     single item with no mealId, so the review reaches every eating event
#   - a hole in the 2 h: "not judged", with the reason
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8313
$Dbg = 9519
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-review-" + [System.Guid]::NewGuid().ToString('N'))
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
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "Promise.resolve(eval(decodeURIComponent(escape(atob('" + $enc + "'))))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text + " " + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value }
# REAL TYPING, one character at a time into whatever holds the focus.
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    Start-Sleep -Milliseconds 70 } }
function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }
function Focus([string]$id) { [void](Eval "(function(){ var e = document.getElementById('$id'); e.focus(); if (e.select) e.select(); return 1; })()") }

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


  $boot = Eval "typeof HT === 'object' && typeof HT.mealReviewHTML === 'function' && typeof HT.glucoseIngest === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the review is not on HT"; Cleanup; exit 2 }

  $fx = EvalA @'
(function () {
  var td = HT.todayKey();
  var at = new Date(td + 'T21:00:00').getTime();
  HT.setClock(function () { return at; });
  localStorage.clear(); HT.boot();
  td = HT.state().current;
  var p = function (n) { return String(n).padStart(2, '0'); };
  var iso = function (ms) { var d = new Date(ms), o = -d.getTimezoneOffset();
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':00'
      + (o < 0 ? '-' : '+') + p(Math.floor(Math.abs(o) / 60)) + ':' + p(Math.abs(o) % 60); };
  var rows = [];
  var curve = function (dk, hhmm, rise, gapFrom) {
    var t0 = HT.dayKeyMs(dk) + HT.hhmmToMin(hhmm) * 60000;
    for (var m = -15; m <= 125; m += 5) {
      if (gapFrom != null && m >= gapFrom && m < gapFrom + 30) continue;
      var v = 5.0;
      if (m > 0 && m <= 30) v = 5.0 + rise * m / 30; else if (m > 30 && m < 90) v = 5.0 + rise * (90 - m) / 60;
      rows.push({ t: iso(t0 + m * 60000), v: Math.round(v * 1000) / 1000, unit: 'mmol/L' });
    }
  };
  var item = function (name, time, mid, carbs, meal) {
    var o = { name: name, meal: meal || 'breakfast', time: time, kcal: 300, protein_g: 10, fat_g: 10, carb_g: carbs, fiber_g: 0, soluble_fiber_g: 0,
              confidence: 'eyeballed', source: 'manual', notes: '' };
    if (mid) o.mealId = mid; return o; };
  var dd = function (b) { return HT.shiftDate(td, -b); };
  [[4, 1, 35], [3, 2, 40], [2, 3, 45]].forEach(function (x) {
    HT.state().days[dd(x[0])] = { status: 'complete', water_l: 0, items: [item('Gate oats', '08:00', 'm' + x[0], x[2])] };
    curve(dd(x[0]), '08:00', x[1]);
  });
  HT.state().days[dd(1)] = { status: 'complete', water_l: 0, items: [item('Gate gap meal', '08:00', 'mg', 40)] };
  curve(dd(1), '08:00', 2, 40);
  // today: the breakfast; a lunch logged as a SINGLE item (no mealId) with a snack an hour after it
  HT.state().days[td] = { status: 'in_progress', water_l: 0, items: [
    item('Gate oats', '08:00', 'mt', 40), item('Gate lunch', '12:00', null, 60, 'lunch'), item('Gate snack', '13:00', 'ms', 20, 'snack') ] };
  curve(td, '08:00', 2); curve(td, '12:00', 1.5);
  HT.resave();
  return Promise.resolve(HT.glucoseIngest(rows, { source: 'fixture' })).then(function () {
    window.__dd = dd; window.__td = td;
    HT.refresh(); HT.dayGroupsOpenAll(true);
    return { ok: true, td: td };
  });
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"ok":true*')) { Write-Host "ERROR: fixture"; Cleanup; exit 2 }

  # ---- 1. depth on demand: nothing on the closed day -----------------------------------
  $c0 = Eval "(function(){ return document.querySelectorAll('#dayView .resprev, #dayView .respexp').length + '|' + /Expected|earlier meals/.test(document.getElementById('dayView').innerText); })()"
  Check ($c0 -eq '0|false') "R225: with no meal opened the day carries NO review -- nothing added to the day, no nudge ($c0)"

  # ---- 2. open the breakfast by a real tap on its row --------------------------------
  $open = EvalA @'
(function () {
  var head = Array.prototype.filter.call(document.querySelectorAll('#dayView .mhead'), function (h) { return /Gate oats/.test(h.textContent); })[0];
  if (!head) return { err: 'no row' };
  head.click();
  var box = document.querySelector('#dayView .resprev');
  if (!box) return { err: 'no review after opening' };
  var meas = Array.prototype.filter.call(box.querySelectorAll('.respline'), function (l) { return /area above baseline/.test(l.textContent); })[0];
  var exp = box.querySelector('.respexp');
  var cs = function (el) { var s = getComputedStyle(el); return { style: s.fontStyle, border: s.borderTopStyle, px: parseFloat(s.fontSize) }; };
  var r = exp.getBoundingClientRect();
  return { measured: meas ? meas.textContent : '', measuredBold: meas ? !!meas.querySelector('b') : false, mStyle: cs(meas),
           expHead: (exp.querySelector('.respexphead') || {}).textContent, eStyle: cs(exp),
           lines: Array.prototype.map.call(exp.querySelectorAll('.respexpline, .respexpnote'), function (l) { return l.textContent; }),
           small: Array.prototype.filter.call(exp.querySelectorAll('div'), function (d) { return parseFloat(getComputedStyle(d).fontSize) < 16; }).length,
           inside: r.left >= 0 && r.right <= window.innerWidth };
})()
'@
  Write-Host ("  the breakfast, opened: " + $open)
  $o = $open | ConvertFrom-Json
  Check ($o.measured -eq ('2 h area above baseline 90 mmol/L' + [char]0x00B7 + 'min') -and $o.measuredBold) "R225 GATE: the 2 h area is MEASURED and shown plain and bold: 90 mmol/L.min -- the number computed by hand"
  Check (($o.expHead -eq 'Expected, from your own earlier meals') -and ($o.eStyle.style -eq 'italic') -and ($o.eStyle.border -eq 'dashed') -and ($o.mStyle.style -eq 'normal')) "R225 GATE: what is EXPECTED is visibly not a measurement -- its own dashed box, italic, headed 'Expected' -- while the measured line is plain"
  $l0 = [string]$o.lines[0]
  Check (($l0 -like 'Your 3 earlier meals like this: rise median 2 mmol/L (1 to 3)*') -and ($l0 -like '*2 h area median 90 (45 to 135)*')) "R225 GATE: three earlier meals of the same food -> median and range of the rise AND of the area, with n ($l0)"
  $l1 = [string]$o.lines[1]
  Check ($l1 -like 'Your 3 earlier meals with similar carbs (30*50 g): rise median 2*') "R225 GATE: expected from its carbs = your earlier meals of 30-50 g carbohydrate, with n -- no model ($l1)"
  Check (([string]$o.lines[2]) -like 'How closely carbs and the rise have tracked on your meals: *') "and how closely carbs and the rise have tracked on your meals is said beside it"
  Check (($o.small -eq 0) -and $o.inside) "every line of it is 16px or larger, and the box is inside the screen"

  # ---- 3. a single item eaten an hour before a snack: shown, not clean, not compared --
  $lunch = EvalA @'
(function () {
  var head = Array.prototype.filter.call(document.querySelectorAll('#dayView .mhead'), function (h) { return /Gate lunch/.test(h.textContent); })[0];
  head.click();
  // by the row's own HEAD: the breakfast's response names the lunch as the next meal
  var boxes = Array.prototype.filter.call(document.querySelectorAll('#dayView .mitem.mopen'), function (m) { return /Gate lunch/.test((m.querySelector('.mhead') || {}).textContent || ''); });
  var b = boxes[0];
  return { text: b ? (b.querySelector('.resprev') || {}).textContent || '' : '', exp: b ? !!b.querySelector('.respexp') : true, rise: b ? /rise/.test(b.textContent) : false };
})()
'@
  Write-Host ("  the lunch: " + $lunch)
  $lu = $lunch | ConvertFrom-Json
  Check (($lu.text -like '*Not clean*other food in the 2 h after it*not compared*') -and (-not $lu.exp) -and $lu.rise) "R225 GATE: a meal with food in the 2 h after it -- a single item with no mealId, so every eating event is reached -- shows its own numbers, says NOT CLEAN, and is not compared"

  # ---- 4. below the floor, and a hole in the 2 h, on earlier days -----------------------
  $past = EvalA @'
(function () {
  var read = function (dk, name) {
    HT.dayJump(dk); HT.dayGroupsOpenAll(true);
    var head = Array.prototype.filter.call(document.querySelectorAll('#dayView .mhead'), function (h) { return h.textContent.indexOf(name) >= 0; })[0];
    if (!head) return 'no row';
    head.click();
    var b = document.querySelector('#dayView .resprev');
    return b ? b.textContent : 'no review';
  };
  return { below: read(window.__dd(2), 'Gate oats'), gap: read(window.__dd(1), 'Gate gap meal') };
})()
'@
  Write-Host ("  earlier days: " + $past)
  $pv = $past | ConvertFrom-Json
  Check ($pv.below -like '*Meals like this: not enough similar meals yet (2 of 3)*') "R225 GATE: below the floor it is SAID, with n -- 'not enough similar meals yet (2 of 3)'"
  Check ($pv.gap -like '*Not judged*gap in the readings inside the 2 h*') "R225 GATE: a hole in the 2 h -> 'Not judged', with the reason"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -eq 0) {
  Write-Host "REVIEW GATE: PASS -- reached from the meal row only; the hand-computed area measured; expected boxed apart, median/range/n at the floor and said below it; not clean shown and not compared; not judged with its reason"
  Write-Host "GATE: PASS"
  exit 0
}
Write-Host ("REVIEW GATE: FAIL -- " + $fails.Count + " check(s)")
Write-Host "GATE: FAIL"
exit 1
