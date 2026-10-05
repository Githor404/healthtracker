# DELETE EVERYTHING -- one action, a confirm that says what goes, and nothing left.
#
# [[D157]] binds "the data stays the user's: local, exportable, DELETABLE". It was
# deletable per PART and not as a whole: clearDay() cleared one day and
# glucoseClear() one stream, so a user who wanted out had to clear day by day and
# the glucose cache separately. That is a door, not an exit.
#
# MEASURED, so the gate knows what "everything" is. All user data is in NINE
# localStorage keys:
#   healthtracker-log, -log-prerestore, -log-premigration, -products, -glucose,
#   -version, -scans, -trash, -byok
# IndexedDB holds ONLY the corpus (two stores, META and VALUES) and Cache Storage
# holds the shell. Neither contains anything about the user, which is why the
# corpus is KEPT and the confirm has to say so rather than leave it ambiguous.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8253
$Dbg = 9459
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-delall-" + [System.Guid]::NewGuid().ToString('N'))
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
}

try {
  Start-Sleep -Milliseconds 600
  $chrome = Start-Process -FilePath $browser -PassThru -ArgumentList @("--headless=new",
    "--remote-debugging-port=$Dbg", "--user-data-dir=$udd", "--no-first-run",
    "--no-default-browser-check", "--disable-gpu", "about:blank")
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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 1; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  $ready = $false
  for ($i = 0; $i -lt 100; $i++) {
    Start-Sleep -Milliseconds 200
    if ((Eval "(typeof window.HT === 'object' && typeof HT.boot === 'function') ? 1 : 0") -eq 1) { $ready = $true; break }
  }
  if (-not $ready) { Write-Host "ERROR: HT never appeared"; Cleanup; exit 2 }

  # ---- a tree with something in EVERY key, so "everything" is testable ----
  $seed = @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  HT.setClock(function () { return Date.parse('2026-09-26T14:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  const DK = '2026-09-26';
  const S = HT.state();
  S.days[DK] = { status: 'in_progress', water_l: 1.5, items: [
    { name: 'lentil stew', meal: 'lunch', time: '12:30', grams: 100, kcal: 200,
      protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 2, soluble_fiber_g: 0,
      confidence: 'eyeballed', source: 'ai-paste', notes: '' }] };
  S.current = DK;
  HT.resave();
  if (typeof HT.glucoseIngest === 'function') {
    HT.glucoseIngest([{ t: DK + 'T08:00:00-04:00', v: 5.4, unit: 'mmol/L' }],
                     { rawUnit: 'mmol/L', source: 'Dexcom G7' });
  }
  // Write every remaining owned key directly, so the census has a full tree.
  const K = HT.keys || {};
  const owned = ['healthtracker-log', 'healthtracker-log-prerestore',
    'healthtracker-log-premigration', 'healthtracker-products',
    'healthtracker-glucose', 'healthtracker-version', 'healthtracker-scans',
    'healthtracker-trash', 'healthtracker-byok'];
  owned.forEach(function (k) { if (!localStorage.getItem(k)) localStorage.setItem(k, '{}'); });
  HT.refresh(); await sleep(300);
  const present = owned.filter(function (k) { return localStorage.getItem(k) !== null; });
  return {
    owned: owned, presentBefore: present.length,
    hasPreview: typeof HT.deleteAllPreview === 'function',
    hasExecute: typeof HT.deleteAllExecute === 'function',
    control: document.querySelectorAll('#settingsPanel .delall, #settingsPanel [data-action=delete-all]').length
  };
})()
'@
  $r0 = EvalA $seed
  if ($r0 -like 'EXCEPTION*') { Write-Host "ERROR: seed threw: $r0"; Cleanup; exit 2 }
  $S0 = $r0 | ConvertFrom-Json

  Chk ($S0.presentBefore -eq 9) "the fixture seeded $($S0.presentBefore) of 9 owned keys, so 'everything was deleted' would be a claim about a partial tree (D96)"
  Chk ([bool]$S0.hasPreview) "HT.deleteAllPreview does not exist -- a destructive action with no preview cannot say what goes"
  Chk ([bool]$S0.hasExecute) "HT.deleteAllExecute does not exist"
  Chk ($S0.control -ge 1) "no delete-everything control in Settings. D157 binds the data to be DELETABLE, and clearDay/glucoseClear delete parts, not the whole"

  if (-not $S0.hasPreview -or -not $S0.hasExecute -or $S0.control -lt 1) {
    Write-Host "DELETE-ALL GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Write-Host "  (the action does not exist yet, so the rest of the gate cannot run)"
    Cleanup; exit 1
  }

  # ---- THE CONFIRM SAYS WHAT GOES, AND WHAT DOES NOT ---------------------
  $pv = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const p = HT.deleteAllPreview();
  const btn = document.querySelector('#settingsPanel .delall, #settingsPanel [data-action=delete-all]');
  if (btn) { btn.click(); await sleep(250); }
  const panel = document.querySelector('#settingsPanel');
  const txt = panel ? (panel.textContent || '').replace(/\s+/g, ' ') : '';
  return { preview: p, confirmText: txt,
           tokenShape: p && typeof p.token === 'string' && p.token.length > 0 };
})()
'@
  $PV = $pv | ConvertFrom-Json
  $ct2 = [string]$PV.confirmText
  Chk ([bool]$PV.tokenShape) "deleteAllPreview returns no token -- a destructive act should not be executable without one"
  Chk ($ct2 -match '(?i)export') "the confirm never mentions EXPORT: '$($ct2.Substring(0, [Math]::Min(160, $ct2.Length)))'. An export first is the only way back, and the user has to be told before the data is gone, not after"
  Chk ($ct2 -match '(?i)cannot be undone|no way back|permanent|gone for good|cannot be recovered') "the confirm never says the act is irreversible"
  Chk ($ct2 -match '(?i)corpus|food database|nutrient database') "the confirm says nothing about the corpus. D157's ruling is to state PLAINLY whether it is kept or removed, and silence is the one option the ruling excludes"
  Chk ($ct2 -match '(?i)glucose') "the confirm does not name the glucose cache, which is deleted and lives outside the export"

  # ---- CANCEL LEAVES EVERYTHING ------------------------------------------
  $cx = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const cancel = document.querySelector('#settingsPanel .delall-cancel, #settingsPanel [data-action=delete-all-cancel]');
  if (cancel) { cancel.click(); await sleep(200); }
  const owned = ['healthtracker-log', 'healthtracker-log-prerestore',
    'healthtracker-log-premigration', 'healthtracker-products',
    'healthtracker-glucose', 'healthtracker-version', 'healthtracker-scans',
    'healthtracker-trash', 'healthtracker-byok'];
  return { cancelFound: !!cancel,
           stillPresent: owned.filter(function (k) { return localStorage.getItem(k) !== null; }).length,
           refusedWithoutToken: (function () {
             try { const r = HT.deleteAllExecute('not-the-token'); return !(r && r.ok); }
             catch (e) { return true; }
           })() };
})()
'@
  $CX = $cx | ConvertFrom-Json
  Chk ([bool]$CX.cancelFound) "the confirm offers no way out -- a destructive confirm with no cancel is a trap"
  Chk ($CX.stillPresent -eq 9) "cancelling the confirm left only $($CX.stillPresent) of 9 keys -- a cancel that deletes anything is worse than no cancel"
  Chk ([bool]$CX.refusedWithoutToken) "deleteAllExecute ran with a WRONG token. The token is the only thing between a mis-tap and the whole log"

  # ---- AND THEN IT ACTUALLY DELETES EVERYTHING ---------------------------
  $dl = EvalA @'
(async function () {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const p = HT.deleteAllPreview();
  const out = HT.deleteAllExecute(p.token);
  await sleep(400);
  const owned = ['healthtracker-log', 'healthtracker-log-prerestore',
    'healthtracker-log-premigration', 'healthtracker-products',
    'healthtracker-glucose', 'healthtracker-version', 'healthtracker-scans',
    'healthtracker-trash', 'healthtracker-byok'];
  const left = owned.filter(function (k) { return localStorage.getItem(k) !== null; });
  const st = HT.state() || {};
  // Any OTHER healthtracker-* key is one the census did not know about.
  const strays = [];
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k && k.indexOf('healthtracker') === 0) strays.push(k);
  }
  return { ok: !!(out && out.ok), left: left, leftN: left.length, strays: strays,
           days: Object.keys(st.days || {}).length,
           glucoseDays: (function () { try { return Object.keys(HT.glucoseRead ? HT.glucoseRead() : {}).length; }
                                       catch (e) { return -1; } })(),
           corpusStillFetchable: await fetch('./corpus/dist/cnf.json', { method: 'HEAD' })
             .then(function (r) { return r.ok; }).catch(function () { return false; }) };
})()
'@
  $DL = $dl | ConvertFrom-Json
  Chk ([bool]$DL.ok) "deleteAllExecute with the right token did not report success"
  Chk ($DL.leftN -eq 0) "$($DL.leftN) owned key(s) survived the delete: $(@($DL.left) -join ', ')"
  Chk (@($DL.strays).Count -eq 0) "localStorage still holds healthtracker key(s) the nine-key census does not know about: $(@($DL.strays) -join ', '). A census that misses a key leaves data behind while reporting none"
  Chk ($DL.days -eq 0) "the in-memory state still holds $($DL.days) day(s) -- clearing storage without clearing memory means the next save writes it all back"
  Chk ($DL.glucoseDays -eq 0) "the glucose cache still holds $($DL.glucoseDays) day(s) after a delete that claimed everything"
  Chk ([bool]$DL.corpusStillFetchable) "the corpus is no longer fetchable. It is a shipped ASSET containing nothing about the user, so it is KEPT by ruling -- and re-downloading it would cost bandwidth for no privacy gain"

  if ($fails.Count) {
    Write-Host "DELETE-ALL GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "DELETE-ALL GATE: PASS -- one action clears all nine owned localStorage keys, the glucose cache and the in-memory state, leaving no stray healthtracker key; a wrong token is refused; cancel leaves all nine intact; and the confirm names the glucose cache, says the act is irreversible, tells the user an export is the only way back, and states plainly that the corpus is kept."
  Write-Host "  THE CORPUS IS KEPT, deliberately: it lives in IndexedDB (two stores, META and VALUES), holds nothing about the user, and is re-fetchable from the origin. Cache Storage holds the shell for the same reason."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
