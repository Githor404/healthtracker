# R313/A -- HOW THIS SUPPORTS YOUR PATHWAYS: one stack item, two cards never merged.
#
# PRE-REGISTERED (DECISIONS R313 part A), on a PLACEHOLDER pack built in the page (R204:
# items Item Z, Product Q, Food F): a real tap on the row link opens the view, from + Log
# and from Settings; card 1 shows the nutrient at the usual dose, its form and its
# pathways as chips, and a real tap on a chip opens the Pathways card at exactly that
# pathway; the 1 % floor (under, at, a line with no reference intake); a named-but-not-
# counted ingredient and a non-nutrient ingredient each get a row; card 2 shows reviewed
# claims only, a Safety sub-list and an Interactions sub-list -- an unreviewed interaction
# and one with no probability are not shown; no probability in card 1, no chip in card 2;
# the zinc intake note above 40 mg cites 40 mg and the IOM, collapsed; the banned words
# nowhere; 44 px; nothing sideways at 390 and 360.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8420
$Dbg = 9620
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-supports-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Emulation.setTimezoneOverride' @{ timezoneId = 'America/Toronto' } | Out-Null   # a fixed zone, so the fixture's times mean the same on any machine
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }


  $boot = Eval "typeof HT === 'object' && typeof HT.openStackSupport === 'function' && typeof HT.packImportText === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the view is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  function TapAt([double]$x, [double]$y) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap' }
  function TapSel([string]$sel) {
    $p = EvalJ ("(function(){ var e = document.querySelector('" + $sel + "'); if (!e) return null; e.scrollIntoView({ block: 'center' }); var r = e.getBoundingClientRect(); return { x: r.left + Math.min(r.width / 2, 120), y: r.top + r.height / 2 }; })()")
    if ($p -eq 'null' -or -not $p) { return $false }
    $q = $p | ConvertFrom-Json; TapAt $q.x $q.y; return $true }

  # ---- the fixture: a PLACEHOLDER pack (R204), built and fingerprinted in the page ---------
  $fx = EvalA @'
(function () {
  localStorage.clear(); HT.boot();
  var T = new Date('2026-11-03T09:00:00').getTime(); HT.setClock(function () { return T; });
  var P = function (p, of) { return { current_version: 1, versions: [{ version: 1, p: p, of: of, kind: 'general', producer: { model: 'm', date: '2026-11-01' }, approved: '2026-11-03' }] }; };
  var rv = '2026-11-03';
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-11-03T10:00:00', private: true, reactome_version: 98,
    groups: [{ id: 'energy', name: 'Group A', claims: [] }, { id: 'glucose', name: 'Group B', claims: [] }, { id: 'fats', name: 'Group C', claims: [] }],
    records: [
      { id: 'pw-001', plain_name: 'Path A1', technical_name: 'Path one', group: 'energy', backbone: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: [],
        supply: [{ cofactor: 'zinc', dri: 'zinc', key: 'zinc_mg', slot: '309', tracked: true }] },
      { id: 'pw-002', plain_name: 'Path B1', technical_name: 'Path two', group: 'glucose', backbone: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: [],
        supply: [{ cofactor: 'iron', dri: 'iron', key: 'iron_mg', slot: '303', tracked: true }, { cofactor: 'compound n (claimed)', dri: null, key: null, slot: null, tracked: false }] },
      { id: 'pw-003', plain_name: 'Path C1', technical_name: 'Path three', group: 'fats', backbone: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: [],
        supply: [{ cofactor: 'fat x (ligand)', dri: null, key: null, slot: '617', tracked: true }] }],
    claims: [
      { id: 'claim-a', claim: 'Placeholder claim A.', subject: { match: ['compound q'] }, reviewed_by_me: rv, evidence: { grade: 'low', human: true }, probability: P(0.6, 'that placeholder A holds'), attributions: [{ source: 'src-a', kind: 'quote' }], pathways: ['pw-002'] },
      { id: 'claim-s', claim: 'Placeholder safety S.', safety: true, subject: { match: ['compound q'] }, reviewed_by_me: rv, evidence: { grade: 'very low', human: true }, probability: P(0.85, 'that placeholder S can happen'), attributions: [] },
      { id: 'claim-u', claim: 'Unreviewed placeholder U.', subject: { match: ['compound q'] }, reviewed_by_me: null, evidence: { grade: 'low' }, probability: P(0.5, 'that U holds'), attributions: [] }],
    interactions: [
      { id: 'int-ok', record_type: 'interaction', match: ['zinc'], subject: { name: 'element y status' }, modifier: { name: 'zinc taken as a supplement' }, direction: 'lowers', reviewed_by_me: rv, evidence: { grade: 'low' }, probability: P(0.8, 'that placeholder zinc lowers element y'), attributions: [{ source: 'src-a', kind: 'quote' }] },
      { id: 'int-np', record_type: 'interaction', match: ['zinc'], subject: { name: 'no probability here' }, modifier: { name: 'zinc' }, direction: 'changes', reviewed_by_me: rv, evidence: { grade: 'low' }, attributions: [] },
      { id: 'int-un', record_type: 'interaction', match: ['zinc'], subject: { name: 'unreviewed thing' }, modifier: { name: 'zinc' }, direction: 'raises', reviewed_by_me: null, evidence: { grade: 'low' }, probability: P(0.7, 'that unreviewed holds'), attributions: [] }],
    reference_intakes: { source: 'Source R', group: 'group G', values: {
      zinc: { label: 'Zinc', value: 10, unit: 'mg', kind: 'RDA', key: 'zinc_mg', slot: '309', slot_factor: 1 },
      iron: { label: 'Iron', value: 8, unit: 'mg', kind: 'RDA', key: 'iron_mg', slot: '303', slot_factor: 1 } } },
    lexicon: { rules: [] },
    sources: [{ id: 'src-a', authors: 'Author A et al.', venue: 'Journal A', year: 2020 }] };
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 9, sha256: hex, body: txt }));
  }).then(function (r) {
    HT.state().settings.stack = [
      { id: 'sz', name: 'Item Z', kind: 'supplement', enabled: true, dose: 1, dose_unit: 'tablet', added_on: '2026-10-01', added_basis: 'added',
        nutrients: { micros: { zinc_mg: 45, iron_mg: 0.04 }, detail: { zinc_mg: { amount: 45, unit: 'mg', per: 'unit', form: 'Form Z', source: 'lnhpd' } } },
        product: { ns: 'lnhpd', npn: '80000010', id: '10', name: 'Item Z', status: 'active', dosage_form: 'Tablet', ingredients: [{ name: 'Zinc', amount: 45, unit: 'mg', form: 'Form Z' }] } },
      { id: 'sq', name: 'Product Q', kind: 'supplement', enabled: true, dose: 2, dose_unit: 'capsule', added_on: '2026-10-01', added_basis: 'added',
        product: { ns: 'lnhpd', npn: '80000009', id: '9', name: 'Product Q', status: 'active', dosage_form: 'Capsule',
          ingredients: [{ name: 'Compound Q', amount: 100, unit: 'mg', form: 'Root' }, { name: 'Compound N', amount: 2, unit: 'mg' }] } },
      { id: 'sf', name: 'Food F', kind: 'food', enabled: true, added_on: '2026-10-01', added_basis: 'added',
        part: { name: 'Row F', grams: 10, kcal: 1, protein_g: 0, fat_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0, ref: { ns: 'cnf', id: '1', name: 'Row F', v: { '617': 0.001, '303': 0.08 } } } }];
    HT.resave(); HT.refresh();
    return { imported: r.ok,
      under: HT.ctxSupplies([{ name: 'x', ref: { v: { '303': 0.079 } } }]), at: HT.ctxSupplies([{ name: 'x', ref: { v: { '303': 0.08 } } }]),
      nori: HT.ctxSupplies([{ name: 'x', ref: { v: { '617': 0.0001 } } }]), zero: HT.ctxSupplies([{ name: 'x', ref: { v: { '617': 0 } } }]) };
  });
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"imported":true*')) { Write-Host "ERROR: the placeholder pack did not import"; Cleanup; exit 2 }
  Check (($fx.Contains('"under":[]')) -and ($fx.Contains('"at":["pw-002"]')) -and ($fx.Contains('"nori":["pw-003"]')) -and ($fx.Contains('"zero":[]'))) "the floor in the strip's own rule: 0.079 mg of iron against an 8 mg intake supplies nothing, 0.08 mg (1 %) supplies; a line with no reference intake counts any amount above zero, and zero is nothing"

  # ---- + Log: the row's link, a real tap ------------------------------------------------------
  $null = EvalJ "(function(){ HT.openSheet('root'); HT.stackOpen(); return 1; })()"
  WaitQuiet 'the stack open'
  $rl = EvalJ "(function(){ var b = document.querySelector('#sheetRoot .stksupport[data-stack=sz]'); return b ? { text: b.textContent, h: Math.round(b.getBoundingClientRect().height), old: document.querySelectorAll('.stkclaims').length } : null; })()"
  Write-Host ("  + Log link: " + $rl)
  Check (($rl -like ('*"text":"How this supports your pathways ' + [char]0x203A + '"*')) -and ($rl -like '*"old":0*') -and ([int](($rl | ConvertFrom-Json).h) -ge 44)) "+ Log's stack row carries 'How this supports your pathways (arrow)', 44 px, and R305's collapsed linked-claims line is gone"
  $t1 = TapSel '#sheetRoot .stksupport[data-stack=\"sz\"]'
  $v1 = EvalJ @'
(function () {
  var p = document.getElementById('supportPanel');
  var c1 = p.querySelector('.supsupply'), c2 = p.querySelector('.supclaims');
  var note = c1 ? c1.querySelector('details.iflag') : null;
  return { shown: getComputedStyle(p).display !== 'none', head: p.querySelector('.supitem').textContent,
    c1: c1 ? c1.textContent : '', c2: c2 ? c2.textContent : '', chips: Array.prototype.map.call(c1.querySelectorAll('.pwchip'), function (b) { return b.getAttribute('data-pw'); }),
    c1prob: /\d+ % that/.test(c1.textContent) || !!c1.querySelector('.clmline'), c2chip: !!c2.querySelector('.pwchip'),
    noteOpen: note ? note.open : null, noteText: note ? note.querySelector('.iflagbody').textContent : '' };
})()
'@
  Write-Host ("  view (Item Z): " + $v1)
  $v = $v1 | ConvertFrom-Json
  Check ($t1 -and $v.shown -and ($v.head -like '*Item Z*Supplement*1 tablet*NPN 80000010*')) "a real tap on the link opens the full-screen view at the item: its name, kind and usual dose"
  Check (($v.c1 -like ('*Supplies ' + [char]0x00B7 + ' 1 pathway*Supplying is not activating.*Zinc 45 mg*(form z)*')) -and ((@($v.chips) -join ',') -eq 'pw-001')) "card 1: the nutrient at the usual dose, its form, and the pathway it supplies as a chip"
  Check ($v.c1 -like '*Iron 0.04 mg*under 1 % of the reference intake per serving; not counted as supplying.*') "card 1: a nutrient under 1 % of the reference intake per serving is a dimmed row that says it is not counted as supplying"
  Check (($v.noteOpen -eq $false) -and ($v.noteText -like '*45 mg*Institute of Medicine*40 mg*food, water and supplements*')) "card 1: the item's intake note, collapsed, cites 40 mg, the Institute of Medicine and its total-intake scope ($($v.noteText))"
  Check (($v.c2 -like ('*Linked claims ' + [char]0x00B7 + ' 0*Interactions ' + [char]0x00B7 + ' 1*Zinc taken as a supplement lowers element y status.*80 % that placeholder zinc lowers element y*GRADE low*Author A et al., Journal A, 2020*')) -and -not ($v.c2 -like '*no probability here*') -and -not ($v.c2 -like '*unreviewed thing*')) "card 2: the reviewed interaction with a probability under its own heading; one with no probability and an unreviewed one are not shown"
  Check ((-not $v.c1prob) -and (-not $v.c2chip)) "the two cards never merge: no probability in card 1, no supply chip in card 2"

  # ---- a chip, a real tap -------------------------------------------------------------------
  $t2 = TapSel '#supportPanel .pwchip[data-pw=\"pw-001\"]'
  $cp = EvalJ @'
(function () {
  var card = document.querySelector('[data-card="pathways"] > details');
  var rec = document.querySelector('#pathways .pwrec.pwmark');
  var marked = Array.prototype.map.call(document.querySelectorAll('#pathways .pwrec.pwmark'), function (r) { return r.getAttribute('data-pw'); });
  return { panel: getComputedStyle(document.getElementById('supportPanel')).display, sheet: getComputedStyle(document.getElementById('entrySheet')).display,
    card: !!(card && card.open), marked: marked, groupOpen: !!(rec && rec.closest('details.pwgroup').open) };
})()
'@
  Write-Host ("  after the chip: " + $cp)
  Check ($t2 -and ($cp -like '*"panel":"none"*') -and ($cp -like '*"sheet":"none"*') -and ($cp -like '*"card":true*') -and ($cp.Contains('"marked":["pw-001"]')) -and ($cp -like '*"groupOpen":true*')) "a real tap on a chip closes the view and + Log and opens the Pathways card at exactly that pathway"

  # ---- Settings: the ingredient rows and the claims -------------------------------------------
  $null = EvalJ "(function(){ HT.openSettings(); return 1; })()"
  WaitQuiet 'settings'
  # the stack list sits in a collapsed Settings section, as it does for the user: opened first
  $t3o = TapSel '#settingsPanel details:has(.stksupport[data-stack=\"sq\"]) > summary'
  $t3 = TapSel '#settingsPanel .stksupport[data-stack=\"sq\"]'
  $v2 = EvalJ @'
(function () {
  var p = document.getElementById('supportPanel');
  var c1 = p.querySelector('.supsupply'), c2 = p.querySelector('.supclaims');
  var safety = c2.querySelector('.supsafety');
  return { shown: getComputedStyle(p).display !== 'none', c1: c1.textContent, c2: c2.textContent,
    safety: safety ? safety.textContent : '', safetyHead: safety ? getComputedStyle(safety.querySelector('.supsubh')).color : '',
    warn: getComputedStyle(document.documentElement).getPropertyValue('--warn').trim(), bad: getComputedStyle(document.documentElement).getPropertyValue('--bad').trim(),
    filed: Array.prototype.map.call(c2.querySelectorAll('.clmpw'), function (b) { return b.textContent; }), page: document.body.textContent.indexOf('Unreviewed placeholder U') >= 0 };
})()
'@
  Write-Host ("  view (Product Q): " + $v2)
  $w = $v2 | ConvertFrom-Json
  Check ($t3o -and $t3 -and $w.shown -and ($w.c1 -like ('*Supplies ' + [char]0x00B7 + ' 0 pathways*Compound N 4 mg*not counted*Path B1*')) -and ($w.c1 -like '*Compound Q (root) 200 mg*not a nutrient; supplies no pathway.*')) "from Settings, a real tap opens the view: a licensed ingredient named on an untracked raw-material line says which pathway lists it; one that is not a nutrient says so; amounts at the usual dose"
  Check (($w.c2 -like ('*Linked claims ' + [char]0x00B7 + ' 1*Placeholder claim A.*60 % that placeholder A holds*GRADE low*')) -and ((@($w.filed) -join ',') -eq ('Path B1 ' + [char]0x203A)) -and ($w.safety -like ('Safety ' + [char]0x00B7 + ' 1*Placeholder safety S.*85 % that placeholder S can happen*'))) "card 2: the reviewed claim with the pathway it is filed under, then the safety entry in its own sub-list"
  Check (($w.page -eq $false) -and ($w.c2 -notlike '*Unreviewed placeholder U*')) "the unreviewed claim naming the same compound shows nowhere"
  $rgbWarn = EvalJ "(function(){ var d = document.createElement('div'); d.style.color = 'var(--warn)'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.style.color = 'var(--bad)'; var b = getComputedStyle(d).color; d.remove(); return { warn: c, bad: b }; })()"
  $rw = $rgbWarn | ConvertFrom-Json
  Check (($w.safetyHead -eq $rw.warn) -and ($w.safetyHead -ne $rw.bad)) "the Safety heading is in the warn colour, never red ($($w.safetyHead))"

  # ---- the Food item: a no-intake line and a line at exactly 1 % -------------------------------
  $null = EvalJ "(function(){ HT.closeStackSupport(); return HT.openStackSupport('sf'); })()"
  WaitQuiet 'food view'
  $v3 = EvalJ "(function(){ var c1 = document.querySelector('#supportPanel .supsupply'); return { t: c1.textContent, chips: Array.prototype.map.call(c1.querySelectorAll('.pwchip'), function (b) { return b.getAttribute('data-pw'); }).sort() }; })()"
  Write-Host ("  view (Food F): " + $v3)
  Check (($v3 -like ('*Supplies ' + [char]0x00B7 + ' 2 pathways*')) -and ($v3 -like '*no reference intake*') -and ($v3.Contains('"chips":["pw-002","pw-003"]'))) "a Food at its grams: a line with no reference intake counts and says so; iron at exactly 1 % of the intake supplies"

  # ---- the words, and the layout at 390 and 360 ------------------------------------------------
  $lay = @()
  foreach ($wd in 390, 360) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wd; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    foreach ($id in 'sz', 'sq', 'sf') {
      $null = EvalJ ("(function(){ return HT.openStackSupport('" + $id + "'); })()")
      WaitQuiet 'layout'
      $lay += EvalJ @'
(function () {
  var p = document.getElementById('supportPanel'), w = p.querySelector('.wrap');
  var small = Array.prototype.filter.call(p.querySelectorAll('button, summary'), function (e) { var r = e.getBoundingClientRect(); return r.height > 0 && r.height < 44; }).length;
  var wide = Array.prototype.filter.call(p.querySelectorAll('*'), function (e) { var r = e.getBoundingClientRect(); return r.width > 0 && r.right > window.innerWidth + 0.5; }).length;
  return { w: window.innerWidth, small: small, wide: wide, side: w.scrollWidth - w.clientWidth, page: document.documentElement.scrollWidth - window.innerWidth, bad: (p.textContent.match(/\b(effects?|works|activates?)\b/gi) || []) };
})()
'@
    }
  }
  Write-Host ("  layout: " + ($lay -join ' '))
  Check (-not ($lay | Where-Object { -not (($_ -like '*"small":0*') -and ($_ -like '*"wide":0*') -and ($_ -like '*"side":0*') -and ($_ -like '*"page":0*')) })) "every control in the view is 44 px and nothing runs or scrolls sideways at 390 and 360"
  Check (-not ($lay | Where-Object { -not ($_.Contains('"bad":[]')) })) "the words 'effects', 'works' and 'activates' appear nowhere in the view ('Supplying is not activating' is the one allowed line)"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("SUPPORTS GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "SUPPORTS GATE: PASS -- a stack item's view keeps what it supplies and what studies claim apart, with the floor, the intake note, safety and interactions"
Write-Host "GATE: PASS"
exit 0
