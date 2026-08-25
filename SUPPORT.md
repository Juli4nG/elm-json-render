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
| `Badge`         | ✅ | `value` expr; optional `variant` expr drives the `data-state` styling token (the tone class stays keyed on the display text). Tone map idle→neutral, queued/running/stopping→info, done→success, error→danger, keyed on the leading whitespace-delimited token minus a trailing ellipsis. Exposed as `Render.badgeTone`. Honors `on.press` (see *Pressable elements*) |
| `Button`        | ✅ | `label` expr; optional `icon` name; optional `disabled` expr (truthy ⇒ native `disabled`, `jr-button--disabled`, no press handler); `on.press` action. An empty resolved `label` with no `icon` renders nothing at all |
| `Checkbox`      | ✅ | optional `label`, optional two-way `checked` |
| `CountPills`    | ⚠️ | required `bind`; optional `groupBy`, `groupOrder`, `itemNoun`, `itemNounPlural` all falling back to the host's `Render.Options.countPills`, plus `emptyLabel`, which has **no host default** (absent ⇒ the renderer synthesizes `"No <plural> yet"`; resolving to `""` ⇒ no empty-state node). Renders a total plus one pill per group, zero counts dropped; unranked groups sort by descending count then name; `groupOrder` matching is case-insensitive and first-wins on duplicates. Every optional key **fails closed when present but malformed**. The row-payload schema is intentionally loose; rows are grouped by a string field and counted. |
| `Table`         | ✅ | required `columns` (each exactly `key` + `label`) + `bind`; renders a plain row table |
| `Alert`         | ✅ | required `tone` (`info`/`warning`/`danger`) + `message` expr; optional `title` expr |
| `Disclosure`    | ✅ | required `label` expr; optional `open` bool (default `false`) |
| `Iframe`        | ⚠️ | required `src` + `title` exprs. **Origin-pinned**: an `<iframe>` is emitted only for an https `src` whose origin is an exact member of `Render.Options.allowedIframeOrigins`; anything else self-hides or renders a placeholder. An always-on provenance bar is not suppressible from a manifest; it names the embedded origin and disclaims it on behalf of `Render.Options.hostName`, which no manifest prop can reach |

An **unknown component `type` fails the decode** (fail-closed). json-render's own renderer
is fail-open here (warns + renders `null`); we are not.

`GroupedTable` (the 2.x name) and `FindingsTable` (the name before 2.0.0) are both accepted as
**deprecated wire-name aliases for `CountPills`**, so a manifest published against either still
decodes rather than being rejected wholesale.

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
- **Icon buttons.** `Button` takes an optional `icon`, a name from a closed set (`trash`,
  `close`, `external`, `refresh`); anything else is rejected at decode. The renderer draws a
  16px inline SVG in `currentColor` (classes `jr-icon jr-icon--<name>`, `aria-hidden`) before the label and adds
  `jr-button--icon`; an empty resolved label makes it icon-only (`jr-button--icon-only`) with an
  `aria-label`/`title` the renderer supplies per icon. Stock json-render's `Button` has no
  `icon`, so this is a deliberate divergence. Without `icon` the button is byte-for-byte
  unchanged. Contract fixture: `contract/fixtures/icon-button.json`.
- **Disabled buttons.** `Button` takes an optional `disabled` expression. Truthy ⇒ the native
  `disabled` attribute, a `jr-button--disabled` class, and **no press handler wired at all**;
  the handler is the enforcement, the rest is presentation. Absent or falsy ⇒ unchanged. Stock
  json-render's `Button` has no `disabled`, so this is a deliberate divergence.
- **Empty-label buttons render nothing.** With no `icon`, a `Button` whose `label` resolves to
  `""` emits no element. The catalog refuses element-level `visible`, so an empty label is the
  only way a manifest can say "this action does not apply to this row"; emitting an invisible
  `<button>` with a live handler on exactly those rows is the failure mode this closes. An
  `icon` makes an empty label legitimate (icon-only), which is the one exception.
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
`on`/`repeat`), **props** (per-component allowlist, e.g. a stray `visible` on a Button
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
3. **`CountPills` payload is intentionally loose**: the contract does not pin a row
   schema, so rows are grouped by a string field and counted. The words used to count
   them come from the manifest or, failing that, from the host's `Render.Options` —
   except `emptyLabel`, which the renderer synthesizes when neither names it.
4. **`SpecStream` / streaming JSON-Patch** (`data-spec` parts) is out of scope; we
   consume a complete flat `Spec`.

## Strictness changes in 3.0.0

Two decode-time behaviors got stricter. Both are hardening in the same direction as everything
else in this file, both are intentional, and both were audited against the manifests known to
exist (`contract/card.json`, its fixtures, and Exosphere's deployed `card.json` v5) with no
regressions found. They are listed here because they can reject a manifest that 2.x, and the
fork Exosphere vendored, accepted.

1. **A present-but-malformed optional field now rejects the manifest.** Previously eight optional
   fields decoded through `Decode.maybe (Decode.field …)`, which cannot tell "absent" from
   "present and unparseable" and reports both as absent: element `repeat`, `Card.title`,
   `Checkbox.label`, `Checkbox.checked`, `Alert.title`, `repeat.key`, an action binding's
   `confirm`, and `confirm`'s `confirmLabel` / `cancelLabel`. Silently reading a malformed
   `confirm` as absent is the failure that matters: it turns a guarded destructive action into an
   unguarded one, which is exactly the outcome fail-closed exists to prevent. All eight now
   reject. A manifest that was already well-formed is unaffected.

2. **A comparand object carrying any `$`-prefixed key now rejects.** Inside a `$cond`, only
   `{ "$state": "<string>" }` is a legal reference operand. Previously just the `$state` key was
   reserved, so `{ "$computed": … }` or `{ "$item": … }` in operand position degraded to an inert
   object literal — which by the object-inequality rule makes the branch permanently `False`, a
   condition that silently never fires rather than an error anyone sees. Any `$`-prefixed key in
   an operand now fails the decode. A plain object or array literal with no `$`-prefixed key is
   still a legal literal.

Neither change affects a well-formed manifest, and neither loosens anything.
