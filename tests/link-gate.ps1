# R286/2 -- "LINK A DATABASE ROW?" ON AN OPENED DAY ITEM, AND THE WEEK'S BATCH. In a real
# browser at 390 px, with the real food database, by real taps.
#
#   Pre-registered in DECISIONS (R286, steps d and e) before the build. The user's answer
#   (29 Oct): on the day view, never at capture; the top three rows of the one ranking,
#   calories beside each; the accuracy calculated from the user's own picks; nothing
#   counts until a tap; the week's unlinked items as one batch. Placeholder foods only.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8405
$Dbg = 9605
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-link-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set LINK_SHOTS=1 to save 390px screenshots to %TEMP%\link-shots.
$shots = $null
if ($env:LINK_SHOTS) { $shots = Join-Path $env:TEMP 'link-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  # ---- the fixture: the real corpus, a day of placeholder foods, the user's own past picks ------
  $cr = EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok), ns: (HT.corpusState() || {}).ns }; })"
  Write-Host ("  corpus: " + $cr)
  if ($cr -notlike '*"ok":true*') { Write-Host "ERROR: the food database did not load"; Cleanup; exit 2 }
  function TapSel([string]$sel) {
    $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); return { ok: q.width > 0 && q.height > 0, x: q.left + q.width / 2, y: q.top + q.height / 2, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
    if (-not $r9.ok) { return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  # Past picks are built FROM THE RANKING ITSELF, so the expected figures are known:
  # names 0-2 the user chose the first row, name 3 the third, names 4-5 a row outside
  # the first three. With 4 picks the line must say "not enough"; with 6, 3 first and 4 in three.
  $fx = @'
(function () {
  var S = HT.state();
  var names = ['cooked lentils', 'plain yogurt', 'raw spinach', 'cooked brown rice', 'apple', 'cheddar cheese'];
  var picks = names.map(function (n) {
    var c = HT.linkRanking({ name: n });          // the order the accuracy reads
    return { name: n, ids: c.map(function (x) { return String(x.id); }), names: c.map(function (x) { return x.name; }) };
  });
  var want = [0, 0, 0, 2, 7, 6];
  var past = {};
  window.__pick = function (i, d) {
    var p = picks[i];
    return { name: p.name, meal: 'lunch', time: '12:00', confidence: 'eyeballed', source: 'ai-paste', grams: 100, kcal: 100,
             protein_g: 1, fat_g: 1, carb_g: 1, fiber_g: 0, soluble_fiber_g: 0, notes: '',
             ref: { ns: HT.corpusState().ns, id: p.ids[want[i]], name: p.names[want[i]], at: d, hash: 'x', attribution: 'x', how: 'picked', when: 'later', v: { '208': 100 } } };
  };
  var d1 = HT.shiftDate(HT.todayKey(), -3), d2 = HT.shiftDate(HT.todayKey(), -2);
  S.days[d1] = { status: 'complete', water_l: 0, items: [0, 1, 2, 3].map(function (i) { return window.__pick(i, d1); }) };
  var t = HT.todayKey();
  S.days[t] = { status: 'in_progress', water_l: 0, items: [
    { name: 'Item zz stew', meal: 'dinner', time: '18:00', confidence: 'eyeballed', source: 'ai-paste', grams: 250, kcal: 300, protein_g: 20, fat_g: 10, carb_g: 30, fiber_g: 4, soluble_fiber_g: 0, notes: '' },
    { name: 'cooked lentils', meal: 'lunch', time: '12:30', confidence: 'eyeballed', source: 'ai-paste', grams: 200, kcal: 230, protein_g: 18, fat_g: 1, carb_g: 40, fiber_g: 8, soluble_fiber_g: 0, notes: '' },
    window.__pick(1, t),
    { name: 'Item S', meal: 'supplement', time: '08:00', confidence: 'measured', source: 'corpus', grams: 10, kcal: 90, protein_g: 0, fat_g: 10, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0, notes: '', stackId: 'stk1', stackKind: 'food' } ] };
  S.current = t;
  window.__d2 = d2;
  HT.resave(); HT.itemCollapseAll(); HT.dayGroupsOpenAll(true); HT.refresh();
  return { first: picks.map(function (p) { return p.names[0]; }), counts: picks.map(function (p) { return p.ids.length; }) };
})()
'@
  $fxr = EvalJ $fx
  Write-Host ("  rankings: " + $fxr)
  WaitQuiet 'fixture'
  $dk = Eval "HT.todayKey()"
  $rowOf = "(function(n){ var r = Array.prototype.filter.call(document.querySelectorAll('.mitem'), function (x) { var e = x.querySelector('.mname'); return e && e.textContent.indexOf(n) >= 0; }); return r; })"
  function OpenItem([string]$nm) {
    [void](Eval ("(function(){ var r = " + $rowOf + "(" + (ConvertTo-Json $nm) + ")[0]; if (r) { r.querySelector('.mhead').setAttribute('data-gate-open', '1'); } return 1; })()"))
    $to = TapSel '[data-gate-open="1"]'
    Write-Host ("  tap to open " + $nm + ": " + ($to | ConvertTo-Json -Compress))
    [void](Eval "(function(){ var e = document.querySelector('[data-gate-open]'); if (e) e.removeAttribute('data-gate-open'); return 1; })()")
    WaitQuiet 'opened'
  }
  $blk = "(function(n){ var r = " + $rowOf + "(n)[0]; var m = r ? r.querySelector('.mlink') : null; if (!m) return { has: false }; var rows = Array.prototype.map.call(m.querySelectorAll('.mlinkrow'), function (b) { var q = b.getBoundingClientRect(); return { t: b.innerText.replace(/\s+/g, ' '), h: Math.round(q.height) }; }); var y = m.querySelector('.mlinkyours'), a = m.querySelector('.mlinkacc'); return { has: true, head: (m.querySelector('.mlinkhead') || {}).textContent || '', rows: rows, yours: y ? y.textContent : '', acc: a ? a.textContent : '', find: !!m.querySelector('.mlinkfind') }; })"

  # ---- GATE 1: the offer on an opened unlinked item; nothing changes before a tap ----------------
  $exp0 = Eval "HT.exportJSON()"
  OpenItem 'cooked lentils'
  $b1 = EvalJ ($blk + "('cooked lentils')")
  $exp1 = Eval "HT.exportJSON()"
  [void](Eval "(function(){ var m = document.querySelector('.mlink'); if (m) m.scrollIntoView({ block: 'center' }); return 1; })()")
  Shot 'link-offer'
  Write-Host ("  offer: " + $b1)
  $b1v = $b1 | ConvertFrom-Json
  $rowsOk = ($b1v.rows.Count -eq 3) -and (@($b1v.rows | Where-Object { $_.h -lt 44 }).Count -eq 0) -and (@($b1v.rows | Where-Object { $_.t -notlike '*cal per 100 g*' -and $_.t -notlike '*calories not in this row*' }).Count -eq 0)
  Check ($b1v.has -and $rowsOk -and ($b1v.head -like '*Nothing counts until you tap one*') -and ($b1v.yours -like 'Yours: * cal per 100 g') -and $b1v.find) "R286 LINK GATE 1: AN OPENED UNLINKED ITEM OFFERS THREE DATABASE ROWS -- 44 px each, calories per 100 g beside each and beside the item's own, 'None of these -- find nutrients' below"
  Check ($exp0 -eq $exp1) "R286 LINK GATE 1: NOTHING COUNTS BEFORE A TAP -- opening the item and drawing the offer leaves the export byte-identical"
  # ---- GATE 2: the accuracy line, under and over n 5 ------------------------------------------------
  Check ($b1v.acc -like '*Not enough of your own picks yet*(4 of 5)*') ("R286 LINK GATE 2: UNDER n 5 IT SAYS SO -- '" + $b1v.acc + "'")
  [void](Eval "(function(){ var S = HT.state(); S.days[window.__d2] = { status: 'complete', water_l: 0, items: [window.__pick(4, window.__d2), window.__pick(5, window.__d2)] }; HT.resave(); HT.refresh(); return 1; })()")
  WaitQuiet 'more picks'
  $b2 = EvalJ ($blk + "('cooked lentils')")
  $b2v = $b2 | ConvertFrom-Json
  Write-Host ("  accuracy: " + $b2v.acc)
  Check ($b2v.acc -like 'Calculated from 6 foods you linked before: the row you chose was first here for 3 of 6 (50 %), and among these three for 4 of 6 (67 %).') ("R286 LINK GATE 2: OVER n 5 IT IS CALCULATED FROM THE USER'S OWN PICKS -- first 3 of 6, among three 4 of 6, as the fixture built them")
  # ---- GATE 3: none on a linked item, a stack item ---------------------------------------------------
  OpenItem 'plain yogurt'
  OpenItem 'Item S'
  $b3 = EvalJ ("(function(){ return { linked: " + $blk + "('plain yogurt').has, stack: " + $blk + "('Item S').has }; })()")
  Check ($b3 -like '*"linked":false,"stack":false*') ("R286 LINK GATE 3: NO OFFER on a linked item or a stack item (" + $b3 + ")")
  # ---- GATE 4a: D127 -- a row in another state is not linked on the tap; the question asks ----------
  # The food is FOUND, not assumed: the first placeholder name whose first three rows hold a row in
  # another state than the name says. It is added to today, opened, and that row tapped.
  $mm = EvalA "(function(){ var names = ['cooked carrots', 'boiled potatoes', 'cooked spinach', 'cooked broccoli', 'boiled egg', 'cooked salmon', 'steamed rice', 'cooked chickpeas', 'roasted peppers', 'cooked mushrooms']; var t = HT.todayKey(); var go = function (k) { if (k >= names.length) return Promise.resolve({ name: '' }); var it = { name: names[k], meal: 'lunch', source: 'ai-paste', grams: 150, kcal: 150, protein_g: 5, fat_g: 3, carb_g: 20, fiber_g: 2 }; return HT.resolveCompute(t, -1, it, null, null).then(function (v) { var top = (v.candidates || []).slice(0, 3); for (var q = 0; q < top.length; q++) { if (top[q].state && v.want && top[q].state !== v.want) return { name: names[k], at: q, want: v.want, row: top[q].name, state: top[q].state }; } return go(k + 1); }); }; return go(0); })()"
  Write-Host ("  state-mismatch food: " + $mm)
  $mmv = $mm | ConvertFrom-Json
  if ($mmv.name) {
    [void](Eval ("(function(){ var S = HT.state(), t = HT.todayKey(); S.days[t].items.push({ name: " + (ConvertTo-Json $mmv.name) + ", meal: 'lunch', time: '13:00', confidence: 'eyeballed', source: 'ai-paste', grams: 150, kcal: 150, protein_g: 5, fat_g: 3, carb_g: 20, fiber_g: 2, soluble_fiber_g: 0, notes: '' }); HT.resave(); HT.refresh(); return 1; })()"))
    WaitQuiet 'mismatch item'
    OpenItem $mmv.name
    [void](Eval ("(function(){ var r = " + $rowOf + "(" + (ConvertTo-Json $mmv.name) + ")[0]; var b = r && r.querySelectorAll('.mlinkrow')[" + $mmv.at + "]; if (b) b.setAttribute('data-gate-pick', '1'); return 1; })()"))
    [void](TapSel '[data-gate-pick="1"]')
    $q4 = EvalJ ("(function(){ var it = HT.state().days[HT.todayKey()].items.filter(function (x) { return x.name === " + (ConvertTo-Json $mmv.name) + "; })[0]; var c = document.querySelector('.rconfirm'); return { asked: !!c && c.getBoundingClientRect().height > 0, linked: !!(it.ref && it.ref.ns) }; })()")
    Write-Host ("  state mismatch: " + $q4)
    Check ($q4 -like '*"asked":true,"linked":false*') ("R286 LINK GATE 4: A ROW IN ANOTHER STATE IS NOT LINKED ON THE TAP -- D127's question asks first (" + $mmv.row + " is " + $mmv.state + ", the item is " + $mmv.want + ")")
    [void](Eval "HT.resolveConfirmCancel(); HT.resolveClose()"); WaitQuiet 'question closed'
  } else {
    Check $false "R286 LINK GATE 4: no placeholder name gave a state mismatch among its first three rows -- the D127 leg could not be exercised"
  }
  # ---- GATE 4b: one tap on a row links it -------------------------------------------------------------
  $kc0 = Eval "HT.state().days[HT.todayKey()].items.filter(function (x) { return x.name === 'cooked lentils'; })[0].kcal"
  [void](Eval ("(function(){ var r = " + $rowOf + "('cooked lentils')[0]; var b = r && r.querySelectorAll('.mlinkrow')[0]; if (b) b.setAttribute('data-gate-pick2', '1'); return 1; })()"))
  [void](TapSel '[data-gate-pick2="1"]')
  $q5 = EvalJ "(function(){ var it = HT.state().days[HT.todayKey()].items.filter(function (x) { return x.name === 'cooked lentils'; })[0]; return { ns: it.ref ? it.ref.ns : '', how: it.ref ? it.ref.how : '', name: it.ref ? it.ref.name : '', kcal: it.kcal, offer: Array.prototype.some.call(document.querySelectorAll('.mitem'), function (x) { var e = x.querySelector('.mname'); return e && e.textContent.indexOf('cooked lentils') >= 0 && !!x.querySelector('.mlinkrow'); }) }; })()"
  Write-Host ("  linked: " + $q5 + " (was " + $kc0 + " kcal)")
  Check (($q5 -like ('*"ns":"' + (($cr | ConvertFrom-Json).ns) + '"*')) -and (($q5 -like '*"how":"picked"*') -or ($q5 -like '*"how":"proposed"*')) -and ($q5 -like '*"offer":false*')) ("R286 LINK GATE 4: ONE TAP ON A ROW LINKS IT -- the item carries the row, recorded as the user's pick (or the remembered proposal they took, D133), its numbers the row's at its grams, and the offer is gone")
  # ---- d2: the weekly review's batch ------------------------------------------------------------------
  [void](Eval "HT.openWeek(HT.todayKey())"); WaitQuiet 'week'
  $wk = EvalJ "(function(){ var c = document.querySelector('#weekBody [data-card=link]'); if (!c) return { card: false }; return { card: true, items: Array.prototype.map.call(c.querySelectorAll('.wklinkitem'), function (b) { return b.textContent; }), line: c.querySelector('.wkline').textContent, h: Math.min.apply(null, Array.prototype.map.call(c.querySelectorAll('.wklinkitem'), function (b) { return Math.round(b.getBoundingClientRect().height); }).concat([99])) }; })()"
  $wkWant = EvalJ "(function(){ var R = { soFar: HT.weekDates(HT.weekMonday(HT.todayKey())).filter(function (d) { return d <= HT.todayKey(); }) }; var L = HT.weekLinkItems(R); return { n: L.items.length, food: L.food, names: L.items.map(function (x) { return x.it.name; }) }; })()"
  Shot 'link-week'
  Write-Host ("  week card: " + $wk + " want " + $wkWant)
  $wkv = $wk | ConvertFrom-Json; $wkw = $wkWant | ConvertFrom-Json
  $namesOk = ($wkv.items.Count -eq $wkw.n) -and (@($wkw.names | Where-Object { $nm = $_; -not (@($wkv.items | Where-Object { $_ -like ($nm + '*') }).Count) }).Count -eq 0)
  Check ($wkv.card -and $namesOk -and ($wkv.h -ge 44) -and ($wkv.line -like '* food items linked to a database row*')) ("R286 WEEKLY (d2): THE WEEK'S UNLINKED FOOD ITEMS AS ONE BATCH -- exactly " + $wkw.n + " of " + $wkw.food + ", each a 44 px way to its rows, with the linked share")
  [void](Eval "HT.closeWeek()")

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("LINK GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "LINK GATE: PASS -- an opened unlinked item offers three rows with calories, nothing counts until a tap, the accuracy is the user's own, one tap links (D127 still asks), and the week lists its unlinked items."
Write-Host "GATE: PASS"
exit 0
