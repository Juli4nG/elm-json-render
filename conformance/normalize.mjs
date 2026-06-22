// Shared HTML normalizer for the json-render conformance harness.
//
// Both Track A (Solid custom-element island) and Track B (this native Elm renderer)
// run their rendered `.jr-root` subtree through THIS function, so the two normalized
// snapshots can be diffed byte-for-byte. The normalizer keeps only the semantic shape
// the contract pins — tag tree, `jr-*` classes, text, and a small allowlist of
// structural attributes — and drops everything frameworks differ on (event wiring,
// inline styles, attribute order/whitespace).
//
// `normalizeElement` runs inside the browser (it takes a live DOM Element); the source
// is also injected into Playwright via `page.evaluate`. Keep it dependency-free and
// self-contained so it serializes cleanly across the CDP boundary.
//
// Two cross-framework gotchas it handles deliberately:
//   - `checked` is a DOM *property*, not an attribute (both Elm and Solid set the
//     property), so it is read off `el.checked`, not `getAttribute`.
//   - void elements (`input`) are emitted self-closing with no bogus close tag.

/** Attributes preserved in the normalized output (everything else is dropped). */
export const KEPT_ATTRIBUTES = ["class", "type", "checked", "data-state", "data-gap"];

/**
 * Normalize a DOM Element subtree to a stable, indented HTML string.
 * @param {Element} el
 * @param {number} [depth]
 * @returns {string}
 */
export function normalizeElement(el, depth = 0) {
  const kept = ["class", "type", "checked", "data-state", "data-gap"];
  const voidTags = ["input", "br", "hr", "img", "meta", "link"];
  const indent = "  ".repeat(depth);
  const tag = el.tagName.toLowerCase();

  const attrs = [];
  for (const name of kept) {
    if (name === "checked") {
      // `checked` is reflected as a property, not an attribute.
      if (tag === "input" && el.checked) attrs.push('checked="true"');
      continue;
    }
    if (el.hasAttribute(name)) {
      let value = el.getAttribute(name);
      if (name === "class") value = value.trim().split(/\s+/).sort().join(" ");
      attrs.push(`${name}="${value}"`);
    }
  }
  const attrStr = attrs.length ? " " + attrs.join(" ") : "";

  if (voidTags.includes(tag)) {
    return `${indent}<${tag}${attrStr} />`;
  }

  const childLines = [];
  for (const node of el.childNodes) {
    if (node.nodeType === 3) {
      // Text node: collapse whitespace, drop if empty.
      const text = node.textContent.replace(/\s+/g, " ").trim();
      if (text) childLines.push(`${"  ".repeat(depth + 1)}${text}`);
    } else if (node.nodeType === 1) {
      childLines.push(normalizeElement(node, depth + 1));
    }
  }

  if (childLines.length === 0) {
    return `${indent}<${tag}${attrStr}></${tag}>`;
  }
  return `${indent}<${tag}${attrStr}>\n${childLines.join("\n")}\n${indent}</${tag}>`;
}
