# HealthTracker

A mobile-first, **fully client-side** nutrition and price tracker. No backend, no
accounts, no analytics — all data lives on your device, and export is always one
tap away.

## What it does

- **Photo → nutrients via AI.** Copy the in-app prompt, send it to your AI
  assistant with a meal photo, paste the JSON reply into Ingest. Macros only — a
  photo can't show micronutrients.
- **Scan → nutrients** *(Phase 2)*. Barcode → OpenFoodFacts → macros + labeled
  micronutrients → portion picker → one-tap log at `measured` confidence.
- **Daily log vs goals.** Totals against your floors (protein, fiber) and ceilings
  (kcal, sodium), a progress-vs-goal ring, and 7-day / all-time averages —
  complete days only.
- **Manual entry & presets.** Type an item in (with label micronutrients if you
  have them), and save calibrated presets for one-tap logging.
- **Price intelligence** *(Phase 2+)*. Optional price + store capture, plus nearby
  community prices from Open Prices.

## Privacy — a stated feature

- **All data is local.** It lives in your browser's storage on this device.
  Nothing is sent to any server by the app itself.
- **No accounts, no telemetry, no analytics.**
- **Your data is yours.** Export the full JSON anytime; import it back on any
  device. A truthful storage badge tells you when a save actually happened.
- **Location** is used only when you explicitly ask for nearby prices, is sent
  only as an Open Prices query parameter, and is **never stored**.
- Data from OpenFoodFacts / Open Prices is community-sourced and treated as
  untrusted — every value is escaped and clamped before it's shown.

## Micronutrient honesty

Micronutrients enter the log only from **labeled** sources — a barcode scan or
explicit manual entry from a package label. The AI photo path produces macro
estimates only (never micros), and daily/averaged micro totals show their
coverage ("from N of M items/days") so partial data is visible, never fiction
wearing decimals.

## Running it

Static HTML/CSS/JS — **no build step, no dependencies** (the barcode scanner
lazy-loads one library on demand). Open `index.html` directly, or serve the
folder over any static host. It installs as a home-screen PWA and works offline.

## License

MIT — see [LICENSE](LICENSE).
