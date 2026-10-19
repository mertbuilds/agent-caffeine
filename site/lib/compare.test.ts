import assert from "node:assert/strict";
import { test } from "node:test";
import { agentsMoreThan } from "./agents";
import { CHECKED_ON, OURS, ROWS, TOOLS, isText } from "./compare";
import { BATTERY_FLOOR } from "./simulator";

test("the day of the check is a real day", () => {
  assert.match(CHECKED_ON, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(new Date(`${CHECKED_ON}T00:00:00Z`).toISOString().slice(0, 10), CHECKED_ON);
});

test("every row has a cell for every tool, and every claim about another tool has a source", () => {
  assert.equal(new Set(ROWS.map((row) => row.id)).size, ROWS.length);
  for (const tool of TOOLS) {
    for (const source of tool.sources) assert.ok(URL.canParse(source.url) && source.url.startsWith("https://"));
    for (const row of ROWS) {
      const cell = row.cells[tool.id];
      assert.ok(cell !== undefined, `${row.id} has no cell for ${tool.id}`);
      const claim = isText(cell) || cell.value !== "unstated" || cell.note !== undefined;
      if (tool.id !== OURS && claim) assert.ok(tool.sources.length > 0, `${tool.name} needs a source for ${row.id}`);
    }
  }
});

test("our cells say what the rest of the site says", () => {
  const cell = (id: string) => {
    const row = ROWS.find((entry) => entry.id === id);
    assert.ok(row !== undefined, `no row ${id}`);
    return row.cells[OURS];
  };
  assert.equal(ROWS[0].id, "price");
  const price = cell("price");
  assert.ok(isText(price));
  assert.equal(price.text, "Free, open source");
  assert.deepEqual(cell("open-source"), { value: "yes", note: "AGPL-3.0" });
  assert.ok(cell("works").note?.includes(`more than ${agentsMoreThan} agents`));
  assert.ok(cell("battery-stop").note?.includes(`${BATTERY_FLOOR}%`));
});

test("no cell has an em dash", () => {
  assert.doesNotMatch(JSON.stringify(ROWS), /—/);
});
