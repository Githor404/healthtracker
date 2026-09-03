# R6.1 confirm-first layout gate.
#
# "Confirm-first, sliders-second" is a LAYOUT claim, so it gets measured as one:
# the question must sit ABOVE the adjustable list, not merely exist in the DOM.
# A gate that only asserted "a lead card rendered" would pass with the card at
# the bottom of the sheet -- the same class of miss as the v0.10.0 lab form
# ("14 rows rendered" while unusable) and the v0.4.1 chip smoke.
#
# Also measured: the confirm button is a real thumb target, the question is not
# clipped, and nothing overflows sideways at phone width. CDP, real index.html.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8133
$origin = "http://127.0.0.1:$port"
$dbg = 9343
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-photolead-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

# A confirm button is the primary thumb target of the whole flow.
$MIN_BTN_H = 40   # tap height
$MIN_BTN_W = 200  # it spans the card, not a token corner button
$MIN_SLIDER = 90  # the correct-instead affordance stays usable in the same card

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

$measure = "(function(){try{HT.openSheet('photo');}catch(e){return JSON.stringify({err:'no-sheet'});}" +
  "var box=document.getElementById('ingestBox');if(!box)return JSON.stringify({err:'no-box'});" +
  "box.value=HT.AI_PROMPT_SAMPLE;try{doPhotoPaste();}catch(e){return JSON.stringify({err:'paste:'+e.message});}" +
  "var lead=document.querySelector('.pmlead');if(!lead)return JSON.stringify({err:'no-lead'});" +
  "var q=lead.querySelector('.pmq'),btn=lead.querySelector('.pmok'),sl=lead.querySelector('input[type=range]');" +
  "var row=document.querySelector('.pmrow');" +
  "var r=function(e){return e?e.getBoundingClientRect():null;};" +
  "var lb=r(lead),rb=r(row),bb=r(btn),sb=r(sl),qb=r(q);" +
  "var body=document.querySelector('.sheetbody');" +
  "return JSON.stringify({" +
  "hasLead:!!lead,hasBtn:!!btn,rows:document.querySelectorAll('.pmrow').length," +
  "qText:(q?q.textContent:'')," +
  "leadBottom:(lb?Math.round(lb.bottom):-1),rowTop:(rb?Math.round(rb.top):-1)," +
  "btnW:(bb?Math.round(bb.width):0),btnH:(bb?Math.round(bb.height):0)," +
  "sliderW:(sb?Math.round(sb.width):0)," +
  "qClipped:(q?(q.scrollHeight>q.clientHeight+1||q.scrollWidth>q.clientWidth+1):true)," +
  "leadOverflow:(lb&&lb.width>0?(lead.scrollWidth>lead.clientWidth+1):true)," +
  "bodyOverflow:(body?(body.scrollWidth>body.clientWidth+1):true)," +
  "pageOverflow:(document.documentElement.scrollWidth>window.innerWidth+1)});})()"

function Measure-Lead([int]$w, [int]$h, [bool]$mobile, [bool]$touch) {
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

  $A = Measure-Lead 360 780 $true  $true    # small phone -- the hard case
  $B = Measure-Lead 390 800 $true  $true    # common phone
  $C = Measure-Lead 900 900 $false $false   # desktop

  function Test-One($m) {
    return ($m.hasLead) -and ($m.hasBtn) -and ($m.rows -eq 1) -and
           ($m.qText -like '*confirm or correct*') -and ($m.qText -like '*oz*') -and
           ($m.leadBottom -gt 0) -and ($m.rowTop -gt 0) -and ($m.leadBottom -le $m.rowTop) -and
           ($m.btnH -ge $MIN_BTN_H) -and ($m.btnW -ge $MIN_BTN_W) -and ($m.sliderW -ge $MIN_SLIDER) -and
           (-not $m.qClipped) -and (-not $m.leadOverflow) -and (-not $m.bodyOverflow) -and (-not $m.pageOverflow)
  }
  $A_ok = Test-One $A
  $B_ok = Test-One $B
  $C_ok = Test-One $C

  Write-Host "R6.1 confirm-first layout (real index.html, CDP device emulation):"
  foreach ($p in @(@('A phone 360px', $A, $A_ok), @('B phone 390px', $B, $B_ok), @('C desktop 900px', $C, $C_ok))) {
    $n = $p[0]; $m = $p[1]; $ok = $p[2]
    Write-Host ("  {0,-16}: lead={1} rows={2} leadBottom={3} rowTop={4} btn={5}x{6} slider={7} clipped={8} overflow={9} -> {10}" -f `
      $n, $m.hasLead, $m.rows, $m.leadBottom, $m.rowTop, $m.btnW, $m.btnH, $m.sliderW, $m.qClipped,
      ([bool]$m.leadOverflow -or [bool]$m.bodyOverflow -or [bool]$m.pageOverflow), $ok)
  }
  Write-Host ("  question (360px) : {0}" -f $A.qText)
  Write-Host ("  thresholds       : question ABOVE the list, button >={0}x{1}px, slider >={2}px, no clipping, no overflow" -f $MIN_BTN_W, $MIN_BTN_H, $MIN_SLIDER)
  Write-Host "-----------------------------------------"

  if ($A_ok -and $B_ok -and $C_ok) {
    Write-Host "PHOTO LEAD GATE: PASS (the question renders ABOVE the list at every width, with a real thumb target)"
    Cleanup; exit 0
  }
  Write-Host "PHOTO LEAD GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
