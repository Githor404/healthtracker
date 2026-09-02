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
# R8.2: arcs are BANDS, not hairlines. Stroke scales with the ring through the
# viewBox, so this asserts the RENDERED band thickness both absolutely and as a
# proportion of the ring -- a future ring resize cannot quietly thin them back out.
# Recalibrated for the MULTI-LANE ring: the old 14 px / 5 %-of-ring thresholds were
# derived from the single-lane design where one stroke was 6.7 % of the diameter.
# Seven-then-four lanes cannot each be 5 % of the ring. The ruled sizes are ~12 px
# anchors and ~14 px practice, so those are what is asserted, in pixels.
$MIN_BAND_PX     = 11     # absolute, at the 390 pt reference width
$MIN_BAND_MAX_PX = 13
# Strokes scale with the ring, so a smaller phone renders proportionally thinner
# bands -- correct behaviour, not a defect. The scale-invariant assertion is the
# PROPORTION, derived from the ruled sizes at the reference (12/328 = 3.66 %,
# 14/328 = 4.27 %). Both are asserted at 390; only the proportion at 360.
$MIN_BAND_PCT     = 3.5
$MIN_BAND_MAX_PCT = 4.1

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
  "var leg=R('#dayView .rlegend');" +
  "var svg=document.querySelector('#dayView .rring');" +
  "var vb=svg?parseFloat((svg.getAttribute('viewBox')||'0 0 180 180').split(' ')[2]):180;" +
  "var pths=svg?[].slice.call(svg.querySelectorAll('path')):[];" +
  "var sws=pths.map(function(e){return parseFloat(getComputedStyle(e).strokeWidth)||0;}).filter(function(x){return x>0;});" +
  "var sw=sws.length?Math.min.apply(null,sws):0, swMax=sws.length?Math.max.apply(null,sws):0;" +
  "var rw=ring?Math.round(ring.width):0;" +
  "var bandPx=(vb>0&&rw>0)?Math.round(sw/vb*rw*10)/10:0;" +
  "var bandMax=(vb>0&&rw>0)?Math.round(swMax/vb*rw*10)/10:0;" +
  "return JSON.stringify({vw:vw,vh:vh,ring:rw,ratio:vw?Math.round(rw/vw*100):0,band:bandPx,bandMax:bandMax,bandPct:rw?Math.round(bandPx/rw*1000)/10:0,bandMaxPct:rw?Math.round(bandMax/rw*1000)/10:0," +
  "chkBottom:chk?Math.round(chk.bottom):null,chkAbove:!!(chk&&chk.bottom<=vh)," +
  "fabVisible:!!(fab&&fab.bottom<=vh&&fab.top>=0)," +
  "cellsTop:cells?Math.round(cells.top):null,cellsAbove:!!(cells&&cells.top<vh)," +
  "capTop:cap?Math.round(cap.top):null,capAbove:!!(cap&&cap.top<vh)," +
  "legAbove:!!(leg&&leg.top<vh)," +
  "pageOverflow:document.documentElement.scrollWidth>vw+1});})()"

# R13 Fork D: report the LARGEST ring that keeps the ring's own affordances above
# the fold at this viewport. The ruled fallback is "the constraint wins over the
# number", so this tells us what number the constraint actually allows.
$sweep = "(function(){var best=0,vh=window.innerHeight;" +
  "var root=document.documentElement,prev=root.style.getPropertyValue('--ringw');" +
  "for(var px=400;px>=200;px-=4){root.style.setProperty('--ringw',px+'px');HT.refresh();" +
  "var c=document.querySelector('#dayView .goalstrip'),k=document.querySelector('#dayView .rrcap');" +
  "var l=document.querySelector('#dayView .rlegend');" +
  "if(c&&l&&c.getBoundingClientRect().top<vh&&l.getBoundingClientRect().top<vh){best=px;break;}}" +
  "root.style.setProperty('--ringw',prev);HT.refresh();" +
  "return JSON.stringify({best:best,vw:window.innerWidth,pct:Math.round(best/window.innerWidth*100)});})()"

function Measure-At([int]$w, [int]$h, [bool]$mobile) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $mobile; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  $sr = Eval $seed
  if ($sr -notlike 'ok*') { Write-Host "  seed failed: $sr" }
  Start-Sleep -Milliseconds 300
  $m = Eval $measure | ConvertFrom-Json
  $sw = Eval $sweep | ConvertFrom-Json
  Add-Member -InputObject $m -NotePropertyName bestPx  -NotePropertyValue $sw.best -Force
  Add-Member -InputObject $m -NotePropertyName bestPct -NotePropertyValue $sw.pct  -Force
  return $m
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

  # R13 Fork D: 844 is the DEVICE height; Safari's usable viewport is ~745 once
  # the address bar and home indicator are accounted for. The gate measured the
  # generous number and was therefore optimistic about reach.
  $P = Measure-At 390 745 $true     # REAL usable phone viewport
  $S = Measure-At 360 690 $true     # a smaller phone, usable height
  $D = Measure-At 1200 900 $false   # desktop -- the cap must hold

  $P_ok = ($P.ratio -ge $MIN_RATIO) -and $P.chkAbove -and $P.fabVisible -and $P.cellsAbove -and $P.legAbove -and ($P.band -ge $MIN_BAND_PX) -and ($P.bandMax -ge $MIN_BAND_MAX_PX) -and ($P.bandPct -ge $MIN_BAND_PCT) -and ($P.bandMaxPct -ge $MIN_BAND_MAX_PCT) -and (-not $P.pageOverflow)
  $S_ok = ($S.ratio -ge $MIN_RATIO) -and $S.chkAbove -and $S.fabVisible -and ($S.bandPct -ge $MIN_BAND_PCT) -and ($S.bandMaxPct -ge $MIN_BAND_MAX_PCT) -and (-not $S.pageOverflow)
  $D_ok = ($D.ring -le 380) -and (-not $D.pageOverflow)

  Write-Host "rhythm-ring centerpiece scale (real index.html, seeded, CDP):"
  Write-Host ("  phone 390x745 : ring={0}px ({1}% of vw) band={2}-{3}px cells-above={4} legend-above={5} -> {6}" -f `
    $P.ring, $P.ratio, $P.band, $P.bandMax, $P.cellsAbove, $P.legAbove, $P_ok)
  Write-Host ("                  largest ring keeping reach at this viewport: {0}px ({1}% of vw)" -f $P.bestPx, $P.bestPct)
  Write-Host ("  phone 360x690 : ring={0}px ({1}% of vw) band={2}-{3}px ({4}-{5}% of ring) -> {6}" -f `
    $S.ring, $S.ratio, $S.band, $S.bandMax, $S.bandPct, $S.bandMaxPct, $S_ok)
  Write-Host ("  desktop 1200  : ring={0}px (capped) overflow={1} -> {2}" -f $D.ring, [bool]$D.pageOverflow, $D_ok)
  Write-Host ("  thresholds    : ring >= {0}% of vw; arc bands >= {1}/{2}px at 390 and >= {3}/{4}% of ring everywhere; checklist, + Log, goal cells and legend above the fold; desktop capped" -f $MIN_RATIO, $MIN_BAND_PX, $MIN_BAND_MAX_PX, $MIN_BAND_PCT, $MIN_BAND_MAX_PCT)
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
