# Quick-log chip reachability gate (D21 Layer-1; the v0.4.3 desktop-scroll fix).
#
# The v0.4.1/0.4.2 smoke asserted "14 chips rendered" -- which passed while ~10
# were unreachable on desktop (horizontal strip that only scrolls by touch). This
# gate asserts the property that actually matters: REACHABILITY.
#
# CDP emulates two devices against the REAL index.html and measures the strip:
#   A. mouse, narrow window (380px, mobile:false, touch off) -> pointer:fine/hover:hover
#      => must WRAP: no horizontal overflow, >1 row, ZERO clipped chips.
#   B. touch phone (380px, mobile:true, touch on)            -> pointer:coarse/hover:none
#      => must stay a one-row SCROLL strip (overflow present) -- reachable by swipe.
#   C. mouse, wide window (1100px)                            => must WRAP too.
# A at 380px is the key case: it proves the fix is pointer-based, so a NARROW
# desktop window wraps (a width-only breakpoint would strand the mouse there).
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8127
$origin = "http://127.0.0.1:$port"
$dbg = 9337
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-chiptest-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

function Find-Browser {
  foreach ($cv in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $cv) { return $cv } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 16384
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count)
    if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$method, [hashtable]$prms) {
  $script:cid++
  $payload = @{ id = $script:cid; method = $method }
  if ($prms) { $payload.params = $prms }
  $json = $payload | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $guard = 0
  while ($true) {
    if (++$guard -gt 300) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }   # skip events
  }
}
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
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  return $r.result.result.value
}

# Emulate a device, load the real page fresh, and measure the chip strip.
# D30: the quick-log chips moved into the + sheet's "log event or biometric"
# entry, so the strip must be OPENED before it can be measured. The assertion is
# unchanged -- every chip still has to be reachable (wrap on mouse, scroll on
# touch); only where the strip lives changed.
$measure = "(function(){try{HT.openSheet('signal');}catch(e){}var el=document.getElementById('sigChips');if(!el)return JSON.stringify({err:'no-strip'});var c=el.querySelectorAll('.chip');var sb=el.getBoundingClientRect();var rows={};var clipped=0;for(var i=0;i<c.length;i++){var r=c[i].getBoundingClientRect();rows[Math.round(c[i].offsetTop)]=1;if(r.right>sb.right+2||r.left<sb.left-2)clipped++;}var bm=null;for(var j=0;j<c.length;j++){if((c[j].textContent||'').indexOf('Bowel movement')>=0){bm=c[j];break;}}var bmr=bm?bm.getBoundingClientRect():null;return JSON.stringify({n:c.length,rows:Object.keys(rows).length,overflow:(el.scrollWidth>el.clientWidth+1),clipped:clipped,bmFound:!!bm,bmIdx:bm?Array.prototype.indexOf.call(c,bm):-1,bmReachable:!!bmr&&bmr.left>=sb.left-1&&bmr.right<=sb.right+1,scrollLeft:Math.round(el.scrollLeft)});})()"

function Measure-Strip([int]$w, [int]$h, [bool]$mobile, [bool]$touch) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  if ($touch) { Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null }
  else        { Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $false } | Out-Null }
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  return (Eval $measure | ConvertFrom-Json)
}

# The chip COUNT is pinned deliberately, the same discipline as
# EXPECTED_ASSERTIONS: a chip that appears or vanishes must be a decision, not a
# drift. Bumped 14 -> 15 by D52/R20, which adds `bm` in the first six -- the touch
# strip is one scrolling row, so where a chip sits is the whole question.
$EXPECT_CHIPS = 15

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
  $mimes = @{ '.html' = 'text/html'; '.js' = 'application/javascript'; '.json' = 'application/json'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.css' = 'text/css' }
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
    try { $ctx.Response.Close() } catch { }
  }
}

function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  WaitServer "$origin/index.html"

  $args = @('--headless=new', '--disable-extensions', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-default-apps', '--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion', '--mute-audio', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd",
            "--remote-debugging-port=$dbg", '--remote-allow-origins=*', 'about:blank')
  $chrome = Start-Process $browser -PassThru -ArgumentList $args

  $wsUrl = $null
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 300
    try {
      $targets = Invoke-RestMethod "http://127.0.0.1:$dbg/json" -TimeoutSec 2
      $pg = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg -and $pg.webSocketDebuggerUrl) { $wsUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $wsUrl) { Write-Host "ERROR: could not reach Chrome debugging endpoint"; Cleanup; exit 2 }

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$wsUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null    | Out-Null
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null

  $A = Measure-Strip 380  900 $false $false   # mouse, narrow desktop window
  $B = Measure-Strip 380  800 $true  $true    # touch phone
  $C = Measure-Strip 1100 900 $false $false   # mouse, wide desktop

  $A_ok = ($A.n -eq $EXPECT_CHIPS) -and $A.bmFound -and $A.bmReachable -and (-not $A.overflow) -and ($A.rows -gt 1) -and ($A.clipped -eq 0)
  $B_ok = ($B.n -eq $EXPECT_CHIPS) -and $B.bmFound -and $B.bmReachable -and ($B.scrollLeft -eq 0) -and ($B.overflow) -and ($B.rows -eq 1)
  $C_ok = ($C.n -eq $EXPECT_CHIPS) -and $C.bmFound -and $C.bmReachable -and (-not $C.overflow) -and ($C.rows -gt 1) -and ($C.clipped -eq 0)

  Write-Host "chip reachability (real index.html, CDP device emulation):"
  Write-Host ("  A mouse/narrow 380px : wrapped={0} rows={1} clipped={2} -> {3}" -f (-not $A.overflow), $A.rows, $A.clipped, $A_ok)
  Write-Host ("  B touch/phone  380px : scrolls={0} rows={1}            -> {2}" -f [bool]$B.overflow, $B.rows, $B_ok)
  Write-Host ("  bm chip (D52/R20)    : idx={0} reachable-unscrolled={1} (touch strip is ONE scrolling row, so placement IS reachability)" -f $B.bmIdx, $B.bmReachable)
  Write-Host ("  C mouse/wide  1100px : wrapped={0} rows={1} clipped={2} -> {3}" -f (-not $C.overflow), $C.rows, $C.clipped, $C_ok)
  Write-Host "-----------------------------------------"

  if ($A_ok -and $B_ok -and $C_ok) {
    Write-Host "CHIP LAYOUT GATE: PASS (mouse wraps to all-reachable rows incl. narrow window; touch keeps the one-row scroll strip)"
    Cleanup; exit 0
  }
  Write-Host "CHIP LAYOUT GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
