# R21.5 capture-outcome gate.
#
# "Exactly one outcome, in view without scrolling" is a LAYOUT claim, so it is
# measured as one. A string gate can prove the modal rendered; only a viewport
# can prove it was READABLE without the user hunting for it -- which is the whole
# defect this slice removes (the draft used to render inline, below two
# textareas, off the bottom of a phone).
#
# Measured against the real index.html, driven through the shipped capture path
# with fetch stubbed, at two phone sizes and one desktop:
#
#   * exactly ONE outcome state exists at a time, and the capture surface carries
#     none of it;
#   * SUCCESS -- the lead question, its slider, and BOTH footer actions are fully
#     inside the viewport with the page unscrolled, and stay there when the item
#     list is long enough to scroll the body;
#   * FAILURE -- the stated message and both ways out are in view;
#   * PENDING -- the counted spinner and the cancel are in view.
#
# NOTE: unlike the data-layer suite this runs in REAL time, not under
# --virtual-time-budget, so it exercises the createImageBitmap decoder that D47
# recorded as unexercisable in the harness.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8137
$origin = "http://127.0.0.1:$port"
$dbg = 9347
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-outcome-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

$MIN_ACTION_H = 44   # a primary action is a thumb target, not a link

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
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return $r.result.result.value
}

# ---- the page-side helpers, installed once per navigation -------------------
$install = @'
(function(){
  window.__g = {};
  __g.rect = function(sel, root){
    var e = (root||document).querySelector(sel);
    if (!e) return { found:false, inView:false };
    var r = e.getBoundingClientRect();
    return { found:true,
             top:Math.round(r.top), bottom:Math.round(r.bottom),
             w:Math.round(r.width), h:Math.round(r.height),
             inView: (r.top >= -1 && r.bottom <= window.innerHeight + 1 &&
                      r.left >= -1 && r.right <= window.innerWidth + 1 &&
                      r.width > 0 && r.height > 0) };
  };
  __g.snap = function(){
    var w = document.getElementById('captureOutcome');
    var foot = document.getElementById('outcomeFoot');
    var body = document.getElementById('outcomeBody');
    var cap = document.getElementById('captureBox');
    var shown = !!w && w.style.display !== 'none' && w.style.display !== '';
    return {
      state: HT.captureOutcomeState(),
      shown: shown,
      title: document.getElementById('outcomeTitle').textContent || '',
      msgText: (document.getElementById('outcomeMsg').textContent || ''),
      lead:   __g.rect('.pmq'),
      slider: __g.rect('.pmlead input[type=range]'),
      primary:__g.rect('#outcomeFoot .btn:nth-of-type(1)'),
      second: __g.rect('#outcomeFoot .btn:nth-of-type(2)'),
      third:  __g.rect('#outcomeFoot .btn:nth-of-type(3)'),
      nActions: document.querySelectorAll('#outcomeFoot .btn').length,
      spin:   __g.rect('#outcomeMsg .byokspin'),
      footInView: (function(){ var r = __g.rect('#outcomeFoot'); return r.inView; })(),
      bodyScrolls: !!body && body.scrollHeight > body.clientHeight + 1,
      pageScrollY: Math.round(window.scrollY || 0),
      pageScrollable: document.documentElement.scrollHeight > window.innerHeight + 1,
      pageOverflowX: document.documentElement.scrollWidth > window.innerWidth + 1,
      captureSurfaceClean: !cap || (cap.innerHTML.indexOf('pmbusy') < 0 &&
                                    cap.innerHTML.indexOf('byokCancel') < 0),
      footHTML: foot ? foot.innerHTML : ''
    };
  };
  __g.key = function(){ HT.byokClear(); HT.byokSave('grok','xai-GATEKEY-0123456789012345',20); };
  __g.file = function(){
    var c=document.createElement('canvas'); c.width=1400; c.height=1050;
    var x=c.getContext('2d'); var g=x.createLinearGradient(0,0,1400,1050);
    g.addColorStop(0,'#873'); g.addColorStop(1,'#39a'); x.fillStyle=g; x.fillRect(0,0,1400,1050);
    return new Promise(function(r){ c.toBlob(function(b){ r(new File([b],'meal.jpg',{type:'image/jpeg'})); },'image/jpeg',0.9); });
  };
  __g.reply = function(n){
    var items = [];
    for (var i=0;i<n;i++) items.push({name:'item '+(i+1),grams:120+i*7,
      per100:{kcal:180,protein_g:9,fat_g:6,carb_g:20,fiber_g:3,soluble_fiber_g:1},
      notes:'assumed a standard portion',scale_linked:true,dominance:i+1});
    return JSON.stringify({choices:[{message:{content:JSON.stringify({meal:'dinner',items:items})}}]});
  };
  __g.ok = function(n){ window.fetch=function(){ return Promise.resolve({ok:true,status:200,
    text:function(){ return Promise.resolve(__g.reply(n)); }}); }; };
  __g.hang = function(){ window.fetch=function(u,i){ return new Promise(function(_,rej){
    var s=i&&i.signal; if(s) s.addEventListener('abort',function(){ var e=new Error('a'); e.name='AbortError'; rej(e); }); }); }; };
  return 'installed';
})()
'@

$capture = @'
(function(){
  HT.photoDiscard(); HT.byokBusyClear(); __g.key();
  return __g.file().then(function(f){ return HT.byokCapture(f); }).then(function(){ return JSON.stringify(__g.snap()); });
})()
'@

function Go([int]$w, [int]$h, [bool]$mobile) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $mobile; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  Eval $install | Out-Null
}
function Measure-Success([int]$items) {
  Eval ("__g.ok($items)") | Out-Null
  return (Eval $capture | ConvertFrom-Json)
}
function Measure-Fail {
  Eval '__g.hang()' | Out-Null
  Eval 'HT.setByokCallTimeout(2000)' | Out-Null
  $r = Eval $capture | ConvertFrom-Json
  Eval 'HT.setByokCallTimeout(120000)' | Out-Null
  return $r
}
function Measure-Pending {
  Eval '__g.hang()' | Out-Null
  Eval 'HT.setByokCallTimeout(120000)' | Out-Null
  Eval '(function(){ HT.photoDiscard(); HT.byokBusyClear(); __g.key();
        __g.file().then(function(f){ window.__p = HT.byokCapture(f); }); return 1; })()' | Out-Null
  Start-Sleep -Milliseconds 1600
  $r = Eval '(function(){ return JSON.stringify(__g.snap()); })()' | ConvertFrom-Json
  Eval '(function(){ HT.byokCancel(); return 1; })()' | Out-Null
  return $r
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

  $results = @()
  $viewports = @(@('phone 360x690', 360, 690, $true), @('phone 390x745', 390, 745, $true), @('desktop 1200x900', 1200, 900, $false))

  Write-Host "R21.5 capture outcome (real index.html, shipped capture path, CDP):"
  $allOk = $true
  foreach ($v in $viewports) {
    $name = $v[0]; $w = $v[1]; $h = $v[2]; $mob = $v[3]
    Go $w $h $mob

    # SUCCESS, short list -- the common case.
    # R33: THREE outcome actions now, not two. D51 made this footer the outcome
    # COMMITMENT surface, and "Ate all of it" / "Ate some of it" are both outcome
    # commitments -- the second is not a draft edit that wandered in. The claim is
    # unchanged and is asserted over all three: in view, at or above the touch
    # floor, with the footer fixed while the body scrolls.
    # Slot order: 1 = ate all (primary), 2 = ate some, 3 = discard.
    $S = Measure-Success 2
    $sOk = $S.state -eq 'success' -and $S.shown -and
           $S.lead.inView -and $S.slider.inView -and
           $S.primary.inView -and $S.second.inView -and
           $S.primary.h -ge $MIN_ACTION_H -and $S.second.h -ge $MIN_ACTION_H -and
           $S.footHTML -like '*photoSave()*' -and $S.footHTML -like '*photoDiscard()*' -and
           $S.footHTML -like '*photoAskConsumption(true)*' -and
           $S.nActions -eq 3 -and
           $S.third.inView -and $S.third.h -ge $MIN_ACTION_H -and
           $S.captureSurfaceClean -and (-not $S.pageOverflowX) -and $S.pageScrollY -eq 0
    Write-Host ("  {0,-17} success : lead={1} slider={2} ateAll={3}({4}px) ateSome={5}({6}px) discard={7} bodyScrolls={8} oneState={9} -> {10}" -f `
      $name, $S.lead.inView, $S.slider.inView, $S.primary.inView, $S.primary.h, $S.second.inView, $S.second.h, $S.third.inView, $S.bodyScrolls, $S.captureSurfaceClean, $sOk)

    # SUCCESS, LONG list -- the footer must not travel with the content.
    $L = Measure-Success 9
    $lOk = $L.state -eq 'success' -and $L.shown -and $L.bodyScrolls -and
           $L.primary.inView -and $L.second.inView -and $L.slider.inView -and
           (-not $L.pageOverflowX) -and $L.pageScrollY -eq 0
    Write-Host ("  {0,-17} long    : bodyScrolls={1} save={2} discard={3} slider={4} -> {5}" -f `
      $name, $L.bodyScrolls, $L.primary.inView, $L.second.inView, $L.slider.inView, $lOk)

    # FAILURE -- stated, with both ways out in view.
    $F = Measure-Fail
    $fOk = $F.state -eq 'error' -and $F.shown -and
           $F.primary.inView -and $F.second.inView -and
           $F.footHTML -like '*captureRetry()*' -and $F.footHTML -like '*capturePasteInstead()*' -and
           $F.msgText -like '*did not answer*' -and $F.msgText -like '*still counted*' -and
           $F.nActions -eq 2 -and $F.captureSurfaceClean
    Write-Host ("  {0,-17} failure : msg='{1}' retry={2} paste={3} -> {4}" -f `
      $name, ($F.msgText -replace '\s+', ' ').Substring(0, [Math]::Min(52, $F.msgText.Length)), $F.primary.inView, $F.second.inView, $fOk)

    # PENDING -- counted and cancellable, in view.
    $P = Measure-Pending
    $pOk = $P.state -eq 'pending' -and $P.shown -and $P.spin.inView -and
           $P.primary.inView -and $P.footHTML -like '*byokCancel*' -and
           $P.msgText -match '\d+s' -and $P.nActions -eq 1 -and $P.captureSurfaceClean
    Write-Host ("  {0,-17} pending : spinner={1} counted='{2}' cancel={3} -> {4}" -f `
      $name, $P.spin.inView, ($P.msgText -replace '[^0-9]*(\d+s).*', '$1'), $P.primary.inView, $pOk)

    $results += @($sOk, $lOk, $fOk, $pOk)
    if (-not ($sOk -and $lOk -and $fOk -and $pOk)) { $allOk = $false }
  }

  Write-Host ("  thresholds        : exactly one outcome state; lead, slider and ALL THREE actions fully inside the viewport with the page unscrolled; actions >={0}px tall; footer fixed while the body scrolls; capture surface carries no outcome" -f $MIN_ACTION_H)
  Write-Host "-----------------------------------------"
  if ($allOk) {
    Write-Host "CAPTURE OUTCOME GATE: PASS (one explicit state per capture, in view without scrolling, at every width)"
    Cleanup; exit 0
  }
  Write-Host "CAPTURE OUTCOME GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
