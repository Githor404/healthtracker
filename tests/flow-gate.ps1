# H16 / D123 -- THE FLOW GATE: each journey, as a tap count, on the shipped page.
#
# WHY THIS IS A CDP GATE AND NOT A HARNESS CASE. A tap count is a property of the
# PAGE -- of which controls exist, which are reachable, and what a click on a real
# element actually does. The harness can assert the seams underneath (dayJump
# refuses a bad key, a visited day is not created, the panel remembers its state)
# and it does. It cannot assert "this took four taps", because nothing in a
# DOM-free core knows what a tap is.
#
# WHAT IT PINS, and every number here was MEASURED on the shipped page first:
#   J0  a day 15 days back: was 15 taps, one per day, no other route -> <= 2
#   J1  eat -> logged -> I see my day: 4
#   J2  a dose -> logged -> on the timeline: 4, and the dose is IN VIEW
#   J3  a medication from its label -> saved -> drug info: was 8 -> 6
#   J4  an old item -> resolved -> in the panel: 3, the third OFFERED not hunted
#
# This gate FAILS BY NAME whenever a journey grows a tap. That is intended, and
# ruled: flow is not a thing asserted once and trusted afterwards -- it is a
# number that drifts, one plausible control at a time, and nothing else in the
# suite would notice.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8161
$origin = "http://127.0.0.1:$port"
$dbg = 9367
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-flowgate-" + [System.Guid]::NewGuid().ToString('N'))
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
  # A phone, because "where the thumb has to travel" is half of what is measured.
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $script = @'
(async function () {
  const out = {};
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  let taps = 0;
  function tap(el, why) {
    if (!el) throw new Error('nothing to tap: ' + why);
    taps++; el.click();
  }
  function byText(sel, re, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel))
      .filter(e => re.test((e.textContent || '').trim()))[0] || null;
  }
  function sheetOpen() {
    const s = document.getElementById('entrySheet');
    return !!s && s.style.display !== 'none';
  }
  function shut() { if (sheetOpen()) HT.closeSheet(); }

  HT.boot();
  HT.byokPatch({ provider: 'grok', key: 'xai-flowgatestub00000000000000',
                 status: { state: 'verified', at: '', message: '' } });
  const today = HT.localDate();
  for (let i = 0; i <= 20; i++) {
    const d = HT.shiftDate(today, -i);
    HT.state().days[d] = HT.state().days[d] || { status: 'in_progress', water_l: 0, items: [] };
  }
  const OLD = HT.shiftDate(today, -15);
  HT.state().days[OLD].items = [{ name: 'lentil soup', meal: 'lunch', time: '12:30', grams: 300,
    kcal: 230, protein_g: 12, fat_g: 4, carb_g: 34, fiber_g: 8, soluble_fiber_g: 2,
    confidence: 'eyeballed', source: 'manual', notes: '' }];
  HT.state().current = today;
  HT.refresh();
  await sleep(200);

  // ---- JOURNEY 0: a past day, and I am on it ------------------------------
  // Was FIFTEEN taps, one per day, with no other route.
  taps = 0;
  const picker = document.querySelector('.daysel .dayjump');
  out.pickerFound = !!picker;
  if (picker) {
    taps++;                              // tap 1: the date itself
    picker.value = OLD;
    picker.dispatchEvent(new Event('change', { bubbles: true }));
    taps++;                              // tap 2: the day, in the OS picker
    await sleep(250);
  }
  out.j0 = { taps: taps, arrived: HT.state().current === OLD };

  // the same jump to a day NOTHING was ever written to -- and it must stay written-to-nothing
  const VOID = HT.shiftDate(today, -9);
  delete HT.state().days[VOID];
  HT.refresh(); await sleep(120);
  taps = 0;
  const p2 = document.querySelector('.daysel .dayjump');
  if (p2) { taps++; p2.value = VOID; p2.dispatchEvent(new Event('change', { bubbles: true })); taps++; await sleep(250); }
  out.j0void = { taps: taps, arrived: HT.state().current === VOID,
                 created: !!HT.state().days[VOID],
                 dayViewDrawn: (document.getElementById('dayView').innerHTML || '').length > 80,
                 backEnabled: !(document.querySelector('.daynav .navbtn') || {}).disabled };
  // the history list is the second route, and it used to be inert
  out.historyTappable = !!document.querySelector('.hrow[onclick]');

  HT.state().current = today; HT.refresh(); await sleep(150);

  // ---- JOURNEY 1: I eat something -> logged -> I see my day ---------------
  taps = 0;
  const n1 = (HT.state().days[today].items || []).length;
  tap(document.getElementById('fab'), 'FAB');
  await sleep(180);
  tap(document.getElementById('mode-manual'), 'Manual');
  await sleep(180);
  document.getElementById('maName').value = 'Greek yogurt';
  document.getElementById('maKcal').value = '120';
  tap(byText('#pane-manual button', /^Add to day$/i), 'Add to day');
  await sleep(300);
  const nm1 = document.querySelector('#maNext .nmbtn');
  out.j1 = { offered: !!nm1, said: (document.querySelector('#maNext .nmsaid') || {}).textContent || '',
             logged: (HT.state().days[today].items || []).length > n1 };
  if (nm1) { tap(nm1, 'See my day'); await sleep(250); }
  out.j1.taps = taps;
  out.j1.sheetClosed = !sheetOpen();
  shut();

  // ---- JOURNEY 2: a dose -> logged -> on the timeline ---------------------
  taps = 0;
  tap(document.getElementById('fab'), 'FAB');
  await sleep(180);
  tap(byText('.sheetfoot .linklike', /Log a dose I took/i), 'Log a dose I took');
  await sleep(200);
  document.getElementById('medName').value = 'Metformin';
  tap(byText('#pane-med button', /^Log this dose$/i), 'Log this dose');
  await sleep(300);
  const nm2 = document.querySelector('#medNext .nmbtn');
  out.j2 = { offered: !!nm2 };
  if (nm2) { tap(nm2, 'See it on the timeline'); await sleep(400); }
  out.j2.taps = taps;
  out.j2.sheetClosed = !sheetOpen();
  // The row must carry THIS dose's id. `.tlrow[data-sid]` was not enough: the
  // attribute is rendered either way, so a row whose id went missing still
  // matched on the attribute's PRESENCE and the gate could not tell the two
  // apart (measured -- the plant that nulled the id failed nothing). Match the
  // VALUE against the record the app actually stored.
  const dayKey2 = HT.state().current;
  const tl2 = (HT.state().timeline || {})[dayKey2] || [];
  let medIdx2 = -1;
  tl2.forEach(function (s, i) { if (s && s.kind === 'medication') medIdx2 = i; });
  let tlrow = null;
  if (medIdx2 >= 0) {
    Array.prototype.slice.call(document.querySelectorAll('.tlrow')).forEach(function (r) {
      if (!tlrow && r.getAttribute('data-sidx') === String(medIdx2)) tlrow = r;
    });
  }
  out.j2.rowIdentified = !!tlrow;
  out.j2.rowInView = (function () {
    if (!tlrow) return false;
    const r = tlrow.getBoundingClientRect();
    return r.top >= -4 && r.top <= window.innerHeight;
  })();
  // Did the ending FIND this dose, or did it fall back? flashEl marks the ROW it
  // found, and the whole card when it found nothing -- so the two are
  // distinguishable, and only that tells them apart. "A row exists and something
  // scrolled" was true either way: measured, an offer pointing at no record at
  // all passed, because the fallback brings the card into view and the row is at
  // the top of it.
  out.j2.rowFlashed = !!(tlrow && tlrow.classList.contains('flash'));
  out.j2.fellBack = !!((document.getElementById('timelineOverlay') || { classList: { contains: function () { return false; } } })
                        .classList.contains('flash'));
  shut();

  // ---- JOURNEY 3: a medication from its label -> saved -> drug info -------
  taps = 0;
  tap(document.getElementById('fab'), 'FAB');
  await sleep(180);
  tap(byText('.sheetfoot .linklike', /Add a medication from its label/i), 'Add a medication from its label');
  await sleep(250);
  taps++;                                 // Take photo; the shutter itself is the OS
  HT.openLabelDraft(JSON.stringify({ name: 'Metformin', generic_name: 'metformin hydrochloride',
    strength: '500 mg', directions: 'Take one tablet twice daily with food' }),
    { whose: 'mine', source: 'label-photo' });
  await sleep(250);
  tap(byText('.pmok, button', /that.s what it says/i), 'confirm');
  await sleep(250);
  tap(byText('button', /^Save to my medications$/i), 'Save to my medications');
  await sleep(350);
  const nm3 = document.querySelector('#labelNext .nmbtn');
  out.j3 = { offered: !!nm3, saved: HT.medList(false).length };
  if (nm3) { tap(nm3, 'Drug info'); await sleep(350); }
  out.j3.taps = taps;
  out.j3.settingsOpen = (document.getElementById('settingsPanel') || {}).style.display === 'flex';
  out.j3.medsExpanded = !!(document.getElementById('medsDetails') || {}).open;
  out.j3.drugAimed = !!(HT.drugView() && HT.drugView().medId);
  HT.closeSettings(); shut();

  // ---- JOURNEY 4: an old item -> resolved -> seen in the panel ------------
  HT.dayJump(OLD); await sleep(200);
  window.scrollTo(0, 0); await sleep(60);
  taps = 0;
  tap(byText('.rchip, button', /find nutrients/i), 'find nutrients');
  for (let w = 0; w < 40 && !document.querySelector('.rcandbtn'); w++) await sleep(500);
  const cands = document.querySelectorAll('.rcandbtn');
  out.j4 = { candidates: cands.length };
  if (cands.length) { tap(cands[0], 'pick'); await sleep(900); }
  const nm4 = document.querySelector('.nextmove .nmbtn');
  out.j4.offered = !!nm4;
  if (nm4) { tap(nm4, 'See it in the panel'); await sleep(350); }
  out.j4.taps = taps;
  const mp = document.querySelector('details.mpanel');
  out.j4.panelOpen = !!(mp && mp.open);
  // and it STAYS open across a refresh -- it used to close itself on every one,
  // which is what made it unreachable as a destination
  HT.refresh(); await sleep(150);
  const mp2 = document.querySelector('details.mpanel');
  out.j4.panelSurvivesRefresh = !!(mp2 && mp2.open);

  // the constraints, on every ending the page can show at once
  const nmAll = Array.prototype.slice.call(document.querySelectorAll('.nextmove'))
    .map(e => (e.textContent || '').toLowerCase()).join(' ');
  out.noNag = (nmAll.indexOf('streak') < 0 && nmAll.indexOf('remaining') < 0 &&
               nmAll.indexOf('to go') < 0 && nmAll.indexOf('keep it up') < 0);
  return JSON.stringify(out);
})()
'@
  $r = EvalAsync $script
  if ($r -like 'EXCEPTION*') { $fails += "the page threw: $r" }
  $J = if ($r -like 'EXCEPTION*') { [pscustomobject]@{} } else { $r | ConvertFrom-Json }

  # --- the pinned tap counts ------------------------------------------------
  # These fail BY NAME when a journey grows a tap. That is the point of the gate:
  # flow is not a thing you assert once and trust, it is a number that drifts.
  if (-not $J.pickerFound) { $fails += "J0: there is no date control on the day header at all" }
  if ($J.j0.taps -gt 2 -or -not $J.j0.arrived) {
    $fails += "J0: a day 15 days back took $($J.j0.taps) taps (pinned <= 2; it was 15, one per day)" }
  if ($J.j0void.taps -gt 2 -or -not $J.j0void.arrived) {
    $fails += "J0: a day with NO RECORD took $($J.j0void.taps) taps (pinned <= 2)" }
  if ($J.j0void.created) {
    $fails += "J0: VISITING a day CREATED it -- day creation injects the supplement (D8/4), so this puts real intake on a day only looked at" }
  if (-not $J.j0void.dayViewDrawn) { $fails += "J0: an unlogged day rendered a BLANK SCREEN instead of an empty day" }
  if (-not $J.j0void.backEnabled) { $fails += "J0: both arrows were disabled on an unlogged day -- the thumb is stranded where the jump left it" }
  if (-not $J.historyTappable) { $fails += "J0: the history rows are inert -- the date picker cannot say which days have data, which is why they are the second route" }

  if ($J.j1.taps -ne 4 -or -not $J.j1.logged) {
    $fails += "J1: eat -> logged -> see my day took $($J.j1.taps) taps (pinned 4)" }
  if (-not $J.j1.offered) { $fails += "J1: nothing was offered after the add -- the sheet stays open and the x is a dismiss, not a destination" }
  if (-not $J.j1.sheetClosed) { $fails += "J1: the offer did not land on the day" }

  if ($J.j2.taps -ne 4) { $fails += "J2: a dose -> on the timeline took $($J.j2.taps) taps (pinned 4)" }
  if (-not $J.j2.offered) { $fails += "J2: nothing was offered after the dose -- measured, the timeline is 1.8 screens below the fold" }
  if (-not $J.j2.rowIdentified) { $fails += "J2: the timeline row carries no record id, so the ending cannot find THIS dose" }
  if (-not $J.j2.rowInView) { $fails += "J2: the offer did not bring the dose into view -- the outcome is still unseen" }
  if (-not $J.j2.rowFlashed) { $fails += "J2: the offer did not FIND this dose -- it marked nothing, or fell back to the whole card" }
  if ($J.j2.fellBack) { $fails += "J2: the offer FELL BACK to the timeline card, which is the behaviour for a dose it could not find" }

  if ($J.j3.taps -ne 6) { $fails += "J3: a medication -> drug info took $($J.j3.taps) taps (pinned 6; it was 8)" }
  if ($J.j3.saved -lt 1) { $fails += "J3: the medication did not save" }
  if (-not $J.j3.offered) { $fails += "J3: nothing was offered after the save -- its information was three taps away inside Settings" }
  if (-not $J.j3.settingsOpen -or -not $J.j3.medsExpanded -or -not $J.j3.drugAimed) {
    $fails += "J3: the offer did not reach the drug surface for the medication just saved" }

  if ($J.j4.candidates -lt 1) { $fails += "J4: the resolve step offered nothing, so the journey could not be measured" }
  if ($J.j4.taps -ne 3) { $fails += "J4: an old item -> panel took $($J.j4.taps) taps (pinned 3 -- the third is OFFERED now, not hunted)" }
  if (-not $J.j4.offered) { $fails += "J4: nothing was offered after the pick -- the panel is closed by default and 0.9 screens down" }
  if (-not $J.j4.panelOpen) { $fails += "J4: the offer did not open the panel" }
  if (-not $J.j4.panelSurvivesRefresh) { $fails += "J4: the panel closed itself on a refresh -- it cannot be a destination if anything that writes shuts it" }

  if (-not $J.noNag) { $fails += "an ending carried a streak, a nudge or a distance to target -- flow moves forward, it does not pull back" }
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "FLOW GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host "FLOW GATE: PASS -- J0 <=2 (was 15), J1 4, J2 4, J3 6 (was 8), J4 3, and every ending shows its outcome"
exit 0
