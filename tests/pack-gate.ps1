# R286/d3 + d4 -- THE PATHWAY PACK ON THE PHONE. In a real browser at 390 px, through the real
# file input, by real taps.
#
#   Pre-registered in DECISIONS (R286, steps d and e) before the build. A pack imports only when
#   its body matches its own fingerprint; it is kept out of the backup; the 14 groups draw and a
#   record's detail sits behind an i; an unreviewed sentence reads "not reviewed yet"; no pathway
#   is ever called active or measured; a reviewed lexicon rule answers "fermented". Placeholder
#   pack content only.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8406
$Dbg = 9606
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-pack-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

function Find-Browser {
  foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null }
function Receive-One {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count); if ($res.EndOfMessage) { break } }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json) }
function Invoke-CDP([string]$m, [hashtable]$p) {
  $script:cid++; $pl = @{ id = $script:cid; method = $m }; if ($p) { $pl.params = $p }
  $b = [Text.Encoding]::UTF8.GetBytes(($pl | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($b), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $g = 0
  while ($true) { if (++$g -gt 3000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg } } }
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
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
# Multi-line JS goes over base64 so no quoting survives to be mangled; the result
# is stringified INSIDE the page (CDP: await the promise -- a JSON.stringify of an
# async eval returns "{}").
function EvalJ([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "JSON.stringify((function(){ return eval(decodeURIComponent(escape(atob('" + $enc + "')))); })())"; returnByValue = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }
# The async form, for anything that touches the corpus: AWAIT the promise and
# stringify INSIDE the page.
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }
# REAL TYPING, one character at a time into whatever holds the focus. Setting
# .value and calling the handler would prove the handler; it would not prove the
# field survives being typed in, which is the whole of the caret rule.
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    Start-Sleep -Milliseconds 70 } }
function Settle { WaitQuiet 'after a step' }   # R283: was a fixed 400 ms

# Set PACK_SHOTS=1 to save 390px screenshots to %TEMP%\pack-shots.
$shots = $null
if ($env:PACK_SHOTS) { $shots = Join-Path $env:TEMP 'pack-shots'; New-Item -ItemType Directory -Force $shots | Out-Null }
function Shot([string]$name) {
  if (-not $shots) { return }
  $rv = Invoke-CDP 'Page.captureScreenshot' @{ format = 'png' }
  [IO.File]::WriteAllBytes((Join-Path $shots ($name + '.png')), [Convert]::FromBase64String($rv.result.data))
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $portv)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$portv/"); $l.Start()
  $mimes = @{ '.html'='text/html'; '.js'='application/javascript'; '.json'='application/json';
              '.png'='image/png'; '.svg'='image/svg+xml'; '.css'='text/css'; '.bin'='application/octet-stream' }
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
    try { $ctx.Response.Close() } catch { } } }
function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { } }

$fails = @()
function Check([bool]$ok, [string]$name) {
  if ($ok) { Write-Host ("  PASS  " + $name) } else { Write-Host ("  FAIL  " + $name); $script:fails += $name } }

try {
  WaitServer "$origin/index.html"
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 400
    try { $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break } } catch { } }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.packImportText === 'function' && typeof HT.linkPrepare === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R286 functions are not on HT"; Cleanup; exit 2 }

  # ---- the fixture: a placeholder pack in the builder's own wrapper format ---------------------------
  # HTPrivate's build_pack.py (tested there) writes {format, version, sha256, body}, `sha256` the
  # hash of `body`'s UTF-8 bytes. The pack here is built the same way, with placeholder content
  # only; the Reactome IDs are real (CC0).
  function TapSel([string]$sel) {
    $r9 = EvalJ ("(function(){ var b = document.querySelector(" + (ConvertTo-Json $sel) + "); if (!b) return { ok: false }; b.scrollIntoView({ block: 'center' }); var q = b.getBoundingClientRect(); return { ok: q.width > 0 && q.height > 0, x: q.left + q.width / 2, y: q.top + q.height / 2, h: Math.round(q.height), w: Math.round(q.width) }; })()") | ConvertFrom-Json
    if (-not $r9.ok) { return $r9 }
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $r9.x; y = $r9.y }) } | Out-Null
    Start-Sleep -Milliseconds 40
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    WaitQuiet 'after a tap'
    return $r9
  }
  $body = @'
{"format":"healthtracker-pack","schema":1,"built_at":"2026-10-29T12:00:00","private":true,"reactome_version":98,
 "groups":[{"id":"energy","name":"Group A"},{"id":"glucose","name":"Group B"}],
 "records":[
  {"id":"pw-001","plain_name":"Path A1","technical_name":"Citric acid cycle (TCA cycle)","group":"energy","backbone":[{"source":"Reactome","version":98,"id":"R-HSA-71403"}],"supply":[{"cofactor":"magnesium","dri":"magnesium","key":"magnesium_mg","slot":"304","tracked":true},{"cofactor":"B5","dri":"pantothenic","tracked":false}],"observable":"not observable","observable_how":"","reviewed_by_me":"2026-10-29","sentence":"A placeholder sentence the user reviewed.","claims":["claim-a"]},
  {"id":"pw-002","plain_name":"Path A2","technical_name":"Respiratory electron transport","group":"energy","backbone":[{"source":"Reactome","version":98,"id":"R-HSA-611105"}],"supply":[],"observable":"proxy","observable_how":"placeholder proxy","reviewed_by_me":null,"sentence":null,"claims":[]},
  {"id":"pw-003","plain_name":"Path B1","technical_name":null,"group":"glucose","backbone":[{"source":null,"note":"no reference pathway ID -- literature-sourced"}],"supply":[],"observable":"direct","observable_how":"placeholder reading","reviewed_by_me":null,"sentence":null,"claims":[]}],
 "claims":[{"id":"claim-a","claim":"Placeholder claim A.","reviewed_by_me":"2026-10-29","evidence":{"grade":"low"},"probability":{"current_version":1,"versions":[{"version":1,"p":0.6,"of":"that placeholder A holds","kind":"general"}]}}],
 "interactions":[],
 "reference_intakes":{"source":"Health Canada, Dietary Reference Intakes tables","group":"males 51-70","values":{"magnesium":{"label":"Magnesium","value":420,"unit":"mg","kind":"RDA"}}},
 "lexicon":{"rules":[{"id":"lx-001","pattern":"kimchi","fermented":"yes","fermented_why":"placeholder reason","marco":{"code":"75502520","desc":"Kimchi","tier":"Hi"},"reviewed_by_me":"2026-10-29"}]},
 "sources":[]}
'@
  $body = ($body -replace "`r`n", "`n")
  $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($body))).Replace('-', '').ToLower()
  $pdir = Join-Path $env:TEMP ("ht-pack-files-" + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $pdir | Out-Null
  $good = Join-Path $pdir 'pack-v001.json'; $bad = Join-Path $pdir 'pack-v002.json'
  [IO.File]::WriteAllText($good, (@{ format = 'healthtracker-pack'; version = 1; sha256 = $sha; body = $body } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($bad, (@{ format = 'healthtracker-pack'; version = 2; sha256 = $sha; body = $body.Replace('Group B', 'Group C') } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
  function PickFile([string]$path) {
    [void](Eval "(function(){ var m = document.getElementById('packMsg'); if (m) m.innerHTML = ''; return 1; })()")
    $doc = Invoke-CDP 'DOM.getDocument' @{ depth = 1 }
    $nid = (Invoke-CDP 'DOM.querySelector' @{ nodeId = $doc.result.root.nodeId; selector = '#packFile' }).result.nodeId
    Invoke-CDP 'DOM.setFileInputFiles' @{ files = @($path); nodeId = $nid } | Out-Null
    # the fingerprint is checked by the browser's own crypto, which the quiet marker does not
    # count -- so the wait is ON THE APP'S ANSWER: the message it writes, or 10 s and a failure
    for ($pw = 0; $pw -lt 200; $pw++) { if ((Eval "(document.getElementById('packMsg') || {}).textContent || ''") -ne '') { break }; Start-Sleep -Milliseconds 50 }
    WaitQuiet 'pack answered'
    return (Eval "(document.getElementById('packMsg') || {}).textContent || ''")
  }
  $exp0 = Eval "HT.exportJSON()"
  [void](Eval "HT.openSettings()"); WaitQuiet 'settings'
  # ---- GATE 1: a pack that does not match its fingerprint is refused ---------------------------------
  $m1 = PickFile $bad
  Write-Host ("  tampered: " + $m1)
  Check (($m1 -like '*does not match its own fingerprint*Nothing was imported*') -and ((Eval "!HT.packLoad()") -eq $true)) "R286 PACK GATE 1: A CHANGED PACK IS REFUSED IN WORDS -- its body does not match its fingerprint, and nothing is kept"
  # ---- GATE 2: the real one imports, and says where it lives ------------------------------------------
  $m2 = PickFile $good
  $now = Eval "(document.getElementById('packNow') || {}).textContent || ''"
  Write-Host ("  imported: " + $m2 + " | " + $now)
  Shot 'pack-settings'
  Check (($m2 -like '*Pathway pack v1 imported: 2 groups, 3 records*not in your backup*') -and ($now -like '*pathway pack v1*')) "R286 PACK GATE 2: A MATCHING PACK IMPORTS -- 2 groups, 3 records, 'kept on this phone only; it is not in your backup'"
  Check ((Eval "HT.exportJSON()") -eq $exp0) "R286 PACK GATE 2: THE BACKUP DOES NOT CARRY THE PACK -- the export is byte-identical with it imported"
  [void](Eval "HT.closeSettings()"); WaitQuiet 'settings closed'
  # ---- GATE 3: the groups on the phone, a record behind its i -------------------------------------------
  [void](Eval "(function(){ var c = document.querySelector('[data-card=pathways] details'); c.open = true; return 1; })()"); WaitQuiet 'pathways open'
  $g3 = EvalJ "(function(){ return { groups: Array.prototype.map.call(document.querySelectorAll('#pathways .pwgroup > summary'), function (s) { return s.textContent; }) }; })()"
  [void](Eval "(function(){ var g = document.querySelector('#pathways .pwgroup'); g.open = true; return 1; })()"); WaitQuiet 'group open'
  $i1 = TapSel '#pathways .pwgroup .pwrec .pwinfo > summary'
  $r1 = EvalJ "(function(){ var r = document.querySelectorAll('#pathways .pwgroup')[0].querySelectorAll('.pwrec'); var a = r[0].querySelector('.pwinfo'); return { open: a.open, text: a.innerText.replace(/\s+/g, ' ') }; })()"
  [void](Eval "(function(){ var r = document.querySelectorAll('#pathways .pwgroup')[0].querySelectorAll('.pwrec'); r[1].querySelector('.pwinfo').open = true; return 1; })()"); WaitQuiet 'second record'
  $r2 = Eval "(function(){ var r = document.querySelectorAll('#pathways .pwgroup')[0].querySelectorAll('.pwrec'); return r[1].querySelector('.pwinfo').innerText.replace(/\s+/g, ' '); })()"
  Shot 'pack-pathways'
  Write-Host ("  groups: " + $g3); Write-Host ("  record A1: " + $r1); Write-Host ("  record A2: " + $r2)
  $r1v = $r1 | ConvertFrom-Json
  Check (($g3 -like '*"Group A ? 2","Group B ? 1"*') -and $r1v.open -and ($i1.h -ge 44) -and ($i1.w -ge 44)) ("R286 PACK GATE 3: THE PHONE SHOWS THE GROUPS, each opening to its records; a record's detail sits behind a 44 px i (" + $i1.w + " x " + $i1.h + ")")
  Check (($r1v.text -like '*Citric acid cycle (TCA cycle)*Reactome R-HSA-71403 (release 98)*A placeholder sentence the user reviewed.*What this phone can see: not at all*Raw materials (necessary, not sufficient)*Magnesium*420 mg a day (RDA)*not counted by the log: B5*Placeholder claim A.*60 % that placeholder A holds*GRADE low*') -and ($r2 -like '*Plain description: not reviewed yet.*through a proxy*')) "R286 PACK GATE 3: A RECORD'S DETAIL -- technical name, Reactome ID and release, its sentence only once reviewed ('not reviewed yet' otherwise), what the phone can see, raw materials against the reference intake, and reviewed claims with probability and GRADE"
  $words = Eval "(function(){ var t = document.getElementById('pathways').innerText; return (t.match(/\b(active|activity|measured|measures)\b/ig) || []).join(','); })()"
  Check ($words -eq '') ("R286 PACK GATE 3: NO PATHWAY IS SAID TO BE ACTIVE OR MEASURED -- the words never appear in the Pathways view (" + $words + ")")
  # ---- GATE 4: the reviewed lexicon rule answers "fermented" on an opened item ---------------------------
  [void](Eval "(function(){ var S = HT.state(), t = HT.todayKey(); S.days[t] = { status: 'in_progress', water_l: 0, items: [{ name: 'kimchi', meal: 'lunch', time: '12:00', confidence: 'eyeballed', source: 'ai-paste', grams: 50, kcal: 10, protein_g: 1, fat_g: 0, carb_g: 2, fiber_g: 1, soluble_fiber_g: 0, notes: '' }] }; S.current = t; HT.resave(); HT.itemCollapseAll(); HT.dayGroupsOpenAll(true); HT.refresh(); return 1; })()"); WaitQuiet 'kimchi'
  [void](TapSel '.mitem .mhead')
  $f4 = Eval "(document.querySelector('.mitem .mferm') || {}).textContent || ''"
  Write-Host ("  fermented: " + $f4)
  Check ($f4 -like 'Fermented: yes*provisional*your lexicon rule lx-001*Hi live microbes*Marco et al. 2022*CC BY-NC 4.0*') "R286 PACK GATE 4: AN OPENED FOOD SAYS IT IS FERMENTED, AND WHERE THAT COMES FROM -- provisional, the reviewed lexicon rule named, Marco's tier cited with its licence"
  # ---- GATE 5: removed, it is gone ---------------------------------------------------------------------
  [void](Eval "HT.packRemove()"); WaitQuiet 'removed'
  $g5 = Eval "(document.getElementById('pathways') || {}).textContent || ''"
  Check (($g5 -like '*No pathway pack on this phone*') -and ((Eval "localStorage.getItem(HT.PACK_KEY) === null") -eq $true)) "R286 PACK GATE 5: REMOVED, THE PACK IS GONE from the phone and the Pathways view says so"
  Remove-Item $pdir -Recurse -Force -ErrorAction SilentlyContinue

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("PACK GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "PACK GATE: PASS -- a pack imports only when it matches its fingerprint, stays out of the backup, shows its groups with each record behind an i, never calls a pathway active, and answers fermented from a reviewed rule."
Write-Host "GATE: PASS"
exit 0
