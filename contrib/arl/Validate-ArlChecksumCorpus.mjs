#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const corpusPath = process.argv[2] ?? path.join(here, "fixtures", "checksum-decision-corpus.json");
const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));

function checksum(row) {
  const separator = row.lastIndexOf(" ", row.length - 2);
  if (separator < 1) throw new Error("missing checksum delimiter");
  let sum = 0;
  for (let index = 1; index <= separator; index += 1) sum = (sum + row.charCodeAt(index)) & 0xff;
  return sum;
}

const ids = new Set();
const summary = { accepted: 0, rejected: 0, low_000_099: 0, high_100_255: 0 };
for (const item of corpus.cases ?? []) {
  if (!item.id || ids.has(item.id)) throw new Error(`duplicate or missing id: ${item.id}`);
  ids.add(item.id);
  if (item.evidence !== "real_arl_trace") throw new Error(`${item.id}: byte case is not trace evidence`);
  if (!item.row.startsWith("#") || !item.row.endsWith("\r")) throw new Error(`${item.id}: invalid framing`);
  const match = item.row.match(/\s(\d{3})\r$/);
  if (!match) throw new Error(`${item.id}: checksum must be three decimal digits`);
  const fields = item.row.slice(1, item.row.lastIndexOf(" ")).split(",");
  if (fields.length !== 15 || fields.some((field) => field.trim() === "" || !Number.isFinite(Number(field))))
    throw new Error(`${item.id}: expected 15 finite decimal fields`);
  const computed = checksum(item.row);
  if (computed !== item.claimed_checksum || Number(match[1]) !== item.claimed_checksum)
    throw new Error(`${item.id}: checksum mismatch claimed=${item.claimed_checksum} computed=${computed}`);
  if (!(["accepted", "rejected"].includes(item.decision))) throw new Error(`${item.id}: invalid decision`);
  if (item.decision === "accepted" && item.impact_reply !== "#em") throw new Error(`${item.id}: accepted case must have #em`);
  if (item.decision === "rejected" && item.impact_reply !== "?") throw new Error(`${item.id}: rejected case must have ?`);
  summary[item.decision] += 1;
  summary[computed <= 99 ? "low_000_099" : "high_100_255"] += 1;
}
for (const item of corpus.reported_only ?? []) {
  if (!item.do_not_use_for_replay || item.status !== "row_not_recovered")
    throw new Error(`reported checksum ${item.checksum} must remain quarantined`);
}
console.log(JSON.stringify({ ok: true, cases: ids.size, reported_only: corpus.reported_only.length, ...summary }));
