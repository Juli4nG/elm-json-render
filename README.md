# elm-json-render

Render [json-render](https://github.com/vercel-labs/json-render) UI manifests in pure Elm.

json-render is a JSON format for describing a user interface: a tree of components (cards,
text, buttons, checkboxes), values bound to a state object, and named actions that fire when
the user interacts. Your app receives that JSON at runtime, perhaps from a server, a plugin,
or an LLM, and this package turns it into plain Elm `Html`.

The package is strict on purpose. A manifest either decodes completely into typed Elm values,
or it is rejected with a diagnostic and nothing renders. There is no `innerHTML`, no script
escape hatch, and no "unknown component, skip it" fallback. If you are rendering UI you did
not write yourself, that strictness is the point.

**Status:** v1. Decoders, expression and binding resolution, renderers, a small TEA host
interface, 54 passing tests, a runnable demo, and a browser-based conformance snapshot.
Pinned to the wire format of `@json-render/core` v0.19.0.

## Why

json-render ships only JS-framework renderers (React, Svelte, Solid). A native Elm renderer
lets a host Elm app stay native: no JS framework, no bundler, no ports bridge. It also lets
the renderer be fail-closed and XSS-safe by construction. You depend on json-render's
*format* (a spec), not its runtime.

## Install

```sh
elm install Juli4nG/elm-json-render
```

## A complete example

Here is a small manifest. It is a card with a title, a line of text interpolated from state,
a checkbox bound two-way to a state field, and a button that emits a named action (with a
confirmation dialog):

```json
{
  "root": "card",
  "elements": {
    "card": {
      "type": "Card",
      "props": { "title": "Deployment" },
      "children": [ "status", "notify", "deploy" ]
    },
    "status": {
      "type": "Text",
      "props": { "value": { "$template": "Environment: ${/env} (${/status})" } }
    },
    "notify": {
      "type": "Checkbox",
      "props": {
        "label": "Notify me when it finishes",
        "checked": { "$bindState": "/notify" }
      }
    },
    "deploy": {
      "type": "Button",
      "props": { "label": "Deploy" },
      "on": {
        "press": {
          "action": "deploy.start",
          "params": { "env": { "$state": "/env" } },
          "confirm": {
            "title": "Start deployment?",
            "message": { "$template": "This will deploy to ${/env}." }
          }
        }
      }
    }
  },
  "state": { "env": "staging", "status": "idle", "notify": false }
}
```

A few things to notice:

- `elements` is a flat map. Children are referenced by key (`"children": [ "status", ... ]`),
  never nested inline.
- Dynamic values are single-key `$` objects: `{ "$state": "/env" }` reads state at an
  RFC 6901 JSON Pointer, `{ "$bindState": "/notify" }` binds two-way, `{ "$template": ... }`
  interpolates.
- The button does not do anything by itself. It emits `deploy.start` with resolved params,
  and your app decides what that verb means.

And here is the host side. The host owns the manifest's `state` (a JSON `Value`) and passes
it to the renderer on every frame. User interactions come back out as `Effect` values that
the host applies:

```elm
import Html exposing (Html)
import Json.Decode exposing (Value)
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)


type alias Model =
    { spec : Result String Spec -- decoded once from the manifest JSON
    , renderer : Render.Model -- renderer-local state (the confirm dialog)
    , hostState : Value -- you own this; the renderer only reads it
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
            -- e.g. verb == "deploy.start", params == {"env": "staging"}.
            -- Check the verb against your allowlist, then perform it.
            { model | renderer = renderer }

        Just (Render.EmitStateChange { path, value }) ->
            -- e.g. the checkbox toggled: path == "/notify", value == true.
            -- Write it into your own state at that JSON Pointer.
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

The renderer emits plain `Html` with `jr-*` classes and no styling of its own; you supply
the CSS. See `demo/index.html` for a complete stylesheet covering every component, plus the
confirm-dialog overlay.

## How validation works

Decoding is the security gate. The decoder rejects, rather than silently dropping:

- an unknown component `type` (only the catalog below is accepted);
- props that do not match the strict per-component shape, including unknown prop keys;
- an unsupported `$` directive, or a `$` directive object carrying extra keys;
- a dangling child key, a missing root, or a `repeat` element with no children;
- element fields and action fields this package does not implement (for example `visible`:
  a manifest that relies on `visible` to hide a control must fail, not render the control
  unconditionally).

A rejected manifest never produces a partial tree. You get an `Err` with a diagnostic, and
`errorStub` gives you a self-contained fallback view. Note that this is deliberately stricter
than json-render's own renderers, which warn and skip on unknown input.

Actions are inert by design. The renderer never navigates, fetches, or executes anything.
Every action surfaces to the host as an `Effect`, and the host decides what runs.

## Modules

- `JsonRender`: the entry point. `decodeValue` / `decodeString` (strict validation) and
  `errorStub` (the failure view).
- `JsonRender.Spec`: the typed spec model and its decoders.
- `JsonRender.Expr`: the expression dialect (`$state`, `$item`, `$index`, `$bindState`,
  `$bindItem`, `$template`) with RFC 6901 JSON Pointer resolution.
- `JsonRender.Render`: the TEA renderer (`Model` / `init` / `Msg` / `update` / `Effect` /
  `view`).

## Supported subset (v1)

Components: `Card`, `Stack`, `Text`, `Badge`, `Button`, `Checkbox`, `GroupedTable`
(a grouped summary table), plus the `repeat` field for iterating a state array. Expressions:
the six `$` forms listed above. Anything outside this subset fails the decode.

See [`SUPPORT.md`](SUPPORT.md) for the full support matrix: exactly which json-render forms
are accepted, which are rejected, and where this renderer deliberately diverges from the
stock ones.

## Development

```sh
elm make                                          # type-check the package
elm-format --validate src/ tests/
elm-test-rs                                       # unit + program tests (54 tests)
cd conformance && npm install && npm run capture  # demo build + golden snapshot
```

Repository layout:

- `demo/`: a host app driving a queued / running / done status lifecycle; build with
  `elm make src/Main.elm --output=app.js`.
- `conformance/`: a Playwright capture, a shared HTML normalizer, and a committed golden
  snapshot, used to verify this renderer's output byte-for-byte against other renderers of
  the same fixtures.
- `contract/`: the pinned json-render wire-format reference, the host and renderer
  interface, and shared fixtures.

## License

[MIT](LICENSE) © 2026 Julian Gonzalez
