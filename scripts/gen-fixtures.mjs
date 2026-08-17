#!/usr/bin/env node
// Generate Elm `Fixtures` modules from the authoritative contract files so the tests
// and the demo consume the exact same bytes as `contract/`. Run from the repo root:
//   node scripts/gen-fixtures.mjs
//
// Emits identical `Fixtures.elm` into tests/ and demo/src/. Elm has no file IO, so the
// JSON is embedded as triple-quoted string constants. (Neither contract file contains a
// `"""` sequence, so triple-quoting is safe.)

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

const cardJson = readFileSync(join(root, "contract/card.json"), "utf8").trim();
const instancesJson = readFileSync(
  join(root, "contract/fixtures/instances.json"),
  "utf8"
).trim();
const pressableJson = readFileSync(
  join(root, "contract/fixtures/pressable.json"),
  "utf8"
).trim();
const iconButtonJson = readFileSync(
  join(root, "contract/fixtures/icon-button.json"),
  "utf8"
).trim();

function guard(label, text) {
  if (text.includes('"""')) {
    throw new Error(`${label} contains a triple-quote; cannot embed safely`);
  }
}
guard("card.json", cardJson);
guard("instances.json", instancesJson);
guard("pressable.json", pressableJson);
guard("icon-button.json", iconButtonJson);

const module = `module Fixtures exposing (cardJson, iconButtonJson, instancesJson, pressableJson)

{-| GENERATED — do not edit by hand. Run \`node scripts/gen-fixtures.mjs\`.

Embeds the authoritative contract fixtures (\`contract/card.json\`,
\`contract/fixtures/instances.json\`, \`contract/fixtures/pressable.json\`,
\`contract/fixtures/icon-button.json\`) as string constants so tests and the demo decode
the exact same bytes as the contract.
-}


{-| The pinned demo card manifest (\`contract/card.json\`). -}
cardJson : String
cardJson =
    """${cardJson}"""


{-| The four-instance fixture (\`contract/fixtures/instances.json\`). -}
instancesJson : String
instancesJson =
    """${instancesJson}"""


{-| The pressable-elements manifest (\`contract/fixtures/pressable.json\`): a repeat whose
row \`Stack\`, name \`Text\` and status \`Badge\` all carry an \`on.press\` binding, plus a
non-pressable \`Stack\`/\`Text\`/\`Badge\` legend. -}
pressableJson : String
pressableJson =
    """${pressableJson}"""


{-| The icon-button manifest (\`contract/fixtures/icon-button.json\`): buttons with an icon and a
label, icon-only buttons (a static empty label and one resolved empty per row), and a plain
label-only button that must render exactly as it always did. -}
iconButtonJson : String
iconButtonJson =
    """${iconButtonJson}"""
`;

const targets = ["tests/Fixtures.elm", "demo/src/Fixtures.elm"];
for (const target of targets) {
  writeFileSync(join(root, target), module);
  console.log(`wrote ${target}`);
}

// Keep generated sources elm-format-clean so the whole tree validates uniformly.
try {
  execFileSync(
    "elm-format",
    ["--yes", ...targets.map((t) => join(root, t))],
    { stdio: "ignore" }
  );
} catch {
  console.warn("note: elm-format not found; generated Fixtures left unformatted");
}
