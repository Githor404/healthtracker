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
# ---- R283: every wait is a wait ON A CONDITION (tests/lib/quiet.js) -------------------
# No fixed sleep stands for "long enough". The page counts its own async work in flight;
# WaitQuiet returns when none is and the DOM has been still for two frames, WaitBoot when
# the NEW page's app is up (the old page is marked first), WaitServer when the test
# server answers. Each fails the gate, by name, if its condition never holds.
$HT_QUIET_JS = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'lib\quiet.js'))
function WaitFail([string]$why) { Write-Host ("  FAIL  " + $why); Write-Host "GATE: FAIL"; try { Cleanup } catch { }; exit 1 }
function WaitQuiet([string]$why) {
  $qr = Invoke-CDP 'Runtime.evaluate' @{ expression = "(window.__htQuiet ? window.__htQuiet(10000).then(function () { return 'quiet'; }, function (e) { return String(e && e.message || e); }) : Promise.resolve('no quiet marker on this page'))"; awaitPromise = $true; returnByValue = $true }
  $v = $qr.result.result.value
  if ($v -ne 'quiet') { WaitFail ("the page did not settle (" + $why + "): " + $v) }
  $ms = (Invoke-CDP 'Runtime.evaluate' @{ expression = 'window.__htQuietLastMs + " ms, waiting on: " + window.__htQuietWaitedOn'; returnByValue = $true }).result.result.value
  if ([double]($ms -replace ' ms.*', '') -gt 3000) { Write-Host ("  NOTE  settling took " + $ms + " (" + $why + ")") } }
function WaitServer([string]$url) {
  for ($sw = 0; $sw -lt 300; $sw++) { try { $null = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2; return } catch { Start-Sleep -Milliseconds 100 } }
  Write-Host "ERROR: test server did not start within 30 s"; try { Cleanup } catch { }; exit 2 }
function MarkOld { try { [void](Invoke-CDP 'Runtime.evaluate' @{ expression = 'window.__htOld = 1'; returnByValue = $true }) } catch { } }
function WaitLoaded {
  for ($bw = 0; $bw -lt 300; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "!window.__htOld && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { return }; Start-Sleep -Milliseconds 100 }
  WaitFail "the page did not load within 30 s" }
function WaitBoot {
  for ($bw = 0; $bw -lt 300; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "!window.__htOld && typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { WaitQuiet 'boot'; return }; Start-Sleep -Milliseconds 100 }
  WaitFail "the app did not boot within 30 s" }
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
        # Two bump levels via marker CONTENT: 'bump' (v2, one token) and 'bump2'
        # (v3, distinct bytes + a second token) so the gate can apply on LOAD then
        # apply a FURTHER change on RESUME without any navigation.
        $level = if (Test-Path $marker) { ([string](Get-Content $marker -Raw)).Trim() } else { '' }
        if ($rel -eq 'sw.js' -and $level) {
          $bytes = [System.IO.File]::ReadAllBytes($full)
          $bytes += [System.Text.Encoding]::UTF8.GetBytes("`n// update-gate bump $level`n")
        } elseif ($rel -eq 'index.html' -and $level) {
          $txt = [System.IO.File]::ReadAllText($full)
          $inject = if ($level -eq 'bump2') { '<!--UPDGATE-TOKEN--><!--UPDGATE-TOKEN2--></body>' } else { '<!--UPDGATE-TOKEN--></body>' }
          $txt = $txt.Replace('</body>', $inject)
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
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
  try { if (Test-Path $marker) { Remove-Item $marker -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  WaitServer "$origin/index.html"

  $chromeArgs = @('--headless=new', '--disable-extensions', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-default-apps', '--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion', '--mute-audio', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd",
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
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null

  # 1. v1 registers + activates (prod path forced so it isn't the localhost dev branch;
  #    swnow=1 zeroes the resume-check throttle -- a test seam like prod=1).
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1&swnow=1" } | Out-Null
  WaitBoot
  $v1state = Eval "navigator.serviceWorker.ready.then(function(){return navigator.serviceWorker.getRegistration()}).then(function(r){return JSON.stringify({active:!!r.active,waiting:!!r.waiting})}).catch(function(e){return '{}'})" $true
  $d1 = $v1state | ConvertFrom-Json
  $v1active = [bool]$d1.active

  # 2. LOAD-applies: shell -> v2; re-navigate (a LOAD) with NO gesture -> new SW must
  #    AUTO-activate (skipWaiting+claim) and the new shell (token) go live.
  Set-Content -Path $marker -Value 'bump' -Encoding ascii
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/?prod=1&swnow=1" } | Out-Null
  $loadApplied = $false
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 600
    if ([bool](Eval "(document.documentElement.outerHTML.indexOf('UPDGATE-TOKEN')>=0)")) { $loadApplied = $true; break }
  }

  # 3. RESUME-applies (v0.5.1 refinement): the page is now controlled + on v2. Bump the
  #    shell AGAIN (v3, a distinct token) and fire a visibilitychange with NO navigation.
  #    The throttled resume-check calls reg.update(), which force-applies + reloads
  #    through the SAME controllerchange path a load uses. This is the iOS switcher case.
  $controlled = [bool](Eval "!!navigator.serviceWorker.controller")
  Set-Content -Path $marker -Value 'bump2' -Encoding ascii
  Eval "document.dispatchEvent(new Event('visibilitychange'))" | Out-Null
  $resumeApplied = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 600
    if ([bool](Eval "(document.documentElement.outerHTML.indexOf('UPDGATE-TOKEN2')>=0)")) { $resumeApplied = $true; break }
  }

  # 5. THE VERSION LINE IS WHERE IT IS CLAIMED TO BE (v0.22.1).
  #    v0.22.0 shipped a changelog line saying Settings shows the version, and it
  #    did not: the element sat on the page's OTHER .about line, a SIBLING of
  #    #settingsPanel, so it rendered at the foot of the MAIN screen. Every gate
  #    was green -- the harness created its own detached element and asserted the
  #    text went into it, which is true wherever that element lives. Presence of a
  #    correct string is not presence on the right surface. So this asserts
  #    CONTAINMENT (panel.contains(el)) and real visibility with Settings open,
  #    against the shipped index.html.
  #    NOTE: the separator is written as the regex escape \u00b7, never as a literal
  #    UTF-8 middot. This file has no BOM, so Windows PowerShell 5.1 reads it in the
  #    system codepage and a literal arrives as mojibake that never matches. This
  #    note used to carry two literal middots itself, which is advice failing to
  #    take its own advice.
  Eval "if (typeof openSettings === 'function') openSettings()" | Out-Null
  WaitQuiet 'after a step'
  $vlJson = Eval "(function(){var p=document.getElementById('settingsPanel'),e=document.getElementById('settingsVersion');if(!p||!e)return JSON.stringify({found:false});var r=e.getBoundingClientRect();return JSON.stringify({found:true,inPanel:p.contains(e),text:e.textContent,w:Math.round(r.width),h:Math.round(r.height)});})()"
  $vl = $null; try { $vl = $vlJson | ConvertFrom-Json } catch {}
  $vlFound   = [bool]($vl -and $vl.found)
  $vlInPanel = [bool]($vlFound -and $vl.inPanel)
  $vlText    = if ($vlFound) { [string]$vl.text } else { '' }
  $vlShaped  = [bool]($vlText -match '^HealthTracker v[0-9]+\.[0-9]+\.[0-9]+( \u00b7 released [0-9]{4}-[0-9]{2}-[0-9]{2})?$')
  $vlHonest  = [bool]($vlText -notmatch 'undefined' -and $vlText -notmatch 'released\s*$')
  $vlVisible = [bool]($vlFound -and $vl.w -gt 0 -and $vl.h -gt 0)
  $vlOk = $vlFound -and $vlInPanel -and $vlShaped -and $vlHonest -and $vlVisible

  Write-Host "SW update lifecycle (CDP, prod path forced, NO gesture):"
  Write-Host ("  1. v1 registers + activates:                          {0}" -f $v1active)
  Write-Host ("  2. shell change -> auto-applies on LOAD (token):      {0}  [force-and-notify]" -f $loadApplied)
  Write-Host ("  3. page controlled before resume:                     {0}" -f $controlled)
  Write-Host ("  4. shell change -> auto-applies on RESUME (token2):   {0}  [v0.5.1 visibilitychange, no navigation]" -f $resumeApplied)
  Write-Host ("  5. version line INSIDE #settingsPanel, visible:       {0}  [text: '{1}']" -f $vlOk, $vlText)
  Write-Host ("     found={0} inPanel={1} shaped={2} honest={3} visible={4}" -f $vlFound, $vlInPanel, $vlShaped, $vlHonest, $vlVisible)
  Write-Host "-----------------------------------------"
  if ($v1active -and $loadApplied -and $controlled -and $resumeApplied -and $vlOk) {
    Write-Host "UPDATE GATE: PASS (auto-applies on both load and app-switcher resume; no gesture; version line is in Settings)"
    Cleanup; exit 0
  }
  Write-Host "UPDATE GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
