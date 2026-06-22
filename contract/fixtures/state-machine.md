# Demo scan state machine (fixture-driven)

Drives both renderers identically so the Solid island and the Elm renderer animate
the same. The demo harness owns a wall-clock timeline keyed by instance id and pushes
host-state updates (see `../host-renderer-interface.md`) at each tick. The renderer is
purely reactive — it never advances state itself.

## Per-instance lifecycle

```
idle ──(startScan)──> queued ──(t+Δq)──> running ──(t+Δr)──> done  (+counts)
                                                  └──(failure)──> error (+message)
```

`scanState` field values used on the wire (bound by `row-status` Badge):
`idle | queued | running | done | error`.

## Demo timeline (relative to each instance's own scan trigger, t=0)

| t (s) | scanState | counts payload added |
|-------|-----------|----------------------|
| 0.0   | queued    | —                    |
| 1.0   | running   | —                    |
| 4.0   | done      | `{ critical, high, medium, low }` |

One instance (`batch-worker-07`, `i-3d4e5f6a`) is scripted to take the **error**
branch at t+4.0 instead of `done`, to exercise the danger tone:
`running → error` with `message: "ssh unreachable"`.

## Fixed per-instance result counts (revealed at `done`)

| id            | name              | critical | high | medium | low |
|---------------|-------------------|----------|------|--------|-----|
| i-0a1b2c3d    | web-frontend-01   | 0        | 2    | 5      | 11  |
| i-1b2c3d4e    | api-backend-02    | 1        | 3    | 4      | 9   |
| i-2c3d4e5f    | postgres-primary  | 0        | 0    | 2      | 6   |
| i-3d4e5f6a    | batch-worker-07   | — (errors)                         |

## "Scan selected" / select-all timeline

- `select-all` toggling sets every row's `selected = true` (host fans the `selectAll`
  bool out to each `instances[i].selected`).
- "Scan selected" with `targetInstanceIds: []` ⇒ host reads which rows have
  `selected === true` and starts their lifecycles **concurrently**, each on its own
  t=0 clock. Rows advance independently (queued/running/done interleave by row).
- A row already `queued`/`running` is **skipped** (dedup) if its per-row Scan button
  or a select-all batch re-triggers it.

## Determinism

Timeline is fixed (no randomness) so a screenshot at, e.g., t=2.0s after a batch start
shows every selected row in `running`, and at t=5.0s shows `done` with the counts above
(and `batch-worker-07` in `error`). Both renderers, fed the same pushes, must match
pixel-for-state.
