# Phase-4 Slice G update-lifecycle gate (DECISIONS.md D6 force-and-notify amendment).
# Machine-checks the FORCE-ON-LOAD mechanism via CDP:
#   1. SW v1 registers + activates.
#   2. The shell changes (a bump marker: the server appends a byte to sw.js to
#      trigger an update, and injects a token into index.html). Re-navigating the
#      page -- with NO gesture, NO SKIP_WAITING message -- must AUTOMATICALLY
#      activate the new SW (skipWaiting + clients.claim) and serve the new shell
#      (the token appears), while the client stayed open (not waiting for a close).
# The real "reopen -> Updated to vX notice, no force-quit" is signed on-device; it
# is reliable because it applies on LOAD (a plain reopen), not on app-switcher resume.
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8124
$origin = "http://127.0.0.1:$port"
$dbg = 9334
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-upd-" + [System.Guid]::NewGuid().ToString('N'))
$marker = Join-Path $repo 'tests\.swbump'
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
function Eval([string]$expr, [bool]$awaitP = $false) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; awaitPromise = $awaitP; returnByValue = $true }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (Test-Path $marker) { Remove-Item $marker -Force }

# static server; when the bump marker exists it makes the shell "change": append a
# byte to sw.js (trigger an update) and inject a token into index.html (a
# detectable new shell). No gesture is ever involved.
$server = Start-Job -ArgumentList $repo, $port, $marker -ScriptBlock {
  param($repo, $port, $marker)
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
        $bumped = Test-Path $marker
        if ($rel -eq 'sw.js' -and $bumped) {
          $bytes = [System.IO.File]::ReadAllBytes($full)
          $bytes += [System.Text.Encoding]::UTF8.GetBytes("`n// update-gate bump v2`n")
        } elseif ($rel -eq 'index.html' -and $bumped) {
          $txt = [System.IO.File]::ReadAllText($full)
          $txt = $txt.Replace('</body>', '<!--UPDGATE-TOKEN--></body>')
          $bytes = [System.Text.Encoding]::UTF8.GetBytes($txt)
        } else {
          $bytes = [System.IO.File]::ReadAllBytes($full)
        }
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
  try { if (Test-Path $marker) { Remove-Item $marker -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  Start-Sleep -Milliseconds 800
  try { Invoke-WebRequest "$origin/index.html" -UseBasicParsing -TimeoutSec 5 | Out-Null }
  catch { Write-Host "ERROR: test server did not start"; Cleanup; exit 2 }

  $chromeArgs = @('--headless=new', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd",
                  "--remote-debugging-port=$dbg", '--remote-allow-origins=*', 'about:blank')
  $chrome = Start-Process $browser -PassThru -ArgumentList $chromeArgs

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

  # 1. v1 registers + activates (prod path forced so it isn't the localhost dev branch)
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1" } | Out-Null
  Start-Sleep -Seconds 2
  $v1state = Eval "navigator.serviceWorker.ready.then(function(){return navigator.serviceWorker.getRegistration()}).then(function(r){return JSON.stringify({active:!!r.active,waiting:!!r.waiting})}).catch(function(e){return '{}'})" $true
  $d1 = $v1state | ConvertFrom-Json
  $v1active = [bool]$d1.active

  # 2. shell changes; re-navigate (a LOAD) with NO gesture -> new SW must AUTO-activate
  #    (skipWaiting+claim) and the new shell (token) must go live, client still open.
  Set-Content -Path $marker -Value 'bump' -Encoding utf8
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1" } | Out-Null
  $autoUpdated = $false; $lingerWait = $true
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 600
    $tok = Eval "(document.documentElement.outerHTML.indexOf('UPDGATE-TOKEN')>=0)"
    if ([bool]$tok) { $autoUpdated = $true }
    $wt = Eval "navigator.serviceWorker.getRegistration().then(function(r){return r?!!r.waiting:false}).catch(function(){return false})" $true
    if (-not [bool]$wt) { $lingerWait = $false }
    if ($autoUpdated -and -not $lingerWait) { break }
  }

  Write-Host "SW update lifecycle (CDP, prod path forced, NO gesture):"
  Write-Host ("  1. v1 registers + activates:                              {0}" -f $v1active)
  Write-Host ("  2. shell change -> new SW auto-activates on load (token):  {0}  [force-and-notify]" -f $autoUpdated)
  Write-Host ("     no waiting worker lingered (didn't wait for a close):   {0}" -f (-not $lingerWait))
  Write-Host "-----------------------------------------"
  if ($v1active -and $autoUpdated -and (-not $lingerWait)) {
    Write-Host "UPDATE GATE: PASS (shell change auto-activated on load, no gesture, client stayed open)"
    Cleanup; exit 0
  }
  Write-Host "UPDATE GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
