# C (R213 + R237/C3) -- THE USER'S OWN FOODS IN SEARCH, AND FOODS LOGGED BEFORE
# WITH NO DATABASE MATCH OFFERED FIRST. By real typing and real taps at 390 px.
#
#   R213  "Not yet offered in the Search pane": a food of the user's own is found
#         in Search, above the database, opens at its serving and logs THEIR
#         numbers (manual, its basis, no citation).
#   C3    The Search half of R237/C3 (the photo half shipped in v0.104.0): a food
#         logged before that no database row answers is offered next time, above
#         the database, and ONE TAP logs it again as last time -- its grams, its
#         numbers, or the amount tapped and edited first (R254/1). A food that
#         had NO numbers is never re-logged by its row: it opens the picker for its
#         name, and only "Log without nutrition" saves it with none (R254/2).
#
# Synthetic names only (the Zebra foods); never the user's.
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8321
$Dbg = 9527
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-searchmine-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set SEARCHMINE_SHOTS=1 to save 390px screenshots to %TEMP%\searchmine-shots.
$shots = $null
if ($env:SEARCHMINE_SHOTS) { $shots = Join-Path $env:TEMP 'searchmine-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.searchEarlier === 'function' && typeof HT.searchPickMine === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the C functions are not on HT"; Cleanup; exit 2 }
  [void](EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok) }; })")

  # ---- the fixture: synthetic names only, never the user's foods -------------------
  # Yesterday: a photo item the database never matched (the AI's estimate), a second
  # one with no numbers at all, and a matched item that must NOT be offered here.
  # Plus one of the user's own foods, from its label, 40 g a serving.
  $fx = EvalJ @'
(function () {
  var S = HT.state(), t = HT.todayKey();
  var d = new Date(t + 'T12:00:00'); d.setDate(d.getDate() - 1);
  var y = d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  var base = { meal: 'lunch', time: '12:30', protein_g: 4, fat_g: 12, carb_g: 30, fiber_g: 1, soluble_fiber_g: 0, confidence: 'eyeballed', notes: '', source: 'ai-paste' };
  S.days[y] = { status: 'in_progress', water_l: 0, items: [
    HT.normalizeItem(Object.assign({}, base, { name: 'Zebra tart', grams: 80, kcal: 250 }), true),
    HT.normalizeItem({ name: 'Zebra stew', meal: 'dinner', time: '19:00', grams: 300, unresolved: true, confidence: 'eyeballed', notes: '', source: 'ai-paste' }, true),
    HT.normalizeItem(Object.assign({}, base, { name: 'Zebra cake', grams: 100, kcal: 300, source: 'corpus', ref: { ns: 'cnf', id: '1', name: 'Zebra cake row', g: 100, v: { '208': 300 } } }), true) ] };
  var f = HT.myFoodUpsert({ name: 'Zebra bar', basis: 'label', per: 'serving', serving_g: 40, kcal: 180, fat_g: 8, carb_g: 22, protein_g: 5 });
  HT.resave();
  return { y: y, food: f.ok, today: (S.days[t] || { items: [] }).items.length };
})()
'@
  Write-Host ("  fixture: " + $fx)
  $fxv = $fx | ConvertFrom-Json
  $yday = $fxv.y
  $today0 = [int]$fxv.today

  # ---- 1. typed into Search, the user's own come first --------------------------------
  [void](Eval "(function(){ HT.openSheet(); var b = null; Array.prototype.forEach.call(document.querySelectorAll('#sheetRoot .srbtn'), function (x) { if (x.textContent === 'Search') b = x; }); b.click(); document.getElementById('fqQuery').focus(); return 1; })()")
  TypeText 'zebra'
  Settle
  $l1 = EvalJ @'
(function () {
  var box = document.getElementById('fqRows');
  var kids = Array.prototype.filter.call(box.querySelectorAll('.fqexit,.fqcap,.fqrow'), function (e) { return e.getBoundingClientRect().height > 0; });
  var seq = kids.map(function (e) {
    if (e.classList.contains('fqexit')) return 'exit';
    if (e.classList.contains('fqcap')) return 'cap:' + e.textContent.split(',')[0];
    if (e.classList.contains('fqown')) return 'own:' + e.querySelector('.fqnm').textContent;
    if (e.classList.contains('fqearlier')) return 'earlier:' + e.querySelector('.fqnm').textContent;
    return 'db';
  });
  var rows = box.querySelectorAll('.fqown,.fqearlier,.fqamt');
  var small = 0, low = 0;
  Array.prototype.forEach.call(rows, function (r) {
    if (r.getBoundingClientRect().height < 44) low++;
    Array.prototype.forEach.call(r.querySelectorAll('span'), function (s) { if (parseFloat(getComputedStyle(s).fontSize) < 16) small++; });
  });
  var e = box.querySelectorAll('.fqearlier');
  var amts = box.querySelectorAll('.fqamt');
  var a0 = amts[0] ? amts[0].getBoundingClientRect() : null;
  return { field: document.getElementById('fqQuery').value, seq: seq, low: low, small: small,
           wide: document.documentElement.scrollWidth - document.documentElement.clientWidth,
           stew: e[0] ? e[0].querySelector('.fqmac').textContent : '', tart: e[1] ? e[1].querySelector('.fqmac').textContent : '',
           amts: amts.length, amt: amts[0] ? amts[0].innerText.replace(/\s+/g, ' ').trim() : '', amtH: a0 ? Math.round(a0.height) : 0, amtW: a0 ? Math.round(a0.width) : 0,
           amtPx: amts[0] ? parseFloat(getComputedStyle(amts[0]).fontSize) : 0, amtRowOfTart: !!(amts[0] && amts[0].parentNode.querySelector('.fqnm').textContent === 'Zebra tart'),
           amtLook: amts[0] ? (getComputedStyle(amts[0]).borderStyle + '|' + getComputedStyle(amts[0].querySelector('.fqamtw')).textDecorationLine) : '' };
})()
'@
  Write-Host ("  the list: " + $l1)
  $l1v = $l1 | ConvertFrom-Json
  $seq = @($l1v.seq) -join ' > '
  Check ($l1v.field -eq 'zebra') "the field keeps what was typed, one character at a time (the caret rule)"
  Check ($seq -like 'exit > cap:Your foods > own:Zebra bar > cap:You logged before > earlier:Zebra stew > earlier:Zebra tart*') ("C GATE: THE USER'S OWN COME FIRST -- 'Not here?' at the top, then Your foods, then the foods logged before with no database match, then the database (" + $seq + ")")
  Check (-not ($seq -like '*Zebra cake*')) "C: an item that HAS a database row is not offered as unmatched"
  Check (($l1v.tart -like 'Log again as last time (*): 250 cal, an estimate') -and ($l1v.stew -like 'No numbers last time * pick a food')) "R254: the row with numbers SAYS WHAT ONE TAP WILL LOG; the row with none says 'No numbers last time - pick a food'"
  Check ((($l1v.amts -eq 1) -and ($l1v.amtRowOfTart -eq $true) -and ($l1v.amt -eq '80 g change'))) ("R254/1: the amount is ITS OWN CONTROL on the row with numbers -- '80 g', marked 'change' -- and the row with none has no amount (" + $l1v.amt + ")")
  Check ((($l1v.amtH -ge 44) -and ($l1v.amtW -ge 44) -and ($l1v.amtPx -ge 16) -and ($l1v.amtLook -like '*underline*'))) ("R254/1: the amount control is at least 44 x 44 at 16px and visibly a control (a button, its word underlined): " + $l1v.amtH + " x " + $l1v.amtW + ", " + $l1v.amtLook)
  Check (($l1v.low -eq 0) -and ($l1v.small -eq 0) -and ($l1v.wide -le 0)) "every row is a 44 px target in 16px type, nothing off the side at 390 px"
  Shot 'search-mine-list'

  # ---- 2. one of the user's own foods: the amount step, at its serving ----------------
  [void](Eval "document.querySelector('#fqRows .fqown').click()")
  Settle
  $s2 = EvalJ "(function(){ var st = document.querySelector('#searchBox .fqstep'); var g = document.getElementById('fqGrams'); var b = document.querySelector('#fqLog .fqlog'); return { name: (st.querySelector('.qsname') || {}).textContent, text: st.innerText.replace(/\s+/g, ' '), grams: g ? g.value : '', btn: b ? b.textContent : '', dis: b ? b.disabled : null, cite: !!st.querySelector('.fqcite') }; })()"
  Write-Host ("  the step: " + $s2)
  $s2v = $s2 | ConvertFrom-Json
  Check (($s2v.name -eq 'Zebra bar') -and ($s2v.grams -eq '40') -and ($s2v.btn -eq 'Log 180 cal') -and ($s2v.dis -eq $false)) "C GATE: a food of the user's own opens AT ITS SERVING -- 40 g filled in, 'Log 180 cal' ready"
  Check (($s2v.text -like '*Your food, from label, per 100 g*your own numbers, from its label*') -and ($s2v.cite -eq $false)) "and says whose numbers they are -- the user's, from its label -- with no database citation, because it has none"
  Shot 'search-mine-step'
  [void](Eval "(function(){ var g = document.getElementById('fqGrams'); g.focus(); g.select(); return 1; })()")
  TypeText '60'
  Settle
  $s2b = Eval "(document.querySelector('#fqLog .fqlog') || {}).textContent"
  Check ($s2b -eq 'Log 270 cal') ("an amount typed over the serving re-counts it: 60 g is 270 cal (" + $s2b + ")")
  [void](Eval "document.querySelector('#fqLog .fqlog').click()")
  Settle
  $m3 = EvalJ "(function(){ var it = HT.state().days[HT.todayKey()].items.slice(-1)[0] || {}; return { n: HT.state().days[HT.todayKey()].items.length, it: it.name + '|' + it.grams + '|' + Math.round(it.kcal) + '|' + Math.round(it.fat_g) + '|' + it.source + '|' + it.basis + '|' + it.confidence + '|' + (it.ref ? 'ref' : 'no-ref') + '|' + (it.unresolved ? 'unres' : 'counted'), sheet: !!document.querySelector('.sheet.open, #sheet.open') }; })()"
  Write-Host ("  logged: " + $m3)
  $m3v = $m3 | ConvertFrom-Json
  Check (([int]$m3v.n -eq ($today0 + 1)) -and ($m3v.it -eq 'Zebra bar|60|270|12|manual|label|measured|no-ref|counted')) "C GATE: LOGGED WITH THE USER'S NUMBERS -- 60 g, 270 cal, 12 g fat, manual, from label, no database citation, counted"

  # ---- 3. an earlier food with numbers: ONE TAP on the row, at the amount shown ---------
  $openSearch = "(function(){ HT.openSheet(); var b = null; Array.prototype.forEach.call(document.querySelectorAll('#sheetRoot .srbtn'), function (x) { if (x.textContent === 'Search') b = x; }); b.click(); document.getElementById('fqQuery').focus(); return 1; })()"
  $pastJ = "JSON.stringify(HT.state().days['$yday'])"
  $past0 = Eval $pastJ
  [void](Eval $openSearch)
  TypeText 'zebra ta'
  Settle
  $taps = 0
  $e1 = Eval "(function(){ var r = document.querySelector('#fqRows .fqearlier'); if (!r) return ''; var n = r.querySelector('.fqnm').textContent; r.click(); return n; })()"
  $taps++
  Settle
  $e3 = EvalJ ("(function(){ var items = HT.state().days[HT.todayKey()].items; var it = items.slice(-1)[0] || {}; return { n: items.length, it: it.name + '|' + it.grams + '|' + Math.round(it.kcal) + '|' + it.source + '|' + it.confidence + '|' + (it.ref ? 'ref' : 'no-ref'), from: (it.repeated_from || {}).date, time: it.time, meal: it.meal, toast: (document.getElementById('toast') || {}).textContent || '' }; })()")
  Write-Host ("  one tap: " + $e1 + " -> " + $e3)
  $e3v = $e3 | ConvertFrom-Json
  Check (($e1 -eq 'Zebra tart') -and ([int]$e3v.n -eq ($today0 + 2)) -and ($taps -eq 1)) "R254/1 GATE: ONE TAP on the row logs it at once -- no amount step, no confirm"
  Check (($e3v.it -eq 'Zebra tart|80|250|ai-paste|eyeballed|no-ref') -and ($e3v.from -eq $yday)) "R254/1 GATE: AT THE AMOUNT SHOWN -- 80 g, 250 cal, still the AI's estimate at its own confidence, recorded as a repeat of yesterday's"
  Check (($e3v.time -match '^\d\d:\d\d$') -and ($e3v.toast -like 'Logged Zebra tart*Undo*')) "a new record at today's time, offered with Undo"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $u3 = Eval "HT.state().days[HT.todayKey()].items.length"
  Check ([int]$u3 -eq ($today0 + 1)) "Undo takes it back"

  # ---- 3b. the amount tapped first: edit, then log at the new amount ---------------------
  [void](Eval $openSearch)
  TypeText 'zebra ta'
  Settle
  [void](Eval "document.querySelector('#fqRows .fqamt').click()")
  Settle
  $a1 = EvalJ "(function(){ var g = document.getElementById('fqEarlyG'); var b = document.querySelector('#fqEarlyLog .fqlog'); return { g: g ? g.value : '', focus: document.activeElement === g, btn: b ? b.textContent : '', n: HT.state().days[HT.todayKey()].items.length, px: g ? parseFloat(getComputedStyle(g).fontSize) : 0, h: b ? Math.round(b.getBoundingClientRect().height) : 0 }; })()"
  Write-Host ("  the amount editor: " + $a1)
  $a1v = $a1 | ConvertFrom-Json
  Check (($a1v.g -eq '80') -and ($a1v.focus -eq $true) -and ($a1v.btn -eq 'Log 250 cal') -and ([int]$a1v.n -eq ($today0 + 1)) -and ($a1v.px -ge 16) -and ($a1v.h -ge 44)) "R254/1: tapping the amount OPENS AN EDITOR, prefilled with 80 g and focused, and logs nothing yet"
  Shot 'search-mine-amount'
  [void](Eval "(function(){ var g = document.getElementById('fqEarlyG'); g.focus(); g.select(); return 1; })()")
  TypeText '120'
  Settle
  $a2 = Eval "(document.querySelector('#fqEarlyLog .fqlog') || {}).textContent"
  Check ($a2 -eq 'Log 375 cal') ("R254/1: the count follows the typed amount -- 120 g is 375 cal (" + $a2 + ")")
  [void](Eval "document.querySelector('#fqEarlyLog .fqlog').click()")
  Settle
  $a3 = Eval "(function(){ var it = HT.state().days[HT.todayKey()].items.slice(-1)[0] || {}; return it.name + '|' + it.grams + '|' + Math.round(it.kcal) + '|' + Math.round(it.carb_g) + '|' + (it.repeated_from || {}).date; })()"
  Check ($a3 -eq ('Zebra tart|120|375|45|' + $yday)) ("R254/1 GATE: THE EDITED AMOUNT IS LOGGED -- 120 g, 375 cal, 45 g carbs, re-expressed from last time's 80 g (" + $a3 + ")")

  # ---- 4. one with NO numbers opens the picker, never re-logs ---------------------------
  [void](Eval $openSearch)
  TypeText 'stew zeb'
  Settle
  $nBefore = [int](Eval "HT.state().days[HT.todayKey()].items.length")
  [void](Eval "document.querySelector('#fqRows .fqearlier').click()")
  Settle
  $p1 = EvalJ "(function(){ var box = document.getElementById('fqRows'); var lab = box.querySelector('.fqlabel'), bare = box.querySelector('.fqbare'); return { n: HT.state().days[HT.todayKey()].items.length, field: document.getElementById('fqQuery').value, head: ((box.querySelector('.fqreprise .fqsub') || {}).textContent || ''), label: lab ? lab.textContent : '', labH: lab ? Math.round(lab.getBoundingClientRect().height) : 0, bare: bare ? bare.textContent : '', earlier: box.querySelectorAll('.fqearlier').length, usda: !!box.querySelector('.fdcnote,.fdcgo') }; })()"
  Write-Host ("  the picker: " + $p1)
  $p1v = $p1 | ConvertFrom-Json
  Check (([int]$p1v.n -eq $nBefore) -and ($p1v.field -eq 'Zebra stew')) "R254/2 GATE: tapping a food that had NO numbers WRITES NOTHING -- it opens the picker, its name in the search field"
  Check (($p1v.head -like 'No numbers last time for*Zebra stew*300 g*') -and ($p1v.label -eq 'Enter from label') -and ($p1v.labH -ge 44) -and ($p1v.bare -eq 'Log without nutrition') -and ($p1v.earlier -eq 0) -and ($p1v.usda -eq $true)) "R254/2: the picker says why, offers 'Enter from label', the USDA offer and 'Log without nutrition', and does not offer the same food back"
  Shot 'search-mine-picker'
  [void](Eval "document.querySelector('#fqRows .fqlabel').click()")
  Settle
  $p2 = EvalJ "(function(){ return { pane: (document.getElementById('pane-manual') || {}).className || '', name: (document.getElementById('maName') || {}).value, grams: (document.getElementById('maGrams') || {}).value, n: HT.state().days[HT.todayKey()].items.length }; })()"
  Write-Host ("  from label: " + $p2)
  Check (($p2 -like '*"pane":"*on*') -and ($p2 -like '*"name":"Zebra stew"*"grams":"300"*') -and ((($p2 | ConvertFrom-Json).n) -eq $nBefore)) "R254/2: 'Enter from label' opens the form with the name and last time's 300 g carried in, and writes nothing"

  # the database: the picked row's numbers, at last time's grams
  [void](Eval $openSearch)
  TypeText 'stew zeb'
  Settle
  [void](Eval "document.querySelector('#fqRows .fqearlier').click()")
  Settle
  [void](Eval "(function(){ var f = document.getElementById('fqQuery'); f.focus(); f.select(); return 1; })()")
  TypeText 'beef stew'
  Settle
  $db = EvalJ "(function(){ var r = document.querySelector('#fqRows .fqrow:not(.fqown):not(.fqearlier):not(.fqlabel)'); var still = !!document.querySelector('#fqRows .fqreprise'); if (!r) return { row: '', still: still }; var n = r.querySelector('.fqnm').textContent; r.click(); var g = document.getElementById('fqGrams'); var b = document.querySelector('#fqLog .fqlog'); return { row: n, still: still, grams: g ? g.value : '', btn: b ? b.textContent : '' }; })()"
  Write-Host ("  a database row: " + $db)
  $dbv = $db | ConvertFrom-Json
  Check (($dbv.row -ne '') -and ($dbv.still -eq $true) -and ($dbv.grams -eq '300') -and ($dbv.btn -like 'Log * cal')) "R254/2: typing another word keeps the picker for that food, and a database row opens at last time's 300 g"
  [void](Eval "document.querySelector('#fqLog .fqlog').click()")
  Settle
  $p3 = EvalJ "(function(){ var items = HT.state().days[HT.todayKey()].items; var it = items.slice(-1)[0] || {}; return { n: items.length, name: it.name, grams: it.grams, kcal: Math.round(it.kcal || 0), ref: !!(it.ref && it.ref.id), unres: it.unresolved === true }; })()"
  Write-Host ("  logged: " + $p3)
  $p3v = $p3 | ConvertFrom-Json
  Check ((([int]$p3v.n) -eq ($nBefore + 1)) -and ($p3v.name -eq $dbv.row) -and ($p3v.grams -eq 300) -and ($p3v.kcal -gt 0) -and ($p3v.ref -eq $true) -and ($p3v.unres -eq $false)) "R254/2 GATE: TODAY'S ENTRY GETS REAL NUMBERS -- the picked row's, at 300 g, cited and counted"
  $past1 = Eval $pastJ
  Check ($past1 -eq $past0) "R254/2 GATE: THE PAST IS UNTOUCHED -- yesterday's entries are byte-for-byte what they were, the stew still not counted"

  # ---- 5. Log a drink offers drinks only ------------------------------------------------
  [void](Eval "(function(){ var S = HT.state(); S.days['$yday'].items.push(HT.normalizeItem({ name: 'Zebra fizz', meal: 'drink', time: '15:00', grams: 330, kcal: 140, protein_g: 0, fat_g: 0, carb_g: 35, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', notes: '', source: 'ai-paste' }, true)); HT.drinkNew(); return 1; })()")
  TypeText 'zebra'
  Settle
  $d5 = EvalJ "(function(){ return Array.prototype.map.call(document.querySelectorAll('#fqRows .fqearlier .fqnm'), function (e) { return e.textContent; }); })()"
  Write-Host ("  in Log a drink: " + $d5)
  Check ($d5 -eq '["Zebra fizz"]') "C: in Log a drink the earlier row offered is the drink, and no food"
  [void](Eval "document.querySelector('#fqRows .fqearlier').click()")
  Settle
  $d6 = Eval "(function(){ var it = HT.state().days[HT.todayKey()].items.slice(-1)[0] || {}; return it.name + '|' + it.meal; })()"
  Check ($d6 -eq 'Zebra fizz|drink') "and it is logged as a drink"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("SEARCH MINE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "SEARCH MINE GATE: PASS -- Search lists the user's own foods first, then foods logged"
Write-Host "  before with no database match; a food of their own logs their numbers at its"
Write-Host "  serving; an earlier one logs in one tap or at an edited amount; one with no numbers"
Write-Host "  opens the picker and today's entry gets a row's numbers, the past untouched."
Write-Host "GATE: PASS"
exit 0
