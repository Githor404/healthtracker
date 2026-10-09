# R159.1 -- THE LANDING PAGE, grouped. And R138, folded in.
#
# RULED (user, 2026-10-09):
#   D       collapse the empty meals into ONE muted line ("No breakfast or snack
#           logged"), TAPPABLE to add to that meal. Meals with items get headers.
#           "I eat in a window; four fixed headers would be mostly dashes."
#   F       a draft lands on the day it was STARTED, never retargeted when the
#           date flips.
#   A       a frequency count NAMES WHAT IT COUNTED.
#   ref.g   scale when present; drop the match (with the existing note) when absent.
#   R138    fix on resume -- visibilitychange re-checks the calendar day.
#   B,C,E   as recommended.
#
# MEASURED FIRST, on the real log (40 days, 55 items):
#   - 10 foods repeat, and ONLY under matchKey (exact name gives 7). One at 5x,
#     nine at 2x, the eleventh at 1x.
#   - 8 of those 10 repeat at a DIFFERENT portion; the top one spans 120-390 g.
#     So the stepper starts at the MOST RECENT portion, labelled, never an average.
#   - one of the ten has NO grams at all, so it steps a COUNT instead.
#   - 24 of 40 days have no items; 0 of 40 carry breakfast AND lunch AND dinner;
#     breakfast appears 0 times ever. Hence ruling D.
#   - ref.g is on ZERO of 55 items, so on today's data every portion change drops
#     the match -- and the screen must say so rather than imply a scaled number.
#
# AND D137 ALREADY RULED THE COUNT'S HONESTY. The key merges five pairs of names on
# this log, one of them across "with beef" / "without". D137: every proposal names
# the item it came from. A COUNT has several, and "2x" names none -- so the row
# carries the names behind it, and its numbers come from ONE chosen item.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8287
$Dbg = 9493
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-landing-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

function Find-Browser {
  foreach ($c in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 262144
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count)
    if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$method, [hashtable]$prms) {
  $script:cid++
  $payload = @{ id = $script:cid; method = $method }
  if ($prms) { $payload.params = $prms }
  $json = $payload | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $guard = 0
  while ($true) {
    if (++$guard -gt 900) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  if ($r.result.exceptionDetails) {
    return 'EXCEPTION: ' + $r.result.exceptionDetails.text + ' | ' + $r.result.exceptionDetails.exception.description
  }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
  $mimes = @{ '.html' = 'text/html'; '.js' = 'application/javascript'; '.json' = 'application/json';
              '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.css' = 'text/css';
              '.bin' = 'application/octet-stream' }
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
    try { $ctx.Response.Close() } catch { }
  }
}

function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

$fails = @()
function Chk([bool]$ok, [string]$msg) { if (-not $ok) { $script:fails += $msg } }

try {
  Start-Sleep -Milliseconds 600
  $chromeArgs = @("--headless=new", "--remote-debugging-port=$Dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $chromeArgs -PassThru
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $page = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($page) { $tabUrl = $page.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }

  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 360; height = 740; deviceScaleFactor = 2; mobile = $true } | Out-Null
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $sane = Eval "typeof HT"
  if ($sane -ne 'object') { Write-Host "ERROR: the page did not load (typeof HT = $sane)"; Cleanup; exit 2 }

  $probe = @'
window.__out = null;
window.__stage = 'start';
(async function () {
  const O = { api: {}, groups: {}, none: {}, resp: {}, bio: {}, freq: {}, sheet: {},
              step: {}, logged: {}, roll: {}, draft: {}, ink: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const stage = (x) => { window.__stage = x; O.stage = x; };
  const txt = (el) => String((el && el.textContent) || '');
  const all = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel));
  const vis = (el) => !!(el && el.offsetParent !== null);
  const D = '2026-10-09';
  try {
  stage('boot');
  HT.setClock(function () { return Date.parse('2026-10-09T14:30:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);

  ['mealKindGroups', 'emptyMealKinds', 'foodFrequency', 'quickSheetOpen',
   'quickPick', 'quickStep', 'quickAddLog', 'mealByTimeOfDay', 'dayGroupToggle',
   'biometricSummary', 'dayRollCheck']
    .forEach(function (k) { O.api[k] = typeof HT[k]; });
  O.api.topN = HT.FREQ_TOP_N;
  // RULED: the new logger is named distinctly from `quickLog`, which already
  // exists as the PRESET logger. Asserting `quickLog` is a function would have
  // passed against that one before a line of this slice was written, and a
  // second definition of the name would silently win (D159). So the DISTINCTNESS
  // is the assertion: both exist, and they are not the same function.
  O.api.presetLogger = typeof HT.quickLog;
  O.api.loggersDistinct = (typeof HT.quickAddLog === 'function')
    && (typeof HT.quickLog === 'function') && (HT.quickAddLog !== HT.quickLog);

  // ---- THE FIXTURE: a day shaped like the real log -- a window, not four meals
  stage('seed');
  const S = HT.state();
  const it = (o) => Object.assign({ meal: 'lunch', time: '12:00', grams: 150, kcal: 300,
    protein_g: 10, fat_g: 10, carb_g: 30, fiber_g: 3, soluble_fiber_g: 1,
    confidence: 'eyeballed', source: 'ai-paste', notes: '' }, o);

  // LUNCH: two items, ONE event -- so the header may carry a response line
  // DINNER: two events -- so the header must NOT carry one line for both
  // a DRINK sharing lunch's mealId -- "drinks stay inside their meal"
  // NO breakfast, NO snack -- the measured shape, and what ruling D is for
  S.days[D] = { status: 'in_progress', water_l: 0, items: [
    it({ name: 'ramen noodles', time: '12:00', mealId: 'm1', kcal: 235, grams: 170 }),
    it({ name: 'chashu pork belly', time: '12:05', mealId: 'm1', kcal: 182, grams: 65 }),
    it({ name: 'green tea', time: '12:10', mealId: 'm1', meal: 'drink', kcal: 2, grams: 200 }),
    it({ name: 'first dinner', time: '18:00', mealId: 'm2', meal: 'dinner', kcal: 400 }),
    it({ name: 'second dinner', time: '20:30', mealId: 'm3', meal: 'dinner', kcal: 250 })
  ] };
  // history, so the frequency list has something to count: the measured shape of
  // one food at 5x under two spellings, and one with NO grams at all.
  // THE FOURTH COLUMN IS THE RULED ref.g CASE, and it needs BOTH shapes or only
  // one branch is ever exercised. Measured: ref.g is on ZERO of 55 real items,
  // so 'drop the match and say so' is the branch today's data takes -- which is
  // precisely why the scaling branch must be fixtured deliberately.
  //   'nog'  -> a match with NO basis: a portion change must DROP it and note it
  //   'withg'-> a match WITH a basis:  a portion change must RE-EXPRESS it
  const hist = [
    ['2026-10-01', 'creamy coleslaw', 130, 'nog'],
    ['2026-10-02', 'creamy coleslaw with mixed vegetables', 390, 'nog'],
    ['2026-10-03', 'creamy coleslaw', 210, 'nog'],
    ['2026-10-04', 'craisins', null, ''],
    ['2026-10-05', 'craisins', null, ''],
    ['2026-10-06', 'smoked salmon', 190, 'withg'],
    ['2026-10-07', 'smoked salmon', 190, 'withg']
  ];
  hist.forEach(function (h, i) {
    const o = { name: h[1], time: '13:00', mealId: 'h' + i, kcal: 120 + i };
    if (h[2] == null) delete o.grams; else o.grams = h[2];
    if (h[3] === 'nog') {
      o.ref = { ns: 'cnf', id: '900', name: h[1], at: h[0], at_ms: 1,
                how: 'exact', when: 'cooked', v: { 203: 4 } };
    } else if (h[3] === 'withg') {
      o.ref = { ns: 'cnf', id: '901', name: h[1], at: h[0], at_ms: 1,
                how: 'exact', when: 'cooked', g: h[2], v: { 203: 4 } };
    }
    S.days[h[0]] = { status: 'complete', water_l: 0, items: [ it(o) ] };
    if (h[2] == null) delete S.days[h[0]].items[0].grams;
  });
  S.current = D;
  // A REAL STREAM, so the response line is exercised in BOTH directions. Without
  // it, dinner carries no line because there is nothing to say -- and a refusal
  // indistinguishable from an absence measures nothing. Lunch gets a clean
  // baseline and a rise that returns; BOTH dinner sittings get readings too, so
  // the dinner header's refusal to print ONE line for TWO meals is a decision.
  const gl = [];
  const two = function (x) { return (x < 10 ? '0' : '') + x; };
  const put = function (mins, v) {
    gl.push({ t: D + 'T' + two(Math.floor(mins / 60)) + ':' + two(mins % 60)
              + ':00-04:00', v: Math.round(v * 10) / 10, unit: 'mmol/L' });
  };
  for (var mm = 11 * 60 + 30; mm <= 15 * 60; mm += 5) {
    var v = 5.2;
    if (mm > 720 && mm <= 750) v = 5.2 + 2.6 * ((mm - 720) / 30);
    else if (mm > 750 && mm <= 840) v = 7.8 - 2.6 * ((mm - 750) / 90);
    put(mm, v);
  }
  for (var m2 = 17 * 60 + 30; m2 <= 22 * 60; m2 += 5) put(m2, 5.4);
  HT.glucoseIngest(gl);
  HT.Store.saveState(S);
  HT.refresh();
  await sleep(400);

  // ---- 1. GROUPS: only the meals that HAVE items get headers ---------------
  stage('groups');
  if (typeof HT.mealKindGroups === 'function') {
    const g = HT.mealKindGroups(D);
    O.groups.raw = JSON.stringify(g).slice(0, 900);
    O.groups.kinds = g.map(function (x) { return String(x.kind); });
    const L = g.filter(function (x) { return x.kind === 'lunch'; })[0];
    const DI = g.filter(function (x) { return x.kind === 'dinner'; })[0];
    O.groups.lunchN = L ? L.n : null;
    O.groups.lunchKcal = L ? L.kcal : null;
    O.groups.lunchFirst = L ? String(L.firstTime || '') : '';
    O.groups.lunchDrinks = L ? L.drinks : null;
    O.groups.lunchEvents = L ? (L.events || []).length : null;
    O.groups.dinnerEvents = DI ? (DI.events || []).length : null;
  }
  if (typeof HT.emptyMealKinds === 'function') O.none.kinds = HT.emptyMealKinds(D);

  const host = document.getElementById('dayView');
  O.groups.headers = all('#dayView .mghead').map(function (h) { return txt(h).replace(/\s+/g, ' ').trim(); });
  O.groups.count = all('#dayView .mgrp').length;
  O.none.rows = all('#dayView .mgnone').length;
  O.none.text = all('#dayView .mgnone').map(function (h) { return txt(h).replace(/\s+/g, ' ').trim(); }).join(' | ');
  O.none.taps = all('#dayView .mgnone [onclick]').length;
  O.none.tapTargets = all('#dayView .mgnone [onclick]').map(function (b) {
    const r = b.getBoundingClientRect();
    return Math.round(r.width) + 'x' + Math.round(r.height);
  });
  // THE BADGES THE REDESIGN REPLACES MUST BE GONE. The draft of this gate looked
  // for `.dkinds, .daybadge, .dbadge` -- none of which exist anywhere in this
  // repo, so it passed before anything was built. The row the user means is
  // QUICK_ADD (`.qab`), the only place Food/Dose/Biometric/Fast/Note render.
  // Counted by CLASS and by the rendered WORDS, with the ruled replacement
  // required present -- otherwise a blank screen satisfies 'the badges are gone'.
  O.groups.badges = all('#dayView .qab').length;
  O.groups.badgeLabels = all('#dayView button').map(function (b) { return txt(b).trim(); })
    .filter(function (sx) { return ['Food', 'Dose', 'Biometric', 'Fast', 'Note'].indexOf(sx) >= 0; });
  O.groups.qa10 = all('#dayView .qa10').length;
  O.groups.cam = all('#dayView .dcam').length;

  // ---- 2. the drink stays inside its meal, flagged ------------------------
  stage('drink');
  O.groups.drinkChip = all('#dayView .mgdrink').map(function (c) { return txt(c).trim(); }).join(' | ');

  // ---- 3. EXPAND: in place, chronological, others stay collapsed ----------
  stage('expand');
  if (typeof HT.dayGroupToggle === 'function') HT.dayGroupToggle('lunch');
  HT.refresh();
  await sleep(350);
  O.groups.openBodies = all('#dayView .mgbody').length;
  O.groups.openKinds = all('#dayView .mgrp').filter(function (g2) {
    return !!g2.querySelector('.mgbody'); }).map(function (g2) {
    return String(g2.getAttribute('data-kind') || ''); });
  O.groups.itemTimes = all('#dayView .mgbody .mgitime').map(function (t) { return txt(t).trim(); });
  O.groups.itemFlags = all('#dayView .mgbody .mgitem').map(function (r) {
    return (r.className.indexOf('mgidrink') >= 0 ? 'DRINK:' : '') + txt(r.querySelector('.mginame')).trim(); });
  O.groups.hasMacros = all('#dayView .mgbody .mgmac').length;

  // ---- 4. the response line: one event may carry it, two may not ----------
  stage('resp');
  O.resp.onLunchHead = all('#dayView .mgrp[data-kind="lunch"] .mghead .mgresp').length;
  O.resp.onDinnerHead = all('#dayView .mgrp[data-kind="dinner"] .mghead .mgresp').length;
  O.resp.dinnerSaysHowMany = txt(document.querySelector('#dayView .mgrp[data-kind="dinner"] .mghead')).replace(/\s+/g, ' ');

  // ---- 5. BIOMETRICS: its own group, with a one-line summary -------------
  stage('bio');
  O.bio.group = all('#dayView .bgrp').length;
  O.bio.fnType = typeof HT.biometricSummary;
  O.bio.summary = all('#dayView .bgsum').map(function (b) { return txt(b).trim(); }).join(' | ');
  if (typeof HT.biometricSummary === 'function') O.bio.fn = JSON.stringify(HT.biometricSummary(D)).slice(0, 200);

  // ---- 6. FREQUENCY: counts by matchKey and NAMES WHAT IT COUNTED --------
  stage('freq');
  if (typeof HT.foodFrequency === 'function') {
    const f = HT.foodFrequency();
    O.freq.n = f.length;
    O.freq.top = f.slice(0, 5).map(function (x) {
      return x.n + 'x [' + x.key + '] names=' + (x.names || []).length
        + ' port=' + (x.grams == null ? 'none' : x.grams) + ' cal=' + x.kcal; });
    const cole = f.filter(function (x) { return /coleslaw/.test(x.key); })[0];
    O.freq.coleN = cole ? cole.n : null;
    O.freq.coleNames = cole ? (cole.names || []).length : null;
    O.freq.coleGrams = cole ? cole.grams : null;
    const cr = f.filter(function (x) { return /craisin/.test(x.key); })[0];
    O.freq.craisinGrams = cr ? cr.grams : 'MISSING';
    O.freq.craisinN = cr ? cr.n : null;
  }

  // ---- 7. THE SHEET: the row names the spellings behind its count --------
  stage('sheet');
  if (typeof HT.quickSheetOpen === 'function') { HT.quickSheetOpen(); await sleep(350); }
  O.sheet.rows = all('.qfrow').length;
  O.sheet.namesShown = all('.qfrow .qnames').length;
  O.sheet.coleRow = (all('.qfrow').filter(function (r) { return /coleslaw/i.test(txt(r)); })[0] || {});
  O.sheet.coleText = O.sheet.coleRow.textContent ? String(O.sheet.coleRow.textContent).replace(/\s+/g, ' ').trim() : '';
  delete O.sheet.coleRow;
  O.sheet.anyAverage = /average|mean/i.test(txt(document.querySelector('.qsheet')) || '');

  // ---- 8. THE STEPPER: starts at the MOST RECENT portion, labelled -------
  stage('step');
  const coleKey = (typeof HT.foodFrequency === 'function')
    ? ((HT.foodFrequency().filter(function (x) { return /coleslaw/.test(x.key); })[0] || {}).key || '') : '';
  if (typeof HT.quickPick === 'function' && coleKey) { HT.quickPick(coleKey); await sleep(300); }
  O.step.shown = all('.qstep').length;
  O.step.n = txt(document.querySelector('.qn')).trim();
  O.step.lastLabel = txt(document.querySelector('.qlast')).replace(/\s+/g, ' ').trim();
  O.step.gramsField = all('.qgrams').length;
  O.step.logBtn = txt(document.querySelector('.qlog')).replace(/\s+/g, ' ').trim();
  O.step.mealLine = txt(document.querySelector('.qmeal')).replace(/\s+/g, ' ').trim();
  O.step.changeLink = all('.qchange').length;
  if (typeof HT.quickStep === 'function') { HT.quickStep(1); await sleep(200); }
  O.step.afterPlus = txt(document.querySelector('.qn')).trim();
  O.step.logAfterPlus = txt(document.querySelector('.qlog')).replace(/\s+/g, ' ').trim();

  // ---- 9. LOGGING: lands now, in the meal for the time of day -----------
  stage('log');
  if (typeof HT.mealByTimeOfDay === 'function') {
    O.logged.at1230 = HT.mealByTimeOfDay('12:30');
    O.logged.at0800 = HT.mealByTimeOfDay('08:00');
    O.logged.at1900 = HT.mealByTimeOfDay('19:00');
    O.logged.at2300 = HT.mealByTimeOfDay('23:00');
  }
  const before = (HT.state().days[D].items || []).length;
  if (typeof HT.quickAddLog === 'function') {
    const r = await Promise.resolve(HT.quickAddLog());
    O.logged.result = JSON.stringify(r).slice(0, 200);
  }
  const after = (HT.state().days[D].items || []);
  O.logged.added = after.length - before;
  const neu = after[after.length - 1] || {};
  O.logged.name = String(neu.name || '');
  O.logged.meal = String(neu.meal || '');
  O.logged.grams = neu.grams == null ? 'none' : neu.grams;
  O.logged.hasRef = !!(neu.ref && neu.ref.id);
  O.logged.lostNote = !!(neu.repeated_from && neu.repeated_from.lostMatch);
  O.logged.day = Object.keys(HT.state().days).filter(function (k) {
    return (HT.state().days[k].items || []).some(function (x) { return x === neu; }); })[0] || '?';
  // AND THE OTHER BRANCH: a row whose match HAS a basis must keep it, re-expressed.
  const salKey = (typeof HT.foodFrequency === 'function')
    ? ((HT.foodFrequency().filter(function (x) { return /salmon/.test(x.key); })[0] || {}).key || '') : '';
  if (salKey && typeof HT.quickPick === 'function') {
    HT.quickPick(salKey); await sleep(150);
    HT.quickStep(1); await sleep(150);
    const r2 = await Promise.resolve(HT.quickAddLog());
    O.logged.salResult = JSON.stringify(r2).slice(0, 160);
    const its2 = HT.state().days[D].items || [];
    const sal = its2[its2.length - 1] || {};
    O.logged.salHasRef = !!(sal.ref && sal.ref.id);
    O.logged.salRefG = (sal.ref && sal.ref.g != null) ? sal.ref.g : null;
    O.logged.salGrams = (sal.grams == null) ? null : sal.grams;
  }

  // ---- 10. R138: a resume on a NEW calendar day lands on today ----------
  stage('roll');
  const was = HT.state().current;
  HT.setClock(function () { return Date.parse('2026-10-10T09:00:00-04:00'); });
  O.roll.before = String(HT.state().current);
  if (typeof HT.dayRollCheck === 'function') {
    const rr = HT.dayRollCheck();
    O.roll.result = JSON.stringify(rr).slice(0, 160);
  }
  O.roll.after = String(HT.state().current);
  O.roll.moved = (O.roll.before !== O.roll.after && O.roll.after === '2026-10-10');
  // and it is IDEMPOTENT -- a second resume on the same day changes nothing
  if (typeof HT.dayRollCheck === 'function') { HT.dayRollCheck(); }
  O.roll.stable = (String(HT.state().current) === '2026-10-10');

  // ---- 11. RULING F: a draft keeps the day it was STARTED ---------------
  stage('draft');
  HT.setClock(function () { return Date.parse('2026-10-10T23:50:00-04:00'); });
  HT.dayRollCheck();
  O.draft.startedOn = String(HT.state().current);
  const reply = JSON.stringify({ meal: 'snack', items: [ { name: 'late toast',
    alts: [ { name: 'late toast', p: 1 } ], grams: 60,
    per100: { kcal: 300, protein_g: 9, fat_g: 4, carb_g: 55, fiber_g: 3, soluble_fiber_g: 0 },
    scale_linked: true, dominance: 1, notes: '' } ] });
  HT.openPhotoDraft(reply);
  const dr = HT.photoDraft();
  // R159.1/F records the day as `startedDay` AT OPEN and pins it to `dayKey` at
  // the first roll check. That two-step is the mechanism, so both steps are read:
  // `dayKey` is deliberately empty here, and asserting it at open tested nothing.
  O.draft.started = dr ? String(dr.startedDay || 'MISSING') : 'no draft';
  O.draft.key = dr ? String(dr.dayKey || '') : 'no draft';
  // midnight passes WHILE the draft is open
  HT.setClock(function () { return Date.parse('2026-10-11T00:05:00-04:00'); });
  HT.dayRollCheck();
  O.draft.currentNow = String(HT.state().current);
  const dr2 = HT.photoDraft();
  O.draft.keyAfterRoll = dr2 ? String(dr2.dayKey || 'MISSING') : 'no draft';
  if (typeof HT.photoSave === 'function') {
    const sr = HT.photoSave();
    O.draft.saved = JSON.stringify(sr).slice(0, 160);
  }
  const d10 = (HT.state().days['2026-10-10'] || {}).items || [];
  const d11 = (HT.state().days['2026-10-11'] || {}).items || [];
  O.draft.landedOn10 = d10.some(function (x) { return /late toast/.test(String(x.name || '')); });
  O.draft.landedOn11 = d11.some(function (x) { return /late toast/.test(String(x.name || '')); });
  O.draft.timeKept = (d10.filter(function (x) { return /late toast/.test(String(x.name || '')); })[0] || {}).time || '';

  // ---- 12. the page does not scroll sideways, and taps clear 44px -------
  stage('ink');
  HT.setClock(function () { return Date.parse('2026-10-09T14:30:00-04:00'); });
  HT.boot(); HT.refresh();
  await sleep(300);
  const de = document.documentElement;
  O.ink.scrollW = de.scrollWidth;
  O.ink.clientW = de.clientWidth;
  // A NUMBER STARTS A HUNT; A NAME ENDS IT. Every element whose right edge is
  // past the viewport, widest first, skipping the ones an ancestor clips (those
  // are not overflow) -- the same distinction page-overflow-gate draws.
  O.ink.widest = [].slice.call(document.querySelectorAll('body *'))
    .map(function (el) {
      const r = el.getBoundingClientRect();
      return { el: el, over: Math.round(r.right - de.clientWidth) };
    })
    .filter(function (x) {
      if (x.over <= 0 || !x.el.offsetParent) return false;
      for (var p = x.el.parentElement; p; p = p.parentElement) {
        const ov = getComputedStyle(p).overflowX;
        if (ov === 'hidden' || ov === 'auto' || ov === 'scroll') return false;
      }
      return true;
    })
    .sort(function (a, b) { return b.over - a.over; })
    .slice(0, 4)
    .map(function (x) {
      // WITH ITS ANCESTRY AND ITS TEXT. The class alone says which rule to read;
      // the chain says which container failed to constrain it, and the text says
      // which content made it that wide -- three different fixes.
      var chain = [];
      for (var q = x.el.parentElement; q && chain.length < 3; q = q.parentElement) {
        chain.push(String(q.className || q.tagName).split(' ')[0]);
      }
      var pr = x.el.parentElement.getBoundingClientRect();
      return (x.el.tagName.toLowerCase() + '.' + String(x.el.className || '?')).slice(0, 34)
        + ' +' + x.over + 'px in [' + chain.join(' < ') + ']'
        + ' parent ' + Math.round(pr.left) + '..' + Math.round(pr.right)
        + ' text="' + String(x.el.textContent || '').trim().slice(0, 30) + '"';
    });
  const taps = all('#dayView .mghead, #dayView .mgnone [onclick], #dayView .qa10, #dayView .dcam');
  O.ink.tapCount = taps.length;
  O.ink.tooSmall = taps.filter(function (t) {
    const r = t.getBoundingClientRect();
    return r.height > 0 && r.height < 44;
  }).map(function (t) { return (t.className || '?') + '@' + Math.round(t.getBoundingClientRect().height); });

  } catch (e) { O.threw = String((e && e.message) || e) + ' @ ' + window.__stage;
                O.stack = String((e && e.stack) || '').slice(0, 500); }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  $kick = Eval $probe
  if ($kick -ne '1') { $fails += "the probe would not start: $kick" }
  $raw = $null
  for ($w = 0; $w -lt 140; $w++) {
    Start-Sleep -Milliseconds 500
    $raw = Eval 'window.__out'
    if ($raw) { break }
  }
  if (-not $raw) {
    $st = Eval 'String(window.__stage)'
    $fails += "the probe HUNG after 70s -- last stage reached: '$st'"
    $RES = [pscustomobject]@{}
  } else { $RES = $raw | ConvertFrom-Json }
  if ($RES.threw) { $fails += "the probe threw: $($RES.threw) | $($RES.stack)" }

  # NAMED, never single capitals -- PowerShell folds variable case, and a later
  # foreach would silently destroy a capture, leaving $null to pass numerically.
  $API = $RES.api; $GRP = $RES.groups; $NONE = $RES.none; $RESP = $RES.resp
  $BIO = $RES.bio; $FREQ = $RES.freq; $SHEET = $RES.sheet; $STEP = $RES.step
  $LOG = $RES.logged; $ROLL = $RES.roll; $DRAFT = $RES.draft; $INK = $RES.ink

  foreach ($fname in @('mealKindGroups', 'emptyMealKinds', 'foodFrequency',
                       'quickSheetOpen', 'quickPick', 'quickStep', 'quickAddLog',
                       'mealByTimeOfDay', 'dayGroupToggle', 'biometricSummary',
                       'dayRollCheck')) {
    Chk ($API.$fname -eq 'function') "HT.$fname is '$($API.$fname)', not a function"
  }
  Chk ($API.presetLogger -eq 'function') "HT.quickLog, the PRESET logger, is '$($API.presetLogger)' -- this gate's distinctness assertion is vacuous unless both loggers exist"
  Chk ($API.loggersDistinct -eq $true) "the new quick-add logger and the preset logger are THE SAME FUNCTION -- ruled: name it distinctly from quickLog, because a second definition of a top-level name silently wins and the one you read is not the one that runs (D159)"
  Chk ($API.topN -eq 10) "FREQ_TOP_N is '$($API.topN)', not the ruled 10"

  # --- 1. only the meals WITH items get headers (ruling D) ----------------
  Chk ($GRP.count -eq 2) "$($GRP.count) meal group(s) rendered for a day holding lunch and dinner only -- ruling D: meals with items get headers, the empties collapse into ONE line (headers: $($GRP.headers -join ' | '))"
  Chk (($GRP.kinds -join ',') -eq 'lunch,dinner') "the groups are '$($GRP.kinds -join ',')', not lunch then dinner -- the day reads in meal order"
  Chk ($GRP.lunchN -eq 3) "lunch reports $($GRP.lunchN) item(s), not the 3 it holds (two foods and a drink sharing its mealId)"
  Chk ($GRP.lunchKcal -eq 419) "lunch reports $($GRP.lunchKcal) cal, not 419 (235 + 182 + 2)"
  Chk ($GRP.lunchFirst -eq '12:00') "lunch reports first time '$($GRP.lunchFirst)', not 12:00"
  Chk ($GRP.lunchEvents -eq 1) "lunch holds $($GRP.lunchEvents) event(s), not 1"
  Chk ($GRP.dinnerEvents -eq 2) "dinner holds $($GRP.dinnerEvents) event(s), not the 2 sittings it was given"
  Chk ($GRP.badges -eq 0) "the Food/Dose/Biometric/Fast/Note badge row is still rendered ($($GRP.badges) .qab) -- the redesign replaces it, and it duplicated the headers"
  Chk ((@($GRP.badgeLabels)).Count -eq 0) "those badge WORDS still render on the day ($(@($GRP.badgeLabels) -join ', ')) -- asserted on the words as well as the class, because a class is renameable and the words are what the user reads"
  Chk ($GRP.qa10 -ge 1) "there is no top-10 quick-add button -- the ruled row REPLACES the badges, so their absence alone is not the slice"
  Chk ($GRP.cam -ge 1) "there is no camera button beside it"

  # --- 2. the empties: ONE muted line, naming them, tappable --------------
  Chk ($NONE.rows -eq 1) "$($NONE.rows) empty-meal row(s) -- ruled: ONE muted line for all of them, not a row each"
  Chk ($NONE.text -match '(?i)breakfast') "the empty line does not name breakfast ('$($NONE.text)')"
  Chk ($NONE.text -match '(?i)snack') "the empty line does not name snack ('$($NONE.text)')"
  Chk ($NONE.text -notmatch '(?i)lunch') "the empty line names LUNCH ('$($NONE.text)'), which has items"
  Chk ($NONE.taps -ge 2) "the empty line offers $($NONE.taps) tap target(s) -- ruled tappable TO THAT MEAL, so each named kind is its own target"
  Chk ((($NONE.tapTargets | Where-Object { [int]($_ -split 'x')[1] -lt 44 }) | Measure-Object).Count -eq 0) "an empty-meal tap target is under 44px tall ($($NONE.tapTargets -join ', '))"
  Chk ((($GRP.kinds) -notcontains 'breakfast') -and (($GRP.kinds) -notcontains 'snack')) "an empty meal got its own header anyway"

  # --- 3. the drink stays inside its meal, flagged -----------------------
  Chk ($GRP.lunchDrinks -eq 1) "lunch reports $($GRP.lunchDrinks) drink(s), not the 1 sharing its mealId"
  Chk ($GRP.drinkChip -match '1 drink') "no '1 drink' chip rendered ('$($GRP.drinkChip)')"

  # --- 4. expand in place; others stay collapsed; chronological ----------
  Chk ($GRP.openBodies -eq 1) "$($GRP.openBodies) group(s) expanded -- tapping one opens IN PLACE and the others stay collapsed"
  Chk (($GRP.openKinds -join ',') -eq 'lunch') "the expanded group is '$($GRP.openKinds -join ',')', not lunch"
  Chk ($GRP.hasMacros -ge 1) "the expanded group shows no macros"
  Chk (($GRP.itemTimes -join ',') -eq '12:00,12:05,12:10') "the expanded items are not in chronological order ('$($GRP.itemTimes -join ',')')"
  Chk (($GRP.itemFlags -join ' | ') -match 'DRINK:green tea') "the drink inside the meal is not flagged as one ('$($GRP.itemFlags -join ' | ')')"

  # --- 5. the response line: one event may carry it, two may not --------
  # BOTH DIRECTIONS. The negative alone would be satisfied by a build that never
  # renders a response line at all, which is why the fixture seeds a stream around
  # lunch's one event AND both dinner sittings.
  Chk ($RESP.onLunchHead -ge 1) "the LUNCH header carries no response line ($($RESP.onLunchHead)) -- it holds ONE event with a clean baseline and a rise that returns, which is exactly the case the ruling says to show in one plain line"
  Chk ($RESP.onDinnerHead -eq 0) "the DINNER header carries a single response line for TWO sittings -- one line summarising two different meals' glucose is an average nobody ate"
  Chk ($RESP.dinnerSaysHowMany -match '2') "the dinner header does not say it holds two events ('$($RESP.dinnerSaysHowMany)')"

  # --- 6. biometrics: its own group, one-line summary -------------------
  Chk ($BIO.group -ge 1) "biometrics has no group of its own"
  # `$BIO.fn` was ABSENT, not empty, while the function did not exist -- and
  # `$null -ne ''` is true, so this check PASSED on an unbuilt feature. The type is
  # asserted separately and the content must be real.
  Chk ($BIO.fnType -eq 'function') "HT.biometricSummary is '$($BIO.fnType)', not a function -- asserted on the TYPE, because an absent property passes every -ne comparison"
  Chk ($BIO.fn -and ([string]$BIO.fn).Length -gt 12) "biometricSummary() returned nothing usable for the fixture day ('$($BIO.fn)')"
  Chk ($BIO.summary -match '(?i)glucose|mmol|mg/dL') "the biometrics group's one-line summary does not mention glucose ('$($BIO.summary)') -- ruled: glucose avg, weight, woke"

  # --- 7. frequency counts by matchKey and NAMES what it counted -------
  Chk ($FREQ.coleN -eq 3) "the coleslaw count is $($FREQ.coleN), not 3 -- the fixture holds two spellings (2 + 1) and matchKey merges them, which is the only grouping that finds the repeat"
  Chk ($FREQ.coleNames -eq 2) "the coleslaw row names $($FREQ.coleNames) spelling(s) -- ruled A: a count NAMES WHAT IT COUNTED, and D137 already refused to leave a merge unnamed"
  Chk ($FREQ.coleGrams -eq 210) "the coleslaw portion is $($FREQ.coleGrams), not the MOST RECENT 210 g -- 8 of 10 real repeats differ, so an average would be a portion never eaten"
  Chk ($FREQ.craisinN -eq 2) "the no-grams food is not counted ($($FREQ.craisinN))"
  Chk ($null -eq $FREQ.craisinGrams) "the food with NO grams on either item reports a portion ('$($FREQ.craisinGrams)') -- it has none to report"

  # --- 8. the sheet ----------------------------------------------------
  Chk ($SHEET.rows -ge 3) "the quick-add sheet lists $($SHEET.rows) row(s) for a fixture with three repeating foods"
  Chk ($SHEET.namesShown -ge 1) "no row shows the spellings behind its count"
  Chk ($SHEET.coleText -match '3') "the coleslaw row does not show its count ('$($SHEET.coleText)')"
  Chk ($SHEET.anyAverage -eq $false) "the sheet says 'average' somewhere -- the numbers come from ONE chosen item, never an average across merged names"

  # --- 9. the stepper --------------------------------------------------
  Chk ($STEP.shown -ge 1) "tapping a row opened no stepper"
  Chk ($STEP.n -eq '1') "the stepper starts at '$($STEP.n)', not 1"
  Chk ($STEP.lastLabel -match '210') "the stepper does not say the portion it starts from ('$($STEP.lastLabel)') -- ruled B: the MOST RECENT portion, labelled as such"
  Chk ($STEP.lastLabel -match '(?i)last') "the portion label does not say it is the LAST one ('$($STEP.lastLabel)') -- an unlabelled number reads as a recommendation"
  Chk ($STEP.gramsField -ge 1) "there is no 'or grams' field"
  Chk ($STEP.logBtn -match '(?i)log') "the log button does not say Log ('$($STEP.logBtn)')"
  Chk ($STEP.logBtn -match '\d') "the log button does not state the calories it will log ('$($STEP.logBtn)')"
  Chk ($STEP.afterPlus -eq '2') "the + did not step the quantity (got '$($STEP.afterPlus)')"
  Chk ($STEP.logAfterPlus -ne $STEP.logBtn) "the log button's figure did not change when the quantity did ('$($STEP.logBtn)' -> '$($STEP.logAfterPlus)')"
  Chk ($STEP.mealLine -ne '') "the sheet does not say which meal it will log to"
  Chk ($STEP.changeLink -ge 1) "there is no 'change' link for the meal"

  # --- 10. logging lands now, in the meal for the time of day ----------
  Chk ($LOG.at0800 -eq 'breakfast') "08:00 maps to '$($LOG.at0800)', not breakfast"
  Chk ($LOG.at1230 -eq 'lunch') "12:30 maps to '$($LOG.at1230)', not lunch"
  Chk ($LOG.at1900 -eq 'dinner') "19:00 maps to '$($LOG.at1900)', not dinner"
  Chk ($LOG.at2300 -eq 'snack') "23:00 maps to '$($LOG.at2300)', not snack"
  Chk ($LOG.added -eq 1) "quickLog added $($LOG.added) item(s), not 1 ($($LOG.result))"
  Chk ($LOG.meal -eq 'lunch') "the logged item landed in '$($LOG.meal)' at 14:30 -- it goes to the meal for the time of day"
  Chk ($LOG.day -eq '2026-10-09') "the logged item landed on '$($LOG.day)', not the current day"
  # BOTH RULED BRANCHES, SEPARATELY. The `-or` this replaces would have passed on
  # either behaviour once a ref existed, which is no assertion at all.
  Chk ($LOG.lostNote -eq $true) "the coleslaw match had NO basis (`$ref.g absent) and was logged at a new portion, so it must DROP and SAY SO -- ruled; instead lostMatch=$($LOG.lostNote), hasRef=$($LOG.hasRef)"
  Chk ($LOG.hasRef -eq $false) "the match with no basis was KEPT at a new portion -- it cannot be re-expressed, and keeping it states a number for a portion it was never measured at"
  Chk ($LOG.salHasRef -eq $true) "the salmon match HAS a basis and must survive a portion change, re-expressed -- instead it was dropped ($($LOG.salResult))"
  Chk ($LOG.salRefG -eq 380) "the re-expressed match reports basis $($LOG.salRefG) g, not the new 380 -- `$g must become the NEW grams, which is what makes scaling twice impossible"

  # --- 11. R138: resume on a new calendar day ---------------------------
  Chk ($ROLL.moved -eq $true) "a resume on a new calendar day left the app on '$($ROLL.before)' instead of moving to 2026-10-10 ($($ROLL.result)) -- the only visibilitychange handler asked the SERVICE WORKER for an update and nothing re-checked the day, so the app showed AND LOGGED TO yesterday"
  Chk ($ROLL.stable -eq $true) "a second resume on the same day moved the current day again -- the check must be idempotent"

  # --- 12. ruling F: the draft keeps the day it was started on ----------
  Chk ($DRAFT.started -eq '2026-10-10') "the draft recorded started-day '$($DRAFT.started)', not the 2026-10-10 it was started on"
  Chk ($DRAFT.key -eq '') "the draft pinned `$dayKey at OPEN ('$($DRAFT.key)') -- it is pinned by the roll check, and a value here means the two-step that implements 'never retargeted' has changed shape"
  Chk ($DRAFT.currentNow -eq '2026-10-11') "the fixture did not actually cross midnight (current is '$($DRAFT.currentNow)'), so the assertion below proves nothing"
  Chk ($DRAFT.keyAfterRoll -eq '2026-10-10') "the open draft was RETARGETED to '$($DRAFT.keyAfterRoll)' when the date flipped -- ruled F: never retargeted"
  Chk ($DRAFT.landedOn10 -eq $true) "the saved draft did not land on the day it was started ($($DRAFT.saved))"
  Chk ($DRAFT.landedOn11 -eq $false) "the saved draft landed on the NEW day -- an entry the user was in the middle of writing was moved under them"
  Chk ($DRAFT.timeKept -ne '') "the item saved across midnight lost its time -- stampTime returns '' for a day that is not today, and the honest time is when the draft was started"

  # --- 13. layout ------------------------------------------------------
  Chk ($INK.clientW -gt 0) "the document reported no width, so the overflow assertion is vacuous"
  Chk ($INK.scrollW -le $INK.clientW) "the page scrolls sideways at 360px: scrollWidth $($INK.scrollW) against clientWidth $($INK.clientW) -- past the edge: $(@($INK.widest) -join '; ')"
  Chk ($INK.tapCount -ge 4) "only $($INK.tapCount) tap target(s) found, so the 44px assertion below is near-vacuous"
  Chk ((@($INK.tooSmall)).Count -eq 0) "tap target(s) under 44px: $($INK.tooSmall -join ', ')"

} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "LANDING GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "LANDING GATE: PASS -- only the meals with items get headers and the empties collapse into ONE muted line that names them and is tappable per meal; a drink stays inside its meal and is flagged; a group expands in place, chronologically, with the others collapsed; a two-sitting kind carries no single response line; biometrics has its own group and summary; the frequency count groups by matchKey, NAMES the spellings it counted, and takes its portion from the most recent item; the stepper starts at 1 with that portion labelled and the log button states its calories; logging lands in the meal for the time of day and either scales or says it lost the match; a resume on a new calendar day moves to today, idempotently; and a draft started before midnight lands on the day it was started, with its time"
Write-Host "GATE: PASS"
exit 0
