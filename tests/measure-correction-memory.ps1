# MEASURE FIRST: does memory miss a correction because it keys on the ACCEPTED
# name while the next capture arrives under the MODEL's name?
#
# Device finding: the same glass of white wine photographed on four days. The model
# offers "apple juice" or "broth" every time; the correction is never found.
#
# This measures, against the REAL corpus index (so the two-rarest-token key is the
# real one, not the no-index fallback):
#
#   1. matchKey('apple juice') vs matchKey('white wine')     -- do they differ?
#   2. rememberedRow('apple juice') after a corrected item   -- does it MISS?
#   3. rememberedRow('white wine')  on the same log          -- does it HIT?
#      (3 is the control: without it, a miss in 2 could mean memory is broken
#       outright rather than keyed on the wrong name.)
#   4. is the model's own name retained on the item at all?  -- ai_identity
#   5. and how many DISTINCT model names one food attracts, which decides whether
#      a correction memory keyed on the model's name can ever accumulate a count.
#
# Nothing is asserted here and nothing is fixed. Exit 0 always unless the probe
# could not run: this is a measurement, and a measurement that fails its own
# expectation is a finding, not an error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repo 'app.js'))) { $repo = 'C:\Users\thoma\projects\healthtracker' }
$Port = 8291
$Dbg = 9497
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-measure-" + [System.Guid]::NewGuid().ToString('N'))
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
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000
  $sane = Eval "typeof HT"
  if ($sane -ne 'object') { Write-Host "ERROR: page did not load (typeof HT = $sane)"; Cleanup; exit 2 }

  $probe = @'
window.__out = null; window.__stage = 'start';
(async function () {
  const O = { keys: {}, miss: {}, hit: {}, stored: {}, spread: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  try {
  HT.setClock(function () { return Date.parse('2026-10-09T12:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);
  O.ns = HT.corpusNamespace();
  O.indexReady = HT.matchIndexReady();

  // ---- 1. the two keys, from the REAL index -------------------------------
  const MODEL = ['apple juice', 'broth', 'chicken broth', 'apple cider'];
  const MINE = 'white wine';
  O.keys.mine = HT.matchKey(MINE);
  O.keys.model = MODEL.map(function (m) { return m + ' -> ' + HT.matchKey(m); });
  O.keys.anyEqual = MODEL.some(function (m) { return HT.matchKey(m) === HT.matchKey(MINE); });
  O.keys.sharedTokens = MODEL.map(function (m) {
    const a = HT.matchTokens(m), b = HT.matchTokens(MINE);
    return m + ' shares [' + a.filter(function (t) { return b.indexOf(t) >= 0; }).join(',') + ']';
  });

  // ---- the fixture: FOUR corrections, exactly as reported ----------------
  // Each day: the model said something, the user accepted a wine row. The item
  // carries the ACCEPTED name and -- per app.js:502 -- the model's name too.
  const S = HT.state();
  const wineId = '2117';             // filled in below from the real corpus
  const rows = HT.matchSearch ? null : null;
  // find a real wine row by name so the ref is not invented
  let found = null;
  const probe2 = HT.resolveSearch ? null : null;
  O.stage = 'find-wine';
  const cands = (typeof HT.matchLookup === 'function') ? HT.matchLookup('wine') : null;
  O.wineLookup = cands ? JSON.stringify(cands).slice(0, 200) : 'no matchLookup';

  const days = ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08'];
  days.forEach(function (d, i) {
    S.days[d] = { status: 'complete', water_l: 0, items: [ {
      name: MINE, meal: 'drink', time: '19:00', grams: 150,
      kcal: 123, protein_g: 0.1, fat_g: 0, carb_g: 3.8, fiber_g: 0, soluble_fiber_g: 0,
      confidence: 'eyeballed', source: 'ai-paste', notes: '',
      ai_identity: MODEL[i],                       // what the model called it
      identity_pick: { kind: 'search' },
      ref: { ns: HT.corpusNamespace(), id: '9001', name: 'Wine, table, white',
             at: d, at_ms: 1, hash: 'h', how: 'picked', g: 150,
             attribution: 'fixture', v: { '221': 15.4 } }
    } ] };
  });
  S.current = days[3];
  HT.Store.saveState(S);
  await sleep(200);

  // ---- 2. THE MISS: the next capture arrives under the model's name -------
  O.stage = 'miss';
  O.miss.byModelName = MODEL.map(function (m) {
    const r = HT.rememberedRow(m);
    return m + ' -> ' + (r ? ('HIT ' + r.name) : 'MISS');
  });
  O.miss.allMiss = MODEL.every(function (m) { return HT.rememberedRow(m) === null; });

  // ---- 3. THE CONTROL: memory is not broken, it is keyed on the other name
  O.stage = 'hit';
  const byMine = HT.rememberedRow(MINE);
  O.hit.byAcceptedName = byMine ? ('HIT ' + byMine.name + ' (from ' + byMine.fromName + ')') : 'MISS';
  O.hit.works = !!byMine;

  // ---- 4. is the model's name retained through normalize + save/restore? --
  O.stage = 'stored';
  const back = HT.state().days[days[0]].items[0];
  O.stored.aiIdentity = String(back.ai_identity || '');
  O.stored.name = String(back.name || '');
  const round = HT.normalizeItem(back);
  O.stored.survivesNormalize = String(round.ai_identity || '');
  O.stored.pickKind = round.identity_pick ? round.identity_pick.kind : null;

  // ---- 5. how many DISTINCT model names does one food attract? -----------
  O.stage = 'spread';
  const seen = {};
  Object.keys(HT.state().days).forEach(function (d) {
    (HT.state().days[d].items || []).forEach(function (it) {
      if (it && it.ai_identity) seen[HT.matchKey(it.ai_identity)] = (seen[HT.matchKey(it.ai_identity)] || 0) + 1;
    });
  });
  O.spread.distinctModelKeys = Object.keys(seen).length;
  O.spread.counts = JSON.stringify(seen);

  } catch (e) { O.threw = String((e && e.message) || e) + ' @ ' + O.stage; }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  $kick = Eval $probe
  if ($kick -ne '1') { Write-Host "ERROR: probe would not start: $kick"; Cleanup; exit 2 }
  $r = $null
  for ($w = 0; $w -lt 100; $w++) { Start-Sleep -Milliseconds 500; $r = Eval 'window.__out'; if ($r) { break } }
  if (-not $r) { Write-Host "ERROR: probe hung at stage $(Eval 'String(window.__stage)')"; Cleanup; exit 2 }
  $M = $r | ConvertFrom-Json
  if ($M.threw) { Write-Host "PROBE THREW: $($M.threw)" }

  Write-Host ""
  Write-Host "=== CORRECTION MEMORY: MEASURED ==================================="
  Write-Host "namespace $($M.ns), match index ready: $($M.indexReady)"
  Write-Host ""
  Write-Host "1. THE KEYS (real corpus, two-rarest-token key)"
  Write-Host "   accepted name 'white wine' -> '$($M.keys.mine)'"
  foreach ($k in $M.keys.model) { Write-Host "   $k" }
  Write-Host "   any model key equals the accepted key: $($M.keys.anyEqual)"
  foreach ($k in $M.keys.sharedTokens) { Write-Host "   $k" }
  Write-Host ""
  Write-Host "2. THE MISS -- four corrections in the log, next capture by model name"
  foreach ($k in $M.miss.byModelName) { Write-Host "   $k" }
  Write-Host "   every model name misses: $($M.miss.allMiss)"
  Write-Host ""
  Write-Host "3. THE CONTROL -- the same log, queried by the ACCEPTED name"
  Write-Host "   'white wine' -> $($M.hit.byAcceptedName)"
  Write-Host "   so memory itself works: $($M.hit.works)"
  Write-Host ""
  Write-Host "4. IS THE MODEL'S NAME ALREADY ON THE ITEM?"
  Write-Host "   item.name        = '$($M.stored.name)'"
  Write-Host "   item.ai_identity = '$($M.stored.aiIdentity)'"
  Write-Host "   survives normalizeItem: '$($M.stored.survivesNormalize)'"
  Write-Host "   identity_pick.kind     = '$($M.stored.pickKind)'"
  Write-Host ""
  Write-Host "5. DISTINCT MODEL NAMES FOR ONE FOOD (decides whether a count can accumulate)"
  Write-Host "   distinct model-name keys across 4 captures: $($M.spread.distinctModelKeys)"
  Write-Host "   counts: $($M.spread.counts)"
  Write-Host "==================================================================="
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup
exit 0
