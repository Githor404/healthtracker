# D143 -- SCROLL BLEED-THROUGH: the page behind a sheet does not move, does not
# take touches, and comes back exactly where it was.
#
# REPORTED FROM THE DEVICE: with the Log sheet open, swiping on the sheet scrolls
# the day underneath it.
#
# ===========================================================================
#  HEADLESS CHROME IS NOT AN IPHONE, AND THIS GATE DOES NOT CLAIM TO BE.
#  Chrome honours `overscroll-behavior` and has neither Safari's rubber-band nor
#  its visual-viewport displacement, so a PASS here is NECESSARY AND NOT
#  SUFFICIENT. The user's device check is the final word on iOS.
# ===========================================================================
#
# MEASURED CENSUS before the fix, at 390x844, with real touch sequences:
#   Scan 282 of 282 | Manual 453 of 453 | Signal 421 of 421 | Med 533 of 533
#     -- NO inner scroller, so a swipe goes straight to the document: BLEEDS
#   Quick 732 of 547 -- an inner scroller, and it chained at its end: BLEEDS
#   Photo / Lab / Settings / photo draft / find nutrients -- did not bleed, and
#     were not protected either; they simply never reached the end of their own
#     content. Five of ten reproduced; nothing defended the other five.
#
# AND THE FIRST INSTRUMENT WAS DEAD. `Input.synthesizeScrollGesture` with a touch
# source does not move this page even with nothing open, so a first census
# reported "no bleed" everywhere and meant nothing. ONLY THE CONTROL CAUGHT IT,
# which is why the control runs first and aborts the gate.
#
# THE GATE ASSERTS THE MECHANISM, NOT ONLY THE SYMPTOM. The capture-outcome modal
# passed a symptom-only census on `overscroll-behavior` alone while never locking
# the page -- a surface can be accidentally clean today and defenceless tomorrow.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8209
$Dbg = 9415
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-overlay-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  # Without focus emulation the page is never 'focused', target.focus() does not
  # move document.activeElement, and the focus assertion below would be a null
  # from a dead instrument -- exactly like synthesizeScrollGesture.
  Invoke-CDP 'Emulation.setFocusEmulationEnabled' @{ enabled = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $setup = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T12:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  // Fixture-synthetic forever: a day long enough that the page really scrolls,
  // or every assertion below is about a page that could not move anyway.
  const DK = '2026-09-26'; const S = HT.state();
  const items = []; for (let i = 0; i < 14; i++) items.push({ name: 'logged food number ' + i,
    meal: 'lunch', time: '12:0' + (i % 10), grams: 100 + i, kcal: 120 + i, protein_g: 5,
    fat_g: 4, carb_g: 18, fiber_g: 2, soluble_fiber_g: 0, confidence: 'eyeballed',
    source: 'ai-paste', notes: '' });
  S.days[DK] = { status: 'in_progress', water_l: 0, items: items };
  S.current = DK; HT.refresh(); await sleep(500);
  return { pageH: document.scrollingElement.scrollHeight, vh: window.innerHeight,
           overlays: document.querySelectorAll('[data-overlay]').length };
})()
'@
  $s0 = EvalA $setup
  if ($s0 -like 'EXCEPTION*') { Write-Host "ERROR: setup threw: $s0"; Cleanup; exit 2 }
  $S0 = $s0 | ConvertFrom-Json
  if ($S0.pageH -le ($S0.vh + 200)) {
    $fails += "the fixture page is only $($S0.pageH)px against a $($S0.vh)px viewport -- it cannot scroll, so nothing below could detect bleed (D96)"
  }
  if ($S0.overlays -lt 8) {
    $fails += "only $($S0.overlays) elements declare data-overlay -- the lock is derived from that attribute, so an undeclared overlay is an unlocked one"
  }
  # THE DECLARATION CONTRACT, derived from the overlay SHAPES rather than from a
  # count. A plant that stripped the attribute from #entrySheet passed a count
  # check, because its scrim still declared itself and the lock still engaged --
  # the sheet was simply inerted along with the page. So what is asserted is that
  # every element wearing an overlay's CSS shape declares itself.
  $undecl = Eval "JSON.stringify(Array.prototype.slice.call(document.querySelectorAll('.sheet, .panel, .omodal, .scrim, .rvwrap, .askwrap, .toast')).filter(function(e){return !e.hasAttribute('data-overlay');}).map(function(e){return (e.id||'')+'.'+(e.className||'');}))"
  $U0 = $undecl | ConvertFrom-Json
  if (@($U0).Count -gt 0) {
    $fails += "these elements wear an overlay's shape but do NOT declare data-overlay, so they neither lock the page nor are excluded from it: $(@($U0) -join ', ')"
  }

  function Swipe([int]$x, [int]$y, [int]$dy) {
    $steps = 12
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    for ($i = 1; $i -le $steps; $i++) {
      Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchMove';
        touchPoints = @(@{ x = $x; y = ($y + [int]($dy * $i / $steps)) }) } | Out-Null
      Start-Sleep -Milliseconds 14 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 420 }
  function Tap([int]$x, [int]$y) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 220 }
  function Park([int]$y) { Eval "window.scrollTo(0, $y); 1" | Out-Null; Start-Sleep -Milliseconds 280 }
  function ScrollY { return [int](Eval 'Math.round(window.scrollY)') }

  # ---- THE CONTROL, and it blocks -----------------------------------------
  Eval 'HT.closeSheet(); HT.closeSettings(); 1' | Out-Null
  Start-Sleep -Milliseconds 400
  Park 320
  $cb = ScrollY
  Swipe 195 500 -260
  $ca = ScrollY
  if ($ca -eq $cb) {
    Write-Host "OVERLAY GATE: FAIL"
    Write-Host "  - CONTROL: a swipe with NO overlay open did not move the page ($cb -> $ca). The instrument is dead, and every assertion below would pass on a page that cannot move. synthesizeScrollGesture fails this way; a real touch sequence does not."
    Cleanup; exit 1
  }
  # and the page must be UNLOCKED with nothing open
  $idle = Eval "JSON.stringify({ pos: getComputedStyle(document.body).position, locked: HT.overlaySync().locked, inert: document.querySelectorAll('[data-overlay-inert]').length })"
  $I = $idle | ConvertFrom-Json
  if ($I.pos -eq 'fixed') { $fails += "with NOTHING open the body is position:fixed -- the page is locked at rest, which is how a toast counted as a modal and made the whole page unscrollable" }
  if ($I.locked) { $fails += "with NOTHING open the lock reports itself engaged" }
  if ($I.inert -gt 0) { $fails += "with NOTHING open $($I.inert) element(s) are still inert" }

  $surfaces = @(
    @{ n = 'Log sheet (Photo)';  o = "HT.openSheet(); HT.setSheetMode('photo');";  s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Log sheet (Scan)';   o = "HT.openSheet(); HT.setSheetMode('scan');";   s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Log sheet (Quick)';  o = "HT.openSheet(); HT.setSheetMode('quick');";  s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Log sheet (Manual)'; o = "HT.openSheet(); HT.setSheetMode('manual');"; s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Log sheet (Signal)'; o = "HT.openSheet(); HT.setSheetMode('signal');"; s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Log sheet (Med)';    o = "HT.openSheet(); HT.setSheetMode('med');";    s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Log sheet (Lab)';    o = "HT.openSheet(); HT.setSheetMode('lab');";    s = '#entrySheet';    c = 'HT.closeSheet();' },
    @{ n = 'Settings panel';     o = 'HT.openSettings();';                         s = '#settingsPanel'; c = 'HT.closeSettings();' }
  )
  foreach ($f in $surfaces) {
    Park 320
    $parked = ScrollY
    Eval ($f.o + ' 1') | Out-Null
    Start-Sleep -Milliseconds 620

    # 1. THE MECHANISM: locked, offset by the parked amount, page layer inert.
    $m = Eval ("JSON.stringify((function(){var b=document.body;var cs=getComputedStyle(b);var e=document.querySelector('" + $f.s + "');var inert=document.querySelectorAll('[data-overlay-inert]').length;var pageInert=true;var k=document.body.children;for(var i=0;i<k.length;i++){var c=k[i];if(c.hasAttribute&&c.hasAttribute('data-overlay'))continue;var t=c.tagName;if(t==='SCRIPT'||t==='NOSCRIPT'||t==='TEMPLATE'||t==='STYLE')continue;if(!c.hasAttribute('inert'))pageInert=false;}var sb=e&&e.querySelector('.sheetbody, .obody, .wrap, .rvbox, .askbox');return {pos:cs.position,top:cs.top,overflow:cs.overflow,inertCount:inert,pageInert:pageInert,found:!!e,chain:sb?getComputedStyle(sb).overscrollBehaviorY:null};})())")
    $M = $m | ConvertFrom-Json
    if (-not $M.found) { $fails += "$($f.n): the surface did not render"; Eval ($f.c + ' 1') | Out-Null; continue }
    if ($M.pos -ne 'fixed') {
      $fails += "$($f.n): the body is '$($M.pos)', not fixed -- an overflow lock alone is the technique that fails on iOS Safari, and it also loses the position"
    }
    if ($M.top -ne ("-" + $parked + "px")) {
      $fails += "$($f.n): the body is offset '$($M.top)' but the page was parked at $parked px -- the offset IS the saved position, so a wrong one restores to the wrong place"
    }
    if (-not $M.pageInert) {
      $fails += "$($f.n): part of the page layer is NOT inert -- it can still take touches and focus, and `pointer-events:none` would not remove it from the tab order"
    }
    if ($M.chain -and $M.chain -ne 'contain' -and $M.chain -ne 'none') {
      $fails += "$($f.n): the overlay's scroller has overscroll-behavior-y '$($M.chain)' -- a swipe reaching its end chains to the page"
    }

    # 2. THE SYMPTOM: a real swipe inside, and again with the body at its end.
    $g = Eval ("JSON.stringify((function(){var e=document.querySelector('" + $f.s + "');var r=e.getBoundingClientRect();var b=e.querySelector('.sheetbody, .obody, .wrap, .rvbox, .askbox');var br=b?b.getBoundingClientRect():null;return {y:br?Math.round(br.top+Math.min(br.height/2,280)):Math.round(r.top+r.height/2),top:Math.round(r.top)};})())")
    $G = $g | ConvertFrom-Json
    $before = ScrollY
    Swipe 195 $G.y -260
    if ((ScrollY) -ne $before) { $fails += "$($f.n): a swipe inside the sheet SCROLLED THE PAGE ($before -> $(ScrollY)) -- the reported defect" }
    Eval ("(function(){var e=document.querySelector('" + $f.s + "');var b=e&&e.querySelector('.sheetbody, .obody, .wrap, .rvbox, .askbox');if(b)b.scrollTop=b.scrollHeight;return 1;})()") | Out-Null
    Start-Sleep -Milliseconds 250
    $atEnd = ScrollY
    Swipe 195 $G.y -260
    if ((ScrollY) -ne $atEnd) { $fails += "$($f.n): a swipe at the END of the sheet's own scroller CHAINED to the page ($atEnd -> $(ScrollY))" }

    # 3. A TAP BEHIND must not reach the page.
    Eval 'window.__behind = null; document.addEventListener("click", function(e){ if(!e.target.closest("[data-overlay]")) window.__behind = String(e.target.className||e.target.tagName); }, { once: true, capture: true }); 1' | Out-Null
    Tap 195 ([Math]::Max(60, $G.top - 50))
    $hit = Eval 'String(window.__behind)'
    if ($hit -and $hit -ne 'null') { $fails += "$($f.n): a tap behind the sheet reached the page ('$hit')" }

    # 4. CLOSING RESTORES EXACTLY.
    Eval ($f.c + ' 1') | Out-Null
    Start-Sleep -Milliseconds 450
    $after = ScrollY
    if ($after -ne $parked) { $fails += "$($f.n): closing restored the page to $after, not $parked -- 'exactly where it was' is the ruling" }
    $un = Eval "JSON.stringify({ pos: getComputedStyle(document.body).position, inert: document.querySelectorAll('[data-overlay-inert]').length })"
    $U = $un | ConvertFrom-Json
    if ($U.pos -eq 'fixed') { $fails += "$($f.n): the body is still fixed after closing" }
    if ($U.inert -gt 0) { $fails += "$($f.n): $($U.inert) page element(s) are still inert after closing" }
  }

  # ---- FOCUS must not disturb the lock -----------------------------------
  # The keyboard case is the known hard one on iOS and CANNOT be reproduced here.
  # What can: focusing an input inside a fixed-body sheet is what triggers the
  # browser's own scroll-into-view, and if that moves the page or rewrites
  # body.top the saved offset is lost -- with or without a keyboard.
  Park 320
  $fparked = ScrollY
  Eval "HT.openSheet(); HT.setSheetMode('manual'); 1" | Out-Null
  Start-Sleep -Milliseconds 650
  $fp = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const sheet = document.getElementById('entrySheet');
  const vis = Array.prototype.slice.call(sheet.querySelectorAll('input, textarea, select'))
    .filter(function (e) {
      // A closed <details> child KEEPS a bounding rect (content-visibility), so a
      // height test alone picks elements that are not rendered and cannot be
      // focused. checkVisibility is the test that tells them apart (D139).
      if (typeof e.checkVisibility === 'function'
          && !e.checkVisibility({ contentVisibilityAuto: true, visibilityProperty: true })) return false;
      const r = e.getBoundingClientRect();
      return r.height > 0 && r.top >= 0 && r.bottom <= window.innerHeight;
    });
  if (!vis.length) return { err: 'no focusable on-screen input in the Manual sheet' };
  const t = vis[0];
  t.focus();
  await sleep(250);
  const o = { name: String(t.id || t.tagName), focused: (document.activeElement === t),
              top: getComputedStyle(document.body).top, pos: getComputedStyle(document.body).position,
              y: Math.round(window.scrollY), sheetTop: Math.round(sheet.getBoundingClientRect().top) };
  t.scrollIntoView({ block: 'center' });
  await sleep(250);
  o.topAfterReveal = getComputedStyle(document.body).top;
  o.yAfterReveal = Math.round(window.scrollY);
  o.sheetTopAfterReveal = Math.round(sheet.getBoundingClientRect().top);
  t.blur();
  return o;
})()
'@
  if ($fp -like 'EXCEPTION*') { $fails += "the focus probe threw: $fp" }
  else {
    $F = $fp | ConvertFrom-Json
    if ($F.err) { $fails += "focus: $($F.err)" }
    elseif (-not $F.focused) {
      $fails += "focus: the input did not take focus, so this assertion would be a null from a dead instrument (the first probe reported exactly that)"
    } else {
      if ($F.pos -ne 'fixed') { $fails += "focus: focusing an input unfixed the body ('$($F.pos)')" }
      if ($F.top -ne ("-" + $fparked + "px")) { $fails += "focus: focusing an input moved the saved offset to '$($F.top)' from -$($fparked)px -- the restore would land in the wrong place" }
      if ($F.y -ne 0) { $fails += "focus: focusing an input scrolled the page to $($F.y)" }
      if ($F.topAfterReveal -ne ("-" + $fparked + "px") -or $F.yAfterReveal -ne 0) {
        $fails += "focus: scrollIntoView on a focused input moved the page (top '$($F.topAfterReveal)', y $($F.yAfterReveal)) -- this is what a keyboard reveal ultimately calls"
      }
      if ($F.sheetTopAfterReveal -ne $F.sheetTop) { $fails += "focus: revealing the input moved the SHEET ($($F.sheetTop) -> $($F.sheetTopAfterReveal))" }
    }
  }
  Eval 'HT.closeSheet(); 1' | Out-Null
  Start-Sleep -Milliseconds 450
  if ((ScrollY) -ne $fparked) { $fails += "focus: after a focus and a close the page restored to $(ScrollY), not $fparked" }

  if ($fails.Count) {
    Write-Host "OVERLAY GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "OVERLAY GATE: PASS -- 8 surfaces: the page is locked at its saved offset and inert, a real swipe inside or at the end of a sheet does not move it, a tap behind does not reach it, and closing restores it exactly. HEADLESS CHROME IS NOT AN IPHONE: the device check is the final word."
  Cleanup
  exit 0
} catch { Write-Host "ERROR: $_"; Cleanup; exit 2 }
