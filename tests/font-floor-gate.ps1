# D124 -- THE 16px FLOOR, MEASURED AS COMPUTED SIZES ON THE SHIPPED PAGE.
#
# WHY THIS GATE EXISTS. D100 ruled a 16px floor and rebuilt 160 declarations to
# reach it: 719 elements under 16px went to 0, and 254 of 262 form controls did
# too -- the latter because a control under 16px makes iOS zoom the viewport on
# focus, which is BEHAVIOUR, not typography. The ruling was implemented and then
# left ungated. Four days after it was confirmed on the device, two new rules at
# 15px went in and nothing in the suite noticed. That is D121's finding again: a
# ruling implemented but ungated survives only until someone edits the line.
#
# WHY COMPUTED, NOT A GREP OF DECLARATIONS. <small> is the proof, and it is why
# D99 exists: the UA stylesheet sizes <small>, <sub> and <sup> RELATIVELY (0.8em),
# so they sat under the floor with NO DECLARATION ANYWHERE to grep for. A search
# of the stylesheet would have reported a clean sheet. Only the computed size on
# a rendered page can see it.
#
# WHAT IT SWEEPS. The app driven into as much of itself as one page can hold:
# a day with food rows, a timeline with three kinds of record, the medication
# list, every sheet mode, the settings panel, and every <details> forced open.
# The coverage is asserted BEFORE the floor is -- a sweep that reached nothing
# would otherwise pass for the wrong reason, which is the shape D96 warns about.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8163
$origin = "http://127.0.0.1:$port"
$dbg = 9369
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-floorgate-" + [System.Guid]::NewGuid().ToString('N'))
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
# ---- R283: every wait is a wait ON A CONDITION (tests/lib/quiet.js) -------------------
# No fixed sleep stands for "long enough". The page counts its own async work in flight;
# WaitQuiet returns when none is and the DOM has been still for two frames, WaitBoot when
# the NEW page's app is up (the old page is marked first), WaitServer when the test
# server answers. Each fails the gate, by name, if its condition never holds.
$HT_QUIET_JS = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'lib\quiet.js'))
function WaitFail([string]$why) { Write-Host ("  FAIL  " + $why); Write-Host "GATE: FAIL"; try { Cleanup } catch { }; exit 1 }
function WaitQuiet([string]$why) {
  $qr = Invoke-CDP 'Runtime.evaluate' @{ expression = "(window.__htQuiet ? window.__htQuiet(10000).then(function () { return 'quiet'; }, function (e) { return String(e && e.message || e); }) : Promise.resolve('no quiet marker on this page'))"; awaitPromise = $true; returnByValue = $true }
  $v = $qr.result.result.value
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
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

$fails = @()
try {
  WaitServer "$origin/index.html"
  $args = @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
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
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $script = @'
(async function () {
  const out = {};
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const FLOOR = 16;

  // Drive as much of the app into the DOM as one page can hold. A surface that
  // never rendered is a surface this gate did not check, so the sweep is only
  // worth what the setup reaches.
  HT.boot();
  // R159.1/A4: the day renders one COLLAPSED header per meal kind, so an item row
  // does not exist until its group is tapped. This gate sweeps those rows, so it
  // opens them -- once, with the sticky seam, which keeps later seeding swept too.
  if (typeof HT.dayGroupsOpenAll === 'function') HT.dayGroupsOpenAll();
  const today = HT.localDate();
  const day = HT.state().days[today] || (HT.state().days[today] = { status: 'in_progress', water_l: 1.5, items: [] });
  day.items = [
    { name: 'Greek yogurt', meal: 'breakfast', time: '08:10', grams: 150, kcal: 120,
      protein_g: 10, fat_g: 4, carb_g: 9, fiber_g: 0, soluble_fiber_g: 0,
      confidence: 'weighed', source: 'manual', notes: 'a note that wraps onto a second line',
      micros: { sodium_mg: 50, calcium_mg: 150, iron_mg: 0.1 } },
    { name: 'lentil soup', meal: 'lunch', time: '12:30', grams: 300, kcal: 230,
      protein_g: 12, fat_g: 4, carb_g: 34, fiber_g: 8, soluble_fiber_g: 2,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' }];
  HT.state().timeline = HT.state().timeline || {};
  HT.state().timeline[today] = [
    { id: 'sig1', kind: 'medication', name: 'Metformin', dose: 500, dose_unit: 'mg', time: '08:15', notes: 'with food' },
    { id: 'sig2', kind: 'biometric', type: 'weight', value: 78.4, unit: 'kg', time: '07:00' },
    { id: 'sig3', kind: 'event', type: 'walk', value: 30, unit: 'min', time: '18:00', notes: '' }];
  HT.state().settings = HT.state().settings || {};
  HT.state().settings.presets = [{ id: 'p1', name: 'Oats + whey', kcal: 420, portion: '80 g' }];
  HT.state().settings.goals = { kcal: { value: 2200, direction: 'max' }, protein_g: { value: 140, direction: 'min' } };
  HT.state().meds = HT.state().meds || {};
  HT.state().meds.m1 = { id: 'm1', source: 'label-photo', created: today,
    printed: { name: 'Metformin', generic_name: 'metformin hydrochloride', strength: '500 mg',
               directions: 'Take one tablet twice daily with food', prescriber: 'Dr A' },
    fills: [{ fill_date: today, quantity: '60', rx_number: '12345' }] };
  HT.refresh();
  await window.__htQuiet(10000);

  // R155/R242: TWO SCREENS THIS GATE NEVER SWEPT -- the night panel (H26) and the
  // photo-search sheet (H27/H30) -- and the floor regressed on both unseen. Each is
  // now driven into the DOM with real content, and reaching it is asserted below.
  const pad = (n) => String(n).padStart(2, '0');
  const iso = (ms) => { const d = new Date(ms), o = -d.getTimezoneOffset();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':00'
      + (o < 0 ? '-' : '+') + pad(Math.floor(Math.abs(o) / 60)) + ':' + pad(Math.abs(o) % 60); };
  const eve = HT.shiftDate(today, -1), nightRows = [];
  for (let m = 22 * 60; m <= 31 * 60; m += 5) nightRows.push({ t: iso(HT.dayKeyMs(eve) + m * 60000), v: 5 + Math.sin(m / 50) * 0.8, unit: 'mmol/L' });
  await Promise.resolve(HT.glucoseIngest(nightRows, { source: 'Gate CGM' }));
  try { HT.renderNights(); } catch (e) {}
  await HT.corpusEnsure(); HT.matchIndexBuild();
  HT.openPhotoDraft(JSON.stringify({ meal: 'dinner', items: [{ name: 'white wine', grams: 150, notes: 'from the photo',
    alts: [{ name: 'white wine', p: 0.6 }, { name: 'apple juice', p: 0.4 }],
    per100: { kcal: 46, protein_g: 0.1, fat_g: 0.1, carb_g: 11, fiber_g: 0.2, soluble_fiber_g: 0 } }] }));
  await window.__htQuiet(10000);
  HT.photoSearchOpen(0);
  await HT.photoSearchRun(0, 'wine');
  await window.__htQuiet(10000);
  out.reachedEarly = { nights: document.querySelectorAll('.nightrow').length, pmsrows: document.querySelectorAll('.pmsrow').length,
                       pmscap: document.querySelectorAll('.pmscap').length, pmsmac: document.querySelectorAll('.pmsmac').length,
                       pmsub: document.querySelectorAll('.pmsub').length };
  const swept = { nightUnder: [], photoUnder: [] };
  const under = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel + ' *, ' + sel)).filter((el) =>
    parseFloat(getComputedStyle(el).fontSize) < FLOOR - 0.01 && Array.prototype.some.call(el.childNodes, (n) => n.nodeType === 3 && /\S/.test(n.nodeValue)))
    .map((el) => el.tagName.toLowerCase() + '.' + String(el.className || '').split(' ')[0] + ' @' + parseFloat(getComputedStyle(el).fontSize) + 'px');
  swept.nightUnder = under('#nights');
  swept.photoUnder = under('.pmsearch');
  out.swept = swept;
  HT.photoDiscard && HT.photoDiscard();

  // every entry surface, and the settings panel with its cards expanded
  const modes = HT.SHEET_MODES.slice();
  HT.openSheet('scan');
  for (const m of modes) { HT.setSheetMode(m); await sleep(60); }
  HT.openSettings();
  await window.__htQuiet(10000);
  Array.prototype.slice.call(document.querySelectorAll('details')).forEach(d => { d.open = true; });
  try { HT.renderMeds(); } catch (e) {}
  try { HT.renderQuickChips(); } catch (e) {}
  HT.refresh();
  await window.__htQuiet(10000);
  Array.prototype.slice.call(document.querySelectorAll('details')).forEach(d => { d.open = true; });
  await window.__htQuiet(10000);

  // ---- the sweep: COMPUTED sizes, on the page, not declarations ------------
  // A grep of the stylesheet cannot see this. D99 is the proof: <small>, <sub>
  // and <sup> are sized by the UA sheet RELATIVELY (0.8em), so they sat under the
  // floor with no declaration anywhere to find.
  function directText(el) {
    for (let n = el.firstChild; n; n = n.nextSibling)
      if (n.nodeType === 3 && /\S/.test(n.nodeValue)) return true;
    return false;
  }
  function where(el) {
    const id = el.id ? '#' + el.id : '';
    const cls = (el.className && typeof el.className === 'string')
      ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '';
    return el.tagName.toLowerCase() + id + cls;
  }
  const all = Array.prototype.slice.call(document.querySelectorAll('*'));
  const textUnder = [], controlUnder = [];
  const seen = {};
  all.forEach(function (el) {
    const tag = el.tagName.toLowerCase();
    if (tag === 'script' || tag === 'style' || tag === 'head' || tag === 'title') return;
    const px = parseFloat(getComputedStyle(el).fontSize);
    if (!(px > 0)) return;
    const isControl = (tag === 'input' || tag === 'select' || tag === 'textarea' || tag === 'button');
    if (px < FLOOR - 0.01) {
      const w = where(el) + ' @' + px.toFixed(1) + 'px';
      if (isControl) { if (!seen['c' + w]) { seen['c' + w] = 1; controlUnder.push(w); } }
      else if (directText(el)) { if (!seen['t' + w]) { seen['t' + w] = 1; textUnder.push(w); } }
    }
  });
  out.elements = all.length;
  out.textUnder = textUnder.length;
  out.controlUnder = controlUnder.length;
  out.worst = textUnder.concat(controlUnder).slice(0, 12);
  // the setup is only worth what it reached -- say so, so a gate that swept an
  // empty page cannot pass for a gate that swept the app
  out.reached = {
    items: document.querySelectorAll('.mitem').length,
    timeline: document.querySelectorAll('.tlrow').length,
    meds: document.querySelectorAll('.medrow').length,
    smalls: document.querySelectorAll('small').length,
    controls: document.querySelectorAll('input,select,textarea,button').length };
  return JSON.stringify(out);
})()
'@
  $r = EvalAsync $script
  if ($r -like 'EXCEPTION*') { $fails += "the page threw: $r" }
  $F = if ($r -like 'EXCEPTION*') { [pscustomobject]@{} } else { $r | ConvertFrom-Json }

  # A sweep that reached nothing would pass for the wrong reason, so the coverage
  # is asserted before the floor is.
  if ($F.elements -lt 400) { $fails += "the sweep saw only $($F.elements) elements -- the page did not render" }
  if ($F.reached.items -lt 2) { $fails += "no food rows rendered -- the day view was not swept" }
  if ($F.reached.timeline -lt 3) { $fails += "no timeline rows rendered -- the timeline was not swept" }
  if ($F.reached.meds -lt 1) { $fails += "no medication rows rendered -- the meds surface was not swept" }
  if ($F.reached.smalls -lt 5) { $fails += "no <small> elements rendered -- the one tag that taught us this cannot be checked by a grep was not swept" }
  if ($F.reached.controls -lt 40) { $fails += "only $($F.reached.controls) form controls rendered -- the controls were not swept" }
  # R155/R242: the two screens that were never swept -- reached, then held to the floor
  if ($F.reachedEarly.nights -lt 1) { $fails += "no night rows rendered -- the night panel was not swept" }
  if (($F.reachedEarly.pmsrows -lt 1) -or ($F.reachedEarly.pmscap -lt 1) -or ($F.reachedEarly.pmsmac -lt 1)) { $fails += "the photo-search sheet did not render its rows, caption and figures ($($F.reachedEarly | ConvertTo-Json -Compress)) -- it was not swept" }
  if (@($F.swept.nightUnder).Count -gt 0) { $fails += ("the NIGHT PANEL has text under 16px: " + (@($F.swept.nightUnder) -join ', ')) }
  if (@($F.swept.photoUnder).Count -gt 0) { $fails += ("the PHOTO-SEARCH SHEET has text under 16px: " + (@($F.swept.photoUnder) -join ', ')) }
  Write-Host ("  night panel and photo-search sheet reached: " + ($F.reachedEarly | ConvertTo-Json -Compress))

  if ($F.textUnder -gt 0) {
    $fails += "$($F.textUnder) element(s) render text below the 16px floor (D100)"
  }
  if ($F.controlUnder -gt 0) {
    $fails += "$($F.controlUnder) form control(s) compute below 16px -- iOS zooms the viewport on focus, which is behaviour, not typography (D100)"
  }
  if ($F.worst) { $F.worst | ForEach-Object { $fails += "    $_" } }
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "FONT FLOOR GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host "FONT FLOOR GATE: PASS -- $($F.elements) elements swept, $($F.reached.controls) controls, $($F.reached.smalls) <small>; nothing computes below 16px"
exit 0
