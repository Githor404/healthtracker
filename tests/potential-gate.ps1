# H24 -- METABOLIC POTENTIAL: what an input DELIVERS, and how fast, derived from
# composition and capture and never from the model.
#
# RULED (user, 2026-10-04):
#   A   build only the buildable group; leave the empty axes DECLARED AND EMPTY
#       rather than rendered as zeros (D146: a day with no readings draws no row)
#   B   liquid vs solid is DERIVED FROM WATER (SR 255), CONTINUOUSLY, no new field
#   C   the rate is a MODIFIER with its inputs always shown. NEVER minutes -- the
#       app measures no gastric emptying, and a time-to-peak is fiction wearing
#       decimals
#   D   fructose admitted as a judged slot (built: slot 212, column 5)
#   E   derive_slots.py --check emits the full per-nutrient table (built)
#
# A RULING CONFLICT, NAMED RATHER THAN RESOLVED IN SILENCE.
#
# app.js carries a STANDING ruling (at refAlcoholG) against deriving a class from
# water: "the cut would be a boundary nobody ruled: milk is ~88% water, soup
# ~85-90%, so the line would decide whether soup is a drink." Ruling C above names
# a modifier "liquid", which needs exactly that cut. Ruling B says CONTINUOUSLY,
# which is what avoids it.
#
# MEASURED IN THE SHIPPED CNF, which settles it:
#   Apple juice, canned or bottled   (1495)  water 88.24 g/100g
#   Soup, cream, asparagus, condensed (923)  water 84.05 g/100g
#
# FOUR POINTS APART. Any cut either lumps them together or declares canned soup a
# beverage, and nobody ruled which. So the engine reports the PERCENTAGE and names
# no class, and this gate asserts the absence of the class words. If the user wants
# the word "liquid" back, that is a ruling to make with these two numbers in view.
#
# THE OTHER MEASURED FIXTURE ROWS:
#   Sweets, honey, strained or extracted (4294)  fructose 40.94 g/100g
#   Butter, regular                       (118)  fructose ABSENT (not zero)
#
# Honey and butter are the fructose pair: one row HAS the new slot, the other
# genuinely lacks it, and absence must read as absence. Fructose clears the bar in
# NEITHER source (22.4% SR / 46.3% CNF), so most foods will never carry it -- which
# is why every figure here states how much of the day it could see.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8283
$Dbg = 9489
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-potential-" + [System.Guid]::NewGuid().ToString('N'))
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
  # The fixture rows were measured in CNF, so the namespace is DRIVEN, never left
  # to the host's locale.
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
  const O = { api: {}, load: {}, zero: {}, fruct: {}, rate: {}, water: {}, words: {},
              cover: {}, ceil: {}, ink: {}, fold: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const stage = (x) => { window.__stage = x; O.stage = x; };
  const txt = (el) => String((el && el.textContent) || '');
  const all = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel));
  const vis = (el) => !!(el && el.offsetParent !== null);
  try {
  stage('boot');
  HT.setClock(function () { return Date.parse('2026-10-08T21:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);
  O.ns = HT.corpusNamespace();
  O.cols = HT.corpusState().cols;

  // ---- the API exists at all (a missing symbol must not abort the probe) ----
  stage('api');
  ['potentialFor', 'potentialHTML', 'potentialCeiling', 'potentialCeilingHTML',
   'refValueAt', 'availCarbG', 'itemWaterPct', 'eventModifiers', 'POTENTIAL_AXES']
    .forEach(function (k) { O.api[k] = (typeof HT[k]); });

  // ---- THE FIXTURE DAY -----------------------------------------------------
  // Four eating events, each carrying exactly one case this gate needs.
  stage('seed');
  const D = '2026-10-08';
  const S = HT.state();
  const item = (o) => Object.assign({ meal: 'lunch', grams: 100, kcal: 300, protein_g: 0,
    fat_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed',
    source: 'ai-paste', notes: '' }, o);

  S.days[D] = { status: 'in_progress', water_l: 0, items: [
    // EVENT m1 -- carbohydrate WITH fibre, fat and protein in the same event.
    // Glucose load must be 60 - 4 = 56, and all three modifiers must name
    // themselves WITH their grams.
    item({ name: 'oat porridge', time: '12:00', mealId: 'm1',
           carb_g: 60, fiber_g: 4, protein_g: 0, fat_g: 0, grams: 250 }),
    item({ name: 'butter',   time: '12:00', mealId: 'm1', kcal: 100, fat_g: 12, grams: 15 }),
    item({ name: 'skyr',     time: '12:00', mealId: 'm1', kcal: 90, protein_g: 18, grams: 150 }),
    // EVENT m2 -- SOLO, carbohydrate only. The three modifiers must be ABSENT,
    // never rendered as "no fat" -- an absent input says nothing, it does not say
    // zero.
    item({ name: 'white rice', time: '18:00', mealId: 'm2',
           carb_g: 45, fiber_g: 0.5, grams: 180 }),
    // EVENT m3 -- UNRESOLVED. No composition at all. Must contribute no row and
    // no zero (D146 / the absence-is-not-zero rule).
    item({ name: 'something at a restaurant', time: '19:00', mealId: 'm3',
           unresolved: true }),
    // EVENT m4 -- the four RESOLVED rows, measured above.
    item({ name: 'honey',       time: '20:00', mealId: 'm4', carb_g: 41, grams: 100 }),
    item({ name: 'butter again', time: '20:00', mealId: 'm4', fat_g: 81, grams: 100 }),
    item({ name: 'apple juice', time: '20:10', mealId: 'm5', carb_g: 11, grams: 100 }),
    item({ name: 'cream soup',  time: '20:20', mealId: 'm6', carb_g: 8, grams: 100 }),
    // EVENT m7 -- FIBRE EXCEEDS CARBOHYDRATE, which is legal on a label and real
    // on some. Event-level subtraction gives -4 g; per-item clamping gives 0. The
    // assertion on this row is the only thing that can tell whether availCarbG is
    // actually CALLED, as opposed to merely existing.
    item({ name: 'psyllium husk', time: '21:00', mealId: 'm7',
           carb_g: 2, fiber_g: 6, grams: 10 })
  ] };
  S.current = D;
  HT.Store.saveState(S);
  await sleep(200);

  // Resolve the four through the REAL path, against the REAL corpus, by the ids
  // measured from the shipped asset.
  stage('resolve');
  const picks = [[5, '4294', 'Sweets, honey, strained or extracted'],
                 [6, '118',  'Butter, regular'],
                 [7, '1495', 'Apple juice, canned or bottled, without added ascorbic acid'],
                 [8, '923',  'Soup, cream, asparagus, canned, condensed']];
  O.resolved = [];
  for (let i = 0; i < picks.length; i++) {
    const r = await HT.resolveItem(D, picks[i][0], picks[i][1], picks[i][2], null, 'picked');
    O.resolved.push(!!(r && r.ok));
  }
  HT.refresh();
  await sleep(400);
  const st = HT.state().days[D].items;
  O.refsWritten = st.filter(function (i) { return i.ref && i.ref.v; }).length;

  // ---- the generic slot accessor the engine needs --------------------------
  stage('refValueAt');
  if (typeof HT.refValueAt === 'function') {
    O.api.honeyFructose = HT.refValueAt(st[5].ref, 212);
    O.api.butterFructose = HT.refValueAt(st[6].ref, 212);
    O.api.honeyWater = HT.refValueAt(st[5].ref, 255);
  }

  // ---- THE ENGINE, read as data before it is read as pixels ----------------
  stage('engine');
  if (typeof HT.potentialFor === 'function') {
    const P = HT.potentialFor(D);
    O.engine = JSON.stringify(P).slice(0, 2400);
    const evs = (P && P.events) || [];
    O.load.n = evs.length;
    const byId = {};
    evs.forEach(function (e) { byId[e.mealId] = e; });
    O.load.m1carb = byId.m1 ? byId.m1.glucoseLoadG : null;
    O.load.m1carbRaw = byId.m1 ? byId.m1.carbG : null;
    O.load.m1fibre = byId.m1 ? byId.m1.fibreG : null;
    O.load.m2carb = byId.m2 ? byId.m2.glucoseLoadG : null;
    O.load.m7carb = byId.m7 ? byId.m7.glucoseLoadG : null;
    O.load.m7raw = byId.m7 ? byId.m7.carbG : null;
    O.load.m7fibre = byId.m7 ? byId.m7.fibreG : null;
    O.load.m1plain = byId.m1 ? byId.m1.loadIsPlainSubtraction : null;
    O.load.m7plain = byId.m7 ? byId.m7.loadIsPlainSubtraction : null;
    O.load.m1protein = byId.m1 ? byId.m1.proteinG : null;
    O.zero.m3present = !!byId.m3;
    O.zero.m3carb = byId.m3 ? byId.m3.glucoseLoadG : 'no-event';
    O.rate.m1 = byId.m1 ? (byId.m1.modifiers || []).map(function (x) { return x.name; }) : [];
    O.rate.m1full = byId.m1 ? JSON.stringify(byId.m1.modifiers || []) : '';
    O.rate.m2 = byId.m2 ? (byId.m2.modifiers || []).map(function (x) { return x.name; }) : [];
    O.fruct.m4 = byId.m4 ? byId.m4.fructoseG : null;
    O.fruct.m2 = byId.m2 ? byId.m2.fructoseG : null;
    O.fruct.cover = P ? JSON.stringify(P.fructoseCoverage || null) : '';
    O.water.juice = byId.m5 ? byId.m5.waterPct : null;
    O.water.soup = byId.m6 ? byId.m6.waterPct : null;
    O.cover.resolved = P ? P.resolvedN : null;
    O.cover.items = P ? P.itemsN : null;
  }
  if (typeof HT.potentialCeiling === 'function') {
    O.ceil.raw = JSON.stringify(HT.potentialCeiling());
  }
  if (typeof HT.potentialCeilingHTML === 'function') {
    const ch = document.createElement('div');
    ch.innerHTML = HT.potentialCeilingHTML();
    O.ceil.html = txt(ch).slice(0, 420);
  }

  // ---- THE SURFACE ---------------------------------------------------------
  stage('surface');
  const host = document.getElementById('potentialPanel');
  O.fold.mounted = !!host;
  const det = host ? host.closest('details') : null;
  O.fold.inDetails = !!det;
  O.fold.closedByDefault = det ? (det.open === false) : null;
  if (det) { det.open = true; if (typeof HT.potentialToggle === 'function') HT.potentialToggle(true); }
  HT.refresh();
  await sleep(350);
  const host2 = document.getElementById('potentialPanel');
  O.fold.visibleWhenOpen = vis(host2);
  const T = txt(host2);
  O.panelText = T.slice(0, 1800);
  O.panelLen = T.length;
  O.rows = all('#potentialPanel .potrow').length;

  // the vocabulary rules, read off the RENDERED text
  O.words.banned = (T.match(/activat|boost|trigger|upregulat|fuels|drives/gi) || []).join(',');
  O.words.saysDelivers = /deliver/i.test(T);
  // RULED C: never a time -- but the ban has to name what it actually forbids, and
  // the first draft of this line did not. What is forbidden is an INFERRED time:
  // minutes to a peak, a time-to-baseline, anything the app would have to model
  // gastric emptying to know. A fast length READ OFF THE LOG is a different thing
  // entirely: it is a measured gap between two capture times, and refusing to
  // state it would be the honesty rule eating a fact it actually has. So hours are
  // allowed and minutes are not, because nothing here produces a figure in minutes
  // that was not modelled.
  O.words.minutes = (T.match(/\d+\s*(min\b|minutes?\b)|time to peak|peaks? at|time to baseline/gi) || []).join(',');
  // the water class words the standing ruling forbids, as a CLASS for a food
  O.words.classWords = (T.match(/\b(liquid|solid|beverage)\b/gi) || []).join(',');
  O.words.percentShown = /%/.test(T);
  // the coverage wording must be the app's existing one, not a third phrasing
  O.words.coverageWording = /from \d+ of \d+ items/.test(T);
  O.words.zeroFructose = /fructose[^.]{0,24}\b0(\.0+)?\s*g/i.test(T);
  O.words.absentSaid = /absent|not in|no value/i.test(T);
  // The fructose figure must name its ORIGIN beside itself.
  const fr = all('#potentialPanel .potfruct');
  O.words.fructRows = fr.length;
  O.words.fructAllSourced = fr.length > 0
    && fr.every(function (el) { return /food database/i.test(txt(el)); });
  // And the clamped row must not print a decomposition.
  O.words.clamped = /2 carb less 6 fibre/.test(T);

  // ---- the ink -------------------------------------------------------------
  // CORRECTED BEFORE THE BUILD. The first draft measured each `.potrow` nowrap,
  // which asserts that a whole row fits on ONE line -- and a row carrying a load,
  // three modifiers and a water fraction is MEANT to wrap. That assertion would
  // have been false about a correct panel, so it would have been answered by
  // cramming the row rather than by fixing anything.
  //
  // CORRECTED A SECOND TIME, and the second error is the same as the first.
  // Draft two measured `.potname`, `.potfig` and `.potmod` nowrap and reported
  // "available carb 44.5 g (45 carb less 0.5 fibre)" at 302px against 298px. But
  // that figure is ALLOWED to break before its parenthetical, and a name is
  // allowed to break at a space. Neither is atomic.
  //
  // What genuinely cannot break: a BORDERED CHIP (a border split across two lines
  // reads as two chips) and a single WORD. Those are measured. Deciding what is
  // atomic by what is convenient to measure, rather than by what cannot break, is
  // the error -- made twice in this one file.
  //
  // D140's trap applies to both measurements: scrollWidth on a wrapping element
  // equals clientWidth, so the probe is absolutely positioned to report the width
  // of its own text.
  stage('ink');
  O.ink.avail = host2 ? Math.round(host2.getBoundingClientRect().width) : 0;
  O.ink.scrollW = host2 ? host2.scrollWidth : 0;
  O.ink.clientW = host2 ? host2.clientWidth : 0;
  const measure = function (el, text) {
    const probe = document.createElement('span');
    probe.style.cssText = 'position:absolute;display:inline-block;white-space:nowrap;visibility:hidden;left:-9999px';
    if (el) probe.className = el.className;
    probe.textContent = text;
    document.body.appendChild(probe);
    const w = probe.getBoundingClientRect().width;
    probe.remove();
    return w;
  };
  const chips = all('#potentialPanel .potmod');
  O.ink.chips = chips.length;
  let widest = 0, widestText = '';
  chips.forEach(function (c) {
    const w = measure(c, txt(c));
    if (w > widest) { widest = w; widestText = txt(c).slice(0, 70); }
  });
  O.ink.widest = Math.round(widest);
  O.ink.widestText = widestText;
  // The longest unbreakable TOKEN in the panel, whatever element it sits in. A
  // word wider than the panel overflows no matter how the boxes wrap.
  const words = T.split(/\s+/).filter(function (x) { return x.length > 2; });
  O.ink.words = words.length;
  let wWidest = 0, wText = '';
  words.forEach(function (x) {
    const w = measure(null, x);
    if (w > wWidest) { wWidest = w; wText = x; }
  });
  O.ink.wordWidest = Math.round(wWidest);
  O.ink.wordText = wText;

  } catch (e) { O.threw = String((e && e.message) || e) + ' @ ' + window.__stage; O.stack = String((e && e.stack) || '').slice(0, 600); }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  $kick = Eval $probe
  if ($kick -ne '1') { $fails += "the probe would not start: $kick" }
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
  } else { $R = $r | ConvertFrom-Json }
  if ($R.threw) { $fails += "the probe threw: $($R.threw)" }

  # NAMED, NOT SHORTENED. The first draft used $K for the ink and then
  # `foreach ($k in ...)` forty lines below -- and PowerShell folds variable case,
  # so those were ONE variable. The loop left $K holding the string
  # 'eventModifiers', every ink assertion read a property off a string and got
  # $null, two failed with empty values and three passed VACUOUSLY, because
  # `$null -le $null` is true. The measurement was right the whole time; the
  # instrument had been overwritten. Single capitals are banned here for that
  # reason, and tests/check-psvars.sh now fails the whole suite on a collision.
  $API = $R.api; $LOAD = $R.load; $ZERO = $R.zero; $FRU = $R.fruct; $MOD = $R.rate
  $WAT = $R.water; $WORD = $R.words; $COV = $R.cover; $CEIL = $R.ceil
  $INK = $R.ink; $FOLD = $R.fold

  # --- the fixture itself must be real, or every assertion below is vacuous ---
  Chk ($R.ns -eq 'cnf') "the Canadian namespace was not driven (ns=$($R.ns))"
  Chk ($R.cols -eq 47) "the installed corpus has $($R.cols) columns, not the 47 that include fructose -- the slot shipped but the device did not take it"
  Chk ($R.refsWritten -eq 4) "$($R.refsWritten) of 4 fixture items resolved against the real corpus -- without all four, the fructose and water cases are not exercised"

  # --- the API exists -------------------------------------------------------
  foreach ($fname in @('potentialFor', 'potentialHTML', 'potentialCeiling',
                       'potentialCeilingHTML', 'refValueAt',
                       'availCarbG', 'itemWaterPct', 'eventModifiers')) {
    Chk ($API.$fname -eq 'function') "HT.$fname is '$($API.$fname)', not a function"
  }
  Chk ($API.POTENTIAL_AXES -eq 'object') "HT.POTENTIAL_AXES is '$($API.POTENTIAL_AXES)' -- ruled A: the empty axes are DECLARED, which needs a declaration to point at"

  # --- the generic slot accessor, against the measured rows -----------------
  Chk ([math]::Abs([double]$API.honeyFructose - 40.94) -lt 0.1) "refValueAt(honey, 212) is $($API.honeyFructose), not the 40.94 g the shipped corpus holds at 100 g"
  Chk ($null -eq $API.butterFructose) "refValueAt(butter, 212) is $($API.butterFructose) -- butter has NO fructose value and absence must read as null, never 0"
  Chk ([math]::Abs([double]$API.honeyWater - 17.10) -lt 0.1) "refValueAt(honey, 255) is $($API.honeyWater), not 17.10 -- the water slot is the basis of the whole liquidity reading"

  # --- GLUCOSE LOAD is carbohydrate MINUS fibre, with both inputs kept -------
  Chk ($LOAD.n -ge 4) "the engine found $($LOAD.n) eating event(s) in a day with six"
  Chk ([math]::Abs([double]$LOAD.m1carb - 56) -lt 0.01) "the glucose load for a 60 g carb / 4 g fibre event is $($LOAD.m1carb), not 56 -- ruled: available carbohydrate, which is carbohydrate minus fibre"
  Chk ([double]$LOAD.m1carb -ne 60) "the glucose load equals the raw carbohydrate (60), so the fibre is not being subtracted at all"
  Chk ([math]::Abs([double]$LOAD.m1carbRaw - 60) -lt 0.01) "the event does not keep its raw carbohydrate ($($LOAD.m1carbRaw)) -- ruled C: a modifier always shows its inputs, and a figure you cannot decompose is not one"
  Chk ([math]::Abs([double]$LOAD.m1fibre - 4) -lt 0.01) "the event does not keep its fibre ($($LOAD.m1fibre))"
  Chk ([math]::Abs([double]$LOAD.m1protein - 18) -lt 0.01) "the protein load is $($LOAD.m1protein), not the 18 g the event carries"

  # --- THE CLAMP IS PER ITEM, which is what proves availCarbG is CALLED ------
  Chk ([math]::Abs([double]$LOAD.m7carb - 0) -lt 0.01) "an item with 2 g carbohydrate and 6 g fibre yields a load of $($LOAD.m7carb), not 0 -- event-level subtraction gives -4 and per-item clamping gives 0, so this is the assertion that distinguishes availCarbG being CALLED from merely existing"
  Chk ([double]$LOAD.m7carb -ge 0) "the glucose load went NEGATIVE ($($LOAD.m7carb)) -- a label may state more fibre than carbohydrate and a negative load is not a thing"
  Chk ([math]::Abs([double]$LOAD.m7raw - 2) -lt 0.01) "the clamped event does not keep its raw carbohydrate ($($LOAD.m7raw))"
  Chk ($LOAD.m1plain -eq $true) "the unclamped event reports its load as NOT a plain subtraction, so the panel will withhold a decomposition that is in fact true"
  Chk ($LOAD.m7plain -eq $false) "the CLAMPED event claims its load is a plain subtraction -- the panel would then print '(2 carb less 6 fibre)' beside a figure of 0 and invite the reader to check arithmetic that did not happen"

  # --- AN ABSENT INPUT IS NOT A ZERO (D146) ---------------------------------
  Chk ($ZERO.m3present -eq $false -or $null -eq $ZERO.m3carb) "the UNRESOLVED event renders a glucose load of $($ZERO.m3carb) -- an item with no composition must contribute no figure, not a zero"
  Chk ($WORD.zeroFructose -eq $false) "the panel prints a fructose figure of 0 g ('$($R.panelText)') -- absence is never zero, and for a slot at 22-46% coverage that is most foods"

  # --- FRUCTOSE: reference-only, and its coverage stated ---------------------
  Chk ([math]::Abs([double]$FRU.m4 - 40.94) -lt 0.2) "the honey event delivers $($FRU.m4) g fructose, not the 40.94 the corpus holds"
  Chk ($null -eq $FRU.m2) "the unresolved-to-corpus rice event reports a fructose figure ($($FRU.m2)) -- fructose exists only as a reference value; no label supplies it"
  Chk ($FRU.cover -ne '' -and $FRU.cover -ne 'null') "the engine states no coverage for fructose -- at 22.4% SR / 46.3% CNF most foods carry none, so a bare total would imply a completeness it does not have"
  Chk ($WORD.coverageWording -eq $true) "the panel does not use the app's existing coverage wording 'from N of M items' -- a third phrasing for the same idea"
  Chk ($WORD.fructRows -ge 2) "only $($WORD.fructRows) fructose figure(s) rendered, so the provenance assertion below is near-vacuous -- the fixture matches two rows that carry the slot"
  Chk ($WORD.fructAllSourced -eq $true) "a fructose figure does not name 'food database' beside itself -- it is the one axis here NO label can supply, so a bare number sits next to label-derived figures looking like the same kind of claim"
  Chk ($WORD.clamped -eq $false) "the panel prints '(2 carb less 6 fibre)' beside a clamped figure of 0 -- a decomposition that describes a subtraction which did not happen"

  # --- THE RATE IS NAMED, NEVER TIMED ---------------------------------------
  Chk ($WORD.minutes -eq '') "the panel states a TIME ('$($WORD.minutes)') -- ruled: never minutes. The app measures no gastric emptying"
  Chk (($MOD.m1 -join ',') -match 'fat') "the multi-item event does not name 'eaten with fat' (got: $($MOD.m1 -join ', '))"
  Chk (($MOD.m1 -join ',') -match 'fibre|fiber') "the multi-item event does not name the fibre modifier (got: $($MOD.m1 -join ', '))"
  Chk (($MOD.m1 -join ',') -match 'protein') "the multi-item event does not name the protein modifier (got: $($MOD.m1 -join ', '))"
  Chk ($MOD.m1full -match '\d') "a modifier carries no input figure ('$($MOD.m1full)') -- ruled C: the modifier with its inputs ALWAYS shown"
  Chk ((($MOD.m2 -join ',') -notmatch 'fat') -and (($MOD.m2 -join ',') -notmatch 'protein')) "the solo carbohydrate event names a fat or protein modifier anyway (got: $($MOD.m2 -join ', ')) -- an absent input says nothing; it does not say zero"

  # --- WATER IS CONTINUOUS, AND NAMES NO CLASS ------------------------------
  Chk ([math]::Abs([double]$WAT.juice - 88.24) -lt 0.5) "apple juice reports $($WAT.juice)% water, not the 88.24 the corpus holds"
  Chk ([math]::Abs([double]$WAT.soup - 84.05) -lt 0.5) "cream soup reports $($WAT.soup)% water, not 84.05"
  Chk ([math]::Abs([double]$WAT.juice - [double]$WAT.soup) -lt 5) "the two fixture rows are $([math]::Round([math]::Abs([double]$WAT.juice - [double]$WAT.soup),1)) points apart -- this gate's whole argument is that they are too close for any cut, so if they have separated the argument needs remaking"
  Chk ($WORD.classWords -eq '') "the panel calls a food '$($WORD.classWords)' -- a CLASS derived from water is the boundary the standing ruling at refAlcoholG refuses, because it would decide whether canned soup is a drink. The percentage is the answer; the class is not"
  Chk ($WORD.percentShown -eq $true) "the panel shows no percentage, so the water reading is not actually surfaced"

  # --- THE VOCABULARY (D157: never plays the clinician) ---------------------
  Chk ($WORD.banned -eq '') "the panel uses a word the advocate purpose forbids: '$($WORD.banned)'. The app states what an input DELIVERED, never that it activated, boosted, triggered or drove anything"
  Chk ($WORD.saysDelivers -eq $true) "the panel never says what an input DELIVERS -- the replacement vocabulary has to actually appear, or this gate is only asserting absences"

  # --- THE DAY'S FIRST HONEST FACT: how much of it is resolved --------------
  Chk ($COV.resolved -eq 4) "the engine reports $($COV.resolved) resolved items, not 4"
  Chk ($COV.items -ge 6) "the engine counts $($COV.items) items in a nine-item day"

  # --- THE TEST-POINT CEILING IS A FUNCTION, NOT A CLAIM --------------------
  Chk ($CEIL.raw -match 'n') "potentialCeiling() returned '$($CEIL.raw)' -- the ruled report (clean-window meals that also carry a matched row, with n) must be re-runnable, not a number I typed once"
  # And it must be READABLE BY THE USER, not only callable by a gate: a figure
  # that exists solely in a record is stale the moment another item is matched,
  # and this one is meant to guide an ongoing activity.
  Chk ($CEIL.html -match 'can test a prediction') "the ceiling renders no surface ('$($CEIL.html)') -- the ruled report has to be readable on the device, not only from a console"
  # And the heading may not reintroduce the word anti-engagement-gate banned. That
  # gate caught my first wording ('Test points for prediction'); this keeps the fix
  # from being undone by someone restoring the ruling's internal phrase verbatim.
  Chk ($CEIL.html -notmatch '(?i)\bpoints\b') "the ceiling heading says 'points' -- banned on any surface as gamification, and the statistical sense is not the one a reader gets"
  Chk ($CEIL.html -match 'clean glucose window') "the ceiling line does not say what makes a meal count"
  Chk (($CEIL.html -match 'Clean windows') -and ($CEIL.html -match 'matched row')) "the ceiling states only the intersection, not the TWO factors -- which of them to work on is the actual question, and H24 measured that matching is the scarce one"


  # --- THE PANEL COSTS NO FOLD BUDGET --------------------------------------
  Chk ($FOLD.mounted -eq $true) "#potentialPanel never mounted"
  Chk ($FOLD.inDetails -eq $true) "the panel is not inside a <details> -- H25 cost the ring its fold budget by mounting a surface above the fold"
  Chk ($FOLD.closedByDefault -eq $true) "the panel is OPEN by default, so it costs the ring its fold budget on every load"
  Chk ($FOLD.visibleWhenOpen -eq $true) "the panel is not visible even when opened"
  Chk ($R.rows -ge 4) "the opened panel renders $($R.rows) row(s) for a six-event day"

  # --- the ink, at 360px ----------------------------------------------------
  Chk ($INK.avail -gt 0) "the panel reported no width, so every ink assertion below is vacuous"
  Chk ($INK.chips -ge 4) "only $($INK.chips) modifier chip(s) were found to measure -- the fixture is expected to produce at least four, so a pass below would prove little"
  Chk ($INK.words -ge 40) "only $($INK.words) word(s) were harvested from the panel, so the longest-token measurement is near-vacuous"
  Chk ($INK.scrollW -le $INK.clientW) "the panel SCROLLS SIDEWAYS: scrollWidth $($INK.scrollW) against clientWidth $($INK.clientW) at 360px. This is the unconditional one -- however the boxes wrap, the page may not"
  Chk ($INK.widest -le $INK.avail) "a modifier chip needs $($INK.widest)px against $($INK.avail)px available ('$($INK.widestText)') -- a chip has a border, so breaking it across two lines reads as two chips"
  Chk ($INK.wordWidest -le $INK.avail) "the single word '$($INK.wordText)' needs $($INK.wordWidest)px against $($INK.avail)px -- a word cannot be broken, so no amount of wrapping saves it"

} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "POTENTIAL GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "POTENTIAL GATE: PASS -- glucose load is carbohydrate minus fibre with both inputs kept; an unresolved item contributes no figure and no zero; fructose arrives only as a reference value, with its coverage stated and never a 0 g; the rate is named with its inputs and the panel states no time at all; water is reported as a percentage for both apple juice (88.2) and cream soup (84.1) and no food is called liquid, solid or a beverage; no banned verb appears and the panel says what an input DELIVERS; the ceiling is a function; and the panel sits closed in a <details> so it costs the ring nothing"
Write-Host "GATE: PASS"
exit 0
