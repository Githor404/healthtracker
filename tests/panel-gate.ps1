# D140 -- THE NUTRIENT PANEL: the label INK must never reach the value.
#
# REPORTED FROM THE DEVICE: "Protein" drawn over "22.85 g", "Theobromine" over
# "0.00", and the same for Carbohydrate, Sugars and Monounsaturated.
#
# MEASURED on the shipped page: 26 of 46 rows at 390x844 and 28 of 46 at
# 360x800 had label ink crossing the value. "Monounsaturated" ran 47px past it.
#
# AND THE RECT SAID EVERYTHING WAS FINE. Every one of those rows kept a tidy 8px
# gap between the label BOX and the value BOX: the box had been squeezed to 36px
# while its text needed 52px, and the glyphs spilled out. The gate asked for --
# rect-vs-rect disjointness -- would have PASSED all 46 broken rows.
#
#   OVERFLOW CANNOT SEE OVERLAP, AND THE BOX CANNOT SEE THE INK.
#
# That is the third time a layout gate passed something unreadable (the starved
# column, the fold, this), so the property gated here is the one that was
# actually violated: scrollWidth, not getBoundingClientRect().
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8189
$Dbg = 9395
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-panelgate-" + [System.Guid]::NewGuid().ToString('N'))
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
    if (++$guard -gt 2000) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
function EvalAsyncB64([string]$js) {
  $j = $js -replace "`r`n", "`n"
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($j))
  $expr = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text + " " + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (-not (Test-Path (Join-Path $repo 'corpus/dist/cnf.bin'))) {
  Write-Host "ERROR: corpus/dist/cnf.bin is missing -- run corpus/encode.py first"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
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

$fails = @()
try {
  Start-Sleep -Milliseconds 600
  $cargs = @("--headless=new", "--remote-debugging-port=$Dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $cargs -PassThru
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
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $setup = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.boot();
  await sleep(300);
  await HT.corpusEnsure();
  // Fixture-synthetic forever (CLAUDE.md). TWO items so some rows carry a
  // combined figure and others do not -- which is what makes a row's coverage
  // DIFFER from the rest, the only case where repeating it says anything.
  const DK = '2026-09-26';
  const S = HT.state();
  const v = {};
  [203,204,205,207,208,221,255,262,263,268,269,291,301,303,304,305,306,307,309,312,
   318,319,320,328,401,404,405,406,409,415,417,418,431,601,606,617,618,621,631,645,
   646,806,815,832,854,861].forEach(function (s, i) { v[String(s)] = (i * 7.31) % 97; });
  v['203'] = 22.85; v['208'] = 520; v['268'] = 2175.6; v['207'] = 1.45; v['318'] = 120;
  S.days[DK] = { status: 'in_progress', water_l: 0, items: [
    { name: 'spaghetti', meal: 'lunch', time: '12:30', grams: 200, kcal: 520,
      protein_g: 22.85, fat_g: 3.2, carb_g: 88.4, fiber_g: 5.1, soluble_fiber_g: 1,
      confidence: 'eyeballed', source: 'ai-paste', notes: '',
      ref: { ns: 'cnf', id: '4464', name: 'Pasta, spaghetti, enriched, cooked',
             at: DK, at_ms: 1, hash: 'h', how: 'picked',
             attribution: 'Canadian Nutrient File, Health Canada, 2015', v: v } },
    { name: 'Oat Crackers', meal: 'snack', time: '13:00', grams: 30, kcal: 140,
      protein_g: 3, fat_g: 5, carb_g: 20, fiber_g: 2, soluble_fiber_g: 0,
      confidence: 'measured', source: 'scan', notes: '', barcode: '00000000',
      micros: { sodium_mg: 180, iron_mg: 1.2, calcium_mg: 20 } } ] };
  S.current = DK;
  HT.refresh();
  await sleep(400);
  const det = document.querySelector('details.mpanel');
  if (det) { det.open = true; HT.panelToggle(true); }
  await sleep(500);
  return { ok: true, rows: document.querySelectorAll('.prow').length };
})()
'@
  $s0 = EvalAsyncB64 $setup
  if ($s0 -like 'EXCEPTION*') { Write-Host "ERROR: setup threw: $s0"; Cleanup; exit 2 }

  $probe = @'
(function () {
  const OUT = { rows: [], labels: [], fonts: [] };
  const rows = Array.prototype.slice.call(document.querySelectorAll('.prow'));
  rows.forEach(function (row) {
    const n = row.querySelector('.pname'), v = row.querySelector('.pval');
    if (!n || !v) return;
    const a = n.getBoundingClientRect(), b = v.getBoundingClientRect();
    // THE INK, not the box: scrollWidth is where the text actually ends.
    const inkRight = a.left + n.scrollWidth;
    const overlapY = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    OUT.rows.push({
      label: (n.textContent || '').trim().slice(0, 30),
      value: (v.textContent || '').trim().slice(0, 18),
      inkPast: Math.round(inkRight - b.left),
      overlapsY: overlapY > 0.5,
      overflows: n.scrollWidth > n.clientWidth + 1,
      chars: (n.textContent || '').trim().length,
      boxW: Math.round(a.width)
    });
  });
  OUT.labels = rows.map(function (r) {
    const n = r.querySelector('.pname'); return n ? (n.textContent || '').trim() : ''; });
  OUT.covAll = document.querySelectorAll('.pcovall').length;
  OUT.covRow = document.querySelectorAll('.pcov').length;
  OUT.altCount = document.querySelectorAll('.palt').length;
  // A closed <details> keeps a bounding rect (content-visibility), so the only
  // honest test of "collapsed" is checkVisibility -- D139's instrument lesson.
  const ab = document.querySelector('.paltbody');
  OUT.altBodyText = ab ? (ab.textContent || '').trim() : '';
  OUT.altCollapsed = ab ? !(typeof ab.checkVisibility === 'function'
      ? ab.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true, visibilityProperty: true })
      : ab.getBoundingClientRect().height > 0) : false;
  const det = document.querySelector('.palt');
  // open it, then FORCE A LAYOUT before asking -- checkVisibility answers from
  // the last computed layout, and nothing has recomputed it yet.
  if (det) { det.open = true; void det.offsetHeight; }
  const ab2 = document.querySelector('.paltbody');
  if (ab2) { void ab2.offsetHeight; }
  OUT.altOpensVisible = ab2 ? (typeof ab2.checkVisibility === 'function'
      ? ab2.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true, visibilityProperty: true })
      : ab2.getBoundingClientRect().height > 0) : false;
  if (det) { det.open = false; }
  ['.pname', '.pval', '.pcov', '.pcovall', '.palt > summary', '.paltbody'].forEach(function (sel) {
    const e = document.querySelector(sel);
    if (e) OUT.fonts.push({ sel: sel, px: Math.round(parseFloat(getComputedStyle(e).fontSize) * 10) / 10 });
  });
  return OUT;
})()
'@
  function Probe([int]$w, [int]$h) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 2; mobile = $true } | Out-Null
    Start-Sleep -Milliseconds 700
    $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $probe; returnByValue = $true }
    if ($r.result.exceptionDetails) { throw "probe threw at ${w}px: $($r.result.exceptionDetails.text)" }
    return $r.result.result.value
  }

  $R390 = Probe 390 844
  $R360 = Probe 360 800

  foreach ($pair in @(@(390, $R390), @(360, $R360))) {
    $w = $pair[0]; $R = $pair[1]
    $rows = @($R.rows)
    # D96: the sweep must have something to sweep.
    if ($rows.Count -lt 30) {
      $fails += "${w}px: only $($rows.Count) panel rows rendered -- too few for this gate to mean anything"
      continue
    }
    # ...and the fixture must make the wrong behaviour POSSIBLE: a label long
    # enough that a starved column would overflow it.
    $longest = ($rows | Sort-Object chars -Descending | Select-Object -First 1)
    if ($longest.chars -lt 14) {
      $fails += "${w}px: the longest label is only $($longest.chars) characters -- the fixture cannot reproduce the defect (D96)"
    }
    $over = @($rows | Where-Object { $_.inkPast -gt 0.5 -and $_.overlapsY })
    if ($over.Count) {
      $worst = ($over | Sort-Object inkPast -Descending | Select-Object -First 3 |
                ForEach-Object { "'" + $_.label + "' over '" + $_.value + "' by " + $_.inkPast + "px" }) -join '; '
      $fails += "${w}px: LABEL INK REACHES THE VALUE on $($over.Count) of $($rows.Count) rows -- $worst"
    }
    $spill = @($rows | Where-Object { $_.overflows })
    if ($spill.Count) {
      $fails += "${w}px: $($spill.Count) label(s) overflow their own box (scrollWidth > clientWidth) -- the box is not the ink, and a box that cannot hold its text will paint outside it"
    }
  }

  # ---- what D118 ruled off the surface ------------------------------------
  $labels = @($R390.labels)
  if ($labels -match '^Ash') { $fails += "Ash is listed as a nutrient row -- D118: not a nutrient at all, an analytical residue" }
  if ($labels -match 'kJ')   { $fails += "Energy (kJ) is a sibling row -- D118: the same quantity in another unit is an alternate expression, not a second nutrient" }
  if ($labels -match '\(IU\)') { $fails += "Vitamin A (IU) is a sibling row -- same class as kJ, and D118 named it" }

  # ...but OFF THE SURFACE IS NOT OUT OF REACH. Existence is not availability,
  # and neither is availability existence: the kJ figure must still be there.
  if ($R390.altCount -lt 1) { $fails += "no alternate-unit disclosure rendered at all -- kJ was removed rather than moved" }
  if ($R390.altBodyText -notmatch 'kJ') { $fails += "the alternate disclosure does not carry the kJ figure (text: '$($R390.altBodyText)')" }
  if (-not $R390.altCollapsed) { $fails += "the alternate units are NOT collapsed -- 'beside calories on tap' means on tap" }
  if (-not $R390.altOpensVisible) { $fails += "the alternate units do not become visible when opened -- present but unreachable" }

  # ---- the coverage line: once, not on every row --------------------------
  if ($R390.covAll -ne 1) { $fails += "the panel states its coverage $($R390.covAll) times at the top -- it must say it exactly once" }
  if ($R390.covRow -ge @($R390.rows).Count) {
    $fails += "the coverage line is repeated on $($R390.covRow) of $(@($R390.rows).Count) rows -- it was on all 46 on the device, and it is what starved the labels"
  }
  if ($R390.covRow -lt 1) {
    $fails += "NO row states its own coverage -- a row whose coverage differs from the rest must still say so, or the summary at the top is a lie about that row"
  }

  # ---- D124's floor, on the classes this slice added ----------------------
  foreach ($f in @($R390.fonts)) {
    if ($f.px -lt 16) { $fails += "16px floor: $($f.sel) computes to $($f.px)px" }
  }
  if (@($R390.fonts).Count -lt 6) { $fails += "only $(@($R390.fonts).Count) of 6 panel classes were found to measure -- coverage before the floor (D124)" }

  if ($fails.Count) {
    Write-Host "PANEL GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "PANEL GATE: PASS -- $(@($R390.rows).Count) rows, no label ink reaches its value at 390 or 360; coverage stated once; kJ and IU on tap; Ash off the surface"
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
