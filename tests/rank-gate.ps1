# R198/1 + R199/1 -- THE ORDER OF SEARCH RESULTS, on both food databases.
#
# REPORTED: "coffee" led with "Coffee cake, cheese"; "sardines" did not find
# sardine; "milk" put "Crackers, milk" among the milks.
#
# TWO KINDS OF CHECK, kept apart because they are not the same claim:
#
#   RULED   -- a property the ruling states, true of whatever the database holds:
#              plural and singular give the same list; the rows headed by the
#              word come before a compound that starts with it or a food
#              flavoured with it.
#   PINNED  -- the top three, by name, for a small fixed list of queries, AS THEY
#              STAND TODAY. A pin is not a claim that the order is right. It is
#              there so that the order cannot change without somebody seeing it
#              change and choosing it. The databases are hash-pinned
#              (check-slots), so a pin moves only when the ranking does.
#
# R200 added three general rules, each RULED here as a property:
#   (b) generic before branded -- no row with a trade name ahead of one without
#   (c) the earlier part of the name -- asserted in the harness on a fixture
#   (d) two spellings, one list -- "yogurt" and "yogourt" give the same rows
#
# WHAT IS NOT CLAIMED, AND IS MEASURED HERE SO IT STAYS SAID:
#   - "coffee" on the Canadian database leads with "Coffee, instant with chicory,
#     powder"; "Coffee, brewed" is SECOND. Both names have three parts, so
#     "plainest name first" ties them. It is first once it has been logged --
#     asserted below.
#   - "sardines" leads with "Fish oil, sardine" on both: neither database has a
#     row headed Sardine, and both rows answer in their second part.
#   - R200(a) GENERALISED to every row was measured and NOT shipped: it put
#     "Candies, milk chocolate coated coffee beans" first for "coffee" on the US
#     database. It stays where it was, between rows that are both the head name.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8297
$Dbg = 9503
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-rank-" + [System.Guid]::NewGuid().ToString('N'))
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

  $boot = Eval "typeof HT === 'object' && typeof HT.typeaheadMineFirst === 'function'"
  if (-not $boot) { Write-Host "ERROR: the app did not boot, or typeaheadMineFirst is not on HT"; Cleanup; exit 2 }
  Invoke-CDP 'Network.enable' $null | Out-Null

  $ask = @'
(function (want) {
  return HT.corpusEnsure().then(function () {
    var top = function (q, n) { return HT.matchTypeahead(q, n).map(function (r) { return r.name; }); };
    var off = [];
    Object.keys(want).forEach(function (q) {
      var got = top(q, 3);
      if (got.join(' | ') !== want[q].join(' | ')) off.push(q + ' => ' + got.join(' | '));
    });
    var headed = function (q, word) {            // every row headed by the word comes before every row that is not
      var rows = top(q, 40), seenOther = false, bad = 0;
      rows.forEach(function (n) {
        var first = n.toLowerCase().split(',')[0].trim();          // 'Eggs, scrambled' is headed egg: the fold is the search's own
        var is = first === word || first === word + 's';
        if (!is) seenOther = true; else if (seenOther) bad++;
      });
      return { bad: bad, first: rows.length ? rows[0] : '', n: rows.length };
    };
    return { ns: HT.corpusState().ns, pins: Object.keys(want).length, off: off,
             plural: top('sardines', 8).join('|') === top('sardine', 8).join('|') && top('sardines', 8).length > 0,
             plural2: top('bananas', 8).join('|') === top('banana', 8).join('|') && top('eggs', 8).join('|') === top('egg', 8).join('|'),
             sardine: top('sardines', 3).filter(function (n) { return /sardine/i.test(n); }).length,
             milk: headed('milk', 'milk'), egg: headed('egg', 'egg'), butter: headed('butter', 'butter'),
             coffee: top('coffee', 8),
             // R200(b): among rows holding the word whole, once a branded row is seen no generic row follows
             brand: ['coffee', 'yogurt', 'milk'].map(function (q) {
               var seen = false, bad = 0, nb = 0;
               top(q, 40).forEach(function (n) {
                 if (!new RegExp('\\b' + q + 's?\\b', 'i').test(n) && !/yogourt/i.test(n)) return;
                 if (HT.nameIsBranded(n)) { seen = true; nb++; } else if (seen) bad++;
               });
               return { q: q, bad: bad, branded: nb };
             }),
             // R200(d): either spelling, the same list
             spell: [['yogurt', 'yogourt'], ['flavor', 'flavour'], ['fiber', 'fibre'], ['whiskey', 'whisky']].map(function (pr) {
               var a = top(pr[0], 8), b = top(pr[1], 8);
               return { pair: pr.join('/'), same: a.join('|') === b.join('|'), n: a.length };
             }),
             half: top('yogou', 3).join('|') === top('yogurt', 3).join('|') };
  });
})
'@

  # ---- the US database (the default) ---------------------------------------------
  $us = EvalA ($ask + @'
({ 'milk': ['Milk, buttermilk, dried', 'Milk, sheep, fluid', 'Milk, low sodium, fluid'],
   'egg': ['Egg, whole, dried', 'Egg, white, dried', 'Egg, yolk, dried'],
   'sardines': ['Fish oil, sardine', 'Fish, sardine, Atlantic, canned in oil, drained solids with bone', 'Fish, sardine, Pacific, canned in tomato sauce, drained solids with bone'],
   'banana': ['Bananas, raw', 'Bananas, dehydrated, or banana powder', 'Pepper, banana, raw'],
   'butter': ['Butter, without salt', 'Butter, salted', 'Butter, Clarified butter (ghee)'],
   'yogurt': ['Yogurt, plain, low fat', 'Yogurt, vanilla, low fat.', 'Yogurt, plain, whole milk'],
   'coffee': ['Beverages, coffee, instant, with chicory', 'Beverages, coffee, instant, chicory', 'Beverages, coffee, instant, regular, prepared with water'] })
'@)
  Write-Host ("  US database: " + $us)
  $uv = $us | ConvertFrom-Json
  Check ($uv.ns -eq 'fdc') "PRECONDITION: this is the US database"
  Check (($uv.plural -eq $true) -and ($uv.plural2 -eq $true) -and ($uv.sardine -eq 3)) "RULED (US): PLURAL AND SINGULAR give the same list -- sardines/sardine, bananas/banana, eggs/egg -- and 'sardines' finds sardine"
  Check (($uv.milk.bad -eq 0) -and ($uv.milk.n -gt 5) -and ($uv.milk.first -like 'Milk,*')) "RULED (US): 'milk' -- every row HEADED Milk comes before every row that only contains it"
  Check (($uv.egg.bad -eq 0) -and ($uv.egg.first -like 'Egg,*') -and ($uv.butter.bad -eq 0) -and ($uv.butter.first -like 'Butter,*')) "RULED (US): the same for 'egg' (not Eggplant, not Egg substitute) and 'butter'"
  Check (($uv.pins -eq 7) -and (@($uv.off).Count -eq 0)) ("PINNED (US): the top three for the seven fixed queries are as recorded" + $(if (@($uv.off).Count) { ' -- MOVED: ' + (@($uv.off) -join ' ;; ') } else { '' }))

  $ub = @($uv.brand)
  Check ((@($ub | Where-Object { $_.bad -ne 0 }).Count -eq 0) -and ($ub.Count -eq 3) -and (@($ub | Where-Object { ($_.q -eq 'coffee') -and ($_.branded -gt 0) }).Count -eq 1)) "R200(b) (US): GENERIC BEFORE BRANDED -- for coffee, yogurt and milk no generic row comes after a branded one, and the coffee list DOES hold branded rows, so the check is not vacuous. 'SILK Coffee, soymilk' led 'coffee' before this"
  $usp = @($uv.spell)
  Check ((@($usp | Where-Object { $_.same -ne $true }).Count -eq 0) -and ($usp.Count -eq 4) -and ($usp[0].n -gt 0) -and ($uv.half -eq $true)) "R200(d) (US): EITHER SPELLING, THE SAME LIST -- yogurt/yogourt, flavor/flavour, fiber/fibre, whiskey/whisky -- and half-typed 'yogou' already shows it"

  # ---- the Canadian database ------------------------------------------------------
  $ua = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua; acceptLanguage = 'en-CA' } | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot
  # R239: BOOT IS A SIGNAL, NOT ONLY A SLEEP. Under suite load 3 s was sometimes too
  # short and the gate reported 'the app did not boot' about the machine. Up to 30 s
  # more for HT and a loaded page; the gate's own boot check still decides.
  for ($bw = 0; $bw -lt 60; $bw++) { $hb = $null; try { $hb = (Invoke-CDP 'Runtime.evaluate' @{ expression = "typeof HT === 'object' && document.readyState === 'complete'"; returnByValue = $true }).result.result.value } catch { }; if ($hb -eq $true) { break }; Start-Sleep -Milliseconds 500 }
  $ca = EvalA ($ask + @'
({ 'coffee': ['Coffee, instant with chicory, powder', 'Coffee, brewed, prepared with tap water', 'Coffee, instant, regular, powder'],
   'milk': ['Milk, dry whole', 'Milk, fluid, skim', 'Milk, condensed, sweetened, canned'],
   'egg': ['Egg, chicken, dried, whole', 'Egg, chicken, white, dried', 'Egg, chicken, yolk, dried'],
   'sardines': ['Fish oil, sardine', 'Fish, sardine, Atlantic, canned in oil, drained solids with bone', 'Fish, sardine, pacific, canned in tomato sauce, drained with bones'],
   'banana': ['Banana, raw', 'Banana, dehydrated or banana powder', 'Orange-strawberry-banana juice'],
   'tea': ['Tea, brewed', 'Tea, hibiscus', 'Tea, brewed with distilled water'],
   'yogurt': ['Yogourt, plain (2-3.9% M.F.)', 'Yogourt, tofu', 'Yogourt, fruit flavoured (2-3.9% M.F.)'] })
'@)
  Write-Host ("  Canadian database: " + $ca)
  $cv = $ca | ConvertFrom-Json
  Check ($cv.ns -eq 'cnf') "PRECONDITION: this is the Canadian database"
  Check (($cv.plural -eq $true) -and ($cv.plural2 -eq $true) -and ($cv.sardine -eq 3)) "RULED (CA): PLURAL AND SINGULAR give the same list, and 'sardines' finds sardine"
  Check (($cv.milk.bad -eq 0) -and ($cv.milk.first -like 'Milk,*') -and ($cv.egg.bad -eq 0) -and ($cv.egg.first -like 'Egg,*')) "RULED (CA): 'milk' and 'egg' -- every row headed by the word before every row that only contains it"
  $csp = @($cv.spell)
  Check ((@($csp | Where-Object { $_.same -ne $true }).Count -eq 0) -and ($csp.Count -eq 4) -and (@($csp | Where-Object { $_.n -eq 0 }).Count -eq 0) -and ($cv.half -eq $true)) "R200(d) (CA): EITHER SPELLING, THE SAME LIST, and none of the four is empty -- 'yogurt' found NOTHING here before, with 78 rows spelled 'yogourt'"
  Check (@(@($cv.brand) | Where-Object { $_.bad -ne 0 }).Count -eq 0) "R200(b) (CA): no generic row after a branded one"
  $cof = @($cv.coffee)
  $cake = -1; $lastCoffee = -1
  for ($i = 0; $i -lt $cof.Count; $i++) {
    if ($cof[$i] -like 'Coffee,*') { $lastCoffee = $i }
    if (($cake -lt 0) -and ($cof[$i] -like 'Coffee cake*')) { $cake = $i } }
  Check (($cof.Count -gt 3) -and ($cof[0] -like 'Coffee,*') -and (($cake -lt 0) -or ($cake -gt $lastCoffee))) "R199 (CA): 'coffee' -- every row that IS coffee comes before any 'Coffee cake'. The reported case: it led with the cake"
  Check (($cof[0] -like 'Coffee, brewed*') -or ($cof[1] -like 'Coffee, brewed*')) "R199 (CA): 'Coffee, brewed' is in the first two WITH NO HISTORY. It is not first: said, not hidden"
  Check (($cv.pins -eq 7) -and (@($cv.off).Count -eq 0)) ("PINNED (CA): the top three for the seven fixed queries are as recorded" + $(if (@($cv.off).Count) { ' -- MOVED: ' + (@($cv.off) -join ' ;; ') } else { '' }))

  # ---- typed for real, then logged, then typed again --------------------------------
  $open = "(function(){ HT.closeSheet(); HT.openSheet(); var bs = document.querySelectorAll('#sheetRoot .srbtn'); for (var i = 0; i < bs.length; i++) if (bs[i].textContent === 'Search') bs[i].click(); var f = document.getElementById('fqQuery'); f.value = ''; f.focus(); return 1; })()"
  $read = @'
(function () {
  var rows = document.querySelectorAll('#fqRows .fqrow');
  var st = HT.foodSearch();
  var names = (st.rows || []).slice(0, 3).map(function (r) { return r.name; });
  var shown = names.every(function (n, i) { return rows[i] && rows[i].textContent.indexOf(n) >= 0; });
  var tag = rows[0] ? rows[0].querySelector('.fqmine') : null;
  var brewed = -1;
  (st.rows || []).forEach(function (r, i) { if (brewed < 0 && r.name.indexOf('Coffee, brewed') === 0) brewed = i; });
  return { n: rows.length, names: names, shown: shown, brewed: brewed,
           tag: tag ? tag.textContent : '', tagPx: tag ? parseFloat(getComputedStyle(tag).fontSize) : 0,
           tagSeen: tag ? (tag.getBoundingClientRect().height > 0 && tag.getBoundingClientRect().width > 0) : false,
           tags: document.querySelectorAll('#fqRows .fqmine').length,
           wide: rows[0] ? (rows[0].scrollWidth - rows[0].clientWidth) : 0 };
})()
'@
  [void](Eval $open)
  TypeText 'coffee'
  Settle
  $t1 = EvalJ $read
  Write-Host ("  typed 'coffee', nothing logged: " + $t1)
  $t1v = $t1 | ConvertFrom-Json
  Check (($t1v.shown -eq $true) -and ($t1v.names[0] -eq 'Coffee, instant with chicory, powder') -and ($t1v.names[1] -like 'Coffee, brewed*')) "TYPED into the Search pane, the rows ON SCREEN are the pinned ones, in that order"
  Check ($t1v.tags -eq 0) "and with nothing logged, no row claims to have been logged before"
  $pk = EvalJ ("(function(){ var rows = document.querySelectorAll('#fqRows .fqrow'); rows[" + [int]$t1v.brewed + "].click(); var g = document.getElementById('fqGrams'); if (g) g.focus(); return { step: !!g }; })()")
  TypeText '250'
  Settle
  $lg = EvalJ @'
(function () {
  var b = document.querySelector('#fqLog .fqlog');
  if (b && !b.disabled) b.click();
  var day = HT.state().days[HT.state().current] || { items: [] };
  var it = day.items[day.items.length - 1] || {};
  return { logged: it.source === 'corpus' && it.grams === 250 && !!it.ref, name: (it.ref || {}).name || '' };
})()
'@
  Write-Host ("  the brewed row picked and logged: " + $pk + " " + $lg)
  Check ($lg -like '*"logged":true*Coffee, brewed*') "the brewed row is picked and LOGGED at 250 g, by real taps"
  [void](Eval $open)
  TypeText 'coffee'
  Settle
  $t2 = EvalJ $read
  Write-Host ("  typed 'coffee' again: " + $t2)
  $t2v = $t2 | ConvertFrom-Json
  Check (($t2v.names[0] -like 'Coffee, brewed*') -and ($t2v.shown -eq $true)) "R199: TYPED AGAIN, 'Coffee, brewed' IS FIRST -- the row this user logged leads"
  Check (($t2v.tag -eq 'you logged this before') -and ($t2v.tagSeen -eq $true) -and ($t2v.tagPx -ge 16) -and ($t2v.tags -eq 1)) "and it SAYS WHY it is first, on the row, at 16px -- and only that row says it"
  Check ($t2v.wide -le 0) "the row does not run off its own edge"
  Check (($t2v.names[1] -eq 'Coffee, instant with chicory, powder')) "everything beneath it keeps the order it had"

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup

Write-Host ""
if ($fails.Count -gt 0) {
  Write-Host ("RANK GATE: FAIL -- " + $fails.Count + " check(s)")
  foreach ($f in $fails) { Write-Host ("  - " + $f) }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "RANK GATE: PASS -- plural and singular and both spellings find each other, a food headed by"
Write-Host "  the word comes before a compound or a flavouring, generic before branded,"
Write-Host "  the fixed queries' top three are as recorded on both databases, and a"
Write-Host "  food logged before leads and says so."
Write-Host "GATE: PASS"
exit 0
