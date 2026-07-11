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
