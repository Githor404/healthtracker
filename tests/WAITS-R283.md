# R283 -- every wait a wait on a condition

Generated from the conversion (line numbers are the ORIGINAL lines, before R283). The conditions:

- **WaitQuiet** -- `tests/lib/quiet.js`, installed in every page before the app: resolves when none of THE APP'S OWN async work is in flight (its timers of 1 s or less, fetches and their bodies, IndexedDB READS -- not the background cache writes, measured at 3,583 in one gate -- createImageBitmap -- counted only when a frame of the app's origin started it), no finite CSS transition or animation is running, and the DOM has not changed for two animation frames. 10 s, then the gate FAILS naming what was still in flight and where it was set. Measured while building it: the antivirus on this machine injects a script into every page that keeps a short timer going for seconds (`gc.kis.v2.scr.kaspersky-labs.com`), which is why only the app's own work counts.
- **WaitBoot** -- after a navigate or reload: the old page is marked first (`MarkOld`), then polled (100 ms) until the NEW page has `HT` and is complete, then WaitQuiet. 30 s, then FAIL.
- **WaitLoaded** -- the same as WaitBoot for a page that is not the app (offline-gate's seed page): the new document complete, 30 s, then FAIL.
- **WaitServer** -- the test server polled (100 ms) until it answers. 30 s, then the gate stops as an environment error.
- **kept** -- a poll interval inside a loop that already waits on a condition, or pacing between input events (keystrokes, touch moves) that is part of the input, not a wait.

| gate | line | old wait | new condition |
|---|---|---|---|
| anti-engagement-gate.ps1 | 115 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| anti-engagement-gate.ps1 | 121 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| anti-engagement-gate.ps1 | 131 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| anti-engagement-gate.ps1 | 137 | `Start-Sleep -Milliseconds 200` | kept: poll interval inside a condition loop |
| anti-engagement-gate.ps1 | 189 | `localStorage.clear(); HT.boot(); await sleep(400);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 245 | `HT.refresh(); await sleep(300);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 263 | `HT.refresh(); await sleep(400);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 268 | `if (hh) { hh.click(); await sleep(40); }` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 270 | `await sleep(200);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 276 | `HT.refresh(); await sleep(250);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 281 | `await sleep(200);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 283 | `HT.refresh(); await sleep(200);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 285 | `HT.boot(); await sleep(300);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 292 | `HT.refresh(); await sleep(200);` | await window.__htQuiet(10000) |
| anti-engagement-gate.ps1 | 301 | `await sleep(250);` | await window.__htQuiet(10000) |
| backup-gate.ps1 | 70 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| backup-gate.ps1 | 108 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| backup-gate.ps1 | 120 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| backup-gate.ps1 | 126 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| backup-gate.ps1 | 265 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after reload) |
| bm-slider-gate.ps1 | 115 | `Start-Sleep -Milliseconds 1500` | WaitBoot (after navigate) |
| bm-slider-gate.ps1 | 118 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| bm-slider-gate.ps1 | 127 | `Start-Sleep -Milliseconds 110` | WaitQuiet |
| bm-slider-gate.ps1 | 168 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| bm-slider-gate.ps1 | 178 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| bm-slider-gate.ps1 | 189 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| bpchart-gate.ps1 | 63 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| bpchart-gate.ps1 | 110 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| bpchart-gate.ps1 | 122 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| bpchart-gate.ps1 | 128 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| bpchart-gate.ps1 | 160 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| capture-gate.ps1 | 126 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| capture-gate.ps1 | 132 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| capture-gate.ps1 | 142 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| capture-gate.ps1 | 149 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| capture-gate.ps1 | 165 | `await sleep(250);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 182 | `await sleep(200);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 198 | `await sleep(600);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 209 | `await sleep(350);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 334 | `Start-Sleep -Milliseconds 800` | WaitQuiet |
| capture-gate.ps1 | 348 | `await sleep(250);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 361 | `await sleep(600);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 494 | `await sleep(400);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 513 | `await sleep(400);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 523 | `await sleep(600);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 535 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| capture-gate.ps1 | 584 | `await sleep(500);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 593 | `await sleep(200);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 599 | `await sleep(700);` | await window.__htQuiet(10000) |
| capture-gate.ps1 | 624 | `await sleep(400);` | await window.__htQuiet(10000) |
| capture-outcome-gate.ps1 | 153 | `Start-Sleep -Milliseconds 1500` | WaitBoot (after navigate) |
| capture-outcome-gate.ps1 | 172 | `Start-Sleep -Milliseconds 1600` | WaitQuiet |
| capture-outcome-gate.ps1 | 215 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| capture-outcome-gate.ps1 | 225 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| capture-outcome-gate.ps1 | 236 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| chart-gate.ps1 | 101 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| chart-gate.ps1 | 103 | `Start-Sleep -Milliseconds 450` | WaitQuiet |
| chart-gate.ps1 | 140 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| chart-gate.ps1 | 146 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| chart-gate.ps1 | 156 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| chart-gate.ps1 | 162 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| chart-gate.ps1 | 215 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 229 | `HT.refresh(); await sleep(300);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 259 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| chart-gate.ps1 | 341 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| chart-gate.ps1 | 440 | `Start-Sleep -Milliseconds 25` | kept: gesture pacing between input events, not a wait |
| chart-gate.ps1 | 443 | `Start-Sleep -Milliseconds 400` | WaitQuiet |
| chart-gate.ps1 | 457 | `Start-Sleep -Milliseconds 25` | kept: gesture pacing between input events, not a wait |
| chart-gate.ps1 | 460 | `Start-Sleep -Milliseconds 400` | WaitQuiet |
| chart-gate.ps1 | 477 | `Start-Sleep -Milliseconds 30` | WaitQuiet |
| chart-gate.ps1 | 480 | `Start-Sleep -Milliseconds 400` | WaitQuiet |
| chart-gate.ps1 | 488 | `Start-Sleep -Milliseconds 700` | WaitQuiet |
| chart-gate.ps1 | 566 | `Start-Sleep -Milliseconds 400` | WaitQuiet |
| chart-gate.ps1 | 570 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| chart-gate.ps1 | 572 | `Start-Sleep -Milliseconds 400` | WaitQuiet |
| chart-gate.ps1 | 580 | `Start-Sleep -Milliseconds 900` | WaitQuiet |
| chart-gate.ps1 | 584 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| chart-gate.ps1 | 589 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| chart-gate.ps1 | 677 | `localStorage.clear(); HT.boot(); await sleep(200);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 705 | `HT.refresh(); await sleep(300);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 707 | `await sleep(400);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 721 | `HT.chartPreset('6 h'); HT.glucoseRedraw(); await sleep(150);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 723 | `HT.chartPreset('24 h'); HT.glucoseRedraw(); await sleep(150);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 727 | `HT.chartPreset('24 h'); HT.glucoseRedraw(); await sleep(250);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 813 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| chart-gate.ps1 | 821 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| chart-gate.ps1 | 827 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| chart-gate.ps1 | 845 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| chart-gate.ps1 | 861 | `Start-Sleep -Milliseconds 150` | WaitQuiet |
| chart-gate.ps1 | 867 | `Start-Sleep -Milliseconds 30` | kept: gesture pacing between input events, not a wait |
| chart-gate.ps1 | 870 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| chart-gate.ps1 | 892 | `HT.chartPreset('24 h'); HT.glucoseRedraw(); await sleep(200);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 898 | `HT.chartPanMs(2 * 86400000); HT.glucoseRedraw(); await sleep(200);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 907 | `await sleep(250);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 913 | `HT.chartPanMs(3 * 86400000); HT.glucoseRedraw(); await sleep(150);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 916 | `HT.chartPreset('6 h'); await sleep(200);` | await window.__htQuiet(10000) |
| chart-gate.ps1 | 971 | `HT.refresh(); await sleep(300);` | await window.__htQuiet(10000) |
| chip-layout-gate.ps1 | 79 | `Start-Sleep -Milliseconds 1400` | WaitBoot (after navigate) |
| chip-layout-gate.ps1 | 126 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| chip-layout-gate.ps1 | 136 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| chip-layout-gate.ps1 | 147 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| close-gate.ps1 | 66 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| close-gate.ps1 | 113 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| close-gate.ps1 | 125 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| close-gate.ps1 | 131 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| close-gate.ps1 | 165 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| close-gate.ps1 | 167 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| cold-start-gate.ps1 | 79 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| cold-start-gate.ps1 | 117 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| cold-start-gate.ps1 | 129 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| cold-start-gate.ps1 | 135 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| cold-start-gate.ps1 | 165 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| cold-start-gate.ps1 | 173 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| cold-start-gate.ps1 | 186 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| cold-start-gate.ps1 | 202 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| cold-start-gate.ps1 | 209 | `Start-Sleep -Milliseconds 3500` | WaitBoot (after navigate) |
| collapse-gate.ps1 | 93 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| collapse-gate.ps1 | 105 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| collapse-gate.ps1 | 111 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| collapse-gate.ps1 | 152 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| collapse-gate.ps1 | 157 | `await HT.corpusEnsure(); await sleep(150);` | await window.__htQuiet(10000) |
| collapse-gate.ps1 | 270 | `Start-Sleep -Milliseconds 700` | WaitQuiet |
| collapse-gate.ps1 | 272 | `Start-Sleep -Milliseconds 150` | WaitQuiet |
| collapse-gate.ps1 | 280 | `Start-Sleep -Milliseconds 600` | WaitQuiet |
| collapse-gate.ps1 | 363 | `Start-Sleep -Milliseconds 600` | WaitQuiet |
| collapse-gate.ps1 | 370 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| collapse-gate.ps1 | 378 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| collapse-gate.ps1 | 383 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| collapse-gate.ps1 | 385 | `Start-Sleep -Milliseconds 500` | WaitQuiet |
| collapse-gate.ps1 | 419 | `await sleep(700);` | await window.__htQuiet(10000) |
| collapse-gate.ps1 | 462 | `await sleep(450);` | await window.__htQuiet(10000) |
| corpus-cache-gate.ps1 | 82 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| corpus-cache-gate.ps1 | 120 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| corpus-cache-gate.ps1 | 132 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| corpus-cache-gate.ps1 | 138 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| corpus-cache-gate.ps1 | 169 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after reload) |
| corpus-cache-gate.ps1 | 181 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after reload) |
| corpus-gate.ps1 | 124 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| corpus-gate.ps1 | 130 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| corpus-gate.ps1 | 141 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| corpus-gate.ps1 | 145 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after navigate) |
| corpus-gate.ps1 | 220 | `Start-Sleep -Milliseconds 2200` | WaitBoot (after navigate) |
| correction-gate.ps1 | 131 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| correction-gate.ps1 | 137 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| correction-gate.ps1 | 148 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| correction-gate.ps1 | 155 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| correction-gate.ps1 | 179 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 180 | `await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 217 | `await sleep(200);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 313 | `await sleep(150);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 325 | `await sleep(150);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 344 | `await sleep(350);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 383 | `await sleep(350);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 400 | `await sleep(300);` | await window.__htQuiet(10000) |
| correction-gate.ps1 | 432 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| dayclose-gate.ps1 | 64 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| dayclose-gate.ps1 | 111 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| dayclose-gate.ps1 | 123 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| dayclose-gate.ps1 | 129 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| dayclose-gate.ps1 | 152 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| dayroll-gate.ps1 | 126 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| dayroll-gate.ps1 | 132 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| dayroll-gate.ps1 | 143 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| dayroll-gate.ps1 | 147 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| dayroll-gate.ps1 | 172 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| dayroll-gate.ps1 | 185 | `await sleep(250);` | await window.__htQuiet(10000) |
| dayroll-gate.ps1 | 285 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| delete-all-gate.ps1 | 96 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| delete-all-gate.ps1 | 102 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| delete-all-gate.ps1 | 112 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| delete-all-gate.ps1 | 119 | `Start-Sleep -Milliseconds 200` | kept: poll interval inside a condition loop |
| delete-all-gate.ps1 | 129 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| delete-all-gate.ps1 | 149 | `HT.refresh(); await sleep(300);` | await window.__htQuiet(10000) |
| delete-all-gate.ps1 | 181 | `if (btn) { btn.click(); await sleep(250); }` | await window.__htQuiet(10000) |
| delete-all-gate.ps1 | 201 | `if (cancel) { cancel.click(); await sleep(200); }` | await window.__htQuiet(10000) |
| delete-all-gate.ps1 | 225 | `await sleep(400);` | await window.__htQuiet(10000) |
| drinkfree-gate.ps1 | 55 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }` | WaitQuiet |
| drinkfree-gate.ps1 | 94 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| drinkfree-gate.ps1 | 106 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| drinkfree-gate.ps1 | 112 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| elite-gate.ps1 | 85 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| elite-gate.ps1 | 123 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| elite-gate.ps1 | 135 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| elite-gate.ps1 | 141 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| elite-gate.ps1 | 331 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| entry-gate.ps1 | 103 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| entry-gate.ps1 | 115 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| entry-gate.ps1 | 119 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| entry-gate.ps1 | 368 | `Start-Sleep -Milliseconds 6500` | WaitQuiet |
| fdc-gate.ps1 | 124 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| fdc-gate.ps1 | 130 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| fdc-gate.ps1 | 141 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| fdc-gate.ps1 | 148 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| fdc-gate.ps1 | 161 | `localStorage.clear(); HT.boot(); await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 162 | `await HT.corpusEnsure(); await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 202 | `await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 203 | `const type = async (q) => { const f = $('#fqQuery'); f.value = q; f.dispatchEvent(new Event('input', { bubbles` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 214 | `await sleep(150);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 226 | `await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 233 | `await sleep(500);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 256 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| fdc-gate.ps1 | 268 | `await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 274 | `await sleep(150);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 291 | `await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 301 | `await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 302 | `const f = $('#fqQuery'); f.value = 'limitme'; f.dispatchEvent(new Event('input', { bubbles: true })); await sl` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 304 | `$('#fqRows .fdcgo').click(); await sleep(400);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 331 | `await HT.resolveOpen(dk, idx); await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 335 | `go.click(); await sleep(400);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 338 | `$('#resolveBox .fdcnone').click(); await sleep(150);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 341 | `$('#resolveBox .fdcgo').click(); await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 357 | `document.querySelectorAll('#resolveBox .fdcrow')[1].click(); await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 379 | `await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 381 | `await HT.photoSearchRun(0, 'gate qxvz'); await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 384 | `await HT.photoSearchAskModel(0); await sleep(400);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 389 | `go.click(); await sleep(500);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 411 | `document.querySelectorAll('.pmsearch .fdcrow')[1].click(); await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 435 | `await sleep(300);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 437 | `await HT.photoSearchRun(0, 'gate qxvz'); await sleep(200);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 438 | `await HT.photoSearchAskModel(0); await sleep(400);` | await window.__htQuiet(10000) |
| fdc-gate.ps1 | 448 | `keep.click(); await sleep(200);` | await window.__htQuiet(10000) |
| flow-gate.ps1 | 131 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| flow-gate.ps1 | 137 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| flow-gate.ps1 | 148 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| flow-gate.ps1 | 153 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| flow-gate.ps1 | 171 | `if (v) return v; if (performance.now() - t0 > 10000) return null; await sleep(25); } };` | await window.__htQuiet(10000) |
| font-floor-gate.ps1 | 121 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| font-floor-gate.ps1 | 127 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| font-floor-gate.ps1 | 138 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| font-floor-gate.ps1 | 142 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| font-floor-gate.ps1 | 186 | `await sleep(250);` | await window.__htQuiet(10000) |
| font-floor-gate.ps1 | 203 | `await sleep(300);` | await window.__htQuiet(10000) |
| font-floor-gate.ps1 | 206 | `await sleep(250);` | await window.__htQuiet(10000) |
| font-floor-gate.ps1 | 224 | `await sleep(150);` | await window.__htQuiet(10000) |
| font-floor-gate.ps1 | 229 | `await sleep(250);` | await window.__htQuiet(10000) |
| font-floor-gate.ps1 | 231 | `await sleep(150);` | await window.__htQuiet(10000) |
| forms-gate.ps1 | 73 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| forms-gate.ps1 | 111 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| forms-gate.ps1 | 123 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| forms-gate.ps1 | 129 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| identity-search-gate.ps1 | 121 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| identity-search-gate.ps1 | 127 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| identity-search-gate.ps1 | 138 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| identity-search-gate.ps1 | 147 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| identity-search-gate.ps1 | 199 | `await sleep(250);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 202 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 223 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 250 | `await sleep(250);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 261 | `await sleep(300);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 268 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 270 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 309 | `await sleep(1200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 329 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 331 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 334 | `if (bw.length) { bw[0].click(); await sleep(1200); }` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 348 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 360 | `await sleep(500);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 377 | `await sleep(700);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 384 | `await sleep(400);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 389 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 392 | `await sleep(1200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 399 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 401 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 408 | `await sleep(500);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 449 | `await sleep(900);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 475 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 478 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 480 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 492 | `await sleep(1200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 507 | `await sleep(500);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 514 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 524 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 527 | `await sleep(200);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 529 | `await sleep(600);` | await window.__htQuiet(10000) |
| identity-search-gate.ps1 | 534 | `await sleep(600);` | await window.__htQuiet(10000) |
| import-gate.ps1 | 123 | `Start-Sleep -Milliseconds 120` | kept: poll interval inside a condition loop |
| import-gate.ps1 | 129 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| import-gate.ps1 | 131 | `Start-Sleep -Milliseconds 350` | WaitQuiet |
| import-gate.ps1 | 252 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| import-gate.ps1 | 258 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| import-gate.ps1 | 268 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| import-gate.ps1 | 283 | `Start-Sleep -Milliseconds 200` | kept: poll interval inside a condition loop |
| import-gate.ps1 | 328 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| import-gate.ps1 | 336 | `HT.refresh(); await sleep(400);` | await window.__htQuiet(10000) |
| import-gate.ps1 | 508 | `if (window.gc) { window.gc(); await sleep(60); window.gc(); await sleep(60); }` | await window.__htQuiet(10000) |
| import-gate.ps1 | 528 | `await sleep(50);` | await window.__htQuiet(10000) |
| import-gate.ps1 | 615 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| jargon-gate.ps1 | 127 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| jargon-gate.ps1 | 133 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| jargon-gate.ps1 | 144 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| jargon-gate.ps1 | 151 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| jargon-gate.ps1 | 223 | `await sleep(400);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 276 | `await sleep(500);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 290 | `if (hh) { hh.click(); await sleep(40); }` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 292 | `await sleep(250);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 307 | `await sleep(150);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 311 | `await sleep(100);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 319 | `await sleep(350);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 323 | `await sleep(300);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 329 | `await sleep(320);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 333 | `await sleep(200);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 338 | `await sleep(600);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 342 | `await sleep(200);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 347 | `if (mp) { mp.open = true; HT.panelToggle(true); await sleep(450); sweep('micronutrient panel'); }` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 352 | `if (pp) { pp.open = true; HT.potentialToggle(true); HT.refresh(); await sleep(450);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 376 | `await sleep(500);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 380 | `await sleep(200);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 383 | `await sleep(450);` | await window.__htQuiet(10000) |
| jargon-gate.ps1 | 386 | `await sleep(200);` | await window.__htQuiet(10000) |
| lab-form-gate.ps1 | 90 | `Start-Sleep -Milliseconds 1400` | WaitBoot (after navigate) |
| lab-form-gate.ps1 | 131 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| lab-form-gate.ps1 | 141 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| lab-form-gate.ps1 | 152 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| landing-gate.ps1 | 125 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| landing-gate.ps1 | 131 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| landing-gate.ps1 | 142 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| landing-gate.ps1 | 149 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| landing-gate.ps1 | 173 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 174 | `await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 260 | `await sleep(400);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 309 | `await sleep(350);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 351 | `if (typeof HT.quickSheetOpen === 'function') { HT.quickSheetOpen(); await sleep(350); }` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 363 | `if (typeof HT.quickPick === 'function' && coleKey) { HT.quickPick(coleKey); await sleep(300); }` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 371 | `if (typeof HT.quickStep === 'function') { HT.quickStep(1); await sleep(200); }` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 402 | `HT.quickPick(salKey); await sleep(150);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 403 | `HT.quickStep(1); await sleep(150);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 464 | `await sleep(300);` | await window.__htQuiet(10000) |
| landing-gate.ps1 | 517 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| lookup-gate.ps1 | 57 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }` | WaitQuiet |
| lookup-gate.ps1 | 96 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| lookup-gate.ps1 | 108 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| lookup-gate.ps1 | 114 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| lookup-gate.ps1 | 351 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| myfood-gate.ps1 | 67 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| myfood-gate.ps1 | 105 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| myfood-gate.ps1 | 117 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| myfood-gate.ps1 | 123 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| night-gate.ps1 | 132 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| night-gate.ps1 | 138 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| night-gate.ps1 | 149 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| night-gate.ps1 | 153 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| night-gate.ps1 | 173 | `await sleep(250);` | await window.__htQuiet(10000) |
| night-gate.ps1 | 222 | `localStorage.clear(); HT.boot(); await sleep(200);` | await window.__htQuiet(10000) |
| night-gate.ps1 | 304 | `localStorage.clear(); HT.boot(); await sleep(200);` | await window.__htQuiet(10000) |
| night-gate.ps1 | 345 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| noauto-gate.ps1 | 77 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| noauto-gate.ps1 | 115 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| noauto-gate.ps1 | 127 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| noauto-gate.ps1 | 133 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| noauto-gate.ps1 | 165 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after reload) |
| offline-gate.ps1 | 104 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| offline-gate.ps1 | 116 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| offline-gate.ps1 | 128 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| offline-gate.ps1 | 135 | `Start-Sleep -Milliseconds 1500` | WaitLoaded (after navigate) |
| offline-gate.ps1 | 139 | `Start-Sleep -Seconds 2` | WaitBoot (after navigate) |
| offline-gate.ps1 | 148 | `Start-Sleep -Milliseconds 1500` | WaitBoot (after reload) |
| offline-gate.ps1 | 155 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| offline-gate.ps1 | 160 | `Start-Sleep -Seconds 2` | WaitBoot (after reload) |
| onedoor-gate.ps1 | 88 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| onedoor-gate.ps1 | 126 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| onedoor-gate.ps1 | 138 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| onedoor-gate.ps1 | 144 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| onedoor-gate.ps1 | 863 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| onedoor-gate.ps1 | 914 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| overlay-gate.ps1 | 103 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| overlay-gate.ps1 | 115 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| overlay-gate.ps1 | 125 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| overlay-gate.ps1 | 135 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| overlay-gate.ps1 | 144 | `S.current = DK; HT.refresh(); await sleep(500);` | await window.__htQuiet(10000) |
| overlay-gate.ps1 | 180 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| overlay-gate.ps1 | 188 | `Start-Sleep -Milliseconds 400` | WaitQuiet |
| overlay-gate.ps1 | 219 | `Start-Sleep -Milliseconds 620` | WaitQuiet |
| overlay-gate.ps1 | 245 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| overlay-gate.ps1 | 258 | `Start-Sleep -Milliseconds 450` | WaitQuiet |
| overlay-gate.ps1 | 275 | `Start-Sleep -Milliseconds 650` | WaitQuiet |
| overlay-gate.ps1 | 293 | `await sleep(250);` | await window.__htQuiet(10000) |
| overlay-gate.ps1 | 298 | `await sleep(250);` | await window.__htQuiet(10000) |
| overlay-gate.ps1 | 323 | `Start-Sleep -Milliseconds 450` | WaitQuiet |
| page-overflow-gate.ps1 | 101 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| page-overflow-gate.ps1 | 107 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| page-overflow-gate.ps1 | 117 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| page-overflow-gate.ps1 | 122 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after navigate) |
| page-overflow-gate.ps1 | 131 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| page-overflow-gate.ps1 | 159 | `HT.refresh(); await sleep(500);` | await window.__htQuiet(10000) |
| page-overflow-gate.ps1 | 163 | `HT.refresh(); await sleep(600);` | await window.__htQuiet(10000) |
| page-overflow-gate.ps1 | 217 | `Start-Sleep -Milliseconds 900` | WaitQuiet |
| page-overflow-gate.ps1 | 238 | `HT.boot(); HT.refresh(); await sleep(600);` | await window.__htQuiet(10000) |
| panel-gate.ps1 | 113 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| panel-gate.ps1 | 119 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| panel-gate.ps1 | 129 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| panel-gate.ps1 | 136 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| panel-gate.ps1 | 146 | `await sleep(300);` | await window.__htQuiet(10000) |
| panel-gate.ps1 | 171 | `await sleep(400);` | await window.__htQuiet(10000) |
| panel-gate.ps1 | 174 | `await sleep(500);` | await window.__htQuiet(10000) |
| panel-gate.ps1 | 233 | `Start-Sleep -Milliseconds 700` | WaitQuiet |
| parity-gate.ps1 | 136 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| parity-gate.ps1 | 142 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| parity-gate.ps1 | 153 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| parity-gate.ps1 | 162 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| parity-gate.ps1 | 183 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 184 | `await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(250);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 216 | `await sleep(500);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 223 | `await sleep(200);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 225 | `await sleep(500);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 245 | `await sleep(400);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 257 | `await HT.photoSearchRun(0, 'sui mai'); await sleep(400);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 266 | `await HT.photoSearchRun(0, 'coffee'); await sleep(400);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 276 | `await sleep(600);` | await window.__htQuiet(10000) |
| parity-gate.ps1 | 364 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| perf-gate.ps1 | 67 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| perf-gate.ps1 | 114 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| perf-gate.ps1 | 126 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| perf-gate.ps1 | 132 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| photo-lead-gate.ps1 | 141 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| photo-lead-gate.ps1 | 151 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| photo-lead-gate.ps1 | 162 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| potential-gate.ps1 | 135 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| potential-gate.ps1 | 141 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| potential-gate.ps1 | 152 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| potential-gate.ps1 | 161 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| potential-gate.ps1 | 184 | `localStorage.clear(); HT.boot(); await sleep(250);` | await window.__htQuiet(10000) |
| potential-gate.ps1 | 185 | `await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(300);` | await window.__htQuiet(10000) |
| potential-gate.ps1 | 235 | `await sleep(200);` | await window.__htQuiet(10000) |
| potential-gate.ps1 | 250 | `await sleep(400);` | await window.__htQuiet(10000) |
| potential-gate.ps1 | 313 | `await sleep(350);` | await window.__htQuiet(10000) |
| potential-gate.ps1 | 413 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| precedence-gate.ps1 | 56 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }` | WaitQuiet |
| precedence-gate.ps1 | 95 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| precedence-gate.ps1 | 107 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| precedence-gate.ps1 | 113 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| precedence-gate.ps1 | 129 | `await HT.corpusEnsure(); HT.matchIndexBuild(); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 135 | `await sleep(500);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 136 | `HT.photoSearchOpen(0); await sleep(250);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 155 | `if (white) { white.click(); await sleep(700); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 158 | `if (use) { use.click(); await sleep(600); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 159 | `const sr = HT.photoSave(); await sleep(900);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 189 | `const rp = HT.logRepeat(dk, wi); await sleep(100);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 192 | `const ex = HT.exportJSON(); HT.restore(ex); await sleep(100);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 209 | `await sleep(600);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 215 | `HT.photoSearchOpen(1); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 216 | `await HT.photoSearchRun(1, 'zzqqxv wibblefrotz'); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 219 | `if (keep) { keep.click(); await sleep(300); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 221 | `HT.photoSearchOpen(0); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 222 | `await HT.photoSearchRun(0, 'qqxxzz wibblejuice'); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 224 | `if (k0) { k0.click(); await sleep(300); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 225 | `HT.photoSave(); await sleep(900);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 250 | `if (line) { line.click(); await sleep(200); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 253 | `if (items[0]) { items[0].click(); await sleep(600); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 255 | `HT.resolveClose && HT.resolveClose(); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 260 | `HT.dayGroupsOpenAll(true); HT.refresh(); await sleep(150);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 263 | `if (rowHead) { o.headTag = ((rowHead.querySelector('.msuggnum') \|\| {}).getAttribute \|\| function () { retur` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 267 | `if (conf) { conf.click(); await sleep(300); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 271 | `if (undo) { undo.click(); await sleep(300); }` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 298 | `const b = HT.boot(); HT.refresh(); await sleep(200);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 303 | `HT.dayGroupsOpenAll && HT.dayGroupsOpenAll(true); HT.refresh(); await sleep(150);` | await window.__htQuiet(10000) |
| precedence-gate.ps1 | 305 | `if (row0) { row0.querySelector('.mhead').click(); await sleep(200); }` | await window.__htQuiet(10000) |
| rank-gate.ps1 | 87 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| rank-gate.ps1 | 125 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| rank-gate.ps1 | 137 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| rank-gate.ps1 | 143 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| rank-gate.ps1 | 223 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| resolve-gate.ps1 | 122 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| resolve-gate.ps1 | 128 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| resolve-gate.ps1 | 139 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| resolve-gate.ps1 | 148 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| resolve-gate.ps1 | 207 | `await sleep(200);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 209 | `await sleep(400);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 216 | `await sleep(200);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 221 | `await sleep(30);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 251 | `await sleep(250);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 255 | `await sleep(HT.RESOLVE_ARM_MS + 400);` | await window.__htQuiet(10000) -- waits for the app's 600 ms arm timer itself |
| resolve-gate.ps1 | 266 | `if (want) { want.click(); await sleep(400); }` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 273 | `await sleep(HT.RESOLVE_ARM_MS + 300);` | await window.__htQuiet(10000) -- waits for the app's 600 ms arm timer itself |
| resolve-gate.ps1 | 276 | `if (useBtn) { useBtn.click(); await sleep(900); }` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 286 | `await sleep(200);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 290 | `await sleep(250);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 293 | `await sleep(HT.RESOLVE_ARM_MS + 300);` | await window.__htQuiet(10000) -- waits for the app's 600 ms arm timer itself |
| resolve-gate.ps1 | 299 | `if (r3[0]) { r3[0].click(); await sleep(400); }` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 302 | `await sleep(HT.RESOLVE_ARM_MS + 300);` | await window.__htQuiet(10000) -- waits for the app's 600 ms arm timer itself |
| resolve-gate.ps1 | 305 | `if (cancelBtn) { cancelBtn.click(); await sleep(400); }` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 332 | `await sleep(200);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 351 | `await sleep(300);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 357 | `await sleep(250);` | await window.__htQuiet(10000) |
| resolve-gate.ps1 | 360 | `await sleep(HT.RESOLVE_ARM_MS + 300);` | await window.__htQuiet(10000) -- waits for the app's 600 ms arm timer itself |
| response-gate.ps1 | 128 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| response-gate.ps1 | 134 | `Start-Sleep -Milliseconds 400` | kept: poll interval inside a condition loop |
| response-gate.ps1 | 145 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| response-gate.ps1 | 149 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| response-gate.ps1 | 173 | `await sleep(250);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 256 | `await sleep(300);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 322 | `await sleep(200);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 348 | `await sleep(200);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 356 | `await sleep(150);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 360 | `await sleep(300);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 380 | `await sleep(200);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 392 | `await sleep(300);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 396 | `await sleep(200);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 416 | `await sleep(300);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 419 | `await sleep(200);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 437 | `await sleep(250);` | await window.__htQuiet(10000) |
| response-gate.ps1 | 483 | `Start-Sleep -Milliseconds 500` | kept: poll interval inside a condition loop |
| review-gate.ps1 | 57 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 500); })") }` | WaitQuiet |
| review-gate.ps1 | 96 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| review-gate.ps1 | 108 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| review-gate.ps1 | 114 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| ring-size-gate.ps1 | 430 | `Start-Sleep -Milliseconds 1500` | WaitBoot (after navigate) |
| ring-size-gate.ps1 | 433 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| ring-size-gate.ps1 | 441 | `Start-Sleep -Milliseconds 1500` | WaitBoot (after navigate) |
| ring-size-gate.ps1 | 444 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| ring-size-gate.ps1 | 450 | `Start-Sleep -Milliseconds 200` | WaitQuiet |
| ring-size-gate.ps1 | 453 | `Start-Sleep -Milliseconds 200` | WaitQuiet |
| ring-size-gate.ps1 | 493 | `Start-Sleep -Milliseconds 1500` | WaitBoot (after navigate) |
| ring-size-gate.ps1 | 496 | `Start-Sleep -Milliseconds 300` | WaitQuiet |
| ring-size-gate.ps1 | 537 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| ring-size-gate.ps1 | 547 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| ring-size-gate.ps1 | 558 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| searchmine-gate.ps1 | 68 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| searchmine-gate.ps1 | 115 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| searchmine-gate.ps1 | 127 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| searchmine-gate.ps1 | 133 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| sensor-gate.ps1 | 86 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| sensor-gate.ps1 | 124 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| sensor-gate.ps1 | 136 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| sensor-gate.ps1 | 142 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| sensor-gate.ps1 | 442 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| served-gate.ps1 | 94 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| served-gate.ps1 | 132 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| served-gate.ps1 | 144 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| served-gate.ps1 | 150 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| served-gate.ps1 | 162 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| served-gate.ps1 | 507 | `Start-Sleep -Milliseconds 250` | WaitQuiet |
| stackcheck-gate.ps1 | 70 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| stackcheck-gate.ps1 | 117 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| stackcheck-gate.ps1 | 129 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| stackcheck-gate.ps1 | 135 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| stackcheck-gate.ps1 | 161 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| stackcheck-gate.ps1 | 230 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| stackcheck-gate.ps1 | 282 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| stackcheck-gate.ps1 | 328 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| stackcheck-gate.ps1 | 383 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |
| stackcheck-gate.ps1 | 397 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| stackcheck-gate.ps1 | 432 | `Start-Sleep -Milliseconds 40` | kept: gesture pacing between input events, not a wait |
| stacktotals-gate.ps1 | 73 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| stacktotals-gate.ps1 | 111 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| stacktotals-gate.ps1 | 123 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| stacktotals-gate.ps1 | 129 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| update-gate.ps1 | 119 | `Start-Sleep -Milliseconds 800 + one request` | WaitServer (poll 100 ms, 30 s, then fail) |
| update-gate.ps1 | 129 | `Start-Sleep -Milliseconds 300` | kept: poll interval inside a condition loop |
| update-gate.ps1 | 140 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| update-gate.ps1 | 146 | `Start-Sleep -Seconds 2` | WaitBoot (after navigate) |
| update-gate.ps1 | 157 | `Start-Sleep -Milliseconds 600` | kept: poll interval inside a condition loop |
| update-gate.ps1 | 170 | `Start-Sleep -Milliseconds 600` | kept: poll interval inside a condition loop |
| update-gate.ps1 | 189 | `Start-Sleep -Milliseconds 200` | WaitQuiet |
| weekly-gate.ps1 | 66 | `function Settle { [void](EvalA "new Promise(function (r) { setTimeout(function () { r(1); }, 400); })") }` | WaitQuiet |
| weekly-gate.ps1 | 113 | `Start-Sleep -Milliseconds 600` | WaitServer (poll 100 ms, 30 s, then fail) |
| weekly-gate.ps1 | 125 | `(none)` | Page.addScriptToEvaluateOnNewDocument(quiet.js) |
| weekly-gate.ps1 | 131 | `Start-Sleep -Milliseconds 3000` | WaitBoot (after navigate) |
| weekly-gate.ps1 | 163 | `Start-Sleep -Milliseconds 2500` | WaitBoot (after reload) |

## By hand

| gate | line | old wait | new condition |
|---|---|---|---|
| cold-start-gate.ps1 | ~203 | Start-Sleep -Milliseconds 1500 (after a forced stop) | poll until no browser of this profile remains (100 ms, 30 s) |
| overlay-gate.ps1 | ~200 | Start-Sleep -Milliseconds 420 (after a swipe) | WaitStill: scrollY unchanged for 3 frames, then WaitQuiet |
| overlay-gate.ps1 | ~205 | Start-Sleep -Milliseconds 220 (after a tap) | WaitStill |
| overlay-gate.ps1 | ~206 | Park: Start-Sleep -Milliseconds 280 (after scrollTo) | WaitStill |
| anti-engagement-gate.ps1 | ~320 | await sleep(400) (after opening Trends) | await window.__htQuiet(10000) |
| backup-gate.ps1 | ~229/246/268 | setTimeout 300/400/300 ms promise | window.__htQuiet(10000) |
| entry-gate.ps1 | ~284 | setTimeout 120 ms promise | window.__htQuiet(10000) |
| precedence-gate.ps1 | ~167 | EvalA setTimeout 1200 ms (after typing a search) | WaitQuiet (the typed search answered) |
| stop-cleanup-check.ps1 (not in the suite) | 66 | Start-Sleep -Seconds 3 (after killing the runner) | WaitFor: the runner process gone (20 s) |
| stop-cleanup-check.ps1 (not in the suite) | 78 | Start-Sleep -Seconds 3 (after killing the caller) | WaitFor: no run-all-gates bash left (20 s) |
| close-gate.ps1 | ~192 | WaitQuiet (from Start-Sleep 300 after the close tap) | two drawn frames: the corpus download is HELD on purpose here, so the page cannot be quiet |
| entry-gate.ps1 | 368 | Start-Sleep -Milliseconds 6500 (the Undo bar's life) | poll until the Undo bar is gone (100 ms, 15 s, then FAIL), then WaitQuiet |
| capture-outcome-gate.ps1 | 172 | Start-Sleep -Milliseconds 1600 (a hung capture) | poll until the pending screen shows, counting seconds (100 ms, 15 s): the call hangs on purpose, so the page is never quiet |
| resolve-gate.ps1 | ~221 | await sleep(30) (check the shield while it is up) | two drawn frames: a quiet wait would also wait out the shield's own 600 ms timer |

## Totals

- 234 x await window.__htQuiet(10000)
- 80 x WaitQuiet
- 73 x WaitBoot
- 56 x Page.addScriptToEvaluateOnNewDocument(quiet.js)
- 55 x WaitServer
- 44 x kept: poll interval inside a condition loop
- 10 x kept: gesture pacing between input events, not a wait
- 5 x await window.__htQuiet(10000) -- waits for the app's 600 ms arm timer itself
- 1 x WaitLoaded
- 14 by hand (above)
