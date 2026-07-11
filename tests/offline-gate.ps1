# Phase 0 offline gate (DECISIONS.md D6, Amendment B).
# Proves the PRODUCTION cache-first path serves the shell + history offline.
#
# One persistent headless Chrome session driven over the DevTools Protocol:
# a PowerShell HttpListener serves the repo on 127.0.0.1; the SW is forced onto
# the prod path via ?prod=1 (not the localhost network-first dev branch). We
# register + precache, verify the shell is cached, then use CDP's real offline
# emulation (Network.emulateNetworkConditions) and reload — asserting the shell +
# seeded history still render with the network cut.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8123
$origin = "http://127.0.0.1:$port"
$dbg = 9333
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-swtest-" + [System.Guid]::NewGuid().ToString('N'))
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
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }   # skip events
  }
}
function Eval([string]$expr, [bool]$awaitP = $false) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; awaitPromise = $awaitP; returnByValue = $true }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

# --- static server ---
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

  # launch Chrome with remote debugging (remote-allow-origins required on modern Chrome)
  $args = @('--headless=new', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd",
            "--remote-debugging-port=$dbg", '--remote-allow-origins=*', 'about:blank')
  $chrome = Start-Process $browser -PassThru -ArgumentList $args

  # find the page target's websocket URL
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
  Invoke-CDP 'Network.enable' $null | Out-Null

  # 1. seed legacy data (seed page runs no app.js, so it can't create the new key
  #    first — D2 precedence would otherwise ignore the seed).
  Invoke-CDP 'Page.navigate' @{ url = "$origin/tests/seed-offline.html" } | Out-Null
  Start-Sleep -Milliseconds 1500

  # 2. load the app under forced prod: boot migrates the seed and registers the SW
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1" } | Out-Null
  Start-Sleep -Seconds 2

  # 3. verify the SW is ready and the shell is actually precached
  $precached = Eval "navigator.serviceWorker.ready.then(function(){return caches.open('healthtracker-shell-v1')}).then(function(c){return c.match('./index.html')}).then(function(m){return !!m}).catch(function(){return false})" $true

  # 4. reload online so the SW takes control and history renders
  Invoke-CDP 'Page.reload' $null | Out-Null
  Start-Sleep -Milliseconds 1500

  # 5. cut the network for real (CDP), then reload — the SW must serve from cache
  Invoke-CDP 'Network.emulateNetworkConditions' @{ offline = $true; latency = 0; downloadThroughput = -1; uploadThroughput = -1 } | Out-Null
  Invoke-CDP 'Page.reload' $null | Out-Null
  Start-Sleep -Seconds 2

  $raw = Eval "JSON.stringify({hrows: document.querySelectorAll('.hrow').length, seeded: document.body.innerHTML.indexOf('2026-07-08')>=0, badge: ((document.getElementById('storeBadge')||{}).textContent||'')})"
  $d = $raw | ConvertFrom-Json

  $hasHistory = $d.hrows -gt 0
  $hasSeeded = [bool]$d.seeded
  $appRan = $d.badge -match 'saved in this browser'

  Write-Host "offline reload (network cut via CDP, prod path forced):"
  Write-Host ("  shell precached (cache has index.html): {0}" -f [bool]$precached)
  Write-Host ("  history rendered offline (.hrow rows):  {0} ({1})" -f $hasHistory, $d.hrows)
  Write-Host ("  seeded day present (2026-07-08):        {0}" -f $hasSeeded)
  Write-Host ("  app.js ran (badge):                     {0} ('{1}')" -f $appRan, $d.badge)
  Write-Host "-----------------------------------------"

  if ($precached -and $hasHistory -and $hasSeeded -and $appRan) {
    Write-Host "OFFLINE GATE: PASS (prod cache-first path served the shell with the network cut)"
    Cleanup; exit 0
  }
  Write-Host "OFFLINE GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
