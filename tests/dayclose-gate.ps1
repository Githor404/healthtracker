# R280 -- A DAY CLOSES BY ITSELF AT 04:00 THE NEXT MORNING. In a real browser at 390 px.
#
#   The calendar day is unchanged; it is closed -- complete, counted in the averages --
#   from 04:00 local time the next morning, on read, with nothing stored. At 03:59:59
#   yesterday is open; at 04:00:00 it is closed with no tap, and joins the average.
#   Past days never closed by hand count. A closed day that looks incomplete says so
#   behind its info button, with the rule; each average says how many days it includes
#   and how many are flagged. An entry added to a closed day (backfill, through the
#   Manual form) changes the averages; nothing is asked.
#
# Synthetic days only. Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8391
$Dbg = 9591
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-dayclose-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set DAYCLOSE_SHOTS=1 to save 390px screenshots to %TEMP%\dayclose-shots.
$shots = $null
if ($env:DAYCLOSE_SHOTS) { $shots = Join-Path $env:TEMP 'dayclose-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.dayIsComplete === 'function' && typeof HT.dayGapFlags === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R280 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: seven past days, none closed by hand, saved and reloaded ---------------
  # d-6, d-5, d-4: 2000 cal; d-3: 500 cal (under half the median); d-2: nothing logged;
  # d-1: 2000 cal. Every stored status is in_progress -- nobody tapped close.
  [void](Eval @'
(function () {
  var S = HT.state(), t = HT.todayKey();
  var f = function (k) { return { name: 'Gate food', meal: 'lunch', time: '12:00', kcal: k, protein_g: 10, fat_g: 10, carb_g: 10, fiber_g: 1, soluble_fiber_g: 0, confidence: 'eyeballed', notes: '', source: 'manual' }; };
  var k = { '-6': 2000, '-5': 2000, '-4': 2000, '-3': 500, '-2': null, '-1': 2000 };
  Object.keys(k).forEach(function (n) { S.days[HT.shiftDate(t, +n)] = { status: 'in_progress', water_l: 0, items: k[n] == null ? [] : [f(k[n])] }; });
  HT.resave();
  return 1;
})()
'@)
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  WaitBoot
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  $pin = "(function (h, m, s) { var d = new Date(); d.setHours(h, m, s, 0); var x = d.getTime(); HT.setClock(function () { return x; }); HT.refresh(); return 1; })"
  $avg = "(function(){ var b = document.querySelectorAll('#averages .avgblock')[0]; var d = b ? b.querySelector('.avgdays') : null; var s = d ? (d.querySelector('summary') || d) : null; return { days: s ? s.textContent.replace(/\s+/g, ' ').replace(/^[^0-9]*/, '').trim() : '', kcal: b && b.querySelector('.avgmacros b') ? b.querySelector('.avgmacros b').textContent : '' }; })()"
  $yest = "(function(){ var t = HT.todayKey(); HT.goToDay(HT.shiftDate(t, -1)); HT.refresh(); var c = document.querySelector('.dayclosed'); var bt = Array.prototype.filter.call(document.querySelectorAll('button'), function (b) { return /close this day|complete this day/i.test(b.textContent); }); var dst = document.querySelector('.daysel .dstat'); var r = { day: HT.state().current, badge: dst ? dst.textContent : '', closed: c ? c.textContent.replace(/\s+/g, ' ').trim() : '', closeBtn: bt.length, stored: HT.state().days[HT.shiftDate(t, -1)].status }; HT.goToDay(t); HT.refresh(); return r; })()"

  # ---- 1. 03:59 -- yesterday is still open; 04:00 -- closed, with no tap ------------------
  [void](Eval ($pin + "(3, 59, 59)"))
  $c0 = EvalJ $yest
  $a0 = EvalJ $avg
  Write-Host ("  03:59:59 yesterday: " + $c0 + " averages: " + $a0)
  [void](Eval ($pin + "(4, 0, 0)"))
  $c1 = EvalJ $yest
  $a1 = EvalJ $avg
  Write-Host ("  04:00:00 yesterday: " + $c1 + " averages: " + $a1)
  $c0v = $c0 | ConvertFrom-Json; $c1v = $c1 | ConvertFrom-Json; $a0v = $a0 | ConvertFrom-Json; $a1v = $a1 | ConvertFrom-Json
  Check (($c0v.badge -like 'closes at 04:00*not yet in averages') -and ($c0v.closeBtn -eq 1) -and ($a0v.days -like '5 closed days included*')) "R280: at 03:59:59 yesterday is still open -- 'closes at 04:00 . not yet in averages', the optional close button, 5 days in the 7-day average"
  Check (($c1v.badge -eq '') -and ($c1v.closed -like 'Closed by itself at 04:00 on *counted in averages*still add, change or delete*') -and ($c1v.closeBtn -eq 0) -and ($c1v.stored -eq 'in_progress') -and ($a1v.days -like '6 closed days included*')) "R280 GATE: A DAY CLOSES AT 04:00 THE NEXT MORNING WITHOUT ANY TAP -- yesterday reads closed and joins the average (6 days); its stored status is unchanged"
  Check (($a1v.days -like ('6 closed days included ' + [char]0xB7 + ' 2 flagged*')) -and ($a1v.kcal -eq '1,700' -or $a1v.kcal -eq '1700')) ("R280 GATE: PAST DAYS COUNT AS COMPLETE -- six never closed by hand; the average says how many it includes and how many are flagged (" + $a1v.days + ", " + $a1v.kcal + " cal: the empty day is left out of the calorie mean, not a zero)")
  Shot 'averages'

  # ---- 2. the flags, on the day, behind the info button -----------------------------------
  [void](Eval "(function(){ HT.goToDay(HT.shiftDate(HT.todayKey(), -3)); HT.refresh(); var s = document.querySelector('.gapflag .gapsum'); if (s) { s.scrollIntoView({ block: 'center' }); s.click(); } return 1; })()")
  Settle
  $f1 = EvalJ "(function(){ var g = document.querySelector('.gapflag'); var s = g ? g.querySelector('.gapsum') : null; var r = s ? s.getBoundingClientRect() : null; var cs = g ? getComputedStyle(s) : null; return { sum: s ? s.textContent : '', open: g ? g.open : false, body: g ? g.querySelector('.gapbody').innerText.replace(/\s+/g, ' ') : '', h: r ? Math.round(r.height) : 0, px: cs ? parseFloat(cs.fontSize) : 0, color: cs ? cs.color : '', wide: document.documentElement.scrollWidth - document.documentElement.clientWidth }; })()"
  Write-Host ("  d-3 flags: " + $f1)
  $f1v = $f1 | ConvertFrom-Json
  Check (($f1v.sum -like '*Calories look incomplete (500 cal)*') -and $f1v.open -and ($f1v.body -like '*Under 50 % of the median*still counts*') -and ($f1v.body -like '*closed by itself at 04:00*') -and ($f1v.h -ge 44) -and ($f1v.px -ge 16) -and ($f1v.wide -le 0)) "R280 GATE 3: a closed day that looks incomplete says so behind its info button (44 px, 16px) -- the rule and its numbers in the detail; a flag, not a nudge"
  Shot 'day-flag'

  # ---- 3. backfill on the closed day, by the Manual form ----------------------------------
  [void](Eval "document.getElementById('fab').click()")
  Settle
  [void](Eval "HT.setSheetMode('manual')")
  Settle
  [void](Eval "document.getElementById('maName').focus()")
  TypeText 'Gate late'
  [void](Eval "(function(){ var k = document.getElementById('maKcal'); k.focus(); return 1; })()")
  TypeText '1000'
  [void](Eval "Array.prototype.filter.call(document.querySelectorAll('#pane-manual button'), function (b) { return /^Add to day$/.test(b.textContent.trim()); })[0].click()")
  Settle
  [void](Eval "HT.closeSheet()")
  Settle
  $b1 = EvalJ "(function(){ var d = HT.shiftDate(HT.todayKey(), -3); var day = HT.state().days[d]; return { n: day.items.length, closed: HT.dayIsComplete(d), flags: HT.dayGapFlags(d).map(function (f) { return f.key; }) }; })()"
  [void](Eval "(function(){ HT.goToDay(HT.todayKey()); HT.refresh(); return 1; })()")
  Settle
  $a2 = EvalJ $avg
  Write-Host ("  backfilled: " + $b1 + " averages: " + $a2)
  $a2v = $a2 | ConvertFrom-Json
  Check (($b1 -like '*"n":2,"closed":true*') -and ($a2v.days -like ('6 closed days included ' + [char]0xB7 + ' 1 flagged*')) -and (($a2v.kcal -eq '1,900') -or ($a2v.kcal -eq '1900'))) ("R280 GATE 2: A BACKFILLED ENTRY ON A CLOSED DAY CHANGES THE AVERAGES -- 1,700 to " + $a2v.kcal + " cal, its calorie flag gone (2 flagged to 1); the day stays closed; nothing asked")
  [void](Eval "HT.setClock(null)")

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("DAY CLOSE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "DAY CLOSE GATE: PASS -- a past day closes at 04:00 the next morning with no tap and joins"
Write-Host "  the averages; past days never closed by hand count; gaps are flagged behind an info"
Write-Host "  button and counted beside each average; a backfilled entry changes the averages."
Write-Host "GATE: PASS"
exit 0
