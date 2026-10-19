# R215/4 + R215/3 -- MANUAL ENTRY LOOKS THE FOOD UP; A DRINK IS FOOD.
# By real typing and real taps at 390 px, on the shipped food database.
#
# RULED (R215/4): type a name -> matching rows with calories beside each -> pick
# one to prefill calories, macros and micronutrients -> adjust the amount or any
# value, an edited value marked "adjusted". No match -> "from label" (R211).
# Ruled 2026-10-14: an UNTOUCHED looked-up micro stays at reference provenance;
# a number the user TYPES OVER is theirs -- a label value -- and the item says
# "adjusted". The from-label path is gated with the user's own case, a seed oil
# in neither database, under a synthetic name (stack contents stay out of the
# repo).
#
# RULED (R215/3): a drink is food with a drink tag, logged like any food --
# found in the database, its calories in the day, then one tap from Your drinks.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8311
$Dbg = 9517
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-lookup-" + [System.Guid]::NewGuid().ToString('N'))
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
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "Promise.resolve(eval(decodeURIComponent(escape(atob('" + $enc + "'))))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text + " " + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value }
# REAL TYPING, one character at a time into whatever holds the focus.
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    Invoke-CDP 'Input.insertText' @{ text = [string]$ch } | Out-Null
    Start-Sleep -Milliseconds 70 } }
function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }
function Focus([string]$id) { [void](Eval "(function(){ var e = document.getElementById('$id'); e.focus(); if (e.select) e.select(); return 1; })()") }

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); $l.Start()
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

  $boot = Eval "typeof HT === 'object' && typeof HT.manualType === 'function' && typeof HT.drinkHistory === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R215 functions are not on HT"; Cleanup; exit 2 }
  $cr = EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok), ns: (HT.corpusState() || {}).ns }; })"
  Write-Host ("  food database: " + $cr)
  if (-not ($cr -like '*"ok":true*')) { Write-Host "ERROR: the food database did not load"; Cleanup; exit 2 }
  [void](Eval "(function(){ window.__d = HT.state().current; HT.openSheet('manual'); return 1; })()")
  $DAY = "HT.state().days[window.__d]"

  # ---- 1. type a name: rows, calories beside each, the label exit first ----------------
  Focus 'maName'; TypeText 'cheddar'
  Settle
  $r1 = EvalA @'
(function () {
  var rows = document.querySelectorAll('#maRows .fqrow');
  var exit = document.querySelector('#maRows .fqnewfood');
  var cal = Array.prototype.filter.call(rows, function (r) { return / cal$/.test((r.querySelector('.fqmac') || {}).textContent || ''); }).length;
  return { rows: rows.length, cal: cal, exit: exit ? exit.textContent : '', exitFirst: !!exit && rows.length > 0 && !!(exit.compareDocumentPosition(rows[0]) & 4),
           first: rows[0] ? rows[0].querySelector('.fqnm').textContent : '', kept: document.getElementById('maName').value,
           focused: document.activeElement && document.activeElement.id };
})()
'@
  Write-Host ("  typed 'cheddar': " + $r1)
  $a1 = $r1 | ConvertFrom-Json
  Check (($a1.rows -ge 3) -and ($a1.cal -eq $a1.rows) -and ($a1.first -like '*heddar*')) "R215/4: typing a name in Manual brings the food database's rows, each with its CALORIES beside it"
  Check (($a1.kept -eq 'cheddar') -and ($a1.focused -eq 'maName')) "the name field survives its own keystrokes -- same field, focus kept"
  Check (($a1.exit -eq 'Not in the database? Add it from its label') -and $a1.exitFirst) "'Not in the database? Add it from its label' is offered ABOVE the rows"

  # ---- 2. pick: everything filled in, at 100 g, micronutrients included ----------------
  $r2 = EvalA @'
(function () {
  document.querySelectorAll('#maRows .fqrow')[0].click();
  var v = function (id) { return (document.getElementById(id) || {}).value; };
  var micros = Array.prototype.filter.call(document.querySelectorAll('#maMicros input'), function (i) { return i.value !== ''; }).length;
  return { name: v('maName'), g: v('maGrams'), kcal: v('maKcal'), p: v('maP'), f: v('maF'), c: v('maC'), ca: v('ma_micro_calcium_mg'), na: v('ma_micro_sodium_mg'), micros: micros,
           head: (document.getElementById('maMicroHead') || {}).textContent, count: (document.getElementById('maMicroCount') || {}).textContent,
           picked: (document.querySelector('#maPicked .mapicked') || {}).textContent || '', rowsGone: document.querySelectorAll('#maRows .fqrow').length === 0 };
})()
'@
  Write-Host ("  picked: " + $r2)
  $a2 = $r2 | ConvertFrom-Json
  Check (($a2.g -eq '100') -and ([double]$a2.kcal -gt 300) -and ([double]$a2.p -gt 15) -and ([double]$a2.f -gt 20) -and ($a2.c -ne '')) "R215/4 GATE: a real click on a row PREFILLS calories, protein, fat and carbs, for 100 g when no amount was typed"
  Check (($a2.micros -ge 5) -and ([double]$a2.ca -gt 300) -and ([double]$a2.na -gt 300)) "R215/4 GATE: and the MICRONUTRIENTS -- $($a2.micros) of them, calcium and sodium among them"
  Check (($a2.head -like '*food database*') -and ($a2.count -like '*from the database*') -and -not ($a2.head -like '*(from label)*')) "the micronutrient heading says these came from the FOOD DATABASE, not from a label: '$($a2.head)$($a2.count)'"
  Check (($a2.picked -like 'From the food database:*') -and ($a2.picked -like '*marked adjusted*') -and $a2.rowsGone) "the form says which row it came from and that a changed number is marked adjusted; the rows give way to the form"

  # ---- 3. the amount rescales everything not changed --------------------------------------
  Focus 'maGrams'; TypeText '40'
  $r3 = EvalA "(function(){ var v = function (id) { return Number((document.getElementById(id) || {}).value); }; return { kcal: v('maKcal'), ca: v('ma_micro_calcium_mg') }; })()"
  Write-Host ("  at 40 g: " + $r3)
  $a3 = $r3 | ConvertFrom-Json
  Check (([Math]::Abs($a3.kcal - 0.4 * [double]$a2.kcal) -le 0.6) -and ([Math]::Abs($a3.ca - 0.4 * [double]$a2.ca) -le 0.6)) "changing the amount to 40 g rescales the calories and the calcium -- the amount is not an adjustment"

  # ---- 4. taken unchanged: exactly what Search writes ---------------------------------------
  $r4 = EvalA @"
(function () {
  var day = $DAY, n0 = day ? day.items.length : 0;
  document.querySelector('#pane-manual .btn.primary[onclick^="addManualItem"]').click();
  day = $DAY;
  var it = day.items[day.items.length - 1];
  var slot = HT.PANEL_KEY_SLOT ? HT.PANEL_KEY_SLOT.calcium_mg : null;
  return { added: day.items.length - n0, source: it.source, conf: it.confidence, ref: !!it.ref, micros: it.micros ? Object.keys(it.micros).length : 0,
           refCa: (it.ref && it.ref.v && slot != null) ? it.ref.v[slot] : null, adjusted: it.adjusted || null, word: HT.itemSourceWord(it), kcal: it.kcal,
           cleared: document.getElementById('maName').value === '' && document.getElementById('maKcal').value === '' };
})()
"@
  Write-Host ("  logged unchanged: " + $r4)
  $a4 = $r4 | ConvertFrom-Json
  Check (($a4.added -eq 1) -and ($a4.source -eq 'corpus') -and $a4.ref -and ($a4.conf -eq 'eyeballed') -and ($null -eq $a4.adjusted)) "taken UNCHANGED it is the database's own entry -- source 'corpus', cited, estimated -- and nothing is marked adjusted"
  Check (($a4.micros -eq 0) -and ([double]$a4.refCa -gt 100)) "its micronutrients stay at REFERENCE provenance, in the cited values -- none is copied in as a label value (D120)"
  Check (($a4.word -eq 'from the food database') -and $a4.cleared) "the row says 'from the food database', and the form is clear for the next one"
  [void](Eval "(function(){ var u = document.querySelector('#toast.show .tundo'); if (u) u.click(); return 1; })()")

  # ---- 5. adjusted: a typed calorie figure and a typed calcium value --------------------
  Focus 'maName'; TypeText 'cheddar'
  Settle
  [void](Eval "document.querySelectorAll('#maRows .fqrow')[0].click()")
  Focus 'maGrams'; TypeText '30'
  Focus 'maKcal'; TypeText '125'
  [void](Eval "(function(){ var d = document.querySelector('#pane-manual details.micros'); if (d) d.open = true; return 1; })()")
  Focus 'ma_micro_calcium_mg'; TypeText '200'
  $r5 = EvalA @"
(function () {
  var count = (document.getElementById('maMicroCount') || {}).textContent;
  var day = $DAY, k0 = HT.dayTotals(day).kcal;
  document.querySelector('#pane-manual .btn.primary[onclick^="addManualItem"]').click();
  day = $DAY;
  var it = day.items[day.items.length - 1];
  var slot = HT.PANEL_KEY_SLOT ? HT.PANEL_KEY_SLOT.calcium_mg : null;
  var slotNa = HT.PANEL_KEY_SLOT ? HT.PANEL_KEY_SLOT.sodium_mg : null;
  return { count: count, kcal: it.kcal, dk: HT.dayTotals(day).kcal - k0, source: it.source, adjusted: (it.adjusted || []).join(','), ca: it.micros ? it.micros.calcium_mg : null,
           refHasCa: !!(it.ref && it.ref.v && slot != null && it.ref.v[slot] != null), refNa: (it.ref && it.ref.v && slotNa != null) ? it.ref.v[slotNa] : null,
           fat: it.fat_g, word: HT.itemSourceWord(it), opened: (HT.closeSheet(), HT.dayGroupsOpenAll(true), itemToggle(window.__d, day.items.length - 1), 1),
           rowWord: (Array.prototype.filter.call(document.querySelectorAll('#dayView .src'), function (s) { return /adjusted/.test(s.textContent); })[0] || {}).textContent || '' };
})()
"@
  Write-Host ("  logged adjusted: " + $r5)
  $a5 = $r5 | ConvertFrom-Json
  Check ($a5.count -like '*from the database*1 typed*') "while typing, the count says which numbers are the database's and which are typed: '$($a5.count)'"
  Check (([double]$a5.kcal -eq 125) -and ([double]$a5.dk -eq 125) -and ($a5.source -eq 'manual') -and ($a5.adjusted -eq 'kcal,calcium_mg')) "R215/4 GATE: an edited value is the user's -- 125 cal logged and added to the day -- and the entry is MARKED ADJUSTED, naming exactly what was changed (calories, calcium)"
  Check (([double]$a5.ca -eq 200) -and (-not $a5.refHasCa) -and ([double]$a5.refNa -gt 50)) "the typed calcium is a LABEL value, and its database figure is taken out of the cited values so one nutrient is never counted twice; the untouched sodium stays at reference"
  Check ([double]$a5.fat -gt 5) "the numbers not changed are still the database's, at 30 g"
  Check (($a5.word -eq 'from the food database, adjusted') -and ($a5.rowWord -like '*adjusted*')) "on the day the row reads 'from the food database, adjusted'"

  [void](Eval "(function(){ HT.openSheet('manual'); return 1; })()")
  # ---- 6. not in either database: from its label (the user's case, a synthetic name) ----
  Focus 'maName'; TypeText 'Gate seed oil'
  Settle
  [void](Eval "document.querySelector('#maRows .fqnewfood').click()")
  $f0 = EvalA "(function(){ return { form: !!document.querySelector('#maFood .mfform'), name: (document.getElementById('mfName') || {}).value, basis: (document.getElementById('mfBasis') || {}).value, rows: document.querySelectorAll('#maRows .fqrow').length }; })()"
  Write-Host ("  the label form: " + $f0)
  Check ($f0 -like '*"form":true*"name":"Gate seed oil"*"basis":"label"*"rows":0*') "nothing fits -> a real click opens the label form IN the manual pane, the typed name carried in, 'from the label' chosen"
  [void](Eval "(function(){ document.getElementById('mfPer').value = 'serving'; return 1; })()")
  Focus 'mfServing'; TypeText '14'
  Focus 'mfKcal'; TypeText '120'
  Focus 'mfFat'; TypeText '14'
  [void](Eval "document.querySelector('#maFood .mfsave').click()")
  Settle
  $r6 = EvalA @"
(function () {
  var v = function (id) { return (document.getElementById(id) || {}).value; };
  var pre = { name: v('maName'), g: v('maGrams'), kcal: v('maKcal'), f: v('maF'), picked: (document.querySelector('#maPicked .mapicked') || {}).textContent || '' };
  var day = $DAY, k0 = HT.dayTotals(day).kcal;
  document.querySelector('#pane-manual .btn.primary[onclick^="addManualItem"]').click();
  day = $DAY;
  var it = day.items[day.items.length - 1];
  return { pre: pre, foods: (HT.state().settings.foods || []).length, name: it.name, basis: it.basis, source: it.source, kcal: it.kcal, grams: it.grams,
           dk: HT.dayTotals(day).kcal - k0, word: HT.itemSourceWord(it), adjusted: it.adjusted || null, ref: !!it.ref };
})()
"@
  Write-Host ("  from its label: " + $r6)
  $a6 = $r6 | ConvertFrom-Json
  Check (($a6.pre.name -eq 'Gate seed oil') -and ($a6.pre.g -eq '14') -and ($a6.pre.kcal -eq '120') -and ($a6.pre.f -eq '14') -and ($a6.pre.picked -like 'From your foods (from label)*')) "saved, the food is picked into the manual form at its label serving -- 14 g, 120 cal, 14 g fat -- and says it is from your foods, from label"
  Check (($a6.foods -eq 1) -and ($a6.basis -eq 'label') -and ($a6.source -eq 'manual') -and ([double]$a6.kcal -eq 120) -and ([double]$a6.dk -eq 120) -and (-not $a6.ref) -and ($null -eq $a6.adjusted)) "R215/4 GATE (from label): logged -- 120 cal in the day's total, basis 'label', no database citation because it has none, nothing adjusted"
  Check ($a6.word -eq 'from label') "and the row reads 'from label'"
  Focus 'maName'; TypeText 'Gate seed'
  Settle
  $r6b = EvalA "(function(){ var o = document.querySelector('#maRows .fqown'); return { own: o ? o.textContent : '', first: !!o && o === document.querySelector('#maRows button') }; })()"
  Write-Host ("  typed again: " + $r6b)
  Check (($r6b -like '*Gate seed oil*from label*') -and ($r6b -like '*"first":true*')) "typed again, it is found BY NAME, first, among your foods"
  [void](Eval "(function(){ HT.manualType(''); document.getElementById('maName').value = ''; return 1; })()")

  # ---- 7. the same lookup in the stack and in a combo part ---------------------------------
  $r7 = EvalA @'
(function () {
  HT.closeSheet(); HT.openSettings();
  var d = document.getElementById('stackDetails'); if (d && !d.open) d.querySelector('summary').click();
  document.querySelector('#stackEditor .stkadd').click();
  document.querySelectorAll('#stackEditor .stkkinds button')[2].click();
  return HT.stackFormSearch ? Promise.resolve(HT.stackFormSearch('cheddar')).then(function () {
    var rows = document.querySelectorAll('#stkRows .fqrow');
    var cal = Array.prototype.filter.call(rows, function (r) { return / cal$/.test((r.querySelector('.fqmac') || {}).textContent || ''); }).length;
    return { rows: rows.length, cal: cal, exit: !!document.querySelector('#stkRows .fqnewfood') };
  }) : { missing: 'stackFormSearch' };
})()
'@
  Write-Host ("  the stack's lookup: " + $r7)
  $a7 = $r7 | ConvertFrom-Json
  Check (($a7.rows -ge 3) -and ($a7.cal -eq $a7.rows) -and $a7.exit) "R215/4: the stack's food lookup is the same rows, calories beside each, with the same 'from its label' exit"
  [void](Eval "(function(){ try { HT.stackFormCancel(); } catch (e) {} HT.closeSettings(); return 1; })()")

  # ---- 8. a drink is food: found, its calories in the day, then one tap -----------------
  [void](Eval "(function(){ HT.openSheet(); document.querySelector('#sheetRoot .srdrinknew').click(); return 1; })()")
  $d0 = Eval "(document.querySelector('#searchBox .srhead') || {}).textContent"
  Check ($d0 -eq 'Log a drink') "'Log a drink' in + Log opens the food database search, headed 'Log a drink'"
  Focus 'fqQuery'; TypeText 'table wine'
  Settle
  # By NAME, not position: on the US database 'wine' leads with a vinegar -- a
  # ranking limit of its own, recorded in R215, and not this gate's question.
  $pick = Eval "(function(){ var rs = Array.prototype.filter.call(document.querySelectorAll('#fqRows .fqrow'), function (r) { var t = r.querySelector('.fqnm').textContent.toLowerCase(); return /wine/.test(t) && /table/.test(t) && !/vinegar/.test(t); }); if (rs[0]) { rs[0].click(); return rs[0].querySelector('.fqnm').textContent; } return ''; })()"
  Write-Host ("  picked the drink: " + $pick)
  Check ($pick -ne '') "a table wine is among the database's rows for 'table wine'"
  Focus 'fqGrams'; TypeText '150'
  $r8 = EvalA @"
(function () {
  var sub = (document.querySelector('#fqLog .fqsub') || {}).textContent || '';
  var day = $DAY, k0 = HT.dayTotals(day).kcal, n0 = day.items.length;
  document.querySelector('#fqLog .fqlog').click();
  day = $DAY;
  var it = day.items[day.items.length - 1];
  var hist = HT.drinkHistory();
  return { sub: sub, added: day.items.length - n0, meal: it.meal, grams: it.grams, kcal: it.kcal, dk: HT.dayTotals(day).kcal - k0, ref: !!it.ref,
           alcohol: (it.ref && it.ref.v) ? it.ref.v[221] : null, hist: hist.length, histName: hist[0] ? hist[0].name : '' };
})()
"@
  Write-Host ("  a drink: " + $r8)
  $a8 = $r8 | ConvertFrom-Json
  Check (($a8.sub -like '*as a drink*') -and ($a8.added -eq 1) -and ($a8.meal -eq 'drink') -and ([double]$a8.grams -eq 150) -and $a8.ref) "R215/3 GATE: the drink is a FOOD entry, 150 g, cited, TAGGED as a drink"
  Check (([double]$a8.kcal -gt 50) -and ([Math]::Abs([double]$a8.dk - [double]$a8.kcal) -lt 0.01)) "R215/3 GATE: and its CALORIES COUNT in the day: +$([Math]::Round([double]$a8.dk)) cal"
  Check (($a8.hist -eq 1) -and ($a8.histName -like '*ine*')) "it is in Your drinks now"
  $r9 = EvalA @"
(function () {
  HT.openSheet();
  var row = document.querySelector('#sheetRoot .drkrow');
  var day = $DAY, k0 = HT.dayTotals(day).kcal, n0 = day.items.length;
  if (row) row.click();
  day = $DAY;
  var it = day.items[day.items.length - 1];
  var out = { row: row ? row.textContent : '', added: day.items.length - n0, grams: it.grams, meal: it.meal, dk: HT.dayTotals(day).kcal - k0 };
  var u = document.querySelector('#toast.show .tundo'); out.undo = !!u; if (u) u.click();
  out.back = $DAY.items.length === n0;
  return out;
})()
"@
  Write-Host ("  one tap from Your drinks: " + $r9)
  $a9 = $r9 | ConvertFrom-Json
  Check (($a9.added -eq 1) -and ([double]$a9.grams -eq 150) -and ($a9.meal -eq 'drink') -and ([Math]::Abs([double]$a9.dk - [double]$a8.kcal) -lt 0.01)) "R215/3 GATE: ONE TAP on it logs the same drink at the LAST SIZE -- 150 g, the same calories again"
  Check ($a9.undo -and $a9.back) "and Undo takes it back"

  # ---- 9. R221/3: "Log a drink" puts drinks first, by category, on BOTH databases ----
  # Typed for real into the Log a drink search. The first row must be one the
  # database files as a beverage AND a wine; the vinegar must still be findable by
  # its full name -- promoted rows come first, nothing is hidden.
  $drinkAsk = @'
(function () {
  HT.closeSheet(); HT.openSheet();
  document.querySelector('#sheetRoot .srdrinknew').click();
  return 1;
})()
'@
  $drinkRead = @'
(function () {
  var rows = Array.prototype.map.call(document.querySelectorAll('#fqRows .fqrow .fqnm'), function (n) { return n.textContent; });
  return { ns: (HT.corpusState() || {}).ns, first: rows[0] || '', rows: rows };
})()
'@
  foreach ($db in @('US', 'CA')) {
    if ($db -eq 'CA') {
      $ua = Eval 'navigator.userAgent'
      Invoke-CDP 'Network.enable' $null | Out-Null
      Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua; acceptLanguage = 'en-CA' } | Out-Null
      Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
      Start-Sleep -Milliseconds 3000
      $cr2 = EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok), ns: (HT.corpusState() || {}).ns }; })"
      Write-Host ("  the Canadian database: " + $cr2)
    }
    [void](Eval $drinkAsk)
    Focus 'fqQuery'; TypeText 'wine'
    Settle
    $w = EvalA $drinkRead
    Write-Host ("  $db, 'wine' in Log a drink: " + $w)
    $wv = $w | ConvertFrom-Json
    Check (($wv.first -match '(?i)wine') -and -not ($wv.first -match '(?i)vinegar') -and -not ($wv.first -match '(?i)cake|sauce')) "R221/3 GATE ($db, $($wv.ns)): 'wine' in Log a drink leads with a WINE -- '$($wv.first)' -- a beverage by the database's own category"
    [void](Eval "(function(){ var f = document.getElementById('fqQuery'); f.value = ''; return 1; })()")
    Focus 'fqQuery'; TypeText 'red wine vinegar'
    Settle
    $v = EvalA $drinkRead
    Write-Host ("  $db, 'red wine vinegar': " + $v)
    Check ((($v | ConvertFrom-Json).rows | Where-Object { $_ -match '(?i)vinegar, red wine' }).Count -ge 1) "R221/3 ($db): and 'red wine vinegar' is still found by its full name -- promoted rows come first, nothing is hidden"
  }
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -eq 0) {
  Write-Host "LOOKUP GATE: PASS -- typed names bring cited rows with calories; a pick fills in macros and micronutrients; an edit is the user's and marked adjusted; from label when nothing fits; a drink is food with its calories, one tap after"
  Write-Host "GATE: PASS"
  exit 0
}
Write-Host ("LOOKUP GATE: FAIL -- " + $fails.Count + " check(s)")
Write-Host "GATE: FAIL"
exit 1
