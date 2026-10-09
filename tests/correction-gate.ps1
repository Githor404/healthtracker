# H31 -- THE CORRECTION THAT WAS NEVER FOUND.
#
# DEVICE FINDING: the same glass of white wine photographed on four days. The model
# offers "apple juice" or "broth" every time; the correction is never found.
#
# MEASURED CAUSE (tests/measure-correction-memory.ps1): memory keys on the ACCEPTED
# name while the next capture arrives under the MODEL's name. rememberedRow() by the
# model's name MISSES all four times; the same log by the accepted name HITS. The
# miss is STRUCTURAL -- a key is built only from its own name's tokens, and
# "apple juice" and "white wine" share none, so those keys cannot collide.
#
# RULED (user, 2026-10-08):
#   B     lead on the FIRST prior correction under the same model name; NEVER
#         aggregate across names. Amended gate condition: the fifth capture must
#         arrive under a model name ALREADY SEEN.
#   HINT  yes, bounded at THREE recent corrections, sent with the photo on the
#         user's own key, and the README privacy line updated in the same commit.
#   C     prefer the free local fix: if the past correction is already among the
#         model's three alternatives, re-rank it first LOCALLY.
#   A,D,E,F as recommended -- derive from the log with no new store (D136), D135's
#         closures bind, and the proposal names both the model's word and the
#         user's choice (D137).
#
# THE MEASURED SPREAD IS WHY B IS "FIRST", NOT "THIRD": four captures of one food
# produced FOUR DISTINCT model-name keys, so a count keyed on the model's name
# splits and a lead gated on three prior corrections would never fire.
#
# AND C COVERS THE CASE B CANNOT. Correction memory keys on the model's NAME; the
# alternative re-rank keys on its ALTERNATIVES. A fifth capture under an unseen
# name gets no lead from B -- but an alternative may still match a past correction,
# and that lead is free and local. Both directions are asserted here.
#
# THE FIXTURE ROW IS REAL: CNF 2852, "Alcohol, table wine, white (11.5% alcohol by
# volume)", read out of the shipped asset rather than invented.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8285
$Dbg = 9491
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-correction-" + [System.Guid]::NewGuid().ToString('N'))
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
  const O = { api: {}, seen: {}, unseen: {}, noagg: {}, guard: {}, alt: {}, hint: {},
              apply: {}, surface: {}, ink: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const stage = (x) => { window.__stage = x; O.stage = x; };
  const txt = (el) => String((el && el.textContent) || '');
  const all = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel));
  const WINE = '2852';
  const WINE_NAME = 'Alcohol, table wine, white (11.5% alcohol by volume)';
  try {
  stage('boot');
  HT.setClock(function () { return Date.parse('2026-10-09T19:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);
  O.ns = HT.corpusNamespace();

  ['correctionsAll', 'correctionLead', 'correctionHistory', 'correctionAltRank',
   'correctionHintText', 'correctionLeadText', 'photoPickCorrection']
    .forEach(function (k) { O.api[k] = typeof HT[k]; });
  O.api.max = HT.CORRECTION_HINT_MAX;

  // ---- THE FIXTURE: the reported history, with the measured name spread -----
  stage('seed');
  const S = HT.state();
  const corr = function (d, modelName, accepted, refId, refName, how) {
    const it = { name: accepted, meal: 'drink', time: '19:00', grams: 150,
      kcal: 123, protein_g: 0.1, fat_g: 0, carb_g: 3.8, fiber_g: 0, soluble_fiber_g: 0,
      confidence: 'eyeballed', source: 'ai-paste', notes: '',
      ai_identity: modelName, identity_pick: { kind: 'search' } };
    if (refId) {
      it.ref = { ns: HT.corpusNamespace(), id: refId, name: refName, at: d, at_ms: 1,
                 hash: 'h', how: how || 'picked', g: 150, attribution: 'f', v: { '221': 15.4 } };
    }
    S.days[d] = { status: 'complete', water_l: 0, items: [ it ] };
  };
  // TWO under 'apple juice', ONE under 'broth', ONE under 'apple cider' -- the
  // spread the measurement found, so the count the surface shows is 2 and not 4.
  corr('2026-10-05', 'apple juice', 'white wine', WINE, WINE_NAME);
  corr('2026-10-06', 'apple juice', 'white wine', WINE, WINE_NAME);
  corr('2026-10-07', 'broth', 'white wine', WINE, WINE_NAME);
  corr('2026-10-08', 'apple cider', 'white wine', WINE, WINE_NAME);
  // D135/1: a correction made by OVERRIDING the state guard must never lead.
  corr('2026-10-04', 'mushroom soup', 'dried shiitake', '1234', 'Mushroom, shiitake, dried',
       'confirmed despite state mismatch');
  // A TYPED correction: no corpus ref at all. Ruled E: it still counts, and what it
  // offers is the NAME only -- a ref-required rule would have led with nothing for
  // exactly the user who typed the answer instead of picking a row.
  corr('2026-10-03', 'green smoothie', 'kale and apple juice blend', null, null);
  S.current = '2026-10-08';
  HT.Store.saveState(S);
  await sleep(200);

  // ---- the scan, read as data before it is read as pixels -------------------
  stage('scan');
  if (typeof HT.correctionsAll === 'function') {
    const allc = HT.correctionsAll();
    O.seen.total = allc.length;
    O.seen.dump = JSON.stringify(allc).slice(0, 700);
  }

  // ---- B: a SEEN model name leads, on the FIRST prior correction ------------
  stage('lead');
  if (typeof HT.correctionLead === 'function') {
    const L = HT.correctionLead('apple juice');
    O.seen.lead = L ? JSON.stringify(L) : 'null';
    O.seen.chosen = L ? String(L.chosenName || '') : '';
    O.seen.count = L ? L.count : null;
    O.seen.refId = L ? String(L.refId || '') : '';
    // ONE prior correction is enough (ruled B). 'broth' has exactly one.
    const one = HT.correctionLead('broth');
    O.seen.oneIsEnough = !!one;
    O.seen.oneCount = one ? one.count : null;
    // the typed correction leads with a NAME and no ref
    const ty = HT.correctionLead('green smoothie');
    O.seen.typedLeads = !!ty;
    O.seen.typedRef = ty ? String(ty.refId || '') : 'MISSING';
    O.seen.typedName = ty ? String(ty.chosenName || '') : '';

    // ---- NEVER AGGREGATE ACROSS NAMES (ruled B; B3 rejected) ---------------
    stage('noagg');
    const t = HT.correctionLead('tomato soup');
    O.noagg.unrelated = t ? ('LED WITH ' + t.chosenName) : 'no lead';
    O.noagg.clean = (t === null);

    // ---- D135/1: the override never leads ---------------------------------
    stage('guard');
    const g = HT.correctionLead('mushroom soup');
    O.guard.lead = g ? ('LED WITH ' + g.chosenName) : 'no lead';
    O.guard.clean = (g === null);
  }

  // ---- C: an UNSEEN model name, with a past correction among the ALTS -------
  stage('alt');
  if (typeof HT.correctionAltRank === 'function') {
    const alts = [{ name: 'pear nectar', p: 0.5 }, { name: 'white wine', p: 0.3 },
                  { name: 'broth', p: 0.2 }];
    const a = HT.correctionAltRank(alts);
    O.alt.hit = a ? JSON.stringify(a) : 'null';
    O.alt.rank = a ? a.rank : null;
    // and an alts list with nothing corrected before must not match
    const b = HT.correctionAltRank([{ name: 'pear nectar', p: 1 }, { name: 'cider vinegar', p: 0 }]);
    O.alt.noFalseHit = (b === null);
    // the UNSEEN name itself gets no lead from B -- the measured gap, asserted
    O.unseen.lead = (HT.correctionLead('pear nectar') === null) ? 'no lead' : 'LED';
    O.unseen.clean = (HT.correctionLead('pear nectar') === null);
  }

  // ---- the HINT: bounded at three, most recent first, corrections only -----
  stage('hint');
  if (typeof HT.correctionHistory === 'function') {
    const h = HT.correctionHistory(99);
    O.hint.unbounded = h.length;
    const h3 = HT.correctionHistory();
    O.hint.bounded = h3.length;
    O.hint.order = h3.map(function (x) { return String(x.modelName || ''); }).join(' | ');
  }
  if (typeof HT.correctionHintText === 'function') {
    const t = HT.correctionHintText();
    O.hint.text = String(t || '');
    const hl = String(t || '').split('\n').filter(function (l) { return l.trim(); });
    O.hint.lines = hl.length;
    // CORRECTED: the first draft capped TOTAL lines at four, which the framing
    // breaks on its own. The bound that matters is that the hint cannot GROW
    // WITH THE LOG, so what is capped is the number of CORRECTION lines; the
    // framing gets its own loose cap so it cannot balloon either.
    O.hint.corrLines = hl.filter(function (l) { return l.trim().indexOf('- ') === 0; }).length;
    O.hint.hasMacros = /kcal|protein|carb|\bfat\b|per100|grams/i.test(t);
    O.hint.hasMicros = /iron|vitamin|sodium|calcium|folate|zinc/i.test(t);
    O.hint.hasCorpusId = /\b2852\b|\bcnf\b|\bfdc\b/i.test(t);
    O.hint.namesBoth = /apple juice/i.test(t) && /white wine/i.test(t);
  }

  // ---- R21-PARITY, RE-PINNED: no corrections -> the body is unchanged -------
  stage('parity');
  const base = HT.AI_DIRECT_PREFIX + HT.aiPromptText();
  O.hint.withCorrections = (typeof HT.correctionHintText === 'function')
    ? (base + HT.correctionHintText()) : base;
  // SNAPSHOTTED THROUGH JSON FIRST. `HT.state()` returns the LIVE object, so the
  // first draft of this took `S2 = HT.state()`, deleted its days -- emptying the
  // fixture's own `S`, which was the same object -- and then 'restored' the
  // emptied state. Eight assertions after this point failed for a reason that had
  // nothing to do with the code they were testing.
  const SNAP = JSON.parse(JSON.stringify(HT.state()));
  const S2 = HT.state();
  Object.keys(S2.days).forEach(function (d) { delete S2.days[d]; });
  HT.Store.saveState(S2);
  await sleep(150);
  O.hint.emptyText = (typeof HT.correctionHintText === 'function')
    ? String(HT.correctionHintText() || '') : 'MISSING';
  O.hint.parityHolds = (O.hint.emptyText === '');
  // PUT THEM BACK BY MUTATING THE LIVE OBJECT. `HT.state()` is `() => APP_STATE`,
  // so `saveState(SNAP)` with a different object wrote the fixture to storage and
  // left APP_STATE empty in memory -- and correctionsAll() reads APP_STATE. The
  // fixture works by mutating the live object, so the restore has to as well.
  const live = HT.state();
  Object.keys(SNAP.days).forEach(function (d) { live.days[d] = SNAP.days[d]; });
  live.current = SNAP.current;
  HT.Store.saveState(live);
  await sleep(150);
  O.hint.restored = HT.correctionsAll ? HT.correctionsAll().length : 0;

  // ---- THE SURFACE: a first row, named, never applied ----------------------
  stage('surface');
  // THROUGH THE REAL PARSE PATH, not an injected draft object: openPhotoDraft is
  // what a capture actually calls, so the alts, aiIdentity and altsMismatch are
  // derived by the same code the device runs rather than written here.
  const reply = JSON.stringify({ meal: 'drink', items: [ {
    name: 'apple juice',
    alts: [ { name: 'apple juice', p: 0.5 }, { name: 'white wine', p: 0.3 },
            { name: 'broth', p: 0.2 } ],
    grams: 150,
    per100: { kcal: 46, protein_g: 0.1, fat_g: 0.1, carb_g: 11, fiber_g: 0.2, soluble_fiber_g: 0 },
    scale_linked: true, dominance: 1, notes: 'a tall glass'
  } ] });
  const op = HT.openPhotoDraft(reply);
  O.surface.draftSet = JSON.stringify(op).slice(0, 160);
  HT.refresh();
  await sleep(350);
  const host = document.getElementById('photoDraft');
  const opts = host ? host.querySelector('.pmalts') : null;
  O.surface.mounted = !!opts;
  const btns = opts ? Array.prototype.slice.call(opts.querySelectorAll('button')) : [];
  O.surface.buttons = btns.map(function (b) { return txt(b).trim().slice(0, 80); });
  O.surface.firstIsCorrection = btns.length > 0 && btns[0].className.indexOf('pmaltcorr') >= 0;
  O.surface.firstText = btns.length ? txt(btns[0]).trim() : '';
  O.surface.saysModelWord = /apple juice/i.test(O.surface.firstText);
  O.surface.saysChoice = /wine/i.test(O.surface.firstText);
  O.surface.saysCount = /last 2 times|last two times/i.test(O.surface.firstText);
  // NEVER "the food IS": a repetition of the user's own answer, not an assertion
  O.surface.noIsClaim = !/\bis (a |an )?(white )?wine\b/i.test(O.surface.firstText);
  // a genuine apple juice is still reachable, and the alts order underneath is
  // the MODEL's order with only the corrected alt promoted
  O.surface.altTexts = btns.filter(function (b) { return b.className.indexOf('pmaltcorr') < 0
    && b.className.indexOf('pmsomething') < 0 && b.className.indexOf('pmaltmem') < 0; })
    .map(function (b) { return txt(b).trim(); });
  O.surface.appleStillThere = O.surface.altTexts.some(function (t) { return /apple juice/i.test(t); });
  // THE RECORDED RANK MUST BE THE MODEL'S, NOT THE DISPLAY POSITION
  O.surface.onclicks = btns.map(function (b) { return String(b.getAttribute('onclick') || ''); });

  // ---- C, ON ITS OWN CASE: an UNSEEN model name whose SECOND alternative is
  // something corrected to before. The first surface case has BOTH mechanisms
  // firing, and the build deliberately SUPPRESSES the promotion there, so the
  // promotion can only be asserted where the lead is absent -- which is also the
  // only case that shows fork C reaching what fork B cannot.
  stage('promo');
  HT.photoDiscard();
  const reply2 = JSON.stringify({ meal: 'drink', items: [ {
    name: 'pear nectar',
    alts: [ { name: 'pear nectar', p: 0.5 }, { name: 'white wine', p: 0.3 },
            { name: 'cider vinegar', p: 0.2 } ],
    grams: 150,
    per100: { kcal: 54, protein_g: 0.2, fat_g: 0, carb_g: 13, fiber_g: 0.5, soluble_fiber_g: 0 },
    scale_linked: true, dominance: 1, notes: ''
  } ] });
  HT.openPhotoDraft(reply2);
  HT.refresh();
  await sleep(350);
  const host3 = document.getElementById('photoDraft');
  const opts3 = host3 ? host3.querySelector('.pmalts') : null;
  const btns3 = opts3 ? Array.prototype.slice.call(opts3.querySelectorAll('button')) : [];
  O.alt.anyLead = btns3.some(function (b) { return b.className.indexOf('pmaltcorr') >= 0; });
  const cands3 = btns3.filter(function (b) {
    return String(b.getAttribute('onclick') || '').indexOf('photoPickCandidate') >= 0; });
  O.alt.firstCandText = cands3.length ? txt(cands3[0]).trim() : '';
  O.alt.firstCandClick = cands3.length ? String(cands3[0].getAttribute('onclick') || '') : '';
  O.alt.firstIsPromo = cands3.length > 0 && cands3[0].className.indexOf('pmaltpromo') >= 0;
  O.alt.allCandTexts = cands3.map(function (b) { return txt(b).trim(); });

  // ---- nothing is applied until it is tapped ------------------------------
  stage('apply');
  HT.photoDiscard();
  HT.openPhotoDraft(reply);
  HT.refresh();
  await sleep(300);
  const d0 = HT.photoDraft();
  const i0 = d0 && d0.items && d0.items[0];
  O.apply.beforeRef = (i0 && i0.ref) ? 'HAS REF' : 'no ref';
  O.apply.beforeName = i0 ? String(i0.name || '') : '';
  O.apply.beforeSettled = !!(i0 && i0.idDone);
  if (typeof HT.photoPickCorrection === 'function') {
    const r = await Promise.resolve(HT.photoPickCorrection(0));
    O.apply.result = JSON.stringify(r).slice(0, 160);
    const d1 = HT.photoDraft();
    const i1 = d1 && d1.items && d1.items[0];
    O.apply.afterName = i1 ? String(i1.name || '') : '';
    O.apply.afterRef = (i1 && i1.ref) ? String(i1.ref.id) : 'no ref';
    O.apply.aiKept = i1 ? String(i1.aiIdentity || '') : '';
  }

  // ---- ink at 360px -------------------------------------------------------
  stage('ink');
  const host2 = document.getElementById('photoDraft');
  O.ink.scrollW = host2 ? host2.scrollWidth : 0;
  O.ink.clientW = host2 ? host2.clientWidth : 0;

  } catch (e) { O.threw = String((e && e.message) || e) + ' @ ' + window.__stage;
                O.stack = String((e && e.stack) || '').slice(0, 500); }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  $kick = Eval $probe
  if ($kick -ne '1') { $fails += "the probe would not start: $kick" }
  $raw = $null
  for ($w = 0; $w -lt 120; $w++) {
    Start-Sleep -Milliseconds 500
    $raw = Eval 'window.__out'
    if ($raw) { break }
  }
  if (-not $raw) {
    $st = Eval 'String(window.__stage)'
    $fails += "the probe HUNG after 60s -- last stage reached: '$st'"
    $RES = [pscustomobject]@{}
  } else { $RES = $raw | ConvertFrom-Json }
  if ($RES.threw) { $fails += "the probe threw: $($RES.threw) | $($RES.stack)" }

  # NAMED, never single capitals: PowerShell folds variable case, so a later
  # `foreach ($x in ...)` would silently destroy a capture called $X and every
  # assertion after it would read $null and pass vacuously (recorded in H24).
  $API = $RES.api; $SEEN = $RES.seen; $UNSEEN = $RES.unseen; $NOAGG = $RES.noagg
  $GUARD = $RES.guard; $ALT = $RES.alt; $HINT = $RES.hint; $APPLY = $RES.apply
  $SURF = $RES.surface; $INK = $RES.ink

  Chk ($RES.ns -eq 'cnf') "the Canadian namespace was not driven (ns=$($RES.ns))"

  # --- the API exists -------------------------------------------------------
  foreach ($fname in @('correctionsAll', 'correctionLead', 'correctionHistory',
                       'correctionAltRank', 'correctionHintText', 'correctionLeadText',
                       'photoPickCorrection')) {
    Chk ($API.$fname -eq 'function') "HT.$fname is '$($API.$fname)', not a function"
  }
  Chk ($API.max -eq 3) "CORRECTION_HINT_MAX is '$($API.max)', not the ruled 3"

  # --- the fixture is real, or everything below is vacuous ------------------
  Chk ($SEEN.total -ge 5) "the scan found $($SEEN.total) correction(s) in a six-item fixture -- without them nothing below is exercised ($($SEEN.dump))"

  # --- B: a SEEN model name leads, on the FIRST prior correction ------------
  Chk ($SEEN.chosen -match 'wine') "a capture under 'apple juice' does not lead with the wine that was chosen twice before (lead=$($SEEN.lead))"
  Chk ($SEEN.refId -eq '2852') "the lead does not carry the corpus row that was chosen (refId='$($SEEN.refId)')"
  Chk ($SEEN.count -eq 2) "the lead reports a count of $($SEEN.count) for 'apple juice' -- the fixture holds exactly TWO under that model name, and the measured point of fork B is that the count is per MODEL NAME and not the four corrections in total"
  Chk ($SEEN.oneIsEnough -eq $true) "ONE prior correction produced no lead -- ruled B: lead on the FIRST, because the model's wording varies and a higher threshold never fires"
  Chk ($SEEN.oneCount -eq 1) "the single-correction lead reports a count of $($SEEN.oneCount), not 1"

  # --- ruled E: a TYPED correction still counts, and offers the name only ---
  Chk ($SEEN.typedLeads -eq $true) "a correction made through the TYPED path produced no lead -- a ref-required rule leads with nothing for the user who typed the answer instead of picking a row"
  Chk ($SEEN.typedRef -eq '') "the typed correction's lead claims a corpus ref ('$($SEEN.typedRef)') -- there was none, and inventing one would put numbers behind a name the corpus never matched"
  Chk ($SEEN.typedName -ne '') "the typed correction's lead carries no name either, so it offers nothing at all"

  # --- NEVER AGGREGATE (B3 rejected on the measurement) --------------------
  Chk ($NOAGG.clean -eq $true) "an unrelated model name was led with a past correction ($($NOAGG.unrelated)) -- aggregating across names means a real broth gets led with wine, and 'broth -> wine' and 'apple juice -> wine' are different confusions"

  # --- D135/1: the override never leads ------------------------------------
  Chk ($GUARD.clean -eq $true) "a correction made by OVERRIDING the state guard became a lead ($($GUARD.lead)) -- overriding once is a decision about one item; becoming the default is a decision about every future one, and it was never made"

  # --- C: the alternative re-rank, and the gap it covers -------------------
  Chk ($UNSEEN.clean -eq $true) "an UNSEEN model name produced a lead from correction memory ($($UNSEEN.lead)) -- it cannot and must not: this is the measured limit of fork B, asserted rather than hidden"
  Chk ($ALT.rank -eq 1) "the past correction sitting at the model's SECOND alternative was not found (got rank $($ALT.rank), hit=$($ALT.hit)) -- this is the case fork B cannot reach, and ruling C covers it for free"
  Chk ($ALT.noFalseHit -eq $true) "an alts list containing nothing ever corrected still reported a match"
  # and the same thing on the RENDERED surface, where the lead is absent
  Chk ($ALT.anyLead -eq $false) "an UNSEEN model name still rendered a correction lead (rows: $($ALT.allCandTexts -join ' | '))"
  Chk ($ALT.firstIsPromo -eq $true) "the corrected alternative was not promoted to the FIRST candidate row (order: $($ALT.allCandTexts -join ' | ')) -- this is the case fork B cannot reach and fork C covers for free"
  Chk ($ALT.firstCandText -match 'white wine') "the first candidate row is '$($ALT.firstCandText)', not the alternative corrected to before"
  Chk ($ALT.firstCandClick -match 'photoPickCandidate\(0,\s*1\)') "the promoted row does not pass the MODEL rank 1 ('$($ALT.firstCandClick)') -- identity_pick.rank is evidence about which of the model candidates was taken, so a display renumbering would record it as rank 0 and say the model had been right"
  Chk ($ALT.firstCandText -match 'chose this before') "the promoted row does not say WHY it moved ('$($ALT.firstCandText)')"

  # --- the HINT: bounded, ordered, corrections only ------------------------
  Chk ($HINT.bounded -eq 3) "the hint carries $($HINT.bounded) corrections, not the ruled three"
  Chk ($HINT.unbounded -gt 3) "asking for 99 returned $($HINT.unbounded) -- the fixture must hold more than three, or 'bounded at three' is proven by an empty log rather than by the bound"
  Chk ($HINT.order -match '^apple cider') "the hint is not MOST RECENT FIRST (order: $($HINT.order))"
  Chk ($HINT.namesBoth -eq $true) "the hint does not name both what the model said and what was chosen ('$($HINT.text)')"
  Chk ($HINT.hasMacros -eq $false) "the hint carries MACROS ('$($HINT.text)') -- it names corrections and nothing else"
  Chk ($HINT.hasMicros -eq $false) "the hint carries a MICRONUTRIENT key ('$($HINT.text)')"
  Chk ($HINT.hasCorpusId -eq $false) "the hint carries a corpus id or namespace ('$($HINT.text)') -- the provider has no use for our row ids and they are not the user's to send"
  Chk ($HINT.corrLines -eq 3) "the hint carries $($HINT.corrLines) correction LINE(S) for three corrections -- this is the bound that matters: the hint must not grow with the log"
  Chk ($HINT.lines -le 6) "the hint is $($HINT.lines) lines in total -- the framing around three corrections must not balloon either"
  Chk ($HINT.text -match 'hints, not answers') "the request does not SAY the corrections are hints rather than answers -- D128 lets the model NAME things, and a hint that reads as an instruction makes the next naming partly the app''s"

  # --- R21-PARITY, RE-PINNED rather than relaxed ---------------------------
  Chk ($HINT.parityHolds -eq $true) "with NO corrections the hint is '$($HINT.emptyText)' rather than empty -- R21-parity's stronger half is that a user who has corrected nothing sends a byte-identical body"
  Chk ($HINT.restored -ge 5) "the fixture did not survive the parity check, so the assertions after it ran against an empty log"

  # --- THE SURFACE ---------------------------------------------------------
  Chk ($SURF.mounted -eq $true) "the identity options never rendered ($($SURF.draftSet))"
  Chk ($SURF.firstIsCorrection -eq $true) "the correction is not the FIRST row (buttons: $($SURF.buttons -join ' | ')) -- the first row is where a stray tap lands, measured twice on the device"
  Chk ($SURF.saysModelWord -eq $true) "the first row does not say what the MODEL said ('$($SURF.firstText)')"
  Chk ($SURF.saysChoice -eq $true) "the first row does not say what the USER chose ('$($SURF.firstText)')"
  Chk ($SURF.saysCount -eq $true) "the first row does not state the count ('$($SURF.firstText)') -- ruled: 'the last 2 times you said this was white wine'"
  Chk ($SURF.noIsClaim -eq $true) "the first row asserts the food IS wine ('$($SURF.firstText)') -- it is a repetition of the user's own earlier answer, which is a reason to put a row first and never a reason to skip the question"
  Chk ($SURF.appleStillThere -eq $true) "a genuine apple juice is no longer one tap away (alts: $($SURF.altTexts -join ' | ')) -- real apple juice exists"

  # the recorded rank must be the MODEL's rank, not the display position
  $promoted = @($SURF.onclicks | Where-Object { $_ -match 'photoPickCandidate' })
  Chk ($promoted.Count -ge 2) "only $($promoted.Count) candidate button(s) carry a pick handler, so the rank assertion below is near-vacuous"
  Chk (($promoted -join ' ') -match 'photoPickCandidate\(0,\s*1\)') "the promoted alternative does not pass the MODEL's rank (handlers: $($promoted -join ' ')) -- identity_pick.rank is calibration evidence about which of the model's candidates was taken, so renumbering it would make every promoted pick record as rank 0 and say the model was right"

  # --- nothing is applied until it is tapped ------------------------------
  Chk ($APPLY.beforeRef -eq 'no ref') "the item carried a ref BEFORE the correction was tapped ($($APPLY.beforeRef)) -- never auto-applied: real apple juice exists"
  Chk ($APPLY.beforeName -eq 'apple juice') "the item's name changed before any tap ('$($APPLY.beforeName)')"
  Chk ($APPLY.beforeSettled -eq $false) "the identity was settled before any tap"
  Chk ($APPLY.afterRef -eq '2852') "tapping the correction did not apply the remembered corpus row (ref='$($APPLY.afterRef)') -- what was chosen before is what is offered"
  Chk ($APPLY.afterName -match 'wine') "tapping the correction did not set the name to what was chosen ('$($APPLY.afterName)')"
  Chk ($APPLY.aiKept -eq 'apple juice') "the MODEL's name was lost when the correction applied ('$($APPLY.aiKept)') -- ai_identity is what the next capture will be keyed on, so losing it here breaks the memory for the very next photo"

  # --- the page does not scroll sideways ----------------------------------
  Chk ($INK.clientW -gt 0) "the draft reported no width, so the overflow assertion is vacuous"
  Chk ($INK.scrollW -le $INK.clientW) "the draft scrolls sideways: scrollWidth $($INK.scrollW) against clientWidth $($INK.clientW) at 360px"

} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "CORRECTION GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "CORRECTION GATE: PASS -- a capture under a model name corrected before leads with what was chosen, on the FIRST prior correction, with the count per model name (2, not 4); an unrelated name and a state-guard override both lead with nothing; an unseen name gets no lead but its ALTERNATIVE matching a past correction is promoted, carrying the model's own rank; a typed correction leads with a name and no invented ref; the hint is bounded at three, most recent first, corrections only, and a user with no corrections sends a byte-identical body; the first row names the model's word and the user's choice without claiming the food IS anything; a genuine apple juice stays one tap away; and nothing applies until it is tapped"
Write-Host "GATE: PASS"
exit 0
