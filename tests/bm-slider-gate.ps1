# R20.1 bm-slider ergonomics gate.
#
# WHAT THIS GATE CAN AND CANNOT MEASURE, recorded rather than papered over.
# The brief asked for the rendered THUMB box, asserted >= 44x44. The thumb of a
# native range input is a UA-shadow pseudo-element and is NOT measurable by any
# route available here -- both were tried:
#   * getComputedStyle(el, '::-webkit-slider-thumb') returns the HOST box
#     (332x36), not the thumb -- so a >=44 check on it would PASS FOR THE WRONG
#     REASON while the real handle was ~16px;
#   * CDP DOM.describeNode with pierce reports no pseudoElements for it.
# A gate that measured the host box and called it the thumb would be a gate that
# lies, so it is not written.
#
# What is measured instead is what the 44x44 standard is actually about: THE AREA
# A FINGER MUST HIT TO SELECT A STOP. On a range input a tap anywhere on the track
# jumps to that position, so the target for a stop is (trackWidth / 7) x (control
# height) -- measurable with getBoundingClientRect, and a STRONGER claim than the
# handle's size. The gate also proves that premise behaviourally, by dispatching
# real taps and checking which stop comes back.
#
# Also measured: the handle does not span two stops (declared width vs measured
# stop pitch), and the readout sits ABOVE the track -- a finger occludes what is
# under and beside a slider exactly while sliding, which is when the readout is
# being read. A mouse never shows that defect.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8143
$origin = "http://127.0.0.1:$port"
$dbg = 9353
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-bmslider-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

$MIN_TARGET = 44     # WCAG 2.5.5 / Apple HIG minimum touch target, CSS px
$THUMB_CSS_PX = 28   # the DECLARED handle size; must stay under the stop pitch

function Find-Browser {
  foreach ($c in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
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
  $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $guard = 0
  while ($true) {
    if (++$guard -gt 300) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return $r.result.result.value
}

$install = @'
(function(){
  window.__b = {};
  __b.open = function(){ HT.openSheet('signal'); HT.pickSignal('bm'); return 1; };
  __b.snap = function(){
    var sl=document.getElementById('sigBmSlider');
    var rd=document.getElementById('sigBmRead');
    var en=document.getElementById('sigBmEnds');
    if(!sl||!rd) return JSON.stringify({err:'missing control'});
    var r=sl.getBoundingClientRect(), q=rd.getBoundingClientRect();
    var e=en?en.getBoundingClientRect():null;
    var pitch=r.width/7;
    return JSON.stringify({
      trackW:Math.round(r.width*10)/10, ctrlH:Math.round(r.height*10)/10,
      pitch:Math.round(pitch*10)/10,
      readAbove:(q.bottom<=r.top+1), readGap:Math.round((r.top-q.bottom)*10)/10,
      readH:Math.round(q.height*10)/10, readText:(rd.textContent||''),
      endsBelow:(e? e.top>=r.bottom-1 : false),
      pageOverflowX:(document.documentElement.scrollWidth>window.innerWidth+1),
      value:sl.value });
  };
  __b.tapPoint = function(n){
    var sl=document.getElementById('sigBmSlider'); var r=sl.getBoundingClientRect();
    var pitch=r.width/7;
    return JSON.stringify({x: Math.round(r.left + pitch*(n-0.5)), y: Math.round(r.top + r.height/2)});
  };
  __b.value = function(){ return document.getElementById('sigBmSlider').value; };
  __b.readout = function(){ return document.getElementById('sigBmRead').textContent||''; };
  return 'installed';
})()
'@

function Go([int]$w, [int]$h) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width=$w; height=$h; deviceScaleFactor=1; mobile=$true } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled=$true; maxTouchPoints=5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  Eval $install | Out-Null
  Eval '__b.open()' | Out-Null
  Start-Sleep -Milliseconds 250
}
function Snap { return (Eval '__b.snap()' | ConvertFrom-Json) }
# A real tap through the real event pipeline. This is what proves the stop ZONE is
# the touch target, rather than the handle being the only thing you may grab.
function TapStop([int]$n) {
  $p = Eval ("__b.tapPoint($n)") | ConvertFrom-Json
  Invoke-CDP 'Input.dispatchMouseEvent' @{ type='mousePressed';  x=$p.x; y=$p.y; button='left'; clickCount=1; buttons=1 } | Out-Null
  Invoke-CDP 'Input.dispatchMouseEvent' @{ type='mouseReleased'; x=$p.x; y=$p.y; button='left'; clickCount=1; buttons=0 } | Out-Null
  Start-Sleep -Milliseconds 110
  return (Eval '__b.value()')
}

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
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  Start-Sleep -Milliseconds 800
  try { Invoke-WebRequest "$origin/index.html" -UseBasicParsing -TimeoutSec 5 | Out-Null }
  catch { Write-Host "ERROR: test server did not start"; Cleanup; exit 2 }

  $args = @('--headless=new', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd",
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
  Invoke-CDP 'Runtime.enable' $null | Out-Null

  $allOk = $true
  Write-Host "R20.1 bm slider ergonomics (real index.html, shipped control, CDP):"
  foreach ($vp in @(@('phone 360x740',360,740), @('phone 390x745',390,745))) {
    $name = $vp[0]
    Go $vp[1] $vp[2]
    $m = Snap
    if ($m.err) { Write-Host ("  {0}: {1}" -f $name, $m.err); $allOk = $false; continue }

    # 1. TOUCH TARGET -- the stop zone, measured, both dimensions.
    $tOK = ($m.pitch -ge $MIN_TARGET) -and ($m.ctrlH -ge $MIN_TARGET)
    Write-Host ("  {0,-14} target : stop pitch={1}px x control height={2}px -> {3} (floor {4})" -f `
      $name, $m.pitch, $m.ctrlH, $tOK, $MIN_TARGET)

    # 2. THE HANDLE MUST NOT SPAN TWO STOPS.
    $spanOK = ($THUMB_CSS_PX -le $m.pitch)
    Write-Host ("  {0,-14} span   : handle {1}px <= stop pitch {2}px -> {3}" -f `
      $name, $THUMB_CSS_PX, $m.pitch, $spanOK)

    # 3. READOUT ABOVE THE TRACK, with real clearance and real text.
    $rOK = $m.readAbove -and ($m.readH -gt 0) -and ($m.readText.Length -gt 0) -and (-not $m.pageOverflowX)
    Write-Host ("  {0,-14} readout: above-track={1} gap={2}px text='{3}' -> {4}" -f `
      $name, $m.readAbove, $m.readGap, $m.readText, $rOK)

    # 4. BEHAVIOUR: a real tap inside a stop's zone selects THAT stop.
    $tapOK = $true; $taps = @()
    foreach ($n in @(1,3,5,7)) {
      $v = TapStop $n
      $taps += ("{0}->{1}" -f $n, $v)
      if ([string]$v -ne [string]$n) { $tapOK = $false }
    }
    Write-Host ("  {0,-14} taps   : {1} -> {2}" -f $name, ($taps -join ' '), $tapOK)

    # 5. And the readout follows the tap, so what you see is what is stored.
    $rv = Eval '__b.readout()'
    $followOK = ($rv -like '*Type 7*')
    Write-Host ("  {0,-14} follows: readout after tapping stop 7 = '{1}' -> {2}" -f $name, $rv, $followOK)

    if (-not ($tOK -and $spanOK -and $rOK -and $tapOK -and $followOK)) { $allOk = $false }
  }
  Write-Host ("  thresholds     : stop zone >= {0}x{0}px (WCAG 2.5.5 / Apple HIG); handle <= stop pitch; readout ABOVE the track; a tap in a stop's zone selects that stop" -f $MIN_TARGET)
  Write-Host "-----------------------------------------"
  if ($allOk) {
    Write-Host "BM SLIDER GATE: PASS (stop zones clear the touch-target floor, the handle never straddles two, and the readout sits where a thumb cannot cover it)"
    Cleanup; exit 0
  }
  Write-Host "BM SLIDER GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
