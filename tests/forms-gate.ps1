# R198/2, R198/3, R199/2 -- THE MANUAL FORM, "ATE:" AT SAVE, AND EDITING A COMBO.
# All at 390 x 844, all by real taps and real typing, all asserted on what is
# rendered or what is stored -- never on the attribute the code set.
#
#   R198/2  the Manual form says "estimated", never "eyeballed"; the Meal box is
#           wide enough for its longest choice ("by the clock" was cut off).
#           MEASURED: a select's own natural width against the width it was
#           given. CONTROL: the same measure on a box squeezed to 60px must
#           report it as cut off -- otherwise the measure sees nothing.
#   R198/3  "Ate:" on the Manual form and on the Scan result, the photo draft's
#           own five choices. A half typed at save halves the item and keeps what
#           was served; one Undo takes back the item and its plate; a share of an
#           item with no weight is refused before anything is written.
#   R199/2  "Edit" beside My combos; a combo renamed, a part resized, a part
#           removed; the NEXT log uses the new amount and the OLD log is
#           byte-for-byte unchanged; delete removes it from My combos, leaves the
#           history intact, and can be undone. Nothing needs a long press: every
#           step below is a plain tap on something visible.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8299
$Dbg = 9505
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-forms-" + [System.Guid]::NewGuid().ToString('N'))
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

  $boot = Eval "typeof HT === 'object' && typeof HT.comboEditOpen === 'function' && typeof HT.formAteSet === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or the R198/R199 functions are not on HT"; Cleanup; exit 2 }

  $tap = "(function (label) { HT.closeSheet(); HT.openSheet(); var bs = document.querySelectorAll('#sheetRoot .srbtn'); for (var i = 0; i < bs.length; i++) if (bs[i].textContent === label) { bs[i].click(); return 1; } return 0; })"

  # ---- R198/2: the Manual form ------------------------------------------------------
  $m0 = Eval ($tap + "('Manual')")
  Settle
  $form = EvalJ @'
(function () {
  var fits = function (sel) {                    // natural width against given width
    var c = sel.cloneNode(true);
    c.removeAttribute('id');
    c.style.cssText = 'position:absolute;visibility:hidden;width:auto;flex:none;min-width:0;max-width:none';
    sel.parentNode.appendChild(c);
    var need = c.getBoundingClientRect().width;
    sel.parentNode.removeChild(c);
    return { have: Math.round(sel.getBoundingClientRect().width), need: Math.round(need) };
  };
  var pane = document.getElementById('pane-manual');
  var meal = document.getElementById('maMeal'), conf = document.getElementById('maConf');
  var opts = function (s) { return Array.prototype.map.call(s.options, function (o) { return o.textContent; }); };
  var fm = fits(meal), fc = fits(conf);
  var keep = meal.style.width; meal.style.width = '60px'; meal.style.flex = 'none';
  var squeezed = fits(meal);
  meal.style.width = keep; meal.style.flex = '';
  var text = pane.innerText;
  return { on: pane.classList.contains('on') && pane.getBoundingClientRect().height > 0,
           mealShown: meal.options[meal.selectedIndex].textContent, meal: fm, conf: fc, squeezed: squeezed,
           confShown: conf.options[conf.selectedIndex].textContent, confOpts: opts(conf), confValue: conf.value,
           word: /eyeball/i.test(text) || opts(conf).concat(opts(meal)).some(function (t) { return /eyeball/i.test(t); }),
           px: [meal, conf].map(function (s) { return parseFloat(getComputedStyle(s).fontSize); }),
           overflow: pane.scrollWidth - pane.clientWidth, vw: window.innerWidth };
})()
'@
  Write-Host ("  the Manual form at 390: " + $form)
  $fv = $form | ConvertFrom-Json
  Check (($m0 -eq 1) -and ($fv.on -eq $true) -and ($fv.vw -eq 390)) "PRECONDITION: the Manual form is open, by its button on the Log sheet, at 390 px"
  Check (($fv.confShown -eq 'estimated') -and ($fv.word -eq $false)) "R198/2: Confidence reads 'estimated' -- the word 'eyeballed' is nowhere on the form, in a label or inside a list"
  Check ($fv.confValue -eq 'eyeballed') "and what is STORED is unchanged -- the wording moved, the data contract did not"
  Check (($fv.mealShown -eq 'by the clock') -and ($fv.meal.have -ge $fv.meal.need)) ("R198/2: the Meal box is as wide as its longest choice needs -- 'by the clock' is not cut off (has " + $fv.meal.have + " px, needs " + $fv.meal.need + ")")
  Check ($fv.conf.have -ge $fv.conf.need) ("and the Confidence box likewise (has " + $fv.conf.have + ", needs " + $fv.conf.need + ")")
  Check ($fv.squeezed.have -lt $fv.squeezed.need) "CONTROL: squeezed to 60 px the SAME measure reports the box as cut off -- so the measure can see the defect it is there for"
  Check (($fv.px[0] -ge 16) -and ($fv.px[1] -ge 16) -and ($fv.overflow -le 0)) "both at 16px, and the form does not scroll sideways"

  # ---- R198/3: "Ate:" on the Manual form ----------------------------------------------
  $bar = @'
(function (id) {
  var bs = document.querySelectorAll('#' + id + ' .atebtn');
  var small = 0, low = 0;
  Array.prototype.forEach.call(bs, function (b) {
    var r = b.getBoundingClientRect();
    if (parseFloat(getComputedStyle(b).fontSize) < 16) small++;
    if (r.height < 44 || r.width < 44) low++;
  });
  var on = document.querySelector('#' + id + ' .atebtn.ateon');
  var lab = document.querySelector('#' + id + ' .atelab');
  return { n: bs.length, small: small, low: low, on: on ? on.textContent : '', lab: lab ? lab.textContent : '',
           labPx: lab ? parseFloat(getComputedStyle(lab).fontSize) : 0 };
})
'@
  $b1 = EvalJ ($bar + "('maAte')")
  Write-Host ("  Ate: on the Manual form: " + $b1)
  $b1v = $b1 | ConvertFrom-Json
  Check (($b1v.n -eq 5) -and ($b1v.lab -eq 'Ate:') -and ($b1v.on -eq 'all')) "R198/3: the Manual form has 'Ate:' with five choices, standing at ALL"
  Check (($b1v.small -eq 0) -and ($b1v.low -eq 0) -and ($b1v.labPx -ge 16)) "each choice at 16px and at least 44 x 44"

  $base = EvalJ "(function(){ var d = HT.state().days[HT.state().current] || { items: [] }; return { items: d.items.length, plates: Object.keys(HT.state().plates || {}).length }; })()"
  $bv = $base | ConvertFrom-Json
  [void](Eval "document.getElementById('maName').focus()"); TypeText 'Gate oats'
  [void](Eval "document.getElementById('maKcal').focus()"); TypeText '300'
  [void](Eval "document.getElementById('maGrams').focus()"); TypeText '200'
  $half = EvalJ @'
(function () {
  var bs = document.querySelectorAll('#maAte .atebtn'), hit = 0;
  Array.prototype.forEach.call(bs, function (b) { if (b.textContent === '\u00bd') { b.click(); hit = 1; } });
  var on = document.querySelector('#maAte .atebtn.ateon');
  return { hit: hit, on: on ? on.textContent === '\u00bd' : false, kept: document.getElementById('maName').value === 'Gate oats' && document.getElementById('maGrams').value === '200' };
})()
'@
  Check ($half -like '*"hit":1*"on":true*"kept":true*') "tapping the half marks it, and what was typed into the form is still there"
  [void](Eval "document.querySelector('#pane-manual button[onclick^=addManualItem]').click()")
  Settle
  $after = @'
(function () {
  // The day's meal groups open on a tap and the rows live inside them. Opened so
  // the row can be read; the ROW is not opened -- the line must show without that.
  Array.prototype.forEach.call(document.querySelectorAll('#dayView .mghead'), function (h) {
    if (h.className.indexOf('bghead') < 0 && h.getAttribute('aria-expanded') !== 'true') h.click(); });
  var d = HT.state().days[HT.state().current] || { items: [] };
  var it = d.items[d.items.length - 1] || {};
  var pl = it.plateId ? HT.getPlate(it.plateId) : null;
  var t = document.getElementById('toast');
  return { items: d.items.length, plates: Object.keys(HT.state().plates || {}).length, name: it.name, grams: it.grams, kcal: it.kcal,
           source: it.source, served: pl && pl.items[0] ? pl.items[0].grams : 0,
           line: HT.itemServedLine(it), dayLines: Array.prototype.map.call(document.querySelectorAll('.mserved'), function (e) { return e.getBoundingClientRect().height > 0 ? e.textContent.replace(/[ \u00a0]+/g, ' ').trim() : '(hidden)'; }),
           toast: t ? t.textContent : '', undo: !!(t && t.querySelector('.tundo') && t.classList.contains('show')),
           barBack: (document.querySelector('#maAte .atebtn.ateon') || {}).textContent || '' };
})()
'@
  $a1 = EvalJ $after
  Write-Host ("  a half, at save, on Manual: " + $a1)
  $a1v = $a1 | ConvertFrom-Json
  Check (($a1v.items -eq ($bv.items + 1)) -and ($a1v.name -eq 'Gate oats') -and ($a1v.grams -eq 100) -and ($a1v.kcal -eq 150)) "R198/3: a HALF said at save logs 100 g and 150 cal of the 200 g and 300 typed"
  Check (($a1v.served -eq 200) -and ($a1v.plates -eq ($bv.plates + 1))) "what was SERVED is kept -- 200 g, on a plate of its own"
  Check ((@($a1v.dayLines) -contains $a1v.line) -and ($a1v.line.Length -gt 0)) ("and the day SHOWS both: '" + $a1v.line + "' is on screen")
  Check (($a1v.undo -eq $true) -and ($a1v.toast -like 'Logged Gate oats*ate*')) "it is confirmed, with Undo"
  Check ($a1v.barBack -eq 'all') "and the form's 'Ate:' is back at ALL for the next item -- a half does not carry over unseen"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $u1 = EvalJ "(function(){ var d = HT.state().days[HT.state().current] || { items: [] }; return { items: d.items.length, plates: Object.keys(HT.state().plates || {}).length }; })()"
  $u1v = $u1 | ConvertFrom-Json
  Check (($u1v.items -eq $bv.items) -and ($u1v.plates -eq $bv.plates)) "ONE Undo takes back the item AND the plate made for it"

  [void](Eval "document.getElementById('maName').focus()"); TypeText 'No weight'
  [void](Eval "document.getElementById('maKcal').focus()"); TypeText '90'
  [void](Eval "(function(){ var bs = document.querySelectorAll('#maAte .atebtn'); Array.prototype.forEach.call(bs, function (b) { if (b.textContent === '\u00bc') b.click(); }); document.querySelector('#pane-manual button[onclick^=addManualItem]').click(); return 1; })()")
  Settle
  $rf = EvalJ "(function(){ var d = HT.state().days[HT.state().current] || { items: [] }; var t = document.getElementById('toast'); return { items: d.items.length, toast: t ? t.textContent : '', kept: document.getElementById('maName').value }; })()"
  Write-Host ("  a share of no weight: " + $rf)
  $rfv = $rf | ConvertFrom-Json
  Check (($rfv.items -eq $bv.items) -and ($rfv.toast -like 'Enter the portion in grams*') -and ($rfv.kept -eq 'No weight')) "a share of an item with NO WEIGHT is refused, in words, before anything is written -- and the form is not cleared"
  [void](Eval "(function(){ HT.formAteSet('manual', 1); HT.clearManualForm && HT.clearManualForm(); ['maName','maKcal','maGrams'].forEach(function (i) { document.getElementById(i).value = ''; }); return 1; })()")

  # ---- R198/3: "Ate:" on the Scan result ----------------------------------------------
  # The product is put in the device's own product cache through the lookup's
  # injected fetch, so the scan below is the real cache-first path and no request
  # leaves the page.
  $seed = EvalA @'
HT.lookupBarcode('3017620422003', { fetchImpl: function () {
  return Promise.resolve({ status: 1, product: { product_name: 'Gate spread', serving_size: '30 g', serving_quantity: 30,
    nutriments: { 'energy-kcal_100g': 500, 'proteins_100g': 6, 'fat_100g': 30, 'carbohydrates_100g': 57, 'fiber_100g': 2, 'iron_100g': 0.004 } } });
} }).then(function (r) { return { found: !!(r && r.found), source: r && r.source }; })
'@
  $s0 = Eval ($tap + "('Scan')")
  Settle
  [void](Eval "document.getElementById('scanBarcode').focus()")
  TypeText '3017620422003'
  [void](Eval "document.querySelector('#pane-scan button[onclick^=doBarcodeLookup]').click()")
  Settle
  $b2 = EvalJ ($bar + "('scanAte')")
  $sc = EvalJ "(function(){ var s = document.querySelector('#scanResult .scansrc'); var h = document.querySelector('#scanResult .scanhead'); return { src: s ? s.textContent : '', head: h ? h.textContent : '' }; })()"
  Write-Host ("  Ate: on the Scan result: " + $seed + " " + $sc + " " + $b2)
  $b2v = $b2 | ConvertFrom-Json
  Check (($s0 -eq 1) -and ($sc -like '*"src":"cached"*Gate spread*')) "PRECONDITION: a barcode typed into the Scan form resolves from the device's own product cache"
  Check (($b2v.n -eq 5) -and ($b2v.lab -eq 'Ate:') -and ($b2v.on -eq 'all') -and ($b2v.small -eq 0) -and ($b2v.low -eq 0)) "R198/3: the Scan result has the same 'Ate:' -- five choices at ALL, 16px, 44 x 44"
  [void](Eval "(function(){ var bs = document.querySelectorAll('#scanAte .atebtn'); Array.prototype.forEach.call(bs, function (b) { if (b.textContent === '\u00bd') b.click(); }); return 1; })()")
  $s1 = EvalJ "(function(){ var on = document.querySelector('#scanAte .atebtn.ateon'); return { on: on ? on.textContent === '\u00bd' : false, head: !!document.querySelector('#scanResult .scanhead') }; })()"
  Check ($s1 -like '*"on":true*"head":true*') "tapping the half marks it and the product is still on screen"
  [void](Eval "document.querySelector('#scanResult button[onclick^=addScanToDay]').click()")
  Settle
  $a2 = EvalJ @'
(function () {
  var d = HT.state().days[HT.state().current] || { items: [] };
  var it = d.items[d.items.length - 1] || {};
  var pl = it.plateId ? HT.getPlate(it.plateId) : null;
  return { name: it.name, grams: it.grams, kcal: it.kcal, source: it.source, iron: (it.micros || {}).iron_mg,
           served: pl && pl.items[0] ? pl.items[0].grams : 0, conf: it.confidence };
})()
'@
  Write-Host ("  a half, at save, on Scan: " + $a2)
  $a2v = $a2 | ConvertFrom-Json
  Check (($a2v.source -eq 'scan') -and ($a2v.grams -eq 15) -and ($a2v.kcal -eq 75) -and ($a2v.served -eq 30)) "R198/3: a HALF of a scanned 30 g serving logs 15 g and 75 cal, with the 30 g served kept"
  Check ([Math]::Abs([double]$a2v.iron - 0.6) -lt 0.001) "and the LABEL micronutrients are halved with it -- 0.6 mg iron of the 1.2 on the serving"

  # ---- R199/2: editing and deleting a combo ---------------------------------------------
  $c0 = EvalJ @'
(function () {
  HT.state().settings.combos = HT.normalizeCombos([{ id: 'gc1', name: 'Gate bowl', parts: [
    { name: 'gate oats', grams: 50, kcal: 190 }, { name: 'gate milk', grams: 200, kcal: 100 } ] }]);
  HT.resave();
  var r = HT.logCombo('gc1', 1);
  window.__old = JSON.stringify(r.items);
  HT.closeSheet(); HT.openSheet();
  var e = document.querySelector('#sheetRoot .sredit');
  var rc = e ? e.getBoundingClientRect() : null;
  return { logged: r.ok === true && r.items.length === 2, edit: e ? e.textContent : '', px: e ? parseFloat(getComputedStyle(e).fontSize) : 0,
           h: rc ? rc.height : 0, w: rc ? rc.width : 0, rows: document.querySelectorAll('#sheetRoot .srcombo').length,
           head: (document.querySelector('#sheetRoot .srheadrow .srhead') || {}).textContent || '' };
})()
'@
  Write-Host ("  My combos: " + $c0)
  $c0v = $c0 | ConvertFrom-Json
  Check (($c0v.logged -eq $true) -and ($c0v.rows -eq 1)) "PRECONDITION: one combo, logged once"
  Check (($c0v.edit -eq 'Edit') -and ($c0v.head -eq 'My combos') -and ($c0v.px -ge 16) -and ($c0v.h -ge 44) -and ($c0v.w -gt 0)) "R199/2: beside 'My combos' there is a visible EDIT link, 16px, 44 px tall"
  [void](Eval "document.querySelector('#sheetRoot .sredit').click()")
  $c1 = EvalJ "(function(){ var e = document.querySelector('#sheetRoot .sredit'); var r = document.querySelector('#sheetRoot .srcombo'); return { link: e ? e.textContent : '', row: r ? r.innerText : '' }; })()"
  Check ($c1 -like '*"link":"Done"*tap to edit*') "tapped, it reads Done and the combo row says 'tap to edit'"
  [void](Eval "document.querySelector('#sheetRoot .srcombo').click()")
  Settle
  $c2 = EvalJ @'
(function () {
  var n = document.getElementById('cnName'), amts = document.querySelectorAll('#cnParts .cnamt');
  var save = document.querySelector('.cnsave'), del = document.querySelector('.cndel');
  var dr = del ? del.getBoundingClientRect() : null;
  return { name: n ? n.value : '', amts: Array.prototype.map.call(amts, function (a) { return a.value; }),
           save: save ? save.textContent : '', del: del ? del.textContent : '', delPx: del ? parseFloat(getComputedStyle(del).fontSize) : 0,
           delSeen: dr ? (dr.height > 0 && dr.width > 0) : false, logged: (HT.state().days[HT.state().current].items || []).length };
})()
'@
  Write-Host ("  opened for editing: " + $c2)
  $c2v = $c2 | ConvertFrom-Json
  Check (($c2v.name -eq 'Gate bowl') -and (@($c2v.amts).Count -eq 2) -and ($c2v.amts[0] -eq '50') -and ($c2v.amts[1] -eq '200')) "a tap on the row OPENS IT for editing: its name and both parts with their amounts"
  Check (($c2v.save -eq 'Save changes') -and ($c2v.del -eq 'Delete this combo') -and ($c2v.delSeen -eq $true) -and ($c2v.delPx -ge 16)) "with Save changes and a visible Delete, 16px"
  [void](Eval "(function(){ var a = document.querySelectorAll('#cnParts .cnamt')[0]; a.focus(); a.select(); return 1; })()")
  TypeText '80'
  [void](Eval "(function(){ var n = document.getElementById('cnName'); n.focus(); n.select(); return 1; })()")
  TypeText 'Gate bowl two'
  [void](Eval "(function(){ var rm = document.querySelectorAll('#cnParts .cnrm'); rm[1].click(); return 1; })()")
  Settle
  [void](Eval "document.querySelector('.cnsave').click()")
  Settle
  $c3 = EvalJ @'
(function () {
  var c = (HT.state().settings.combos || [])[0] || { parts: [] };
  var mine = HT.state().days[HT.state().current].items.filter(function (x) { return x.comboId === 'gc1'; });
  var same = JSON.stringify(mine) === window.__old;
  var row = document.querySelector('#sheetRoot .srcombo');
  var next = HT.logCombo('gc1', 1);
  return { n: (HT.state().settings.combos || []).length, id: c.id, name: c.name, parts: c.parts.length, grams: (c.parts[0] || {}).grams, kcal: (c.parts[0] || {}).kcal,
           same: same, row: row ? row.innerText : '', nextGrams: next.ok ? next.items[0].grams : -1, nextKcal: next.ok ? next.items[0].kcal : -1, nextN: next.ok ? next.items.length : -1,
           stillSame: JSON.stringify(HT.state().days[HT.state().current].items.filter(function (x) { return x.comboId === 'gc1'; }).slice(0, 2)) === window.__old };
})()
'@
  Write-Host ("  saved, then logged again: " + $c3)
  $c3v = $c3 | ConvertFrom-Json
  Check (($c3v.n -eq 1) -and ($c3v.id -eq 'gc1') -and ($c3v.name -eq 'Gate bowl two') -and ($c3v.parts -eq 1) -and ($c3v.grams -eq 80) -and ($c3v.kcal -eq 304)) "R199/2: SAVED -- renamed, the amount typed over (50 -> 80 g, 190 -> 304 cal), a part removed -- the same combo, not a second one"
  Check ($c3v.row -like '*Gate bowl two*') "and My combos SHOWS the new name"
  Check ($c3v.same -eq $true) "THE OLD LOG IS UNCHANGED -- byte for byte what was logged before the edit: 50 g of oats, 200 g of milk"
  Check (($c3v.nextGrams -eq 80) -and ($c3v.nextKcal -eq 304) -and ($c3v.nextN -eq 1) -and ($c3v.stillSame -eq $true)) "THE NEXT LOG USES THE NEW AMOUNT -- 80 g -- and the earlier one still stands beside it"

  [void](Eval "(function(){ HT.closeSheet(); HT.openSheet(); document.querySelector('#sheetRoot .sredit').click(); document.querySelector('#sheetRoot .srcombo').click(); return 1; })()")
  Settle
  $n0 = EvalJ "(function(){ return { items: HT.state().days[HT.state().current].items.filter(function (x) { return x.comboId === 'gc1'; }).length }; })()"
  [void](Eval "document.querySelector('.cndel').click()")
  Settle
  $c4 = EvalJ @'
(function () {
  var t = document.getElementById('toast');
  return { n: (HT.state().settings.combos || []).length, rows: document.querySelectorAll('#sheetRoot .srcombo').length,
           named: document.getElementById('sheetRoot').innerText.indexOf('Gate bowl two') >= 0,
           edit: !!document.querySelector('#sheetRoot .sredit'),
           items: HT.state().days[HT.state().current].items.filter(function (x) { return x.comboId === 'gc1'; }).length,
           same: JSON.stringify(HT.state().days[HT.state().current].items.filter(function (x) { return x.comboId === 'gc1'; }).slice(0, 2)) === window.__old,
           toast: t ? t.textContent : '', undo: !!(t && t.querySelector('.tundo') && t.classList.contains('show')) };
})()
'@
  Write-Host ("  deleted: " + $n0 + " " + $c4)
  $c4v = $c4 | ConvertFrom-Json
  Check (($c4v.n -eq 0) -and ($c4v.rows -eq 0) -and ($c4v.named -eq $false)) "R199/2: DELETED -- it is gone from My combos"
  Check ($c4v.edit -eq $false) "and with no combos left the heading and its Edit link are not drawn over nothing (D146)"
  Check (($c4v.items -eq 3) -and (($n0 | ConvertFrom-Json).items -eq 3) -and ($c4v.same -eq $true)) "THE HISTORY IS INTACT -- all three items logged with it are still on the day, the first two byte for byte"
  Check (($c4v.undo -eq $true) -and ($c4v.toast -like 'Deleted Gate bowl two*')) "the deletion is confirmed, with Undo"
  [void](Eval "document.querySelector('#toast .tundo').click()")
  Settle
  $c5 = EvalJ "(function(){ var c = (HT.state().settings.combos || [])[0] || {}; var r = document.querySelector('#sheetRoot .srcombo'); return { name: c.name || '', id: c.id || '', row: r ? r.innerText : '' }; })()"
  Write-Host ("  undone: " + $c5)
  Check ($c5 -like '*"name":"Gate bowl two"*"id":"gc1"*Gate bowl two*') "and Undo brings it back, on screen"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("FORMS GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "FORMS GATE: PASS -- the Manual form says 'estimated' and cuts nothing off, 'Ate:' works at save"
Write-Host "  on Manual and Scan with one Undo, and a combo can be edited and deleted by"
Write-Host "  plain taps without touching what was logged before."
Write-Host "GATE: PASS"
exit 0
