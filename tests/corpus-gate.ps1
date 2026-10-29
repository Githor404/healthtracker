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
#      count matches what the encoder wrote -- for BOTH namespaces, with the
#      Canadian one driven under a real en-CA locale override. The gate FAILS if
#      the override did not take, because a gate that silently tests the default
#      while claiming the override is worse than no gate at all.
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
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  return $r.result.result.value
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
  # R221/5: KILL the server job's process, then remove the job. Stop-Job waited 120 s on a job
  # blocked in GetContext() -- in every gate, ~88 min of a 100 min sweep spent holding memory.
  try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

$fails = @()
try {
  WaitServer "$origin/index.html"
  $args = @("--headless=new", "--disable-extensions", "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-features=Translate,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess,AutofillServerCommunication,CalculateNativeWinOcclusion", "--mute-audio", "--remote-debugging-port=$dbg", "--user-data-dir=$udd",
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
  Invoke-CDP 'Page.addScriptToEvaluateOnNewDocument' @{ source = $HT_QUIET_JS } | Out-Null   # R283
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Network.enable' $null | Out-Null
  MarkOld
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  WaitBoot

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
  $av = EvalAsync $script
  if ($av -like 'EXCEPTION*') { $fails += "the page threw: $av" }
  $A = if ($av -like 'EXCEPTION*') { [pscustomobject]@{} } else { $av | ConvertFrom-Json }

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

  # --- B: the REAL shipped asset, for EACH namespace ------------------------
  # Locale selects the SOURCE NAMESPACE (D114), so the Canadian path has to be
  # driven under a Canadian locale rather than assumed to work because the
  # default one did.
  $seen = @{}
  foreach ($case in @(@{ locale = ''; expect = 'fdc' }, @{ locale = 'en-CA'; expect = 'cnf' })) {
    $loc = $case.locale
    $want = $case.expect
    # Emulation.setLocaleOverride moves Intl but NOT navigator.language, which is
    # what corpusNamespace() reads -- measured: with it, both cases ran fdc and
    # the gate said so. Network.setUserAgentOverride's acceptLanguage is the one
    # that moves navigator.language.
    $ua = Eval 'navigator.userAgent'
    if ($loc -ne '') {
      try { Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua; acceptLanguage = $loc } | Out-Null }
      catch { $fails += "could not set the locale to $loc -- the Canadian path was NOT exercised"; continue }
    } else {
      try { Invoke-CDP 'Network.setUserAgentOverride' @{ userAgent = $ua; acceptLanguage = 'en-US' } | Out-Null } catch { }
    }
    MarkOld
    Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
    WaitBoot

    $script2 = @'
(async function () {
  await new Promise(function (r) {
    const d = indexedDB.deleteDatabase(HT.CORPUS_DB);
    d.onsuccess = d.onerror = d.onblocked = function () { r(); };
  });
  const lang = String((navigator && navigator.language) || '');
  const ns = HT.corpusNamespace();
  const r = await HT.corpusAcquire(true);
  const st = HT.corpusState();
  const meta = await (await fetch('./corpus/dist/' + ns + '.json')).json();
  const row = await HT.corpusLookup(meta.index[0][0]);
  return JSON.stringify({ lang: lang, ns: ns, ok: r.ok, why: r.why || '',
                          rows: st.rows, declared: meta.rows,
                          cols: st.cols, declaredCols: meta.cols,
                          attribution: String(st.attribution || ''),
                          firstRowLen: row ? row.length : -1 });
})()
'@
    $bv = EvalAsync $script2
    if ($bv -like 'EXCEPTION*') { $fails += "the page threw on acquisition ($want): $bv"; continue }
    $B = $bv | ConvertFrom-Json
    $seen[$want] = $B

    # THE LOAD-BEARING ASSERTION: the override must have actually taken. Without
    # this the en-CA case would quietly re-run the default one and report PASS.
    if ($want -eq 'cnf' -and ($B.lang -notlike '*CA*')) {
      $fails += "the en-CA override did not take (navigator.language='$($B.lang)') -- the Canadian path was NOT exercised"
    }
    if ($B.ns -ne $want) { $fails += "locale '$loc' selected namespace '$($B.ns)', expected '$want'" }
    if (-not $B.ok) { $fails += "[$want] the real corpus did not acquire (why=$($B.why))" }
    if ($B.rows -ne $B.declared) { $fails += "[$want] installed rows $($B.rows) != the $($B.declared) the encoder wrote" }
    if ($B.cols -ne $B.declaredCols) { $fails += "[$want] installed cols $($B.cols) != declared $($B.declaredCols)" }
    if ($B.firstRowLen -ne $B.declaredCols) { $fails += "[$want] a row of the real corpus is not cols wide" }
    if ([string]::IsNullOrEmpty($B.attribution)) { $fails += "[$want] the real corpus carries no attribution" }
  }
  # The two namespaces must be DIFFERENT corpora, or the locale switch did
  # nothing observable and both cases were the same test run twice.
  if ($seen.ContainsKey('fdc') -and $seen.ContainsKey('cnf') -and
      $seen['fdc'].rows -eq $seen['cnf'].rows) {
    $fails += "both namespaces reported the same row count -- the locale switch selected the same corpus twice"
  }

  foreach ($k in @('fdc', 'cnf')) {
    if ($seen.ContainsKey($k)) {
      Write-Host ("corpus[{0}]: lang='{1}' rows={2} cols={3} (encoder declared {4}x{5})" -f `
        $k, $seen[$k].lang, $seen[$k].rows, $seen[$k].cols, $seen[$k].declared, $seen[$k].declaredCols)
    }
  }
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
