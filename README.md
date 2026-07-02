# elm-json-render

A **native Elm renderer** for [json-render](https://github.com/vercel-labs/json-render) manifests:
decode a json-render flat-`Spec` into typed Elm and render `Html`, with **fail-closed** validation
by construction — strict decoders, no `innerHTML`/script escape hatch, so the rendered tree is
XSS-safe by construction.

**Status:** working v1 — decoders, expression/binding resolution, renderers, a small TEA host
interface, 54 passing tests, a demo, and a Playwright conformance snapshot. Pinned to
`@json-render/core` v0.19.0. Precedent for a native Elm renderer of a JS-first format:
[elm-ui-patternfly](https://lenards.github.io/elm-ui-patternfly/).

## Why

json-render ships only JS-framework renderers (React/Svelte/Solid). A native Elm renderer lets a
host Elm app stay native — no JS framework, no bundler, no Elm↔JS bridge — and be fail-closed and
XSS-safe by construction. You depend on json-render's *format* (a spec), not its runtime.

## Install

```sh
elm install Juli4nG/elm-json-render
```

## Usage

The host owns the manifest's `state` (a JSON `Value`) and passes it to the renderer every frame.
Decoding is the security gate: an off-catalog component type, a malformed prop, a dangling child
key, or a missing root all produce `Err` — never a partial tree. User actions flow back out as
`Effect` values the host applies.

```elm
import Html exposing (Html)
import Json.Decode exposing (Value)
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)


type alias Model =
    { spec : Result String Spec   -- decoded once from the manifest JSON
    , renderer : Render.Model      -- renderer-local state (the confirm dialog)
    , hostState : Value            -- you own this; the renderer only reads it
    }


type Msg
    = RendererMsg Render.Msg


init : String -> Value -> Model
init manifestJson hostState =
    { spec = JsonRender.decodeString manifestJson
    , renderer = Render.init
    , hostState = hostState
    }


update : Msg -> Model -> Model
update (RendererMsg rMsg) model =
    let
        ( renderer, effect ) =
            Render.update rMsg model.renderer
    in
    case effect of
        Just (Render.EmitAction { verb, params }) ->
            -- re-check the verb against your allowlist, then run it
            { model | renderer = renderer }

        Just (Render.EmitStateChange { path, value }) ->
            -- apply the write into your own state at `path`
            { model | renderer = renderer }

        Nothing ->
            { model | renderer = renderer }


view : Model -> Html Msg
view model =
    case model.spec of
        Ok spec ->
            Html.map RendererMsg (Render.view spec model.hostState model.renderer)

        Err message ->
            JsonRender.errorStub message
```

The renderer emits plain `Html` with `jr-*` classes; you supply the CSS (see `demo/index.html` for a
complete stylesheet covering card, badge, button, checkbox, findings, and the confirm overlay).

## Modules

- `JsonRender` — facade: `decodeValue` / `decodeString` (fail-closed validation) and `errorStub`.
- `JsonRender.Spec` — the typed spec model + strict, fail-closed decoders.
- `JsonRender.Expr` — the expression dialect (`$state`, `$item`, `$index`, `$bindState`,
  `$bindItem`, `$template`) with RFC 6901 JSON-Pointer resolution.
- `JsonRender.Render` — the TEA renderer (`Model` / `init` / `Msg` / `update` / `Effect` / `view`).

See [`SUPPORT.md`](SUPPORT.md) for exactly which json-render forms are and aren't supported, and how
this renderer deliberately diverges from stock json-render (short version: everything unsupported
**fails the decode**, rather than being silently dropped).

## Scope (v1)

Scoped to a practical component subset — Card, Stack, Text, Badge, Button, Checkbox, the `repeat`
field, and FindingsTable — plus the expression forms above. It grows as new manifests need more.

## Build & verify

```sh
elm make                                             # type-check the package
elm-format --validate src/ tests/
elm-test-rs                                           # unit + program-test (54 tests)
cd conformance && npm install && npm run capture      # demo build + golden snapshot
```

- `demo/` — a host app driving a `queued → running → done` state machine; build with
  `elm make src/Main.elm --output=app.js`.
- `conformance/` — Playwright capture + a shared normalizer + a committed golden snapshot.
- `contract/` — the pinned format reference, the host↔renderer interface, and fixtures.

## License

[MIT](LICENSE) © 2026 Julian Gonzalez
