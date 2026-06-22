# Supported json-render subset & contract notes

`elm-json-render` implements the json-render **wire format** pinned to
`@json-render/core` v0.19.0 (`contract/pinned-format-reference.md`), **scoped to the
CloudShield card's needs**. This file records exactly what is and isn't supported, and
where the renderer deliberately diverges from stock json-render. Per the package's
fail-closed stance, "not supported" almost always means **the decoder rejects it**, not
"silently ignored".

## Components (catalog)

| Component       | Supported | Notes |
|-----------------|-----------|-------|
| `Card`          | ✅ | optional `title` expr |
| `Stack`         | ✅ | `direction` (`row`/`col`), `gap`; carries `repeat` |
| `Text`          | ✅ | required `value` expr |
| `Badge`         | ✅ | `value` expr; tone map idle→neutral, queued/running→info, done→success, error→danger |
| `Button`        | ✅ | `label` expr; `on.press` action |
| `Checkbox`      | ✅ | optional `label`, optional two-way `checked` |
| `FindingsTable` | ⚠️ | `bind` + `groupBy`; renders empty-state when `null`, else groups by field. **Findings payload schema is not pinned by the contract** — implemented minimally; revisit when Track A pins it. |

An **unknown component `type` fails the decode** (fail-closed). json-render's own renderer
is fail-open here (warns + renders `null`); we are not.

## Expression / binding forms

| Form | Supported | Notes |
|------|-----------|-------|
| `{ "$state": "/ptr" }`      | ✅ | RFC 6901 read |
| `{ "$item": "field" }`      | ✅ | item-value in props; absolute **path** at top-level of action params, **value** when nested (pinned §5.1) |
| `{ "$index": true }`        | ✅ | repeat index |
| `{ "$bindState": "/ptr" }`  | ✅ | two-way; write-back = the pointer |
| `{ "$bindItem": "field" }`  | ✅ | two-way; write-back = `basePath ++ "/" ++ field` (whole-item `""` → `basePath`, no trailing slash) |
| `{ "$template": "…${/ptr}…${bare}…" }` | ✅ | `${/abs}` → state; `${bare}` → item-first then state |
| `{ "$cond": …, "$then": …, "$else": … }` | ❌ | **rejected at decode.** Not needed by the card; add when one needs it. |
| `{ "$computed": "fn", "args": … }` | ❌ | **rejected at decode.** Needs a host function registry; out of scope for v1. |
| unknown `$foo` directive    | ❌ | **rejected at decode** (stock json-render is fail-open and keeps it verbatim; we fail-closed). |
| directive object with extra non-`$` siblings | ❌ | **rejected** — a directive must be the only key, else its siblings would be silently dropped. |

## Element-level fields

| Field | Supported | Notes |
|-------|-----------|-------|
| `type` / `props` / `children` / `on` / `repeat` | ✅ | |
| `visible` | ❌ | **rejected at decode.** json-render's `VisibilityCondition` is not implemented; a manifest relying on `visible` to hide a control must fail closed rather than render it unconditionally. |
| `watch`   | ❌ | **rejected at decode.** Not used by the card. |

## Actions

- `on.press` → an `Effect` (`EmitAction { verb, params }`) the host applies. The renderer
  never executes the verb (no URL/`navigate`/`fetch` is ever wired, per the trust model).
- An `ActionBinding` accepts **only** `action`, `params`, `confirm`. Unsupported fields
  (`onSuccess`, `onError`, `preventDefault`) are **rejected at decode**, not silently
  dropped — declared follow-up/error behavior must fail closed, not vanish.
- `confirm` is honored by the renderer (it owns the dialog) and only emits on accept.
  Confirm accepts only `title`/`message`/`confirmLabel`/`cancelLabel`/`variant`.
- **Multiple bindings per event are rejected at decode.** json-render allows `on.press`
  to be an `ActionBinding[]`; the card uses exactly one. An array of length ≠ 1 fails the
  decode (a single-element array is accepted) rather than silently truncating to the first.
- Built-in runtime verbs (`setState`/`pushState`/`removeState`/`push`/`pop`/`validateForm`)
  are **not** implemented as renderer built-ins — every verb surfaces to the host, which
  owns all state writes. Checkbox two-way writes surface as `EmitStateChange`.

## Strictness summary (fail-closed key allowlists)

Elm decoders ignore unknown object keys by default; this renderer rejects them instead,
so unsupported contract surface fails closed rather than rendering with silently-dropped
semantics. Enforced via `rejectUnknownKeys` on: **element** (`type`/`props`/`children`/
`on`/`repeat`), **props** (per-component allowlist — e.g. a stray `disabled` on a Button
fails), **action binding** (`action`/`params`/`confirm`), **confirm**, and **repeat**.

## Deviations from the contract / stock json-render

1. **Fail-closed everywhere.** Stock json-render's renderer is fail-open (unknown
   type/child/action/directive → warn + skip). This renderer pushes all of that to the
   **decoder**, which rejects on any off-catalog/structural/unsupported input, and the
   host shows an error stub. This is intentional (`contract/pinned-format-reference.md` §6,
   "fail-closed is ours") and the security floor of the package.
2. **Structural validation is built into the decoder** (missing root, dangling child key,
   `repeat` without children) rather than a separate opt-in `validateSpec` pass.
3. **`FindingsTable` payload is underspecified** by the contract; the minimal grouped
   rendering here is provisional and should be reconciled with Track A once the findings
   schema is pinned.
4. **`SpecStream` / streaming JSON-Patch** (`data-spec` parts) is out of scope — we
   consume a complete flat `Spec`.
