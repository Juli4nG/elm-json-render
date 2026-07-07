// Capture the native Elm renderer's HTML for the conformance snapshot.
//
// Loads the compiled demo in its deterministic terminal state
// (`?scenario=final`), normalizes the `.jr-root` subtree with the shared
// `normalize.mjs`, and writes the golden snapshot. Other renderers of the same format
// capture the same way with the same normalizer, so the two goldens diff byte-for-byte.
//
// Uses the locally-installed Google Chrome (`channel: "chrome"`) so no browser download
// is required. Run: `npm run capture` (from conformance/).

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright-core";
import { normalizeElement } from "./normalize.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const demoUrl =
  pathToFileURL(join(here, "..", "demo", "index.html")).href + "?scenario=final";
const goldenPath = join(here, "golden.elm.normalized.html");

const browser = await chromium.launch({ channel: "chrome" });
try {
  const page = await browser.newPage();
  await page.goto(demoUrl);
  await page.waitForSelector(".jr-root");

  // Inject the shared normalizer as a global so its recursive self-reference resolves
  // inside the page, then run it over the rendered root.
  await page.evaluate(`window.normalizeElement = ${normalizeElement.toString()}`);
  const normalized = await page.evaluate(() =>
    window.normalizeElement(document.querySelector(".jr-root"))
  );

  writeFileSync(goldenPath, normalized + "\n");
  console.log(`wrote ${goldenPath}`);
} finally {
  await browser.close();
}
