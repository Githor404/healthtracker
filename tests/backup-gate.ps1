# R213/B1 (R206) -- A BACKUP THAT IS A FILE, AND THE WAY BACK FROM IT.
#
# BEFORE: the only way out was "Copy data" -- the whole log on the clipboard.
#
# RULED: "Export backup" makes healthtracker-backup-YYYY-MM-DD-vNN.json through
# the share sheet; a download where a file cannot be shared; the clipboard as a
# secondary link; "Last backup: <date>" in Settings; NO NAG. Gate: round trip.
#
# A headless browser has no share sheet, so the two routes are driven as the
# page meets them: navigator.share / canShare are replaced with a stand-in that
# RECEIVES THE FILE (name, type and bytes are then asserted), and the download
# route is caught at the anchor's own click, with the bytes read back from its
# URL. The round trip is real: the downloaded bytes are written to a file on
# disk, every key of the site's storage is cleared, the app is reloaded EMPTY,
# the file is chosen through the real file input, and Restore is tapped.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8305
$Dbg = 9511
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-backup-" + [System.Guid]::NewGuid().ToString('N'))
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
function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }

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
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.exportBackup === 'function' && typeof HT.restoreFilePicked === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the backup functions are not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'DOM.enable' $null | Out-Null

  # R227.1: imported streams in the fixture -- glucose with rises E-lite flags, and
  # steps -- and, before the file is made, the stores, the flagged rises and the
  # rendered glucose chart, to be compared after the wipe and the restore.
  [void](EvalA @'
(function () {
  var t = HT.todayKey();
  window.__clock = new Date(t + 'T21:00:00').getTime();
  HT.setClock(function () { return window.__clock; });
  var p = function (n) { return String(n).padStart(2, '0'); };
  var iso = function (ms) { var d = new Date(ms), o = -d.getTimezoneOffset();
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':00'
      + (o < 0 ? '-' : '+') + p(Math.floor(Math.abs(o) / 60)) + ':' + p(Math.abs(o) % 60); };
  var base = HT.dayKeyMs(t), rows = [];
  for (var m = 0; m < 1260; m += 5) {
    var v = 5.5;
    if (m >= 180 && m <= 210) v = 5.0 + 3 * (m - 180) / 30;
    if (m >= 1020 && m <= 1060) v = 5.5 + 3.5 * (m - 1020) / 40;
    if (m > 1060 && m < 1120) v = 9 - 3.5 * (m - 1060) / 60;
    rows.push({ t: iso(base + m * 60000), v: Math.round(v * 100) / 100, unit: 'mmol/L' });
  }
  return Promise.resolve(HT.glucoseIngest(rows, { source: 'Gate CGM' })).then(function () {
    localStorage.setItem('healthtracker-steps', JSON.stringify((function () { var o = {}; o[t] = { t: [1015, 1020], n: [180, 240], src: 'Gate phone' }; return o; })()));
    return 1;
  });
})()
'@)
  [void](EvalJ @'
(function () {
  var t = HT.todayKey();
  HT.addManualEntry({ name: 'Gate lunch', meal: 'lunch', time: '12:00', grams: 250, kcal: 520, protein_g: 30, fat_g: 20, carb_g: 50, fiber_g: 6, soluble_fiber_g: 0 });
  HT.stackUpsert({ name: 'Gate capsule', dose: '300', dose_unit: 'mg' });
  HT.myFoodUpsert({ name: 'Gate seed oil', basis: 'label', per: 'serving', serving_g: 14, kcal: 120, fat_g: 14 });
  HT.logStack([]);
  HT.resave();
  window.__before = HT.exportJSON();
  HT.refresh(); HT.closeSettings && HT.closeSettings();
  var gh = document.querySelector('#dayView .ghead'); if (gh) gh.click();
  var chart = document.querySelector('#dayView .tchartbox');
  sessionStorage.setItem('__r2271', JSON.stringify({ g: JSON.stringify(HT.glucoseRead()), s: JSON.stringify(HT.stepsRead()),
    rises: JSON.stringify(HT.eliteDay(t)), chart: chart ? chart.innerHTML : '', clock: window.__clock }));
  if (gh) gh.click();
  HT.openSettings();
  document.getElementById('backupBtn').scrollIntoView({ block: 'center' });
  return 1;
})()
'@)
  $ui = EvalJ @'
(function () {
  var b = document.getElementById('backupBtn'), c = document.getElementById('backupCopy'), l = document.getElementById('backupLast');
  var r = b.getBoundingClientRect(), rc = c.getBoundingClientRect();
  return { label: b.textContent, h: r.height, w: r.width, px: parseFloat(getComputedStyle(b).fontSize), copy: c.textContent, copyH: rc.height,
           copyPx: parseFloat(getComputedStyle(c).fontSize), last: l.textContent, lastPx: parseFloat(getComputedStyle(l).fontSize),
           order: !!(b.compareDocumentPosition(c) & Node.DOCUMENT_POSITION_FOLLOWING) };
})()
'@
  Write-Host ("  the backup card: " + $ui)
  $uv = $ui | ConvertFrom-Json
  Check (($uv.label -eq 'Export backup') -and ($uv.h -ge 44) -and ($uv.w -gt 0) -and ($uv.px -ge 16)) "R213: Settings has 'Export backup' -- 44 px, 16px"
  Check (($uv.copy -eq 'Copy as text instead') -and ($uv.copyH -ge 44) -and ($uv.copyPx -ge 16) -and ($uv.order -eq $true)) "the clipboard is a SECONDARY link beneath it"
  Check (($uv.last -eq 'No backup file made yet.') -and ($uv.lastPx -ge 16)) "and before any backup the line says none has been made -- nothing more"

  # ---- the share sheet, closed without saving -------------------------------------------
  $cancel = EvalA @'
(function () {
  Object.defineProperty(navigator, 'canShare', { configurable: true, value: function (d) { return !!(d && d.files && d.files.length); } });
  Object.defineProperty(navigator, 'share', { configurable: true, value: function () { var e = new Error('closed'); e.name = 'AbortError'; return Promise.reject(e); } });
  window.__dl = null;
  HTMLAnchorElement.prototype.__click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () { if (this.download) { window.__dl = { name: this.download, href: this.href }; return; } return this.__click(); };
  document.getElementById('backupBtn').click();
  return new Promise(function (r) { setTimeout(r, 300); }).then(function () {
    return { last: document.getElementById('backupLast').textContent, stored: HT.backupLast() === null, downloaded: !!window.__dl };
  });
})()
'@
  Write-Host ("  share sheet closed: " + $cancel)
  Check ($cancel -like '*"last":"No backup file made yet."*"stored":true*"downloaded":false*') "R213 GATE: closing the share sheet records NO backup -- none was made -- and does not fall through to a download behind the user's back"

  # ---- the share sheet, a file handed over ------------------------------------------------
  $share = EvalA @'
(function () {
  window.__shared = null;
  Object.defineProperty(navigator, 'share', { configurable: true, value: function (d) {
    window.__shared = { n: d.files.length, name: d.files[0].name, type: d.files[0].type, size: d.files[0].size };
    return d.files[0].text().then(function (t) { window.__sharedText = t; });
  } });
  document.getElementById('backupBtn').click();
  return new Promise(function (r) { setTimeout(r, 400); }).then(function () {
    var j = null; try { j = JSON.parse(window.__sharedText); } catch (e) {}
    return { shared: window.__shared, same: window.__sharedText === window.__before, version: j ? j.version : null, schema: HT.SCHEMA_VERSION,
             days: j ? Object.keys(j.days).length : -1, last: document.getElementById('backupLast').textContent, today: HT.todayKey(),
             downloaded: !!window.__dl, how: (HT.backupLast() || {}).how };
  });
})()
'@
  Write-Host ("  shared: " + $share)
  $sv = $share | ConvertFrom-Json
  $want = 'healthtracker-backup-' + $sv.today + '-v' + $sv.schema + '.json'
  Check (($sv.shared.n -eq 1) -and ($sv.shared.name -eq $want) -and ($sv.shared.name -match '^healthtracker-backup-\d{4}-\d{2}-\d{2}-v\d+\.json$') -and ($sv.shared.type -eq 'application/json')) ("R213 GATE: the share sheet is handed ONE FILE named " + $want + ", as JSON")
  Check (($sv.same -eq $true) -and ($sv.version -eq $sv.schema) -and ($sv.days -ge 1)) "and its bytes are the whole store, at the current format"
  Check (($sv.last -like 'Last backup: *(shared)') -and ($sv.how -eq 'share') -and ($sv.downloaded -eq $false)) "R213 GATE: Settings now reads 'Last backup: <date>'"
  Check (-not ($sv.last -match '(?i)overdue|days ago|remember|should|forget|now')) "NO NAG: the line holds a date and nothing that urges"

  # ---- where a file cannot be shared: a download ----------------------------------------------
  $dl = EvalA @'
(function () {
  Object.defineProperty(navigator, 'canShare', { configurable: true, value: undefined });
  window.__dl = null;
  document.getElementById('backupBtn').click();
  return new Promise(function (r) { setTimeout(r, 300); }).then(function () {
    if (!window.__dl) return { caught: false };
    return fetch(window.__dl.href).then(function (x) { return x.text(); }).then(function (t) {
      window.__dlText = t;
      return { caught: true, name: window.__dl.name, same: t === window.__before, last: document.getElementById('backupLast').textContent, bytes: t.length };
    });
  });
})()
'@
  Write-Host ("  downloaded: " + $dl)
  $dv = $dl | ConvertFrom-Json
  Check (($dv.caught -eq $true) -and ($dv.name -eq $want) -and ($dv.same -eq $true) -and ($dv.last -like 'Last backup: *(downloaded)')) "R213 GATE: with no file sharing, the SAME file is offered as a download -- same name, same bytes -- and the line says it was downloaded"

  # ---- the round trip ------------------------------------------------------------------------------
  $text = EvalJ "window.__dlText"
  $text = $text | ConvertFrom-Json
  $path = Join-Path $env:TEMP $want
  [IO.File]::WriteAllText($path, [string]$text, (New-Object Text.UTF8Encoding($false)))
  [void](Eval "(function(){ localStorage.clear(); return 1; })()")
  Invoke-CDP 'Page.reload' @{ ignoreCache = $false } | Out-Null
  Start-Sleep -Milliseconds 3000
  $empty = EvalJ "(function(){ var S = HT.state(); return { days: Object.keys(S.days).filter(function (k) { return S.days[k].items.length > 0; }).length, stack: (S.settings.stack || []).length, foods: (S.settings.foods || []).length, last: HT.backupLastLine() }; })()"
  Write-Host ("  storage cleared, reloaded: " + $empty)
  Check ($empty -like '*"days":0*"stack":0*"foods":0*"last":"No backup file made yet."*') "PRECONDITION: the site's storage is cleared and the app starts EMPTY -- no food, no stack, no foods, no record of a backup"
  [void](Eval "(function(){ window.confirm = function () { return true; }; HT.openSettings(); document.getElementById('restoreFile').scrollIntoView({ block: 'center' }); return 1; })()")
  $obj = Invoke-CDP 'Runtime.evaluate' @{ expression = "document.getElementById('restoreFile')" }
  Invoke-CDP 'DOM.setFileInputFiles' @{ files = @($path); objectId = $obj.result.result.objectId } | Out-Null
  Settle
  $loaded = EvalJ "(function(){ var b = document.getElementById('importBox'); return { len: b.value.length, toast: document.getElementById('toast').textContent, still: Object.keys(HT.state().days).filter(function (k) { return HT.state().days[k].items.length > 0; }).length }; })()"
  Write-Host ("  the file chosen: " + $loaded)
  $lv = $loaded | ConvertFrom-Json
  Check (($lv.len -eq $dv.bytes) -and ($lv.toast -like ('Loaded ' + $want + '*')) -and ($lv.still -eq 0)) "R213 GATE: the backup FILE, chosen through the real file input, is LOADED -- and nothing is replaced until Restore is tapped"
  [void](Eval "(function(){ var bs = document.querySelectorAll('#settingsPanel button'); for (var i = 0; i < bs.length; i++) if ((bs[i].getAttribute('onclick') || '').indexOf('doRestore') === 0) { bs[i].click(); return 1; } return 0; })()")
  Settle
  $rt = EvalJ @'
(function () {
  var S = HT.state(), t = HT.todayKey(), d = S.days[t] || { items: [] };
  var norm = function (txt) { var o = JSON.parse(txt); delete o.migratedAt; return JSON.stringify(o); };
  return { identical: norm(HT.exportJSON()) === norm(window.__dlTextKeep || HT.exportJSON()), items: d.items.map(function (i) { return i.name + '|' + i.kcal; }),
           stack: (S.settings.stack || []).map(function (s) { return s.name + '|' + s.dose + '|' + s.kind; }), foods: (S.settings.foods || []).map(function (f) { return f.name + '|' + f.basis; }),
           doses: (S.timeline[t] || []).map(function (r) { return r.name + '|' + r.stackKind; }), json: HT.exportJSON() };
})()
'@
  $rv = $rt | ConvertFrom-Json
  $same = ([string]$rv.json) -eq ([string]$text)
  Write-Host ("  restored: items " + (@($rv.items) -join ', ') + " ; stack " + (@($rv.stack) -join ', ') + " ; foods " + (@($rv.foods) -join ', ') + " ; doses " + (@($rv.doses) -join ', ') + " ; identical " + $same)
  Check (($rv.items -contains 'Gate lunch|520') -and ($rv.stack -contains 'Gate capsule|300|supplement') -and ($rv.foods -contains 'Gate seed oil|label') -and ($rv.doses -contains 'Gate capsule|supplement')) "R213 GATE: ROUND TRIP -- the food, the stack, my foods and the logged dose are all back"
  Check $same "R213 GATE: and a new export of the restored app is BYTE-IDENTICAL to the file it was restored from"
  $st = EvalJ @'
(function () {
  var b = JSON.parse(sessionStorage.getItem('__r2271') || '{}');
  HT.setClock(function () { return b.clock; });
  HT.closeSettings && HT.closeSettings(); HT.refresh();
  var t = HT.todayKey();
  var gh = document.querySelector('#dayView .ghead'); if (gh) gh.click();
  var chart = document.querySelector('#dayView .tchartbox');
  var rises = HT.eliteDay(t);
  return { glucose: JSON.stringify(HT.glucoseRead()) === b.g, gDays: Object.keys(HT.glucoseRead()).length,
           steps: JSON.stringify(HT.stepsRead()) === b.s, src: (HT.glucoseRead()[t] || {}).src || '',
           rises: JSON.stringify(rises) === b.rises, nRises: (rises && rises.rises) ? rises.rises.length : (Array.isArray(rises) ? rises.length : -1),
           chart: !!chart && chart.innerHTML === b.chart && b.chart.length > 100 };
})()
'@
  Write-Host ("  the streams after the round trip: " + $st)
  $sv2 = $st | ConvertFrom-Json
  Check ($sv2.glucose -and ($sv2.gDays -ge 1) -and ($sv2.src -eq 'Gate CGM') -and $sv2.steps) "R227.1 GATE: EXPORT -> WIPE -> RESTORE brings the imported GLUCOSE and STEPS back, identical, with their source"
  Check ($sv2.rises -and ($sv2.nRises -ge 1)) "R227.1 GATE: the E-lite RISES are identical to before ($($sv2.nRises) flagged)"
  Check $sv2.chart "R227.1 GATE: and the GLUCOSE CHART renders identically -- the same drawing, byte for byte"
  try { Remove-Item $path -Force -ErrorAction SilentlyContinue } catch { }

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("BACKUP GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "BACKUP GATE: PASS -- Export backup hands the share sheet one dated file, falls back to a"
Write-Host "  download, records nothing when the sheet is closed, shows the last backup"
Write-Host "  with no urging, and a restore from that file gives back the same bytes."
Write-Host "GATE: PASS"
exit 0
