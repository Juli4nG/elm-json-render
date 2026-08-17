# Supported json-render subset & contract notes

`elm-json-render` implements the json-render **wire format** pinned to
`@json-render/core` v0.19.0 (`contract/pinned-format-reference.md`), **scoped to a
practical subset**. This file records exactly what is and isn't supported, and
where the renderer deliberately diverges from stock json-render. Per the package's
fail-closed stance, "not supported" almost always means **the decoder rejects it**, not
"silently ignored".

## Components (catalog)

| Component       | Supported | Notes |
|-----------------|-----------|-------|
| `Card`          | ✅ | optional `title` expr |
| `Stack`         | ✅ | `direction` (`row`/`col`), `gap`; carries `repeat`; honors `on.press` (see *Pressable elements*) |
| `Text`          | ✅ | required `value` expr; honors `on.press` (see *Pressable elements*) |
| `Badge`         | ✅ | `value` expr; optional `variant` expr drives the `data-state` styling token (the tone class stays keyed on the display text). Tone map idle→neutral, queued/running→info, done→success, error→danger, keyed on the leading whitespace-delimited token. Honors `on.press` (see *Pressable elements*) |
| `Button`        | ✅ | `label` expr; `on.press` action |
| `Checkbox`      | ✅ | optional `label`, optional two-way `checked` |
| `GroupedTable`  | ⚠️ | `bind` + `groupBy`; renders empty-state when `null`, else groups by field. The row-payload schema is intentionally loose; the table groups rows by a string field and counts them. |
| `Table`         | ✅ | required `columns` (each exactly `key` + `label`) + `bind`; renders a plain row table |
| `Alert`         | ✅ | required `tone` (`info`/`warning`/`danger`) + `message` expr; optional `title` expr |
| `Disclosure`    | ✅ | required `label` expr; optional `open` bool (default `false`) |
| `Iframe`        | ⚠️ | required `src` + `title` exprs. **Origin-pinned**: an `<iframe>` is emitted only for an https `src` whose origin is an exact member of the host-supplied allowlist passed to `Render.view`; anything else self-hides or renders a placeholder. An always-on provenance bar is not suppressible from a manifest |

An **unknown component `type` fails the decode** (fail-closed). json-render's own renderer
is fail-open here (warns + renders `null`); we are not.

`FindingsTable` is accepted as a **deprecated wire-name alias for `GroupedTable`** (its name
before 2.0.0), so a pre-2.0.0 manifest still decodes rather than being rejected wholesale.

## Expression / binding forms

| Form | Supported | Notes |
|------|-----------|-------|
| `{ "$state": "/ptr" }`      | ✅ | RFC 6901 read |
| `{ "$item": "field" }`      | ✅ | item-value in props; absolute **path** at top-level of action params, **value** when nested (pinned §5.1) |
| `{ "$index": true }`        | ✅ | repeat index |
| `{ "$bindState": "/ptr" }`  | ✅ | two-way; write-back = the pointer |
| `{ "$bindItem": "field" }`  | ✅ | two-way; write-back = `basePath ++ "/" ++ field` (whole-item `""` → `basePath`, no trailing slash) |
| `{ "$template": "…${/ptr}…${bare}…" }` | ✅ | `${/abs}` → state; `${bare}` → item-first then state |
| `{ "$cond": …, "$then": …, "$else": … }` | ✅ | Core's conditional. `$cond` is the full `VisibilityCondition` grammar (`$state`/`$item`/`$index` sources; `eq`/`neq`/`gt`/`gte`/`lt`/`lte`/`not`; `{$state}` operand refs; bare-array/`$and`/`$or` composition). Both branches are expressions (recursive). Must carry exactly `$cond`/`$then`/`$else`; malformed conditions fail-closed. |
| `{ "$computed": "fn", "args": … }` | ❌ | **rejected at decode.** Needs a host function registry; out of scope for v1. |
| unknown `$foo` directive    | ❌ | **rejected at decode** (stock json-render is fail-open and keeps it verbatim; we fail-closed). |
| directive object with extra non-`$` siblings | ❌ | **rejected**: a directive must be the only key, else its siblings would be silently dropped. |

## Element-level fields

| Field | Supported | Notes |
|-------|-----------|-------|
| `type` / `props` / `children` / `on` / `repeat` | ✅ | |
| `visible` | ❌ | **rejected at decode.** The `VisibilityCondition` grammar itself is now implemented (see `$cond` above), but it is not yet wired as an element-level `visible`/`hidden` gate; a manifest relying on `visible` to hide a control must fail closed rather than render it unconditionally. |
| `watch`   | ❌ | **rejected at decode.** Not used by the v1 subset. |

## Actions

- `on.press` → an `Effect` (`EmitAction { verb, params }`) the host applies. The renderer
  never executes the verb (no URL/`navigate`/`fetch` is ever wired, per the trust model).
- **Pressable elements.** `on.press` is honored on `Button`, `Text`, `Badge` and `Stack`.
  Stock json-render wires it on `Button` only, so this is a deliberate divergence (a manifest
  can make a whole row activate). A non-`Button` element carrying a press binding renders with
  `role="button"`, `tabindex="0"` and the class `jr-pressable` (the host's styling hook), and
  activates on click **and** on Enter / Space; any other key is ignored (the decoder fails, so
  the event is left untouched). Without a binding the element is byte-for-byte unchanged: no
  class, no role, no tabindex, no handlers. Click and keydown stop propagation, so a pressable
  nested inside a pressable emits exactly one action, the innermost. A `Checkbox` inside a
  pressable `Stack` is the exception (its click is not a press binding): it toggles *and*
  presses the stack, so do not nest one there. Contract fixture:
  `contract/fixtures/pressable.json`.
- An `ActionBinding` accepts **only** `action`, `params`, `confirm`. Unsupported fields
  (`onSuccess`, `onError`, `preventDefault`) are **rejected at decode**, not silently
  dropped; declared follow-up/error behavior must fail closed, not vanish.
- `confirm` is honored by the renderer (it owns the dialog) and only emits on accept.
  Confirm accepts only `title`/`message`/`confirmLabel`/`cancelLabel`/`variant`.
- **Multiple bindings per event are rejected at decode.** json-render allows `on.press`
  to be an `ActionBinding[]`; the v1 subset uses exactly one. An array of length ≠ 1 fails the
  decode (a single-element array is accepted) rather than silently truncating to the first.
- Built-in runtime verbs (`setState`/`pushState`/`removeState`/`push`/`pop`/`validateForm`)
  are **not** implemented as renderer built-ins; every verb surfaces to the host, which
  owns all state writes. Checkbox two-way writes surface as `EmitStateChange`.

## Strictness summary (fail-closed key allowlists)

Elm decoders ignore unknown object keys by default; this renderer rejects them instead,
so unsupported contract surface fails closed rather than rendering with silently-dropped
semantics. Enforced via `rejectUnknownKeys` on: **element** (`type`/`props`/`children`/
`on`/`repeat`), **props** (per-component allowlist, e.g. a stray `disabled` on a Button
fails), **action binding** (`action`/`params`/`confirm`), **confirm**, and **repeat**.

**Optional fields fail closed too.** An optional field that is *present but malformed* is
rejected, never decoded as absent: a `confirm` block missing its `message`, a malformed
`repeat`, a `$computed` in a Checkbox `checked` or an Alert `title` all fail the decode
rather than silently degrading to a button with no dialog or an element rendered once.

## Deviations from the contract / stock json-render

1. **Fail-closed everywhere.** Stock json-render's renderer is fail-open (unknown
   type/child/action/directive → warn + skip). This renderer pushes all of that to the
   **decoder**, which rejects on any off-catalog/structural/unsupported input, and the
   host shows an error stub. This divergence is intentional and is the security floor of
   the package.
2. **Structural validation is built into the decoder** (missing root, dangling child key,
   `repeat` without children) rather than a separate opt-in `validateSpec` pass.
3. **`GroupedTable` payload is intentionally loose**: the contract does not pin a row
   schema, so the table groups rows by a string field and counts them.
4. **`SpecStream` / streaming JSON-Patch** (`data-spec` parts) is out of scope; we
   consume a complete flat `Spec`.
