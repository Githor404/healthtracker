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

# RETIRED 2026-10-09, superseded by the user's ruling. The rings now SHARE the
# card with the figures, so a share-of-viewport floor measures the wrong thing:
# at 70% there is no room beside them, which is what forced text INTO the disc,
# and text inside a disc is what collided with the ink on the device.
#
# What the floor was protecting -- a ring big enough to read -- is now a PIXEL
# minimum, and what it never protected is now tested directly:
#
#   rings >= 130px
#   ZERO ink collisions at 360 AND 390
#   all text >= 16px (D100, which font-floor-gate also holds)
#
# $MIN_RATIO = 70   <- retired; kept here as a comment so the next reader finds
#                      the number and its reason rather than its absence.
$MIN_RING_PX = 130  # the ruled minimum, in pixels, because the ring no longer
                    # owns the width it used to
# R8.2: arcs are BANDS, not hairlines. Stroke scales with the ring through the
# viewBox, so this asserts the RENDERED band thickness both absolutely and as a
# proportion of the ring -- a future ring resize cannot quietly thin them back out.
# Recalibrated for the MULTI-LANE ring: the old 14 px / 5 %-of-ring thresholds were
# derived from the single-lane design where one stroke was 6.7 % of the diameter.
# Seven-then-four lanes cannot each be 5 % of the ring. The ruled sizes are ~12 px
# anchors and ~14 px practice, so those are what is asserted, in pixels.
# R18.2: 97% was the wrong bar and this gate passed the reported defect at 91.7%.
# The rule the fix implements is figure-and-ground, so the gate asserts THAT: no
# single arc past HALF the lane (past half, the eye reads the remainder as the
# mark), and the lane's total draw under 60% so the dots stay the loudest thing
# on it. Measured on the reported shape: one meal cluster, ~21 h ago, nothing since.
$EAT_MAX_PCT     = 60
$EAT_MAX_ONE_PCT = 50
# RETIRED 2026-10-09 with the 70% floor, and for the reason this file already
# gives three lines below: "strokes scale with the ring, so a smaller phone
# renders proportionally thinner bands -- correct behaviour, not a defect. The
# scale-invariant assertion is the PROPORTION." These two numbers were derived
# from a 328px ring at the 390 reference; the ruled ring is 150px, where 11px of
# stroke is not thin, it is impossible. Measured: 5.5-6.4px, which is the SAME
# 3.7-4.3% of the ring that passed before. The proportion carries the whole
# requirement and still holds at both widths.
#
# $MIN_BAND_PX     = 11   <- retired
# $MIN_BAND_MAX_PX = 13   <- retired
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

$seed = "(function(){try{localStorage.clear();" +
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
  # MEASURED FROM A DEFINED SCROLL POSITION. Without this the fold tests read
# whatever scroll offset the PREVIOUS Measure-At left: resizing 390 -> 360
# clamps scrollTop to the new maximum, so a shorter document lands at a
# different offset and "is X above the fold" silently answers a different
# question. R159.1/A2 shrank the card and chkAbove flipped at 360 with no
# change to anything above the checklist, which is how this surfaced.
  # AND THE CHANGELOG NOTICE IS DISMISSED FIRST. It is a TRANSIENT overlay that
  # goes on the first tap, and it is as tall as its text: the 0.73.0 note made it
  # 520px and pushed the regimen checklist 88px below the fold at 360, failing a
  # leg that has nothing to do with the ring. Every fold assertion here was being
  # measured against a page carrying half a screen of text that disappears -- so
  # ANY release with a long note would have failed this gate, and the budget it
  # asserted was never the steady-state one.
  "try{ if(window.HT&&HT.dismissVersionNotice) HT.dismissVersionNotice(); }catch(e){}" +
  "var vn=document.getElementById('versionNotice'); if(vn) vn.style.display='none';" +
  "window.scrollTo(0,0);" +
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
  "cardH:(function(){var c=document.querySelector('#dayView .dcard');return c?Math.round(c.getBoundingClientRect().height):0;})()," +

  "fabVisible:!!(fab&&fab.bottom<=vh&&fab.top>=0)," +
  "cellsTop:cells?Math.round(cells.top):null,cellsAbove:!!(cells&&cells.top<vh)," +
  "capTop:cap?Math.round(cap.top):null,capAbove:!!(cap&&cap.top<vh)," +
  "legAbove:!!(leg&&leg.top<vh)," +
  # ---- INK INSIDE THE DISC, AGAINST THE CIRCLE (not against a box) -------
  # The constraint is sqrt(r^2 - y^2), so the test is each text rect's
  # FURTHEST CORNER versus the arc's inner radius. A planted element proves
  # the detector fires before a clean result from it is trusted.
  "collide:(function(){" +
  "  var bx=document.querySelector('#dayView .ringbox');" +
  "  if(!bx) return {n:0,worst:0,who:'no ringbox',planted:false};" +
  "  var br=bx.getBoundingClientRect();" +
  "  var cx=br.left+br.width/2, cy=br.top+br.height/2;" +
  "  var arc=bx.querySelector('.calrarc')||bx.querySelector('.calrtrack');" +
  "  var sw=arc?parseFloat(getComputedStyle(arc).strokeWidth)||0:0;" +
  "  var vb=58, box=br.width, scale=box/180;" +
  "  var r=(vb*scale)-(sw/2);" +
  "  function worstCorner(el){" +
  "    var q=el.getBoundingClientRect();" +
  "    if(!q.width||!q.height) return -1;" +
  "    var xs=[q.left-cx,q.right-cx], ys=[q.top-cy,q.bottom-cy], m=0;" +
  "    for(var i=0;i<2;i++)for(var j=0;j<2;j++){" +
  "      var d=Math.sqrt(xs[i]*xs[i]+ys[j]*ys[j]); if(d>m)m=d; }" +
  "    return m; }" +
  "  var els=[].slice.call(bx.querySelectorAll('*')).filter(function(el){" +
  "    if(el.tagName==='svg'||el.closest('svg')) return false;" +
  "    return (el.textContent||'').trim().length>0 && el.children.length===0; });" +
  "  var worst=0, who='';" +
  "  els.forEach(function(el){ var d=worstCorner(el);" +
  "    if(d>r && d-r>worst){ worst=d-r; who=(el.className||el.tagName)+' '+(el.textContent||'').trim().slice(0,24); } });" +
  "  var n=els.filter(function(el){ return worstCorner(el)>r; }).length;" +
  "  var plant=document.createElement('span');" +
  "  plant.style.cssText='position:absolute;left:0;top:50%;width:100%;text-align:center;font-size:16px';" +
  "  plant.textContent='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';" +
  "  bx.appendChild(plant);" +
  "  var caught=worstCorner(plant)>r;" +
  "  plant.remove();" +
  "  return {n:n,worst:Math.round(worst*10)/10,who:who,r:Math.round(r*10)/10,planted:caught}; })()," +
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

# R18.1: THE SHAPE THE GATES KEPT MISSING. Every ring gate to date seeded records
# INSIDE the window, so a lane could never be measured while mostly EMPTY -- which
# is exactly when the meals lane drew a full dashed circle (0.13.0, and again in
# the seven-lane build). This seeds the device shape: two meals 0.8 h apart
# yesterday evening, NOTHING logged today, and an older meal leaving an unresolved
# gap behind them. Then it measures what is actually drawn.
$seedSparse = "(function(){try{localStorage.clear();" +
  "HT.setClock(function(){return new Date(2026,8,3,16,0,0).getTime();});HT.boot();" +
  # 16:00, so the last meal is ~21 h back: the shape that was STILL drawing a
  # ring with a notch after 0.16.2, and the reason this seed is not milder.
  "var mk=function(n,t,k){return {name:n,meal:'dinner',time:t,kcal:k,protein_g:0,fat_g:0,carb_g:0,fiber_g:0,soluble_fiber_g:0,confidence:'eyeballed',notes:'',source:'manual'};};" +
    "HT.state().days['2026-09-02']={status:'open',items:[mk('a','18:00',600),mk('b','18:48',300)],water_l:0};" +
  # DATE-PINNED, and it must not expire at midnight. This scene is only the
  # reported shape when the day on screen is the day the seeded clock stands on.
  # It drew an EMPTY meals lane from 2026-09-04 onward -- paths=0, dots=0 -- until
  # D50, because localDate() consulted the real wall clock and the booted `current`
  # was the real today whatever the seam said.
  #
  # Nothing pins `current` here on purpose: the clock is set ABOVE, before boot, and
  # the day on screen following it is D50 working. This gate is that fix's evidence
  # in a real browser against the shipped app -- revert D50 and the lane empties.
  "HT.refresh();return 'ok';}catch(e){return 'ERR '+e;}})()"

# Rendered coverage of the meals lane: summed arc length against the lane's own
# circumference. Measured from the DOM, not from the model, because the defect was
# a DRAWING that contradicted a correct-enough model.
$measureEat = "(function(){" +
  "var svg=document.querySelector('#dayView .rring');if(!svg)return JSON.stringify({err:'no-ring'});" +
  "var track=svg.querySelector('circle.rtrack[data-lane=eat]');if(!track)return JSON.stringify({err:'no-eat-track'});" +
  "var r=parseFloat(track.getAttribute('r'))||0;var circ=2*Math.PI*r;" +
  "var paths=[].slice.call(svg.querySelectorAll('path[data-lane=eat]'));" +
  "var lens=paths.map(function(e){try{return e.getTotalLength();}catch(err){return 0;}});" +
  "var sum=lens.reduce(function(a,b){return a+b;},0);" +
  "var dots=svg.querySelectorAll('circle.rdot[data-lane=eat]').length;" +
  "return JSON.stringify({paths:paths.length,dots:dots,circ:Math.round(circ*10)/10," +
  "sumPct:circ?Math.round(sum/circ*1000)/10:0,maxPct:circ?Math.round(Math.max.apply(null,lens.concat([0]))/circ*1000)/10:0});})()"

function Measure-Sparse([int]$w, [int]$h) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  $sr = Eval $seedSparse
  if ($sr -notlike 'ok*') { Write-Host "  sparse seed failed: $sr" }
  Start-Sleep -Milliseconds 300
  return (Eval $measureEat | ConvertFrom-Json)
}

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
  $P_ok = ($P.ring -ge $MIN_RING_PX) -and ($P.collide.n -eq 0) -and $P.collide.planted -and $P.chkAbove -and $P.fabVisible -and $P.cellsAbove -and ($P.bandPct -ge $MIN_BAND_PCT) -and ($P.bandMaxPct -ge $MIN_BAND_MAX_PCT) -and (-not $P.pageOverflow)
  $S_ok = ($S.ring -ge $MIN_RING_PX) -and ($S.collide.n -eq 0) -and $S.collide.planted -and $S.chkAbove -and $S.fabVisible -and ($S.bandPct -ge $MIN_BAND_PCT) -and ($S.bandMaxPct -ge $MIN_BAND_MAX_PCT) -and (-not $S.pageOverflow)
  $D_ok = ($D.ring -le 380) -and (-not $D.pageOverflow)

  $E = Measure-Sparse 390 745
  # A mostly-empty meals lane must not read as a ring: the dots carry the day.
  $E_ok = ($E.paths -ge 0) -and ($E.sumPct -lt $EAT_MAX_PCT) -and ($E.maxPct -lt $EAT_MAX_ONE_PCT) -and ($E.dots -ge 2)

  Write-Host "rhythm-ring centerpiece scale (real index.html, seeded, CDP):"
  Write-Host ("  phone 390x745 : ring={0}px band={1}-{2}px cells-above={3} ink-crossing-arc={4} (worst {5}px, r={6}) planted-caught={7} -> {8}" -f `
    $P.ring, $P.band, $P.bandMax, $P.cellsAbove, $P.collide.n, $P.collide.worst, $P.collide.r, $P.collide.planted, $P_ok)
  if ($P.collide.n -gt 0) { Write-Host ("                  worst offender: {0}" -f $P.collide.who) }
  Write-Host ("                  largest ring keeping reach at this viewport: {0}px ({1}% of vw)" -f $P.bestPx, $P.bestPct)
  Write-Host ("  phone 360x690 : ring={0}px band={1}-{2}px ({3}-{4}% of ring) ink-crossing-arc={5} (worst {6}px, r={7}) planted-caught={8} -> {9}" -f `
    $S.ring, $S.band, $S.bandMax, $S.bandPct, $S.bandMaxPct, $S.collide.n, $S.collide.worst, $S.collide.r, $S.collide.planted, $S_ok)
  if ($S.collide.n -gt 0) { Write-Host ("                  worst offender: {0}" -f $S.collide.who) }
  Write-Host ("  legs 390      : ring>=130={0} collide0={1} planted={2} chkAbove={3} fab={4} cells={5} bandPct={6} bandMaxPct={7} noOverflow={8}" -f `
    ($P.ring -ge $MIN_RING_PX), ($P.collide.n -eq 0), $P.collide.planted, $P.chkAbove, $P.fabVisible, $P.cellsAbove, ($P.bandPct -ge $MIN_BAND_PCT), ($P.bandMaxPct -ge $MIN_BAND_MAX_PCT), (-not $P.pageOverflow))
  Write-Host ("  heights 360   : chkBottom={0} vh=690 ringbox={1} card={2}" -f `
    $S.chkBottom, $S.ring, $S.cardH)
  Write-Host ("  legs 360      : ring>=130={0} collide0={1} planted={2} chkAbove={3} fab={4} bandPct={5} bandMaxPct={6} noOverflow={7}" -f `
    ($S.ring -ge $MIN_RING_PX), ($S.collide.n -eq 0), $S.collide.planted, $S.chkAbove, $S.fabVisible, ($S.bandPct -ge $MIN_BAND_PCT), ($S.bandMaxPct -ge $MIN_BAND_MAX_PCT), (-not $S.pageOverflow))
  Write-Host ("  desktop 1200  : ring={0}px (capped) overflow={1} -> {2}" -f $D.ring, [bool]$D.pageOverflow, $D_ok)
  Write-Host ("  thresholds    : ring >= {0}px (the 70%-of-viewport floor is RETIRED, superseded by ruling); arc bands >= {1}/{2}% of the ring at every width (the absolute 11/13px pair is RETIRED with the 70% floor); checklist, + Log and goal cells above the fold; desktop capped; ZERO ink inside the disc may cross the arc" -f $MIN_RING_PX, $MIN_BAND_PCT, $MIN_BAND_MAX_PCT)
  Write-Host ("  sparse meals  : eat-lane paths={0} dots={1} drawn={2}% of the lane (largest {3}%) -> {4}" -f `
    $E.paths, $E.dots, $E.sumPct, $E.maxPct, $E_ok)
  Write-Host ("  thresholds    : a mostly-empty meals lane draws < {0}% of its circumference, no single arc past {1}%, and keeps its meal dots" -f $EAT_MAX_PCT, $EAT_MAX_ONE_PCT)
  Write-Host "-----------------------------------------"

  Write-Host ("  mini grid     : {0} rings at {1}px, {2}/row, overlaps={3} spill={4} detached-labels={5} -> {6}" -f `
    $P.grid.n, $P.grid.svgW, $P.grid.perRow, $P.grid.overlaps, $P.grid.spill, $P.grid.detached, $G_ok)
  Write-Host ("  contrast      : light arc/track={0} arc/bg={1} | dark arc/track={2} arc/bg={3} -> {4}" -f `
    $P.cLight.arcVsTrack, $P.cLight.arcVsBg, $P.cDark.arcVsTrack, $P.cDark.arcVsBg, $C_ok)
  Write-Host ("                  thresholds: >=7 rings/row at <={0}px, zero overlap/spill/detachment; arc-vs-track >={1}, arc-vs-background >={2}, BOTH themes" -f `
    $MAX_MINI_PX, $MIN_ARC_TRACK, $MIN_ARC_BG)

  if ($P_ok -and $S_ok -and $D_ok -and $G_ok -and $C_ok -and $E_ok) {
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
