# H19 -- GLUCOSE: A COLLAPSED DAY ROW THAT OPENS INTO A ZOOMABLE CHART.
#
# Written BEFORE the build and failing by name on every ruled behaviour.
#
# IT DECLARES ITS OWN FOOTING, as ruled. The one-off export this design was
# measured against spans well under two days, so the 3-day and 10-day presets
# CANNOT be exercised against real cadence. Every assertion is tagged:
#
#   [M] MEASURED CADENCE -- the fixture mirrors the real export's TIME STRUCTURE:
#       300 s between readings (median, p25 and p75 all 300 s in the real data;
#       99.6% of intervals in 4-6 min), instantaneous samples, and one hole of 50
#       min (9 consecutive samples dropped leaves ten steps between survivors --
#       the real export's single gap was 45 min, which is the same kind of hole).
#       The VALUES are synthetic: the repo is fixture-synthetic forever and the
#       real readings never enter it. Every assertion here is about structure.
#
#   [I] INVENTED CADENCE -- the same 300 s step extended past the export's span.
#       The step is measured; the LENGTH is invented. Nothing here claims the
#       device behaves this way for ten days, only that the chart does.
#
# So a green run means LESS for 3-day and 10-day than for 6-hour and 24-hour, and
# the PASS line says so rather than leaving the reader to assume otherwise.
#
# MEASURED BEFORE ANY OF IT: the chart's box inside the day card is 328 px at a
# 390 px viewport and ~298 px at 360. A 10-day window is therefore 2,880 readings
# across 328 columns = 8.8 per column, which is what makes the min/max envelope
# necessary rather than tidy.
#
# RULED: A separate-key cache, out of the export by construction, and SAID so on
#          the surface.
#        B right edge = last reading, never "now"; the age stated is the REAL age,
#          never the 3-hour nominal. A look-back instrument, never live.
#        C min/max envelope per column, never bridging a gap. SMOOTHING REJECTED.
#        D fixed declared domain 2-14 mmol/L; outside is clipped AND MARKED.
#        E unit verbatim + canonical, never converted; two units refuse one line.
#        F a generic control, shaped by glucose and Trends.
#        G axis-locked by first movement, so a vertical swipe still scrolls.
#   and  the DAY ROW: collapsed to average/low/high + unit + the count it came
#          from + the last reading's age; one tap opens the chart in place. A day
#          with a gap must not read like a full day.
#
# THE ONE AVERAGE THAT IS ALLOWED, and why it is not a contradiction: a day's
# average STATED WITH ITS COUNT is a claim about that day's readings, and the
# count is what makes it checkable. An average used to DRAW the line is a
# rendering shortcut that hides the spike. The first is ruled in; the second
# stays rejected. This gate asserts both halves.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8223
$Dbg = 9429
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-chart-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None
$fails = @()
$ran = @{ M = 0; I = 0 }

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
# TAGGED, counted, and the tag travels into the failure text -- so the PASS line
# can state what each half of the run was standing on.
function Chk([string]$tag, [bool]$cond, [string]$msg) {
  $script:ran[$tag] = $script:ran[$tag] + 1
  if (-not $cond) { $script:fails += "[$tag] $msg" }
}
function Tap([int]$x, [int]$y) {
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
  Start-Sleep -Milliseconds 40
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
  Start-Sleep -Milliseconds 450
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
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  # ===================== THE FIXTURE =======================================
  # Deterministic and SYNTHETIC in value; the TIME STRUCTURE is the measured one.
  # `days` back from a fixed last reading, 300 s apart, optionally with the one
  # 45-minute gap the real export had, optionally with a second unit mixed in.
  $fixture = @'
(function (days, withGap, unitMix) {
  const STEP = 300;                                    // MEASURED: 300 s exactly
  const END = Date.parse('2026-09-26T07:30:00-04:00'); // clock is 10:35, so ~3 h old
  const n = Math.round(days * 86400 / STEP);
  const start = END - (n - 1) * STEP * 1000;
  const rows = [];
  for (let i = 0; i < n; i++) {
    const t = start + i * STEP * 1000;
    let v = 5.6 + 1.9 * Math.sin(i / 34) + 0.8 * Math.sin(i / 7.3);
    // ANCHORED TO THE END, not to a percentage: every preset window ends at the
    // last reading, so a feature at 42% of an 11-day series sits 6.4 days back and
    // is invisible in the 3-day window. The gap had to be moved for this reason
    // earlier in the same slice; the excursions needed it too.
    // BEFORE the gap (n-25) and inside the 3-day window: the excursions have to
    // land in the LONG dense run, because timeChart only reduces a run longer than
    // the plot is wide. End-anchored at n-12 they sat in the short post-gap run of
    // ~17 readings, which is drawn point-by-point -- so the pixel assertion for
    // ruling C was passing against the direct-draw path and never touched the
    // envelope at all. An assertion about a reduction must be exercised where the
    // reduction happens.
    if (i === n - 60) v = 16.4;                         // above the declared domain
    if (i === n - 120) v = 1.1;                         // below it
    rows.push({ t: new Date(t).toISOString(), v: Math.round(v * 10) / 10,
                unit: (unitMix && i === 3) ? 'mg/dL' : 'mmol/L' });
  }
  // THE GAP GOES NEAR THE END, and that is a correction: at 50% of the series it
  // landed on the previous DAY (so the summarised day had no gap to report) and
  // outside the 3-day window (so the envelope had no gap to avoid bridging).
  // Twenty-five samples back from the last reading is 125 min, which is inside
  // the summarised day and inside all four preset windows at once.
  let gapAt = null;
  if (withGap && n > 40) { gapAt = n - 25; rows.splice(gapAt, 9); }   // 9 x 300 s = 45 min
  HT.glucoseClear();
  const r = HT.glucoseIngest(rows, { source: 'Dexcom G7', rawUnit: 'mmol<180.1558800000541>/L' });
  HT.refresh();
  return { ok: !!(r && r.ok), stored: r ? r.stored : 0, asked: rows.length, gapAt: gapAt };
})
'@
  $boot = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T10:35:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  // R159.1/A4: the day renders one COLLAPSED header per meal kind, so an item row
  // does not exist until its group is tapped. This gate sweeps those rows, so it
  // opens them -- once, with the sticky seam, which keeps later seeding swept too.
  if (typeof HT.dayGroupsOpenAll === 'function') HT.dayGroupsOpenAll();
  const DK = '2026-09-26'; const S = HT.state();
  S.days[DK] = { status: 'in_progress', water_l: 0, items: [
    { name: 'lentil stew', meal: 'lunch', time: '06:30', grams: 200, kcal: 420,
      protein_g: 20, fat_g: 8, carb_g: 60, fiber_g: 9, soluble_fiber_g: 2,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' }] };
  S.timeline = S.timeline || {};
  S.timeline[DK] = [
    { time: '05:10', kind: 'event', type: 'walk', source: 'manual', notes: '', unit: 'min', value: 30 }];
  S.current = DK;
  HT.refresh(); await sleep(300);
  return { hasIngest: typeof HT.glucoseIngest === 'function',
           hasClear:  typeof HT.glucoseClear === 'function',
           hasChart:  typeof HT.timeChart === 'function',
           hasWindow: typeof HT.chartWindow === 'function',
           hasPreset: typeof HT.chartPreset === 'function',
           hasToggle: typeof HT.glucoseToggle === 'function',
           hasSummary: typeof HT.glucoseDaySummary === 'function' };
})()
'@
  $b = EvalA $boot
  if ($b -like 'EXCEPTION*') { Write-Host "ERROR: boot threw: $b"; Cleanup; exit 2 }
  $B = $b | ConvertFrom-Json
  Chk 'M' ([bool]$B.hasIngest)  "HT.glucoseIngest does not exist -- there is no ingest to gate"
  Chk 'M' ([bool]$B.hasClear)   "HT.glucoseClear does not exist -- a CACHE that cannot be cleared is not a cache (A)"
  Chk 'M' ([bool]$B.hasChart)   "HT.timeChart does not exist -- F ruled a GENERIC control, so this is not a glucose-only function"
  Chk 'M' ([bool]$B.hasWindow)  "HT.chartWindow does not exist"
  Chk 'M' ([bool]$B.hasPreset)  "HT.chartPreset does not exist"
  Chk 'M' ([bool]$B.hasToggle)  "HT.glucoseToggle does not exist -- the row cannot expand in place"
  Chk 'M' ([bool]$B.hasSummary) "HT.glucoseDaySummary does not exist -- the collapsed row has nothing to state"
  if (-not $B.hasIngest -or -not $B.hasChart -or -not $B.hasSummary) {
    Write-Host "CHART GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Write-Host "  (nothing is built yet, so the rest of the gate cannot run)"
    Write-Host "assertions run: $($ran['M']) on MEASURED cadence, $($ran['I']) on INVENTED cadence"
    Cleanup; exit 1
  }

  # ===================== [M] THE COLLAPSED DAY ROW =========================
  $m = Eval ("JSON.stringify(($fixture)(1.59, true, false))")
  Start-Sleep -Milliseconds 500
  $M0 = $m | ConvertFrom-Json
  Chk 'M' ([bool]$M0.ok) "the measured-cadence fixture did not ingest ($($M0.stored) of $($M0.asked))"

  $rowProbe = @'
(function () {
  const row = document.querySelector('#dayView .grow');
  if (!row) return JSON.stringify({ err: 'no .grow glucose row in the day view' });
  const head = row.querySelector('.ghead');
  const O = {
    h: Math.round(row.getBoundingClientRect().height),
    open: row.classList.contains('gopen'),
    headText: head ? (head.textContent || '').replace(/\s+/g, ' ').trim() : null,
    rowText: (row.textContent || '').replace(/\s+/g, ' ').trim(),
    isMitem: row.classList.contains('mitem'),
    hasChart: !!row.querySelector('svg.tchart'),
    // no verdict colour: no class on the row or its children may carry a
    // judgement token (D24/D93 -- the four provenance tokens are for confidence)
    verdictClasses: Array.prototype.slice.call(row.querySelectorAll('*'))
      .map(function (e) { return String(e.className || ''); })
      .filter(function (c) { return /\b(good|bad|warn|ok|danger|high|low)\b/.test(c); }),
    summary: HT.glucoseDaySummary('2026-09-26'),
    fonts: [],
  };
  ['.ghead', '.gstat', '.gcov', '.gage'].forEach(function (sel) {
    const e = row.querySelector(sel);
    if (e) O.fonts.push({ sel: sel, px: Math.round(parseFloat(getComputedStyle(e).fontSize) * 10) / 10 });
  });
  const b = head ? head.getBoundingClientRect() : null;
  O.tap = b ? { x: Math.round(b.left + b.width / 2), y: Math.round(b.top + Math.min(22, b.height / 2)) } : null;
  return JSON.stringify(O);
})()
'@
  $r1 = Eval $rowProbe
  $R1 = $r1 | ConvertFrom-Json
  if ($R1.err) {
    $fails += "[M] $($R1.err)"
  } else {
    $ht = [string]$R1.headText
    Chk 'M' (-not $R1.isMitem) "the glucose row carries the .mitem class, so collapse-gate's food-row budget (<=60px, <=4 facts) applies to a row that is ruled to carry average, low, high, a count AND an age. It is a different row and needs its own class"
    Chk 'M' (-not $R1.open) "the glucose row starts EXPANDED -- depth on demand: the summary first, the chart on tap"
    Chk 'M' (-not $R1.hasChart) "the chart is in the DOM while the row is collapsed -- a 2,880-point chart that renders unasked is the cost the collapse exists to avoid"

    # the three statistics, the unit, and the count that makes them checkable
    Chk 'M' ($ht -match '(?i)\bavg\b|\baverage\b') "the collapsed row does not state an average: '$ht'"
    Chk 'M' ($ht -match '(?i)mmol') "the collapsed row does not carry the unit -- E: the unit is part of the reading's identity: '$ht'"
    Chk 'M' (([regex]::Matches($ht, '\d+\.\d')).Count -ge 3) "the collapsed row shows fewer than three figures; ruled: average, low AND high: '$ht'"
    Chk 'M' ($R1.rowText -match '(?i)from \d+ reading') "the row does not say how many readings the average came from -- an average without its count is not checkable: '$($R1.rowText)'"

    # A DAY WITH A GAP MUST NOT READ LIKE A FULL DAY
    # ARITHMETIC CORRECTED: removing 9 consecutive samples leaves TEN steps between
    # the survivors, so the hole is 50 min, not 45. The gate had it wrong, not the row.
    Chk 'M' ($R1.rowText -match '(?i)missing|gap|no readings|absent') "the fixture's day has a 50-minute hole (9 dropped samples = 10 steps) and the row does not say so -- ruled: a day with a gap must not read like a full day: '$($R1.rowText)'"

    # B: the last reading's REAL age, on the row, so a stale day shows unopened
    Chk 'M' ($R1.rowText -match '(?i)\bago\b') "the row does not carry the last reading's age -- B: a stale day must be visible without opening it: '$($R1.rowText)'"
    Chk 'M' ($R1.rowText -notmatch '(?i)\b3 h behind\b') "the row quotes the 3-hour NOMINAL; measured, 3 h is a FLOOR with a long tail, so the age shown is the real one"
    Chk 'M' ($R1.rowText -notmatch '(?i)\bcurrent\b|\bnow\b|\blive\b') "the row describes a HealthKit value as current/now/live -- ruled impossible: a look-back instrument, never live"

    # no verdict colours, on the row either
    Chk 'M' (@($R1.verdictClasses).Count -eq 0) "the row carries judgement classes ($(@($R1.verdictClasses) -join ', ')) -- D24/D93: no verdict colours"
    foreach ($bad in @('in range', 'out of range', 'target', 'normal')) {
      Chk 'M' ($R1.rowText -notmatch ('(?i)\b' + [Regex]::Escape($bad) + '\b')) "the row says '$bad' -- no in-range framing"
    }

    # the summary API agrees with what is printed, and knows its own shortfall
    $S1 = $R1.summary
    Chk 'M' ($null -ne $S1 -and $S1.n -gt 0) "glucoseDaySummary returned nothing for the fixture day"
    if ($null -ne $S1) {
      Chk 'M' ($S1.lo -le $S1.avg -and $S1.avg -le $S1.hi) "the summary is incoherent: lo $($S1.lo), avg $($S1.avg), hi $($S1.hi)"
      Chk 'M' ($S1.expected -gt 0 -and $S1.n -lt $S1.expected) "the summary does not record a shortfall against the cadence ($($S1.n) of $($S1.expected)) -- that is what stops a gapped day reading as full"
      Chk 'M' ($S1.gapMs -gt 0) "the summary reports no missing time although the fixture drops 9 consecutive samples"
      Chk 'M' ($S1.unit -eq 'mmol/L') "the canonical unit is '$($S1.unit)', expected mmol/L"
      Chk 'M' ($null -ne $S1.rawUnit -and ([string]$S1.rawUnit).Length -gt 0) "the platform's verbatim unit string was not kept -- E ruled verbatim AND canonical"
    }

    foreach ($f in @($R1.fonts)) { Chk 'M' ($f.px -ge 16) "16px floor -- $($f.sel) computes to $($f.px)px" }
    Chk 'M' (@($R1.fonts).Count -ge 2) "only $(@($R1.fonts).Count) text classes found on the row -- coverage before the floor (D124)"

    # ---- ONE TAP OPENS THE CHART IN PLACE --------------------------------
    if ($R1.tap) {
      Eval "window.scrollTo(0, Math.max(0, document.querySelector('#dayView .grow').getBoundingClientRect().top + window.scrollY - 260)); 1" | Out-Null
      Start-Sleep -Milliseconds 250
      $t = (Eval $rowProbe) | ConvertFrom-Json
      $hBefore = $t.h
      Tap $t.tap.x $t.tap.y
      $t2 = (Eval $rowProbe) | ConvertFrom-Json
      Chk 'M' ([bool]$t2.open) "one tap did not expand the glucose row in place (no .gopen)"
      Chk 'M' ([bool]$t2.hasChart) "the row expanded but drew no chart"
      Chk 'M' ($t2.h -gt $hBefore) "the row did not grow when expanded ($hBefore -> $($t2.h))"
    }
  }

  # ===================== [M] THE CHART ITSELF ==============================
  $probe = @'
(function () {
  const O = {};
  const svg = document.querySelector('#dayView .grow svg.tchart');
  if (!svg) return JSON.stringify({ err: 'no svg.tchart inside the expanded glucose row' });
  const box = svg.getBoundingClientRect();
  O.boxW = Math.round(box.width); O.boxH = Math.round(box.height);
  const lines = Array.prototype.slice.call(svg.querySelectorAll('polyline.tseries'));
  O.runs = lines.length;
  O.nodes = lines.reduce(function (a, l) {
    return a + (l.getAttribute('points') || '').trim().split(/\s+/).filter(function (s) { return s; }).length; }, 0);
  O.axis = Array.prototype.slice.call(svg.querySelectorAll('.taxis text')).map(function (t) { return (t.textContent || '').trim(); });
  const wl = document.querySelector('#dayView .grow .twindow');
  O.windowText = wl ? (wl.textContent || '').replace(/\s+/g, ' ').trim() : null;
  O.marks = Array.prototype.slice.call(svg.querySelectorAll('.tmark')).map(function (m) {
    return { x: Math.round(m.getBoundingClientRect().left - box.left), kind: m.getAttribute('data-kind') || '' }; });
  O.clips = svg.querySelectorAll('.tclip').length;
  O.presets = Array.prototype.slice.call(document.querySelectorAll('#dayView .grow .tpreset')).map(function (b) { return (b.textContent || '').trim(); });
  O.bodyText = (document.querySelector('#dayView .grow .gbody') || {}).textContent || '';
  O.bodyText = O.bodyText.replace(/\s+/g, ' ').trim();
  O.fonts = [];
  ['.twindow', '.tpreset', '.tnote'].forEach(function (sel) {
    const e = document.querySelector('#dayView .grow ' + sel);
    if (e) O.fonts.push({ sel: sel, px: Math.round(parseFloat(getComputedStyle(e).fontSize) * 10) / 10 });
  });
  return JSON.stringify(O);
})()
'@
  $p1 = Eval $probe
  $P1 = $p1 | ConvertFrom-Json
  if ($P1.err) {
    $fails += "[M] $($P1.err)"
  } else {
    Chk 'M' ($P1.boxW -ge 290 -and $P1.boxW -le 345) "the chart box is $($P1.boxW)px; measured 328 inside the day card at a 390 viewport"

    # A GAP IS A BREAK -- the assertion the existing index-based sparkline cannot pass
    Chk 'M' ($P1.runs -ge 2) "the series is drawn as $($P1.runs) continuous run(s); the fixture's 50-min hole must BREAK the line. One run means it was drawn straight through, which is what an index-based x always does"

    # TIME-PROPORTIONAL x: 9 missing samples must span about 9 normal steps
    $gapRatio = Eval @'
(function () {
  const svg = document.querySelector('#dayView .grow svg.tchart');
  const lines = Array.prototype.slice.call(svg.querySelectorAll('polyline.tseries'));
  if (lines.length < 2) return -1;
  const pts = lines.map(function (l) {
    return (l.getAttribute('points') || '').trim().split(/\s+/).filter(function (s) { return s; })
      .map(function (s) { return parseFloat(s.split(',')[0]); }); });
  const a = pts[0], b = pts[1];
  if (a.length < 2 || !b.length) return -1;
  const step = (a[a.length - 1] - a[0]) / (a.length - 1);
  if (!(step > 0)) return -1;
  return Math.round(((b[0] - a[a.length - 1]) / step) * 10) / 10;
})()
'@
    Chk 'M' ([double]$gapRatio -ge 6.0) "the hole spans $gapRatio x a normal step; 9 samples are missing so it must span about 9x. A value near 1 means x is spaced by INDEX, and such a chart cannot show a gap at all"

    Chk 'M' ($null -ne $P1.windowText -and ([string]$P1.windowText).Length -gt 0) "there is no .twindow line stating the visible window"
    Chk 'M' ($P1.windowText -match '\d') "the window line carries no figures: '$($P1.windowText)'"
    $want = @('6 h', '24 h', '3 days', '10 days')
    foreach ($w in $want) {
      Chk 'M' ((@($P1.presets) -join '|') -match [Regex]::Escape($w)) "preset '$w' is missing (found: $(@($P1.presets) -join ', '))"
    }
    Chk 'M' ($P1.bodyText -match '(?i)apple health|healthkit') "the expanded body does not say where the readings came from"
    Chk 'M' ($P1.bodyText -match '(?i)not in (your )?export|excluded from .*export|re-?acquir') "the body does not say this is a CACHE kept out of the export -- A ruled: say so where glucose appears"
    Chk 'M' ($P1.clips -ge 2) "the fixture carries two values outside the declared 2-14 domain and $($P1.clips) clip marks were drawn -- D ruled clipped and MARKED, never rescaled"
    Chk 'M' (@($P1.marks).Count -ge 2) "only $(@($P1.marks).Count) mark(s) on the chart -- the fixture has a meal and an event and both belong on the same axis"
    $ax = (@($P1.axis) -join ' ')
    # SUPERSEDED BY H23/5, and replaced rather than dropped. The unit used to
    # ride the top tick; measured, those nine glyphs covered the above-domain
    # clip marker. The unit must still be on screen -- the window line carries
    # it now -- so both halves are asserted here.
    Chk 'M' ($ax -notmatch '(?i)mmol') "the y-axis labels still carry the unit ('$ax'). H23/5 moved it to the window line because '14 mmol/L' is 76.7 units wide against a 38-unit gutter and covered the clip marker that says a value left the declared range"
    Chk 'M' ((Eval "(document.querySelector('#dayView .grow .twindow')||{}).textContent||''") -match '(?i)mmol') "the unit left the axis and did NOT appear on the window line, so it is nowhere on screen"
    Chk 'M' ($ax -match '(^|\s)2(\s|$)' -and $ax -match '14') "the y-axis does not show the declared 2-14 domain: '$ax'"
    foreach ($f in @($P1.fonts)) { Chk 'M' ($f.px -ge 16) "16px floor -- $($f.sel) computes to $($f.px)px" }
  }

  # ---- G: AXIS-LOCKED GESTURES, with real touch sequences -----------------
  $geo = Eval "JSON.stringify((function(){var s=document.querySelector('#dayView .grow svg.tchart');if(!s)return null;var b=s.getBoundingClientRect();return {x:Math.round(b.left+b.width/2),y:Math.round(b.top+b.height/2)};})())"
  if ($geo -and $geo -ne 'null') {
    $G = $geo | ConvertFrom-Json
    $axBefore = Eval "JSON.stringify(Array.prototype.slice.call(document.querySelectorAll('#dayView .grow .taxis text')).map(function(t){return (t.textContent||'').trim()+'@'+Math.round(t.getBoundingClientRect().top);}))"
    $winBefore = Eval "JSON.stringify(HT.chartWindow())"
    $pageBefore = Eval "Math.round(window.scrollY)"
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $G.x; y = $G.y }) } | Out-Null
    foreach ($dx in 20, 45, 70, 95) {
      Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchMove'; touchPoints = @(@{ x = ($G.x - $dx); y = $G.y }) } | Out-Null
      Start-Sleep -Milliseconds 25
    }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 400
    $winAfter = Eval "JSON.stringify(HT.chartWindow())"
    $pageAfterH = Eval "Math.round(window.scrollY)"
    $axAfter = Eval "JSON.stringify(Array.prototype.slice.call(document.querySelectorAll('#dayView .grow .taxis text')).map(function(t){return (t.textContent||'').trim()+'@'+Math.round(t.getBoundingClientRect().top);}))"
    Chk 'M' ($winBefore -ne $winAfter) "a horizontal drag did not pan the window through time (before $winBefore, after $winAfter)"
    Chk 'M' ($pageBefore -eq $pageAfterH) "a HORIZONTAL drag scrolled the page ($pageBefore -> $pageAfterH) -- G ruled axis-locked by the first movement"
    Chk 'M' ($axBefore -eq $axAfter) "the y-axis labels moved while time scrolled -- ruled fixed; a moving axis makes two windows mean different things"

    $G = (Eval "JSON.stringify((function(){var s=document.querySelector('#dayView .grow.gopen svg.tchart');if(!s)return null;var b=s.getBoundingClientRect();return {x:Math.round(b.left+b.width/2),y:Math.round(b.top+b.height/2)};})())") | ConvertFrom-Json
    $winB2 = Eval "JSON.stringify(HT.chartWindow())"
    $pageB2 = Eval "Math.round(window.scrollY)"
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $G.x; y = $G.y }) } | Out-Null
    foreach ($dy in 20, 45, 70, 95) {
      Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchMove'; touchPoints = @(@{ x = $G.x; y = ($G.y - $dy) }) } | Out-Null
      Start-Sleep -Milliseconds 25
    }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 400
    Chk 'M' ((Eval "Math.round(window.scrollY)") -ne $pageB2) "a VERTICAL drag on the chart did not scroll the page -- G ruled the thumb is never trapped"
    Chk 'M' ((Eval "JSON.stringify(HT.chartWindow())") -eq $winB2) "a vertical drag also panned the window -- the axis lock is not holding"

    # RE-READ THE BOX. $G was taken before the vertical-drag test, which SCROLLED
    # THE PAGE -- so by now those coordinates point at whatever moved into that
    # place. Measured: the pinch works (24 h -> 5 days, every touch arriving and
    # cancelable); the gate was aiming at a page that had moved under it. Same
    # family as D144's stale element reference, one layer out: a coordinate
    # captured before a scroll is a coordinate into a page that no longer exists.
    $G = (Eval "JSON.stringify((function(){var s=document.querySelector('#dayView .grow.gopen svg.tchart');if(!s)return null;var b=s.getBoundingClientRect();return {x:Math.round(b.left+b.width/2),y:Math.round(b.top+b.height/2)};})())") | ConvertFrom-Json
    $spanB = Eval "(function(){var w=HT.chartWindow();return Math.round((w.to-w.from)/1000);})()"
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(
      @{ x = ($G.x - 60); y = $G.y; id = 1 }, @{ x = ($G.x + 60); y = $G.y; id = 2 }) } | Out-Null
    foreach ($s in 40, 25, 12) {
      Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchMove'; touchPoints = @(
        @{ x = ($G.x - $s); y = $G.y; id = 1 }, @{ x = ($G.x + $s); y = $G.y; id = 2 }) } | Out-Null
      Start-Sleep -Milliseconds 30
    }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 400
    Chk 'M' ($spanB -ne (Eval "(function(){var w=HT.chartWindow();return Math.round((w.to-w.from)/1000);})()")) "a two-finger pinch did not change the window span (was $spanB s)"
  } else {
    $fails += "[M] the chart svg has no box, so no gesture could be aimed at it"
  }

  # ---- INK and the floor at 360 -------------------------------------------
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 360; height = 800; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Start-Sleep -Milliseconds 700
  $ink = Eval @'
(function () {
  const row = document.querySelector('#dayView .grow');
  if (!row) return JSON.stringify({ err: 'no .grow at 360' });
  const hits = [];
  const kids = Array.prototype.slice.call(row.querySelectorAll('*'));
  const vis = function (e) { return typeof e.checkVisibility === 'function'
    ? e.checkVisibility({ contentVisibilityAuto: true, visibilityProperty: true })
    : e.getBoundingClientRect().height > 0; };
  kids.forEach(function (el) {
    let t = '';
    for (let j = 0; j < el.childNodes.length; j++)
      if (el.childNodes[j].nodeType === 3) t += el.childNodes[j].nodeValue;
    if (!t.replace(/\s+/g, ' ').trim() || !vis(el)) return;
    if (el.scrollWidth <= el.clientWidth + 1) return;
    const cs = getComputedStyle(el);
    if (cs.overflowX === 'hidden' || cs.overflowX === 'clip') return;   // clipped is not overflowing (D144)
    const a = el.getBoundingClientRect();
    kids.forEach(function (ot) {
      if (ot === el || el.contains(ot) || ot.contains(el) || !vis(ot)) return;
      const b = ot.getBoundingClientRect();
      if (b.width <= 0 || b.height <= 0) return;
      const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      if (oy > 0.5 && (a.left + el.scrollWidth) - b.left > 0.5)
        hits.push(String(el.className || el.tagName).slice(0, 24) + ' over ' + String(ot.className || ot.tagName).slice(0, 24));
    });
  });
  const svg = row.querySelector('svg.tchart');
  const docW = document.documentElement.clientWidth;
  let rowOver = 0; const whoOver = [];
  // `e.className` on an SVG element is an SVGAnimatedString, not a string, so it
  // stringifies to "[object SVGAnimatedString]" and names nothing. The class lives
  // in getAttribute('class') for both HTML and SVG.
  const nameOf = function (e) {
    const c = e.getAttribute && e.getAttribute('class');
    return (c ? String(c) : String(e.tagName || '')).slice(0, 22);
  };
  // A CLIPPED ELEMENT IS NOT AN OVERFLOWING ONE -- the correction D144 had to make
  // to the ink probe, needed again here: .tchartbox clips, so an svg child whose
  // box runs past it paints nothing past it.
  const clipped = function (e) {
    for (let a = e.parentElement; a; a = a.parentElement) {
      const cs = getComputedStyle(a);
      if (cs.overflowX === 'hidden' || cs.overflowX === 'clip') return true;
      if (a === row) break;
    }
    return false;
  };
  kids.concat([row]).forEach(function (e) {
    const b = e.getBoundingClientRect();
    if (b.width <= 0) return;
    if (clipped(e)) return;
    const o = Math.round(Math.max(b.right - docW, (e.scrollWidth || 0) - Math.ceil(b.width)));
    if (o > 0) whoOver.push(nameOf(e) + ' +' + o + ' (l' + Math.round(b.left) + ' r' + Math.round(b.right) + ' w' + Math.round(b.width) + ')');
    if (o > rowOver) rowOver = o;
  });
  return JSON.stringify({ hits: hits, boxW: svg ? Math.round(svg.getBoundingClientRect().width) : null,
    rowOverflow: Math.max(0, rowOver), whoOver: whoOver.slice(0, 6),
    pageOver: document.documentElement.scrollWidth - docW });
})()
'@
  $INK = $ink | ConvertFrom-Json
  Chk 'M' (-not $INK.err) "at 360: $($INK.err)"
  Chk 'M' (@($INK.hits).Count -eq 0) "at 360: label ink reaches a neighbour on $(@($INK.hits).Count) element(s) -- $(@($INK.hits) -join '; ')"
  # SCOPED, AND THE BASELINE RECORDED. The first version of this asserted that the
  # PAGE does not scroll horizontally at 360, and it failed -- on a 3 px overflow
  # that MEASURED IDENTICAL with the chart open, with the row collapsed, and with no
  # glucose in the store at all. The widest elements are .ttrail and .tleg, which
  # belong to Trends. Blaming the chart for that would be a gate failing the wrong
  # component, and widening the threshold to 3 px would be a gate learning to
  # tolerate whatever it found. So: the ROW is asserted at zero, and the PAGE is
  # asserted as no-worse-than-baseline. The Trends overflow is recorded as its own
  # finding rather than absorbed here.
  Chk 'M' ($INK.rowOverflow -eq 0) "at 360: the glucose row overflows by $($INK.rowOverflow)px -- $(@($INK.whoOver) -join '; ')"
  Chk 'M' ($INK.pageOver -le 3) "at 360: the page overflows horizontally by $($INK.pageOver)px with the chart open; the measured baseline WITHOUT any glucose is 3px (from .ttrail/.tleg in Trends), so anything beyond that is the chart's"
  Chk 'M' ($INK.boxW -ge 255 -and $INK.boxW -le 315) "at 360 the chart box is $($INK.boxW)px; measured ~298"
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Start-Sleep -Milliseconds 400

  # ---- E: TWO UNITS REFUSE ONE LINE ---------------------------------------
  Eval ("JSON.stringify(($fixture)(0.5, false, true))") | Out-Null
  Start-Sleep -Milliseconds 500
  Eval "(function(){var r=document.querySelector('#dayView .grow');if(r && !r.classList.contains('gopen')) HT.glucoseToggle('2026-09-26');return 1;})()" | Out-Null
  Start-Sleep -Milliseconds 400
  $mix = Eval "JSON.stringify((function(){var r=document.querySelector('#dayView .grow');return {text:r?(r.textContent||'').replace(/\s+/g,' ').trim():'',runs:r?r.querySelectorAll('polyline.tseries').length:-1,refused:!!(r&&r.querySelector('.tunitrefuse'))};})())"
  $MX = $mix | ConvertFrom-Json
  Chk 'M' ([bool]$MX.refused) "a series carrying two units drew anyway -- E ruled it REFUSES one line and says why"
  Chk 'M' ($MX.text -match '(?i)unit') "the refusal does not mention the unit, so it does not say WHY"

  # ===================== [I] INVENTED CADENCE ==============================
  $i = Eval ("JSON.stringify(($fixture)(11, true, false))")
  Start-Sleep -Milliseconds 900
  $I0 = $i | ConvertFrom-Json
  Chk 'I' ([bool]$I0.ok) "the invented-cadence fixture did not ingest ($($I0.stored) of $($I0.asked))"
  Eval "(function(){var r=document.querySelector('#dayView .grow');if(r && !r.classList.contains('gopen')) HT.glucoseToggle('2026-09-26');return 1;})()" | Out-Null
  Start-Sleep -Milliseconds 500

  foreach ($preset in @(@('3 days', 259200), @('10 days', 864000))) {
    $label = $preset[0]; $secs = [int]$preset[1]
    Eval "JSON.stringify(HT.chartPreset('$label'))" | Out-Null
    Start-Sleep -Milliseconds 500
    $got = Eval "(function(){var w=HT.chartWindow();return Math.round((w.to-w.from)/1000);})()"
    Chk 'I' ([Math]::Abs([int]$got - $secs) -le [int]($secs * 0.03)) "the '$label' preset set a $got s window, expected about $secs s"
    $red = Eval @'
(function () {
  const svg = document.querySelector('#dayView .grow svg.tchart');
  if (!svg) return JSON.stringify({ nodes: -1, runs: -1, boxW: 0 });
  const lines = Array.prototype.slice.call(svg.querySelectorAll('polyline.tseries'));
  return JSON.stringify({
    nodes: lines.reduce(function (a, l) {
      return a + (l.getAttribute('points') || '').trim().split(/\s+/).filter(function (s) { return s; }).length; }, 0),
    runs: lines.length, boxW: Math.round(svg.getBoundingClientRect().width) });
})()
'@
    $R = $red | ConvertFrom-Json
    Chk 'I' ($R.nodes -gt 0) "at '$label' the chart drew nothing"
    Chk 'I' ($R.nodes -le ($R.boxW * 2 + 12)) "at '$label' the chart drew $($R.nodes) nodes across $($R.boxW) columns -- C ruled a min/max envelope, so at most two per column (about $($R.boxW * 2)). Drawing all 2,880 is the cost the envelope exists to avoid"
    Chk 'I' ($R.runs -ge 2) "at '$label' the hole stopped breaking the line ($($R.runs) run) -- C ruled the envelope must NEVER bridge a gap"
    # C, ASSERTED IN PIXELS. The fixture carries a deliberate 16.4 and a 1.1, which
    # clip to the top and bottom of the declared 2-14 domain. With a min/max
    # envelope the drawn line still TOUCHES both edges; with a mean per column it
    # cannot, because the excursion is averaged against its neighbours. This is the
    # assertion that catches `(a.v + b.v) / 2` written inline -- the source grep
    # only catches an averaging word, and a defect does not have to be named.
    $ext = Eval @'
(function () {
  const svg = document.querySelector('#dayView .grow svg.tchart');
  if (!svg) return JSON.stringify({ err: 'no svg' });
  const ys = [];
  Array.prototype.slice.call(svg.querySelectorAll('polyline.tseries')).forEach(function (l) {
    (l.getAttribute('points') || '').trim().split(/\s+/).forEach(function (pt) {
      if (!pt) return;
      const y = parseFloat(pt.split(',')[1]);
      if (y === y) ys.push(y);
    });
  });
  const vb = (svg.getAttribute('viewBox') || '0 0 328 150').split(/\s+/).map(Number);
  return JSON.stringify({ minY: ys.length ? Math.min.apply(null, ys) : null,
                          maxY: ys.length ? Math.max.apply(null, ys) : null,
                          // FROM THE CODE, not a literal. padB moved 20 -> 24 for H23's
                          // time axis, and a hardcoded 20 here reported the plot floor
                          // 4 units below where the chart actually drew it.
                          h: vb[3], padT: HT.CHART_PAD.T, padB: HT.CHART_PAD.B });
})()
'@
    $EX = $ext | ConvertFrom-Json
    if ($EX.err) { $fails += "[I] at '$label': $($EX.err)" }
    else {
      $plotBottom = $EX.h - $EX.padB
      Chk 'I' ($EX.minY -le ($EX.padT + 2)) "at '$label' the drawn line never reaches the TOP of the plot (min y $($EX.minY), top $($EX.padT)) -- the fixture carries a value above the declared domain, so a min/max envelope must still touch the ceiling. A mean per column cannot, which is the defect C rejects and the source grep alone cannot see"
      Chk 'I' ($EX.maxY -ge ($plotBottom - 2)) "at '$label' the drawn line never reaches the BOTTOM of the plot (max y $($EX.maxY), bottom $plotBottom) -- same reason, for the value below the domain"
    }
  }

  # ---- A: THE CACHE IS OUTSIDE THE EXPORT, BY CONSTRUCTION ----------------
  $exp = Eval "JSON.stringify((function(){var j=HT.exportJSON();return {hasGlucose:/glucose/i.test(j),hasKey:/healthtracker-glucose/.test(j)};})())"
  $E = $exp | ConvertFrom-Json
  Chk 'M' (-not $E.hasGlucose) "the export carries a 'glucose' key -- A ruled a re-acquirable CACHE, excluded like the corpus"
  Chk 'M' (-not $E.hasKey) "the export mentions the glucose storage key"
  $sep = Eval "JSON.stringify((function(){try{return {inLS:!!localStorage.getItem('healthtracker-glucose'),inState:('glucose' in HT.state())};}catch(e){return {err:String(e)};}})())"
  $SEP = $sep | ConvertFrom-Json
  Chk 'M' ([bool]$SEP.inLS) "nothing is stored under the separate glucose key, so the cache is not where A ruled it"
  Chk 'M' (-not $SEP.inState) "glucose is inside APP_STATE -- being OUTSIDE it is what keeps it out of the export by construction rather than by a filter someone must remember"

  # ---- the one average that is allowed, and the one that is not -----------
  Chk 'M' ((Eval "String(typeof HT.timeChart)") -eq 'function') "HT.timeChart vanished mid-run"
  $smooth = Eval "JSON.stringify((function(){var s=String(HT.timeChart);return {mentionsSmooth:/smooth|movingAvg|moving_average|ema\\b/i.test(s)};})())"
  $SM = $smooth | ConvertFrom-Json
  Chk 'M' (-not $SM.mentionsSmooth) "the chart control contains smoothing -- the day's average WITH ITS COUNT is a statement about the day and is ruled in; an average used to DRAW the line hides the spike and stays rejected"

  # ======================= H23: READING THE CHART ===========================
  #
  # RE-SEEDS DELIBERATELY. These assertions need a PAST day and a NEWEST day in
  # one store, which the fixture above does not have; everything before this
  # point has already run. The past day gets a FULL 24h of readings so the
  # window's left edge coincides with its first reading -- measured the hard way:
  # 19h of data in a 24h window leaves the left 60 units empty, which parked the
  # above-domain spike clear of the axis label and let an ink test pass while
  # proving nothing. The spike's x is computed, not eyeballed.
  $h23 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const OLD = '2026-09-24';          // the day the row is opened FROM
  const NEW = '2026-09-26';          // the globally newest readings live here
  HT.setClock(function () { return Date.parse('2026-09-26T10:35:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(200);
  const S = HT.state();
  S.days[OLD] = { status: 'in_progress', water_l: 0, items: [
    { name: 'lentil stew', meal: 'lunch', time: '12:30', grams: 200, kcal: 420,
      protein_g: 20, fat_g: 8, carb_g: 60, fiber_g: 9, soluble_fiber_g: 2,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' }] };
  S.days[NEW] = { status: 'in_progress', water_l: 0, items: [] };
  S.timeline = S.timeline || {};
  S.timeline[OLD] = [{ time: '18:00', kind: 'event', type: 'sauna', source: 'manual',
                       notes: '', unit: 'min', value: 20 }];
  S.current = OLD;
  HT.glucoseClear();
  // A FULL 24h on the past day. The spike sits at i=3 (00:15), which lands at
  // x = 38 + (20/1440)*284 = 41.9 -- inside the 76.7-unit top label.
  const mk = function (dk, n, spike) {
    const rows = [];
    for (let i = 0; i < n; i++) {
      const mi = i * 5;
      const hh = String(Math.floor(mi / 60)).padStart(2, '0');
      const mm = String(mi % 60).padStart(2, '0');
      let v = 5.6 + 1.5 * Math.sin(i / 11);
      if (spike && i === 3) v = 18.4;      // ABOVE the 14 ceiling, under the label
      rows.push({ t: dk + 'T' + hh + ':' + mm + ':00-04:00', v: Math.round(v * 10) / 10, unit: 'mmol/L' });
    }
    return rows;
  };
  HT.glucoseIngest(mk(OLD, 288, true), { rawUnit: 'mmol<180.1558800000541>/L', source: 'Dexcom G7' });
  HT.glucoseIngest(mk(NEW, 40, false), { rawUnit: 'mmol<180.1558800000541>/L', source: 'Dexcom G7' });
  HT.refresh(); await sleep(300);
  if (!HT.glucoseIsOpen(OLD)) HT.glucoseToggle(OLD);
  await sleep(400);
  const q = function (sel) { return document.querySelector('#dayView .grow ' + sel); };
  const box = function (el) { const b = el.getBBox();
    return { x: b.x, y: b.y, r: b.x + b.width, b: b.y + b.height }; };
  const over = function (a, c) { return !(c.x > a.r || c.r < a.x || c.y > a.b || c.b < a.y); };
  const tickText = function () {
    const g = document.querySelector('#dayView .grow svg.tchart .txaxis');
    return g ? Array.prototype.slice.call(g.querySelectorAll('text'))
                 .map(function (t) { return (t.textContent || '').trim(); }).join('|') : '';
  };

  // TICK COMPARISON FIRST, because it has to change the preset and every other
  // measurement below must describe ONE state. Capturing geometry and then
  // changing the window reported two charts as though they were one.
  HT.chartPreset('6 h'); HT.glucoseRedraw(); await sleep(150);
  const ticks6 = tickText();
  HT.chartPreset('24 h'); HT.glucoseRedraw(); await sleep(150);
  const ticks24 = tickText();

  // ONE STATE, set deliberately, and everything after this reads it.
  HT.chartPreset('24 h'); HT.glucoseRedraw(); await sleep(250);
  const svg = q('svg.tchart');
  const labels = svg ? Array.prototype.slice.call(svg.querySelectorAll('.taxis text')) : [];
  const clips = svg ? Array.prototype.slice.call(svg.querySelectorAll('.tclip')) : [];
  const runs = svg ? Array.prototype.slice.call(svg.querySelectorAll('.tseries')) : [];
  let inkHits = 0, offCanvas = 0;
  labels.forEach(function (t) {
    const lb = box(t);
    if (lb.y < 0) offCanvas++;
    clips.concat(runs).forEach(function (el) { if (over(lb, box(el))) inkHits++; });
  });
  const xax = svg ? svg.querySelector('.txaxis') : null;
  let axOutsideBand = 0;
  if (xax) {
    Array.prototype.slice.call(xax.querySelectorAll('*')).forEach(function (el) {
      if (!el.getBBox) return;
      try { if (box(el).y < 150 - HT.CHART_PAD.B - 1) axOutsideBand++; } catch (e) { }
    });
  }
  return {
    viewedDay: OLD, newestDay: NEW,
    clipsInView: clips.length,
    labelCount: labels.length,
    labelTexts: labels.map(function (t) { return (t.textContent || '').trim(); }),
    inkHits: inkHits,
    offCanvas: offCanvas,
    windowLine: (q('.twindow') || {}).textContent || '',
    rowAge: (q('.gage') || {}).textContent || '',
    hasXAxis: !!xax,
    axOutsideBand: axOutsideBand,
    ticks6: ticks6, ticks24: ticks24,
    readoutCount: document.querySelectorAll('#dayView .grow .treadout').length,
    crossCount: document.querySelectorAll('#dayView .grow .tcross').length
  };
})()
'@
  if ($h23 -like 'EXCEPTION*') {
    $fails += "H23 fixture threw: $h23"
  } else {
    $H = $h23 | ConvertFrom-Json
    # One diagnostic line, always printed: when the ink assertion passes it
    # matters whether it passed because nothing collided or because nothing
    # was drawn, and the reader should not have to ask.
    Write-Host ("  [H23 fixture] clips-in-view={0} labels={1} ink-hits={2} off-canvas={3} xaxis={4}" -f `
      $H.clipsInView, ($H.labelTexts -join ' / '), $H.inkHits, $H.offCanvas, $H.hasXAxis)

    # THE FIXTURE MUST CONTAIN THE STATE (D96). If no clip is in view the ink
    # assertion below would pass by having nothing to collide with -- which is
    # exactly how this measurement fooled me twice before the x was computed.
    Chk 'M' ($H.clipsInView -ge 1) "H23-ink FIXTURE: no .tclip is in view, so the ink assertion has nothing to collide with and would pass for free. The above-domain spike is outside the drawn window"
    Chk 'M' ($H.inkHits -eq 0) "H23-ink: an axis label's box covers $($H.inkHits) piece(s) of chart ink. Measured before the fix: the 9-glyph '14 mmol/L' is 76.7 units against a 38-unit gutter and covers the above-domain CLIP MARKER -- the one mark D146 ruling D requires, saying a value left the declared range. Labels are numbers only; the unit belongs on the window line"
    Chk 'M' ($H.offCanvas -eq 0) "H23-ink: $($H.offCanvas) axis label(s) start above the viewBox (y < 0), so SVG trims the top of their glyphs"

    # 1. ANCHOR TO THE VIEWED DAY.
    Chk 'M' ($H.windowLine -match '9/24') "H23-day: the row was opened for $($H.viewedDay) and its window line does not name that day: '$($H.windowLine)'. H19-B ruled the right edge is the last reading without saying WHOSE; for a row attached to a day it is that day's"
    Chk 'M' ($H.windowLine -notmatch '9/26') "H23-day: the window line names $($H.newestDay), the globally newest day, while the row was opened for $($H.viewedDay): '$($H.windowLine)'"

    # 3. TWO AGES, TWO NAMES.
    Chk 'M' ($H.rowAge -match 'last reading this day') "H23-ages: the row does not say 'last reading this day': '$($H.rowAge)'"
    Chk 'M' ($H.windowLine -match 'newest reading held') "H23-ages: the window line does not say 'newest reading held': '$($H.windowLine)'"
    Chk 'M' ($H.rowAge -notmatch 'newest reading held') "H23-ages: the ROW uses the window line's phrase, so one name covers two quantities again"
    Chk 'M' ($H.windowLine -notmatch 'last reading this day') "H23-ages: the WINDOW LINE uses the row's phrase"

    # 5. THE TIME AXIS.
    Chk 'M' ([bool]$H.hasXAxis) "H23-axis: no .txaxis exists. 20 user units are reserved at the bottom and nothing is drawn in them"
    Chk 'M' ($H.axOutsideBand -eq 0) "H23-axis: $($H.axOutsideBand) time-axis element(s) draw above the reserved bottom band, so the axis is eating the plot"
    Chk 'M' (($H.ticks6 -ne '') -and ($H.ticks24 -ne '')) "H23-axis: the time axis renders no tick text at 6 h ('$($H.ticks6)') or 24 h ('$($H.ticks24)')"
    Chk 'M' ($H.ticks6 -ne $H.ticks24) "H23-axis: the ticks are identical at 6 h and 24 h ('$($H.ticks6)'), so they do not adapt to the zoom"

    # 2. ONE READOUT, ONE OWNER -- asserted as a COUNT, because the defect this
    # ruling prevents is two writers on one line.
    Chk 'M' ($H.readoutCount -le 1) "H23-readout: $($H.readoutCount) .treadout elements exist. One line, ONE owner -- two features writing one line is the shape that produced the two-ages defect"
  }

  # ---- 2b. TAP vs SWIPE, AND THE READOUT'S TWO SHAPES ---------------------
  #
  # Ruled: a tap (not a swipe) snaps a crosshair to the nearest moment and shows
  # value, time and nearest meal/event in ONE readout line. A tapped column
  # holding more than one reading states the RANGE, the span and the count --
  # never one value wearing false precision, which is the same refusal as the
  # rejected in-chart averaging ([[D146]] ruling C).
  #
  # Real Input.dispatchTouchEvent, because synthesizeScrollGesture is dead in
  # this build and a synthetic click would not exercise the movement threshold
  # that separates a tap from a pan.
  Eval "(function(){var r=document.querySelector('#dayView .grow');if(r)window.scrollTo(0,Math.max(0,r.getBoundingClientRect().top+window.scrollY-200));return 1;})()" | Out-Null
  Start-Sleep -Milliseconds 300
  # Coordinates AFTER the scroll. Before it they address a page that has moved.
  $g23 = (Eval "JSON.stringify((function(){var s=document.querySelector('#dayView .grow svg.tchart');if(!s)return null;var b=s.getBoundingClientRect();return {x:Math.round(b.left+b.width*0.5),y:Math.round(b.top+b.height*0.5),xlate:Math.round(b.left+b.width*0.965),w:Math.round(b.width),left:Math.round(b.left)};})())") | ConvertFrom-Json
  if ($null -eq $g23) {
    $fails += "H23-touch: no chart on screen to tap"
  } else {
    # --- the WIDE preset first: a column there holds many readings -----------
    Eval "HT.chartPreset('10 days'); HT.glucoseRedraw(); 1" | Out-Null
    Start-Sleep -Milliseconds 250
    Eval "(function(){var e=document.querySelector('#dayView .grow .treadout');if(e)e.remove();return 1;})()" | Out-Null
    # At 10 days a window anchored to the VIEWED day reaches back ten days,
    # and only its final day holds readings -- so the centre is empty and a
    # centre tap would exercise the nearest-reading fallback, never a range.
    Tap $g23.xlate $g23.y
    Start-Sleep -Milliseconds 250
    $r10 = (Eval "JSON.stringify((function(){var e=document.querySelector('#dayView .grow .treadout');return {n:document.querySelectorAll('#dayView .grow .treadout').length,cross:document.querySelectorAll('#dayView .grow .tcross').length,txt:e?(e.textContent||'').replace(/\s+/g,' ').trim():null};})())") | ConvertFrom-Json
    Chk 'I' ($r10.n -eq 1) "H23-tap: a real tap at the 10-day preset produced $($r10.n) readout element(s), expected exactly 1"
    Chk 'I' ($r10.cross -ge 1) "H23-tap: no .tcross crosshair was placed by a real tap"
    if ($r10.txt) {
      Chk 'I' ($r10.txt -match '\d+(\.\d+)?\u2013\d+(\.\d+)?') "H23-readout: a column holding many readings must state a RANGE (lo-hi), not one value wearing false precision: '$($r10.txt)'"
      Chk 'I' ($r10.txt -match '(?i)\d+\s*readings') "H23-readout: the range readout does not state its COUNT: '$($r10.txt)'"
      Chk 'I' ($r10.txt -match '\d{1,2}:\d{2}\s*\u2013\s*\d{1,2}:\d{2}|\d{1,2}:\d{2}-\d{1,2}:\d{2}') "H23-readout: the range readout does not state the TIME SPAN it covers: '$($r10.txt)'"
      Chk 'I' ($r10.txt -match 'mmol/L') "H23-readout: the readout does not name the unit, which the axis no longer carries: '$($r10.txt)'"
    } else {
      $fails += "[I] H23-readout: a real tap at the 10-day preset showed no readout at all"
    }

    # --- ZOOMING IN turns the range into a single reading --------------------
    # NO SECOND TAP. The pick is a moment; the readout is derived from it at the
    # current zoom, so this is the ruling tested literally rather than two
    # separate taps that happen to differ.
    Eval "HT.chartPreset('6 h'); HT.glucoseRedraw(); 1" | Out-Null
    Start-Sleep -Milliseconds 300
    $r6 = (Eval "JSON.stringify((function(){var e=document.querySelector('#dayView .grow .treadout');return {n:document.querySelectorAll('#dayView .grow .treadout').length,txt:e?(e.textContent||'').replace(/\s+/g,' ').trim():null};})())") | ConvertFrom-Json
    Chk 'M' ($r6.n -eq 1) "H23-tap: after zooming to 6 h a tap produced $($r6.n) readout element(s), expected exactly 1 -- one line, one owner"
    if ($r6.txt) {
      Chk 'M' ($r6.txt -notmatch '\d+(\.\d+)?\u2013\d+(\.\d+)?') "H23-readout: zoomed to 6 h a column holds ONE reading, so the readout must state its exact value, not a range: '$($r6.txt)'"
      Chk 'M' ($r6.txt -notmatch '(?i)readings') "H23-readout: a single-reading readout should not report a count of readings: '$($r6.txt)'"
      Chk 'M' ($r6.txt -match '\d{1,2}:\d{2}') "H23-readout: the single-reading readout does not state its time: '$($r6.txt)'"
    } else {
      $fails += "[M] H23-readout: a tap at the 6 h preset showed no readout"
    }

    # --- A SWIPE STILL PANS, AND SHOWS NOTHING ------------------------------
    # CLEAR THE STATE, not the element. Removing the rendered line left
    # CHART_PICK set, so the pan's own redraw re-rendered the readout from it and
    # the assertion below blamed the swipe for something the previous tap owned.
    Eval "HT.chartPickSet(null); 1" | Out-Null
    Start-Sleep -Milliseconds 150
    $w0 = Eval "JSON.stringify(HT.chartWindow())"
    $sx = $g23.x
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $sx; y = $g23.y }) } | Out-Null
    foreach ($dx in 14, 30, 48, 66) {
      Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchMove'; touchPoints = @(@{ x = ($sx - $dx); y = $g23.y }) } | Out-Null
      Start-Sleep -Milliseconds 30
    }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 300
    $w1 = Eval "JSON.stringify(HT.chartWindow())"
    $sw = (Eval "JSON.stringify({n:document.querySelectorAll('#dayView .grow .treadout').length})") | ConvertFrom-Json
    Chk 'M' ($w0 -ne $w1) "H23-swipe: a real horizontal swipe did not move the window ($w0 -> $w1), so the pan the tap must be distinguished FROM is not happening"
    Chk 'M' ($sw.n -eq 0) "H23-swipe: a swipe produced a readout. A tap is distinguished from a pan by a movement threshold, as the axis lock already does -- without that, panning the chart keeps firing a readout nobody asked for"
  }

  # ---- 6. PANNING AWAY FROM THE OPENED DAY, AND THE WAY BACK ---------------
  #
  # Ruled: scrolling through time IS the feature, so panning beyond the opened
  # day is allowed. Two things have to hold while it does -- the window line
  # always names the VISIBLE window, and when the opened day is no longer on
  # screen there is a one-tap way back. A preset tap re-anchors by itself
  # (chartPreset reads chartAnchorMs), so "back to <day>" covers the case of
  # panning away WITHOUT changing zoom. No forward counterpart: reaching a
  # distant day is the date jump's job, not the chart's.
  $pan = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const OLD = '2026-09-24';
  HT.state().current = OLD;
  HT.chartPickSet(null);
  HT.chartPreset('24 h'); HT.glucoseRedraw(); await sleep(200);
  const q = function (sel) { return document.querySelector('#dayView .grow ' + sel); };
  const line0 = (q('.twindow') || {}).textContent || '';
  const back0 = document.querySelectorAll('#dayView .grow .tback').length;

  // Pan forward by two days: the opened day leaves the window entirely.
  HT.chartPanMs(2 * 86400000); HT.glucoseRedraw(); await sleep(200);
  const line1 = (q('.twindow') || {}).textContent || '';
  const back1 = document.querySelectorAll('#dayView .grow .tback').length;
  const backEl = q('.tback');
  const backTxt = backEl ? (backEl.textContent || '').replace(/\s+/g, ' ').trim() : null;
  const w1 = HT.chartWindow();

  // The one tap back.
  if (typeof HT.chartBackToDay === 'function') HT.chartBackToDay();
  await sleep(250);
  const line2 = (q('.twindow') || {}).textContent || '';
  const back2 = document.querySelectorAll('#dayView .grow .tback').length;
  const w2 = HT.chartWindow();

  // And a PRESET tap re-anchors on its own, from a panned-away window.
  HT.chartPanMs(3 * 86400000); HT.glucoseRedraw(); await sleep(150);
  const backAway = document.querySelectorAll('#dayView .grow .tback').length;
  const wAway = HT.chartWindow();
  HT.chartPreset('6 h'); await sleep(200);
  const back3 = document.querySelectorAll('#dayView .grow .tback').length;
  const w3 = HT.chartWindow();

  if (typeof HT.dayKeyMs !== 'function') return { err: 'HT.dayKeyMs is not exported, so the day span cannot be computed and every overlap assertion below would read false for the wrong reason' };
  const dayFrom = HT.dayKeyMs(OLD);
  const dayTo = dayFrom == null ? null : dayFrom + 86400000;
  const overlaps = function (w) {
    return dayFrom != null && w.from < dayTo && w.to > dayFrom;
  };
  return {
    openedDay: OLD,
    line0: line0, line1: line1, line2: line2,
    back0: back0, back1: back1, back2: back2, back3: back3, backAway: backAway,
    backTxt: backTxt,
    overlap1: overlaps(w1), overlap2: overlaps(w2), overlap3: overlaps(w3),
    overlapAway: overlaps(wAway),
    hasFn: typeof HT.chartBackToDay === 'function'
  };
})()
'@
  if ($pan -like 'EXCEPTION*') {
    $fails += "H23-pan fixture threw: $pan"
  } else {
    $PN = $pan | ConvertFrom-Json
    if ($PN.err) { $fails += "[M] H23-pan: $($PN.err)" }
    Chk 'M' ([bool]$PN.hasFn) "H23-pan: HT.chartBackToDay does not exist"
    # THE WINDOW LINE FOLLOWS THE WINDOW.
    Chk 'M' ($PN.line0 -ne $PN.line1) "H23-pan: the window line did not change after panning two days ('$($PN.line1)') -- it must always name the VISIBLE window, not the one the row opened on"
    Chk 'M' (-not $PN.overlap1) "H23-pan fixture: panning two days did not take the opened day off screen, so the assertions below are about the wrong state"
    # THE WAY BACK, ONLY WHEN IT IS NEEDED.
    Chk 'M' ($PN.back0 -eq 0) "H23-pan: a 'back to the day' control is showing while the opened day is still in view -- it is for panning AWAY, not furniture"
    Chk 'M' ($PN.back1 -eq 1) "H23-pan: $($PN.back1) back-to-day control(s) after the opened day left the window, expected exactly 1"
    Chk 'M' ($PN.backTxt -match '(?i)back') "H23-pan: the control does not say it goes back: '$($PN.backTxt)'"
    Chk 'M' ($PN.backTxt -match '9/24|09/24|Sep') "H23-pan: the control does not NAME the day it returns to ('$($PN.backTxt)') -- 'back' alone makes the user guess which day they left"
    Chk 'M' ([bool]$PN.overlap2) "H23-pan: one tap on the control did not bring the opened day back into the window"
    Chk 'M' ($PN.back2 -eq 0) "H23-pan: the control is still showing after it returned to the opened day"
    Chk 'M' ($PN.line1 -ne $PN.line2) "H23-pan: the window line did not change when the control returned to the opened day"
    # A PRESET TAP RE-ANCHORS BY ITSELF.
    Chk 'M' (-not $PN.overlapAway) "H23-pan fixture: the second pan did not take the opened day off screen, read from the WINDOW rather than from the control -- using the control's presence as the fixture's evidence made a broken control report a fixture problem"
    Chk 'M' ($PN.backAway -eq 1) "H23-pan: the control did not appear after the second pan"
    Chk 'M' ([bool]$PN.overlap3) "H23-pan: tapping a preset from a panned-away window did not re-anchor to the opened day -- chartPreset reads chartAnchorMs, so this is the behaviour that makes a forward counterpart unnecessary"
    Chk 'M' ($PN.back3 -eq 0) "H23-pan: the control still shows after a preset tap re-anchored the window"
  }

  # ---- 4. A FUTURE TIMESTAMP IS A DATA ERROR, NEVER FRESHNESS --------------
  $fut = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const DK = '2026-09-26';
  HT.glucoseClear();
  // Deliberately 40 minutes AHEAD of the mocked clock (10:35).
  HT.glucoseIngest([{ t: DK + 'T11:15:00-04:00', v: 5.6, unit: 'mmol/L' }],
                   { rawUnit: 'mmol<180.1558800000541>/L', source: 'Dexcom G7' });
  HT.state().current = DK;
  HT.refresh(); await sleep(300);
  const row = document.querySelector('#dayView .grow');
  return { age: row ? ((row.querySelector('.gage') || {}).textContent || '') : null,
           words: HT.ageWords(-2400000) };
})()
'@
  if ($fut -like 'EXCEPTION*') {
    $fails += "H23 future-timestamp fixture threw: $fut"
  } else {
    $F = $fut | ConvertFrom-Json
    Chk 'M' ($F.words -notmatch '(?i)just now') "H23-future: ageWords on a NEGATIVE age returns '$($F.words)' -- a reading dated after the clock is a data error, not freshness"
    Chk 'M' ($F.words -match '(?i)ahead|future') "H23-future: ageWords on a negative age does not say the reading is ahead of the clock: '$($F.words)'"
    Chk 'M' ($F.age -notmatch '(?i)just now') "H23-future: the ROW renders a future reading as '$($F.age)'"
  }

  if ($fails.Count) {
    Write-Host "CHART GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Write-Host ""
    Write-Host "assertions run: $($ran['M']) on MEASURED cadence, $($ran['I']) on INVENTED cadence"
    Cleanup
    exit 1
  }
  Write-Host "CHART GATE: PASS -- $($ran['M']) assertions on MEASURED cadence (300 s step, instantaneous samples, one 50-min hole: the real export's time structure, with synthetic values) and $($ran['I']) on INVENTED cadence (the same step extended past the export's span, for the 3-day and 10-day presets only)."
  Write-Host "  THE 3-DAY AND 10-DAY PRESETS HAVE NEVER BEEN EXERCISED AGAINST REAL DATA -- the one-off export is far shorter than either. A green run says less about them than about 6 h and 24 h, which is the whole reason this line counts them separately."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
