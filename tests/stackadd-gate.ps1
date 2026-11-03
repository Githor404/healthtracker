# R317 -- A STACK ITEM ADDED BY THE LOGGING ROUTES. In a real browser at 390 px, by real taps.
# A Food: Scan barcode (+ Log's own scanner; its card's "Add to my stack" saves the label's
# numbers at the portion, the barcode kept), Photo (the model names, the row gives the numbers),
# Find (your foods, the database, the USDA offer) and Enter by hand. A Supplement: its barcode
# through OpenFoodFacts fills its name and one serving's nutrients, marked, to check. The R279
# banner with Undo, the duplicate guard, the tap counts (target <= 6), 44 px, nothing sideways.
# Placeholder products seeded into the product cache; no network, no name from the user's stack.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8432
$Dbg = 9632
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-stackadd-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set FASTRULE_SHOTS=1 to save 390px screenshots to %TEMP%\fastrule-shots.
$shots = $null
if ($env:STACKADD_SHOTS) { $shots = Join-Path $env:TEMP 'stackadd-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
function Shot([string]$name) {
  if (-not $shots) { return }
  $rv = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png' }
  [IO.File]::WriteAllBytes((Join-Path $shots ($name + '.png')), [Convert]::FromBase64String($rv.result.data))
}

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

  $boot = Eval "typeof HT === 'object' && typeof HT.packImportText === 'function' && typeof HT.linkPrepare === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R286 functions are not on HT"; Cleanup; exit 2 }

  function TapSel([string]$sel) {
    $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); return { ok: q.width > 0 && q.height > 0, x: q.left + q.width / 2, y: q.top + q.height / 2, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
    if (-not $r9.ok) { return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  $boot = Eval "typeof HT === 'object' && typeof HT.stackScanOpen === 'function' && typeof HT.stackFoodPhotoReply === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R317 functions are not on HT"; Cleanup; exit 2 }
  [void](EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok) }; })")
  # ---- the fixture: two PLACEHOLDER products in the product cache (no network) -----------------
  $fx = @'
(function () {
  HT.ProductCache.put({ barcode: '00000017', name: 'Gate oil', brands: 'Brand X', serving_g: 15, cacheVersion: 1, kcalOnLabel: true,
    per100: { kcal: 884, protein_g: 0, fat_g: 100, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0 }, micros: { saturated_fat_g: 14, vitamin_d_ug: 2 } });
  HT.ProductCache.put({ barcode: '00000024', name: 'Gate capsule', serving_g: 1, cacheVersion: 1,
    per100: { kcal: 0, protein_g: 0, fat_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0 }, micros: { zinc_mg: 1000, vitamin_c_mg: 5000 } });
  var S = HT.state(); S.settings.stack = []; HT.stackUpsert({ kind: 'supplement', name: 'Gate tea' }); HT.resave(); HT.refresh();
  return 1;
})()
'@
  [void](Eval $fx); WaitQuiet 'fixture'
  $stackJ = "JSON.stringify((HT.state().settings.stack || []).map(function (s) { return { n: s.name, k: s.kind, bc: s.barcode || '', part: s.part || null, mi: (s.nutrients && s.nutrients.micros) || null, det: (s.nutrients && s.nutrients.detail) || null }; }))"
  $sideways = "(function(){ var e = document.scrollingElement; var sh = document.getElementById('entrySheet'); var b = sh ? sh.querySelector('.sheetbody') || sh : null; return (e.scrollWidth - e.clientWidth) + (b ? Math.max(0, b.scrollWidth - b.clientWidth) : 0); })()"
  function TypeInto([string]$id, [string]$text) {
    [void](Eval ("(function(){ var e = document.getElementById(" + (ConvertTo-Json $id) + "); e.scrollIntoView({ block: 'center' }); e.focus(); e.value = ''; return 1; })()"))
    TypeText $text; Settle }
  function Sizes([string]$sel) { EvalJ ("(function(){ return Array.prototype.map.call(document.querySelectorAll(" + (ConvertTo-Json $sel) + "), function (b) { var r = b.getBoundingClientRect(); return { t: b.textContent.trim(), h: Math.round(r.height), px: parseFloat(getComputedStyle(b).fontSize) }; }); })()") }

  # ---- GATE 1: A FOOD BY ITS BARCODE, by real taps from the home screen ------------------------
  $taps = 0
  if ((TapSel '#fab').ok) { $taps++ }
  if ((TapSel '#sheetRoot .stkopen').ok) { $taps++ }
  if ((TapSel '#sheetRoot .stkaddlog').ok) { $taps++ }
  if ((TapSel '#sheetRoot .stkkinds button:nth-child(3)').ok) { $taps++ }
  $r0 = Sizes '#sheetRoot .stkroute'
  Shot 'stackadd-food-form'
  $w0 = Eval $sideways
  if ((TapSel '#sheetRoot .stkroutes .stkscan').ok) { $taps++ }
  $m1 = Eval "JSON.stringify({ mode: HT.sheetMode ? HT.sheetMode() : null, forK: (HT.scanFor() || {}).kind || '' })"
  # the camera's reading, stood in for by the barcode typed and Look up (the phone reads it with no tap)
  TypeInto 'scanBarcode' '00000017'
  [void](TapSel '#pane-scan button[onclick="doBarcodeLookup()"]')
  $c1 = Eval "(document.getElementById('scanResult') || {}).innerText || ''"
  $a1 = Sizes '#scanResult .stkscanadd'
  $w1 = Eval $sideways
  Shot 'stackadd-scan-card'
  if ((TapSel '#scanResult .stkscanadd').ok) { $taps++ }
  $s1 = Eval $stackJ
  $b1 = Eval "(document.getElementById('logConfirm') || {}).innerText || ''"
  Shot 'stackadd-banner'
  Write-Host ("  routes " + $r0 + " sideways " + $w0 + "/" + $w1 + "; scan pane " + $m1)
  Write-Host ("  card: " + ($c1 -replace "`n", ' | '))
  Write-Host ("  taps " + $taps + "; stack " + $s1 + "; banner " + ($b1 -replace "`n", ' '))
  $r0v = @($r0 | ConvertFrom-Json)
  Check (($r0 -like '*"t":"Scan barcode"*') -and ($r0 -like '*"t":"Enter by hand"*') -and ($r0 -notlike '*"t":"Photo"*') -and (@($r0v | Where-Object { $_.h -lt 44 -or $_.px -lt 16 }).Count -eq 0) -and ($w0 -eq 0)) "R317 GATE 1: THE FOOD FORM OFFERS THE LOGGING ROUTES -- Scan barcode and Enter by hand above the search, each 44 px and 16px; Photo only with a key (none here); nothing sideways"
  Check (($m1 -like '*"forK":"food"*') -and ($c1 -like 'For your stack*Gate oil*serving*15 g*133 cal*Vitamin D*0.3 mcg*Add to my stack*Back to the form*') -and ($c1 -notlike '*Meal*') -and ($c1 -notlike '*Add to day*') -and ($a1 -like '*"h":4*') -and ($w1 -eq 0)) "R317 GATE 1: + LOG'S OWN SCANNER, ITS CARD FOR THE STACK -- the product, the portion picker at its serving (15 g, 133 cal, vitamin D 0.3 mcg), 'Add to my stack', no meal or 'Add to day'; nothing sideways"
  Check (($taps -eq 6) -and ($s1 -like '*"n":"Gate oil","k":"food"*"source":"scan","grams":15,"kcal":132.6*"fat_g":15*"micros":{"saturated_fat_g":2.1,"vitamin_d_ug":0.3},"barcode":"00000017","kcal_on_label":true*')) ("R317 GATE 1: SAVED IN " + $taps + " TAPS (+ Log, Daily stack, + Add to stack, Food, Scan barcode, Add to my stack; target <= 6) -- a Food with the label's numbers at 15 g, its labelled micronutrients, its barcode")
  Check ($b1 -like 'Added to your stack: Gate oil 15 g*Undo*') "R317 GATE 1 (R279): THE TOP OF THE SCREEN SAYS IT WAS ADDED -- 'Added to your stack: Gate oil 15 g', with Undo"
  # Undo takes it back; a second scan adds it again
  [void](TapSel '#logConfirm .lcundo')
  $u1 = Eval $stackJ
  Check (($u1 -like '*Gate tea*') -and ($u1 -notlike '*Gate oil*')) "R317 GATE 1: ITS UNDO REMOVES IT -- only the item that was there before is left"
  [void](TapSel '#sheetRoot .stkaddlog'); [void](TapSel '#sheetRoot .stkkinds button:nth-child(3)'); [void](TapSel '#sheetRoot .stkroutes .stkscan')
  TypeInto 'scanBarcode' '00000017'; [void](TapSel '#pane-scan button[onclick="doBarcodeLookup()"]'); [void](TapSel '#scanResult .stkscanadd')

  # ---- GATE 2: TICKED, ITS NUMBERS ARE IN THE DAY -----------------------------------------------
  $t2 = EvalJ "(function(){ var s = HT.state().settings.stack.filter(function (x) { return x.name === 'Gate oil'; })[0]; HT.stackCheck(s.id); var it = (HT.state().days[HT.todayKey()].items || []).filter(function (x) { return x.stackId === s.id; })[0] || {}; return { n: it.name, src: it.source, g: it.grams, fat: it.fat_g, kcal: Math.round(it.kcal), d: (it.micros || {}).vitamin_d_ug, bc: it.barcode, meal: it.meal }; })()"
  Write-Host ("  ticked: " + $t2)
  Check ($t2 -like '*"n":"Gate oil","src":"scan","g":15,"fat":15,"kcal":133,"d":0.3,"bc":"00000017","meal":"supplement"*') "R317 GATE 2: A TICK PUTS ITS NUMBERS IN THE DAY -- 15 g, 15 g fat, 133 cal and the label's 0.3 mcg vitamin D, filed under the stack, its barcode kept"

  # ---- GATE 3: THE DUPLICATE GUARD --------------------------------------------------------------
  [void](TapSel '#sheetRoot .stkaddlog'); [void](TapSel '#sheetRoot .stkkinds button:nth-child(3)'); [void](TapSel '#sheetRoot .stkroutes .stkscan')
  TypeInto 'scanBarcode' '00000017'; [void](TapSel '#pane-scan button[onclick="doBarcodeLookup()"]')
  [void](TapSel '#scanResult .stkscanadd')
  $g3 = Eval "(document.getElementById('scanResult') || {}).innerText || ''"
  $n3 = Eval "(HT.state().settings.stack || []).length"
  [void](TapSel '#scanResult .scanguard .btn:not(.primary)')
  $g3b = Eval "(document.getElementById('scanResult') || {}).innerText || ''"
  [void](TapSel '#scanResult .stkscanadd')
  [void](TapSel '#scanResult .scanguard .btn.primary')
  $n3b = Eval "(HT.state().settings.stack || []).length"
  Write-Host ("  guard: " + ($g3 -replace "`n", ' | ') + " ; n " + $n3 + " -> " + $n3b)
  Check (($g3 -like '*Already in your stack: Gate oil*Add another*Cancel*') -and ($n3 -eq 2) -and ($g3b -like '*Add to my stack*') -and ($n3b -eq 3)) "R317 GATE 3 (R279): A PRODUCT ALREADY IN THE STACK IS NOT ADDED SILENTLY -- 'Already in your stack: Gate oil', Cancel adds nothing, Add another adds it"
  [void](Eval "(function(){ var l = HT.state().settings.stack; HT.stackItemRemove(l[l.length - 1].id); HT.renderSheetRoot(); return 1; })()")

  # ---- GATE 4: A FOOD BY SEARCH ------------------------------------------------------------------
  [void](Eval "HT.closeSheet()"); WaitQuiet 'closed'
  $t4 = 0
  if ((TapSel '#fab').ok) { $t4++ }
  if ((TapSel '#sheetRoot .stkopen').ok) { $t4++ }
  if ((TapSel '#sheetRoot .stkaddlog').ok) { $t4++ }
  if ((TapSel '#sheetRoot .stkkinds button:nth-child(3)').ok) { $t4++ }
  TypeInto 'stkQuery' 'butter'
  $q4 = EvalJ "(function(){ return { rows: document.querySelectorAll('#stkRows .fqrow').length, fdc: (document.querySelector('#stkRows .fdcnote, #stkRows .fdcgo') || {}).textContent || '' }; })()"
  if ((TapSel '#stkRows .fqrow').ok) { $t4++ }
  TypeInto 'stkGrams' '10'
  if ((TapSel '#sheetRoot .stklogform .stksave, #sheetRoot .stkform .stksave').ok) { $t4++ }
  $s4 = Eval $stackJ
  Write-Host ("  search: " + $q4 + " taps " + $t4 + " stack " + $s4)
  $p4 = Eval "JSON.stringify((function(){ var s = (HT.state().settings.stack || []).filter(function (x) { return x.part && x.part.ref; })[0]; return s ? { g: s.part.grams, kcal: s.part.kcal > 0, ns: s.part.ref.ns, src: s.part.source } : null; })())"
  Write-Host ("  the search's item: " + $p4)
  Check (($q4 -like '*"rows":*') -and ($q4 -notlike '*"rows":0*') -and ($q4 -like '*USDA FoodData Central*') -and ($t4 -eq 6) -and ($p4 -like '*"g":10,"kcal":true,"ns":"*","src":"corpus"*')) ("R317 GATE 4: A FOOD BY SEARCH CARRIES ITS ROW -- database rows, then the USDA FoodData Central offer; picked and saved in " + $t4 + " taps (target <= 6) with the row's numbers at 10 g, cited: " + $p4)

  # ---- GATE 5: ENTER BY HAND (My foods) STILL WORKS ------------------------------------------------
  [void](TapSel '#sheetRoot .stkaddlog'); [void](TapSel '#sheetRoot .stkkinds button:nth-child(3)')
  [void](TapSel '#sheetRoot .stkroutes .stkhand')
  $f5 = Eval "!!document.querySelector('#stkFood .mfform')"
  TypeInto 'mfName' 'Gate seed'; TypeInto 'mfKcal' '120'; TypeInto 'mfFat' '14'
  [void](TapSel '#stkFood .mfsave')
  TypeInto 'stkGrams' '14'
  [void](TapSel '#sheetRoot .stkform .stksave')
  $s5 = Eval $stackJ
  Write-Host ("  by hand: form " + $f5 + " stack " + $s5)
  Check ($f5 -and ($s5 -like '*"n":"Gate seed","k":"food"*"grams":14*"basis":"label"*')) "R317 GATE 5: ENTER BY HAND STILL WORKS -- the label form opens with nothing typed first; the food is saved to my foods and into the stack at 14 g, 'from label'"

  # ---- GATE 6: THE PHOTO NAMES; THE NUMBERS COME FROM THE ROW ------------------------------------
  [void](TapSel '#sheetRoot .stkaddlog'); [void](TapSel '#sheetRoot .stkkinds button:nth-child(3)')
  $p6js = @'
(function(){ var r = HT.stackFoodPhotoReply(JSON.stringify({ items: [{ name: 'butter', kcal: 9999, fat_g: 999 }, { name: 'bread' }, { name: 'butter' }] })); return Promise.resolve(r.pending).then(function () { return { ok: r.ok, names: r.names, q: document.getElementById('stkQuery').value, btns: Array.prototype.map.call(document.querySelectorAll('#stkPhotoOut .stkphotoname'), function (b) { return b.textContent; }), rows: document.querySelectorAll('#stkRows .fqrow').length, picked: !!document.querySelector('#sheetRoot .stkpicked'), note: (document.querySelector('#stkPhotoOut .note') || {}).textContent || '' }; }); })()
'@
  $p6 = EvalA $p6js
  [void](TapSel '#stkRows .fqrow'); TypeInto 'stkGrams' '10'; [void](TapSel '#sheetRoot .stkform .stksave')
  $k6 = Eval "JSON.stringify((function(){ var l = HT.state().settings.stack; var s = l[l.length - 1]; return { k: Math.round(s.part.kcal), ref: !!s.part.ref }; })())"
  Write-Host ("  photo: " + $p6 + " saved " + $k6)
  $k6v = $k6 | ConvertFrom-Json
  Check ($p6.Contains('"ok":true,"names":["butter","bread"]') -and $p6.Contains('"q":"butter"') -and $p6.Contains('"btns":["butter","bread"]') -and ($p6 -notlike '*"rows":0*') -and ($p6 -like '*"picked":false*') -and ($p6 -like '*numbers are not used*') -and $k6v.ref -and ($k6v.k -lt 999)) ("R317 GATE 6: A PHOTO'S REPLY ONLY NAMES -- two names (repeats dropped) offered as searches, the first run, NOTHING PICKED; the row picked gives the numbers (" + $k6v.k + " cal at 10 g, not the model's 9999)")

  # ---- GATE 7: A SUPPLEMENT BY ITS BARCODE (OpenFoodFacts) -----------------------------------------
  [void](Eval "HT.closeSheet()"); WaitQuiet 'closed'
  $t7 = 0
  if ((TapSel '#fab').ok) { $t7++ }
  if ((TapSel '#sheetRoot .stkopen').ok) { $t7++ }
  if ((TapSel '#sheetRoot .stkaddlog').ok) { $t7++ }
  if ((TapSel '#sheetRoot .stkform .stkscan').ok) { $t7++ }
  TypeInto 'scanBarcode' '00000024'; [void](TapSel '#pane-scan button[onclick="doBarcodeLookup()"]')
  $c7 = Eval "(document.getElementById('scanResult') || {}).innerText || ''"
  if ((TapSel '#scanResult .stkscanuse').ok) { $t7++ }
  $f7 = EvalJ "(function(){ return { name: (document.getElementById('stkName') || {}).value, notes: Array.prototype.map.call(document.querySelectorAll('#sheetRoot .stkoffnote, #sheetRoot .stkoffmsg'), function (n) { return n.textContent; }), rows: document.querySelectorAll('#sheetRoot .stkxrow').length }; })()"
  Shot 'stackadd-supp-form'
  if ((TapSel '#sheetRoot .stkform .stksave').ok) { $t7++ }
  $s7 = Eval $stackJ
  Write-Host ("  supplement card: " + ($c7 -replace "`n", ' | ')); Write-Host ("  form " + $f7 + " taps " + $t7 + " stack " + $s7)
  Check (($c7 -like '*For your stack*Gate capsule*one serving (1 g)*Zinc 10 mg*Vitamin C 50 mg*Check them against your label*Use these*') -and ($f7 -like '*"name":"Gate capsule"*From OpenFoodFacts, one serving*check it against your label*"rows":2*')) "R317 GATE 7: A SUPPLEMENT'S BARCODE, THROUGH OPENFOODFACTS -- its name and one serving's zinc and vitamin C are filled in as two rows, each marked 'from OpenFoodFacts -- check it against your label'; nothing saved yet"
  Check (($t7 -eq 6) -and ($s7 -like '*"n":"Gate capsule","k":"supplement","bc":"00000024"*"mi":{"zinc_mg":10,"vitamin_c_mg":50}*"source":"off"*')) ("R317 GATE 7: SAVED IN " + $t7 + " TAPS (+ Log, Daily stack, + Add to stack, Scan barcode, Use these, Add to my stack; target <= 6) -- 10 mg zinc and 50 mg vitamin C counted, each kept as from OpenFoodFacts, the barcode on the item")

  # ---- GATE 8: FROM SETTINGS, THE FORM MOVES INTO + LOG ---------------------------------------------
  [void](Eval "HT.closeSheet()"); WaitQuiet 'closed'
  [void](Eval "(function(){ HT.openSettings(); var d = document.getElementById('stackDetails'); if (d && !d.open) d.querySelector('summary').click(); return 1; })()"); WaitQuiet 'settings'
  [void](TapSel '#stackEditor .stkadd'); [void](TapSel '#stackEditor .stkkinds button:nth-child(3)')
  TypeInto 'stkNote' 'gate note'
  [void](TapSel '#stackEditor .stkroutes .stkscan')
  $g8 = Eval "JSON.stringify({ settings: getComputedStyle(document.getElementById('settingsPanel')).display, sheet: getComputedStyle(document.getElementById('entrySheet')).display, forK: (HT.scanFor() || {}).kind || '' })"
  TypeInto 'scanBarcode' '00000017'; [void](TapSel '#pane-scan button[onclick="doBarcodeLookup()"]'); [void](TapSel '#scanResult .stkscanadd'); [void](TapSel '#scanResult .scanguard .btn.primary')
  $n8 = Eval "JSON.stringify((function(){ var l = HT.state().settings.stack; var s = l[l.length - 1]; return { n: s.name, note: s.note || '' }; })())"
  Write-Host ("  from Settings: " + $g8 + " saved " + $n8)
  Check (($g8 -like '*"settings":"none","sheet":"flex","forK":"food"*') -and ($n8 -like '*"n":"Gate oil","note":"gate note"*')) "R317 GATE 8: FROM SETTINGS, SCAN BARCODE OPENS + LOG'S SCANNER with Settings closed, and what was typed in the form is kept on the item"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("STACKADD GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "STACKADD GATE: PASS -- a food reaches the stack by barcode, search, photo names and by hand, a supplement by its barcode, each carrying its numbers; the banner, its Undo and the duplicate guard hold; the routes take 6 taps."
Write-Host "GATE: PASS"
exit 0
