# R189 -- SERVED vs EATEN: the day counts what was eaten, and shows what was served.
#
# THE DEVICE FINDING: 120 g of wings served, about 40 g eaten, and the day
# counted 120.
#
# TWO CORRECTIONS, STORED SEPARATELY. The inedible part is a CITED figure about
# the food (the Canadian Nutrient File's refuse table) and lives on the plate
# item. What was left is the USER'S statement and lives on the event. This gate
# holds the second from moving the first, and the first from moving the second.
#
# WHY A GATE AND NOT ONLY THE HARNESS BLOCK. The harness builds its own refuse
# table and its own plates, so it proves the arithmetic and the rule. It cannot
# prove that the SHIPPED Canadian corpus carries the figure for the real wing row,
# that the figure reaches a real amount step and a real day row, that the served
# weight is ON THE SCREEN beside the eaten one, or that any of it is readable and
# tappable.
#
# PRE-REGISTERED (DECISIONS.md R189 section 5, plus R190 and R191):
#   1. wings, 120 g served, on the shipped corpus's own row: 38% bone taken off,
#      74.4 g edible -- on the photo path and on the by-weight path
#   2. 1/2 tapped, by a real click: 37.2 g, the calories exactly halved, the day
#      total moved by exactly that
#   3. the served figure is on the row whenever it differs from the eaten one,
#      and a row where they do not differ has ONE figure
#   4. the correction shows its percentage, its part, the row it matched and its
#      source, on every surface that shows it
#   5. "it was boneless", tapped once, is remembered: the next log of the same
#      food is NOT corrected (R191)
#   6. a photographed item called boneless is not corrected (R191)
#   7. a boneless breast is offered and not applied; a banana and an egg logged
#      by weight get NO automatic correction (R190)
#   8. the two corrections are separate: undoing one leaves the other
#   9. every control 44px, every figure 16px, nothing scrolls sideways, at 390
#      and 360
#  10. R299.1: End meal -- one tap ends a partly eaten meal, totals unchanged, the tap
#      kept with its time; an older reminder ends the same way
#
# THE CORPUS IS THE CANADIAN ONE, under a real en-CA override, because it is the
# only one with a refuse table. If it does not hydrate WITH that table this is
# exit 2, not a pass: a served-vs-eaten gate over a corpus with no refuse data
# would pass every "not corrected" check and mean nothing.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8267
$Dbg = 9461
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-served-" + [System.Guid]::NewGuid().ToString('N'))
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
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
# Multi-line JS goes over base64 so no quoting survives to be mangled; the result
# is stringified INSIDE the page (CDP: await the promise -- a JSON.stringify of an
# async eval returns "{}").
function EvalJ([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "JSON.stringify((function(){ return eval(decodeURIComponent(escape(atob('" + $enc + "')))); })())"; returnByValue = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }
# The async form, for anything that touches the corpus: AWAIT the promise and
# stringify INSIDE the page.
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }
# REAL TYPING, one character at a time into whatever holds the focus. Setting
# .value and calling the handler would prove the handler; it would not prove the
# field survives being typed in, which is the whole of the caret rule.
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    Start-Sleep -Milliseconds 70 } }
function Settle { WaitQuiet 'after a step' }   # R283: was a fixed 400 ms

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $portv)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$portv/"); $l.Start()
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
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { } }

$fails = @()
function Check([bool]$ok, [string]$name) {
  if ($ok) { Write-Host ("  PASS  " + $name) } else { Write-Host ("  FAIL  " + $name); $script:fails += $name } }

try {
  WaitServer "$origin/index.html"
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio",
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
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  # navigator.language is what corpusNamespace() reads, and only the user-agent
  # override's acceptLanguage moves it (measured in corpus-gate).
  Invoke-CDP 'Network.enable' $null | Out-Null
  $ua = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua; acceptLanguage = 'en-CA' } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.refuseDecide === 'function' && typeof HT.eventSetAte === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the served-vs-eaten path is not on HT"; Cleanup; exit 2 }

  $corpus = EvalA @'
HT.corpusEnsure().then(function () {
  var m = HT.corpusMem() || {};
  var rows = (m.refuse && m.refuse.rows) || {};
  var idx = {}; (m.index || []).forEach(function (r) { idx[r[0]] = r[1]; });
  var find = function (name) { var hit = ''; Object.keys(idx).forEach(function (k) { if (idx[k] === name) hit = k; }); return hit; };
  window.__ids = { wing: find('Chicken, broiler, wing, meat and skin, batter dipped, fried'),
                   breast: find('Chicken, broiler, breast, meat and skin, roasted'),
                   banana: find('Banana, raw'), egg: find('Egg, chicken, whole, fresh or frozen, raw') };
  window.__name = function (k) { return idx[window.__ids[k]]; };
  window.__sum = function () { var d = HT.state().days[HT.state().current] || { items: [] };
    return d.items.reduce(function (a, x) { return a + (x.kcal || 0); }, 0); };
  window.__last = function () { var d = HT.state().days[HT.state().current] || { items: [] }; return d.items[d.items.length - 1]; };
  // A food logged BY WEIGHT, through the search pane's own pick, amount and Log
  // button -- the row is read from the corpus rather than typed for, so the gate
  // does not depend on where the typeahead happens to rank it.
  window.__byWeight = function (key, grams) {
    var id = window.__ids[key], m2 = HT.corpusMem();
    return HT.corpusLookup(id).then(function (row) {
      HT.closeSheet(); HT.openSheet(); HT.setSheetMode('search');
      var st = HT.foodSearch();
      st.rows = [{ id: id, name: idx[id], row: row, meta: m2,
                   kcal: HT.corpusValueAt(row, m2.slots, 208), protein: HT.corpusValueAt(row, m2.slots, 203),
                   fat: HT.corpusValueAt(row, m2.slots, 204), carb: HT.corpusValueAt(row, m2.slots, 205) }];
      st.phase = 'rows';
      HT.searchPickAt(0); HT.searchGrams(String(grams));
      var box = document.getElementById('fqLog');
      var line = box.querySelector('.rfline');
      var pre = { refuse: HT.searchRefuse(), offered: !!line, on: !!line && line.className.indexOf('rfon') >= 0,
                  head: line ? (line.querySelector('.rfhead') || {}).textContent : '',
                  cite: line ? (line.querySelector('.rfcite') || {}).textContent : '',
                  kcal100: st.rows[0].kcal, button: (box.querySelector('.fqlog') || {}).textContent || '' };
      box.querySelector('.fqlog').click();
      var it = window.__last();
      return { pre: pre, grams: it.grams, kcal: it.kcal, source: it.source, plate: !!it.plateId,
               served: HT.itemServedLine(it), name: it.name };
    });
  };
  return { ns: m.ns, refuseRows: Object.keys(rows).length, ids: window.__ids,
           wing: rows[window.__ids.wing], breast: rows[window.__ids.breast],
           banana: rows[window.__ids.banana], egg: rows[window.__ids.egg] };
})
'@
  Write-Host ("  corpus: " + $corpus)
  if (-not (($corpus -like '*"ns":"cnf"*') -and (-not ($corpus -like '*"refuseRows":0*')))) {
    Write-Host "ERROR: the Canadian corpus did not hydrate WITH its refuse table, so nothing checked here would mean anything"; Cleanup; exit 2 }
  $cz = $corpus | ConvertFrom-Json
  Check ($cz.refuseRows -eq 1224) "the SHIPPED Canadian corpus carries the refuse table -- 1,224 rows, the count measured in the source"
  Check (($cz.ids.wing -ne '') -and ($cz.ids.breast -ne '') -and ($cz.ids.banana -ne '') -and ($cz.ids.egg -ne '')) "the four foods this gate names are in it, found by their published names"
  Check ($corpus.Contains('"wing":[38,[["bone",38]]]')) "the batter-fried wing row is 38% bone and nothing else -- the figure the report's own '120 g served, ~75 g edible' agrees with"
  Check ($corpus.Contains('"banana":[36,[["skin",36]]]') -and $corpus.Contains('"egg":[12,[]]')) "a banana is 36% skin and an egg 12% with no part named -- the two that must NOT be taken off automatically"

  # ---- 1 + 6. the PHOTO path: wings, and wings called boneless -------------------
  # Before the user has answered anything, so what is asserted is the rule alone.
  $photo = EvalA @'
(function () {
  var p = { kcal: 290, protein_g: 20, fat_g: 21, carb_g: 6, fiber_g: 0, soluble_fiber_g: 0 };
  var r = HT.openPhotoDraft(JSON.stringify({ meal: 'dinner', items: [
    { name: 'chicken wings', grams: 120, notes: '', per100: p },
    { name: 'boneless chicken wings', grams: 100, notes: '', per100: p } ] }));
  var id = window.__ids.wing, nm = window.__name('wing');
  return HT.photoSearchApply(0, id, nm, 'picked').then(function () {
    return HT.photoSearchApply(1, id, nm, 'picked'); }).then(function () {
    var items = document.querySelectorAll('.rfblock .rfitem');
    var read = function (n) { if (!n) return null; var l = n.querySelector('.rfline');
      return { on: l.className.indexOf('rfon') >= 0, head: (l.querySelector('.rfhead') || {}).textContent,
               cite: (l.querySelector('.rfcite') || {}).textContent, btn: (l.querySelector('.rfbtn') || {}).textContent }; };
    var small = [], short = [];
    Array.prototype.forEach.call(document.querySelectorAll('.rfblock .rfname, .rfblock .rfhead, .rfblock .rfcite, .rfblock .rfbtn'), function (e) {
      var fs = parseFloat(getComputedStyle(e).fontSize); if (fs < 16) small.push(e.className + ' ' + fs);
      if (e.tagName === 'BUTTON' && e.offsetHeight < 44) short.push(e.className + ' ' + e.offsetHeight); });
    var tot = (document.querySelector('.pmtot') || {}).textContent || '';
    var before = window.__sum();
    var s = HT.photoSave();
    var its = s.items || [];
    return { opened: !!r.ok, n: items.length, a: read(items[0]), b: read(items[1]), small: small, short: short, total: tot,
             saved: !!s.ok, g0: its[0] ? its[0].grams : null, k0: its[0] ? its[0].kcal : null,
             g1: its[1] ? its[1].grams : null, added: window.__sum() - before,
             plate0: HT.getPlate(s.plateId).items[0].refuse, served0: HT.getPlate(s.plateId).items[0].grams,
             line0: its[0] ? HT.itemServedLine(its[0]) : '', line1: its[1] ? HT.itemServedLine(its[1]) : 'x' };
  });
})()
'@
  Write-Host ("  photo: " + $photo)
  $ph = $photo | ConvertFrom-Json
  Check (($ph.opened -eq $true) -and ($ph.n -eq 2)) "a photographed plate matched to the wing row shows a correction line for each item"
  Check (($ph.a.on -eq $true) -and ($ph.a.head -like '120 g served*~74.4 g edible')) "PHOTO: wings are corrected before the save -- '120 g served . ~74.4 g edible' is on the draft"
  Check (($ph.a.cite -like '38%*') -and ($ph.a.cite -like '*bone*') -and ($ph.a.cite -like '*Chicken, broiler, wing*') -and ($ph.a.cite -like '*Canadian Nutrient File*')) "the correction shows its percentage, its part, THE ROW IT MATCHED and its source (ruled D)"
  Check (($ph.b.on -eq $false) -and ($ph.b.head -like 'Served on the bone*')) "R191: the item the photo called BONELESS is not corrected -- same row, and it is the identification that says the bone is not there. The correction is offered, off"
  Check ($photo.Contains('"small":[]') -and $photo.Contains('"short":[]')) "the draft's correction lines are >= 16px and their buttons >= 44px"
  # R237 RE-POINT: the wings are MATCHED to the wing row, and a matched row's numbers
  # are the item's now -- 324 kcal per 100 g on the shipped CNF row, not the
  # photo's 290. Bone, eaten share and every rule below are unchanged.
  Check ($ph.total -like '565 cal*') "the draft's own total counts the EDIBLE wings (241) and the whole boneless ones (324) at the MATCHED ROW's 324 kcal/100 g: the figure beside Save is the figure the day will show"
  Check (($ph.saved -eq $true) -and ([math]::Abs($ph.g0 - 74.4) -lt 1e-6) -and ([math]::Abs($ph.k0 - 241.056) -lt 1e-6) -and ($ph.g1 -eq 100)) "saved: 74.4 g and 241.056 cal of wings reach the day (the row's 324/100 g), and 100 g of the boneless ones"
  Check ([math]::Abs($ph.added - 565.056) -lt 1e-6) "the day total moved by what was EATEN -- 565.056 -- not by the 712.8 that was served"
  Check (($ph.served0 -eq 120) -and ($ph.plate0.applied -eq $true) -and ($ph.plate0.by -eq 'rule') -and ($ph.plate0.pct -eq 38)) "the plate keeps the served 120 g AS ENTERED, with the correction stored beside it as the rule's decision"
  Check (($ph.line0 -eq ('120 g served ' + [char]0xB7 + ' ~74.4 g edible ' + [char]0xB7 + ' 74.4 g')) -and ($ph.line1 -eq '')) "the wings' row will show both figures; the boneless row, where nothing differs, has ONE"

  # ---- 2 + 3. the logged row, by real clicks ------------------------------------
  $row = EvalJ @'
(function () {
  HT.closeSheet();
  var nm = window.__name('wing');
  // The day's meal groups open on a tap; the rows live inside them. Opened here
  // so the row can be read -- what is asserted is that the ROW shows the served
  // figure without the row itself being opened.
  window.__open = function () {
    Array.prototype.forEach.call(document.querySelectorAll('#dayView .mghead'), function (h) {
      if (h.className.indexOf('bghead') < 0 && h.getAttribute('aria-expanded') !== 'true') h.click(); }); };
  window.__open();
  window.__row = function () { var hit = null; window.__open();
    Array.prototype.forEach.call(document.querySelectorAll('#dayView .mitem'), function (r) {
      if (!hit && r.querySelector('.mserved') && (r.querySelector('.mname') || {}).textContent === nm) hit = r; });
    return hit; };
  var r = window.__row();
  if (!r) return { err: 'no row for the wings carries a served line' };
  var sv = r.querySelector('.mserved');
  var plain = 0, both = 0;
  Array.prototype.forEach.call(document.querySelectorAll('#dayView .mitem'), function (x) { if (x.querySelector('.mserved')) both++; else plain++; });
  var out = { served: sv.textContent, font: parseFloat(getComputedStyle(sv).fontSize), visible: sv.getBoundingClientRect().height > 0,
              head: !!r.querySelector('.mhead .mname') && !!r.querySelector('.mhead .mnum'),
              num: (r.querySelector('.mhead .mnum') || {}).textContent, both: both, plain: plain,
              openBefore: !!r.querySelector('.atebar') };
  r.querySelector('.mhead').click();
  r = window.__row();
  var bar = r.querySelector('.atebar');
  out.bar = !!bar;
  out.choices = bar ? Array.prototype.map.call(bar.querySelectorAll('.atebtn'), function (b) { return b.textContent; }).join('|') : '';
  out.pressed = bar ? ((bar.querySelector('.ateon') || {}).textContent || '') : '';
  out.gbox = bar ? !!bar.querySelector('.ateg') : false;
  out.rf = !!r.querySelector('.mbody .rfline.rfon');
  return out;
})()
'@
  Write-Host ("  the row: " + $row)
  $rw = $row | ConvertFrom-Json
  Check ($rw.served -eq ('120 g served ' + [char]0xB7 + ' ~74.4 g edible ' + [char]0xB7 + ' 74.4 g')) "THE SERVED FIGURE IS ON THE DAY'S ROW while the row is still closed: '120 g served . ~74.4 g edible . 74.4 g'"
  Check (($rw.font -ge 16) -and ($rw.visible -eq $true)) "at >= 16px, and actually on screen"
  Check (($rw.head -eq $true) -and ($rw.both -eq 1) -and ($rw.plain -ge 1)) "D144 holds beside it: the collapsed line is still name and one number, and ONLY the row whose figures differ gets the second line"
  Check (($rw.bar -eq $true) -and ($rw.openBefore -eq $false)) "a real click opens the row, and 'Ate:' is inside it -- never a prompt on the day (ruled E)"
  Check (($rw.choices -eq ('all|' + [char]0xBE + '|' + [char]0xBD + '|' + [char]0xBC)) -and ($rw.gbox -eq $true)) "the control is the ruled five: all, 3/4, 1/2, 1/4, and a grams box"
  Check ($rw.pressed -eq 'all') "and it stands at ALL -- the default, stated rather than asked"
  Check ($rw.rf -eq $true) "the correction is in the opened row too, with its way out"

  $half = EvalJ @'
(function () {
  var before = window.__sum();
  var r = window.__row();
  var b = null;
  Array.prototype.forEach.call(r.querySelectorAll('.atebtn'), function (x) { if (x.textContent === '\u00bd') b = x; });
  if (!b) return { err: 'no half button' };
  b.click();
  r = window.__row();
  var day = HT.state().days[HT.state().current];
  var it = day.items.filter(function (x) { return x.plateId && x.name === window.__name('wing') && HT.itemServedLine(x); })[0];
  var t = document.getElementById('toast');
  return { grams: it.grams, kcal: it.kcal, moved: window.__sum() - before, ate: it.ate,
           served: (r.querySelector('.mserved') || {}).textContent, num: (r.querySelector('.mhead .mnum') || {}).textContent,
           want: HT.kcalDisp(it.kcal), pressed: (r.querySelector('.ateon') || {}).textContent || '',
           plateGrams: HT.getPlate(it.plateId).items[0].grams, refuse: HT.getPlate(it.plateId).items[0].refuse.applied,
           refG: it.ref ? it.ref.g : null, ref208: it.ref ? it.ref.v['208'] : null,
           undo: !!t.querySelector('.tundo'), toast: t.textContent,
           split: Array.prototype.some.call(r.querySelectorAll('.mserved .msbit'), function (b) { return b.getClientRects().length > 1; }),
           bits: r.querySelectorAll('.mserved .msbit').length };
})()
'@
  Write-Host ("  half: " + $half)
  $hf = $half | ConvertFrom-Json
  Check ([math]::Abs($hf.grams - 37.2) -lt 1e-6) "HALF TAPPED, by a real click: 37.2 g eaten -- half of the 74.4 g that was edible, not half of the 120 g served (ruled F)"
  Check ([math]::Abs($hf.kcal - 120.528) -lt 1e-6) "the calories are exactly halved: 120.528 (half of the edible 241.056)"
  Check ([math]::Abs($hf.moved + 120.528) -lt 1e-6) "THE TOTAL UPDATES: the day's calories fell by exactly the half that was not eaten"
  Check ($hf.served -eq ('120 g served ' + [char]0xB7 + ' ~74.4 g edible ' + [char]0xB7 + ' ate ' + [char]0xBD + ' ' + [char]0xB7 + ' 37.2 g')) "the row reads '120 g served . ~74.4 g edible . ate 1/2 . 37.2 g' -- the ruled order, every figure present"
  Check (($hf.num -like ($hf.want + '*')) -and ($hf.pressed -eq [string][char]0xBD)) "the row's headline number is the eaten calories, and the control shows the half that was tapped"
  Check (($hf.plateGrams -eq 120) -and ($hf.refuse -eq $true)) "SEPARATE: the fraction did not touch the served weight or the bone correction"
  Check (([math]::Abs($hf.refG - 37.2) -lt 1e-6) -and ($null -ne $hf.ref208)) "the cited values moved with the grams"
  Check (($hf.undo -eq $true) -and ($hf.toast -like 'Ate * 37.2 g*Undo')) "the tap can be undone, and its bar names the AMOUNT -- a forty-character food name wrapped it to four lines over the row it was confirming"
  Check (($hf.bits -eq 4) -and ($hf.split -eq $false)) "no figure on the row is split from its unit: the line breaks between figures, never inside one"

  # ---- 5 + 8. "it was boneless", once -- and the next log ---------------------------
  $bone = EvalJ @'
(function () {
  var r = window.__row();
  var b = r.querySelector('.mbody .rfline .rfbtn');
  if (!b) return { err: 'no way out of the correction in the row' };
  var label = b.textContent;
  b.click();
  var day = HT.state().days[HT.state().current];
  var it = day.items.filter(function (x) { return x.plateId && x.name === window.__name('wing') && x.ate && x.ate.kind === 'fraction'; })[0];
  var pi = HT.getPlate(it.plateId).items[0];
  var row2 = null;
  Array.prototype.forEach.call(document.querySelectorAll('#dayView .mitem'), function (x) {
    if (!row2 && x.querySelector('.mserved')) row2 = x; });
  return { label: label, grams: it.grams, ate: it.ate.fraction, applied: pi.refuse.applied, by: pi.refuse.by, served: pi.grams,
           line: row2 ? row2.querySelector('.mserved').textContent : '', memory: HT.refuseMemory(window.__ids.wing) };
})()
'@
  Write-Host ("  boneless: " + $bone)
  $bn = $bone | ConvertFrom-Json
  Check ($bn.label -eq 'it was boneless') "the way out of a bone correction is in the user's words"
  Check (([math]::Abs($bn.grams - 60) -lt 1e-6) -and ($bn.ate -eq 0.5)) "SEPARATE, the other way: taking the correction off put the bone back -- 60 g -- and the HALF stayed a half"
  Check (($bn.applied -eq $false) -and ($bn.by -eq 'user') -and ($bn.served -eq 120)) "it is recorded as the USER'S answer, and the served 120 g is still as entered"
  Check ($bn.line -eq ('120 g served ' + [char]0xB7 + ' ate ' + [char]0xBD + ' ' + [char]0xB7 + ' 60 g')) "the row drops the edible figure it no longer has, and keeps the served one"
  Check ($bn.memory.applied -eq $false) "and it is REMEMBERED for that food"

  # The next log of the same food, typed for real this time.
  [void](Eval "(function(){ HT.closeSheet(); HT.openSheet(); var bs = document.querySelectorAll('#sheetRoot .srbtn'); for (var i = 0; i < bs.length; i++) if (bs[i].textContent === 'Search') bs[i].click(); document.getElementById('fqQuery').focus(); return 1; })()")
  TypeText 'wing batter dipped'
  Settle
  $pick = EvalJ @'
(function () {
  var st = HT.foodSearch(), at = -1;
  (st.rows || []).forEach(function (r, i) { if (r.id === window.__ids.wing) at = i; });
  if (at < 0) return { err: 'the wing row is not among the rows typed for', rows: (st.rows || []).map(function (r) { return r.name; }) };
  document.querySelectorAll('#fqRows .fqrow')[at].click();
  document.getElementById('fqGrams').focus();
  return { picked: true };
})()
'@
  Write-Host ("  next log, pick: " + $pick)
  Check ($pick -like '*"picked":true*') "the same wing row is found by typing for it"
  TypeText '120'
  Settle
  $next = EvalJ @'
(function () {
  var box = document.getElementById('fqLog');
  var line = box.querySelector('.rfline');
  var out = { line: !!line, on: !!line && line.className.indexOf('rfon') >= 0,
              head: line ? line.querySelector('.rfhead').textContent : '', btn: line ? line.querySelector('.rfbtn').textContent : '',
              cite: line ? line.querySelector('.rfcite').textContent : '', by: (HT.searchRefuse() || {}).by,
              small: [], short: [] };
  Array.prototype.forEach.call(box.querySelectorAll('.rfhead, .rfcite, .rfbtn, .fqlog'), function (e) {
    var fs = parseFloat(getComputedStyle(e).fontSize); if (fs < 16) out.small.push(e.className + ' ' + fs);
    if (e.tagName === 'BUTTON' && e.offsetHeight < 44) out.short.push(e.className + ' ' + e.offsetHeight); });
  box.querySelector('.fqlog').click();
  var it = window.__last();
  out.grams = it.grams; out.served = HT.itemServedLine(it); out.source = it.source;
  return out;
})()
'@
  Write-Host ("  next log: " + $next)
  $nx = $next | ConvertFrom-Json
  Check (($nx.line -eq $true) -and ($nx.on -eq $false) -and ($nx.by -eq 'memory')) "R191: WINGS MARKED BONELESS ONCE ARE NOT CORRECTED ON THE NEXT LOG -- the user's earlier answer wins over the list"
  Check (($nx.head -eq 'Served on the bone?') -and ($nx.btn -eq 'take 38% off') -and ($nx.cite -like '*Canadian Nutrient File*')) "the correction is still OFFERED, one tap, with its figure and its source -- remembered is not hidden"
  Check ($next.Contains('"small":[]') -and $next.Contains('"short":[]')) "the amount step's correction line and Log button are >= 16px and >= 44px"
  Check (($nx.grams -eq 120) -and ($nx.served -eq '') -and ($nx.source -eq 'corpus')) "logged: the whole 120 g counted, one figure on the row"

  # ---- 7. a boneless breast, a banana and an egg, by weight -------------------------
  foreach ($c in @(@('breast', 150, 'bone'), @('banana', 120, 'skin'), @('egg', 100, 'inedible part'))) {
    $js = "window.__byWeight('" + $c[0] + "', " + $c[1] + ")"
    $bw = EvalA $js
    Write-Host ("  " + $c[0] + " by weight: " + $bw)
    $bv = $bw | ConvertFrom-Json
    Check (($bv.pre.offered -eq $true) -and ($bv.pre.on -eq $false) -and ($bv.pre.refuse.applied -eq $false)) ("a " + $c[0] + " logged by weight gets NO AUTOMATIC CORRECTION -- the " + $c[2] + " is offered, off")
    Check (($bv.grams -eq $c[1]) -and ($bv.served -eq '') -and ([math]::Abs($bv.kcal - $bv.pre.kcal100 * $c[1] / 100) -lt 1e-6)) ("and all " + $c[1] + " g are counted, at the food's own calories, with one figure on the row")
  }

  # ---- 1 (again). wings by weight on a clean slate: corrected ------------------------
  # The memory above says boneless, so this is a DIFFERENT wing row -- the rule's
  # own decision, on the path that is not a photo.
  $w2 = EvalA @'
(function () {
  var m = HT.corpusMem(), want = 'Chicken, broiler, wing, meat and skin,  roasted', id = '';
  (m.index || []).forEach(function (r) { if (r[1] === want || r[1] === want.replace('  ', ' ')) id = r[0]; });
  if (!id) return Promise.resolve({ err: 'no roasted wing row' });
  window.__ids.wing2 = id;
  return window.__byWeight('wing2', 120).then(function (o) { o.pct = m.refuse.rows[id][0]; return o; });
})()
'@
  Write-Host ("  wings by weight: " + $w2)
  $wv = $w2 | ConvertFrom-Json
  Check (($wv.pre.on -eq $true) -and ($wv.pre.refuse.by -eq 'rule') -and ($wv.pct -eq 48)) "wings logged BY WEIGHT are corrected by the rule -- the roasted row, 48% bone, with no memory for it"
  Check (([math]::Abs($wv.grams - 62.4) -lt 1e-6) -and ($wv.served -eq ('120 g served ' + [char]0xB7 + ' ~62.4 g edible ' + [char]0xB7 + ' 62.4 g')) -and ($wv.plate -eq $true)) "62.4 g counted of 120 g served, through the same plate, with both figures on the row"
  Check ($wv.pre.button -like 'Log * cal') "and the Log button stated the EDIBLE calories before it was tapped"

  # ---- R189/2. a TYPED item, reduced afterwards; and a removed search ---------------
  $typed = EvalJ @'
(function () {
  HT.closeSheet();
  var r = HT.addManualEntry({ name: 'Gate oats', meal: 'breakfast', time: '08:00', grams: 200, kcal: 300,
    protein_g: 10, fat_g: 6, carb_g: 54, fiber_g: 8, soluble_fiber_g: 0, confidence: 'weighed' });
  HT.refresh(); window.__open();
  var find = function () { var hit = null;
    Array.prototype.forEach.call(document.querySelectorAll('#dayView .mitem'), function (x) {
      if (!hit && (x.querySelector('.mname') || {}).textContent === 'Gate oats') hit = x; }); return hit; };
  var row = find();
  if (!row) return { err: 'no row for the typed item' };
  var plates0 = Object.keys(HT.state().plates || {}).length;
  var before = { served: !!row.querySelector('.mserved'), plate: !!r.item.plateId };
  row.querySelector('.mhead').click();
  row = find();
  var bar = row.querySelector('.atebar');
  var offered = !!bar, platesOffered = Object.keys(HT.state().plates || {}).length - plates0;
  var b = null;
  if (bar) Array.prototype.forEach.call(bar.querySelectorAll('.atebtn'), function (x) { if (x.textContent === '\u00bd') b = x; });
  if (b) b.click();
  row = find();
  var it = HT.state().days[HT.state().current].items.filter(function (x) { return x.name === 'Gate oats'; })[0];
  var pl = it.plateId ? HT.getPlate(it.plateId) : null;
  return { before: before, offered: offered, platesOffered: platesOffered, grams: it.grams, kcal: it.kcal,
           kind: pl ? pl.kind : '', servedG: pl ? pl.items[0].grams : null, refuse: pl ? !!pl.items[0].refuse : null,
           line: (row.querySelector('.mserved') || {}).textContent || '', conf: it.confidence };
})()
'@
  Write-Host ("  typed item: " + $typed)
  $ty = $typed | ConvertFrom-Json
  Check (($ty.before.served -eq $false) -and ($ty.before.plate -eq $false)) "R189/2: a TYPED item with a weight starts as an ordinary row -- one figure, no plate"
  Check (($ty.offered -eq $true) -and ($ty.platesOffered -eq 0)) "opening it offers 'Ate:' (ruled A: every path with a served weight), and OFFERING it writes no plate"
  Check (($ty.grams -eq 100) -and ($ty.kcal -eq 150)) "a real click on 1/2 halves it: 100 g, 150 cal"
  Check (($ty.kind -eq 'entry') -and ($ty.servedG -eq 200) -and ($ty.refuse -eq $false)) "the plate is made at that moment, holding the 200 g served -- and NO bone or peel correction: a typed weight is already what the user says they had"
  Check ($ty.line -eq ('weighed 200 g ' + [char]0xB7 + ' ate ' + [char]0xBD + ' ' + [char]0xB7 + ' 100 g')) "and the row shows both figures, the first AS WEIGHED: 'weighed 200 g . ate 1/2 . 100 g' (R197/3 -- the weight was measured, the share is the user's statement, and the item keeps its weighed dot)"
  Check ($ty.conf -eq 'weighed') "R189/2 (ruled R242): the share leaves the CONFIDENCE as it was -- still 'weighed' ($($ty.conf)); the weight was measured, the share is the user's statement"

  $gone = EvalJ @'
(function () {
  var cur = HT.state().current, day = HT.state().days[cur];
  var it = day.items.filter(function (x) { return x.name === window.__name('banana') && x.plateId; })[0];
  if (!it) return { err: 'no searched banana on the day' };
  var pid = it.plateId, wasEntry = HT.plateIsEntry(HT.getPlate(pid));
  var open0 = HT.openPlates(cur).length;
  HT.deleteItem(day.items.indexOf(it));
  var out = { wasEntry: wasEntry, plateGone: HT.getPlate(pid) === null,
              offered: HT.openPlates(cur).filter(function (p) { return p.id === pid; }).length, openDelta: HT.openPlates(cur).length - open0 };
  var u = document.querySelector('#toast .tundo'); if (u) u.click();
  out.back = !!HT.getPlate(pid) && day.items.filter(function (x) { return x.plateId === pid; }).length === 1;
  return out;
})()
'@
  Write-Host ("  a removed search: " + $gone)
  Check ($gone -like '*"wasEntry":true*') "the searched banana's plate is an entry plate"
  Check (($gone -like '*"plateGone":true*') -and ($gone -like '*"offered":0*') -and ($gone -like '*"openDelta":0*')) "REMOVING the banana takes its plate with it, and NOTHING is offered back as leftovers -- v0.86.0 offered a deleted food back for two days"
  Check ($gone -like '*"back":true*') "a real click on Undo brings back the item and its plate together"

  # ---- R299.1: END MEAL -- one tap ends a partly eaten meal ---------------------------
  # PRE-REGISTERED (DECISIONS R299.1): a partial entry shows the reminder with End meal;
  # one real tap clears it and the day's totals and items are unchanged; the tap is kept
  # with its time and the rest not eaten; a reminder from older data (a plate stored
  # before the field existed) is cleared the same way; the button is 44px.
  $em = EvalJ @'
(function () {
  HT.closeSheet(); HT.refresh();
  var st = HT.state(), cur = st.current, day = st.days[cur];
  var snap = function () { return JSON.stringify({ t: HT.dayTotals(st.days[cur]), items: st.days[cur].items }); };
  var out = {};
  var line = document.querySelector('#dayView .plwrap');
  var btn = line ? line.querySelector('.plend') : null;
  out.n0 = HT.plateRecallCount();
  out.line = line ? line.textContent : '';
  out.btnText = btn ? btn.textContent : '';
  out.btnH = btn ? btn.offsetHeight : 0;
  out.buttons = line ? line.querySelectorAll('.plend').length : 0;
  var open0 = HT.openPlates(cur).map(function (p) { return p.id; });
  var before = snap();
  if (btn) btn.click();
  var open1 = HT.openPlates(cur).map(function (p) { return p.id; });
  var ended = open0.filter(function (id) { return open1.indexOf(id) < 0; });
  out.endedN = ended.length;
  var pl = ended.length ? HT.getPlate(ended[0]) : null;
  out.stamp = pl && pl.ended ? pl.ended.at : '';
  out.leftG = pl && pl.ended ? pl.ended.left_g : null;
  out.leftNow = pl ? HT.plateRemainder(pl).leftGrams : null;
  out.same = snap() === before;
  out.n1 = HT.plateRecallCount();
  out.question = !!document.querySelector('.modal.show, #sheetRoot.show');
  // + Log, the Leftovers section: the typed oats (200 g served, half eaten) ended there.
  var oats = st.days[cur].items.filter(function (x) { return x.name === 'Gate oats'; })[0];
  out.oatsOpen = !!oats && open1.indexOf(oats.plateId) >= 0;
  HT.openQuickAdd();
  var rowEnd = null;
  Array.prototype.forEach.call(document.querySelectorAll('#sheetRoot .plitem'), function (x) {
    if ((x.querySelector('.plname') || {}).textContent === 'Gate oats') rowEnd = x.querySelector('.plend'); });
  out.sheetBtn = rowEnd ? rowEnd.textContent : '';
  out.sheetBtnH = rowEnd ? rowEnd.offsetHeight : 0;
  var before2 = snap();
  if (rowEnd) rowEnd.click();
  out.oatsEnded = !!oats && !!(HT.getPlate(oats.plateId) || {}).ended;
  out.oatsLeft = oats && HT.getPlate(oats.plateId).ended ? HT.getPlate(oats.plateId).ended.left_g : null;
  out.oatsGone = !Array.prototype.some.call(document.querySelectorAll('#sheetRoot .plitem .plname'), function (x) { return x.textContent === 'Gate oats'; });
  out.same2 = snap() === before2;
  out.oatsItem = oats ? [oats.grams, oats.kcal] : null;
  HT.closeSheet();
  // Undo puts the reminder back; the meal is ended again after it.
  var u = document.querySelector('#toast .tundo'); if (u) u.click();
  out.undone = !!oats && !HT.getPlate(oats.plateId).ended && HT.openPlates(cur).some(function (p) { return p.id === oats.plateId; });
  if (oats) HT.endMeal(oats.plateId);
  // AN OLDER REMINDER: a plate written before `ended` existed, as a restore brings it.
  var d = new Date(cur + 'T12:00:00'); d.setDate(d.getDate() - 1);
  var p2 = function (n) { return String(n).padStart(2, '0'); };
  var y = d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate());
  var raw = JSON.parse(JSON.stringify({ id: 'r2991-old', date: y, meal: 'dinner', time: '19:00',
    items: [{ name: 'Gate stew', grams: 300, per100: { kcal: 100, protein_g: 5, fat_g: 4, carb_g: 10, fiber_g: 1 }, notes: '' }] }));
  st.plates['r2991-old'] = HT.normalizePlate(raw);
  st.days[cur].items.push({ name: 'Gate stew', meal: 'dinner', time: '08:00', kcal: 100, protein_g: 5, fat_g: 4, carb_g: 10, fiber_g: 1,
    soluble_fiber_g: 0, grams: 100, confidence: 'eyeballed', notes: '', source: 'ai-paste', plateId: 'r2991-old', plateIdx: 0 });
  HT.resave(); HT.refresh();
  out.oldOffered = HT.openPlates(cur).some(function (p) { return p.id === 'r2991-old'; });
  var oline = document.querySelector('#dayView .plwrap');
  out.oldLine = oline ? oline.textContent : '';
  var before3 = snap();
  var ob = oline ? oline.querySelector('.plend') : null;
  if (ob) ob.click();
  out.oldEnded = !!(HT.getPlate('r2991-old') || {}).ended;
  out.oldLeft = HT.getPlate('r2991-old').ended ? HT.getPlate('r2991-old').ended.left_g : null;
  out.same3 = snap() === before3;
  out.oldGone = !HT.openPlates(cur).some(function (p) { return p.id === 'r2991-old'; });
  // The tap survives the backup's round trip: the normaliser keeps it.
  var rt = HT.normalizePlate(JSON.parse(JSON.stringify(HT.getPlate('r2991-old'))));
  out.roundTrip = !!rt.ended && rt.ended.at === HT.getPlate('r2991-old').ended.at;
  out.nEnd = HT.plateRecallCount();
  return out;
})()
'@
  Write-Host ("  end meal: " + $em)
  $e = $em | ConvertFrom-Json
  Check (($e.n0 -ge 1) -and ($e.line -like '*leftover*') -and ($e.btnText -eq 'End meal') -and ($e.buttons -eq 1)) "R299.1: a partly eaten meal's reminder on the day shows ONE button, 'End meal' ($($e.line))"
  Check (($e.btnH -ge 44) -and ($e.sheetBtnH -ge 44)) "End meal is a 44px target on the day ($($e.btnH)) and in + Log ($($e.sheetBtnH))"
  Check (($e.endedN -eq 1) -and ($e.n1 -eq ($e.n0 - 1)) -and ($e.question -eq $false)) "one real tap ends that meal and its reminder is gone -- no sheet or question opens"
  Check ($e.same -eq $true) "the day's totals and every item are unchanged by the tap"
  Check (($e.stamp -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') -and ($null -ne $e.leftG) -and ($e.leftNow -gt 1)) "the tap is kept with its time ($($e.stamp)) and the rest not eaten ($($e.leftG) g); the remainder itself is untouched arithmetic"
  Check (($e.oatsOpen -eq $true) -and ($e.sheetBtn -eq 'End meal') -and ($e.oatsEnded -eq $true) -and ($e.oatsGone -eq $true) -and ($e.same2 -eq $true)) "in + Log's Leftovers, the typed oats (200 g, half eaten) end with one tap, leave the list, and the totals stay"
  Check ((($e.oatsLeft -join ',') -eq '100') -and (($e.oatsItem -join ',') -eq '100,150')) "the oats' rest is recorded as 100 g not eaten, and the item still reads 100 g, 150 cal"
  Check ($e.undone -eq $true) "the bar's Undo puts the reminder back"
  Check (($e.oldOffered -eq $true) -and ($e.oldLine -like '*Gate stew*') -and ($e.oldEnded -eq $true) -and ($e.oldGone -eq $true) -and ($e.same3 -eq $true)) "a reminder from OLDER data (a plate stored before the field existed) shows End meal and is cleared the same way, totals unchanged"
  Check ((($e.oldLeft -join ',') -eq '200') -and ($e.roundTrip -eq $true) -and ($e.nEnd -ge 0)) "its rest, 200 g, is recorded as not eaten, and the tap survives the backup's normaliser"

  # ---- 9. the opened row, measured at both widths ------------------------------------
  foreach ($w in @(390, 360)) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    WaitQuiet 'after a step'
    $sz = EvalJ @'
(function () {
  HT.closeSheet(); HT.refresh(); window.__open();
  var rows = [];
  Array.prototype.forEach.call(document.querySelectorAll('#dayView .mitem'), function (x) { if (x.querySelector('.mserved')) rows.push(x); });
  if (!rows.length) return { err: 'no row with a served line' };
  if (!rows[0].querySelector('.atebar')) rows[0].querySelector('.mhead').click();
  rows = [];
  Array.prototype.forEach.call(document.querySelectorAll('#dayView .mitem'), function (x) { if (x.querySelector('.mserved')) rows.push(x); });
  var r = rows[0], small = [], short = [], n = 0;
  Array.prototype.forEach.call(r.querySelectorAll('.mserved, .atelab, .atebtn, .ateglab, .ateg, .rfhead, .rfcite, .rfbtn'), function (e) {
    n++;
    var fs = parseFloat(getComputedStyle(e).fontSize); if (fs < 16) small.push(e.className + ' ' + fs);
    var ctl = e.tagName === 'BUTTON' || e.tagName === 'INPUT';
    if (ctl && e.offsetHeight < 44) short.push(e.className + ' ' + e.offsetHeight);
    if (e.className.indexOf('atebtn') >= 0 && e.offsetWidth < 44) short.push(e.className + ' w' + e.offsetWidth); });
  var split = Array.prototype.some.call(r.querySelectorAll('.mserved .msbit'), function (b) { return b.getClientRects().length > 1; });
  return { n: n, small: small, short: short, split: split, rowOverflow: r.scrollWidth - r.clientWidth,
           page: document.documentElement.scrollWidth - window.innerWidth, served: r.querySelector('.mserved').textContent };
})()
'@
    Write-Host ("  sizes@" + $w + ": " + $sz)
    Check ($sz.Contains('"small":[]')) ("every figure and word in the opened row is >= 16px at " + $w)
    Check ($sz.Contains('"short":[]')) ("every control in it is >= 44px, both ways, at " + $w)
    Check ($sz -like '*"split":false*') ("and no figure is split from its unit at " + $w)
    Check (($sz -like '*"rowOverflow":0*') -and ($sz -like '*"page":0*') -and (-not ($sz -like '*"n":0,*'))) ("and neither the row nor the page scrolls sideways at " + $w + ", over a non-empty set")
  }
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null

  # ---- no dead control, with a plant ---------------------------------------------------
  $dead = EvalJ @'
(function () {
  var scan = function () { var bad = [], n = 0;
    Array.prototype.forEach.call(document.querySelectorAll('#dayView .atebar [onclick], #dayView .atebar [onchange], #dayView .rfline [onclick]'), function (b) {
      ['onclick', 'onchange'].forEach(function (attr) {
        var a = b.getAttribute(attr); if (!a) return;
        n++;
        var fn = (a.match(/^([A-Za-z0-9_$.]+)\s*\(/) || [])[1];
        if (!fn) { bad.push('unparsed: ' + a); return; }
        if (typeof window[fn] !== 'function') bad.push(fn);
      }); });
    return { n: n, bad: bad }; };
  var a = scan();
  var keep = window.eventSetAte; window.eventSetAte = undefined;
  var planted = scan().bad;
  window.eventSetAte = keep;
  return { controls: a.n, dead: a.bad, planted: planted.indexOf('eventSetAte') >= 0, restored: typeof window.eventSetAte === 'function' };
})()
'@
  Write-Host ("  controls: " + $dead)
  Check ($dead.Contains('"dead":[]') -and (-not ($dead -like '*"controls":0*'))) "every control in the opened row resolves to a function that EXISTS"
  Check (($dead -like '*"planted":true*') -and ($dead -like '*"restored":true*')) "PLANT: with one handler taken away the scan names it, and it is put back"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("SERVED GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "SERVED GATE: PASS -- the day counts what was eaten and shows what was served:"
Write-Host "  wings corrected for bone from the shipped Canadian table, a half tapped and"
Write-Host "  the total moved by exactly that, both figures on the row, boneless remembered,"
Write-Host "  and a breast, a banana and an egg left whole."
Write-Host "GATE: PASS"
exit 0
