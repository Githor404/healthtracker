# R305/3 -- LINKED CLAIMS ON THE STACK ITEM.
#
# PRE-REGISTERED (DECISIONS R305/3), on a PLACEHOLDER pack built in the page (R204: item
# names Item A / Item C): a non-nutrient item shows "supplies no nutrients . linked to 1
# claim"; a real tap opens the claim with its probability, GRADE and source; a planted
# unreviewed claim naming the same item never shows; an item with nutrients shows its
# claims below them; the strip after a tick shows the count and its link opens them; a
# group-level claim shows on the group's i; never "effects" or "works"; 44 px; nothing
# sideways.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8414
$Dbg = 9614
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-claims-" + [System.Guid]::NewGuid().ToString('N'))
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


  $boot = Eval "typeof HT === 'object' && typeof HT.stackClaims === 'function' && typeof HT.packImportText === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or linked claims are not on HT"; Cleanup; exit 2 }
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
  var T = new Date('2026-10-28T09:00:00').getTime(); HT.setClock(function () { return T; });
  var P = function (p, of) { return { current_version: 1, versions: [{ version: 1, p: p, of: of, kind: 'general', producer: { model: 'm', date: '2026-10-31' }, approved: '2026-10-31' }] }; };
  var body = { format: 'healthtracker-pack', schema: 1, built_at: '2026-10-31T10:00:00', private: true, reactome_version: 98,
    groups: [{ id: 'energy', name: 'Group A', claims: ['claim-g'] }, { id: 'glucose', name: 'Group B', claims: [] }],
    records: [{ id: 'pw-001', plain_name: 'Path A1', technical_name: 'Path one', group: 'energy', backbone: [], supply: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: '2026-10-29', claims: [] },
              { id: 'pw-002', plain_name: 'Path B1', technical_name: 'Path two', group: 'glucose', backbone: [], supply: [], observable: 'not observable', observable_how: '', sentence: 'A sentence.', reviewed_by_me: '2026-10-29', claims: [] }],
    claims: [
      { id: 'claim-a', claim: 'Placeholder claim A.', subject: { stack_item: 'Item A', compound: 'compound a' }, reviewed_by_me: '2026-10-31', evidence: { grade: 'low', human: true }, probability: P(0.6, 'that placeholder A holds'), attributions: [{ source: 'src-a', kind: 'quote' }] },
      { id: 'claim-b', claim: 'Unreviewed placeholder B.', subject: { stack_item: 'item a ' }, reviewed_by_me: null, evidence: { grade: 'low' }, probability: P(0.5, 'that B holds'), attributions: [] },
      { id: 'claim-c', claim: 'Placeholder claim C.', subject: { stack_item: 'Item C' }, reviewed_by_me: '2026-10-31', evidence: { grade: 'moderate', human: false }, probability: P(0.3, 'that placeholder C holds'), attributions: [{ source: 'src-a', kind: 'quote' }] },
      { id: 'claim-g', claim: 'Placeholder group claim G.', reviewed_by_me: '2026-10-31', evidence: { grade: 'low' }, probability: P(0.6, 'that placeholder G holds'), attributions: [] }],
    interactions: [], reference_intakes: { source: 'x', group: 'y', values: {} }, lexicon: { rules: [] },
    sources: [{ id: 'src-a', authors: 'Author A et al.', venue: 'Journal A', year: 2020 }] };
  var txt = JSON.stringify(body);
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (h) {
    var hex = Array.prototype.map.call(new Uint8Array(h), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    return HT.packImportText(JSON.stringify({ format: 'healthtracker-pack', version: 9, sha256: hex, body: txt }));
  }).then(function (r) {
    HT.state().settings.stack = [
      { id: 'sa', name: 'Item A', kind: 'dose', enabled: true, dose: 600, dose_unit: 'mg', added_on: '2026-10-01', added_basis: 'added' },
      { id: 'sc', name: 'Item C', kind: 'dose', enabled: true, dose: 100, dose_unit: 'mg', added_on: '2026-10-01', added_basis: 'added', nutrients: { micros: { magnesium_mg: 100 } } }];
    HT.resave(); HT.refresh();
    return { imported: r.ok, version: r.version, claimsA: HT.stackClaims(HT.state().settings.stack[0]).map(function (c) { return c.id; }) };
  });
})()
'@
  Write-Host ("  fixture: " + $fx)
  if (-not ($fx -like '*"imported":true*')) { Write-Host "ERROR: the placeholder pack did not import"; Cleanup; exit 2 }
  Check ($fx.Contains('"claimsA":["claim-a"]')) "R305/3: an item's claims are the REVIEWED ones naming it -- the planted unreviewed claim naming the same item (other case, a trailing space) is not among them"

  # ---- + Log: the non-nutrient item and the item with nutrients ------------------------------
  $null = EvalJ "(function(){ HT.openSheet('root'); HT.stackOpen(); return 1; })()"
  WaitQuiet 'the stack open'
  $l1 = EvalJ @'
(function () {
  var row = function (id) { var d = document.querySelector('#sheetRoot .stkclaims[data-stack="' + id + '"]'); return d; };
  var a = row('sa'), c = row('sc');
  return { aHead: a ? a.querySelector('summary').textContent : '', aOpen: a ? a.open : null, aH: a ? Math.round(a.querySelector('summary').getBoundingClientRect().height) : 0,
           cHead: c ? c.querySelector('summary').textContent : '', unreviewed: document.body.textContent.indexOf('Unreviewed placeholder B') >= 0 };
})()
'@
  Write-Host ("  + Log rows: " + $l1)
  $a = $l1 | ConvertFrom-Json
  Check (($a.aHead -eq ('supplies no nutrients ' + [char]0x00B7 + ' linked to 1 claim')) -and ($a.aOpen -eq $false) -and ($a.aH -ge 44)) "a non-nutrient item shows 'supplies no nutrients . linked to 1 claim', collapsed, a 44 px target ($($a.aHead))"
  Check ($a.cHead -eq ('linked claims ' + [char]0x00B7 + ' 1')) "an item with nutrients shows 'linked claims . 1' ($($a.cHead))"
  $t1 = TapSel '#sheetRoot .stkclaims[data-stack=\"sa\"] summary'
  $o1 = EvalJ @'
(function () {
  var d = document.querySelector('#sheetRoot .stkclaims[data-stack="sa"]');
  return { open: d.open, text: d.textContent, unreviewed: document.body.textContent.indexOf('Unreviewed placeholder B') >= 0 };
})()
'@
  Write-Host ("  opened: " + $o1)
  $o = $o1 | ConvertFrom-Json
  Check ($t1 -and ($o.open -eq $true) -and ($o.text -like '*Placeholder claim A.*60 % that placeholder A holds*GRADE low*Author A et al., Journal A, 2020*')) "a real tap opens it: the claim, its probability (60 % that ...), its GRADE and its source"
  Check (($o.unreviewed -eq $false) -and ($a.unreviewed -eq $false)) "the unreviewed claim shows nowhere on the page"

  # ---- Settings: the claims sit below the nutrients ----------------------------------------
  $st = EvalJ @'
(function () {
  HT.closeSheet(); HT.openSettings();
  var rows = Array.prototype.filter.call(document.querySelectorAll('#settingsPanel .stkrow.stked'), function (r) { return /Item C/.test(r.textContent); });
  var r = rows[0]; if (!r) return { err: 'no Settings row' };
  var kids = Array.prototype.slice.call(r.children);
  var nut = kids.filter(function (k) { return /counts toward/.test(k.textContent); })[0], cl = r.querySelector('.stkclaims');
  var out = { below: !!(nut && cl) && kids.indexOf(cl) > kids.indexOf(nut), head: cl ? cl.querySelector('summary').textContent : '' };
  cl.open = true; out.animal = /animal and cell work, not people/.test(cl.textContent);
  HT.closeSettings();
  return out;
})()
'@
  Write-Host ("  Settings: " + $st)
  Check (($st -like '*"below":true*') -and ($st -like '*"animal":true*')) "in Settings the item's linked claims sit BELOW its nutrients, and a claim from animal or cell work says so"

  # ---- the strip after a tick ---------------------------------------------------------------
  $sp = EvalJ "(function(){ HT.closeSheet(); HT.stackCheck('sa'); HT.refresh(); var s = document.getElementById('ctxStrip'); var l = s.querySelector('.ctxlink[onclick*=stackClaimsShow]'); return { kind: s.getAttribute('data-kind'), text: s.textContent, link: l ? l.textContent : '' }; })()"
  Write-Host ("  strip: " + $sp)
  $t2 = TapSel '#ctxStrip .ctxlink[onclick*=\"stackClaimsShow\"]'
  $sv = EvalJ "(function(){ var d = document.querySelector('#sheetRoot .stkclaims[data-stack=sa]'); return { open: !!(d && d.open), sheet: getComputedStyle(document.getElementById('entrySheet')).display !== 'none' }; })()"
  Write-Host ("  after the link: " + $sv + " tapped=" + $t2)
  Check (($sp -like '*"kind":"stack"*') -and ($sp -like ('*Supplies no nutrients ' + [char]0x00B7 + ' linked to 1 claim*')) -and $t2 -and ($sv -like '*"open":true*') -and ($sv -like '*"sheet":true*')) "after a tick the strip shows the count, and its link opens + Log at the item with its claims open"

  # ---- a group's own i --------------------------------------------------------------------------
  $gp = EvalJ @'
(function () {
  HT.closeSheet(); HT.refresh();
  var g = document.querySelector('#pathways details.pwgroup[data-group="energy"]'); if (!g) return { err: 'no group' };
  g.open = true;
  var rec = g.querySelector('.pwgrouprec'); var info = rec ? rec.querySelector('details.pwinfo') : null;
  if (info) info.open = true;
  var other = document.querySelector('#pathways details.pwgroup[data-group="glucose"] .pwgrouprec');
  return { has: !!rec, text: info ? info.textContent : '', other: !!other };
})()
'@
  Write-Host ("  group: " + $gp)
  Check (($gp -like '*"has":true*') -and ($gp -like '*Placeholder group claim G.*60 % that placeholder G holds*GRADE low*') -and ($gp -like '*"other":false*')) "a group-level claim shows on its group's own i, with its probability and GRADE; a group with none has no such line"

  # ---- the words, and the layout -------------------------------------------------------------
  $wd = EvalJ @'
(function () {
  HT.openSheet('root'); HT.stackOpen();
  var t = Array.prototype.map.call(document.querySelectorAll('.stkclaims, .pwgrouprec, #ctxStrip'), function (e) { return e.textContent; }).join(' | ');
  var small = Array.prototype.filter.call(document.querySelectorAll('.stkclaims summary'), function (e) { var r = e.getBoundingClientRect(); return r.height > 0 && r.height < 44; }).length;
  return { bad: (t.match(/\b(effects?|works)\b/gi) || []), small: small, page: document.documentElement.scrollWidth - window.innerWidth };
})()
'@
  Write-Host ("  words: " + $wd)
  Check (($wd.Contains('"bad":[]')) -and ($wd -like '*"small":0*') -and ($wd -like '*"page":0*')) "the words 'effects' and 'works' appear nowhere in these surfaces; every summary is 44 px; nothing scrolls sideways at 390"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("CLAIMS GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "CLAIMS GATE: PASS -- a stack item shows its reviewed linked claims, with probability, GRADE and source, and nothing unreviewed"
Write-Host "GATE: PASS"
exit 0
