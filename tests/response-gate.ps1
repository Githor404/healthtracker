# H25 -- MEAL RESPONSE, TEST TAGGING, AND THE ONE-TAP EVENT MECHANISM.
#
# RULED (user, 2026-10-05 / 2026-10-07):
#   C         a window cut short is BOUNDED when the peak falls before the gap,
#             and DECLINED when the gap comes before any peak. Never present a
#             bounded window as clean.
#   BASELINE  the mean of the 20 minutes before, with n shown, refused below n=2;
#             and if another eating event falls inside those 20 minutes, SAY SO.
#   G         a one-tap "moved" event, sharing its mechanism with H26's "woke".
#   MEAL      an eating event is items merged by mealId.
#   ONE-THIRD the meals without a clean window are a figure on the surface.
#   ONE MECHANISM, THREE KINDS, ONE GATE: moved, woke and drink (the alcohol
#             stopgap) all go through the same path; H26 uses it rather than
#             building its own.
#
# EVERY NUMBER IN THE CLEAN CASE IS CHOSEN IN ADVANCE and asserted exactly, so the
# arithmetic is checked against an answer decided before the code ran rather than
# against whatever the code happens to produce.
#
# ONE CASE PER DAY. The gap cases need the readings to STOP, and a single day
# carrying six differently-shaped windows would make each case depend on the
# others' noise. Six days, six independent shapes.
#
# Fixture-synthetic forever (CLAUDE.md): no export is ever read, and the glucose is
# seeded through the REAL ingest path rather than written into the store.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8261
$Dbg = 9467
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-response-" + [System.Guid]::NewGuid().ToString('N'))
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
  $buf = New-Object byte[] 65536
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
    if (++$guard -gt 600) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  # REPORT THE EXCEPTION. Discarding exceptionDetails here meant a probe with a
  # syntax error returned an empty string, and the gate said only "the probe would
  # not start" -- true, unhelpful, and it cost a diagnosis.
  if ($r.result.exceptionDetails) { return 'EXCEPTION: ' + $r.result.exceptionDetails.text + ' | ' + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value
}
function EvalAsync([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + ($r.result.exceptionDetails.text) }
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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $probe = @'
window.__out = null;
window.__stage = 'start';
(async function () {
  const O = { cases: {}, quick: {}, tests: {}, surface: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  // The stage also goes in the TITLE, which the DevTools HTTP endpoint reports
  // from the BROWSER process -- readable even when the page's own thread is
  // blocked and Runtime.evaluate can no longer be serviced.
  const stage = (s) => { window.__stage = s; O.stage = s; try { document.title = 'STAGE:' + s; } catch (e) {} };
  try {
  HT.setClock(function () { return Date.parse('2026-09-26T21:00:00-04:00'); });
  localStorage.clear();
  HT.boot();
  await sleep(250);

  // ---- GLUCOSE, seeded through the REAL ingest path -----------------------
  // A ramp helper so each case's shape is stated as a list of (minute, value)
  // anchors and filled at the 5-minute cadence the real sensor uses.
  const G = [];
  function at(day, mins, v) {
    const hh = String(Math.floor(mins / 60)).padStart(2, '0');
    const mm = String(mins % 60).padStart(2, '0');
    G.push({ t: day + 'T' + hh + ':' + mm + ':00-04:00', v: v, unit: 'mmol/L' });
  }
  // linear fill between anchors, every 5 min, inclusive of both ends
  function ramp(day, m0, v0, m1, v1) {
    for (let m = m0; m <= m1; m += 5) {
      const f = (m1 === m0) ? 0 : (m - m0) / (m1 - m0);
      at(day, m, Math.round((v0 + (v1 - v0) * f) * 10) / 10);
    }
  }

  // CASE 1 -- CLEAN. meal 12:00. baseline 5.0 (n=4 over 11:40-11:55),
  // peak 8.0 at 12:45 (rise 3.0, 45 min), back to 5.0 at 14:00 (120 min).
  const D1 = '2026-09-20';
  ramp(D1, 11 * 60 + 40, 5.0, 12 * 60, 5.0);        // baseline window + the meal minute
  ramp(D1, 12 * 60 + 5, 5.3, 12 * 60 + 45, 8.0);    // rise to peak
  ramp(D1, 12 * 60 + 50, 7.7, 14 * 60, 5.0);        // return to baseline
  ramp(D1, 14 * 60 + 5, 5.0, 16 * 60, 5.0);         // rest of the 4 h window

  // CASE 2 -- PEAK THEN GAP -> BOUNDED. meal 07:00, peak 7.5 at 07:40,
  // readings STOP at 08:35 (95 min after the meal) without returning.
  const D2 = '2026-09-21';
  ramp(D2, 6 * 60 + 40, 5.0, 7 * 60, 5.0);
  ramp(D2, 7 * 60 + 5, 5.4, 7 * 60 + 40, 7.5);
  ramp(D2, 7 * 60 + 45, 7.3, 8 * 60 + 35, 6.2);     // still above baseline when it stops

  // CASE 3 -- GAP BEFORE ANY PEAK -> DECLINED. meal 18:00, readings stop 18:10.
  const D3 = '2026-09-22';
  ramp(D3, 17 * 60 + 40, 5.0, 18 * 60, 5.0);
  ramp(D3, 18 * 60 + 5, 5.1, 18 * 60 + 10, 5.2);

  // CASE 4 -- A FOLLOWING MEAL INSIDE THE WINDOW. meal 20:00, second 21:00.
  const D4 = '2026-09-23';
  ramp(D4, 19 * 60 + 40, 5.0, 20 * 60, 5.0);
  ramp(D4, 20 * 60 + 5, 5.4, 20 * 60 + 40, 7.0);
  ramp(D4, 20 * 60 + 45, 6.8, 23 * 60 + 55, 5.0);

  // CASE 5 -- BASELINE CONTAMINATED by an eating event inside the 20 min before.
  const D5 = '2026-09-24';
  ramp(D5, 14 * 60 + 40, 5.0, 15 * 60, 5.6);
  ramp(D5, 15 * 60 + 5, 6.0, 15 * 60 + 45, 7.8);
  ramp(D5, 15 * 60 + 50, 7.5, 18 * 60, 5.2);

  // CASE 6 -- BASELINE n < 2. meal 10:00, ONE reading in 09:40-10:00.
  const D6 = '2026-09-25';
  at(D6, 9 * 60 + 55, 5.0);
  ramp(D6, 10 * 60 + 5, 5.4, 10 * 60 + 45, 7.2);
  ramp(D6, 10 * 60 + 50, 7.0, 13 * 60, 5.1);

  stage('seed-glucose');
  const ing = HT.glucoseIngest(G, { source: 'fixture' });
  O.seeded = ing.stored;
  O.offered = G.length;
  O.seedSkipped = ing.skipped;

  // ---- MEALS ------------------------------------------------------------
  stage('seed-meals');
  const S = HT.state();
  const item = (o) => Object.assign({ meal: 'lunch', grams: 200, kcal: 400, protein_g: 10,
    fat_g: 10, carb_g: 60, fiber_g: 4, soluble_fiber_g: 1, confidence: 'eyeballed',
    source: 'ai-paste', notes: '' }, o);
  function day(dk, items) { S.days[dk] = { status: 'complete', water_l: 0, items: items }; }

  day(D1, [ item({ name: 'oat porridge', time: '12:00', mealId: 'm1' }),
            item({ name: 'blueberries',  time: '12:00', mealId: 'm1' }) ]);
  day(D2, [ item({ name: 'oat porridge', time: '07:00', mealId: 'm2' }) ]);
  day(D3, [ item({ name: 'late supper',  time: '18:00', mealId: 'm3' }) ]);
  day(D4, [ item({ name: 'first dinner', time: '20:00', mealId: 'm4' }),
            item({ name: 'second dinner', time: '21:00', mealId: 'm5' }) ]);
  day(D5, [ item({ name: 'a nibble',     time: '14:50', mealId: 'm6' }),
            item({ name: 'the meal',     time: '15:00', mealId: 'm7' }) ]);
  day(D6, [ item({ name: 'thin baseline', time: '10:00', mealId: 'm8' }) ]);
  S.current = D1;
  HT.Store.saveState(S);
  HT.refresh();
  await sleep(300);

  // ---- THE EVENT MERGE (ruled: a meal is items merged by mealId) ----------
  stage('merge-events');
  const ev1 = HT.mealEvents(D1);
  O.cases.d1Events = ev1.length;
  O.cases.d1FirstItems = ev1.length ? ev1[0].items.length : 0;
  const ev4 = HT.mealEvents(D4);
  O.cases.d4Events = ev4.length;

  // ---- CASE 1: every number chosen in advance ----------------------------
  stage('case1');
  const r1 = HT.mealResponse(D1, 'm1');
  O.cases.c1 = { phase: r1.phase, base: r1.baseline && r1.baseline.mean, baseN: r1.baseline && r1.baseline.n,
                 contaminated: !!(r1.baseline && r1.baseline.contaminated),
                 rise: r1.rise, tPeak: r1.tToPeak, tBase: r1.tToBaseline,
                 cov: r1.coverage && r1.coverage.n, gaps: r1.coverage && r1.coverage.gaps,
                 following: r1.following };

  // ---- CASE 2: peak then gap -> BOUNDED ---------------------------------
  stage('case2');
  const r2 = HT.mealResponse(D2, 'm2');
  O.cases.c2 = { phase: r2.phase, rise: r2.rise, tPeak: r2.tToPeak,
                 tBase: r2.tToBaseline, stopsAt: r2.stopsAt };

  // ---- CASE 3: gap before any peak -> DECLINED --------------------------
  stage('case3');
  const r3 = HT.mealResponse(D3, 'm3');
  O.cases.c3 = { phase: r3.phase, why: r3.why, rise: r3.rise };

  // ---- CASE 4: a following meal inside the window -----------------------
  stage('case4');
  const r4 = HT.mealResponse(D4, 'm4');
  O.cases.c4 = { phase: r4.phase, following: r4.following, followingMin: r4.followingMin };

  // ---- CASE 5: contaminated baseline ------------------------------------
  stage('case5');
  const r5 = HT.mealResponse(D5, 'm7');
  O.cases.c5 = { phase: r5.phase, contaminated: !!(r5.baseline && r5.baseline.contaminated),
                 baseN: r5.baseline && r5.baseline.n };

  // ---- CASE 6: baseline n < 2 -> refused --------------------------------
  stage('case6');
  const r6 = HT.mealResponse(D6, 'm8');
  O.cases.c6 = { phase: r6.phase, why: r6.why, baseN: r6.baseline && r6.baseline.n };

  // ---- THE ONE-THIRD, ON THE SURFACE ------------------------------------
  stage('coverage');
  const cov = HT.responseCoverage();
  O.surface.clean = cov.clean;
  O.surface.total = cov.total;

  // ---- ONE MECHANISM, THREE KINDS ---------------------------------------
  stage('quick-events');
  O.quick.declared = (HT.QUICK_EVENTS || []).map(q => q.id);
  // A TAP LOGS TO TODAY, not to the day under test -- quickEvent uses localDate()
  // because that is what a tap means. Reading D1 measured an empty timeline and
  // reported the mechanism broken when it was the fixture looking in the wrong day.
  const TODAY = HT.localDate();
  O.quick.today = TODAY;
  const before = (HT.state().timeline[TODAY] || []).length;
  const qa = HT.quickEvent('moved');
  const qb = HT.quickEvent('woke');
  const qc = HT.quickEvent('drink', 'wine');
  await sleep(200);
  const tl = HT.state().timeline[TODAY] || [];
  O.quick.added = tl.length - before;
  O.quick.ok = [qa, qb, qc].every(r => r && r.ok === true);
  const byType = {};
  tl.forEach(function (e) { byType[e.type] = e; });
  O.quick.types = Object.keys(byType).sort();
  O.quick.movedSource = byType.walk ? byType.walk.source : '';
  O.quick.wokeKind = byType.woke ? byType.woke.kind : '';
  O.quick.drinkVariant = byType.alcohol ? byType.alcohol.variant : '';
  O.quick.drinkValue = byType.alcohol ? byType.alcohol.value : null;
  // D8-shaped claim: a tap records THAT it happened, never an invented quantity
  O.quick.movedHasNoValue = byType.walk ? (byType.walk.value === undefined) : null;

  // the variant must survive the RESTORE boundary, not just the write
  stage('restore-roundtrip');
  const exp = HT.exportJSON();
  // RESTORE IS CONFIRM-GATED (D3), and this is a REAL page, not the harness. An
  // unanswered window.confirm blocks the renderer thread outright: Runtime.evaluate
  // stops being serviced, the CDP client waits forever, and the gate hangs with no
  // output at all. The harness has its own stub; a CDP gate has to bring one.
  const realConfirm = window.confirm;
  window.confirm = function () { return true; };
  window.__confirm = true;
  HT.restore(exp);
  window.confirm = realConfirm;
  await sleep(200);
  const tl2 = (HT.state().timeline[TODAY] || []).filter(e => e.type === 'alcohol')[0];
  O.quick.variantSurvivesRestore = tl2 ? tl2.variant : '';

  // ---- TEST TAGGING: stored, while the numbers stay derived -------------
  stage('test-tagging');
  HT.toggleMealTest(D1, 'm1');
  HT.toggleMealTest(D2, 'm2');
  await sleep(150);
  O.tests.taggedD1 = (HT.state().days[D1].items || []).every(i => i.test === true);
  const before1 = JSON.stringify(HT.mealResponse(D1, 'm1'));
  HT.boot();                                   // a reload
  await sleep(300);
  O.tests.survivesReload = (HT.state().days[D1].items || []).every(i => i.test === true);
  O.tests.recomputed = (JSON.stringify(HT.mealResponse(D1, 'm1')) === before1);
  // and the response numbers are NOT stored on the item
  O.tests.noStoredNumbers = (HT.state().days[D1].items || []).every(function (i) {
    return i.response === undefined && i.rise === undefined && i.baseline === undefined;
  });

  // ---- GROUPING: by ref id, never by typed name -------------------------
  stage('grouping');
  const St = HT.state();
  const mkref = (id, nm) => ({ ns: 'cnf', id: id, name: nm, at: D1, at_ms: 1, hash: 'h',
    how: 'picked', when: 'capture', attribution: 'x', v: { '208': 300 } });
  St.days[D1].items.forEach(i => { i.ref = mkref('111', 'Oats, rolled'); });
  St.days[D2].items.forEach(i => { i.ref = mkref('111', 'Oats, rolled'); });
  // a DIFFERENT food with a confusingly similar typed name, resolved elsewhere
  St.days[D3] = { status: 'complete', water_l: 0, items: [ item({ name: 'oat porridge',
    time: '18:00', mealId: 'm3', test: true, ref: mkref('222', 'Oats, instant, dry') }) ] };
  HT.Store.saveState(St);
  HT.refresh();
  await sleep(200);
  const groups = HT.testGroups();
  O.tests.groupCount = groups.length;
  O.tests.groups = groups.map(g => ({ key: g.key, keyKind: g.keyKind, n: g.n,
                                      names: g.members.map(m => m.name).sort() }));

  // ---- THE SURFACE: what the phone actually shows ---------------------
  stage('surface');
  const St2 = HT.state();
  St2.current = D1;
  HT.Store.saveState(St2);
  HT.refresh();
  await sleep(300);
  // open every row, because the response lives in the disclosure body (fork D)
  const heads = Array.prototype.slice.call(document.querySelectorAll('.mhead'));
  for (let i = 0; i < heads.length; i++) { heads[i].click(); await sleep(40); }
  await sleep(200);
  const resp = document.querySelector('.resp');
  O.surface.respRendered = !!resp;
  O.surface.respVisible = !!(resp && resp.offsetParent !== null);
  O.surface.respText = resp ? (resp.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 220) : '';
  // the baseline must carry its n wherever it is shown (ruled)
  O.surface.baselineHasN = /mean of \d+ readings/.test(O.surface.respText);
  O.surface.hasCoverage = /from \d+ readings over \d+ min/.test(O.surface.respText);
  // a statement that a figure is NOT clean may not be quieter than the figure
  const line = document.querySelector('.respline');
  O.surface.lineFont = line ? Math.round(parseFloat(getComputedStyle(line).fontSize)) : 0;
  // the test control
  const tbtn = document.querySelector('.mtest');
  O.surface.testControl = !!(tbtn && tbtn.offsetParent !== null);
  O.surface.testControlH = tbtn ? Math.round(tbtn.getBoundingClientRect().height) : 0;

  // a BOUNDED day must say what was not observed, in words
  stage('surface-bounded');
  HT.state().current = D2;
  HT.refresh();
  await sleep(300);
  const h2 = Array.prototype.slice.call(document.querySelectorAll('.mhead'));
  for (let i = 0; i < h2.length; i++) { h2[i].click(); await sleep(40); }
  await sleep(200);
  const r2el = document.querySelector('.resp');
  const r2t = r2el ? (r2el.textContent || '').replace(/\s+/g, ' ') : '';
  O.surface.boundedSaysNotObserved = /not observed/i.test(r2t);
  O.surface.boundedSaysWhereItStops = /data stops at \d+ min/i.test(r2t);
  const warn = document.querySelector('.respwarn');
  O.surface.warnFont = warn ? Math.round(parseFloat(getComputedStyle(warn).fontSize)) : 0;

  // the one-tap row is built FROM the declaration
  stage('surface-quick');
  // The one-tap row lives beside the signal chips, which sit inside a
  // disclosure. Measuring a collapsed element reports 0px and would have read
  // as a touch-floor failure -- the control is where it belongs; the fixture
  // simply had not opened the section a user taps to reach it.
  Array.prototype.slice.call(document.querySelectorAll('details')).forEach(function (d) { d.open = true; });
  await sleep(250);
  const qbtns = Array.prototype.slice.call(document.querySelectorAll('.qbtn'));
  O.surface.quickButtons = qbtns.length;
  O.surface.quickMinH = qbtns.length ? Math.min.apply(null, qbtns.map(b => Math.round(b.getBoundingClientRect().height))) : 0;
  O.surface.quickVisible = qbtns.length > 0 && qbtns.every(b => b.offsetParent !== null);
  // DERIVED OVER EVERY KIND. The first version took the FIRST variant-bearing kind
  // and added its variants -- correct while `drink` was the only one, and wrong the
  // moment H26's `sensor` arrived with two of its own. A hand-computed expectation
  // that happens to match one configuration is a pin on a coincidence.
  O.surface.expectedButtons = HT.QUICK_EVENTS.reduce(function (n, q) {
    return n + ((q.variants && q.variants.length) ? q.variants.length : 1);
  }, 0);

  // the one-third figure, on the surface
  stage('surface-figure');
  const fig = HT.responseCoverageHTML();
  O.surface.figureHTML = String(fig || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 160);
  O.surface.figureStatesBoth = /\d+ of \d+ meals/.test(O.surface.figureHTML);

  stage('done');
  } catch (e) {
    O.threw = String((e && e.message) || e) + ' @ ' + window.__stage;
  }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  # KICKED OFF, NOT AWAITED. `awaitPromise` blocks the CDP client until the page's
  # promise settles, and its receive loop waits on a message that never comes -- so
  # a hang inside the probe produced NO OUTPUT AT ALL for ten minutes. Polling turns
  # that into a named stage.
  # The page must be ALIVE before the probe means anything: a gate that evaluates
  # into a blank page reports "HT is not defined" and reads like a code failure.
  $sane = Eval "typeof HT"
  if ($sane -ne 'object') { Write-Host "ERROR: the page did not load (typeof HT = $sane)"; Cleanup; exit 2 }
  $kick = Eval $probe
  if ($kick -ne '1') { $fails += "the probe would not start (got '$kick')" }
  $r = $null
  for ($w = 0; $w -lt 120; $w++) {
    Start-Sleep -Milliseconds 500
    $r = Eval 'window.__out'
    if ($r) { break }
  }
  if (-not $r) {
    $st = Eval 'String(window.__stage)'
    $fails += "the probe HUNG after 60s -- last stage reached: '$st'"
    $R = [pscustomobject]@{}
  } else {
    $R = $r | ConvertFrom-Json
  }
  if ($R.threw) { $fails += "the probe threw partway through: $($R.threw) -- everything after that point is absent, not false" }

  $C = $R.cases
  $Q = $R.quick
  $T = $R.tests
  $SF = $R.surface

  # --- the fixture must be real before anything it feeds can mean anything ---
  # DERIVED, not guessed. The first version of this asserted "> 300" from my own
  # estimate of what the ramps would produce; they produce 214. Every row OFFERED
  # must be STORED, which is exact, and the absolute size is reported rather than
  # compared against a number I made up.
  Chk ($R.seeded -eq $R.offered) "$($R.seeded) of $($R.offered) offered readings were stored (skipped $($R.seedSkipped)) -- the fixture did not land whole"
  Chk ([int]$R.offered -gt 150) "the fixture offers only $($R.offered) readings -- too thin for six independent windows (D96)"

  # --- a meal is items merged by mealId (ruled) ------------------------------
  Chk ($C.d1Events -eq 1) "day 1 has two items sharing a mealId and produced $($C.d1Events) event(s) -- a multi-item lunch is ONE meal"
  Chk ($C.d1FirstItems -eq 2) "the merged event carries $($C.d1FirstItems) item(s), not the 2 that share its mealId"
  Chk ($C.d4Events -eq 2) "day 4 has two DIFFERENT mealIds and produced $($C.d4Events) event(s)"

  # --- CASE 1: numbers chosen in advance ------------------------------------
  Chk ($C.c1.phase -eq 'ok') "the clean case reported phase '$($C.c1.phase)', not 'ok'"
  Chk ($C.c1.base -eq 5.0) "baseline is $($C.c1.base), not the 5.0 the fixture was built with"
  Chk ($C.c1.baseN -eq 4) "baseline n is $($C.c1.baseN), not 4 -- the 20 min before the meal hold readings at 11:40, 11:45, 11:50 and 11:55"
  Chk ($C.c1.contaminated -eq $false) "the clean case reports a contaminated baseline, and nothing else was eaten in those 20 minutes"
  Chk ($C.c1.rise -eq 3.0) "peak rise is $($C.c1.rise), not the 3.0 the fixture was built with (5.0 -> 8.0)"
  Chk ($C.c1.tPeak -eq 45) "time to peak is $($C.c1.tPeak) min, not 45"
  Chk ($C.c1.tBase -eq 120) "time back to baseline is $($C.c1.tBase) min, not 120"
  Chk ([int]$C.c1.cov -gt 0) "coverage is not stated as a COUNT on the clean response (got '$($C.c1.cov)')"
  Chk ($C.c1.gaps -eq 0) "the clean window reports $($C.c1.gaps) gap(s), and it was built without one"
  Chk ([string]::IsNullOrEmpty($C.c1.following)) "the clean case reports a following meal ('$($C.c1.following)'), and nothing follows it inside 4 h"

  # --- CASE 2: peak BEFORE the gap -> BOUNDED (ruled C) ---------------------
  Chk ($C.c2.phase -eq 'bounded') "a window whose peak falls BEFORE the gap reported '$($C.c2.phase)' -- the ruling says bounded"
  Chk ($C.c2.rise -eq 2.5) "the bounded case lost its rise: $($C.c2.rise), not 2.5 (5.0 -> 7.5). A bound is honest BECAUSE there is something to bound"
  Chk ($C.c2.tPeak -eq 40) "time to peak is $($C.c2.tPeak) min, not 40"
  Chk ($null -eq $C.c2.tBase) "time to baseline is '$($C.c2.tBase)' on a window that never returned -- it must be ABSENT, never a number"
  Chk ($C.c2.stopsAt -eq 95) "the bound does not say where the data stops ($($C.c2.stopsAt)), and the ruling's own wording is 'data stops at 95 min'"

  # --- CASE 3: gap BEFORE any peak -> DECLINED (ruled C) -------------------
  Chk ($C.c3.phase -eq 'declined') "a window that stops before any peak reported '$($C.c3.phase)' -- the ruling declines it"
  Chk (-not [string]::IsNullOrEmpty($C.c3.why)) "the declined case gives no reason"
  Chk ($null -eq $C.c3.rise) "a declined window reported a rise of '$($C.c3.rise)' -- there was no peak to measure one from"

  # --- CASE 4: a following meal is declared --------------------------------
  Chk (-not [string]::IsNullOrEmpty($C.c4.following)) "a meal 60 min into the window was NOT declared"
  Chk ($C.c4.followingMin -eq 60) "the following meal is declared at $($C.c4.followingMin) min, not 60"
  Chk ($C.c4.phase -ne 'ok') "a window containing another meal reported phase 'ok' -- it must not read as clean"

  # --- CASE 5: a contaminated baseline says so (ruled) ---------------------
  Chk ($C.c5.contaminated -eq $true) "an eating event 10 min before the meal did NOT mark the baseline -- the ruling applies the window rule to the thing the response is measured against"

  # --- CASE 6: baseline below n=2 is refused -------------------------------
  Chk ($C.c6.phase -eq 'declined') "a baseline of n=$($C.c6.baseN) produced phase '$($C.c6.phase)' -- below n=2 it is refused"
  Chk ($C.c6.why -match 'baseline') "the refusal does not name the baseline as the reason ('$($C.c6.why)')"

  # --- THE ONE-THIRD IS A FIGURE, NOT A SILENTLY SMALLER SET --------------
  Chk ([int]$SF.total -gt 0) "responseCoverage() reports a total of $($SF.total) -- the figure the 'says so' half exists to report is missing"
  Chk ([int]$SF.clean -lt [int]$SF.total) "every meal in a fixture built with gaps, a follower and a thin baseline reported CLEAN ($($SF.clean) of $($SF.total)) -- this fixture cannot show the number it exists to report (D96)"

  # --- ONE MECHANISM, THREE KINDS ------------------------------------------
  # RE-PINNED 3 -> 4 ON PURPOSE (H26). The ruling was "one mechanism, three event
  # kinds"; H26's sensor arm then joined the SAME mechanism as a fourth rather than
  # getting one of its own, which is what building the mechanism once was for. The
  # census is ORDER-FREE and pinned by SET, so a fifth kind fails here and has to be
  # added deliberately.
  $declared = ($Q.declared | Sort-Object) -join ','
  Chk ($declared -eq 'drink,moved,sensor,woke') "QUICK_EVENTS declares '$declared' -- the pinned set is drink, moved, sensor, woke. A new kind fails here on purpose: add it, and say why"
  Chk ($Q.ok -eq $true) "not every one-tap event reported ok"
  Chk ($Q.added -eq 3) "three taps produced $($Q.added) timeline record(s)"
  Chk (($Q.types -join ',') -eq 'alcohol,walk,woke') "the three taps landed as types '$($Q.types -join ',')' -- moved is a walk, woke is its own type, drink is alcohol"
  Chk ($Q.movedSource -eq 'quick') "a tapped event records source '$($Q.movedSource)', not 'quick' -- the record cannot tell a tap from a typed entry, and the ruling names a successor that will replace the tap"
  Chk ($Q.wokeKind -eq 'event') "woke landed as kind '$($Q.wokeKind)', not 'event'"
  Chk ($Q.drinkValue -eq 1) "the drink tap recorded a value of '$($Q.drinkValue)', not 1 drink"
  Chk ($Q.drinkVariant -eq 'wine') "the drink's TYPE did not survive as a field (got '$($Q.drinkVariant)') -- notes is user-editable free text and parsing it would be an inference, not a transport"
  Chk ($Q.variantSurvivesRestore -eq 'wine') "the drink's type did not survive export -> restore (got '$($Q.variantSurvivesRestore)') -- an additive field must be listed in the normalizer to survive"
  Chk ($Q.movedHasNoValue -eq $true) "the 'moved' tap invented a duration -- one tap records THAT it happened; a quantity nobody supplied is the fabrication D8 forbids"

  # --- TEST TAGGING: stored, numbers derived (fork E) ----------------------
  Chk ($T.taggedD1 -eq $true) "tagging a meal as a test did not mark its items"
  Chk ($T.survivesReload -eq $true) "the test tag did NOT survive a reload -- a tag is a user DECLARATION and must be stored"
  Chk ($T.recomputed -eq $true) "the response numbers changed across a reload -- they are DERIVED and must recompute identically"
  Chk ($T.noStoredNumbers -eq $true) "response numbers were written onto the item -- 'derive, don't store' applies to the numbers, and only the tag is an input"

  # --- GROUPING by ref id, never by typed name (fork F) -------------------
  Chk ($T.groupCount -eq 2) "$($T.groupCount) test group(s) formed from two foods sharing a NAME but not a ref -- grouping by the typed name is the merge D137 found across a real difference"
  $byref = $T.groups | Where-Object { $_.key -eq '111' }
  Chk ($null -ne $byref) "no group is keyed by the shared corpus ref id 111"
  Chk ($byref.n -eq 2) "the two meals of the same corpus row grouped as n=$($byref.n), not 2"
  Chk ($byref.keyKind -eq 'ref') "the grouping key is not labelled as a ref ('$($byref.keyKind)') -- a wrong grouping must be VISIBLE, which means saying what it grouped on"
  # --- THE SURFACE: what the phone shows ----------------------------------
  Chk ($SF.respRendered -eq $true) "no response rendered in any row body -- the engine can be right and show nowhere, and the user attests on the DEVICE"
  Chk ($SF.respVisible -eq $true) "the response is in the DOM but not visible (offsetParent null) -- textContent would have reported it anyway"
  Chk ($SF.baselineHasN -eq $true) "the rendered baseline does not carry its n ('$($SF.respText)') -- ruled: a baseline is a statement about a window WITH its count"
  Chk ($SF.hasCoverage -eq $true) "the rendered response does not state its coverage as a count ('$($SF.respText)')"
  Chk ($SF.testControl -eq $true) "no test control on the meal row"
  Chk ([int]$SF.testControlH -ge 44) "the test control is $($SF.testControlH)px tall, below the 44px touch floor"
  Chk ($SF.boundedSaysNotObserved -eq $true) "a bounded window does not say the return was NOT OBSERVED, in words"
  Chk ($SF.boundedSaysWhereItStops -eq $true) "a bounded window does not say WHERE the data stops -- the ruling's own wording is 'data stops at 95 min'"
  Chk ([int]$SF.warnFont -ge [int]$SF.lineFont) "the NOT-CLEAN statement renders at $($SF.warnFont)px against the figure's $($SF.lineFont)px -- a caveat quieter than the number it qualifies is a caveat that will not be read"
  Chk ([int]$SF.quickButtons -eq [int]$SF.expectedButtons) "the one-tap row renders $($SF.quickButtons) control(s) against $($SF.expectedButtons) declared in QUICK_EVENTS -- it is built FROM the declaration so a fourth kind cannot be forgotten here"
  Chk ($SF.quickVisible -eq $true) "a one-tap control is not visible"
  Chk ([int]$SF.quickMinH -ge 44) "the smallest one-tap control is $($SF.quickMinH)px -- a tap that needs aiming is not one tap"
  Chk ($SF.figureStatesBoth -eq $true) "the one-third figure does not state BOTH numbers ('$($SF.figureHTML)') -- ruled: the meals without a clean window are the figure the 'says so' half exists to report"
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "RESPONSE GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "RESPONSE GATE: PASS -- six windows with numbers chosen in advance; a peak before a gap is BOUNDED and a gap before a peak is DECLINED; a following meal and a contaminated baseline each say so; the one-third is a figure; one mechanism carries moved, woke and drink, and the drink's type survives a restore; a test tag is stored while its numbers are derived; and tests group by corpus ref, never by typed name"
Write-Host "GATE: PASS"
exit 0
