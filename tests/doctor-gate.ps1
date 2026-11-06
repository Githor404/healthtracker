# R314.1 -- "DISCUSS WITH YOUR DOCTOR".
#
# PRE-REGISTERED (DECISIONS R314.1): every item kind appears from a placeholder fixture (R204:
# no real names); each states a fact and its source and none is advice; an own item, discussed
# with a date and an answer, by taps; a removal recorded and restorable; an item that stops
# applying kept under "No longer applies"; discussed survives the backup and a reload; the
# printable page fits A4 and Letter; the share text holds every current item.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8436
$Dbg = 9636
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-doctor-" + [System.Guid]::NewGuid().ToString('N'))
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
  WaitQuiet 'before input'
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    WaitQuiet 'typing' } }
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


  $boot = Eval "typeof HT === 'object' && typeof HT.doctorGather === 'function' && typeof HT.packImportText === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or R314.1 is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  function TapAt([double]$x, [double]$y) {
    WaitQuiet 'before input'
    Write-Host ('  STEP tap at ' + [int]$x + ',' + [int]$y)
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap' }
  function TapSel([string]$sel) {
    WaitQuiet 'before input'
    Write-Host ('  STEP tap ' + $sel)
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + Math.min(r.width / 2, 120), y: r.top + r.height / 2 }; })()")
    if ($p -eq 'null' -or -not $p) { return $false }
    $q = $p | ConvertFrom-Json; TapAt $q.x $q.y; return $true }

  # DOCTOR_SHOTS=1 keeps screenshots in %TEMP%\doctor-shots (for looking, not for the verdict)
  $shots = $null
  if ($env:DOCTOR_SHOTS) { $shots = Join-Path $env:TEMP 'doctor-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
  function Shot([string]$name) {
    if (-not $shots) { return }
    $rv = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png' }
    [IO.File]::WriteAllBytes((Join-Path $shots ($name + '.png')), [Convert]::FromBase64String($rv.result.data)) }
  # ---- the fixture: placeholder stack, pack, readings (R204: no real names) ------------------------
  $fx = EvalA @'
(function () {
  localStorage.clear(); HT.boot();
  var T = new Date('2026-10-28T20:00:00').getTime(); HT.setClock(function () { return T; });
  var S = HT.state(), td = HT.todayKey();
  S.settings.stack = [{ id: 'sa', name: 'Item A', kind: 'dose', enabled: true, dose: 1, dose_unit: 'tablet', added_on: '2026-10-01', added_basis: 'added', nutrients: { micros: { zinc_mg: 50 } } }];
  S.timeline[td] = [{ type: 'dose', kind: 'medication', name: 'Item A', time: '08:00', source: 'stack', stackId: 'sa', micros: { zinc_mg: 50 } },
    { type: 'bp_systolic', time: '07:00', value: 142, source: 'manual' }, { type: 'bp_diastolic', time: '07:00', value: 88, source: 'manual' },
    { type: 'bp_systolic', time: '12:00', value: 138, source: 'manual' }, { type: 'bp_diastolic', time: '12:00', value: 84, source: 'manual' },
    { type: 'bp_systolic', time: '19:00', value: 136, source: 'manual' }, { type: 'bp_diastolic', time: '19:00', value: 86, source: 'manual' }];
  // a planted low night: readings below 3.0 mmol/L between 02:00 and 03:00 the night before
  var ev = HT.shiftDate(td, -1), rows = [];
  for (var m = 21 * 60; m < 33 * 60; m += 5) {
    var dk = m < 24 * 60 ? ev : td, mm = m % (24 * 60);
    var hh = ('0' + Math.floor(mm / 60)).slice(-2) + ':' + ('0' + (mm % 60)).slice(-2);
    rows.push({ t: new Date(dk + 'T' + hh + ':00').toISOString(), v: (m >= 26 * 60 && m < 27 * 60) ? 2.8 : 5.5, unit: 'mmol/L' });
  }
  HT.resave();
  HT.glucoseIngest(rows, { source: 'fixture' });
  var rv = '2026-10-20';
  var body = { format: 'healthtracker-pack', schema: 1, groups: [{ id: 'g', name: 'Group A' }], records: [], lexicon: { rules: [] }, sources: [{ id: 'src-a', authors: 'Placeholder A', venue: 'Placeholder Journal', year: 2020 }],
    claims: [
      { id: 'clm-neg', claim: 'Placeholder claim against the item.', subject: { match: ['item a'] }, reviewed_by_me: rv, attributions: [{ source: 'src-a' }],
        evidence: { grade: 'low' }, probability: { versions: [{ p: 0.6, of: 'that the effect is real' }] },
        for_me: { direction: 'negative', short: 'placeholder short', reviewed_by_me: rv },
        tests: [{ name: 'Placeholder test', why: 'named in the placeholder source', reviewed_by_me: rv }, { name: 'Unreviewed test', why: 'x' }] },
      { id: 'clm-safe', claim: 'Placeholder safety claim.', safety: true, subject: { match: ['item a'] }, reviewed_by_me: rv, attributions: [{ source: 'src-a' }],
        evidence: { grade: 'moderate' }, probability: { versions: [{ p: 0.4, of: 'that the event happens' }] } }],
    interactions: [{ id: 'int-a', claim: 'Placeholder interaction.', match: ['item a'], reviewed_by_me: rv, attributions: [{ source: 'src-a' }], probability: { versions: [{ p: 0.3, of: 'that the interaction occurs' }] } }],
    doctor_list: [{ id: 'pc-1', text: 'Placeholder item prepared on the computer.', source: 'your notes on your computer' }],
    reference_intakes: { source: 'Health Canada', group: 'Males 51-70', values: {} } };
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 5, sha256: hex, body: txt }));
  }).then(function (r) { HT.refresh(); return { ok: r.ok, td: td }; });
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"ok":true*')) { Write-Host "ERROR: fixture"; Cleanup; exit 2 }

  # ---- 1. open the list by a tap: every kind appears -----------------------------------------
  [void](Eval "(function(){ HT.openSettings(); return 1; })()"); WaitQuiet 'settings'
  $t1 = TapSel '#dlDetails > summary'
  WaitQuiet 'list opened'
  $l1 = EvalJ "(function(){ var b = document.getElementById('doctorListBox'); return { heads: Array.prototype.map.call(b.querySelectorAll('.dlhead'), function (h) { return h.textContent; }), items: Array.prototype.map.call(b.querySelectorAll('.dlitem'), function (e) { return e.getAttribute('data-dl'); }), text: b.textContent.replace(/\s+/g, ' ') }; })()"
  [void](Eval "(function(){ var d = document.getElementById('dlDetails'); if (d) d.scrollIntoView({ block: 'start' }); return 1; })()"); Shot 'list'
  Write-Host ("  opened: " + $l1)
  $Lst = $l1 | ConvertFrom-Json
  $want = @('limit:zinc_mg', 'negative:clm-neg:sa', 'safety:clm-safe:sa', 'interaction:int-a:sa', 'test:placeholder-test', 'reading:glucose-low', 'reading:bp-above', 'pc:pc-1')
  $missing = @($want | Where-Object { @($Lst.items) -notcontains $_ })
  Check ($t1 -and ($missing.Count -eq 0) -and (-not ($l1 -like '*unreviewed-test*'))) ("R314.1: OPENED BY A TAP, every kind is gathered from its placeholder -- upper level, negative claim, safety, interaction, a reviewed test (an unreviewed one is not), the low night, BP above the lines, an item from the computer; missing: " + ($missing -join ', '))
  Check (($Lst.text -like '*Zinc: above*40 mg*on 1 of the last 28 days*Source: IOM*') -and ($Lst.text -like '*Item A: Placeholder claim against the item.*60 % that the effect is real*GRADE low*Source: Placeholder A*') -and ($Lst.text -like '*Glucose: a reading below 3.0 mmol/L*Source: International Hypoglycaemia Study Group*') -and ($Lst.text -like '*Blood pressure: 3 of 3 readings*above 135/85 mmHg*mean of a series*')) "R314.1: each item states its fact and its source -- the level and its scope, the claim with its probability, GRADE and source, the flag's own words, BP n of m with the threshold's caveat"
  $adv = [regex]::Matches(($Lst.text -replace 'Mark discussed|Remove|Share|Printable page|\+ Add your own item', ''), '(?i)\b(should|must|recommend\w*|avoid|stop|start|consider)\b').Count
  Check ($adv -eq 0) "R314.1: no advice wording anywhere in the list ($adv found)"

  # ---- 2. an own item, by taps; discussed with a date and the doctor's answer ------------------
  $t2 = TapSel '#doctorListBox .dladd'
  [void](Eval "document.getElementById('dlOwnText').focus()"); TypeText 'Placeholder own question'
  $t3 = TapSel '#doctorListBox .dlownsave'
  $ownKey = Eval "(HT.state().settings.doctorList.own[0] ? 'own:' + HT.state().settings.doctorList.own[0].id : '')"
  $t4 = TapSel ("#doctorListBox .dlitem[data-dl=\""" + $ownKey + "\""] .dldisc")
  [void](Eval "document.getElementById('dlAnswer').focus()"); TypeText 'Placeholder answer'
  $t5 = TapSel '#doctorListBox .dlsave'
  $d1 = Eval ("JSON.stringify(HT.state().settings.doctorList.seen['" + $ownKey + "'].discussed)")
  $sz = EvalJ "(function(){ var b = document.getElementById('doctorListBox'); return { tiny: Array.prototype.filter.call(b.querySelectorAll('button, summary'), function (e) { var r = e.getBoundingClientRect(); return r.height > 0 && r.height < 44; }).length, small: Array.prototype.filter.call(b.querySelectorAll('.dltext, .dlans, .note, .dlhead'), function (e) { return e.offsetHeight > 0 && parseFloat(getComputedStyle(e).fontSize) < 16; }).length, wide: document.documentElement.scrollWidth - window.innerWidth }; })()"
  Write-Host ("  own: " + $ownKey + " discussed " + $d1 + " / sizes " + $sz)
  Check ($t2 -and $t3 -and $t4 -and $t5 -and ($ownKey -like 'own:*') -and ($d1 -like '*"date":"2026-10-28","answer":"Placeholder answer"*')) "R314.1: an own item added and marked discussed with today's date and the doctor's answer, all by taps"
  Check ($sz -like '*"tiny":0,"small":0,"wide":0*') "R314.1: 44 px controls, 16 px text, nothing sideways at 390"

  # ---- 3. removed, recorded and restorable; no longer applies --------------------------------
  $t6 = TapSel '#doctorListBox .dlitem[data-dl="safety:clm-safe:sa"] .dlrm'
  $r1 = EvalJ "(function(){ var e = HT.state().settings.doctorList.seen['safety:clm-safe:sa']; return { removed: !!e.removed && !isNaN(Date.parse(e.removed)), inRemoved: !!document.querySelector('#doctorListBox .dlremoved .dlitem[data-dl=\x22safety:clm-safe:sa\x22]') }; })()"
  [void](Eval "(function(){ var d = document.querySelector('#doctorListBox .dlremoved'); if (d) d.open = true; return 1; })()")
  $t7 = TapSel '#doctorListBox .dlremoved .dlrestore'
  $r2 = Eval "!HT.state().settings.doctorList.seen['safety:clm-safe:sa'].removed && !!document.querySelector('#doctorListBox > .dlgrp .dlitem[data-dl=\x22safety:clm-safe:sa\x22]')"
  [void](Eval "(function(){ HT.state().settings.stack[0].enabled = false; HT.resave(); HT.doctorOpen(); return 1; })()")
  $g1 = EvalJ "(function(){ var S = HT.doctorSections(); return { gone: S.gone.sort(), live: S.live.length }; })()"
  [void](Eval "(function(){ HT.state().settings.stack[0].enabled = true; HT.resave(); HT.doctorOpen(); return 1; })()")
  Write-Host ("  removed: " + $r1 + " restored " + $r2 + " / item switched off: " + $g1)
  Check ($t6 -and ($r1 -like '*"removed":true,"inRemoved":true*') -and $t7 -and ($r2 -eq $true)) "R314.1: a removal is the user's tap, recorded with its time, listed under Removed, and restorable"
  Check (($g1 -like '*interaction:int-a:sa*') -and ($g1 -like '*negative:clm-neg:sa*') -and ($g1 -like '*safety:clm-safe:sa*')) "R314.1: with the stack item switched off, its claims move to 'No longer applies' -- kept, not deleted"

  # ---- 4. discussed survives a backup round trip and a reload ---------------------------------
  $bk = EvalJ "(function(){ var j = HT.exportJSON(); var o = JSON.parse(typeof j === 'string' ? j : JSON.stringify(j)); return { has: !!(o.settings && o.settings.doctorList && o.settings.doctorList.seen && o.settings.doctorList.seen['$ownKey'] && o.settings.doctorList.seen['$ownKey'].discussed.answer === 'Placeholder answer') }; })()"
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
  WaitBoot
  $rl = Eval ("(function(){ var e = HT.state().settings.doctorList && HT.state().settings.doctorList.seen['" + $ownKey + "']; return !!e && !!e.discussed && e.discussed.answer === 'Placeholder answer' && e.discussed.date === '2026-10-28'; })()")
  Write-Host ("  backup: " + $bk + " / after reload: " + $rl)
  Check (($bk -like '*"has":true*') -and ($rl -eq $true)) "R314.1: 'discussed' with its date and the doctor's answer is in the backup and survives a reload"

  # ---- 5. the printable page fits A4 and Letter; the share text holds every current item -------
  [void](Eval "(function(){ var T = new Date('2026-10-28T20:00:00').getTime(); HT.setClock(function () { return T; }); HT.doctorOpen(); HT.doctorPrintOpen(); return 1; })()"); WaitQuiet 'print view'
  Shot 'print-view'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ media = 'print' } | Out-Null
  $fits = @()
  foreach ($w in @(680, 703)) {   # A4 and Letter at 96 dpi less 15 mm margins each side: 794-113, 816-113
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 1000; deviceScaleFactor = 1; mobile = $false } | Out-Null
    WaitQuiet 'print width'
    $fits += EvalJ "(function(){ var p = document.getElementById('doctorPrint'); var vis = Array.prototype.filter.call(document.body.children, function (e) { return e !== p && getComputedStyle(e).display !== 'none' && e.tagName !== 'SCRIPT'; }).length; var c = p.querySelectorAll('button, input, select, textarea'); var shown = Array.prototype.filter.call(c, function (e) { return e.offsetHeight > 0; }).length; return { w: $w, wide: Math.max(document.documentElement.scrollWidth, p.scrollWidth) - window.innerWidth, others: vis, controls: shown, small: Array.prototype.filter.call(p.querySelectorAll('li, .dlpsrc, .dlpfoot'), function (e) { return parseFloat(getComputedStyle(e).fontSize) < 16; }).length, items: p.querySelectorAll('li').length }; })()"
  }
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ media = '' } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  $sh = EvalJ "(function(){ var t = HT.doctorPlainText(); var S = HT.doctorSections(); return { all: S.live.every(function (k) { return t.indexOf(S.seen[k].text) >= 0; }), n: S.live.length, src: (t.match(/\[Source: /g) || []).length }; })()"
  Write-Host ("  print: " + ($fits -join ' ') + " / share: " + $sh)
  $okPrint = @($fits | Where-Object { $_ -like '*"wide":0,"others":0,"controls":0,"small":0*' }).Count -eq 2
  Check $okPrint "R314.1: the printable page at A4 and Letter widths (print styles) shows only the list -- nothing sideways, no control, 16 px text"
  Check ($sh -like '*"all":true*') "R314.1: the share text holds every current item, each with its source"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("DOCTOR GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "DOCTOR GATE: PASS -- every kind gathered with its source and no advice; own items, discussed with the answer, kept across a backup and a reload; removal recorded; the page fits A4 and Letter"
Write-Host "GATE: PASS"
exit 0
