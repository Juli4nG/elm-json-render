# elm-json-render

A **native Elm renderer** for [json-render](https://github.com/vercel-labs/json-render) manifests:
decode a json-render flat-`Spec` into typed Elm and render `Html`, with **fail-closed** validation
by construction (strict decoders; no `innerHTML`/script escape hatch).

**Status:** working v1 — decoders, expression/binding resolution, renderers, host
interface, tests (48 green), demo, and a Playwright conformance snapshot. This is
**Track B** of the CloudShield × Exosphere dynamic-UI work — the durable, no-build,
no-framework path, intended to grow into an open-source package (precedent:
[elm-ui-patternfly](https://lenards.github.io/elm-ui-patternfly/)). See [`PLAN.md`](PLAN.md).

## Layout

- `src/JsonRender/` — the package: `Spec` (fail-closed decoders), `Expr` (expression
  dialect + RFC 6901 pointers), `Render` (TEA component → `Html`), and the `JsonRender`
  facade (`decode` / `errorStub`).
- `tests/` — `elm-test-rs` unit suites + an `elm-program-test` suite. Run: `elm-test-rs`.
- `demo/` — a host application driving the fixture state machine; build with
  `elm make src/Main.elm --output=app.js` (or `cd conformance && npm run build-demo`).
- `conformance/` — Playwright capture + shared normalizer + the committed golden snapshot
  for diffing against Track A. See [`conformance/README.md`](conformance/README.md).
- [`SUPPORT.md`](SUPPORT.md) — exactly which json-render forms are / aren't supported, and
  deviations from the contract.

## Build & verify

```sh
elm make                       # type-check the package (all exposed modules)
elm-format --validate src/ tests/
elm-test-rs                    # unit + program-test
cd conformance && npm install && npm run capture   # demo build + golden snapshot
```

## Why

json-render ships only JS-framework renderers (React/Svelte/Solid). A native Elm renderer keeps a
host Elm app (Exosphere) native — no JS framework, no bundler, no Elm↔JS bridge — and is
fail-closed + XSS-safe by construction. We depend on json-render's *format* (a spec), not its code.

## Scope (v1)

Scoped to the components the CloudShield card uses (Card, Stack, Text, Badge, Button, Checkbox, the
`repeat` field, FindingsTable) and the expression forms it needs (`$state`, `$item`,
`$bindState`/`$bindItem`, `$template`). Grows as new cards need more.

## Contract

See [`contract/`](contract/): `card.json`, `host-renderer-interface.md`,
`pinned-format-reference.md`, `fixtures/`. Pinned to `@json-render/core` v0.19.0 @ `e2d00fa`.

> The planning repo (`bnr`) is the source of truth for the contract; the copies here track it.

## License

Private for now. Intended MIT when public.
