# R213/B2-B4 -- THE STACK ITEM'S KIND, A FOOD FROM ITS LABEL, AND THE INTAKE NOTE.
# By real typing and real taps at 390 px.
#
#   B3  REPORTED: a food the user takes daily is in neither food database and was
#       entered with a different food standing in. RULED GATE: create from label
#       -> save in the stack -> log -> the day's totals include it, with "from
#       label" provenance. Also: found again by name; usable as a combo part.
#   B2  Supplement (default), Medication, Food. The word leads the row on the
#       timeline and on the day. Medication is distinct in the stored record.
#   B4  An intake flag is a small note: COLLAPSED BY DEFAULT, a 44-point target,
#       opens on a tap to at least 16px, and is collapsed AGAIN after the surface
#       is redrawn -- in the stack editor, on the Log sheet and in the panel.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8307
$Dbg = 9513
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-myfood-" + [System.Guid]::NewGuid().ToString('N'))
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
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { } }

$fails = @()
function Check([bool]$ok, [string]$name) {
  if ($ok) { Write-Host ("  PASS  " + $name) } else { Write-Host ("  FAIL  " + $name); $script:fails += $name } }

try {
  Start-Sleep -Milliseconds 600
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new",
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

  $boot = Eval "typeof HT === 'object' && typeof HT.myFoodUpsert === 'function' && typeof HT.intakeNoteHTML === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R213 functions are not on HT"; Cleanup; exit 2 }
  [void](EvalA "HT.corpusEnsure().then(function (r) { return { ok: !!(r && r.ok) }; })")

  # ---- B3: a food that is in neither database, from its label, into the stack ---------
  [void](Eval "(function(){ HT.openSettings(); var d = document.getElementById('stackDetails'); if (!d.open) d.querySelector('summary').click(); document.querySelector('#stackEditor .stkadd').click(); return 1; })()")
  $k0 = EvalJ "(function(){ var bs = document.querySelectorAll('#stackEditor .stkkinds button'); return { words: Array.prototype.map.call(bs, function (b) { return b.textContent; }), on: (document.querySelector('#stackEditor .stkkinds button.on') || {}).textContent, low: Array.prototype.filter.call(bs, function (b) { return b.getBoundingClientRect().height < 44 || parseFloat(getComputedStyle(b).fontSize) < 16; }).length }; })()"
  Write-Host ("  the kinds: " + $k0)
  Check ($k0.Contains('"words":["Supplement","Medication","Food"]') -and $k0.Contains('"on":"Supplement"') -and $k0.Contains('"low":0')) "R213/B2: a new stack item offers Supplement, Medication, Food -- SUPPLEMENT chosen by default -- each 44 px and 16px"
  [void](Eval "document.querySelectorAll('#stackEditor .stkkinds button')[2].click()")
  [void](Eval "document.getElementById('stkQuery').focus()"); TypeText 'zzqq oil'
  Settle
  $n0 = EvalJ "(function(){ var l = document.querySelector('#stkRows .fqnewfood'); var r = l ? l.getBoundingClientRect() : null; return { link: l ? l.textContent : '', h: r ? r.height : 0, px: l ? parseFloat(getComputedStyle(l).fontSize) : 0, dbRows: document.querySelectorAll('#stkRows .fqrow').length }; })()"
  Write-Host ("  a food the database does not hold: " + $n0)
  Check ($n0.Contains('"link":"Not in the database? Add it from its label"')) "R213/B3: typing a food the database does not hold offers 'Not in the database? Add it from its label', above whatever the database did find for those words"
  Check ((($n0 | ConvertFrom-Json).h -ge 44) -and (($n0 | ConvertFrom-Json).px -ge 16)) "as a visible 44 px, 16px control"
  [void](Eval "document.querySelector('#stkRows .fqnewfood').click()")
  $f0 = EvalJ "(function(){ var f = document.querySelector('#stkFood .mfform'); var n = document.getElementById('mfName'); return { form: !!f, name: n ? n.value : '', basis: (document.getElementById('mfBasis') || {}).value, per: (document.getElementById('mfPer') || {}).value, small: f ? Array.prototype.filter.call(f.querySelectorAll('input,select,button'), function (c) { return parseFloat(getComputedStyle(c).fontSize) < 16; }).length : -1, wide: f ? f.scrollWidth - f.clientWidth : -1 }; })()"
  Write-Host ("  the label form: " + $f0)
  Check ($f0 -like '*"form":true*"name":"zzqq oil"*"basis":"label"*"per":"100g"*"small":0*"wide":0*') "the form opens with the typed name carried in, 'from the label' and 'per 100 g' selected, every control 16px, nothing off the side"
  [void](Eval "(function(){ var n = document.getElementById('mfName'); n.focus(); n.select(); return 1; })()"); TypeText 'Gate seed oil'
  [void](Eval "(function(){ document.getElementById('mfPer').value = 'serving'; document.getElementById('mfServing').focus(); return 1; })()"); TypeText '14'
  [void](Eval "document.getElementById('mfKcal').focus()"); TypeText '120'
  [void](Eval "document.getElementById('mfFat').focus()"); TypeText '14'
  [void](Eval "document.querySelector('#stkFood .mfsave').click()")
  Settle
  $f1 = EvalJ "(function(){ var S = HT.state(); var f = (S.settings.foods || [])[0] || { per100: {} }; var g = document.getElementById('stkGrams'); return { foods: (S.settings.foods || []).length, name: f.name, basis: f.basis, kcal100: Math.round(f.per100.kcal), fat100: Math.round(f.per100.fat_g), serving: f.serving_g, picked: (document.querySelector('#stackEditor .stkpicked') || {}).textContent || '', grams: g ? g.value : '', formGone: !document.querySelector('#stkFood .mfform') }; })()"
  Write-Host ("  saved: " + $f1)
  Check ($f1 -like '*"foods":1*"name":"Gate seed oil"*"basis":"label"*"kcal100":857*"fat100":100*"serving":14*') "R213/B3 GATE: CREATED FROM ITS LABEL -- typed per 14 g serving, stored per 100 g (857 cal, 100 g fat), kept in my foods"
  Check ($f1 -like '*"picked":"Your food, from label: Gate seed oil"*"grams":"14"*"formGone":true*') "and it is picked into the stack item straight away, with the label's serving offered as the grams"
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  $s1 = EvalJ "(function(){ var st = HT.state().settings.stack || []; var s = st[0] || { part: {} }; var row = document.querySelector('#stackEditor .stkrow .stksub'); return { n: st.length, kind: s.kind, grams: (s.part || {}).grams, basis: (s.part || {}).basis, kcal: Math.round((s.part || {}).kcal), row: row ? row.textContent : '' }; })()"
  Write-Host ("  in the stack: " + $s1)
  Check ($s1 -like '*"n":1*"kind":"food"*"grams":14*"basis":"label"*"kcal":120*') "R213/B3 GATE: SAVED IN THE STACK as a Food, 14 g, 120 cal, carrying 'label' as its basis"
  Check (($s1 | ConvertFrom-Json).row -like 'Food*14 g*from label*counts in your day*') "its row reads Food, 14 g, from label, counts in your day"

  # a supplement over its cited level, and a medication, by the editor
  [void](Eval "(function(){ document.querySelector('#stackEditor .stkadd').click(); document.getElementById('stkName').focus(); return 1; })()"); TypeText 'Gate vitamin D'
  [void](Eval "(function(){ document.querySelector('#stkSuggest .stksug').click(); document.getElementById('stkUnit').value = 'IU'; document.getElementById('stkDose').focus(); return 1; })()"); TypeText '6000'
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle
  [void](Eval "(function(){ document.querySelector('#stackEditor .stkadd').click(); document.querySelectorAll('#stackEditor .stkkinds button')[1].click(); document.getElementById('stkName').focus(); return 1; })()"); TypeText 'Gate medicine'
  [void](Eval "document.getElementById('stkDose').focus()"); TypeText '10'
  [void](Eval "document.querySelector('#stackEditor .stksave').click()")
  Settle

  # ---- B4: the note, in the editor ----------------------------------------------------------
  $note = @'
(function (sel) {
  var all = document.querySelectorAll(sel + ' details.iflag');
  var d = all[0];
  if (!d) return { n: 0 };
  var sm = d.querySelector('summary'), bd = d.querySelector('.iflagbody'), ic = d.querySelector('svg.iflagico');
  sm.scrollIntoView({ block: 'center' });
  // A closed <details> keeps a box for its hidden content, so the body's own
  // height says nothing. What is measured is whether the body is VISIBLE, and
  // how tall the whole note is -- closed, it is its summary and no more.
  var r = sm.getBoundingClientRect();
  var vis = function () { return typeof bd.checkVisibility === 'function' ? bd.checkVisibility({ contentVisibilityAuto: true }) : d.open; };
  var out = { n: all.length, openBefore: d.open, bodyBefore: vis() ? 1 : 0, noteBefore: Math.round(d.getBoundingClientRect().height), label: (d.querySelector('.iflaglab') || {}).textContent, aria: sm.getAttribute('aria-label'),
              h: Math.round(r.height), w: Math.round(r.width), icon: !!ic && ic.getBoundingClientRect().width > 0, colour: getComputedStyle(sm).color,
              red: getComputedStyle(document.documentElement).getPropertyValue('--bad').trim(), labPx: parseFloat(getComputedStyle(d.querySelector('.iflaglab')).fontSize) };
  sm.click();
  var b1 = bd.getBoundingClientRect();
  out.openAfter = d.open; out.bodyAfter = vis() ? Math.round(b1.height) : 0; out.noteAfter = Math.round(d.getBoundingClientRect().height); out.bodyPx = parseFloat(getComputedStyle(bd).fontSize); out.text = bd.textContent;
  out.wide = bd.scrollWidth - bd.clientWidth;
  return out;
})
'@
  $rgb = "(function (hex) { var c = document.createElement('span'); c.style.color = hex; document.body.appendChild(c); var v = getComputedStyle(c).color; c.remove(); return v; })"
  $n1 = EvalJ ($note + "('#stackEditor')")
  Write-Host ("  the note in the editor: " + $n1)
  $n1v = $n1 | ConvertFrom-Json
  $redRgb = Eval ($rgb + "('" + $n1v.red + "')")
  Check (($n1v.n -eq 1) -and ($n1v.openBefore -eq $false) -and ($n1v.bodyBefore -eq 0) -and ($n1v.noteBefore -le 52)) ("R213/B4 GATE: in the stack editor the flag is COLLAPSED BY DEFAULT -- its sentence is not visible and the note is " + $n1v.noteBefore + " px tall, its summary and no more")
  Check (($n1v.label -eq ('Intake note ' + [char]0x2014 + ' tap to read')) -and ($n1v.aria -eq $n1v.label) -and ($n1v.icon -eq $true) -and ($n1v.h -ge 44) -and ($n1v.w -ge 44) -and ($n1v.labPx -ge 16)) "it is an icon and 'Intake note - tap to read', a 44 x 44 target, 16px, named the same for a screen reader"
  Check (($n1v.colour -ne $redRgb) -and ($n1v.colour -ne 'rgb(0, 0, 0)')) ("its colour is not the app's red (" + $n1v.colour + " against " + $redRgb + ")")
  Check (($n1v.openAfter -eq $true) -and ($n1v.bodyAfter -gt 0) -and ($n1v.noteAfter -gt ($n1v.noteBefore + 40)) -and ($n1v.bodyPx -ge 16) -and ($n1v.wide -le 0)) "R213/B4 GATE: it EXPANDS ON A TAP, to 16px, within the screen"
  Check (($n1v.text -like 'This item: 150 *This is above*100 * (4000 IU) of Vitamin D*Source: *') ) "expanded it gives MY AMOUNT, the level, and the source"
  [void](Eval "(function(){ HT.closeSettings(); HT.openSettings(); return 1; })()")
  $n1b = EvalJ "(function(){ var d = document.querySelector('#stackEditor details.iflag'); return { open: d ? d.open : null }; })()"
  Check ($n1b -like '*"open":false*') "R213/B4 GATE: COLLAPSED AGAIN the next time the screen is shown -- nothing remembers it was opened"

  # ---- log it: kinds on the timeline and the day; totals; the notes on the sheet and panel ----
  [void](Eval "(function(){ HT.closeSettings(); HT.openSheet(); document.querySelector('#sheetRoot .stkopen').click(); return 1; })()")
  $n2 = EvalJ ($note + "('#sheetRoot')")
  Write-Host ("  the note on the Log sheet: " + $n2)
  $n2v = $n2 | ConvertFrom-Json
  Check (($n2v.n -eq 1) -and ($n2v.openBefore -eq $false) -and ($n2v.bodyBefore -eq 0) -and ($n2v.noteBefore -le 52) -and ($n2v.h -ge 44) -and ($n2v.openAfter -eq $true) -and ($n2v.bodyAfter -gt 0) -and ($n2v.bodyPx -ge 16)) "R213/B4 GATE: on the Log sheet the same -- collapsed, 44 px, opens to 16px"
  $subs = EvalJ "(function(){ return Array.prototype.map.call(document.querySelectorAll('#sheetRoot .stkrow .stksub'), function (e) { return e.textContent.split(' ')[0]; }); })()"
  Check ([string]$subs -eq '["Food","Supplement","Medication"]') "R213/B2: each row on the Log sheet leads with its kind's word"
  $k0d = EvalJ "(function(){ return { kcal: HT.dayTotals(HT.state().days[HT.todayKey()]).kcal, fat: HT.dayTotals(HT.state().days[HT.todayKey()]).fat_g }; })()"
  [void](Eval "(function(){ document.querySelector('#sheetRoot .stklog').click(); HT.closeSheet(); Array.prototype.forEach.call(document.querySelectorAll('#dayView .mghead'), function (h) { if (h.className.indexOf('bghead') < 0 && h.getAttribute('aria-expanded') !== 'true') h.click(); }); return 1; })()")
  Settle
  $day = EvalJ @'
(function () {
  var t = HT.todayKey(), S = HT.state(), d = S.days[t];
  var row = document.querySelector('#dayView .mitem');
  if (row) row.querySelector('.mhead').click();
  row = document.querySelector('#dayView .mitem');
  var src = row ? row.querySelector('.mbody .src') : null, nm = row ? row.querySelector('.mname') : null;
  HT.renderTimeline && HT.renderTimeline();
  var tl = Array.prototype.map.call(document.querySelectorAll('.tlrow[data-sidx]'), function (r) { return (r.querySelector('.tltag') || {}).textContent + '|' + (r.querySelector('.tlmain') || {}).textContent.replace(/\s+/g, ' ').trim(); });
  return { items: d.items.map(function (i) { return i.name + '|' + i.grams + '|' + Math.round(i.kcal) + '|' + i.basis + '|' + i.stackKind + '|' + (i.ref ? 'ref' : 'no-ref'); }),
           kcal: Math.round(HT.dayTotals(d).kcal * 1000) / 1000, fat: Math.round(HT.dayTotals(d).fat_g * 1000) / 1000,
           name: nm ? nm.textContent : '', src: src ? src.textContent : '', srcSeen: src ? src.getBoundingClientRect().height > 0 : false, srcPx: src ? parseFloat(getComputedStyle(src).fontSize) : 0,
           recs: (S.timeline[t] || []).map(function (r) { return r.name + '|' + r.kind + '|' + r.stackKind; }), tl: tl,
           bio: (function () { var h = document.querySelector('#dayView .bghead'); if (h && h.getAttribute('aria-expanded') !== 'true') h.click();
                               return Array.prototype.map.call(document.querySelectorAll('#dayView .bgdose'), function (e) { return e.innerText.replace(/\s+/g, ' ').trim(); }); })() };
})()
'@
  Write-Host ("  logged: " + $day)
  $dv = $day | ConvertFrom-Json
  $kb = ($k0d | ConvertFrom-Json)
  Check ((@($dv.items).Count -eq 1) -and ($dv.items[0] -eq 'Gate seed oil|14|120|label|food|no-ref')) "R213/B3 GATE: LOGGED -- one day item, 14 g, 120 cal, basis 'label', and no database citation, because it has none"
  Check (([Math]::Abs([double]$dv.kcal - ([double]$kb.kcal + 120)) -lt 0.01) -and ([Math]::Abs([double]$dv.fat - ([double]$kb.fat + 14)) -lt 0.01)) "R213/B3 GATE: THE DAY'S TOTALS INCLUDE IT -- 120 cal and 14 g of fat more than before"
  Check (($dv.src -eq 'from label') -and ($dv.srcSeen -eq $true) -and ($dv.srcPx -ge 16)) "R213/B3 GATE: and its row SAYS 'from label', on screen, at 16px"
  Check ($dv.name -like ('Food ' + [char]0xB7 + ' Gate seed oil')) "R213/B2: on the day view the entry leads with its kind: 'Food . Gate seed oil'"
  Check ((@($dv.recs) -contains 'Gate vitamin D|medication|supplement') -and (@($dv.recs) -contains 'Gate medicine|medication|medication')) "R213/B2 GATE: MEDICATION IS DISTINCT IN THE DATA -- both are dose records, one stored as a supplement and one as a medication"
  Check ((@(@($dv.tl) | Where-Object { $_ -like ('supp|Supplement ' + [char]0xB7 + ' Gate vitamin D 6000 IU*') }).Count -eq 1) -and (@(@($dv.tl) | Where-Object { $_ -like ('med|Medication ' + [char]0xB7 + ' Gate medicine 10 mg*') }).Count -eq 1)) "R213/B2: the timeline rows read 'Supplement . Gate vitamin D 6000 IU' and 'Medication . Gate medicine 10 mg' -- a supplement is no longer tagged 'med'"

  Check ((@(@($dv.bio) | Where-Object { $_ -like ('*Supplement ' + [char]0xB7 + ' Gate vitamin D*6000 IU') }).Count -eq 1) -and (@(@($dv.bio) | Where-Object { $_ -like ('*Medication ' + [char]0xB7 + ' Gate medicine*10 mg') }).Count -eq 1) -and (@(@($dv.bio) | Where-Object { $_ -match '\bmedication$' }).Count -eq 0)) ("R213/B2: on the DAY VIEW each dose reads its kind, its name and its amount -- it printed the bare word 'medication' (" + (@($dv.bio) -join ' ; ') + ")")
  [void](Eval "(function(){ var det = document.querySelector('details.mpanel'); if (det && !det.open) { det.open = true; HT.panelToggle(true); } HT.renderPanel(); return 1; })()")
  $n3 = EvalJ ($note + "('#microPanel')")
  Write-Host ("  the note in the panel: " + $n3)
  $n3v = $n3 | ConvertFrom-Json
  Check (($n3v.n -eq 1) -and ($n3v.openBefore -eq $false) -and ($n3v.bodyBefore -eq 0) -and ($n3v.noteBefore -le 52) -and ($n3v.h -ge 44) -and ($n3v.openAfter -eq $true) -and ($n3v.bodyAfter -gt 0) -and ($n3v.bodyPx -ge 16) -and ($n3v.wide -le 0)) "R213/B4 GATE: in the Micronutrients panel the same -- collapsed, 44 px, opens to 16px"
  Check ($n3v.text -like 'Today: 150 *from your stack*This is above*Source: *') "and expanded it gives the day's amount by source, the level and the source"
  [void](Eval "HT.renderPanel()")
  Check ((EvalJ "(function(){ var d = document.querySelector('#microPanel details.iflag'); return { open: d ? d.open : null }; })()") -like '*"open":false*') "collapsed again when the panel is redrawn"

  # ---- found again by name; and as a combo part -------------------------------------------------
  [void](Eval "(function(){ HT.openSheet(); document.querySelector('#sheetRoot .srnew').click(); document.getElementById('cnName').focus(); return 1; })()"); TypeText 'Gate combo'
  [void](Eval "document.getElementById('cnQuery').focus()"); TypeText 'seed'
  Settle
  $c0 = EvalJ "(function(){ var own = document.querySelectorAll('#cnRows .fqown'); var first = document.querySelector('#cnRows .fqrow'); return { own: own.length, text: own[0] ? own[0].innerText.replace(/\s+/g, ' ') : '', first: !!first && first.classList.contains('fqown') }; })()"
  Write-Host ("  found again in a combo: " + $c0)
  Check ($c0 -like '*"own":1*Gate seed oil*from label, per 100 g: 857 cal*"first":true*') "R213/B3: typed into a combo's search, the food is FOUND BY NAME, listed first, saying where its numbers come from"
  [void](Eval "document.querySelector('#cnRows .fqown').click()")
  Settle
  [void](Eval "document.querySelector('.cnsave').click()")
  Settle
  $c1 = EvalJ "(function(){ var c = (HT.state().settings.combos || [])[0] || { parts: [{}] }; var r = HT.logCombo(c.id, 1); var it = r.ok ? r.items[0] : {}; return { combo: c.name, part: c.parts[0].name + '|' + c.parts[0].grams + '|' + c.parts[0].basis, logged: it.name + '|' + it.grams + '|' + Math.round(it.kcal) + '|' + it.basis }; })()"
  Write-Host ("  as a combo part: " + $c1)
  Check ($c1 -like '*"combo":"Gate combo"*"part":"Gate seed oil|14|label"*"logged":"Gate seed oil|14|120|label"*') "R213/B3: it is saved as a COMBO PART at its serving, and logs from the combo with the same numbers and the same basis"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("MY FOOD GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "MY FOOD GATE: PASS -- a food from its label is created, saved in the stack, logged, counted in"
Write-Host "  the day and marked 'from label'; a stack item says which kind it is and a"
Write-Host "  medication is distinct in the data; an intake note is collapsed until tapped."
Write-Host "GATE: PASS"
exit 0
