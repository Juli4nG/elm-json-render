# elm-json-render

A **native Elm renderer** for [json-render](https://github.com/vercel-labs/json-render) manifests:
decode a json-render flat-`Spec` into typed Elm and render `Html`, with **fail-closed** validation
by construction (strict decoders; no `innerHTML`/script escape hatch).

**Status:** scaffold. This is **Track B** of the CloudShield × Exosphere dynamic-UI work — the
durable, no-build, no-framework path, intended to grow into an open-source package (precedent:
[elm-ui-patternfly](https://lenards.github.io/elm-ui-patternfly/)). See [`PLAN.md`](PLAN.md).

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
