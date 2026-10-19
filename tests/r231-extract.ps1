# R231/R239 -- EXTRACT EVERY MEAL FROM A BACKUP, with the APP'S OWN figures.
#
# Not a gate: a re-runnable tool for the R231 held-out check. It restores the given
# backup into the app in a headless browser (this repo's own app.js -- so the
# migrations, the precedence rule, mealResponse and the clean rule are exactly the
# shipped ones) and writes one JSON with every eating event: nutrients, the response
# (rise, 2 h area, judged), clean or not, food around it, uncounted / provisional
# items, and the contexts R231 names. Nothing is stored in the repo; the backup and
# the output stay wherever you point them.
#
#   powershell -File tests/r231-extract.ps1 -Backup <healthtracker-backup-*.json> -Out <events.json>
#   python tests/r231-heldout.py <events.json>
param([Parameter(Mandatory = $true)][string]$Backup, [Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8381
$Dbg = 9581
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-r231-" + [System.Guid]::NewGuid().ToString('N'))
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
function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }
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
  Start-Sleep -Milliseconds 600
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
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000


  if (-not (Test-Path $Backup)) { Write-Host "ERROR: no such backup: $Backup"; Cleanup; exit 2 }
  $boot = Eval "typeof HT === 'object' && typeof HT.reviewPool === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot"; Cleanup; exit 2 }
  $bk = [IO.File]::ReadAllText((Resolve-Path $Backup), [Text.Encoding]::UTF8)
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bk))
  [void](Invoke-CDP 'Runtime.evaluate' @{ expression = "window.__backupText = decodeURIComponent(escape(atob('" + $b64 + "'))); 1"; returnByValue = $true })
  $js = @'
(function () {
  // R231 pre-registration report: every eating event (sitting) in the restored
  // backup, with the APP'S OWN response figures (mealResponse / mealIauc / the
  // review's clean rule) and the inputs R231 names. Read only; nothing stored.
  var raw = window.__backupText;
  window.__confirm = true; window.confirm = function () { return true; }; window.alert = function () {};
  var rr = HT.restore(raw);
  if (!rr || !rr.ok) return { err: 'restore failed: ' + JSON.stringify(rr) };
  HT.refresh();
  var pool = HT.reviewPool();
  var tl = HT.state().timeline || {};
  var num = function (x) { var n = Number(x); return isFinite(n) ? n : 0; };
  var H2 = 120 * 60000;
  var alcoholOf = function (it) { var v = it && it.ref && it.ref.v; return v && v['221'] != null ? num(v['221']) : 0; };
  var dayAlcohol = function (dk, fromMin) {
    var d = (HT.state().days || {})[dk]; var a = 0, n = 0;
    ((d && d.items) || []).forEach(function (it) {
      var m = HT.hhmmToMin(it.time); if (m == null || m < fromMin) return;
      a += alcoholOf(it); if (it.meal === 'drink' && alcoholOf(it) > 0) n++;
    });
    (tl[dk] || []).forEach(function (r) { if (r && r.type === 'alcohol') { var m = HT.hhmmToMin(r.time); if (m != null && m >= fromMin) n += num(r.value) || 1; } });
    return { g: a, n: n };
  };
  var sleepEnding = function (dk) {
    var h = null;
    (tl[dk] || []).forEach(function (r) { if (r && r.type === 'sleep' && num(r.value) > 0) h = (h || 0) + num(r.value); });
    return h;
  };
  var eventsBefore = function (dk, ms, type) {
    var n = 0, base = HT.dayKeyMs(dk);
    (tl[dk] || []).forEach(function (r) { if (!r || r.type !== type) return; var m = HT.hhmmToMin(r.time); if (m != null && base + m * 60000 <= ms) n++; });
    return n;
  };
  var stressDay = function (dk) { return (tl[dk] || []).filter(function (r) { return r && r.type === 'glucose_rise' && /stress/.test(String(r.variant || r.label || r.notes || '')); }).length; };
  var out = pool.map(function (e) {
    HT.reviewEntry(e);
    var items = e.ev.items || [];
    var sum = function (k) { return items.reduce(function (a, it) { return a + num(it[k]); }, 0); };
    var prior = pool.filter(function (o) { return o !== e && o.ms < e.ms && o.ms >= e.ms - H2; });
    var after = pool.filter(function (o) { return o !== e && o.ms > e.ms && o.ms <= e.ms + H2; });
    var st = HT.stepsIn(e.ms, e.ms + H2);
    var r = e.r || {};
    return {
      dk: e.dk, ms: e.ms, hour: new Date(e.ms).getHours() + new Date(e.ms).getMinutes() / 60,
      n: items.length, names: items.map(function (it) { return String(it.name || ''); }),
      refs: items.map(function (it) { return it.ref ? (String(it.ref.ns || '') + ':' + String(it.ref.id || '')) : ''; }),
      combo: e.key.combo, key: e.key.names,
      kcal: sum('kcal'), carbs: sum('carb_g'), fat: sum('fat_g'), protein: sum('protein_g'), fiber: sum('fiber_g'),
      alcohol: items.reduce(function (a, it) { return a + alcoholOf(it); }, 0),
      carbsKnown: e.carbsKnown, confs: items.map(function (it) { return it.confidence; }),
      phase: r.phase || '', why: r.why || r.iaucWhy || '', rise: r.rise, iauc: r.iauc2h,
      base: r.baseline ? r.baseline.mean : null, baseN: r.baseline ? r.baseline.n : null,
      tToPeak: r.tToPeak, judged: e.judged, cleanBefore: e.cleanBefore, cleanAfter: e.cleanAfter,
      priorN: prior.length, priorCarbs: prior.reduce(function (a, o) { return a + o.carbs; }, 0),
      priorMin: prior.length ? Math.round((e.ms - prior[prior.length - 1].ms) / 60000) : null,
      afterN: after.length, afterCarbs: after.reduce(function (a, o) { return a + o.carbs; }, 0),
      afterMin: after.length ? Math.round((after[0].ms - e.ms) / 60000) : null,
      steps2h: st && st.known ? st.steps : null,
      sleepH: sleepEnding(e.dk),
      alcEveBefore: dayAlcohol(HT.shiftDate(e.dk, -1), 17 * 60),
      redLight: eventsBefore(e.dk, e.ms, 'red_light'), sauna: eventsBefore(e.dk, e.ms, 'sauna'),
      stressDay: stressDay(e.dk),
      nRecomputed: items.filter(function (it) { return !!it.recomputed; }).length,
      nUncounted: items.filter(function (it) { return it.unresolved === true; }).length,
      nProvisional: items.filter(function (it) { return it.provisional === true; }).length,
      carbsWas: items.reduce(function (a, it) { if (!it.recomputed) return a + num(it.carb_g); var w = it.recomputed.was || {}; return a + (w.unresolved ? 0 : num(w.carb_g)); }, 0),
      kcalWas: items.reduce(function (a, it) { if (!it.recomputed) return a + num(it.kcal); var w = it.recomputed.was || {}; return a + (w.unresolved ? 0 : num(w.kcal)); }, 0)
    };
  });
  var recs = [], unc = [];
  Object.keys(HT.state().days).sort().forEach(function (dk) {
    (HT.state().days[dk].items || []).forEach(function (it) {
      if (it.recomputed) { var w = it.recomputed.was || {}; recs.push({ dk: dk, time: it.time, name: it.name, wasUnres: !!w.unresolved, kcalWas: w.unresolved ? 0 : num(w.kcal), kcal: num(it.kcal), carbWas: w.unresolved ? 0 : num(w.carb_g), carb: num(it.carb_g), alc: (it.ref && it.ref.v && it.ref.v['221'] != null) ? num(it.ref.v['221']) : 0 }); }
      if (it.unresolved === true) unc.push({ dk: dk, time: it.time, name: it.name });
    });
  });
  var g = HT.glucoseRead(), gd = Object.keys(g).sort();
  return { recomputed: recs, uncounted: unc, schema: HT.state().version, n: out.length, glucoseDays: gd.length, glucoseFirst: gd[0], glucoseLast: gd[gd.length - 1], events: out };
})()

'@
  $res = EvalA $js
  [IO.File]::WriteAllText($Out, $res, (New-Object Text.UTF8Encoding $false))
  if ($res -like 'EXCEPTION*') { Write-Host ("ERROR: " + $res.Substring(0, [Math]::Min(300, $res.Length))); Cleanup; exit 1 }
  Write-Host ("wrote " + $res.Length + " chars to " + $Out)
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup
exit 0
