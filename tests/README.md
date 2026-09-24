# Tests

Gate evidence lives here so it is **re-runnable by any future session**, not just
attested once. No Node, no build step — just a headless browser.

## Data layer (Phase 0)

`data-layer.test.html` is a self-contained harness (synthetic fixtures inline)
that exercises the real `../app.js`: the storage adapter, versioned schema, and
one-time `uha-log-v1` migration. It swaps a fake `localStorage` per scenario so
every case — including "storage blocked" — is fully isolated.

Checks (30):

- **Lossless migration** — item counts, per-day kcal totals, statuses, `water_l`,
  and `soluble_fiber_g`-present-on-every-item all preserved; the legacy blob is
  left **byte-identical** (untouched); the new key is written. (DECISIONS.md D2/D4)
- **D2 precedence** — with both keys present the new key wins; legacy-only days are
  **not** resurrected; migration never re-runs.
- **Idempotency** — second boot loads from store; `migratedAt` unchanged.
- **Truthful badge** — a forced write failure *after* load degrades `local → memory`
  and the badge warns to export (baseline rule #5).
- **Private mode** — storage blocked → memory tier, migration does not run.

### Run

```sh
bash tests/run-data-layer.sh
```

Prints each assertion and exits non-zero unless the summary reports `ALL PASS`.
Requires Chrome or Edge. To eyeball it, open `tests/data-layer.test.html` in a
browser directly.

All fixtures are **synthetic** — no real history, per the history-free-repo rule.

## Service worker (Phase 0)

Two checks back the "loads offline" gate (DECISIONS.md D6):

### `check-precache.sh` — precache list is honest

```sh
bash tests/check-precache.sh
```

Parses `PRECACHE` out of `sw.js` and fails if any listed path is missing on
disk. A 404 in `cache.addAll` rejects the whole SW install *silently* and
disables offline — this makes that failure class loud.

### `offline-gate.ps1` — the prod path actually serves offline

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/offline-gate.ps1
```

Canonical offline evidence. A PowerShell `HttpListener` serves the repo on
`127.0.0.1`; headless Chrome/Edge with a persistent profile is forced onto the
**production** cache-first path via `?prod=1` (not the localhost network-first
dev branch). It seeds synthetic history, loads with the server up (SW registers +
precaches), **stops the server**, then reloads — and asserts the shell + seeded
day still render with the origin unreachable. Exit 0 on PASS.

Manual fallback: open the app over `http://localhost`, then DevTools →
Application → Service Workers → check **Offline** → reload → confirm history
renders.

## Capture outcome (R21.5)

### `capture-outcome-gate.ps1` — one explicit outcome, in view without scrolling

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/capture-outcome-gate.ps1
```

"Exactly one outcome, front and centre" is a **layout** claim, so it is measured
as one. A string gate can prove the modal rendered; only a viewport can prove it
was readable without hunting for it — which is the defect this slice removed (the
draft used to render inline in the entry sheet, below two textareas, off the
bottom of a phone).

Drives the **shipped** capture path against the real `index.html` with `fetch`
stubbed, at 360×690, 390×745 and 1200×900, and asserts per state:

- **success** — the confirm-first question, its slider and **both** footer actions
  are fully inside the viewport with the page unscrolled; actions ≥ 44 px tall;
- **success, long list** — the body scrolls and the footer **does not**, so Save
  and Discard stay reachable whatever the item count;
- **failure** — the stated message plus *Try again* and *Paste the response
  manually*, both in view;
- **pending** — the counted spinner and the cancel, in view;
- and in every state, **exactly one** outcome exists: the capture surface carries
  none of it.

Unlike the data-layer suite this runs in **real time**, not under
`--virtual-time-budget`, so it exercises the `createImageBitmap` decoder that D47
recorded as unexercisable in the harness.

Proven against the defect: returning `#photoDraft` to the sheet body fails the
success cases at every width; restoring the second capture-surface paint fails
the pending cases.

## flow (H16 / D123)

### `flow-gate.ps1` — each journey, as a tap count, on the shipped page

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/flow-gate.ps1
```

**Why a CDP gate.** A tap count is a property of the page: which controls exist,
which are reachable, and what a click on a real element does. The harness asserts
the seams underneath (`dayJump` refuses a bad key, a visited day is not created,
the panel remembers its state) and cannot assert “this took four taps”, because
nothing in a DOM-free core knows what a tap is.

Every number it pins was **measured on the shipped page first**, at 390×844:

| journey | was | pinned |
|---|---|---|
| 0 — a past day | **15 taps**, one per day, no other route | ≤ 2, incl. a day with **no record**, and visiting it creates nothing |
| 1 — eat → logged → see my day | 4 | 4, and the day is **offered** |
| 2 — a dose → on the timeline | 4, outcome 1.8 screens below the fold | 4, and the dose is **in view** |
| 3 — a medication → drug info | 8 (3 of them hunting through Settings) | **6** |
| 4 — an old item → the panel | 18 from today | **3** standing on the day |

**It fails by name whenever a journey grows a tap. That is intended and ruled.**
Flow is not asserted once and trusted afterwards — it is a number that drifts one
plausible control at a time, and no other gate in the suite would notice.

## bm slider ergonomics (R20.1)

### `bm-slider-gate.ps1` — the touch target is the stop's zone

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/bm-slider-gate.ps1
```

**What it cannot measure, stated up front.** A native range input's thumb is a
UA-shadow pseudo-element and is not measurable here: `getComputedStyle(el,
'::-webkit-slider-thumb')` returns the **host box** (332×36), and CDP
`DOM.describeNode` with `pierce` reports no pseudoElements. A `>=44` assertion on
the host box would pass for the wrong reason while the real handle was ~16px, so
that assertion is not written.

It measures the thing WCAG 2.5.5 is actually about — **the area a finger must hit
to select a stop**. On a range input a tap anywhere on the track jumps to that
position, so the target is `(trackWidth / 7) × control height`, and the gate
**proves that premise behaviourally** by dispatching real taps at stops 1/3/5/7
and checking which stop comes back.

At 360×740 and 390×745 it asserts: the stop zone clears 44×44; the handle stays
under the stop pitch so it never straddles two stops; and the readout sits
**above** the track — a finger occludes what is under and beside a slider exactly
while sliding, and a mouse never shows that defect.

Proven against the defect: restoring the pre-R20.1 control (36px tall, readout
below the track) fails at both widths.

## Running everything — `run-all-gates.sh`

```sh
bash tests/run-all-gates.sh
GATE_TIMEOUT=900 bash tests/run-all-gates.sh   # per-gate seconds, default 600
```

Runs the data-layer harness, the static checks, and every `*-gate.ps1`, and holds
each to the same bar: **presence and a verdict, or fail — by name.**

A gate must PRINT a `GATE: PASS` / `GATE: FAIL` line. One that prints neither
fails the suite exactly as a missing file does. **There is no third outcome
called silence**, because silence is how this project's recurring defect —
a check that stops checking while everything reports green — keeps arriving:

| outcome | verdict |
|---|---|
| hung past the timeout (`rc=124`) | FAIL — no verdict will ever arrive |
| exited, printed no `GATE:` line | FAIL — present but speechless |
| printed `GATE: FAIL` | FAIL, with the failing measurements echoed |
| `GATE: PASS` but exited non-zero | FAIL — the two disagree, so neither is trusted |
| `GATE: PASS` and exited 0 | PASS |

Run the gates through this, not one at a time by hand. **The hand-run loop is
where the silent skip lived** — a `grep 'GATE:'` prints nothing for an unrunnable
gate and moves on to the next one, and nothing in the repository was wrong.

### Every check is wired, and the count says what it counts (D75)

Every `tests/check-*.sh` is on one of two lists in the runner:

| list | checks | run by |
|---|---|---|
| `STATIC_CHECKS` | `check-guidance.sh`, `check-precache.sh` | the runner, judged like any gate |
| `IN_HARNESS` | `check-sw-hash.sh`, `check-version.sh`, `check-writesites.sh`, `check-zxing.sh` | `run-data-layer.sh`, as preconditions |

A `check-*.sh` on neither list fails the suite as **unwired**. If the harness
stops calling an `IN_HARNESS` check, that check fails as **not-called**. This
matters because the harness itself would still pass. A new check joins one list
in the commit that adds it.

**The count is the number of verdict lines the runner prints:** 1 harness + the
`STATIC_CHECKS` + every `*-gate.ps1`. Today that is 1 + 3 + 10 = **14**. The
`IN_HARNESS` checks are part of the harness's verdict and are not counted again.
Every run prints the sum, and the suite fails if the passes don't add up to it:

```
counted: 1 harness + 3 static + 10 CDP = 14 verdicts (4 more checks run inside the harness and are part of its verdict)
SUITE: PASS (14 of 14 produced a verdict, and every verdict was PASS)
```

**Quote the number together with that line.** A bare count can't be told apart
from a count that lost a gate. Until D75 the runner never ran
`check-precache.sh` or `check-guidance.sh`, while GATES.md counted both.

## Running a defect pass (D60) — two rules learned the hard way

A defect pass plants a known defect, runs a gate, and requires the gate to fail
**by name**. The runner is a scratchpad script, not a committed one, so these two
rules have to live here or they are re-learned every slice.

**1. Only one pass at a time, enforced by a lock.** Two runners sharing `app.js`
do not merely race: each plants while the other measures, so **both** produce
verdicts about a tree neither of them wrote. The output interleaves and reads as a
suite-wide collapse. The runner must take an exclusive lock (`O_CREAT | O_EXCL`)
and refuse to start while one is held. *This was already known in the sibling
collectibles repo, where the same collision happened weeks earlier and a PID lock
was the fix — and it was not ported here. When a harness finding lands in either
repo, check whether the other has the same exposure.*

**2. Read the plant back off the disk, before and after the run.** A run against a
tree that does not carry the plant produces **no failures**, which scores as
VACUOUS — *"your gate is worthless"* — and that is the one verdict shaped like a
reason to go and weaken a gate that is fine. A tree that lost its plant is
**INCONCLUSIVE**, never a verdict about the gate.

**If a pass dies mid-run it leaves the tree planted.** The `finally` block only
helps if the process lives to reach it. The reliable tell is `APP_VERSION` reading
the **plant version** (`x.y.z+1`), which exists only between a plant and its
restore. Check it after any pass that does not report, and do not infer from an
empty process listing that a pass has finished — that inference was made twice in
one session and was wrong both times.

## Environment dependency — antivirus exclusion for `tests/`

The ten `*-gate.ps1` scripts drive headless Chrome over CDP: PowerShell +
`--remote-debugging-port` + synthetic input injection. That profile matches
automation-malware heuristics, and it has been flagged in practice —
**Kaspersky quarantined `bm-slider-gate.ps1` as `PDM:Trojan.Win32.Bazon.a`
mid-session.** A behavioural false positive; the script was fine.

**If a gate script goes missing, suspect the AV before the runner.** The symptom
is `The argument '...' to the -File parameter does not exist`, or a batch run
that silently skips a gate.

```sh
ls tests/*.ps1 | wc -l          # expect 8
git checkout -- tests/<gate>.ps1  # every gate script is committed
```

This machine carries a scoped AV exclusion for `tests/`, **set to all components
— see the RESOLVED note below; the dialog's default scope is not sufficient**. **A
green suite on a machine without that exclusion proves less than it appears to**,
because a quarantined gate does not run and does not say so.

`run-data-layer.sh` now refuses to start on that footing: it opens with a
**gate-script census** against a pinned manifest of the eight names, so a
quarantined script fails the suite loudly and by name, with its `git checkout`
line printed. Adding a ninth gate fails the census until its name joins the
manifest — the same deliberate re-pin `EXPECTED_ASSERTIONS` requires.

### The second AV mode: present, but denied execution

Observed 2026-09-06 on `bm-slider-gate.ps1`:

```
Program 'powershell.exe' failed to run: Access is denied
```

— in one second, reproducibly, with the file **byte-identical to its commit**
and every other CDP gate running clean minutes earlier. It is the **only** gate
that calls `Input.dispatchMouseEvent`, which is the behaviour the detection
fires on.

**The census does not catch this**: it checks presence, and the file is present.
A present-but-unrunnable gate is the same silent skip wearing a new costume —
a loop grepping for `GATE: PASS` prints nothing and moves on. That hole is now
closed by `run-all-gates.sh`, which treats a missing `GATE:` line as a failure
by name; it reports this exact case as:

```
bm-slider-gate.ps1         FAIL - PRODUCED NO VERDICT (rc=126)
      timeout: failed to run command 'powershell.exe': Permission denied
```

### RESOLVED 2026-09-06 — the exclusion must be set to ALL COMPONENTS

**The open question above is answered: a file-scanning exclusion is not enough.**

Kaspersky's exclusion dialog defaults to **Selected components**, which covered
Scan and File Anti-Virus — neither of which was doing the blocking. The block came
from the **proactive-defence module**, and it is not in that default set. Setting
the `tests/` exclusion to **All components** (and restarting Kaspersky) cleared it:
`bm-slider-gate.ps1` now runs its `Input.dispatchMouseEvent` assertions end to end
and reports `BM SLIDER GATE: PASS` with exit 0.

```
tests/  ->  exclusion scope: All components     # NOT "Selected components"
```

### The correction that cost two sessions: it is ONE event, not two modes

The heading above says "the second AV mode", as if quarantine-at-rest and
denied-execution were two states a file could sit in. **They are not.** Watched
across a single run, the sequence is:

1. before the run — file present, byte-identical to its commit, census reads 8 of 8;
2. the suite tries to execute it — `rc=126`, `Permission denied`, in about a second;
3. immediately after — the file is **gone**, from the Git-Bash view as well as Win32.

**The denial and the quarantine are the same event, triggered by the execution
attempt.** The file is untouched on disk until something tries to run it.

This is why `git checkout -- tests/bm-slider-gate.ps1` *looks like it failed*: it
succeeds, the file is genuinely restored and hash-matches HEAD, and then the next
run takes it again. Two sessions were spent re-restoring a file that had restored
correctly every time. **Verify a restore with `git hash-object`, not with the next
suite run** — the suite run is what destroys the evidence.

A mid-run tell, if you need to distinguish this from a real missing file: `icacls`
on the blocked path returns `The system cannot find the file specified` while
`icacls` on any sibling gate resolves normally. The block is path-specific.

### Do not try to evidence a quarantine from the Windows event log

`avp` (Kaspersky) writes to the Windows **Application** log, but with **no message
text registered** — `Get-WinEvent` returns entries whose `Message` is empty, so
there is nothing chasable in them:

```powershell
# dead end — returns Id 4662 entries with empty Message, and nothing for the gate
Get-WinEvent -LogName Application | Where-Object { $_.ProviderName -match 'Kaspersky|avp' }
```

**Kaspersky's own Reports view is the only source that names the detection and the
quarantined path.** Go there first; the event log will only cost time.
