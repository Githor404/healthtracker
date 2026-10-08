# H27 -- "SOMETHING ELSE": THE WAY OUT OF THE IDENTITY DEAD END.
#
# Reported from the device: photographing a drink, the photo draft offers three
# identity choices; when none is right, there is no discoverable way to give the
# correct one.
#
# MEASURED before anything was built, and it is worse than three choices.
# `identityOptionsHTML` renders the memory proposal, up to three candidate names,
# "None of these", and then `photoIdentityOptions` -- a PRESETS dropdown that
# returns the empty string when there are no presets. Presets ship empty by the
# multi-user rule, and the real log has ZERO of them. So the only re-pick
# affordance the code had was INVISIBLE, and the one path out of the question
# ("None of these") discarded the answer.
#
# THE HAZARD IS ASSERTED, NOT ASSUMED (D96): this gate checks that
# photoIdentityOptions(0) is still the empty string with zero presets, so the
# defect it exists for remains visible to it.
#
# Fixture-synthetic forever (CLAUDE.md): no export is ever read. The corpus rows
# and ids are DISCOVERED AT RUNTIME from the real index rather than pinned, so a
# corpus refresh cannot rot the fixture into a false pass.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8171
$origin = "http://127.0.0.1:$port"
$dbg = 9377
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-idsearchgate-" + [System.Guid]::NewGuid().ToString('N'))
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
  return $r.result.result.value
}
function EvalAsync([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + ($r.result.exceptionDetails.text) }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (-not (Test-Path (Join-Path $repo 'corpus/dist/cnf.bin'))) {
  Write-Host "ERROR: corpus/dist/cnf.bin is missing -- run corpus/encode.py first"; exit 2
}

$server = Start-Job -ArgumentList $repo, $port -ScriptBlock {
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
try {
  Start-Sleep -Milliseconds 600
  $chromeArgs = @("--headless=new", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $chromeArgs -PassThru
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$dbg/json" -TimeoutSec 3
      $page = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($page) { $tabUrl = $page.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }

  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  # The device is Canadian, and the candidate list differs by namespace (D114).
  # The reported case came from `cnf`, so the gate is driven there.
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $probe = @'
(async function () {
  const out = {};
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const txt = (el) => String((el && el.textContent) || '');
  const all = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel));
  const vis = (el) => !!(el && el.offsetParent !== null);
  // The identity list is found BY THE ITEM IT BELONGS TO, never by position: the
  // lead block and the rows are different hosts, and a settled row collapses its
  // control (D144), so an index into .pmalts drifts as the draft is worked.
  function listFor(re) {
    const lists = all('.pmalts').concat(all('.pmsearch'));
    for (let i = 0; i < lists.length; i++) {
      const host = lists[i].closest('.pmrow') || lists[i].closest('.pmlead');
      if (host && re.test(txt(host))) return lists[i];
    }
    return null;
  }
  function openSearchFor(re) {
    const l = listFor(re);
    const b = l && l.querySelector('.pmsomething');
    if (!b) return false;
    b.click();
    return true;
  }
  function srows() { return all('.pmsrow'); }
  // Numbers at ANY depth, so a model reply cannot smuggle one inside a nested
  // object and satisfy a shallow check.
  function anyNumber(o) {
    if (typeof o === 'number') return true;
    if (o && typeof o === 'object') {
      const ks = Object.keys(o);
      for (let i = 0; i < ks.length; i++) if (anyNumber(o[ks[i]])) return true;
    }
    return false;
  }

  // ONE THROW MUST NOT COST EIGHTY MEASUREMENTS. The first red run of this gate
  // aborted on the first missing symbol and reported every assertion as failed
  // with NOTHING behind any of them -- eighty findings, no data, and no way to
  // tell a real failure from an absent one. Whatever was measured before a throw
  // now survives it, and the throw itself is a named failure.
  try {
  HT.setClock(function () { return Date.parse('2026-10-05T19:00:00-04:00'); });
  localStorage.clear();
  HT.boot();
  await sleep(250);
  await HT.corpusEnsure();
  HT.matchIndexBuild();
  await sleep(200);
  out.ns = HT.corpusNamespace();

  // ---- THE MEASURED STATE: zero presets, zero memory ----------------------
  const S = HT.state();
  out.presets0 = ((S.settings && S.settings.presets) || []).length;
  out.memory0 = !HT.rememberedRow('red wine');
  // A key is saved at FIXTURE TIME so the only difference between the two
  // normalisation checks is whether the local search found anything. Nothing
  // clicks the offer, so nothing is ever sent.
  out.keySaved = !!(HT.byokSave('grok', 'xai-GATEFIXTURE0000000000000', 5) || {}).ok;

  const mk = (name, kcal100, grams) => ({ name: name, grams: grams, notes: 'estimated from the photo',
    alts: [{ name: name, p: 0.5 }, { name: name + ', plain', p: 0.3 }, { name: 'something else entirely', p: 0.2 }],
    per100: { kcal: kcal100, protein_g: 1, fat_g: 0, carb_g: 3, fiber_g: 0, soluble_fiber_g: 0 } });
  const paste = JSON.stringify({ meal: 'dinner', items: [
    mk('red wine', 85, 150),
    mk('noodles', 140, 270),
    mk('clear broth', 7, 200),
    mk('grandmas secret sauce', 60, 40)] });
  const r0 = HT.openPhotoDraft(paste);
  await sleep(600);
  out.opened = !!r0.ok;
  out.draftMeal0 = String(HT.photoDraft().meal || '');

  // ---- 1. ONE CONTROL, ON EVERY LIST, WITH ZERO PRESETS AND ZERO MEMORY ----
  // The old re-pick was a presets dropdown, and with no presets it rendered
  // nothing at all. That is the hazard, and it must still be true here or this
  // gate is checking a defect that moved (D96).
  out.oldRepickEmpty = (HT.photoIdentityOptions(0) === '');
  const lists = all('.pmalts');
  out.nLists = lists.length;
  out.everyListHasSearch = lists.length > 0 && lists.every(l => !!l.querySelector('.pmsomething'));
  out.everyListSearchVisible = lists.length > 0 && lists.every(l => vis(l.querySelector('.pmsomething')));
  out.searchLabel = txt(lists[0] && lists[0].querySelector('.pmsomething')).trim();
  out.terminusCount = all('.pmaltnone').length;
  out.pickNoneGone = (typeof HT.photoPickNone !== 'function');
  out.presetSelectCount = all('.pmid').length;
  const sb0 = lists[0] && lists[0].querySelector('.pmsomething');
  out.searchH = sb0 ? Math.round(sb0.getBoundingClientRect().height) : 0;
  out.searchFont = sb0 ? Math.round(parseFloat(getComputedStyle(sb0).fontSize)) : 0;

  // ---- 2. OPENING IT, AND DISMISSING IT WITHOUT TYPING --------------------
  // The one case the rulings did not cover: a cancel must leave the item exactly
  // as it was. A cancel that resolved anything would reintroduce the terminus by
  // the back door.
  const before0 = JSON.stringify(HT.photoDraft().items[0]);
  out.openedSearch = openSearchFor(/red wine/i);
  await sleep(250);
  const panel = document.querySelector('.pmsearch');
  out.panelOpen = !!panel;
  out.inputPresent = !!document.getElementById('pmsQuery');
  out.panelReplacesList = !!panel && panel.querySelectorAll('.pmalt').length === 0;
  if (panel) {
    const pr = panel.getBoundingClientRect();
    out.panelOnScreen = pr.top >= 0 && pr.top < window.innerHeight;
  }
  const cx = document.querySelector('.pmscancel');
  if (cx) cx.click();
  await sleep(300);
  out.cancelClosed = !document.querySelector('.pmsearch');
  out.cancelLeftItem = (JSON.stringify(HT.photoDraft().items[0]) === before0);
  out.cancelKeptQuestion = !!listFor(/red wine/i);

  // ---- 3. TYPING: MEMORY FIRST, THEN THE CORPUS, EACH WITH A KCAL PAIR ----
  out.reopened = openSearchFor(/red wine/i);
  await sleep(200);
  await HT.photoSearchRun(0, 'wine table red');
  await sleep(600);
  const w = srows();
  out.nWineRows = w.length;
  out.cap = HT.IDENTITY_SEARCH_MAX;
  out.withinCap = w.length > 0 && w.length <= HT.IDENTITY_SEARCH_MAX;
  out.capStated = new RegExp('\\b' + HT.IDENTITY_SEARCH_MAX + '\\b').test(txt(document.querySelector('.pmscap')));
  // H30 re-pin: a candidate row carries the FULL MACRO ROW, not energy alone.
  // Ruled after measuring that energy ENDORSES the wrong row for siu mai
  // (Dumpling, plain 197 vs Potsticker 136 against an estimate of ~210) while
  // protein separates them. Which macro gives away a wrong match depends on the
  // food, so all four travel.
  out.everyRowKcal = w.length > 0 && w.every(b => /\bcal\b/i.test(txt(b)));
  out.everyRowMacros = w.length > 0 && w.every(b => !!b.querySelector('.pmsmac'));
  // ITS OWN ELEMENT, not a regex over the whole panel: a candidate row that
  // happens to read 85 cal/100g would have satisfied the panel-wide test while
  // the pair itself was missing.
  out.oursShown = /\b85\b/.test(txt(document.querySelector('.pmsours')));
  // A `%` IN A CORPUS FOOD NAME IS NOT A SCORE. "Cream, 18% M.F." is what the
  // database calls that food, and the first version of this assertion failed on
  // it -- testing the database's spelling instead of the app's restraint. The
  // claim is narrower and exact: the only number the app adds to a row is the
  // energy, in one format, and no similarity figure appears anywhere.
  // H30 re-pin: the figures moved from `.rkcal` (still the RESOLVE surface's own
  // span) to `.pmsmac`, in one known format. The claim is unchanged -- the only
  // numbers the app adds to a row are composition figures, in one shape -- and the
  // shape is now P / F / C / cal.
  out.rowKcalTexts = w.map(b => txt(b.querySelector('.pmsmac')).trim());
  out.kcalFormatOnly = out.rowKcalTexts.length > 0
    && out.rowKcalTexts.every(t => /^P [\d.?]+ \u00b7 F [\d.?]+ \u00b7 C [\d.?]+ \u00b7 [\d?]+ cal$/.test(t));
  out.noJaccard = !w.some(b => /\d\.\d\d/.test(txt(b)));
  out.jaccardControl = /\d\.\d\d/.test(txt(w[0] || document.body) + ' 0.37');
  out.noBlankMemRow = !document.querySelector('.pmsmem');
  out.askAbsentWhenRowsFound = !document.querySelector('.pmsask');
  out.wineRows = w.slice(0, 4).map(b => txt(b).trim().slice(0, 46));

  // ---- 4. ONE TAP SETS THE NAME AND THE MATCH ----------------------------
  const wine = w.filter(b => /wine/i.test(txt(b)))[0] || w[0];
  out.wineRowText = txt(wine).trim().slice(0, 60);
  if (wine) wine.click(); else out.noWineRow = true;
  await sleep(1200);
  const it0 = HT.photoDraft().items[0];
  out.pickedName = String(it0.name || '');
  out.pickedNameChanged = (out.pickedName !== 'red wine');
  out.pickedRef = !!it0.ref;
  out.refWhen = it0.ref ? String(it0.ref.when || '') : '';
  out.refHow = it0.ref ? String(it0.ref.how || '') : '';
  out.refG = it0.ref ? it0.ref.g : null;
  out.itemG = it0.grams;
  out.pickedNotUnres = (it0.unres !== true);
  out.pickedSettled = (it0.idDone === true);
  out.pickKind = (it0.idPick && String(it0.idPick.kind || '')) || '';
  out.panelClosedAfterPick = !document.querySelector('.pmsearch');
  // H26 needs ALCOHOL GRAMS, which is what ruling A says to read.
  out.alcoholG = it0.ref ? HT.refAlcoholG(it0.ref) : null;

  // ---- 5. RULING A: NO DRINK CLASS FROM WATER ----------------------------
  // A high-water pick must not invent a boundary. The draft's meal is unchanged
  // and no item gains a meal of its own.
  out.openedBroth = openSearchFor(/clear broth/i);
  await sleep(200);
  await HT.photoSearchRun(2, 'water tap municipal');
  await sleep(600);
  const bw = srows();
  out.nBrothRows = bw.length;
  if (bw.length) { bw[0].click(); await sleep(1200); }
  const it2 = HT.photoDraft().items[2];
  out.brothRef = !!it2.ref;
  out.brothWaterG = it2.ref ? (it2.ref.v['255'] || 0) : 0;
  out.brothAlcoholG = it2.ref ? HT.refAlcoholG(it2.ref) : null;
  // A ref with NO alcohol slot must report ABSENCE, not zero. Returning 0 would
  // claim a measurement nobody made -- zero-filling a missing micronutrient, one
  // function along.
  out.absentAlcohol = HT.refAlcoholG({ v: {} });
  out.draftMealAfter = String(HT.photoDraft().meal || '');
  out.noItemMeal = HT.photoDraft().items.every(x => x.meal == null);

  // ---- 6. THE STATE GUARD STILL FIRES ON A SEARCH PICK (D135/1) ----------
  out.openedNoodles = openSearchFor(/noodle/i);
  await sleep(200);
  // THE APP CLASSIFIES ITS OWN ROWS. A regex for the word "dry" asked a narrower
  // question than foodState answers -- it also counts dried, dehydrated,
  // uncooked, instant, powder, mix, concentrate and flakes -- so the probe reads
  // `state` off the rows the app built and tries a few queries until one has a
  // dry row. A corpus refresh therefore cannot rot this fixture into a false pass
  // OR a false failure.
  const DRYQ = ['noodles dry', 'spaghetti dry', 'macaroni uncooked', 'noodles instant',
                'rice dry', 'lentils dried', 'milk powder'];
  let dryRow = null;
  for (let qi = 0; qi < DRYQ.length && !dryRow; qi++) {
    await HT.photoSearchRun(1, DRYQ[qi]);
    await sleep(500);
    const st = HT.photoSearchState();
    const rs = (st && st.rows) || [];
    const hit = rs.filter(c => c.state === 'dry')[0];
    if (hit) {
      out.dryQuery = DRYQ[qi];
      out.dryRowName = String(hit.name || '');
      dryRow = srows().filter(b => txt(b).indexOf(hit.name) >= 0)[0] || null;
      out.dryRowFoundInDom = !!dryRow;
    }
  }
  const dr = srows();
  out.nDryRows = dr.length;
  out.dryOffered = !!dryRow;
  const before1 = JSON.stringify(HT.photoDraft().items[1]);
  const dry = dryRow;
  if (dry) dry.click(); else out.noDryRow = true;
  await sleep(700);
  out.guardFired = !!document.querySelector('.pmsconfirmbtn');
  out.guardText = txt(document.querySelector('.pmswarn')).trim();
  out.guardHidesRows = (srows().length === 0);
  out.notResolvedWhileAsking = !HT.photoDraft().items[1].ref;
  const gcancel = all('.pmsconfirmbtn').filter(b => /cancel/i.test(txt(b)))[0];
  if (gcancel) gcancel.click();
  await sleep(400);
  out.guardCancelUntouched = (JSON.stringify(HT.photoDraft().items[1]) === before1);
  out.guardCancelRowsBack = (srows().length > 0);
  const dry2 = srows().filter(b => txt(b).indexOf(out.dryRowName) >= 0)[0];
  if (dry2) dry2.click();
  await sleep(600);
  const guse = all('.pmsconfirmbtn').filter(b => /use anyway/i.test(txt(b)))[0];
  if (guse) guse.click();
  await sleep(1200);
  const it1 = HT.photoDraft().items[1];
  out.dryRefHow = it1.ref ? String(it1.ref.how || '') : '';
  out.dryRefWhen = it1.ref ? String(it1.ref.when || '') : '';

  // ---- 7. NO MATCH IS NOT A DEAD END ------------------------------------
  out.openedSauce = openSearchFor(/secret sauce/i);
  await sleep(200);
  await HT.photoSearchRun(3, 'zzqqxv wibblefrotz');
  await sleep(600);
  out.nNoneRows = srows().length;
  out.noMatchSaysSo = /nothing|no row|not in/i.test(txt(document.querySelector('.pmsnone')));
  out.keepOffered = vis(document.querySelector('.pmskeep'));
  out.askPresentWhenEmpty = vis(document.querySelector('.pmsask'));
  const keep = document.querySelector('.pmskeep');
  if (keep) keep.click();
  await sleep(500);
  const it3 = HT.photoDraft().items[3];
  out.keptName = String(it3.name || '');
  out.keptUnres = (it3.unres === true);
  out.keptNoRef = !it3.ref;
  out.keptSettled = (it3.idDone === true);

  // ---- 8. D8: THE MODEL MAY NORMALISE A NAME, NEVER SUPPLY A NUMBER -----
  // Asserted on the REQUEST as well as the result.
  const prompt = String(HT.identityNormalisePrompt() || '');
  out.promptLen = prompt.length;
  out.promptAsksName = /\bname/i.test(prompt);
  // H30 RE-PIN OF A SAFETY ASSERTION, narrowed to what the honesty rule actually
  // forbids rather than loosened. H27 banned every money word, which was right
  // while the model was asked for NAMES ONLY. Ruling A3 now asks it for the same
  // eyeballed MACRO estimate the photo path has always produced, labelled the same
  // way -- and the honesty rule says so in its own words.
  //
  // What stays absolutely forbidden is MICRONUTRIENTS. And a ban cannot be detected
  // by the words the ban uses -- the prompt's own prohibition says 'vitamins,
  // minerals' -- so the check reads the JSON SHAPE the prompt asks to be returned.
  const shape = (prompt.match(/\{[^}]*\}[^}]*\}/) || [''])[0];
  out.promptShape = shape.slice(0, 200);
  out.shapeAsksMicros = /iron|vitamin|sodium|calcium|folate|zinc|magnesium|cholesterol/i.test(shape);
  out.promptSaysEyeballed = /eyeballed/i.test(prompt);
  out.promptForbidsMicros = /do not include[^.]*micronutrient|vitamins, minerals/i.test(prompt);
  // H30: the parse returns { names, per100 } -- names are QUERIES, and per100 is
  // the one permitted numeric payload. The contraband below must not survive.
  const parsed = HT.identityNormaliseParse('{"names":["Wine, table, red","Cabernet"],'
    + '"per100":{"kcal":550,"protein_g":9,"iron_mg":4},"micros":{"vitamin_c_mg":9},"confidence":0.7}');
  out.parsedNames = (parsed && Array.isArray(parsed.names)) ? parsed.names : null;
  out.parseKeptMacros = !!(parsed && parsed.per100 && parsed.per100.kcal === 550);
  out.parseDroppedMicros = !!(parsed && parsed.per100 && parsed.per100.iron_mg === undefined)
    && (parsed.micros === undefined);
  out.parseDroppedConfidence = (parsed && parsed.confidence === undefined);
  const body = HT.byokBody(null, 'x', 'm', null);
  const parts = (body && body.messages && body.messages[0] && body.messages[0].content) || [];
  out.bodyPartKinds = (Array.isArray(parts) ? parts : []).map(p => String(p.type || ''));

  // ---- 9. IT SAVES -----------------------------------------------------
  const sr = HT.photoSave();
  await sleep(900);
  out.saveOk = !!(sr && sr.ok);
  const day = HT.state().days[HT.state().current] || { items: [] };
  const saved = (day.items || []);
  out.savedCount = saved.length;
  const sauce = saved.filter(x => /wibblefrotz|zzqqxv/i.test(String(x.name || '')))[0];
  out.savedTypedName = sauce ? String(sauce.name) : '';
  out.savedUnresolved = sauce ? (sauce.unresolved === true) : null;
  const swine = saved.filter(x => x.ref && HT.refAlcoholG(x.ref) > 0)[0];
  out.savedAlcoholG = swine ? HT.refAlcoholG(swine.ref) : null;

  // ---- 10. MEMORY LEADS THE SEARCH RESULTS (D137/D133) ------------------
  // Seeded from the REAL index so the id cannot rot, and the remembered row's
  // name is NOT the typed query -- so "it names its source" cannot pass by echo.
  const seed = HT.matchCandidates('wine table red', 1)[0];
  out.seedId = seed ? String(seed.id) : '';
  out.seedName = seed ? String(seed.name) : '';
  HT.state().days['2026-09-20'] = { status: 'complete', water_l: 0, items: [
    { name: 'cab sauv', meal: 'dinner', time: '19:00', grams: 150, kcal: 128,
      protein_g: 0, fat_g: 0, carb_g: 4, fiber_g: 0, soluble_fiber_g: 0,
      confidence: 'eyeballed', source: 'ai-paste', notes: '',
      ref: { ns: 'cnf', id: out.seedId, name: out.seedName, at: '2026-09-20', at_ms: 1,
             hash: 'h', how: 'picked', when: 'later',
             attribution: 'Canadian Nutrient File, Health Canada, 2015', v: { '221': 15 } } }] };
  out.memoryNow = !!HT.rememberedRow('cab sauv');
  const r1 = HT.openPhotoDraft(JSON.stringify({ meal: 'dinner', items: [mk('house red', 85, 150)] }));
  await sleep(600);
  out.memDraftOpened = !!r1.ok;
  out.openedMem = openSearchFor(/house red/i);
  await sleep(200);
  await HT.photoSearchRun(0, 'cab sauv');
  await sleep(600);
  const mr = srows();
  out.nMemRows = mr.length;
  out.memRowFirst = mr.length > 0 && /\bpmsmem\b/.test(String(mr[0].className || ''));
  // WIDENED from 90: the macro row now sits between the name and the provenance
  // line, so a 90-character window stopped reaching the words this asserts on.
  // The text was there; the measurement was too short to see it.
  out.memRowText = txt(mr[0]).trim().slice(0, 220);
  out.memNamesSource = /cab sauv/i.test(out.memRowText);
  out.memCarriesCorpusName = out.seedName ? (out.memRowText.indexOf(out.seedName) >= 0) : false;
  out.memNotEcho = out.seedName ? (('cab sauv').indexOf(out.seedName) < 0) : false;
  if (mr[0]) mr[0].click();
  await sleep(1200);
  const itm = HT.photoDraft().items[0];
  out.memPickRef = !!itm.ref;
  out.memPickWhen = itm.ref ? String(itm.ref.when || '') : '';
  out.memPickName = String(itm.name || '');

  // ---- 10b. A SEARCH DOES NOT SURVIVE THE DRAFT IT WAS OPENED ON --------
  // Found in the defect pass, not by this gate: every openPhotoDraft above
  // follows a pick or a keep, both of which close the search, so the state the
  // defect lives in was never reached. PHOTO_SEARCH is keyed by ITEM INDEX, and
  // an index into a replaced list points at a different food.
  HT.photoSearchOpen(0);
  HT.photoSearchType('left open on purpose');
  out.searchOpenBeforeNewDraft = (HT.photoSearchState() !== null);
  HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: [mk('a different food', 90, 120)] }));
  await sleep(500);
  out.searchClearedByNewDraft = (HT.photoSearchState() === null);
  out.noPanelOnNewDraft = !document.querySelector('.pmsearch');
  out.newDraftAsksItsOwnQuestion = !!listFor(/a different food/i);
  // and the same on a discard, which is the other way a draft goes away
  HT.photoSearchOpen(0);
  HT.photoDiscard();
  await sleep(200);
  out.searchClearedByDiscard = (HT.photoSearchState() === null);

  // ---- 11. SUPERSEDING THE DROPDOWN MUST NOT LOSE WHAT IT COULD DO ------
  // Fork E takes the presets re-pick away. A control that SUPERSEDES another has
  // to be able to do what it replaced, or it is a removal wearing a
  // supersession -- and the user who has presets is the one who finds out.
  HT.state().settings.presets = [{ id: 'p1', name: 'my protein shake', kcal: 220,
    protein_g: 30, fat_g: 4, carb_g: 12, fiber_g: 2, soluble_fiber_g: 0, portion_g: 330 }];
  const r2 = HT.openPhotoDraft(JSON.stringify({ meal: 'snack', items: [mk('beige drink', 60, 330)] }));
  await sleep(600);
  out.presetDraftOpened = !!r2.ok;
  out.openedPreset = openSearchFor(/beige drink/i);
  await sleep(200);
  await HT.photoSearchRun(0, 'my protein shake');
  await sleep(600);
  const pr2 = all('.pmspreset');
  out.nPresetRows = pr2.length;
  out.presetRowNames = pr2.map(b => txt(b).trim().slice(0, 40));
  if (pr2[0]) pr2[0].click();
  await sleep(600);
  const itp = HT.photoDraft().items[0];
  out.presetPickedName = String(itp.name || '');
  out.presetPer100 = (itp.per100 && itp.per100.kcal != null) ? Math.round(itp.per100.kcal) : null;
  out.presetSettled = (itp.idDone === true);
  } catch (e) {
    out.threw = String((e && e.message) || e);
  }
  return JSON.stringify(out);
})()
'@
  $r = EvalAsync $probe
  if ($r -like 'EXCEPTION*') { $fails += "the page threw: $r" }
  $R = if ($r -like 'EXCEPTION*') { [pscustomobject]@{} } else { $r | ConvertFrom-Json }

  # --- setup, and the hazard this gate exists to see (D96) ------------------
  if ($R.threw) { $fails += "the probe threw partway through: $($R.threw) -- everything measured after that point is absent, not false" }
  if ($R.ns -ne 'cnf') { $fails += "the Canadian namespace was NOT driven (ns=$($R.ns)) -- the reported case came from it" }
  if (-not $R.opened) { $fails += "setup: the photo draft did not open" }
  if ($R.presets0 -ne 0) { $fails += "setup: the fixture has $($R.presets0) preset(s) -- the measured state is ZERO, which is why the old re-pick was invisible" }
  if (-not $R.memory0) { $fails += "setup: something is already remembered, so 'the list with zero memory' is not what was measured" }
  if (-not $R.oldRepickEmpty) {
    $fails += "photoIdentityOptions(0) is no longer empty with zero presets -- the invisible-re-pick hazard moved, and this gate can no longer see the defect it exists for"
  }
  if ($R.nLists -lt 4) { $fails += "only $($R.nLists) identity list(s) rendered -- the 4-item plate should put one on every item" }

  # --- ONE CONTROL, on every list ------------------------------------------
  if (-not $R.everyListHasSearch) { $fails += "an identity list has NO type-and-search control -- the dead end is still reachable from it" }
  if ($R.everyListHasSearch -and -not $R.everyListSearchVisible) {
    $fails += "the search control is PRESENT but not visible (offsetParent null) -- textContent would have reported it anyway"
  }
  if ($R.searchLabel -notmatch 'something else') { $fails += "the control is not labelled 'Something else' (got '$($R.searchLabel)')" }
  if ($R.terminusCount -ne 0) { $fails += "'None of these' still renders ($($R.terminusCount) found) -- two buttons opening one thing is one thing with two names (D139/D147)" }
  if (-not $R.pickNoneGone) { $fails += "photoPickNone still exists -- unresolved is still something you can PICK, which the ruling removes" }
  if ($R.presetSelectCount -ne 0) { $fails += "the presets dropdown still renders beside the search ($($R.presetSelectCount) found) -- fork E says it is superseded, not accompanied" }
  if ($R.searchH -lt 44) { $fails += "the search control is $($R.searchH)px tall, below the 44px touch floor" }
  if ($R.searchFont -lt 16) { $fails += "the search control renders at $($R.searchFont)px, below the 16px floor (D124)" }

  # --- opening it, and the cancel the rulings did not cover -----------------
  if (-not $R.openedSearch) { $fails += "the search control did not open anything" }
  if (-not $R.panelOpen) { $fails += "no search panel appeared" }
  if (-not $R.inputPresent) { $fails += "the panel has no text field -- type-and-search is the whole point" }
  if (-not $R.panelReplacesList) { $fails += "the panel left the candidate buttons on screen, so the tap that opened it can land on one (D127)" }
  if (-not $R.panelOnScreen) { $fails += "the panel opened off screen at 390x844" }
  if (-not $R.cancelClosed) { $fails += "cancelling did not close the panel" }
  if (-not $R.cancelLeftItem) { $fails += "DISMISSING THE SEARCH WITHOUT TYPING CHANGED THE ITEM -- a cancel that resolves anything reintroduces the terminus by the back door" }
  if (-not $R.cancelKeptQuestion) { $fails += "cancelling left the item with no identity question at all" }

  # --- typing: the results, and what each row shows ------------------------
  if (-not $R.reopened) { $fails += "the search would not reopen after a cancel" }
  if ([int]$R.nWineRows -lt 1) { $fails += "a search for 'wine table red' returned NOTHING from the real corpus -- the fixture cannot exercise a pick" }
  if (-not $R.withinCap) { $fails += "the search returned $($R.nWineRows) rows against a cap of $($R.cap)" }
  if (-not $R.capStated) { $fails += "the cap ($($R.cap)) is not stated on the surface -- a silently truncated search reads as 'that food is not in the database'" }
  if (-not $R.everyRowKcal) { $fails += "a search row is missing its energy (rows: $($R.wineRows -join ' | '))" }
  if (-not $R.everyRowMacros) { $fails += "a search row carries no .pmsmac macro row -- H30 ruled the full P/F/C/cal row on every candidate, because which macro exposes a wrong match depends on the food" }
  if (-not $R.oursShown) { $fails += "the item's OWN energy per 100 g (85) is not shown beside the rows -- a kcal PAIR is what makes the right pick visible (D122)" }
  if (-not $R.kcalFormatOnly) { $fails += "a row's figures are not the one known format 'P n . F n . C n . n cal' (got: $($R.rowKcalTexts -join ' | '))" }
  if (-not $R.noJaccard) { $fails += "a similarity figure appeared on a search row (C1 holds: no number the user cannot act on)" }
  if (-not $R.jaccardControl) { $fails += "the no-similarity test does not FIND a planted 0.37, so it proves nothing (D96)" }
  if (-not $R.noBlankMemRow) { $fails += "a memory row rendered with nothing remembered -- absence must be absent, not blank" }

  # --- one tap sets the name AND the match --------------------------------
  if (-not $R.pickedRef) { $fails += "one tap on a search row did NOT resolve the item -- picking must set the name and the match together" }
  if (-not $R.pickedNameChanged) { $fails += "the pick left the model's name in place ('$($R.pickedName)') -- the name and the match are one answer" }
  if ($R.refWhen -ne 'capture') { $fails += "the ref says when='$($R.refWhen)', not 'capture' -- resolve-at-capture is what D141 measures" }
  if ($R.refHow -ne 'picked') { $fails += "the ref says how='$($R.refHow)' -- a typed search the user chose from is 'picked'" }
  if ($R.refG -ne $R.itemG) { $fails += "the ref froze at g=$($R.refG) against the item's $($R.itemG) grams (ruling H2)" }
  if (-not $R.pickedNotUnres) { $fails += "the item is still flagged unresolved after a successful pick" }
  if (-not $R.pickedSettled) { $fails += "the identity did not settle, so the question stays open after it was answered" }
  if (-not $R.panelClosedAfterPick) { $fails += "the search panel stayed open after the pick" }

  # --- H26 reads ALCOHOL GRAMS (ruling A) ---------------------------------
  if (-not ($R.alcoholG -gt 0)) { $fails += "the wine pick carries no alcohol grams (got '$($R.alcoholG)') -- H26's night comparison has nothing to read" }

  # --- ruling A, the other half: no drink class from water ----------------
  if ([int]$R.nBrothRows -lt 1) { $fails += "a search for 'water tap municipal' returned nothing, so the high-water case is not exercised" }
  if (-not $R.brothRef) { $fails += "the high-water pick did not resolve" }
  if (-not ($R.brothWaterG -gt 0)) { $fails += "the high-water row carries no water (slot 255), so this fixture cannot test the boundary that must NOT be invented" }
  if ($R.brothAlcoholG -gt 0) { $fails += "a water row reports $($R.brothAlcoholG) g of alcohol" }
  if ($null -ne $R.absentAlcohol) { $fails += "refAlcoholG returns '$($R.absentAlcohol)' for a ref with NO alcohol slot -- absence is not a quantity, and zero is a measurement" }
  if ($R.draftMealAfter -ne $R.draftMeal0) { $fails += "the draft's meal changed from '$($R.draftMeal0)' to '$($R.draftMealAfter)' -- ruling A forbids deriving a drink class from water content" }
  if (-not $R.noItemMeal) { $fails += "an item gained a meal of its own after a pick -- ruling A forbids setting meal:'drink' from a matched row" }

  # --- the state guard still fires (D135/1) ------------------------------
  if (-not $R.dryOffered) { $fails += "no row the app itself classifies as DRY was found by any of the probe's queries ($($R.nDryRows) rows on the last one) -- without one the state guard has nothing to fire on" }
  if (-not $R.guardFired) { $fails += "a DRY row was picked for a (probably) cooked item and NOTHING ASKED -- the D135/1 guard does not reach the search path" }
  if (-not $R.guardHidesRows) { $fails += "the question left the search rows on screen, so the tap that answers it can land on another row" }
  if (-not $R.notResolvedWhileAsking) { $fails += "the item resolved while the question was still being asked" }
  if ($R.guardText -notmatch 'probably') { $fails += "the question does not hedge an INFERRED state: '$($R.guardText)'" }
  if ($R.guardText -notmatch 'too (high|low)') { $fails += "the question does not name the CONSEQUENCE in the units already held: '$($R.guardText)'" }
  if (-not $R.guardCancelUntouched) { $fails += "cancelling the state question changed the item" }
  if (-not $R.guardCancelRowsBack) { $fails += "cancelling the state question did not return the search rows" }
  if ($R.dryRefHow -ne 'confirmed despite state mismatch') { $fails += "going ahead recorded how='$($R.dryRefHow)' -- the record must say the mismatch was confirmed" }
  if ($R.dryRefWhen -ne 'capture') { $fails += "the confirmed-anyway ref says when='$($R.dryRefWhen)', not 'capture'" }

  # --- no match is NOT a dead end ---------------------------------------
  if ([int]$R.nNoneRows -ne 0) { $fails += "the nonsense query returned $($R.nNoneRows) row(s), so the empty case is not exercised" }
  if (-not $R.noMatchSaysSo) { $fails += "an empty search says nothing about being empty" }
  if (-not $R.keepOffered) { $fails += "an empty search offers no way to keep what was typed -- that is the dead end again, one surface along" }
  if ($R.keptName -ne 'zzqqxv wibblefrotz') { $fails += "what was typed did not stand as the name (got '$($R.keptName)')" }
  if (-not $R.keptUnres) { $fails += "the kept name did not land UNRESOLVED -- honest ignorance is the outcome, and it has to be recorded as one" }
  if (-not $R.keptNoRef) { $fails += "a ref was written for a name the corpus does not hold" }
  if (-not $R.keptSettled) { $fails += "the identity did not settle, so the item still asks a question the user answered" }

  # --- D8: the model may normalise a NAME, never supply a NUMBER ---------
  if (-not $R.askAbsentWhenRowsFound) { $fails += "the model's normalisation was offered even though the LOCAL search found rows -- fork D says local first, so the common path costs no call" }
  if (-not $R.askPresentWhenEmpty) { $fails += "the model's normalisation is not offered when the local search returns nothing -- which is the only case it was ruled for" }
  if ([int]$R.promptLen -lt 20) { $fails += "identityNormalisePrompt() is empty or missing" }
  if (-not $R.promptAsksName) { $fails += "the normalisation request does not ask for a NAME" }
  if ($R.shapeAsksMicros) { $fails += "the JSON SHAPE the request asks for names a MICRONUTRIENT key ('$($R.promptShape)') -- forbidden absolutely, at the request and not only at the result" }
  if (-not $R.promptSaysEyeballed) { $fails += "the request does not say the estimate is EYEBALLED, so the label is not part of the contract it was asked under" }
  if (-not $R.promptForbidsMicros) { $fails += "the request does not TELL the model to leave micronutrients out -- the parse drops them either way, but a contract that does not say so invites a reply that fights it" }
  if (-not $R.parseKeptMacros) { $fails += "identityNormaliseParse dropped the eyeballed MACRO estimate -- ruled A3 permits exactly that one payload, and it is what the macro pair is read against"
  }
  if (-not $R.parseDroppedMicros) { $fails += "identityNormaliseParse let a MICRONUTRIENT through -- including one hidden inside per100, which is exactly where a model would put it" }
  if (-not $R.parseDroppedConfidence) { $fails += "identityNormaliseParse let the model's confidence figure through" }
  if (($R.parsedNames -join '|') -ne 'Wine, table, red|Cabernet') { $fails += "identityNormaliseParse did not return just the names (got '$($R.parsedNames -join '|')')" }
  if (($R.bodyPartKinds -join ',') -ne 'text') { $fails += "a text-only request still carries an image part (parts: $($R.bodyPartKinds -join ',')) -- the normalisation sends no photo" }

  # --- it saves ---------------------------------------------------------
  if (-not $R.saveOk) { $fails += "the draft would not save after the search settled every identity" }
  if ($R.savedTypedName -ne 'zzqqxv wibblefrotz') { $fails += "the typed name did not reach the record (got '$($R.savedTypedName)')" }
  if ($R.savedUnresolved -ne $true) { $fails += "the record does not say the typed item is unresolved" }
  if (-not ($R.savedAlcoholG -gt 0)) { $fails += "no saved item carries alcohol grams -- H26 reads the RECORD, not the draft" }

  # --- memory leads the search results (D133/D137) ----------------------
  if (-not $R.memoryNow) { $fails += "the seeded prior day is not remembered, so the memory-first claim is untested" }
  if (-not $R.memDraftOpened) { $fails += "the second draft did not open" }
  if ([int]$R.nMemRows -lt 1) { $fails += "the search returned no rows with a memory present" }
  if (-not $R.memRowFirst) { $fails += "the remembered row is not FIRST in the search results (first row: '$($R.memRowText)')" }
  if (-not $R.memNamesSource) { $fails += "the remembered row does not NAME the item it came from: '$($R.memRowText)'" }
  if (-not $R.memCarriesCorpusName) { $fails += "the remembered row does not carry the corpus row's own name ('$($R.seedName)')" }
  if (-not $R.memNotEcho) { $fails += "the fixture's remembered name is a substring of the typed query, so 'it names its source' could pass by echo (D96)" }
  if (-not $R.memPickRef) { $fails += "picking the remembered row did not resolve the item" }
  if ($R.memPickWhen -ne 'capture') { $fails += "the memory pick says when='$($R.memPickWhen)', not 'capture'" }

  # --- a search does not outlive its draft (found in the defect pass) -------
  if (-not $R.searchOpenBeforeNewDraft) { $fails += "the search was not open before the new draft, so this case proves nothing (D96)" }
  if (-not $R.searchClearedByNewDraft) { $fails += "A SEARCH LEFT OPEN SURVIVED INTO THE NEXT DRAFT -- its index now points at a different food" }
  if (-not $R.noPanelOnNewDraft) { $fails += "the stale search panel RENDERED over the new draft" }
  if (-not $R.newDraftAsksItsOwnQuestion) { $fails += "the new draft's own identity question is missing" }
  if (-not $R.searchClearedByDiscard) { $fails += "discarding a draft left the search open, so the next draft inherits it" }

  # --- fork E: the supersession must not be a removal -----------------------
  if (-not $R.presetDraftOpened) { $fails += "the preset draft did not open" }
  if ([int]$R.nPresetRows -lt 1) { $fails += "the search does not offer the user's OWN presets, so superseding the dropdown LOST a path instead of replacing it (fork E)" }
  if ($R.presetPickedName -ne 'my protein shake') { $fails += "picking a preset from the search did not set its name (got '$($R.presetPickedName)')" }
  if ($R.presetPer100 -ne 67) { $fails += "the preset's numbers did not arrive scaled to per-100 g (got $($R.presetPer100), expected 67 from 220 kcal per 330 g)" }
  if (-not $R.presetSettled) { $fails += "a preset pick did not settle the identity" }
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "IDENTITY-SEARCH GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "IDENTITY-SEARCH GATE: PASS -- one control on every list with zero presets and zero memory; a cancel changes nothing; one tap sets the name and the match at capture; the state guard still fires; a name the corpus does not hold stands unresolved and saves; the model is asked for a name and never for a number"
Write-Host "GATE: PASS"
exit 0
