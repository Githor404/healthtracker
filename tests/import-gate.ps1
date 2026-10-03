# H20 -- THE GLUCOSE IMPORT ROUTE, driven through a REAL <input type=file>.
#
# WHY THIS GATE EXISTS AT ALL: D146 shipped `glucoseIngest()` and no way to reach
# it. Every assertion in chart-gate called that function from JavaScript, so a
# gate that drives the API could not notice the API was unreachable. *A test that
# calls the function has not tested the route.* So nothing here calls
# glucoseIngest, glucoseImportFile or any ingest function directly: files are
# handed to a real file input with DOM.setFileInputFiles, the way a picker hands
# them over, and the only thing clicked is what a thumb can click.
#
# AND THE FIRST IMPORT IS TESTED FROM THE STATE IT ACTUALLY HAPPENS IN: empty
# storage, no glucose, no row. D146 made glucoseRowHTML return the empty string
# for a day with no readings -- deliberately -- so the row cannot host the FIRST
# import. Seeding glucose to make the row appear and then testing the row's button
# would exercise the easy half and reproduce the exact hole H20 was ruled to fix.
# Four checks in two slices have passed because their fixture lacked the state the
# defect lived in; this one names the state first.
#
# RULED (H20):
#   A  ONE control, sniffing the full Apple Health export (streamed) and a
#      Shortcut-produced glucose file. Unrecognised input REFUSED BY NAME, never
#      guessed. Merge by timestamp; re-imports never duplicate.
#   C  the control lives on the glucose row, with the day's EMPTY GLUCOSE STATE as
#      the home for the first import and Settings as the fallback.
#   D  progress shows BYTES and READINGS, because 99.99% of an export is not
#      glucose and a readings-only counter would sit at zero looking broken.
#   E  the file is read and discarded; NOTHING LEAVES THE PHONE -- asserted on the
#      request log, not on intent.
#
# FIXTURES ARE GENERATED AT RUNTIME into TEMP and deleted after. The Apple-export
# fixture is SYNTHETIC XML in the real shape -- the attribute set and the one-line
# <Record> layout measured from a real export -- and no real reading, and no 491MB
# file, ever enters this repo.
#
# MEASURED, and the reason streaming is admissible at all: a 491MB export costs
# ~14MB of heap and 2.0s on this machine, because each chunk is scanned and
# dropped with only the partial last line kept. Bounded, not scaling. What this
# gate can assert is that the SHAPE is bounded; it cannot speak for iOS, and says
# so.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8241
$Dbg = 9447
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-import-" + [System.Guid]::NewGuid().ToString('N'))
$fixdir = Join-Path $env:TEMP ("ht-importfix-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None
$fails = @()
function Chk([bool]$cond, [string]$msg) { if (-not $cond) { $script:fails += $msg } }

function Find-Browser {
  foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 262144
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count); if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$m, [hashtable]$p) {
  $script:cid++; $pl = @{ id = $script:cid; method = $m }; if ($p) { $pl.params = $p }
  $b = [Text.Encoding]::UTF8.GetBytes(($pl | ConvertTo-Json -Depth 20 -Compress))
  [void]$ws.SendAsync([ArraySegment[byte]]::new($b), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $g = 0
  while ($true) {
    if (++$g -gt 6000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value
}
# A REAL PICKER SELECTION. Not a synthesised change event, not a direct call: the
# file is attached to the input exactly as the OS dialog attaches it.
function Pick-File([string]$selector, [string]$path) {
  $doc = Invoke-CDP 'DOM.getDocument' @{ depth = 1 }
  $nid = (Invoke-CDP 'DOM.querySelector' @{ nodeId = $doc.result.root.nodeId; selector = $selector }).result.nodeId
  if (-not $nid) { throw "no node for $selector" }
  Invoke-CDP 'DOM.setFileInputFiles' @{ files = @($path); nodeId = $nid } | Out-Null
}
# WAIT ON THIS IMPORT, NOT ON A CLOCK.
#
# `done` alone cannot distinguish this import's completion from the previous
# one's, so a fixed sleep -- or a bare `done` poll -- can read a STALE message
# and count it as a pass. That matters most exactly where the evidence is an
# absence: the re-import assertion expects the count NOT to change, so if the
# probe runs before the import does, the assertion passes while testing nothing.
# `seq` increments once per attempt, which makes the wait a real signal.
# ConvertFrom-Json emits a JSON array as ONE object in PowerShell 5.1, so
# @(...) around it yields a list of length 1 whose single element is the array.
# Every downstream read then lies quietly: -join prints System.Object[], a
# Where-Object on a property matches nothing, and -notcontains never matches.
# foreach enumerates it correctly; the leading comma stops the return unrolling
# a single-element result back to a scalar.
function AsList([string]$jsonText) {
  $o = $jsonText | ConvertFrom-Json
  $out = @()
  foreach ($x in $o) { $out += $x }
  return ,$out
}
function Import-Seq {
  return [int](Eval "(function(){var p=HT.glucoseImportProgress();return p?p.seq:0;})()")
}
function Wait-Import([int]$after, [int]$maxMs = 40000) {
  $t0 = [Environment]::TickCount
  while (([Environment]::TickCount - $t0) -lt $maxMs) {
    $p = (Eval "JSON.stringify(HT.glucoseImportProgress())") | ConvertFrom-Json
    if ($p -and ([int]$p.seq) -gt $after -and $p.done) { return $p }
    Start-Sleep -Milliseconds 120
  }
  return $null
}
function Tap([int]$x, [int]$y) {
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $x; y = $y }) } | Out-Null
  Start-Sleep -Milliseconds 40
  Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
  Start-Sleep -Milliseconds 350
}

# ---------------- the fixtures, written at runtime ------------------------
New-Item -ItemType Directory -Path $fixdir -Force | Out-Null
$TYPE = 'HKQuantityTypeIdentifierBloodGlucose'
function New-AppleExport([string]$path, [int]$glucose, [int]$noise) {
  # ONE LINE PER RECORD, the layout measured in the real file, with the same
  # attribute set. Values are synthetic. The noise records are other types, so
  # the sniff and the scan both have to ignore things that are not glucose --
  # measured: 451 glucose records in 491MB is about 0.01% of the file.
  $sw = New-Object IO.StreamWriter($path, $false, [Text.Encoding]::UTF8)
  $sw.Write("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n")
  $sw.Write("<!DOCTYPE HealthData [ <!ELEMENT HealthData (Record*)> ]>`n")
  $sw.Write("<HealthData locale=`"en_CA`">`n")
  $sw.Write(" <ExportDate value=`"2026-09-26 10:35:51 -0400`"/>`n")
  $base = [DateTime]::Parse('2026-09-26T07:30:00')
  for ($i = 0; $i -lt $noise; $i++) {
    $sw.Write(" <Record type=`"HKQuantityTypeIdentifierStepCount`" sourceName=`"Phone`" unit=`"count`" creationDate=`"2026-09-26 08:00:00 -0400`" startDate=`"2026-09-26 08:00:00 -0400`" endDate=`"2026-09-26 08:01:00 -0400`" value=`"$($i + 1)`"/>`n")
  }
  for ($i = 0; $i -lt $glucose; $i++) {
    $t = $base.AddSeconds(-300 * ($glucose - 1 - $i)).ToString('yyyy-MM-dd HH:mm:ss') + ' -0400'
    $v = [Math]::Round(5.6 + 1.9 * [Math]::Sin($i / 34.0), 1)
    $sw.Write(" <Record type=`"$TYPE`" sourceName=`"Dexcom G7`" sourceVersion=`"13425`" unit=`"mmol&lt;180.1558800000541&gt;/L`" creationDate=`"2026-09-26 10:30:00 -0400`" startDate=`"$t`" endDate=`"$t`" value=`"$v`"/>`n")
  }
  $sw.Write("</HealthData>`n")
  $sw.Close()
}
$F_EXPORT = Join-Path $fixdir 'export-small.xml'
$F_BIG = Join-Path $fixdir 'export-big.xml'
$F_JSON = Join-Path $fixdir 'glucose.json'
$F_EMPTY = Join-Path $fixdir 'empty.xml'
$F_JUNK = Join-Path $fixdir 'shopping-list.txt'
$F_NOGLU = Join-Path $fixdir 'export-noglucose.xml'
# The two shapes a Shortcut produces when the recipe is followed carelessly.
# Both sniff as a glucose file and both parse as valid JSON, so they reach the
# ingest and die there -- which is why the route reported "0 new readings" and no
# error until the stored==0 guard was added. Verified against fourteen candidate
# outputs; these are the two that were silently accepted.
$F_BADDATE = Join-Path $fixdir 'glucose-unformatted-date.json'
$F_BADNUM = Join-Path $fixdir 'glucose-decimal-comma.json'
New-AppleExport $F_EXPORT 120 300
# 64MB, and the size is the whole point. A 12.8MB fixture CANNOT discriminate:
# materialised as UTF-16 it costs ~26MB, under the 60MB threshold below, so the
# check would have passed the one implementation it exists to reject. At 64MB
# the two hypotheses land either side of that line -- bounded ~22MB measured,
# materialised ~128MB. A threshold discriminates because of its fixture, not
# because of its number.
New-AppleExport $F_BIG 300 300000
New-AppleExport $F_NOGLU 0 500
Set-Content -LiteralPath $F_BADDATE -Encoding utf8 -Value '[{"t":"October 2, 2026 at 7:30 AM","v":"5.6","unit":"mmol/L"}]'
Set-Content -LiteralPath $F_BADNUM -Encoding utf8 -Value '[{"t":"2026-09-26T07:30:00-04:00","v":"5,6","unit":"mmol/L"}]'
New-Item -ItemType File -Path $F_EMPTY -Force | Out-Null
Set-Content -Path $F_JUNK -Value "milk`neggs`nbread" -Encoding utf8
# the Shortcut-produced shape: a plain array of readings
# A DELIBERATELY NON-OVERLAPPING WINDOW. The XML fixture's newest reading is
# 07:30; these run 07:35 -> 10:30, so no timestamp collides. On a shared grid the
# count after this import is the same whether the JSON was read or dropped, and
# the assertion that follows would be theatre.
$JSON_N = 36
$rows = @()
$b2 = [DateTime]::Parse('2026-09-26T10:30:00')
for ($i = 0; $i -lt $JSON_N; $i++) {
  $t = $b2.AddSeconds(-300 * ($JSON_N - 1 - $i)).ToString('yyyy-MM-ddTHH:mm:ss') + '-04:00'
  $v = [Math]::Round(5.6 + 1.9 * [Math]::Sin($i / 11.0), 1)
  $rows += [pscustomobject]@{ t = $t; v = $v; unit = 'mmol/L' }
}
($rows | ConvertTo-Json -Depth 4) | Set-Content -Path $F_JSON -Encoding utf8
Write-Host ("  fixtures: export-small {0:N0}B, export-big {1:N0}B, glucose.json {2:N0}B, empty 0B, junk, no-glucose {3:N0}B" -f `
  (Get-Item $F_EXPORT).Length, (Get-Item $F_BIG).Length, (Get-Item $F_JSON).Length, (Get-Item $F_NOGLU).Length)

# THE PASS LINE BELOW CLAIMS THIS GATE NEVER CALLS THE INGEST API. Checked, not
# asserted -- D146's gate reached glucoseIngest from JavaScript and therefore
# could not see that no button existed. If a later edit here reaches for that
# shortcut, this gate fails instead of printing a PASS line that has quietly
# become false.
$selfSrc = (Get-Content -Raw -LiteralPath $PSCommandPath)
$selfCode = ($selfSrc -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
foreach ($banned in @(('glucose' + 'Ingest'), ('glucose' + 'Write'), ('normalize' + 'Glucose'))) {
  if ($selfCode -match [regex]::Escape($banned)) {
    Write-Host "IMPORT GATE: FAIL"
    Write-Host "  - this gate calls HT.$banned directly. The route is the subject; reaching past it is how D146 shipped an ingest with no button. Hand the file to the input instead."
    exit 1
  }
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome or Edge found"; exit 2 }
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
    try { $ctx.Response.Close() } catch { }
  }
}
function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
  try { if (Test-Path $fixdir) { Remove-Item $fixdir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  Start-Sleep -Milliseconds 600
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "--js-flags=--expose-gc", "about:blank")
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'DOM.enable' $null | Out-Null
  Invoke-CDP 'Input.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 745; deviceScaleFactor = 1; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  # WAIT ON A REAL SIGNAL, not a clock. A fixed sleep here reported
  # "HT is not defined" on the first run of this gate, which reads like a parse
  # error in app.js and is actually a gate that asked too early -- the same
  # confusion the ring-size settle-wait was held back for. Poll for the thing
  # that must exist, and if it never does, say what the page WAS so the next
  # reader is not guessing.
  $ready = $false
  for ($i = 0; $i -lt 100; $i++) {
    Start-Sleep -Milliseconds 200
    if ((Eval "(typeof window.HT === 'object' && typeof HT.boot === 'function') ? 1 : 0") -eq 1) { $ready = $true; break }
  }
  if (-not $ready) {
    $diag = Eval "JSON.stringify({state: document.readyState, title: document.title, scripts: document.querySelectorAll('script[src]').length, ht: typeof window.HT, url: location.href})"
    Write-Host "ERROR: HT never appeared. page was: $diag"
    Cleanup; exit 2
  }

  # ========== THE EMPTY STATE: where the FIRST import has to live ==========
  $boot = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T10:35:00-04:00'); });
  // NOTHING LEAVES THE PHONE, checked at the CALL. Resource-timing entries are
  // a weaker instrument: an aborted or blocked request may leave none, so an
  // empty timing list is not proof nobody tried. These wrappers record the
  // attempt. Installed before the first import, not after.
  window.__out = [];
  (function () {
    const log = function (k, u) {
      let cross = true;
      try { cross = new URL(String(u), location.href).origin !== location.origin; }
      catch (e) { cross = true; }
      if (!cross) return;
      let st = '';
      try { st = String((new Error()).stack || ''); } catch (e) { }
      // ATTRIBUTION. A web-antivirus on this machine injects a script from its
      // own domain, and that script issues XHRs through this wrapper -- so the
      // API alone cannot say whose call it is. The stack can: a call made by
      // this origin's own code names this origin in its frames.
      window.__out.push({ kind: k, url: String(u).slice(0, 140),
                          ours: st.indexOf(location.origin) >= 0, stack: st.slice(0, 200) });
    };
    const of = window.fetch;
    window.fetch = function (u) { log('fetch', (u && u.url) || u); return of.apply(this, arguments); };
    const oo = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (m, u) { log('xhr', u); return oo.apply(this, arguments); };
    if (navigator.sendBeacon) {
      const ob = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = function (u) { log('beacon', u); return ob.apply(null, arguments); };
    }
    const OW = window.WebSocket;
    if (OW) { window.WebSocket = function (u) { log('ws', u); return new OW(...arguments); }; }
  })();
  localStorage.clear(); HT.boot(); await sleep(250);
  const DK = '2026-09-26'; const S = HT.state();
  S.days[DK] = { status: 'in_progress', water_l: 0, items: [
    { name: 'lentil stew', meal: 'lunch', time: '06:30', grams: 200, kcal: 420,
      protein_g: 20, fat_g: 8, carb_g: 60, fiber_g: 9, soluble_fiber_g: 2,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' }] };
  S.current = DK;
  if (typeof HT.glucoseClear === 'function') HT.glucoseClear();
  HT.refresh(); await sleep(400);
  return {
    hasFile:    !!document.querySelector('#dayView input[type=file]'),
    hasEmpty:   !!document.querySelector('#dayView .gempty'),
    hasRow:     !!document.querySelector('#dayView .grow'),
    hasImportFn: typeof HT.glucoseImportFile === 'function',
    hasSniff:   typeof HT.glucoseSniff === 'function',
    emptyText:  (document.querySelector('#dayView .gempty') || {}).textContent || '',
    scSteps:    document.querySelectorAll('#dayView .screcipe .scsteps li').length,
    scText:     (document.querySelector('#dayView .screcipe') || {}).textContent || '',
    fallbackText: (document.querySelector('#dayView .gefall') || {}).textContent || '',
    settings:   !!document.querySelector('#settingsPanel input[type=file].gimportfile, #glucoseImportSettings')
  };
})()
'@
  $b = EvalA $boot
  if ($b -like 'EXCEPTION*') { Write-Host "ERROR: boot threw: $b"; Cleanup; exit 2 }
  $B = $b | ConvertFrom-Json

  Chk ([bool]$B.hasEmpty) "there is no .gempty glucose state in the day -- C ruled the FIRST import needs a home, and D146 made the row render nothing when there are no readings, so the row cannot be it"
  Chk ([bool]$B.hasFile) "there is no file input inside #dayView -- the route must be reachable from the day, not only from Settings"
  Chk (-not $B.hasRow) "a .grow row rendered with no readings -- D146 ruled a day with no glucose draws no row, and the empty state is a different element"
  Chk ([bool]$B.hasImportFn) "HT.glucoseImportFile does not exist"
  Chk ([bool]$B.hasSniff) "HT.glucoseSniff does not exist -- A ruled ONE control that sniffs the format"
  Chk ($B.emptyText -match '(?i)apple health|healthkit') "the empty state does not say where readings come from: '$($B.emptyText)'"
  Chk ($B.emptyText -match '(?i)import|choose|add|file') "the empty state offers no action: '$($B.emptyText)'"
  Chk ($B.emptyText -match '(?i)shell|app store|native|later|for now|until') "the empty state does not say this is a STOPGAP -- H20 ruled it says plainly that the durable route reads HealthKit directly: '$($B.emptyText)'"
  Chk ([bool]$B.settings) "there is no import control in Settings -- C ruled Settings is the FALLBACK"

  # H21/F: THE SHORTCUT LEADS. Asserted as an ORDER, not as a presence -- both
  # routes are named on this surface, so "mentions the Shortcut" would have
  # passed the version that led with the full export, which is the version that
  # told the user to do the one thing that had just failed on their phone.
  $iSc = $B.emptyText.IndexOf('Shortcut')
  $iEx = $B.emptyText.IndexOf('Export All Health Data')
  Chk ($iSc -ge 0) "the empty state never mentions the Shortcut, which H21 ruled the recommended path"
  Chk ($iEx -ge 0) "the empty state never mentions the full export, which stays the named FALLBACK rather than disappearing"
  Chk ($iSc -ge 0 -and $iEx -ge 0 -and $iSc -lt $iEx) "the empty state reaches 'Export All Health Data' (at $iEx) before 'Shortcut' (at $iSc) -- H21 ruled the Shortcut LEADS, because the export is what failed on the device for storage"
  Chk ($B.scSteps -eq 6) "the in-app recipe renders $($B.scSteps) steps, expected 6 -- and the step count is load-bearing: the first draft of this recipe collapsed Combine Text and the Text that brackets it into one step, which is unbuildable as written"
  Chk ($B.fallbackText -match '(?i)zip') "the fallback never mentions that the export arrives as a .zip on a phone -- the device finding behind H21"
  Chk ($B.fallbackText -match '(?i)storage|room|space') "the fallback does not say the unzip needs room -- which is the reason the Shortcut leads, and a fallback that hides its own cost is a trap"

  if (-not $B.hasFile -or -not $B.hasImportFn) {
    Write-Host "IMPORT GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Write-Host "  (the route does not exist yet, so the rest of the gate cannot run)"
    Cleanup; exit 1
  }

  # ========== THE FIRST IMPORT, through the picker, from the empty state ====
  # The origin set BEFORE any import. Everything already talking to the network
  # on this machine is in here, so what matters afterwards is whether the set
  # GREW.
  $ORIGINS_JS = @'
JSON.stringify((function () {
  const r = (window.performance && performance.getEntriesByType) ? performance.getEntriesByType('resource') : [];
  const seen = {};
  for (let i = 0; i < r.length; i++) {
    try { const o = new URL(r[i].name).origin; if (o !== location.origin) seen[o] = (seen[o] || 0) + 1; }
    catch (e) { seen['<unparseable>'] = (seen['<unparseable>'] || 0) + 1; }
  }
  return Object.keys(seen).sort();
})())
'@
  $originsBefore = AsList (Eval $ORIGINS_JS)
  $s0 = Import-Seq
  Pick-File '#dayView input[type=file]' $F_EXPORT
  $p1 = Wait-Import $s0
  Chk ($null -ne $p1) "the first import never finished -- the picker was handed $(Split-Path -Leaf $F_EXPORT) and no attempt completed within 40s"
  if ($null -ne $p1) {
    Chk ($p1.format -eq 'apple') "the first import sniffed format '$($p1.format)', expected 'apple'"
    Chk ([string]::IsNullOrEmpty($p1.error)) "the first import reported an error: $($p1.error)"
  }
  $r1 = EvalA @'
(async function () {
  const s = HT.glucoseDaySummary('2026-09-26');
  const prog = document.querySelector('#dayView .gprog, #dayView .gimportnote');
  return { n: s ? s.n : 0, unit: s ? s.unit : null, raw: s ? s.rawUnit : null,
           row: document.querySelectorAll('#dayView .grow').length,
           empty: document.querySelectorAll('#dayView .gempty').length,
           prog: prog ? (prog.textContent || '').replace(/\s+/g, ' ').trim() : null };
})()
'@
  $R1 = $r1 | ConvertFrom-Json
  Chk ($R1.n -gt 0) "the picker selection imported nothing (n=$($R1.n)) -- this is the whole point: a real file input, no call to the ingest API anywhere in this test"
  Chk ($R1.unit -eq 'mmol/L') "the imported canonical unit is '$($R1.unit)', expected mmol/L"
  Chk ($null -ne $R1.raw -and ([string]$R1.raw).Length -gt 0) "the platform's verbatim unit string was not kept from the export (E)"
  Chk ($R1.row -ge 1) "after the first import the day still shows no glucose row"
  Chk ($R1.empty -eq 0) "the empty state is still on the page after readings arrived -- it is the home for the FIRST import, not a permanent fixture"

  # ========== THE SAME CONTROL TAKES THE OTHER FORMAT ======================
  $n_before = $R1.n
  $s0 = Import-Seq
  Pick-File '#dayView input[type=file]' $F_JSON
  $p2 = Wait-Import $s0
  Chk ($null -ne $p2) "the Shortcut-JSON import never finished"
  if ($null -ne $p2) {
    Chk ($p2.format -eq 'shortcut') "the JSON was sniffed as '$($p2.format)', expected 'shortcut' -- ONE control, and it has to tell the two apart without being told"
    Chk ([string]::IsNullOrEmpty($p2.error)) "the JSON import reported an error: $($p2.error)"
  }
  $r2 = EvalA @'
(async function () {
  const s = HT.glucoseDaySummary('2026-09-26');
  return { n: s ? s.n : 0, unit: s ? s.unit : null };
})()
'@
  $R2 = $r2 | ConvertFrom-Json
  Chk ($R2.n -eq ($n_before + $JSON_N)) "a Shortcut-style glucose JSON, through the SAME control, on a grid that overlaps nothing, should have added exactly $JSON_N readings -- the count went $n_before -> $($R2.n). A ruled ONE control and two formats, sniffed; this is the assertion that fires if the sniff silently dropped the JSON"
  Chk ($R2.unit -eq 'mmol/L') "the JSON import's canonical unit is '$($R2.unit)', expected mmol/L"

  # ========== A RE-IMPORT MUST NOT DUPLICATE ===============================
  # THE ASSERTION BELOW EXPECTS AN ABSENCE (the count must not move), which is
  # the one shape that passes for free if the import never ran. So this wait is
  # load-bearing, not hygiene.
  $s0 = Import-Seq
  Pick-File '#dayView input[type=file]' $F_EXPORT
  $p3 = Wait-Import $s0
  Chk ($null -ne $p3) "the re-import never finished, so the no-duplicates assertion below would have passed without testing anything"
  if ($null -ne $p3) {
    Chk ($p3.added -eq 0) "the re-import reported $($p3.added) NEW readings from a file already imported -- the merge is by timestamp and every one of these was already held"
    Chk ($p3.readings -gt 0) "the re-import parsed $($p3.readings) readings, so it did not actually re-read the file"
  }
  $r3 = EvalA @'
(async function () {
  const s = HT.glucoseDaySummary('2026-09-26');
  return { n: s ? s.n : 0 };
})()
'@
  $R3 = $r3 | ConvertFrom-Json
  Chk ($R3.n -eq $R2.n) "re-importing the same export changed the count ($($R2.n) -> $($R3.n)) -- the merge is by timestamp and a re-import must add nothing. This is the defect D146 found as `store[dk] = norm`, now reachable through the route"

  # ========== UNRECOGNISED INPUT IS REFUSED BY NAME ========================
  # Read once, before the refusal loop, so the loop can compare against it.
  $scFmtEarly = Eval "HT.GLUCOSE_SC_DATEFMT"
  $nStable = $R3.n
  foreach ($bad in @(@($F_JUNK, 'a shopping list'), @($F_EMPTY, 'a 0-byte file'), @($F_NOGLU, 'an export with no glucose'),
                     @($F_BADDATE, "a Shortcut file with Shortcuts' DEFAULT date rendering"),
                     @($F_BADNUM, 'a Shortcut file whose value carries a locale decimal comma'))) {
    $path = $bad[0]; $what = $bad[1]; $nBefore = $nStable
    $s0 = Import-Seq
    Pick-File '#dayView input[type=file]' $path
    $pb = Wait-Import $s0
    Chk ($null -ne $pb) "$what produced no completed attempt at all -- the refusal assertions below cannot be believed"
    if ($null -ne $pb) {
      Chk (-not [string]::IsNullOrEmpty($pb.error)) "$what completed with NO error recorded -- it was accepted, or it failed silently"
      Chk ($pb.added -eq 0) "$what added $($pb.added) readings"
    }
    $rb = EvalA @'
(async function () {
  const s = HT.glucoseDaySummary('2026-09-26');
  const err = document.querySelector('#dayView .gerr, #dayView .gimportnote');
  return { n: s ? s.n : 0, msg: err ? (err.textContent || '').replace(/\s+/g, ' ').trim() : null };
})()
'@
    $RB = $rb | ConvertFrom-Json
    Chk ($RB.n -eq $nBefore) "$what changed the stored readings ($nBefore -> $($RB.n)) -- an unrecognised or empty file must leave the cache untouched"
    Chk ($null -ne $RB.msg -and ([string]$RB.msg).Length -gt 0) "$what produced no message at all -- A ruled unrecognised input is REFUSED BY NAME, never guessed and never silent"
    if ($what -like '*DEFAULT date*') {
      # The refusal that names a date pattern must name THE pattern -- the one
      # the recipe prints. Two patterns in one app is two instructions.
      Chk ($RB.msg.Contains($scFmtEarly)) "the refusal for a bad date names a pattern other than the one the app prints ('$scFmtEarly'): $($RB.msg)"
    }
    Chk ($RB.msg -match [regex]::Escape((Split-Path -Leaf $path))) "$what was refused without naming the file -- '$(Split-Path -Leaf $path)' does not appear in '$($RB.msg)'. A ruled refused BY NAME: the user picked a file from a list of files, so the app has to say WHICH one it could not read"
  }

  # ========== THE HEAP STAYS BOUNDED ON A BIG FILE =========================
  $heap = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  // Collect FIRST. Four imports have already run in this page, and without a
  // collection their garbage is counted as this import's growth -- measured,
  // that was the difference between 22MB and 41MB for the same work.
  if (window.gc) { window.gc(); await sleep(60); window.gc(); await sleep(60); }
  return { before: performance.memory ? performance.memory.usedJSHeapSize : 0,
           gc: typeof window.gc === 'function' };
})()
'@
  $HEAP0 = $heap | ConvertFrom-Json
  $H0 = $HEAP0.before
  Chk ([bool]$HEAP0.gc) "window.gc is unavailable, so the baseline below is whatever the collector happened to be holding and the growth figure carries four earlier imports' garbage"
  Chk ($H0 -gt 0) "performance.memory reported nothing, so the bounded-heap assertion below compares 0 against 0 and cannot fail -- a check that cannot fail is not a check (D96)"
  $s0 = Import-Seq
  Eval "window.__seq0 = $s0; 1" | Out-Null
  Pick-File '#dayView input[type=file]' $F_BIG
  # The peak has to be sampled WHILE the import runs, so this loop lives in the
  # page rather than in PowerShell -- and it stops on this attempt's sequence,
  # not on a `done` left standing by the last one.
  $r4 = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  let peak = performance.memory ? performance.memory.usedJSHeapSize : 0;
  for (let i = 0; i < 400; i++) {
    await sleep(50);
    if (performance.memory) { const u = performance.memory.usedJSHeapSize; if (u > peak) peak = u; }
    const p = HT.glucoseImportProgress ? HT.glucoseImportProgress() : null;
    if (p && p.seq > window.__seq0 && p.done) break;
  }
  const s = HT.glucoseDaySummary('2026-09-26');
  return { peak: peak, n: s ? s.n : 0,
           progress: HT.glucoseImportProgress ? HT.glucoseImportProgress() : null };
})()
'@
  $R4 = $r4 | ConvertFrom-Json
  $growthMB = [Math]::Round((($R4.peak - $H0) / 1048576), 1)
  Chk ($growthMB -lt 80) "importing the 64MB export grew the heap by ${growthMB}MB. Measured on this route: a 5x larger file moves the peak 1.24x (17.8 -> 22.1MB), against a 7.7MB noise band from importing one file twice -- so the peak tracks the 2MB chunk, not the file. Reading this file into one string would cost ~128MB of UTF-16 and is what this number separates. A peak that scales with the file is what kills an iOS tab on a 491MB export. The 80MB line sits between the two: bounded measures 22MB in isolation and up to 42MB with earlier imports uncollected, materialised would be ~128MB"
  Chk ($null -ne $R4.progress) "HT.glucoseImportProgress does not report -- D ruled progress shows BYTES and READINGS, because 99.99% of an export is not glucose and a readings-only counter sits at zero looking broken"
  if ($null -ne $R4.progress) {
    Chk ($R4.progress.bytes -gt 0) "progress reported 0 bytes read for a multi-megabyte file"
    Chk ($null -ne $R4.progress.readings) "progress does not report a readings count"
  }

  # ========== NOTHING LEFT THE PHONE ======================================
  # Asserted on the REQUEST LOG rather than on intent: the whole claim is
  # checkable, so it is checked.
  $CALLS = AsList (Eval "JSON.stringify(window.__out || [])")
  $ours = @($CALLS | Where-Object { $_.ours })
  $foreign = @($CALLS | Where-Object { -not $_.ours })
  $ourList = ($ours | ForEach-Object { $_.kind + ' ' + $_.url }) -join '; '
  Chk ($ours.Count -eq 0) "$($ours.Count) cross-origin call(s) were made BY THIS APP'S OWN CODE during the imports -- the stack names this origin, so attribution is not in doubt: $ourList"

  $originsAfter = AsList (Eval $ORIGINS_JS)
  $newOrigins = @($originsAfter | Where-Object { $originsBefore -notcontains $_ })
  $newDetail = ''
  if ($newOrigins.Count) {
    $newDetail = (AsList (Eval @'
JSON.stringify((function () {
  const r = (window.performance && performance.getEntriesByType) ? performance.getEntriesByType('resource') : [];
  const out = [];
  for (let i = 0; i < r.length; i++) {
    try { if (new URL(r[i].name).origin !== location.origin) out.push(r[i].initiatorType + ' ' + r[i].name.slice(0, 90)); }
    catch (e) { }
  }
  return out;
})())
'@)) -join ' | '
  }
  Chk ($newOrigins.Count -eq 0) "the imports introduced $($newOrigins.Count) cross-origin destination(s) the page was not already talking to: $(@($newOrigins) -join ', '). Every cross-origin resource, with how it was reached: $newDetail. This half needs no call stack, so it catches a parser-initiated leak too"

  # Reported, not asserted: a call this app did not make is not this app's
  # defect, and a gate that fails on the tester's antivirus teaches everyone to
  # ignore it.
  $foreignOrigins = @()
  foreach ($c in $foreign) {
    try { $o = ([Uri]$c.url).GetLeftPart([UriPartial]::Authority) } catch { $o = '<unparseable>' }
    if ($foreignOrigins -notcontains $o) { $foreignOrigins += $o }
  }

  # ========== THE PRINTED RECIPE MUST PARSE ================================
  #
  # The app prints a recipe. This builds a file from THAT recipe's own constants
  # and hands it to the route. The timestamp is formatted FROM
  # GLUCOSE_SC_DATEFMT, so changing the pattern changes the test input: if the
  # printed pattern ever stops producing something this parser accepts, the gate
  # fails here. A recipe printed next to an importer that would reject it is
  # worse than no recipe.
  $scLine = Eval "HT.GLUCOSE_SC_LINE"
  $scFmt = Eval "HT.GLUCOSE_SC_DATEFMT"
  $scFile = Eval "HT.GLUCOSE_SC_FILE"
  Chk (-not [string]::IsNullOrEmpty($scLine)) "HT.GLUCOSE_SC_LINE is empty, so the printed recipe cannot be checked against the parser"
  Chk (-not [string]::IsNullOrEmpty($scFmt)) "HT.GLUCOSE_SC_DATEFMT is empty"
  Chk ($B.scText.Contains($scFmt)) "the date pattern the gate verifies ('$scFmt') is not the pattern the app prints -- the user would be typing something no test covers"
  if ($scLine -and $scFmt) {
    # ICU -> .NET for the two constructs the recipe is allowed to use.
    $netFmt = $scFmt.Replace('ZZZZZ', 'zzz').Replace("'T'", '\T')
    $t1 = [DateTimeOffset]::Parse('2026-09-26T07:30:00-04:00').ToString($netFmt)
    $t2 = [DateTimeOffset]::Parse('2026-09-26T07:35:00-04:00').ToString($netFmt)
    $mk = {
      param($stamp, $val)
      $scLine.Replace('[Start Date]', $stamp).Replace('[Value]', $val).Replace('[Unit]', 'mmol/L')
    }
    $l1 = & $mk $t1 '5.6'
    $l2 = & $mk $t2 '5.9'
    Chk ($l1 -ne $scLine) "substituting the recipe's placeholders changed nothing -- the placeholder names in GLUCOSE_SC_LINE moved, and this check would otherwise import a file full of literal placeholders and blame the parser"
    # Built exactly as the recipe says: the rows joined by a comma (step 4) and
    # wrapped in brackets (step 5). Those are two steps for a reason, and this
    # is the shape they produce.
    $scPath = Join-Path $fixdir $(if ($scFile) { $scFile } else { 'glucose.json' })
    [IO.File]::WriteAllText($scPath, ('[' + $l1 + ',' + $l2 + ']'), (New-Object Text.UTF8Encoding $false))
    Eval "HT.glucoseClear();HT.refresh();1" | Out-Null
    Start-Sleep -Milliseconds 300
    $s0 = Import-Seq
    Pick-File '#dayView input[type=file]' $scPath
    $pr = Wait-Import $s0
    Chk ($null -ne $pr) "the file built from the app's own printed recipe never finished importing"
    if ($null -ne $pr) {
      Chk ([string]::IsNullOrEmpty($pr.error)) "THE APP PRINTS A RECIPE THIS ROUTE REFUSES: $($pr.error)"
      Chk ($pr.format -eq 'shortcut') "the recipe's output sniffed as '$($pr.format)', expected 'shortcut'"
      Chk ($pr.added -eq 2) "the recipe's output added $($pr.added) readings, expected 2 -- the two rows it was built from"
    }
    $scStored = [int](Eval "HT.glucoseCount()")
    Chk ($scStored -eq 2) "after importing the recipe's own output the cache holds $scStored readings, expected 2"
  }

  if ($fails.Count) {
    Write-Host "IMPORT GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "IMPORT GATE: PASS -- the first import happens from the day's EMPTY glucose state through a real file input, with no call to any ingest function in this test; one control takes both an Apple export and a Shortcut JSON; a re-import adds nothing; five kinds of bad input are each refused by name with the cache untouched (a shopping list, a 0-byte file, an export with no glucose, and the two Shortcut shapes that sniff and parse fine but carry unreadable dates or a decimal comma); the heap grew ${growthMB}MB on a 64MB file, where materialising it would cost ~128MB; nothing this app's own code requested left the origin; the day's empty state LEADS with the Shortcut and names the export as the fallback with its storage cost; and a file built from the app's OWN PRINTED RECIPE -- timestamp formatted from the pattern the app displays -- is accepted by this route."
  if ($foreign.Count) {
    Write-Host "  ATTRIBUTED AND EXCLUDED: $($foreign.Count) cross-origin call(s) from code this app did not load -- $(@($foreignOrigins) -join ', ') -- a web-antivirus on this machine injects a script into every page and that script uses XMLHttpRequest. Their stacks name no file of this origin, and they were present before the first import, so neither instrument above attributes them to the app."
  }
  Write-Host "  WHAT THIS GATE CANNOT SEE: its fixtures are synthetic, so it cannot tell whether these regexes match a real Apple export. Measured separately and outside this gate, the real 490.8MB export went through this route at 451 readings in 4.6s and a 48MB peak -- the same count an independent parser found. ATTESTED ON DEVICE (D150, iOS 27): the real 490MB export.xml imported from the Files app on the phone, the row and chart rendered, and pinch/swipe work -- so Safari does slice a 490MB Blob and iOS does hand a file that size to a web page. Headless Chrome is still not an iPhone, but it is no longer the only evidence. What this gate STILL cannot see: the .zip the export actually arrives in (H21, unbuilt), and the 3-day/10-day windows, which have never had real data to show -- the export carries 451 readings across 3 days."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
