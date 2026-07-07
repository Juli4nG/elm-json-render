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
  "/results":   null,                           // bound by GroupedTable ($state)
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
- **Findings**: `setState("/results", <payload>)` re-renders the `GroupedTable`.

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
