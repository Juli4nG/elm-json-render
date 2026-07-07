// Unit tests for the shared normalizer. Run: `node --test` (from conformance/).
//
// `normalizeElement` is written against the live-DOM Element interface, so these tests
// use a minimal fake implementing exactly the surface it touches (tagName, nodeType,
// checked, hasAttribute, getAttribute, childNodes / textContent).

import assert from "node:assert/strict";
import { test } from "node:test";
import { normalizeElement } from "./normalize.mjs";

function el(tag, attrs = {}, children = []) {
  return {
    tagName: tag.toUpperCase(),
    nodeType: 1,
    checked: attrs.checked === true,
    hasAttribute: (name) => name !== "checked" && name in attrs,
    getAttribute: (name) => attrs[name],
    childNodes: children,
  };
}

function text(value) {
  return { nodeType: 3, textContent: value };
}

test("keeps only jr-* class tokens, sorted", () => {
  const node = el("span", { class: "zz-x jr-badge jr-badge--success framework-noise" });
  assert.equal(normalizeElement(node), '<span class="jr-badge jr-badge--success"></span>');
});

test("omits the class attribute entirely when no jr-* tokens remain", () => {
  const node = el("div", { class: "framework-wrapper data-v-abc" });
  assert.equal(normalizeElement(node), "<div></div>");
});

test("reflects the checked PROPERTY (not attribute) and self-closes void inputs", () => {
  const checkedBox = el("input", { type: "checkbox", checked: true });
  const uncheckedBox = el("input", { type: "checkbox" });
  assert.equal(normalizeElement(checkedBox), '<input type="checkbox" checked="true" />');
  assert.equal(normalizeElement(uncheckedBox), '<input type="checkbox" />');
});

test("collapses text whitespace and indents the tree", () => {
  const node = el("div", { class: "jr-card" }, [
    el("h2", { class: "jr-card__title" }, [text("  Server   scan  ")]),
  ]);
  assert.equal(
    normalizeElement(node),
    [
      '<div class="jr-card">',
      '  <h2 class="jr-card__title">',
      "    Server scan",
      "  </h2>",
      "</div>",
    ].join("\n")
  );
});

test("drops non-allowlisted attributes (data-gap kept, style/id dropped)", () => {
  const node = el("div", { class: "jr-stack", "data-gap": "2", style: "color:red", id: "x" });
  assert.equal(normalizeElement(node), '<div class="jr-stack" data-gap="2"></div>');
});
