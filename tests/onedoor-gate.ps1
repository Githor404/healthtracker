# ONE DOOR -- the Log sheet has one entrance and one root.
#
# THE DEVICE FINDING, in the user's words: "I tapped + Log to make a combo and
# got lost." Two entry points opened the SAME sheet element in different modes.
# The FAB opened `scan` -- the camera-and-barcode path -- while the stack, the
# combos and the top 10 sat behind the day's own Quick add button. Same sheet, two
# doors, and the door you took decided what you could reach.
#
# WHY THIS GATE EXISTS AND THE HARNESS BLOCK IS NOT ENOUGH:
#   - the harness page has no #sheetRoot, so `renderSheetRoot` returns early
#     there. Every DOM-shaped claim asserted in that page would be asserted on
#     nothing. The composed ORDER of the blocks and the two-doors equality can
#     only be read off a real render of the shipped index.html.
#   - the pre-registration said the equality is asserted "by comparing the
#     rendered sheet, not by reading the argument". Comparing the argument is how
#     the original defect would have passed: both doors did call openSheet.
#
# ASSERTED HERE, and every line of it was pre-registered before the code existed:
#   1. the two doors render a BYTE-IDENTICAL root, and it is not empty
#   2. the five blocks appear in the RULED ORDER, positionally
#      (stack -> combos -> top -> something new -> the not-food links)
#   3. D146: no stack configured draws no stack block; no combos draws no combos
#      block -- and the rest of the sheet still renders
#   4. the top block shows THREE, and "Show all N" names the REAL N -- a user
#      with four repeats is shown four, never "10"
#   5. a combo saved and logged NO times is tappable, through a REAL CLICK, and
#      reaches the stepper (A4: the silent no-op, arriving through the other door)
#   6. the root hides the mode strip and the back link; a mode shows both, and the
#      back link returns to the root -- one door needs a spine
#   7. no dead control: nothing in the root is wired to a function that does not
#      exist, checked by CALLING every onclick target rather than by reading it
#   8. every control in the root is >= 16px, the buttons are >= 44px tall, and the
#      sheet does not scroll sideways at 390 or 360
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8231
$Dbg = 9437
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-onedoor-" + [System.Guid]::NewGuid().ToString('N'))
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
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "(window.__htQuiet ? window.__htQuiet(10000).then(function () { return 'quiet'; }, function (e) { return String(e && e.message || e); }) : Promise.resolve('no quiet marker on this page'))"; awaitPromise = $true; returnByValue = $true }
  $v = $r.result.result.value
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

  $boot = Eval "typeof HT === 'object' && typeof HT.renderSheetRoot === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the root sheet is not on HT"; Cleanup; exit 2 }

  # ---- the fixture ------------------------------------------------------------
  # FOUR repeat rows, deliberately: the pre-registration said "a user with four
  # repeats sees four, not three and a lie", and that case cannot be tested on a
  # fixture with ten. Two combos, one of which has been logged NO times, which is
  # the state that made tapping it do nothing.
  $fx = @'
(function () {
  var S = HT.state();
  var D1 = HT.shiftDate(HT.todayKey(), -1), D2 = HT.shiftDate(HT.todayKey(), -2);
  var f = function (name, grams, kcal, time) {
    return { name: name, meal: 'snack', time: time, grams: grams, kcal: kcal,
             protein_g: 1, fat_g: 1, carb_g: 1, fiber_g: 0, soluble_fiber_g: 0,
             confidence: 'measured', source: 'manual', notes: '' }; };
  // Four foods, each logged on both days, so the frequency list has exactly four
  // rows. Synthetic names, per the repo's standing rule -- a gate fixture is not a
  // place to keep a real log.
  var menu = [['Food A', 14, 124], ['Food B', 170, 100],
              ['Food C', 30, 196], ['Food D', 90, 180]];
  var day = function () { return { status: 'in_progress', water_l: 0,
    items: menu.map(function (m, i) { return f(m[0], m[1], m[2], '0' + (8 + i) + ':00'); }) }; };
  S.days[D1] = day(); S.days[D2] = day();
  S.settings.stack = HT.normalizeStack([
    { id: 'sg1', name: 'Capsule A', kind: 'dose', dose: 600, dose_unit: 'mg' },
    { id: 'sg2', name: 'Capsule B', kind: 'dose', dose: 500, dose_unit: 'mg' } ]);
  S.settings.combos = HT.normalizeCombos([
    { id: 'cg1', name: 'Coffee and cream', parts: [
        { name: 'brewed coffee', grams: 250, kcal: 2 },
        { name: 'half-and-half', grams: 15.5, kcal: 18 } ] },
    { id: 'cg2', name: 'Just coffee', parts: [ { name: 'brewed coffee', grams: 250, kcal: 2 } ] } ]);
  return { days: Object.keys(S.days).length, rows: HT.foodFrequency().length,
           stack: S.settings.stack.length, combos: S.settings.combos.length };
})()
'@
  $fxr = EvalJ $fx
  Write-Host ("  fixture: " + $fxr)
  Check ($fxr -like '*"rows":4*') "the fixture gives FOUR repeat rows, so the four-repeats case is testable at all"

  # ---- 1. the two doors --------------------------------------------------------
  $doors = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();                       // the FAB
  var a = document.getElementById('sheetRoot').innerHTML;
  var am = document.getElementById('pane-root').className;
  HT.closeSheet(); HT.openQuickAdd();                    // the day-s own button
  var b = document.getElementById('sheetRoot').innerHTML;
  var bm = document.getElementById('pane-root').className;
  return { same: a === b, len: a.length, aOn: am.indexOf('on') >= 0, bOn: bm.indexOf('on') >= 0 };
})()
'@
  Write-Host ("  doors: " + $doors)
  Check ($doors -like '*"same":true*') "both doors render a BYTE-IDENTICAL root -- compared on the RENDER, not on the argument, because comparing the argument is how the original defect passed"
  Check (($doors -like '*"aOn":true*') -and ($doors -like '*"bOn":true*')) "...and both land on the root pane rather than one of them opening the camera"
  Check (-not ($doors -like '*"len":0*')) "the root is not empty, so the equality above is not two blanks agreeing"

  # ---- 2. the ruled order, positionally ---------------------------------------
  $order = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var h = document.getElementById('sheetRoot').innerHTML;
  var at = function (s) { return h.indexOf(s); };
  return { stack: at('stkopen'), combos: at('My combos'), top: at('Your top'),
           novel: at('Something new'), links: at('srlinks') };
})()
'@
  Write-Host ("  order: " + $order)
  $o = $order | ConvertFrom-Json
  Check (($o.stack -ge 0) -and ($o.combos -ge 0) -and ($o.top -ge 0) -and ($o.novel -ge 0) -and ($o.links -ge 0)) `
        "all five blocks are present on the root"
  Check (($o.stack -lt $o.combos) -and ($o.combos -lt $o.top) -and ($o.top -lt $o.novel) -and ($o.novel -lt $o.links)) `
        "and they are in the RULED ORDER -- same-every-day, then what repeats, then what is new, then what is not food: most certain to least, which is the opposite of opening on the camera"

  # ---- 3. the top block counts honestly ---------------------------------------
  $top = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot');
  var first = el.querySelectorAll('.qfrow').length;
  var more = el.querySelector('.srmore');
  var moreText = more ? more.textContent : '';
  var head = (el.innerHTML.match(/Your top ([0-9]+)/) || [])[1] || '';
  HT.topAllToggle();
  var all = el.querySelectorAll('.qfrow').length;
  var fewer = el.querySelector('.srmore') ? el.querySelector('.srmore').textContent : '';
  HT.topAllToggle();
  return { first: first, all: all, moreText: moreText, head: head, fewer: fewer,
           back: el.querySelectorAll('.qfrow').length };
})()
'@
  Write-Host ("  top: " + $top)
  $t = $top | ConvertFrom-Json
  Check ($t.first -eq 3) "the top block opens showing THREE rows"
  Check ($t.all -eq 4) "and Show all reveals the REST -- four, which is how many there are"
  Check ($t.moreText -like '*4*') "the button NAMES THE REAL NUMBER: a user with four repeats is offered four, never 'Show all 10' over a list of four"
  Check ($t.head -eq '4') "and the heading counts the same four, so the heading and the button cannot disagree"
  Check ($t.back -eq 3) "toggling back collapses it again, so the control is a toggle rather than a one-way door"

  # ---- 4. a combo logged no times, through a real click -----------------------
  # THE DEFECT THIS CATCHES: the frequency list is a measurement over the log, so a
  # combo saved a minute ago was not in it, `quickRow` found nothing, `quickPlan`
  # returned null, the stepper rendered '' and TAPPING IT DID NOTHING AT ALL. That
  # is A4's silent no-op arriving through the other door. Asserted with a real
  # click, because a function call would not have proved the row was reachable.
  $tap = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot');
  var btns = el.querySelectorAll('.srcombo');
  var logged = HT.foodFrequency().filter(function (r) { return r.key === 'combo:cg1'; }).length;
  if (!btns.length) return { err: 'no combo rows on the root' };
  btns[0].click();
  var q = document.getElementById('pane-quick');
  var plan = HT.quickPlan();
  return { neverLogged: logged === 0, quickOn: q.className.indexOf('on') >= 0,
           stepped: !!plan && !!plan.combo, parts: plan && plan.combo ? plan.combo.rows.length : -1 };
})()
'@
  Write-Host ("  tap: " + $tap)
  Check ($tap -like '*"neverLogged":true*') "the combo under test has been logged NO times -- the precondition, stated, so a pass here cannot come from a combo that happened to be in the list"
  Check ($tap -like '*"quickOn":true*') "tapping it moves the sheet to the stepper rather than doing nothing at all (A4)"
  Check ($tap -like '*"stepped":true*') "...and a plan exists behind that screen, so the button it shows will log something"
  Check ($tap -like '*"parts":2*') "the stepper holds BOTH parts, so the one tap logs the coffee and the cream"
  $backOut = EvalJ @'
(function () {
  HT.setSheetMode('root');
  return { plan: HT.quickPlan(), rootOn: document.getElementById('pane-root').className.indexOf('on') >= 0 };
})()
'@
  Check ($backOut -like '*"plan":null*') "and going back to the root ABANDONS the pick -- a half-finished action must not outlive the gesture that walked away from it"

  # ---- 4b. A FOOD ROW, tapped from the root -----------------------------------
  # THE GAP IN MY OWN PRE-REGISTRATION, and the flow gate found it. I asserted
  # that the top block SHOWS three rows and never that TAPPING one arrives
  # anywhere: the combo rows went through comboPickById, which happened to set the
  # mode, while the food rows called quickPickAt, which did not. The pick landed,
  # the stepper rendered into a pane that was not on screen, and the Log button it
  # drew was real and unreachable. Counting a control is not reaching it.
  $food = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot');
  var rows = el.querySelectorAll('.qfrow');
  if (!rows.length) return { err: 'no food rows on the root' };
  var label = rows[0].textContent;
  rows[0].click();
  var q = document.getElementById('pane-quick');
  var vis = function (n) { if (!n) return false; var r = n.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && getComputedStyle(n).visibility !== 'hidden'; };
  var log = null;
  Array.prototype.forEach.call(document.querySelectorAll('#pane-quick button'), function (b) {
    if ((b.textContent || '').indexOf('Log ') === 0) log = b; });
  return { quickOn: q.className.indexOf('on') >= 0, picked: !!HT.quickPlan(),
           logVisible: vis(log), logText: log ? log.textContent : '', row: label };
})()
'@
  Write-Host ("  food: " + $food)
  Check ($food -like '*"quickOn":true*') "tapping a FOOD row on the root moves the sheet to the stepper -- the rows live on two surfaces now, and only one of them renders the stepper"
  Check ($food -like '*"picked":true*') "...and the pick is real behind it"
  Check ($food -like '*"logVisible":true*') "and the Log button is ON SCREEN and tappable -- the defect was a real button drawn into a hidden pane, which reads exactly like a row that does nothing"
  Check ($food -like '*"logText":"Log *') "the button states what it will log before it is tapped"

  # ---- 5. the spine: the strip, the back link -----------------------------
  $spine = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var modes = document.getElementById('sheetModes'), back = document.getElementById('sheetBack');
  // MEASURED, not read off the attribute. This check used to read `.hidden`, and
  // it passed through v0.83.0 and v0.84.0 while the strip sat on the root in
  // plain sight: `hidden` is an attribute, `.modes{display:flex}` is a class rule,
  // and the class won. A screenshot found it. So: is it on the screen?
  var off = function (n) { var r = n.getBoundingClientRect();
    return getComputedStyle(n).display === 'none' || r.height === 0; };
  var rootHid = { modes: off(modes), back: off(back) };
  var sx = document.querySelector('#entrySheet .sheetx'), sh = document.getElementById('entrySheet');
  var xGap = Math.round(sh.getBoundingClientRect().right - sx.getBoundingClientRect().right);
  // THE PLANT is the defect itself: the attribute still says hidden while the
  // element is forced on screen. The old check would have passed here.
  modes.style.display = 'flex';
  var plant = { attr: modes.hidden, measuredOff: off(modes) };
  modes.style.display = '';
  HT.setSheetMode('manual');
  var inMode = { modes: off(modes), back: off(back) };
  back.click();
  var after = document.getElementById('pane-root').className.indexOf('on') >= 0;
  return { rootHid: rootHid, inMode: inMode, backReturns: after, plant: plant, xAtRight: xGap >= 0 && xGap < 40 };
})()
'@
  Write-Host ("  spine: " + $spine)
  Check (($spine -like '*"rootHid":{"modes":true,"back":true}*')) "on the root the mode strip is hidden -- the strip IS the root-s own content, so showing both is showing the list twice"
  Check (($spine -like '*"inMode":{"modes":false,"back":false}*')) "and inside a mode both the strip and the back link are there: one door needs a spine, or the sheet is a maze with one entrance"
  Check ($spine -like '*"backReturns":true*') "the back link returns to the root, by a real click"
  Check ($spine -like '*"xAtRight":true*') "on the root the close button is at the RIGHT edge of the sheet -- hiding the strip for real left it stranded on the left, which a second screenshot found"
  Check ($spine -like '*"plant":{"attr":true,"measuredOff":false}*') "PLANT: with the strip forced on screen while its attribute still says hidden, the measurement says ON SCREEN -- the attribute check this replaced passed on exactly that, for two releases"

  # ---- 5b. R197/2: SEARCH IS ON SCREEN WITHOUT SCROLLING, AND THE FOOT IS GONE -----
  # Ruled: "shrink the Log-sheet footer so Search is visible without scrolling at
  # 390x844. Gate it." Measured on THIS fixture -- a stack, two combos, four
  # repeats, which is a full sheet -- because a sheet with nothing on it would
  # show Search however tall its foot was.
  #
  # MEASURED BEFORE: the foot was four stacked links, about 290px of 844, on every
  # pane; on the root, two of the four repeated the two directly above it. With
  # the foot gone Search was STILL 14px below the screen, in the second row of a
  # two-by-two. So this asserts the thing ruled, not the mechanism: where the
  # Search button's bottom edge is.
  $fold = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot'), body = document.querySelector('#entrySheet .sheetbody');
  var foot = document.getElementById('sheetFoot');
  var b = null, row = [];
  Array.prototype.forEach.call(el.querySelectorAll('.srbtn'), function (x) { row.push(Math.round(x.getBoundingClientRect().top)); if (x.textContent === 'Search') b = x; });
  var r = b.getBoundingClientRect(), fr = foot.getBoundingClientRect();
  var off = function (n) { var q = n.getBoundingClientRect(); return getComputedStyle(n).display === 'none' || q.height === 0; };
  var out = { vw: window.innerWidth, vh: window.innerHeight, scrolled: body.scrollTop, searchTop: Math.round(r.top), searchBottom: Math.round(r.bottom),
              bodyTop: Math.round(body.getBoundingClientRect().top), oneRow: row.every(function (t) { return t === row[0]; }), n: row.length,
              footOff: off(foot), footH: Math.round(fr.height),
              links: Array.prototype.map.call(el.querySelectorAll('.srlinks .linklike'), function (x) { return x.textContent; }).join('|') };
  // THE PLANT is the defect this would otherwise repeat: the attribute says
  // hidden while the foot is forced on screen (the mode-strip lesson).
  foot.style.display = 'flex';
  out.plant = { attr: foot.hidden, measuredOff: off(foot) };
  foot.style.display = '';
  HT.setSheetMode('manual');
  var more = foot.querySelector('.sheetmore');
  out.pane = { off: off(foot), h: Math.round(foot.getBoundingClientRect().height), open: more.open,
               summary: (more.querySelector('summary') || {}).textContent };
  more.querySelector('summary').click();
  var small = [], short = [];
  Array.prototype.forEach.call(more.querySelectorAll('.linklike'), function (x) {
    var fs = parseFloat(getComputedStyle(x).fontSize); if (fs < 16) small.push(fs);
    if (x.offsetHeight < 44) short.push(x.offsetHeight); });
  out.opened = { open: more.open, links: Array.prototype.map.call(more.querySelectorAll('.linklike'), function (x) { return x.textContent; }).join('|'),
                 visible: Array.prototype.every.call(more.querySelectorAll('.linklike'), function (x) { return x.getBoundingClientRect().height > 0; }),
                 small: small, short: short };
  HT.setSheetMode('root'); HT.setSheetMode('manual');
  out.reclosed = !foot.querySelector('.sheetmore').open;
  HT.setSheetMode('root');
  return out;
})()
'@
  Write-Host ("  the fold: " + $fold)
  $fd = $fold | ConvertFrom-Json
  Check (($fd.vw -eq 390) -and ($fd.vh -eq 844) -and ($fd.scrolled -eq 0)) "PRECONDITION: 390x844, and the sheet has not been scrolled"
  Check (($fd.searchBottom -le $fd.vh) -and ($fd.searchTop -ge $fd.bodyTop)) "R197/2: SEARCH IS ON SCREEN WITHOUT SCROLLING on a full Log sheet -- its whole button, above the bottom edge. Before: 14px below it even with the foot removed"
  Check (($fd.oneRow -eq $true) -and ($fd.n -eq 4)) "because the four are one row now, in the ruled order, and not two rows of two"
  Check (($fd.footOff -eq $true) -and ($fd.footH -eq 0)) "the root has NO foot -- measured as not on screen, not read off its attribute"
  Check ($fold.Contains('"plant":{"attr":true,"measuredOff":false}')) "PLANT: with the foot forced on screen while its attribute still says hidden, the measurement says ON SCREEN -- the check that the mode strip's gate did not have"
  Check ($fd.links -eq 'Log a dose I took|Log event or biometric|Add a medication from its label|Log a lab panel') "nothing was lost with it: the root's own links now carry all four the foot offered"
  Check (($fd.pane.off -eq $false) -and ($fd.pane.h -le 60) -and ($fd.pane.open -eq $false) -and ($fd.pane.summary -like 'Other things to log*')) "on every other pane the foot is ONE line -- 60px or less, where it was about 290"
  Check (($fd.opened.open -eq $true) -and ($fd.opened.visible -eq $true) -and ($fd.opened.links -eq 'Log event or biometric|Add a medication from its label|Log a dose I took|Log a lab panel')) "a real click opens it to the same four links"
  Check ($fold.Contains('"small":[],"short":[]')) "each of them >= 16px and >= 44px tall"
  Check ($fd.reclosed -eq $true) "and it is closed again on the next pane, whatever it was left as"

  # ---- 6. D146: nothing configured draws no block -----------------------------
  $empty = EvalJ @'
(function () {
  var S = HT.state();
  var keepS = JSON.parse(JSON.stringify(S.settings.stack || []));
  var keepC = JSON.parse(JSON.stringify(S.settings.combos || []));
  S.settings.stack = []; S.settings.combos = [];
  HT.closeSheet(); HT.openSheet();
  var h = document.getElementById('sheetRoot').innerHTML;
  var out = { stack: h.indexOf('stkopen') >= 0, combos: h.indexOf('My combos') >= 0,
              top: h.indexOf('Your top') >= 0, novel: h.indexOf('Something new') >= 0,
              apology: (h.indexOf('None yet') >= 0) || (h.indexOf('coming next') >= 0) };
  S.settings.stack = keepS; S.settings.combos = keepC;
  HT.closeSheet(); HT.openSheet();
  return out;
})()
'@
  Write-Host ("  empty: " + $empty)
  Check ($empty -like '*"stack":false*') "with no stack configured the stack block is ABSENT (D146) -- an empty stack must not advertise itself on a sheet opened to log food"
  Check ($empty -like '*"combos":false*') "with no combos saved the combos block is ABSENT, which is what the pre-registration said and what the first draft of the code got wrong"
  Check ($empty -like '*"apology":false*') "and neither leaves behind a heading over an apology for being empty, or a note promising a feature that is not there"
  Check (($empty -like '*"top":true*') -and ($empty -like '*"novel":true*')) "while the blocks that DO have something in them still render, so the absences are narrow"

  # ---- 7. no dead control ------------------------------------------------------
  # The defect by name: a button wired to a function that does not exist throws on
  # tap and looks like a button that does nothing. Checked by RESOLVING every
  # onclick target in the root, not by reading the markup for known names -- a
  # read would only ever catch the names I thought to look for.
  $dead = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot');
  var bad = [];
  Array.prototype.forEach.call(el.querySelectorAll('[onclick]'), function (b) {
    var a = b.getAttribute('onclick') || '';
    var fn = (a.match(/^([A-Za-z0-9_$.]+)\s*\(/) || [])[1];
    if (!fn) { bad.push('unparsed: ' + a); return; }
    var ref = fn.split('.').reduce(function (o, k) { return (o == null) ? o : o[k]; }, window);
    if (typeof ref !== 'function') bad.push(fn);
  });
  return { controls: el.querySelectorAll('[onclick]').length, dead: bad };
})()
'@
  Write-Host ("  controls: " + $dead)
  # .Contains, NOT -like: PowerShell reads [ ] in a wildcard as a CHARACTER CLASS,
  # so '*"dead":[]*' is not a pattern that fails to match -- it is an invalid
  # pattern that THROWS, and it threw here on the first run. An empty JSON array is
  # the shape every list-of-problems check in this gate reports, so the three of
  # them compare substrings instead.
  Check ($dead.Contains('"dead":[]')) "every control on the root resolves to a function that EXISTS -- resolved, not read, so it catches the names nobody thought to look for"
  Check (-not ($dead -like '*"controls":0*')) "and there are controls to resolve, so the line above is not a pass over an empty list"
  # THE PLANT. A check that cannot fail is not a check, and this is the newest
  # idea in this file -- resolving handlers rather than reading for known names.
  # So one handler is taken away and the same scan must name it. Restored in the
  # same expression, because a plant that outlives its assertion is a defect.
  $plant = EvalJ @'
(function () {
  var keep = window.comboPickById;
  window.comboPickById = undefined;
  var el = document.getElementById('sheetRoot');
  var bad = [];
  Array.prototype.forEach.call(el.querySelectorAll('[onclick]'), function (b) {
    var at = b.getAttribute('onclick') || '';
    var fn = (at.match(/^([A-Za-z0-9_$.]+)\s*\(/) || [])[1];
    if (!fn) return;
    var ref = fn.split('.').reduce(function (o, k) { return (o == null) ? o : o[k]; }, window);
    if (typeof ref !== 'function') bad.push(fn);
  });
  window.comboPickById = keep;
  return { caught: bad, restored: typeof window.comboPickById === 'function' };
})()
'@
  Write-Host ("  plant: " + $plant)
  Check ($plant.Contains('comboPickById')) "PLANT: with one handler taken away the scan NAMES IT -- so the clean result above is a measurement and not a scan that quietly checks nothing"
  Check ($plant.Contains('"restored":true')) "...and the plant is put back inside the same expression, because a plant that outlives its assertion is itself the defect"

  # =========================== ONE DOOR / 2 ====================================
  # Search in block (d), and "+ New combo" beneath the combos. Both need the
  # corpus, so it is acquired first and its absence is an ENVIRONMENT error: a
  # search gate that passed over an empty index would be the fast nothing.
  $corpus = EvalA @'
HT.corpusEnsure().then(function () {
  var st = HT.corpusState();
  return { ready: !!(st && st.ready), rows: st ? st.rows : 0, probe: HT.matchCandidates('coffee', 8).length };
})
'@
  Write-Host ("  corpus: " + $corpus)
  if (-not (($corpus -like '*"ready":true*') -and (-not ($corpus -like '*"probe":0*')))) {
    Write-Host "ERROR: the corpus did not hydrate, so nothing searched here would mean anything"; Cleanup; exit 2 }

  # ---- 9. Search: block (d), typed for real -----------------------------------
  $sopen = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot');
  var names = Array.prototype.map.call(el.querySelectorAll('.srbtn'), function (b) { return b.textContent; }).join(',');
  var btn = null;
  Array.prototype.forEach.call(el.querySelectorAll('.srbtn'), function (b) { if (b.textContent === 'Search') btn = b; });
  if (!btn) return { names: names, err: 'no Search button' };
  btn.click();
  var f = document.getElementById('fqQuery');
  if (f) { f.__mark = 'kept'; f.focus(); }
  return { names: names, paneOn: document.getElementById('pane-search').className.indexOf('on') >= 0,
           field: !!f, back: !document.getElementById('sheetBack').hidden,
           control: HT.matchCandidates('coff', 8).length };
})()
'@
  Write-Host ("  search open: " + $sopen)
  Check ($sopen -like '*"names":"Photo,Scan,Search,Manual"*') "block (d) reads Photo, Scan, Search, Manual -- the ruled four, in the ruled order"
  Check (($sopen -like '*"paneOn":true*') -and ($sopen -like '*"field":true*')) "a real click on Search opens the search pane with its field"
  Check ($sopen -like '*"back":true*') "and the back link is there, so the pane is one tap from the root like every other"
  Check ($sopen -like '*"control":0*') "CONTROL: the matcher alone returns NOTHING for the half-typed 'coff' -- so the rows asserted next are the typeahead's and not the matcher's"
  TypeText 'coff'
  Settle
  $styped = EvalJ @'
(function () {
  var f = document.getElementById('fqQuery');
  var box = document.getElementById('fqRows');
  var first = box && box.firstElementChild;
  var st = HT.foodSearch();
  return { kept: !!f && f.__mark === 'kept', active: document.activeElement === f,
           value: f ? f.value : null, caret: f ? f.selectionStart : -1,
           rows: box ? box.querySelectorAll('.fqrow').length : -1,
           exitFirst: !!first && first.className.indexOf('fqexit') >= 0,
           cap: box ? (box.querySelector('.fqcap') || {}).textContent || '' : '',
           macros: box ? box.querySelectorAll('.fqmac').length : -1,
           allCoff: !!st && st.rows.length > 0 && st.rows.every(function (r) { return /coff/i.test(r.name); }) };
})()
'@
  Write-Host ("  search typed: " + $styped)
  $sv = $styped | ConvertFrom-Json
  Check ($sv.rows -gt 0) "typing FOUR LETTERS of a word finds rows -- search as you type, not search once the word is finished"
  Check ($sv.allCoff -eq $true) "and every row is one the half-typed word begins"
  Check (($sv.kept -eq $true) -and ($sv.active -eq $true)) "THE CARET RULE: after four real keystrokes the field is the SAME element and still holds the focus -- it was not rebuilt under the typing"
  Check (($sv.value -eq 'coff') -and ($sv.caret -eq 4)) "...every character landed, and the caret is at the end of them"
  Check ($sv.exitFirst -eq $true) "the way out comes BEFORE the list -- a list that always has a plausible first row needs its exit where someone who recognises nothing finds it first"
  Check (($sv.macros -eq $sv.rows) -and ($sv.cap -like '*per 100 g*')) "every row shows its macros, and the caption says what they are per"

  $srank = EvalJ @'
(function () {
  var whole = function (q) {
    var m = HT.matchTypeahead(q, 8);
    var re = new RegExp('(^|[^a-z])' + q + '([^a-z]|$)', 'i');
    return { first: m.length ? m[0].name : '', ok: m.length > 0 && re.test(m[0].name) };
  };
  return { milk: whole('milk'), egg: whole('egg'), coffee: whole('coffee') };
})()
'@
  Write-Host ("  search ranking: " + $srank)
  $sr = $srank | ConvertFrom-Json
  Check (($sr.milk.ok -eq $true) -and ($sr.egg.ok -eq $true) -and ($sr.coffee.ok -eq $true)) "a word typed IN FULL leads with a row that holds it as a whole word -- milk before milkfish, egg before eggplant, coffee before coffeecake. v0.84.0 led with the rarer longer word on all three, and nothing here asked"

  $spick = EvalJ @'
(function () {
  var st = HT.foodSearch();
  var i = -1;
  st.rows.forEach(function (r, k) { if (i < 0 && r.kcal > 0 && r.protein != null) i = k; });
  if (i < 0) return { err: 'no row with energy and protein to pick' };
  var want = st.rows[i];
  window.__od2 = { id: want.id, name: want.name, kcal100: want.kcal,
                   before: (HT.state().days[HT.state().current] || { items: [] }).items.length };
  document.querySelectorAll('#fqRows .fqrow')[i].click();
  var g = document.getElementById('fqGrams');
  var b = document.querySelector('#fqLog .fqlog');
  if (g) { g.__mark = 'kept'; g.focus(); }
  var box = document.getElementById('searchBox');
  return { step: !!g, disabled: !!b && b.disabled, text: b ? b.textContent : '',
           cited: (box.textContent || '').indexOf('Food database: ') >= 0,
           says: (box.textContent || '').indexOf('not a label') >= 0 };
})()
'@
  Write-Host ("  search pick: " + $spick)
  Check ($spick -like '*"step":true*') "a real click on a row opens the amount step"
  Check (($spick -like '*"disabled":true*') -and ($spick -like '*"text":"Enter an amount"*')) "with no amount the button is DISABLED and says what it is waiting for -- no portion is assumed"
  Check ($spick -like '*"cited":true*') "the source is NAMED beside the figures, before anything is logged (ruling a: cited)"
  Check ($spick -like '*"says":true*') "and the surface says whose numbers these are -- the database's, not a label's"
  TypeText '250'
  Settle
  $slog = EvalJ @'
(function () {
  var g = document.getElementById('fqGrams');
  var b = document.querySelector('#fqLog .fqlog');
  var pre = { kept: !!g && g.__mark === 'kept', active: document.activeElement === g,
              value: g ? g.value : null, enabled: !!b && !b.disabled, text: b ? b.textContent : '' };
  if (b) b.click();
  var day = HT.state().days[HT.state().current] || { items: [] };
  var it = day.items[day.items.length - 1] || {};
  var ref = it.ref || { v: {} };
  var w = window.__od2;
  var sheet = document.getElementById('entrySheet');
  return { pre: pre, added: day.items.length - w.before, name: it.name === w.name,
           kcal: Math.abs((it.kcal || 0) - w.kcal100 * 2.5) < 1e-6,
           ownIsRow: it.kcal === ref.v['208'] && it.protein_g === ref.v['203'] && it.fat_g === ref.v['204'],
           grams: it.grams, conf: it.confidence, source: it.source, micros: it.micros === undefined,
           refId: ref.id === w.id, ns: ref.ns, hash: !!ref.hash, attribution: !!ref.attribution, refG: ref.g,
           refSlots: Object.keys(ref.v).length, closed: getComputedStyle(sheet).display === 'none',
           search: HT.foodSearch() };
})()
'@
  Write-Host ("  search log: " + $slog)
  $sl = $slog | ConvertFrom-Json
  Check (($sl.pre.kept -eq $true) -and ($sl.pre.active -eq $true) -and ($sl.pre.value -eq '250')) "the amount field survives its own keystrokes too -- only the button under it is redrawn"
  Check (($sl.pre.enabled -eq $true) -and ($sl.pre.text -like 'Log * cal')) "and the button now states what it will log"
  Check (($sl.added -eq 1) -and ($sl.name -eq $true)) "one real click logs ONE item, named as the row"
  Check (($sl.kcal -eq $true) -and ($sl.grams -eq 250)) "RULING (a): its own calories are the row's, at the typed grams"
  Check ($sl.ownIsRow -eq $true) "...and its own macros are EXACTLY the cited values at those grams -- one arithmetic, so the item and its citation cannot disagree"
  Check (($sl.refId -eq $true) -and ($sl.hash -eq $true) -and ($sl.attribution -eq $true) -and ($sl.refG -eq 250) -and ($sl.ns -ne '')) "CITED: the item carries the row's namespace, id, hash, attribution and the grams its values are at"
  Check ($sl.conf -eq 'eyeballed') "confidence is eyeballed -- the portion was typed"
  Check ($sl.source -eq 'corpus') "R189: and its SOURCE is the food database -- v0.84.0 wrote 'manual' here, which said a person had typed numbers nobody typed"
  Check (($sl.micros -eq $true) -and ($sl.refSlots -gt 5)) "MICROS DO NOT MOVE: the item has no micros map of its own, and the row's other values are in the citation where they were always kept"
  Check (($sl.closed -eq $true) -and ($null -eq $sl.search)) "the sheet closes on the day, and the search is put down"

  # ---- 10. "+ New combo", with nothing logged first ----------------------------
  $cnone = EvalJ @'
(function () {
  var S = HT.state();
  var keep = JSON.parse(JSON.stringify(S.settings.combos || []));
  S.settings.combos = [];
  HT.closeSheet(); HT.openSheet();
  var h = document.getElementById('sheetRoot').innerHTML;
  var none = { heading: h.indexOf('My combos') >= 0, button: h.indexOf('srnew') >= 0 };
  S.settings.combos = keep;
  HT.closeSheet(); HT.openSheet();
  h = document.getElementById('sheetRoot').innerHTML;
  return { none: none, combos: h.indexOf('My combos'), btn: h.indexOf('srnew'), top: h.indexOf('Your top') };
})()
'@
  Write-Host ("  new combo, placement: " + $cnone)
  $cp = $cnone | ConvertFrom-Json
  Check (($cp.none.heading -eq $false) -and ($cp.none.button -eq $true)) "with NO combos saved the heading is still absent (D146) and '+ New combo' is still there -- the way to make the first one must not need one"
  Check (($cp.combos -ge 0) -and ($cp.combos -lt $cp.btn) -and ($cp.btn -lt $cp.top)) "and with combos it sits BENEATH them and above the top block, positionally, as ruled"

  $copen = EvalJ @'
(function () {
  window.__od2c = { before: (HT.state().days[HT.state().current] || { items: [] }).items.length,
                    combos: (HT.state().settings.combos || []).length };
  document.querySelector('#sheetRoot .srnew').click();
  var n = document.getElementById('cnName');
  if (n) n.focus();
  var b = document.querySelector('#cnTotal .cnsave');
  return { paneOn: document.getElementById('pane-combo').className.indexOf('on') >= 0, name: !!n,
           query: !!document.getElementById('cnQuery'), disabled: !!b && b.disabled,
           why: (document.querySelector('#cnTotal .cnwhy') || {}).textContent || '' };
})()
'@
  Write-Host ("  new combo, open: " + $copen)
  Check (($copen -like '*"paneOn":true*') -and ($copen -like '*"name":true*') -and ($copen -like '*"query":true*')) "a real click on '+ New combo' opens the builder: a name, and a search for parts"
  Check (($copen -like '*"disabled":true*') -and ($copen -like '*Add at least one part*')) "an empty builder cannot save, and says why"
  TypeText 'Gate coffee'
  [void](Eval "(function(){ var q = document.getElementById('cnQuery'); q.__mark = 'kept'; q.focus(); return 1; })()")
  TypeText 'coffee'
  Settle
  $cadd = EvalJ @'
(function () {
  var q = document.getElementById('cnQuery');
  var box = document.getElementById('cnRows');
  var first = box && box.firstElementChild;
  var st = HT.comboNew();
  var typed = { kept: q.__mark === 'kept', active: document.activeElement === q, value: q.value, caret: q.selectionStart,
                rows: box.querySelectorAll('.fqrow').length, name: document.getElementById('cnName').value,
                ownFirst: !!first && first.className.indexOf('fqexit') >= 0 };
  // A row that CARRIES caffeine, or the coverage line below would be asserting on
  // an accident of which coffee the corpus lists first.
  var i = -1;
  st.rows.forEach(function (r, k) {
    var c = r.row ? HT.corpusValueAt(r.row, r.meta.slots, 262) : null;
    if (i < 0 && c != null && c > 0 && r.kcal != null) i = k; });
  if (i < 0) return { typed: typed, err: 'no coffee row carrying caffeine among the rows' };
  box.querySelectorAll('.fqrow')[i].click();
  var b = document.querySelector('#cnTotal .cnsave');
  var amt = document.querySelector('#cnParts .cnamt');
  if (amt) { amt.__mark = 'kept'; amt.focus(); }
  return { typed: typed, parts: HT.comboNew().parts.length, cleared: q.value === '' && q.__mark === 'kept',
           rowsGone: box.querySelectorAll('.fqrow').length === 0, disabled: !!b && b.disabled,
           why: (document.querySelector('#cnTotal .cnwhy') || {}).textContent || '', amt: !!amt };
})()
'@
  Write-Host ("  new combo, a matched part: " + $cadd)
  $ca = $cadd | ConvertFrom-Json
  Check (($ca.typed.kept -eq $true) -and ($ca.typed.active -eq $true) -and ($ca.typed.value -eq 'coffee') -and ($ca.typed.caret -eq 6)) "the part search survives six real keystrokes -- same element, focus kept, caret at the end"
  Check (($ca.typed.rows -gt 0) -and ($ca.typed.name -eq 'Gate coffee')) "rows arrive as it is typed, and the name typed before it is still in its field"
  Check ($ca.typed.ownFirst -eq $true) "'Not here? Add it without database numbers' comes BEFORE the rows"
  Check (($ca.parts -eq 1) -and ($ca.cleared -eq $true) -and ($ca.rowsGone -eq $true)) "a real click on a row adds the part and clears the search for the next one, without rebuilding the field"
  Check (($ca.disabled -eq $true) -and ($ca.why -like '*1 part still needs an amount*')) "a matched part is OWED an amount -- none is invented for it, and the builder says so"
  TypeText '250'
  Settle
  $camt = EvalJ @'
(function () {
  var amt = document.querySelector('#cnParts .cnamt');
  var tot = (document.getElementById('cnTotal') || {}).textContent || '';
  var t = HT.comboNewTotal();
  var q = document.getElementById('cnQuery'); q.focus();
  return { kept: amt.__mark === 'kept', value: amt.value, one: tot.split('from 1 of 1 part').length - 1,
           caffeine: t.caffeine > 0, kcalFrom: t.kcalFrom, cafFrom: t.caffeineFrom,
           enabled: !document.querySelector('#cnTotal .cnsave').disabled };
})()
'@
  Write-Host ("  new combo, the amount: " + $camt)
  $cm = $camt | ConvertFrom-Json
  Check (($cm.kept -eq $true) -and ($cm.value -eq '250')) "the amount field survives its own keystrokes -- the total beneath is what redraws"
  Check (($cm.one -eq 2) -and ($cm.caffeine -eq $true) -and ($cm.enabled -eq $true)) "with one matched part the total shows calories AND caffeine, each 'from 1 of 1 part', and the combo can be saved"
  TypeText 'zzqqx cream'
  Settle
  $ctyp = EvalJ @'
(function () {
  var box = document.getElementById('cnRows');
  // R217: v0.96.0 put "Not in the database? Add it from its label" (.fqnewfood)
  // ahead of this offer with the same .fqexit class, so the bare selector took
  // the my-food button. The typed-part offer is still there; ask for IT.
  var own = box.querySelector('.fqexit:not(.fqnewfood)');
  var pre = { rows: box.querySelectorAll('.fqrow').length, offer: own ? own.textContent : '' };
  if (own) own.click();
  var tot = (document.getElementById('cnTotal') || {}).textContent || '';
  var t = HT.comboNewTotal();
  return { pre: pre, parts: t.parts, kcalFrom: t.kcalFrom, cafFrom: t.caffeineFrom,
           says: tot.split('from 1 of 2 parts').length - 1,
           calBox: document.querySelectorAll('#cnParts .cncal').length,
           before: (HT.state().days[HT.state().current] || { items: [] }).items.length - window.__od2c.before };
})()
'@
  Write-Host ("  new combo, a typed part: " + $ctyp)
  $cy = $ctyp | ConvertFrom-Json
  Check ($cy.pre.offer -like '*zzqqx cream*') "what was typed is offered as a part in its own words when the database has no better answer"
  Check (($cy.parts -eq 2) -and ($cy.kcalFrom -eq 1) -and ($cy.cafFrom -eq 1)) "the typed part brings NO calories and NO caffeine to the total"
  Check ($cy.says -eq 2) "and the total SAYS 'from 1 of 2 parts' for BOTH figures -- coverage grammar, not silence: without it one part's caffeine reads as the whole drink's"
  Check ($cy.calBox -eq 1) "only the typed part offers a calories box -- a matched part's numbers are the row's and cannot be typed over"
  # ---- 10b. R187: BACK DOES NOT DISCARD A HALF-BUILT COMBO ----------------------
  # v0.84.0 threw the name, both parts and the amount away on the back link,
  # without a word. Ruled: keep it, or ask. It is KEPT -- and the root says so.
  $cdraft = EvalJ @'
(function () {
  document.getElementById('sheetBack').click();
  var btn = document.querySelector('#sheetRoot .srnew');
  var out = { rootOn: document.getElementById('pane-root').className.indexOf('on') >= 0,
              label: btn ? btn.textContent : '' };
  HT.closeSheet(); HT.openSheet();
  document.querySelector('#sheetRoot .srnew').click();
  var amt = document.querySelector('#cnParts .cnamt');
  var tot = (document.getElementById('cnTotal') || {}).textContent || '';
  out.paneOn = document.getElementById('pane-combo').className.indexOf('on') >= 0;
  out.name = document.getElementById('cnName').value;
  out.parts = HT.comboNew().parts.length;
  out.shownParts = document.querySelectorAll('#cnParts .cnpart').length;
  out.amt = amt ? amt.value : '';
  out.says = tot.split('from 1 of 2 parts').length - 1;
  out.over = !!document.querySelector('#cnTotal .cnover');
  out.query = document.getElementById('cnQuery').value;
  return out;
})()
'@
  Write-Host ("  new combo, the draft: " + $cdraft)
  $cd = $cdraft | ConvertFrom-Json
  Check (($cd.rootOn -eq $true) -and ($cd.label -like '*Continue combo draft*2 parts*')) "a real click on the back link returns to the root, and the root SAYS a draft is kept and how big it is"
  Check (($cd.paneOn -eq $true) -and ($cd.name -eq 'Gate coffee') -and ($cd.parts -eq 2) -and ($cd.shownParts -eq 2)) "after CLOSING the sheet and coming back, the builder holds the name and both parts -- on the screen, not only in memory"
  Check (($cd.amt -eq '250') -and ($cd.says -eq 2)) "the amount typed for the matched part is still in its box, and the total still says 'from 1 of 2 parts' twice"
  Check (($cd.over -eq $true) -and ($cd.query -eq '')) "the way to throw it away is on the screen, and the half-typed search was not kept with it"

  $csave = EvalJ @'
(function () {
  var b = document.querySelector('#cnTotal .cnsave');
  var enabled = !!b && !b.disabled;
  if (b) b.click();
  var S = HT.state();
  var combos = S.settings.combos || [];
  var c = combos[combos.length - 1] || { parts: [{}, {}] };
  var p0 = c.parts[0] || {}, p1 = c.parts[1] || {};
  var root = document.getElementById('sheetRoot');
  var row = null;
  Array.prototype.forEach.call(root.querySelectorAll('.srcombo'), function (r) {
    if ((r.textContent || '').indexOf('Gate coffee') >= 0) row = r; });
  var out = { enabled: enabled, added: combos.length - window.__od2c.combos, name: c.name,
              logged: (S.days[S.current] || { items: [] }).items.length - window.__od2c.before,
              rootOn: document.getElementById('pane-root').className.indexOf('on') >= 0, onRoot: !!row,
              p0ref: !!p0.ref, p0caf: p0.ref ? HT.refValueAt(p0.ref, 262) > 0 : false, p0g: p0.grams,
              p0own: !!p0.ref && p0.kcal === p0.ref.v['208'], p0conf: p0.confidence,
              p1ref: p1.ref === undefined, p1name: p1.name, draft: HT.comboNew(),
              newLabel: (root.querySelector('.srnew') || {}).textContent || '' };
  if (row) row.click();
  var plan = HT.quickPlan();
  out.stepParts = plan && plan.combo ? plan.combo.rows.length : -1;
  HT.setSheetMode('root');
  return out;
})()
'@
  Write-Host ("  new combo, saved: " + $csave)
  $cs = $csave | ConvertFrom-Json
  Check (($cs.enabled -eq $true) -and ($cs.added -eq 1) -and ($cs.name -eq 'Gate coffee')) "a real click on Save stores ONE combo under the typed name"
  Check ($cs.logged -eq 0) "WITH NO ITEMS LOGGED FIRST -- the ruling's own point: the day has exactly the items it had before the builder opened"
  Check (($cs.p0ref -eq $true) -and ($cs.p0caf -eq $true) -and ($cs.p0g -eq 250)) "the part that matched carries its ref, and with it the caffeine, at its amount"
  Check (($cs.p0own -eq $true) -and ($cs.p0conf -eq 'eyeballed')) "...and its own calories are the cited row's at that amount (ruling a, through the same one function as Search)"
  Check (($cs.p1ref -eq $true) -and ($cs.p1name -eq 'zzqqx cream')) "the part that did not match carries NO ref, so no caffeine -- it degrades exactly as pre-registered"
  Check (($cs.rootOn -eq $true) -and ($cs.onRoot -eq $true) -and ($null -eq $cs.draft)) "saving returns to the root with the new combo ON it, and the draft is gone"
  Check ($cs.stepParts -eq 2) "and a real click on that new row reaches the stepper with both parts -- the combo made a moment ago is loggable"
  Check ($cs.newLabel -eq '+ New combo') "and with the draft saved the root offers '+ New combo' again, not a draft that no longer exists"
  [void](Eval "(function(){ document.querySelector('#sheetRoot .srnew').click(); document.getElementById('cnName').focus(); return 1; })()")
  TypeText 'Throwaway'
  Settle
  $cover = EvalJ @'
(function () {
  var b = document.querySelector('#cnTotal .cnover');
  var had = !!b && !!HT.comboNewDraft();
  if (b) b.click();
  var out = { had: had, name: document.getElementById('cnName').value, draft: HT.comboNewDraft(),
              gone: !document.querySelector('#cnTotal .cnover') };
  HT.setSheetMode('root');
  out.label = (document.querySelector('#sheetRoot .srnew') || {}).textContent || '';
  return out;
})()
'@
  Write-Host ("  new combo, start over: " + $cover)
  Check ($cover -like '*"had":true*') "a name alone is a draft, and Start over is offered for it"
  Check (($cover -like '*"name":""*') -and ($cover -like '*"draft":null*') -and ($cover -like '*"gone":true*')) "a real click on Start over empties the builder -- the one way a draft is discarded, and it is the user's own act"
  Check ($cover -like '*"label":"+ New combo"*') "and the root no longer offers a draft"

  # ---- 11. no dead control on either new pane ----------------------------------
  # Section 7's scan, widened: these panes wire `oninput` as well as `onclick`,
  # and a field whose handler does not exist is a field that silently eats typing.
  $dead2 = EvalA @'
(function () {
  var scan = function (host) {
    var bad = [], n = 0;
    ['onclick', 'oninput'].forEach(function (attr) {
      Array.prototype.forEach.call(host.querySelectorAll('[' + attr + ']'), function (b) {
        n++;
        var a = b.getAttribute(attr) || '';
        var fn = (a.match(/^([A-Za-z0-9_$.]+)\s*\(/) || [])[1];
        if (!fn) { bad.push('unparsed: ' + a); return; }
        var ref = fn.split('.').reduce(function (o, k) { return (o == null) ? o : o[k]; }, window);
        if (typeof ref !== 'function') bad.push(fn);
      }); });
    return { n: n, bad: bad };
  };
  HT.closeSheet(); HT.openSheet(); HT.setSheetMode('search');
  return HT.searchType('coffee').then(function () {
    var a = scan(document.getElementById('searchBox'));
    HT.searchPickAt(0);
    var b = scan(document.getElementById('searchBox'));
    HT.setSheetMode('combo');
    return HT.comboNewType('coffee').then(function () {
      HT.comboNewAddAt(0);
      HT.comboNew().q = 'something typed'; HT.comboNewAddTyped();
      var c = scan(document.getElementById('comboNewBox'));
      // Drafts are KEPT now, so a gate that builds one must put it down or the
      // next section opens on it.
      HT.comboNewDiscard();
      return { controls: a.n + b.n + c.n, dead: a.bad.concat(b.bad).concat(c.bad) };
    });
  });
})()
'@
  Write-Host ("  controls, new panes: " + $dead2)
  Check ($dead2.Contains('"dead":[]')) "every control on the search pane, its amount step and the builder resolves to a function that EXISTS"
  Check (-not ($dead2 -like '*"controls":0*')) "and there are controls to resolve"

  # ---- 12. the type floor on the new panes, at both widths ---------------------
  foreach ($w2 in @(390, 360)) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w2; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    WaitQuiet 'after a step'
    $sz2 = EvalA @'
(function () {
  var measure = function (host, acc) {
    Array.prototype.forEach.call(host.querySelectorAll('button, input, label, div, span'), function (b) {
      if (!b.offsetParent) return;
      var own = Array.prototype.some.call(b.childNodes, function (c) { return c.nodeType === 3 && /\S/.test(c.nodeValue); });
      var ctl = b.tagName === 'BUTTON' || b.tagName === 'INPUT';
      if (!own && !ctl) return;
      acc.n++;
      var fs = parseFloat(getComputedStyle(b).fontSize);
      if (fs < 16) acc.small.push((b.className || b.tagName) + ' ' + fs);
      var link = (b.className || '').indexOf('linklike') >= 0;
      if (ctl && !link && b.offsetHeight < 44) acc.short.push((b.className || b.tagName) + ' ' + b.offsetHeight);
    });
    var sheet = document.getElementById('entrySheet');
    acc.overflow = Math.max(acc.overflow, sheet.scrollWidth - sheet.clientWidth, host.scrollWidth - host.clientWidth);
  };
  var acc = { n: 0, small: [], short: [], overflow: 0 };
  HT.closeSheet(); HT.openSheet(); HT.setSheetMode('search');
  return HT.searchType('cheese cheddar').then(function () {
    measure(document.getElementById('searchBox'), acc);
    HT.searchPickAt(0);
    measure(document.getElementById('searchBox'), acc);
    HT.setSheetMode('combo');
    return HT.comboNewType('cheese cheddar').then(function () {
      measure(document.getElementById('comboNewBox'), acc);
      HT.comboNewAddAt(0);
      HT.comboNew().q = 'a typed part with a long name to wrap'; HT.comboNewAddTyped();
      measure(document.getElementById('comboNewBox'), acc);
      HT.comboNewDiscard();
      HT.setSheetMode('root');
      return acc;
    });
  });
})()
'@
    Write-Host ("  sizes, new panes@" + $w2 + ": " + $sz2)
    Check ($sz2.Contains('"small":[]')) ("every piece of text on the search pane and the builder is >= 16px at " + $w2)
    Check ($sz2.Contains('"short":[]')) ("every button and field on them is >= 44px tall at " + $w2)
    Check ($sz2 -like '*"overflow":0*') ("and neither scrolls sideways at " + $w2)
    Check (-not ($sz2 -like '*"n":0,*')) ("...over a non-empty set of elements at " + $w2)
  }
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null

  # ---- 8. the type floor and the sideways scroll ------------------------------
  # The foot links are `.linklike`, which the app uses at 16px with no height
  # floor everywhere else; the floor asserted here is the project's font floor,
  # plus 44px on the things that are buttons rather than links.
  foreach ($w in @(390, 360)) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    WaitQuiet 'after a step'
    $sz = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSheet();
  var el = document.getElementById('sheetRoot');
  var small = [], short = [];
  Array.prototype.forEach.call(el.querySelectorAll('button'), function (b) {
    var cs = getComputedStyle(b);
    var fs = parseFloat(cs.fontSize);
    if (fs < 16) small.push((b.className || '?') + ' ' + fs);
    var link = (b.className || '').indexOf('linklike') >= 0;
    if (!link && b.offsetHeight < 44) short.push((b.className || '?') + ' ' + b.offsetHeight);
  });
  var sheet = document.getElementById('entrySheet');
  return { n: el.querySelectorAll('button').length, small: small, short: short,
           overflowSheet: sheet.scrollWidth - sheet.clientWidth,
           overflowRoot: el.scrollWidth - el.clientWidth };
})()
'@
    Write-Host ("  sizes@" + $w + ": " + $sz)
    Check ($sz.Contains('"small":[]')) ("every control on the root is >= 16px at " + $w)
    Check ($sz.Contains('"short":[]')) ("every button on the root is >= 44px tall at " + $w)
    Check (($sz -like '*"overflowSheet":0*') -and ($sz -like '*"overflowRoot":0*')) ("and the sheet does not scroll sideways at " + $w)
  }

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("ONE-DOOR GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "ONE-DOOR GATE: PASS -- one entrance, five blocks in the ruled order, search as you type with the caret kept, a searched food cited as its own numbers, a combo built with nothing logged first, an"
Write-Host "  honest count, a never-logged combo reachable by tap, a spine out of every"
Write-Host "  mode, no dead control, and nothing drawn for a block with nothing in it."
Write-Host "GATE: PASS"
exit 0
