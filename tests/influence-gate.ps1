# R318/2 -- THE INFLUENCE LAYER: an approved negative claim stated in the top box right after a
# matching tick or food; positive claims summed in the weekly review, never flagged per meal.
#
# PRE-REGISTERED (DECISIONS R318 part 2), on a PLACEHOLDER pack and stack built in the page
# (R204): a real tick of an item an approved negative claim at 80 % names flags it at once, with
# the amount and the probability, amber and never red, its i (44 px) opening the basis; one at
# 29 % does not; a positive claim never flags; a direction not approved never flags; the
# threshold at 25 % makes the 29 % one flag and at 85 % stops the 80 % one; a real drink log with
# alcohol flags the alcohol claim; the wheel's notch is on exactly the flagged claims' pathways
# and the stack item's goes when it is switched off; the weekly card lists the positive claim
# with its days; no advice words; nothing sideways; opening the basis writes nothing.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8434
$Dbg = 9634
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-influence-" + [System.Guid]::NewGuid().ToString('N'))
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

$shots = $env:INFLUENCE_SHOTS
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

  $boot = Eval "typeof HT === 'object' && typeof HT.influenceNegatives === 'function' && typeof HT.packImportText === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the influence layer is not on HT"; Cleanup; exit 2 }
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
    for ($tw = 0; $tw -lt 100; $tw++) {
      $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false, why: 'absent' }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); if (!(q.width > 0 && q.height > 0)) return { ok: false, why: 'not laid out' }; var cx = q.left + q.width / 2, cy = q.top + q.height / 2, hit = document.elementFromPoint(cx, cy); if (!hit || !(hit === b || b.contains(hit) || hit.contains(b))) return { ok: false, why: 'covered' }; var k = [q.left, q.top, q.width, q.height].map(Math.round).join(','); var still = window.__tapRect === k; window.__tapRect = k; return { ok: still, why: still ? '' : 'moving', x: cx, y: cy, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
      if ($r9.ok) { break }; Start-Sleep -Milliseconds 100 }
    if (-not $r9.ok) { Write-Host ('  STEP FAILED: ' + $sel + ' never showed (' + $r9.why + ')'); return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  # ---- the fixture: a PLACEHOLDER pack (R204) with approved directions, a placeholder stack ----
  $mk = @'
(function () {
  localStorage.clear(); HT.boot();
  var rv = '2026-11-03';
  var pr = function (p, of) { return { current_version: 1, versions: [{ version: 1, p: p, of: of, kind: 'general' }] }; };
  var dir = function (d, sh, ok) { return { direction: d, short: sh, reviewed_by_me: ok === false ? null : rv }; };
  var rec = function (id, name, claims) { return { id: id, plain_name: name, technical_name: name, group: 'g1', backbone: [], supply: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: claims }; };
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-11-03T10:00:00', private: true, reactome_version: 98,
    groups: [{ id: 'g1', name: 'Gate group', claims: [] }],
    records: [rec('pw-001', 'Gate path 1', ['c-neg', 'c-pos']), rec('pw-002', 'Gate path 2', ['c-alc']), rec('pw-003', 'Gate path 3', ['c-low'])],
    claims: [
      { id: 'c-neg', claim: 'Gate negative claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(0.8, 'that gate negative holds'), subject: { match: ['gatezinc'] }, for_me: dir('negative', 'gate negative') },
      { id: 'c-pos', claim: 'Gate positive claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(0.9, 'that gate positive holds'), subject: { match: ['gatezinc'] }, for_me: dir('positive', 'gate positive') },
      { id: 'c-low', claim: 'Gate low claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(0.29, 'that gate low holds'), subject: { match: ['gatelow'] }, for_me: dir('negative', 'gate low') },
      { id: 'c-un', claim: 'Gate unapproved claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(0.9, 'that gate unapproved holds'), subject: { match: ['gateunapp'] }, for_me: dir('negative', 'gate unapproved', false) },
      { id: 'c-alc', claim: 'Gate alcohol claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(0.8, 'that gate alcohol holds'), food_features: ['alcohol'], for_me: dir('negative', 'gate alcohol') }],
    interactions: [], reference_intakes: { source: 'x', group: 'y', values: {} }, lexicon: { rules: [] }, sources: [] };
  var S = HT.state(), t = HT.todayKey(), y = HT.shiftDate(t, -1);
  S.settings.stack = HT.normalizeStack([
    { id: 'sz', added_on: HT.shiftDate(t, -3), added_basis: 'created', name: 'Gatezinc 50', kind: 'supplement', dose: 50, dose_unit: 'mg' },
    { id: 'sl', added_on: HT.shiftDate(t, -3), added_basis: 'created', name: 'Gatelow tea', kind: 'supplement', dose: 1, dose_unit: 'capsule' },
    { id: 'su', added_on: HT.shiftDate(t, -3), added_basis: 'created', name: 'Gateunapp drops', kind: 'supplement', dose: 5, dose_unit: 'drop' }]);
  S.days[y] = { status: 'complete', water_l: 0, items: [{ name: 'Gate wine', meal: 'drink', time: '19:00', grams: 150, kcal: 128, protein_g: 0, fat_g: 0, carb_g: 4, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'corpus', notes: '',
    ref: { ns: 'cnf', id: '9001', name: 'Gate wine row', at: '2026-11-01', hash: 'h', attribution: 'x', how: 'picked', v: { '221': 10.6, '208': 85 } } }] };
  S.current = t; HT.resave();
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 15, sha256: hex, body: txt }));
  }).then(function (r) { HT.refresh(); return { imported: r.ok }; });
})()
'@
  $fx = EvalA $mk
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"imported":true*')) { Write-Host "ERROR: the placeholder pack did not import"; Cleanup; exit 2 }
  $ST = "(function(){ var s = document.getElementById('ctxStrip'), l = s.querySelector('.ctxl'), sm = s.querySelector('.ctxneg > summary'), r = sm ? sm.getBoundingClientRect() : null; var tok = function (n) { var d = document.createElement('div'); d.style.color = 'var(' + n + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; }; return { neg: s.getAttribute('data-neg'), kind: s.getAttribute('data-kind'), first: l ? l.textContent.replace(/\s+/g, ' ').trim() : '', all: s.textContent.replace(/\s+/g, ' '), edge: getComputedStyle(s).borderLeftColor, warn: tok('--warn'), bad: tok('--bad'), mark: s.querySelector('.ctxnegmk') ? getComputedStyle(s.querySelector('.ctxnegmk')).backgroundColor : '', sh: r ? Math.round(r.height) : 0 }; })()"
  function Strip { return ((EvalJ $ST) | ConvertFrom-Json) }
  function TickByTap([string]$name) {
    $null = TapSel '#fab'
    $null = TapSel '#sheetRoot .stkopen'
    $t = TapSel ('#sheetRoot .stkrow input[aria-label="' + $name + '"]')
    $null = TapSel '#entrySheet .sheetx'
    return $t }

  # ---- a real tick of an item matching an approved negative claim at 80 % ----------------------
  $exp0 = Eval "HT.exportJSON()"
  $k1 = TickByTap 'Gatezinc 50'
  $a = Strip
  Write-Host ("  after Gatezinc: " + ($a | ConvertTo-Json -Compress))
  if ($shots) { [void](Eval "window.scrollTo(0, 0); 1"); WaitQuiet 'shot'; Shot 'influence-flag-light'; Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'dark' }) } | Out-Null; WaitQuiet 'dark'; Shot 'influence-flag-dark'; Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null; WaitQuiet 'light' }
  Check ($k1.ok -and ($a.neg -eq '1') -and ($a.first -like ('Gatezinc 50 50 mg ' + [char]0xB7 + ' claim: gate negative ' + [char]0xB7 + ' 80 %*'))) "a real tick of an item an approved NEGATIVE claim at 80 % names puts it in the top box at once, as the first line: item, amount, the claim, its probability"
  Check (($a.edge -eq $a.warn) -and ($a.mark -eq $a.warn) -and ($a.edge -ne $a.bad) -and ($a.sh -ge 44)) "amber, never red: the box's edge and the line's mark are the warn colour; its i is a 44 px target"
  Check (($a.all -notlike '*gate positive*') -and ($a.all -notmatch '\b(should|stop|avoid|don''t|try|must|need to)\b')) "a POSITIVE claim on the same item never flags; the words carry no advice"
  $null = Eval "(function(){ HT.refresh(); return 1; })()"; WaitQuiet 'redraw'
  $aR = Strip
  Check (($aR.neg -eq '1') -and ($aR.first -eq $a.first)) "R321: the box that showed the flag keeps it on a redraw"
  $bt = TapSel '#ctxStrip .ctxneg > summary'
  Check ($bt.ok -and ($bt.h -ge 44)) "the flag's i is a real 44 px target of its own: tapped at its centre, nothing else is there"
  $b = Eval "(function(){ var d = document.querySelector('#ctxStrip .ctxneg'); return (d && d.open ? 'open|' : 'shut|') + (d ? d.textContent.replace(/\s+/g, ' ') : ''); })()"
  Write-Host ("  basis: " + $b)
  Check ($b -like 'open|*Gate negative claim. 80 % that gate negative holds*GRADE low*general, no personal data yet*not a reading of you*') "a real tap on its i opens the basis: the claim, 'N % that ...', GRADE, general or personal, and that it is a study claim, not a reading"

  # ---- below the threshold, unapproved: no flag ------------------------------------------------
  $null = TickByTap 'Gatelow tea'
  $c = Strip
  $null = Eval "(function(){ HT.setInfluenceMin(25); return 1; })()"; WaitQuiet 'threshold 25'
  $c25 = Strip
  $null = Eval "(function(){ HT.setInfluenceMin(85); return 1; })()"; WaitQuiet 'threshold 85'
  $null = TickByTap 'Gatezinc 50'
  $null = TickByTap 'Gatezinc 50'
  $c85 = Strip
  $null = Eval "(function(){ HT.setInfluenceMin(30); return 1; })()"; WaitQuiet 'threshold 30'
  $null = TickByTap 'Gateunapp drops'
  $u = Strip
  Write-Host ("  29 %: " + $c.neg + ' | at 25: ' + $c25.first + ' | at 85: ' + $c85.neg + ' ' + $c85.first + ' | unapproved: ' + $u.neg)
  Check (($c.neg -eq '0') -and ($c.all -notlike '*gate low*')) "a negative claim at 29 % does not flag at the default 30 %"
  Check (($c25.neg -eq '1') -and ($c25.first -like ('Gatelow tea 1 capsule ' + [char]0xB7 + ' claim: gate low ' + [char]0xB7 + ' 29 %*')) -and ($c85.neg -eq '0')) "THE THRESHOLD TAKES EFFECT: at 25 % the 29 % claim flags; at 85 % the 80 % one, ticked again, does not"
  Check (($u.neg -eq '0') -and ($u.all -notlike '*gate unapproved*')) "a direction the user has not approved never flags, even at 90 %"

  # ---- R321: at most once a day per item -- the same item ticked again today shows no flag -------
  $null = TickByTap 'Gatezinc 50'
  $z0 = Strip
  $z1t = TickByTap 'Gatezinc 50'
  $z1 = Strip
  $zn = Eval "(function(){ var tl = (HT.state().timeline || {})[HT.todayKey()] || []; return tl.filter(function (r) { return r.stackId === 'sz'; }).length + '|' + JSON.stringify(HT.influenceShown()[HT.todayKey()] || {}); })()"
  Write-Host ("  zinc again, at 30 %: unticked " + $z0.neg + ' | ticked ' + $z1.neg + ' [' + $z1.first + '] | ' + $zn)
  Check ($z1t.ok -and ($z1.kind -eq 'stack') -and ($z1.neg -eq '0') -and ($z1.all -notlike '*gate negative*') -and ($z1.all -like '*Gatezinc 50*') -and ($zn -like '1|*"s:sz"*')) "R321: THE SAME ITEM TICKED AGAIN THE SAME DAY (a real untick and tick, at 30 %) shows its box without the flag -- one flag a day per item"

  # ---- a real food log: a drink with alcohol flags the alcohol claim ---------------------------
  $null = TapSel '#fab'
  $d1 = TapSel '#sheetRoot .drkrow'
  $null = TapSel '#entrySheet .sheetx'
  $w = Strip
  Write-Host ("  after the drink: " + $w.first)
  Check ($d1.ok -and ($w.neg -eq '1') -and ($w.first -like ('Gate wine 150 g ' + [char]0xB7 + ' claim: gate alcohol ' + [char]0xB7 + ' 80 %*'))) "a real food log of a drink whose row has alcohol flags the approved alcohol claim at once"

  # ---- the wheel's notch: exactly the flagged claims' pathways, while they are current ----------
  $null = TapSel '[data-card="pathways"] > details > summary'
  $n1 = Eval "Array.prototype.map.call(document.querySelectorAll('#pathways .pwnotch'), function (n) { return n.getAttribute('data-pw'); }).sort().join(',')"
  $nf = Eval "(function(){ var n = document.querySelector('#pathways .pwnotch'); var d = document.createElement('div'); d.style.color = 'var(--warn)'; document.body.appendChild(d); var w = getComputedStyle(d).color; d.remove(); return n && getComputedStyle(n).fill === w ? 'warn' : (n ? getComputedStyle(n).fill + ' vs ' + w : ''); })()"
  $null = Eval "(function(){ HT.stackItemEnable('sz', false); HT.renderPathways(); return 1; })()"; WaitQuiet 'switched off'
  $n2 = Eval "Array.prototype.map.call(document.querySelectorAll('#pathways .pwnotch'), function (n) { return n.getAttribute('data-pw'); }).sort().join(',')"
  Write-Host ("  notches: " + $n1 + ' -> switched off: ' + $n2 + ' (' + $nf + ')')
  Check (($n1 -eq 'pw-001,pw-002') -and ($n2 -eq 'pw-002') -and ($nf -eq 'warn')) "the wheel's amber notch sits on exactly the flagged claims' pathways -- the stack item's while it is switched on, the drink's within 28 days -- and the item's goes when it is switched off"

  # ---- the weekly review: the positive claim with its days --------------------------------------
  $wk = Eval "(function(){ var h = HT.weekReviewHTML(HT.weekMonday(HT.todayKey())); var d = document.createElement('div'); d.innerHTML = h; var c = d.querySelector('[data-card=positive]'); return c ? c.textContent.replace(/\s+/g, ' ') : 'NONE'; })()"
  Write-Host ("  weekly: " + $wk)
  Check (($wk -like '*Positive claims*gate positive*90 % that gate positive holds*from Gatezinc 50*1 of * days this week*1 of 28 in the last 4 weeks*') -and ($wk -notlike '*gate negative*')) "the weekly review lists the approved positive claim the week's ticks matched, with its probability and its days -- this week and the last 4 weeks; no negative one there"

  # ---- layout, and nothing written but the entries and the note --------------------------------
  $lay = @()
  foreach ($wd in 390, 360) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wd; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    WaitQuiet 'resize'
    $lay += Eval "(function(){ var s = document.getElementById('ctxStrip').getBoundingClientRect(); return [window.innerWidth, Math.round(s.right) <= window.innerWidth, document.documentElement.scrollWidth - window.innerWidth].join(':'); })()"
    Shot ("influence-" + $wd)
  }
  Write-Host ("  layout: " + ($lay -join ' '))
  Check (-not ($lay | Where-Object { $_ -notlike '*:true:0' })) "nothing runs sideways at 390 and 360"
  $e1 = Eval "HT.exportJSON()"
  $null = TapSel '#ctxStrip .ctxneg > summary'
  Check ((Eval "HT.exportJSON()") -eq $e1) "opening a flag's basis writes nothing"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("INFLUENCE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "INFLUENCE GATE: PASS -- an approved negative claim is stated after the action that matches it, amber, with its probability and no advice; positive ones are summed in the week, never flagged"
Write-Host "GATE: PASS"
exit 0
