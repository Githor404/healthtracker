# Does the REAL D136 key (two rarest tokens, plural-folded, rarity from the
# shipped corpus) merge the names that are one food?
#
# Measured offline, the token-set fallback keeps them apart:
#   "creamy coleslaw"                        3x
#   "creamy coleslaw with mixed vegetables"  2x
#
# Those are one food. If the real key merges them the top entry is 5x and
# frequency should be keyed by matchKey; if it does not, the quick-add list shows
# one food twice and the grouping needs a ruling.
#
# Also asked, on the same page: does matchKey merge any pair that is NOT one food?
# A merge that over-merges is worse than one that under-merges, because it hides a
# different food inside a count.
$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\thoma\projects\healthtracker'
$Port = 8293
$Dbg = 9499
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-keys-" + [System.Guid]::NewGuid().ToString('N'))
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
  $buf = New-Object byte[] 262144
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
    if (++$guard -gt 900) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  if ($r.result.exceptionDetails) {
    return 'EXCEPTION: ' + $r.result.exceptionDetails.text + ' | ' + $r.result.exceptionDetails.exception.description
  }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no browser"; exit 2 }
$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
  $mimes = @{ '.html' = 'text/html'; '.js' = 'application/javascript'; '.json' = 'application/json';
              '.png' = 'image/png'; '.bin' = 'application/octet-stream'; '.css' = 'text/css' }
  while ($l.IsListening) {
    try { $ctx = $l.GetContext() } catch { break }
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
      if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
      $full = Join-Path $repo $rel
      if (Test-Path $full -PathType Leaf) {
        $b = [System.IO.File]::ReadAllBytes($full)
        $e = [System.IO.Path]::GetExtension($full).ToLower()
        if ($mimes.ContainsKey($e)) { $ctx.Response.ContentType = $mimes[$e] }
        $ctx.Response.OutputStream.Write($b, 0, $b.Length)
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
}

try {
  Start-Sleep -Milliseconds 600
  $args2 = @("--headless=new", "--remote-debugging-port=$Dbg", "--user-data-dir=$udd",
             "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $args2 -PassThru
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $pg = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg) { $tabUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: no CDP"; Cleanup; exit 2 }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  $ua = Eval 'navigator.userAgent'
  Invoke-CDP 'Network.enable' $null | Out-Null
  Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua; acceptLanguage = 'en-CA' } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "http://127.0.0.1:$Port/" } | Out-Null
  Start-Sleep -Milliseconds 3000
  if ((Eval 'typeof HT') -ne 'object') { Write-Host "ERROR: no HT"; Cleanup; exit 2 }

  $probe = @'
window.__o = null;
(async function () {
  const O = {};
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  try {
  HT.boot(); await sleep(200);
  await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);
  O.ready = HT.matchIndexReady();
  O.ns = HT.corpusNamespace();
  // THE WHOLE LOG, under the real key. export.json is fetched from the same local
  // server rather than restored into state: nothing is mutated and no personal
  // data is written anywhere -- the page just reads the names and keys them.
  try {
    const r = await fetch('/export.json');
    const ex = await r.json();
    const freq = {}, names = {}, grams = {};
    Object.keys(ex.days || {}).forEach(function (d) {
      (ex.days[d].items || []).forEach(function (it) {
        if (!it || it._auto) return;
        const k = HT.matchKey(String(it.name || ''));
        if (!k) return;
        freq[k] = (freq[k] || 0) + 1;
        (names[k] = names[k] || []).push(String(it.name || ''));
        if (it.grams != null && it.grams !== '') (grams[k] = grams[k] || []).push(Number(it.grams));
      });
    });
    const rows = Object.keys(freq).map(function (k) { return { k: k, n: freq[k],
      names: names[k].filter(function (v, i, a) { return a.indexOf(v) === i; }),
      grams: (grams[k] || []).filter(function (v, i, a) { return a.indexOf(v) === i; }).sort(function(a,b){return a-b;}) }; });
    rows.sort(function (a, b) { return b.n - a.n; });
    O.total = Object.keys(freq).reduce(function (a, k) { return a + freq[k]; }, 0);
    O.distinct = rows.length;
    O.repeats = rows.filter(function (r2) { return r2.n >= 2; }).length;
    O.top = rows.slice(0, 14).map(function (r2) {
      return r2.n + 'x  [' + r2.k + ']  names=' + r2.names.length
        + '  grams=' + (r2.grams.length ? r2.grams.join('/') : 'none');
    });
    O.merged = rows.filter(function (r2) { return r2.names.length > 1; })
      .map(function (r2) { return r2.n + 'x ' + r2.names.join('  +  '); });
  } catch (e) { O.logErr = String((e && e.message) || e); }
  // THE CONTROL PAIRS ONLY. D136's measurement rests on two pairs that must NOT
  // merge, and those are already named in the decision log. The user's own foods
  // are NOT hardcoded here -- this file is committed and the repo is public-facing
  // and fixture-synthetic (CLAUDE.md); the real names are read from the log below,
  // at run time, on the machine that owns it.
  const NAMES = ['green onions', 'crab', 'red lentils', 'brown lentils'];
  O.keys = NAMES.map(function (n) { return n + '  ==>  ' + HT.matchKey(n); });
  // The merge question is answered from the LOG (see O.merged below) rather than
  // from a pair written into this file.
  O.coleslawMerge = null;
  // the pairs D136 measured as MUST-NOT-MATCH, re-checked on today's corpus
  O.onionCrab = (HT.matchKey('green onions') === HT.matchKey('crab'));
  O.lentils = (HT.matchKey('red lentils') === HT.matchKey('brown lentils'));
  } catch (e) { O.threw = String((e && e.message) || e); }
  window.__o = JSON.stringify(O);
})();
'1'
'@
  if ((Eval $probe) -ne '1') { Write-Host "ERROR: probe would not start"; Cleanup; exit 2 }
  $raw = $null
  for ($w = 0; $w -lt 80; $w++) { Start-Sleep -Milliseconds 500; $raw = Eval 'window.__o'; if ($raw) { break } }
  if (-not $raw) { Write-Host "ERROR: probe hung"; Cleanup; exit 2 }
  $M = $raw | ConvertFrom-Json
  if ($M.threw) { Write-Host "THREW: $($M.threw)" }
  Write-Host ""
  Write-Host "THE REAL D136 KEY (two rarest tokens, rarity from the shipped $($M.ns) corpus)"
  Write-Host "index ready: $($M.ready)"
  Write-Host ""
  foreach ($k in $M.keys) { Write-Host "  $k" }
  Write-Host ""
  Write-Host "THE WHOLE LOG UNDER THE REAL KEY"
  Write-Host "  $($M.total) items -> $($M.distinct) distinct foods, $($M.repeats) appear more than once"
  if ($M.logErr) { Write-Host "  (could not read the log: $($M.logErr))" }
  foreach ($t in $M.top) { Write-Host "    $t" }
  Write-Host ""
  Write-Host "  NAMES THE KEY MERGED (one food under several spellings):"
  if (@($M.merged).Count -eq 0) { Write-Host "    none" } else { foreach ($t in $M.merged) { Write-Host "    $t" } }
  Write-Host ""
  Write-Host "  the two coleslaw names MERGE:        $($M.coleslawMerge)"
  Write-Host "  green onions == crab (must be false): $($M.onionCrab)"
  Write-Host "  red == brown lentils (must be false): $($M.lentils)"
  Write-Host ""
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
Cleanup
exit 0
