# R269 Part 2 -- EVERY CLOSE CONTROL IS A 44 x 44 PX TAP TARGET. Measured at 390 px.
#
#   The x on Settings and on + Log was 28 px tall (found by weekly-gate, R265.1);
#   only the weekly review's had been made 44. This gate takes its list of close
#   controls FROM THE SOURCE (a button showing an x, or saying close / dismiss in
#   its text, aria-label or title), opens every surface that holds one, measures
#   each as the browser lays it out, and fails if any is under 44 x 44 -- or if a
#   close control in the source was never measured, so a new one cannot slip by.
#
# Synthetic data only. Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8385
$Dbg = 9585
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-close-" + [System.Guid]::NewGuid().ToString('N'))
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
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
    # R271: a held corpus download is an EVENT; kept, so the gate can release it.
    if ($msg.method -eq 'Fetch.requestPaused') { $script:paused += $msg.params.requestId } } }
$script:paused = @()
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

# Set CLOSE_SHOTS=1 to save 390px screenshots to %TEMP%\close-shots.
$shots = $null
if ($env:CLOSE_SHOTS) { $shots = Join-Path $env:TEMP 'close-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
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

  $boot = Eval "typeof HT === 'object' && typeof HT.openSheet === 'function' && typeof HT.openSettings === 'function' && typeof HT.renderVersionNotice === 'function' && typeof HT.byokBusy === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the surfaces' open functions are not on HT"; Cleanup; exit 2 }

  # ---- R271: CLOSED WHILE LOADING STAYS CLOSED ----------------------------------------------
  # Found by this gate (R269): a Find-nutrients panel closed while its database was
  # still loading opened again when the database answered. Run FIRST, on a fresh
  # profile, so the corpus is not yet on the device; its download is HELD by CDP
  # (Fetch) so the panel is provably still loading when the close link is TAPPED,
  # then released, and the panel must stay closed.
  # (the service worker fetches for the page from its own target, out of this one's
  # sight, so the page bypasses it for this check)
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Network.setBypassServiceWorker' @{ bypass = $true } | Out-Null
  Invoke-CDP 'Fetch.enable' @{ patterns = @(@{ urlPattern = '*corpus/dist/*' }) } | Out-Null
  $o271 = EvalJ @'
(function(){ var S = HT.state(), dk = HT.todayKey();
  S.days[dk] = S.days[dk] || { status: 'in_progress', water_l: 0, items: [] };
  S.days[dk].items.push({ name: 'Gate soup', meal: 'lunch', time: '12:00', grams: 250, unresolved: true, source: 'ai-paste', confidence: 'eyeballed', notes: '' });
  HT.resave(); HT.goToDay(dk); HT.refresh();
  window.__r271 = null;
  HT.resolveOpen(dk, S.days[dk].items.length - 1).then(function (r) { window.__r271 = r || {}; });
  return 1; })()
'@
  for ($w = 0; $w -lt 40 -and $script:paused.Count -eq 0; $w++) { [void](Eval "1"); Start-Sleep -Milliseconds 100 }
  $held = $script:paused.Count
  $pre271 = (EvalJ "(function(){ var v = HT.resolveView(); var b = document.querySelector('#resolveBox .rvbox .xclose'); if (b) b.scrollIntoView({ block: 'center' }); var r = b ? b.getBoundingClientRect() : null; return { phase: v ? v.phase : null, x: r ? r.left + r.width / 2 : -1, y: r ? r.top + r.height / 2 : -1 }; })()") | ConvertFrom-Json
  Check (($held -gt 0) -and ($pre271.phase -eq 'loading') -and ($pre271.x -ge 0)) "R271: the panel is open and LOADING -- the corpus download is held ($held request(s)), the close link is on screen"
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $pre271.x; y = $pre271.y }) } | Out-Null
  Start-Sleep -Milliseconds 40
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
  # R283: the download is HELD here on purpose, so the page cannot be quiet; what the next
  # check needs is the tap drawn -- two frames.
  [void](Invoke-CDP 'Runtime.evaluate' @{ expression = 'new Promise(function (r) { requestAnimationFrame(function () { requestAnimationFrame(function () { r(1); }); }); })'; awaitPromise = $true; returnByValue = $true })
  $mid271 = Eval "JSON.stringify({ open: !!HT.resolveView(), box: !!document.querySelector('#resolveBox .rvbox') })" | ConvertFrom-Json
  Check ((-not $mid271.open) -and (-not $mid271.box)) "R271: one tap on close closes it while the database is still loading"
  # release the download (and any that follow), then wait for the database to answer
  for ($w = 0; $w -lt 100; $w++) {
    $ids = $script:paused; $script:paused = @()
    foreach ($id in $ids) { Invoke-CDP 'Fetch.continueRequest' @{ requestId = $id } | Out-Null }
    $done = Eval "window.__r271 ? JSON.stringify(window.__r271) : ''"
    if ($done) { break }
    Start-Sleep -Milliseconds 150 }
  Invoke-CDP 'Fetch.disable' $null | Out-Null
  Invoke-CDP 'Network.setBypassServiceWorker' @{ bypass = $false } | Out-Null
  Invoke-CDP 'Network.disable' $null | Out-Null
  Settle
  $post271 = Eval "JSON.stringify({ open: !!HT.resolveView(), box: !!document.querySelector('#resolveBox .rvbox'), why: (window.__r271 || {}).why || '' })" | ConvertFrom-Json
  Check ([bool]$done -and (-not $post271.open) -and (-not $post271.box)) ("R271 GATE: closed while loading, the Find-nutrients panel STAYS closed when the database answers (answered: " + $done + ")")
  [void](Eval "(function(){ var S = HT.state(), dk = HT.todayKey(); S.days[dk].items = S.days[dk].items.filter(function (x) { return x.name !== 'Gate soup'; }); HT.resave(); HT.refresh(); return 1; })()"); Settle

  # ---- 0. THE CENSUS, FROM THE SOURCE: every control that closes or dismisses ----------
  # A close control is a button that shows an x (the multiplication sign, by
  # codepoint) or says "close" / "dismiss" in its text, aria-label or title. Its
  # handler name is what ties the source to the page: each one found here must be
  # MEASURED below, on a rendered surface, or the gate fails naming it -- a new
  # close button cannot arrive unmeasured.
  $srcText = [IO.File]::ReadAllText((Join-Path $repo 'app.js')) + [IO.File]::ReadAllText((Join-Path $repo 'index.html'))
  $xs = [string][char]0x00d7
  $expected = @{}
  foreach ($m in [regex]::Matches($srcText, '<button\b[^>]*>[^<]{0,40}</button>')) {
    $tag = $m.Value
    $oc = [regex]::Match($tag, 'onclick="(?:event\.stopPropagation\(\);)?([A-Za-z_][A-Za-z0-9_]*)\(')
    if (-not $oc.Success) { continue }
    $fn = $oc.Groups[1].Value
    $inner = [regex]::Match($tag, '>([^<]*)</button>$').Groups[1].Value.Trim()
    $lab = ([regex]::Match($tag, 'aria-label="([^"]*)"').Groups[1].Value + ' ' + [regex]::Match($tag, 'title="([^"]*)"').Groups[1].Value).ToLower()
    $isX = (($inner -eq $xs) -or ($inner -eq '&times;') -or ($inner -eq '\u00d7')) -and ($fn -match '(?i)close|dismiss')
    $isWord = ($inner -match '^(?i)close$') -or ($lab -match '\b(close|dismiss)\b')
    if ($isX -or $isWord) { $expected[$fn] = $true }
  }
  $expNames = @($expected.Keys | Sort-Object)
  Write-Host ("  census: " + $expNames.Count + " close controls in the source: " + ($expNames -join ', '))
  Check ($expNames.Count -ge 8) "R269 census: the source's close controls are found (the x on + Log, Settings, the weekly review and the capture outcome, the version notice's x, and the close links of the resolve panel, the clinician summary and the drug label)"

  # The SAME rule, applied to the rendered page: every close control on screen, with
  # its tap target as the browser lays it out (getBoundingClientRect, not a CSS value).
  $measureJs = @'
(function (surface) {
  var xs = '\u00d7';
  var out = [];
  Array.prototype.forEach.call(document.querySelectorAll('button'), function (b) {
    var t = (b.textContent || '').trim();
    var oc = b.getAttribute('onclick') || '';
    var fm = oc.replace(/^event\.stopPropagation\(\);/, '').match(/^([A-Za-z_][A-Za-z0-9_]*)\(/);
    var fn = fm ? fm[1] : '';
    var lab = ((b.getAttribute('aria-label') || '') + ' ' + (b.getAttribute('title') || '')).toLowerCase();
    var isX = t === xs && /close|dismiss/i.test(fn);
    var isWord = /^close$/i.test(t) || /\b(close|dismiss)\b/.test(lab);
    if (!(isX || isWord)) return;
    var r = b.getBoundingClientRect();
    if (!(r.width > 0 && r.height > 0)) return;
    out.push({ surface: surface, fn: fn, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10 });
  });
  return out;
})
'@
  $script:measured = @()
  function MeasureOn([string]$surface) {
    $r = EvalJ ($measureJs + "('" + $surface + "')")
    $rows = @()
    foreach ($row in ($r | ConvertFrom-Json)) { $rows += $row }
    foreach ($row in $rows) { Write-Host ("    " + $surface + ": " + $row.fn + " " + $row.w + " x " + $row.h) }
    $script:measured += $rows
    return $rows.Count }

  # ---- 1. each surface opened, its close controls measured ------------------------------
  [void](Eval "HT.openSheet('root')"); Settle
  $n1 = MeasureOn '+ Log'
  Shot 'plus-log'
  [void](Eval "HT.closeSheet()"); Settle

  [void](Eval "HT.openSettings()"); Settle
  $n2 = MeasureOn 'Settings'
  Shot 'settings'
  # the drug label opens INSIDE Settings, under Medications (a synthetic med)
  [void](Eval "(function(){ var S = HT.state(); S.meds = S.meds || {}; S.meds['gatemed1'] = { id: 'gatemed1', printed: { name: 'Gate medicine' }, fills: [] }; var d = document.getElementById('medsDetails'); if (d) d.open = true; HT.renderMeds(); HT.drugOpen('gatemed1'); return 1; })()"); Settle
  [void](Eval "(function(){ var e = document.getElementById('drugInfo'); if (e) e.scrollIntoView({ block: 'center' }); return 1; })()"); Settle
  $n3 = MeasureOn 'Settings > Medications > drug label'
  Shot 'drug-label'
  [void](Eval "HT.drugClose(); HT.closeSettings()"); Settle

  [void](Eval "HT.openWeek()"); Settle
  $n4 = MeasureOn 'Weekly review'
  [void](Eval "HT.closeWeek()"); Settle

  [void](Eval "HT.byokBusy('error', 'Gate: the provider did not answer')"); Settle
  $n5 = MeasureOn 'Capture outcome (failure)'
  Shot 'outcome'
  [void](Eval "HT.byokBusyClear()"); Settle

  [void](Eval "HT.renderVersionNotice({ to: '0.111.0', from: '0.110.0', notes: [{ v: '0.111.0', note: 'Gate note' }] })"); Settle
  [void](Eval "(function(){ var e = document.getElementById('versionNotice'); if (e) e.scrollIntoView({ block: 'center' }); return 1; })()"); Settle
  $n6 = MeasureOn 'Version notice'
  Shot 'version-notice'
  [void](Eval "HT.dismissVersionNotice()"); Settle

  # the resolve panel, on a synthetic not-counted item (its loading phase carries the link)
  # (awaited: closed while still loading, the panel comes back when the database answers)
  [void](EvalA "(function(){ var S = HT.state(), dk = HT.todayKey(); S.days[dk] = S.days[dk] || { status: 'in_progress', water_l: 0, items: [] }; S.days[dk].items.push({ name: 'Gate stew', meal: 'dinner', time: '18:00', grams: 300, unresolved: true, source: 'ai-paste', confidence: 'eyeballed', notes: '' }); HT.resave(); HT.goToDay(dk); HT.refresh(); return HT.resolveOpen(dk, S.days[dk].items.length - 1).then(function () { return 1; }); })()"); Settle
  $n7 = MeasureOn 'Find nutrients (resolve)'
  Shot 'resolve'
  [void](Eval "HT.resolveClose()"); Settle

  # the clinician summary, inside Nights (opened as a tap on its summary would)
  [void](Eval "(function(){ var n = document.getElementById('nights'); var d = n && n.closest('details'); if (d) d.open = true; HT.openClinicianSummary(); var c = document.querySelector('#nights .xclose'); if (c) c.scrollIntoView({ block: 'center' }); return 1; })()"); Settle
  $n8 = MeasureOn 'Nights > clinician summary'
  Shot 'clinician'
  [void](Eval "HT.closeClinicianSummary()"); Settle

  # R279: the log confirmation at the top of the screen, after a scan or photo log
  [void](Eval "HT.logConfirmShow([{ name: 'Gate seeds', grams: 30, time: '12:00' }], function () {})"); Settle
  $n9 = MeasureOn 'Log confirmation (R279)'
  Shot 'log-confirm'
  [void](Eval "HT.logConfirmHide()"); Settle
  # R298: the context strip's x, on the strip as an action leaves it (an opened item)
  [void](Eval "(function(){ var S = HT.state(), dk = HT.state().current; S.days[dk] = S.days[dk] || { status: 'in_progress', water_l: 0, items: [] }; S.days[dk].items.push({ name: 'Gate strip', meal: 'lunch', time: '12:00', kcal: 100, protein_g: 1, fat_g: 1, carb_g: 1, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }); HT.resave(); HT.ctxNoteSet({ kind: 'open', dk: dk, item: { i: S.days[dk].items.length - 1, name: 'Gate strip', time: '12:00' } }); HT.refresh(); window.scrollTo(0, 0); return 1; })()"); Settle
  $n10 = MeasureOn 'Context strip (R298)'
  Shot 'context-strip'
  [void](Eval "HT.ctxDismiss()"); Settle

  # ---- 2. the verdicts -------------------------------------------------------------------
  $small = @($script:measured | Where-Object { ($_.w -lt 44) -or ($_.h -lt 44) })
  foreach ($s in $small) { Write-Host ("    UNDER 44: " + $s.surface + " " + $s.fn + " " + $s.w + " x " + $s.h) }
  Check ($script:measured.Count -ge 8) ("R269: close controls were measured on the rendered surfaces (" + $script:measured.Count + ")")
  Check ($small.Count -eq 0) "R269 GATE: EVERY close control on every surface is a tap target of at least 44 x 44 px, as laid out at 390 px"
  $seen = @{}
  foreach ($row in $script:measured) { $seen[[string]$row.fn] = $true }
  $unmeasured = @($expNames | Where-Object { -not $seen.ContainsKey($_) })
  foreach ($u in $unmeasured) { Write-Host ("    NOT MEASURED: " + $u) }
  Check ($unmeasured.Count -eq 0) "R269 GATE: every close control the SOURCE holds was measured on a rendered surface -- none arrives unmeasured"
  $xOnSheets = @($script:measured | Where-Object { $_.fn -in @('closeSheet', 'closeSettings') })
  Check (($xOnSheets.Count -ge 2) -and (@($xOnSheets | Where-Object { $_.h -ge 44 -and $_.w -ge 44 }).Count -eq $xOnSheets.Count)) "R269 GATE: the x on + Log and on Settings (28 px tall before) are 44 x 44"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("CLOSE GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "CLOSE GATE: PASS -- every close control the source holds was found on its rendered surface and"
Write-Host "  measured at 390 px: each tap target is at least 44 x 44 px."
Write-Host "GATE: PASS"
exit 0
