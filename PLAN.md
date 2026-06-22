---
schema_version: 1
plan_id: package-elm-json-render
title: "Package — elm-json-render (native Elm renderer for json-render manifests)"
status: active
created_at_utc: 2026-06-22T00:00:00Z
updated_at_utc: 2026-06-22T00:00:00Z
default_destination: local_markdown
publish_policy: draft_then_ask
update_cadence: every_small_step
targets:
  local_path: package-elm-json-render-plan.md
  logseq_page: null
  github_issue: null
  gitlab_issue: null
  github_pr: null
  gitlab_mr: null
---

# Package — elm-json-render (native Elm renderer)

> Track B of `phase-1-plan.md`. The **durable, native endgame.** Decodes a json-render-format
> manifest into typed Elm and renders `Html` — no JS framework, no build step, fail-closed by
> construction. A future open-source contribution (precedent: `elm-ui-patternfly`). Contract:
> `phase-0-spec.md`.

## Summary

A standalone **Elm package** that decodes json-render's wire format (flat element map + expression
objects + `repeat` + `on:{action,params}`) into a typed Elm tree and renders it to `Html`, scoped
to the components the CloudShield card uses. State is **host-owned** (Exosphere pushes it in);
actions become **Elm messages**. Because Elm decoders are strict and Elm `Html` has no
`innerHTML`/script escape hatch, it is **fail-closed and XSS-safe by construction**.

## Problem

json-render has no Elm renderer; using its JS renderers means a framework + build + an Elm↔JS bridge
+ a non-Elm seam in a proudly-Elm app. A native Elm renderer keeps Exosphere pure-Elm with no new
tooling, is safe by construction, and (per Julian) is the durable choice — we depend on json-render's
*format* (a spec), not its code. The team has done this before (`elm-ui-patternfly`, owned by the
lead architect).

## Success Criteria

- [ ] Decoders for json-render's element model (flat `{ root, elements, state }`) → a typed Elm
  tree, scoped to our card's components; an unknown type/prop **fails the decode** (fail-closed).
- [ ] Expression/binding resolution for our card's needs: `$state` JSON-Pointer paths, `repeat`
  with `$item`/`$index`, `$template` string interpolation.
- [ ] Component renderers → `Html` for Card / Stack / Text / Badge / Button / Checkbox / repeat /
  FindingsTable.
- [ ] **Live state from the host** re-renders rows (queued → running → done); Scan / select-all
  produce Elm messages (host re-checks the verb allowlist + action-confirmation).
- [ ] Invalid / off-catalog JSON → a host **error stub**, never a partial render.
- [ ] Structured as a **standalone, extractable Elm package** (publishable as `elm-json-render`),
  used by Exosphere via a thin integration.

## Out Of Scope

- Full json-render spec (only the card's subset; the package can grow later).
- The Solid island (Track A); object storage; CloudShield agent.
- json-render's JS-side features (streaming, devtools) — we consume the *format*, not the runtime.

## Constraints

1. **Native Elm only** — no JS, no new build tool (`elm make` already exists in Exosphere).
2. **Pin a json-render format version**; track changelogs deliberately (it's v0.x).
3. Scoped to the **CloudShield card**; standalone-package structure from day one (clean module
   boundary, not entangled with Exosphere internals).
4. **Fail-closed by construction** — rely on strict decoders; show the error stub on any failure.

## Parts

### Part 1 — Decode the element model
- **Goal:** json-render's flat `{root, elements, state}` → a typed Elm tree, scoped.
- **Red:** Elm has no decoder for a json-render manifest. **Green:** the shared `card.json` decodes
  to a typed value; a manifest with an unknown component type **fails** the decode (fail-closed).
- [ ] `Decoder` for elements + the typed component union (our subset)

### Part 2 — Expression / binding resolution
- **Goal:** resolve `$state` (JSON-Pointer), `repeat` (`$item`/`$index`), `$template`.
- **Green:** a `$state`-bound badge reads host state; `repeat` over `$instances` yields one row per
  instance; `$template` interpolates a name. (This is the non-trivial part — bound to the card's needs.)

### Part 3 — Component renderers → Html
- **Goal:** draw the allowlisted components.
- **Green:** the decoded card renders as `Html` with correct layout; an off-catalog node never
  reaches render (Part 1 rejected it).

### Part 4 — Host state + actions
- **Goal:** the make-or-break + the action path.
- **Green:** host pushes per-row scan state → rows update live; a Button yields an Elm message
  (verb + params) the host confirms against the allowlist.

### Part 5 — Package + demo
- **Goal:** standalone, extractable, demonstrable.
- **Green:** a tiny example Elm app renders the card and drives a fake queued→running→done loop;
  module boundaries are clean enough to publish as `elm-json-render`.

## Step Log

- 2026-06-22 — Plan created. No code yet.

## Validation

- Each Part's Green Test is a running Elm renderer (example app, then the Exosphere switch in
  `phase-1-plan.md` Part 4). Decoder fail-closed behavior is unit-tested with **elm-test-rs** (the
  suite Exosphere already uses).

## Risks

- **json-render v0.x format churn.** We pin a version and own the decoders; Elm's compiler flags
  exactly what breaks on a bump. Depending on a *spec* (not their code) is the more durable side of
  this risk.
- **Reimplementing expression/repeat semantics in Elm.** The real work; static layout is easy, the
  live-binding + iteration runtime is the effort. Bound it to the card's needs.
- **Scope creep toward the full spec.** Resist; grow the package only as new cards need components.
- **Staying in sync with json-render releases.** Update deliberately, version the package.

## Publish Targets

- Canonical: `package-elm-json-render-plan.md`. Intended to graduate into a standalone
  `elm-json-render` package (open-source contribution) once proven.

## Handoff

- Build Part 1 (decode + fail-closed) first — it's the security floor. Then expression resolution
  (Part 2, the hard part), renderers, then state/actions. Keep the module boundary clean for
  extraction. Hand the integration (mount + state-in + msg-out) to the Exosphere switch
  (`phase-1-plan.md` Part 4).
