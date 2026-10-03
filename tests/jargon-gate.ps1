# D139 -- THE JARGON CENSUS: no internal vocabulary reaches the surface.
#
# MEASURED on the shipped page at 390x844 before this slice: `eyeballed` rendered
# on 13 rows, `ai-paste` on every photo item, `reference values` on every matched
# row, and a bare `kcal` in 54 distinct strings. The good news in that measurement
# was that nothing worse leaked -- no D-numbers, no `ref`, no `corpus`, no
# `provenance`, no `schema`. What leaked was a countable set, and this gate is what
# stops it coming back.
#
# THE CENSUS IS DEFINED BY WHAT RENDERS, NOT BY WHAT THE SOURCE SAYS. A grep of
# app.js cannot see a string built by concatenation across three lines, and most of
# these were. So the page is driven and its visible text harvested (D131: a census
# defined by a convention is defeated by the first write that breaks it).
#
# AND THE INSTRUMENT CHECKS ITSELF FIRST. A closed <details> is hidden by Chrome
# with `content-visibility`, which KEEPS A NON-ZERO BOUNDING RECT -- so a naive
# rect test scores collapsed text as visible. That fooled the measurement that
# produced this slice. The gate therefore proves it can tell the two apart before
# it trusts its own sweep: the inverse of the <small> lesson, where a declaration
# lied about size and only the computed value told the truth.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8183
$origin = "http://127.0.0.1:$port"
$dbg = 9389
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-jargon-" + [System.Guid]::NewGuid().ToString('N'))
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
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  return $r.result.result.value
}
function EvalAsyncB64([string]$js) {
  $j = $js -replace "`r`n", "`n"
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($j))
  # await the PROMISE, then stringify inside the .then -- JSON.stringify of a
  # pending promise is "{}" and reads exactly like an empty result
  $expr = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) {
    return "EXCEPTION: " + ($r.result.exceptionDetails.text) + " " + ($r.result.exceptionDetails.exception.description)
  }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (-not (Test-Path (Join-Path $repo 'corpus/dist/cnf.bin'))) {
  Write-Host "ERROR: corpus/dist/cnf.bin is missing -- run corpus/encode.py first"; exit 2
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
  $cargs = @("--headless=new", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $cargs -PassThru
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
  $ua0 = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua0; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $js = @'
(async function () {
  // PAIRS, not an object: PowerShell's ConvertFrom-Json refuses two keys that
  // differ only by case, and the surface has both "Biometric" and "biometric".
  const OUT = { screens: [], seen: [], notes: [] };
  const SEEN = Object.create(null);
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));

  // ---- the instrument, and its own test ------------------------------------
  // A closed <details> is hidden with content-visibility, which keeps a non-zero
  // bounding rect. checkVisibility is the only test that reports it correctly;
  // the ancestor walk is the fallback for engines without it.
  function visible(el) {
    if (typeof el.checkVisibility === 'function') {
      if (!el.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true,
                                visibilityProperty: true })) return false;
    } else {
      const cs = getComputedStyle(el), r = el.getBoundingClientRect();
      if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return false;
      if (r.width <= 0 || r.height <= 0) return false;
    }
    for (let p = el.parentElement; p; p = p.parentElement)
      if (p.tagName === 'DETAILS' && !p.open) return false;
    return true;
  }
  function sweep(screen) {
    const all = document.body.querySelectorAll('*');
    let n = 0;
    for (let i = 0; i < all.length; i++) {
      const el = all[i];
      if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE') continue;
      let t = '';
      for (let j = 0; j < el.childNodes.length; j++)
        if (el.childNodes[j].nodeType === 3) t += el.childNodes[j].nodeValue;
      const ph = el.getAttribute && el.getAttribute('placeholder');
      const al = el.getAttribute && el.getAttribute('aria-label');
      t = String(t).replace(/\s+/g, ' ').trim();
      if (!t && !ph && !al) continue;
      if (!visible(el)) continue;
      [t, ph, al].forEach(function (x) {
        if (!x) return;
        const k = String(x).replace(/\s+/g, ' ').trim();
        if (!k) return;
        if (!(k in SEEN)) { SEEN[k] = 1; OUT.seen.push([k, screen]); }
        n++;
      });
    }
    OUT.screens.push(screen + ' (' + n + ')');
  }

  // The clock is PINNED. This gate's fixture dates are fixed, so leaving the
  // clock live made its coverage assertions depend on the day it was run --
  // and one of them duly started failing four days later on an untouched tree.
  HT.setClock(function () { return Date.parse('2026-09-26T14:00:00-04:00'); });
  HT.boot();
  await sleep(400);
  sweep('first run');

  // ---- a SYNTHETIC day that renders every vocabulary site -----------------
  // Fixture-synthetic forever (CLAUDE.md): the gate must never need an export.
  const DK = '2026-09-26';
  const S = HT.state();
  const mk = (o) => Object.assign({ meal: 'lunch', time: '12:30', grams: 100, kcal: 200,
    protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 2, soluble_fiber_g: 0,
    confidence: 'eyeballed', source: 'ai-paste', notes: '' }, o);
  S.days[DK] = { status: 'in_progress', water_l: 0, items: [
    // a PHOTO item carrying a database match: the readable name, the visible
    // source marker, and the citation behind its disclosure
    mk({ name: 'lentil stew', ref: { ns: 'cnf', id: '1', name: 'Lentils, boiled',
         at: DK, at_ms: 1, hash: 'h', how: 'picked',
         attribution: 'Canadian Nutrient File, Health Canada, 2015', v: { '301': 1 } } }),
    // a PHOTO item with nothing known about its composition
    { name: 'mystery side', meal: 'lunch', time: '12:31', grams: 80, unresolved: true,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' },
    // a SCANNED item, with label micros
    mk({ name: 'Oat Crackers', time: '12:32', confidence: 'measured', source: 'scan',
         barcode: '00000000', micros: { sodium_mg: 100, iron_mg: 1 } }),
    // a TYPED item and a PRESET, so every source word renders
    mk({ name: 'black coffee', time: '12:33', confidence: 'weighed', source: 'manual' }),
    mk({ name: 'my usual shake', time: '12:34', source: 'preset' }),
    mk({ name: 'Vitamin D3', time: '12:35', meal: 'supplement', source: 'supplement', _auto: true })
  ] };
  S.timeline = S.timeline || {};
  S.timeline[DK] = [
    { time: '07:00', kind: 'biometric', type: 'weight', source: 'manual', notes: '', unit: 'kg', value: 90 },
    { time: '08:00', kind: 'event', type: 'cold_plunge', source: 'manual', notes: '', unit: 'min', value: 5 }
  ];
  S.current = DK;
  HT.refresh();
  await sleep(500);
  // D144: THE WORDS MOVED BEHIND A TAP. The collapse put confidence, source and
  // the citation in a body that renders only when the row is expanded, so this
  // sweep would pass over a surface that no longer prints them -- a sweep that
  // passes because the text is collapsed has not swept it. Every row is expanded
  // first, which is also the state the user reads those words in.
  // BY INDEX, re-querying each time: `itemToggle` re-renders the whole day, so a
  // list of .mhead elements captured up front is detached after the first click
  // and the remaining clicks land on a page that no longer exists -- one row
  // would have expanded and the sweep would have called that coverage.
  const rowN = document.querySelectorAll('.mitem').length;
  for (let r = 0; r < rowN; r++) {
    const h = document.querySelectorAll('.mitem')[r];
    const hh = h && h.querySelector('.mhead');
    if (hh) { hh.click(); await sleep(40); }
  }
  await sleep(250);
  OUT.rowsSeen = rowN;
  OUT.expandedRows = document.querySelectorAll('.mitem.mopen').length;
  sweep('day view');

  // ---- the instrument's SELF-TEST, before its sweep is trusted ------------
  // ...and the self-test's own subject is in that body too
  const cite = document.querySelector('.mcite');
  const body = cite && cite.querySelector('.mcitebody');
  OUT.citeFound = !!body;
  if (body) {
    const rect = body.getBoundingClientRect();
    OUT.closedHasRect = rect.height > 0;          // the trap: geometry says visible
    OUT.closedReportedHidden = !visible(body);    // the instrument says otherwise
    cite.open = true;
    await sleep(150);
    OUT.openReportedVisible = visible(body);
    OUT.citeText = (body.textContent || '').trim().slice(0, 120);
    cite.open = false;
    await sleep(100);
  }

  // an unfinished PAST day carries the status label
  const PAST = '2026-09-01';
  S.days[PAST] = { status: 'in_progress', water_l: 0, items: [mk({ name: 'old lunch' })] };
  S.current = PAST;
  HT.refresh();
  await sleep(350);
  sweep('past unfinished day');
  S.current = DK;
  HT.refresh();
  await sleep(300);

  // ---- every pane one tap behind -----------------------------------------
  const MODES = ['scan', 'quick', 'photo', 'manual', 'signal', 'med', 'lab'];
  for (let i = 0; i < MODES.length; i++) {
    HT.openSheet(); HT.setSheetMode(MODES[i]);
    await sleep(320);
    sweep('sheet:' + MODES[i]);
  }
  HT.closeSheet();
  await sleep(200);

  // the resolve surface, through the real corpus
  await HT.corpusEnsure();
  await HT.resolveOpen(DK, 1);
  await sleep(600);
  sweep('resolve sheet');
  OUT.resolveRows = document.querySelectorAll('.rcandbtn').length;
  HT.resolveClose();
  await sleep(200);

  // the micronutrient panel, expanded -- where the citation line lives
  const mp = document.querySelector('details.mpanel');
  if (mp) { mp.open = true; HT.panelToggle(true); await sleep(450); sweep('micronutrient panel'); }

  HT.openSettings();
  await sleep(450);
  sweep('settings');
  HT.closeSettings();
  await sleep(200);
  return OUT;
})()
'@
  $r = EvalAsyncB64 $js
  if ($r -like 'EXCEPTION*') { Write-Host "ERROR: the page threw: $r"; Cleanup; exit 2 }
  $R = $r | ConvertFrom-Json

  # ---- the instrument, before its findings ----------------------------------
  # D144: the day-view sweep now depends on rows being EXPANDED, because the
  # words it checks moved into a body that renders only when they are. If the
  # expand silently stopped working this gate would go green over a surface it
  # never read -- the same shape as the three dead instruments this suite has
  # already caught, so the fixture states its own precondition.
  if (-not $R.expandedRows -or $R.expandedRows -lt 1) {
    $fails += "the day-view sweep expanded NO rows, so it swept a surface with the row's vocabulary collapsed out of it -- a sweep that passes because the text is hidden has not swept it (D144)"
  }
  elseif ($R.expandedRows -lt $R.rowsSeen) {
    $fails += "the day-view sweep expanded $($R.expandedRows) of $($R.rowsSeen) rows -- the shapes differ (matched, unresolved, lost-match), so a partial expand sweeps some vocabulary and not the rest"
  }
  if (-not $R.citeFound) {
    $fails += "the citation disclosure did not render, so the instrument's self-test could not run (D96)"
  } else {
    if (-not $R.closedHasRect) {
      $fails += "SELF-TEST: a closed <details> no longer keeps a bounding rect, so this gate's reason for using checkVisibility is gone -- re-read the instrument before trusting the sweep"
    }
    if (-not $R.closedReportedHidden) {
      $fails += "SELF-TEST: the instrument reports COLLAPSED text as visible -- the sweep below would score a closed disclosure as on-screen, which is how the measurement was fooled"
    }
    if (-not $R.openReportedVisible) {
      $fails += "SELF-TEST: the instrument reports OPENED text as hidden -- it cannot see the surface at all"
    }
  }
  if ($R.resolveRows -lt 1) { $fails += "the resolve surface rendered no candidate rows, so its vocabulary was never swept" }

  # typed objects, not nested arrays: PowerShell unrolls @(@(a,b)) unpredictably
  # and $_[0] then indexes a CHAR out of a string instead of a pair
  $strings = @()
  foreach ($pair in $R.seen) { $strings += [pscustomobject]@{ t = [string]$pair[0]; s = [string]$pair[1] } }
  if ($strings.Count -lt 250) {
    $fails += "only $($strings.Count) visible strings were harvested across $($R.screens.Count) screens -- too few for the census to mean anything (a sweep of a blank page passes everything)"
  }

  # ---- COVERAGE FIRST, then the floor (D124) --------------------------------
  # A sweep that finds no banned words on a page that rendered none of the new
  # ones is not evidence of anything.
  $must = @(
    @{ re = 'estimated';        why = 'the word that replaced "eyeballed"' },
    @{ re = 'from photo';       why = 'the word that replaced "ai-paste"' },
    @{ re = 'from barcode';     why = 'the word that replaced "scan"' },
    @{ re = 'typed in';         why = 'the word that replaced "manual"' },
    # EXACT, not a substring: styling the row marker away still left the
    # micronutrient panel's citation line ("Food database: Canadian Nutrient
    # File...") matching a loose /food database/, so the plant passed. A
    # coverage assertion satisfied by a different component is not coverage.
    @{ re = '^food database$'; why = 'the VISIBLE source marker on a matched row, as its own element' },
    @{ re = '^Food database: ';  why = 'the citation line in the micronutrient panel' },
    @{ re = 'no nutrition yet'; why = 'the words that replaced "composition not recorded"' },
    @{ re = 'Day total';        why = 'the words that replaced "Total (est.)"' },
    @{ re = 'gaps? to confirm'; why = 'the fasting-gap count, which D139 wrongly renamed to a nutrition count' },
    @{ re = 'not counted in averages'; why = 'the words that replaced "excluded from averages"' },
    @{ re = 'Lentils \(boiled\)'; why = 'the readable form of a cited row name' },
    @{ re = '\d+ cal';          why = 'the row unit ruled in place of kcal' }
  )
  foreach ($m in $must) {
    $hit = $strings | Where-Object { $_.t -match $m.re } | Select-Object -First 1
    if (-not $hit) {
      $fails += "COVERAGE: nothing on any surface matches /$($m.re)/ -- $($m.why). The census cannot pass on a page that never rendered the vocabulary."
    }
  }

  # ---- the census -----------------------------------------------------------
  $banned = @(
    @{ re = 'eyeball';                 say = 'the stored confidence value, shown raw' },
    @{ re = 'ai[- ]paste';             say = 'the stored source value, shown raw' },
    @{ re = 'reference value';         say = 'D120''s internal term for a database number' },
    @{ re = 'composition not recorded'; say = 'corpus vocabulary for "no nutrition yet"' },
    @{ re = 'Total \(est\.\)';         say = 'an abbreviation nobody says out loud' },
    @{ re = 'excluded from averages';  say = 'the old day-status wording' },
    @{ re = 'tap to resolve';          say = '"resolve" is the app''s word, not the user''s' },
    # THE SEPARATOR IS THE REGEX ESCAPE, never a literal. Measured: a literal em
    # dash in this BOM-less file reaches the regex engine as codepoints
    # 226,8364,8221 instead of 8212, so this pattern could not match and this
    # banned phrase was never actually checked. update-gate documented the same
    # hazard for the middot; this list never got the lesson.
    @{ re = 'unresolved\s*\u2014\s*resolve'; say = 'the same word twice, neither of them the user''s' },
    @{ re = 'BYOK';                    say = 'an acronym only a developer knows' },
    @{ re = '(^|\s)Ingest(ed|ing)?($|\s|\.)'; say = 'the app''s word for "add to my log"' },
    @{ re = '(^|[\s\d\(])kcal\b';      say = 'the unit token, ruled to "cal" on rows and "Calories" in headings' }
  )
  foreach ($b in $banned) {
    $hits = $strings | Where-Object { $_.t -match $b.re }
    if ($hits) {
      $where = ($hits | Select-Object -First 3 | ForEach-Object { "'" + ($_.t.Substring(0, [Math]::Min(58, $_.t.Length))) + "' (" + $_.s + ")" }) -join '; '
      $fails += "JARGON: /$($b.re)/ is on the surface in $(@($hits).Count) place(s) -- $($b.say). Found: $where"
    }
  }

  if ($fails.Count) {
    Write-Host "JARGON GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "JARGON GATE: PASS -- $($strings.Count) visible strings across $($R.screens.Count) screens; the vocabulary is present and the internal words are not"
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
