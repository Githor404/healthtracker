# R298 STRIP GATE -- THE CONTEXT STRIP (R297's principle: surface what relates to the last action,
# without the screen rearranging itself). In a real browser at 390 px (and 360), by the app's own
# actions and real taps.
#
#   Pre-registered in DECISIONS (R298 step 2) before the build. Each kind -- food logged, a stack
#   tick, a food opened, and the quiet state -- is drawn and photographed in light and dark; the
#   strip is the same height in every state and the day card never moves; it lives 3 h or until
#   the next food / stack / opened food, and the x ends it; its contents are worked out once and
#   again only when glucose arrives (or the note, its day or the pack change); the links open the
#   right place (the Pathways card at exactly the named pathways); it says "supplies", never
#   "activates"; its note survives a reload and is not in the backup; and on a year of days with a
#   year of CGM a redraw with a strip showing stays inside the perf budget. Placeholder pack and
#   synthetic days only.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8409
$Dbg = 9609
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-strip-" + [System.Guid]::NewGuid().ToString('N'))
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

# The strip's screenshots, each kind at 390 px in light and dark, always kept here (STRIP_SHOTS
# names another folder).
$shots = Join-Path $env:TEMP 'strip-shots'
if ($env:STRIP_SHOTS) { $shots = $env:STRIP_SHOTS }
New-Item -ItemType Directory -Force $shots | Out-Null
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


  $boot = Eval "typeof HT === 'object' && typeof HT.ctxStripCompute === 'function' && typeof HT.packImportText === 'function' && typeof HT.logRepeat === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R298 strip functions are not on HT"; Cleanup; exit 2 }
  function TapSel([string]$sel) {
    $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); return { ok: q.width > 0 && q.height > 0, x: q.left + q.width / 2, y: q.top + q.height / 2, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
    if (-not $r9.ok) { return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  function Theme([string]$t) { Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = $t }) } | Out-Null; WaitQuiet ('theme ' + $t) }
  function Shots([string]$name) {
    [void](Eval "window.scrollTo(0, 0)")
    Theme 'light'; Shot ($name + '-light'); Theme 'dark'; Shot ($name + '-dark'); Theme 'light' }
  function SetClock([string]$hhmm, [int]$dayOff) {
    [void](EvalJ ("(function(){ var d = new Date(HT.todayKey() + 'T00:00:00'); d.setDate(d.getDate() + " + $dayOff + "); var p = '" + $hhmm + "'.split(':'); d.setHours(+p[0], +p[1], 0, 0); var at = d.getTime(); HT.setClock(function () { return at; }); return 1; })()")) }

  # ---- the placeholder pack (pack-gate's wrapper; generic content; real Reactome IDs, CC0) ----
  $body = @'
{"format":"healthtracker-pack","schema":1,"built_at":"2026-10-29T12:00:00","private":true,"reactome_version":98,
 "groups":[{"id":"energy","name":"Group A"},{"id":"gut","name":"Group B"},{"id":"other","name":"Group C"}],
 "records":[
  {"id":"pw-001","plain_name":"Path A1","technical_name":"Citric acid cycle (TCA cycle)","group":"energy","backbone":[{"source":"Reactome","version":98,"id":"R-HSA-71403"}],"supply":[{"cofactor":"magnesium","dri":"magnesium","key":"magnesium_mg","slot":"304","tracked":true}],"observable":"not observable","observable_how":"","reviewed_by_me":"2026-10-29","sentence":"A placeholder sentence.","claims":[]},
  {"id":"pw-002","plain_name":"Path A2","technical_name":"Protein placeholder","group":"energy","backbone":[{"source":null,"note":"literature-sourced"}],"supply":[{"cofactor":"leucine and other amino acids","dri":"protein","key":"protein_g","slot":"203","tracked":true}],"observable":"proxy","observable_how":"placeholder","reviewed_by_me":"2026-10-29","sentence":"A placeholder sentence.","claims":[]},
  {"id":"pw-003","plain_name":"Path B1","technical_name":null,"group":"gut","backbone":[{"source":null,"note":"literature-sourced"}],"supply":[{"cofactor":"fermentable fibre","dri":"fibre","key":"fiber_g","slot":"291","tracked":true}],"observable":"proxy","observable_how":"placeholder","reviewed_by_me":"2026-10-29","sentence":"A placeholder sentence.","claims":[]},
  {"id":"pw-004","plain_name":"Path C1","technical_name":null,"group":"other","backbone":[{"source":null,"note":"literature-sourced"}],"supply":[{"cofactor":"choline","dri":"choline","tracked":false}],"observable":"not observable","observable_how":"","reviewed_by_me":"2026-10-29","sentence":"A placeholder sentence.","claims":[]}],
 "claims":[],"interactions":[],
 "reference_intakes":{"source":"Health Canada, Dietary Reference Intakes tables","group":"males 51-70","values":{"magnesium":{"label":"Magnesium","value":420,"unit":"mg","kind":"RDA"}}},
 "lexicon":{"rules":[{"id":"lx-001","pattern":"\\bkimchi\\b","fermented":"yes","fermented_why":"placeholder reason","marco":{"code":"0","desc":"Kimchi","tier":"Hi"},"reviewed_by_me":"2026-10-29"}]},
 "sources":[]}
'@
  $body = ($body -replace "`r`n", "`n")
  $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($body))).Replace('-', '').ToLower()
  $wrap = (@{ format = 'healthtracker-pack'; version = 1; sha256 = $sha; body = $body } | ConvertTo-Json -Compress)
  [void](Eval ("window.__wrap = " + (ConvertTo-Json $wrap) + "; 1"))

  # ---- the fixture: ten past days with lunch, glucose, a two-item stack, today's lunch ----
  SetClock '12:52' 0
  $fx = EvalA @'
(function () {
  localStorage.clear(); HT.boot();
  var td = HT.state().current, S = HT.state();
  var p = function (n) { return String(n).padStart(2, '0'); };
  var iso = function (ms) { var d = new Date(ms), o = -d.getTimezoneOffset();
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':00'
      + (o < 0 ? '-' : '+') + p(Math.floor(Math.abs(o) / 60)) + ':' + p(Math.abs(o) % 60); };
  var rows = [];
  var curve = function (dk, hhmm, rise, from, to) {
    var t0 = HT.dayKeyMs(dk) + HT.hhmmToMin(hhmm) * 60000;
    for (var m = from; m <= to; m += 5) { var v = 5.0;
      if (m > 0 && m <= 30) v = 5.0 + rise * m / 30; else if (m > 30 && m < 90) v = 5.0 + rise * (90 - m) / 60;
      rows.push({ t: iso(t0 + m * 60000), v: Math.round(v * 1000) / 1000, unit: 'mmol/L' }); } };
  var item = function (name, time, mid, carbs, kcal, extra) {
    var o = { name: name, meal: 'lunch', time: time, kcal: kcal, protein_g: 20, fat_g: 8, carb_g: carbs, fiber_g: 3, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' };
    if (mid) o.mealId = mid; if (extra) for (var k in extra) o[k] = extra[k]; return o; };
  for (var b = 1; b <= 10; b++) {
    var dk = HT.shiftDate(td, -b);
    S.days[dk] = { status: 'complete', water_l: 0, items: [ item('Strip salmon', '12:30', 'l' + b, 0, 280), item('Strip rice', '12:31', 'l' + b, 48, 220), item('Kimchi', '12:32', 'l' + b, 4, 20) ] };
    curve(dk, '12:30', 1.8, -60, 180);
  }
  S.days[td] = { status: 'in_progress', water_l: 0, items: [ item('Strip salmon', '12:30', 'lt', 0, 280), item('Strip rice', '12:31', 'lt', 50, 220, { grams: 150 }) ] };
  curve(td, '12:30', 2.0, -60, 20);
  var y = HT.shiftDate(td, -3);
  S.settings.stack = HT.normalizeStack([
    { id: 'sa', added_on: y, added_basis: 'created', name: 'Item A', kind: 'supplement', dose: 1, dose_unit: 'capsule', nutrients: { micros: { magnesium_mg: 200 } } },
    { id: 'sb', added_on: y, added_basis: 'created', name: 'Item B', kind: 'supplement', dose: 1, dose_unit: 'capsule', nutrients: { micros: { vitamin_d_ug: 125 } } } ]);
  HT.resave();
  return Promise.resolve(HT.glucoseIngest(rows, { source: 'fixture' })).then(function () {
    return HT.packImportText(window.__wrap);
  }).then(function (pk) {
    HT.refresh();
    return { ok: true, pack: pk && pk.ok, td: td, stack: (S.settings.stack || []).length };
  });
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"ok":true*"pack":true*')) { Write-Host "ERROR: fixture"; Cleanup; exit 2 }
  WaitQuiet 'fixture'

  $ST = @'
(function () {
  var e = document.getElementById('ctxStrip'), r = e.getBoundingClientRect(), nx = e.nextElementSibling.getBoundingClientRect();
  var links = Array.prototype.slice.call(e.querySelectorAll('button, summary')).map(function (b) {
    var q = b.getBoundingClientRect(), line = b.closest('.ctxl'), l = line ? line.getBoundingClientRect() : r;
    return { t: b.textContent.trim().slice(0, 24), h: Math.round(q.height), w: Math.round(q.width), inside: q.left >= r.left - 0.5 && q.right <= r.right + 0.5 && q.right <= l.right + 0.5 }; });
  return { kind: e.getAttribute('data-kind'), h: Math.round(r.height * 10) / 10, next: Math.round((nx.top - r.top) * 10) / 10, top: Math.round(r.top + scrollY),
           head: (e.querySelector('.ctxhead') || {}).textContent || '',
           lines: Array.prototype.slice.call(e.querySelectorAll('.ctxl')).map(function (l) { return l.textContent; }),
           links: links, text: e.textContent, computes: HT.ctxComputes(), note: localStorage.getItem(HT.CTX_KEY) };
})()
'@
  function Strip { return ((EvalJ $ST) | ConvertFrom-Json) }
  $words = @()
  $td = Eval "HT.state().current"

  # ---- 1. QUIET: nothing has happened ----
  $q0 = Strip; $words += $q0.text
  Write-Host ("  quiet: " + $q0.head + " | " + ($q0.lines -join ' | '))
  Check (($q0.kind -eq 'quiet') -and ($q0.lines[0] -like '*since last logged food*') -and ($q0.lines[1] -like 'Glucose *mmol/L*ago*')) "R298 STRIP 1: with no recent action the strip shows the fast status and the current glucose (value, unit, age), not an empty box"
  Shots 'strip-quiet'

  # ---- 2. FOOD LOGGED: Kimchi again, one tap, joins today's lunch sitting ----
  $kim = Eval "HT.state().days[HT.shiftDate(HT.state().current, -1)].items.map(function (i) { return i.name; }).indexOf('Kimchi')"
  [void](Eval ("HT.logRepeat(HT.shiftDate(HT.state().current, -1), " + $kim + ").ok"))
  WaitQuiet 'food logged'
  $f1 = Strip; $words += $f1.text
  $pw = (Eval "JSON.stringify(HT.ctxKept().pw)") | ConvertFrom-Json
  Write-Host ("  food: " + $f1.head + " | " + ($f1.lines -join ' | ') + "  pathways " + ($pw -join ','))
  Check (($f1.kind -eq 'food') -and ($f1.head -like 'Just logged*Lunch, 3 items*12:30*') -and ($f1.lines[1] -like '*a fast from 00:52*')) "R298 STRIP 2: after logging food the strip names the sitting (Lunch, 3 items, 12:30) and the fast status (a fast from 00:52 if nothing more)"
  Check (($f1.lines[2] -like ('supplies ' + $pw.Count + ' pathways*Kimchi fermented')) -and ($pw.Count -eq 2) -and ($pw -contains 'pw-002') -and ($pw -contains 'pw-003')) "R298 STRIP 2: Kimchi is fermented (the reviewed rule) and the sitting SUPPLIES the 2 pathways whose raw-material lines its nutrients count toward (protein, fibre) -- not the magnesium one, not the untracked one"
  Check (($f1.h -eq $q0.h) -and ($f1.next -eq $q0.next)) ("R298 STRIP NO SHIFT: the food strip is the quiet strip's height and the day card starts at the same place (" + $f1.h + "/" + $q0.h + " px, " + $f1.next + "/" + $q0.next + ")")
  Shots 'strip-food'

  # ---- 3. COMPUTED ONCE ----
  $c0 = [int]$f1.computes
  [void](Eval "(function(){ for (var i = 0; i < 20; i++) HT.refresh(); return 1; })()")
  $c1 = [int](Eval "HT.ctxComputes()")
  Check ($c1 -eq $c0) ("R298 STRIP COMPUTED ONCE: 20 redraws after the action re-insert the kept strip and work nothing out again (" + $c0 + " -> " + $c1 + ")")
  # glucose arrives: the clock moves on inside the 3 h and the readings come in
  SetClock '14:40' 0
  [void](Eval "HT.refresh(); 1")
  $c2 = [int](Eval "HT.ctxComputes()")
  $l0before = (Strip).lines[0]
  $gi = EvalA @'
(function () {
  var td = HT.state().current, rows = [];
  var p = function (n) { return String(n).padStart(2, '0'); };
  var t0 = HT.dayKeyMs(td) + HT.hhmmToMin('12:30') * 60000;
  for (var m = 25; m <= 125; m += 5) { var v = 5.0; if (m > 0 && m <= 30) v = 7.0; else if (m > 30 && m < 90) v = 5.0 + 2 * (90 - m) / 60;
    var d = new Date(t0 + m * 60000), o = -d.getTimezoneOffset();
    rows.push({ t: d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':00' + (o < 0 ? '-' : '+') + p(Math.floor(Math.abs(o) / 60)) + ':' + p(Math.abs(o) % 60), v: Math.round(v * 1000) / 1000, unit: 'mmol/L' }); }
  return Promise.resolve(HT.glucoseIngest(rows, { source: 'fixture' })).then(function () { HT.refresh(); return { ok: true }; });
})()
'@
  $g2 = Strip
  Write-Host ("  glucose arrived: '" + $l0before + "' -> '" + $g2.lines[0] + "' (computes " + $c1 + " -> " + $c2 + " -> " + $g2.computes + ")")
  Check (($c2 -eq $c1) -and ([int]$g2.computes -eq $c2 + 1) -and ($g2.lines[0] -ne $l0before) -and ($g2.lines[0] -like 'Glucose rose*back in*') -and ($g2.kind -eq 'food')) "R298 STRIP COMPUTED ONCE: the clock moving on inside the 3 h works nothing out again; glucose arriving works it out once more, and the sitting's line becomes the measured rise and the time back"
  $words += $g2.text

  # ---- 4. "supplies N pathways >" opens the Pathways card at exactly those pathways ----
  $t4 = TapSel '#ctxStrip .ctxl .ctxlink'
  $pv = (EvalJ @'
(function () {
  var card = document.querySelector('[data-card="pathways"] > details');
  var groups = Array.prototype.slice.call(document.querySelectorAll('#pathways details.pwgroup'));
  var marked = Array.prototype.slice.call(document.querySelectorAll('#pathways .pwrec.pwmark')).map(function (r) { return r.getAttribute('data-pw'); });
  var first = document.querySelector('#pathways .pwrec.pwmark'), q = first ? first.getBoundingClientRect() : null;
  return { cardOpen: !!(card && card.open), open: groups.filter(function (g) { return g.open; }).map(function (g) { return g.getAttribute('data-group'); }),
           marked: marked, inView: !!(q && q.top >= 0 && q.bottom <= innerHeight) };
})()
'@) | ConvertFrom-Json
  Write-Host ("  pathways: tap " + $t4.w + "x" + $t4.h + " card " + $pv.cardOpen + " open " + ($pv.open -join ',') + " marked " + ($pv.marked -join ','))
  Check ($t4.ok -and ($t4.h -ge 44) -and $pv.cardOpen -and (($pv.open -join ',') -eq 'energy,gut') -and (($pv.marked | Sort-Object) -join ',') -eq 'pw-002,pw-003' -and $pv.inView) "R298 STRIP LINK: 'supplies 2 pathways' (a 44 px target) opens the Pathways card with exactly the named pathways' groups open, those 2 marked, the first on screen; the other group stays closed"

  # ---- 5. a water tap does not replace the food strip ----
  [void](Eval "HT.waterTap(0.25).ok"); [void](Eval "HT.refresh(); 1")
  $w5 = Strip
  Check ($w5.kind -eq 'food') "R298 STRIP LIFETIME: a water tap does not replace a food strip -- it says nothing about that food"

  # ---- 6. STACK TICK replaces it ----
  [void](Eval "HT.stackCheck('sa').ok"); WaitQuiet 'stack tick'
  $s6 = Strip; $words += $s6.text
  Write-Host ("  stack: " + $s6.head + " | " + ($s6.lines -join ' | '))
  Check (($s6.kind -eq 'stack') -and ($s6.head -like 'Just ticked*Item A*14:40*1 of 2') -and ($s6.lines[0] -eq 'Magnesium today 200 mg (stack 200)') -and ($s6.lines[2] -like '*all totals*')) "R298 STRIP 3: a stack tick replaces the food strip: the item, its time, 1 of 2 taken, and today's magnesium total with the stack's share"
  Check (($s6.h -eq $q0.h) -and ($s6.next -eq $q0.next)) "R298 STRIP NO SHIFT: the stack strip is the same height, the day card where it was"
  Shots 'strip-stack'
  $t6 = TapSel '#ctxStrip .ctxl .ctxlink'
  $panel = Eval "(function(){ var d = document.querySelector('details.mpanel'); return !!(d && d.open); })()"
  Check ($t6.ok -and ($t6.h -ge 44) -and ($panel -eq $true)) "R298 STRIP LINK: 'all totals' opens the Micronutrients panel"
  # Took all: Item B's vitamin D is over the cited upper level -> the intake note, collapsed
  [void](Eval "HT.stackTookAll().ok"); WaitQuiet 'took all'
  $s7 = Strip; $words += $s7.text
  Write-Host ("  took all: " + $s7.head + " | " + ($s7.lines -join ' | '))
  $flagOpen = Eval "(function(){ var d = document.querySelector('#ctxStrip details.iflag'); return d ? (d.open ? 'open' : 'closed') : 'none'; })()"
  Check (($s7.kind -eq 'stack') -and ($s7.head -like 'Took all*2 of 2') -and ($s7.lines[0] -like 'Vitamin D today 125 mcg (stack 125)') -and ($s7.text -like '*Intake note*') -and ($flagOpen -eq 'closed')) "R298 STRIP 3: Took all names its items' totals, and the day's upper-limit flag is the R213 intake note, collapsed"
  Check (($s7.h -eq $q0.h) -and ($s7.next -eq $q0.next)) "R298 STRIP NO SHIFT: with the intake note (closed) the strip is still the same height"
  $nt = TapSel '#ctxStrip details.iflag > summary'
  $grown = (Strip).h
  Check ($nt.ok -and ($nt.h -ge 44) -and ($grown -gt $q0.h)) "R298 STRIP: the user opening the intake note (a 44 px target) is the one thing that lets the strip grow"
  [void](Eval "HT.refresh(); 1")

  # ---- 7. FOOD OPENED ----
  $ri = Eval "HT.state().days[HT.state().current].items.map(function (i) { return i.name; }).indexOf('Strip rice')"
  [void](Eval ("HT.itemToggle(HT.state().current, " + $ri + ").open"))
  WaitQuiet 'item opened'
  $o8 = Strip; $words += $o8.text
  Write-Host ("  opened: " + $o8.head + " | " + ($o8.lines -join ' | '))
  Check (($o8.kind -eq 'open') -and ($o8.head -like 'Opened*Strip rice*150 g') -and ($o8.lines[0] -like 'Not linked*Link a row?*') -and ($o8.lines[1] -like 'Fermented: unknown*') -and ($o8.lines[2] -like 'supplies 2 pathways*')) "R298 STRIP 4: an opened food shows its database row (not linked, Link a row?), Fermented, and the pathways it supplies"
  Check (($o8.h -eq $q0.h) -and ($o8.next -eq $q0.next)) "R298 STRIP NO SHIFT: the opened-food strip is the same height"
  Shots 'strip-open'
  $t8 = TapSel '#ctxStrip .ctxl .ctxlink'
  Write-Host ("  after Link a row?: mlink " + (Eval "document.querySelectorAll('.mlink').length") + ", mbody " + (Eval "document.querySelectorAll('.mbody').length") + ", kept " + (Eval "JSON.stringify((HT.ctxKept() || {}).n)"))
  $lk = Eval ("(function(){ var e = document.getElementById(HT.linkBoxId ? HT.linkBoxId(HT.state().current, " + $ri + ") : ''); if (!e) e = document.querySelector('.mlink'); if (!e) return 'none'; var q = e.getBoundingClientRect(); return (q.top >= 0 && q.bottom <= innerHeight + 200) ? 'shown' : 'off'; })()")
  Check ($t8.ok -and ($t8.h -ge 44) -and ($lk -eq 'shown')) ("R298 STRIP LINK: 'Link a row?' brings the opened item's own link offer on screen (" + $lk + ")")

  # ---- 8. the x ends it; every link stayed inside the strip ----
  $allLinks = @($f1.links) + @($s6.links) + @($s7.links) + @($o8.links)
  $badLinks = @($allLinks | Where-Object { (-not $_.inside) -or ($_.h -lt 44) } | ForEach-Object { $_.t + ' ' + $_.w + 'x' + $_.h + ' inside=' + $_.inside })
  if ($badLinks.Count) { Write-Host ("  controls not passing: " + ($badLinks -join ' ; ')) }
  Check ((@($allLinks | Where-Object { -not $_.inside }).Count -eq 0) -and (@($allLinks | Where-Object { $_.h -lt 44 }).Count -eq 0)) ("R298 STRIP: every control in every state is a 44 px target and sits wholly inside its line and the strip (" + $allLinks.Count + " controls)")
  $x9 = TapSel '#ctxStrip .ctxx'
  $d9 = Strip
  Check ($x9.ok -and ($d9.kind -eq 'quiet') -and ($d9.note -like '*"kind":"none"*') -and ($d9.h -eq $q0.h)) "R298 STRIP LIFETIME: the x ends the strip at once; the quiet state shows, same height"

  # ---- 9. 3 h, whichever first ----
  SetClock '15:00' 0
  [void](Eval ("HT.logRepeat(HT.shiftDate(HT.state().current, -1), " + $kim + ").ok")); WaitQuiet 'food again'
  SetClock '17:59' 0; [void](Eval "HT.refresh(); 1"); $e1 = Strip
  SetClock '18:01' 0; [void](Eval "HT.refresh(); 1"); $e2 = Strip; $words += $e2.text
  Write-Host ("  at 2 h 59: " + $e1.kind + "; at 3 h 1: " + $e2.kind + " -- " + $e2.head)
  Check (($e1.kind -eq 'food') -and ($e2.kind -eq 'quiet') -and ($e2.head -like 'Nothing new in 3 h*') -and ($e2.h -eq $q0.h)) "R298 STRIP LIFETIME: a food strip still shows at 2 h 59 and has become the quiet state at 3 h 1"
  Shots 'strip-quiet-after'

  # ---- 10. 360 px: no shift there either ----
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 360; height = 690; deviceScaleFactor = 2; mobile = $true } | Out-Null
  WaitQuiet '360'
  $a10 = Strip
  [void](Eval ("HT.logRepeat(HT.shiftDate(HT.state().current, -1), " + $kim + ").ok")); WaitQuiet 'food at 360'
  $b10 = Strip
  Check (($a10.kind -eq 'quiet') -and ($b10.kind -eq 'food') -and ($a10.h -eq $b10.h) -and ($a10.next -eq $b10.next) -and (@($b10.links | Where-Object { -not $_.inside }).Count -eq 0)) ("R298 STRIP NO SHIFT at 360 px: quiet and food the same height (" + $a10.h + "/" + $b10.h + "), the day card where it was, the link inside the strip")
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  WaitQuiet '390'

  # ---- 11. words ----
  $all = ($words -join ' ')
  Check (($all -notmatch '(?i)activat') -and ($f1.text -like '*supplies*') -and ($o8.text -like '*supplies*') -and ($all -notmatch '(?i)\bshould\b')) "R298 STRIP WORDS: 'supplies', never 'activates' (R286), and no 'should', in every state"

  # ---- 12. the note: kept on the phone, not in the backup ----
  $note = Eval "localStorage.getItem(HT.CTX_KEY)"
  $exp = Eval "HT.exportJSON()"
  MarkOld
  Invoke-CDP 'Page.reload' @{ ignoreCache = $true } | Out-Null
  WaitBoot
  $note2 = Eval "localStorage.getItem(HT.CTX_KEY)"
  Check (($note -like '*"kind":"food"*') -and ($note2 -eq $note) -and ($exp -notlike '*healthtracker-context*') -and ($exp -notlike '*"kind":"food","dk"*')) "R298 STRIP NOTE: the last-action note survives a reload, under its own key, and is not in the backup"

  # ---- 13. cost: the perf gate's year WITH CGM, a food strip showing ----
  $m13 = EvalJ @'
(function () {
  // the perf gate's own fixture, from a clean profile: a year of days of 8 items, a year of
  // CGM -- and then one food logged, so a food strip is what the redraws re-insert
  var at = new Date(HT.todayKey() + 'T12:40:00').getTime(); HT.setClock(function () { return at; });
  localStorage.clear(); HT.boot();
  var S = HT.state(), t = HT.todayKey();
  var f = function (k) { return { name: 'Perf food', meal: 'lunch', time: '12:00', kcal: k, protein_g: 10, fat_g: 10, carb_g: 10, fiber_g: 1, soluble_fiber_g: 0, confidence: 'eyeballed', notes: '', source: 'manual' }; };
  for (var n = 1; n <= 365; n++) { var items = []; for (var j = 0; j < 8; j++) items.push(f(200 + j * 10 + n % 7)); S.days[HT.shiftDate(t, -n)] = { status: 'in_progress', water_l: 0, items: items }; }
  var store = {};
  Object.keys(S.days).forEach(function (dk) { var tt = [], v = [];
    for (var m = 0; m < 1440; m += 5) { var x = m - 720, val = 5.0; if (x > 0 && x <= 30) val = 5.0 + 2 * x / 30; else if (x > 30 && x < 90) val = 5.0 + 2 * (90 - x) / 60; tt.push(m); v.push(Math.round(val * 100) / 100); }
    store[dk] = { u: 'mmol/L', t: tt, v: v }; });
  HT.glucoseWrite(store); HT.resave();
  var y = HT.shiftDate(t, -1); HT.logRepeat(y, 0);
  var calib = function () { var a = []; for (var i = 0; i < 120000; i++) a.push((i * 7919) % 100003); a.sort(function (x, y) { return x - y; }); var d = document.createElement('div'); var h = ''; for (var k = 0; k < 400; k++) h += '<div class="trow"><span>' + a[k] + '</span><b>' + a[k + 1] + '</b></div>'; d.innerHTML = h; document.body.appendChild(d); var hh = d.getBoundingClientRect().height; d.remove(); return hh; };
  for (var w = 0; w < 3; w++) { HT.refresh(); calib(); }
  var c0 = HT.ctxComputes(), R = [], C = [];
  for (var i = 0; i < 21; i++) { var a = performance.now(); HT.refresh(); document.body.getBoundingClientRect(); var b = performance.now(); calib(); var c = performance.now(); R.push(b - a); C.push(c - b); }
  var med = function (v) { var s = v.slice().sort(function (x, y) { return x - y; }); return s[(s.length - 1) / 2]; };
  var r = med(R), cm = med(C);
  return { days: Object.keys(S.days).length, glucoseDays: Object.keys(HT.glucoseRead()).length, kind: document.getElementById('ctxStrip').getAttribute('data-kind'),
           recomputed: HT.ctxComputes() - c0, redrawMs: Math.round(r), calibMs: Math.round(cm), ratio: Math.round(r / cm * 100) / 100 };
})()
'@
  Write-Host ("  cost: " + $m13)
  $mv = $m13 | ConvertFrom-Json
  Check (($mv.days -ge 366) -and ($mv.glucoseDays -ge 366) -and ($mv.kind -eq 'food') -and ($mv.recomputed -eq 0) -and ($mv.ratio -le 3.0)) ("R298 STRIP COST: on a year of days with a year of CGM and a food strip showing, a redraw costs " + $mv.ratio + " reference workloads (budget 3.0) and works the strip out 0 times")

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("STRIP GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host ("STRIP GATE: PASS -- the context strip shows what relates to the last action at one fixed height, lives 3 h or until the next action, is worked out once, opens the right places, says supplies, keeps its note out of the backup, and stays inside the perf budget. Screenshots: " + $shots)
Write-Host "GATE: PASS"
exit 0
