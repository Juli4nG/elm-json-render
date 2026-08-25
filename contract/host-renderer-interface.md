# Host ↔ Renderer Interface Contract (framework-neutral)

Applies identically to **any other renderer of this contract** and the **native Elm
renderer**. Both consume the same json-render flat `Spec` (`card.json`) and the same
host-state shape, emit the same action events, and react to the same state-push
mechanism. Nothing here is renderer-specific. Format pinned in
`pinned-format-reference.md`.

## 1. Inputs

### 1.1 Manifest (the json-render `Spec`)
The validated `ui` body of the manifest envelope — `card.json`, a flat
`Spec { root, elements, state }` in json-render's real dialect. The host has **already**
run fail-closed validation (catalog `validate` + structural `validateSpec`) before handing
it to the renderer; the renderer assumes a valid spec and does NOT re-open trust decisions.
(Renderer stays fail-open internally per json-render; safety is the host's pre-mount gate —
see pinned-format-reference §6.)

### 1.2 Host state object (the data the renderer reflects)
The host owns and pushes a single JSON state object addressed by RFC 6901 JSON Pointers.
**Authoritative host model** (what the host tracks):

```
instances : [ { id, name, status } ]      // from $instances (host-resolved, fresh)
scan      : { <id>: { state, counts?, message? } }   // host-owned, polled
selection : { <id>: bool }                // local UI, select-all + per-row toggles
selectAll : bool                          // local UI
results   : <findings payload | null>     // host-owned, from scan-result object
```

**Renderer-facing projection (REQUIRED).** Because json-render reads per-row data off the
repeat *item* (not via `selection[id]`/`scan[id]` map indirection), the host MUST flatten
its model into the denormalized array the manifest reads, under these exact pointers:

```jsonc
{
  "/selectAll": false,                          // bound by select-all checkbox ($bindState)
  "/results":   null,                           // bound by CountPills ($state)
  "/instances": [
    {
      "id":        "<id>",                       // stable repeat key
      "name":      "<name>",                     // read by $item:"name"
      "selected":  false,                        // = selection[id]; two-way $bindItem
      "scanState": "idle",                       // = scan[id].state; read by $item:"scanState"
      "counts":    { "critical": 0, "high": 0, "medium": 0, "low": 0 }  // optional, when done
    }
  ]
}
```

The host is the single owner of this projection: on every change to its internal
`selection`/`scan`/`selectAll` it re-emits the affected `instances[i]` (and `/selectAll`,
`/results`). The renderer never derives these maps itself.

### 1.3 Host options (what the host tells the renderer about ITSELF)

Distinct from the manifest and from state: a small record of host-owned settings the renderer
reads but a manifest can never reach. In the Elm renderer this is `Render.Options`, passed to
`Render.view`; `Render.defaultOptions` is the empty-handed starting point.

```elm
{ allowedIframeOrigins : List String
, hostName : String
, countPills :
    { groupBy : String
    , groupOrder : List String
    , itemNoun : String
    , itemNounPlural : String
    }
}
```

- `allowedIframeOrigins` is the security boundary for `Iframe`: an `<iframe>` is emitted only
  for an https `src` whose origin is an exact member. Empty disables all iframes. This must
  never be reachable from a manifest.
- `hostName` is the trust chrome that goes with it: the always-on provenance bar reads
  "Third-party content from `<origin>` — not verified by `<hostName>`". Host-owned for the same
  reason the allowlist is — the embedded party must never get to write the sentence disclaiming
  itself — and named rather than generic because a disclaimer reads as a promise from whoever is
  named in it.
- `countPills` is vocabulary, not security: the words a `CountPills` element counts in when its
  manifest does not name its own. It exists so a manifest published before those prop keys
  existed keeps reading in the host's words with no wire change. `emptyLabel` is deliberately
  NOT in here: when neither the manifest nor anything else names it, the renderer synthesizes
  "No `<plural>` yet" from the plural noun already in play.

### 1.4 Refusal classification (what the host shows when validation fails)

The decoder's diagnostic is written for whoever is debugging the publisher. A host with a real
audience classifies it instead of printing it: `Spec.errorKind` returns
`UnknownCatalogSurface` when the manifest named a component type, an icon, or any other key
this build does not have — a prop key, but equally an unsupported element, action-binding,
confirm, `repeat` or `Table`-column key — since the honest reading of all of those is version
skew. `Malformed` covers everything else, where nothing suggests a newer renderer would help.
Both refuse to render; only the sentence differs.

Known limit, accepted: the decode error embeds the offending JSON, so a malformed manifest whose
own DATA quotes one of the classifier's marker strings is read as skew. It picks the wrong
sentence and nothing else.

## 2. Outputs (the action event)

The only thing the renderer emits to the host is an **action event** when a wired `on`
fires. Shape (framework-neutral):

```
{ verb: string, params: object }
```

- `verb` = the `ActionBinding.action` string from the manifest (e.g. `"scan.start"`).
- `params` = the manifest `params` object **with json-render expressions resolved** against
  the current state / repeat scope at dispatch time.
- The renderer does NOT execute the verb. It hands `(verb, params)` to the host (Solid:
  custom-element CustomEvent / port message; Elm: a `Cmd`/port out). The host owns all side
  effects (writing scan-request objects, mutating `selection`, etc.).
- **`confirm` is honored before emit:** if the binding carries `confirm`, the renderer shows
  the confirm dialog and only emits on accept. (Both renderers implement the dialog; the host
  is never asked to confirm.)
- **No `navigate`/URL/fetch is ever wired.** The host MUST NOT supply a `navigate` callback;
  built-in `push`/`pop` (if ever present) are in-state-only.

### 2.1 The two `startScan` param shapes (PINNED contract)

1. **"Scan selected"** → `params = { "targetInstanceIds": [] }`. The empty array is the
   contract signal for **"use current selection."** The host reads its own
   `selection`/`selectAll` and starts every `selected` row. (json-render passes the empty
   array verbatim; the "use selection" meaning is host convention.)

2. **Per-row "Scan"** → `params = { "targetInstanceIds": [ { "$item": "id" } ] }`. **Verified
   (pinned-format-reference §5.1):** because the `$item` is nested in an array, json-render
   resolves it to the **literal id value**, so the host receives `targetInstanceIds: ["<id>"]`
   (not a state path). That id comes from the **host's own `$instances` projection** (not the
   VM), so it is trustworthy; per trust rule §5.4 the host still re-resolves it to the real
   OpenStack instance (name+id from the project's own list) and the confirm dialog names it
   before acting.

Both renderers MUST emit the per-row event carrying enough scope (the resolved id or the row
index/basePath) for the host to identify the row unambiguously.

### 2.2 Pressable non-`Button` elements (Elm renderer)

`on: { press: … }` is honored on `Text`, `Badge` and `Stack` as well as `Button`, so a
manifest can make a whole row, a status badge or a label activate an action. The binding is
the same `ActionBinding` (same `params` resolution, same `confirm` dialog); only the
host-visible markup differs:

- with a press binding the element carries `role="button"`, `tabindex="0"` and the class
  `jr-pressable` (the host's styling hook: cursor, hover, `:focus-visible`), and activates on
  click **and** on Enter / Space;
- with no press binding it renders exactly as before: no class, no role, no tabindex, no
  handlers. (The conformance golden is byte-identical across this change.)
- click and keydown **stop propagation**, so a pressable nested inside a pressable (a row
  `Stack` holding a pressable `Text`) emits exactly one action: the innermost one. A
  `Checkbox` inside a pressable `Stack` is the exception, since its click is not a press
  binding: it toggles *and* presses the enclosing stack. Do not nest one there.

Stock json-render renderers wire `on.press` on `Button` only, so `jr-pressable` markup is a
deliberate divergence and is kept out of the shared conformance fixture (`card.json`). It has
its own contract fixture, `fixtures/pressable.json`.

### 2.3 Icon buttons (Elm renderer)

`Button` takes an optional `icon`, a name from a **closed set** — `"trash"`, `"close"`,
`"external"`, `"refresh"`. It is a name, never markup and never an expression: the renderer owns
the shapes, so a manifest can ask for one of four glyphs and cannot inject an image. A name
outside the set is refused at decode time.

- with an `icon` the button carries `jr-button--icon` and renders a 16px inline SVG in
  `currentColor` (classes `jr-icon jr-icon--<name>`, `aria-hidden`) BEFORE the label;
- an **empty** resolved label makes it icon-only: `jr-button--icon-only`, no text child, and the
  renderer supplies `aria-label` / `title` itself (`trash` → "Remove", `close` → "Close",
  `external` → "Open", `refresh` → "Refresh"), because the manifest has no way to name a shape;
- with no `icon` the button renders exactly as before: `class="jr-button"`, the label as its only
  child, no SVG, nothing named. (The conformance golden is byte-identical across this change.)

Sizing, hit area and hover tone belong to the host stylesheet, as with every other `jr-*` class.

Stock json-render's `Button` has no `icon`, so this is a deliberate divergence and is kept out of
the shared conformance fixture (`card.json`). It has its own contract fixture,
`fixtures/icon-button.json`.

## 3. How the host pushes a state update (so a badge re-renders)

The host drives all live updates by **writing host state at a JSON Pointer**; the renderer
reflects it reactively. Framework-neutral protocol:

```
host.setState(path, value)   // path = RFC 6901 JSON Pointer; value = new JSON
```

- **Single-row scan progress** (the live badge): the host writes the row's `scanState`
  (and later `counts`) at its absolute pointer, e.g. `setState("/instances/2/scanState",
  "running")`, then at done `setState("/instances/2/scanState", "done")` and
  `setState("/instances/2/counts", { critical:0, high:0, medium:2, low:6 })`. The
  `row-status` Badge bound via `{ "$item": "scanState" }` re-renders for that row only.
- **Select-all**: `setState("/selectAll", true)` then fan out
  `setState("/instances/<i>/selected", true)` for each eligible row (the host owns the
  fan-out; json-render's select-all checkbox only two-way-binds `/selectAll`).
- **Findings**: `setState("/results", <payload>)` re-renders the `CountPills`.

**Reactivity caveat (both renderers must honor):** json-render's default store compares by
reference (`===`, `state-store.ts`). To make a change register, the host MUST pass a **new
object/array reference** for any mutated container (don't mutate `instances[i]` in place —
replace the element or the array). The Elm renderer (immutable by nature) satisfies this for
free; the Solid island must use the store's immutable set path (it does, via
`immutableSetByPath`). The host-side push API therefore always sends fresh values.

**Write-back from the renderer (two-way inputs):** when the user toggles a `$bindState` /
`$bindItem` checkbox, the renderer writes back to the bound absolute path and surfaces it to
the host via the same state-change channel (Solid: `onStateChange([{path,value}])` →
custom-element event; Elm: port out). The host treats that as the source of truth for
`selection`/`selectAll` and re-projects as needed. Net: state is host-owned; the renderer's
write-backs are reported to the host, never applied behind its back.
