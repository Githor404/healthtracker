# R207 / R208 -- A STACK DOSE THAT COUNTS TOWARD A NUTRIENT.
#
# MEASURED BEFORE THIS WAS BUILT: a stack item set to "goes on my timeline" wrote
# a dose record and added nothing to any nutrient total, and the only flag
# compared ONE item's own amount to the limit -- never the day.
#
# RULED (R208), and each is asserted on what is rendered or stored, after real
# typing and real taps:
#   1. the editor SUGGESTS a nutrient when the name holds one, and never sets it:
#      the list still reads "nothing" until the user taps the suggestion
#   2. a mapped dose adds to that nutrient's day total as its own "from your
#      stack" line, with no calories; an unmapped dose stays on the timeline only
#   3. a limit's SCOPE decides what is compared to it:
#        vitamin D  -- total: food + stack.  40 from food + 75 from the stack is
#                      flagged at 115, where neither part alone is over
#        magnesium  -- supplemental only.   400 from food + 300 from the stack is
#                      NOT flagged; 400 from the stack IS
#   4. the flag names its source and its scope, and holds no instruction
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8303
$Dbg = 9509
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-stacktotals-" + [System.Guid]::NewGuid().ToString('N'))
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
function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }

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
  Start-Sleep -Milliseconds 600
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
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }

  $boot = Eval "typeof HT === 'object' && typeof HT.dayIntakeFlags === 'function' && typeof HT.stackSuggestMicro === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R208 functions are not on HT"; Cleanup; exit 2 }

  # food on the day, with a LABEL's magnesium and vitamin D
  [void](EvalJ @'
(function () {
  var t = HT.todayKey();
  HT.state().days[t].items = [HT.normalizeItem({ name: 'Gate greens', meal: 'lunch', time: '12:00', kcal: 120, protein_g: 4, fat_g: 1, carb_g: 20, fiber_g: 5, soluble_fiber_g: 0,
    confidence: 'measured', source: 'scan', barcode: '00000000', micros: { magnesium_mg: 400, vitamin_d_ug: 40 } }, true)];
  HT.resave(); HT.refresh();
  return 1;
})()
'@)
  $add = "(function(){ HT.openSettings(); var d = document.getElementById('stackDetails'); if (!d.open) d.querySelector('summary').click(); document.querySelector('#stackEditor .stkadd').click(); document.getElementById('stkName').focus(); return 1; })()"
  $look = @'
(function () {
  var sel = document.getElementById('stkMicro'), b = document.querySelector('#stkSuggest .stksug');
  var r = b ? b.getBoundingClientRect() : null;
  return { select: sel ? sel.value : '(none)', shown: sel ? sel.options[sel.selectedIndex].textContent : '', sug: b ? b.textContent : '',
           h: r ? r.height : 0, w: r ? r.width : 0, px: b ? parseFloat(getComputedStyle(b).fontSize) : 0 };
})()
'@

  # ---- 1. the suggestion ------------------------------------------------------------
  [void](Eval $add)
  TypeText 'Gate magnesium'
  $s1 = EvalJ $look
  Write-Host ("  name typed: " + $s1)
  $s1v = $s1 | ConvertFrom-Json
  Check (($s1v.select -eq '') -and ($s1v.shown -eq 'nothing')) "R208 GATE: with 'Gate magnesium' TYPED, 'Counts toward' still reads NOTHING -- the app set nothing by itself"
  Check (($s1v.sug -eq 'Count it toward Magnesium?') -and ($s1v.h -ge 44) -and ($s1v.w -gt 0) -and ($s1v.px -ge 16)) "R208 GATE: and it SUGGESTS it, as a visible button -- 'Count it toward Magnesium?', 44 px, 16px"
  [void](Eval "document.querySelector('#stkSuggest .stksug').click()")
  $s2 = EvalJ $look
  Check ($s2 -like '*"select":"magnesium_mg"*"shown":"Magnesium"*"sug":""*') "tapped, the list reads Magnesium and the suggestion is gone -- set by the user's tap"
  [void](Eval "document.getElementById('stkDose').focus()"); TypeText '300'
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  [void](Eval "(function(){ document.querySelector('#stackEditor .stkadd').click(); document.getElementById('stkName').focus(); return 1; })()")
  TypeText 'Gate vitamin D'
  [void](Eval "document.querySelector('#stkSuggest .stksug').click()")
  [void](Eval "(function(){ var u = document.getElementById('stkUnit'); u.value = 'IU'; document.getElementById('stkDose').focus(); return 1; })()"); TypeText '3000'
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  [void](Eval "(function(){ document.querySelector('#stackEditor .stkadd').click(); document.getElementById('stkName').focus(); return 1; })()")
  TypeText 'Gate herb'
  $s3 = EvalJ $look
  [void](Eval "document.getElementById('stkDose').focus()"); TypeText '500'
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  Check ($s3 -like '*"select":""*"sug":""*') "CONTROL: a name with no tracked nutrient in it ('Gate herb') is offered NO suggestion"
  $st = EvalJ @'
(function () {
  var S = HT.state(), t = HT.todayKey(), st = S.settings.stack || [];
  return { n: st.length, map: st.map(function (s) { return s.name + '|' + s.dose + '|' + s.dose_unit + '|' + JSON.stringify((s.nutrients && s.nutrients.micros) || {}); }),
           rows: Array.prototype.map.call(document.querySelectorAll('#stackEditor .stkrow .stksub'), function (e) { return e.textContent; }),
           doses: (S.timeline[t] || []).length };
})()
'@
  Write-Host ("  the stack: " + $st)
  $stv = $st | ConvertFrom-Json
  Check (($stv.n -eq 3) -and ($stv.map[0] -eq 'Gate magnesium|300|mg|{"magnesium_mg":300}') -and ($stv.map[1] -eq 'Gate vitamin D|3000|IU|{"vitamin_d_ug":75}') -and ($stv.map[2] -eq 'Gate herb|500|mg|{}')) "the three are saved as set: 300 mg toward magnesium, 3000 IU toward vitamin D as 75 micrograms, and the third toward nothing"
  Check (($stv.rows[0] -like '*counts toward Magnesium*') -and ($stv.rows[1] -like '*counts toward Vitamin D*') -and (-not ($stv.rows[2] -like '*counts toward*')) -and ($stv.doses -eq 0)) "each row SAYS what it counts toward, the third says nothing of the kind, and nothing has been logged"

  # ---- 2. logged: 400 from food + 300 from the stack -----------------------------------
  $panel = @'
(function () {
  var t = HT.todayKey();
  var det = document.querySelector('details.mpanel');
  if (det && !det.open) { det.open = true; HT.panelToggle(true); }
  HT.renderPanel();
  var row = function (name) {
    var r = Array.prototype.filter.call(document.querySelectorAll('#microPanel .prow'), function (x) { return ((x.querySelector('.pname') || {}).textContent || '').trim() === name; })[0];
    if (!r) return { found: false };
    var st = r.querySelector('.pstack'), fl = r.querySelector('.pflag');
    var sb = st ? st.getBoundingClientRect() : null, fb = fl ? fl.getBoundingClientRect() : null;
    return { found: true, val: (r.querySelector('.pval') || {}).textContent, stack: st ? st.textContent : '', stackSeen: sb ? (sb.height > 0 && sb.width > 0) : false,
             stackPx: st ? parseFloat(getComputedStyle(st).fontSize) : 0, flag: fl ? ((fl.querySelector('.iflagbody') || {}).textContent || '') : '', flagSeen: fb ? (fb.height > 0 && fb.width > 0) : false,
             flagPx: fl ? parseFloat(getComputedStyle(fl.querySelector('.iflaglab')).fontSize) : 0, wide: r.scrollWidth - r.clientWidth };
  };
  var day = HT.state().days[t], tl = HT.state().timeline[t] || [];
  return { mg: row('Magnesium'), vd: row('Vitamin D'), flags: document.querySelectorAll('#microPanel .pflag').length,
           kcal: HT.dayTotals(day).kcal, items: day.items.length, doses: tl.length,
           herb: tl.filter(function (r) { return r.name === 'Gate herb'; }).map(function (r) { return r.micros === undefined; }) };
})()
'@
  [void](Eval "(function(){ HT.closeSettings(); HT.openSheet(); document.querySelector('#sheetRoot .stkopen').click(); document.querySelector('#sheetRoot .stkall').click(); HT.closeSheet(); return 1; })()")
  Settle
  $p1 = EvalJ $panel
  Write-Host ("  food 400 + stack 300: " + $p1)
  $p1v = $p1 | ConvertFrom-Json
  Check (($p1v.doses -eq 3) -and ($p1v.items -eq 1) -and ($p1v.kcal -eq 120)) "R208 GATE: the tap wrote three doses and NO day item, and the day's CALORIES are unchanged at 120"
  Check (($p1v.mg.found -eq $true) -and ($p1v.mg.val -like '700.00*') -and ($p1v.mg.stack -eq 'includes 300.00 mg from your stack') -and ($p1v.mg.stackSeen -eq $true) -and ($p1v.mg.stackPx -ge 16)) "R208 GATE: Magnesium's row reads 700 mg and SAYS 'includes 300.00 mg from your stack' -- its own line, on screen, at 16px"
  Check (($p1v.mg.flag -eq '') -and ($p1v.mg.wide -le 0)) "R208 GATE: FOOD 400 + STACK 300 -> NO FLAG on magnesium. Its level is about supplements only: 300 is under 350, and the food is not counted toward it"
  Check (($p1v.vd.val -like '115.0*') -and ($p1v.vd.stack -like 'includes 75.0*from your stack') -and ($p1v.vd.flag -like 'Today: 115 *75 * from your stack*40 * from food labels*') -and ($p1v.vd.flagSeen -eq $true) -and ($p1v.vd.flagPx -ge 16)) "R208 GATE: VITAMIN D IS SUMMED AND FLAGGED ON THE TOTAL -- 40 from food + 75 from the stack = 115, and the flag says what was summed"
  Check (($p1v.flags -eq 1) -and (@($p1v.herb).Count -eq 1) -and ($p1v.herb[0] -eq $true)) "one flag in the whole panel; and the unmapped dose carries no nutrient -- it is on the timeline and nowhere else"

  # ---- 3. the stack's magnesium raised to 400 ---------------------------------------------
  [void](Eval "(function(){ var t = HT.todayKey(); HT.state().timeline[t] = []; HT.resave(); HT.openSettings(); document.querySelector('#stackEditor .stkedit').click(); var d = document.getElementById('stkDose'); d.focus(); d.select(); return 1; })()")
  TypeText '400'
  $e1 = EvalJ "(function(){ return { micro: document.getElementById('stkMicro').value, name: document.getElementById('stkName').value }; })()"
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  [void](Eval "(function(){ HT.closeSettings(); HT.openSheet(); document.querySelector('#sheetRoot .stkopen').click(); return 1; })()")
  $row = EvalJ "(function(){ var r = document.querySelectorAll('#sheetRoot .stkrow')[0]; var f = r ? r.querySelector('.stkflag .iflagbody') : null; return { flag: f ? f.textContent : '' }; })()"
  [void](Eval "(function(){ document.querySelector('#sheetRoot .stkall').click(); HT.closeSheet(); return 1; })()")
  Settle
  $p2 = EvalJ $panel
  Write-Host ("  stack 400: " + $e1 + " " + $p2)
  $p2v = $p2 | ConvertFrom-Json
  Check ($e1 -like '*"micro":"magnesium_mg"*"name":"Gate magnesium"*') "reopened for editing, the item still holds what it counts toward"
  Check (($p2v.mg.val -like '800.00*') -and ($p2v.mg.stack -eq 'includes 400.00 mg from your stack')) "the row now reads 800 mg, 400 of it from the stack"
  $mf = [string]$p2v.mg.flag
  Check (($mf -like 'Today: 400 mg*400 mg from your stack*') -and ($p2v.mg.flagSeen -eq $true) -and ($p2v.mg.flagPx -ge 16)) "R208 GATE: STACK MAGNESIUM 400 -> FLAG, and the amount it names is the 400 from supplements, not the 800 on the row"
  Check (($mf -like '*Health Canada*') -and ($mf -like '*Reference values for elements*') -and ($mf -like '*350 mg of Magnesium from supplements*') -and ($mf -like '*does not include magnesium from food and water*') -and (-not ($mf -like '*food labels*')) -and (-not ($mf -like '*25-OH*'))) "R208 GATE: the flag names its SOURCE and its SCOPE -- Health Canada, supplements only, not food and water -- and does not list food it did not count"
  Check (-not ($mf -match '\b(should|reduce|stop|lower|avoid|too much|must)\b')) "R208: FLAG, NO NAG -- the sentence holds no instruction"
  Check (($row | ConvertFrom-Json).flag -like '*Health Canada*350 mg*') "and the stack row on the Log sheet keeps its own flag for the item"
  Check (($p2v.flags -eq 2) -and ($p2v.kcal -eq 120)) "two flags now, each on its own nutrient's row; calories still 120"
  $ov = EvalJ "(function(){ var p = document.getElementById('microPanel'); return { wide: p.scrollWidth - p.clientWidth, page: document.documentElement.scrollWidth - document.documentElement.clientWidth }; })()"
  Check ($ov -like '*"wide":0*"page":0*') "nothing runs off the side at 390"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("STACK TOTALS GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "STACK TOTALS GATE: PASS -- a nutrient is suggested and never set; a mapped dose"
Write-Host "  adds to its nutrient as its own line with no calories; vitamin D is flagged"
Write-Host "  on the day's total and magnesium on supplements only, each naming its source."
Write-Host "GATE: PASS"
exit 0
