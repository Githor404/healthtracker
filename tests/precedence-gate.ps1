# R233.1 + R234 + R237 -- ONE NUMBER-PRECEDENCE RULE, AND THE PAST RECOMPUTED. By real
# typing and taps at 390 px, on the real food database.
#
#   1. the reported case: a photo the AI calls "apple juice"; "wine" typed on it is
#      looked up AS IT IS TYPED; the white wine row picked replaces ALL the AI's
#      numbers -- the item counts the row's energy, carbohydrate and alcohol
#   2. the correction is learned (the next "apple juice" offers the wine first); a
#      typed name with no pick says "not counted"; an unconfirmed item the user's own
#      past can answer counts provisionally from it
#   3. the day says its undercount beside its calories, the list routes to the
#      picker, "suggested -- tap to confirm" confirms, and Undo puts it back
#   4. a stored v16 log is recomputed on boot, automatically: rows win, what each
#      item was is kept on it, the user's own values are never touched
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8317
$Dbg = 9523
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-precedence-" + [System.Guid]::NewGuid().ToString('N'))
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
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "Promise.resolve(eval(decodeURIComponent(escape(atob('" + $enc + "'))))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text + " " + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value }
# REAL TYPING, one character at a time into whatever holds the focus.
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    Start-Sleep -Milliseconds 70 } }
function Settle { WaitQuiet 'after a step' }   # R283: was a fixed 500 ms
function Focus([string]$id) { [void](Eval "(function(){ var e = document.getElementById('$id'); e.focus(); if (e.select) e.select(); return 1; })()") }

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


  $boot = Eval "typeof HT === 'object' && typeof HT.applyPrecedence === 'function' && typeof HT.openPhotoDraft === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or R237 is not on HT"; Cleanup; exit 2 }

  # ---- 1. THE REAL CASE: photo "apple juice" -> type "wine" -> pick the white wine row --
  $o1 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-10-16T17:20:00-04:00'); });
  localStorage.clear(); HT.boot();
  await HT.corpusEnsure(); HT.matchIndexBuild(); await window.__htQuiet(10000);
  window.__ns = HT.corpusNamespace();
  const juice = { name: 'apple juice', grams: 180, notes: 'pale yellow, slightly cloudy', alts: [{ name: 'apple juice', p: 0.6 }, { name: 'white wine', p: 0.2 }, { name: 'lemonade', p: 0.2 }],
                  per100: { kcal: 46, protein_g: 0.1, fat_g: 0.1, carb_g: 11.3, fiber_g: 0.2, soluble_fiber_g: 0.1 } };
  window.__juice = juice;
  HT.openPhotoDraft(JSON.stringify({ meal: 'drink', items: [juice] }));
  await window.__htQuiet(10000);
  HT.photoSearchOpen(0); await window.__htQuiet(10000);
  const f = document.getElementById('pmsQuery'); f.focus();
  return { ns: window.__ns, field: !!f };
})()
'@
  Write-Host ("  draft: " + $o1)
  Focus 'pmsQuery'
  TypeText 'wine'
  WaitQuiet 'the typed search answered'   # R283: was a fixed 1.2 s
  $o2 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const rows = Array.prototype.slice.call(document.querySelectorAll('.pmsrow'));
  const names = rows.map((b) => (b.querySelector('.pmsnm') || b).textContent);
  const o = { typedNoEnter: rows.length > 0, n: rows.length, first: names[0] || '', names: names.slice(0, 5),
              focusKept: document.activeElement && document.activeElement.id === 'pmsQuery',
              cal: rows.length ? /cal/.test(rows[0].textContent) : false };
  const white = rows.filter((b) => /wine/i.test(b.textContent) && /white/i.test(b.textContent))[0];
  o.white = white ? (white.querySelector('.pmsnm') || white).textContent : '';
  if (white) { white.click(); await window.__htQuiet(10000); }
  // the state guard may ask; a drink is a drink either way, so use it
  const use = Array.prototype.filter.call(document.querySelectorAll('.pmsconfirmbtn'), (b) => /Use anyway/.test(b.textContent))[0];
  if (use) { use.click(); await window.__htQuiet(10000); }
  const sr = HT.photoSave(); await window.__htQuiet(10000);
  const day = HT.state().days[HT.state().current] || { items: [] };
  const it = day.items.filter((x) => x.ref && /wine/i.test(String(x.ref.name || '')))[0];
  o.saved = !!(sr && sr.ok) && !!it;
  if (it) {
    const g = Number(it.grams), b = Number(it.ref.g) || g, k = g / b;
    o.kcal = it.kcal; o.rowKcal = Number(it.ref.v['208']) * k; o.carb = it.carb_g; o.rowCarb = Number(it.ref.v['205']) * k;
    o.alc = HT.refAlcoholG(it.ref); o.unres = it.unresolved === true; o.aiKcal = 46 * g / 100; o.grams = g;
  }
  return o;
})()
'@
  Write-Host ("  picked: " + $o2)
  $p = $o2 | ConvertFrom-Json
  Check ($p.typedNoEnter -and $p.focusKept -and $p.cal) "R233.1/1 GATE: typing 'wine' on the photo item LOOKS IT UP as it is typed -- rows with calories, no Enter, the caret still in the field ($($p.n) rows; first '$($p.first)')"
  Check ($p.saved -and ([Math]::Abs($p.kcal - $p.rowKcal) -lt 0.01) -and ([Math]::Abs($p.carb - $p.rowCarb) -lt 0.01) -and ($p.alc -gt 0) -and (-not $p.unres)) "R233.1/1 + /3 GATE: picking '$($p.white)' replaces ALL the AI's numbers -- the item counts the row's $([Math]::Round($p.kcal,1)) kcal and $([Math]::Round($p.carb,1)) g carbs, and $([Math]::Round($p.alc,1)) g alcohol (the AI said $([Math]::Round($p.aiKcal,1)) kcal of apple juice)"

  # ---- 1b. THE SAME ITEM, THE SAME NUMBERS: capture, the later resolve pass, a repeat, a restore --
  $o1b = EvalA @'
(async function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const dk = HT.state().current, day = HT.state().days[dk];
  const wi = day.items.findIndex((x) => x.ref && /wine/i.test(String(x.ref.name || '')));
  const w = day.items[wi];
  const o = { capture: w.kcal };
  day.items.push({ name: 'white wine', meal: 'drink', time: '17:30', grams: 180, unresolved: true, confidence: 'eyeballed', source: 'ai-paste', notes: '' });
  HT.resave();
  const ri = day.items.length - 1;
  await HT.resolveItem(dk, ri, w.ref.id, w.ref.name, null, 'picked');
  o.resolve = HT.state().days[dk].items[ri].kcal;
  const rp = HT.logRepeat(dk, wi); await window.__htQuiet(10000);
  o.repeat = rp && rp.item ? rp.item.kcal : null;
  window.__confirm = true; window.confirm = function () { return true; };
  const ex = HT.exportJSON(); HT.restore(ex); await window.__htQuiet(10000);
  o.restore = HT.state().days[dk].items[wi].kcal;
  // leave the day as the next steps expect: only the captured wine
  const d2 = HT.state().days[dk]; d2.items = [d2.items[wi]]; HT.resave(); HT.refresh();
  return o;
})()
'@
  Write-Host ("  the same numbers: " + $o1b)
  $sn = $o1b | ConvertFrom-Json
  Check (($sn.capture -eq $sn.resolve) -and ($sn.capture -eq $sn.repeat) -and ($sn.capture -eq $sn.restore)) "R237/A GATE: the same wine gives the SAME NUMBERS whichever way it arrives -- capture $($sn.capture), resolve $($sn.resolve), repeat $($sn.repeat), restore $($sn.restore)"

  # ---- 2. learned: the next "apple juice" leads with the wine; and a kept name is not counted --
  $o3 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const op = HT.openPhotoDraft(JSON.stringify({ meal: 'drink', items: [window.__juice, { name: 'grandmas secret sauce', grams: 40, notes: '', alts: [{ name: 'grandmas secret sauce', p: 1 }],
                                                                   per100: { kcal: 60, protein_g: 1, fat_g: 3, carb_g: 7, fiber_g: 0, soluble_fiber_g: 0 } }] }));
  await window.__htQuiet(10000);
  if (!op || !op.ok) return { err: 'second draft did not open: ' + JSON.stringify(op) };
  const alts = document.querySelector('.pmalts');
  const firstAlt = alts ? alts.querySelector('.pmalt') : null;
  const o = { lead: firstAlt ? firstAlt.textContent : '' };
  // the sauce: say what it is, pick nothing, keep the name
  HT.photoSearchOpen(1); await window.__htQuiet(10000);
  await HT.photoSearchRun(1, 'zzqqxv wibblefrotz'); await window.__htQuiet(10000);
  const keep = document.querySelector('.pmskeep');
  o.keepText = keep ? keep.textContent : '';
  if (keep) { keep.click(); await window.__htQuiet(10000); }
  // the juice: keep it under its own name, unpicked -- the past should suggest
  HT.photoSearchOpen(0); await window.__htQuiet(10000);
  await HT.photoSearchRun(0, 'qqxxzz wibblejuice'); await window.__htQuiet(10000);
  const k0 = document.querySelector('.pmskeep');
  if (k0) { k0.click(); await window.__htQuiet(10000); }
  HT.photoSave(); await window.__htQuiet(10000);
  HT.refresh(); window.scrollTo(0, 0);
  const day = HT.state().days[HT.state().current];
  const sauce = day.items.filter((x) => /zzqqxv wibblefrotz/.test(x.name))[0];
  const juice2 = day.items.filter((x) => x.provisional === true)[0];
  o.sauceUnres = !!sauce && sauce.unresolved === true;
  o.prov = !!juice2; o.provKcal = juice2 ? juice2.kcal : null; o.provRow = juice2 && juice2.suggested ? juice2.suggested.name : '';
  o.items = day.items.map((x) => [x.name, x.unresolved ? 'U' : '', x.provisional ? 'P' : '', x.ref ? 'R' : '', x.suggested ? 'S' : '', x.ai_identity || '', x.plateId || ''].join('|'));
  o.plates = Object.keys(HT.state().plates || {}).map((k) => (HT.state().plates[k].items || []).map((x) => x.name + '<' + (x.ai_identity || '') + '>' + (x.unresolved ? 'U' : '')).join(','));
  return o;
})()
'@
  Write-Host ("  learned: " + $o3)
  $l = $o3 | ConvertFrom-Json
  Check ($l.lead -match 'wine') "R237/C1 GATE: the next photo the AI calls 'apple juice' OFFERS THE USER'S CORRECTION FIRST ($($l.lead))"
  Check (($l.keepText -like '*not counted*') -and $l.sauceUnres) "R233.1/1 GATE: a typed name with no pick is offered as 'with no nutrition (not counted)' -- said, never saved silently as a counted 0"
  Check ($l.prov -and ($l.provKcal -gt 0) -and ($l.provRow -match 'wine')) "R233.1/4 GATE: an unconfirmed 'apple juice' with the user's own past behind it COUNTS PROVISIONALLY from that row ($($l.provKcal) kcal, '$($l.provRow)')"

  # ---- 3. the day says it; the list routes; "suggested -- tap to confirm"; Undo ----------
  $o4 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const o = {};
  const line = document.querySelector('#dayView .uncbtn');
  o.line = line ? line.textContent : '';
  if (line) { line.click(); await window.__htQuiet(10000); }
  const items = Array.prototype.slice.call(document.querySelectorAll('#dayView .uncitem'));
  o.list = items.map((b) => b.textContent);
  if (items[0]) { items[0].click(); await window.__htQuiet(10000); }
  o.picker = !!(HT.resolveView && HT.resolveView());
  HT.resolveClose && HT.resolveClose(); await window.__htQuiet(10000);
  HT.refresh();
  // open the provisional row and confirm it
  const day = HT.state().days[HT.state().current];
  const pi = day.items.findIndex((x) => x.provisional === true);
  HT.dayGroupsOpenAll(true); HT.refresh(); await window.__htQuiet(10000);
  o.headTag = '';
  const rowHead = Array.prototype.filter.call(document.querySelectorAll('#dayView .mitem'), (r) => !!r.querySelector('.msuggnum'))[0];
  if (rowHead) { o.headTag = ((rowHead.querySelector('.msuggnum') || {}).getAttribute || function () { return ''; }).call(rowHead.querySelector('.msuggnum'), 'title') || ''; rowHead.querySelector('.mhead').click(); await window.__htQuiet(10000); }
  const conf = document.querySelector('#dayView .msuggbtn');
  o.confText = conf ? conf.textContent : '';
  const k0 = day.items[pi].kcal;
  if (conf) { conf.click(); await window.__htQuiet(10000); }
  const it = HT.state().days[HT.state().current].items[pi];
  o.confirmed = !!it.ref && !it.provisional && it.kcal === k0;
  const undo = document.querySelector('#toast .tundo');
  if (undo) { undo.click(); await window.__htQuiet(10000); }
  const it2 = HT.state().days[HT.state().current].items[pi];
  o.undone = !!it2 && it2.provisional === true && !it2.ref;
  return o;
})()
'@
  Write-Host ("  the day: " + $o4)
  $d = $o4 | ConvertFrom-Json
  Check (($d.line -match '^\d[\d,.]* cal \+ 1 item not counted') -and ($d.line -match '1 suggested')) "R233.1/5 GATE: the day says its undercount beside its calories -- '$($d.line)'"
  Check ((@($d.list).Count -eq 1) -and ($d.list[0] -match 'wibblefrotz.*pick a food') -and $d.picker) "R233.1/5 GATE: one tap lists what is not counted, and each one opens the food picker"
  Check (($d.headTag -match 'suggested') -and ($d.confText -match 'suggested .* tap to confirm') -and $d.confirmed -and $d.undone) "R233.1/4 GATE: the suggested row says so, 'suggested -- tap to confirm' confirms it with the same numbers, and Undo puts it back"

  # ---- 4. THE PAST, automatically: a stored v16 log boots recomputed -----------------
  $o5 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const row = { ns: 'cnf', id: '2852', name: 'Alcohol, table wine, white', at: '2026-10-09', hash: 'h', attribution: 'CNF', how: 'proposed', when: 'later', g: 180,
                v: { '208': 147.6, '203': 0.13, '204': 0, '205': 4.68, '291': 0, '221': 18.54 } };
  const dk = HT.state().current;
  const v16 = { version: 16, current: dk, settings: {}, priceLog: {}, timeline: {}, fastLog: {}, regimens: { active: '', list: [], log: {} }, plates: {}, meds: {}, labels: {},
    days: {} };
  v16.days[dk] = { status: 'in_progress', water_l: 0, items: [
    { name: 'white wine', meal: 'drink', time: '17:18', grams: 180, kcal: 82.8, protein_g: 0.2, fat_g: 0.2, carb_g: 20.3, fiber_g: 0.4, soluble_fiber_g: 0.2, confidence: 'eyeballed', source: 'ai-paste', notes: '', ref: row },
    { name: 'white wine', meal: 'drink', time: '20:02', grams: 180, unresolved: true, confidence: 'eyeballed', source: 'ai-paste', notes: '', ref: row },
    { name: 'oats', meal: 'breakfast', time: '08:00', grams: 40, kcal: 150, protein_g: 5, fat_g: 3, carb_g: 27, fiber_g: 4, soluble_fiber_g: 2, confidence: 'weighed', source: 'manual', notes: '', ref: row, adjusted: ['kcal'] }] };
  localStorage.clear();
  localStorage.setItem('healthtracker-log', JSON.stringify(v16));
  const b = HT.boot(); HT.refresh(); await window.__htQuiet(10000);
  const its = HT.state().days[dk].items;
  const o = { source: b.source, v: HT.state().version, k0: its[0].kcal, k1: its[1].kcal, oats: its[2].kcal, rec0: its[0].recomputed ? its[0].recomputed.was.kcal : null,
              kept: !!localStorage.getItem(HT.PREMIGRATION_V16_KEY) };
  // the row says it, where its details are
  HT.dayGroupsOpenAll && HT.dayGroupsOpenAll(true); HT.refresh(); await window.__htQuiet(10000);
  const row0 = Array.prototype.filter.call(document.querySelectorAll('#dayView .mitem'), (r) => /17:18/.test(r.textContent))[0];
  if (row0) { row0.querySelector('.mhead').click(); await window.__htQuiet(10000); }
  const rc = document.querySelector('#dayView .mrecount');
  o.says = rc ? rc.textContent : '';
  return o;
})()
'@
  Write-Host ("  the past: " + $o5)
  $q = $o5 | ConvertFrom-Json
  Check (($q.source -eq 'migrated') -and ($q.v -eq 17) -and ($q.k0 -eq 147.6) -and ($q.k1 -eq 147.6) -and ($q.rec0 -eq 82.8) -and $q.kept) "R237/B GATE: a stored v16 log is recomputed AUTOMATICALLY on boot -- both wines count the row's 147.6 kcal, the old 82.8 is kept on the item, and the v16 blob was kept first"
  Check ($q.oats -eq 150) "R237/B GATE: a value the user set (adjusted kcal 150) is never touched"
  Check ($q.says -like 'Recounted from its food database row*was 83 cal*') "R237/B: the item says so where its details are -- '$($q.says)'"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -eq 0) {
  Write-Host "PRECEDENCE GATE: PASS -- a typed correction is looked up as it is typed and a picked row replaces every AI number; the correction is learned; a kept name says not counted; a past answer counts provisionally; the day states its undercount and routes it; confirm and Undo; a v16 log recomputes on boot with the old figures kept and the user's own values untouched"
  Write-Host "GATE: PASS"
  exit 0
}
Write-Host ("PRECEDENCE GATE: FAIL -- " + $fails.Count + " check(s)")
Write-Host "GATE: FAIL"
exit 1
