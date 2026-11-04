# R313/B -- THE CONNECTIONS LAYER inside a pathway's i: two cards, never merged.
#
# PRE-REGISTERED (DECISIONS R313 part B), on a PLACEHOLDER pack built in the page (R204): a
# real tap on a pathway's i shows "Connected . effect not measured" then "Claims . effect
# with probability"; the connected rows are the pack's own, in order, then the literature
# link; a neighbour missing from the pack is not drawn; "shares" in plain names, three and
# "N more"; the literature row names its source; the count not shown is stated; no
# probability or GRADE in the connected card and no connection in the claims card; the
# literature link on both ends; a pathway with none says so; a real tap on a row opens that
# pathway's group and i, marked; 44 px rows, nothing sideways at 390 and 360; no pathway
# said to be active or measured; a pack with no connections shows no connected card.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8421
$Dbg = 9621
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-connect-" + [System.Guid]::NewGuid().ToString('N'))
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

  $boot = Eval "typeof HT === 'object' && typeof HT.pwStep === 'function' && typeof HT.packImportText === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the connections are not on HT"; Cleanup; exit 2 }
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or linked claims are not on HT"; Cleanup; exit 2 }
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
  # ---- the fixture: a PLACEHOLDER pack (R204) with a connections layer, built in the page -----
  $mk = @'
window.__mkPack = function (withConn) {
  var P = function (p, of) { return { current_version: 1, versions: [{ version: 1, p: p, of: of, kind: 'general', producer: { model: 'm', date: '2026-11-03' }, approved: '2026-11-03' }] }; };
  var rv = '2026-11-03';
  var rec = function (id, name, g, claims) { return { id: id, plain_name: name, technical_name: name + ' tech', group: g, backbone: [{ source: 'Reactome', version: 98, id: 'R-HSA-' + id.slice(3) }], supply: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: rv, claims: claims || [] }; };
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-11-03T10:00:00', private: true, reactome_version: 98,
    groups: [{ id: 'energy', name: 'Group A', claims: [] }, { id: 'glucose', name: 'Group B', claims: [] }],
    records: [rec('pw-001', 'Path A1', 'energy', ['claim-a']), rec('pw-002', 'Path A2', 'energy'), rec('pw-003', 'Path A3', 'energy'), rec('pw-004', 'Path A4', 'energy'),
              rec('pw-005', 'Path B1', 'glucose'), rec('pw-006', 'Path B2', 'glucose'), rec('pw-007', 'Path B3', 'glucose')],
    claims: [{ id: 'claim-a', claim: 'Placeholder claim A.', reviewed_by_me: rv, evidence: { grade: 'low', human: true }, probability: P(0.6, 'that placeholder A holds'), attributions: [{ source: 'src-a', kind: 'quote' }], pathways: ['pw-001'] }],
    interactions: [], reference_intakes: { source: 'x', group: 'y', values: {} }, lexicon: { rules: [] },
    sources: [{ id: 'src-a', authors: 'Author A et al.', venue: 'Journal A', year: 2020 }, { id: 'src-l', authors: 'Author L et al.', venue: 'Journal L', year: 2001 }] };
  if (withConn) body.connections = { reactome_version: 98, licence: 'CC0', rule: 'r', names: { proteins: { PROT1: { plain: 'Plain one' } } }, records: {
      'pw-001': { n: 8, shown: [
        { id: 'pw-099', score: 9, proteins: ['GONE'], molecules: [] },
        { id: 'pw-002', score: 4, proteins: [], molecules: ['2-trans,6-trans-farnesyl diphosphate(3-)'] },
        { id: 'pw-003', score: 3, proteins: ['PROT1', 'PROT2'], molecules: ['m1(2-)', 'm2'] },
        { id: 'pw-005', score: 2, proteins: ['PROT3'], molecules: [] },
        { id: 'pw-006', score: 1, proteins: [], molecules: ['m3'] },
        { id: 'pw-004', score: 0.5, proteins: [], molecules: ['m4(1-)'] }] },
      'pw-004': { n: 0, shown: [] } },
    literature: [{ a: 'pw-001', b: 'pw-007', says: 'placeholder link L', ruled: 'x', sources: ['src-l'], quotes: [] },
                 { a: 'pw-005', b: 'pw-001', says: 'placeholder link M', ruled: 'x', sources: [], quotes: [] }] };
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 10, sha256: hex, body: txt }));
  });
};
(function () { localStorage.clear(); HT.boot(); return window.__mkPack(true).then(function (r) { HT.refresh(); return { imported: r.ok }; }); })()
'@
  $fx = EvalA $mk
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"imported":true*')) { Write-Host "ERROR: the placeholder pack did not import"; Cleanup; exit 2 }
  $open = @'
(function (id) {
  var card = document.querySelector('[data-card="pathways"] > details'); if (card) card.open = true;
  var r = document.querySelector('#pathways .pwrec[data-pw="' + id + '"]'); r.closest('details.pwgroup').open = true;
  return 1;
})
'@
  $read = @'
(function (id) {
  var r = document.querySelector('#pathways .pwrec[data-pw="' + id + '"]'), info = r.querySelector('details.pwinfo');
  var cn = info.querySelector('.pwconnected'), cl = info.querySelector('.pwclaims');
  var kids = Array.prototype.slice.call(info.querySelectorAll('.pwcard'));
  return { open: info.open, conn: cn ? cn.innerText.replace(/\s+/g, ' ') : null, claims: cl ? cl.innerText.replace(/\s+/g, ' ') : null,
    order: kids.map(function (k) { return k.classList.contains('pwconnected') ? 'conn' : 'claims'; }),
    to: cn ? Array.prototype.map.call(cn.querySelectorAll('.pwconn'), function (b) { return b.getAttribute('data-to'); }) : [],
    via: cn ? Array.prototype.map.call(cn.querySelectorAll('.pwconnvia'), function (b) { return b.textContent; }) : [],
    connProb: cn ? (/\d+ %|GRADE/.test(cn.innerText)) : null, claimsConn: cl ? !!cl.querySelector('.pwconn') : null };
})
'@
  $null = EvalJ ($open + "('pw-001')")
  $t1 = TapSel '#pathways .pwrec[data-pw=\"pw-001\"] details.pwinfo > summary'
  $a1 = EvalJ ($read + "('pw-001')")
  Write-Host ("  pw-001: " + $a1)
  $a = $a1 | ConvertFrom-Json
  Check ($t1 -and $a.open -and ((@($a.order) -join ',') -eq 'conn,claims') -and ($a.conn -like ('CONNECTED ' + [char]0x00B7 + ' EFFECT NOT MEASURED*Reactome 98 (CC0)*does not say a change in one reaches the other*')) -and ($a.claims -like ('CLAIMS ' + [char]0x00B7 + ' EFFECT WITH PROBABILITY*'))) "a real tap on a pathway's i shows two cards, in order: 'Connected . effect not measured' (Reactome 98, CC0, and what a connection does not say), then 'Claims . effect with probability'"
  Check (((@($a.to) -join ',') -eq 'pw-002,pw-003,pw-005,pw-006,pw-004,pw-007') -and ($a.conn -notlike '*GONE*')) "the connected rows are the pack's own, in its order (most specific first), then the literature link; a neighbour missing from the pack is not drawn ($(@($a.to) -join ','))"
  Check (($a.via[0] -eq 'shares farnesyl diphosphate') -and ($a.via[1] -eq 'shares Plain one, PROT2, m1 and 1 more') -and ($a.via[5] -eq ('literature: placeholder link L ' + [char]0x2014 + ' Author L et al., Journal L, 2001'))) "each row says what is shared in plain names -- a protein by the pack's name (its symbol where the pack has none), a molecule without its charge and stereo locants -- at most three and 'N more'; a literature link says so and names its source"
  Check (($a.via[2] -eq 'shares PROT3; literature: placeholder link M') -and ((@($a.to) | Where-Object { $_ -eq 'pw-005' }).Count -eq 1)) "R318/1.6: ONE ROW PER CONNECTED PATHWAY -- a neighbour also linked by the literature appears once, its literature reason merged into its row"
  $tk = Eval "(function(){ var t = document.querySelector('#pathways .pwrec[data-pw=pw-001] .pwconnected .pwtechids'); return t ? t.textContent : ''; })()"
  Check (($tk -like '*Path A3: proteins PROT1, PROT2; molecules m1(2-), m2*') -and -not (($a.via -join ' ') -like '*m1(2-)*')) "R318/1.6: the technical IDs -- gene symbols, Reactome's molecule names -- sit behind the connected card's own i, not in its rows"
  Check ($a.conn -like '*3 more connected, not shown: the 5 sharing the most specific participants are.*') "more neighbours than shown: the count not shown is stated"
  Check (($a.connProb -eq $false) -and ($a.claimsConn -eq $false) -and ($a.claims -like '*Placeholder claim A.*60 % that placeholder A holds*GRADE low*')) "the two cards never merge: no probability or GRADE in the connected card, no connection in the claims card, which keeps the claim with its probability"

  # ---- the literature link reads from both ends; a record with none says so -------------------
  $null = EvalJ ("(function(){ document.querySelectorAll('#pathways details.pwinfo').forEach(function (d) { d.open = true; }); return 1; })()")
  $b7 = EvalJ ($read + "('pw-007')"); $b4 = EvalJ ($read + "('pw-004')")
  Write-Host ("  pw-007: " + $b7); Write-Host ("  pw-004: " + $b4)
  Check (($b7.Contains('"to":["pw-001"]')) -and ($b7 -like '*literature: placeholder link L*') -and ($b4 -like '*No connection by the rule*')) "a literature link shows on both of its pathways; a pathway with no connection by the rule says so"

  # ---- a real tap on a connection --------------------------------------------------------------
  $null = EvalJ "(function(){ HT.renderPathways(); return 1; })()"
  $null = EvalJ ($open + "('pw-001')")
  $null = TapSel '#pathways .pwrec[data-pw=\"pw-001\"] details.pwinfo > summary'
  $t2 = TapSel '#pathways .pwrec[data-pw=\"pw-001\"] .pwconn[data-to=\"pw-005\"]'
  $c2 = EvalJ "(function(){ var r = document.querySelector('#pathways .pwrec[data-pw=pw-005]'); return { group: r.closest('details.pwgroup').open, mark: r.classList.contains('pwmark'), info: r.querySelector('details.pwinfo').open, marked: document.querySelectorAll('#pathways .pwmark').length }; })()"
  Write-Host ("  after the tap: " + $c2)
  Check ($t2 -and ($c2 -like '*"group":true*"mark":true*"info":true*"marked":1*')) "a real tap on a connection opens that pathway's group and its i, the pathway marked"

  # ---- the layout -----------------------------------------------------------------------------
  $lay = @()
  foreach ($wd in 390, 360) {
    Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $wd; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
    $null = EvalJ "(function(){ HT.renderPathways(); var c = document.querySelector('[data-card=pathways] > details'); c.open = true; document.querySelectorAll('#pathways details').forEach(function (d) { d.open = true; }); return 1; })()"
    WaitQuiet 'layout'
    $lay += EvalJ @'
(function () {
  var p = document.getElementById('pathways');
  var small = Array.prototype.filter.call(p.querySelectorAll('.pwconn'), function (e) { var r = e.getBoundingClientRect(); return r.height > 0 && r.height < 44; }).length;
  var wide = Array.prototype.filter.call(p.querySelectorAll('.pwcard, .pwcard *'), function (e) { var r = e.getBoundingClientRect(); return r.width > 0 && r.right > window.innerWidth + 0.5; }).length;
  var t = p.innerText.replace(/effect not measured/gi, '');
  return { w: window.innerWidth, small: small, wide: wide, page: document.documentElement.scrollWidth - window.innerWidth, words: (t.match(/\b(active|activity|measured|measures|activates?)\b/ig) || []) };
})()
'@
  }
  Write-Host ("  layout: " + ($lay -join ' '))
  Check (-not ($lay | Where-Object { -not (($_ -like '*"small":0*') -and ($_ -like '*"wide":0*') -and ($_ -like '*"page":0*')) })) "every connection row is a 44 px target and nothing runs sideways at 390 and 360"
  Check (-not ($lay | Where-Object { -not ($_.Contains('"words":[]')) })) "no pathway is said to be active or measured: the one allowed phrase is the card's own 'effect not measured'"

  # ---- an old pack, with no connections --------------------------------------------------------
  $old = EvalA "(function(){ return window.__mkPack(false).then(function (r) { HT.renderPathways(); document.querySelectorAll('#pathways details').forEach(function (d) { d.open = true; }); return { ok: r.ok, conn: document.querySelectorAll('#pathways .pwconnected').length, claims: document.querySelectorAll('#pathways .pwclaims').length }; }); })()"
  Write-Host ("  old pack: " + $old)
  Check (($old -like '*"ok":true*"conn":0*') -and -not ($old -like '*"claims":0*')) "a pack with no connections layer shows no connected card, and its claims as before"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("CONNECT GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "CONNECT GATE: PASS -- a pathway's i keeps what it shares (no effect claimed) apart from what studies claim"
Write-Host "GATE: PASS"
exit 0
