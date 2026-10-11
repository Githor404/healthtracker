# ONE DOOR, question 2: does removing the page's "Quick add" button keep the fold?
#
# Pre-registration asked which of two options keeps the day's ruled affordances
# above the fold -- the page button opening the same sheet, or the button removed
# entirely. This measures BOTH on the shipped page, in one run, without editing the
# tree: it measures as shipped, then removes the element from the DOM and measures
# again. The same trick ring-size-gate's ink plant uses, for the same reason -- a
# configuration you have to edit the source to see is a configuration you will
# measure once and never again.
#
# It is a MEASUREMENT, not a gate. It prints numbers and exits 0 either way; the
# gate-script census pins *-gate.ps1 only, deliberately, so this joins nothing.
#
# WHAT THIS SCRIPT IS AND IS NOT AN AUTHORITY ON.
#
#   TRUST: the DELTA between the two configurations. That is what it was written to
#   measure, it is measured twice at two widths, and it has a mechanical
#   explanation.
#
#   DO NOT TRUST: the absolute above/below-fold readings. This seed clears
#   localStorage and boots FIRST-RUN, and on that page #dayView's own top sits at
#   101px at 360x690 and at 635px at 390x745 -- a 534px difference in where the day
#   begins, from something preceding it that this probe does not isolate. The
#   readings are therefore seed-dependent and were not chased further, because they
#   do not bear on the comparison.
#
#   THE AUTHORITY ON THE FOLD IS ring-size-gate, which seeds a realistic page
#   (regimen, goals, seven prior days) and asserts cells-above and chkAbove at both
#   widths. It passes. If the fold is ever the question, that is the instrument.
#
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File tests/measure-fold.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8177
$origin = "http://127.0.0.1:$port"
$dbg = 9387
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-fold-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

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

# The clock is PINNED, for the reason ring-size-gate states: the day is a
# trailing-window instrument and a wall-clock run is not a re-runnable one.
$seed = "(function(){try{localStorage.clear();" +
  "HT.setClock(function(){return new Date(2026,0,15,15,0,0).getTime();});HT.boot();" +
  "var td=HT.state().current;" +
  "var mk=function(n,t,k){return {name:n,meal:'snack',time:t,kcal:k,protein_g:1,fat_g:1,carb_g:1,fiber_g:1,soluble_fiber_g:0,confidence:'eyeballed',notes:'',source:'manual'};};" +
  "HT.state().days[td].items.push(mk('a','08:00',300),mk('b','12:30',450),mk('c','19:00',600));" +
  "HT.setGoal('protein_g',120,'min');" +
  "HT.refresh();return 'ok';}catch(e){return 'ERR '+e;}})()"

# Every number the fold question turns on, in one read. `bottom` is what matters:
# an element whose bottom is below the viewport is an element the user must scroll
# to reach, which is the thing the ruled affordances may not become.
# SCROLL IS RESET FIRST. getBoundingClientRect is viewport-relative, so a page
# left scrolled makes every `bottom` read lower than it is -- and the first draft
# of this script reported the 390 viewport 550px below the 360 one, which is
# backwards and was the tell. An unexplained number is not a measurement.
$measure = "(function(){window.scrollTo(0,0);var vh=window.innerHeight,vw=window.innerWidth;" +
  "var b=function(sel){var e=document.querySelector(sel);if(!e)return null;" +
  "var r=e.getBoundingClientRect();return {top:Math.round(r.top),bottom:Math.round(r.bottom),h:Math.round(r.height)};};" +
  "var card=b('#dayView .dcard'), cells=b('#dayView .goalstrip'), cap=b('#dayView .rrcap');" +
  "var act=b('#dayView .dact'), qa=b('#dayView .qa10'), grp=b('#dayView .mghead');" +
  "var fab=b('.fab')||b('#logFab');" +
  "var doc=Math.round(document.documentElement.scrollHeight);" +
  "return JSON.stringify({vw:vw,vh:vh,doc:doc,card:card,cells:cells,cap:cap,act:act,qa:qa,grp:grp,fab:fab," +
  "cellsAbove:!!(cells&&cells.bottom<=vh),capAbove:!!(cap&&cap.bottom<=vh)," +
  "grpAbove:!!(grp&&grp.bottom<=vh),actAbove:!!(act&&act.bottom<=vh)});})()"

# Remove the page button and re-render through the app's own path, so the layout
# that follows is the layout the app would produce -- not a hole where an element
# used to be.
# WHAT SITS ABOVE THE DAY, and how tall each block is. Added because the first
# run put every element inside #dayView exactly 550px lower at 390 than at 360 --
# a CONSTANT offset, which means one block above it, not a layout that reflowed.
# Reporting the above/below-fold readings without explaining that would have been
# publishing a number I could not account for.
$above = "(function(){window.scrollTo(0,0);var out=[];" +
  "var dv=document.getElementById('dayView');if(!dv)return '[]';" +
  "var sibs=[].slice.call((dv.parentNode||document.body).children);" +
  "for(var i=0;i<sibs.length;i++){var e=sibs[i];var r=e.getBoundingClientRect();" +
  "if(r.height<1)continue;" +
  "out.push({tag:e.tagName.toLowerCase(),id:e.id||'',cls:String(e.className||'').slice(0,28)," +
  "h:Math.round(r.height),top:Math.round(r.top)});" +
  "if(e===dv)break;}" +
  "return JSON.stringify(out);})()"

$strip = "(function(){var e=document.querySelector('#dayView .qa10');" +
  "if(!e)return 'no-qa10';e.parentNode.removeChild(e);return 'stripped';})()"

function Measure-At([int]$w, [int]$h) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  $sr = Eval $seed
  if ($sr -notlike 'ok*') { Write-Host "  seed failed: $sr" }
  Start-Sleep -Milliseconds 300
  $withBtn = Eval $measure | ConvertFrom-Json
  $st = Eval $strip
  Start-Sleep -Milliseconds 200
  $without = Eval $measure | ConvertFrom-Json
  return @{ with = $withBtn; without = $without; stripped = $st }
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

  $cargs = @('--headless=new', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd",
             "--remote-debugging-port=$dbg", '--remote-allow-origins=*', 'about:blank')
  $chrome = Start-Process $browser -PassThru -ArgumentList $cargs

  $wsUrl = $null
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 300
    try {
      $j = Invoke-RestMethod "http://127.0.0.1:$dbg/json/list" -TimeoutSec 2
      $pg = $j | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $wsUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $wsUrl) { Write-Host "ERROR: no CDP target"; Cleanup; exit 2 }

  $ws = New-Object Net.WebSockets.ClientWebSocket
  $ws.Options.SetRequestHeader('Origin', "http://127.0.0.1:$dbg")
  $ws.ConnectAsync([Uri]$wsUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null

  Write-Host "ONE DOOR / fold: does removing the page's Quick add button keep the fold?"
  Write-Host "(measured on the shipped page, clock pinned; `with` is as shipped, `without` strips .qa10)"
  foreach ($vp in @(@(360, 690), @(390, 745))) {
    $m = Measure-At $vp[0] $vp[1]
    $w = $m.with; $o = $m.without
    Write-Host ""
    Write-Host ("  viewport {0}x{1}   (strip: {2})" -f $vp[0], $vp[1], $m.stripped)
    Write-Host ("    day card height    : {0}px with  ->  {1}px without   (delta {2}px)" -f `
      $w.card.h, $o.card.h, ($w.card.h - $o.card.h))
    Write-Host ("    document height    : {0}px with  ->  {1}px without   (delta {2}px)" -f `
      $w.doc, $o.doc, ($w.doc - $o.doc))
    if ($w.qa) { Write-Host ("    the button itself  : {0}px tall, bottom at {1}px" -f $w.qa.h, $w.qa.bottom) }
    else { Write-Host "    the button itself  : NOT FOUND -- nothing was measured about its cost" }
    foreach ($row in @(@('goal cells', 'cells'), @('ring caption', 'cap'), @('action row', 'act'), @('first meal header', 'grp'))) {
      $k = $row[1]
      $wv = $w.$k; $ov = $o.$k
      $wb = if ($wv) { "$($wv.bottom)px" } else { 'absent' }
      $ob = if ($ov) { "$($ov.bottom)px" } else { 'absent' }
      $wa = if ($wv) { if ($wv.bottom -le $w.vh) { 'above' } else { 'BELOW' } } else { '-' }
      $oa = if ($ov) { if ($ov.bottom -le $o.vh) { 'above' } else { 'BELOW' } } else { '-' }
      Write-Host ("    {0,-18}: bottom {1,-8} {2,-5}  ->  {3,-8} {4,-5}" -f $row[0], $wb, $wa, $ob, $oa)
    }
    Write-Host ("    fold at {0}px" -f $w.vh)
    Write-Host "    blocks above the day, tallest first:"
    $ab = Eval $above | ConvertFrom-Json
    $ab | Sort-Object -Property h -Descending | Select-Object -First 5 | ForEach-Object {
      Write-Host ("      {0,5}px  top {1,5}px  {2} {3} {4}" -f $_.h, $_.top, $_.tag, $_.id, $_.cls)
    }
  }
  Write-Host ""
  Write-Host "MEASUREMENT ONLY -- no verdict, no exit code to read."
  Write-Host "TRUST THE DELTA. The absolute above/below readings are seed-dependent"
  Write-Host "on this first-run seed (see the header); ring-size-gate is the fold authority."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
