# R287 -- WHAT KEEPS A FAST: net carbs <= 5 g and protein <= 5 g for the portion logged, whatever
# its fat or calories; alcohol always ends it; unknown ends it; the user's own mark wins. In a real
# browser at 390 px, by real taps. The rule's own cases (cream coffee, butter and coconut-oil
# coffee, oil, a 30 g protein item, wine, unknown, an override each way) are in the harness;
# this gate checks what only a screen can: the line on an entry, its taps, the editor, Settings'
# words and limits, the weekly note. Placeholder foods only.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8407
$Dbg = 9607
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-fastrule-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set FASTRULE_SHOTS=1 to save 390px screenshots to %TEMP%\fastrule-shots.
$shots = $null
if ($env:FASTRULE_SHOTS) { $shots = Join-Path $env:TEMP 'fastrule-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.packImportText === 'function' && typeof HT.linkPrepare === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R286 functions are not on HT"; Cleanup; exit 2 }

  function TapSel([string]$sel) {
    $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); return { ok: q.width > 0 && q.height > 0, x: q.left + q.width / 2, y: q.top + q.height / 2, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
    if (-not $r9.ok) { return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  # ---- the fixture: dinner yesterday, a cream coffee and a protein shake this morning, lunch -------
  $fx = @'
(function () {
  var S = HT.state(), t = HT.todayKey(), y = HT.shiftDate(t, -1);
  var f = function (o) { return Object.assign({ meal: 'snack', confidence: 'eyeballed', source: 'manual', notes: '', fiber_g: 0, soluble_fiber_g: 0 }, o); };
  S.days[y] = { status: 'complete', water_l: 0, items: [f({ name: 'Item dinner', meal: 'dinner', time: '20:00', kcal: 600, fat_g: 20, carb_g: 60, protein_g: 40 })] };
  S.days[t] = { status: 'in_progress', water_l: 0, items: [
    f({ name: 'Item coffee with cream', time: '08:00', kcal: 60, fat_g: 6, carb_g: 1, protein_g: 0.8 }),
    f({ name: 'Item lunch', meal: 'lunch', time: '12:00', kcal: 500, fat_g: 20, carb_g: 50, protein_g: 30 }) ] };
  S.current = t;
  HT.resave(); HT.itemCollapseAll(); HT.dayGroupsOpenAll(true); HT.refresh();
  return 1;
})()
'@
  [void](Eval $fx); WaitQuiet 'fixture'
  $hrs = "JSON.stringify(HT.fastsClosed().map(function (g) { return g.hours; }))"
  $h0 = Eval $hrs
  $rowOf = "(function(n){ return Array.prototype.filter.call(document.querySelectorAll('.mitem'), function (x) { var e = x.querySelector('.mname'); return e && e.textContent.indexOf(n) >= 0; })[0]; })"
  function OpenItem([string]$nm) {
    [void](Eval ("(function(){ var r = " + $rowOf + "(" + (ConvertTo-Json $nm) + "); if (r) r.querySelector('.mhead').setAttribute('data-gate-open', '1'); return 1; })()"))
    [void](TapSel '[data-gate-open="1"]')
    [void](Eval "(function(){ var e = document.querySelector('[data-gate-open]'); if (e) e.removeAttribute('data-gate-open'); return 1; })()")
  }
  $fastOf = "(function(n){ var r = " + $rowOf + "(n); var m = r && r.querySelector('.mfast'); if (!m) return { has: false }; return { has: true, line: m.querySelector('.mfastline').textContent, btns: Array.prototype.map.call(m.querySelectorAll('.mfastbtn'), function (b) { return { t: b.textContent, h: Math.round(b.getBoundingClientRect().height) }; }) }; })"
  # ---- GATE 1: the cream coffee keeps the fast, and says why; one tap marks it the other way ---------
  OpenItem 'Item coffee with cream'
  $c1 = EvalJ ($fastOf + "('Item coffee with cream')")
  Shot 'fast-coffee'
  Write-Host ("  fasts " + $h0 + "; coffee: " + $c1)
  $c1v = $c1 | ConvertFrom-Json
  Check (($h0 -eq '[16]') -and $c1v.has -and ($c1v.line -like 'Fast: keeps it*1 g net carbs and 0.8 g protein*within 5 g / 5 g*') -and ($c1v.btns[0].t -eq 'Breaks my fast') -and ($c1v.btns[0].h -ge 44)) "R287 FAST GATE 1: A CREAM COFFEE KEEPS THE FAST -- dinner to lunch is one 16 h fast; the opened entry says why (net carbs and protein against 5 g / 5 g) and offers 'Breaks my fast' at 44 px"
  [void](Eval ("(function(){ var r = " + $rowOf + "('Item coffee with cream'); r.querySelector('.mfastbtn').setAttribute('data-gate-fb', '1'); return 1; })()"))
  [void](TapSel '[data-gate-fb="1"]')
  $c2 = EvalJ ($fastOf + "('Item coffee with cream')")
  $h1 = Eval $hrs
  $ov = Eval "JSON.stringify(HT.state().days[HT.todayKey()].items.filter(function (x) { return x.name === 'Item coffee with cream'; })[0].fast_override)"
  Write-Host ("  marked: " + $c2 + " fasts " + $h1 + " record " + $ov)
  Check (($c2 -like '*Fast: ends it*you marked it*breaks my fast*') -and ($h1 -eq '[12]') -and ($c2 -like '*Back to the rule*') -and ($ov -like '*"v":"breaks","at":"20*')) "R287 FAST GATE 1: ONE TAP MARKS IT 'BREAKS MY FAST' -- the fast is now 12 h, the tap is kept with its time, and 'Back to the rule' is offered"
  # ---- GATE 2: the item editor carries the same line and taps -----------------------------------------
  [void](Eval "(function(){ var i = HT.state().days[HT.todayKey()].items.map(function (x) { return x.name; }).indexOf('Item lunch'); HT.openItemEdit(i); return 1; })()"); WaitQuiet 'editor'
  $e2 = EvalJ "(function(){ var im = document.getElementById('ieMsg'); var m = im && im.parentElement ? im.parentElement.querySelector('.mfast') : null; return m ? { line: m.querySelector('.mfastline').textContent, btn: (m.querySelector('.mfastbtn') || {}).textContent } : { line: '' }; })()"
  Write-Host ("  editor: " + $e2)
  Check ($e2 -like '*Fast: ends it*50 g net carbs and 30 g protein*over 5 g / 5 g*Keeps my fast*') "R287 FAST GATE 2: THE ITEM'S EDIT SAYS WHAT IT DOES TO A FAST and offers the user's mark ('Keeps my fast' on a 30 g protein lunch)"
  [void](Eval "HT.closeItemEdit()"); WaitQuiet 'editor closed'
  # ---- GATE 3: Settings states the rule in its own words, and the limits are the user's --------------
  [void](Eval "HT.openSettings(); var d = document.querySelector('[data-setting=fasting] details'); if (d) d.open = true"); WaitQuiet 'settings'
  $s3 = EvalJ "(function(){ return { note: (document.getElementById('fastRuleNote') || {}).textContent, nc: document.getElementById('fastNetCarb').value, pr: document.getElementById('fastProtein').value }; })()"
  Write-Host ("  settings: " + $s3)
  $s3v = $s3 | ConvertFrom-Json
  $words = Eval "HT.FAST_RULE_WORDS"
  [void](Eval "(function(){ var p = document.getElementById('fastProtein'); p.value = '35'; p.dispatchEvent(new Event('change', { bubbles: true })); return 1; })()"); WaitQuiet 'limit'
  $h3 = Eval $hrs
  $lim = Eval "JSON.stringify(HT.fastKeepLimits())"
  [void](Eval "(function(){ var p = document.getElementById('fastProtein'); p.value = ''; p.dispatchEvent(new Event('change', { bubbles: true })); return 1; })()"); WaitQuiet 'limit back'
  Write-Host ("  protein limit 35: fasts " + $h3 + " limits " + $lim)
  Check (($s3v.note -eq $words) -and ($s3v.nc -eq '5') -and ($s3v.pr -eq '5') -and ($words -notmatch 'ketosis|autophagy')) "R287 FAST GATE 3: SETTINGS STATES THE RULE IN THE RULING'S WORDS -- '$words' -- with the limits at 5 g / 5 g, and nothing about ketosis or autophagy"
  Check (($lim -like '*"protein":35*') -and ($h3 -eq '[12]')) "R287 FAST GATE 3: THE LIMITS ARE THE USER'S -- protein up to 35 g is taken; the user's own 'breaks my fast' on the coffee still wins over it"
  [void](Eval "HT.closeSettings()"); WaitQuiet 'settings closed'
  # ---- GATE 4: the weekly review's fasting i says the same -------------------------------------------
  [void](Eval "HT.openWeek(HT.todayKey())"); WaitQuiet 'week'
  $w4 = Eval "(function(){ var c = document.querySelector('#weekBody [data-card=fasting]'); return c ? c.textContent : ''; })()"
  [void](Eval "HT.closeWeek()")
  Check ($w4 -like ('*' + $words + '*')) "R287 FAST GATE 4: THE WEEKLY REVIEW'S FASTING NOTE STATES THE SAME RULE, word for word"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("FASTRULE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "FASTRULE GATE: PASS -- a fat-only item keeps a fast and says why, the user's mark flips it with its time kept, the editor and Settings carry the rule in its own words, and the limits are the user's."
Write-Host "GATE: PASS"
exit 0
