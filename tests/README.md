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

Runs the data-layer harness and every `*-gate.ps1`, and holds each to the same
bar: **presence and a verdict, or fail — by name.**

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

## Environment dependency — antivirus exclusion for `tests/`

The eight `*-gate.ps1` scripts drive headless Chrome over CDP: PowerShell +
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

This machine carries a scoped AV exclusion for `tests/`. **A green suite on a
machine without that exclusion proves less than it appears to**, because a
quarantined gate does not run and does not say so.

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

A file-scanning exclusion for `tests/` may not be enough; this block is on
*execution* of that path, so the proactive-defence module likely needs the
exclusion too.
