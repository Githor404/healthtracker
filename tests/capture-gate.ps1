# D141 -- RESOLVE AT CAPTURE: one control, two questions, and the geometry it
# has to fit into.
#
# Ruled (D138 forks A-G, on measurement):
#   A  at capture ONLY MEMORY proposes; the matcher's top pick is never
#      pre-selected (16 of 38 were the right food -- 22 of 38 would have put a
#      wrong one under the thumb at the lowest-attention moment)
#   B1 the remembered row's energy pair is FETCHED BY ID; its absence never
#      withholds the proposal, and is shown as absent
#   C1 a questioned proposal is never pre-selected
#   E1 per-item confirms only, no accept-all
#   F1 `ref.when` is its own field ('capture' | 'later'); how and when are two
#      questions and one enum answering both is last week's rename defect
#   G1 the proposal is the LEADING IDENTITY OPTION, not a new row
#
# AND EVERY GEOMETRY THRESHOLD IS A MEASURED BASELINE, not a tolerance -- taken
# ON THE FIXTURE IT GATES, because a threshold borrowed from another fixture
# fails the fixture rather than the build:
#
#   PHASE 0, a six-item draft with NO alternates (where the ruled floor was
#   measured): .pmrow 187px uniform, body 649px visible at 390 and 609px at 360,
#   content 1,298px -- already a 2x SCROLL -- and rows fully visible 2 of 5 at
#   390, 1 of 5 at 360.
#
#   PHASES 1-2, the same draft WITH alternates and partial coverage, which the
#   ruling requires this gate to render: a row is 287px and ZERO rows fit. So the
#   property gated there is the one G1 actually claims -- the proposal costs ~0px
#   -- as a max row height, plus ink collisions, which were ZERO.
#
# The 287px figure is itself the density finding for the presentation arc: with
# its alternates showing, the surface the user logs from most fits no whole row.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8193
$Dbg = 9399
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-capgate-" + [System.Guid]::NewGuid().ToString('N'))
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
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  # ---- the fixture, declared once and reused by both phases ----------------
  # SIX items (the largest save in the log), each carrying ALTERNATES so .pmalt
  # renders, and one driven to "None of these" so the draft total carries .pmcov.
  # Fixture-synthetic forever (CLAUDE.md): no export is ever read.
  $fixture = @'
(async function (refName, refState) {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T12:00:00-04:00'); });
  localStorage.clear();
  HT.boot();
  await sleep(250);
  await HT.corpusEnsure();
  HT.matchIndexBuild();
  // A PRIOR day whose resolved item is a REWORDING of a draft item: both
  // "ramen noodle soup" and "cooked wheat ramen noodles" key to 'noodle ramen'
  // in the real CNF index (D136/D137), and the source name is NOT a substring
  // of the draft name, so an assertion that it appears cannot pass by echo.
  const S = HT.state();
  S.days['2026-09-01'] = { status: 'complete', water_l: 0, items: [
    { name: 'ramen noodle soup', meal: 'lunch', time: '12:00', grams: 300, kcal: 400,
      protein_g: 10, fat_g: 5, carb_g: 60, fiber_g: 3, soluble_fiber_g: 1,
      confidence: 'eyeballed', source: 'ai-paste', notes: '',
      ref: { ns: 'cnf', id: '4464', name: refName, at: '2026-09-01', at_ms: 1,
             hash: 'h', how: 'picked', when: 'later',
             attribution: 'Canadian Nutrient File, Health Canada, 2015', v: { '301': 1 } } }] };
  S.current = '2026-09-26';
  HT.refresh();
  await sleep(200);
  const NAMES = [
    ['spicy creamy ramen broth (tantan/miso-style)', 72, 340],
    ['cooked wheat ramen noodles', 138, 170],
    ['chashu pork belly', 280, 65],
    ['scallions (green onion)', 32, 8],
    ['wood ear mushrooms (kikurage)', 25, 18],
    ['menma bamboo shoots', 22, 15]];
  const paste = JSON.stringify({ meal: 'lunch', items: NAMES.map(function (n) {
    return { name: n[0], grams: n[2], notes: 'estimated from the photo',
             alts: [{ name: n[0], p: 0.7 }, { name: n[0] + ', plain', p: 0.2 },
                    { name: 'something else entirely', p: 0.1 }],
             per100: { kcal: n[1], protein_g: 4, fat_g: 3, carb_g: 20,
                       fiber_g: 1, soluble_fiber_g: 0 } };
  }) });
  const r = HT.openPhotoDraft(paste);
  await sleep(600);
  // Force partial coverage so .pmcov renders on the draft total.
  //
  // H27: this used to click "None of these", which resolved an item to nothing on
  // purpose. That terminus is gone, and the only way to an unresolved item now is
  // to SAY what it was and have the database not hold it -- which is a different
  // fact about the item, and the one the record should carry.
  const lastI = HT.photoDraft().items.length - 1;
  HT.photoSearchOpen(lastI);
  HT.photoSearchType('zzqqxv wibblefrotz');
  HT.photoSearchKeep(lastI);
  await sleep(350);
  return { ok: !!r.ok, error: r.error || null,
           rows: document.querySelectorAll('.pmrow').length,
           refState: refState };
})
'@

  function Setup([string]$refName, [string]$refState) {
    $call = "($fixture)(" + ($refName | ConvertTo-Json) + "," + ($refState | ConvertTo-Json) + ")"
    return EvalAsyncB64 $call
  }

  # ---- the probe: geometry + the ruled behaviours --------------------------
  $probe = @'
(function () {
  const O = { ink: [], fonts: [], rows: [] };
  const draft = document.getElementById('photoDraft');
  const rows = Array.prototype.slice.call(document.querySelectorAll('.pmrow'));
  O.rowCount = rows.length;
  function scroller(el) {
    for (let p = el; p; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if (/auto|scroll/.test(cs.overflowY) && p.scrollHeight > p.clientHeight + 1) return p;
    }
    return null;
  }
  const sc = draft ? (scroller(draft) || draft.parentElement) : null;
  if (sc) {
    const r = sc.getBoundingClientRect();
    O.bodyVisibleH = Math.round(r.height);
    O.bodyScrollH = Math.round(sc.scrollHeight);
    O.bodyTop = Math.round(r.top); O.bodyBottom = Math.round(r.bottom);
  }
  let visible = 0;
  rows.forEach(function (row, i) {
    const r = row.getBoundingClientRect();
    const inView = sc ? (r.top >= O.bodyTop - 1 && r.bottom <= O.bodyBottom + 1) : false;
    if (inView) visible++;
    O.rows.push({ i: i, h: Math.round(r.height), inView: inView });
  });
  O.rowsFullyVisible = visible;
  O.maxRowH = O.rows.length ? Math.max.apply(null, O.rows.map(function (r) { return r.h; })) : 0;
  // RULED BUDGET: a row WITHOUT a proposal may not grow at all; a row WITH one
  // may grow by one wrapped sentence. So the two are measured apart.
  rows.forEach(function (row, i) {
    O.rows[i].hasProp = !!row.querySelector('.pmaltmem');
  });
  const withP = O.rows.filter(function (r) { return r.hasProp; });
  const noP = O.rows.filter(function (r) { return !r.hasProp; });
  O.propRowCount = withP.length;
  O.maxHWithProp = withP.length ? Math.max.apply(null, withP.map(function (r) { return r.h; })) : 0;
  O.maxHNoProp = noP.length ? Math.max.apply(null, noP.map(function (r) { return r.h; })) : 0;

  // THE PHOTO MODAL'S OWN FOOTER, not the entry sheet's -- the first measurement
  // matched the wrong element and its claim went unverified.
  // MEASURED DOM: #photoDraft sits inside #outcomeBody.obody (the scroller) which
  // sits inside #captureOutcome.omodal (position:fixed). The footer is
  // #outcomeFoot.ofoot -- a NON-SCROLLING SIBLING of the body, which is how
  // R21.5 keeps Save in view whatever the item count. The first attempt looked
  // for .sheet/.panel and position:fixed and found the entry sheet's footer.
  const modal = draft ? draft.closest('.omodal') : null;
  O.modalClass = modal ? String(modal.className || '') : '';
  const foot = document.getElementById('outcomeFoot');
  if (foot) {
    const fr = foot.getBoundingClientRect();
    O.footText = (foot.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 70);
    O.footOnScreen = fr.top >= 0 && fr.bottom <= window.innerHeight + 1 && fr.height > 0;
    O.footOutsideScroller = sc ? !sc.contains(foot) : true;
  }

  // INK, not the box (D140)
  rows.forEach(function (row, ri) {
    const kids = Array.prototype.slice.call(row.querySelectorAll('*'));
    kids.forEach(function (el) {
      let t = '';
      for (let j = 0; j < el.childNodes.length; j++)
        if (el.childNodes[j].nodeType === 3) t += el.childNodes[j].nodeValue;
      if (!t.replace(/\s+/g, ' ').trim()) return;
      if (el.scrollWidth <= el.clientWidth + 1) return;
      const a = el.getBoundingClientRect();
      const inkRight = a.left + el.scrollWidth;
      kids.forEach(function (ot) {
        if (ot === el || el.contains(ot) || ot.contains(el)) return;
        const b = ot.getBoundingClientRect();
        if (b.width <= 0 || b.height <= 0) return;
        const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (oy > 0.5 && inkRight - b.left > 0.5)
          O.ink.push({ row: ri, over: Math.round(inkRight - b.left),
                       from: String(el.className || el.tagName).slice(0, 20),
                       onto: String(ot.className || ot.tagName).slice(0, 20) });
      });
    });
  });

  // the floor, with coverage: all eight classes must be PRESENT
  ['.pmhead', '.pmhead b', '.pmmeta', '.pmg', '.pmunit', '.pmnote', '.pmalt', '.pmcov']
    .forEach(function (sel) {
      const e = document.querySelector(sel);
      O.fonts.push({ sel: sel, px: e ? Math.round(parseFloat(getComputedStyle(e).fontSize) * 10) / 10 : null });
    });

  // ---- the ruled behaviour, read off the surface -------------------------
  // The memory proposal must be the FIRST option in the identity control of the
  // row whose name is a rewording of the prior resolve.
  let target = null;
  rows.forEach(function (row) {
    const h = (row.querySelector('.pmhead') || {}).textContent || '';
    if (/cooked wheat ramen noodles/.test(h)) target = row;
  });
  O.targetFound = !!target;
  if (target) {
    const opts = Array.prototype.slice.call(target.querySelectorAll('.pmalts > button'));
    O.optCount = opts.length;
    O.firstOptText = opts.length ? (opts[0].textContent || '').replace(/\s+/g, ' ').trim() : '';
    O.firstOptClass = opts.length ? String(opts[0].className || '') : '';
    O.anyOptIsPreselected = opts.some(function (b) {
      return b.getAttribute('aria-pressed') === 'true' || /\bpmaltsel\b/.test(String(b.className || '')); });
    O.optTexts = opts.map(function (b) { return (b.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80); });
  }
  O.draftItemHasRefBeforeTap = !!(HT.photoDraft() && (HT.photoDraft().items || []).some(function (it) { return it && it.ref; }));
  return O;
})()
'@
  function Probe([int]$w, [int]$h) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 2; mobile = $true } | Out-Null
    Start-Sleep -Milliseconds 800
    $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $probe; returnByValue = $true }
    if ($r.result.exceptionDetails) { throw "probe threw at ${w}px: $($r.result.exceptionDetails.text)" }
    return $r.result.result.value
  }

  # ======================= PHASE 0: the ruled visibility floor ============
  # Six items, NO alternates -- the fixture the >=2 / >=1 floor was measured on.
  $bare = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T12:00:00-04:00'); });
  localStorage.clear();
  HT.boot();
  await sleep(250);
  const NAMES = [
    ['spicy creamy ramen broth (tantan/miso-style)', 72, 340],
    ['cooked wheat ramen noodles', 138, 170],
    ['chashu pork belly', 280, 65],
    ['scallions (green onion)', 32, 8],
    ['wood ear mushrooms (kikurage)', 25, 18],
    ['menma bamboo shoots', 22, 15]];
  const r = HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: NAMES.map(function (n) {
    return { name: n[0], grams: n[2], notes: 'estimated from the photo',
             per100: { kcal: n[1], protein_g: 4, fat_g: 3, carb_g: 20,
                       fiber_g: 1, soluble_fiber_g: 0 } };
  }) }));
  await sleep(600);
  return { ok: !!r.ok, rows: document.querySelectorAll('.pmrow').length };
})()
'@
  $s0 = EvalAsyncB64 $bare
  if ($s0 -like 'EXCEPTION*') { Write-Host "ERROR: phase 0 setup threw: $s0"; Cleanup; exit 2 }
  $P390 = Probe 390 844
  $P360 = Probe 360 800
  foreach ($pair in @(@(390, $P390, 2), @(360, $P360, 1))) {
    $w = $pair[0]; $R = $pair[1]; $floor = $pair[2]
    if (@($R.rows).Count -lt 5) {
      $fails += "phase 0 ${w}px: only $(@($R.rows).Count) rows rendered -- the bare six-item fixture did not stand up (D96)"
      continue
    }
    if ($R.maxRowH -gt 187) {
      $fails += "phase 0 ${w}px: a draft row is $($R.maxRowH)px against the measured 187px -- the proposal was ruled to cost ~0px"
    }
    if ($R.rowsFullyVisible -lt $floor) {
      $fails += "phase 0 ${w}px: only $($R.rowsFullyVisible) row(s) fully visible against the ruled floor of $floor -- the proposal may not cost a visible row"
    }
  }

  # ======================= PHASE 1: a CLEAN memory proposal ================
  $s1 = Setup 'Pasta, spaghetti, enriched, cooked' 'cooked'
  if ($s1 -like 'EXCEPTION*') { Write-Host "ERROR: setup threw: $s1"; Cleanup; exit 2 }
  $R390 = Probe 390 844
  $R360 = Probe 360 800

  # THE THRESHOLD MUST COME FROM THE FIXTURE IT GATES. The ruled "rows visible
  # >=2 at 390, >=1 at 360" was measured on a draft WITHOUT alternates, where a
  # row is 187px. This gate's fixture must carry alternates (the ruled coverage
  # requirement), and they make a row 287px -- so ZERO rows fit, and a >=2 floor
  # would be failing the fixture rather than the build.
  #
  # So what is gated here is the property G1 actually claims: the proposal costs
  # ~0px. MEASURED pre-build on THIS fixture: rows 287/237/287/287/287, max 287.
  # Phase 0 below keeps the ruled visibility floor, on the fixture it came from.
  # AMENDED 2026-10-05, 287 -> 337, RULED. H27 put the way out of the identity
  # dead end on its own full-width line, which costs exactly one 44px line plus
  # its 6px gap on every unsettled row.
  #
  # The clause this budget carries is "a row that gained NO FUNCTION may not
  # grow". This row gained one: before H27 its only exit was "None of these",
  # which recorded nothing. So the figure moves and the clause stands.
  #
  # MEASURED both sides on this fixture at 360px: at HEAD the four chips packed
  # into 3 lines (144px) because "None of these" was 126px and shared the last
  # line; the replacement is 146px against 136px of room. Shortening it to fit
  # was possible -- 135px, one pixel of margin -- and rejected: a layout that
  # holds by a pixel is hostage to the next word, and to how long the MODEL's
  # candidate names happen to be.
  $MAX_ROW_H = 337
  # +87px measured: the sentence names the source item, its date and that it
  # brings nutrients -- all ruled content -- and wraps to three lines at 390px.
  $SENTENCE_BUDGET = 92
  foreach ($pair in @(@(390, $R390), @(360, $R360))) {
    $w = $pair[0]; $R = $pair[1]
    if (@($R.rows).Count -lt 5) {
      $fails += "${w}px: only $(@($R.rows).Count) draft rows rendered -- the six-item fixture did not stand up (D96)"
      continue
    }
    # RULED: a row WITHOUT a proposal may not grow AT ALL. That is the no-regression
    # line, and it is where a careless layout change would show up.
    if ($R.maxHNoProp -gt $MAX_ROW_H) {
      $fails += "${w}px: a row with NO proposal is $($R.maxHNoProp)px against the pre-build $MAX_ROW_H px -- a row that gained no function may not grow"
    }
    # ...and a row WITH one may grow by one wrapped sentence. Measured +87px.
    if ($R.maxHWithProp -gt ($MAX_ROW_H + $SENTENCE_BUDGET)) {
      $fails += "${w}px: the proposal row is $($R.maxHWithProp)px against a budget of $($MAX_ROW_H + $SENTENCE_BUDGET)px -- one wrapped sentence was accepted, not two"
    }
    if ($R.propRowCount -ne 1) {
      $fails += "${w}px: $($R.propRowCount) rows carry a proposal -- exactly one item in this fixture has a memory, so any other count means the proposal is appearing where nothing was remembered (Fork A)"
    }
    if (@($R.ink).Count) {
      $worst = (@($R.ink) | Sort-Object over -Descending | Select-Object -First 3 |
                ForEach-Object { "$($_.from) over $($_.onto) by $($_.over)px (row $($_.row))" }) -join '; '
      $fails += "${w}px: LABEL INK REACHES A NEIGHBOUR on $(@($R.ink).Count) element(s) -- $worst. The measured baseline was ZERO, so this is a regression, not a tolerance"
    }
    foreach ($f in @($R.fonts)) {
      if ($null -eq $f.px) { $fails += "${w}px: $($f.sel) never rendered -- coverage before the floor (D124): the fixture must force every class it claims to check" }
      elseif ($f.px -lt 16) { $fails += "${w}px: 16px floor -- $($f.sel) computes to $($f.px)px" }
    }
    if (-not $R.footText) { $fails += "${w}px: #outcomeFoot was not found -- the photo modal's own footer is where Save lives (R21.5)" }
    else {
      if ($R.footText -notmatch 'Ate all of it|Save') { $fails += "${w}px: the modal footer does not carry the save action: '$($R.footText)'" }
      if (-not $R.footOnScreen) { $fails += "${w}px: the modal footer holding Save is not fully on screen" }
      if (-not $R.footOutsideScroller) { $fails += "${w}px: the modal footer SCROLLS with the body -- R21.5 put Save outside the scroller so it stays in view whatever the item count" }
    }
  }

  # ---- G1: the proposal is the LEADING identity option --------------------
  if (-not $R390.targetFound) {
    $fails += "the row whose name is a rewording of the prior resolve did not render, so nothing below was tested (D96)"
  } else {
    if (-not $R390.firstOptText) {
      $fails += "G1: the identity control has no options at all on the target row"
    } else {
      if ($R390.firstOptText -notmatch 'ramen noodle soup') {
        $fails += "G1: the FIRST identity option does not name the item the match came from (D137). It reads: '$($R390.firstOptText)'"
      }
      if ($R390.firstOptText -notmatch 'with its nutrients') {
        $fails += "G1: the first option does not say it BRINGS NUTRIENTS -- one control now answers two questions, and the user must know which they are choosing. It reads: '$($R390.firstOptText)'"
      }
      if ($R390.firstOptText -notmatch 'Sep') {
        $fails += "G1: the first option does not say WHEN the match was made (D137). It reads: '$($R390.firstOptText)'"
      }
    }
    if ($R390.anyOptIsPreselected) {
      $fails += "C1/E1: an identity option is PRE-SELECTED -- at capture nothing is ever applied without a tap"
    }
    if ($R390.draftItemHasRefBeforeTap) {
      $fails += "C1: a draft item already carries a ref before anything was tapped -- the proposal applied itself"
    }
  }

  # ---- F1 + the rule ruled to be gated specifically ----------------------
  $behav = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const O = {};
  function rowFor(re) {
    const rows = Array.prototype.slice.call(document.querySelectorAll('.pmrow'));
    for (let i = 0; i < rows.length; i++) {
      const h = (rows[i].querySelector('.pmhead') || {}).textContent || '';
      if (re.test(h)) return rows[i];
    }
    return null;
  }
  // (a) TAKE THE MEMORY OPTION -> name AND ref, with ref.when = 'capture'
  let row = rowFor(/cooked wheat ramen noodles/);
  const opts = row ? Array.prototype.slice.call(row.querySelectorAll('.pmalts > button')) : [];
  if (!opts.length) return { err: 'no identity options on the memory row' };
  opts[0].click();
  await sleep(400);
  const d1 = HT.photoDraft();
  const mem = (d1.items || []).filter(function (it) { return !!it.ref; })[0] || null;
  O.memSetRef = !!mem;
  O.memRefName = mem ? String(mem.ref.name || '') : '';
  O.memRefWhen = mem ? String(mem.ref.when || '') : '';
  O.memRefHow = mem ? String(mem.ref.how || '') : '';
  O.memName = mem ? String(mem.name || '') : '';
  O.memHasKcal = !!(mem && mem.ref && mem.ref.v && Object.keys(mem.ref.v).length > 0);

  // (b) THE RULE RULED TO BE GATED SPECIFICALLY: take a NON-memory alternate
  //     on another row -> the NAME only. The ref stays unresolved and is never
  //     carried over from the memory option beside it.
  row = rowFor(/chashu pork belly/);
  const o2 = row ? Array.prototype.slice.call(row.querySelectorAll('.pmalts > button')) : [];
  O.otherOptCount = o2.length;
  if (o2.length >= 2) {
    const want = (o2[o2.length - 2].textContent || '').replace(/\s+/g, ' ').trim();
    o2[o2.length - 2].click();
    await sleep(400);
    const d2 = HT.photoDraft();
    const it2 = (d2.items || []).filter(function (it) {
      return String(it.name || '').indexOf('pork belly') >= 0 || /something else|plain/.test(String(it.name || '')); })[0] || null;
    O.otherPicked = want.slice(0, 60);
    O.otherName = it2 ? String(it2.name || '') : '';
    O.otherHasRef = !!(it2 && it2.ref);
  }
  // (c) and SAVED, the ref survives the write boundary with its own field
  const sr = HT.photoSave();
  await sleep(600);
  O.saved = !!(sr && sr.ok);
  const day = HT.state().days[HT.state().current] || { items: [] };
  const withRef = (day.items || []).filter(function (it) { return it && it.ref; });
  O.savedWithRef = withRef.length;
  O.savedWhen = withRef.length ? String(withRef[0].ref.when || '') : '';
  O.savedHow = withRef.length ? String(withRef[0].ref.how || '') : '';
  O.savedNoRefCount = (day.items || []).filter(function (it) { return it && !it.ref; }).length;
  return O;
})()
'@
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Start-Sleep -Milliseconds 500
  $B = EvalAsyncB64 $behav
  if ($B -like 'EXCEPTION*') { $fails += "the behaviour phase threw: $B" }
  else {
    $Bo = $B | ConvertFrom-Json
    if ($Bo.err) { $fails += "behaviour setup: $($Bo.err)" }
    if (-not $Bo.memSetRef) { $fails += "G1: taking the memory option set NO ref -- it must settle both questions, which is the whole reason one control answers them" }
    if ($Bo.memRefWhen -ne 'capture') { $fails += "F1: ref.when is '$($Bo.memRefWhen)', not 'capture' -- how and when are two questions, and one enum answering both is last week's rename defect" }
    if ($Bo.memName -notmatch 'ramen noodle soup') { $fails += "G1: taking the memory option left the name as '$($Bo.memName)' -- it must set the name too, so a repeated food converges on one name" }
    if (-not $Bo.memHasKcal) { $fails += "B1: the remembered row's values were not fetched by id, so the proposal carries no energy pair to read" }
    if ($Bo.otherOptCount -lt 2) { $fails += "the second row offered fewer than two identity options, so the name-only rule was never exercised (D96)" }
    else {
      if (-not $Bo.otherName) { $fails += "picking a non-memory alternate set no name at all" }
      if ($Bo.otherHasRef) { $fails += "THE RULED GATE: picking a NON-MEMORY alternate carried a ref over -- it must set the NAME ONLY, and the ref must stay unresolved" }
    }
    if (-not $Bo.saved) { $fails += "the draft did not save, so nothing crossed the write boundary" }
    if ($Bo.savedWithRef -lt 1) { $fails += "F1: no saved item carries a ref -- the capture-time match did not survive the write" }
    if ($Bo.savedWhen -ne 'capture') { $fails += "F1: the SAVED ref.when is '$($Bo.savedWhen)' -- the field must survive normalizeItem/normalizeRef, which is where an undeclared field is dropped (D131)" }
    if ($Bo.savedNoRefCount -lt 1) { $fails += "every saved item carries a ref -- items without a memory must stay unresolved (Fork A)" }
  }

  # ============ PHASE 1b: a PART-EATEN plate re-expresses the values =======
  # RULED H2: a plate eaten at 1/3 and 1/2 must carry reference values at exactly
  # 1/3 and 1/2. MEASURED on the real log: 24 of 45 photo items reach the day
  # through a plate and 7 were eaten as a fraction, so without ref.g a part-eaten
  # record would report reference nutrients at 2x or 3x.
  $s1b = Setup 'Pasta, spaghetti, enriched, cooked' 'cooked'
  if ($s1b -like 'EXCEPTION*') { $fails += "phase 1b setup threw: $s1b" }
  else {
    $frac = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const O = {};
  function rowIdx(re) {
    const d = HT.photoDraft();
    const items = (d && d.items) || [];
    for (let i = 0; i < items.length; i++) if (re.test(String(items[i].name || ''))) return i;
    return -1;
  }
  const mi = rowIdx(/cooked wheat ramen noodles/);
  if (mi < 0) return { err: 'no memory row in the draft' };
  const rows = Array.prototype.slice.call(document.querySelectorAll('.pmrow'));
  let btn = null;
  rows.forEach(function (row) {
    const h = (row.querySelector('.pmhead') || {}).textContent || '';
    if (/cooked wheat ramen noodles/.test(h)) btn = row.querySelector('.pmaltmem');
  });
  if (!btn) return { err: 'no memory option to take' };
  btn.click();
  await sleep(500);
  const d = HT.photoDraft();
  const mi2 = rowIdx(/ramen noodle soup/);          // renamed by the pick
  if (mi2 < 0) return { err: 'the renamed item was not found' };
  O.plateGrams = Number(d.items[mi2].grams);
  O.refG = Number((d.items[mi2].ref || {}).g);
  O.refV301 = Number(((d.items[mi2].ref || {}).v || {})['301']);
  // eat a THIRD of it
  HT.photoSetAte(mi2, 'fraction', 1 / 3);
  await sleep(200);
  // photoSave() with NO ARGS passes all:true and ignores PHOTO_DRAFT.ate, so the
  // 1/3 never applied and this assertion was passing at a ratio of 1 -- vacuous
  // in exactly D96's sense. photoSaveSome() is the path that carries the
  // fractions, and it is the path the consumption question uses.
  const sr = HT.photoSaveSome();
  await sleep(700);
  O.saved = !!(sr && sr.ok);
  const day = HT.state().days[HT.state().current] || { items: [] };
  const eaten = (day.items || []).filter(function (it) { return it && it.ref && /ramen noodle soup/.test(it.name || ''); })[0] || null;
  if (eaten) {
    O.eatenGrams = Number(eaten.grams);
    O.eatenRefG = Number(eaten.ref.g);
    O.eatenV301 = Number((eaten.ref.v || {})['301']);
  }
  // and a HALF, from the remainder of the same plate
  const pid = sr && sr.plateId;
  if (pid) {
    // statements index PLATE ITEMS, so the fraction must sit at the index of the
    // item carrying the ref. A one-element array consumed plate item 0 instead.
    const plate = HT.getPlate(pid);
    const pitems = (plate && plate.items) || [];
    let pi = -1;
    for (let i = 0; i < pitems.length; i++)
      if (/ramen noodle soup/.test(String(pitems[i].name || ''))) pi = i;
    O.plateIdxWithRef = pi;
    O.plateItemHasRef = pi >= 0 ? !!pitems[pi].ref : false;
    const st2 = pitems.map(function (_, i) {
      return { kind: 'fraction', fraction: i === pi ? 0.5 : 0 }; });
    const r2 = HT.consumeFromPlate(pid, st2,
                                   { date: HT.state().current, mealId: 'gate-half' });
    await sleep(400);
    O.half = !!(r2 && r2.ok !== false);
    O.r2ok = r2 ? String(r2.ok) : 'null';
    O.r2why = r2 ? String(r2.why || r2.error || '') : '';
    O.r2items = (r2 && r2.items) ? r2.items.length : -1;
    O.dayMealIds = ((HT.state().days[HT.state().current] || {}).items || [])
      .map(function (it) { return String(it.mealId || '') + ':' + String(it.name || '').slice(0, 14) + ':' + (it.ref ? 'ref' : 'noref'); });
    const day2 = HT.state().days[HT.state().current] || { items: [] };
    const halves = (day2.items || []).filter(function (it) {
      return it && it.ref && it.mealId === 'gate-half'; });
    if (halves.length) {
      O.halfGrams = Number(halves[0].grams);
      O.halfRefG = Number(halves[0].ref.g);
      O.halfV301 = Number((halves[0].ref.v || {})['301']);
    }
  }
  return O;
})()
'@
    $F = EvalAsyncB64 $frac
    if ($F -like 'EXCEPTION*') { $fails += "phase 1b threw: $F" }
    else {
      $Fo = $F | ConvertFrom-Json
      if ($Fo.err) { $fails += "phase 1b: $($Fo.err)" }
      elseif (-not $Fo.refG) { $fails += "H2: the ref carries no `g` -- nothing records the grams its values were frozen at, so no event can re-express them" }
      else {
        if ([Math]::Abs($Fo.refG - $Fo.plateGrams) -gt 0.5) {
          $fails += "H2: ref.g is $($Fo.refG) but the item it was frozen on is $($Fo.plateGrams) g -- the basis must be the grams the values are for"
        }
        if (-not $Fo.eatenGrams) { $fails += "H2: no part-eaten record carrying a ref reached the day" }
        else {
          $ratio = $Fo.eatenGrams / $Fo.refG
          if ([Math]::Abs($ratio - 1) -lt 0.01) {
            $fails += "H2 fixture: the part-eaten record is $([Math]::Round($ratio,3)) of the plate -- at a ratio of 1 this assertion passes whether the values are re-expressed or not (D96)"
          }
          $wantV = $Fo.refV301 * ($Fo.eatenGrams / $Fo.refG)
          if ([Math]::Abs($Fo.eatenV301 - $wantV) -gt ([Math]::Max(0.0001, $wantV * 0.001))) {
            $fails += "H2: a plate eaten at $([Math]::Round($Fo.eatenGrams / $Fo.refG, 3)) carries calcium $($Fo.eatenV301) where $([Math]::Round($wantV, 4)) is the same value re-expressed -- the dry-ramen error through a different door"
          }
          if ([Math]::Abs($Fo.eatenRefG - $Fo.eatenGrams) -gt 0.5) {
            $fails += "H2: the event's ref.g is $($Fo.eatenRefG) but its grams are $($Fo.eatenGrams) -- after re-expression the basis must be the NEW grams, or the next reader scales it twice"
          }
        }
        if (-not $Fo.plateItemHasRef) { $fails += "H2: the stored PLATE item carries no ref -- normalizePlateItem dropped it, which is the allowlist trap (D131) at the boundary this ruling crosses" }
        if (-not $Fo.halfGrams) { $fails += "H2: a second consumption from the same plate carried no ref -- every event inherits the match, not just the first [r2.ok=$($Fo.r2ok) why=$($Fo.r2why) items=$($Fo.r2items) plateIdx=$($Fo.plateIdxWithRef) day=$($Fo.dayMealIds -join ' | ')]" }
        else {
          $wantH = $Fo.refV301 * ($Fo.halfGrams / $Fo.refG)
          if ([Math]::Abs($Fo.halfV301 - $wantH) -gt ([Math]::Max(0.0001, $wantH * 0.001))) {
            $fails += "H2: the half-plate event carries calcium $($Fo.halfV301) where $([Math]::Round($wantH, 4)) is the re-expressed value"
          }
        }
      }
    }
  }

  # ======================= PHASE 2: a QUESTIONED proposal ==================
  # The same fixture, with the prior resolve pointing at a DRY row. The proposal
  # must still appear, must be LABELLED in D122's wording, and must not apply.
  $s2 = Setup 'Soup, ramen noodles, any flavour, dry' 'dry'
  if ($s2 -like 'EXCEPTION*') { $fails += "phase 2 setup threw: $s2" }
  else {
    $Q = Probe 390 844
    if (-not $Q.targetFound) { $fails += "phase 2: the target row did not render" }
    else {
      if ($Q.firstOptText -notmatch 'dry') {
        $fails += "C1: a questioned proposal is not LABELLED with the state that differs -- it reads: '$($Q.firstOptText)'. D122's wording is what made the dry rows obvious"
      }
      if ($Q.anyOptIsPreselected -or $Q.draftItemHasRefBeforeTap) {
        $fails += "C1: a QUESTIONED proposal was pre-selected or applied without a tap -- the exact shape D125 and D133 exist to prevent"
      }
    }
  }

  if ($fails.Count) {
    Write-Host "CAPTURE GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "CAPTURE GATE: PASS -- six-item draft, no ink reaches a neighbour at 390 or 360, rows visible held at the measured baseline, the memory proposal leads the identity control and sets name+ref with when='capture', a non-memory alternate sets the name only, and a questioned proposal is labelled and never applied"
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
