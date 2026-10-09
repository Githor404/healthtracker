# D144 -- PRESENTATION SLICE 2: the collapsed row.
#
# Ruled: A2 the headline is the user's primaryNutrient (default kcal), so the row
# agrees with the ring. B1 tap expands in place; edit is one tap deeper. P1 the
# photo draft's identity control collapses once idDone.
#
# EVERY THRESHOLD IS A MEASURED BASELINE, taken on the fixture it gates.
#
#  DAY ROW, before (390x844, six items incl. matched / unresolved / lost-match):
#    heights 117 / 146 median / 278 max, 5-13 visible facts
#    parts: .mname 24-48 (wraps), .mmeta 48-72 (2-3 lines), .mref 108, .mlost 72
#    0 of 6 rows fully visible; page 4,404px = 5.2 screens; total 2.4 screens down
#    INK COLLISIONS: ZERO at 390 and 360 -- so zero is a no-regression line here,
#    not a tolerance, and this gate asserts INK rather than boxes because a box
#    kept its tidy gap on 26 unreadable panel rows (D140).
#
#  PHOTO DRAFT, before: rows 237-287px, of which .pmid-wrap is 122-172px.
#    A six-item save is 1,385px of rows; settling every identity leaves 575px.
#    `idDone` is already recorded and changes nothing today.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8217
$Dbg = 9423
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-collapse-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

function Find-Browser {
  foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null }
function Receive-One {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count); if ($res.EndOfMessage) { break } }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json) }
function Invoke-CDP([string]$m, [hashtable]$p) {
  $script:cid++; $pl = @{ id = $script:cid; method = $m }; if ($p) { $pl.params = $p }
  $b = [Text.Encoding]::UTF8.GetBytes(($pl | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($b), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $g = 0
  while ($true) { if (++$g -gt 3000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg } } }
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (-not (Test-Path (Join-Path $repo 'corpus/dist/cnf.bin'))) {
  Write-Host "ERROR: corpus/dist/cnf.bin is missing"; exit 2 }

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
    try { $ctx.Response.Close() } catch { } } }
function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { } }

$fails = @()
try {
  Start-Sleep -Milliseconds 600
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 400
    try { $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break } } catch { } }
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

  # Six items covering every row shape the collapse has to handle: a matched row
  # (the 278px one), an unresolved row, a no-macros row, a scanned row, a
  # lost-match row and the auto supplement.
  $fixture = @'
(function (primary) {
  const DK = '2026-09-26'; const S = HT.state();
  const REF = { ns: 'cnf', id: '4464', name: 'Pasta, spaghetti, enriched, cooked',
    at: DK, at_ms: 1, hash: 'h', how: 'proposed', when: 'capture', g: 200,
    attribution: 'Canadian Nutrient File, Health Canada, 2015',
    v: { '203': 22.85, '208': 520, '301': 22, '307': 5 } };
  const base = function (o) { return Object.assign({ meal: 'lunch', time: '12:30', grams: 200,
    kcal: 520, protein_g: 22.85, fat_g: 3.2, carb_g: 88.4, fiber_g: 5.1, soluble_fiber_g: 1,
    confidence: 'eyeballed', source: 'ai-paste', notes: '' }, o); };
  S.days[DK] = { status: 'in_progress', water_l: 0, items: [
    base({ name: 'spaghetti with a long enough name to wrap', ref: REF }),
    base({ name: 'chashu pork belly' }),
    { name: 'mystery side', meal: 'lunch', time: '12:31', grams: 80, unresolved: true,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' },
    base({ name: 'Oat Crackers', confidence: 'measured', source: 'scan',
           barcode: '00000000', micros: { sodium_mg: 180, iron_mg: 1.2 } }),
    base({ name: 'repeated lentils', repeated_from: { date: '2026-09-22',
           name: 'cooked brown lentils', lostMatch: true } }),
    base({ name: 'Vitamin D3', meal: 'supplement', time: '09:00', source: 'supplement', _auto: true })
  ] };
  S.current = DK;
  S.settings = S.settings || {};
  S.settings.primaryNutrient = primary || '';
  HT.refresh();
  return { rows: document.querySelectorAll('.mitem').length, primary: primary || '(unset)' };
})
'@
  $boot = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T12:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  // R159.1/A4: the day renders one COLLAPSED header per meal kind, so an item row
  // does not exist until its group is tapped. This gate sweeps those rows, so it
  // opens them -- once, with the sticky seam, which keeps later seeding swept too.
  if (typeof HT.dayGroupsOpenAll === 'function') HT.dayGroupsOpenAll();
  await HT.corpusEnsure(); await sleep(150);
  return { ok: true };
})()
'@
  $b0 = EvalA $boot
  if ($b0 -like 'EXCEPTION*') { Write-Host "ERROR: boot threw: $b0"; Cleanup; exit 2 }

  $probe = @'
(function () {
  const O = { rows: [], ink: [], fonts: [] };
  const VH = window.innerHeight;
  function visible(el) {
    if (typeof el.checkVisibility === 'function')
      return el.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true, visibilityProperty: true });
    const cs = getComputedStyle(el), r = el.getBoundingClientRect();
    return cs.display !== 'none' && cs.visibility !== 'hidden' && r.width > 0 && r.height > 0;
  }
  // INK, not boxes: a box kept its tidy 8px gap on 26 unreadable panel rows (D140).
  function inkOver(root) {
    const hits = [];
    const kids = Array.prototype.slice.call(root.querySelectorAll('*'));
    kids.forEach(function (el) {
      let t = '';
      for (let j = 0; j < el.childNodes.length; j++)
        if (el.childNodes[j].nodeType === 3) t += el.childNodes[j].nodeValue;
      if (!t.replace(/\s+/g, ' ').trim()) return;
      if (!visible(el)) return;
      if (el.scrollWidth <= el.clientWidth + 1) return;
      // A CLIPPED element is not an OVERFLOWING one. With `overflow:hidden` the
      // browser paints nothing past the box edge, so scrollWidth > clientWidth
      // here reports a TRUNCATION, not a collision -- and D144's collapsed name
      // is truncated by design, with the whole name one tap away and in `title`.
      // This NARROWS the probe to what D140 built it to catch (a box keeping its
      // tidy gap while the ink escaped); it does not widen what passes. Without
      // it the probe would report 'the ellipsis overlaps the time by 90px' on a
      // row where nothing is painted there at all -- the fourth instrument in
      // three slices to answer a question it was not measuring.
      const oc = getComputedStyle(el);
      if (oc.overflowX === 'hidden' || oc.overflowX === 'clip') return;
      const a = el.getBoundingClientRect();
      const inkRight = a.left + el.scrollWidth;
      kids.forEach(function (ot) {
        if (ot === el || el.contains(ot) || ot.contains(el) || !visible(ot)) return;
        const b = ot.getBoundingClientRect();
        if (b.width <= 0 || b.height <= 0) return;
        const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (oy > 0.5 && inkRight - b.left > 0.5)
          hits.push({ over: Math.round(inkRight - b.left),
                      from: String(el.className || el.tagName).slice(0, 20),
                      onto: String(ot.className || ot.tagName).slice(0, 20) });
      });
    });
    return hits;
  }
  const rows = Array.prototype.slice.call(document.querySelectorAll('.mitem'));
  rows.forEach(function (row, i) {
    const r = row.getBoundingClientRect();
    const facts = [];
    row.querySelectorAll('*').forEach(function (el) {
      let t = '';
      for (let j = 0; j < el.childNodes.length; j++)
        if (el.childNodes[j].nodeType === 3) t += el.childNodes[j].nodeValue;
      t = t.replace(/\s+/g, ' ').trim();
      if (t && visible(el)) facts.push(t.slice(0, 44));
    });
    const line = row.querySelector('.mline');
    // ONE LINE, MEASURED AS ONE LINE. The 60px budget below admits TWO lines of
    // 16px text (24+24+8+1 = 57), so a plant that let the name wrap passed it --
    // a height budget says "short", which is not the claim the ruling made.
    // `nameLines` is the name's own box against one line-box of its own
    // line-height; `headRows` is the number of distinct offsetTops among the
    // three parts, which catches a part dropping to a second row even when the
    // name itself did not wrap.
    const nm = row.querySelector('.mline .mname');
    let nameLines = null;
    if (nm) {
      const lh = parseFloat(getComputedStyle(nm).lineHeight);
      const one = (lh === lh && lh > 0) ? lh : parseFloat(getComputedStyle(nm).fontSize) * 1.5;
      nameLines = Math.max(1, Math.round(nm.getBoundingClientRect().height / one));
    }
    const parts = line ? Array.prototype.slice.call(line.querySelectorAll('.mname, .mtime, .mnum, .rchip')) : [];
    const tops = {};
    parts.forEach(function (e) {
      if (e.getBoundingClientRect().height > 0) tops[Math.round(e.getBoundingClientRect().top)] = 1;
    });
    O.rows.push({ i: i, h: Math.round(r.height), facts: facts.length, texts: facts,
                  expanded: row.classList.contains('mopen'),
                  // THE ROUTE, and whether the row has a number at all: a row
                  // reading "--" with its only way to a number hidden behind a tap
                  // is a dead end, so the slot carries one or the other.
                  nameLines: nameLines,
                  headRows: Object.keys(tops).length,
                  routeOnLine: !!(line && line.querySelector('.rchip')),
                  hasNum: !!(line && line.querySelector('.mnum')),
                  numText: ((line && line.querySelector('.mnum')) || {}).textContent || '',
                  name: ((row.querySelector('.mname') || {}).textContent || '').trim().slice(0, 34) });
    Array.prototype.push.apply(O.ink, inkOver(row));
  });
  ['.mname', '.mhead', '.mnum', '.mmeta', '.mref', '.mkcal', '.mlost', '.msrc', '.rchip']
    .forEach(function (sel) {
      const e = document.querySelector('.mitem ' + sel);
      O.fonts.push({ sel: sel, px: e ? Math.round(parseFloat(getComputedStyle(e).fontSize) * 10) / 10 : null });
    });
  const dt = document.querySelector('.daytot');
  if (dt) O.dayTotalTop = Math.round(dt.getBoundingClientRect().top + window.scrollY);
  O.pageH = Math.round(document.body.scrollHeight);
  O.vh = VH;
  O.rowSum = O.rows.reduce(function (a, r) { return a + r.h; }, 0);
  return O;
})()
'@
  function Probe([int]$w, [int]$h) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 2; mobile = $true } | Out-Null
    Start-Sleep -Milliseconds 700
    Eval 'window.scrollTo(0,0); 1' | Out-Null
    Start-Sleep -Milliseconds 150
    $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $probe; returnByValue = $true }
    if ($r.result.exceptionDetails) { throw "probe threw at ${w}: $($r.result.exceptionDetails.text)" }
    return $r.result.result.value
  }

  # =============== A2 + B1: the COLLAPSED day row ==========================
  Eval ("($fixture)('')") | Out-Null
  Start-Sleep -Milliseconds 600
  $C390 = Probe 390 844
  $C360 = Probe 360 800

  # the measured baseline was 117 / 146 median / 278 max. A collapsed row is one
  # line, and it must still be a TAP TARGET -- two-sided, so "compact" cannot be
  # satisfied by making it unusable.
  $COLLAPSED_MAX = 60
  $COLLAPSED_MIN = 44
  foreach ($pair in @(@(390, $C390), @(360, $C360))) {
    $w = $pair[0]; $R = $pair[1]
    if (@($R.rows).Count -lt 6) {
      $fails += "${w}px: only $(@($R.rows).Count) rows rendered -- the six-shape fixture did not stand up (D96)"
      continue
    }
    foreach ($row in @($R.rows)) {
      if ($row.expanded) { continue }
      if ($row.h -gt $COLLAPSED_MAX) {
        $fails += "${w}px: collapsed row '$($row.name)' is $($row.h)px against a budget of $COLLAPSED_MAX -- the measured baseline was 117-278px and the ruling is name, time, one number"
      }
      if ($row.h -lt $COLLAPSED_MIN) {
        $fails += "${w}px: collapsed row '$($row.name)' is only $($row.h)px -- it is also the tap target that expands it, and 44px is the floor"
      }
      # ONE LINE, asserted as one line. The height budget does NOT imply this:
      # two 16px lines plus the row's own padding come to 57px and sat inside the
      # 60px budget, which is how a plant that let the name wrap passed (defect
      # pass, D144). A budget measures how tall; this measures how many.
      if ($row.nameLines -gt 1) {
        $fails += "${w}px: collapsed row '$($row.name)' wraps its name onto $($row.nameLines) lines -- the ruling is ONE line, and the 60px budget admits two of them, so the budget cannot be the thing that says so"
      }
      if ($row.headRows -gt 1) {
        $fails += "${w}px: collapsed row '$($row.name)' puts its headline on $($row.headRows) rows -- name, time and the one number share a single line, or the row is not the one line the ruling describes"
      }
      if ($row.facts -gt 4) {
        $fails += "${w}px: collapsed row '$($row.name)' shows $($row.facts) facts ($($row.texts -join ' | ')) -- the ruling is name, time and ONE headline number"
      }
      # THE ROUTE IS NOT DETAIL. The third slot answers "what is this worth?" with
      # a figure OR with the offer to go and get one -- never with a dash whose
      # only way forward is behind a tap. Exactly one of the two, never both
      # (that would be a fifth fact) and never neither.
      if ($row.routeOnLine -and $row.hasNum) {
        $fails += "${w}px: collapsed row '$($row.name)' carries BOTH a number and the route on one line -- that is a fourth fact beside the x, and at 390px it leaves ~76px for the name"
      }
      if (-not $row.routeOnLine -and -not $row.hasNum) {
        $fails += "${w}px: collapsed row '$($row.name)' has neither a number nor a route in its headline slot"
      }
      if ($row.hasNum -and $row.numText -match '^\s*\u2014\s*$') {
        $fails += "${w}px: collapsed row '$($row.name)' headlines a DASH while its 'find nutrients' route is behind a tap -- a row with no number must offer the route in that slot, or the only way out of a dead end costs an extra tap"
      }
    }
    # ...and the fixture has to CONTAIN such a row, or the rule above is vacuous
    if (-not (@($R.rows) | Where-Object { -not $_.expanded -and $_.routeOnLine })) {
      $fails += "${w}px: NO collapsed row headlines the route -- the six-shape fixture includes an unresolved item, so either it stopped rendering or the route rule is being checked against nothing (D96)"
    }
    if (-not (@($R.rows) | Where-Object { -not $_.expanded -and $_.hasNum })) {
      $fails += "${w}px: NO collapsed row headlines a number, so the A2 rule above is being checked against nothing"
    }
    if (@($R.ink).Count) {
      $worst = (@($R.ink) | Sort-Object over -Descending | Select-Object -First 3 |
                ForEach-Object { "$($_.from) over $($_.onto) by $($_.over)px" }) -join '; '
      $fails += "${w}px: LABEL INK REACHES A NEIGHBOUR on $(@($R.ink).Count) element(s) -- $worst. The baseline was ZERO, so this is a regression, and it is ink rather than boxes because a box kept its gap on 26 unreadable rows (D140)"
    }
    foreach ($f in @($R.fonts)) {
      if ($null -eq $f.px) { continue }   # not every class renders in every state
      if ($f.px -lt 16) { $fails += "${w}px: 16px floor -- $($f.sel) computes to $($f.px)px" }
    }
    $present = @($R.fonts | Where-Object { $null -ne $_.px }).Count
    if ($present -lt 3) { $fails += "${w}px: only $present text classes were found to measure -- coverage before the floor (D124)" }
  }
  # the whole list, and the total's position: baseline 1,057px of rows and 2.4 screens
  if ($C390.rowSum -gt 420) {
    $fails += "the six rows total $($C390.rowSum)px against a budget of 420 -- the baseline was 1,057px and the point of the slice is the list, not one row"
  }
  if ($C390.dayTotalTop -and $C390.dayTotalTop -gt (2 * $C390.vh)) {
    $fails += "the day total is still $([Math]::Round($C390.dayTotalTop / $C390.vh, 1)) screens down (baseline 2.4) -- it is what a tracker exists to answer"
  }

  # ---- A2: the headline IS the primaryNutrient ----------------------------
  $hl = Eval "JSON.stringify((function(){var n=document.querySelector('.mitem .mnum, .mitem .mkcal');return {txt:n?(n.textContent||'').replace(/\s+/g,' ').trim():null};})())"
  $H = $hl | ConvertFrom-Json
  if (-not $H.txt) { $fails += "A2: no headline number found on a collapsed row" }
  elseif ($H.txt -notmatch 'cal') { $fails += "A2: with primaryNutrient unset the headline reads '$($H.txt)' -- the default is kcal, shown as 'cal' (D139)" }
  Eval ("($fixture)('protein_g')") | Out-Null
  Start-Sleep -Milliseconds 600
  $hl2 = Eval "JSON.stringify((function(){var n=document.querySelector('.mitem .mnum, .mitem .mkcal');return {txt:n?(n.textContent||'').replace(/\s+/g,' ').trim():null};})())"
  $H2 = $hl2 | ConvertFrom-Json
  if (-not $H2.txt -or $H2.txt -eq $H.txt) {
    $fails += "A2: setting primaryNutrient to protein_g did not change the headline (still '$($H2.txt)') -- the row is supposed to agree with the ring, which is the whole reason A2 was chosen over plain kcal"
  }
  Eval ("($fixture)('')") | Out-Null
  Start-Sleep -Milliseconds 500

  # ---- B1: tap EXPANDS in place; edit is one tap DEEPER -------------------
  # (the tap sequence is driven below with real taps rather than click(), so the
  # expand is exercised the way a thumb does it)
  $geo = Eval "JSON.stringify((function(){var r=document.querySelector('.mitem');var b=r.getBoundingClientRect();return {x:Math.round(b.left+b.width/2),y:Math.round(b.top+b.height/2),h:Math.round(b.height),top:Math.round(b.top)};})())"
  $G = $geo | ConvertFrom-Json
  Eval "window.scrollTo(0, Math.max(0, $($G.top) + window.scrollY - 300)); 1" | Out-Null
  Start-Sleep -Milliseconds 300
  $g2 = Eval "JSON.stringify((function(){var r=document.querySelector('.mitem');var b=r.getBoundingClientRect();return {x:Math.round(b.left+b.width/2),y:Math.round(b.top+Math.min(24,b.height/2)),h:Math.round(b.height)};})())"
  $G2 = $g2 | ConvertFrom-Json
  $editBefore = Eval 'JSON.stringify(!!HT.itemEditTarget())'
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $G2.x; y = $G2.y }) } | Out-Null
  Start-Sleep -Milliseconds 40
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
  Start-Sleep -Milliseconds 500
  $after = Eval "JSON.stringify((function(){var r=document.querySelector('.mitem');return {h:Math.round(r.getBoundingClientRect().height),expanded:r.classList.contains('mopen'),edit:!!HT.itemEditTarget()};})())"
  $A = $after | ConvertFrom-Json
  if ($editBefore -eq 'true') { $fails += "B1: an editor was already open before any tap" }
  if (-not $A.expanded) { $fails += "B1: one tap did not expand the row in place (no .mopen)" }
  if ($A.h -le $G2.h) { $fails += "B1: the row did not grow when expanded ($($G2.h) -> $($A.h))" }
  if ($A.edit) { $fails += "B1: ONE tap opened the editor -- edit is a tap DEEPER, and a row that edits on first touch is the surface this slice exists to calm" }
  # the expanded row must SHOW what the collapsed one hid, or the collapse hides
  # rather than defers (D53: depth on demand, not depth removed)
  $exp = Eval "JSON.stringify((function(){var r=document.querySelector('.mitem');var t=(r.textContent||'').replace(/\s+/g,' ');return {hasConf:/estimated|measured|weighed/.test(t),hasSrc:/from photo|from barcode|typed in|saved item|daily supplement/.test(t),hasMacros:/P \d|protein/i.test(t)};})())"
  $E = $exp | ConvertFrom-Json
  if (-not $E.hasConf) { $fails += "B1: the expanded row does not show how sure the number is -- the collapse must DEFER detail, not delete it (D53)" }
  if (-not $E.hasSrc) { $fails += "B1: the expanded row does not show where the item came from" }
  if (-not $E.hasMacros) { $fails += "B1: the expanded row does not show the macros the collapsed row hid" }
  # and the ink must still be clean when expanded
  $expInk = Invoke-CDP 'Runtime.evaluate' @{ expression = $probe; returnByValue = $true }
  $EI = $expInk.result.result.value
  if (@($EI.ink).Count) { $fails += "expanded: label ink reaches a neighbour on $(@($EI.ink).Count) element(s)" }

  # =============== P1: the draft's identity control ========================
  $p1 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const O = {};
  const NAMES = [['spicy creamy ramen broth (tantan/miso-style)', 72, 340],
    ['cooked wheat ramen noodles', 138, 170], ['chashu pork belly', 280, 65],
    ['scallions (green onion)', 32, 8], ['wood ear mushrooms (kikurage)', 25, 18],
    ['menma bamboo shoots', 22, 15]];
  HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: NAMES.map(function (n) {
    return { name: n[0], grams: n[2], notes: 'x',
             alts: [{ name: n[0], p: 0.7 }, { name: n[0] + ', plain', p: 0.2 },
                    { name: 'something else entirely', p: 0.1 }],
             per100: { kcal: n[1], protein_g: 4, fat_g: 3, carb_g: 20, fiber_g: 1, soluble_fiber_g: 0 } };
  }) }));
  await sleep(700);
  function stats() {
    const rows = Array.prototype.slice.call(document.querySelectorAll('.pmrow'));
    return rows.map(function (r) {
      const idw = r.querySelector('.pmid-wrap');
      const alts = r.querySelector('.pmalts');
      const vis = function (e) {
        if (!e) return false;
        if (typeof e.checkVisibility === 'function')
          return e.checkVisibility({ contentVisibilityAuto: true, visibilityProperty: true });
        return e.getBoundingClientRect().height > 0;
      };
      return { h: Math.round(r.getBoundingClientRect().height),
               idH: idw ? Math.round(idw.getBoundingClientRect().height) : 0,
               altsVisible: vis(alts) };
    });
  }
  O.unsettled = stats();
  // MEASURED, and this gate's first version got it wrong: a six-item draft
  // renders FIVE .pmrow elements, because the LEAD item is drawn in its own
  // block. Row k is item k+1. Settling "every item but 0" therefore settled
  // every rendered row and then asserted that the first one was unsettled.
  // The row now declares its item index, so this settles by that.
  const d = HT.photoDraft();
  // A MISSING ATTRIBUTE IS NULL, AND Number(null) IS 0 -- not NaN. Read
  // through Number() alone, a row that stopped declaring its index came back as
  // item 0, this settled "every item but 0" (the LEAD item, which renders no
  // row), every rendered row arrived settled, and the gate failed on the
  // unsettled-row assertion instead of the one written for it. A gate that
  // fails for the wrong reason will mislead whoever reads it next.
  const rowIdx = Array.prototype.slice.call(document.querySelectorAll('.pmrow'))
    .map(function (r) {
      const a = r.getAttribute('data-pmi');
      return (a === null || a === '' || Number(a) !== Number(a)) ? null : Number(a);
    });
  O.rowItemIdx = rowIdx;
  O.itemCount = (d.items || []).length;
  // ...and with NO index to settle by, nothing is settled: a fabricated
  // mapping would produce a confident verdict about an arrangement the page
  // never had. Number(null) is 0, so an unchecked read called such a row
  // item 0 -- the LEAD item, which renders no row at all.
  if (rowIdx[0] !== null) (d.items || []).forEach(function (it, i) { if (i !== rowIdx[0]) it.idDone = true; });
  HT.renderPhotoDraft();
  await sleep(450);
  O.mixed = stats();
  O.sumUnsettled = O.unsettled.reduce(function (a, r) { return a + r.h; }, 0);
  O.sumMixed = O.mixed.reduce(function (a, r) { return a + r.h; }, 0);
  HT.photoDiscard(); HT.captureOutcomeDismiss();
  return O;
})()
'@
  if ($p1 -like 'EXCEPTION*') { $fails += "the P1 phase threw: $p1" }
  else {
    $P = $p1 | ConvertFrom-Json
    $u = @($P.unsettled); $m = @($P.mixed)
    if ($u.Count -lt 5) { $fails += "P1: only $($u.Count) draft rows rendered (D96)" }
    elseif (@($P.rowItemIdx).Count -lt 1 -or $null -eq $P.rowItemIdx[0]) {
      $fails += "P1: the draft rows do not declare which item they are (data-pmi absent), so the row left unsettled cannot be identified -- a six-item draft renders five rows and the mapping is not the identity"
    }
    elseif (@($P.rowItemIdx | Where-Object { $null -eq $_ }).Count) {
      $fails += "P1: $(@($P.rowItemIdx | Where-Object { $null -eq $_ }).Count) draft row(s) declare no item index -- one missing is the same hazard as all of them missing, because Number(null) is 0 and an unchecked read would call such a row item 0"
    }
    else {
      # row 0 was left UNSETTLED on purpose: an unsettled row keeps its control
      if (-not $m[0].altsVisible) {
        $fails += "P1: an UNSETTLED row's identity control is collapsed -- a row that still has a question to ask must keep it open"
      }
      $settled = $m[1..($m.Count - 1)]
      foreach ($r in $settled) {
        if ($r.altsVisible) {
          $fails += "P1: a SETTLED row still shows its identity alternates -- once idDone there is nothing left to ask"
        }
      }
      # the measured saving: .pmid-wrap was 122-172px of a 237-287px row
      $maxSettled = ($settled | Measure-Object -Property h -Maximum).Maximum
      if ($maxSettled -gt 170) {
        $fails += "P1: a settled row is still $maxSettled px -- the identity control measured 122-172px of a 237-287px row, so settling it must shed that"
      }
      if ($P.sumMixed -ge $P.sumUnsettled) {
        $fails += "P1: settling five of six identities did not reduce the draft at all ($($P.sumUnsettled) -> $($P.sumMixed) px)"
      }
    }
  }

  if ($fails.Count) {
    Write-Host "COLLAPSE GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "COLLAPSE GATE: PASS -- six row shapes collapse to one tappable line at 390 and 360, the headline follows primaryNutrient, one tap expands in place and the editor is a tap deeper, no ink reaches a neighbour in either state, and a settled draft identity sheds its control while an unsettled one keeps it"
  Cleanup
  exit 0
} catch { Write-Host "ERROR: $_"; Cleanup; exit 2 }
