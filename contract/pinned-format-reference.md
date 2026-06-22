# json-render — Pinned Wire-Format Reference (real dialect)

**Source of truth:** `github.com/vercel-labs/json-render` @ commit `e2d00fa`
(HEAD of default branch, 2026-06-15). `@json-render/core` **v0.19.0**
(`packages/core/package.json`), `zod ^4.3.6`. Renderer packages reviewed:
`@json-render/react`, `@json-render/solid`, `@json-render/svelte` (all v0.19.0).
Pinned from source by the Phase 1 Part 1 workflow (3 independent from-source pin
reports, reconciled; the claim with a file+symbol citation wins).

This is the wire format BOTH renderers (Solid island + native Elm) MUST implement.
It is the *format* we adopt as the AI-generation target — NOT json-render's renderer.
**Fail-closed is ours:** the json-render renderer is fail-OPEN by default (see §6);
we validate against our catalog and refuse to mount on any error.

---

## 1. Spec / manifest model — flat element map

`packages/core/src/types.ts:172` (`interface Spec`):

```ts
interface Spec {
  root: string;                          // root element key
  elements: Record<string, UIElement>;   // FLAT map keyed by id
  state?: Record<string, unknown>;       // optional initial state (JSON-Pointer addressable)
}
```

- Exactly three fields: `root`, `elements`, `state`. **No `version`, no `meta`.**
  (Our manifest *envelope* — `schemaVersion`, `catalog`, `publisher` — wraps this
  `Spec` as its `ui` body; the envelope is ours, not json-render's. See spec §1.)
- Children are referenced by **string keys** into `elements`, never nested inline.
- A human-authored **nested** form exists (`children: NestedNode[]`) and is converted
  to the flat `Spec` by `nestedToFlat()` (`types.ts:688`, auto-keys `el-0`, `el-1`, …).
  The **flat form is canonical**; renderers consume `Spec`. We author flat.
- Streaming form ("SpecStream") = newline-delimited RFC 6902 JSON-Patch ops
  (`parseSpecStreamLine` `types.ts:556`, `applySpecPatch` `types.ts:634`); carried on
  the AI-SDK wire as data part `"data-spec"` (`types.ts:1266`). **Not used by us** —
  we publish a complete flat `Spec`.

## 2. Element model — `UIElement`

`packages/core/src/types.ts:56`:

```ts
interface UIElement<T extends string = string, P = Record<string, unknown>> {
  type: T;                                                  // component type from catalog
  props: P;                                                 // component props
  children?: string[];                                      // child element KEYS (flat)
  visible?: VisibilityCondition;                            // visibility (top-level)
  on?: Record<string, ActionBinding | ActionBinding[]>;     // event name -> action(s)
  repeat?: { statePath: string; key?: string };             // iterate children per state-array item
  watch?: Record<string, ActionBinding | ActionBinding[]>;  // JSON-Pointer -> action(s) on change
}
```

- `visible`, `on`, `repeat`, `watch` are **siblings of `type`/`props`/`children`** —
  **never inside `props`**. The structural linter flags `*_in_props` (`spec-validator.ts`).
- `FlatElement` (`types.ts:85`) adds `key`/`parentKey?` — that variant is only the
  array-input form to `flatToTree`; canonical `Spec.elements` is a keyed map of plain
  `UIElement`.

## 3. Expression / binding dialect — 8 `$`-prefixed object forms

**Not a string-expression language.** Every dynamic value is a plain JSON object with a
single `$`-prefixed discriminant key. The canonical set is `BUILT_IN_KEYS`
(`packages/core/src/directives.ts:49-58`); evaluation is a flat type-guard cascade in
`resolvePropValue` (`packages/core/src/props.ts:202-317`). Paths are **RFC 6901 JSON
Pointers** everywhere (leading `/`, slash-delimited, `~1`→`/`, `~0`→`~`,
`parseJsonPointer` `types.ts:266-308`).

| Form | Value shape | Meaning |
|---|---|---|
| `{ "$state": "/ptr" }` | JSON-Pointer string | Read global state: `getByPath(stateModel, ptr)`. (props.ts:211) |
| `{ "$item": "field" }` | relative field; `""` = whole item | **In props:** the item field *value*. **In action params:** the absolute state PATH (see §5). (props.ts:216-222) |
| `{ "$index": true }` | literal `true` sentinel | Current repeat index (a number). (props.ts:225) |
| `{ "$bindState": "/ptr" }` | JSON-Pointer string | Two-way bind to global state. Reads like `$state`; write-back path exposed via `resolveBindings`. (props.ts:230, 355) |
| `{ "$bindItem": "field" }` | relative field; `""` = whole item | Two-way bind to a repeat-item field. Write-back path = `repeatBasePath + "/" + field`. (props.ts:235, 359) |
| `{ "$cond": <VisibilityCondition>, "$then": <expr>, "$else": <expr> }` | branches are themselves expressions | Evaluate `$cond` via `evaluateVisibility`, recurse the chosen branch. (props.ts:242-245) |
| `{ "$computed": "fnName", "args"?: {…} }` | host fn name + named args | Call host-registered `ctx.functions[fnName]`. Unknown fn → `console.warn` once + `undefined`. (props.ts:248-266) |
| `{ "$template": "…${/ptr}…${field}…" }` | string with `${…}` placeholders | Interpolation (below). (props.ts:272-290) |

**`$template` interpolation** (`props.ts:272-290`), regex `/\$\{([^}]+)\}/g`:
- `${/abs/ptr}` (starts with `/`) → `getByPath(stateModel, ptr)`.
- `${bareName}` → repeat item FIRST (`getByPath(repeatItem, name)`), then fall back to
  state at `"/" + name`.
- `null`/`undefined` → `""`; else `String(value)`. Placeholders are `${…}`, **NOT**
  `{ $state }` objects inside the string.

**Unknown `$foo` keys are fail-open:** they fall through to generic object recursion
(values resolved, key kept verbatim) — not an error, not dropped (props.ts:298-305).
User directives are addable via `defineDirective`/`createDirectiveRegistry`
(`directives.ts`) but **cannot shadow** the 8 built-ins (directives.ts:67-81).

**Visibility grammar** (`VisibilityCondition`, `types.ts:162`; `visibility.ts`):
```ts
type VisibilityCondition =
  | boolean
  | SingleCondition            // ({$state|$item}|{$index:true}) + one of eq|neq|gt|gte|lt|lte + not?:true
  | SingleCondition[]          // implicit AND
  | { $and: VisibilityCondition[] }
  | { $or:  VisibilityCondition[] };
```
No operator ⇒ truthiness check. These comparison ops live on **conditions** (`visible`
and `$cond`), distinct from the 8 prop-expression keys.

## 4. `repeat` — iteration (element-level, NOT a component)

`types.ts:71`, on `UIElement`:
```ts
repeat?: { statePath: string; key?: string };
```
- `statePath` = JSON-Pointer to a state array. `key` = optional item-field for stable
  list keys (default = array index).
- The element bearing `repeat` renders **once as the container**; its `children` keys are
  re-instantiated per array item. The structural validator requires `repeat` to have
  ≥1 child (`spec-validator.ts:132`).
- Per-item scope (`{ item, index, basePath }`) sets `repeatItem`, `repeatIndex`, and
  `repeatBasePath = "${statePath}/${index}"` (e.g. `/instances/0`). The loop that *sets*
  this scope lives in the **renderer** packages (Solid `renderer.tsx:427-484`,
  `repeat-scope.tsx`); core only *consumes* the context. **Both our renderers must
  implement this scope** identically.
- Inside the scope: `{$item:"f"}`, `{$index:true}`, `{$bindItem:"f"}` resolve against
  the current item; `${bareName}` in `$template` resolves item-first.

## 5. Actions / events

Element-level `on` (`types.ts:69`): `Record<eventName, ActionBinding | ActionBinding[]>`.
`ActionBinding` (`packages/core/src/actions.ts:39`):

```ts
interface ActionBinding {
  action: string;                          // named verb -> host handler (NOT a URL)
  params?: Record<string, DynamicValue>;   // KEY IS `params` (NOT actionParams)
  confirm?: ActionConfirm;                 // { title, message, confirmLabel?, cancelLabel?, variant? }
  onSuccess?: { navigate: string } | { set: Record<string,unknown> } | { action: string };
  onError?:   { set: Record<string,unknown> } | { action: string };
  preventDefault?: boolean;
}
```

- **Actions are named verbs → host `ActionHandler` functions, never URLs.**
  `ActionHandler = (params) => Promise<T>|T` (`actions.ts:107`).
- The key is **`params`**. There is **no `actionParams`** and **no `emit` wire field** —
  `emit(eventName)` is a renderer-supplied *function* passed to components, which looks up
  `element.on[eventName]` and dispatches (React `renderer.tsx`, Solid `renderer.tsx:188-210`).
- **Built-in verbs handled by the runtime itself** (no host handler needed; each an early
  return in `ActionProvider.execute`): `setState`, `pushState` (supports `$id` auto-id +
  `clearStatePath`), `removeState`, `push`/`pop` (an in-state-only `/navStack` +
  `/currentScreen` screen stack), `validateForm`. (Solid `actions.tsx:123-191`; React
  `react/src/schema.ts:54`.)
- **No built-in URL / navigate / fetch / window action exists.** The only navigation
  primitive is `onSuccess:{navigate:string}` → a **host-supplied `navigate` callback**
  (`actions.ts:209-210`). It is **inert unless the host passes `navigate`**. For our trust
  model: **do not supply `navigate`**, and treat `push`/`pop` as in-state-only.
- Unknown action at runtime → `console.warn("…Unknown action…")`, **no throw** (fail-open).

### 5.1 RESOLVED — `$item` in action `params` (value vs path depends on nesting)

`resolveActionParam` (`props.ts:381-392`) special-cases `$item`/`$index` **only at the top
level** of a param value: a top-level `{ "$item": "id" }` → the **absolute state path**
`/instances/<index>/id` (so `setState`/`removeState` can target a row); top-level
`{ "$index": true }` → the index number; **everything else delegates to `resolvePropValue`**.

`resolvePropValue` resolves `$item` to the **field VALUE** (`props.ts:216-222`,
`getByPath(repeatItem, field)`) and **recurses into arrays** (`props.ts:294`,
`value.map(resolvePropValue)`).

**Therefore our per-row Scan button is value-clean by construction.** Its param is
`targetInstanceIds: [ { "$item": "id" } ]` — the `$item` is **nested inside an array**, so
`resolveActionParam` → `resolvePropValue(array)` → maps each element →
`resolvePropValue({$item:"id"})` → **the literal id value**. The host receives
`targetInstanceIds: ["<id>"]`, not a path. (A *top-level* `{ "$item": "id" }` param would
instead give the path — we avoid that by nesting in the array.) **Confirmed from source.**

**Trust note:** the id originates from the **host-supplied** `$instances` projection (not the
VM), so it is already trustworthy; per trust rule §5.4 the host still re-resolves it against
its authoritative instance list before confirming + acting.

## 6. Catalog, validation, and the fail-OPEN default

Three distinct things (do not conflate):

1. **Catalog grammar/schema** — `defineCatalog(schema, catalog)` (`schema.ts:1565`,
   sugar for `schema.createCatalog`). **Takes the Schema FIRST, then the catalog data.**
   Each component entry = `{ props: z.ZodType, slots?, description?, events?, example? }`
   (`CatalogComponentDef`, `schema.ts:1130`). A built catalog exposes (`Catalog`,
   `schema.ts:83`): `prompt()`, `jsonSchema({strict?})`, `validate(spec)`, `zodSchema()`,
   `componentNames`, `actionNames`.
2. **Strict whole-spec validation is OPT-IN.** `catalog.validate(spec)` =
   `zodSchema.safeParse(spec)` → `{ success, data?, error? }` (`schema.ts:460`). It
   constrains `type` to an enum of catalog component names (`schema.ts:521-532`) and so
   *will* reject an unknown `type` — **but only if you call it.** Note **props are lenient
   by construction**: for a multi-component catalog `propsOf` returns
   `z.record(z.string(), z.unknown())` (`schema.ts:533-545`), so per-component prop schemas
   only bite when you author them strictly. A separate structural validator
   `validateSpec(spec)` (`spec-validator.ts:79`) checks missing root, dangling child keys,
   `repeat` without children, fields-misplaced-in-props, etc.; `autoFixSpec` **auto-relocates**
   rather than rejecting.
3. **The renderer itself validates NOTHING — fail-open.** `defineRegistry(_catalog, …)`
   ignores the catalog at runtime (param literally `_catalog`, unused — React
   `renderer.tsx:739`; Solid `renderer.tsx:662`) and maps names→functions with no Zod
   check. Unknown component type → `registry[type] ?? fallback`; if none →
   `console.warn("No renderer for component type: …")` + render `null`, rest of tree
   survives (React `renderer.tsx:391-395`; Solid `renderer.tsx:331,336-341`). Missing child
   key → warn + skip. Unknown action → warn + no-op. Each element wrapped in an
   `ErrorBoundary` (Solid `renderer.tsx:287-294`).

**Security implication — fail-CLOSED is ours.** To reject a whole manifest on any
off-catalog `type`/prop/action, **WE** must (a) run our own strict catalog `validate(spec)`
with real per-component Zod prop schemas AND (b) run `validateSpec(spec)` structurally,
**before mounting**, and refuse to render on any error. The stock renderer will silently
drop unknowns; we do not rely on it.

---

## CONFIRMED vs STILL-UNCERTAIN

### CONFIRMED from source (file+symbol cited above)
- `Spec = { root, elements: Record<id,UIElement>, state? }` flat map. `types.ts:172`.
- `UIElement = { type, props, children?, visible?, on?, repeat?, watch? }`. `types.ts:56`.
- The 8 expression keys (`$state`, `$item`, `$index`, `$bindState`, `$bindItem`, `$cond`,
  `$computed`, `$template`) and their shapes. `props.ts:202-317`, `directives.ts:49-58`.
- `$template` placeholders are `${/ptr}` / `${bareName}` (item-first), NOT object-in-string.
  `props.ts:272-290`.
- `$index` is the sentinel `{ "$index": true }`, not a path. `props.ts:225`.
- Paths are RFC 6901 JSON Pointers (leading `/`, `~0`/`~1` escapes, `-` = append).
  `types.ts:266-308`.
- `repeat: { statePath, key? }` is element-level, renders container once, needs ≥1 child;
  per-item scope `basePath = ${statePath}/${index}`. `types.ts:71`, Solid `renderer.tsx:427-484`.
- `on: { event: ActionBinding|ActionBinding[] }`; key is `params` (no `actionParams`);
  no `emit` wire field. `types.ts:69`, `actions.ts:39`.
- Built-in verbs `setState`/`pushState`/`removeState`/`push`/`pop`/`validateForm`; no
  URL/fetch/navigate action; `navigate` only via opt-in host callback. `actions.tsx:123-291`,
  `actions.ts:209-210`.
- Renderer is fail-open (unknown type/child/action → warn, never throw). Strict validation
  is opt-in (`catalog.validate` = `safeParse`; `validateSpec` structural). React
  `renderer.tsx:391-395`, Solid `renderer.tsx:331-341`, `schema.ts:460`, `spec-validator.ts:79`.
- Visibility grammar (`boolean | SingleCondition | [] | $and | $or` + comparison ops).
  `types.ts:162`, `visibility.ts`.
- Two-way write-back: component reads resolved value from `props`, writes through the
  `bindings[propName]` absolute path; in Svelte via `getBoundProp` →
  `context.set(path,v)` → `onStateChange([{path,value}])`. Svelte
  `StateProvider.svelte:57-73,149-158`; real `Checkbox.svelte`/`Select.svelte`.
- **`$item` inside action `params`:** path-resolved ONLY at the top level
  (`resolveActionParam` `props.ts:381-392`); **nested in an array/object it resolves to the
  VALUE** via `resolvePropValue` (`props.ts:216-222`, array recursion `props.ts:294`). Our
  per-row Scan param `[ { "$item": "id" } ]` therefore delivers the literal id. **Verified
  2026-06-22 from the clone.** (§5.1)

### STILL-UNCERTAIN — verify before relying
1. **Empty-array "use current selection" param** (`{ "targetInstanceIds": [] }` on the top
   "Scan selected" button). The literal empty array passes through fine; the **semantic**
   ("empty ⇒ use selection state") is **our host convention**, not json-render's. No source
   risk; host-owned.
3. **`ProgressInline`/`FindingsTable`/`Badge` tone mapping** from a per-row `scanState`
   string. json-render binds the string fine; mapping `running→spinner`, `error→danger` is
   **component-internal** (our catalog component code), not wire-level. Renderers implement
   identical tone maps.
4. **Exact `confirm` object fields.** `ActionConfirm = { title, message, confirmLabel?,
   cancelLabel?, variant? }`. `variant` enum values not exhaustively pinned; we use
   `"default"`/`"danger"`. To check: `ActionConfirm` in `actions.ts`.
5. **`watch` semantics.** Confirmed it exists (`types.ts:72`). Not used in the card; if
   adopted later, verify change-detection (reference `===`, `state-store.ts`) for nested map
   updates.
