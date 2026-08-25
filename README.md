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

**Status:** v3. Decoders, expression and binding resolution, renderers, a small TEA host
interface, 237 passing tests, a runnable demo, and a browser-based conformance snapshot.
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
            Html.map RendererMsg
                (Render.view options spec model.hostState model.renderer)

        Err message ->
            JsonRender.errorStub message


{-| What you tell the renderer about yourself.

`allowedIframeOrigins` is the iframe origin allowlist: an `Iframe` element renders only
when its resolved `src` is an https URL whose origin is an exact member of this list.
Keep it `[]` unless you deliberately embed something.

`hostName` is what the iframe provenance bar disclaims on behalf of ("not verified by
<hostName>"). Name your app: a disclaimer reads as a promise from whoever is named in it,
and readers skim a generic one.

`countPills` is the vocabulary a `CountPills` element falls back to when the manifest does
not name its own. `Render.defaultOptions` is exactly this record with `[]`, "the host
application" and plain "items", so start there and override what you care about.
-}
options : Render.Options
options =
    { allowedIframeOrigins = []
    , hostName = "Acme Console"
    , countPills =
        { groupBy = "severity"
        , groupOrder = [ "critical", "high", "medium", "low", "info" ]
        , itemNoun = "finding"
        , itemNounPlural = "findings"
        }
    }
```

The renderer emits plain `Html` with `jr-*` classes and no styling of its own; you supply
the CSS. See `demo/index.html` for a complete stylesheet covering every component, plus the
confirm-dialog overlay.

## Pressable elements

`on: { press: … }` is not just for `Button`. `Text`, `Badge` and `Stack` honor the same
single binding, so a manifest can make a status badge, a label, or a whole row activate an
action:

```json
"row": {
  "type": "Stack",
  "props": { "direction": "row", "gap": 2 },
  "on": { "press": { "action": "row.open", "params": { "resultId": { "$item": "id" } } } },
  "children": ["row-name", "row-status"]
}
```

An element carrying a press binding renders with `role="button"`, `tabindex="0"` and the
class `jr-pressable` (your styling hook for cursor, hover and `:focus-visible`), and
activates on click as well as on Enter and Space. Any other key is left alone. `confirm`
works exactly as it does on a button.

An element with no press binding renders exactly as it always did: no class, no role, no
tabindex, no handlers.

Click and keydown stop propagation, so a pressable nested inside a pressable (a row `Stack`
holding a pressable `Text` with its own action) fires exactly one action, the innermost one.
A `Checkbox` inside a pressable `Stack` is the one exception, because its click is not a
press binding: it toggles *and* presses the stack. Keep checkboxes out of pressable stacks.

## Icon buttons

`Button` takes an optional `icon`. It is a **name from a closed set** — `"trash"`, `"close"`,
`"external"`, `"refresh"` — never markup and never an expression: the renderer draws the glyph
itself, so a manifest you did not write cannot hand you an image.

```json
"row-remove": {
  "type": "Button",
  "props": { "label": "", "icon": "trash" },
  "on": { "press": { "action": "row.remove", "params": { "resultId": { "$item": "id" } } } },
  "children": []
}
```

The glyph is a 16px inline SVG in `currentColor` (classes `jr-icon jr-icon--<name>`,
`aria-hidden`), placed before the label, and the button gains `jr-button--icon`. The per-glyph
class is your hook for styling one shape differently — a destructive hover on `jr-icon--trash`,
say — without the manifest getting a say in it. A non-empty label stays visible beside it.

An **empty** resolved label makes the button icon-only: it gains `jr-button--icon-only`, renders
no text, and the renderer supplies `aria-label` and `title` per icon (`trash` → "Remove",
`close` → "Close", `external` → "Open", `refresh` → "Refresh"). The manifest cannot name a shape,
so the renderer does; the alternative is a control that is invisible to a screen reader.

Sizing and hover tone are yours, as with every `jr-*` class. A button with no `icon` renders
exactly what it always did.

## Disabled and absent buttons

`Button` takes an optional `disabled` expression. When it resolves truthy the button gets the
native `disabled` attribute, a `jr-button--disabled` class, and **no press handler at all**. The
last one is the part that holds; the other two are presentation.

```json
"cancel": {
  "type": "Button",
  "props": { "label": "Cancel", "disabled": { "$state": "/busy" } },
  "on": { "press": { "action": "run.cancel", "params": {} } }
}
```

An **empty resolved label with no icon renders nothing at all**. The catalog has no `visible`
prop on purpose, so collapsing the label to `""` is the only way a manifest can say "this action
does not apply to this row" — typically a per-row `$cond`. Emitting a button anyway would leave
an invisible control with a live handler on exactly the rows where the press carries no id.

Disabled and absent are different states: disabled means "here but unavailable" and stays where
the eye expects it, empty-label means "not applicable" and goes away.

## Counting rows

`CountPills` takes an array of records and renders a total plus one pill per group. The renderer
counts and orders; the words are yours.

```json
"results": {
  "type": "CountPills",
  "props": {
    "bind": { "$state": "/results" },
    "groupBy": "severity",
    "groupOrder": ["critical", "high", "medium", "low", "info"],
    "itemNoun": "finding",
    "itemNounPlural": "findings",
    "emptyLabel": "No vulnerabilities found"
  }
}
```

Every key but `bind` is optional. `groupBy`, `groupOrder`, `itemNoun` and `itemNounPlural`
fall back to the `countPills` field of your `Render.Options`; that split is what lets a manifest
published before these keys existed keep rendering in your vocabulary rather than in the
renderer's. `emptyLabel` is the exception and has no host default — see below.

Optional is not lenient. A key that is present but malformed (a null `groupBy`, a `groupOrder`
with a non-string member, a `$computed` in `emptyLabel`) rejects the whole manifest rather than
decoding as absent.

Groups your `groupOrder` does not name sort after the ones it does, by descending count then
name, which is also what an empty order does to everything. Zero counts are dropped. Matching is
case-insensitive, and a value listed twice takes its first position.

`emptyLabel` is what an empty table says, and it is the one key with no host default. Absent, the
renderer synthesizes "No `<plural>` yet" from whichever plural is in play, which is right for a
table with nothing bound yet and wrong for a completed, genuinely empty one — only the publisher
knows which, so it supplies the string. Resolving it to the empty string renders no empty-state
node at all.

Markup is `div.jr-counts` with a `span.jr-counts__total` and one
`span.jr-counts__pill.jr-counts__pill--<group>` per group, each holding a `__dot`, a `__count`
and a `__label`. The per-group modifier is your hook for tinting the dot.

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

`errorStub` prints the decoder's diagnostic verbatim, which suits a developer and does not suit
an end user. If your host has a real audience, pass the message to `Spec.errorKind` and write
your own copy:

- `UnknownCatalogSurface` — the manifest named a component type, an icon, or any other key
  this build does not have: a prop key, but also an unsupported element key (`visible`,
  `watch`), action-binding key (`onSuccess`), confirm key, `repeat` key or `Table` column key. The honest reading is that the publisher is describing an interface a
  newer renderer would understand, so "this app may need updating" is a real thing to say.
- `Malformed` — everything else. Nothing suggests a newer renderer would fare better, so the
  message should say the refusal is deliberate and point at the publisher.

The classifier lives next to the `Decode.fail` arms it classifies and reads the same strings
those arms are built from, so rewording a diagnostic cannot silently break it. One known limit:
`Decode.errorToString` prints the offending JSON, so a malformed manifest whose own data quotes
one of those strings is read as skew. That picks the wrong sentence and nothing else — both kinds
still refuse to render.

Actions are inert by design. The renderer never navigates, fetches, or executes anything.
Every action surfaces to the host as an `Effect`, and the host decides what runs.

## Modules

- `JsonRender`: the entry point. `decodeValue` / `decodeString` (strict validation) and
  `errorStub` (the failure view).
- `JsonRender.Spec`: the typed spec model and its decoders, plus `errorKind` for turning a
  decode failure into a sentence a reader can act on.
- `JsonRender.Expr`: the expression dialect (`$state`, `$item`, `$index`, `$bindState`,
  `$bindItem`, `$template`, `$cond`) with RFC 6901 JSON Pointer resolution.
- `JsonRender.Render`: the TEA renderer (`Model` / `init` / `Msg` / `update` / `Effect` /
  `Options` / `view`).

## Supported subset

Components: `Card`, `Stack`, `Text`, `Badge`, `Button`, `Checkbox`, `CountPills`
(a counted, grouped pill summary), `Table`, `Alert`, `Disclosure`, and `Iframe` (origin-pinned
to a host-supplied allowlist), plus the `repeat` field for iterating a state array. Expressions:
the seven `$` forms listed above, `$cond` included. Anything outside this subset fails the
decode.

See [`SUPPORT.md`](SUPPORT.md) for the full support matrix: exactly which json-render forms
are accepted, which are rejected, and where this renderer deliberately diverges from the
stock ones.

## Development

```sh
elm make                                          # type-check the package
elm-format --validate src/ tests/
elm-test-rs                                       # unit + program tests (237 tests)
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
