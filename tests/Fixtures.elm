module Fixtures exposing (cardJson, instancesJson)

{-| GENERATED — do not edit by hand. Run `node scripts/gen-fixtures.mjs`.

Embeds the authoritative contract fixtures (`contract/card.json`,
`contract/fixtures/instances.json`) as string constants so tests and the demo decode
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
      "type": "FindingsTable",
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
