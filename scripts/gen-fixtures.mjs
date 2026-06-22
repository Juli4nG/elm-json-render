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

function guard(label, text) {
  if (text.includes('"""')) {
    throw new Error(`${label} contains a triple-quote; cannot embed safely`);
  }
}
guard("card.json", cardJson);
guard("instances.json", instancesJson);

const module = `module Fixtures exposing (cardJson, instancesJson)

{-| GENERATED — do not edit by hand. Run \`node scripts/gen-fixtures.mjs\`.

Embeds the authoritative contract fixtures (\`contract/card.json\`,
\`contract/fixtures/instances.json\`) as string constants so tests and the demo decode
the exact same bytes as the contract.
-}


{-| The pinned CloudShield card manifest (\`contract/card.json\`). -}
cardJson : String
cardJson =
    """${cardJson}"""


{-| The four-instance fixture (\`contract/fixtures/instances.json\`). -}
instancesJson : String
instancesJson =
    """${instancesJson}"""
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
