# R215 -- EVERY ENTRY GOES THROUGH + LOG. By real clicks at 390 px.
#
# RULED (R215/R216, 2026-10-13; answers 2026-10-14): all logging goes through
# + Log. A side entry point is removed, or becomes a link that opens + Log at the
# right spot. Three things stay on the page because they are ANSWERS to something
# the page shows, not entries: Fasted / Ate, didn't log (a fasting gap), the
# answer to a glucose rise, and the side slept on (a flagged night). The gate
# allows EXACTLY that list and nothing else.
#
# HOW IT IS ASKED -- A CENSUS, NOT A LIST OF KNOWN BUTTONS. A gate that checked
# the buttons R215 moved would pass on the next side door somebody adds. So the
# page is seeded with every surface that can show a control at once (an open
# sleep past its question, a pending fast, a rise with no food before it, a
# flagged night, leftovers, today's regimen, a sensor, a deleted item in the
# trash), every group and disclosure on it is opened, and then EVERY visible
# control outside + Log and Settings is clicked, one at a time, each from the
# same restored state. Before and after each click the stored entries are
# counted: food items, timeline records, water, open sessions, fasting answers,
# regimen ticks. A click that adds to any of them must be one of the named
# answers -- or the Restore of a deleted entry, which brings back what was
# already logged and is named separately so it cannot hide in the answer list.
#
# Then the other half of the ruling: every ONE-TAP control that moved into
# + Log writes when tapped there, and its Undo takes the write back exactly
# ("Undo everywhere"). And the two links (leftovers, regimen) open + Log on the
# thing they name.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8309
$Dbg = 9515
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-entry-" + [System.Guid]::NewGuid().ToString('N'))
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
# Multi-line JS goes over base64 so no quoting survives to be mangled, and the
# result is stringified INSIDE the page after the promise settles.
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "Promise.resolve(eval(decodeURIComponent(escape(atob('" + $enc + "'))))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text + " " + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value }

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); $l.Start()
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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $boot = Eval "typeof HT === 'object' && typeof HT.oneTapHTML === 'function' && typeof HT.glucoseIngest === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R215 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: every surface that can carry a control, at once -----------------
  # The clock is fixed at 21:00 today so the evening's glucose has happened.
  $fx = EvalA @'
(function () {
  var dk = HT.todayKey();
  var at21 = new Date(dk + 'T21:00:00').getTime();
  HT.setClock(function () { return at21; });
  localStorage.clear(); HT.boot();
  dk = HT.state().current;
  var y = HT.shiftDate(dk, -1);
  window.confirm = function () { return true; }; window.prompt = function () { return null; };
  // yesterday: dinner at 19:00, a drink -- then nothing until 12:30 today, a 17.5 h gap (a pending fast)
  HT.state().days[y] = { status: 'complete', water_l: 1, items: [
    { name: 'Gate dinner', meal: 'dinner', time: '19:00', grams: 400, kcal: 600, protein_g: 30, fat_g: 20, carb_g: 60, fiber_g: 5, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' },
    { name: 'Gate wine', meal: 'drink', time: '19:30', grams: 150, kcal: 124, protein_g: 0, fat_g: 0, carb_g: 4, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' } ] };
  // today: lunch, half eaten (leftovers); a second item, deleted (the trash)
  var l = HT.addManualEntry({ name: 'Gate lunch', meal: 'lunch', time: '12:30', kcal: 500, protein_g: 20, fat_g: 20, carb_g: 50, grams: 300 });
  HT.logAteApply(l.item, 0.5);
  var d2 = HT.addManualEntry({ name: 'Gate snack', meal: 'snack', time: '13:00', kcal: 100, grams: 50 });
  HT.deleteItem(HT.state().days[dk].items.indexOf(d2.item));
  // a regimen for today; a sensor; an old badge drink; a sleep open 13 h (past its question)
  HT.addRegimenFromJSON(JSON.stringify({ name: 'Gate plan', entries: [
    { kind: 'medication', time: '08:00', name: 'Gate medicine', dose: 10, dose_unit: 'mg' },
    { kind: 'event', time: '12:00', type: 'walk' } ] }));
  HT.setActiveRegimen(HT.state().regimens.list[0].id);
  HT.state().settings.sensorDevice = 'dexcom-g7';
  HT.addSignal({ type: 'sensor', source: 'quick', date: dk, time: '09:00', variant: 'left arm', device: 'dexcom-g7' });
  HT.addSignal({ type: 'alcohol', source: 'quick', date: y, time: '20:00', value: 1, unit: 'drinks', variant: 'wine' });
  HT.state().settings.laneOpen = { sleep: { start: dk + 'T08:00', startedAt: new Date(at21 - 13 * 3600000).toISOString() } };
  HT.resave();
  // glucose: last night one reading below 3.0 (a flagged night -> the side question);
  // today flat, with an 18:00 climb and no food in the 4 h before it (a rise to answer)
  var rows = [], pad = function (n) { return String(n).padStart(2, '0'); };
  var push = function (ms, v) { var d = new Date(ms); var o = -d.getTimezoneOffset();
    var tz = (o < 0 ? '-' : '+') + pad(Math.floor(Math.abs(o) / 60)) + ':' + pad(Math.abs(o) % 60);
    rows.push({ t: d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':00' + tz, v: v, unit: 'mmol/L' }); };
  var y21 = new Date(y + 'T21:00:00').getTime();
  for (var m = 0; m <= 720; m += 5) push(y21 + m * 60000, m === 360 ? 2.8 : 5.4);
  var t9 = new Date(dk + 'T09:05:00').getTime();
  for (var k = 0; k <= 700; k += 5) { var mm = 545 + k; var v = 5.5; if (mm >= 1080 && mm <= 1120) v = 5.5 + 3.5 * (mm - 1080) / 40; if (mm > 1120) v = 9; push(t9 + k * 60000, v); }
  return Promise.resolve(HT.glucoseIngest(rows, { source: 'fixture' })).then(function () {
    HT.resave(); HT.refresh();
    // EVERY key: glucose, steps and the trash are stored apart from the log, and a
    // click that clears one must not leave the next click without it.
    window.__SNAP = {};
    for (var i = 0; i < localStorage.length; i++) { var key = localStorage.key(i); window.__SNAP[key] = localStorage.getItem(key); }
    sessionStorage.setItem('__egsnap', JSON.stringify(window.__SNAP));
    sessionStorage.setItem('__egclock', String(at21));
    return { ok: !!window.__SNAP['healthtracker-log'], keys: Object.keys(window.__SNAP).map(function (k) { return k + ':' + window.__SNAP[k].length; }).join(' '),
             tier: (typeof Store !== 'undefined') ? Store.tier : '?', dk: dk, trash: HT.trashRead().length, leftovers: HT.plateRecallCount(),
             flagged: HT.lowFlagState().flagged, pending: HT.pendingFastCandidates().length };
  });
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"ok":true*')) { Write-Host "ERROR: the fixture did not build"; Cleanup; exit 2 }

  # ---- the census ---------------------------------------------------------------------
  # Each click starts from a FRESH PAGE LOAD of the same stored state. An in-page
  # reset was tried first and is not enough: the app keeps view state in memory
  # (a "Not now" snooze lasts the session), so one click changed which controls
  # the next round saw. The snapshot and the clock ride in sessionStorage, which
  # survives a reload of the same tab.
  # __reset(): the snapshot back, booted at the fixture's clock, every disclosure
  # on the page opened. __controls(): every visible control outside + Log,
  # Settings and the Undo bar, in document order.
  $H = @'
(function () {
  window.__reset = function () {
    var snap = JSON.parse(sessionStorage.getItem('__egsnap') || '{}');
    var at = Number(sessionStorage.getItem('__egclock'));
    localStorage.clear();
    Object.keys(snap).forEach(function (k) { localStorage.setItem(k, snap[k]); });
    window.confirm = function () { return true; }; window.prompt = function () { return null; };
    HT.setClock(function () { return at; });
    HT.boot(); HT.refresh();
    try { HT.closeSheet(); } catch (e) {}
    try { HT.closeSettings(); } catch (e) {}
    var t = document.getElementById('toast'); if (t) { t.classList.remove('show'); t.textContent = ''; }
    try { HT.dayGroupsOpenAll(true); } catch (e) {}
    var gh = document.querySelector('#dayView .ghead'); if (gh && !document.querySelector('.elblock')) gh.click();
    Array.prototype.forEach.call(document.querySelectorAll('details'), function (d) {
      if (!d.closest('#entrySheet') && !d.closest('#settingsPanel')) d.open = true; });
    var tob = document.getElementById('timeOrderBox'); if (tob) tob.hidden = false;
  };
  window.__visible = function (el) { var r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden'; };
  window.__controls = function () {
    return Array.prototype.filter.call(document.querySelectorAll('button, a, [onclick], input, select, summary'), function (el) {
      if (el.closest('#entrySheet') || el.closest('#settingsPanel') || el.closest('#toast')) return false;
      if (el.closest('[style*="display:none"]') || el.closest('[style*="display: none"]') || el.closest('[hidden]')) return false;
      if (el.type === 'file' || el.type === 'hidden') return false;
      return window.__visible(el);
    });
  };
  window.__counts = function () {
    var S = HT.state(), o = { items: 0, timeline: 0, water: 0, lanes: 0, fasts: 0, regimen: 0 };
    Object.keys(S.days || {}).forEach(function (d) { o.items += (S.days[d].items || []).length; o.water += Number(S.days[d].water_l) || 0; });
    Object.keys(S.timeline || {}).forEach(function (d) { o.timeline += (S.timeline[d] || []).length; });
    o.lanes = Object.keys((S.settings && S.settings.laneOpen) || {}).length;
    o.fasts = JSON.stringify(S.fastLog || {}).length;
    o.regimen = JSON.stringify((S.regimens && S.regimens.log) || {}).length;
    return o;
  };
  window.__reset();
  return 1;
})()
'@
  function Fresh {
    [void](Eval "(function(){ var snap = JSON.parse(sessionStorage.getItem('__egsnap') || '{}'); localStorage.clear(); Object.keys(snap).forEach(function (k) { localStorage.setItem(k, snap[k]); }); return 1; })()")
    Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
    for ($w = 0; $w -lt 50; $w++) { Start-Sleep -Milliseconds 200
      if (Eval "typeof HT === 'object' && typeof HT.oneTapHTML === 'function' && document.readyState === 'complete'") { break } }
    [void](EvalA $H) }
  Fresh
  $n = [int](Eval "window.__controls().length")
  Write-Host ("  controls on the page, everything opened: " + $n)
  Check ($n -ge 25) "the census has something to count -- $n visible controls on the page with every surface seeded and opened"

  $results = @()
  for ($i = 0; $i -lt $n; $i++) {
    Fresh
    $one = EvalA @"
(function () {
  var els = window.__controls();
  var el = els[$i];
  if (!el) return { i: $i, missing: true, n: els.length };
  var d = { i: $i, tag: el.tagName.toLowerCase(), text: (el.textContent || el.value || '').replace(/\s+/g, ' ').trim().slice(0, 60),
            on: (el.getAttribute('onclick') || '').slice(0, 90), n: els.length };
  var href = el.tagName === 'A' ? (el.getAttribute('href') || '') : '';
  if (href && href.charAt(0) !== '#' && href.indexOf('javascript:') !== 0) { d.skipped = 'leaves the app'; return d; }
  var b = window.__counts();
  try { el.click(); } catch (e) { d.err = String(e); }
  return new Promise(function (r) { setTimeout(r, 120); }).then(function () {
    var a = window.__counts();
    d.grew = Object.keys(a).filter(function (k) { return a[k] > b[k] + 1e-9; });
    return d;
  });
})()
"@
    $results += ($one | ConvertFrom-Json)
  }
  $grew = @($results | Where-Object { $_.grew -and @($_.grew).Count -gt 0 })
  $missing = @($results | Where-Object { $_.missing })
  Check ($missing.Count -eq 0) "the control list is the SAME after every reset, so each index named one control (missing: $($missing.Count))"
  $answerRx = '^(event\.stopPropagation\(\);)?(resolveFastAt|eliteLabel|logSleepSide)\('
  $restoreRx = '^trashRestore\('
  $answers = @($grew | Where-Object { $_.on -match $answerRx })
  $restores = @($grew | Where-Object { $_.on -match $restoreRx })
  $outside = @($grew | Where-Object { -not ($_.on -match $answerRx) -and -not ($_.on -match $restoreRx) })
  foreach ($g in $grew) { Write-Host ("    writes: [" + ($g.grew -join ',') + "] '" + $g.text + "'  " + $g.on) }
  Check ($outside.Count -eq 0) "R215 GATE: NO control on the page writes an entry except the named answers -- every one of $n was clicked, and the writes found were all answers or a Restore"
  foreach ($o in $outside) { Write-Host ("    NOT ALLOWED: '" + $o.text + "' " + $o.on + " grew " + ($o.grew -join ',')) }
  $kinds = @($answers | ForEach-Object { ($_.on -replace '^event\.stopPropagation\(\);', '') -replace '\(.*$', '' } | Sort-Object -Unique)
  Check (($kinds -join ',') -eq 'eliteLabel,logSleepSide,resolveFastAt') "and ALL THREE named answers were on the page and did write: the fasting gap, the glucose rise, the side slept on (found: $($kinds -join ','))"
  Check ($restores.Count -ge 1) "the trash's Restore was on the page too, and is counted apart from the answers -- it brings back an entry, it does not make one"
  $moved = @($results | Where-Object { $_.on -match '^(quickEvent|addWater|laneOn|laneOff|laneTapStart|laneTapEnd|lanePickOpen|regimenLogTap|regimenConfirmLog|substituteRegimenEntry|drinkTap|drinkRepeatAt|openPlateConsume|logRepeat|logSignalPreset)\(' })
  Check ($moved.Count -eq 0) "none of the moved controls is on the page in any form -- no Moved/Woke/sensor/water/start/stop/regimen/leftover/drink button outside + Log (found $($moved.Count))"

  # ---- the links open + Log at the right spot --------------------------------------------
  Fresh
  $links = EvalA @'
(function () {
  window.__reset();
  var out = {};
  var pl = document.querySelector('#dayView .plline:not(.rglink)');
  out.leftLine = pl ? pl.textContent : '';
  if (pl) pl.click();
  out.leftOpen = !!document.querySelector('#sheetRoot .plrecall .plrow') && window.__visible(document.getElementById('sheetRoot'));
  window.__reset();
  var rg = document.querySelector('#dayView .rglink');
  out.rgLine = rg ? rg.textContent : '';
  if (rg) rg.click();
  out.rgOpen = !!document.querySelector('#sheetRoot #sheetRegimen .rgrow') && window.__visible(document.getElementById('sheetRoot'));
  out.rgOnPage = document.querySelectorAll('#regimenChecklist .rgrow').length;
  window.__reset();
  out.ringLinks = 0;
  try { HT.summonLane('sauna'); out.ringLinks = (document.querySelector('#dayView .rctrl') || { innerHTML: '' }).innerHTML.indexOf("openSheet('signal')") >= 0 ? 1 : 0;
        out.ringWrites = /laneOn\(|laneOff\(/.test((document.querySelector('#dayView') || {}).innerHTML || ''); } catch (e) { out.err = String(e); }
  return out;
})()
'@
  Write-Host ("  links: " + $links)
  $lk = $links | ConvertFrom-Json
  Check (($lk.leftLine -like '*leftover*') -and ($lk.leftOpen -eq $true)) "the 'N leftover' line opens + Log on the leftovers, listed there to tap"
  Check (($lk.rgLine -like '*regimen*of*logged*') -and ($lk.rgOpen -eq $true) -and ($lk.rgOnPage -eq 0)) "the regimen line says how much is logged and opens + Log on today's checklist; the checklist itself is no longer on the page"
  Check (($lk.ringLinks -eq 1) -and ($lk.ringWrites -eq $false)) "the ring is read-only: a summoned lane states itself and links to + Log, with no on or off"

  # ---- every one-tap control in + Log writes, and its Undo takes it back ---------------
  # A real click on each, then a real click on the Undo bar.
  $taps = @(
    @{ sel = "#sigOneTap .otwater button:nth-of-type(1)"; name = "+0.25 L of water" },
    @{ sel = "#sigOneTap .otwater button:nth-of-type(2)"; name = "+0.5 L of water" },
    @{ sel = "#sigOneTap button[onclick^=""quickEvent('moved'""]"; name = "Moved" },
    @{ sel = "#sigOneTap button[onclick^=""laneTapStart('sauna'""]"; name = "Sauna start" },
    @{ sel = "#sigOneTap button[onclick^=""laneTapStart('red_light'""]"; name = "Red light start" },
    @{ sel = "#sigOneTap button[onclick^=""quickEvent('sensor', 'right arm'""]"; name = "New sensor, right arm" },
    @{ sel = "#sheetRoot .drkrow"; name = "a drink from Your drinks"; root = $true }
  )
  foreach ($t in $taps) {
    $mode = if ($t.root) { "root" } else { "signal" }
    $sel = $t.sel -replace "'", "\'"
    Fresh
    $r = EvalA @"
(function () {
  window.__reset();
  HT.state().settings.laneOpen = {}; HT.resave(); HT.refresh();
  HT.openSheet('$mode');
  var el = document.querySelector('$sel');
  if (!el) return { missing: true };
  var b = window.__counts(), k0 = HT.dayTotals(HT.state().days[HT.state().current]).kcal;
  el.click();
  var a = window.__counts(), k1 = HT.dayTotals(HT.state().days[HT.state().current]).kcal;
  var u = document.querySelector('#toast.show .tundo');
  var words = (document.getElementById('toast') || {}).textContent || '';
  if (u) u.click();
  var c = window.__counts();
  var same = function (x, y) { return Object.keys(x).every(function (k) { return Math.abs(x[k] - y[k]) < 1e-9; }); };
  return { grew: Object.keys(a).filter(function (k) { return a[k] > b[k] + 1e-9; }), words: words.slice(0, 80), undo: !!u, back: same(b, c), kcal: k1 - k0 };
})()
"@
    Write-Host ("  " + $t.name + ": " + $r)
    $rr = $r | ConvertFrom-Json
    Check ((-not $rr.missing) -and (@($rr.grew).Count -ge 1) -and $rr.undo -and $rr.back) ("in + Log, '" + $t.name + "' writes on one tap, and its Undo puts every count back where it was")
    if ($t.root) { Check ([double]$rr.kcal -gt 100) "R215 GATE: a drink from Your drinks ADDS ITS CALORIES to the day (+$($rr.kcal) cal) -- the defect R214 reported was a drink that did not" }
  }

  # ---- R221/2: a water mis-tap stays fixable after its Undo bar has gone ------------
  # The ruled gate, by real taps: +0.5 twice, wait past the Undo, delete one on the
  # day -> the day's water drops by exactly 0.5.
  Fresh
  $w0 = EvalA @'
(function () {
  HT.openSheet('signal');
  var b = document.querySelector('#sigOneTap .otwater button:nth-of-type(2)');
  var d = HT.state().current, before = HT.dayWater(d);
  b.click(); b.click();
  return { label: b.textContent, before: before, after: HT.dayWater(d), entries: HT.dayWaterEntries(d).length };
})()
'@
  Write-Host ("  two water taps: " + $w0)
  Start-Sleep -Milliseconds 6500
  $w1 = EvalA @'
(function () {
  var d = HT.state().current;
  var undoGone = !document.querySelector('#toast.show .tundo');
  HT.closeSheet(); HT.dayGroupsOpenAll(true);
  var rows = Array.prototype.filter.call(document.querySelectorAll('#dayView .bgline'), function (r) { return /Water/.test((r.querySelector('.mginame') || {}).textContent || ''); });
  var x = rows[0] && rows[0].querySelector('.bgrm');
  var before = HT.dayWater(d);
  var size = x ? x.getBoundingClientRect() : null;
  if (x) x.click();
  return { undoGone: undoGone, rows: rows.length, x: !!x, h: size ? Math.round(size.height) : 0, w: size ? Math.round(size.width) : 0,
           before: before, after: HT.dayWater(d), entries: HT.dayWaterEntries(d).length,
           undoBack: !!document.querySelector('#toast.show .tundo') };
})()
'@
  Write-Host ("  after the Undo bar, one deleted on the day: " + $w1)
  $wa = $w0 | ConvertFrom-Json; $wb = $w1 | ConvertFrom-Json
  Check (($wa.label -like '+0.5*') -and ([Math]::Abs($wa.after - $wa.before - 1.0) -lt 1e-6) -and ($wa.entries -eq 2)) "R221/2: two taps of +0.5 L are two entries, and the day's water rises by 1.0"
  Check ($wb.undoGone -and ($wb.rows -eq 2) -and $wb.x -and ($wb.h -ge 44) -and ($wb.w -ge 44)) "R221/2: with the Undo bar long gone, both are LISTED on the day, each with a 44 px x"
  Check (([Math]::Abs($wb.before - $wb.after - 0.5) -lt 1e-6) -and ($wb.entries -eq 1) -and $wb.undoBack) "R221/2 GATE: deleting one drops the day's water by exactly 0.5 -- and that delete has its own Undo"

  # ---- R223: waking up is the easiest thing in the app -- counted in TAPS ---------------
  # Reported from real use: ring -> Sleep -> a small "close" -> the night logged again
  # as an event: 4+ taps, a hidden control, and two records for one sleep. Ruled: a
  # wake-up is at most 3 taps from the day page, a bedtime at most 3, ONE record per
  # night, and the time the picker is given is the time stored. Every tap below is a
  # real click on an element that is ON SCREEN when it is clicked; they are counted.
  $tapJs = @'
  window.__taps = 0;
  window.__tap = function (el, what) {
    if (!el) throw new Error('no ' + what);
    var r = el.getBoundingClientRect();
    if (!(r.width > 0 && r.height > 0 && r.top >= 0 && r.bottom <= window.innerHeight)) throw new Error(what + ' is not on screen (' + Math.round(r.top) + '..' + Math.round(r.bottom) + ')');
    window.__taps++; el.click(); return r;
  };
  window.__sleeps = function () { var n = 0, tl = HT.state().timeline || {}; Object.keys(tl).forEach(function (d) { (tl[d] || []).forEach(function (r) { if (r.type === 'sleep') n++; }); }); return n; };
'@
  Fresh
  $wk = EvalA ($tapJs + @'
(function () {
  window.__reset();
  var d = HT.state().current;
  HT.state().settings.laneOpen.sleep.start = d + 'T14:00'; HT.resave(); HT.refresh();
  window.scrollTo(0, 0);
  var o = { sleepsBefore: window.__sleeps() };
  window.__tap(document.querySelector('#dayView .ringbox'), 'the ring');
  var big = document.querySelector('#sigOneTap .otsleepbig');
  o.big = big ? big.textContent : '';
  var br = window.__tap(big, 'the Woke button');
  o.bigH = Math.round(br.height); o.bigW = Math.round(br.width); o.vw = window.innerWidth;
  o.asked = !!document.querySelector('#sigOneTap .lpick') && window.__sleeps() === o.sleepsBefore;
  var now = document.querySelector('#sigOneTap .lpick .lpnow');
  o.nowDefault = !!now && now.classList.contains('primary');
  window.__tap(now, 'Now');
  o.taps = window.__taps;
  o.sleepsAfter = window.__sleeps();
  o.closed = !HT.laneOpenState('sleep').open;
  var rec = (HT.state().timeline[d] || []).filter(function (r) { return r.type === 'sleep'; }).pop();
  o.wake = rec ? HT.minutesToHHMM(HT.sleepWakeMin(rec)) : '';
  return o;
})()
'@)
  Write-Host ("  waking, from the day: " + $wk)
  $w = $wk | ConvertFrom-Json
  Check (($w.big -like ('Woke ' + [char]0x2014 + ' end sleep*')) -and ($w.bigH -ge 44) -and ($w.bigW -ge ($w.vw - 60))) "R223: the ring opens + Log on ONE big button -- 'Woke - end sleep', $($w.bigH) px tall, full width"
  Check ($w.asked -and $w.nowDefault) "it asks the time first, Now highlighted, nothing written yet"
  Check (($w.taps -le 3) -and ($w.sleepsAfter -eq $w.sleepsBefore + 1) -and $w.closed -and ($w.wake -eq '21:00')) "R223 GATE: WAKING UP IN $($w.taps) TAPS from the day page -- ring, Woke, Now -- one sleep record, the sleep closed, woke 21:00"

  Fresh
  $bd = EvalA ($tapJs + @'
(function () {
  window.__reset();
  delete HT.state().settings.laneOpen.sleep; HT.resave(); HT.refresh();
  window.scrollTo(0, 0);
  var o = {};
  window.__tap(document.querySelector('#dayView .ringbox'), 'the ring');
  var big = document.querySelector('#sigOneTap .otsleepbig');
  o.big = big ? big.textContent : '';
  window.__tap(big, 'Going to sleep');
  window.__tap(document.querySelector('#sigOneTap .lpick .lpnow'), 'Now');
  o.taps = window.__taps;
  o.open = HT.laneOpenState('sleep').open;
  o.start = (HT.state().settings.laneOpen.sleep || {}).start || '';
  return o;
})()
'@)
  Write-Host ("  going to sleep, from the day: " + $bd)
  $b = $bd | ConvertFrom-Json
  Check (($b.big -eq 'Going to sleep') -and ($b.taps -le 3) -and $b.open -and ($b.start -like '*T21:00')) "R223 GATE: GOING TO SLEEP IN $($b.taps) TAPS from the day page -- ring, Going to sleep, Now -- the sleep open from 21:00"

  Fresh
  $one = EvalA ($tapJs + @'
(function () {
  window.__reset();
  var d = HT.state().current;
  HT.state().settings.laneOpen.sleep.start = d + 'T14:00'; HT.resave(); HT.refresh();
  var o = { before: window.__sleeps() };
  // the reported path: the night typed into the event form while the sleep is open
  HT.openSheet('signal');
  var sel = document.getElementById('sigType'); sel.value = 'sleep'; sel.dispatchEvent(new Event('change'));
  document.getElementById('sigValue').value = '6.5';
  document.getElementById('sigTime').value = '14:00';
  document.querySelector('#pane-signal .btn.primary[onclick^="addSignalFromForm"]').click();
  o.afterForm = window.__sleeps();
  o.openAfterForm = HT.laneOpenState('sleep').open;
  o.toast = ((document.getElementById('toast') || {}).textContent || '').slice(0, 90);
  // there is nothing left to end, so a second record cannot be made by ending it
  o.bigNow = (document.querySelector('#sigOneTap .otsleepbig') || {}).textContent || '';
  var u = document.querySelector('#toast.show .tundo'); if (u) u.click();
  o.afterUndo = window.__sleeps(); o.reopened = HT.laneOpenState('sleep').open;
  // the picker's own time is the time stored
  HT.openSheet('signal');
  document.querySelector('#sigOneTap .otsleepbig').click();
  document.getElementById('lpTime').value = '19:15';
  document.querySelector('#sigOneTap .lpsave').click();
  var rec = (HT.state().timeline[d] || []).filter(function (r) { return r.type === 'sleep'; }).pop();
  o.picked = rec ? HT.minutesToHHMM(HT.sleepWakeMin(rec)) : ''; o.src = rec ? rec.wake_src : '';
  o.final = window.__sleeps();
  // and the ring's detail view has no "close" any more
  HT.closeSheet(); HT.ringLegendToggle(true); HT.summonLane('sleep');
  var c = document.querySelector('#dayView .rctrl');
  o.ctrl = c ? c.textContent : ''; o.keyBtn = !!document.querySelector('#dayView .ringkeybtn');
  return o;
})()
'@)
  Write-Host ("  one sleep, one record: " + $one)
  $q = $one | ConvertFrom-Json
  Check (($q.afterForm -eq $q.before + 1) -and (-not $q.openAfterForm) -and ($q.toast -like '*open sleep was ended*') -and ($q.bigNow -eq 'Going to sleep')) "R223 GATE: ONE SLEEP, ONE RECORD -- the night typed while a sleep was open ENDS the open one (it says so), so it cannot be ended again into a second record"
  Check (($q.afterUndo -eq $q.before) -and $q.reopened) "and Undo takes the typed night back and reopens the sleep"
  Check (($q.picked -eq '19:15') -and ($q.src -eq 'typed') -and ($q.final -eq $q.before + 1)) "R223 GATE: the time given to the picker is the time stored -- woke 19:15 -- and the night is still ONE record"
  Check ((-not ($q.ctrl -match '(?i)close')) -and $q.keyBtn) "R223: the ring's detail view has no 'close'; the key has its own button beside the ring"

  # ---- and never closed for the user ----------------------------------------------------
  Fresh
  $sl = EvalA @'
(function () {
  window.__reset();
  HT.setClock(function () { return new Date(HT.state().current + 'T21:00:00').getTime() + 20 * 3600000; });
  HT.refresh();
  return { stillOpen: HT.laneOpenState('sleep').open };
})()
'@
  Write-Host ("  a day later: " + $sl)
  Check (($sl | ConvertFrom-Json).stillOpen) "R215 GATE: open for more than a day and redrawn, the sleep is STILL OPEN -- nothing closes it for the user any more"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -eq 0) {
  Write-Host "ENTRY GATE: PASS -- every control on the page clicked; only the three named answers (and Restore) write; the moved controls are in + Log, each with its Undo; the links open + Log on what they name; sleep is asked, never closed for the user"
  Write-Host "GATE: PASS"
  exit 0
}
Write-Host ("ENTRY GATE: FAIL -- " + $fails.Count + " check(s)")
Write-Host "GATE: FAIL"
exit 1
