# R242/B -- USDA FOODDATA CENTRAL, WITH THE USER'S OWN KEY.
#
# RULED (2026-10-10, COMMERCIAL; R242/B): FDC admitted -- Branded AND Survey
# (FNDDS) -- with the user's own key, entered in Settings and stored on the device
# only; every result shows its macros beside the item's own estimate; "nothing
# fits" comes BEFORE the list; the citation is carried; the precedence rule
# applies. R245 measured the first row wrong in most of a ten-food sample, so a row
# is a SUGGESTION: nothing is sent until a tap, nothing is picked until a tap.
#
# Driven on the three surfaces a food is picked on -- Search, the not-counted
# picker, the photo sheet -- against a STUBBED service: window.fetch answers for
# api.nal.usda.gov in the page, so this gate never calls USDA and needs no key.
# Fixtures are synthetic.
#
# Set FDC_SHOTS=1 to save 390px screenshots of each surface to %TEMP%\fdc-shots.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8319
$origin = "http://127.0.0.1:$port"
$dbg = 9525
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-fdc-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None
$shots = $null
if ($env:FDC_SHOTS) { $shots = Join-Path $env:TEMP 'fdc-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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
    if (++$guard -gt 2000) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
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
function Eval([string]$expr) {
  $rv = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  return $rv.result.result.value
}
function EvalAsyncB64([string]$js) {
  $j = $js -replace "`r`n", "`n"
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($j))
  $expr = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"
  $rv = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($rv.result.exceptionDetails) {
    return "EXCEPTION: " + ($rv.result.exceptionDetails.text) + " " + ($rv.result.exceptionDetails.exception.description)
  }
  return $rv.result.result.value
}
function Shot([string]$name) {
  if (-not $shots) { return }
  $rv = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png' }
  [IO.File]::WriteAllBytes((Join-Path $shots ($name + '.png')), [Convert]::FromBase64String($rv.result.data))
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
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

$fails = @()
try {
  WaitServer "$origin/index.html"
  $cargs = @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $cargs -PassThru
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
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  # ---- stage 1: the slots, no key, the key, the offer, the tap, the rows -------
  $js1 = @'
(async function () {
  const G = window.__G = { checks: [], calls: [] };
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const all = (s) => Array.prototype.slice.call(document.querySelectorAll(s));
  window.__sleep = sleep;
  try {
    localStorage.clear(); HT.boot(); await window.__htQuiet(10000);
    await HT.corpusEnsure(); await window.__htQuiet(10000);
    const realFetch = window.fetch;
    window.__realFetch = realFetch;
    // THE CORPUS SLOTS ARE FDC's: the list held in app.js must be the shipped files' own.
    const cj = await (await realFetch('corpus/dist/cnf.json')).json();
    const fj = await (await realFetch('corpus/dist/fdc.json')).json();
    ok(JSON.stringify(cj.slots) === JSON.stringify(HT.FDC_SLOTS) && JSON.stringify(fj.slots) === JSON.stringify(HT.FDC_SLOTS),
       'the slot list FDC rows are read under is the shipped files\u2019 own, so an FDC figure lands where a database figure would');
    // THE STUBBED SERVICE. Synthetic rows; 'limitme' answers 429.
    const N = (num, v, unit, how) => ({ nutrientNumber: String(num), value: v, unitName: unit || 'G', derivationCode: how || '' });
    const FOODS = [
      { fdcId: 9200001, dataType: 'Survey (FNDDS)', description: 'Gate stew, beef and vegetable', publishedDate: '2024-10-31',
        foodNutrients: [N(208, 120, 'KCAL'), N(203, 9), N(204, 5), N(205, 10), N(291, 1.5), N(307, 300, 'MG')] },
      { fdcId: 9200002, dataType: 'Branded', description: 'GATE SMOKED FISH SPREAD', brandName: 'GATE BRAND', publishedDate: '2023-03-16',
        foodNutrients: [N(208, 250, 'KCAL', 'LCCS'), N(203, 14, 'G', 'LCCS'), N(204, 21, 'G', 'LCCS'), N(205, 0.8, 'G', 'LCSL'), N(307, 600, 'MG', 'LCCS')] },
    ];
    window.fetch = function (u, o) {
      const url = String(u);
      if (url.indexOf('api.nal.usda.gov') >= 0) {
        let body = {};
        try { body = JSON.parse(String((o && o.body) || '{}')); } catch (e) {}
        G.calls.push({ url: url, method: String((o && o.method) || 'GET'), query: String(body.query || ''), types: body.dataType });
        if (body.query === 'limitme') return Promise.resolve(new Response('{"error":{"code":"OVER_RATE_LIMIT"}}', { status: 429 }));
        return Promise.resolve(new Response(JSON.stringify({ totalHits: FOODS.length, foods: FOODS }),
          { status: 200, headers: { 'Content-Type': 'application/json' } }));
      }
      if (url.indexOf('/chat/completions') >= 0) {
        const content = JSON.stringify({ names: ['gate fish spread', 'smoked fish', 'fish pate', 'FOURTH'],
          per100: { kcal: 230, protein_g: 15, fat_g: 18, carb_g: 2, fiber_g: 0, soluble_fiber_g: 0 } });
        return Promise.resolve(new Response(JSON.stringify({ choices: [{ message: { content: content } }] }),
          { status: 200, headers: { 'Content-Type': 'application/json' } }));
      }
      return realFetch.apply(window, arguments);
    };
    const dk = HT.state().current;
    window.__dk = dk;
    const nItems = () => ((HT.state().days[dk] || {}).items || []).length;
    // -- no key: the Search pane says so and offers no button --
    HT.openSheet();
    all('#sheetRoot .srbtn').forEach(function (b) { if (b.textContent === 'Search') b.click(); });
    await window.__htQuiet(10000);
    const type = async (q) => { const f = $('#fqQuery'); f.value = q; f.dispatchEvent(new Event('input', { bubbles: true })); await window.__htQuiet(10000); };
    await type('gate stew');
    const r0 = String(($('#fqRows') || {}).innerHTML || '');
    ok(r0.indexOf('needs your own free key') > 0 && !$('#fqRows .fdcgo') && G.calls.length === 0,
       'NO KEY: Search says FoodData Central needs your own key, under Settings -- no button, no call', r0.replace(/<[^>]+>/g, ' ').slice(-200));
    // -- the key, through the Settings card --
    HT.closeSheet();
    HT.renderFdcKey();
    const K = 'GATEKEY0123456789abcdefGATEKEY0123456789';
    $('#fdcKeyIn').value = K;
    all('#fdcKeyBox button').filter(function (b) { return b.textContent === 'Save'; })[0].click();
    await window.__htQuiet(10000);
    const box = String($('#fdcKeyBox').innerHTML);
    ok(HT.fdcConfigured() && box.indexOf(K) < 0 && box.indexOf('saved:') > 0 && $('#fdcKeyIn').value === ''
       && String(localStorage.getItem(HT.FDC_LS)).indexOf(K) > 0,
       'SETTINGS: the key is saved on this device, shown only masked, and the field is emptied');
    ok(HT.exportJSON().indexOf(K) < 0 && String(localStorage.getItem(HT.keys.STORE_KEY) || '').indexOf(K) < 0,
       'SETTINGS: the key is in neither the log nor the export or backup');
    ok(box.indexOf('never included in an export or a backup') > 0 && box.indexOf('1,000 searches an hour') > 0 && box.indexOf('logs') > 0,
       'SETTINGS: it says where the key goes, that the service takes it in the search address and can log it, and the hourly allowance');
    // -- with a key: OFFERED, and typing never calls --
    HT.openSheet();
    all('#sheetRoot .srbtn').forEach(function (b) { if (b.textContent === 'Search') b.click(); });
    await window.__htQuiet(10000);
    await type('gate'); await type('gate stew');
    const go = $('#fqRows .fdcgo');
    ok(!!go && String(go.textContent).indexOf('Search USDA FoodData Central for \u201cgate stew\u201d') === 0 && G.calls.length === 0,
       'OFFERED: one button naming the words it will search -- and typing has sent NOTHING', go ? go.textContent : '(no button)');
    const before = nItems();
    go.click();
    await window.__htQuiet(10000);
    const c0 = G.calls[0] || {};
    ok(G.calls.length === 1 && c0.method === 'POST' && c0.url.indexOf('api_key=' + K) > 0 && c0.query === 'gate stew'
       && JSON.stringify(c0.types) === JSON.stringify(['Branded', 'Survey (FNDDS)']),
       'THE TAP: exactly one POST, the key as the service requires, the typed words, Branded and Survey (FNDDS) only', JSON.stringify(c0));
    const none = $('#fqRows .fdcnone'), rows = all('#fqRows .fdcrow');
    ok(!!none && rows.length === 2 && (none.compareDocumentPosition(rows[0]) & Node.DOCUMENT_POSITION_FOLLOWING),
       'RULED: "None of these fits" comes BEFORE the list');
    ok(rows.every(function (b) { return /cal/.test(b.textContent) && /P \d/.test(b.textContent); })
       && String(rows[0].textContent).indexOf('Typical recipe (Survey, FNDDS)') > 0 && String(rows[1].textContent).indexOf('Packaged food') > 0,
       'RULED: every row shows its kind and its macros', rows.map(function (b) { return b.textContent; }).join(' | '));
    ok(nItems() === before, 'SUGGESTIONS ONLY: rows arrived and nothing was logged or picked');
    window.__rowsBefore = before;
    const fz = function (sel) { const e = $(sel); return e ? parseFloat(getComputedStyle(e).fontSize) : 0; };
    ok(['#fqRows .fdcrow', '#fqRows .fdctype', '#fqRows .fdcmac', '#fqRows .fdccap', '#fqRows .fdcnone'].every(function (s) { return fz(s) >= 16; }),
       'every new text is at least 16px');
    rows[0].scrollIntoView({ block: 'center' });
  } catch (e) { ok(false, 'stage 1 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r1 = EvalAsyncB64 $js1
  if ($r1 -like 'EXCEPTION*') { $fails += "stage 1: $r1" }
  WaitQuiet 'after a step'
  Shot 'search-rows'

  # ---- stage 2: pick in Search, the amount, the log ---------------------------
  $js2 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  const $ = (s) => document.querySelector(s);
  try {
    const dk = window.__dk;
    document.querySelectorAll('#fqRows .fdcrow')[0].click();
    await window.__htQuiet(10000);
    const step = String(($('#searchBox') || {}).textContent || '');
    ok(step.indexOf('Typical recipe (Survey, FNDDS)') >= 0 && step.indexOf('Source: U.S. Department of Agriculture') >= 0
       && step.indexOf('retrieved') > 0 && step.indexOf('USDA FoodData Central, per 100 g') >= 0,
       'PICKED: the amount step names the kind of row and carries the citation with its retrieval date', step.slice(0, 300));
    const g = $('#fqGrams'); g.value = '200'; g.dispatchEvent(new Event('input', { bubbles: true }));
    await window.__htQuiet(10000);
    window.__shotStep = 1;
  } catch (e) { ok(false, 'stage 2 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r2 = EvalAsyncB64 $js2
  if ($r2 -like 'EXCEPTION*') { $fails += "stage 2: $r2" }
  Shot 'search-step'
  $js3 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  const $ = (s) => document.querySelector(s);
  try {
    const dk = window.__dk;
    $('#searchBox .fqlog').click();
    await window.__htQuiet(10000);
    const items = (HT.state().days[dk] || {}).items || [];
    const it = items[items.length - 1] || {};
    ok(items.length === window.__rowsBefore + 1 && it.source === 'corpus' && it.ref && it.ref.ns === HT.FDC_NS && it.ref.id === '9200001'
       && Math.abs(it.kcal - 240) < 1e-6 && Math.abs(it.ref.v['307'] - 600) < 1e-6 && String(it.ref.attribution).indexOf('retrieved') > 0,
       'LOGGED: 200 g of the picked row is 240 cal, the item cites FoodData Central with its retrieval date, and its sodium rides in the reference values', JSON.stringify({ kcal: it.kcal, ns: it.ref && it.ref.ns }));
    HT.closeSheet();
    // -- an error is said, and writes nothing --
    HT.openSheet();
    Array.prototype.slice.call(document.querySelectorAll('#sheetRoot .srbtn')).forEach(function (b) { if (b.textContent === 'Search') b.click(); });
    await window.__htQuiet(10000);
    const f = $('#fqQuery'); f.value = 'limitme'; f.dispatchEvent(new Event('input', { bubbles: true })); await window.__htQuiet(10000);
    const n0 = items.length;
    $('#fqRows .fdcgo').click(); await window.__htQuiet(10000);
    const er = String(($('#fqRows') || {}).textContent || '');
    ok(er.indexOf('hourly limit') > 0 && !!$('#fqRows .fdcgo') && ((HT.state().days[dk] || {}).items || []).length === n0,
       'REFUSED: the hourly limit is SAID, the search can be tried again, and nothing was written', er.slice(-160));
    HT.closeSheet();
  } catch (e) { ok(false, 'stage 3 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r3 = EvalAsyncB64 $js3
  if ($r3 -like 'EXCEPTION*') { $fails += "stage 3: $r3" }

  # ---- stage 4: the not-counted picker -----------------------------------------
  $js4 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  const $ = (s) => document.querySelector(s);
  try {
    const dk = window.__dk;
    const day = HT.state().days[dk];
    day.items.push(HT.normalizeItem({ name: 'gate stew', meal: 'dinner', time: '19:30', grams: 150, unresolved: true,
      source: 'ai-paste', confidence: 'eyeballed', notes: '' }, true));
    HT.resave(); HT.refresh();
    const idx = day.items.length - 1;
    window.__ridx = idx;
    const calls0 = G.calls.length;
    await HT.resolveOpen(dk, idx); await window.__htQuiet(10000);
    const go = $('#resolveBox .fdcgo');
    ok(!!go && String(go.textContent).indexOf('\u201cgate stew\u201d') > 0 && G.calls.length === calls0,
       'NOT COUNTED: the picker offers FoodData Central for the item\u2019s name -- and has sent nothing');
    go.click(); await window.__htQuiet(10000);
    ok(G.calls.length === calls0 && document.querySelectorAll('#resolveBox .fdcrow').length === 2,
       'the same words searched again this session are answered from memory -- no second call');
    $('#resolveBox .fdcnone').click(); await window.__htQuiet(10000);
    ok(!document.querySelector('#resolveBox .fdcrow') && !!$('#resolveBox .fdcgo') && HT.dayUncounted(dk).length >= 1,
       '"None of these fits" closes the rows, offers the search again, and leaves the item not counted');
    $('#resolveBox .fdcgo').click(); await window.__htQuiet(10000);
    document.querySelectorAll('#resolveBox .fdcrow')[0].scrollIntoView({ block: 'center' });
  } catch (e) { ok(false, 'stage 4 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r4 = EvalAsyncB64 $js4
  if ($r4 -like 'EXCEPTION*') { $fails += "stage 4: $r4" }
  Shot 'resolve-rows'
  $js5 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  try {
    const dk = window.__dk, idx = window.__ridx;
    const un0 = HT.dayUncounted(dk).length;
    document.querySelectorAll('#resolveBox .fdcrow')[1].click(); await window.__htQuiet(10000);
    const it = HT.state().days[dk].items[idx];
    ok(it.ref && it.ref.ns === HT.FDC_NS && it.ref.id === '9200002' && Math.abs(it.kcal - 375) < 1e-6
       && it.ref.v['205'] === undefined && HT.dayUncounted(dk).length === un0 - 1,
       'COUNTED: the picked packaged row counts the item at 375 cal for its 150 g by the precedence rule, and its "less than" carbohydrate stays absent', JSON.stringify({ kcal: it.kcal, carb: it.carb_g }));
  } catch (e) { ok(false, 'stage 5 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r5 = EvalAsyncB64 $js5
  if ($r5 -like 'EXCEPTION*') { $fails += "stage 5: $r5" }

  # ---- stage 6: the photo sheet, fed the AI's short names ----------------------
  $js6 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  const $ = (s) => document.querySelector(s);
  try {
    HT.byokSave('grok', 'xai-GATEFIXTURE0000000000000', 5);
    HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: [{ name: 'creamy fish thing on a cracker', grams: 80, notes: 'from the photo',
      alts: [{ name: 'creamy fish thing on a cracker', p: 0.5 }], per100: { kcal: 230, protein_g: 15, fat_g: 18, carb_g: 2, fiber_g: 0, soluble_fiber_g: 0 } }] }));
    await window.__htQuiet(10000);
    HT.photoSearchOpen(0);
    await HT.photoSearchRun(0, 'gate qxvz'); await window.__htQuiet(10000);
    const go0 = $('.pmsearch .fdcgo');
    ok(!!go0 && String(go0.textContent).indexOf('\u201cgate qxvz\u201d') > 0, 'PHOTO: with nothing found locally, FoodData Central is offered for the typed words');
    await HT.photoSearchAskModel(0); await window.__htQuiet(10000);
    const go = $('.pmsearch .fdcgo');
    const want = '\u201cgate fish spread, smoked fish, fish pate\u201d';
    ok(!!go && String(go.textContent).indexOf(want) > 0, 'PHOTO (R245): after your AI suggested names, FoodData Central is fed its SHORT names -- at most three', go ? go.textContent : '(none)');
    const calls0 = G.calls.length;
    go.click(); await window.__htQuiet(10000);
    const qs = G.calls.slice(calls0).map(function (c) { return c.query; });
    ok(JSON.stringify(qs) === JSON.stringify(['gate fish spread', 'smoked fish', 'fish pate']),
       'PHOTO: one call per name, three names, in the AI\u2019s order', JSON.stringify(qs));
    const blk = String(($('.pmsearch .fdcblock') || {}).innerHTML || '');
    ok(blk.indexOf('Yours, per 100 g') > 0 && blk.indexOf('230 cal') > 0 && blk.indexOf('None of these fits') < blk.indexOf('fdcrow')
       && document.querySelectorAll('.pmsearch .fdcrow').length === 2,
       'RULED: the item\u2019s own estimate is stated beside the FDC rows, and the exit is first');
    ok(!HT.photoDraft().items[0].ref, 'SUGGESTIONS ONLY: the rows are shown and the photo item has no row until one is tapped');
    document.querySelectorAll('.pmsearch .fdcrow')[1].scrollIntoView({ block: 'center' });
  } catch (e) { ok(false, 'stage 6 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r6 = EvalAsyncB64 $js6
  if ($r6 -like 'EXCEPTION*') { $fails += "stage 6: $r6" }
  Shot 'photo-rows'
  $js7 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  try {
    document.querySelectorAll('.pmsearch .fdcrow')[1].click(); await window.__htQuiet(10000);
    const it = HT.photoDraft().items[0];
    ok(it.ref && it.ref.ns === HT.FDC_NS && it.name === 'GATE SMOKED FISH SPREAD' && Math.abs(it.ref.v['208'] - 200) < 1e-6
       && Math.abs(it.per100.kcal - 250) < 1e-6 && !HT.photoSearchState(),
       'PHOTO PICKED: one tap gives the item the row\u2019s name and its numbers at the item\u2019s 80 g (200 cal), and closes the search', JSON.stringify({ name: it.name, per100: it.per100 && it.per100.kcal }));
    HT.photoDiscard && HT.photoDiscard();
  } catch (e) { ok(false, 'stage 7 threw', e && e.stack); }
  return { n: G.checks.length };
})()
'@
  $r7 = EvalAsyncB64 $js7
  if ($r7 -like 'EXCEPTION*') { $fails += "stage 7: $r7" }

  # ---- stage 8: R253/1 (the R238 bug) -- the keep button says what was TYPED ----
  # Before the fix this screen read "Use 'FOURTH' with no nutrition": the AI's last
  # suggested name, left in the field's text by the search of each name.
  $js8 = @'
(async function () {
  const G = window.__G, sleep = window.__sleep;
  const ok = (c, m, d) => G.checks.push({ ok: !!c, m: m, d: d === undefined ? '' : String(d).slice(0, 300) });
  const $ = (s) => document.querySelector(s);
  try {
    HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: [{ name: 'creamy fish thing', grams: 80, notes: 'from the photo',
      alts: [{ name: 'creamy fish thing', p: 0.5 }], per100: { kcal: 230, protein_g: 15, fat_g: 18, carb_g: 2, fiber_g: 0, soluble_fiber_g: 0 } }] }));
    await window.__htQuiet(10000);
    HT.photoSearchOpen(0);
    await HT.photoSearchRun(0, 'gate qxvz'); await window.__htQuiet(10000);
    await HT.photoSearchAskModel(0); await window.__htQuiet(10000);
    const st = HT.photoSearchState() || {};
    const keep = $('.pmsearch .pmskeep');
    const kt = String((keep && keep.textContent) || '');
    ok(st.normalised === true && st.asked && st.asked.length === 4,
       'R253/1 setup: your AI suggested four names and each was searched');
    ok(!!keep && kt.indexOf('\u201cgate qxvz\u201d') > 0 && kt.indexOf('FOURTH') < 0 && kt.indexOf('fish pate') < 0,
       'R253/1 GATE: after "Ask my AI for other names" the keep button names what YOU typed, not the AI\u2019s last name', kt);
    ok(String(($('#pmsQuery') || {}).value) === 'gate qxvz',
       'R253/1: the field still holds what you typed');
    keep.click(); await window.__htQuiet(10000);
    const it = HT.photoDraft().items[0];
    ok(it.name === 'gate qxvz' && it.unres === true && !it.ref,
       'R253/1 GATE: tapping it keeps YOUR words as the name, not counted', JSON.stringify({ name: it.name, unres: it.unres }));
    HT.photoDiscard && HT.photoDiscard();
  } catch (e) { ok(false, 'stage 8 threw', e && e.stack); }
  return { checks: G.checks };
})()
'@
  $r8 = EvalAsyncB64 $js8
  if ($r8 -like 'EXCEPTION*') { $fails += "stage 8: $r8"; $R = $null } else { $R = $r8 | ConvertFrom-Json }
  if ($R) {
    foreach ($c in $R.checks) {
      if ($c.ok) { Write-Host "  ok    $($c.m)" }
      else { Write-Host "  FAIL  $($c.m) $($c.d)"; $fails += $c.m }
    }
    if (@($R.checks).Count -lt 20) { $fails += "only $(@($R.checks).Count) checks ran -- a stage stopped early" }
  }
  if ($fails.Count) {
    Write-Host "FDC GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "FDC GATE: PASS -- $(@($R.checks).Count) checks on Search, the not-counted picker and the photo sheet, against a stubbed service"
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
