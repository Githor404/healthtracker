# R226 + R230 + R232 -- "NO ALCOHOL TODAY", ALCOHOL-FREE REWARDS, "STOPPED EATING". By real
# taps at 390 px, each counted, each on screen when it is clicked.
#
#   - No alcohol today: + Log, the button -- at most 3 taps; an explicit zero that
#     the export tells apart from a day with nothing logged
#   - R232: sparkling water after the mark asks nothing; white wine ASKS, on the day,
#     and changes nothing until answered; an unlabelled drink is asked about once
#   - gold circles on exactly the marked days and the counts beside the rings,
#     only with "Alcohol-free rewards" on (it ships off); off again keeps the marks
#   - Stopped eating: + Log, Stopped eating, Now -- at most 3 taps, the time asked;
#     the fasting arc is exactly stop -> next food, drawn in its own colour
#
# The one-door census (no new control on the day writes) is entry-gate's.
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8315
$Dbg = 9521
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-drinkfree-" + [System.Guid]::NewGuid().ToString('N'))
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


  $boot = Eval "typeof HT === 'object' && typeof HT.noDrinksTap === 'function' && typeof HT.eatStopSave === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or R226 is not on HT"; Cleanup; exit 2 }

  # Every tap is a real click on an element ON SCREEN when it is clicked, counted.
  # Bringing a row into view inside the sheet is a scroll, not a tap, and is
  # counted apart so it cannot hide.
  $tapJs = @'
  window.__taps = 0; window.__scrolls = 0;
  window.__tap = function (el, what) {
    if (!el) throw new Error('no ' + what);
    var r = el.getBoundingClientRect();
    if (!(r.top >= 0 && r.bottom <= window.innerHeight)) { el.scrollIntoView({ block: 'center' }); window.__scrolls++; r = el.getBoundingClientRect(); }
    if (!(r.width > 0 && r.height > 0 && r.top >= 0 && r.bottom <= window.innerHeight)) throw new Error(what + ' is not on screen');
    window.__taps++; el.click(); return r;
  };
  window.__fresh = function (seed) {
    var td0 = HT.todayKey();
    var at = new Date(td0 + 'T21:00:00').getTime();
    HT.setClock(function () { return at; });
    localStorage.clear(); HT.boot();
    if (seed) seed(HT.state().current);
    HT.resave(); HT.refresh(); window.scrollTo(0, 0);
    return HT.state().current;
  };
'@

  # ---- 1. "No alcohol today": + Log, then the button -- counted --------------------
  $nd = EvalA ($tapJs + @'
(function () {
  try {
    var td = window.__fresh();
    window.__tap(document.getElementById('fab'), '+ Log');
    var b = document.querySelector('#sheetRoot .ndbtn');
    var o = { label: b ? b.textContent : '' };
    window.__tap(b, 'No alcohol today');
    o.taps = window.__taps; o.scrolls = window.__scrolls;
    var m = HT.noDrinksMark(td);
    o.marked = !!m; o.value = m ? m.rec.value : null;
    o.row = ((document.querySelector('#sheetRoot .ndrow') || {}).textContent || '');
    var ex = JSON.parse(HT.exportJSON());
    o.exp = (ex.timeline[td] || []).filter(function (r) { return r.type === 'no_alcohol'; }).map(function (r) { return r.value; });
    o.expY = (ex.timeline[HT.shiftDate(td, -1)] || []).length;
    return o;
  } catch (e) { return { err: String(e) }; }
})()
'@)
  Write-Host ("  no drinks: " + $nd)
  $n = $nd | ConvertFrom-Json
  Check (($n.label -eq 'No alcohol today') -and ($n.taps -le 3) -and $n.marked -and ($n.value -eq 0)) "R226 GATE: 'No alcohol today' in $($n.taps) TAPS from the day -- + Log, the button -- stored as an explicit zero ($($n.scrolls) scroll(s) to bring it into view)"
  Check (($n.row -like 'No alcohol today*marked 21:00*') ) "R226: the drinks section then says the day is marked, with a way to remove it ($($n.row))"
  Check ((($n.exp -join ',') -eq '0') -and ($n.expY -eq 0)) "R226 GATE: in the export the marked day is {no_alcohol: 0}; an unmarked day has nothing -- distinct"

  # ---- 2. R232: alcohol only. Sparkling water asks nothing; white wine asks; a drink
  # nothing says anything about is asked about once, by a real tap, and remembered.
  $ask = EvalA ($tapJs + @'
(function () {
  try {
    var dr = function (name, time, ref) { return Object.assign({ name: name, meal: 'drink', time: time, kcal: 0, protein_g: 0, fat_g: 0, carb_g: 0, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'corpus', notes: '' }, ref ? { ref: ref } : {}); };
    var td = window.__fresh(function (d) {
      HT.addSignal({ type: 'no_alcohol', value: 0, unit: 'drinks', source: 'quick', date: d, time: '12:00' });
      HT.state().days[d] = { status: 'partial', water_l: 0, items: [dr('Gate sparkling water', '13:00', { ns: 'fdc', id: 'g1', v: { '221': 0 } })] };
    });
    var o = { water: !!document.querySelector('#dayView .ndask') };
    // a drink its source says nothing about: asked once
    HT.state().days[td].items.push(dr('Gate kombucha', '14:00')); HT.resave(); HT.refresh();
    var q1 = document.querySelector('#dayView .ndask');
    o.unknownQ = q1 ? (q1.querySelector('.ndq') || {}).textContent : '';
    var no = Array.prototype.filter.call(q1 ? q1.querySelectorAll('button') : [], function (b) { return b.textContent === 'No'; })[0];
    window.__tap(no, 'No');
    o.afterNo = !!document.querySelector('#dayView .ndask');
    // white wine: asks
    HT.state().days[td].items.push(dr('Gate white wine', '19:00', { ns: 'fdc', id: 'g2', v: { '221': 14.2 } })); HT.resave(); HT.refresh();
    var q = document.querySelector('#dayView .ndask');
    o.q = q ? (q.querySelector('.ndq') || {}).textContent : ''; o.still = !!HT.noDrinksMark(td);
    var rm = Array.prototype.filter.call(q ? q.querySelectorAll('button') : [], function (b) { return b.textContent === 'Remove mark'; })[0];
    window.__tap(rm, 'Remove mark');
    o.gone = !HT.noDrinksMark(td) && !document.querySelector('#dayView .ndask');
    return o;
  } catch (e) { return { err: String(e) }; }
})()
'@)
  Write-Host ("  the questions: " + $ask)
  $a = $ask | ConvertFrom-Json
  Check (-not $a.water) "R232 GATE: sparkling water (its source: 0 g alcohol) after the mark -> NO question"
  Check (($a.unknownQ -eq ('Does this drink contain alcohol? ' + [char]0x2014 + ' Gate kombucha')) -and (-not $a.afterNo)) "R232 GATE: a drink its source says nothing about is asked about ONCE -- 'Does this drink contain alcohol?' -- and 'No' is remembered: the question goes"
  Check (($a.q -eq ('You marked no alcohol today ' + [char]0x2014 + ' remove that mark?')) -and $a.still) "R232 GATE: white wine (alcohol > 0 from its source) after the mark ASKS on the day -- 'You marked no alcohol today -- remove that mark?' -- and nothing changed silently"
  Check $a.gone "R226: 'Remove mark' removes it, and the question goes"

  # ---- 3. gold circles and counts: only marked days, only with the toggle on --------
  $gold = EvalA ($tapJs + @'
(function () {
  try {
    var td = window.__fresh(function (d) {
      [0, 1, 3].forEach(function (k) { HT.addSignal({ type: 'no_alcohol', value: 0, unit: 'drinks', source: 'quick', date: HT.shiftDate(d, -k), time: '20:00' }); });
    });
    HT.setRhythmRange('week');
    var read = function () {
      var g = document.getElementById('rhythmGrid');
      var minis = Array.prototype.slice.call(g.querySelectorAll('.rmini'));
      return { gold: minis.filter(function (b) { return !!b.querySelector('.rmgold'); }).map(function (b) { return b.title.slice(0, 10); }).sort().join(','),
               count: ((g.querySelector('.afcount') || {}).textContent || '') };
    };
    var o = { off: read() };
    // the toggle, by a real tap in Settings
    var cb = document.getElementById('afRewards');
    HT.openSettings && HT.openSettings();
    cb.closest('details') && (cb.closest('details').open = true);
    window.__tap(cb, 'Alcohol-free rewards');
    o.setOn = HT.afRewardsOn();
    HT.closeSettings && HT.closeSettings();
    o.on = read();
    var gp = document.querySelector('#rhythmGrid .rmgold');
    o.goldColour = gp ? getComputedStyle(gp).fill : '';
    HT.setRhythmRange('month'); o.month = read(); HT.setRhythmRange('week');
    o.want = [0, 1, 3].map(function (k) { return HT.shiftDate(td, -k); }).sort().join(',');
    HT.openSettings && HT.openSettings();
    window.__tap(document.getElementById('afRewards'), 'Alcohol-free rewards');
    HT.closeSettings && HT.closeSettings();
    o.offAgain = read();
    o.marksKept = [0, 1, 3].every(function (k) { return HT.afDay(HT.shiftDate(td, -k)); });
    o.dom = new Date(td + 'T00:00:00').getDate();
    o.dim = new Date(new Date(td + 'T00:00:00').getFullYear(), new Date(td + 'T00:00:00').getMonth() + 1, 0).getDate();
    return o;
  } catch (e) { return { err: String(e) }; }
})()
'@)
  Write-Host ("  rewards: " + $gold)
  $g = $gold | ConvertFrom-Json
  Check (($g.off.gold -eq '') -and ($g.off.count -eq '')) "R230 GATE: rewards OFF by default -- no gold circle and no count, though three days are marked"
  Check ($g.setOn -and ($g.on.gold -eq $g.want) -and ($g.goldColour -ne '')) "R226 GATE: switched ON, a GOLD circle on EXACTLY the marked days ($($g.on.gold)) and on no other"
  Check ($g.on.count -like ('3 of 7 days alcohol-free*current run 2 days')) "R226/R230 GATE: beside the rings, '3 of 7 days alcohol-free' and the current run -- today and yesterday, 2 ($($g.on.count))"
  $mWant = if ($g.dom -lt $g.dim) { "* of $($g.dom) days alcohol-free this month so far*" } else { "* of $($g.dim) days alcohol-free*" }
  Check ($g.month.count -like $mWant) "R230 GATE: the month counts out of the days so far ($($g.month.count))"
  Check (($g.offAgain.gold -eq '') -and ($g.offAgain.count -eq '') -and $g.marksKept) "R226 GATE: switched OFF again, the gold and the counts go and every mark is KEPT"

  # the checkbox says the setting's state whenever Settings opens -- a restore can change it
  $cbs = Eval "(function(){ HT.state().settings.alcoholFreeRewards = true; HT.resave(); HT.openSettings(); var a = document.getElementById('afRewards').checked; HT.closeSettings(); delete HT.state().settings.alcoholFreeRewards; HT.resave(); HT.openSettings(); var b = document.getElementById('afRewards').checked; HT.closeSettings(); return a + '|' + b; })()"
  Check ($cbs -eq 'true|false') "R226: the Settings checkbox shows the stored setting each time Settings opens ($cbs)"

  # ---- 4. "Stopped eating": + Log, Stopped eating, Now -- counted; the arc drawn -----
  $st = EvalA ($tapJs + @'
(function () {
  try {
    var td = window.__fresh(function (d) {
      var f = function (n, t) { return { name: n, meal: 'dinner', time: t, kcal: 400, protein_g: 20, fat_g: 10, carb_g: 40, fiber_g: 3, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }; };
      HT.state().days[d] = { status: 'partial', water_l: 0, items: [f('Gate lunch', '12:00'), f('Gate dinner', '18:30')] };
    });
    var before = HT.eatStopsAbs().length;
    window.__tap(document.getElementById('fab'), '+ Log');
    var b = document.querySelector('#sheetRoot .srstop');
    var o = { label: b ? b.textContent : '' };
    window.__tap(b, 'Stopped eating');
    o.asked = !!document.querySelector('#sheetRoot .esPick') && HT.eatStopsAbs().length === before;
    var now = document.querySelector('#sheetRoot .esPick .lpnow');
    o.nowDefault = !!now && now.classList.contains('primary');
    window.__tap(now, 'Now');
    o.taps = window.__taps;
    var rec = (HT.state().timeline[td] || []).filter(function (r) { return r.type === 'eat_stop'; });
    o.n = rec.length; o.time = rec.length ? rec[0].time : '';
    // the next food, tomorrow 09:30: the drawn arc runs stop -> food exactly
    var tm = HT.shiftDate(td, 1);
    HT.state().days[tm] = { status: 'partial', water_l: 0, items: [{ name: 'Gate eggs', meal: 'breakfast', time: '09:30', kcal: 200, protein_g: 12, fat_g: 10, carb_g: 2, fiber_g: 0, soluble_fiber_g: 0, confidence: 'eyeballed', source: 'manual', notes: '' }] };
    HT.resave();
    var sp = HT.eatStopSpans(null)[0];
    o.label2 = sp ? sp.label : ''; o.mins = sp ? sp.a1 - sp.a0 : 0;
    var arcs = [td, tm].map(function (d) { return HT.rhythmModel(d, { live: false }).arcs.filter(function (a) { return a.kind === 'stopfast'; })[0]; });
    o.arcSum = arcs.reduce(function (s, a) { return s + (a ? a.endMin - a.startMin : 0); }, 0);
    // drawn on the page: the day after, with its ring
    HT.goToDay(tm); HT.refresh();
    var path = document.querySelector('#dayView path.ra-stopfast');
    o.drawn = !!path; o.stroke = path ? getComputedStyle(path).stroke : '';
    // the meals and sleep hues, resolved the way the browser resolves them
    var hue = function (v) { var d = document.createElement('div'); d.style.color = 'var(' + v + ')'; document.body.appendChild(d); var c = getComputedStyle(d).color; d.remove(); return c; };
    o.eatStroke = hue('--lane-eat'); o.sleepStroke = hue('--lane-sleep');
    // the words: ONE tap on "Ring key" beside the ring (the ring itself opens + Log, R223)
    window.__taps = 0;
    window.__tap(document.querySelector('#dayView .ringkeybtn'), 'Ring key');
    o.keyTaps = window.__taps;
    o.legend = Array.prototype.map.call(document.querySelectorAll('#dayView .rrrow'), function (r) { return r.textContent; }).filter(function (t) { return /Fasted/.test(t); })[0] || '';
    return o;
  } catch (e) { return { err: String(e) }; }
})()
'@)
  Write-Host ("  stopped eating: " + $st)
  $s = $st | ConvertFrom-Json
  Check (($s.label -eq 'Stopped eating') -and $s.asked -and $s.nowDefault -and ($s.taps -le 3) -and ($s.n -eq 1) -and ($s.time -eq '21:00')) "R226 GATE: 'Stopped eating' in $($s.taps) TAPS from the day -- + Log, Stopped eating, Now -- the time ASKED first, Now highlighted, one record at 21:00"
  Check (($s.mins -eq 750) -and ($s.arcSum -eq 750) -and ($s.label2 -eq ('Fasted 12 h 30 m (21:00 ' + [char]0x2192 + ' 09:30)'))) "R226 GATE: the fasting arc is exactly stop -> next food: 21:00 to 09:30 = 750 min, over two days ($($s.label2))"
  Check ($s.drawn -and ($s.stroke -ne '') -and ($s.stroke -ne $s.eatStroke) -and ($s.stroke -ne $s.sleepStroke)) "R226 GATE: it is DRAWN on the ring in its own colour -- not the meals colour, not sleep's ($($s.stroke) vs $($s.eatStroke), $($s.sleepStroke))"
  Check (($s.keyTaps -eq 1) -and ($s.legend -eq ('Fasted 12 h 30 m (21:00 ' + [char]0x2192 + ' 09:30)'))) "R226 GATE: one tap on 'Ring key' says it in words: 'Fasted 12 h 30 m (21:00 -> 09:30)'"
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -eq 0) {
  Write-Host "DRINKFREE GATE: PASS -- no alcohol today and stopped eating each within 3 taps; the zero distinct from missing in the export; sparkling water asks nothing, white wine asks, an unlabelled drink is asked once; gold and counts only for marked days and only with the toggle on, marks kept when off; the fasting arc is stop to next food in its own colour"
  Write-Host "GATE: PASS"
  exit 0
}
Write-Host ("DRINKFREE GATE: FAIL -- " + $fails.Count + " check(s)")
Write-Host "GATE: FAIL"
exit 1
