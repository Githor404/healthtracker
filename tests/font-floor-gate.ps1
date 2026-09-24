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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $script = @'
(async function () {
  const out = {};
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const FLOOR = 16;

  // Drive as much of the app into the DOM as one page can hold. A surface that
  // never rendered is a surface this gate did not check, so the sweep is only
  // worth what the setup reaches.
  HT.boot();
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
  await sleep(250);

  // every entry surface, and the settings panel with its cards expanded
  const modes = HT.SHEET_MODES.slice();
  HT.openSheet('scan');
  for (const m of modes) { HT.setSheetMode(m); await sleep(60); }
  HT.openSettings();
  await sleep(150);
  Array.prototype.slice.call(document.querySelectorAll('details')).forEach(d => { d.open = true; });
  try { HT.renderMeds(); } catch (e) {}
  try { HT.renderQuickChips(); } catch (e) {}
  HT.refresh();
  await sleep(250);
  Array.prototype.slice.call(document.querySelectorAll('details')).forEach(d => { d.open = true; });
  await sleep(150);

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
