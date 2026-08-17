module Fixtures exposing (cardJson, instancesJson, pressableJson)

{-| GENERATED — do not edit by hand. Run `node scripts/gen-fixtures.mjs`.

Embeds the authoritative contract fixtures (`contract/card.json`,
`contract/fixtures/instances.json`, `contract/fixtures/pressable.json`) as string constants so tests and the demo decode
the exact same bytes as the contract.

-}


{-| The pinned demo card manifest (`contract/card.json`).
-}
cardJson : String
cardJson =
    """{
  "root": "card",
  "elements": {
    "card": {
      "type": "Card",
      "props": { "title": "Scan instances" },
      "children": ["toolbar", "list", "results"]
    },
    "toolbar": {
      "type": "Stack",
      "props": { "direction": "row", "gap": 2 },
      "children": ["select-all", "scan-selected"]
    },
    "select-all": {
      "type": "Checkbox",
      "props": {
        "label": "Select all",
        "checked": { "$bindState": "/selectAll" }
      },
      "children": []
    },
    "scan-selected": {
      "type": "Button",
      "props": { "label": "Scan selected" },
      "on": {
        "press": {
          "action": "scan.start",
          "params": { "targetInstanceIds": [] },
          "confirm": {
            "title": "Scan selected instances?",
            "message": "Queue scans for the currently selected instances.",
            "variant": "default"
          }
        }
      },
      "children": []
    },
    "list": {
      "type": "Stack",
      "props": { "direction": "col", "gap": 1 },
      "repeat": { "statePath": "/instances", "key": "id" },
      "children": ["row"]
    },
    "row": {
      "type": "Stack",
      "props": { "direction": "row", "gap": 2 },
      "children": ["row-select", "row-name", "row-status", "row-scan-btn"]
    },
    "row-select": {
      "type": "Checkbox",
      "props": {
        "checked": { "$bindItem": "selected" }
      },
      "children": []
    },
    "row-name": {
      "type": "Text",
      "props": {
        "value": { "$item": "name" }
      },
      "children": []
    },
    "row-status": {
      "type": "Badge",
      "props": {
        "value": { "$item": "scanState" }
      },
      "children": []
    },
    "row-scan-btn": {
      "type": "Button",
      "props": { "label": "Scan" },
      "on": {
        "press": {
          "action": "scan.start",
          "params": { "targetInstanceIds": [{ "$item": "id" }] },
          "confirm": {
            "title": "Scan this instance?",
            "message": { "$template": "Queue a scan for ${name}?" },
            "variant": "default"
          }
        }
      },
      "children": []
    },
    "results": {
      "type": "GroupedTable",
      "props": {
        "bind": { "$state": "/results" },
        "groupBy": "severity"
      },
      "children": []
    }
  },
  "state": {
    "selectAll": false,
    "instances": [],
    "results": null
  }
}"""


{-| The four-instance fixture (`contract/fixtures/instances.json`).
-}
instancesJson : String
instancesJson =
    """[
  { "id": "i-0a1b2c3d", "name": "web-frontend-01", "status": "ACTIVE" },
  { "id": "i-1b2c3d4e", "name": "api-backend-02", "status": "ACTIVE" },
  { "id": "i-2c3d4e5f", "name": "postgres-primary", "status": "ACTIVE" },
  { "id": "i-3d4e5f6a", "name": "batch-worker-07", "status": "ACTIVE" }
]"""


{-| The pressable-elements manifest (`contract/fixtures/pressable.json`): a repeat whose
row `Stack`, name `Text` and status `Badge` all carry an `on.press` binding, plus a
non-pressable `Stack`/`Text`/`Badge` legend.
-}
pressableJson : String
pressableJson =
    """{
  "root": "card",
  "elements": {
    "card": {
      "type": "Card",
      "props": { "title": "Scan history" },
      "children": ["legend", "list"]
    },
    "legend": {
      "type": "Stack",
      "props": { "direction": "row", "gap": 2 },
      "children": ["legend-text", "legend-badge"]
    },
    "legend-text": {
      "type": "Text",
      "props": { "value": "Recent scans" },
      "children": []
    },
    "legend-badge": {
      "type": "Badge",
      "props": { "value": "idle" },
      "children": []
    },
    "list": {
      "type": "Stack",
      "props": { "direction": "col", "gap": 1 },
      "repeat": { "statePath": "/rows", "key": "id" },
      "children": ["row"]
    },
    "row": {
      "type": "Stack",
      "props": { "direction": "row", "gap": 2 },
      "on": {
        "press": {
          "action": "row.open",
          "params": { "resultId": { "$item": "id" } }
        }
      },
      "children": ["row-name", "row-status"]
    },
    "row-name": {
      "type": "Text",
      "props": { "value": { "$item": "name" } },
      "on": {
        "press": {
          "action": "row.navigate",
          "params": { "instanceId": { "$item": "instanceId" } }
        }
      },
      "children": []
    },
    "row-status": {
      "type": "Badge",
      "props": { "value": { "$item": "state" } },
      "on": {
        "press": {
          "action": "row.detail",
          "params": { "text": { "$item": "error" } },
          "confirm": {
            "title": "Show the failure detail?",
            "message": { "$template": "Open the error reported for ${name}." }
          }
        }
      },
      "children": []
    }
  },
  "state": {
    "rows": []
  }
}"""
