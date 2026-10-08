# H30 -- PARITY: a typed name gets what a photo gets.
#
# DEVICE FINDING: photographed siu mai, not identified. Typed "sui mai" into
# Something else -- no candidates and NO NUTRIENTS AT ALL. Deleted it,
# re-photographed, and it was identified. The same food succeeded through the
# camera and failed through the keyboard.
#
# RULED (user, 2026-10-07):
#   A3  full parity -- normalised name, EYEBALLED ESTIMATE, alternatives. Labelled,
#       never micros. The estimate's real job is giving the macro pair something
#       to sit beside.
#   B   the fallback renders ALWAYS when the search is empty, DIRECTLY UNDER THE
#       INPUT, with a plain "needs your key" state when unconfigured. Not
#       automatic -- local-first stays.
#   C   the pair on every candidate reached through a normalised name; NEVER
#       auto-pick; and the normalised word is shown as a query the app RAN
#       ("searched for potsticker"), never as an answer.
#   D   up to five search terms, each run locally, and the user picks from REAL
#       ROWS. The model supplies search terms, never an answer.
#
# THE TWO REAL-CORPUS CASES, AND WHY THE SECOND ONE MATTERS MOST.
#
# Measured in the shipped CNF:
#   Dumpling, plain        (501830)  P 3.5  F 10.7  C 21.6  197 kcal
#   Potsticker or wonton   (502501)  P 8.3  F  5.5  C 13.3  136 kcal
#   siu mai, eyeballed               P ~12  F ~11          ~210 kcal
#
# ON ENERGY THE WRONG ROW LOOKS BETTER: 197 is closer to ~210 than 136 is. So the
# kcal pair would have ENDORSED the plain flour dumpling. PROTEIN is the
# discriminator -- 3.5 against 8.3 against ~12 -- because that is the meat, which
# is the whole difference between the two foods. This gate asserts BOTH halves:
# that protein exposes it, AND that kcal alone would not have.
#
# THE PROVIDER REPLY IS STUBBED AND SMUGGLES CONTRABAND. It carries micros and a
# confidence figure the contract does not allow, so the boundary is proven to drop
# them rather than merely assumed to.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8281
$Dbg = 9487
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-parity-" + [System.Guid]::NewGuid().ToString('N'))
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
  # Report the exception rather than returning an empty string: a probe with a
  # syntax error otherwise reports only "would not start", which cost a diagnosis
  # on the H25 gate.
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
  # The device is Canadian and the two gated rows were measured in CNF, so the
  # namespace is DRIVEN rather than left to the host's locale.
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
  const O = { empty: {}, asked: {}, rows: [], item: {}, ink: {}, words: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const stage = (x) => { window.__stage = x; O.stage = x; };
  const txt = (el) => String((el && el.textContent) || '');
  const all = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel));
  const vis = (el) => !!(el && el.offsetParent !== null);
  try {
  HT.setClock(function () { return Date.parse('2026-10-07T12:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(250);
  O.ns = HT.corpusNamespace();

  // THE STUBBED REPLY. It smuggles micros and a confidence number: the contract
  // permits an eyeballed MACRO estimate and nothing else, so the boundary has to
  // drop the rest rather than be trusted to.
  const realFetch = window.fetch;
  O.asked.requests = [];
  window.fetch = function (u, o) {
    const url = String(u);
    if (url.indexOf('/chat/completions') >= 0) {
      O.asked.requests.push(String((o && o.body) || ''));
      const content = JSON.stringify({
        names: ['potsticker', 'pork dumpling', 'siu mai', 'shumai', 'dim sum', 'SIXTH'],
        per100: { kcal: 210, protein_g: 12, fat_g: 11, carb_g: 16, fiber_g: 1, soluble_fiber_g: 0 },
        micros: { iron_mg: 2.5, sodium_mg: 400 },
        confidence: 0.8,
        vitamin_c_mg: 9
      });
      const body = JSON.stringify({ choices: [{ message: { content: content } }] });
      return Promise.resolve(new Response(body, { status: 200,
        headers: { 'Content-Type': 'application/json' } }));
    }
    return realFetch.apply(window, arguments);
  };

  // a draft whose first item is the reported food
  const mk = (name, kcal, grams) => ({ name: name, grams: grams, notes: 'from the photo',
    alts: [{ name: name, p: 0.4 }, { name: name + ', plain', p: 0.3 }, { name: 'other', p: 0.3 }],
    per100: { kcal: kcal, protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 1, soluble_fiber_g: 0 } });
  HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: [
    mk('unidentified item', 150, 120), mk('a second thing', 90, 100)] }));
  await sleep(500);

  // ---- B: the offer renders when the search is empty, WITH NO KEY --------
  stage('empty-no-key');
  O.empty.configured0 = HT.byokConfigured();
  const lists = all('.pmalts');
  lists[0].querySelector('.pmsomething').click();
  await sleep(200);
  await HT.photoSearchRun(0, 'sui mai');
  await sleep(500);
  O.empty.rows = all('.pmsrow').length;
  const ask0 = document.querySelector('.pmsask');
  O.empty.askPresentNoKey = !!ask0;
  O.empty.askVisibleNoKey = vis(ask0);
  O.empty.askTextNoKey = txt(ask0).trim();
  O.empty.keepOffered = vis(document.querySelector('.pmskeep'));
  // DIRECTLY UNDER THE INPUT: above the keep button and above any rows
  const inp = document.getElementById('pmsQuery');
  const keepEl = document.querySelector('.pmskeep');
  if (ask0 && inp) {
    O.empty.askBelowInput = ask0.getBoundingClientRect().top >= inp.getBoundingClientRect().top;
    O.empty.askAboveKeep = keepEl ? (ask0.getBoundingClientRect().top <= keepEl.getBoundingClientRect().top) : null;
    O.empty.askOnScreen = ask0.getBoundingClientRect().top < window.innerHeight;
  }

  // ---- with a key, the offer is live -----------------------------------
  stage('empty-with-key');
  HT.byokSave('grok', 'xai-GATEFIXTURE0000000000000', 5);
  await HT.photoSearchRun(0, 'sui mai');
  await sleep(400);
  const ask1 = document.querySelector('.pmsask');
  O.empty.askVisibleWithKey = vis(ask1);
  O.empty.askTextWithKey = txt(ask1).trim();

  // ---- D: five search terms, each run LOCALLY -------------------------
  stage('ask-model');
  const res = await HT.photoSearchAskModel(0);
  await sleep(600);
  O.asked.ok = !!(res && res.ok);
  O.asked.names = (res && res.names) || [];
  O.asked.searchedFor = String((res && res.searchedFor) || '');
  O.asked.triedCount = (res && res.tried) ? res.tried.length : null;
  const st = HT.photoSearchState() || {};
  O.asked.stateNames = (st.asked || []).slice();
  // ONE provider call, not one per name
  O.asked.calls = O.asked.requests.length;
  // the REQUEST must not ask for micronutrients
  const body0 = O.asked.requests[0] || '';
  // A BAN CANNOT BE DETECTED BY THE WORDS THE BAN USES. The first version matched
  // the prompt's own prohibition (*do not include vitamins, minerals...*) and
  // reported that the request ASKED for them. What is checkable is the JSON SHAPE
  // the prompt asks to be returned: it must name no micronutrient key.
  const shape = (String(HT.identityNormalisePrompt()).match(/\{[^}]*\}[^}]*\}/) || [''])[0];
  O.asked.shape = shape.slice(0, 200);
  O.asked.shapeAsksMicros = /iron|vitamin|sodium|calcium|folate|zinc|magnesium/i.test(shape);
  O.asked.shapeAsksMacros = /protein_g/.test(shape) && /kcal/.test(shape);
  O.asked.requestSaysEyeballed = /eyeballed/i.test(body0);

  // ---- A3: the item gets an EYEBALLED ESTIMATE, and NO MICROS -----------
  stage('parity');
  const it = HT.photoDraft().items[0];
  O.item.hasPer100 = !!it.per100;
  O.item.kcal = it.per100 ? it.per100.kcal : null;
  O.item.protein = it.per100 ? it.per100.protein_g : null;
  O.item.confidence = String(it.confidence || '');
  O.item.micros = it.micros === undefined;
  O.item.per100Keys = it.per100 ? Object.keys(it.per100).sort() : [];
  O.item.estimateFlagged = (it.estimateFrom === 'model');
  // the parse must drop the contraband
  const parsed = HT.identityNormaliseParse(JSON.stringify({
    names: ['a', 'b', 'c', 'd', 'e', 'f'],
    per100: { kcal: 1, protein_g: 2, fat_g: 3, carb_g: 4, fiber_g: 5, soluble_fiber_g: 6, iron_mg: 9 },
    micros: { iron_mg: 9 }, confidence: 0.5, sodium_mg: 7 }));
  O.item.parseNames = parsed.names;
  O.item.parsePer100Keys = parsed.per100 ? Object.keys(parsed.per100).sort() : [];
  O.item.parseHasMicros = !!(parsed.micros || (parsed.per100 && parsed.per100.iron_mg != null));
  O.item.parseHasConfidence = parsed.confidence !== undefined;

  // ---- C: the rows, the macro pair, and 'searched for X' ----------------
  stage('rows');
  const rowEls = all('.pmsrow');
  O.rows = rowEls.map(function (b) {
    const m = b.querySelector('.pmsmac');
    return { name: txt(b.querySelector('.pmsnm')).trim().slice(0, 60),
             macro: txt(m).trim(), hasMacro: !!m };
  });
  O.words.searchedFor = txt(document.querySelector('.pmssearched')).trim();
  O.words.oursOnce = all('.pmsours').length;
  O.words.oursText = txt(document.querySelector('.pmsours')).trim();
  // NEVER AN ANSWER: no sentence may claim the food IS the normalised word
  const panel = txt(document.querySelector('.pmsearch'));
  O.words.panel = panel.replace(/\s+/g, ' ').trim().slice(0, 300);
  O.words.noClaim = !/this is a |it is a |identified as /i.test(panel);
  // NEVER AUTO-PICKED
  // PARITY MEANS THE ITEM NOW HAS COMPOSITION, so `unres` -- which means 'no
  // composition' -- is legitimately false here. The claim worth asserting is that
  // nothing was picked FOR the user: no corpus ref, and the identity not settled.
  O.words.notSettled = (HT.photoDraft().items[0].idDone !== true);
  O.words.noRef = !HT.photoDraft().items[0].ref;

  // ---- the ink, content-sized (D140's trap, twice) ---------------------
  stage('ink');
  const probe = document.createElement('span');
  probe.className = 'pmsmac';
  probe.style.cssText = 'position:absolute;left:-9999px;white-space:nowrap;display:inline-block';
  document.body.appendChild(probe);
  const host = document.querySelector('.pmsearch');
  O.ink.avail = host ? Math.round(host.getBoundingClientRect().width) : 0;
  O.ink.needs = O.rows.map(function (r) {
    probe.textContent = r.macro;
    return Math.ceil(probe.getBoundingClientRect().width);
  });
  probe.remove();
  O.ink.widest = O.ink.needs.length ? Math.max.apply(null, O.ink.needs) : 0;

  stage('done');
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

  $E = $R.empty; $A = $R.asked; $IT = $R.item; $W = $R.words; $K = $R.ink

  Chk ($R.ns -eq 'cnf') "the Canadian namespace was not driven (ns=$($R.ns))"

  # --- B: the offer is there WITH NO KEY, and says so --------------------
  Chk ($E.rows -eq 0) "the typed name found $($E.rows) row(s) in the real corpus -- this gate needs the EMPTY case the device hit"
  Chk ($E.configured0 -eq $false) "the fixture starts with a key configured, so the no-key case is not exercised"
  Chk ($E.askPresentNoKey -eq $true) "with NO KEY the normalisation offer is ABSENT -- which is what the device hit: not a fallback nobody finds, but one that was not there"
  Chk ($E.askVisibleNoKey -eq $true) "the offer is present but not visible with no key"
  Chk ($E.askTextNoKey -match 'key') "with no key the offer does not say it needs one ('$($E.askTextNoKey)')"
  Chk ($E.askBelowInput -eq $true) "the offer is not under the input"
  Chk ($E.askAboveKeep -eq $true) "the offer sits BELOW the keep button -- ruled: directly under the input"
  Chk ($E.askOnScreen -eq $true) "the offer is off screen"
  Chk ($E.askVisibleWithKey -eq $true) "with a key the offer is not visible"

  # --- D: five terms, ONE call, each run locally -------------------------
  Chk ($A.ok -eq $true) "the normalisation call did not succeed against the stub"
  Chk ($A.names.Count -eq 5) "$($A.names.Count) search term(s) survived the parse -- ruled UP TO FIVE, and the stub offered six"
  Chk ($A.calls -eq 1) "$($A.calls) provider call(s) for five terms -- the terms are run LOCALLY, not one call each"
  Chk ($A.searchedFor -ne '') "the app does not report WHICH term it searched"
  Chk ($A.shapeAsksMicros -eq $false) "the JSON SHAPE the request asks for names a micronutrient key ('$($A.shape)') -- never, by the honesty rule"
  Chk ($A.shapeAsksMacros -eq $true) "the requested shape does not name the macro keys, so the one permitted payload is not actually specified ('$($A.shape)')"
  Chk ($A.requestSaysEyeballed -eq $true) "the request does not say the estimate is EYEBALLED, so the label is not in the contract it was asked under"

  # --- A3: the estimate arrives, labelled, with NO micros ---------------
  Chk ($IT.hasPer100 -eq $true) "the typed item got NO estimate -- which is literally the reported 'no nutrients at all'"
  Chk ($IT.kcal -eq 210) "the estimate's energy is $($IT.kcal), not the 210 the reply carried"
  Chk ($IT.protein -eq 12) "the estimate's protein is $($IT.protein), not 12"
  Chk ($IT.confidence -eq 'eyeballed') "the item's confidence is '$($IT.confidence)', not eyeballed"
  Chk ($IT.micros -eq $true) "the item carries a micros map from the MODEL -- the honesty rule forbids it absolutely"
  Chk (($IT.per100Keys -join ',') -eq 'carb_g,fat_g,fiber_g,kcal,protein_g,soluble_fiber_g') "the estimate carries keys '$($IT.per100Keys -join ',')' -- six macros, nothing else"
  Chk ($IT.estimateFlagged -eq $true) "the estimate is not marked as the MODEL's -- an unlabelled number is indistinguishable from a sourced one"
  Chk (($IT.parseNames -join ',') -eq 'a,b,c,d,e') "the parse returned '$($IT.parseNames -join ',')' -- five names, and the sixth dropped"
  Chk ($IT.parseHasMicros -eq $false) "the parse let a micronutrient through"
  Chk ($IT.parseHasConfidence -eq $false) "the parse let the model's confidence figure through"
  Chk (($IT.parsePer100Keys -join ',') -eq 'carb_g,fat_g,fiber_g,kcal,protein_g,soluble_fiber_g') "the parsed estimate carries '$($IT.parsePer100Keys -join ',')'"

  # --- C: the rows carry the FULL macro row, and nothing claims an answer -
  Chk ($R.rows.Count -gt 0) "the normalised search found no rows at all -- then normalisation reached nothing and this gate proves nothing"
  Chk (($R.rows | Where-Object { -not $_.hasMacro }).Count -eq 0) "a candidate row carries no macro figures"
  Chk ($W.oursOnce -eq 1) "the item's own estimate is stated $($W.oursOnce) time(s) -- ONCE above the list, which is what makes the full macro row fit"
  Chk ($W.oursText -match '210') "the item's estimate line does not carry its energy ('$($W.oursText)')"
  Chk ($W.oursText -match '12') "the item's estimate line does not carry its protein -- the discriminator for this food"
  Chk ($W.searchedFor -match 'searched for') "the surface does not say it RAN a search ('$($W.searchedFor)') -- ruled C: a query the app ran, never an answer"
  Chk ($W.noClaim -eq $true) "the panel claims the food IS the normalised word ('$($W.panel)')"
  Chk ($W.notSettled -eq $true) "the identity was SETTLED without the user tapping a row -- ruled: never auto-pick"
  Chk ($W.noRef -eq $true) "a corpus ref was written without the user tapping a row"

  # --- THE TWO REAL-CORPUS CASES ----------------------------------------
  $pot = $R.rows | Where-Object { $_.name -match 'Potsticker' } | Select-Object -First 1
  Chk ($null -ne $pot) "the normalised terms did not reach 'Potsticker or wonton' -- the row that proves normalisation finds a TRUE row (names: $(($R.rows | ForEach-Object { $_.name }) -join ' | '))"
  $dum = $R.rows | Where-Object { $_.name -match 'Dumpling, plain' } | Select-Object -First 1
  if ($null -ne $dum) {
    # THE RECORDED FINDING, ASSERTED: protein exposes it and kcal does NOT.
    Chk ($dum.macro -match '3\.5') "the plain-dumpling row does not show its PROTEIN (3.5) -- the only figure that exposes it as the wrong food ('$($dum.macro)')"
    Chk ($dum.macro -match '197') "the plain-dumpling row does not show its energy (197)"
  } else {
    $fails += "the normalised terms did not reach 'Dumpling, plain' -- the case that proves the kcal pair alone would have ENDORSED the wrong row cannot be exercised (names: $(($R.rows | ForEach-Object { $_.name }) -join ' | '))"
  }

  # --- the ink, measured content-sized ----------------------------------
  Chk ($K.avail -gt 0) "the panel reported no width, so the ink measurement is vacuous"
  Chk ($K.widest -le $K.avail) "the widest macro row needs $($K.widest)px against $($K.avail)px available -- it must fit on ONE line, which is why the item's estimate is stated once rather than per row"
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "PARITY GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "PARITY GATE: PASS -- the normalisation offer is present and visible with NO key and says it needs one; five terms survive, one provider call runs them all locally; the typed item gets an eyeballed macro estimate, labelled, with the micros and confidence the reply smuggled both dropped; every candidate carries its full macro row against the item estimate stated once; the surface says what it SEARCHED and never what the food IS; nothing is auto-picked; and the real corpus returns both Potsticker or wonton and Dumpling, plain with the protein that tells them apart"
Write-Host "GATE: PASS"
exit 0
