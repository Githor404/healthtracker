# R138 + R159.1 ruling F -- THE DAY THE APP SHOWS, AND THE DAY A DRAFT LANDS ON.
#
# R138 existed only as a queue position in the decision log; this is its first
# specification.
#
# MEASURED FIRST, AND IT MOVED THE FIX. `ensureCurrentDay` ALREADY forces
# `current = today` at boot and at restore, so BOOT WAS NEVER BROKEN. The only
# `visibilitychange` handler in the app asks the SERVICE WORKER to re-check for an
# update -- nothing re-checked the calendar day. So a PWA left open or resumed from
# the app switcher after midnight showed yesterday AND LOGGED TO YESTERDAY, which
# makes it a data defect and not only a view one. Fixed where it was assumed to be,
# the change would have landed in a function that was already correct.
#
# RULED (user, 2026-10-09):
#   R138  fix on resume -- visibilitychange re-checks the calendar day.
#   F     a draft lands on the day it was STARTED, never retargeted when the date
#         flips.
#
# AND THE TIME HAD TO TRAVEL WITH IT. `stampTime(dayKey)` returns '' for any day
# that is not today (D112: no fabricated clock time on a past day), so a draft
# opened at 23:50 and saved at 00:05 landed on the right day with NO TIME -- out of
# the timeline's sort, with a blank row. 23:50 is MEASURED, so carrying it satisfies
# D112 rather than bypassing it.
#
# THE FIRST ATTEMPT PATCHED A DEAD PATH. `photoSave` builds `written` with a time,
# and six lines below says "R33: `written` above is no longer what reaches the day".
# The items come from `consumeFromPlate`, whose own comment had anticipated the
# mistake: "APP_STATE.current here would fabricate a time again, one argument
# along."
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8289
$Dbg = 9495
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$udd = Join-Path $env:TEMP ("ht-dayroll-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 360; height = 740; deviceScaleFactor = 2; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 3000

  $sane = Eval "typeof HT"
  if ($sane -ne 'object') { Write-Host "ERROR: the page did not load (typeof HT = $sane)"; Cleanup; exit 2 }

  # THE RESUME LISTENER IS IN index.html, NOT app.js, so it is asserted as SHIPPED
  # TEXT as well as behaviourally: a handler that exists only in a gate's own call
  # is a handler the device does not have.
  $wired = Eval "(function () { return String(document.documentElement.innerHTML).indexOf('HT.dayRollCheck') >= 0; })()"
  Chk ($wired -eq $true) "nothing in the shipped page calls HT.dayRollCheck -- the function can exist and still never run on a resume, which is the defect this slice is about"

  $probe = @'
window.__out = null;
window.__stage = 'start';
(async function () {
  const O = { api: {}, roll: {}, draft: {}, boot: {} };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const stage = (x) => { window.__stage = x; O.stage = x; };
  try {
  stage('boot');
  HT.setClock(function () { return Date.parse('2026-10-09T14:30:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(250);
  O.api.dayRollCheck = typeof HT.dayRollCheck;
  O.api.dayForWriteKey = typeof HT.dayForWriteKey;
  O.boot.landedToday = (String(HT.state().current) === '2026-10-09');

  // A day with something in it, so moving off it is observable.
  const S = HT.state();
  S.days['2026-10-09'] = { status: 'in_progress', water_l: 0, items: [ {
    name: 'lunch thing', meal: 'lunch', time: '12:00', grams: 100, kcal: 200,
    protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 1, soluble_fiber_g: 0,
    confidence: 'eyeballed', source: 'manual', notes: '' } ] };
  HT.Store.saveState(S);
  HT.refresh();
  await sleep(250);

  // ---- R138: a resume on a NEW calendar day lands on today ---------------
  stage('roll');
  HT.setClock(function () { return Date.parse('2026-10-10T09:00:00-04:00'); });
  O.roll.before = String(HT.state().current);
  O.roll.result = JSON.stringify(HT.dayRollCheck());
  O.roll.after = String(HT.state().current);
  O.roll.moved = (O.roll.before === '2026-10-09' && O.roll.after === '2026-10-10');
  // the old day is NOT disturbed -- moving the view must not touch the record
  O.roll.oldDayKept = ((HT.state().days['2026-10-09'] || {}).items || []).length;
  // IDEMPOTENT: a second resume on the same day reports no move
  const again = HT.dayRollCheck();
  O.roll.secondMoved = !!(again && again.moved);
  O.roll.stable = (String(HT.state().current) === '2026-10-10');

  // ---- RULING F: a draft keeps the day it was STARTED -------------------
  stage('draft');
  HT.setClock(function () { return Date.parse('2026-10-10T23:50:00-04:00'); });
  HT.dayRollCheck();
  O.draft.startedOn = String(HT.state().current);
  const reply = JSON.stringify({ meal: 'snack', items: [ { name: 'late toast',
    alts: [ { name: 'late toast', p: 1 } ], grams: 60,
    per100: { kcal: 300, protein_g: 9, fat_g: 4, carb_g: 55, fiber_g: 3, soluble_fiber_g: 0 },
    scale_linked: true, dominance: 1, notes: '' } ] });
  const op = HT.openPhotoDraft(reply);
  O.draft.opened = !!(op && op.ok);
  const dr = HT.photoDraft();
  // BEFORE any roll the draft claims NO day of its own -- it only records where it
  // started. Taking a day at open could not tell a date flip from the user
  // navigating, and D112's harness case asserts the user's navigation wins.
  O.draft.startedDay = dr ? String(dr.startedDay || 'MISSING') : 'no draft';
  O.draft.startedTime = dr ? String(dr.startedTime || 'MISSING') : 'no draft';
  O.draft.unpinnedAtOpen = dr ? (dr.dayKey == null) : null;

  // midnight passes WHILE the draft is open, and a resume happens
  HT.setClock(function () { return Date.parse('2026-10-11T00:05:00-04:00'); });
  HT.dayRollCheck();
  O.draft.currentNow = String(HT.state().current);
  const dr2 = HT.photoDraft();
  O.draft.keyAfterRoll = dr2 ? String(dr2.dayKey || 'MISSING') : 'no draft';
  O.draft.pinnedTime = dr2 ? String(dr2.pinnedTime || 'MISSING') : 'no draft';
  O.draft.stillOpen = !!dr2;

  const sr = HT.photoSave();
  O.draft.saved = JSON.stringify(sr).slice(0, 180);
  const d10 = ((HT.state().days['2026-10-10'] || {}).items || []);
  const d11 = ((HT.state().days['2026-10-11'] || {}).items || []);
  const mine = d10.filter(function (x) { return /late toast/.test(String(x.name || '')); })[0];
  O.draft.landedOn10 = !!mine;
  O.draft.landedOn11 = d11.some(function (x) { return /late toast/.test(String(x.name || '')); });
  O.draft.timeKept = mine ? String(mine.time || '') : '';

  // ---- THE DISTINCTION THE FIRST DESIGN MISSED: the USER moving the day ----
  // Ruled F is about the date FLIPPING. A user who navigates to another day while
  // a draft is open is making a deliberate choice -- "log this onto last Tuesday"
  // -- and D112's harness case asserts that choice is honoured, with no time,
  // because today's clock on a past day is a fabrication.
  stage('navigate');
  HT.setClock(function () { return Date.parse('2026-10-11T12:00:00-04:00'); });
  HT.dayRollCheck();
  HT.photoDiscard();
  HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: [ { name: 'tuesday thing',
    alts: [ { name: 'tuesday thing', p: 1 } ], grams: 100,
    per100: { kcal: 200, protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 1, soluble_fiber_g: 0 },
    scale_linked: true, dominance: 1, notes: '' } ] }));
  // the USER navigates -- no clock change, so no pin
  HT.state().current = '2026-10-04';
  if (!HT.state().days['2026-10-04']) HT.state().days['2026-10-04'] = { status: 'in_progress', water_l: 0, items: [] };
  HT.photoSave();
  const past = ((HT.state().days['2026-10-04'] || {}).items || [])
    .filter(function (x) { return /tuesday thing/.test(String(x.name || '')); })[0];
  O.draft.navLanded = !!past;
  O.draft.navTime = past ? String(past.time || '') : 'MISSING';

  // ---- and a draft started TODAY still behaves exactly as before --------
  stage('sameday');
  HT.setClock(function () { return Date.parse('2026-10-11T12:00:00-04:00'); });
  HT.dayRollCheck();
  HT.photoDiscard();
  HT.openPhotoDraft(JSON.stringify({ meal: 'lunch', items: [ { name: 'noon thing',
    alts: [ { name: 'noon thing', p: 1 } ], grams: 100,
    per100: { kcal: 200, protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 1, soluble_fiber_g: 0 },
    scale_linked: true, dominance: 1, notes: '' } ] }));
  HT.photoSave();
  const d11b = ((HT.state().days['2026-10-11'] || {}).items || []);
  const noon = d11b.filter(function (x) { return /noon thing/.test(String(x.name || '')); })[0];
  O.draft.sameDayLanded = !!noon;
  O.draft.sameDayTime = noon ? String(noon.time || '') : '';

  } catch (e) { O.threw = String((e && e.message) || e) + ' @ ' + window.__stage;
                O.stack = String((e && e.stack) || '').slice(0, 500); }
  window.__out = JSON.stringify(O);
})();
'1'
'@
  $kick = Eval $probe
  if ($kick -ne '1') { $fails += "the probe would not start: $kick" }
  $raw = $null
  for ($w = 0; $w -lt 100; $w++) {
    Start-Sleep -Milliseconds 500
    $raw = Eval 'window.__out'
    if ($raw) { break }
  }
  if (-not $raw) {
    $st = Eval 'String(window.__stage)'
    $fails += "the probe HUNG after 50s -- last stage reached: '$st'"
    $RES = [pscustomobject]@{}
  } else { $RES = $raw | ConvertFrom-Json }
  if ($RES.threw) { $fails += "the probe threw: $($RES.threw) | $($RES.stack)" }

  $API = $RES.api; $ROLL = $RES.roll; $DRAFT = $RES.draft; $BOOT = $RES.boot

  Chk ($API.dayRollCheck -eq 'function') "HT.dayRollCheck is '$($API.dayRollCheck)', not a function"
  Chk ($API.dayForWriteKey -eq 'function') "HT.dayForWriteKey is '$($API.dayForWriteKey)', not a function"

  # --- boot was never broken, and must stay that way -------------------
  Chk ($BOOT.landedToday -eq $true) "boot did not land on today -- ensureCurrentDay already did this before the slice, and the slice must not have broken it"

  # --- R138: the resume ------------------------------------------------
  Chk ($ROLL.moved -eq $true) "a resume on a new calendar day left the app on '$($ROLL.before)' instead of moving to 2026-10-10 ($($ROLL.result))"
  Chk ($ROLL.oldDayKept -eq 1) "moving the view changed the OLD day's records ($($ROLL.oldDayKept) item(s) left of 1) -- a date roll moves what is shown, never what is stored"
  Chk ($ROLL.secondMoved -eq $false) "a second resume on the same day reported a move -- the check must be idempotent, or every resume dirties the store"
  Chk ($ROLL.stable -eq $true) "the current day moved again on an idempotent call (now '$($ROLL.after)')"

  # --- ruling F: the draft ---------------------------------------------
  Chk ($DRAFT.opened -eq $true) "the draft did not open, so nothing below is exercised"
  Chk ($DRAFT.startedDay -eq '2026-10-10') "the draft recorded started day '$($DRAFT.startedDay)', not 2026-10-10"
  Chk ($DRAFT.startedTime -eq '23:50') "the draft recorded start time '$($DRAFT.startedTime)', not 23:50 -- the time is what stops an entry written across midnight from landing with a blank clock"
  Chk ($DRAFT.unpinnedAtOpen -eq $true) "the draft took a day of its own AT OPEN -- then it cannot tell a date flip from the user deliberately navigating to another day, and D112's case asserts the navigation wins"
  Chk ($DRAFT.pinnedTime -eq '23:50') "the roll did not pin the capture time ('$($DRAFT.pinnedTime)')"
  Chk ($DRAFT.currentNow -eq '2026-10-11') "the fixture did not actually cross midnight (current is '$($DRAFT.currentNow)'), so the assertions below prove nothing"
  Chk ($DRAFT.stillOpen -eq $true) "the date roll DISCARDED the open draft"
  Chk ($DRAFT.keyAfterRoll -eq '2026-10-10') "the open draft was RETARGETED to '$($DRAFT.keyAfterRoll)' when the date flipped -- ruled F: never retargeted, because silently moving an entry the user is in the middle of writing is how a meal gets lost"
  Chk ($DRAFT.landedOn10 -eq $true) "the saved draft did not land on the day it was started ($($DRAFT.saved))"
  Chk ($DRAFT.landedOn11 -eq $false) "the saved draft landed on the NEW day as well or instead"
  Chk ($DRAFT.timeKept -eq '23:50') "the item saved across midnight has time '$($DRAFT.timeKept)', not the 23:50 it was captured at -- stampTime returns '' for a day that is not today, and re-deriving it at the far end is what blanked it"

  # --- the USER moving the day is honoured, with no fabricated time -----
  Chk ($DRAFT.navLanded -eq $true) "a draft saved after the USER navigated to a past day did not land there -- ruled F is about the date FLIPPING, and freezing the day at open breaks the deliberate case D112 asserts"
  Chk ($DRAFT.navTime -eq '') "the item logged onto a past day by navigation carries time '$($DRAFT.navTime)' -- today's clock on a past day is the fabrication D112 forbids, and it is how the first attempt at this slice broke that rule"

  # --- and the ordinary case is untouched ------------------------------
  Chk ($DRAFT.sameDayLanded -eq $true) "a draft started and saved on the SAME day no longer lands"
  Chk ($DRAFT.sameDayTime -ne '') "a same-day draft lost its time, so the change broke the ordinary path to fix the rare one"

} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup
  exit 2
}
Cleanup

if ($fails.Count) {
  Write-Host "DAYROLL GATE: FAIL"
  $fails | ForEach-Object { Write-Host "  - $_" }
  Write-Host "GATE: FAIL"
  exit 1
}
Write-Host "DAYROLL GATE: PASS -- the shipped page calls dayRollCheck on resume; boot still lands on today; a resume on a new calendar day moves the view without touching the old day's records, and a second resume reports no move. A draft claims no day at open; the CLOCK pins it, so one opened at 23:50 keeps its day and its 23:50 across midnight and lands on neither the new day nor with a blank time. The USER moving the day still wins: a draft saved after navigating to a past day lands there, with NO time, because today's clock on a past day is the fabrication D112 forbids. A same-day draft is unchanged."
Write-Host "GATE: PASS"
exit 0
