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

  # ---- R331.1: the wheel's dots -- only what was logged, and its balance -----------------------
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  WaitQuiet '390'
  $mk2 = @'
(function () {
  localStorage.clear(); HT.boot();
  var rv = '2026-11-07';
  var pr = function (p, of) { return { current_version: 1, versions: [{ version: 1, p: p, of: of, kind: 'general' }] }; };
  var dir = function (d, sh) { return { direction: d, short: sh, reviewed_by_me: rv }; };
  var rec = function (id, name, claims) { return { id: id, plain_name: name, technical_name: name, group: 'g1', backbone: [], supply: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: claims }; };
  var cl = function (id, p, m, d, sh) { return { id: id, claim: 'Gate ' + sh + ' claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(p, 'that gate ' + sh + ' holds'), subject: { match: [m] }, for_me: dir(d, 'gate ' + sh) }; };
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-11-07T10:00:00', private: true, reactome_version: 98,
    groups: [{ id: 'g1', name: 'Gate group', claims: [] }],
    records: [rec('pw-001', 'Gate path 1', ['c-neg']), rec('pw-002', 'Gate path 2', ['c-pos']), rec('pw-003', 'Gate path 3', ['c-neu']), rec('pw-004', 'Gate path 4', ['c-never']), rec('pw-005', 'Gate path 5', ['c-old']), rec('pw-006', 'Gate path 6', ['c-neg', 'c-older'])],
    claims: [cl('c-neg', 0.3, 'gatezinc', 'negative', 'negative'), cl('c-pos', 0.9, 'gatebean', 'positive', 'positive'), cl('c-neu', 0.8, 'gatezinc', 'neutral', 'neutral'),
             cl('c-never', 0.8, 'gatenever', 'negative', 'never'), cl('c-old', 0.8, 'gateold', 'negative', 'old'), cl('c-older', 0.5, 'gateolder', 'positive', 'older')],
    interactions: [], reference_intakes: { source: 'x', group: 'y', values: {} }, lexicon: { rules: [] }, sources: [] };
  var S = HT.state(), t = HT.todayKey();
  S.settings.stack = HT.normalizeStack([{ id: 'sz', added_on: HT.shiftDate(t, -40), added_basis: 'created', name: 'Gatezinc 50', kind: 'supplement', dose: 50, dose_unit: 'mg' }]);
  var food = function (n) { return { name: n, meal: 'lunch', time: '12:00', grams: 100, kcal: 100, protein_g: 5, fat_g: 1, carb_g: 10, fiber_g: 2, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }; };
  S.days[t] = { status: 'in_progress', water_l: 0, items: [food('Gatebean salad')] };
  S.days[HT.shiftDate(t, -28)] = { status: 'complete', water_l: 0, items: [food('Gateold stew')] };   // the 29th day back: outside the 28
  S.days[HT.shiftDate(t, -10)] = { status: 'complete', water_l: 0, items: [food('Gateolder bread')] };  // R332.1: an older, positive match
  S.current = t;
  window.__ticks = function (n) {
    S.timeline = S.timeline || {};
    for (var i = 0; i < 25; i++) { var dk = HT.shiftDate(t, -i); S.timeline[dk] = (S.timeline[dk] || []).filter(function (r) { return r.stackId !== 'sz'; });
      if (i < n) S.timeline[dk].push({ kind: 'medication', stackId: 'sz', name: 'Gatezinc 50', time: '08:00', source: 'stack', value: 50, unit: 'mg' }); }
    HT.resave(); HT.refresh(); return 1; };
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 16, sha256: hex, body: txt }));
  }).then(function (r) { window.__ticks(6); return { imported: r.ok }; });
})()
'@
  $fx2 = EvalA $mk2
  Write-Host ("  R331.1 fixture: " + $fx2)
  WaitQuiet 'balance fixture'
  $open = Eval "document.querySelector('[data-card=\""pathways\""] > details').open"
  if (-not $open) { $null = TapSel '[data-card="pathways"] > details > summary' }
  $DOTS = "Array.prototype.map.call(document.querySelectorAll('#pathways .pwdot'), function (d) { return d.getAttribute('data-pw') + ':' + ['pwdotpos', 'pwdotneg', 'pwdotzero'].filter(function (c) { return d.classList.contains(c); })[0] + ':' + d.getAttribute('data-size') + ':' + d.getAttribute('data-net'); }).sort().join(',')"
  $d6 = Eval $DOTS
  $col = Eval "(function(){ var tok = function (n) { var d = document.createElement('div'); d.style.color = 'var(' + n + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; }; var f = function (s) { var e = document.querySelector('#pathways .pwdot' + s); return e ? getComputedStyle(e).stroke : ''; }; return (f('.pwdotneg') === tok('--warn') ? 'neg=warn' : 'neg=' + f('.pwdotneg')) + '|' + (f('.pwdotpos') === tok('--good') ? 'pos=good' : 'pos=' + f('.pwdotpos')) + '|' + (f('.pwdotneg') !== tok('--bad') ? 'notred' : 'RED'); })()"
  $null = Eval "window.__ticks(7)"; WaitQuiet '7 ticks'
  $d7 = Eval $DOTS
  $null = Eval "window.__ticks(20)"; WaitQuiet '20 ticks'
  $d20 = Eval $DOTS
  Write-Host ("  dots at 6 / 7 / 20 ticks: " + $d6 + ' / ' + $d7 + ' / ' + $d20 + ' (' + $col + ')')
  Check (($fx2 -like '*"imported":true*') -and ($d6 -eq 'pw-001:pwdotneg:1:-1.8,pw-002:pwdotpos:1:0.9,pw-006:pwdotneg:1:-1.3')) "R331.1 DOTS MEAN SOMETHING LOGGED: a stack item ticked 6 days against a negative claim at 30 % (-1.8) and a food eaten today matching a positive one at 90 % (+0.9) draw a dot each; a NEUTRAL claim's pathway, one whose claim nothing logged matches, and a food 29 days back draw none"
  Check ($col -eq 'neg=warn|pos=good|notred') ("R331.1 COLOUR: the net for you is the green token, against you the R318 amber, never red (" + $col + ")")
  Check (($d7 -like 'pw-001:pwdotneg:2:-2.1,*') -and ($d20 -like 'pw-001:pwdotneg:3:-6,*')) "R331.1 SIZE: repeated small negatives build up -- the 30 % daily tick steps the dot from the smallest (6 ticks, -1.8) to the middle (7, -2.1) to the largest (20, -6.0)"
  # ---- R332.1: the list carries the same dots; the panel explains its dot ------------------------
  $null = TapSel '#pathways .pwgbtn[data-group="g1"]'
  $ld = EvalJ @'
(function () {
  var dir = function (e) { return ['pwdotpos', 'pwdotneg', 'pwdotzero'].filter(function (c) { return e.classList.contains(c); })[0] + ':' + e.getAttribute('data-size'); };
  var wheel = {}; Array.prototype.forEach.call(document.querySelectorAll('#pathways .pwdot'), function (d) { wheel[d.getAttribute('data-pw')] = dir(d); });
  var bad = [];
  Array.prototype.forEach.call(document.querySelectorAll('#pathways .pwglist .pwpick'), function (b) {
    var m = b.querySelector('.pwdotmkc'), id = b.getAttribute('data-pw');
    var got = m ? dir(m) : 'none', want = wheel[id] || 'none';
    if (got !== want) bad.push(id + ' list ' + got + ' wheel ' + want);
  });
  return { n: Object.keys(wheel).length, bad: bad };
})()
'@
  Write-Host ("  list dots: " + $ld)
  Check ($ld -like '{"n":3,"bad":`[`]}') "R332.1 LIST: each pathway button in the group's list carries the same dot as its wheel segment -- direction and size -- and a pathway with no dot carries none"
  $null = TapSel '#pathways .pwpick[data-pw="pw-001"]'
  $whyJs = @'
(function () {
  var w = document.querySelector('#pathways .pwpanel .pwwhydot');
  if (!w) return 'NONE';
  var dir = function (e) { return ['pwdotpos', 'pwdotneg', 'pwdotzero'].filter(function (c) { return e.classList.contains(c); })[0] + ':' + e.getAttribute('data-size'); };
  var pid = (document.querySelector('#pathways .pwpanel') || {}).getAttribute('data-pw');
  var mk = w.querySelector('.pwdotrow .pwdotmkc'), wd = document.querySelector('#pathways .pwdot[data-pw="' + pid + '"]');
  return w.innerText.replace(/\s+/g, ' ') + '|same:' + (mk && wd ? dir(mk) === dir(wd) : !mk && !wd)
    + '|signs:' + Array.prototype.map.call(w.querySelectorAll('.pwmatch'), function (li) { return li.getAttribute('data-sign') + '/' + dir(li.querySelector('.pwdotmkc')).split(':')[0]; }).join(',');
})()
'@
  $p1 = EvalJ $whyJs
  $null = TapSel '#pathways .pwpanel .pwdotrow'
  $hd = EvalJ "(function(){ var d = document.querySelector('#pathways .pwdot[data-pw=""pw-001""]'); return (d && d.classList.contains('pwhl')) + '|' + document.querySelector('#pathways .pwpanel .pwdotrow').getAttribute('aria-pressed'); })()"
  [void](Eval "(function(){ var p = document.querySelector('#pathways .pwpanel'); if (p) p.scrollIntoView({ block: 'center' }); return 1; })()")
  Shot 'balance-panel-light'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'dark' }) } | Out-Null; WaitQuiet 'dark'
  Shot 'balance-panel-dark'
  [void](Eval "(function(){ var w = document.querySelector('#pathways .pwwheel'); if (w) w.scrollIntoView({ block: 'start' }); return 1; })()")
  Shot 'balance-wheel-dark'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null; WaitQuiet 'light'
  Shot 'balance-wheel-light'
  $null = TapSel '#pathways .pwpanel .pwdotrow'
  $pt = EvalJ "(function(){ var d = document.querySelector('#pathways .pwdot[data-pw=""pw-001""]'), svg = d.ownerSVGElement; svg.scrollIntoView({ block: 'center' }); var b = svg.getBoundingClientRect(), k = b.width / Number(svg.getAttribute('width')); return { x: b.left + Number(d.getAttribute('cx')) * k, y: b.top + Number(d.getAttribute('cy')) * k }; })()"
  $ptv = $pt | ConvertFrom-Json
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $ptv.x; y = $ptv.y }) } | Out-Null
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
  WaitQuiet 'wheel tap'
  $hw = EvalJ "(function(){ var r = document.querySelector('#pathways .pwpanel .pwhlrow.pwhl'), d = document.querySelector('#pathways .pwdot[data-pw=""pw-001""]'); return (r ? r.getAttribute('data-hl') : '') + '|' + (d && d.classList.contains('pwhl')) + '|' + (document.querySelector('#pathways .pwpanel') || {}).getAttribute('data-pw'); })()"
  $null = TapSel '#pathways .pwpick[data-pw="pw-006"]'
  $p6 = EvalJ $whyJs
  $null = TapSel '#pathways .pwpick[data-pw="pw-002"]'
  $p2 = EvalJ $whyJs
  $null = TapSel '#pathways .pwpick[data-pw="pw-004"]'
  $p4 = EvalJ $whyJs
  Write-Host ("  why: " + $p1 + ' / ' + $p6 + ' / ' + $p2 + ' / ' + $p4 + ' / highlight ' + $hd + ' and ' + $hw)
  $m = [char]0x2212; $x = [char]0xD7; $d = [char]0xB7
  Check (($p1 -like ('*Leans against you ' + $d + ' last 28 days ' + $d + ' ' + $m + '6.0 Gatezinc 50 ' + $x + '20 (last *gate negative ' + $d + ' against you ' + $d + ' 30 % that gate negative holds ' + $d + ' GRADE low*effect not measured in you*|same:true|signs:neg/pwdotneg*')) -and ($p2 -like ('*Leans for you ' + $d + ' last 28 days ' + $d + ' +0.9 Gatebean salad ' + $x + '1 (last *gate positive ' + $d + ' for you ' + $d + ' 90 % that gate positive holds*|same:true|signs:pos/pwdotpos*'))) "R332.1 WHY THIS DOT: the panel opens with the wheel's own dot (same direction and size), which way it leans, the window and the net, then each match -- the item and times, the claim, a green or amber marker, for or against you, probability and GRADE"
  Check (($p6 -like '*signs:neg/pwdotneg,pos/pwdotpos*') -and ($p6 -like '*Gatezinc 50*Gateolder bread*') -and ($p4 -like '*Nothing you logged in the last 28 days matches a claim for this pathway.*|same:true|signs:*')) "R332.1: matches of both directions are listed newest first, each with its own marker (today's tick before a food 10 days back); a pathway with no dot says nothing logged matches"
  Check (($hd -like '*true|true*') -and ($hw -like '*dot|true|pw-001*')) "R332.1 TAP-HIGHLIGHT BOTH WAYS: a real tap on 'Why this dot' highlights the dot on the wheel; a real tap on the dot (its slice) highlights its row, the pathway still picked"
  $all = Eval "document.getElementById('pathways').innerText.replace(/\s+/g, ' ')"
  $info = Eval "(document.querySelector('#pathways .pwwheelinfo') || {}).textContent || ''"
  Check (($all -notmatch '(?i)\b(should|must|avoid|recommend|stop|start)\b') -and ($info -like '*Known share: the share of the food you logged in the last 28 days that carries a figure for this pathway*s raw materials. It measures coverage, not how well the pathway is supplied.*')) "R331.1 WORDS: no should, must, avoid, recommend, stop or start anywhere on the Pathways card; the wheel's i says what the known share is and that it measures coverage, not how well the pathway is supplied"

  # ---- R333: evidence levels, time tiers with a switch, from -> to links ---------------------------
  $mk3 = @'
(function () {
  localStorage.clear(); HT.boot();
  var rv = '2026-11-08';
  var pr = function (p, of) { return { current_version: 1, versions: [{ version: 1, p: p, of: of, kind: 'general' }] }; };
  var dir = function (d, sh) { return { direction: d, short: sh, reviewed_by_me: rv }; };
  var rec = function (id, claims) { return { id: id, plain_name: 'Gate path ' + Number(id.slice(3)), technical_name: id, group: 'g1', backbone: [], supply: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: claims }; };
  var cl = function (id, p, m, d, extra) { return Object.assign({ id: id, claim: 'Gate ' + id + ' claim.', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: pr(p, 'that ' + id + ' holds'), subject: { match: [m] }, for_me: dir(d, 'gate ' + id) }, extra || {}); };
  var own = function (res, n, ho, ok) { return { measured_in_me: { result: res, by: 'own data', n: n, held_out: ho, test: 'gate test', date: '2026-11-01', p: 0.72, reviewed_by_me: ok === false ? null : rv } }; };
  var panel = function (res) { return { measured_in_me: { result: res, by: 'blood panel', test: 'gate marker', date: '2026-11-01', reviewed_by_me: rv } }; };
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-11-08T10:00:00', private: true, reactome_version: 98,
    groups: [{ id: 'g1', name: 'Gate group', claims: [] }],
    records: [rec('pw-001', ['c-zinc']), rec('pw-002', ['c-bean']), rec('pw-003', ['c-bean2']), rec('pw-004', ['c-fill']), rec('pw-005', ['c-ring']), rec('pw-006', ['c-contra']),
              rec('pw-007', ['c-n4']), rec('pw-008', ['c-noho']), rec('pw-009', ['c-unapp']), rec('pw-010', ['c-fill', 'c-ring']), rec('pw-011', ['c-fill', 'c-n4']), rec('pw-012', ['c-fill', 'c-contra'])],
    claims: [cl('c-zinc', 0.3, 'gatezinc', 'negative'), cl('c-bean', 0.9, 'gatebean', 'positive'), cl('c-bean2', 0.5, 'gatebean', 'positive'),
             cl('c-fill', 0.6, 'gatefill', 'positive', own('agrees', 6, true)), cl('c-ring', 0.6, 'gatefill', 'positive', panel('agrees')), cl('c-contra', 0.6, 'gatefill', 'positive', own('disagrees', 8, true)),
             cl('c-n4', 0.6, 'gatefill', 'positive', own('agrees', 4, true)), cl('c-noho', 0.6, 'gatefill', 'positive', own('agrees', 9, false)), cl('c-unapp', 0.6, 'gatefill', 'positive', own('agrees', 9, true, false)),
             cl('c-link', 0.7, 'gatenone', 'positive', { link: { from: 'pw-001', to: 'pw-003', says: 'gate link says', reviewed_by_me: rv } }),
             cl('c-linkun', 0.7, 'gatenone', 'negative', { link: { from: 'pw-001', to: 'pw-002', says: 'gate unapproved link', reviewed_by_me: null } }),
             cl('c-linkneu', 0.7, 'gatenone', 'neutral', { link: { from: 'pw-001', to: 'pw-004', says: 'gate neutral link', reviewed_by_me: rv } })],
    tiers: { reviewed_by_me: rv, records: {}, references: { R1: { code: 'R1', citation: 'Gate A et al. A gate source. 2020. PMID 1' } } },
    interactions: [], reference_intakes: { source: 'x', group: 'y', values: {} }, lexicon: { rules: [] }, sources: [] };
  ['pw-001', 'pw-004', 'pw-005', 'pw-006', 'pw-007', 'pw-008', 'pw-009', 'pw-010', 'pw-011', 'pw-012'].forEach(function (id) { body.tiers.records[id] = { tier: 'fast', uncertain: false, qualifier: '', basis: 'Gate fast basis.', refs: ['R1'], verified: 'yes, abstract', kind: 'H' }; });
  body.tiers.records['pw-002'] = { tier: 'slow', uncertain: true, qualifier: 'uncertain', basis: 'Gate slow basis.', refs: ['R1'], verified: 'time scale NOT in abstract', kind: 'R' };
  var S = HT.state(), t = HT.todayKey();
  S.settings.stack = HT.normalizeStack([{ id: 'sz', added_on: HT.shiftDate(t, -40), added_basis: 'created', name: 'Gatezinc 50', kind: 'supplement', dose: 50, dose_unit: 'mg' }]);
  var food = function (n) { return { name: n, meal: 'lunch', time: '12:00', grams: 100, kcal: 100, protein_g: 5, fat_g: 1, carb_g: 10, fiber_g: 2, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }; };
  S.days = {};
  S.days[t] = { status: 'in_progress', water_l: 0, items: [food('Gatefill tonic')] };
  S.days[HT.shiftDate(t, -20)] = { status: 'complete', water_l: 0, items: [food('Gatebean salad')] };   // in slow's 90 and medium's 28, not fast's 7
  S.current = t;
  S.timeline = {};
  [0, 10].forEach(function (i) { S.timeline[HT.shiftDate(t, -i)] = [{ kind: 'medication', stackId: 'sz', name: 'Gatezinc 50', time: '08:00', source: 'stack', value: 50, unit: 'mg' }]; });
  HT.resave();
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 22, sha256: hex, body: txt }));
  }).then(function (r) { HT.refresh(); return { imported: r.ok }; });
})()
'@
  $fx3 = EvalA $mk3
  Write-Host ("  R333 fixture: " + $fx3)
  WaitQuiet 'R333 fixture'
  $open = Eval "document.querySelector('[data-card=\""pathways\""] > details').open"
  if (-not $open) { $null = TapSel '[data-card="pathways"] > details > summary' }
  $W3 = @'
(function () {
  var tok = function (n) { var d = document.createElement('div'); d.style.color = 'var(' + n + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; };
  var dots = Array.prototype.map.call(document.querySelectorAll('#pathways .pwdot'), function (d) {
    var cs = getComputedStyle(d);
    return d.getAttribute('data-pw') + ':' + d.getAttribute('data-ev') + ':' + d.getAttribute('data-net') + ':' + d.getAttribute('data-days') + ':' + (cs.fill === 'none' ? 'hollow' : (cs.fill === tok('--good') || cs.fill === tok('--warn') ? 'solid' : cs.fill));
  }).sort().join(',');
  var btns = Array.prototype.map.call(document.querySelectorAll('#pathways .pwtierbtn'), function (b) { var r = b.getBoundingClientRect(); return b.getAttribute('data-tier') + ':' + b.getAttribute('aria-pressed') + ':' + (r.height >= 44 && r.width >= 44 ? 'ok' : Math.round(r.height) + 'x' + Math.round(r.width)); }).join(',');
  var faded = document.querySelectorAll('#pathways .pwseg.pwfaded').length;
  return { tier: HT.pwWheelState().tier, btns: btns, dots: dots, faded: faded, rings: document.querySelectorAll('#pathways .pwsegs .pwdotring').length, strikes: document.querySelectorAll('#pathways .pwsegs .pwdotstrike').length };
})()
'@
  $tMed = EvalJ $W3
  $null = TapSel '#pathways .pwtierbtn[data-tier="fast"]'
  $tFast = EvalJ $W3
  [void](Eval "(function(){ var w = document.querySelector('#pathways .pwwheel'); if (w) w.scrollIntoView({ block: 'start' }); return 1; })()")
  Shot 'r333-fast-light'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'dark' }) } | Out-Null; WaitQuiet 'dark'
  Shot 'r333-fast-dark'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null; WaitQuiet 'light'
  $null = TapSel '#pathways .pwtierbtn[data-tier="slow"]'
  $tSlow = EvalJ $W3
  Write-Host ("  tiers: medium " + $tMed); Write-Host ("  fast " + $tFast); Write-Host ("  slow " + $tSlow)
  Check (($fx3 -like '*"imported":true*') -and ($tMed -like '*"tier":"medium","btns":"fast:false:ok,medium:true:ok,slow:false:ok","dots":"pw-003:science:0.5:28:hollow","faded":11,*')) "R333 TIERS: the wheel opens on Medium (three 44 px buttons); only the pathway with no cited time scale reads with it -- its dot counts a food 20 days back over 28 days -- and the 11 tiered pathways are faded with no dot"
  Check ($tFast -like '*"tier":"fast"*"dots":"pw-001:science:-0.3:7:hollow,pw-004:filled:0.6:7:solid,pw-005:ringed:0.6:7:solid,pw-006:contradicts:0.6:7:hollow,pw-007:science:0.6:7:hollow,pw-008:science:0.6:7:hollow,pw-009:science:0.6:7:hollow,pw-010:filled:1.2:7:solid,pw-011:science:1.2:7:hollow,pw-012:contradicts:1.2:7:hollow","faded":2,"rings":1,"strikes":2}') "R333 FAST + EVIDENCE LEVELS: Fast counts 7 days (today's tick, not the one 10 days back: -0.3); own data agreeing at n 6 with a held-out check is filled, a panel agreeing ringed, disagreeing struck; n 4, no held-out check or an unapproved check stay hollow; mixed dots: filled+ringed filled, filled+science hollow, filled+contradicted struck"
  Check ($tSlow -like '*"tier":"slow"*"dots":"pw-002:science:0.9:90:hollow","faded":11,*') "R333 SLOW: Slow counts 90 days -- the food 20 days back draws its dot; the other pathways are faded with no dot"
  # a pick moves the switch to the pathway's own tier; the panel says the time scale
  # (the wheel's state outlives HT.boot: an earlier section may have left g1 open, and a tap would close it)
  if ((Eval "HT.pwWheelState().group") -ne 'g1') { $null = TapSel '#pathways .pwgbtn[data-group="g1"]' }
  $null = TapSel '#pathways .pwtierbtn[data-tier="fast"]'
  $null = TapSel '#pathways .pwpick[data-pw="pw-002"]'
  $TP = "(function(){ var p = document.querySelector('#pathways .pwpanel .pwwhydot'); return HT.pwWheelState().tier + '|' + (document.querySelector('#pathways .pwtierbtn[aria-pressed=""true""]') || {}).getAttribute('data-tier') + '|' + (p ? p.innerText.replace(/\s+/g, ' ') : 'NONE'); })()"
  $pk2 = Eval $TP
  $null = TapSel '#pathways .pwpick[data-pw="pw-003"]'
  $pk3 = Eval $TP
  $null = TapSel '#pathways .pwpick[data-pw="pw-004"]'
  $pk4 = Eval $TP
  $null = TapSel '#pathways .pwpanel .pwtierinfo > summary'
  $ti = Eval "(document.querySelector('#pathways .pwpanel .pwtierinfo') || {}).innerText"
  $ld3 = EvalJ "(function(){ var bad = []; Array.prototype.forEach.call(document.querySelectorAll('#pathways .pwglist .pwpick'), function (b) { var id = b.getAttribute('data-pw'), m = b.querySelector('.pwdotmkc'), w = document.querySelector('#pathways .pwdot[data-pw=""' + id + '""]'); var g = m ? m.getAttribute('data-ev') : 'none', x = w ? w.getAttribute('data-ev') : 'none'; if (g !== x) bad.push(id + ' ' + g + '/' + x); }); return bad; })()"
  Write-Host ("  picks: " + $pk2 + ' / ' + $pk3 + ' / ' + $pk4 + ' / i ' + $ti + ' / list ' + $ld3)
  $d = [char]0xB7
  Check (($pk2 -like ('slow|slow|*Leans for you ' + $d + ' last 90 days ' + $d + ' +0.9*Timescale: slow (uncertain) ' + $d + ' its dot counts the last 90 days.*')) -and ($pk3 -like ('medium|medium|*Leans for you ' + $d + ' last 28 days*Timescale not cited ' + $d + ' its dot counts the last 28 days (Medium).*'))) "R333 PICK: picking a slow pathway while Fast is on moves the switch to Slow; the panel's dot counts 90 days and says 'Timescale: slow (uncertain)'; a pathway with no cited time scale moves it to Medium and says 'Timescale not cited'"
  Check (($pk4 -like ('fast|fast|*your data agrees (n 6, held-out check, calculated 72 %: gate test)*Timescale: fast*')) -and ($ti -like '*Gate fast basis.*Gate A et al. A gate source. 2020. PMID 1*Checked: yes, abstract*') -and ($ld3 -eq '[]')) "R333 PANEL: a match says its level in words ('your data agrees (n 6, held-out check, calculated 72 %...)'); the timescale's i gives its basis, citation and how it was checked; the list's dots carry the wheel's level"
  # lines: an approved from -> to link colours exactly its line, with an arrow; an unapproved one changes nothing
  $null = TapSel '#pathways .pwpick[data-pw="pw-001"]'
  $ln = EvalJ @'
(function () {
  var tok = function (n) { var d = document.createElement('div'); d.style.color = 'var(' + n + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; };
  var ch = Array.prototype.map.call(document.querySelectorAll('#pathways .pwchords .pwchord'), function (c) { var cs = getComputedStyle(c); return c.getAttribute('data-b') + ':' + (c.classList.contains('pwlinked') ? 'linked' : 'plain') + ':' + (cs.stroke === tok('--good') ? 'good' : cs.stroke) + ':' + cs.strokeDasharray; });
  var ar = Array.prototype.map.call(document.querySelectorAll('#pathways .pwchords .pwarrow'), function (a) { return a.getAttribute('data-b') + ':' + (getComputedStyle(a).fill === tok('--good') ? 'good' : getComputedStyle(a).fill); });
  var rows = Array.prototype.map.call(document.querySelectorAll('#pathways .pwpanel .pwlinerowwrap'), function (w) { return (w.getAttribute('data-link') || '-') + '=' + w.querySelector('.pwlinemean').innerText; });
  return { chords: ch, arrows: ar, rows: rows, rowArrow: document.querySelectorAll('#pathways .pwpanel .pwlinemk .pwarrow').length };
})()
'@
  Write-Host ("  links: " + $ln)
  [void](Eval "(function(){ var w = document.querySelector('#pathways .pwwheel'); if (w) w.scrollIntoView({ block: 'start' }); return 1; })()")
  Shot 'r333-link-light'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'dark' }) } | Out-Null; WaitQuiet 'dark'
  Shot 'r333-link-dark'
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null; WaitQuiet 'light'
  Check ($ln -like ('{"chords":`["pw-003:linked:good:none"`],"arrows":`["pw-003:good"`],"rows":`["pw-001>pw-003=Gate path 1 acts on Gate path 3: gate link says ' + $d + ' claim: Gate c-link claim. ' + $d + ' for you ' + $d + ' 70 % that c-link holds ' + $d + ' GRADE low ' + $d + ' science only: no measure of you yet"`],"rowArrow":1}')) "R333 LINES: an approved claim naming 'Gate path 1 acts on Gate path 3' draws that line -- with no other connection -- solid in the claim's green, an arrow at its 'to' end, its row saying the direction, the claim, for you, probability and GRADE; a link not yet approved draws no line, nor does an approved link on a neutral claim (R335.1)"
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
