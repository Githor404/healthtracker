# R186 -- THE SENSOR-CHANGE ENTRY: a tap that says it worked.
#
# THE DEVICE FINDING, in the user's words: "Tapped New sensor, left arm, after
# applying a new G7. Biometrics now shows 12:47 New sensor -- it saved, but" there
# was no confirmation, the entry named neither the sensor nor the arm, nothing
# counted the days, and a second tap would have written a second change.
#
# WHY A GATE AND NOT ONLY THE HARNESS BLOCK. The harness holds what needs no
# screen: the stored contract, the countdown at pinned times, the dedupe, the edit
# provenance. Every reported defect here was a thing ON the screen or missing
# from it, and the harness page has no toast and no badges -- `offerUndo` returns
# early there. A confirmation asserted in that page is asserted on nothing.
#
# PRE-REGISTERED (DECISIONS.md, R186 section 4), and each line is here:
#   1. a real tap writes ONE sensor record carrying type and site, and the
#      Biometrics row reads "New sensor . <type> . <arm>"
#   2. the confirmation is VISIBLE, names type, site and time, offers Undo, is
#      16px MEASURED, is ONE LINE, and is gone after about five seconds
#   3. the status line near the badges reads Day 1 of N after the tap and a LATER
#      day before it -- the countdown is asserted to RESET, not merely to exist
#   4. past the wear time it reads as grace, and past grace it says so
#   5. a second tap, same arm, inside the window writes nothing; the other arm
#      corrects the one record; a tap OUTSIDE the window writes a second (the
#      control -- without it the dedupe could be a tap that never writes)
#   6. Moved, Woke and Drink confirm too, with an Undo that removes the record
#   7. the wear time's source is reachable from the same surface
#   8. the first tap ever ASKS the type and writes nothing until answered
#
# THE CLOCK IS PINNED (D50) through the app's one clock seam, so "Day 3" and
# "grace period" are asserted at stated times rather than waited for. The toast's
# own five seconds are real seconds: that timer is the thing under test.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8263
$Dbg = 9453
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-sensor-" + [System.Guid]::NewGuid().ToString('N'))
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
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.sensorTap === 'function' && typeof HT.setClock === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the sensor path is not on HT"; Cleanup; exit 2 }

  # ---- the clock, pinned at 12:47 today ----------------------------------------
  # TODAY, so the day the app is showing is the day the tap lands on and the
  # Biometrics row can be read off the screen.
  $pin = EvalJ @'
(function () {
  window.__now = HT.dayKeyMs(HT.localDate()) + (12 * 60 + 47) * 60000;
  HT.setClock(function () { return window.__now; });
  window.__count = function (type) { var n = 0, tl = HT.state().timeline || {};
    Object.keys(tl).forEach(function (k) { (tl[k] || []).forEach(function (e) { if (e && e.type === type) n++; }); }); return n; };
  window.__btn = function (text) { var hit = null;
    Array.prototype.forEach.call(document.querySelectorAll('#sigOneTap button'), function (b) {
      if (!hit && (b.textContent || '').trim() === text) hit = b; }); return hit; };
  window.__toast = function () { var e = document.getElementById('toast'); var r = e.getBoundingClientRect();
    var u = e.querySelector('.tundo'); var cs = getComputedStyle(e);
    return { shown: e.className.indexOf('show') >= 0, opacity: Math.round(parseFloat(cs.opacity) * 100) / 100,
             text: (e.textContent || '').trim(), undo: !!u,
             font: parseFloat(cs.fontSize), undoFont: u ? parseFloat(getComputedStyle(u).fontSize) : 0,
             height: Math.round(r.height), left: Math.round(r.left), right: Math.round(r.right),
             vw: window.innerWidth,
             // ONE LINE, measured two ways: the box is one line tall once its padding
             // is taken off, AND the words fit inside it. A no-wrap pill is always one
             // line tall -- text that spills out of it would pass the first test alone.
             lines: Math.round((r.height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom))
                               / (parseFloat(cs.lineHeight) || (parseFloat(cs.fontSize) * 1.5))),
             fits: e.scrollWidth <= e.clientWidth + 1, spill: e.scrollWidth - e.clientWidth }; };
  HT.state().settings.sensorDevice = '';
  HT.refresh();
  // R215: the sensor is logged in + Log ("Log event or biometric"); the day keeps
  // the countdown, read-only. Opened as a user opens it.
  HT.openSheet('signal');
  var q = document.getElementById('sigOneTap');
  var nd = new Date(HT.nowMs());
  return { time: String(nd.getHours()).padStart(2, '0') + ':' + String(nd.getMinutes()).padStart(2, '0'), sensors: window.__count('sensor'), left: !!window.__btn('left arm'), right: !!window.__btn('right arm'),
           status: !!q.querySelector('.snstat'), ask: !!q.querySelector('.snask') };
})()
'@
  Write-Host ("  start: " + $pin)
  Check ($pin -like '*"time":"12:47"*') "the clock is pinned at 12:47 through the app's one clock seam (D50)"
  Check (($pin -like '*"left":true*') -and ($pin -like '*"right":true*')) "both arm badges are in + Log to tap (R215: moved off the day)"
  Check (($pin -like '*"sensors":0*') -and ($pin -like '*"status":false*')) "with no sensor ever logged there is NO status line (D146) -- nothing counts days from a change that never happened"

  # ---- 8 (first): the first tap ever ASKS, and writes nothing -------------------
  $ask = EvalJ @'
(function () {
  window.__btn('left arm').click();
  var q = document.getElementById('sigOneTap');
  var box = q.querySelector('.snask');
  var names = box ? Array.prototype.map.call(box.querySelectorAll('.qbtn'), function (b) { return b.textContent; }).join('|') : '';
  var small = [], short = [];
  if (box) Array.prototype.forEach.call(box.querySelectorAll('button, .snq'), function (b) {
    var fs = parseFloat(getComputedStyle(b).fontSize); if (fs < 16) small.push(b.className + ' ' + fs);
    if (b.tagName === 'BUTTON' && b.offsetHeight < 44) short.push(b.className + ' ' + b.offsetHeight); });
  return { asked: !!box, q: box ? (box.querySelector('.snq') || {}).textContent : '', names: names,
           sensors: window.__count('sensor'), setting: HT.state().settings.sensorDevice, small: small, short: short,
           toast: window.__toast().shown };
})()
'@
  Write-Host ("  first tap: " + $ask)
  Check (($ask -like '*"asked":true*') -and ($ask -like '*Which sensor is this?*')) "RULED A: the first tap ever asks which sensor it is, in the page, with no modal"
  Check ($ask -like '*"names":"Dexcom G7|Dexcom G7 15 Day|Another sensor"*') "the list is the built-in one, and it includes a way to say 'none of these'"
  Check (($ask -like '*"sensors":0*') -and ($ask -like '*"setting":""*')) "and NOTHING is written or remembered until it is answered -- no type is pre-selected in code"
  Check ($ask.Contains('"small":[]') -and $ask.Contains('"short":[]')) "the question and its answers are >= 16px, and every answer is >= 44px tall"

  # ---- 1 + 2: answered, the tap is finished -------------------------------------
  $first = EvalJ @'
(function () {
  var b = null;
  Array.prototype.forEach.call(document.querySelectorAll('#sigOneTap .snask .qbtn'), function (x) { if (x.textContent === 'Dexcom G7') b = x; });
  // R282: the bar's lifetime is measured on the PAGE's clock -- when it went up and when
  // it came down -- not by the gate sleeping and hoping its own wake-up is on time.
  var tEl = document.getElementById('toast');
  window.__tst = { on: null, off: null };
  if (window.__tmo) window.__tmo.disconnect();
  window.__tmo = new MutationObserver(function () {
    var up = tEl.className.indexOf('show') >= 0, t = performance.now();
    if (up && window.__tst.on == null) window.__tst.on = t;
    if (!up && window.__tst.on != null && window.__tst.off == null) window.__tst.off = t;
  });
  window.__tmo.observe(tEl, { attributes: true, attributeFilter: ['class'] });
  window.__tst.tap = performance.now();
  b.click();
  var tl = HT.state().timeline[HT.localDate()] || [];
  var rec = tl.filter(function (e) { return e.type === 'sensor'; })[0] || {};
  var q = document.getElementById('sigOneTap');
  return { sensors: window.__count('sensor'), device: rec.device, variant: rec.variant, time: rec.time, source: rec.source,
           setting: HT.state().settings.sensorDevice, askGone: !q.querySelector('.snask') };
})()
'@
  Write-Host ("  first entry: " + $first)
  $f = $first | ConvertFrom-Json
  Check (($f.sensors -eq 1) -and ($f.device -eq 'dexcom-g7') -and ($f.variant -eq 'left arm') -and ($f.time -eq '12:47')) "answering finishes the tap: ONE entry, carrying the type, the site from the badge tapped, and the time"
  Check (($f.setting -eq 'dexcom-g7') -and ($f.askGone -eq $true)) "the type is remembered and the question is gone"
  Settle
  $t1 = EvalJ "window.__toast()"
  Write-Host ("  confirmation: " + $t1)
  $tv = $t1 | ConvertFrom-Json
  Check (($tv.shown -eq $true) -and ($tv.opacity -ge 0.95)) "THE CONFIRMATION IS VISIBLE -- on screen and opaque, which is the thing the report said was missing"
  Check ($tv.text -like 'New sensor * Dexcom G7 * left arm * 12:47*') "it names the sensor, the site and the time"
  Check ($tv.undo -eq $true) "and it IS the Undo bar (ruled E): the confirmation and the way back are one line, not two things"
  Check (($tv.font -eq 16) -and ($tv.undoFont -eq 16)) "16px, MEASURED -- the words and the Undo both"
  Check (($tv.lines -eq 1) -and ($tv.fits -eq $true) -and ($tv.left -ge 0) -and ($tv.right -le $tv.vw)) "ONE LINE -- one line tall AND the words fit inside the bar -- and all of it inside the screen at 390"
  $row = EvalJ @'
(function () {
  var head = document.querySelector('#dayView .bghead');
  if (head && head.getAttribute('aria-expanded') !== 'true') head.click();
  var names = Array.prototype.map.call(document.querySelectorAll('#dayView .bgline .mginame'), function (n) { return n.textContent; });
  var st = document.querySelector('#sigOneTap .snwords');
  var badge = window.__btn('left arm');
  return { group: !!document.querySelector('#dayView .bghead'), rows: names,
           status: st ? st.textContent : '', statusFont: st ? parseFloat(getComputedStyle(st).fontSize) : 0,
           sameBox: !!st && !!badge && document.getElementById('sigOneTap').contains(st),
           below: !!st && !!badge && st.getBoundingClientRect().top >= badge.getBoundingClientRect().bottom,
           gap: (st && badge) ? Math.round(st.getBoundingClientRect().top - badge.getBoundingClientRect().bottom) : -1 };
})()
'@
  Write-Host ("  the row and the status: " + $row)
  $rw = $row | ConvertFrom-Json
  Check (@($rw.rows) -contains ('New sensor ' + [char]0xB7 + ' Dexcom G7 ' + [char]0xB7 + ' left arm')) "the Biometrics row NAMES the sensor and the site -- the arm was always stored; it was never shown"
  Check ($rw.status -eq ('Dexcom G7 ' + [char]0xB7 + ' Day 1 of 10 ' + [char]0xB7 + ' left arm')) "THE COUNTDOWN: 'Dexcom G7 . Day 1 of 10 . left arm'"
  Check (($rw.statusFont -ge 16) -and ($rw.sameBox -eq $true) -and ($rw.below -eq $true) -and ($rw.gap -lt 120)) "it sits NEAR THE BADGES -- same block, directly beneath them -- at >= 16px"

  # ---- 2 (the five seconds) ------------------------------------------------------
  # The toast's own timer is the thing under test. R282: read on the page's clock --
  # the MutationObserver set before the tap stamps when the bar went up and when it
  # came down -- and the gate WAITS FOR the bar to come down (a condition, polled)
  # instead of sleeping 3.0 + 2.4 s and assuming 0.8 s had passed. Under suite load
  # the gate's own sleeps overran and the bar had already gone at "~4 s".
  $tst = $null
  for ($w = 0; $w -lt 150; $w++) { $tst = EvalJ "window.__tst" | ConvertFrom-Json; if ($tst.off -ne $null) { break }; Start-Sleep -Milliseconds 100 }
  $upMs = if ($tst.off -ne $null) { [double]$tst.off - [double]$tst.tap } else { -1 }
  Write-Host ("  the bar, on the page's clock: up " + ([double]$tst.on - [double]$tst.tap) + " ms after the tap, down " + $upMs + " ms after it")
  Check ($upMs -ge 4000) "the bar is still up about four seconds after the tap"
  Check (($upMs -gt 0) -and ($upMs -le 6300)) "and gone by about six -- ~5 s, as ruled, not the 7 s every other undo bar keeps"

  # ---- 7: the source is one tap away, on the same surface -----------------------
  $cite = EvalJ @'
(function () {
  var d = document.querySelector('#sigOneTap .snstat details.cited');
  if (!d) return { has: false };
  d.open = true;
  var t = d.textContent || '';
  return { has: true, org: t.indexOf('Dexcom') >= 0, date: t.indexOf('2026-10-11') >= 0,
           quote: t.indexOf('up to 10 days, with a 12-hour grace period') >= 0,
           counted: t.indexOf('not read from the sensor') >= 0,
           font: parseFloat(getComputedStyle(d.querySelector('small')).fontSize) };
})()
'@
  Write-Host ("  citation: " + $cite)
  Check (($cite -like '*"has":true*') -and ($cite -like '*"org":true*') -and ($cite -like '*"date":true*') -and ($cite -like '*"quote":true*')) "the wear time's SOURCE is reachable from the same surface: who says so, when it was read, and the sentence itself"
  Check ($cite -like '*"counted":true*') "and it says the days are counted from the logged time, not read from the sensor"

  # ---- 3: the countdown RESETS ----------------------------------------------------
  $later = EvalJ @'
(function () {
  window.__now += 2 * 86400000 + 3600000;              // two days and an hour on
  HT.refresh();
  var before = (document.querySelector('#sigOneTap .snwords') || {}).textContent || '';
  var n0 = window.__count('sensor');
  window.__btn('right arm').click();
  var q = document.getElementById('sigOneTap');
  return { before: before, asked: !!q.querySelector('.snask'), added: window.__count('sensor') - n0,
           after: (q.querySelector('.snwords') || {}).textContent || '' };
})()
'@
  Write-Host ("  two days on: " + $later)
  $lt = $later | ConvertFrom-Json
  Check ($lt.before -eq ('Dexcom G7 ' + [char]0xB7 + ' Day 3 of 10 ' + [char]0xB7 + ' left arm')) "two days and an hour later the line reads Day 3 of 10 -- the count moves with the clock"
  Check (($lt.asked -eq $false) -and ($lt.added -eq 1)) "the NEXT sensor costs ONE tap: the type is the last one used and is not asked again"
  Check ($lt.after -eq ('Dexcom G7 ' + [char]0xB7 + ' Day 1 of 10 ' + [char]0xB7 + ' right arm')) "and the countdown RESETS to Day 1 of 10 on the new arm -- read after a line that said Day 3, so the 1 is a reset and not a number that was always 1"
  Settle
  $t2 = EvalJ "window.__toast()"
  Check (($t2 -like '*"shown":true*') -and ($t2 -like '*right arm*') -and ($t2 -like '*"lines":1*') -and ($t2 -like '*"fits":true*')) "that tap confirms too, naming the new site, on one line"

  # ---- 5: the second tap -----------------------------------------------------------
  $dup = EvalJ @'
(function () {
  var n0 = window.__count('sensor');
  window.__now += 3 * 60000;
  window.__btn('right arm').click();
  var same = { added: window.__count('sensor') - n0, toast: window.__toast().text };
  window.__now += 2 * 60000;
  window.__btn('left arm').click();
  var day = HT.state().timeline[HT.localDate()] || [];
  var recs = day.filter(function (e) { return e.type === 'sensor'; });
  var other = { added: window.__count('sensor') - n0, variant: recs[0] ? recs[0].variant : '', n: recs.length,
                orig: recs[0] && recs[0].orig ? recs[0].orig.variant : '', toast: window.__toast().text,
                undo: window.__toast().undo,
                status: (document.querySelector('#sigOneTap .snwords') || {}).textContent || '' };
  return { same: same, other: other };
})()
'@
  Write-Host ("  the second tap: " + $dup)
  $dp = $dup | ConvertFrom-Json
  Check (($dp.same.added -eq 0) -and ($dp.same.toast -like 'Already logged at*')) "RULED C: three minutes later the SAME arm writes NOTHING, and says the change is already logged and when"
  Check (($dp.other.added -eq 0) -and ($dp.other.n -eq 1) -and ($dp.other.variant -eq 'left arm') -and ($dp.other.orig -eq 'right arm')) "RULED C: the OTHER arm inside the window CORRECTS the one entry -- still one record, with the first-written site kept beside it"
  Check (($dp.other.toast -like 'Site corrected * left arm * Undo') -and ($dp.other.undo -eq $true)) "the correction is said -- what changed, and to what -- and it is undoable"
  Check ($dp.other.status -like '*Day 1 of 10*left arm') "and the status line follows the corrected site"
  Settle
  $t3 = EvalJ "window.__toast()"
  Write-Host ("  correction bar: " + $t3)
  Check (($t3 -like '*"lines":1*') -and ($t3 -like '*"fits":true*') -and ($t3 -like '*"font":16*')) "the correction's bar is one line at 16px as well"
  $ctl = EvalJ @'
(function () {
  var n0 = window.__count('sensor');
  window.__now += 6 * 60000;                           // eleven minutes after the entry
  window.__btn('left arm').click();
  var added = window.__count('sensor') - n0;
  var u = document.querySelector('#toast .tundo');
  if (u) u.click();
  return { added: added, afterUndo: window.__count('sensor') - n0 };
})()
'@
  Write-Host ("  outside the window: " + $ctl)
  Check ($ctl -like '*"added":1*') "CONTROL: eleven minutes after the entry a tap DOES write a second change -- so the dedupe is a window, not a tap that never writes"
  Check ($ctl -like '*"afterUndo":0*') "and a real click on Undo removes exactly that entry"

  # ---- 4: grace, then past -----------------------------------------------------------
  $grace = EvalJ @'
(function () {
  var last = HT.sensorLast();
  var words = function () { HT.refresh(); return (document.querySelector('#sigOneTap .snwords') || {}).textContent || ''; };
  window.__now = last.ms + 10 * 86400000 - 60000;      var d10 = words();
  window.__now = last.ms + 10 * 86400000 + 3600000;    var g = words();
  window.__now = last.ms + 10 * 86400000 + 12 * 3600000 + 60000;  var p = words();
  window.__now = last.ms + 5 * 60000;                  HT.refresh();
  return { d10: d10, grace: g, past: p };
})()
'@
  Write-Host ("  wear time: " + $grace)
  $gr = $grace | ConvertFrom-Json
  Check ($gr.d10 -like '*Day 10 of 10*') "one minute before ten days it is still Day 10 of 10"
  Check ($gr.grace -like '*grace period*11 h left*') "an hour past ten days the line reads GRACE PERIOD, with the hours left of the twelve"
  Check ($gr.past -like '*past its wear time*') "and past the grace period it says so -- a statement of elapsed time, with no instruction in it"
  Check (-not (($gr.past + $gr.grace) -match '(?i)replace|change it|should|must|now')) "neither line tells the user what to do"

  # ---- 6: Moved and Woke confirm too (ruled E) ---------------------------------------
  # R215: the Drink badge is RETIRED -- a drink is food (tests/lookup-gate.ps1 logs
  # one and its Undo). What is asserted for it here is that it is gone.
  $nod = Eval "(function(){ return Array.prototype.filter.call(document.querySelectorAll('#sigOneTap button, #quickEvents button'), function (b) { return /^(wine|beer|spirit|Drink)$/.test((b.textContent || '').trim()); }).length; })()"
  Check ([int]$nod -eq 0) "R215: no Drink badge, and none of its amount-less kinds, anywhere a one-tap event is offered"
  foreach ($k in @(@('Moved', 'walk', 'Moved'), @('Woke', 'woke', 'Woke'))) {
    $label = $k[0]; $type = $k[1]; $says = $k[2]
    $js = "(function () { var n0 = window.__count('" + $type + "'); window.__btn('" + $label + "').click(); var added = window.__count('" + $type + "') - n0; var t = window.__toast(); var u = document.querySelector('#toast .tundo'); if (u) u.click(); return { added: added, shown: t.shown, text: t.text, undo: t.undo, font: t.font, lines: t.lines, fits: t.fits, afterUndo: window.__count('" + $type + "') - n0 }; })()"
    $qe = EvalJ $js
    Write-Host ("  " + $says + ": " + $qe)
    $qv = $qe | ConvertFrom-Json
    Check (($qv.added -eq 1) -and ($qv.shown -eq $true) -and ($qv.text -like ($says + '*')) -and ($qv.undo -eq $true)) ($says + " confirms on the tap, by name, with an Undo -- it was as silent as the sensor, through the same function")
    Check (($qv.font -eq 16) -and ($qv.lines -eq 1) -and ($qv.fits -eq $true)) ($says + "'s bar is 16px and one line")
    Check ($qv.afterUndo -eq 0) ($says + "'s Undo removes the record it wrote")
  }

  # ---- R192: Red light, one tap from the event pane -----------------------------------
  $rl = EvalJ @'
(function () {
  var n0 = window.__count('red_light');
  HT.openSheet(); HT.setSheetMode('signal');
  var chips = document.querySelectorAll('#sigPresets .chip');
  var first = chips[0];
  if (!first) return { err: 'no preset in the event pane' };
  var strip = document.getElementById('sigChips');
  var above = first.getBoundingClientRect().bottom <= strip.getBoundingClientRect().top + 1;
  var inStrip = strip.querySelectorAll('.chippre').length;
  var label = first.textContent, vis = first.getBoundingClientRect().height > 0;
  var fs = parseFloat(getComputedStyle(first).fontSize), h = first.offsetHeight;
  first.click();
  var t = window.__toast();
  var tl = HT.state().timeline[HT.localDate()] || [];
  var rec = tl.filter(function (e) { return e.type === 'red_light'; }).pop() || {};
  var u = document.querySelector('#toast .tundo'); if (u) u.click();
  var after = window.__count('red_light') - n0;
  HT.closeSheet();
  return { label: label, visible: vis, font: fs, height: h, added: (rec.type === 'red_light') ? 1 : 0, value: rec.value, unit: rec.unit,
           source: rec.source, shown: t.shown, text: t.text, undo: t.undo, lines: t.lines, fits: t.fits, tfont: t.font, afterUndo: after,
           above: above, inStrip: inStrip };
})()
'@
  Write-Host ("  red light: " + $rl)
  $rv = $rl | ConvertFrom-Json
  Check (($rv.label -like 'Red light * 15 min') -and ($rv.visible -eq $true)) "R192: 'Red light . 15 min' is in the event pane -- one tap from Log event or biometric"
  Check (($rv.above -eq $true) -and ($rv.inStrip -eq 0)) "it sits ABOVE the chip strip and not in it: in the strip it pushed a chip that is ruled reachable-without-scrolling off a phone's screen (D52/R20)"
  Check (($rv.font -ge 16) -and ($rv.height -ge 44)) "it is >= 16px and >= 44px tall"
  Check (($rv.added -eq 1) -and ($rv.value -eq 15) -and ($rv.unit -eq 'min') -and ($rv.source -eq 'quick')) "a real click logs ONE red-light event of 15 minutes -- no value box, no second tap"
  Check (($rv.shown -eq $true) -and ($rv.text -like 'Red light * 15 min *Undo') -and ($rv.undo -eq $true)) "and confirms it on the Undo bar, by name and minutes"
  Check (($rv.lines -eq 1) -and ($rv.fits -eq $true) -and ($rv.tfont -eq 16)) "one line, 16px, inside the bar"
  Check ($rv.afterUndo -eq 0) "and Undo removes it"

  # ---- the longest bar there is, at both widths --------------------------------------
  # "Dexcom G7 15 Day ... right arm" is the longest confirmation this app can
  # produce, and 360 is the narrowest screen the suite measures.
  foreach ($w in @(390, 360)) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    Start-Sleep -Milliseconds 250
    $wide = EvalJ @'
(function () {
  var keep = JSON.parse(JSON.stringify(HT.state().timeline));
  var dev = HT.state().settings.sensorDevice;
  HT.state().timeline = {};
  HT.state().settings.sensorDevice = 'dexcom-g7-15';
  window.__btn('right arm').click();
  var t = window.__toast();
  var st = document.querySelector('#sigOneTap .snstat');
  var out = { text: t.text, lines: t.lines, fits: t.fits, spill: t.spill, font: t.font, left: t.left, right: t.right, vw: t.vw,
              status: (document.querySelector('#sigOneTap .snwords') || {}).textContent || '',
              statusOverflow: st ? st.scrollWidth - st.clientWidth : -1,
              page: document.documentElement.scrollWidth - window.innerWidth };
  HT.doUndo();
  HT.state().timeline = keep; HT.state().settings.sensorDevice = dev; HT.refresh();
  return out;
})()
'@
    Write-Host ("  longest bar@" + $w + ": " + $wide)
    $wd = $wide | ConvertFrom-Json
    # MEASURED, and it is why the words are allowed to give: the full line is 48px
    # too long at 390 and 78px too long at 360, at a type size that is ruled and a
    # line count that is ruled. So the bar drops "New sensor" and nothing else.
    Check (($wd.text -like 'Dexcom G7 15 Day * right arm *:* Undo') -and (-not ($wd.text -like 'New sensor*'))) ("the longest confirmation still names the TYPE, the SITE and the TIME at " + $w + ", having dropped only the words the tap itself just said")
    Check (($wd.lines -eq 1) -and ($wd.fits -eq $true) -and ($wd.font -eq 16)) ("and is still ONE LINE at 16px at " + $w + " -- one line tall, and the words inside the bar")
    Check (($wd.left -ge 0) -and ($wd.right -le $wd.vw)) ("with every character inside the screen at " + $w)
    Check (($wd.statusOverflow -le 0) -and ($wd.page -le 0)) ("and neither the status line nor the page scrolls sideways at " + $w)
  }
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null

  # ---- changing the remembered type writes nothing ------------------------------------
  $chg = EvalJ @'
(function () {
  var n0 = window.__count('sensor');
  var link = document.querySelector('#sigOneTap .snchg');
  if (!link) return { err: 'no change-type link' };
  link.click();
  var asked = !!document.querySelector('#sigOneTap .snask');
  var b = null;
  Array.prototype.forEach.call(document.querySelectorAll('#sigOneTap .snask .qbtn'), function (x) { if (x.textContent === 'Dexcom G7 15 Day') b = x; });
  b.click();
  return { asked: asked, added: window.__count('sensor') - n0, setting: HT.state().settings.sensorDevice,
           askGone: !document.querySelector('#sigOneTap .snask'),
           status: (document.querySelector('#sigOneTap .snwords') || {}).textContent || '' };
})()
'@
  Write-Host ("  change type: " + $chg)
  Check (($chg -like '*"asked":true*') -and ($chg -like '*"added":0*') -and ($chg -like '*"setting":"dexcom-g7-15"*')) "the remembered type can be changed for the NEXT sensor, and changing it writes no entry"
  Check ($chg -like '*Dexcom G7 * Day 1 of 10*') "and the entry already logged keeps the type it was logged with -- a setting does not rewrite a record"

  # ---- ruled D: the user states a type on an entry that has none ----------------------
  $edit = EvalJ @'
(function () {
  // On the day the app is SHOWING: the editor opens in that day's timeline, and
  // the clock above has been walked two days on.
  var d = HT.state().current;
  window.__now = HT.dayKeyMs(d) + 10 * 3600000;
  HT.state().timeline = {};
  HT.state().timeline[d] = [{ type: 'sensor', kind: 'event', time: '09:15', source: 'quick', variant: 'left arm' }];
  HT.refresh();
  var before = (document.querySelector('#sigOneTap .snwords') || {}).textContent || '';
  HT.openRecordEdit(d, 0);
  var sel = document.getElementById('reDevice');
  if (!sel) return { err: 'the editor offered no sensor type' };
  var first = sel.options[0].textContent, hadVal = !!document.getElementById('reVal');
  sel.value = 'dexcom-g7';
  var save = null;
  Array.prototype.forEach.call(document.querySelectorAll('#timelineOverlay .rewrap button'), function (b) { if (b.textContent === 'Save') save = b; });
  if (save) save.click();
  var rec = HT.state().timeline[d][0];
  return { before: before, first: first, hadVal: hadVal, device: rec.device, orig: rec.orig ? rec.orig.device : 'none',
           edited: !!rec.edited_at, after: (document.querySelector('#sigOneTap .snwords') || {}).textContent || '' };
})()
'@
  Write-Host ("  the user's own edit: " + $edit)
  $ed = $edit | ConvertFrom-Json
  Check (($ed.before -like 'Sensor * day 1 * left arm') -and (-not ($ed.before -like '* of *'))) "RULED D: an entry with no type is NOT given one by the code -- its line counts the day and claims no 'of N'"
  Check (($ed.first -eq 'not recorded') -and ($ed.hadVal -eq $false)) "its editor shows the type as 'not recorded' and offers no value box, since a sensor change has no value"
  Check (($ed.device -eq 'dexcom-g7') -and ($ed.orig -eq '') -and ($ed.edited -eq $true)) "the user sets it through the editor's own Save, and the provenance is a USER EDIT: when it was edited, and that no type was first recorded"
  Check ($ed.after -like 'Dexcom G7 * Day 1 of 10 * left arm') "and once stated, the countdown has a wear time to count against"

  # ---- no dead control ------------------------------------------------------------------
  $dead = EvalJ @'
(function () {
  var scan = function () { var bad = [], n = 0;
    Array.prototype.forEach.call(document.querySelectorAll('#sigOneTap [onclick]'), function (b) {
      n++;
      var a = b.getAttribute('onclick') || '';
      var fn = (a.match(/^([A-Za-z0-9_$.]+)\s*\(/) || [])[1];
      if (!fn) { bad.push('unparsed: ' + a); return; }
      var ref = fn.split('.').reduce(function (o, k) { return (o == null) ? o : o[k]; }, window);
      if (typeof ref !== 'function') bad.push(fn);
    }); return { n: n, bad: bad }; };
  var a = scan();
  HT.sensorAskType();
  var b = scan();
  HT.sensorAskCancel();
  var keep = window.sensorChoose; window.sensorChoose = undefined;
  HT.sensorAskType();
  var planted = scan().bad;
  window.sensorChoose = keep;
  HT.sensorAskCancel();
  return { controls: a.n + b.n, dead: a.bad.concat(b.bad), planted: planted.length > 0 && planted[0] === 'sensorChoose',
           restored: typeof window.sensorChoose === 'function' };
})()
'@
  Write-Host ("  controls: " + $dead)
  Check ($dead.Contains('"dead":[]') -and (-not ($dead -like '*"controls":0*'))) "every control beside the badges, in both its states, resolves to a function that EXISTS"
  Check (($dead -like '*"planted":true*') -and ($dead -like '*"restored":true*')) "PLANT: with one handler taken away the scan names it, and it is put back"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("SENSOR GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "SENSOR GATE: PASS -- a tap that says it worked: the type asked once, an entry"
Write-Host "  naming its sensor and site, one line at 16px with Undo for about five"
Write-Host "  seconds, a countdown that resets, grace and past stated without advice, no"
Write-Host "  second change from a second tap, and the wear time's source one tap away."
Write-Host "GATE: PASS"
exit 0
