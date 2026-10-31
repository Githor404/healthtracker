# R306 -- THE MICRONUTRIENTS SECTION, PER DAY, BY WEIGHT.
#
# PRE-REGISTERED (DECISIONS R306): a day whose food is all covered shows plain totals at
# 100 %; a partial day shows dimmed totals with "partial" and the % known; unknown is never
# zero; a stack dose is in the total and labelled; the reference intake shows from a
# (placeholder) pack and not without one; the shortcut counts exactly the unlinked foods
# and a real tap opens the suggestions for exactly those; a tap on a row links that food
# and only then does it count; no verdict colour; 16 px; 44 px; nothing sideways.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8415
$Dbg = 9615
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-micro-" + [System.Guid]::NewGuid().ToString('N'))
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


  $boot = Eval "typeof HT === 'object' && typeof HT.panelWeightCoverage === 'function' && typeof HT.corpusEnsure === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or R306 is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  function TapAt([double]$x, [double]$y) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap' }
  function TapSel([string]$sel) {
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + Math.min(r.width / 2, 120), y: r.top + r.height / 2 }; })()")
    if ($p -eq 'null' -or -not $p) { return $false }
    $q = $p | ConvertFrom-Json; TapAt $q.x $q.y; return $true }

  # ---- the fixture -----------------------------------------------------------------------------
  $fx = EvalA @'
HT.corpusEnsure().then(function () {
  localStorage.clear(); HT.boot();
  var T = new Date('2026-10-28T20:00:00').getTime(); HT.setClock(function () { return T; });
  var S = HT.state();
  var it = function (name, g, v, extra) { var o = { name: name, meal: 'lunch', time: '12:00', kcal: 100, protein_g: 5, fat_g: 2, carb_g: 15, fiber_g: 1, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' };
    if (g != null) o.grams = g; if (v) o.ref = { ns: 'cnf', id: 'x' + name.length, name: name, v: v, attribution: 'Canadian Nutrient File, Health Canada, 2015' }; if (extra) for (var k in extra) o[k] = extra[k]; return o; };
  S.days['2026-10-27'] = { status: 'in_progress', water_l: 0, items: [it('Gate fish', 100, { 303: 2, 301: 40 }), it('Gate greens', 200, { 303: 1, 301: 60 })] };
  S.days['2026-10-28'] = { status: 'in_progress', water_l: 0, items: [it('Gate fish', 100, { 303: 2 }), it('Lentils', 150, null), it('White rice', 150, null), it('Gate soup', null, null, { source: 'ai-paste' })] };
  S.settings.stack = [{ id: 'ss', name: 'Item S', kind: 'dose', enabled: true, dose: 100, dose_unit: 'mg', added_on: '2026-10-01', added_basis: 'added', nutrients: { micros: { magnesium_mg: 100 } } }];
  S.current = '2026-10-28'; HT.resave(); HT.refresh();
  HT.stackCheck('ss');
  HT.panelToggle(true); HT.refresh();
  return { ok: true, corpus: HT.corpusMem() ? HT.corpusMem().ns : null };
})
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"ok":true*')) { Write-Host "ERROR: fixture"; Cleanup; exit 2 }
  $RowJS = @'
window.__row = function (slot) { var r = document.querySelector('#microPanel .prow[data-slot="' + slot + '"]'); if (!r) return null;
  var v = r.querySelector('.pval'), m = document.querySelector('#microPanel .pcov');
  return { text: r.textContent.replace(/\s+/g, ' ').trim(), val: v ? v.textContent.trim() : '', part: r.classList.contains('ppart'), abs: r.classList.contains('pabs'),
           col: v ? getComputedStyle(v).color : '', muted: m ? getComputedStyle(m).color : '' }; };
1
'@
  [void](EvalJ $RowJS)

  # ---- a full day, and a partial day ---------------------------------------------------------
  $full = EvalJ "(function(){ HT.dayJump('2026-10-27'); HT.panelToggle(true); HT.refresh(); return { iron: window.__row(303), ca: window.__row(301) }; })()"
  Write-Host ("  full day: " + $full)
  $f = $full | ConvertFrom-Json
  Check (($f.iron.val -like '3*') -and ($f.iron.text -like '*100 % of the day*food known*') -and ($f.iron.part -eq $false) -and ($f.ca.text -like '*100 % of the day*food known*')) "R306: a day whose food all carries a value shows PLAIN totals at 100 % known (iron 3 mg)"
  $part = EvalJ "(function(){ HT.dayJump('2026-10-28'); HT.panelToggle(true); HT.refresh(); return { iron: window.__row(303), ca: window.__row(301), mg: window.__row(304), noW: (document.querySelector('#microPanel .pcovall') || {}).textContent || '' }; })()"
  Write-Host ("  partial day: " + $part)
  $p = $part | ConvertFrom-Json
  Check (($p.iron.val -like '2*') -and ($p.iron.text -like '*25 % of the day*food known*partial*') -and ($p.iron.part -eq $true) -and ($p.iron.col -eq $p.iron.muted)) "a partial day shows the total DIMMED (the muted colour, no verdict colour) with 'partial' and the % known: iron 2 mg, 25 % of 400 g"
  Check (($p.iron.val -like '2*') -and (-not ($p.iron.val -like '0*'))) "unknown is never zero: the two foods with no value add nothing to iron -- the total is the known 2 mg, not a sum padded with zeros"
  Check (($null -eq $p.ca) -or ($p.ca.abs -eq $true) -or ($p.ca.val -eq [string][char]0x2013)) "a nutrient no food on the day carries reads '-', never 0 ($($p.ca.val))"
  Check (($p.mg.text -like '*100*from your stack*') -and ($p.mg.text -like '*0 % of the day*food known*')) "the stack dose is in the magnesium total and labelled as such; it is not food, so the % known stays 0"
  Check ($p.noW -like '*1 item has no weight*not in the % known*') "the item with no weight is named as not in the % known ($($p.noW))"

  # ---- the reference intake, from a placeholder pack -------------------------------------------------
  $ri = EvalA @'
(function () {
  var body = { format: 'healthtracker-pack', schema: 1, groups: [{ id: 'g', name: 'Group A' }], records: [], claims: [], interactions: [], lexicon: { rules: [] }, sources: [],
    reference_intakes: { source: 'Health Canada, Dietary Reference Intakes tables', group: 'Males 51-70', values: { iron: { label: 'Iron', value: 8, unit: 'mg', kind: 'RDA', slot: '303', slot_factor: 1 } } } };
  var txt = JSON.stringify(body);
  var before = window.__row(303).text;
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 3, sha256: hex, body: txt }));
  }).then(function (r) { HT.refresh(); return { ok: r.ok, before: before, after: window.__row(303).text, src: document.getElementById('microPanel').textContent.indexOf('Males 51-70') >= 0 }; });
})()
'@
  Write-Host ("  reference intake: " + $ri)
  $rv = $ri | ConvertFrom-Json
  Check (($rv.ok -eq $true) -and (-not ($rv.before -like '*RDA*')) -and ($rv.after -like '*RDA 8 mg*') -and ($rv.src -eq $true)) "the reference intake shows only from a pack -- none before, 'RDA 8 mg' and its source and group after"

  # ---- the shortcut: exactly the unlinked foods -------------------------------------------------------
  $sc = EvalJ "(function(){ var b = document.querySelector('#microPanel .plinkbtn'); return { text: b ? b.textContent : '', want: HT.panelUnlinked('2026-10-28').map(function (x) { return x.it.name; }).join(',') }; })()"
  Write-Host ("  shortcut: " + $sc)
  Check (($sc -like ('*"text":"2 foods have no nutrient data ' + [char]0x2014 + ' link them*')) -and ($sc -like '*"want":"Lentils,White rice"*')) "the shortcut counts exactly the unlinked foods: 2 (not the linked fish, not the soup with no weight)"
  $t1 = TapSel '#microPanel .plinkbtn'
  $null = EvalA "new Promise(function (r) { var n = 0; (function w() { var ok = document.querySelectorAll('#microPanel .plinkitem .mlinkrow').length > 0 && !document.querySelector('#microPanel .plinkitem .note'); if (ok || ++n > 60) return r(1); setTimeout(w, 100); })(); })"
  $op = EvalJ "(function(){ return Array.prototype.map.call(document.querySelectorAll('#microPanel .plinkitem'), function (e) { return (e.querySelector('.plinkname') || {}).textContent.split(' ')[0] + ':' + e.querySelectorAll('.mlinkrow').length; }); })()"
  Write-Host ("  opened: " + $op)
  Check ($t1 -and ($op -like '*Lentils:3*') -and ($op -like '*White:3*') -and (($op | ConvertFrom-Json).Count -eq 2)) "a real tap opens a suggestion box for EXACTLY those foods, each with the top 3 database rows"
  $pre = EvalJ "(function(){ var d = HT.state().days['2026-10-28']; return { ref: !!d.items[1].ref, iron: window.__row(303).text }; })()"
  $t2 = TapSel '#microPanel .plinkitem[data-idx=\"1\"] .mlinkrow'
  $null = EvalA "new Promise(function (r) { var n = 0; (function w() { if (HT.state().days['2026-10-28'].items[1].ref || ++n > 60) return r(1); setTimeout(w, 100); })(); })"
  $post = EvalJ "(function(){ HT.refresh(); var d = HT.state().days['2026-10-28']; var b = document.querySelector('#microPanel .plinkbtn'); return { ref: !!d.items[1].ref, iron: window.__row(303).text, left: b ? b.textContent : '' }; })()"
  Write-Host ("  before the tap: " + $pre + " / after: " + $post)
  Check (($pre -like '*"ref":false*') -and ($post -like '*"ref":true*') -and ($post -like ('*"left":"1 food has no nutrient data ' + [char]0x2014 + ' link it*'))) "nothing counted until the tap; a real tap on a row links that food, and the shortcut counts one fewer"
  Check (-not ((($pre | ConvertFrom-Json).iron) -eq (($post | ConvertFrom-Json).iron))) "and the iron row changed with it (its coverage or total now includes the linked food)"

  # ---- the layout ----------------------------------------------------------------------------------------
  $ly = EvalJ @'
(function () {
  var P = document.getElementById('microPanel');
  var small = Array.prototype.filter.call(P.querySelectorAll('.prow, .pcov, .plinkbtn, .plinkname, .pcovall'), function (e) { return e.offsetHeight > 0 && parseFloat(getComputedStyle(e).fontSize) < 16; }).length;
  var tiny = Array.prototype.filter.call(P.querySelectorAll('button'), function (e) { var r = e.getBoundingClientRect(); return r.height > 0 && r.height < 44; }).length;
  var red = Array.prototype.filter.call(P.querySelectorAll('.prow *'), function (e) { var c = getComputedStyle(e).color; return /rgb\(2[0-9]{2}, (10[0-9]|1[0-3][0-9]), /.test(c); }).length;
  return { small: small, tiny: tiny, red: red, page: document.documentElement.scrollWidth - window.innerWidth };
})()
'@
  Write-Host ("  layout: " + $ly)
  Check (($ly -like '*"small":0*') -and ($ly -like '*"tiny":0*') -and ($ly -like '*"red":0*') -and ($ly -like '*"page":0*')) "16 px text, 44 px controls, no verdict red, nothing sideways at 390"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("MICRO GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "MICRO GATE: PASS -- each nutrient is one total per day with its coverage by weight, partial under 60 %, never zero for unknown, and the unlinked foods one tap from their rows"
Write-Host "GATE: PASS"
exit 0
