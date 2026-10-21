# R246 PART 1 -- THE DAILY STACK, ONE CHECKBOX ROW PER ITEM. By real taps at 390 px.
#
#   One tap on a row = taken NOW at the item's usual dose, linked to its item.
#   Tapping the dose or the time edits it; what the user changes is stored as
#   stated by them, and survives a reload. Unchecking removes it, with Undo; an
#   unchecked item is NOT TAKEN that day, and the export says so beside "taken".
#   Took all checks every item not yet taken. The ruled gates: one tap = checked at
#   Now with the usual dose; an edit persists; unchecked counts as not taken; Took
#   all then uncheck one -> N-1; two taps for the common case (+ Log, Took all).
#   R255: an item added today reads "not in stack yet" yesterday -- on the sheet,
#   uncounted and without a checkbox, and in the backup.
#   R256: every switch of the Settings include box is kept with its time; off at 09:00
#   and on at 15:30 the same day both stay; a day off all day reads "switched off";
#   a partial day's times sit behind the item's info button; the backup lists them.
#
# Synthetic items only (the Gate items); never the user's stack (R204).
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8323
$Dbg = 9529
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-stackcheck-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set STACKCHECK_SHOTS=1 to save 390px screenshots to %TEMP%\stackcheck-shots.
$shots = $null
if ($env:STACKCHECK_SHOTS) { $shots = Join-Path $env:TEMP 'stackcheck-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.stackCheck === 'function' && typeof HT.exportStackDays === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R246 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: a synthetic stack, never the user's (R204), saved and reloaded ----------
  [void](Eval @'
(function () {
  var S = HT.state();
  // R255: joined the stack three days ago, as the backfill would date them
  var d3 = new Date(); d3.setDate(d3.getDate() - 3);
  var k3 = d3.getFullYear() + '-' + ('0' + (d3.getMonth() + 1)).slice(-2) + '-' + ('0' + d3.getDate()).slice(-2);
  S.settings.stack = HT.normalizeStack([
    { id: 'g1', added_on: k3, added_basis: 'created', name: 'Gate D', kind: 'supplement', dose: 1000, dose_unit: 'IU' },
    { id: 'g2', added_on: k3, added_basis: 'created', name: 'Gate capsule', kind: 'medication', dose: 2, dose_unit: 'capsule' },
    { id: 'g3', added_on: k3, added_basis: 'created', name: 'Gate oil', kind: 'food', part: { name: 'Gate oil row', grams: 10, kcal: 90, fat_g: 10, protein_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0,
      confidence: 'eyeballed', source: 'corpus', ref: { ns: 'cnf', id: '9', name: 'Gate oil row', hash: 'h', attribution: 'CNF', g: 10, v: { '208': 90, '204': 10 } } } } ]);
  HT.resave();
  return 1;
})()
'@)
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Milliseconds 2500
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  $state = "(function(){ var S = HT.state(), t = HT.todayKey(); var tl = (S.timeline[t] || []).filter(function (r) { return r.kind === 'medication'; }); var it = (S.days[t] || { items: [] }).items; return { doses: tl.map(function (r) { return r.name + '|' + r.dose + '|' + r.dose_unit + '|' + r.time + '|' + r.stackId + '|' + (r.stated || []).join('+'); }), foods: it.map(function (i) { return i.name + '|' + i.grams + '|' + i.time + '|' + i.stackId; }), now: (function () { var d = new Date(); return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2); })(), head: ((document.querySelector('#sheetRoot .stkopen') || {}).textContent || '') }; })()"

  # ---- 1. THE COMMON CASE IN TWO TAPS: + Log, Took all ------------------------------------
  $taps = 0
  [void](Eval "document.getElementById('fab').click()"); $taps++
  Settle
  $h0 = EvalJ "(function(){ var b = document.querySelector('#sheetRoot .stkopen'), a = document.querySelector('#sheetRoot .stkall'); var rb = b.getBoundingClientRect(), ra = a.getBoundingClientRect(); var s = document.querySelector('#sheetRoot .srbtn'); return { head: b.textContent, all: a.textContent, h: Math.round(rb.height), ah: Math.round(ra.height), px: parseFloat(getComputedStyle(b).fontSize), rows: document.querySelectorAll('#sheetRoot .stkrow').length, searchSeen: s ? s.getBoundingClientRect().bottom <= window.innerHeight : false }; })()"
  Write-Host ("  + Log: " + $h0)
  $h0v = $h0 | ConvertFrom-Json
  Check (($h0v.head -eq ('Daily stack ' + [char]0xB7 + ' 0 of 3 taken')) -and ($h0v.all -eq 'Took all') -and ($h0v.rows -eq 0) -and ($h0v.h -ge 44) -and ($h0v.ah -ge 44) -and ($h0v.px -ge 16)) "R246: + Log shows the stack as ONE line -- '0 of 3 taken' and Took all, 44 px, 16px -- not a list"
  Check ($h0v.searchSeen -eq $true) "and the four ways in, Search among them, stay above the fold (R197/2)"
  [void](Eval "document.querySelector('#sheetRoot .stkall').click()"); $taps++
  Settle
  $t1 = EvalJ $state
  Write-Host ("  Took all: " + $t1)
  $t1v = $t1 | ConvertFrom-Json
  $now = $t1v.now
  Check (($taps -eq 2) -and (@($t1v.doses).Count -eq 2) -and (@($t1v.foods).Count -eq 1) -and (@($t1v.doses) -contains ('Gate D|1000|IU|' + $now + '|g1|')) -and (@($t1v.doses) -contains ('Gate capsule|2|capsule|' + $now + '|g2|')) -and ($t1v.foods[0] -eq ('Gate oil row|10|' + $now + '|g3'))) "R246 GATE: TWO TAPS FOR THE COMMON CASE -- + Log, Took all: all three taken now at their usual doses, each linked to its item"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $t1u = EvalJ $state
  Check ($t1u -like '*"doses":[]*"foods":[]*') "and Took all's Undo takes all three back"

  # ---- 2. ONE ROW, ONE TAP: taken now at the usual dose ------------------------------------
  [void](Eval "(function(){ HT.closeSheet(); document.getElementById('fab').click(); document.querySelector('#sheetRoot .stkopen').click(); return 1; })()")
  Settle
  $r0 = EvalJ "(function(){ var rows = document.querySelectorAll('#sheetRoot .stkrow'); return { n: rows.length, checked: document.querySelectorAll('#sheetRoot .stkrow input:checked').length, sub: Array.prototype.map.call(rows, function (r) { return (r.querySelector('.stksub') || {}).textContent || ''; }) }; })()"
  Write-Host ("  opened: " + $r0)
  $r0v = $r0 | ConvertFrom-Json
  Check (($r0v.n -eq 3) -and ($r0v.checked -eq 0) -and ($r0v.sub[0] -like ('Supplement ' + [char]0xB7 + ' usual 1000 IU ' + [char]0xB7 + ' not taken'))) "R246: opened, each item is a checkbox row, unchecked, saying its usual dose and 'not taken'"
  [void](Eval "document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]')[0].click()")
  Settle
  $r1 = EvalJ "(function(){ var r = document.querySelectorAll('#sheetRoot .stkrow')[0]; var d = r.querySelector('.stkdose'), t = r.querySelector('.stktime'); var rd = d ? d.getBoundingClientRect() : null, rt = t ? t.getBoundingClientRect() : null; return { checked: r.querySelector('input').checked, line: r.innerText.replace(/\s+/g, ' ').trim(), dose: d ? d.textContent : '', time: t ? t.textContent : '', dh: rd ? Math.round(rd.height) : 0, dw: rd ? Math.round(rd.width) : 0, th: rt ? Math.round(rt.height) : 0, tw: rt ? Math.round(rt.width) : 0, px: d ? parseFloat(getComputedStyle(d).fontSize) : 0, head: document.querySelector('#sheetRoot .stkopen').textContent, wide: document.documentElement.scrollWidth - document.documentElement.clientWidth }; })()"
  Write-Host ("  one tap: " + $r1)
  $r1v = $r1 | ConvertFrom-Json
  $t2 = EvalJ $state
  $t2v = $t2 | ConvertFrom-Json
  Check (($r1v.checked -eq $true) -and (@($t2v.doses).Count -eq 1) -and ($t2v.doses[0] -eq ('Gate D|1000|IU|' + $t2v.now + '|g1|'))) "R246 GATE: ONE TAP = CHECKED, taken NOW at the USUAL dose -- 1000 IU, linked to its item, nothing stated"
  Check (($r1v.line -like ('Gate D 1000 IU ' + $t2v.now + '*')) -and ($r1v.head -eq ('Daily stack ' + [char]0xB7 + ' 1 of 3 taken'))) ("R246: the row reads 'Gate D . 1000 IU . " + $t2v.now + "' and the head counts it (" + $r1v.line + ")")
  Check (($r1v.dh -ge 44) -and ($r1v.dw -ge 44) -and ($r1v.th -ge 44) -and ($r1v.tw -ge 44) -and ($r1v.px -ge 16) -and ($r1v.wide -le 0)) "the dose and the time are each a 44 x 44 control at 16px, nothing off the side at 390 px"
  Shot 'stack-checked'

  # ---- 3. THE DOSE AND THE TIME, EDITED -- AND KEPT -----------------------------------------
  [void](Eval "document.querySelectorAll('#sheetRoot .stkrow')[0].querySelector('.stkdose').click()")
  Settle
  $e0 = EvalJ "(function(){ var f = document.getElementById('stkEdDose'), u = document.getElementById('stkEdUnit'); return { v: f ? f.value : '', unit: u ? u.value : '', focus: document.activeElement === f }; })()"
  Check ($e0 -like '*"v":"1000"*"unit":"IU"*"focus":true*') "tapping the dose opens its editor, amount and unit filled in and focused"
  Shot 'stack-dose'
  [void](Eval "(function(){ var f = document.getElementById('stkEdDose'); f.focus(); f.select(); return 1; })()")
  TypeText '2000'
  [void](Eval "document.querySelector('#sheetRoot .stkedsave').click()")
  Settle
  [void](Eval "document.querySelectorAll('#sheetRoot .stkrow')[0].querySelector('.stktime').click()")
  Settle
  $e1 = EvalJ "(function(){ var t = document.getElementById('stkEdTime'); var n = document.querySelector('#sheetRoot .stkednow'); return { t: t ? t.value : '', now: n ? n.textContent : '' }; })()"
  Check ($e1 -like '*"now":"Now"*') "tapping the time opens its editor, offering Now or another time"
  Shot 'stack-time'
  [void](Eval "(function(){ var t = document.getElementById('stkEdTime'); t.value = '07:45'; document.querySelector('#sheetRoot .stkedsave').click(); return 1; })()")
  Settle
  $t3 = EvalJ $state
  Write-Host ("  edited: " + $t3)
  Check ($t3 -like '*"Gate D|2000|IU|07:45|g1|dose+time"*') "R246 GATE: AN EDIT IS THE RECORD -- 2000 IU at 07:45, both STATED BY THE USER"
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Milliseconds 2500
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  [void](Eval "(function(){ document.getElementById('fab').click(); document.querySelector('#sheetRoot .stkopen').click(); return 1; })()")
  Settle
  $p1 = EvalJ "(function(){ var r = document.querySelectorAll('#sheetRoot .stkrow')[0]; return { checked: r.querySelector('input').checked, dose: (r.querySelector('.stkdose') || {}).textContent, time: (r.querySelector('.stktime') || {}).textContent }; })()"
  $t4 = EvalJ $state
  Write-Host ("  after a reload: " + $p1 + " " + $t4)
  Check (($p1 -like '*"checked":true*"dose":"2000 IU"*"time":"07:45"*') -and ($t4 -like '*"Gate D|2000|IU|07:45|g1|dose+time"*')) "R246 GATE: AN EDIT PERSISTS -- after a reload the row is still checked at 2000 IU, 07:45, and the record still says what the user stated"

  # ---- 4. UNCHECKED = NOT TAKEN; Undo -------------------------------------------------------
  $x0 = EvalJ "(function(){ var d = JSON.parse(HT.exportJSON()).stackDays.days[HT.todayKey()] || []; return d.map(function (r) { return r.name + ':' + r.status + (r.doses ? '@' + r.doses.map(function (x) { return x.time + '/' + x.amount + x.unit + '/' + (x.stated || []).join('+'); }).join(';') : ''); }); })()"
  Write-Host ("  export, Gate D taken: " + $x0)
  Check ($x0 -like '*"Gate D:taken@07:45/2000IU/dose+time"*') "R246 GATE: the export says TAKEN with the time, the dose and what the user stated"
  [void](Eval "document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]')[0].click()")
  Settle
  $x1 = EvalJ "(function(){ var d = JSON.parse(HT.exportJSON()).stackDays.days[HT.todayKey()] || []; return { exp: d.map(function (r) { return r.name + ':' + r.status; }), checked: document.querySelectorAll('#sheetRoot .stkrow input:checked').length, head: document.querySelector('#sheetRoot .stkopen').textContent, toast: (document.getElementById('toast') || {}).textContent || '' }; })()"
  Write-Host ("  unchecked: " + $x1)
  Check (($x1 -like '*"Gate D:not taken"*') -and ($x1 -like '*"checked":0*') -and ($x1 -like ('*0 of 3 taken*')) -and ($x1 -like '*Unchecked Gate D*Undo*')) "R246 GATE: UNCHECKED COUNTS AS NOT TAKEN -- the record is gone, the export says 'not taken', with Undo offered"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $t5 = EvalJ $state
  Check ($t5 -like '*"Gate D|2000|IU|07:45|g1|dose+time"*') "and Undo puts the same record back -- its edited dose and time with it"

  # ---- 5. TOOK ALL, THEN UNCHECK ONE -> N-1 --------------------------------------------------
  [void](Eval "document.querySelector('#sheetRoot .stkall').click()")
  Settle
  $n3 = EvalJ "(function(){ return { on: document.querySelectorAll('#sheetRoot .stkrow input:checked').length, done: !!document.querySelector('#sheetRoot .stkalldone'), all: !!document.querySelector('#sheetRoot .stkall') }; })()"
  Check ($n3 -like '*"on":3*"done":true*"all":false*') "Took all checks the two not yet taken, keeps the one that was, and then reads 'all taken'"
  $t6 = EvalJ $state
  Check ($t6 -like '*"Gate D|2000|IU|07:45|g1|dose+time"*') "and leaves the edited Gate D as it was -- Took all takes only what is not yet checked"
  [void](Eval "document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]')[1].click()")
  Settle
  $n4 = EvalJ "(function(){ var d = JSON.parse(HT.exportJSON()).stackDays.days[HT.todayKey()] || []; return { on: document.querySelectorAll('#sheetRoot .stkrow input:checked').length, head: document.querySelector('#sheetRoot .stkopen').textContent, exp: d.map(function (r) { return r.name + ':' + r.status; }) }; })()"
  Write-Host ("  Took all, then one unchecked: " + $n4)
  Check (($n4 -like '*"on":2*') -and ($n4 -like '*2 of 3 taken*') -and ($n4 -like '*"Gate D:taken","Gate capsule:not taken","Gate oil:taken"*')) "R246 GATE: TOOK ALL, THEN UNCHECK ONE -> N-1 -- two of three taken, the capsule not taken in the export"
  Shot 'stack-n-1'

  # ---- 6. R255: AN ITEM ADDED TODAY READS "NOT IN STACK YET" YESTERDAY -----------------------
  # Added through the editor's own save (stackUpsert), then everything else by taps:
  # back one day, + Log, open the stack.
  [void](Eval @'
(function () {
  HT.closeSheet();
  var r = HT.stackUpsert({ name: 'Gate new', kind: 'supplement', dose: 5, dose_unit: 'mg' });
  var d = new Date(); d.setDate(d.getDate() - 1);
  var yk = d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  HT.state().days[yk] = { status: 'in_progress', items: [], water_l: 0 };
  HT.resave();
  return r.ok;
})()
'@)
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Milliseconds 2500
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  $a0 = EvalJ "(function(){ var t = HT.todayKey(); var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Gate new'; })[0] || {}; var s = Array.prototype.map.call(document.querySelectorAll('#stackEditor .stksince'), function (e) { return e.textContent; }); return { added: g.added_on === t, basis: g.added_basis, since: s }; })()"
  Write-Host ("  added: " + $a0)
  Check (($a0 -like '*"added":true*"basis":"added"*') -and ($a0 -like '*(the day it was added)*') -and ($a0 -like '*(the day it was created in Settings)*')) "R255: a new item joins the stack today, and Settings says since when and by which rule"
  [void](Eval "(function(){ var b = Array.prototype.filter.call(document.querySelectorAll('.navbtn'), function (x) { return x.textContent.indexOf(String.fromCharCode(8249)) >= 0; })[0]; b.click(); return 1; })()")
  Settle
  [void](Eval "document.getElementById('fab').click()")
  Settle
  [void](Eval "document.querySelector('#sheetRoot .stkopen').click()")
  Settle
  $y0 = EvalJ "(function(){ var n = document.querySelector('#sheetRoot .stknotyet'); return { day: HT.state().current, head: document.querySelector('#sheetRoot .stkopen').textContent, boxes: document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]').length, line: n ? n.innerText.replace(/\s+/g, ' ').trim() : '', box: n ? n.querySelectorAll('input').length : -1, px: n ? parseFloat(getComputedStyle(n.querySelector('.stksub')).fontSize) : 0, wide: document.documentElement.scrollWidth - document.documentElement.clientWidth }; })()"
  Write-Host ("  yesterday: " + $y0)
  $y0v = $y0 | ConvertFrom-Json
  Check (($y0v.day -ne (Eval "HT.todayKey()")) -and ($y0v.head -eq ('Daily stack ' + [char]0xB7 + ' 0 of 3 taken')) -and ($y0v.boxes -eq 3) -and ($y0v.line -like ('Gate new*not in stack yet*')) -and ($y0v.box -eq 0) -and ($y0v.px -ge 16) -and ($y0v.wide -le 0)) "R255 GATE: AN ITEM ADDED TODAY READS 'NOT IN STACK YET' YESTERDAY -- shown without a checkbox, not counted (0 of 3), never 'not taken'"
  $y1 = EvalJ "(function(){ var t = HT.state().current; var d = JSON.parse(HT.exportJSON()).stackDays.days[t] || []; return d.map(function (r) { return r.name + ':' + r.status; }); })()"
  Write-Host ("  export, yesterday: " + $y1)
  Check (($y1 -like '*"Gate new:not in stack yet"*') -and ($y1 -like '*"Gate D:not taken"*') -and ($y1 -notlike '*"Gate new:not taken"*')) "R255 GATE: and the backup says the same for that day -- 'not in stack yet', beside the items that were in it"
  Shot 'stack-notyet'

  # ---- 7. R256: EVERY SWITCH, WITH ITS TIME --------------------------------------------------
  # The include box in Settings, clicked, with the app's clock pinned for each click:
  # two days ago 21:00 off; today 08:00 on, 09:00 off, 15:30 on. So yesterday was off
  # all day and today is a partial day.
  [void](Eval @'
(function () {
  HT.closeSheet();
  var box = function () { return document.querySelector('#stackEditor input[aria-label="include Gate capsule in the daily stack"]'); };
  var at = function (dd, h, m) { var d = new Date(); d.setDate(d.getDate() + dd); d.setHours(h, m, 0, 0); var t = d.getTime(); HT.setClock(function () { return t; }); };
  at(-2, 21, 0); box().click();
  at(0, 8, 0); box().click();
  at(0, 9, 0); box().click();
  at(0, 15, 30); box().click();
  HT.setClock(null);
  return 1;
})()
'@)
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Milliseconds 2500
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  $w0 = EvalJ "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Gate capsule'; })[0] || {}; var t = HT.todayKey(); return { ev: (g.switches || []).map(function (e) { return (e.on ? 'on' : 'off') + '@' + (e.at.slice(0, 10) === t ? 'today' : 'earlier') + e.at.slice(10) + (e.stated ? '/stated' : '') + (typeof e.tzo === 'number' ? '/tzo' : ''); }), on: g.enabled }; })()"
  Write-Host ("  switches, after a reload: " + $w0)
  Check (($w0 -like '*"off@earlierT21:00:00/stated/tzo","on@todayT08:00:00/stated/tzo","off@todayT09:00:00/stated/tzo","on@todayT15:30:00/stated/tzo"*') -and ($w0 -like '*"on":true*')) "R256 GATE: OFF AT 09:00 AND ON AT 15:30 THE SAME DAY -- every click stored with its full time, offset and 'stated', all four kept through a reload"
  $nav = "(function (dd) { var d = new Date(); d.setDate(d.getDate() + dd); var k = d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); for (var i = 0; i < 6 && HT.state().current !== k; i++) { var ch = HT.state().current > k ? 8249 : 8250; var b = Array.prototype.filter.call(document.querySelectorAll('.navbtn'), function (x) { return x.textContent.indexOf(String.fromCharCode(ch)) >= 0; })[0]; if (!b) break; b.click(); } return HT.state().current === k; })"
  $ok0 = Eval ($nav + "(0)")
  [void](Eval "document.getElementById('fab').click()")
  Settle
  [void](Eval "document.querySelector('#sheetRoot .stkopen').click()")
  Settle
  [void](Eval "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#sheetRoot .stkrow'), function (x) { return x.innerText.indexOf('Gate capsule') >= 0; })[0]; r.querySelector('.stkinfosum').click(); return 1; })()")
  Settle
  $w1 = EvalJ "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#sheetRoot .stkrow'), function (x) { return x.innerText.indexOf('Gate capsule') >= 0; })[0]; var sm = r.querySelector('.stkinfosum'), b = r.querySelector('.stkinfobody'); var rs = sm.getBoundingClientRect(); return { box: r.querySelectorAll('input[type=checkbox]').length, info: b ? b.innerText : '', seen: b ? b.getBoundingClientRect().height > 0 : false, h: Math.round(rs.height), w: Math.round(rs.width), px: b ? parseFloat(getComputedStyle(b).fontSize) : 0, wide: document.documentElement.scrollWidth - document.documentElement.clientWidth }; })()"
  Write-Host ("  today: " + $ok0 + " " + $w1)
  $w1v = $w1 | ConvertFrom-Json
  Check (($ok0 -eq $true) -and ($w1v.box -eq 1) -and ($w1v.info -eq ('Switched on 08:00 ' + [char]0xB7 + ' switched off 09:00 ' + [char]0xB7 + ' switched on 15:30')) -and $w1v.seen -and ($w1v.h -ge 44) -and ($w1v.w -ge 44) -and ($w1v.px -ge 16) -and ($w1v.wide -le 0)) "R256 GATE: A PARTIAL DAY shows the item, with its checkbox, and every switch time behind its info button (44 px, 16px)"
  Shot 'stack-switch-times'
  [void](Eval "HT.closeSheet()")
  $ok1 = Eval ($nav + "(-1)")
  [void](Eval "document.getElementById('fab').click()")
  Settle
  [void](Eval "document.querySelector('#sheetRoot .stkopen').click()")
  Settle
  $w2 = EvalJ "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#sheetRoot .stkrow'), function (x) { return x.innerText.indexOf('Gate capsule') >= 0; })[0]; var d = JSON.parse(HT.exportJSON()).stackDays; var it = d.items.filter(function (i) { return i.name === 'Gate capsule'; })[0]; return { line: r ? r.innerText.replace(/\s+/g, ' ').trim() : '', box: r ? r.querySelectorAll('input').length : -1, head: document.querySelector('#sheetRoot .stkopen').textContent, exp: (d.days[HT.state().current] || []).filter(function (x) { return x.name === 'Gate capsule'; }).map(function (x) { return x.status; }), events: it ? it.switches.length : 0, nine: it ? it.switches.filter(function (e) { return !e.on && /T09:00:00$/.test(e.at); }).length : 0 }; })()"
  Write-Host ("  yesterday: " + $ok1 + " " + $w2)
  $w2v = $w2 | ConvertFrom-Json
  Check (($ok1 -eq $true) -and ($w2v.line -eq ('Gate capsule Medication ' + [char]0xB7 + ' switched off')) -and ($w2v.box -eq 0) -and ($w2v.head -eq ('Daily stack ' + [char]0xB7 + ' 0 of 2 taken')) -and ((@($w2v.exp) -join ',') -eq 'switched off')) "R256 GATE: ON A DAY IT WAS OFF ALL DAY THE ITEM READS 'SWITCHED OFF' -- no checkbox, not counted (0 of 2), and the backup says the same"
  Check (($w2 -like '*"events":4*') -and ($w2 -like '*"nine":1*')) "R256 GATE: THE BACKUP LISTS THE EVENTS -- all four for the item, the 09:00 off among them"
  Shot 'stack-switched-off'

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("STACK CHECK GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "STACK CHECK GATE: PASS -- + Log, Took all logs the stack in two taps; one tap on a row"
Write-Host "  is taken now at the usual dose; an edited dose and time are stated and survive a"
Write-Host "  reload; unchecked is not taken in the export; Took all then uncheck one is N-1;"
Write-Host "  an item added today reads 'not in stack yet' yesterday, on the sheet and in the backup;"
Write-Host "  every switch is kept with its time, an off day reads 'switched off', the backup lists them."
Write-Host "GATE: PASS"
exit 0
