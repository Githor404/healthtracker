# R202 / R203 / R204 -- NOTHING IS LOGGED WITHOUT A TAP.
#
# REPORTED: a supplement appeared at 02:16 on a night the user was asleep. The
# "Daily supplement" setting wrote an item into every day at the moment the day's
# record was created -- app start, or a resume after midnight -- stamped with that
# clock. The day's snack group then read "865 cal . 4 items . 02:16" for food
# eaten at 23:02.
#
# THIS GATE STARTS FROM THE OLD STORE. It writes a schema-14 blob with the old
# setting ENABLED and a day that holds an auto-added item at 02:16 beside three
# snacks at 23:02-23:03, and loads the app on it. Then, by real taps and typing:
#   1. the migration: today is EMPTY; the setting became one stack item; the old
#      entry is ordinary, says "time unknown (auto-added at app open)", and can
#      be deleted with Undo
#   2. A SIMULATED MIDNIGHT: the clock is moved past midnight and the page is
#      told it became visible -- the real resume path. The new day holds nothing
#   3. the day's groups: the snack header reads 3 items at 23:02; the supplement
#      has a group of its own with no time
#   4. the stack editor in Settings: a dose typed in, a food picked from the food
#      database at typed grams -- and neither act logs anything
#   5. "+ Log -> Daily stack . 0 of N taken" (R246): opening it logs nothing; Took all
#      logs N; one unchecked leaves N-1; an entry is deleted and brought back
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8301
$Dbg = 9507
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-noauto-" + [System.Guid]::NewGuid().ToString('N'))
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

  $boot = Eval "typeof HT === 'object' && typeof HT.migrateV14toV15 === 'function' && typeof HT.stackUpsert === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R203 functions are not on HT"; Cleanup; exit 2 }

  # ---- the old store ---------------------------------------------------------------
  $seed = EvalJ @'
(function () {
  var t = HT.todayKey(), y = HT.shiftDate(t, -1);
  var it = function (name, meal, time, kcal, extra) {
    var o = { name: name, meal: meal, time: time, kcal: kcal, protein_g: 0, fat_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0,
              confidence: 'measured', notes: '', source: 'manual' };
    Object.keys(extra || {}).forEach(function (k) { o[k] = extra[k]; });
    return o;
  };
  var blob = { version: 14, days: {}, current: y,
    settings: { goals: {}, supplement: { enabled: true, name: 'Daily capsule', nutrients: {} }, stack: [], combos: [], presets: [] },
    priceLog: {}, plates: {}, meds: {}, labels: {}, timeline: {}, fastLog: {}, regimens: { active: '', list: [], log: {} } };
  blob.days[y] = { status: 'complete', water_l: 0, items: [
    it('Daily capsule', 'supplement', '02:16', 0, { source: 'supplement', notes: 'auto-applied daily supplement', _auto: true }),
    it('Gate cheese', 'snack', '23:02', 400), it('Gate crackers', 'snack', '23:03', 300), it('Gate wine', 'snack', '23:03', 165) ] };
  localStorage.setItem('healthtracker-log', JSON.stringify(blob));
  window.__y = y;
  return { today: t, past: y };
})()
'@
  $sv = $seed | ConvertFrom-Json
  Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
  Start-Sleep -Milliseconds 3000
  [void](Eval "(function(){ window.__y = HT.shiftDate(HT.todayKey(), -1); return 1; })()")   # a reload clears the page's own variables
  $open = "Array.prototype.forEach.call(document.querySelectorAll('#dayView .mghead'), function (h) { if (h.className.indexOf('bghead') < 0 && h.getAttribute('aria-expanded') !== 'true') h.click(); });"

  # ---- 1. the migration ---------------------------------------------------------------
  $m = EvalJ @'
(function () {
  var S = HT.state(), t = HT.todayKey(), y = HT.shiftDate(t, -1);
  var old = (S.days[y] || { items: [] }).items[0] || {};
  return { version: S.version, current: S.current, today: t, todayItems: (S.days[t] || { items: [-1] }).items.length,
           todayDoses: (S.timeline[t] || []).length, rows: document.querySelectorAll('#dayView .mitem').length,
           setting: S.settings.supplement === undefined, stack: (S.settings.stack || []).map(function (s) { return s.name + '|' + s.kind + '|' + (s.dose === undefined ? 'no-amount' : s.dose) + '|' + s.enabled; }),
           oldFlag: old._auto === undefined, oldMark: old.autoLegacy === true, oldTime: old.time, oldNote: old.notes, n: (S.days[y] || { items: [] }).items.length };
})()
'@
  Write-Host ("  loaded on the old store: " + $m)
  $mv = $m | ConvertFrom-Json
  Check (($mv.version -eq 17) -and ($mv.current -eq $mv.today)) "PRECONDITION: the app started on a schema-14 store with the old setting ENABLED, migrated it, and is on today"
  Check (($mv.todayItems -eq 0) -and ($mv.todayDoses -eq 0) -and ($mv.rows -eq 0)) "R203: TODAY IS EMPTY -- starting the app logged nothing: no item, no dose, no row on screen. With the old setting this start wrote one"
  Check (($mv.setting -eq $true) -and (@($mv.stack).Count -eq 1) -and ($mv.stack[0] -eq 'Daily capsule|supplement|no-amount|true')) "R203: the setting is gone and became ONE stack item -- its name, and no amount, because the old setting never held one"
  Check (($mv.oldFlag -eq $true) -and ($mv.oldMark -eq $true) -and ($mv.oldTime -eq '') -and ($mv.oldNote -eq 'auto-added by old setting (at app open, 02:16)') -and ($mv.n -eq 4)) "R204: the entry it had auto-added is ordinary and marked, its time CLEARED, the old stamp kept in the note -- and it is still on its day"

  # ---- 2. a simulated midnight ----------------------------------------------------------
  $roll = EvalJ @'
(function () {
  var before = HT.todayKey();
  var vis = document.visibilityState;
  HT.setClock(function () { return Date.now() + 26 * 3600 * 1000; });
  document.dispatchEvent(new Event('visibilitychange'));       // the real resume listener
  var S = HT.state(), after = HT.todayKey();
  var out = { vis: vis, before: before, after: after, current: S.current,
              created: !!S.days[after], items: (S.days[after] || { items: [-1] }).items.length, doses: (S.timeline[after] || []).length,
              rows: document.querySelectorAll('#dayView .mitem').length,
              anywhere: Object.keys(S.days).filter(function (k) { return k !== window.__y; }).reduce(function (a, k) { return a + S.days[k].items.length; }, 0) };
  HT.setClock(null);
  document.dispatchEvent(new Event('visibilitychange'));       // and back to the real day
  out.back = HT.state().current === HT.todayKey();
  return out;
})()
'@
  Write-Host ("  a simulated midnight, then a resume: " + $roll)
  $rv = $roll | ConvertFrom-Json
  Check (($rv.vis -eq 'visible') -and ($rv.after -ne $rv.before) -and ($rv.current -eq $rv.after) -and ($rv.created -eq $true)) "PRECONDITION: the clock is past midnight, the page's own resume listener ran, and the app MOVED to the new day and made its record"
  Check (($rv.items -eq 0) -and ($rv.doses -eq 0) -and ($rv.rows -eq 0)) "R203 GATE: THE DAY-ROLL CREATED NO ENTRY -- the new day holds no item and no dose, and the screen shows no row. This is the 02:16 entry, not happening"
  Check (($rv.anywhere -eq 0) -and ($rv.back -eq $true)) "and no other day gained one either"

  # ---- 3. the day's groups, on the reported day -------------------------------------------
  [void](Eval "(function(){ HT.dayJump(window.__y); return 1; })()")
  Settle
  $g = EvalJ @'
(function () {
  var meta = function (kind) { return Array.prototype.map.call(document.querySelectorAll('#dayView .mgrp[data-kind="' + kind + '"] .mgmeta'), function (e) { return e.textContent; }); };
  var num = function (kind) { return Array.prototype.map.call(document.querySelectorAll('#dayView .mgrp[data-kind="' + kind + '"] .mgnum'), function (e) { return e.textContent; }); };
  var name = (document.querySelector('#dayView .mgrp[data-kind="supplement"] .mgname') || {}).textContent || '';
  return { current: HT.state().current === window.__y, snack: meta('snack'), snackCal: num('snack'), sup: meta('supplement'), supName: name,
           groups: document.querySelectorAll('#dayView .mgrp[data-kind]').length };
})()
'@
  Write-Host ("  the reported day: " + $g)
  $gv = $g | ConvertFrom-Json
  Check (($gv.current -eq $true) -and (@($gv.snack).Count -eq 1) -and ($gv.snack[0] -like '3 items*23:02*') -and (-not ($gv.snack[0] -like '*02:16*')) -and ($gv.snackCal[0] -like '865*')) "R202 GATE: the snack header reads '865 cal . 3 items . 23:02' -- the food's own time. It read '4 items . 02:16'"
  Check ((@($gv.sup).Count -eq 1) -and ($gv.sup[0] -like '1 item*') -and (-not ($gv.sup[0] -match '\d\d:\d\d')) -and ($gv.supName -eq 'Daily stack')) "R202 GATE: the supplement has a group OF ITS OWN, with no time on it -- it is never filed under a meal by the clock"

  [void](Eval ("(function(){ " + $open + " return 1; })()"))
  $row = @'
(function () {
  var r = Array.prototype.filter.call(document.querySelectorAll('#dayView .mitem'), function (x) { return (x.querySelector('.mname') || { getAttribute: function () { return ''; } }).getAttribute('title') === 'Daily capsule'; })[0];
  if (!r) return { found: false, n: HT.state().days[window.__y].items.length };
  var rm = r.querySelector('.rm'), tm = r.querySelector('.mtime');
  var h0 = Math.round(r.getBoundingClientRect().height);
  var rb = rm ? rm.getBoundingClientRect() : null, tb = tm ? tm.getBoundingClientRect() : null;
  var tpx = tm ? parseFloat(getComputedStyle(tm).fontSize) : 0;
  r.querySelector('.mhead').click();                        // open it: the reason is the first thing inside
  r = Array.prototype.filter.call(document.querySelectorAll('#dayView .mitem'), function (x) { return (x.querySelector('.mname') || { getAttribute: function () { return ''; } }).getAttribute('title') === 'Daily capsule'; })[0];
  var lg = r.querySelector('.mbody .mlegacy');
  var b = lg ? lg.getBoundingClientRect() : null;
  rm = r.querySelector('.rm');
  return { found: true, n: HT.state().days[window.__y].items.length, says: lg ? lg.textContent : '', saysPx: lg ? parseFloat(getComputedStyle(lg).fontSize) : 0,
           seen: b ? (b.height > 0 && b.width > 0) : false, time: tm ? tm.textContent : '(none)', timeSeen: tb ? (tb.height > 0 && tb.width > 0) : false, timePx: tpx, h: h0,
           rm: !!rm, rmSeen: rb ? (rb.height > 0 && rb.width > 0) : false };
})()
'@
  $r1 = EvalJ $row
  Write-Host ("  the auto-added entry's row: " + $r1)
  $r1v = $r1 | ConvertFrom-Json
  Check (($r1v.found -eq $true) -and ($r1v.time -eq 'time unknown') -and ($r1v.timeSeen -eq $true) -and ($r1v.timePx -ge 16) -and ($r1v.h -le 60)) ("R204 GATE: its COLLAPSED row says 'time unknown' where the time would be, on screen at 16px, and is still one line (" + $r1v.h + " px of 60)")
  Check (($r1v.says -eq 'time unknown (auto-added at app open)') -and ($r1v.seen -eq $true) -and ($r1v.saysPx -ge 16)) "R204 GATE: OPENED, it says why -- 'time unknown (auto-added at app open)', on screen, at 16px"
  Check (($r1v.rm -eq $true) -and ($r1v.rmSeen -eq $true)) "R203 GATE: and it has a visible delete control -- nothing that is logged is non-deletable"
  [void](Eval "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#dayView .mitem'), function (x) { return (x.querySelector('.mname') || { getAttribute: function () { return ''; } }).getAttribute('title') === 'Daily capsule'; })[0]; r.querySelector('.rm').click(); return 1; })()")
  Settle
  $d1 = EvalJ "(function(){ var t = document.getElementById('toast'); return { n: HT.state().days[window.__y].items.length, gone: !HT.state().days[window.__y].items.some(function (i) { return i.name === 'Daily capsule'; }), undo: !!(t && t.querySelector('.tundo') && t.classList.contains('show')), group: document.querySelectorAll('#dayView .mgrp[data-kind=supplement]').length }; })()"
  Write-Host ("  deleted: " + $d1)
  Check ($d1 -like '*"n":3*"gone":true*"undo":true*"group":0*') "R203 GATE: tapped, it is DELETED -- three items left, its group gone from the day -- and Undo is offered"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $u1 = EvalJ "(function(){ var i = HT.state().days[window.__y].items.filter(function (x) { return x.name === 'Daily capsule'; })[0] || {}; return { n: HT.state().days[window.__y].items.length, mark: i.autoLegacy === true, time: i.time }; })()"
  Check ($u1 -like '*"n":4*"mark":true*"time":""*') "and Undo brings it back as it was"

  # ---- 4. the stack editor ---------------------------------------------------------------------
  [void](Eval "(function(){ HT.dayJump(HT.todayKey()); HT.openSettings(); var d = document.getElementById('stackDetails'); if (!d.open) d.querySelector('summary').click(); d.scrollIntoView({ block: 'start' }); return 1; })()")
  Settle
  $e0 = EvalJ @'
(function () {
  var ed = document.getElementById('stackEditor'), add = ed ? ed.querySelector('.stkadd') : null;
  var b = add ? add.getBoundingClientRect() : null;
  return { names: Array.prototype.map.call(ed.querySelectorAll('.stkname'), function (e) { return e.textContent; }),
           add: add ? add.textContent : '', addH: b ? b.height : 0, addPx: add ? parseFloat(getComputedStyle(add).fontSize) : 0,
           old: !!document.getElementById('supEnabled') || /auto-add/i.test(document.getElementById('settingsPanel').innerText),
           heading: /Micronutrients \(from the supplement label\)/.test(document.getElementById('settingsPanel').textContent) };
})()
'@
  Write-Host ("  Settings, Daily stack: " + $e0)
  $e0v = $e0 | ConvertFrom-Json
  Check ((@($e0v.names).Count -eq 1) -and ($e0v.names[0] -eq 'Daily capsule') -and ($e0v.add -eq 'Add an item') -and ($e0v.addH -ge 44) -and ($e0v.addPx -ge 16)) "R203: Settings has a DAILY STACK listing the carried-over item, with 'Add an item' (44 px, 16px)"
  Check (($e0v.old -eq $false) -and ($e0v.heading -eq $false)) "R203: the 'auto-add to each new day' switch is GONE, and so is the empty 'Micronutrients (from the supplement label)' heading"

  [void](Eval "document.querySelector('#stackEditor .stkadd').click()")
  [void](Eval "document.getElementById('stkName').focus()"); TypeText 'Gate capsule'
  [void](Eval "document.getElementById('stkDose').focus()"); TypeText '600'
  [void](Eval "document.getElementById('stkNote').focus()"); TypeText 'with food'
  $f0 = EvalJ @'
(function () {
  var f = document.querySelector('#stackEditor .stkform'), small = [], low = [];
  Array.prototype.forEach.call(f.querySelectorAll('button, input, select'), function (c) {
    if (parseFloat(getComputedStyle(c).fontSize) < 16) small.push(c.id || c.className);
    if (c.tagName === 'BUTTON' && c.getBoundingClientRect().height < 44) low.push(c.className);
  });
  var units = Array.prototype.map.call(document.getElementById('stkUnit').options, function (o) { return o.textContent; });
  return { small: small, low: low, units: units, unit: document.getElementById('stkUnit').value,
           overflow: f.scrollWidth - f.clientWidth, kept: document.getElementById('stkName').value };
})()
'@
  Write-Host ("  the item form: " + $f0)
  $f0v = $f0 | ConvertFrom-Json
  Check ((@($f0v.small).Count -eq 0) -and (@($f0v.low).Count -eq 0) -and ($f0v.overflow -le 0)) "the form's fields are 16px, its buttons at least 44 px tall, and it does not scroll sideways at 390"
  Check ((@($f0v.units) -contains 'mg') -and (@($f0v.units) -contains 'IU') -and (@($f0v.units) -contains 'g') -and (@($f0v.units) -contains ([string][char]0xB5 + 'g')) -and (-not (@($f0v.units) -contains 'mcg'))) "R203: the unit list offers mg, micrograms (shown as the micro sign + g, never 'mcg'), IU and g"
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  [void](Eval "document.querySelector('#stackEditor .stkadd').click()")
  [void](Eval "document.querySelectorAll('#stackEditor .stkkinds button')[2].click()")
  # The food database is fetched once, on first use; wait for it rather than for a
  # fixed pause, so the search below is typed into a ready pane.
  $db = EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok), rows: HT.corpusState().rows }; })"
  [void](Eval "document.getElementById('stkQuery').focus()"); TypeText 'butter'
  Settle
  $pk = EvalJ "(function(){ var rows = document.querySelectorAll('#stkRows .fqrow'); var n = rows.length, nm = n ? rows[0].querySelector('.fqname').textContent : '', q = document.getElementById('stkQuery').value; if (n) rows[0].click(); var g = document.getElementById('stkGrams'); if (g) g.focus(); return { rows: n, name: nm, typed: q, picked: (document.querySelector('#stackEditor .stkpicked') || {}).textContent || '' }; })()"
  TypeText '10'
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  $e1 = EvalJ @'
(function () {
  var S = HT.state(), t = HT.todayKey(), st = S.settings.stack || [];
  var f = st[2] || {};
  return { n: st.length, dose: st[1] ? (st[1].name + '|' + st[1].dose + '|' + st[1].dose_unit + '|' + st[1].note + '|' + st[1].kind) : '',
           food: f.kind === 'food' && !!f.part && f.part.grams === 10 && !!f.part.ref && f.part.kcal > 0 && f.part.source === 'corpus', foodName: f.name || '',
           rows: Array.prototype.map.call(document.querySelectorAll('#stackEditor .stkrow'), function (e) { return e.innerText.replace(/\s+/g, ' '); }),
           form: !!document.querySelector('#stackEditor .stkform'),
           todayItems: (S.days[t] || { items: [] }).items.length, todayDoses: (S.timeline[t] || []).length };
})()
'@
  Write-Host ("  two items added: " + $pk + " " + $e1)
  $e1v = $e1 | ConvertFrom-Json
  Check (($e1v.n -eq 3) -and ($e1v.dose -eq 'Gate capsule|600|mg|with food|supplement')) "R203 GATE: a DOSE typed into the editor is saved -- name, amount, unit and note"
  Check (($pk -like '*"typed":"butter"*') -and (-not ($pk -like '*"rows":0*')) -and ($e1v.food -eq $true) -and ($e1v.foodName -like 'Butter*')) "R203 GATE: a FOOD is found by typing into the editor's own search, picked, and given typed grams -- stored with the food database's numbers and its citation"
  Check ((@($e1v.rows).Count -eq 3) -and ($e1v.rows[1] -like '*Gate capsule*600 mg*with food*') -and ($e1v.rows[2] -like '*10 g*counts in your day*') -and ($e1v.form -eq $false)) "and the list SHOWS all three, each with its amount"
  Check (($e1v.todayItems -eq 0) -and ($e1v.todayDoses -eq 0)) "R203 GATE: EDITING THE STACK LOGGED NOTHING -- today still holds no item and no dose"

  # ---- 5. the one tap (R246: Took all, and a row unchecked) ------------------------------------
  [void](Eval "(function(){ HT.closeSettings(); HT.openSheet(); return 1; })()")
  Settle
  $s0 = EvalJ @'
(function () {
  var b = document.querySelector('#sheetRoot .stkopen'), r = b ? b.getBoundingClientRect() : null, S = HT.state(), t = HT.todayKey();
  var a = document.querySelector('#sheetRoot .stkall'), ra = a ? a.getBoundingClientRect() : null;
  return { label: b ? b.textContent : '', h: r ? r.height : 0, px: b ? parseFloat(getComputedStyle(b).fontSize) : 0, all: a ? a.textContent : '', ah: ra ? ra.height : 0,
           items: (S.days[t] || { items: [] }).items.length, doses: (S.timeline[t] || []).length };
})()
'@
  Write-Host ("  + Log: " + $s0)
  $s0v = $s0 | ConvertFrom-Json
  Check (($s0v.label -like ('Daily stack ' + [char]0xB7 + ' 0 of 3 taken')) -and ($s0v.h -ge 44) -and ($s0v.px -ge 16) -and ($s0v.all -eq 'Took all') -and ($s0v.ah -ge 44)) "R203 / R246: + Log offers 'Daily stack . 0 of 3 taken' and 'Took all' -- 44 px, 16px"
  Check (($s0v.items -eq 0) -and ($s0v.doses -eq 0)) "and OPENING the sheet logged nothing"
  [void](Eval "document.querySelector('#sheetRoot .stkopen').click()")
  $s1 = EvalJ "(function(){ var c = document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]'); return { ticks: c.length, on: Array.prototype.filter.call(c, function (x) { return x.checked; }).length, items: (HT.state().days[HT.todayKey()] || { items: [] }).items.length, doses: (HT.state().timeline[HT.todayKey()] || []).length }; })()"
  Check ($s1 -like '*"ticks":3*"on":0*"items":0*"doses":0*') "R246: opened, it lists the three, NONE checked, and opening it logged nothing"
  [void](Eval "document.querySelector('#sheetRoot .stkall').click()")
  Settle
  $count = "(function(){ var S = HT.state(), t = HT.todayKey(), tl = S.timeline[t] || [], it = (S.days[t] || { items: [] }).items; var x = document.getElementById('toast'); return { items: it.length, doses: tl.length, names: it.map(function (i) { return i.name.split(',')[0] + '|' + i.grams + '|' + i.source + '|' + i.meal; }), dose: tl.map(function (r) { return r.name + '|' + (r.dose === undefined ? '' : r.dose) + '|' + r.source; }), times: it.concat(tl).map(function (r) { return r.time; }).filter(function (v, i, a) { return a.indexOf(v) === i; }).length, undo: !!(x && x.querySelector('.tundo') && x.classList.contains('show')), on: Array.prototype.filter.call(document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]'), function (c) { return c.checked; }).length }; })()"
  $s2 = EvalJ $count
  Write-Host ("  Took all: " + $s2)
  $s2v = $s2 | ConvertFrom-Json
  Check ((($s2v.items + $s2v.doses) -eq 3) -and ($s2v.items -eq 1) -and ($s2v.doses -eq 2) -and ($s2v.on -eq 3)) "R203 / R246 GATE: TOOK ALL LOGS N -- three: one food into the day, two doses onto the timeline, every row now checked"
  Check (($s2v.names[0] -like 'Butter|10|corpus|supplement') -and (@($s2v.dose) -contains 'Gate capsule|600|stack') -and ($s2v.times -eq 1) -and ($s2v.undo -eq $true)) "at ONE time, each as it was set up, with Undo offered"
  [void](Eval "document.querySelectorAll('#sheetRoot .stkrow input[type=checkbox]')[1].click()")
  Settle
  $s4 = EvalJ $count
  Write-Host ("  one unchecked: " + $s4)
  $s4v = $s4 | ConvertFrom-Json
  Check ((($s4v.items + $s4v.doses) -eq 2) -and ($s4v.items -eq 1) -and ($s4v.doses -eq 1) -and ($s4v.on -eq 2) -and (@(@($s4v.dose) | Where-Object { $_ -like 'Gate capsule*' }).Count -eq 0)) "R246 GATE: TOOK ALL, THEN UNCHECK ONE -> N-1 -- two entries, and the unchecked dose is gone"

  # every entry deletable, with Undo
  [void](Eval ("(function(){ HT.closeSheet(); " + $open + " return 1; })()"))
  Settle
  $d2 = EvalJ @'
(function () {
  var t = HT.todayKey();
  var rows = document.querySelectorAll('#dayView .mgrp[data-kind="supplement"] .mitem');
  var heads = Array.prototype.map.call(document.querySelectorAll('#dayView .mgrp[data-kind]'), function (g) { return g.getAttribute('data-kind'); });
  var n0 = HT.state().days[t].items.length, had = rows.length, rm = rows[0] ? rows[0].querySelector('.rm') : null;
  if (rm) rm.click();
  var x = document.getElementById('toast');
  return { kinds: heads, rows: had, before: n0, after: HT.state().days[t].items.length, undo: !!(x && x.querySelector('.tundo') && x.classList.contains('show')) };
})()
'@
  Write-Host ("  a stack entry deleted: " + $d2)
  $d2v = $d2 | ConvertFrom-Json
  Check ((@($d2v.kinds).Count -eq 1) -and ($d2v.kinds[0] -eq 'supplement') -and ($d2v.rows -eq 1)) "the day shows them under the stack's own group ('Daily stack'), not under whichever meal the clock would have picked"
  Check (($d2v.before -eq 1) -and ($d2v.after -eq 0) -and ($d2v.undo -eq $true)) "R203 GATE: a stack entry on the day is DELETED by its own control, with Undo offered"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $d3 = EvalJ @'
(function () {
  var t = HT.todayKey(), n = HT.state().days[t].items.length, tl0 = (HT.state().timeline[t] || []).length;
  var r = HT.deleteSignal(t, 0);
  var x = document.getElementById('toast');
  var mid = (HT.state().timeline[t] || []).length, undo = !!(x && x.querySelector('.tundo') && x.classList.contains('show'));
  if (undo) x.querySelector('.tundo').click();
  return { items: n, tl0: tl0, mid: mid, undo: undo, back: (HT.state().timeline[t] || []).length };
})()
'@
  Write-Host ("  restored; then a dose deleted and restored: " + $d3)
  $d3v = $d3 | ConvertFrom-Json
  Check ($d3v.items -eq 1) "and Undo brings the day entry back"
  Check (($d3v.tl0 -eq 1) -and ($d3v.mid -eq 0) -and ($d3v.undo -eq $true) -and ($d3v.back -eq 1)) "R203 GATE: a stack DOSE on the timeline is deleted through the timeline's own delete, with Undo, and comes back"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("NO-AUTO GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "NO-AUTO GATE: PASS -- starting the app, a midnight roll, opening the sheet and"
Write-Host "  editing the stack log nothing; Took all logs N, unchecking one leaves N-1; an old"
Write-Host "  auto-added entry says its time is unknown; and everything can be deleted"
Write-Host "  and brought back."
Write-Host "GATE: PASS"
exit 0
