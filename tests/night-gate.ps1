# H26 -- NIGHT PATTERNS: the shape with no label, and two flag arms that must be
# told apart.
#
# RULED (user, 2026-10-06):
#   A       ship the SHAPE with NO LABEL -- fall rate, trough, recovery rate,
#           duration. A description claims nothing; "possible compression low" is a
#           claim the data cannot yet support.
#   D       the clinician summary is available ON DEMAND AT ANY TIME. The app FLAGS
#           (never alerts) any night with a reading below 3.0 (consensus level 2,
#           cited), OR two or more nights with readings below 3.9.
#   B       one night is 21:00 -> 09:00, keyed by the evening, STATED on the surface.
#   C       "which side did you sleep on" is asked ONLY when a flag appears, never
#           daily -- so its ABSENCE on a clean night is gated too.
#   E       the fingerstick sentence lives on the flag ITSELF and in the summary,
#           never once in Settings.
#   F       the no-alarms statement sits wherever a low is shown: this is a 3-hour
#           look-back and the Dexcom app is the live safety tool.
#   first   the first line states HOW MANY NIGHTS it has.
#
# THE TWO FLAG ARMS ARE DIFFERENT SHAPES, and the fixture is built to tell them
# apart rather than to satisfy both at once:
#   arm 1 is PER NIGHT     -- one sub-3.0 reading flags that night, on its own
#   arm 2 is A RECURRENCE  -- two or more nights carrying sub-3.9 readings
# So ONE night with a single sub-3.9 reading and nothing below 3.0 must NOT flag.
# That negative is the case that proves these are thresholds and not "any low".
#
# MEASURED ON THE REAL READINGS (451, 2026-09-30 -> 10-02): three readings below
# 3.9 and one below 3.0, ALL ON ONE NIGHT. So the real data fires arm 1 and NOT
# arm 2 -- which is exactly why the two must not be collapsed.
#
# Fixture-synthetic forever (CLAUDE.md): no export is read; glucose is seeded
# through the real ingest path.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8271
$Dbg = 9477
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-night-" + [System.Guid]::NewGuid().ToString('N'))
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
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }
  # Report the exception rather than returning an empty string: a probe with a
  # syntax error otherwise reports only "would not start", which cost a diagnosis
  # on the H25 gate.
  if ($r.result.exceptionDetails) {
    return 'EXCEPTION: ' + $r.result.exceptionDetails.text + ' | ' + $r.result.exceptionDetails.exception.description
  }
  return $r.result.result.value
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $Port -ScriptBlock {
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
function Chk([bool]$ok, [string]$msg) { if (-not $ok) { $script:fails += $msg } }

try {
  Start-Sleep -Milliseconds 600
  $chromeArgs = @("--headless=new", "--remote-debugging-port=$Dbg", "--user-data-dir=$udd",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu", "about:blank")
  $chrome = Start-Process -FilePath $browser -ArgumentList $chromeArgs -PassThru
  $tabUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 400
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$Dbg/json" -TimeoutSec 3
      $page = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($page) { $tabUrl = $page.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $tabUrl) { Write-Host "ERROR: CDP never came up"; Cleanup; exit 2 }

  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$tabUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $sane = Eval "typeof HT"
  if ($sane -ne 'object') { Write-Host "ERROR: the page did not load (typeof HT = $sane)"; Cleanup; exit 2 }

  $probe = @'
window.__out = null;
window.__stage = 'start';
(async function () {
  const O = { boundary: {}, shape: {}, arm1: {}, arm2: {}, clean: {}, words: {}, sensor: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const stage = (s) => { window.__stage = s; O.stage = s; try { document.title = 'STAGE:' + s; } catch (e) {} };
  try {
  HT.setClock(function () { return Date.parse('2026-09-20T12:00:00-04:00'); });
  localStorage.clear();
  HT.boot();
  await sleep(250);

  // ---- a tiny glucose seeder, by (evening key, minute-of-night, value) ----
  // minutes run from 21:00 of the evening, so 0 = 21:00 and 600 = 07:00 next day.
  function seed(rows) {
    const out = [];
    rows.forEach(function (r) {
      const ev = r[0], mins = r[1], v = r[2];
      const base = Date.parse(ev + 'T21:00:00-04:00') + mins * 60000;
      const d = new Date(base);
      const pad = (n) => String(n).padStart(2, '0');
      const t = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
        + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':00-04:00';
      out.push({ t: t, v: v, unit: 'mmol/L' });
    });
    return HT.glucoseIngest(out, { source: 'fixture' });
  }
  function flat(ev, from, to, v, step) {
    const rows = [];
    for (let m = from; m <= to; m += (step || 5)) rows.push([ev, m, v]);
    return rows;
  }

  // ---- PHASE A: ONE night with a single sub-3.9 reading, nothing sub-3.0 --
  // Neither arm may fire: arm 1 needs a sub-3.0 reading, arm 2 needs TWO nights.
  // This negative is what proves these are thresholds and not "any low".
  stage('phase-A');
  let rows = flat('2026-09-12', 0, 700, 5.5);
  rows = rows.concat([['2026-09-12', 360, 3.6]]);     // 03:00, below 3.9 only
  seed(rows);
  O.arm2.nightsAfterOne = HT.nightCount();
  const fA = HT.lowFlagState();
  O.arm2.flaggedAfterOne = fA.flagged;
  O.arm2.whyAfterOne = String(fA.why || '');

  // ---- PHASE B: a SECOND such night -> arm 2 fires ----------------------
  stage('phase-B');
  let rowsB = flat('2026-09-13', 0, 700, 5.4);
  rowsB = rowsB.concat([['2026-09-13', 400, 3.5]]);   // 03:40, below 3.9 only
  seed(rowsB);
  const fB = HT.lowFlagState();
  O.arm2.flaggedAfterTwo = fB.flagged;
  O.arm2.whyAfterTwo = String(fB.why || '');
  O.arm2.arm = String(fB.arm || '');
  O.arm2.nights = (fB.nights || []).slice().sort();
  O.arm2.nightCount = HT.nightCount();

  // ---- PHASE C: a night with a sub-3.0 reading -> arm 1, on its own -----
  stage('phase-C');
  localStorage.clear(); HT.boot(); await sleep(200);
  // a real shape: flat, a fall to a trough, a recovery -- numbers chosen in advance
  // 21:00 .. 02:00 flat 5.0 ; fall to 2.8 at 03:00 ; recover to 5.0 at 04:00
  let rowsC = flat('2026-09-10', 0, 300, 5.0);              // 21:00 -> 02:00
  for (let m = 305; m <= 360; m += 5) {                      // 02:05 -> 03:00 falling
    const f = (m - 300) / 60;
    rowsC.push(['2026-09-10', m, Math.round((5.0 + (2.8 - 5.0) * f) * 10) / 10]);
  }
  for (let m = 365; m <= 420; m += 5) {                      // 03:05 -> 04:00 recovering
    const f = (m - 360) / 60;
    rowsC.push(['2026-09-10', m, Math.round((2.8 + (5.0 - 2.8) * f) * 10) / 10]);
  }
  rowsC = rowsC.concat(flat('2026-09-10', 425, 700, 5.0));
  seed(rowsC);
  const fC = HT.lowFlagState();
  O.arm1.flagged = fC.flagged;
  O.arm1.arm = String(fC.arm || '');
  O.arm1.why = String(fC.why || '');
  O.arm1.nights = (fC.nights || []).slice();
  O.arm1.nightCount = HT.nightCount();

  // the SHAPE, with no label (ruled A)
  stage('shape');
  const sh = HT.nightShape('2026-09-10');
  O.shape.n = sh.n;
  O.shape.lowest = sh.lowest && sh.lowest.v;
  O.shape.lowestAt = sh.lowest && sh.lowest.at;
  O.shape.fallRate = sh.fallRate;
  O.shape.recoveryRate = sh.recoveryRate;
  O.shape.minutesBelow = sh.minutesBelowL1;
  O.shape.keys = Object.keys(sh).sort();
  O.shape.html = String(HT.nightShapeHTML('2026-09-10') || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();

  // the boundary (ruled B): a reading at 08:55 belongs to the PREVIOUS evening
  stage('boundary');
  O.boundary.window = HT.nightWindowWords();
  O.boundary.lateKey = HT.nightKeyFor(Date.parse('2026-09-11T08:55:00-04:00'));
  O.boundary.earlyKey = HT.nightKeyFor(Date.parse('2026-09-10T21:05:00-04:00'));
  O.boundary.outsideKey = HT.nightKeyFor(Date.parse('2026-09-11T20:55:00-04:00'));

  // ---- the SENTENCES, wherever a low is shown (rulings E and F) ---------
  stage('words');
  const flagHTML = String(HT.lowFlagHTML() || '');
  const flagText = flagHTML.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
  O.words.flagText = flagText.slice(0, 400);
  O.words.flagFingerstick = /fingerstick/i.test(flagText);
  O.words.flagNoAlarms = /(3[- ]hour look[- ]back|look[- ]back)/i.test(flagText) && /Dexcom/i.test(flagText);
  O.words.flagHasNoAlertWord = !/\balert(s|ed|ing)?\b|\balarm(s|ed|ing)?\b(?! )/i.test(flagText.replace(/no alarms?/ig, '').replace(/never alerts?/ig, ''));
  const sumText = String(HT.clinicianSummaryHTML() || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
  O.words.sumText = sumText.slice(0, 500);
  O.words.sumFingerstick = /fingerstick/i.test(sumText);
  O.words.sumHasDates = /2026-09-10/.test(sumText);
  O.words.sumHasLowest = /2\.8/.test(sumText);
  O.words.sumAvailable = sumText.length > 40;
  // the first line states how many nights (ruled)
  O.words.nightsStated = /\b1 night\b/.test(sumText) || /\b1 night\b/.test(flagText)
    || /\b1 night\b/.test(String(HT.nightPanelHTML() || '').replace(/<[^>]*>/g, ' '));
  const panelText = String(HT.nightPanelHTML() || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
  O.words.panelText = panelText.slice(0, 300);
  O.words.panelStatesWindow = /21:00/.test(panelText) && /09:00/.test(panelText);

  // RULING A's TEETH: no label word anywhere in the shape or the flag
  const LABELS = /compress|suspect|possible|likely|probabl|artefact|artifact/i;
  O.words.shapeHasNoLabel = !LABELS.test(O.shape.html);
  O.words.flagHasNoLabel = !LABELS.test(flagText);
  O.words.labelControl = LABELS.test('possible compression low');

  // ---- the sleep-side question: ONLY on a flagged night (ruled C) -------
  stage('sleep-side');
  O.arm1.sideAsk = String(HT.sleepSideAskHTML('2026-09-10') || '').length > 0;
  const sideRes = HT.logSleepSide('2026-09-10', 'left');
  O.arm1.sideLogged = !!(sideRes && sideRes.ok);
  const tl = HT.state().timeline;
  let sideRec = null;
  Object.keys(tl).forEach(function (d) {
    (tl[d] || []).forEach(function (e) { if (e.type === 'sleep_side') sideRec = e; });
  });
  O.arm1.sideVariant = sideRec ? String(sideRec.variant || '') : '';

  // ---- PHASE D: a CLEAN night -> no flag, and NO sleep-side question ----
  stage('phase-D');
  localStorage.clear(); HT.boot(); await sleep(200);
  seed(flat('2026-09-15', 0, 700, 5.2));
  const fD = HT.lowFlagState();
  O.clean.flagged = fD.flagged;
  O.clean.nightCount = HT.nightCount();
  O.clean.sideAsk = String(HT.sleepSideAskHTML('2026-09-15') || '').length;
  O.clean.flagHTML = String(HT.lowFlagHTML() || '').length;
  // the summary is ON DEMAND AT ANY TIME (ruled D), including with no flag
  O.clean.sumAvailable = String(HT.clinicianSummaryHTML() || '').replace(/<[^>]*>/g, ' ').trim().length > 20;
  // and the shape still renders -- a description claims nothing, so it is not
  // gated on a flag
  O.clean.shapeRenders = String(HT.nightShapeHTML('2026-09-15') || '').length > 0;

  // ---- the sensor arm, through the mechanism H25 built ------------------
  stage('sensor');
  O.sensor.declared = (HT.QUICK_EVENTS || []).map(q => q.id).sort();
  const sres = HT.quickEvent('sensor', 'left arm');
  O.sensor.ok = !!(sres && sres.ok);
  const today = HT.localDate();
  const srec = (HT.state().timeline[today] || []).filter(e => e.type === 'sensor')[0];
  O.sensor.type = srec ? String(srec.type) : '';
  O.sensor.variant = srec ? String(srec.variant || '') : '';
  O.sensor.source = srec ? String(srec.source || '') : '';

  stage('done');
  } catch (e) {
    O.threw = String((e && e.message) || e) + ' @ ' + window.__stage;
  }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  $kick = Eval $probe
  if ($kick -ne '1') { $fails += "the probe would not start: $kick" }
  $r = $null
  for ($w = 0; $w -lt 120; $w++) {
    Start-Sleep -Milliseconds 500
    $r = Eval 'window.__out'
    if ($r) { break }
  }
  if (-not $r) {
    $st = Eval 'String(window.__stage)'
    $fails += "the probe HUNG after 60s -- last stage reached: '$st'"
    $R = [pscustomobject]@{}
  } else { $R = $r | ConvertFrom-Json }
  if ($R.threw) { $fails += "the probe threw: $($R.threw)" }

  $B = $R.boundary; $S = $R.shape; $A1 = $R.arm1; $A2 = $R.arm2; $CL = $R.clean; $W = $R.words; $SN = $R.sensor

  # --- ruled B: the night window, and the surface says what it is ----------
  Chk ($B.window -match '21:00' -and $B.window -match '09:00') "the night window is not stated as 21:00 -> 09:00 (got '$($B.window)')"
  Chk ($B.lateKey -eq '2026-09-10') "a reading at 08:55 keys to night '$($B.lateKey)' -- a night is keyed by its EVENING, so it belongs to 2026-09-10"
  Chk ($B.earlyKey -eq '2026-09-10') "a reading at 21:05 keys to night '$($B.earlyKey)', not its own evening"
  Chk ([string]::IsNullOrEmpty($B.outsideKey)) "a reading at 20:55 was placed in night '$($B.outsideKey)' -- it falls outside the window and belongs to NO night"
  Chk ($W.panelStatesWindow -eq $true) "the surface does not state the 21:00-09:00 boundary ('$($W.panelText)') -- ruled, because 'the lowest value of the night' changes with it"

  # --- arm 2 is a RECURRENCE, and one night must not satisfy it ------------
  Chk ($A2.nightsAfterOne -eq 1) "one seeded night counted as $($A2.nightsAfterOne)"
  Chk ($A2.flaggedAfterOne -eq $false) "ONE night with a single sub-3.9 reading and nothing below 3.0 was FLAGGED ('$($A2.whyAfterOne)') -- arm 2 needs two or more nights, and arm 1 needs a sub-3.0 reading. This negative is what makes the two arms real thresholds rather than 'any low'"
  Chk ($A2.flaggedAfterTwo -eq $true) "a SECOND night with a sub-3.9 reading did not raise the flag -- ruled: two or more nights with readings below 3.9"
  Chk ($A2.arm -eq 'recurrence') "the fired arm is reported as '$($A2.arm)', not 'recurrence' -- which arm fired is the difference between one bad night and a pattern"
  Chk (($A2.nights -join ',') -eq '2026-09-12,2026-09-13') "the flag names nights '$($A2.nights -join ',')' rather than both nights that carry the readings"
  Chk ($A2.whyAfterTwo -match '3\.9') "the recurrence reason does not cite 3.9 ('$($A2.whyAfterTwo)')"

  # --- arm 1 fires on ONE night, alone ------------------------------------
  Chk ($A1.flagged -eq $true) "a night with a reading below 3.0 was not flagged"
  Chk ($A1.nightCount -eq 1) "arm 1 fired with $($A1.nightCount) night(s) of data, which is right, but the count is wrong"
  Chk ($A1.arm -eq 'level2') "the fired arm is '$($A1.arm)', not 'level2' -- a sub-3.0 reading is the consensus level-2 value and flags on its own"
  Chk ($A1.why -match '3\.0') "the level-2 reason does not cite 3.0 ('$($A1.why)')"

  # --- ruled A: the SHAPE, with numbers and NO LABEL ----------------------
  Chk ($S.lowest -eq 2.8) "the trough is $($S.lowest), not the 2.8 the fixture was built with"
  Chk ($S.lowestAt -match '03:00') "the trough is reported at '$($S.lowestAt)', not 03:00"
  Chk ($null -ne $S.fallRate) "the shape reports no FALL RATE -- ruled A ships the shape, which is fall rate, trough, recovery rate and duration"
  Chk ($null -ne $S.recoveryRate) "the shape reports no RECOVERY RATE"
  Chk ($null -ne $S.minutesBelow) "the shape reports no DURATION below the threshold"
  Chk ([double]$S.fallRate -lt 0) "the fall rate is $($S.fallRate) -- a fall is negative, and a sign error here would read as a rise"
  Chk ([double]$S.recoveryRate -gt 0) "the recovery rate is $($S.recoveryRate) -- a recovery is positive"
  Chk ($W.labelControl -eq $true) "the label matcher does not match 'possible compression low', so the two checks below prove nothing (D96)"
  Chk ($W.shapeHasNoLabel -eq $true) "the shape surface carries a LABEL word ('$($S.html)') -- ruled A: a description claims nothing, and 'possible compression low' is a claim the data cannot support"
  Chk ($W.flagHasNoLabel -eq $true) "the flag carries a LABEL word ('$($W.flagText)')"

  # --- rulings E and F: the sentences, wherever a low is shown -------------
  Chk ($W.flagFingerstick -eq $true) "the FLAG does not carry the fingerstick sentence ('$($W.flagText)') -- ruled E: a safety sentence the user has to go and find is a safety sentence that was not said"
  Chk ($W.sumFingerstick -eq $true) "the clinician summary does not carry the fingerstick sentence"
  Chk ($W.flagNoAlarms -eq $true) "the flag does not say this is a look-back and that the Dexcom app is the live safety tool ('$($W.flagText)')"

  # --- ruled: the first line states how many nights -----------------------
  Chk ($W.nightsStated -eq $true) "no surface states HOW MANY NIGHTS it has -- ruled, and it is the figure that stops 'most days' being answered by two nights"

  # --- ruled D: the summary is ON DEMAND AT ANY TIME ----------------------
  Chk ($W.sumAvailable -eq $true) "the clinician summary is empty on a flagged log"
  Chk ($W.sumHasDates -eq $true) "the summary does not list the DATE of the night ('$($W.sumText)')"
  Chk ($W.sumHasLowest -eq $true) "the summary does not list the LOWEST value"
  Chk ($CL.sumAvailable -eq $true) "the clinician summary is NOT available on a clean log -- ruled D: available on demand AT ANY TIME, so no threshold gates reaching it"

  # --- ruled C: no flag, no question ------------------------------------
  Chk ($CL.flagged -eq $false) "a clean night was flagged"
  Chk ($CL.flagHTML -eq 0) "a clean log renders a flag surface ($($CL.flagHTML) chars) -- nothing to flag means nothing shown"
  Chk ($A1.sideAsk -eq $true) "a FLAGGED night does not ask which side you slept on -- ruled C makes it the flag's follow-up"
  Chk ($CL.sideAsk -eq 0) "a CLEAN night asks which side you slept on ($($CL.sideAsk) chars) -- ruled C: only when a flag appears, NEVER daily"
  Chk ($A1.sideLogged -eq $true) "the sleep-side answer did not record"
  Chk ($A1.sideVariant -eq 'left') "the sleep side recorded as '$($A1.sideVariant)' -- it rides the same variant field as the drink, because notes is free text and parsing it would be an inference"
  Chk ($CL.shapeRenders -eq $true) "the shape does not render on an unflagged night -- a description claims nothing, so it is not gated on a flag"

  # --- the sensor arm, through the mechanism H25 built --------------------
  Chk (($SN.declared -join ',') -eq 'drink,moved,sensor,woke') "QUICK_EVENTS declares '$($SN.declared -join ',')' -- the sensor arm joins the SAME mechanism as a fourth kind rather than getting one of its own"
  Chk ($SN.ok -eq $true) "the sensor tap did not record"
  Chk ($SN.type -eq 'sensor') "the sensor event landed as type '$($SN.type)'"
  Chk ($SN.variant -eq 'left arm') "the sensor arm recorded as '$($SN.variant)' -- asked once per sensor, and it must be readable without parsing prose"
  Chk ($SN.source -eq 'quick') "the sensor event records source '$($SN.source)', not 'quick'"
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "NIGHT GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "NIGHT GATE: PASS -- the night is 21:00-09:00 keyed by its evening and the surface says so; one night with a single sub-3.9 reading is NOT flagged while a sub-3.0 reading flags alone and two such nights flag as a recurrence; the shape ships with fall rate, trough, recovery rate and duration and NO label word; the fingerstick and look-back sentences ride with every low; the summary is reachable with or without a flag; the sleep-side question appears only behind a flag; and the sensor arm joins the one-tap mechanism as a fourth kind"
Write-Host "GATE: PASS"
exit 0
