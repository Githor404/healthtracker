# Lab-panel form density gate (D34; the v0.10.1 phone-width fix).
#
# The v0.10.0 harness asserted "14 analyte rows rendered" -- which passed while
# the form was unusable on a phone: four controls per row at 380px squeezed the
# value field to a sliver and truncated the longer analyte names. Same class of
# miss as the v0.4.1 chip smoke ("14 chips rendered" while 10 were unreachable),
# so it gets the same answer: measure the property that actually matters.
#
# Here that property is USABLE DENSITY at phone width -- every control wide
# enough to type into, no analyte name truncated, and nothing overflowing
# horizontally. CDP measures the REAL index.html at three widths.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8129
$origin = "http://127.0.0.1:$port"
$dbg = 9339
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-labform-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

# Minimums for a field a human transcribes numbers into on a phone.
$MIN_VALUE = 88   # the value input
$MIN_REF   = 56   # each reference-interval input
$MIN_UNIT  = 74   # the unit select

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
  $json = $payload | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $guard = 0
  while ($true) {
    if (++$guard -gt 300) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  return $r.result.result.value
}

$measure = "(function(){try{HT.openSheet('lab');}catch(e){}" +
  "var host=document.getElementById('labRows');if(!host)return JSON.stringify({err:'no-form'});" +
  "var q=function(s){return [].slice.call(host.querySelectorAll(s));};" +
  "var vals=q('input[id^=\""lab_v_\""]'),los=q('input[id^=\""lab_lo_\""]'),his=q('input[id^=\""lab_hi_\""]'),sels=q('select');" +
  "var refs=los.concat(his);" +
  "var w=function(e){return Math.round(e.getBoundingClientRect().width);};" +
  "var minW=function(a){return a.length?Math.min.apply(null,a.map(w)):0;};" +
  "var names=q('.labfname');" +
  "var trunc=names.filter(function(e){return e.scrollWidth>e.clientWidth+1;}).length;" +
  "var body=document.querySelector('.sheetbody');" +
  "return JSON.stringify({rows:q('.labfrow').length||host.children.length," +
  "nVal:vals.length,nRef:refs.length,nSel:sels.length,nName:names.length," +
  "minVal:minW(vals),minRef:minW(refs),minSel:minW(sels),truncNames:trunc," +
  "bodyOverflow:(body?(body.scrollWidth>body.clientWidth+1):true)," +
  "pageOverflow:(document.documentElement.scrollWidth>window.innerWidth+1)});})()"

function Measure-Form([int]$w, [int]$h, [bool]$mobile, [bool]$touch) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  if ($touch) { Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null }
  else        { Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $false } | Out-Null }
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1400
  return (Eval $measure | ConvertFrom-Json)
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

  $A = Measure-Form 360 780 $true  $true    # small phone -- the hard case
  $B = Measure-Form 390 800 $true  $true    # common phone
  $C = Measure-Form 900 900 $false $false   # desktop

  function Test-One($m) {
    return ($m.rows -eq 14) -and ($m.nVal -eq 14) -and ($m.nRef -eq 28) -and
           ($m.minVal -ge $MIN_VALUE) -and ($m.minRef -ge $MIN_REF) -and ($m.minSel -ge $MIN_UNIT) -and
           ($m.truncNames -eq 0) -and (-not $m.bodyOverflow) -and (-not $m.pageOverflow)
  }
  $A_ok = Test-One $A
  $B_ok = Test-One $B
  $C_ok = Test-One $C

  Write-Host "lab-panel form density (real index.html, CDP device emulation):"
  foreach ($p in @(@('A phone 360px', $A, $A_ok), @('B phone 390px', $B, $B_ok), @('C desktop 900px', $C, $C_ok))) {
    $n = $p[0]; $m = $p[1]; $ok = $p[2]
    Write-Host ("  {0,-16}: rows={1} value>={2}px ref>={3}px unit>={4}px truncated={5} overflow={6} -> {7}" -f `
      $n, $m.rows, $m.minVal, $m.minRef, $m.minSel, $m.truncNames, ([bool]$m.bodyOverflow -or [bool]$m.pageOverflow), $ok)
  }
  Write-Host ("  thresholds       : value>={0} ref>={1} unit>={2}, zero truncated names, no horizontal overflow" -f $MIN_VALUE, $MIN_REF, $MIN_UNIT)
  Write-Host "-----------------------------------------"

  if ($A_ok -and $B_ok -and $C_ok) {
    Write-Host "LAB FORM GATE: PASS (every control typable at 360px; no name truncated; no horizontal overflow)"
    Cleanup; exit 0
  }
  Write-Host "LAB FORM GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
