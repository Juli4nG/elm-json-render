# Conformance harness

Captures the native Elm renderer's rendered HTML in a real browser and normalizes it to
a stable snapshot, so **Track A** (the Solid custom-element island) and **Track B** (this
renderer) can be diffed byte-for-byte from the **same fixtures**.

## What it does

1. `build-demo` regenerates the Elm fixtures from `../contract/` and compiles the demo
   (`../demo/src/Main.elm` → `../demo/app.js`).
2. `capture.mjs` loads `../demo/index.html?scenario=final` in the locally-installed
   Google Chrome (via `playwright-core`, `channel: "chrome"` — no browser download),
   waits for `.jr-root`, and runs the shared [`normalize.mjs`](normalize.mjs) over it.
3. The normalized HTML is written to [`golden.elm.normalized.html`](golden.elm.normalized.html)
   (committed — it's the artifact Track A diffs against).

The `final` scenario is the deterministic terminal state of the fixture state machine
(`../contract/fixtures/state-machine.md`): all four instances scanned, `batch-worker-07`
in the error branch, every row selected.

## Run it

```sh
cd conformance
npm install        # playwright-core only; uses your installed Chrome
npm run capture    # builds the demo, drives Chrome, writes the golden
```

## The normalizer (the contract between tracks)

[`normalize.mjs`](normalize.mjs) keeps only what the contract pins and both frameworks
must agree on:

- the tag tree and text content;
- `jr-*` classes (class-token order sorted);
- a small structural attribute allowlist (`type`, `data-state`, `data-gap`) plus the
  `checked` **property** (read off `el.checked`, since both Elm and Solid set the
  property, not the attribute).

Everything frameworks legitimately differ on — event wiring, inline styles, attribute
order/whitespace — is dropped. Track A imports the **same** `normalize.mjs`, so a passing
conformance check is `diff golden.elm.normalized.html golden.solid.normalized.html` → empty.
