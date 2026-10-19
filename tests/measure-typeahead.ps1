# MEASURE: what does search-as-you-type over the corpus actually cost?
#
# ONE-DOOR/2 is ruled to search the corpus AS THE USER TYPES, reusing the
# matcher. The existing identity rail does NOT do that, and its code says why:
#
#   "Typing does NOT re-render: the field would be rebuilt under the caret on
#    every keystroke. The text is held, and the search runs on a deliberate act."
#
# So there are two open questions and this script answers the second one only:
#   (a) the caret -- a RENDERING question, settled by rendering the field once and
#       re-rendering only the list beneath it. No measurement decides it.
#   (b) the COST -- is a search per keystroke affordable at all, and does fetching
#       the macro row for each candidate (an IndexedDB read per row) stay inside a
#       keystroke's budget, or must the list show names first and numbers after?
#
# Measured, per query, growing one character at a time the way typing does:
#   - matchCandidates alone (RAM: the hydrated index)
#   - the same plus corpusLookup for every candidate (IndexedDB, async)
#   - how many rows came back, so a fast number is not a fast nothing
#
# WHAT THIS IS NOT AN AUTHORITY ON: a headless browser on a desktop is not the
# user's phone. It bounds the SHAPE of the cost -- RAM-only versus per-row disk
# reads, and how that grows with query length -- not the absolute milliseconds.
#
# Exit 0 always on a successful measurement: this is a measurement, not a gate,
# and it prints no GATE line precisely so the runner never counts it as one.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8233
$Dbg = 9439
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-typeahead-" + [System.Guid]::NewGuid().ToString('N'))
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
  while ($true) { if (++$g -gt 6000) { throw "no response for $m" }
    $msg = Receive-One; if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg } } }
function Eval([string]$e) { (Invoke-CDP 'Runtime.evaluate' @{ expression = $e; returnByValue = $true }).result.result.value }
# AWAIT THE PROMISE, and stringify INSIDE the page: a JSON.stringify of an async
# eval returns "{}" otherwise.
function EvalA([string]$js) {
  $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($js -replace "`r`n", "`n")))
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = "eval(decodeURIComponent(escape(atob('" + $enc + "')))).then(function(o){return JSON.stringify(o);})"; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + $r.result.exceptionDetails.text }
  return $r.result.result.value }

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (-not (Test-Path (Join-Path $repo 'corpus/dist/cnf.bin'))) {
  Write-Host "ERROR: corpus/dist/cnf.bin is missing -- there is nothing to search"; exit 2 }

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
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { } }

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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  # The corpus has to be installed and hydrated or every number below is a
  # measurement of an empty index -- the fast-nothing this script is written to
  # avoid reporting.
  # CORPUS_MEM is not exported, and should not be: corpusState() is the declared
  # window onto it, and matchCandidates returning rows is the proof that matters --
  # a ready flag with an index nothing can search would be the fast nothing.
  $ready = EvalA @'
HT.corpusEnsure().then(function () {
  var st = HT.corpusState();
  var probe = HT.matchCandidates('coffee', 8);
  return { hydrated: !!(st && st.ready && probe.length > 0), rows: st ? st.rows : 0,
           ns: st ? st.ns : '?', probeRows: probe.length };
})
'@
  Write-Host ("  corpus: " + $ready)
  if (-not ($ready -like '*"hydrated":true*')) {
    Write-Host "ERROR: the corpus did not hydrate, so nothing measured here would mean anything"
    Cleanup; exit 2 }

  Write-Host ""
  Write-Host "  ---- per-keystroke cost, matcher only (RAM) and with macros (IndexedDB) ----"
  Write-Host ""
  $res = EvalA @'
(function () {
  var QS = ['coffee', 'olive oil', 'cheddar cheese', 'sardines canned'];
  var out = [];
  var jobs = [];
  QS.forEach(function (q) {
    for (var n = 1; n <= q.length; n++) {
      if (n < 2) continue;                      // one character is not a search
      jobs.push({ q: q, s: q.slice(0, n) });
    }
  });
  // The matcher first, synchronously, so its cost is isolated from any disk read.
  jobs.forEach(function (j) {
    var t0 = performance.now();
    var c = HT.matchCandidates(j.s, 8);
    j.matchMs = performance.now() - t0;
    j.rows = c.length;
    j.ids = c.map(function (x) { return x.id; });
  });
  // THE TYPEAHEAD ITSELF, added once it existed. The matcher above is whole-word,
  // so mid-word it is timing a search that finds nothing; this is the search the
  // user actually gets. Timed twice: COLD pays for the per-row weight cache, and
  // two letters can begin a thousand rows, so the first keystroke is the worst.
  jobs.forEach(function (j) {
    var t0 = performance.now();
    var c = HT.matchTypeahead(j.s, 8);
    j.taMs = performance.now() - t0;
    j.taRows = c.length;
  });
  jobs.forEach(function (j) {
    var t0 = performance.now();
    HT.matchTypeahead(j.s, 8);
    j.taWarmMs = performance.now() - t0;
  });
  // Then the macro fetch for the SAME candidate sets, each timed on its own.
  var chain = Promise.resolve();
  jobs.forEach(function (j) {
    chain = chain.then(function () {
      var t0 = performance.now();
      return Promise.all(j.ids.map(function (id) { return HT.corpusLookup(id); }))
        .then(function (rows) {
          j.macroMs = performance.now() - t0;
          j.got = rows.filter(function (r) { return !!r; }).length;
        });
    });
  });
  return chain.then(function () {
    // Reported per query at its full length, plus the worst keystroke anywhere in
    // the typing of it -- the worst case is what a budget has to hold.
    var by = {};
    jobs.forEach(function (j) {
      var b = by[j.q] = by[j.q] || { q: j.q, keystrokes: 0, maxMatch: 0, maxMacro: 0, sumMatch: 0, sumMacro: 0,
                                     taCold: 0, taWarm: 0, midRows: 0, midMatcher: 0 };
      if (j.taMs > b.taCold) b.taCold = j.taMs;
      if (j.taWarmMs > b.taWarm) b.taWarm = j.taWarmMs;
      // Rows on the keystrokes where the word is NOT finished: the matcher's
      // count beside the typeahead's is the whole-word finding, as a number.
      if (j.s !== j.q) { b.midRows += j.taRows; b.midMatcher += j.rows; }
      b.keystrokes++;
      b.sumMatch += j.matchMs; b.sumMacro += j.macroMs;
      if (j.matchMs > b.maxMatch) b.maxMatch = j.matchMs;
      if (j.macroMs > b.maxMacro) b.maxMacro = j.macroMs;
      if (j.s === j.q) { b.finalRows = j.rows; b.finalGot = j.got; b.top = j.ids.slice(0, 3).join(','); }
    });
    return Object.keys(by).map(function (k) {
      var b = by[k];
      return { q: b.q, keystrokes: b.keystrokes,
               matchMax: Math.round(b.maxMatch * 100) / 100,
               matchAvg: Math.round((b.sumMatch / b.keystrokes) * 100) / 100,
               macroMax: Math.round(b.maxMacro * 100) / 100,
               macroAvg: Math.round((b.sumMacro / b.keystrokes) * 100) / 100,
               rows: b.finalRows, got: b.finalGot,
               typeaheadColdMax: Math.round(b.taCold * 100) / 100,
               typeaheadWarmMax: Math.round(b.taWarm * 100) / 100,
               midWordRowsTypeahead: b.midRows, midWordRowsMatcher: b.midMatcher };
    });
  });
})()
'@
  Write-Host ("  " + $res)
  Write-Host ""

  # One more thing the design turns on: a query that matches NOTHING must be as
  # cheap as one that matches, or the empty state is the slow path.
  $miss = EvalA @'
(function () {
  var t0 = performance.now();
  var c = HT.matchCandidates('qqzzxx nothing at all', 8);
  var ms = performance.now() - t0;
  var t1 = performance.now();
  var c2 = HT.matchCandidates('a', 8);
  var ms1 = performance.now() - t1;
  return Promise.resolve({ missMs: Math.round(ms * 100) / 100, missRows: c.length,
                           oneCharMs: Math.round(ms1 * 100) / 100, oneCharRows: c2.length });
})()
'@
  Write-Host ("  edges: " + $miss)

} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  Cleanup
  exit 2
}
Cleanup
Write-Host ""
Write-Host "measure-typeahead: done. No verdict -- this is a measurement, and the"
Write-Host "  absolute milliseconds are a desktop's, not the phone's. What it settles is"
Write-Host "  the SHAPE: whether the matcher is affordable per keystroke, and whether the"
Write-Host "  per-row macro reads belong in the keystroke or after the pick."
exit 0
