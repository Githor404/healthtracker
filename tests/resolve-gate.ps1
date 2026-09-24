# D125 -- A RESOLVE THE USER DID NOT MAKE: the tap point, and the two fixtures.
#
# Reported from the device: "wood ear mushrooms" carried a match to "Tomato
# products, canned, sauce with mushrooms" that was never chosen.
#
# MEASURED, on the device's exact shape at 390x844, before the fix:
#   - the distance from the point the "find nutrients" chip was tapped to the
#     nearest candidate row was ZERO -- a row covered the tap exactly
#   - the list appeared 0 ms after the tap (the corpus is hydrated, so the
#     render is synchronous)
#   - the covering row was ENABLED the instant it appeared
# One tap opens the list, the second tap of a double-tap resolves it.
#
# And the list itself was wrong: the matcher returned the two CORRECT rows first
# (Jew's ear, raw/dried -- the corpus carries wood ear under its other name), and
# D122's state rank buried both, because each STATES a state mismatching an
# INFERRED "cooked" while a tomato sauce and a Spanish omelet state none and so
# ranked as merely unknown. The right answers were demoted for being specific.
#
# BOTH FIXTURES ARE GATED TOGETHER, and that is the point: wood ear (the correct
# rows stay at the top) and ramen (the dry rows are still labelled, with the kcal
# pair visible). A fix that passes one and fails the other is the regression.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8167
$origin = "http://127.0.0.1:$port"
$dbg = 9373
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-resolvegate-" + [System.Guid]::NewGuid().ToString('N'))
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
if (-not (Test-Path (Join-Path $repo 'corpus/dist/fdc.bin'))) {
  Write-Host "ERROR: corpus/dist/fdc.bin is missing -- run corpus/encode.py first"; exit 2
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
  $args = @("--headless=new", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $args -PassThru
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
  # Both reported cases came from `cnf`, so both are driven there.
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $script = @'
(async function () {
  const out = {};
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  function chipFor(re) {
    let c = null;
    Array.prototype.slice.call(document.querySelectorAll('.mitem')).forEach(function (row) {
      if (!c && re.test(row.textContent || '')) c = row.querySelector('.rchip');
    });
    return c;
  }
  function rows() { return Array.prototype.slice.call(document.querySelectorAll('.rcandbtn')); }
  function overlaps(a, b) { return a.bottom >= b.top && a.top <= b.bottom; }

  HT.boot();
  const DK = '2026-09-08', MEAL = 'pmmttavodn_ektw';
  const mk = (name, grams, kcal) => ({ name: name, meal: 'lunch', time: '12:30', grams: grams,
    kcal: kcal, protein_g: 1, fat_g: 1, carb_g: 1, fiber_g: 1, soluble_fiber_g: 0,
    confidence: 'eyeballed', source: 'ai-paste', notes: '', mealId: MEAL });
  HT.state().days[DK] = { status: 'in_progress', water_l: 0, items: [
    mk('wood ear mushrooms', 28, 8), mk('ramen noodles', 270, 370)] };
  HT.state().current = DK;
  HT.refresh();
  await sleep(200);
  await HT.corpusEnsure();
  await sleep(400);
  out.ns = HT.corpusNamespace();

  // ---- FIXTURE 1: wood ear -- the correct rows must stay at the top --------
  const chip = chipFor(/wood ear/i);
  if (!chip) { out.err = 'no wood ear chip'; return JSON.stringify(out); }
  chip.scrollIntoView({ block: 'center' });
  await sleep(200);
  const chipBox = chip.getBoundingClientRect();
  out.chipY = Math.round(chipBox.top + chipBox.height / 2);
  chip.click();
  for (let i = 0; i < 60 && !rows().length; i++) await sleep(25);
  await sleep(30);

  const r1 = rows();
  out.woodRows = r1.slice(0, 4).map(b => (b.textContent || '').trim().slice(0, 46));
  out.woodTopTwoAreCorrect = /jew.s ear/i.test(out.woodRows[0] || '') && /jew.s ear/i.test(out.woodRows[1] || '');
  out.woodHedged = r1.some(b => /probably cooked/i.test(b.textContent || ''));
  out.woodKcalShown = r1.every(b => /kcal\/100g/i.test(b.textContent || ''));

  // ---- THE SHIELD, as a distance ------------------------------------------
  // Measured before the fix: the distance from the tap to the nearest resolve
  // control was 0 px -- a row covered the tap exactly, enabled, 0 ms after it.
  let covering = null, nearestEnabledPx = 99999;
  r1.forEach(function (b) {
    const r = b.getBoundingClientRect();
    if (overlaps(r, chipBox) && !covering) covering = b;
    if (!b.disabled) {
      const d = overlaps(r, chipBox) ? 0
        : Math.round(Math.min(Math.abs(chipBox.top - r.bottom), Math.abs(r.top - chipBox.bottom)));
      if (d < nearestEnabledPx) nearestEnabledPx = d;
    }
  });
  out.aRowCoversTheTap = !!covering;          // the hazard must still exist (D96)
  out.coveringDisabled = !!(covering && covering.disabled);
  out.nearestEnabledPx = nearestEnabledPx;

  // a tap at that point must not resolve
  const before = !!(HT.state().days[DK].items[0].ref);
  if (covering) covering.click();
  await sleep(250);
  out.resolvedByShieldedTap = !!(HT.state().days[DK].items[0].ref) && !before;

  // and the shield LIFTS -- nothing is permanently harder to reach
  await sleep(HT.RESOLVE_ARM_MS + 400);
  const r2 = rows();
  out.liftedAfterWindow = r2.length > 0 && r2.every(b => !b.disabled);

  // a deliberate tap now resolves, and the record says how and when.
  // Guarded, because a run where the shield is ABSENT has already resolved the
  // item and closed the sheet by now -- and a gate that throws here stops before
  // the ramen fixture, which is the half the ruling says must be judged with it.
  const want = r2.filter(b => /jew.s ear/i.test(b.textContent || ''))[0] || r2[0];
  if (want) { want.click(); await sleep(900); }
  else { out.noRowsToPick = true; }
  const ref = HT.state().days[DK].items[0].ref;
  out.resolvedAfterLift = !!ref;
  out.refName = ref ? String(ref.name || '') : '';
  out.refHow = ref ? String(ref.how || '') : '';
  out.refAtMs = ref ? ref.at_ms : null;
  out.refAt = ref ? String(ref.at || '') : '';

  // ---- FIXTURE 2: ramen -- D122's case must not regress --------------------
  HT.closeSheet();
  await sleep(200);
  const chip2 = chipFor(/ramen/i);
  if (!chip2) { out.err2 = 'no ramen chip'; return JSON.stringify(out); }
  chip2.scrollIntoView({ block: 'center' });
  await sleep(250);
  chip2.click();
  for (let i = 0; i < 60 && !rows().length; i++) await sleep(25);
  await sleep(HT.RESOLVE_ARM_MS + 300);
  const r3 = rows();
  out.ramenRows = r3.slice(0, 4).map(b => (b.textContent || '').trim().slice(0, 46));
  out.ramenHasDry = r3.some(b => /\bdry\b/i.test(b.textContent || ''));
  out.ramenHedged = r3.some(b => /probably cooked/i.test(b.textContent || ''));
  out.ramenKcalShown = r3.every(b => /kcal\/100g/i.test(b.textContent || ''));
  out.ramenNoScore = !r3.some(b => /%/.test(b.textContent || ''));
  return JSON.stringify(out);
})()
'@
  $r = EvalAsync $script
  if ($r -like 'EXCEPTION*') { $fails += "the page threw: $r" }
  $R = if ($r -like 'EXCEPTION*') { [pscustomobject]@{} } else { $r | ConvertFrom-Json }

  if ($R.err) { $fails += "setup: $($R.err)" }
  if ($R.ns -ne 'cnf') { $fails += "the Canadian namespace was NOT driven (ns=$($R.ns)) -- both reported cases came from it" }

  # --- the hazard must still be possible, or the gate proves nothing (D96) ---
  if (-not $R.aRowCoversTheTap) {
    $fails += "no candidate row lands on the tap point any more, so this gate can no longer see the defect it exists for"
  }
  if (-not $R.coveringDisabled) { $fails += "the row covering the tap point is LIVE -- a second tap resolves an item the user never chose" }
  if ($R.resolvedByShieldedTap) { $fails += "a tap at the coordinates of the opening tap RESOLVED the item" }
  if ($R.nearestEnabledPx -lt 1) { $fails += "the nearest ENABLED resolve control is $($R.nearestEnabledPx)px from the tap -- it must not cover it" }
  if (-not $R.liftedAfterWindow) { $fails += "the shield never lifted -- the list must be fully usable a blink later" }
  if (-not $R.resolvedAfterLift) { $fails += "a deliberate tap after the window did not resolve" }

  # --- fixture 1: the correct rows stay at the top ---------------------------
  if (-not $R.woodTopTwoAreCorrect) {
    $fails += "wood ear: the two correct rows are not at the top (got: $($R.woodRows -join ' | '))" }
  if (-not $R.woodHedged) { $fails += "wood ear: a mismatch against a GUESSED state is not labelled 'probably'" }
  if (-not $R.woodKcalShown) { $fails += "wood ear: a row is missing its kcal per 100 g" }

  # --- the record can testify ------------------------------------------------
  if ($R.refHow -ne 'picked') { $fails += "the record does not say it was PICKED (how='$($R.refHow)')" }
  if (-not $R.refAtMs) { $fails += "the record carries no time, only the date '$($R.refAt)' -- it cannot be ordered against another resolve" }

  # --- fixture 2: ramen must not regress ------------------------------------
  if ($R.err2) { $fails += "ramen setup: $($R.err2)" }
  if (-not $R.ramenHasDry) { $fails += "ramen: no dry row offered, so this fixture cannot show the regression it guards" }
  if (-not $R.ramenHedged) { $fails += "ramen: the dry rows are NOT labelled -- this is the case D122 exists for" }
  if (-not $R.ramenKcalShown) { $fails += "ramen: the kcal pair is missing, which is what made the dry rows obvious" }
  if (-not $R.ramenNoScore) { $fails += "ramen: a score appeared on a row (C1 holds)" }
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "RESOLVE GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host "RESOLVE GATE: PASS -- the tap point is shielded and lifts; wood ear keeps its correct rows on top; ramen still says dry; the record says how and when"
exit 0
