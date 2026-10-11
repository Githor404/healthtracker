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
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
# Multi-line JS goes over base64 so no quoting survives to be mangled; the result
# is stringified INSIDE the page (CDP: await the promise -- a JSON.stringify of an
# async eval returns "{}").
function EvalJ([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "JSON.stringify((function(){ return eval(decodeURIComponent(escape(atob('" + $enc + "')))); })())"; returnByValue = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

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
function Check([bool]$ok, [string]$name) {
  if ($ok) { Write-Host ("  PASS  " + $name) } else { Write-Host ("  FAIL  " + $name); $script:fails += $name } }

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
  var rootHid = { modes: modes.hidden, back: back.hidden };
  HT.setSheetMode('manual');
  var inMode = { modes: modes.hidden, back: back.hidden };
  back.click();
  var after = document.getElementById('pane-root').className.indexOf('on') >= 0;
  return { rootHid: rootHid, inMode: inMode, backReturns: after };
})()
'@
  Write-Host ("  spine: " + $spine)
  Check (($spine -like '*"rootHid":{"modes":true,"back":true}*')) "on the root the mode strip is hidden -- the strip IS the root-s own content, so showing both is showing the list twice"
  Check (($spine -like '*"inMode":{"modes":false,"back":false}*')) "and inside a mode both the strip and the back link are there: one door needs a spine, or the sheet is a maze with one entrance"
  Check ($spine -like '*"backReturns":true*') "the back link returns to the root, by a real click"

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

  # ---- 8. the type floor and the sideways scroll ------------------------------
  # The foot links are `.linklike`, which the app uses at 16px with no height
  # floor everywhere else; the floor asserted here is the project's font floor,
  # plus 44px on the things that are buttons rather than links.
  foreach ($w in @(390, 360)) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    Start-Sleep -Milliseconds 250
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
Write-Host "ONE-DOOR GATE: PASS -- one entrance, five blocks in the ruled order, an"
Write-Host "  honest count, a never-logged combo reachable by tap, a spine out of every"
Write-Host "  mode, no dead control, and nothing drawn for a block with nothing in it."
Write-Host "GATE: PASS"
exit 0
