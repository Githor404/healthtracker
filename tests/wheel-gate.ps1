# R318/1 -- THE PATHWAY WHEEL at the top of the Pathways card.
#
# PRE-REGISTERED (DECISIONS R318 part 1), on a PLACEHOLDER pack of 76 records in 14 groups
# built in the page (R204), with a fixture log: a closed card draws nothing and a real tap
# opening it draws one segment per record; each segment's shade is its known share computed
# from the fixture by hand, the ones with no lines hatched; every group's slice is 44 px along
# the rim and 44 px deep at 390 and 360; a real tap on the smallest slice lists its pathways
# as 44 px buttons; a real tap on one draws exactly its connections and opens its panel; the
# panel's rows equal the rows of its i in the list, one per connected pathway, in plain names
# (symbols behind the i); a row's tap selects that pathway; taps write nothing; no "Show
# all"; group numbers 12 px (the recorded exception) and nothing else under 16 px; the hatch
# apart from "none known" in light and dark; nothing sideways; a perf budget.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8433
$Dbg = 9633
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-wheel-" + [System.Guid]::NewGuid().ToString('N'))
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
  WaitQuiet 'before input'
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    WaitQuiet 'typing' } }
function Settle { WaitQuiet 'after a step' }   # R283: was a fixed 400 ms

$shots = $env:WHEEL_SHOTS
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
  Invoke-CDP 'Emulation.setTimezoneOverride' @{ timezoneId = 'America/Toronto' } | Out-Null   # a fixed zone, so the fixture's times mean the same on any machine
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.pwWheelFill === 'function' && typeof HT.packImportText === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the wheel is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  function TapAt([double]$x, [double]$y) {
    WaitQuiet 'before input'
    Write-Host ('  STEP tap at ' + [int]$x + ',' + [int]$y)
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap' }
  function TapSel([string]$sel) {
    WaitQuiet 'before input'
    Write-Host ('  STEP tap ' + $sel)
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + Math.min(r.width / 2, 120), y: r.top + r.height / 2 }; })()")
    if ($p -eq 'null' -or -not $p) { return $false }
    $q = $p | ConvertFrom-Json; TapAt $q.x $q.y; return $true }
  # ---- the fixture: a PLACEHOLDER pack (R204) of 76 records in 14 groups, built in the page ----
  $mk = @'
window.__mkWheel = function () {
  var rv = '2026-11-03';
  var sizes = [10, 8, 7, 6, 6, 6, 5, 5, 5, 5, 4, 3, 2, 4];
  var groups = [], records = [], k = 0;
  var PROT = { cofactor: 'protein', key: 'protein_g', tracked: true }, IRON = { cofactor: 'iron', key: 'iron_mg', slot: '303', dri: 'iron', tracked: true }, UNT = { cofactor: 'untracked x', tracked: false };
  var lines = { 'pw-001': [PROT], 'pw-002': [IRON], 'pw-003': [PROT, IRON], 'pw-004': [UNT], 'pw-020': [PROT], 'pw-066': [IRON] };
  sizes.forEach(function (n, gi) {
    var gid = 'g' + (gi + 1);
    groups.push({ id: gid, name: 'Gate group ' + (gi + 1), claims: [] });
    for (var i = 0; i < n; i++) {
      k++; var id = 'pw-' + ('00' + k).slice(-3);
      records.push({ id: id, plain_name: 'Gate path ' + k, technical_name: 'Gate tech ' + k, group: gid, backbone: [{ source: 'Reactome', version: 98, id: 'R-HSA-' + (1000 + k) }],
        supply: lines[id] || [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: k === 10 ? ['claim-a'] : [] });
    }
  });
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-11-03T10:00:00', private: true, reactome_version: 98, groups: groups, records: records,
    claims: [{ id: 'claim-a', claim: 'Placeholder claim A.', reviewed_by_me: rv, evidence: { grade: 'low', human: true }, probability: { current_version: 1, versions: [{ version: 1, p: 0.6, of: 'that placeholder A holds', kind: 'general' }] }, pathways: ['pw-010'] }],
    interactions: [], reference_intakes: { source: 'x', group: 'y', values: { iron: { label: 'Iron', value: 8, unit: 'mg', kind: 'RDA', slot: 303, slot_factor: 1 } } }, lexicon: { rules: [] },
    sources: [{ id: 'src-l', authors: 'Author L et al.', venue: 'Journal L', year: 2001 }],
    connections: { reactome_version: 98, licence: 'CC0', rule: 'r',
      names: { proteins: { SYMA: { plain: 'Plain enzyme A' }, SYMB: { plain: 'Plain enzyme B' } } },
      records: { 'pw-010': { n: 9, shown: [{ id: 'pw-011', score: 3, proteins: ['SYMA'], molecules: ['gate molecule(2-)'] }, { id: 'pw-040', score: 2, proteins: ['SYMB'], molecules: [] },
                                          { id: 'pw-075', score: 1, proteins: [], molecules: ['m5'] }, { id: 'pw-099', score: 0.5, proteins: ['GONE'], molecules: [] }] } },
      literature: [{ a: 'pw-011', b: 'pw-010', says: 'eleven links ten', sources: ['src-l'], quotes: [] }, { a: 'pw-010', b: 'pw-050', says: 'ten links fifty', sources: [], quotes: [] }] } };
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 14, sha256: hex, body: txt }));
  });
};
(function () {
  localStorage.clear(); HT.boot();
  var S = HT.state(), t = HT.todayKey();
  var f = function (n, g, x) { return Object.assign({ name: n, meal: 'lunch', time: '12:00', grams: g, kcal: 100, carb_g: 1, fat_g: 1, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }, x); };
  // 28 days: 600 g carrying protein and iron, 400 g protein only -> protein 100 %, iron 60 %
  S.days[t] = { status: 'in_progress', water_l: 0, items: [f('Gate food A', 600, { protein_g: 10, micros: { iron_mg: 2 } }), f('Gate dose', 50, { meal: 'supplement', stackId: 's1', micros: { iron_mg: 9 } })] };
  S.days[HT.shiftDate(t, -5)] = { status: 'complete', water_l: 0, items: [f('Gate food B', 400, { protein_g: 8 })] };
  S.days[HT.shiftDate(t, -29)] = { status: 'complete', water_l: 0, items: [f('Gate food old', 1000, { protein_g: 8, micros: { iron_mg: 3 } })] };
  S.current = t; HT.resave();
  return window.__mkWheel().then(function (r) { HT.refresh(); return { imported: r.ok }; });
})()
'@
  $fx = EvalA $mk
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"imported":true*')) { Write-Host "ERROR: the placeholder pack did not import"; Cleanup; exit 2 }

  # ---- a closed card draws no wheel; a real tap on its summary draws it ---------------------------
  $c0 = Eval "(function(){ var c = document.querySelector('[data-card=pathways] > details'); c.open = false; HT.renderPathways(); return document.querySelectorAll('#pathways .pwwheel').length; })()"
  $t0 = TapSel '[data-card=\"pathways\"] > details > summary'
  $c1 = Eval "document.querySelectorAll('#pathways .pwwheel svg .pwseg').length"
  Check (($c0 -eq 0) -and $t0 -and ($c1 -eq 76)) "a closed Pathways card draws no wheel; a real tap opening it draws one segment per record (76; closed: $c0, open: $c1)"

  # ---- shade = the known share, computed by hand from the fixture --------------------------------
  $sh = EvalJ @'
(function () {
  var want = { 'pw-001': 1, 'pw-002': 0.6, 'pw-003': 0.8, 'pw-004': 0, 'pw-020': 1, 'pw-066': 0.6 };
  var segs = Array.prototype.slice.call(document.querySelectorAll('#pathways .pwseg'));
  var bad = [];
  segs.forEach(function (s) {
    var id = s.getAttribute('data-pw'), w = want[id];
    if (w != null) {
      var op = Number(s.getAttribute('fill-opacity')), exp = Math.round((0.08 + 0.72 * w) * 1000) / 1000;
      if (Math.abs(Number(s.getAttribute('data-share')) - w) > 1e-9 || op !== exp || s.classList.contains('pwhatched')) bad.push(id + ':' + s.getAttribute('data-share') + '/' + op);
    } else if (!s.classList.contains('pwhatched') || s.getAttribute('fill') !== 'url(#pwhatch)') bad.push(id + ':not hatched');
  });
  var fills = segs.filter(function (s) { return !s.classList.contains('pwhatched'); }).map(function (s) { return getComputedStyle(s).fill; });
  return { n: segs.length, bad: bad, hatched: segs.filter(function (s) { return s.classList.contains('pwhatched'); }).length,
           oneHue: fills.every(function (x) { return x === fills[0]; }), hue: fills[0], txt: getComputedStyle(document.body).color };
})()
'@
  Write-Host ("  shades: " + $sh)
  Check ($sh.Contains('"n":76,"bad":[],"hatched":70') -and $sh.Contains('"oneHue":true')) "each segment's shade is its known share from the fixture (protein 100 %, iron 60 % -- a label value; the 2-line mean 80 %; an untracked line 0 %; the food 29 days back and the stack dose left out), one neutral hue at 8 % + 72 % x share; the 70 with no lines are hatched"

  # ---- geometry: every group's slice 44 px along the rim and 44 px deep, at 390 and 360 ------------
  $geo = @()
  foreach ($wd in 390, 360) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wd; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    $null = Eval "(function(){ HT.renderPathways(); return 1; })()"
    WaitQuiet 'resize'
    $geo += EvalJ @'
(function () {
  var svg = document.querySelector('#pathways .pwwheelsvg'), b = svg.getBoundingClientRect();
  var hits = Array.prototype.slice.call(svg.querySelectorAll('.pwhit'));
  var scale = b.width / Number(svg.getAttribute('width'));
  var rim = hits.map(function (h) { var a0 = +h.getAttribute('data-a0'), a1 = +h.getAttribute('data-a1'), r1 = +h.getAttribute('data-r1'), r0 = +h.getAttribute('data-r0'); return { chord: 2 * r1 * Math.sin((a1 - a0) / 2) * scale, deep: (r1 - r0) * scale }; });
  return { w: window.innerWidth, size: Math.round(b.width), groups: hits.length, minChord: Math.round(Math.min.apply(null, rim.map(function (x) { return x.chord; })) * 10) / 10,
           minDeep: Math.round(Math.min.apply(null, rim.map(function (x) { return x.deep; }))), legend: document.querySelectorAll('#pathways .pwgbtn').length,
           smallBtn: Array.prototype.filter.call(document.querySelectorAll('#pathways .pwgbtn'), function (e) { var r = e.getBoundingClientRect(); return r.height < 44 || r.width < 44; }).length };
})()
'@
  }
  Write-Host ("  geometry: " + ($geo -join ' '))
  Check (-not ($geo | Where-Object { $g = $_ | ConvertFrom-Json; -not (($g.groups -eq 14) -and ($g.minChord -ge 44) -and ($g.minDeep -ge 44) -and ($g.legend -eq 14) -and ($g.smallBtn -eq 0)) })) "every group's slice is at least 44 px along the rim and its tap region 44 px deep, and each of the 14 legend buttons is a 44 px target, at 390 and 360"

  # ---- step 1: a real tap on the SMALLEST group's slice lists its pathways as 44 px buttons ---------
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  $null = Eval "(function(){ HT.renderPathways(); return 1; })()"
  WaitQuiet 'back to 390'
  $exp0 = Eval "HT.exportJSON()"
  $pt = EvalJ @'
(function () {
  var h = document.querySelector('#pathways .pwhit[data-group="g13"]'), svg = h.ownerSVGElement;
  svg.scrollIntoView({ block: 'center' });
  var b = svg.getBoundingClientRect(), s = b.width / Number(svg.getAttribute('width')), c = Number(svg.getAttribute('width')) / 2;
  var a = (+h.getAttribute('data-a0') + +h.getAttribute('data-a1')) / 2, r = (+h.getAttribute('data-r0') + +h.getAttribute('data-r1')) / 2;
  return { x: b.left + (c + r * Math.sin(a)) * s, y: b.top + (c - r * Math.cos(a)) * s };
})()
'@
  $pv = $pt | ConvertFrom-Json
  TapAt $pv.x $pv.y
  $s1 = EvalJ "(function(){ var l = document.querySelector('#pathways .pwglist'); if (!l) return { list: null }; var b = Array.prototype.slice.call(l.querySelectorAll('.pwpick')); return { list: l.getAttribute('data-group'), n: b.length, ids: b.map(function (x) { return x.getAttribute('data-pw'); }), small: b.filter(function (x) { var r = x.getBoundingClientRect(); return r.height < 44 || r.width < 44; }).length, on: (document.querySelector('#pathways .pwhit.pwon') || {}).getAttribute ? document.querySelector('#pathways .pwhit.pwon').getAttribute('data-group') : null, chords: document.querySelectorAll('#pathways .pwchord').length }; })()"
  Write-Host ("  step 1: " + $s1)
  Check ($s1.Contains('"list":"g13","n":2,"ids":["pw-071","pw-072"],"small":0,"on":"g13","chords":0')) "STEP 1: a real tap on the smallest group's slice (2 pathways) selects that group and lists its pathways below as 44 px buttons; nothing is drawn across the wheel yet"

  # ---- step 2: a real tap on a pathway draws exactly its connections and opens its panel ------------
  $null = TapSel '#pathways .pwgbtn[data-group=\"g1\"]'
  $t2 = TapSel '#pathways .pwpick[data-pw=\"pw-010\"]'
  $s2 = EvalJ @'
(function () {
  var ch = Array.prototype.slice.call(document.querySelectorAll('#pathways .pwchord'));
  var panel = document.querySelector('#pathways .pwpanel');
  var rows = panel ? Array.prototype.slice.call(panel.querySelectorAll('.pwwhylines .pwconn')) : [];
  var nb = Array.prototype.map.call(document.querySelectorAll('#pathways .pwseg.pwnb'), function (s) { return s.getAttribute('data-pw'); }).sort();
  return { panel: panel ? panel.getAttribute('data-pw') : null, sel: Array.prototype.map.call(document.querySelectorAll('#pathways .pwseg.pwsel'), function (s) { return s.getAttribute('data-pw'); }),
    chordFrom: ch.every(function (c) { return c.getAttribute('data-a') === 'pw-010'; }), chordTo: ch.map(function (c) { return c.getAttribute('data-b'); }).sort(),
    rowTo: rows.map(function (r) { return r.getAttribute('data-to'); }), nb: nb, dashed: ch.filter(function (c) { return c.classList.contains('pwlit'); }).map(function (c) { return c.getAttribute('data-b'); }) };
})()
'@
  Write-Host ("  step 2: " + $s2)
  Check ($t2 -and $s2.Contains('"panel":"pw-010","sel":["pw-010"],"chordFrom":true,"chordTo":["pw-011","pw-040","pw-050","pw-075"],"rowTo":["pw-011","pw-040","pw-075","pw-050"],"nb":["pw-011","pw-040","pw-050","pw-075"],"dashed":["pw-050"]')) "STEP 2: a real tap on a pathway selects it, draws exactly its connections -- one curve per connected pathway, all from it, dashed only where the literature alone links them -- outlines those, and opens its panel"

  # ---- the panel: R332.1 -- why these lines, one row per drawn line; the same pathways as the i -------
  $p3 = EvalJ @'
(function () {
  var panel = document.querySelector('#pathways .pwpanel');
  var rows = Array.prototype.slice.call(panel.querySelectorAll('.pwwhylines .pwlinerow'));
  var li = document.querySelector('#pathways .pwrec[data-pw="pw-010"] details.pwinfo');
  var inames = Array.prototype.map.call(li.querySelectorAll('.pwconnected .pwconn .pwconnname'), function (r) { return r.textContent.replace(/\s*\u203a\s*$/, '').trim(); });
  var pnames = rows.map(function (r) { return r.querySelector('.pwconnname').textContent.trim(); });
  var ch = Array.prototype.slice.call(document.querySelectorAll('#pathways .pwchords .pwchord'));
  var style = function (e) { return e.classList.contains('pwlit') ? 'dashed' : 'solid'; };
  var tech = panel.querySelector('.pwtechids');
  return { same: JSON.stringify(pnames) === JSON.stringify(inames), order: rows.map(function (r) { return r.getAttribute('data-hl'); }).join(',') === ch.map(function (c) { return c.getAttribute('data-b'); }).join(','),
    styles: rows.map(function (r) { return style(r.querySelector('.pwlinemkp')); }).join(',') === ch.map(style).join(','),
    small: Array.prototype.filter.call(panel.querySelectorAll('.pwhlrow, .pwopen'), function (e) { var q = e.getBoundingClientRect(); return q.height < 44 || q.width < 44; }).length,
    row11: rows.filter(function (r) { return r.getAttribute('data-hl') === 'pw-011'; }).map(function (r) { return r.innerText.replace(/\s+/g, ' ').trim(); })[0] || '',
    plain: rows.map(function (r) { return r.textContent; }).join(' ').indexOf('SYMA') < 0,
    tech: tech ? tech.textContent.indexOf('SYMA') >= 0 && tech.textContent.indexOf('gate molecule(2-)') >= 0 : false,
    order2: Array.prototype.map.call(panel.querySelectorAll(':scope > .pwwhy > .pwcardh, :scope > .pwbg > .pwcardh'), function (e) { return e.textContent; }).join('|'),
    head: panel.innerText.replace(/\s+/g, ' ').slice(0, 3000) };
})()
'@
  Write-Host ("  panel: " + $p3)
  $p3v = $p3 | ConvertFrom-Json
  Check ($p3v.same -and $p3v.order -and $p3v.styles -and ($p3v.small -eq 0)) "R332.1 WHY THESE LINES: one row per line drawn on the wheel, in the wheel's order, each with a sample in its line's own style (solid or dashed), the same pathways as its i in the list; every row and its Open button 44 px"
  Check (($p3v.row11 -like ('Gate path 11 both use Plain enzyme A, gate molecule; literature: eleven links ten ' + [char]0x2014 + ' Author L et al., Journal L, 2001 connected ' + [char]0x2014 + ' effect not measured*')) -and $p3v.plain -and $p3v.tech) "R332.1: a line's row says what the two share in plain words ('both use ...'), the literature link's own words, and what the line means -- connected, effect not measured; gene symbols only behind the i"
  Check (($p3v.order2 -like 'Why this dot|Why these lines|*About this pathway') -and ($p3v.head -like '*Nothing you logged in the last 28 days matches a claim for this pathway*Gate group 1*Raw materials known: no raw materials listed*Reviewed claims: 1*')) "R332.1 ORDER: the panel reads in the order of the wheel -- why this dot (none here, and it says so), why these lines, then the background"
  # ---- R332.1: tap-highlight both ways, by real taps --------------------------------------------------
  $null = TapSel '#pathways .pwpanel .pwlinerow[data-hl=\"pw-050\"]'
  $h1 = Eval "(function(){ var c = Array.prototype.filter.call(document.querySelectorAll('#pathways .pwchords .pwchord.pwhl'), function (x) { return true; }).map(function (x) { return x.getAttribute('data-b'); }).join(','); var r = document.querySelector('#pathways .pwpanel .pwlinerow[data-hl=\""pw-050\""]'); return c + '|' + (r ? r.getAttribute('aria-pressed') : ''); })()"
  $pt2 = EvalJ @'
(function () {
  var c = document.querySelector('#pathways .pwchords .pwchord[data-b="pw-011"]'), svg = c.ownerSVGElement;
  svg.scrollIntoView({ block: 'center' });
  var m = c.getAttribute('d').match(/Q[^ ]+ [^ ]+ ([-\d.]+) ([-\d.]+)/), b = svg.getBoundingClientRect(), s = b.width / Number(svg.getAttribute('width'));
  return { x: b.left + Number(m[1]) * s, y: b.top + Number(m[2]) * s };
})()
'@
  $pv2 = $pt2 | ConvertFrom-Json
  TapAt $pv2.x $pv2.y
  $h2 = Eval "(function(){ var c = Array.prototype.map.call(document.querySelectorAll('#pathways .pwchords .pwchord.pwhl'), function (x) { return x.getAttribute('data-b'); }).join(','); var r = document.querySelector('#pathways .pwpanel .pwhlrow.pwhl'); return c + '|' + (r ? r.getAttribute('data-hl') : '') + '|' + (document.querySelector('#pathways .pwpanel') || {}).getAttribute('data-pw'); })()"
  Shot 'wheel-hl'
  Write-Host ("  highlight: row->line " + $h1 + ' ; wheel->row ' + $h2)
  Check (($h1 -eq 'pw-050|true') -and ($h2 -eq 'pw-011|pw-011|pw-010')) "R332.1 TAP-HIGHLIGHT BOTH WAYS: a real tap on a line's row highlights that line on the wheel (and the row); a real tap on the wheel at a line's end highlights the line and its row, the pathway still picked"
  $t3 = TapSel '#pathways .pwpanel .pwconn[data-to=\"pw-040\"]'
  $s3 = Eval "(function(){ var p = document.querySelector('#pathways .pwpanel'); return (p ? p.getAttribute('data-pw') : '') + '|' + document.querySelectorAll('#pathways .pwchord').length; })()"
  Check ($t3 -and ($s3 -eq 'pw-040|0')) "a real tap on a row's Open button (R332.1; the row itself highlights) selects that pathway on the wheel (${s3} -- it has no connections of its own, so nothing is drawn)"
  Check ((Eval "HT.exportJSON()") -eq $exp0) "the taps wrote nothing: the export is unchanged"
  Check ((Eval "(function(){ return /show all/i.test(document.getElementById('pathways').innerText); })()") -eq $false) "there is no 'Show all connections' control"

  # ---- type: the group numbers at 12 px, nothing else in the wheel under 16 px ---------------------
  $ty = EvalJ @'
(function () {
  var w = document.querySelector('#pathways .pwwheel');
  var nums = Array.prototype.map.call(w.querySelectorAll('.pwgnum'), function (t) { return getComputedStyle(t).fontSize; });
  var under = [];
  Array.prototype.forEach.call(w.querySelectorAll('*'), function (e) {
    if (e.closest('title') || e.tagName.toLowerCase() === 'title' || e.classList.contains('pwgnum')) return;
    var own = Array.prototype.some.call(e.childNodes, function (n) { return n.nodeType === 3 && n.textContent.trim(); });
    if (!own) return;
    var r = e.getBoundingClientRect(); if (!r.width && !r.height) return;
    if (parseFloat(getComputedStyle(e).fontSize) < 16) under.push(e.className + ':' + getComputedStyle(e).fontSize);
  });
  return { nums: nums.length, all12: nums.every(function (x) { return x === '12px'; }), under: under };
})()
'@
  Write-Host ("  type: " + $ty)
  Check ($ty.Contains('"nums":14,"all12":true,"under":[]')) "the 14 group numbers are 12 px -- the recorded exception for this view -- and no other text in the wheel is under 16 px"

  # ---- light and dark: the hatch apart from 'none known'; nothing sideways at 390 and 360 -----------
  $th = @()
  foreach ($mode in 'light', 'dark') {
    Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = $mode }) } | Out-Null
    foreach ($wd in 390, 360) {
      Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wd; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
      $null = Eval "(function(){ HT.pwWheelPick('pw-010'); return 1; })()"
      WaitQuiet 'theme'
      $th += EvalJ @'
(function () {
  var rgb = function (s) { var m = String(s).match(/[\d.]+/g).map(Number); return m.slice(0, 3); };
  var lum = function (c) { var f = function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
  var cs = getComputedStyle(document.documentElement);
  var tok = function (n) { var d = document.createElement('div'); d.style.color = 'var(' + n + ')'; document.body.appendChild(d); var c = rgb(getComputedStyle(d).color); d.remove(); return c; };
  var panel = tok('--panel'), txt = tok('--txt'), hatch = tok('--pwhatch');
  var none = panel.map(function (p, i) { return p + (txt[i] - p) * 0.08; });
  var L1 = lum(hatch), L2 = lum(none), ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
  var w = document.querySelector('#pathways .pwwheel');
  var wide = Array.prototype.filter.call(w.querySelectorAll('*'), function (e) { var r = e.getBoundingClientRect(); return r.width > 0 && r.right > window.innerWidth + 0.5; }).length;
  return { w: window.innerWidth, dark: matchMedia('(prefers-color-scheme: dark)').matches, ratio: Math.round(ratio * 100) / 100, wide: wide, page: document.documentElement.scrollWidth - window.innerWidth };
})()
'@
      if ($shots) { [void](Eval "(function(){ document.querySelector('#pathways .pwwheel').scrollIntoView({ block: 'start' }); window.scrollBy(0, -60); return 1; })()"); WaitQuiet 'shot'; Shot ("wheel-" + $mode + "-" + $wd); [void](Eval "(function(){ document.querySelector('#pathways .pwglist').scrollIntoView({ block: 'start' }); window.scrollBy(0, -60); return 1; })()"); WaitQuiet 'shot'; Shot ("wheel-list-" + $mode + "-" + $wd) }
    }
  }
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null
  Write-Host ("  themes: " + ($th -join ' '))
  Check (-not ($th | Where-Object { $v = $_ | ConvertFrom-Json; -not ($v.ratio -ge 1.5) })) "in light and dark the hatch stripe and a 'none known' segment differ by at least 1.5:1"
  Check (-not ($th | Where-Object { -not ($_.Contains('"wide":0,"page":0')) })) "nothing runs sideways at 390 and 360, light and dark"

  # ---- perf: building and selecting, against perf-gate's reference workload ------------------------
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  WaitQuiet 'back to 390'
  $pf = EvalJ @'
(function () {
  var calib = function () { var a = []; for (var i = 0; i < 120000; i++) a.push((i * 7919) % 100003); a.sort(function (x, y) { return x - y; }); var d = document.createElement('div'); var h = ''; for (var k = 0; k < 400; k++) h += '<div class="trow"><span>' + a[k] + '</span><b>' + a[k + 1] + '</b></div>'; d.innerHTML = h; document.body.appendChild(d); var hh = d.getBoundingClientRect().height; d.remove(); return hh; };
  var med = function (v) { var s = v.slice().sort(function (x, y) { return x - y; }); return s[(s.length - 1) / 2]; };
  HT.pwWheelGroup('g1'); HT.pwWheelGroup('g1');
  for (var w = 0; w < 3; w++) { HT.pwWheelFill(); calib(); }
  var B = [], S = [], C = [];
  for (var i = 0; i < 11; i++) {
    var a = performance.now(); HT.pwWheelFill(); document.body.getBoundingClientRect(); var b = performance.now();
    HT.pwWheelPick(i % 2 ? 'pw-010' : 'pw-001'); document.body.getBoundingClientRect(); var c = performance.now();
    calib(); var d = performance.now();
    B.push(b - a); S.push(c - b); C.push(d - c);
  }
  var cm = med(C);
  return { buildMs: Math.round(med(B) * 100) / 100, selectMs: Math.round(med(S) * 100) / 100, calibMs: Math.round(cm * 10) / 10,
           build: Math.round(med(B) / cm * 1000) / 1000, select: Math.round(med(S) / cm * 1000) / 1000 };
})()
'@
  Write-Host ("  perf: " + $pf)
  $pfv = $pf | ConvertFrom-Json
  Check (($pfv.build -le 0.5) -and ($pfv.select -le 0.25)) ("perf: building the open wheel costs " + $pfv.build + " and a selection " + $pfv.select + " of the reference workload (median of 11) -- budgets 0.5 and 0.25")
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("WHEEL GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "WHEEL GATE: PASS -- every pathway on one wheel, shaded by its known share, reached in two 44 px taps; a pathway's connections drawn alone, its panel the same rows as its i"
Write-Host "GATE: PASS"
exit 0
