# THE PAGE'S OWN HORIZONTAL OVERFLOW. Ruled after a measurement found 3px of it
# at 360 that NOTHING WAS WATCHING.
#
# Every layout gate here checks its own component: lab-form-gate its form,
# chip-layout-gate the signal strip, panel-gate and collapse-gate the ink inside
# their own rows. None asks whether the DOCUMENT scrolls sideways. So a 3px
# overflow from `.ttrail`/`.tleg` in Trends sat there unseen across 24 verdicts,
# and was only found incidentally while attributing a different failure.
#
# IT ASSERTS ZERO, NOT THREE. A threshold written around what the first run found
# would be a gate that ratifies the defect it was created to catch -- the opposite
# of a baseline taken from the fixture it gates, because here the fixture IS the
# shipped page and the right number is the one a phone needs, not the one it has.
#
# ON FAILURE IT NAMES THE OFFENDER AND ITS PARENT CHAIN, with every box. A probe
# that reports a quantity without an owner makes the reader guess, and guessing is
# what cost this project most of an afternoon the day this gate was ruled.
#
# WIDTHS: 390 and 360, the two every other gate in this repo uses. 320 is NOT
# covered and this gate does not imply anything about it.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8239
$Dbg = 9445
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-pageovf-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None
$fails = @()

function Find-Browser {
  foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 262144
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count); if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$m, [hashtable]$p) {
  $script:cid++; $pl = @{ id = $script:cid; method = $m }; if ($p) { $pl.params = $p }
  $b = [Text.Encoding]::UTF8.GetBytes(($pl | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($b), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $g = 0
  while ($true) {
    if (++$g -gt 4000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome or Edge found"; exit 2 }
$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); $l.Start()
  $mimes = @{ '.html'='text/html'; '.js'='application/javascript'; '.json'='application/json';
              '.png'='image/png'; '.svg'='image/svg+xml'; '.css'='text/css'; '.bin'='application/octet-stream' }
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
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 745; deviceScaleFactor = 1; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 2500

  # A FULL page: every section that can render, so nothing escapes by being empty.
  # Trends in particular only draws its trail and legend once there is a series to
  # draw, and the 3px this gate exists for comes from exactly that.
  $seed = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T10:35:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  const S = HT.state();
  const mk = function (n, t, kcal) { return { name: n, meal: 'lunch', time: t, grams: 150,
    kcal: kcal, protein_g: 20, fat_g: 9, carb_g: 30, fiber_g: 6, soluble_fiber_g: 2,
    confidence: 'weighed', source: 'manual', notes: '' }; };
  // several days, so Trends has a series and the trail/legend render
  for (let d = 0; d < 9; d++) {
    const dk = HT.shiftDate('2026-09-26', -d);
    S.days[dk] = { status: 'complete', water_l: 1.4, items: [
      mk('oats and berries with yoghurt', '07:30', 320 + d * 7),
      mk('chicken, rice and broccoli', '12:30', 520 - d * 5)] };
    S.timeline = S.timeline || {};
    S.timeline[dk] = [
      { time: '06:10', kind: 'event', type: 'walk', source: 'manual', notes: '', unit: 'min', value: 35 },
      { time: '07:05', kind: 'biometric', type: 'weight', source: 'manual', notes: '', unit: 'kg', value: 90.4 - d * 0.1 }];
  }
  S.current = '2026-09-26';
  HT.setGoal('kcal', 2200, 'max'); HT.setGoal('fiber_g', 30, 'min');
  HT.setGoal('protein_g', 120, 'min'); HT.setGoal('weight', 80, 'max', 'kg');
  // glucose too, so H19's row and chart are on the page
  if (typeof HT.glucoseIngest === 'function') {
    const STEP = 300, END = Date.parse('2026-09-26T07:30:00-04:00');
    const n = 300, start = END - (n - 1) * STEP * 1000, rows = [];
    for (let i = 0; i < n; i++) rows.push({ t: new Date(start + i * STEP * 1000).toISOString(),
      v: Math.round((5.6 + 1.9 * Math.sin(i / 34)) * 10) / 10, unit: 'mmol/L' });
    HT.glucoseClear();
    HT.glucoseIngest(rows, { source: 'Dexcom G7', rawUnit: 'mmol<180.1558800000541>/L' });
  }
  HT.refresh(); await sleep(500);
  // open every disclosure, because a section that never renders never overflows
  Array.prototype.slice.call(document.querySelectorAll('.wrap details')).forEach(function (d) { d.open = true; });
  if (typeof HT.glucoseToggle === 'function') HT.glucoseToggle('2026-09-26');
  HT.refresh(); await sleep(600);
  return { days: Object.keys(S.days).length,
           details: document.querySelectorAll('.wrap details[open]').length,
           glucoseRow: document.querySelectorAll('#dayView .grow').length };
})()
'@
  $s = EvalA $seed
  if ($s -like 'EXCEPTION*') { Write-Host "ERROR: seed threw: $s"; Cleanup; exit 2 }
  $S0 = $s | ConvertFrom-Json
  Write-Host "  seeded: $($S0.days) days, $($S0.details) disclosures open, $($S0.glucoseRow) glucose row(s)"
  if ($S0.days -lt 5) { $fails += "the fixture seeded only $($S0.days) days -- Trends needs a series or its trail never renders, and a page that does not render cannot overflow (D96)" }
  if ($S0.details -lt 3) { $fails += "only $($S0.details) disclosures are open -- a closed section never overflows, so this gate would pass by not looking" }

  # THE PROBE. Names every offender and walks its parent chain, because a number
  # without an owner is half a measurement.
  $probe = @'
(function () {
  const docW = document.documentElement.clientWidth;
  const over = document.documentElement.scrollWidth - docW;
  const nameOf = function (e) {
    const c = e.getAttribute && e.getAttribute('class');
    return (c ? String(c) : String(e.tagName || '')).slice(0, 24);
  };
  const chainOf = function (e) {
    const out = [];
    for (let a = e.parentElement, i = 0; a && i < 5; a = a.parentElement, i++) {
      const b = a.getBoundingClientRect();
      out.push(nameOf(a) + '(w' + Math.round(b.width) + ' r' + Math.round(b.right) + ')');
      if (a.tagName === 'BODY') break;
    }
    return out.join(' < ');
  };
  const hits = [];
  Array.prototype.slice.call(document.querySelectorAll('body *')).forEach(function (e) {
    const b = e.getBoundingClientRect();
    if (b.width <= 0 || b.height <= 0) return;
    if (b.right <= docW + 0.5) return;
    hits.push({ name: nameOf(e), left: Math.round(b.left), right: Math.round(b.right),
                w: Math.round(b.width), past: Math.round(b.right - docW), chain: chainOf(e) });
  });
  hits.sort(function (a, b) { return b.past - a.past; });
  return JSON.stringify({ docW: docW, scrollW: document.documentElement.scrollWidth,
    overflow: over, innerWidth: window.innerWidth, count: hits.length, hits: hits.slice(0, 6) });
})()
'@

  # TWO STATES, because the first version of this gate passed on one of them while
  # the defect lived in the other. The measured 3px at 360 is in the FIRST-RUN
  # state -- the one a new user sees -- and a richly seeded nine-day fixture does
  # not contain it. A gate whose fixture lacks the condition reports the absence of
  # the condition, not the absence of the defect.
  function Probe-Widths([string]$label) {
    foreach ($wh in @(@(390, 745), @(360, 690))) {
      Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wh[0]; height = $wh[1]; deviceScaleFactor = 1; mobile = $true } | Out-Null
      Start-Sleep -Milliseconds 900
      $R = (Eval $probe) | ConvertFrom-Json
      $w = $wh[0]
      Write-Host ("  [{0}] {1}x{2}: clientWidth={3} scrollWidth={4} overflow={5}px, {6} element(s) past the edge (clipped ones are not overflow)" -f `
        $label, $w, $wh[1], $R.docW, $R.scrollW, $R.overflow, $R.count)
      if ($R.overflow -gt 0) {
        $script:fails += "[$label] ${w}px: THE PAGE SCROLLS SIDEWAYS by $($R.overflow)px. Nothing on a phone should need a horizontal swipe to be read, and no gate in this suite was watching for it."
        foreach ($h in @($R.hits)) {
          $script:fails += "    $($h.name) runs $($h.past)px past the edge (left $($h.left), right $($h.right), width $($h.w)) inside $($h.chain)"
        }
      }
    }
  }
  Probe-Widths 'seeded'

  # FIRST RUN: empty storage, nothing logged. This is where the measured 3px is.
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 745; deviceScaleFactor = 1; mobile = $true } | Out-Null
  $fr = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  localStorage.clear();
  HT.boot(); HT.refresh(); await sleep(600);
  return { ok: true };
})()
'@
  Probe-Widths 'first run'

  if ($fails.Count) {
    Write-Host "PAGE OVERFLOW GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "PAGE OVERFLOW GATE: PASS -- at 390 and 360, with every disclosure open and a nine-day fixture so Trends draws its trail, the document does not scroll sideways by a single pixel."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
