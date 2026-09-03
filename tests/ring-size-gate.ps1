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
# R17 thresholds. Arcs are graphical objects, so WCAG non-text guidance (3:1) is
# the reference; the arc-vs-track pair is asserted a little lower because the two
# are adjacent bands of the same family, not figure-and-ground.
$MIN_MINI_PER_ROW = 7
$MAX_MINI_PX      = 56
$MIN_ARC_TRACK    = 1.6
$MIN_ARC_BG       = 2.2
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
  # The ring is a TRAILING-24H instrument, so a wall-clock gate is not a
  # re-runnable one: seeded 06:30 and 23:00 entries fall outside the window
  # when the suite runs after midnight, no practice lane draws, and the band
  # assertion fails on byte-identical code. Pin the clock through the shipped
  # seam so the seeded scene is the same scene at every hour. (Found 2026-09-03
  # at 00:28 local, when R6.1 ran the gate and this failed on unchanged code.)
  "HT.setClock(function(){return new Date(2026,0,15,15,0,0).getTime();});HT.boot();" +
  "HT.state().settings.presets.push({id:'p1',name:'Lunch',meal:'lunch',kcal:500,soluble_fiber_g:0});" +
  "HT.addRegimenFromJSON(JSON.stringify({name:'P',window:{start:'12:00',end:'20:00'},entries:[" +
  "{kind:'medication',time:'08:00',name:'Med'},{kind:'food',time:'12:00',presetId:'p1'}]}));" +
  "var td=HT.state().current;var mk=function(n,t,k){return {name:n,meal:'snack',time:t,kcal:k,protein_g:0,fat_g:0,carb_g:0,fiber_g:0,soluble_fiber_g:0,confidence:'eyeballed',notes:'',source:'manual'};};" +
  "HT.state().days[td].items.push(mk('a','08:00',300),mk('b','19:00',600));" +
  "HT.state().timeline[td]=[{time:'06:30',kind:'event',type:'walk',value:40,unit:'min',source:'manual',notes:''}];" +
  "HT.setGoal('protein_g',120,'min');HT.setGoal('weight',80,'max','kg');" +
  "for(var i=1;i<7;i++){var d=HT.shiftDate(td,-i);HT.state().days[d]={status:'complete',items:[mk('m','08:00',300),mk('n','19:00',500)],water_l:0};" +
  "HT.state().timeline[d]=[{time:'23:00',kind:'biometric',type:'sleep',value:7,unit:'h',source:'manual',notes:''}];}" +
  "HT.refresh();" +
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

# R17: the long-flagged MINI-GRID DENSITY gate. This surface has been unattested
# since 0.11.0, and the 0.14.0 report is what it would have caught: minis
# inheriting main-ring geometry, drawing outside their boxes and overlapping.
$grid = "(function(){" +
  "var minis=[].slice.call(document.querySelectorAll('#rhythmGrid .rmini'));" +
  "if(!minis.length)return JSON.stringify({n:0});" +
  "var R=minis.map(function(e){return e.getBoundingClientRect();});" +
  "var overlaps=0;for(var i=0;i<R.length;i++)for(var j=i+1;j<R.length;j++){" +
  "if(!(R[i].right<=R[j].left+0.5||R[j].right<=R[i].left+0.5||R[i].bottom<=R[j].top+0.5||R[j].bottom<=R[i].top+0.5))overlaps++;}" +
  "var spill=0,detached=0,svgW=0;" +
  "minis.forEach(function(e){var s=e.querySelector('svg'),l=e.querySelector('small');var br=e.getBoundingClientRect();" +
  "if(!s||!l){detached++;return;}var sr=s.getBoundingClientRect(),lr=l.getBoundingClientRect();svgW=Math.round(sr.width);" +
  "if(sr.left<br.left-0.5||sr.right>br.right+0.5||sr.top<br.top-0.5||sr.bottom>br.bottom+0.5)spill++;" +
  "if(!(lr.top>=sr.bottom-1&&lr.bottom<=br.bottom+1&&lr.left>=br.left-1&&lr.right<=br.right+1))detached++;});" +
  "var top0=Math.min.apply(null,R.map(function(r){return Math.round(r.top);}));" +
  "var perRow=R.filter(function(r){return Math.round(r.top)===top0;}).length;" +
  "return JSON.stringify({n:R.length,overlaps:overlaps,spill:spill,detached:detached,svgW:svgW,perRow:perRow});})()"

# R17: arc-vs-track contrast, in BOTH themes. The R13 palette was designed against
# dark only, so light mode was never specced -- this is what closes that.
$contrast = "(function(){" +
  "var toRGB=function(c){var p=String(c).replace(/[^0-9.,]/g,'').split(',').map(parseFloat);" +
  "return (p.length>=3&&!isNaN(p[0]))?[p[0],p[1],p[2]]:null;};" +
  "var lum=function(rgb){var a=rgb.map(function(v){v/=255;return v<=0.03928?v/12.92:Math.pow((v+0.055)/1.055,2.4);});" +
  "return 0.2126*a[0]+0.7152*a[1]+0.0722*a[2];};" +
  "var ratio=function(x,y){var l1=lum(x),l2=lum(y);var hi=Math.max(l1,l2),lo=Math.min(l1,l2);return Math.round(((hi+0.05)/(lo+0.05))*100)/100;};" +
  "var paths=[].slice.call(document.querySelectorAll('#dayView .rring path'));" +
  "var track=document.querySelector('#dayView .rtrack');" +
  "if(!paths.length||!track)return JSON.stringify({err:'no marks'});" +
  "var tc=toRGB(getComputedStyle(track).stroke);" +
  "var bg=toRGB(getComputedStyle(document.querySelector('.card')).backgroundColor);" +
  "var worstTrack=99,worstBg=99;" +
  "paths.forEach(function(pth){var ac=toRGB(getComputedStyle(pth).stroke);if(!ac)return;" +
  "worstTrack=Math.min(worstTrack,ratio(ac,tc));if(bg)worstBg=Math.min(worstBg,ratio(ac,bg));});" +
  "return JSON.stringify({arcVsTrack:worstTrack===99?0:worstTrack,arcVsBg:worstBg===99?0:worstBg,n:paths.length});})()"

function Measure-At([int]$w, [int]$h, [bool]$mobile) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $mobile; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  $sr = Eval $seed
  if ($sr -notlike 'ok*') { Write-Host "  seed failed: $sr" }
  Start-Sleep -Milliseconds 300
  $m = Eval $measure | ConvertFrom-Json
  $gr = Eval $grid | ConvertFrom-Json
  Add-Member -InputObject $m -NotePropertyName grid -NotePropertyValue $gr -Force
  # both themes, on the same seeded page
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'light' }) } | Out-Null
  Start-Sleep -Milliseconds 200
  $cl = Eval $contrast | ConvertFrom-Json
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-color-scheme'; value = 'dark' }) } | Out-Null
  Start-Sleep -Milliseconds 200
  $cd = Eval $contrast | ConvertFrom-Json
  Invoke-CDP 'Emulation.setEmulatedMedia' @{ features = @() } | Out-Null
  Add-Member -InputObject $m -NotePropertyName cLight -NotePropertyValue $cl -Force
  Add-Member -InputObject $m -NotePropertyName cDark  -NotePropertyValue $cd -Force
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

  $G_ok = ($P.grid.n -ge 7) -and ($P.grid.overlaps -eq 0) -and ($P.grid.spill -eq 0) -and
          ($P.grid.detached -eq 0) -and ($P.grid.svgW -le $MAX_MINI_PX) -and ($P.grid.perRow -ge $MIN_MINI_PER_ROW)
  $C_ok = ($P.cLight.arcVsTrack -ge $MIN_ARC_TRACK) -and ($P.cLight.arcVsBg -ge $MIN_ARC_BG) -and
          ($P.cDark.arcVsTrack  -ge $MIN_ARC_TRACK) -and ($P.cDark.arcVsBg  -ge $MIN_ARC_BG)
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

  Write-Host ("  mini grid     : {0} rings at {1}px, {2}/row, overlaps={3} spill={4} detached-labels={5} -> {6}" -f `
    $P.grid.n, $P.grid.svgW, $P.grid.perRow, $P.grid.overlaps, $P.grid.spill, $P.grid.detached, $G_ok)
  Write-Host ("  contrast      : light arc/track={0} arc/bg={1} | dark arc/track={2} arc/bg={3} -> {4}" -f `
    $P.cLight.arcVsTrack, $P.cLight.arcVsBg, $P.cDark.arcVsTrack, $P.cDark.arcVsBg, $C_ok)
  Write-Host ("                  thresholds: >=7 rings/row at <={0}px, zero overlap/spill/detachment; arc-vs-track >={1}, arc-vs-background >={2}, BOTH themes" -f `
    $MAX_MINI_PX, $MIN_ARC_TRACK, $MIN_ARC_BG)

  if ($P_ok -and $S_ok -and $D_ok -and $G_ok -and $C_ok) {
    Write-Host "RING GATE: PASS (centerpiece scale + mini-grid density + arc contrast in both themes)"
    Cleanup; exit 0
  }
  Write-Host "RING GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
