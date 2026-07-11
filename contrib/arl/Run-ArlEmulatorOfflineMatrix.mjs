#!/usr/bin/env node
import childProcess from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const corpusPath = path.join(here, "fixtures", "checksum-decision-corpus.json");
const emulatorPath = path.join(here, "Start-ArlEmulator.ps1");
const count = Number(process.argv[2] ?? 50);
if (!Number.isInteger(count) || count < 1 || count > 500) throw new Error("count must be 1..500");
const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
const cases = Array.from({ length: count }, (_, index) => corpus.cases[index % corpus.cases.length]);
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "arl-offline-matrix-"));
const profilePath = path.join(temp, "profile.json");
const logPath = path.join(temp, "emulator.ndjson");
const port = 20000 + Math.floor(Math.random() * 20000);

const profile = {
  name: "offline-checksum-decision-matrix",
  description: "Generated localhost-only transport integrity matrix. Client decisions replay observed evidence; they do not prove IMPACT behavior.",
  safety: { transport: "localhost_tcp", listen_address: "127.0.0.1", touches_arl_hardware: false, opens_real_com_port: false },
  transaction_idle_ms: 10,
  default_response_delay_ms: 0,
  responses: [
    ...cases.map((item, index) => ({
    label: `matrix-${String(index + 1).padStart(3, "0")}-${item.id}`,
    phase: "analysis-result",
    match: "exact_ascii",
    pattern_ascii: "#rd 246\r",
    response_ascii: item.row,
    repeat_policy: "sequence",
    sequence_key: "offline-matrix",
    sequence_index: index,
    sequence_next: index + 1,
    })),
    { label: "matrix-consume-accepted", phase: "decision", match: "exact_ascii", pattern_ascii: "#em 242\r", response_ascii: "" },
    { label: "matrix-consume-rejected", phase: "decision", match: "exact_ascii", pattern_ascii: "?\r", response_ascii: "" },
  ],
};
const serialized = JSON.stringify(profile, null, 2) + "\n";
if (/COM\d|directserial|realport/i.test(serialized)) throw new Error("matrix profile contains a physical serial reference");
fs.writeFileSync(profilePath, serialized);

const emulator = childProcess.spawn("pwsh", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", emulatorPath,
  "-ProfilePath", profilePath, "-ListenAddress", "127.0.0.1", "-Port", String(port), "-LogPath", logPath,
  "-MaxConnections", "1", "-ExitAfterIdleMs", "500"],
  { stdio: ["ignore", "pipe", "pipe"] });
let stderr = "";
emulator.stderr.on("data", (data) => { stderr += data; });

function connect() {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 10000;
    const attempt = () => {
      const socket = net.createConnection({ host: "127.0.0.1", port });
      socket.once("connect", () => resolve(socket));
      socket.once("error", (error) => {
        socket.destroy();
        if (Date.now() >= deadline) reject(error); else setTimeout(attempt, 50);
      });
    };
    attempt();
  });
}

function readFrame(socket) {
  return new Promise((resolve, reject) => {
    let data = Buffer.alloc(0);
    const timeout = setTimeout(() => { cleanup(); reject(new Error("response timeout")); }, 5000);
    const onData = (chunk) => {
      data = Buffer.concat([data, chunk]);
      const end = data.indexOf(13);
      if (end >= 0) { const frame = data.subarray(0, end + 1).toString("ascii"); cleanup(); resolve(frame); }
    };
    const onError = (error) => { cleanup(); reject(error); };
    const cleanup = () => { clearTimeout(timeout); socket.off("data", onData); socket.off("error", onError); };
    socket.on("data", onData); socket.on("error", onError);
  });
}

let socket;
try {
  socket = await connect();
  for (let index = 0; index < cases.length; index += 1) {
    socket.write("#rd 246\r", "ascii");
    const actual = await readFrame(socket);
    if (actual !== cases[index].row) throw new Error(`attempt ${index + 1}: byte mismatch`);
    socket.write(cases[index].decision === "accepted" ? "#em 242\r" : "?\r", "ascii");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  socket.destroy();
  await Promise.race([
    new Promise((resolve) => emulator.once("exit", resolve)),
    new Promise((_, reject) => setTimeout(() => reject(new Error("emulator exit timeout")), 5000)),
  ]);
  if (emulator.exitCode !== 0) throw new Error(`emulator exited ${emulator.exitCode}: ${stderr}`);
  const events = fs.readFileSync(logPath, "utf8").split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  const matches = events.filter((event) => event.event === "rule_match" && event.phase === "analysis-result" && String(event.rule).startsWith("matrix-"));
  if (matches.length !== count) throw new Error(`expected ${count} rule matches, got ${matches.length}`);
  const result = { ok: true, attempts: count, exact_rows: corpus.cases.length, accepted_replays: cases.filter((item) => item.decision === "accepted").length,
    rejected_replays: cases.filter((item) => item.decision === "rejected").length, physical_serial_references: 0, log_bytes: fs.statSync(logPath).size };
  console.log(JSON.stringify(result));
} finally {
  socket?.destroy();
  if (emulator.exitCode === null) emulator.kill("SIGKILL");
  if (!process.env.ARL_KEEP_MATRIX_TEMP) fs.rmSync(temp, { recursive: true, force: true });
}
