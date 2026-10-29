# R281 -- THE DAILY STACK FROM + LOG: AN EMPTY STACK, A JOIN DATE, SEVERAL NUTRIENTS, AND A
# SUPPLEMENT FOUND BY ITS HEALTH CANADA NPN. In a real browser at 390 px, by real taps.
#
#   Pre-registered in DECISIONS (R281) before the build. Health Canada's database is
#   answered by the gate in the page (HT.setLnhpdFetch) -- no network. Placeholder items
#   and products only (R204).
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8403
$Dbg = 9603
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-stackscan-" + [System.Guid]::NewGuid().ToString('N'))
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

# Set STACKSCAN_SHOTS=1 to save 390px screenshots to %TEMP%\stackscan-shots.
$shots = $null
if ($env:STACKSCAN_SHOTS) { $shots = Join-Path $env:TEMP 'stackscan-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.lnhpdLookup === 'function' && typeof HT.setLnhpdFetch === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R281 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: an EMPTY stack, and Health Canada answered by the gate (no network) ------
  # Placeholder products only (R204). NPN 80000003: an active capsule, magnesium 150 mg as
  # citrate per capsule, label dose 2; 80000004: a licence no longer active; anything else:
  # not in the database.
  $stub = @'
(function () {
  var S = HT.state(); S.settings.stack = []; HT.resave();
  window.__hc = [];
  HT.setLnhpdFetch(function (url) {
    window.__hc.push(url);
    var m = /natural-licences\/(\w+)\/.*[?&]id=(\d+)/.exec(url), body = '[]';
    if (m && m[1] === 'productlicence' && (m[2] === '80000003' || m[2] === '80000004')) body = JSON.stringify([
      { lnhpd_id: m[2] === '80000003' ? 77 : 78, licence_number: m[2], product_name: m[2] === '80000003' ? 'Gate magnesium' : 'Gate old product',
        flag_primary_name: 1, flag_product_status: m[2] === '80000003' ? 1 : 2, dosage_form: 'Capsule', company_name: 'Gate Co' }]);
    if (m && m[1] === 'medicinalingredient' && (m[2] === '77' || m[2] === '78')) body = JSON.stringify({ metadata: {}, data: [
      { ingredient_name: 'Magnesium', quantity: 150, quantity_unit_of_measure: 'milligrams', source_material: 'Magnesium citrate' },
      { ingredient_name: 'Gate herb', quantity: 500, quantity_unit_of_measure: 'milligrams', source_material: 'root' }] });
    if (m && m[1] === 'productdose' && (m[2] === '77' || m[2] === '78')) body = JSON.stringify([{ quantity_dose: 2, uom_type_desc_quantity_dose: 'Capsule', frequency: 1, uom_type_desc_frequency: 'daily' }]);
    return Promise.resolve(new Response(body, { status: 200, headers: { 'Content-Type': 'application/json' } }));
  });
  return 1;
})()
'@
  [void](Eval $stub)
  function TapSel([string]$sel) {
    $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); return { ok: q.width > 0 && q.height > 0, x: q.left + q.width / 2, y: q.top + q.height / 2, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
    if (-not $r9.ok) { return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  $stk = "(function(){ return HT.state().settings.stack.map(function (s) { return { name: s.name, npn: s.product ? s.product.npn : '', mg: s.nutrients && s.nutrients.micros ? s.nutrients.micros.magnesium_mg : null, zn: s.nutrients && s.nutrients.micros ? s.nutrients.micros.zinc_mg : null, since: s.added_on, basis: s.added_basis, je: (s.join_edits || []).length }; }); })()"

  # ---- 1. an EMPTY stack still offers + Add to stack in + Log ---------------------------------
  $e1 = TapSel '#fab'
  $e0 = EvalJ "(function(){ var sec = document.querySelector('#sheetRoot .stksec'); var a = document.querySelector('#sheetRoot .stkaddlog'); var r = a ? a.getBoundingClientRect() : null; return { sec: !!sec, add: a ? a.textContent : '', h: r ? Math.round(r.height) : 0, head: !!document.querySelector('#sheetRoot .stkopen'), all: !!document.querySelector('#sheetRoot .stkall') }; })()"
  Write-Host ("  empty stack, + Log: " + $e0)
  Shot 'empty-stack'
  [void](TapSel '#sheetRoot .stkaddlog')
  [void](Eval "document.getElementById('stkName').focus()")
  TypeText 'Item C'
  [void](TapSel '#sheetRoot .stklogform .stksave')
  $c1 = EvalJ "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#sheetRoot .stkrow'), function (x) { return x.querySelector('.stkname') && x.querySelector('.stkname').textContent === 'Item C'; })[0]; return { saved: HT.state().settings.stack.length, row: !!r, box: r ? r.querySelectorAll('input[type=checkbox]').length : 0 }; })()"
  Write-Host ("  Item C: " + $c1)
  $e0v = $e0 | ConvertFrom-Json
  Check ($e0v.sec -and ($e0v.add -eq '+ Add to stack') -and ($e0v.h -ge 44) -and (-not $e0v.head) -and (-not $e0v.all) -and ($c1 -like '*"saved":1,"row":true,"box":1*')) "R281 GATE 1: WITH AN EMPTY STACK, + Log still shows '+ Add to stack' (44 px; no count, no Took all) -- the first item is added from + Log and can be ticked"

  # ---- 5. the NPN route, from the home screen, counted ----------------------------------------
  [void](Eval "HT.closeSheet()"); WaitQuiet 'sheet closed'
  $taps = 0
  if ((TapSel '#fab').ok) { $taps++ }
  if ((TapSel '#sheetRoot .stkopen').ok) { $taps++ }
  if ((TapSel '#sheetRoot .stkaddlog').ok) { $taps++ }
  [void](Eval "document.getElementById('stkNpn').focus()")
  TypeText '80000003'
  if ((TapSel '#sheetRoot .stknpnlook').ok) { $taps++ }
  $pv = EvalJ "(function(){ var c = document.querySelector('#sheetRoot .stkprod'); return { card: c ? c.innerText.replace(/\s+/g, ' ') : '', name: (document.getElementById('stkName') || {}).value, dose: (document.getElementById('stkDose') || {}).value, unit: (document.getElementById('stkUnit') || {}).value, wide: document.documentElement.scrollWidth - document.documentElement.clientWidth }; })()"
  Write-Host ("  proposal: " + $pv)
  Shot 'npn-proposal'
  if ((TapSel '#sheetRoot .stklogform .stksave').ok) { $taps++ }
  $s5 = EvalJ $stk
  Write-Host ("  taps " + $taps + "; stack: " + $s5)
  $pvv = $pv | ConvertFrom-Json
  Check (($pvv.card -like '*Gate magnesium*Gate Co*NPN 80000003*licence active*Capsule*label dose 2*Magnesium*150 milligrams per unit*as Magnesium citrate*counts toward Magnesium*Gate herb*kept, not a nutrient this app totals*Open Government*') -and ($pvv.name -eq 'Gate magnesium') -and ($pvv.dose -eq '2') -and ($pvv.unit -eq 'capsule') -and ($pvv.wide -le 0)) "R281 GATE 5: THE NPN LOOKS UP HEALTH CANADA -- the proposal shows the product, its licence, each ingredient with its amount and FORM, what counts and what is kept, and the source; units from the label dose"
  Check (($taps -eq 5) -and ($s5 -like '*"name":"Gate magnesium","npn":"80000003","mg":300*')) ("R281 GATE 5: SAVED IN " + $taps + " TAPS from the home screen (+ Log, Daily stack, + Add to stack, Look up, Add to my stack; target <= 6) -- the item carries the NPN, and 2 capsules x 150 mg = 300 mg magnesium")
  $hc = Eval "window.__hc.length + '|' + window.__hc.every(function (u) { return u.indexOf('https://health-products.canada.ca/api/natural-licences/') === 0; })"
  Check ($hc -eq '3|true') ("R281 5: the lookup asked Health Canada only, three requests, on the tap (" + $hc + ")")
  # ticked: its magnesium reaches the day
  [void](Eval "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#sheetRoot .stkrow'), function (x) { return x.querySelector('.stkname') && x.querySelector('.stkname').textContent === 'Gate magnesium'; })[0]; r.querySelector('input[type=checkbox]').click(); return 1; })()")
  WaitQuiet 'ticked'
  $d5 = EvalJ "(function(){ var m = HT.stackDoseMicros(HT.todayKey()); return m.magnesium_mg ? m.magnesium_mg.amount : 0; })()"
  Check ($d5 -eq '300') ("R281 5: ticked, its 300 mg magnesium reaches the day from the stack (" + $d5 + ")")

  # an unknown NPN writes nothing; a licence no longer active says so
  [void](Eval "HT.closeSheet()"); WaitQuiet 'sheet closed'
  [void](TapSel '#fab'); [void](TapSel '#sheetRoot .stkopen'); [void](TapSel '#sheetRoot .stkaddlog')
  $n0 = [int](Eval "HT.state().settings.stack.length")
  [void](Eval "document.getElementById('stkNpn').focus()"); TypeText '80000099'
  [void](TapSel '#sheetRoot .stknpnlook')
  $u5 = EvalJ "(function(){ var m = document.querySelector('#sheetRoot .stknpnmsg'); return { msg: m ? m.textContent : '', n: HT.state().settings.stack.length }; })()"
  Check ($u5 -like ('*No product with that NPN in Health Canada*"n":' + $n0 + '*')) ("R281 5: an unknown NPN says so and writes nothing (" + $u5 + ")")
  [void](Eval "(function(){ var i = document.getElementById('stkNpn'); i.value = ''; i.focus(); return 1; })()"); TypeText '80000004'
  [void](TapSel '#sheetRoot .stknpnlook')
  $o5 = EvalJ "(function(){ var c = document.querySelector('#sheetRoot .stkprod'); return c ? c.innerText.replace(/\s+/g, ' ') : ''; })()"
  Check ($o5 -like '*Gate old product*licence not active*') ("R281 5: a licence no longer active is SHOWN as such, never hidden (" + $o5.Substring(0, [Math]::Min(80, $o5.Length)) + ")")
  [void](Eval "HT.stackFormCancel()"); WaitQuiet 'cancelled'

  # ---- 2. the join date ------------------------------------------------------------------------
  [void](Eval "(function(){ HT.stackFormOpen('', 'log'); return 1; })()"); WaitQuiet 'form'
  [void](Eval "document.getElementById('stkName').focus()"); TypeText 'Item D'
  $back5 = Eval "HT.shiftDate(HT.todayKey(), -5)"
  [void](Eval "(function(){ var d = document.getElementById('stkSince'); d.value = '$back5'; d.dispatchEvent(new Event('change', { bubbles: true })); return 1; })()")
  [void](TapSel '#sheetRoot .stklogform .stksave')
  $j2 = EvalJ "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Item D'; })[0]; return { since: g.added_on, basis: g.added_basis, three: HT.stackDayState(g, HT.shiftDate(HT.todayKey(), -3)), max: (function(){ HT.stackFormOpen(g.id); var m = document.getElementById('stkSince').getAttribute('max'); HT.stackFormCancel(); return m; })() }; })()"
  [void](Eval "HT.closeSheet(); HT.openSettings(); var sd = document.getElementById('stackDetails'); if (sd) sd.open = true"); WaitQuiet 'settings'
  $j2s = EvalJ "(function(){ var r = Array.prototype.filter.call(document.querySelectorAll('#stackEditor .stked'), function (x) { return x.querySelector('.stkname').textContent === 'Item D'; })[0]; return r ? r.querySelector('.stksince').textContent : ''; })()"
  Write-Host ("  Item D: " + $j2 + " " + $j2s)
  Check (($j2 -like ('*"since":"' + $back5 + '","basis":"stated","three":"in"*')) -and ($j2 -like ('*"max":"' + (Eval "HT.todayKey()") + '"*')) -and ($j2s -like '*(the date you gave)*')) "R281 GATE 2: AN ITEM ADDED WITH A PAST JOIN DATE SHOWS IT -- 'In your stack since <date> (the date you gave)'; 3 days back it is in the stack, not 'not yet'; the field allows no future day"
  [void](Eval "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Item D'; })[0]; HT.stackFormOpen(g.id); var d = document.getElementById('stkSince'); d.value = HT.shiftDate(HT.todayKey(), -7); return 1; })()")
  [void](TapSel '#stackEditor .stksave')
  $j3 = EvalJ "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Item D'; })[0]; var e = (g.join_edits || [])[0] || {}; return { n: (g.join_edits || []).length, stated: e.stated === true, today: String(e.at || '').slice(0, 10) === HT.todayKey(), exp: !!(JSON.parse(HT.exportJSON()).stackDays.items.filter(function (i) { return i.name === 'Item D'; })[0] || {}).join_edits }; })()"
  Check ($j3 -like '*"n":1,"stated":true,"today":true,"exp":true*') ("R281 2: changed in Edit, ONE join edit is recorded -- the user's, with its time -- and the backup carries it (" + $j3 + ")")
  [void](Eval "HT.closeSettings()"); WaitQuiet 'settings closed'

  # ---- 4. two items, one nutrient: the day sums them; the limit reads the sum ----------------------
  $mk = @'
(function () {
  HT.stackFormOpen('', 'log');
  document.getElementById('stkName').value = 'Item A2';
  HT.stackFormExtraAdd();
  document.getElementById('stkX0K').value = 'magnesium_mg'; document.getElementById('stkX0A').value = '200'; document.getElementById('stkX0U').value = 'mg';
  var r1 = HT.stackFormSave();
  HT.stackFormOpen('', 'log');
  document.getElementById('stkName').value = 'Item B2';
  HT.stackFormExtraAdd(); HT.stackFormExtraAdd();
  document.getElementById('stkX0K').value = 'magnesium_mg'; document.getElementById('stkX0A').value = '200';
  document.getElementById('stkX1K').value = 'zinc_mg'; document.getElementById('stkX1A').value = '10';
  var r2 = HT.stackFormSave();
  return { a: r1.ok, b: r2.ok };
})()
'@
  $m4 = EvalJ $mk
  [void](Eval "(function(){ var g = HT.state().settings.stack; ['Item A2', 'Item B2'].forEach(function (n) { var s = g.filter(function (x) { return x.name === n; })[0]; HT.stackCheck(s.id); }); return 1; })()")
  WaitQuiet 'ticked both'
  $m4b = EvalJ "(function(){ var m = HT.stackDoseMicros(HT.todayKey()); var f = HT.dayIntakeFlags(HT.todayKey()).filter(function (x) { return x.key === 'magnesium_mg'; })[0]; return { mg: m.magnesium_mg ? m.magnesium_mg.amount : 0, zn: m.zinc_mg ? m.zinc_mg.amount : 0, flag: f ? f.amount : 0, alone: HT.intakeFlag('magnesium_mg', 200) === null }; })()"
  Write-Host ("  two items: " + $m4 + " " + $m4b)
  Check (($m4 -like '*"a":true,"b":true*') -and ($m4b -like '*"mg":700,"zn":10,"flag":700,"alone":true*')) "R281 GATE 4: TWO PLACEHOLDER ITEMS CONTAINING THE SAME NUTRIENT SUM in the day's total -- 200 + 200 mg magnesium beside the 300 mg product = 700, zinc 10; the limit check reads the sum, and 200 alone flags nothing"

  # ---- 3. the photo route: provisional until confirmed ---------------------------------------------
  [void](Eval "(function(){ HT.stackFormCancel(); HT.closeSettings(); HT.openSheet('root'); HT.stackOpen(); HT.stackFormOpen('', 'log'); HT.suppLabelReply(JSON.stringify({ name: 'Gate photo', ingredients: [{ name: 'Zinc', amount: 15, unit: 'mg', form: 'zinc gluconate' }] })); return 1; })()")
  WaitQuiet 'photo proposal'
  $p3 = EvalJ "(function(){ var c = document.querySelector('#sheetRoot .stkprod'); var b = c ? c.querySelector('.stkconfirm') : null; var r = b ? b.getBoundingClientRect() : null; return { card: c ? c.innerText.replace(/\s+/g, ' ') : '', btnH: r ? Math.round(r.height) : 0 }; })()"
  Shot 'photo-provisional'
  [void](TapSel '#sheetRoot .stklogform .stksave')
  $p3a = EvalJ "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Gate photo'; })[0]; return { zn: g.nutrients && g.nutrients.micros ? g.nutrients.micros.zinc_mg || 0 : 0, prov: g.product && g.product.ns }; })()"
  [void](Eval "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Gate photo'; })[0]; HT.closeSheet(); HT.openSettings(); var sd = document.getElementById('stackDetails'); if (sd) sd.open = true; HT.stackFormOpen(g.id); return 1; })()"); WaitQuiet 'edit'
  [void](TapSel '#stackEditor .stkconfirm')
  [void](TapSel '#stackEditor .stksave')
  $p3b = EvalJ "(function(){ var g = HT.state().settings.stack.filter(function (x) { return x.name === 'Gate photo'; })[0]; return { zn: g.nutrients && g.nutrients.micros ? g.nutrients.micros.zinc_mg || 0 : 0, src: g.nutrients && g.nutrients.detail && g.nutrients.detail.zinc_mg ? g.nutrients.detail.zinc_mg.source : '', conf: !!(g.product && g.product.confirmed) }; })()"
  Write-Host ("  photo: " + $p3 + " saved " + $p3a + " confirmed " + $p3b)
  Check (($p3 -like '*Provisional*read from your photo by your AI provider, not from a database*count toward nothing until you confirm*Zinc*15 mg per unit*as zinc gluconate*') -and ($p3 -like '*"btnH":4[4-9]*' -or $p3 -like '*"btnH":[5-9][0-9]*') -and ($p3a -like '*"zn":0,"prov":"label-photo"*')) "R281 GATE 3: A PHOTO WITH NO NPN IS PROVISIONAL -- said so, with its provenance and a 44 px confirm; saved unconfirmed, it counts toward nothing"
  Check ($p3b -like '*"zn":15,"src":"label-photo","conf":true*') ("R281 GATE 3: confirmed by the user in Edit, it counts -- 15 mg zinc, its source kept (" + $p3b + ")")
  [void](Eval "HT.closeSettings(); HT.setLnhpdFetch(null)")

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("STACK SCAN GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "STACK SCAN GATE: PASS -- an empty stack still offers + Add to stack; an NPN finds the product"
Write-Host "  in Health Canada's database in 5 taps, cited, its forms kept and its nutrients counted;"
Write-Host "  a join date can be given and changed; two items' nutrients sum; photo numbers wait to count."
Write-Host "GATE: PASS"
exit 0
