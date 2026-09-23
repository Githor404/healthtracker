# Micronutrient corpus round-trip gate (D114/D116).
#
# WHY THIS IS A CDP GATE AND NOT A HARNESS CASE. The committed harness runs from
# a file:// origin, and IndexedDB there neither succeeds nor fails -- open()
# simply never calls back. A harness case would hang, and a hang is a no-verdict,
# which reads exactly like the characterised output-capture intermittent. So the
# pure seams (slot -> column, NaN -> null, per-100g scaling) are gated in the
# harness where they can be, and the ROUND TRIP is gated here, over http, where
# IndexedDB actually works.
#
# What this asserts, against the REAL committed assets:
#   A. a payload whose byte length is not rows x cols x 4 is REFUSED, and writes
#      NOTHING -- there is no half-corpus, because both stores commit in ONE
#      transaction or neither does (D59)
#   B. the real shipped asset acquires: fetch -> install -> hydrate, and the row
#      count matches what the encoder wrote
#   C. values survive the round trip, NaN survives as ABSENCE, and zero survives
#      as zero -- absence is never zero (D8/D90), which is the whole reason the
#      sentinel is NaN
#   D. the attribution the licence requires travels WITH the data
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8151
$origin = "http://127.0.0.1:$port"
$dbg = 9357
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-corpustest-" + [System.Guid]::NewGuid().ToString('N'))
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
  $buf = New-Object byte[] 65536
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
    if (++$guard -gt 600) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function EvalAsync([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { return "EXCEPTION: " + ($r.result.exceptionDetails.text) }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }
if (-not (Test-Path (Join-Path $repo 'corpus/dist/fdc.bin'))) {
  Write-Host "ERROR: corpus/dist/fdc.bin is missing -- run corpus/encode.py first"; exit 2
}

$server = Start-Job -ArgumentList $repo, $port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
  $mimes = @{ '.html' = 'text/html'; '.js' = 'application/javascript'; '.json' = 'application/json';
              '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.css' = 'text/css';
              '.bin' = 'application/octet-stream' }
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
}

$fails = @()
try {
  Start-Sleep -Milliseconds 600
  $args = @("--headless=new", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $args -PassThru
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$dbg/json" -TimeoutSec 3
      $page = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($page) { $tabUrl = $page.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }

  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 2500

  # --- A + C + D: atomicity, the round trip, and the sentinel ---------------
  $script = @'
(async function () {
  const out = {};
  await new Promise(function (r) {
    const d = indexedDB.deleteDatabase(HT.CORPUS_DB);
    d.onsuccess = d.onerror = d.onblocked = function () { r(); };
  });
  const META = { ns: 'fdc', version: 1, cols: 3, slots: [203, 301, 303], hash: 't',
                 attribution: 'USDA FoodData Central, SR Legacy (2018)',
                 basis: 'per 100 g', index: [['1', 'Butter'], ['2', 'Cheddar']] };
  const bad = await HT.corpusInstall(META, new Float32Array([1, 2, 3]).buffer);
  out.refused = (bad.ok === false && bad.why === 'size-mismatch');
  out.nothingWritten = !(await HT.corpusHydrate());
  const ok = await HT.corpusInstall(META, new Float32Array([1, NaN, 0, 4, 5, NaN]).buffer);
  out.installed = (ok.ok === true && ok.rows === 2 && ok.cols === 3);
  await HT.corpusHydrate();
  const st = HT.corpusState();
  out.hydrated = (st.ready === true && st.rows === 2);
  out.attribution = String(st.attribution || '');
  const row = await HT.corpusLookup('2');
  out.rowLen = row ? row.length : -1;
  out.v203 = HT.corpusValueAt(row, META.slots, 203);
  out.v301 = HT.corpusValueAt(row, META.slots, 301);
  out.v303 = HT.corpusValueAt(row, META.slots, 303);
  const r1 = await HT.corpusLookup('1');
  out.nanIsNull = (HT.corpusValueAt(r1, META.slots, 301) === null);
  out.zeroIsZero = (HT.corpusValueAt(r1, META.slots, 303) === 0);
  out.unknownNull = ((await HT.corpusLookup('nope')) === null);
  return JSON.stringify(out);
})()
'@
  # An exception INSIDE THE PAGE is the code failing, not the environment
  # failing. Exit 2 is for "could not run at all" -- no browser, no CDP, no
  # asset. Treating a page throw as an environment error let a planted defect
  # (two transactions instead of one) return NO VERDICT, which is the one
  # outcome a defect pass cannot read.
  $a = EvalAsync $script
  if ($a -like 'EXCEPTION*') { $fails += "the page threw: $a" }
  $A = if ($a -like 'EXCEPTION*') { [pscustomobject]@{} } else { $a | ConvertFrom-Json }

  if (-not $A.refused) { $fails += "a payload whose length is not rows x cols x 4 was ACCEPTED" }
  if (-not $A.nothingWritten) { $fails += "a refused install still wrote something -- there must be no half-corpus" }
  if (-not $A.installed) { $fails += "a well-formed corpus did not install" }
  if (-not $A.hydrated) { $fails += "the index did not hydrate to RAM" }
  if ($A.attribution -notlike '*FoodData Central*') { $fails += "the attribution did not travel with the data" }
  if ($A.rowLen -ne 3) { $fails += "a food row did not read back at its own key" }
  if ($A.v203 -ne 4 -or $A.v301 -ne 5) { $fails += "values did not survive the round trip" }
  if ($null -ne $A.v303) { $fails += "NaN did not survive as absence" }
  if (-not $A.nanIsNull) { $fails += "NaN read back as a number" }
  if (-not $A.zeroIsZero) { $fails += "ZERO read back as absence -- absence is never zero, and neither is zero absence" }
  if (-not $A.unknownNull) { $fails += "an unknown food returned a row instead of null" }

  # --- B: the REAL shipped asset, fetched and installed ---------------------
  $script2 = @'
(async function () {
  await new Promise(function (r) {
    const d = indexedDB.deleteDatabase(HT.CORPUS_DB);
    d.onsuccess = d.onerror = d.onblocked = function () { r(); };
  });
  const r = await HT.corpusAcquire(true);
  const st = HT.corpusState();
  const meta = await (await fetch('./corpus/dist/' + HT.corpusNamespace() + '.json')).json();
  const row = await HT.corpusLookup(meta.index[0][0]);
  return JSON.stringify({ ok: r.ok, why: r.why || '', ns: st.ns, rows: st.rows,
                          declared: meta.rows, cols: st.cols, declaredCols: meta.cols,
                          attribution: String(st.attribution || ''),
                          firstRowLen: row ? row.length : -1 });
})()
'@
  $b = EvalAsync $script2
  if ($b -like 'EXCEPTION*') { $fails += "the page threw on acquisition: $b" }
  $B = if ($b -like 'EXCEPTION*') { [pscustomobject]@{} } else { $b | ConvertFrom-Json }

  if (-not $B.ok) { $fails += "the real shipped corpus did not acquire (why=$($B.why))" }
  if ($B.rows -ne $B.declared) { $fails += "installed rows $($B.rows) != the $($B.declared) the encoder wrote" }
  if ($B.cols -ne $B.declaredCols) { $fails += "installed cols $($B.cols) != the declared $($B.declaredCols)" }
  if ($B.firstRowLen -ne $B.declaredCols) { $fails += "a row of the real corpus is not cols wide" }
  if ([string]::IsNullOrEmpty($B.attribution)) { $fails += "the real corpus carries no attribution" }

  Write-Host ("corpus: ns={0} rows={1} cols={2} (encoder declared {3}x{4})" -f $B.ns, $B.rows, $B.cols, $B.declared, $B.declaredCols)
  Write-Host ("        atomicity refused-and-clean={0}, NaN=absence={1}, zero=zero={2}" -f ($A.refused -and $A.nothingWritten), $A.nanIsNull, $A.zeroIsZero)
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}

Cleanup
if ($fails.Count -gt 0) {
  foreach ($f in $fails) { Write-Host "  FAIL: $f" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "GATE: PASS"
exit 0
