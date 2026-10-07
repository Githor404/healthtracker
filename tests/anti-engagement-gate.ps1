# ENGAGEMENT MECHANICS, ON THE RENDERED SURFACE AND IN BEHAVIOUR.
#
# [[D157]] binds the app to "speak up when something matters, never to drive
# engagement -- flags, not nudges". The behaviour was already right and the
# principle was written in exactly one comment (app.js: "Not a menu, not a nag,
# and never a streak, a nudge or a distance to a goal") and enforced nowhere.
#
# WHY THE BANNED SET TARGETS FRAMING, NOT VOCABULARY. Measured first, and three
# words collided with honest copy:
#   - "streak"      -- Trends renders `streak 3 days . 5 confirmed . avg 14h`,
#                      a FACT about the user's own fasting, with its denominator
#   - "don't break" -- Settings says "0-calorie drinks and the daily supplement
#                      don't break a fast", a factual rule
#   - "consecutive" -- the fasting streak's own definition
# Banning those words would fail the gate on truthful text, and a check that
# cries wolf is a check people stop reading. So what is banned is PRAISE,
# PENALTY FRAMING, RETURN PROMPTS, SOCIAL COMPARISON and GAMIFICATION -- phrases
# with no honest use in this app.
#
# AND ONE CONSTRUCTIVE ASSERTION, which is the measurement paying off: if
# `streak` is on the surface, its DENOMINATOR must be on the surface with it. A
# streak shown as a bare number is a prize; shown with "5 confirmed" it is a
# count. That is the difference the ban cannot express.
#
# COVERAGE, STATED. This gate sweeps FIRST RUN, the DAY VIEW (rows expanded, with
# a pending offer) and TRENDS -- the surfaces where a prod could live. It does
# NOT sweep all thirteen screens jargon-gate visits; duplicating that navigation
# would be a second copy that drifts, and drift in a test is worse than a
# narrower scope that says so.
#
# The API absences (Notification, PushManager, setAppBadge) belong to
# check-egress.sh and are deliberately NOT repeated here -- two checks over one
# property is a second opinion about it.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$Port = 8251
$Dbg = 9457
$origin = "http://127.0.0.1:$Port"
$script:cid = 0
$ws = $null; $chrome = $null; $server = $null
$udd = Join-Path $env:TEMP ("ht-engage-" + [System.Guid]::NewGuid().ToString('N'))
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
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 1; mobile = $true } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  $ready = $false
  for ($i = 0; $i -lt 100; $i++) {
    Start-Sleep -Milliseconds 200
    if ((Eval "(typeof window.HT === 'object' && typeof HT.boot === 'function') ? 1 : 0") -eq 1) { $ready = $true; break }
  }
  if (-not $ready) { Write-Host "ERROR: HT never appeared"; Cleanup; exit 2 }

  $sweep = @'
(async function () {
  let out_floor = 0;
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const OUT = { screens: [], seen: [], behaviour: {} };
  const SEEN = Object.create(null);
  // The instrument jargon-gate established: a closed <details> keeps a bounding
  // rect, so checkVisibility is the only test that reports it correctly.
  function visible(el) {
    if (typeof el.checkVisibility === 'function') {
      if (!el.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true,
                                visibilityProperty: true })) return false;
    } else {
      const cs = getComputedStyle(el), r = el.getBoundingClientRect();
      if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return false;
      if (r.width <= 0 || r.height <= 0) return false;
    }
    for (let p = el.parentElement; p; p = p.parentElement)
      if (p.tagName === 'DETAILS' && !p.open) return false;
    return true;
  }
  function sweep(screen) {
    const all = document.body.querySelectorAll('*');
    let n = 0;
    for (let i = 0; i < all.length; i++) {
      const el = all[i];
      if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE') continue;
      let t = '';
      for (let j = 0; j < el.childNodes.length; j++)
        if (el.childNodes[j].nodeType === 3) t += el.childNodes[j].nodeValue;
      const ph = el.getAttribute && el.getAttribute('placeholder');
      const al = el.getAttribute && el.getAttribute('aria-label');
      t = String(t).replace(/\s+/g, ' ').trim();
      if (!t && !ph && !al) continue;
      if (!visible(el)) continue;
      [t, ph, al].forEach(function (x) {
        if (!x) return;
        const k = String(x).replace(/\s+/g, ' ').trim();
        if (!k) return;
        if (!(k in SEEN)) { SEEN[k] = 1; OUT.seen.push([k, screen]); }
        n++;
      });
    }
    OUT.screens.push(screen + ' (' + n + ')');
  }

  HT.setClock(function () { return Date.parse('2026-09-26T14:00:00-04:00'); });
  localStorage.clear(); HT.boot(); await sleep(400);
  sweep('first run');

  // A day with unresolved items, so the next-tap OFFER exists to be dismissed,
  // and several confirmed fasting days so the streak actually renders.
  const DK = '2026-09-26';
  const S = HT.state();
  const mk = (o) => Object.assign({ meal: 'lunch', time: '12:30', grams: 100, kcal: 200,
    protein_g: 5, fat_g: 5, carb_g: 20, fiber_g: 2, soluble_fiber_g: 0,
    confidence: 'eyeballed', source: 'ai-paste', notes: '' }, o);
  S.days[DK] = { status: 'in_progress', water_l: 0, items: [
    mk({ name: 'lentil stew', mealId: 'm1' }),
    mk({ name: 'side salad', time: '12:31', mealId: 'm1' })
  ] };
  // Eating events spaced so that TWO gaps clear the 16 h threshold, on
  // consecutive days -- a streak is DERIVED from those gaps, never stored.
  S.days['2026-09-24'] = { status: 'complete', water_l: 0, items: [
    mk({ name: 'early dinner', time: '19:00' }) ] };
  S.days['2026-09-25'] = { status: 'complete', water_l: 0, items: [
    mk({ name: 'late lunch', time: '12:00' }), mk({ name: 'dinner', time: '19:00' }) ] };

  // ---- FORK C: SEED PAST EVERY DAY-COUNT FLOOR IN THE FILE -------------
  // The first version of this fixture seeded THREE logged days. The nudge layer's
  // floor was SEVEN, so its card was empty in all four sweeps and this gate's PASS
  // line described a page its own subject was absent from. That layer is gone
  // (H28/A1); the floor that remains is D95's typical, which is a SUFFICIENCY
  // floor -- it suppresses output until it has enough days, which is the opposite
  // of a nudge -- and it is now the thing this seeding keeps populated.
  //
  // THE FLOOR IS READ FROM THE APP, not typed here. A fixture that hard-codes 3
  // against a constant of 8 cannot report the mismatch, and one that hard-codes 8
  // goes stale the moment the constant moves.
  const FLOOR = Number(HT.TYPICAL_MIN_DAYS) || 0;
  out_floor = FLOOR;
  const need = FLOOR + 1;
  // Complete days with full macros, because the typical counts COMPLETE days only
  // and skips any day whose composition cannot be totalled.
  for (let k = 0; k < need; k++) {
    const d = new Date(Date.parse('2026-09-23T00:00:00') - k * 86400000);
    const key = d.toISOString().slice(0, 10);
    if (S.days[key]) continue;
    S.days[key] = { status: 'complete', water_l: 2, items: [
      mk({ name: 'breakfast', time: '08:00', kcal: 400, protein_g: 20, fat_g: 10, carb_g: 50, fiber_g: 6 }),
      mk({ name: 'dinner', time: '19:00', kcal: 700, protein_g: 35, fat_g: 25, carb_g: 70, fiber_g: 9 }) ] };
  }
  S.current = DK;
  // PERSISTED, not just assigned. Further down this probe calls HT.boot() to prove
  // a dismissed offer survives a reboot -- and a reboot reloads from localStorage,
  // which discarded every day seeded only in memory. The typical then reported
  // n=0 of m=0 with twelve days "seeded", and the assertion's own evidence line is
  // what made that visible instead of sending me back to read typicalWindow.
  HT.Store.saveState(S);
  HT.refresh(); await sleep(300);
  // THE KEYS COME FROM THE APP, not from my idea of its format. fastLog is keyed
  // by the candidate's START timestamp and matched by matchResolution; keying it
  // by a date string left every candidate 'pending' and the streak at 0, which
  // this gate's own fixture guard caught.
  S.fastLog = S.fastLog || {};
  const evs = (typeof HT.fastEvents === 'function') ? HT.fastEvents() : [];
  OUT.behaviour.floor = out_floor;
  OUT.behaviour.loggedDaysSeeded = Object.keys(S.days).length;
  OUT.behaviour.fastEvents = evs.length;
  for (let i = 1; i < evs.length; i++) {
    const a = evs[i - 1], b = evs[i];
    const hrs = (Date.parse(b) - Date.parse(a)) / 3600000;
    if (hrs >= 16) S.fastLog[a] = { state: 'fasted', start: a, end: b, hours: Math.round(hrs * 10) / 10 };
  }
  OUT.behaviour.fastsResolved = Object.keys(S.fastLog).length;
  OUT.behaviour.streak = (typeof HT.fastingStats === 'function')
    ? (HT.fastingStats(HT.state().days) || {}).streak : null;
  HT.refresh(); await sleep(400);
  const rowN = document.querySelectorAll('.mitem').length;
  for (let r = 0; r < rowN; r++) {
    const h = document.querySelectorAll('.mitem')[r];
    const hh = h && h.querySelector('.mhead');
    if (hh) { hh.click(); await sleep(40); }
  }
  await sleep(200);
  sweep('day view');

  // ---- THE OFFER, AND THAT IT NEVER COMES BACK ---------------------------
  if (typeof HT.resolveWalkStart === 'function') {
    HT.resolveWalkStart(DK, 'm1');
    HT.refresh(); await sleep(250);
    OUT.behaviour.offerShown = document.querySelectorAll('.rwalk').length;
    sweep('day view with a pending offer');
    if (typeof HT.resolveWalkDismiss === 'function') {
      HT.resolveWalkDismiss();
      await sleep(200);
      OUT.behaviour.afterDismiss = document.querySelectorAll('.rwalk').length;
      HT.refresh(); await sleep(200);
      OUT.behaviour.afterRerender = document.querySelectorAll('.rwalk').length;
      HT.boot(); await sleep(300);
      OUT.behaviour.afterBoot = document.querySelectorAll('.rwalk').length;
    } else { OUT.behaviour.noDismissFn = true; }
  } else { OUT.behaviour.noWalkFn = true; }

  // ---- TRENDS, where the fasting streak lives ----------------------------
  HT.state().current = DK;
  HT.refresh(); await sleep(200);
  let opened = false;
  const tabs = Array.prototype.slice.call(document.querySelectorAll('[onclick],[data-view],button,a'));
  for (const el of tabs) {
    const t = ((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
    if (t.indexOf('trend') >= 0) { el.click(); opened = true; await sleep(400); break; }
  }
  OUT.trendsOpened = opened;
  Array.prototype.slice.call(document.querySelectorAll('.wrap details')).forEach(function (d) { d.open = true; });
  await sleep(250);
  // THE FLOORED SURFACE MUST BE POPULATED, or this sweep is reading an empty page
  // again -- one floor along from the one that hid the nudge.
  const tb = document.querySelector('.tbrow');
  OUT.behaviour.typicalPresent = !!tb;
  OUT.behaviour.typicalWithheld = !!(tb && /No typical yet/i.test(tb.textContent || ''));
  // The assertion carries its own evidence: "withheld" without the counts sends
  // the reader back to the source to find out which filter rejected the days.
  try {
    const tm = HT.typicalWindow(HT.getTypicalNutrient(), HT.TYPICAL_WINDOW);
    OUT.behaviour.typN = tm.n; OUT.behaviour.typM = tm.m;
    OUT.behaviour.typOmitted = tm.omitted; OUT.behaviour.typEmpty = tm.empty;
    OUT.behaviour.typEnough = tm.enough;
    OUT.behaviour.typNutrient = String(HT.getTypicalNutrient() || '');
  } catch (e) { OUT.behaviour.typErr = String(e && e.message); }
  OUT.behaviour.tbrowText = tb ? (tb.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 150) : '';
  sweep('trends');
  OUT.streakStrings = OUT.seen.filter(function (p) { return /streak/i.test(p[0]); }).map(function (p) { return p[0]; });
  return OUT;
})()
'@
  $raw = EvalA $sweep
  if ($raw -like 'EXCEPTION*') { Write-Host "ERROR: sweep threw: $raw"; Cleanup; exit 2 }
  $R = $raw | ConvertFrom-Json

  $strings = @()
  foreach ($pair in $R.seen) { $strings += [pscustomobject]@{ t = [string]$pair[0]; s = [string]$pair[1] } }
  Write-Host ("  swept: {0}" -f ($R.screens -join ', '))
  Chk ($strings.Count -ge 120) "only $($strings.Count) visible strings were harvested across $($R.screens.Count) screens -- a sweep of a blank page passes everything (D96)"

  # ---- THE BANNED FRAMING -------------------------------------------------
  $banned = @(
    @{ re = '(?i)keep it up|well done|great job|nice work|on a roll|you.?re doing (great|well)';
       say = 'praise -- an advocate reports, it does not applaud' },
    @{ re = '(?i)(broke|lost) (your|the) (streak|run|record)|streak (lost|broken|gone)|back to zero';
       say = 'penalty framing -- a missed day is a fact, not a forfeit' },
    @{ re = '(?i)you missed|you forgot|don.?t forget to|time to log|come back|check in soon';
       say = 'a return prompt -- this exists to bring the user back, not to tell them something' },
    @{ re = '(?i)leaderboard|rank(ed)? (against|among)|better than (others|average|most)|compared to other';
       say = 'social comparison -- D157 says compare against the user OWN baseline' },
    @{ re = '(?i)\bbadge\b|\btrophy\b|\bachievement\b|\breward\b|\bpoints\b';
       say = 'gamification -- a reward for logging is a reason to log that is not the user interest' },
    @{ re = '(?i)\d+\s*day\s*(streak|run)\b';
       say = 'a streak worn as a prize. The factual form is "streak N days - M confirmed", which states its denominator' }
  )
  foreach ($b in $banned) {
    $hits = $strings | Where-Object { $_.t -match $b.re }
    if ($hits) {
      $where = ($hits | Select-Object -First 3 | ForEach-Object { "'" + ($_.t.Substring(0, [Math]::Min(64, $_.t.Length))) + "' (" + $_.s + ")" }) -join '; '
      $fails += "ENGAGEMENT: /$($b.re)/ is on the surface in $(@($hits).Count) place(s) -- $($b.say). Found: $where"
    }
  }

  # ---- THE CONSTRUCTIVE HALF: a streak must carry its denominator ---------
  $streaks = @($R.streakStrings)
  Chk ($streaks.Count -ge 1) "no string containing 'streak' was found on any swept surface, so the assertion below -- that a streak always carries its denominator -- had nothing to test. Fixture: $($R.behaviour.fastEvents) eating events, $($R.behaviour.fastsResolved) fasts resolved, fastingStats streak = $($R.behaviour.streak). A streak is DERIVED from gaps between meals and resolved in fastLog keyed by the candidate's start timestamp -- it cannot be seeded directly"
  foreach ($s in $streaks) {
    Chk ($s -match '(?i)confirmed') "a streak is on the surface WITHOUT its denominator: '$s'. 'streak 3 days' alone is a prize; 'streak 3 days - 5 confirmed' is a count, and that difference is the whole ruling"
  }

  # ---- THE BEHAVIOURAL HALF: a dismissed offer never returns --------------
  $B = $R.behaviour
  Chk (-not $B.noWalkFn) "HT.resolveWalkStart is not exported, so the dismissal behaviour could not be driven"
  Chk (-not $B.noDismissFn) "HT.resolveWalkDismiss is not exported"
  if (-not $B.noWalkFn -and -not $B.noDismissFn) {
    Chk ($B.offerShown -ge 1) "the next-tap offer never rendered, so dismissing it proves nothing -- the fixture must contain the state the rule is about"
    Chk ($B.afterDismiss -eq 0) "the offer is still on screen after being dismissed ($($B.afterDismiss) present)"
    Chk ($B.afterRerender -eq 0) "the offer CAME BACK on the next render ($($B.afterRerender) present) -- re-prompting a dismissed offer is the nudge D157 forbids"

  # --- FORK C: the sweep must not read a page its subject is absent from ----
  Chk ($B.floor -gt 0) "the day-count floor came back as '$($B.floor)' -- it is READ from HT.TYPICAL_MIN_DAYS, so a zero means the export is gone and the seeding proves nothing (D96)"
  Chk ($B.loggedDaysSeeded -gt $B.floor) "the fixture seeded $($B.loggedDaysSeeded) day(s) against a floor of $($B.floor) -- the first version of this gate seeded THREE against SEVEN and swept an empty card for four surfaces"
  Chk ($B.typicalPresent -eq $true) "the floored surface (D95's typical) did not render at all, so this sweep cannot say whether a populated one is clean"
  Chk ($B.typicalWithheld -eq $false) "the typical is still WITHHELD: model n=$($B.typN) of m=$($B.typM) (omitted $($B.typOmitted), empty $($B.typEmpty), enough=$($B.typEnough), nutrient=$($B.typNutrient)), $($B.loggedDaysSeeded) day(s) seeded against floor $($B.floor). Row reads: '$($B.tbrowText)'"
    Chk ($B.afterBoot -eq 0) "the offer came back after a reboot ($($B.afterBoot) present)"
  }

  if ($fails.Count) {
    Write-Host "ANTI-ENGAGEMENT GATE: FAIL"
    foreach ($f in $fails) { Write-Host "  - $f" }
    Cleanup
    exit 1
  }
  Write-Host "ANTI-ENGAGEMENT GATE: PASS -- $($strings.Count) visible strings across $($R.screens.Count) surfaces carry no praise, no penalty framing, no return prompt, no social comparison and no gamification; the one legitimate streak carries its denominator; and a dismissed offer stays dismissed across a re-render AND a reboot."
  Write-Host "  SCOPE, STATED: first run, the day view with rows expanded and a pending offer, and trends. NOT all thirteen screens jargon-gate visits -- duplicating that navigation would be a second copy that drifts. The Notification/PushManager/badge absences belong to check-egress.sh and are not repeated here."
  Cleanup
  exit 0
} catch {
  Write-Host "ERROR: $_"
  Cleanup
  exit 2
}
