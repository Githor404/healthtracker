# R322 -- WAIST CIRCUMFERENCE: logged through + Log like weight, stored in cm, shown in the chosen
# unit (inches unless cm); a How to measure i; the Trends chart with R309's zoom and the user's
# goal line; the waist-to-height ratio only with a height set, cited (NICE NG246) and with no
# verdict word; the top box past 8 days (fewer than 5 entries); the weekly card; backup, restore
# and a fresh boot keep the waists, the unit and the height (and the R318 threshold, whose loss
# at boot this release fixes).
#
# PRE-REGISTERED (DECISIONS R322). Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8435
$Dbg = 9635
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-waist-" + [System.Guid]::NewGuid().ToString('N'))
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

$shots = $env:WAIST_SHOTS
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
  Invoke-CDP 'Emulation.setTimezoneOverride' @{ timezoneId = 'America/Toronto' } | Out-Null   # a fixed zone, so the fixture's times mean the same on any machine
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.waistUnit === 'function' && typeof HT.weekWaistCardHTML === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or waist is not on HT"; Cleanup; exit 2 }
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
    for ($tw = 0; $tw -lt 100; $tw++) {
      $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false, why: 'absent' }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); if (!(q.width > 0 && q.height > 0)) return { ok: false, why: 'not laid out' }; var cx = q.left + q.width / 2, cy = q.top + q.height / 2, hit = document.elementFromPoint(cx, cy); if (!hit || !(hit === b || b.contains(hit) || hit.contains(b))) return { ok: false, why: 'covered' }; var k = [q.left, q.top, q.width, q.height].map(Math.round).join(','); var still = window.__tapRect === k; window.__tapRect = k; return { ok: still, why: still ? '' : 'moving', x: cx, y: cy, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
      if ($r9.ok) { break }; Start-Sleep -Milliseconds 100 }
    if (-not $r9.ok) { Write-Host ('  STEP FAILED: ' + $sel + ' never showed (' + $r9.why + ')'); return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  # ---- the fixture: three earlier waists, stored in cm, the last 10 days ago ----------------
  $mk = @'
(function () {
  localStorage.clear(); HT.boot();
  var t = HT.todayKey();
  [[-24, 92.2], [-17, 91.4], [-10, 90.9]].forEach(function (x) { HT.addSignal({ type: 'waist', value: x[1], unit: 'cm', date: HT.shiftDate(t, x[0]), time: '07:30' }); });
  HT.state().current = t; HT.resave(); HT.refresh();
  return Promise.resolve({ n: HT.waistReadings().length, unit: HT.waistUnit() });
})()
'@
  $fx = EvalA $mk
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"n":3*"unit":"in"*')) { Write-Host "ERROR: the fixture did not build"; Cleanup; exit 2 }
  $dot = [char]0xB7
  $STRIP = "(function(){ var s = document.getElementById('ctxStrip'); return s ? s.textContent.replace(/\s+/g, ' ').trim() : ''; })()"

  # ---- the top box: 3 entries, the last 10 days ago -> past the 8-day fallback --------------
  $s0 = Eval $STRIP
  Write-Host ("  top box at rest: " + $s0)
  Check ($s0 -like ('*Waist ' + $dot + ' last measurement 10 days ago*')) "THE TOP BOX: with fewer than 5 waists, one 10 days old (past 8 days) reads 'Waist $dot last measurement 10 days ago'"

  # ---- one door: + Log -> Log event or biometric -> the Waist chip; inches, then cm -----------
  $null = TapSel '#fab'
  $o1 = TapSel '#sheetRoot .linklike[onclick*=signal]'
  $o2 = TapSel '#sigChips .chip[onclick*=waist]'
  $f = (EvalJ "(function(){ var u = document.getElementById('sigUnit'); return { type: document.getElementById('sigType').value, unit: u.value, units: Array.prototype.map.call(u.options, function (o) { return o.value; }).join(','), how: !!document.querySelector('#sigHowWaist > summary') }; })()") | ConvertFrom-Json
  Write-Host ("  form: " + ($f | ConvertTo-Json -Compress))
  Check ($o1.ok -and $o2.ok -and ($f.type -eq 'waist') -and ($f.unit -eq 'in') -and ($f.units -eq 'in,cm') -and $f.how) "ONE DOOR: + Log, Log event or biometric, the Waist chip -- the form opens on inches (the default), with cm offered and a How to measure i"
  $hw = TapSel '#sigHowWaist > summary'
  $ht = Eval "(function(){ var d = document.getElementById('sigHowWaist'); return (d && d.open ? 'open|' : 'shut|') + (d ? d.textContent.replace(/\s+/g, ' ') : ''); })()"
  Write-Host ("  how: " + $ht)
  if ($shots) { Shot 'waist-form' }
  Check ($hw.ok -and ($hw.h -ge 44) -and ($ht -like 'open|*method (NICE guideline NG246*Find the bottom of the ribs and the top of the hips*midway between these points*just above the belly button*breathe out naturally before taking the measurement*Tip: measure at the same time of day*') -and ($ht -notlike '*navel*')) "R323: the i (a 44 px target) opens NICE's method, quoted and cited (NG246): midway between the bottom of the ribs and the top of the hips, after breathing out naturally -- with the same time of day as a tip"
  $null = TapSel '#sigValue'
  TypeText '34.5'
  $l1 = TapSel '#pane-signal .btn.primary[onclick*=addSignalFromForm]'
  $null = Eval "(function(){ document.getElementById('sigUnit').value = 'cm'; return 1; })()"   # a native picker: chosen by value
  WaitQuiet 'unit picked'
  $null = TapSel '#sigValue'
  TypeText '90'
  $l2 = TapSel '#pane-signal .btn.primary[onclick*=addSignalFromForm]'
  $rec = Eval "(function(){ return ((HT.state().timeline || {})[HT.todayKey()] || []).filter(function (r) { return r.type === 'waist'; }).map(function (r) { return r.value + ' ' + r.unit; }).join(',') + '|' + HT.waistUnit() + '|' + (HT.state().settings.signalUnits || {}).waist; })()"
  Write-Host ("  stored: " + $rec)
  Check ($l1.ok -and $l2.ok -and ($rec -eq '87.63 cm,90 cm|in|undefined')) "BOTH ARE STORED IN ONE UNIT: 34.5 in as 87.63 cm, 90 cm as 90 cm; the unit shown stays inches (logging in cm does not change it)"
  $null = TapSel '#entrySheet .sheetx'

  # ---- the day shows the chosen unit; the top box no longer notes it; deletable ---------------
  $null = Eval "(function(){ HT.dayGroupsOpenAll(true); return 1; })()"
  WaitQuiet 'groups open'
  $dv = (EvalJ "(function(){ var rows = Array.prototype.filter.call(document.querySelectorAll('#dayView .bgline'), function (r) { return /waist/i.test(r.textContent); }); return { rows: rows.map(function (r) { return (r.querySelector('.bgval') || r).textContent.trim(); }).join(','), all: document.getElementById('dayView').textContent.replace(/\s+/g, ' ') }; })()") | ConvertFrom-Json
  $s1 = Eval $STRIP
  Write-Host ("  day rows: " + $dv.rows + ' | top box: ' + $s1)
  Check (($dv.rows -eq '34.5 in,35.4 in') -and ($dv.all -like '*waist 35.4 in*') -and ($s1 -notlike '*Waist*last measurement*')) "THE DAY SHOWS THE CHOSEN UNIT: 34.5 in and 90 cm as 35.4 in, the group's summary 'waist 35.4 in'; with today's waist the top box says nothing about it"
  $rm = TapSel '#dayView .bgrm[onclick$=",1)"]'
  $af = Eval "(function(){ return ((HT.state().timeline || {})[HT.todayKey()] || []).filter(function (r) { return r.type === 'waist'; }).length + '|' + !!document.querySelector('#toast.show .tundo'); })()"
  Check ($rm.ok -and ($rm.h -ge 44) -and ($af -eq '1|true')) "every entry is deletable where it is listed: x (44 px) removes the 90 cm entry, with Undo"

  # ---- Trends: the chart, its zoom, a goal line; the ratio only with a height ----------------
  $null = Eval "(function(){ Array.prototype.forEach.call(document.querySelectorAll('.card details'), function (d) { if (/Trends/.test((d.querySelector('summary') || {}).textContent || '')) d.open = true; }); HT.renderTrends(); return 1; })()"
  WaitQuiet 'trends open'
  $TR = "(function(){ var row = Array.prototype.filter.call(document.querySelectorAll('#trends .trow'), function (r) { return /^Waist/.test(((r.querySelector('.thead') || {}).textContent || '').trim()); })[0]; if (!row) return { found: false }; var g = row.querySelector('g.tgoal'), ln = row.querySelector('.tgoalline'); var tok = function (n) { var d = document.createElement('div'); d.style.color = 'var(' + n + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; }; return { found: true, head: row.querySelector('.thead').textContent.replace(/\s+/g, ' ').trim(), svg: !!row.querySelector('svg'), zoom: ((row.querySelector('.bpzoomlab') || {}).textContent || ''), goal: g ? g.getAttribute('data-goal') : '', stroke: ln ? getComputedStyle(ln).stroke : '', dash: ln ? getComputedStyle(ln).strokeDasharray : '', muted: tok('--muted'), whtr: ((row.querySelector('.twhtr') || {}).textContent || '').replace(/\s+/g, ' ').trim() }; })()"
  $t0 = (EvalJ $TR) | ConvertFrom-Json
  Write-Host ("  trends: " + ($t0 | ConvertTo-Json -Compress))
  Check ($t0.found -and $t0.svg -and ($t0.head -like 'Waist in*') -and ($t0.whtr -eq '')) "TRENDS DRAWS A WAIST CHART in the chosen unit (in); no ratio without a height"
  $z = TapSel '.tzoomrow[data-key=waist] .zin'
  $t1 = (EvalJ $TR) | ConvertFrom-Json
  Check ($z.ok -and ($t1.zoom -like ('2' + [char]0xD7 + ' wide*'))) "it zooms like the other graphs (R309): + widens it to 2x, scrolling sideways"
  $null = Eval "(function(){ HT.graphGoalSet('waist', 35); return 1; })()"
  WaitQuiet 'goal set'
  $t2 = (EvalJ $TR) | ConvertFrom-Json
  Write-Host ("  goal: " + $t2.goal + ' ' + $t2.stroke + ' ' + $t2.dash)
  Check (($t2.goal -eq 'goal 35 in') -and ($t2.stroke -eq $t2.muted) -and ($t2.dash -ne 'none') -and ($t2.dash -ne '')) "a goal line set in Settings, Goals draws on it: dashed, in the muted colour, labelled 'goal 35 in' -- no verdict colour"
  $h1 = EvalJ "HT.setHeight('70')"
  WaitQuiet 'height set'
  $null = Eval "(function(){ HT.renderTrends(); return 1; })()"
  WaitQuiet 'trends redrawn'
  $t3 = (EvalJ $TR) | ConvertFrom-Json
  $ib = TapSel '#trends .twhtr .wsinfosum'
  $ibt = Eval "(function(){ var d = document.querySelector('#trends .twhtr .wsinfo'); return (d && d.open ? 'open|' : 'shut|') + (d ? d.textContent.replace(/\s+/g, ' ') : ''); })()"
  Write-Host ("  ratio: " + $t3.whtr + ' | ' + $ibt)
  if ($shots) { Shot 'waist-trends-light' }
  if ($shots) {
    $null = Eval "(function(){ HT.openSettings(); var g = Array.prototype.filter.call(document.querySelectorAll('#settingsPanel details'), function (d) { return /^Goals/.test(((d.querySelector('summary') || {}).textContent || '').trim()); })[0]; if (g) g.open = true; var w = document.getElementById('waistSet'); if (w) w.scrollIntoView({ block: 'center' }); return 1; })()"
    WaitQuiet 'settings open'
    Shot 'waist-settings'
    $null = Eval "(function(){ HT.closeSettings ? HT.closeSettings() : null; return 1; })()"
    WaitQuiet 'settings closed'
  }
  Check (($h1 -like '*"height_cm":177.8*') -and ($t3.whtr -like ('latest 34.5 in ' + $dot + ' waist-to-height 0.49*'))) "WITH A HEIGHT SET (70 in, kept as 177.8 cm) the latest waist carries its ratio: 'latest 34.5 in $dot waist-to-height 0.49'"
  Check ($ib.ok -and ($ib.h -ge 44) -and ($ibt -like 'open|*NICE guideline NG246*adults with a BMI below 35*keep their waist to less than half their height (so a waist-to-height ratio of under 0.5)*') -and ($ibt -notlike '*navel*') -and ($ibt -notmatch '\b(healthy|increased|high|risk|should|good|bad)\b')) "R323: its i (44 px) cites NICE NG246 -- the ratio for adults with a BMI below 35, NICE's own words on 0.5 quoted -- and no verdict word in the app's voice"

  # ---- the unit switched to cm: everything redraws in cm --------------------------------------
  $null = Eval "(function(){ HT.setWaistUnit('cm'); HT.renderTrends(); return 1; })()"
  WaitQuiet 'unit cm'
  $t4 = (EvalJ $TR) | ConvertFrom-Json
  $dv2 = Eval "(function(){ return Array.prototype.filter.call(document.querySelectorAll('#dayView .bgline'), function (r) { return /waist/i.test(r.textContent); }).map(function (r) { return (r.querySelector('.bgval') || r).textContent.trim(); }).join(','); })()"
  Write-Host ("  in cm: " + $t4.head + ' | ' + $t4.goal + ' | ' + $t4.whtr + ' | day ' + $dv2)
  Check (($t4.head -like 'Waist cm*') -and ($t4.goal -eq 'goal 88.9 cm') -and ($t4.whtr -like ('latest 87.6 cm ' + $dot + ' waist-to-height 0.49*')) -and ($dv2 -eq '87.6 cm')) "CM CHOSEN IN SETTINGS: the chart, the goal line (35 in is 88.9 cm), the ratio line and the day all show cm"

  # ---- the weekly review ---------------------------------------------------------------------
  $wk = Eval "(function(){ var d = document.createElement('div'); d.innerHTML = HT.weekReviewHTML(HT.weekMonday(HT.todayKey())); var c = d.querySelector('[data-card=waist]'); return c ? c.textContent.replace(/\s+/g, ' ') : 'NONE'; })()"
  Write-Host ("  weekly: " + $wk)
  Check ($wk -like ('*Waist*Latest 87.6 cm*waist-to-height 0.49*28 days to *92.2 cm*87.6 cm*readings*')) "THE WEEKLY REVIEW has a Waist card: the latest with its ratio, and the 28 days to the week's last day -- first and latest reading, the change, n"

  # ---- backup -> restore, and a fresh boot, keep every waist, the unit, the height ------------
  $null = Eval "(function(){ HT.setInfluenceMin(40); return 1; })()"
  WaitQuiet 'threshold 40'
  $bk = EvalJ "(function(){ var txt = HT.exportJSON(); window.confirm = function () { return true; }; localStorage.clear(); HT.boot(); var empty = HT.waistReadings().length; var r = HT.restore(txt); return { empty: empty, ok: !!(r && r.ok !== false), n: HT.waistReadings().length, unit: HT.waistUnit(), h: HT.heightCm(), neg: HT.influenceMin(), same: HT.exportJSON() === txt }; })()"
  Write-Host ("  restore: " + $bk)
  WaitQuiet 'restored'
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  WaitBoot
  $rb = Eval "HT.waistReadings().length + '|' + HT.waistUnit() + '|' + HT.heightCm() + '|' + HT.influenceMin()"
  Write-Host ("  after a reload: " + $rb)
  Check (($bk -like '*"empty":0*"ok":true*"n":4*"unit":"cm"*"h":177.8*"neg":0.4*')) "EXPORT -> RESTORE keeps every waist (4), the chosen unit, the height -- and the flag threshold"
  Check ($rb -eq '4|cm|177.8|0.4') "A FRESH BOOT keeps them too (before this release the threshold was dropped at the next start)"

  # ---- layout ------------------------------------------------------------------------------
  $null = Eval "(function(){ Array.prototype.forEach.call(document.querySelectorAll('.card details'), function (d) { if (/Trends/.test((d.querySelector('summary') || {}).textContent || '')) d.open = true; }); HT.renderTrends(); return 1; })()"
  WaitQuiet 'trends again'
  $lay = @()
  foreach ($wd in 390, 360) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wd; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    WaitQuiet 'resize'
    $lay += Eval "(function(){ return [window.innerWidth, document.documentElement.scrollWidth - window.innerWidth].join(':'); })()"
    Shot ("waist-" + $wd)
  }
  Write-Host ("  layout: " + ($lay -join ' '))
  Check (-not ($lay | Where-Object { $_ -notlike '*:0' })) "nothing runs sideways at 390 and 360"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("WAIST GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "WAIST GATE: PASS -- a waist logged in inches or cm through + Log is stored in cm and shown in the chosen unit; chart, zoom and goal line; the ratio only with a height, cited; the top box past 8 days; the weekly card; backup, restore and boot keep it"
Write-Host "GATE: PASS"
exit 0
