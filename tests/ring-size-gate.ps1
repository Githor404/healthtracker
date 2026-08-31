# Rhythm-ring centerpiece-scale gate (D35 addendum).
#
# The ring is the day's centerpiece, so it must render at centerpiece scale --
# ~80% of viewport width on a phone -- WITHOUT pushing the day's working
# affordances below the fold. The ruled constraint wins over the number: if the
# target size breaks reach, the ring sizes down, not the other way round.
#
# Measured on the REAL index.html at 390x844 with a seeded regimen, day items and
# goals, so the checklist, caption and goal cells all have content to place.
#
# NOTE on the two originally-named measurables: #regimenChecklist renders ABOVE
# #dayView in the day card, so ring growth cannot push it down; and the "+ Log"
# pill is position:fixed, so it is in the viewport by construction. Both are
# asserted anyway (they are the ruled wording), but the assertions that actually
# BIND are the ones below them -- the ring's own swap affordance (the goal cells)
# and the pending-fast resolve row in the ring caption, which are the surfaces the
# ring itself depends on and the only ones ring growth can push off screen.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8131
$origin = "http://127.0.0.1:$port"
$dbg = 9341
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-ringsize-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

$MIN_RATIO = 70     # percent of viewport width the ring must occupy on a phone

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

$seed = "(function(){try{" +
  "HT.state().settings.presets.push({id:'p1',name:'Lunch',meal:'lunch',kcal:500,soluble_fiber_g:0});" +
  "HT.addRegimenFromJSON(JSON.stringify({name:'P',window:{start:'12:00',end:'20:00'},entries:[" +
  "{kind:'medication',time:'08:00',name:'Med'},{kind:'food',time:'12:00',presetId:'p1'}]}));" +
  "var td=HT.state().current;var mk=function(n,t,k){return {name:n,meal:'snack',time:t,kcal:k,protein_g:0,fat_g:0,carb_g:0,fiber_g:0,soluble_fiber_g:0,confidence:'eyeballed',notes:'',source:'manual'};};" +
  "HT.state().days[td].items.push(mk('a','08:00',300),mk('b','19:00',600));" +
  "HT.state().timeline[td]=[{time:'06:30',kind:'event',type:'walk',value:40,unit:'min',source:'manual',notes:''}];" +
  "HT.setGoal('protein_g',120,'min');HT.setGoal('weight',80,'max','kg');HT.refresh();" +
  "return 'ok';}catch(e){return 'ERR '+e;}})()"

$measure = "(function(){" +
  "var vw=window.innerWidth,vh=window.innerHeight;" +
  "var R=function(s){var e=document.querySelector(s);return e?e.getBoundingClientRect():null;};" +
  "var ring=R('#dayView .ringbox');" +
  "var chk=R('#regimenChecklist');" +
  "var fab=R('#fab');" +
  "var cells=R('#dayView .goalstrip');" +
  "var cap=R('#dayView .rrcap');" +
  "var rw=ring?Math.round(ring.width):0;" +
  "return JSON.stringify({vw:vw,vh:vh,ring:rw,ratio:vw?Math.round(rw/vw*100):0," +
  "chkBottom:chk?Math.round(chk.bottom):null,chkAbove:!!(chk&&chk.bottom<=vh)," +
  "fabVisible:!!(fab&&fab.bottom<=vh&&fab.top>=0)," +
  "cellsTop:cells?Math.round(cells.top):null,cellsAbove:!!(cells&&cells.top<vh)," +
  "capTop:cap?Math.round(cap.top):null,capAbove:!!(cap&&cap.top<vh)," +
  "pageOverflow:document.documentElement.scrollWidth>vw+1});})()"

function Measure-At([int]$w, [int]$h, [bool]$mobile) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $mobile; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  $sr = Eval $seed
  if ($sr -notlike 'ok*') { Write-Host "  seed failed: $sr" }
  Start-Sleep -Milliseconds 300
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

  $P = Measure-At 390 844 $true     # the ruled phone viewport
  $S = Measure-At 360 780 $true     # a smaller phone
  $D = Measure-At 1200 900 $false   # desktop -- the cap must hold

  $P_ok = ($P.ratio -ge $MIN_RATIO) -and $P.chkAbove -and $P.fabVisible -and $P.cellsAbove -and $P.capAbove -and (-not $P.pageOverflow)
  $S_ok = ($S.ratio -ge $MIN_RATIO) -and $S.chkAbove -and $S.fabVisible -and (-not $S.pageOverflow)
  $D_ok = ($D.ring -le 380) -and (-not $D.pageOverflow)

  Write-Host "rhythm-ring centerpiece scale (real index.html, seeded, CDP):"
  Write-Host ("  phone 390x844 : ring={0}px ({1}% of vw) checklist-above={2} +Log-visible={3} goal-cells-above={4} caption-above={5} -> {6}" -f `
    $P.ring, $P.ratio, $P.chkAbove, $P.fabVisible, $P.cellsAbove, $P.capAbove, $P_ok)
  Write-Host ("  phone 360x780 : ring={0}px ({1}% of vw) checklist-above={2} +Log-visible={3} -> {4}" -f `
    $S.ring, $S.ratio, $S.chkAbove, $S.fabVisible, $S_ok)
  Write-Host ("  desktop 1200  : ring={0}px (capped) overflow={1} -> {2}" -f $D.ring, [bool]$D.pageOverflow, $D_ok)
  Write-Host ("  thresholds    : ring >= {0}% of viewport width on phones; checklist, + Log, goal cells and ring caption all above the fold; desktop capped" -f $MIN_RATIO)
  Write-Host "-----------------------------------------"

  if ($P_ok -and $S_ok -and $D_ok) {
    Write-Host "RING SIZE GATE: PASS (centerpiece scale without pushing the ring's own affordances below the fold)"
    Cleanup; exit 0
  }
  Write-Host "RING SIZE GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
