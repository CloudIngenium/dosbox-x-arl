# ARL 3460 Lab History - July 2026

This document is the handoff log for the ARL 3460 / IMPACT+ / DOSBox-X recovery
work. It captures the tests, hypotheses, evidence, changes, and current next
steps so the work can resume in another thread, machine, or shift without
rediscovering the same facts.

## Current Objective

Make `Laboratorio-ARL.Corp.Tpu.mx` run IMPACT+ reliably against the Thermo/ARL
3460 using Windows 11, DOSBox-X, and the PCIe serial card, while keeping the
native FreeDOS/native-COM machine as production fallback.

The current pass/fail gate is not "IMPACT can talk to the ARL". That already
passes sometimes. The gate is:

- IMPACT initializes the ARL.
- IMPACT reads status channels.
- IMPACT sends the analysis request.
- The ARL sparks and returns result/status.
- IMPACT accepts the result, exits the busy state, sends the expected end/ack
  transition, updates `INTERFAC.DAT`, and can repeat this for several analyses.
- Printed output is captured on disk and can be sent to the Epson printer.

## Machines And Stable Facts

- HP bench PC: `Laboratorio-ARL.Corp.Tpu.mx`.
- Do not use `10.30.1.6` for this lab PC; that was observed to be a different
  Linux host.
- ARL serial cable is on WCH `COM5`.
- The second WCH serial port is `COM4`.
- `COM3` is Intel AMT SOL and is not the ARL port.
- WCH registry/device mapping was more reliable than `Win32_SerialPort`.
- WCH FIFO/buffer settings were reduced/disabled. Memory from the earlier run
  records COM5 moved from `RxFIFO=128, TxFIFO=256` to `RxFIFO=1, TxFIFO=1` with
  a registry backup and `pnputil /restart-device`.
- Current IMPACT path on the HP: `C:\ARL\IMPLUS`.
- Current ARL toolkit path on the HP: `C:\ARL\DOSBox-X-ARL`.
- Current diagnostics root: `C:\ARL\diagnostics`.
- Current known working/fallback production path remains the older
  FreeDOS/native-COM machine.

## Hardware And DOS Context

Known-good behavior:

- ARL hardware and cable are presumed good because IMPACT works on older
  computers using native serial ports under FreeDOS/MS-DOS.
- The same class of failure happened historically under Windows 7 DOS emulation,
  while the same hardware worked when booted into FreeDOS on bare metal.

Current HP/Windows/DOSBox-X stack:

- Windows 11 host.
- DOSBox-X directserial opens Windows `COM5`.
- DOS guest sees this as COM1.
- IMPACT changes serial settings during a run; status traffic is seen at 9600
  baud, and post-result result-read traffic is seen at 2400 baud.
- We are treating this as a Windows/DOSBox-X UART/state/timing problem until
  proven otherwise.

Dell/FreeDOS printer note:

- The Dell server has a StarTech `PEX1SP950` 1S1P Native PCI Express card with a
  16C950 UART.
- BIOS showed the StarTech serial and parallel ports assigned IRQs, but IMPACT
  still reported printer errors on the Dell.
- FreeDOS/native-COM is still the ARL measurement fallback. LPT printing on that
  Dell is a separate issue from the HP DOSBox-X post-result serial loop.

## Software Built Or Deployed

Fork:

- Repository: `CloudIngenium/dosbox-x-arl`.
- Local working branch during this investigation: `arl-trace-push`.
- Upstream base: normal DOSBox-X `2026.07.02`, tag `dosbox-x-v2026.07.02`.

Important lab builds:

- `96994b1` moved UART data-register tracing to the code paths IMPACT actually
  uses, so `uartdata` can prove guest `THR/RHR` access.
- `9663306` added the SIMPLE386 reject-test matrix and modem-line options.
- As of the 2026-07-08 remote repair, HP uses
  `C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe` with SHA256
  `4FD862333CE71A86F942CCF46B14490D534A7623D95CEE3D63CA6B7BBD1FF8E6`.

Recent commits in the fork:

- `fa2f6e8` - Add ARL safe serial trace launcher.
- `55a49f7` - Fix ARL trace launchers parameter splatting.
- `f7c0d5e` - Fix ARL LPT watcher argument quoting.
- `6948cc7` - Document ARL safe serial trace regression.
- `c3b2ebc` - Add ARL RX4000 tuning launcher.
- `fc3851b` - Add ARL UARTDATA diagnostic launcher.
- `1cc500d` - Validate ARL UARTDATA launcher in CI.
- `85fcc41` - Cap ARL serial trace size.
- `ac246de` - Handle ARL checksum sweep end-sample command.
- `6436a9b` - Add ARL emulator setup fallbacks.

CI status at the time this note was written:

- Workflow run for `1cc500d` completed successfully.
- Workflow run for `85fcc41` was still in progress.

## Desktop Shortcuts And Launchers

The HP has side-by-side launchers. They generate timestamped diagnostics folders
under `C:\ARL\diagnostics`.

Normal/low-overhead profile:

- Shortcut: `ARL IMPACT+ STABILITY TRACE`.
- Script: `Launch-ArlImpactStabilityTrace.ps1`.
- Settings: `cycles=fixed 8000`, `rxdelay:3000`, `arltracelevel:basic`,
  `arltracehangms:30000`.
- Use for normal repeat tests after the root issue is understood.

High-rxdelay regression profile:

- Shortcut/script: `ARL IMPACT+ SAFE SERIAL TRACE`.
- Settings: `cycles=fixed 8000`, `rxdelay:10000`, `arltracelevel:basic`.
- Result: worse than `rxdelay:3000`; do not use as the next default.

Intermediate-rxdelay profile:

- Shortcut: `ARL IMPACT+ RX4000 TRACE`.
- Settings: `cycles=fixed 8000`, `rxdelay:4000`, `arltracelevel:basic`.
- Result: reproduced the same post-result loop as `rxdelay:3000`.

Deep UART diagnostic profile:

- Shortcut: `ARL IMPACT+ UARTDATA TRACE`.
- Script: `Launch-ArlImpactUartDataTrace.ps1`.
- Settings: `cycles=fixed 8000`, `rxdelay:3000`, `arltracelevel:uartdata`,
  `arltracehangms:15000`.
- Purpose: one controlled burn only, to prove whether IMPACT consumes guest UART
  receive data (`RHR`) cleanly during the repeated-result loop.

## Trace Options Added To DOSBox-X

`directserial` now accepts ARL observability options:

```ini
serial1 = directserial realport:COM5 rxdelay:3000 arltracelevel:basic arltracesession:sample-analysis arltracehangms:30000 arltracemaxmb:64 arltrace:C:\ARL\diagnostics\<run>\serial.ndjson
```

Options:

- `arltrace:<file>` writes NDJSON trace events.
- `arltracelevel:basic|uartdata|uart|full`.
- `arltracesession:<label>`.
- `arltracehangms:<ms>`.
- `arltracemaxmb:<mb>`, added after trace files grew very large in loops.

Trace levels:

- `basic`: TX/RX bytes, baud/data/parity/stop, RX error bits, modem lines.
- `uartdata`: `basic` plus guest `THR/RHR` reads/writes.
- `uart`: more guest UART register reads/writes.
- `full`: host Windows serial DCB/timeouts/modem state. Use only briefly.

The default generated configs now include a 64 MB trace cap for future builds.
The currently deployed `96994b1` EXE does not yet enforce `arltracemaxmb`, but
the option is already in the generated configs so the next artifact will honor
it without changing shortcuts.

## LPT / Printing Work

Goal:

- Capture what IMPACT prints.
- Preserve it on disk for later parsing/Zap ingestion.
- Send it immediately to the Epson printer when requested/available.

DOSBox-X config:

```ini
parallel1 = file append:C:\ARL\diagnostics\<run>\LPTCAP.PRN timeout:2000
```

Helper scripts:

- `Print-ArlLptCapture.ps1`.
- `Watch-ArlLptCapture.ps1`.

Findings and fixes:

- A good run produced `LPTCAP.PRN` with a complete ASCII IMPACT report.
- The Epson was detected as `EPSON LX-350` on `USB001`.
- Dry-run validated reading a 7,594 byte captured report and preparing 7,595
  bytes with a final form-feed.
- The first watcher launcher generated PowerShell arguments without commas, so
  `-SpoolDir` was incorrectly parsed as the `ParentPid` value. This prevented
  auto-print/capture watcher behavior.
- `Start-ArlTraceRun.ps1` was fixed to generate a proper PowerShell array for
  watcher arguments.
- On `2026-07-08 16:43`, the HP still had stale `.ps1` toolkit copies and
  reproduced the `ParentPid` parsing error in
  `sample-analysis-20260708-163002\lpt-watch.err.log`. The corrected
  `contrib/arl/*.ps1` scripts were recopied to `C:\ARL\DOSBox-X-ARL\`, and a
  smoke test of `Watch-ArlLptCapture.ps1` with a fake parent PID exited cleanly
  without the parameter error.

Expected behavior after the fix:

- `LPTCAP.PRN` remains the raw appended capture.
- Stable appended chunks are copied to `print-jobs\*.prn`.
- Each print job gets a JSON manifest and SHA256.
- If auto-print is enabled, the raw bytes are sent to `EPSON LX-350`, with a
  form-feed appended only for the sent copy.

## TICS Work

TICS was investigated as a safer independent tool to validate the ACS/ICS link.

Findings:

- Running `tics` directly from the mounted IMPACT root initially failed with
  "Bad command or filename".
- TICS expects legacy database/procedure paths.
- The UI showed `DBTICS` database selection and then requested a path like
  `C:\TICS\PROC`.
- `Start-ArlTraceRun.ps1` prepares aliases from `DBTICSOE.*` to `DBTICS.*` when
  needed and creates `C:\ARL\IMPLUS\TICS\PROC` for the DOS `C:\TICS\PROC` path.

TICS safety rule:

- Use TICS for read-only/non-destructive checks only: communication parameters,
  statistics, `TL`, `VE`, `SI`, and `RS`.
- Do not run synchronize/reset commands unless explicitly planning that test.

## Emulator Work

The emulator is a safe bench harness, not a replacement for the real ARL.

Design:

- V1 is external to DOSBox-X.
- DOSBox-X uses `serial1=nullmodem` to localhost.
- The emulator never opens `COM5`.
- Profiles are trace-driven and must be derived only from real, confirmed
  protocol bytes.

Modes prepared:

- `happy-path`.
- `silent-after-spark`.
- `delayed-result`.
- `line-drop`.
- `bad-response`.

Purpose:

- Let IMPACT/TICS be tested against controlled responses after enough real
  protocol traces are captured.
- Reproduce "silent after spark" or "delayed result" safely without touching the
  real ARL.

### Checksum Acceptance Finding

Detailed checksum notes and the current inventory are maintained in
`docs/ARL-PROTOCOL-CHECKSUM-NOTES-2026-07.md`.

As of 2026-07-09, the local inventory from five captured real traces contains 18
result rows:

- 13 accepted rows, all with checksum `000-099`.
- 5 rejected rows, all with checksum `100-255`.
- Every rejected row has a checksum that validates under the observed algorithm
  of summing ASCII payload bytes modulo 256.

Interpretation: the failure is probably not RX loss. IMPACT appears to reject
valid result rows when the result checksum is a three-digit value of 100 or
higher. This may be a receive-side parser/presentation bug in IMPACT rather than
an ARL checksum error.

The `95 EMU CHECKSUM SWEEP` profile was adjusted after it accidentally sent the
same `099` row as both the control and recovery row. That caused IMPACT to treat
two identical rows as a stable complete sample and enter the `Store Result?`
flow, contaminating the checksum experiment. The profile now uses visually
distinct values for every sweep case and a sequence of distinct low-checksum
recovery rows after `?`, so the experiment measures checksum/format acceptance
rather than repeated-sample behavior. Trace-derived emulator profiles also
include safe fallbacks for `st `, `#st `, `ns `, and `#ns ` setup/new-sample
commands.

Next emulator tests:

- Verify `099` is accepted.
- Verify `100` and `101` are rejected.
- Test `100` as `00`, `101` as `01`, and `117` as `17`.
- Test leading-zero-shaped rows that preserve numeric values but recompute to
  checksum values below 100.

## Test Timeline And Evidence

### Earlier Windows/FIFO baseline

Observation:

- The ARL works on older FreeDOS/native-COM computers.
- Windows DOS emulation historically reproduced the post-spark issue.
- Windows-side buffering was therefore a high-priority suspect.

Actions:

- Verified HP COM mapping through registry/PnP instead of `Win32_SerialPort`.
- Reduced WCH COM5 FIFO/buffers to minimum/disabled.
- After FIFO was disabled, status channel reads became possible again.

Conclusion:

- FIFO/buffering matters, but it did not fully solve the post-spark result loop.

### Basic status-read success

Observation:

- IMPACT could initialize the ARL and read temperature/voltage/status channels
  with the HP/DOSBox-X stack.

Conclusion:

- The failure is not basic COM opening or a completely wrong serial port.
- The failure occurs later, around analysis result/status completion.

### Run `sample-analysis-20260708-131347`

Symptom:

- "Please Run Sample" stopped blinking but values did not load on screen.
- `INTERFAC.DAT` did not update.

Trace facts:

- ARL bytes reached DOSBox-X.
- RX continued with `rx_error_bits=0`.
- The ARL repeatedly returned numeric result lines after `we 252` and
  `#rd 246`.

Conclusion:

- This pointed away from total Windows RX loss and toward IMPACT not accepting
  or completing the post-result state.

### Run `sample-analysis-20260708-135100`

Symptom:

- First burn completed and displayed values.
- Second burn entered the result wait/poll loop.

Trace facts:

- DOSBox-X kept receiving ARL bytes.
- IMPACT kept reading guest UART `RHR`; RX bytes and guest RHR reads matched in
  the analyzer snapshot.
- No framing, parity, overrun, or write errors were seen.
- The second result phase entered repeated `#rd 246` plus many `?` polls.

Conclusion:

- Serial receive was alive during the failure.
- The failure is not simply "ARL is silent" or "Windows dropped all RX bytes".

### Run `sample-analysis-20260708-145951`

This is the most valuable mixed-good/mixed-bad trace so far.

Symptoms:

- IMPACT displayed three readings and got ready to print.
- Later it entered the same stuck post-result loop.

Trace facts:

- Four `#rd` result transactions were seen.
- Three good result transactions were followed by `#em`.
- The loop transaction had 136 `?` polls and no `#em`.
- The ARL kept sending parseable numeric result rows.
- The same run captured a complete `LPTCAP.PRN` report.

Conclusion:

- `#em` is a strong discriminator between accepted and stuck result
  transactions.
- The bug can appear after successful reads in the same DOSBox/IMPACT session.
- This run should be preserved as the reference "good then bad" trace.

### Run `sample-analysis-20260708-154724`

Profile:

- `rxdelay:10000`, `cycles=fixed 8000`, `arltracelevel:basic`.

Symptoms:

- IMPACT did not accept readings.

Trace facts:

- `TX bytes: 788`.
- `RX bytes: 10694`.
- No RX framing/parity/overrun errors.
- One `#rd 246` result transaction.
- 104 `?` polls.
- The ARL repeatedly returned a parseable numeric result row.
- IMPACT never sent `#em`.

Conclusion:

- `rxdelay:10000` is worse than the 3000 stability profile and should not be
  the default.

### Runs `sample-analysis-20260708-155656` and `sample-analysis-20260708-160436`

Profiles:

- `rxdelay:3000` and `rxdelay:4000`, both `cycles=fixed 8000`.

Trace facts:

- Both reproduced the same pattern:
  - IMPACT sends setup/status commands.
  - IMPACT sends `#rd 246`.
  - ARL returns repeated numeric result rows at 2400 baud.
  - IMPACT keeps sending `?`.
  - IMPACT does not send `#em`.
- RX errors were zero in these traces.

Conclusion:

- Raising `rxdelay` slightly from 3000 to 4000 did not solve the loop.
- The next test should change observability (`uartdata`), not keep tuning
  `rxdelay` blindly.

### Run `sample-analysis-20260708-160646`

Profile:

- `rxdelay:4000`, `cycles=fixed 8000`, basic trace.

Symptom:

- IMPACT got stuck reading status channels or in an earlier status state.

Trace facts:

- It did not reach `#rd`.
- It repeatedly sent status-style `st` traffic at 9600 baud.
- RX bytes had errors, mostly `err=24` at 9600 baud.
- Observed bytes were mostly non-ASCII/noisy values such as `80`, `78`, `F8`,
  and `00`.

Conclusion:

- This is likely a secondary state problem after closing DOSBox while the ARL/ICS
  was still in the post-result read state.
- It should not be treated as the same root failure as the clean 2400-baud
  `#rd` loop.
- Before another test, clear/reinitialize the ARL/ICS state, not just IMPACT.

### Runs `sample-analysis-20260708-160703` and `sample-analysis-20260708-160736`

Profiles:

- `160703`: `rxdelay:10000`, basic.
- `160736`: `rxdelay:3000`, basic.

Trace facts:

- `160703` mostly reached status traffic and did not enter result read.
- `160736` entered the `#rd 246` loop with repeated numeric rows and no `#em`.

Conclusion:

- The state can alternate between:
  - clean post-result loop at 2400 baud with valid repeated rows; and
  - dirty/recovery status-read failure at 9600 baud after closing mid-loop.

### Run `sample-analysis-20260708-163002`

Profile:

- `ARL IMPACT+ UARTDATA TRACE`.
- `rxdelay:3000`, `cycles=fixed 8000`, `arltracelevel:uartdata`.

Symptom:

- The burn finished at the ARL, but IMPACT stayed on "Please Run Sample" and did
  not show the analysis values.

Trace facts:

- Active DOSBox process used:
  `C:\ARL\diagnostics\sample-analysis-20260708-163002\dosbox-sample-analysis.conf`.
- `serial.ndjson` was 8.55 MB, 19,263 trace lines.
- TX/RX summary:
  - `tx=753`.
  - `rx=7220`.
  - guest UART `THR=753`.
  - guest UART `RHR=7220`.
  - `rx_after_rd=6983`.
  - `rhr_after_rd=6983`.
- Error/FIFO summary:
  - `rx_error_bits=0` for all 7,220 RX bytes.
  - `max_errors_in_fifo=0`.
  - `max_overrun_errors=0`.
- Protocol summary:
  - IMPACT sent one `#rd 246`.
  - The ARL returned a valid numeric row beginning with `#`.
  - IMPACT then sent 70 `?` retries.
  - The ARL repeated the same numeric result row after each `?`.
  - IMPACT never sent `#em`.
- Result row seen repeatedly:

  ```text
  #16.884,2.592,0.581,0.288,0.606,12.364,1.082,13.719,0.805,12.794,2.742,5.244,2.478,0.963,13.719 113
  ```

- Checksum was valid using the same rule as accepted rows: modulo-256 of the
  ASCII payload without leading `#`, including the trailing space before the
  checksum.
- `INTERFAC.DAT` did not update; it remained at `2026-07-08 15:05:43`.
- `TELEX.DAT` and `IMPACT.INI` were touched at launch time
  (`2026-07-08 16:30:22`) but no accepted analysis file write occurred.

Comparison to mixed-good run `sample-analysis-20260708-145951`:

- Accepted transactions:
  - `#rd 246`.
  - ARL result row.
  - IMPACT sends `#em 242` about 60 ms later.
  - IMPACT continues with `pa`, `#m1`, `cl`, `dc`, `m2`, `we`.
- Rejected/stuck transactions:
  - `#rd 246`.
  - ARL result row.
  - IMPACT sends `?` within a few milliseconds.
  - ARL repeats the same row.
  - No `#em`.

Conclusion:

- This trace rejects the theory that Windows/DOSBox receives bytes but fails to
  deliver them to the DOS guest during the main loop.
- Host RX and guest `RHR` reads matched exactly in the loop.
- The clean failure is now best described as: IMPACT receives a syntactically
  valid result row, rejects it at the application/protocol state level, sends
  `?`, and never transitions to `#em`.

## Protocol Discoveries

Command checksum:

- The trailing number after commands and result rows appears to be modulo-256
  checksum of the ASCII payload including the trailing space before the checksum.
- Example: `#rd 246`.
- Example: `#em 242`.
- The repeated numeric result rows in failing traces also matched this checksum
  rule.

Important implication:

- The ARL is not obviously returning corrupt ASCII result rows during the
  repeated-result loop.
- If IMPACT rejects them, the reason is now more likely an IMPACT/ICS
  state-machine or expected-result condition than host RX loss.

Accepted-result discriminator:

- Good result transactions include `#em` after `#rd`.
- Stuck result transactions do not include `#em`.
- The repeated `?` polling loop is the signature of a not-accepted result.

UART delivery discriminator:

- `sample-analysis-20260708-163002` proved host RX and guest UART `RHR` reads
  matched exactly during the repeated-result loop.
- That means the current clean failure is not "DOSBox received bytes but IMPACT
  did not read them".
- The failed packet is read by IMPACT and then rejected quickly enough that
  IMPACT sends `?` within a few milliseconds of receiving the row.

Baud/state discriminator:

- Clean post-result loop: 2400 baud, numeric rows, RX errors zero.
- Dirty status-read state: 9600 baud, RX error bits nonzero, garbage-like bytes.

## Hypotheses Tested

### H1: Wrong COM port or no basic communication

Status: rejected.

Evidence:

- IMPACT initializes the ARL and reads status channels.
- TX/RX traces show real protocol exchanges on `COM5`.

### H2: WCH/Windows FIFO causes loss

Status: partially supported but not sufficient.

Evidence:

- Disabling/minimizing FIFO helped status reads.
- Post-result failure still occurs after FIFO reduction.

### H3: `rxdelay:10000` gives IMPACT enough time

Status: rejected for now.

Evidence:

- `sample-analysis-20260708-154724` showed worse behavior with no accepted
  readings and the same `#rd`/`?`/no-`#em` pattern.

### H4: `rxdelay:4000` is a better middle value than 3000

Status: not supported.

Evidence:

- `rxdelay:4000` reproduced the same loop.

### H5: Curve/alloy selection causes the failure

Status: mostly rejected.

Evidence:

- The hypothesis was plausible because failures were observed while using
  `KC-356Y/KC-356HY`.
- Switching back to `AL / AL` reproduced the same "Please Run Sample" loop.
- The same session/history showed failures after prior successful readings,
  independent of curve.

### H6: ARL is silent after spark

Status: rejected for the main failure.

Evidence:

- In the main failure traces, RX bytes continue and the ARL repeats valid
  numeric rows.

### H7: IMPACT receives bytes but does not accept the result

Status: strongly supported and current leading hypothesis.

Evidence:

- Repeated valid result rows.
- No RX errors in clean post-result loops.
- Good transactions send `#em`; bad transactions do not.
- `INTERFAC.DAT` does not update in bad transactions.
- In `sample-analysis-20260708-163002`, host RX bytes and guest `RHR` reads
  matched exactly (`7220` each), so IMPACT had access to the returned bytes.

### H8: Closing DOSBox mid-loop leaves ARL/ICS in a dirty state

Status: strongly supported.

Evidence:

- After closing a stuck session, later runs sometimes fail earlier at status
  channels.
- Dirty status traces show RX errors at 9600 baud, not valid 2400-baud result
  rows.
- This fits ARL/ICS still being in a post-result conversation while IMPACT
  restarts status polling.

## Current Interpretation

There appear to be two related but distinct states:

1. Main post-result loop:
   - IMPACT reaches analysis result read.
   - ARL sends valid numeric rows at 2400 baud.
   - DOSBox receives those bytes and the DOS guest reads them from `RHR`.
   - IMPACT sends repeated `?`.
   - IMPACT never sends `#em`.
   - No RX framing/parity/overrun errors in the clean examples.
   - `INTERFAC.DAT` does not update.

2. Dirty restart/status state:
   - Happens after closing DOSBox/IMPACT during the post-result loop.
   - IMPACT starts status reads at 9600 baud.
   - RX has framing/break-style errors.
   - This likely means ARL/ICS was not reinitialized back to the status protocol
     state.

The `uartdata` trace answered the previous open question: IMPACT reads the
returned bytes from the guest UART. The next useful work is to determine what
condition makes IMPACT choose `?` instead of `#em`.

## Current Next Test Protocol

Before the next burn:

- Close any active DOSBox-X.
- Confirm no DOSBox-X process is active.
- Clear/reinitialize the ARL/ICS state with the operator. Do not assume
  restarting IMPACT alone is enough.
- Use `AL / AL` for the next controlled test unless the operator explicitly
  needs another curve.

Run:

- Prefer `ARL IMPACT+ UARTDATA TRACE` for one more controlled single-burn test
  if disk space allows; otherwise use `ARL IMPACT+ STABILITY TRACE`.
- Do one burn only per launch.
- If it succeeds, record the run folder and do not immediately change multiple
  variables.
- If "Please Run Sample" keeps blinking more than 60 to 90 seconds after the
  ARL finished, close DOSBox-X to stop trace growth and preserve the run folder.

Recommended next variables to test, one at a time:

- `cycles=fixed 6000` with `rxdelay:3000`.
- `cycles=fixed 10000` with `rxdelay:3000`.
- Fresh ARL/ICS state before each run, avoiding repeated restarts after a stuck
  loop without operator-side reinitialization.
- Same exact sample/curve sequence after a full ARL/ICS reset to check whether
  accepted versus rejected rows correlate with instrument state rather than
  DOSBox timing.

Expected output:

- New folder under `C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS`.
- `serial.ndjson` with `basic` plus guest `THR/RHR` events.
- `run-metadata.json` showing `trace_level = uartdata`.
- If IMPACT prints, `LPTCAP.PRN` and `print-jobs\*.prn`.

Analyze after test:

```powershell
C:\ARL\DOSBox-X-ARL\Analyze-ArlTrace.ps1 `
  -TracePath C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS\serial.ndjson `
  -OutDir C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS

C:\ARL\DOSBox-X-ARL\Compare-ArlResultTransactions.ps1 `
  -RunPath C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS
```

Questions to answer:

- Does changing CPU timing change the moment IMPACT chooses `?` versus `#em`?
- Does a fresh ARL/ICS state allow the first result row to be accepted
  consistently?
- Do failed rows always have valid checksum and the same 15-value shape as
  accepted rows?
- Does the loop begin after a particular IMPACT command sequence before `#rd`
  (`pa`, `#m1`, `cl`, `dc`, `m2`, `we`)?
- Does `INTERFAC.DAT` update only on transactions where `#em` appears?

## If Work Resumes Later

Start here:

1. Read this file.
2. Read `docs/ARL-TRACE.md`.
3. On the HP, inspect the latest run folders:

   ```powershell
   Get-ChildItem C:\ARL\diagnostics -Directory |
     Sort-Object LastWriteTime -Descending |
     Select-Object -First 10 Name, LastWriteTime
   ```

4. Preserve the reference mixed-good run:

   ```text
   C:\ARL\diagnostics\sample-analysis-20260708-145951
   ```

5. Do not resume by changing many timing values at once. Use one variable per
   burn.

Do not forget:

- `rxdelay:10000` was worse.
- `rxdelay:4000` did not fix the loop.
- Curve/alloy selection is unlikely to be the primary cause.
- A status-read hang after closing DOSBox mid-loop may be dirty ARL/ICS state,
  not a new COM configuration failure.
- `#em` after `#rd` is the key accepted-result signal.
- `UARTDATA TRACE` showed host RX and guest `RHR` reads match exactly in the
  clean loop.
- The clean loop is now an IMPACT/ICS acceptance problem, not a proven Windows
  RX delivery problem.

## 2026-07-08 17:33 CYCLES6000 Good Reference

Launcher:

- `ARL IMPACT+ CYCLES6000 TRACE`.
- `cycles=fixed 6000`.
- `rxdelay:3000`.
- `trace_level=basic`.
- Direct serial COM5, WCH FIFO disabled/minimized.

Run folder:

```text
C:\ARL\diagnostics\sample-analysis-20260708-173311
```

Observed while the session was still open:

- `serial.ndjson` grew normally without runaway size.
- At 17:40, trace summary showed `#rd=4`, `#em=4`, `?=0`.
- RX/TX errors were zero.
- `LPTCAP.PRN` contained real IMPACT print output, including "Absolute
  Intensities" and "Ratioed Intensities".
- A preservation snapshot was copied:
  - `INTERFAC.DAT.snapshot-20260708-174032`
  - `LPTCAP.snapshot-20260708-174032.PRN`

Interpretation:

- This is the best good-reference HP/DOSBox-X run so far.
- `6000/3000` is currently the strongest timing candidate.
- The important difference from bad runs is not merely whether bytes arrive;
  accepted rows are followed by `#em`, while rejected loops send `?`.
- Continue testing `6000/3000` before moving to 10000 or other variables.

LPT note:

- The raw DOSBox LPT capture worked.
- Auto-print did not run for this already-open session because the HP had a
  stale `Watch-ArlLptCapture.ps1` that did not understand `-SpoolDir` and
  parsed it as `ParentPid`.
- The corrected `Watch-ArlLptCapture.ps1` and `Print-ArlLptCapture.ps1` were
  recopied to `C:\ARL\DOSBox-X-ARL\`.
- A smoke test with `-ExecutionPolicy Bypass` confirmed the corrected watcher
  accepts `-SpoolDir` and exits cleanly when the parent PID is gone.

## 2026-07-08 17:46 CYCLES6000 Multi-Burn Failure

Same run folder:

```text
C:\ARL\diagnostics\sample-analysis-20260708-173311
```

Operator sequence:

- Approximately two burns in `AL / AL`.
- Then switched to `AL / SS-413BD`.
- Four SS-413BD burns displayed correctly.
- The fifth SS-413BD burn stuck with the prior four rows still on screen.

Analyzer output:

- `#rd=8`, `#em=7`, `?=95`.
- RX errors: zero.
- TX errors: zero.
- New analyzer metrics report:
  - Result-read transactions: 8.
  - Accepted results: 7.
  - Rejected results: 1.
  - Accepted before first reject: 7.
  - First rejected row duration: 757 ms.
  - IMPACT sent `?` 5 ms after the row terminator.
- Trace did not show a Windows receive loss; it showed a valid result row
  repeated while IMPACT sent `?`.
- `result-transaction-comparison.md` classified candidate 33 as a post-result
  poll loop.
- The repeated row was:

```text
21.146,2.417,0.590,0.246,0.560,11.943,0.531,8.926,0.420,15.152,2.828,2.012,2.352,0.769,8.926 231
```

Checksum check:

- Claimed checksum: `231`.
- Computed checksum: `231`.
- Therefore the rejected row is checksum-valid.

Interpretation:

- This is not a silent ARL, missing RX, or bad-checksum failure.
- `6000/3000` is still the best observed setting, but it can fall into an
  IMPACT acceptance loop after several successful burns.
- The next parameter test should keep `rxdelay=3000` and sweep cycles near
  6000 rather than jumping back to `10000`.

Next launchers added:

- `ARL IMPACT+ CYCLES5000 TRACE` (`cycles=fixed 5000`, `rxdelay:3000`).
- `ARL IMPACT+ CYCLES7000 TRACE` (`cycles=fixed 7000`, `rxdelay:3000`).

Offline toolkit updates:

- `Analyze-ArlTrace.ps1` now writes `lab-next-test.md` and
  `lab-next-test.json`.
- These files summarize result-read acceptance count, first rejected checksum,
  `INTERFAC.DAT`/LPT artifacts, and the next recommended variable.
- `Analyze-ArlTrace.ps1` now also writes `audit-manifest.md` and
  `audit-manifest.json` with SHA-256 hashes, file sizes, classification,
  result-read counts, and the selected next-step recommendation. Use this as
  the evidence index before moving a run into ARL.BauxTP.com or R2.

Original next test idea, superseded later the same day:

- We planned to try `CYCLES5000 TRACE` and `CYCLES7000 TRACE` around 6000.
- Those tests were run and did not improve the system. See the follow-up
  section below for the current recommendation.

## 2026-07-08 18:25-18:30 CYCLES5000 / CYCLES7000 Follow-Up

New runs:

```text
C:\ARL\diagnostics\sample-analysis-20260708-175857  cycles=5000 rxdelay=3000
C:\ARL\diagnostics\sample-analysis-20260708-182449  cycles=7000 rxdelay=3000
C:\ARL\diagnostics\sample-analysis-20260708-182520  cycles=7000 rxdelay=3000
C:\ARL\diagnostics\sample-analysis-20260708-182856  cycles=7000 rxdelay=3000
```

Findings:

- `5000/3000` reached result read once, but rejected immediately:
  - `#rd=1`, `#em=0`, `?=187`.
  - First row checksum was valid: claimed `238`, computed `238`.
  - RX/TX errors were zero.
  - This is not better than 6000; it fails on the first result instead of
    after several accepted results.
- `7000/3000` did not reach result read:
  - `#rd=0`.
  - Repeated status/readiness traffic such as `st`, `#rs`, and `ns`.
  - One long run had RX errors.
  - This setting appears worse for initialization/status stability.

Updated interpretation:

- The cycle sweep did not reveal a better value around 6000.
- `6000/3000` remains the best observed transport setting.
- The practical next step is not more wide cycle sweeps; it is:
  - session hygiene,
  - short IMPACT sessions,
  - 6000/3000 after ARL service,
  - `ARL IMPACT+ CYCLES6000 UARTDATA TRACE` only if normal 6000 fails again.

Updated recommended test order:

1. After ARL service, launch `ARL IMPACT+ CYCLES6000 TRACE`.
2. Use a fresh DOSBox/IMPACT session.
3. Run one reference burn.
4. If it passes, run up to four burns maximum, then close/reopen IMPACT before
   attempting more.
5. If it fails with `?`, launch `ARL IMPACT+ CYCLES6000 UARTDATA TRACE` for
   one detailed burn; do not keep moving cycles blindly.

## 2026-07-08 386-Class Cycle Probe

Rationale:

- IMPACT appears to accept or reject complete checksum-valid result rows within
  a few milliseconds, so the remaining hypothesis is a narrow DOS timing/state
  window rather than missing serial bytes.
- A 1993-era IMPACT installation plausibly targeted 386DX/33-40 or early
  486SX/25-class PCs. DOSBox-X `cycles` is not a direct MHz conversion, but it
  is the available control for guest instruction pacing.

New controlled launchers:

- `ARL IMPACT+ CYCLES3500 TRACE` (`cycles=fixed 3500`, `rxdelay:3000`).
- `ARL IMPACT+ CYCLES4000 TRACE` (`cycles=fixed 4000`, `rxdelay:3000`).

Test order:

1. Fresh DOSBox/IMPACT session.
2. Try `CYCLES3500 TRACE` first.
3. If status channels do not read or the first result fails, close DOSBox and
   try `CYCLES4000 TRACE`.
4. Stop after the first failure loop and run `Analyze-ArlTrace.ps1 -NoTimeline`
   on the run folder.

Follow-up:

- `CYCLES3500 TRACE` read status and accepted the first burn, but the second
  burn fell back into the same "Please Run Sample" loop.
- `CYCLES4000 TRACE` did not read status channels.
- This weakens "find one magic cycle count" as the main fix. Cycle count still
  influences whether IMPACT reaches a usable state, but the accepted-vs-rejected
  traces show complete checksum-valid result rows being received before IMPACT
  sends `?`.
- The next no-rebuild variables should hold the best transport setting
  (`cycles=fixed 6000`, `rxdelay:3000`) and change DOSBox-X CPU personality:
  `core=simple`, `cputype=386`, then both together.

New launchers prepared:

- `ARL IMPACT+ CYCLES6000 SIMPLE TRACE`
  - `core=simple`
  - `cputype=486`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
- `ARL IMPACT+ CYCLES6000 CPU386 TRACE`
  - `core=normal`
  - `cputype=386`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
- `ARL IMPACT+ CYCLES6000 SIMPLE386 TRACE`
  - `core=simple`
  - `cputype=386`
  - `cycles=fixed 6000`
  - `rxdelay:3000`

Test these in that order. Stop a launcher after the first result-reject loop and
preserve/analyze the run instead of continuing to burn in the same stuck
conversation.

## 2026-07-08 Memory-Layout Probe

Rationale:

- IMPACT is receiving complete checksum-valid result rows but sometimes rejects
  them with `?` instead of accepting with `#em`.
- That can still be an IMPACT internal-state problem rather than a serial-loss
  problem: EMS/XMS/UMB layout, resident driver placement, or a buffer path that
  changes when old DOS software detects expanded memory.
- Native FreeDOS machines that work may have a different `CONFIG.SYS` /
  `AUTOEXEC.BAT` memory layout than DOSBox-X defaults.

New launchers prepared:

- `ARL IMPACT+ CYCLES6000 NOEMS TRACE`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
  - `memsize=16`
  - `xms=true`, `ems=false`, `umb=true`
- `ARL IMPACT+ CYCLES6000 LOWMEM TRACE`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
  - `memsize=4`
  - `xms=true`, `ems=false`, `umb=true`
- `ARL IMPACT+ CYCLES6000 CONVENTIONAL TRACE`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
  - `memsize=4`
  - `xms=false`, `ems=false`, `umb=false`
- `ARL IMPACT+ CYCLES6000 NOUMB TRACE`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
  - `memsize=16`
  - `xms=true`, `ems=true`, `umb=false`
- `ARL IMPACT+ CYCLES6000 NOMOUSE TRACE`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
  - `memsize=16`
  - `xms=true`, `ems=true`, `umb=true`
  - does not load `DOS\MOUSE.COM`

Test order:

1. `NOEMS` first. It is the least disruptive memory change and directly tests
   whether EMS detection changes IMPACT's buffering/result parser path.
2. `NOUMB` second if `NOEMS` still rejects rows. This keeps EMS enabled but
   removes upper-memory placement effects.
3. `NOMOUSE` third if the user can operate IMPACT from keyboard. This removes
   one resident DOS driver without changing EMS/XMS.
4. `LOWMEM` fourth if the softer memory-layout tests still reject rows.
5. `CONVENTIONAL` last. It may reduce free memory enough to expose other DOS
   limits, but it is useful if IMPACT was written for a very plain DOS memory
   environment.

For each memory variant, use a fresh IMPACT launch and stop after the first
reject loop. Do not combine memory changes with cycle/core/cputype changes until
one memory variant has a clear signal.

Correction after operator note:

- The failed run initially believed to be `NOEMS` was actually
  `ARL IMPACT+ CYCLES6000 UARTDATA TRACE`.
- Therefore `NOEMS` remains untested as of this note.
- `UARTDATA` is now treated as diagnostic-only because it adds high-volume UART
  register tracing and may perturb the same timing path being measured. Use
  `basic` trace launchers for stability tests.

## 2026-07-08 CYCLES6000 SIMPLE First Success And LPT Watcher Fix

Observed:

- `ARL IMPACT+ CYCLES6000 SIMPLE TRACE` completed at least the first analysis
  successfully, then the operator reported two completed analyses.
- Remote metadata confirmed:
  - `cycles=6000`
  - `rxdelay=3000`
  - `core=simple`
  - `cputype=486`
  - `trace_level=basic`
  - EMS/XMS/UMB normal.
- `LPTCAP.PRN` grew to 5242 bytes, so IMPACT did generate printer output.

Print issue:

- The auto-print watcher failed to start because `Start-ArlTraceRun.ps1`
  generated `$watcherArgs` as an array. PowerShell splatted it positionally into
  `Watch-ArlLptCapture.ps1`, so `-SpoolDir` was interpreted as the `ParentPid`
  argument.
- Fixed by generating a hashtable and splatting named parameters.
- Manual replay of `LPTCAP.PRN` sent 5243 RAW bytes, including an appended form
  feed, to `EPSON LX-350` on `USB001`.
- Windows showed the print job in the EPSON queue with status `Normal`; if no
  paper moved, the remaining issue is printer/driver/USB consumption, not LPT
  capture.

## 2026-07-08 SIMPLE386 Valid-Row Reject Reference

Reference run:

- `C:\ARL\diagnostics\sample-analysis-20260708-205041`
- Snapshot:
  `C:\ARL\diagnostics\sample-analysis-20260708-205041\snapshot-20260708-205610`
- Launcher profile:
  - `core=simple`
  - `cputype=386`
  - `cycles=fixed 6000`
  - `rxdelay:3000`
  - `arltracelevel=basic`

This is the current primary evidence run. IMPACT accepted three analysis rows,
then rejected the fourth even though the row was complete and checksum-valid.

Analyzer signal:

- result reads: `4`
- accepted by IMPACT: `3`
- rejected by IMPACT: `1`
- accepted before first reject: `3`
- post-result `?` poll count: `90`
- repeated result row count: `90`
- RX/TX errors: none reported by the trace analyzer

The rejected row:

```text
#106.251,13.389,2.615,0.690,3.180,65.430,1.528,62.935,1.454,87.305,11.880,10.284,19.361,6.779,62.935 117
```

Its trailing checksum is `117`, and the analyzer computed `117`. The important
shift is that this should not be treated as a simple Windows RX-loss failure.
The ARL returned a valid row, DOSBox-X captured it, and IMPACT then sent `?`
instead of `#em`.

Active hypotheses after this run:

- IMPACT rejects by value/range/curve state even though the serial row is valid.
- IMPACT accumulates state after several burns and rejects a later valid row.
- DOS memory layout or resident driver placement changes an old parser/buffer
  path.
- Modem-control lines do not match what a native COM port exposed to IMPACT or
  to the ARL/ICS.
- Printing or file side effects interfere after successful prior analyses.

Implemented no-rebuild test matrix:

1. `ARL IMPACT+ CYCLES6000 SIMPLE386 NOMOUSE TRACE`
   - `core=simple`, `cputype=386`, no `DOS\MOUSE.COM`.
2. `ARL IMPACT+ CYCLES6000 SIMPLE386 NOUMB TRACE`
   - `core=simple`, `cputype=386`, `umb=false`.
3. `ARL IMPACT+ CYCLES6000 SIMPLE386 NOAUTOPRINT TRACE`
   - captures `LPTCAP.PRN` but does not start the watcher or send to Epson.
4. `ARL IMPACT+ CYCLES6000 SIMPLE386 EMSBOARD TRACE`
   - `ems=emsboard`.
5. `ARL IMPACT+ CYCLES6000 SIMPLE386 EMM386 TRACE`
   - `ems=emm386`.

Additional no-rebuild DOS compatibility launchers:

- `ARL IMPACT+ CYCLES6000 SIMPLE386 ZEROEMS TRACE`
  - `zero memory on ems memory allocation=true`.
- `ARL IMPACT+ CYCLES6000 SIMPLE386 ZEROXMS TRACE`
  - `zero memory on xms memory allocation=true`.
- `ARL IMPACT+ CYCLES6000 SIMPLE386 MCBCOMPAT TRACE`
  - `mcb corruption becomes application free memory=true`.
- `ARL IMPACT+ CYCLES6000 SIMPLE386 NOSHARE TRACE`
  - `share=false`.
- `ARL IMPACT+ CYCLES6000 SIMPLE386 UNMASKDISKIO TRACE`
  - `unmask timer on disk io=true`.

Build-required launchers now installed on the HP:

- `ARL IMPACT+ CYCLES6000 SIMPLE386 FORCELINES TRACE`
  - adds `arlforcects:1 arlforcedsr:1 arlforcedcd:1`.
- `ARL IMPACT+ CYCLES6000 SIMPLE386 HOLDRTS-DTR TRACE`
  - adds `arlholdrts:1 arlholddtr:1`.

2026-07-08 modem-line test result:

- `FORCELINES` reached the analysis/result-read phase, but IMPACT rejected the
  first checksum-valid row and sent `?` repeatedly. The ARL/DOSBox trace showed
  `#rd`, a valid 15-value result row with checksum `214`, then repeated rows
  while IMPACT kept polling with `?`. This reproduces the valid-row reject
  pattern; it is not an ARL-silent failure.
- `HOLDRTS-DTR` was worse as an operator test: the captured sessions did not
  reach a useful result-read transaction. One run reached status read and got a
  valid status row, but no `pa`/`dc`/`#rd` analysis transaction followed before
  close.
- Conclusion: do not continue with `FORCELINES` or `HOLDRTS-DTR` as the next
  default. The next useful isolation test is `NOAUTOPRINT`, because it keeps the
  serial profile close to the best SIMPLE386 baseline while removing LPT watcher
  and print side effects.

LPT watcher durability fix after this test:

- `Watch-ArlLptCapture.ps1` now accepts `ParentStartTime` so it can detect when
  Windows reuses the DOSBox PID for a different process.
- The analyzer now skips hash failures on locked log files instead of failing
  the whole trace analysis.

Test rule:

- Start each launcher from a fresh DOSBox/IMPACT process.
- Do up to five burns or stop at the first `Please Run Sample` loop.
- Preserve/analyze the run before trying the next variable.
- Do not use `UARTDATA` for stability tests unless a short proof capture is
  explicitly needed.

Emulator profiles derived from this run:

- `profiles\impact-simple386-four-row-sequence.json` returns the three accepted
  rows, then the valid row that IMPACT rejected, and repeats it when IMPACT
  sends `?`.
- `profiles\impact-simple386-rejected-row-first.json` returns the rejected row
  as the first result. If IMPACT rejects it immediately, suspect value/range or
  row format. If it accepts it first but rejects it after three accepted rows,
  suspect accumulated IMPACT/session state.

## 2026-07-08/09 SIMPLE386 Matrix 01-05

Operator shortcuts were shortened under `C:\Users\Public\Desktop` to reduce
selection mistakes. The first five matrix tests produced:

- `01 NOAUTOPRINT - 6000 SIMPLE386`
  - Run: `C:\ARL\diagnostics\sample-analysis-20260708-225509`
  - Accepted first burn with `#em`, then rejected a complete checksum-valid
    second result row with repeated `?`.
  - Conclusion: LPT watcher/autoprint is not the primary trigger.
- `02 NO MOUSE.COM - 6000 SIMPLE386`
  - Run: `C:\ARL\diagnostics\sample-analysis-20260708-230028`
  - Rejected the first checksum-valid result row with repeated `?`.
  - Note: this disables only the DOS mouse driver load; DOSBox-X internal
    `INT 33h`/PS2/AUX mouse support remains active unless disabled separately.
- `03 NOUMB - 6000 SIMPLE386`
  - Run: `C:\ARL\diagnostics\sample-analysis-20260708-230247`
  - Rejected the first checksum-valid result row.
- `04 EMSBOARD - 6000 SIMPLE386`
  - Run: `C:\ARL\diagnostics\sample-analysis-20260708-230537`
  - Rejected the first checksum-valid result row.
- `05 EMM386 - 6000 SIMPLE386`
  - Run: `C:\ARL\diagnostics\sample-analysis-20260708-230916`
  - Rejected the first checksum-valid result row.

Current read:

- Do not spend more ARL burn time on `06-10` until a stronger variable is
  tested.
- The next high-signal test is `11 NOINT33 - 6000 SIMPLE386`, which disables
  `DOS\MOUSE.COM`, DOSBox-X `int33`, BIOS PS/2 mouse emulation, and keyboard
  AUX mouse emulation, with auto-print off for the test.

2026-07-09 rollback insight:

- After shortcuts `01-11`, the operator noted none of the active matrix
  profiles reproduced the earlier useful behavior.
- The best earlier run was not `SIMPLE386`; it was `ARL IMPACT+ CYCLES6000
  TRACE` with `core=normal`, `cputype=486`, `rxdelay=3000`, normal mouse,
  normal EMS/XMS/UMB, and auto-print enabled.
- Restore that as `00 BASELINE - 6000 486` before spending more burns on
  deeper compatibility variants.

2026-07-09 display adjustment:

- Generated configs now default to a larger 4:3 operator window:
  `windowresolution=1280x960`, `output=openglnb`, `aspect=true`,
  `scaler=none`.
- This is intended to improve RDP readability without changing IMPACT's DOS
  video mode.

2026-07-09 timing conclusion:

- `sample-analysis-20260708-173311` is the strongest mixed reference:
  7 accepted rows and 1 rejected row.
- Accepted timing: first RX avg/max `14.143/16 ms`, row duration avg/max
  `745.286/772 ms`, IMPACT response avg/max `6/7 ms`.
- Rejected timing: first RX `15 ms`, row duration `757 ms`, IMPACT response
  `5 ms`.
- This makes a simple "row arrived too late/incomplete" explanation unlikely.
  IMPACT had a complete checksum-valid row at nearly the same timing and still
  replied `?`.
- Current working hypotheses:
  - row content/range/alloy/curve acceptance;
  - accumulated IMPACT state after several burns;
  - emulator/DOS memory or parser state that does not exist on FreeDOS;
  - missing pre-result context that changes how IMPACT interprets `#rd`.

2026-07-09 emulator setup:

- Added `New-ArlEmulatorProfileFromTrace.ps1` to distill real result rows from
  `result-timing.csv` into safe localhost-only emulator profiles.
- Added `Start-ArlTraceRun.ps1 -StartEmulator` so emulator launchers start the
  TCP emulator before DOSBox-X opens the `nullmodem` connection.
- Created HP profiles:
  - `C:\ARL\DOSBox-X-ARL\profiles\impact-6000-good7-then-reject.json`
    from `sample-analysis-20260708-173311`; self-test OK, 10 rules.
  - `C:\ARL\DOSBox-X-ARL\profiles\impact-6000-rejectfirst-current.json`
    from `sample-analysis-20260708-232928`; self-test OK, 3 rules.
- Recreated public desktop shortcuts:
  - `90 EMU GOOD-THEN-REJECT`
  - `91 EMU REJECT-FIRST`
- Dry-run verified the emulator config uses
  `serial1 = nullmodem server:127.0.0.1 port:3460 transparent:1 rxdelay:1000`
  and does not open `COM5`.

2026-07-09 emulator prelude fix:

- `91 EMU REJECT-FIRST` initially hung in IMPACT's "Configuring ICS" phase.
- Cause: the emulator profile only knew result-read responses; IMPACT first
  sends ICS setup/status commands and waits for acknowledgements.
- Updated `New-ArlEmulatorProfileFromTrace.ps1 -IncludeProtocolPrelude` to
  replay trace-derived pre-`#rd` responses from `protocol-candidates.json`.
- Regenerated profiles on HP:
  - `impact-6000-good7-then-reject.json`: 15 rules, including one initial
    `0x7F` sync ignore rule, 4 `init-status` rules, 8 result rows, 1
    reject-loop rule, and 1 `#em` rule.
  - `impact-6000-rejectfirst-current.json`: 8 rules, including one initial
    `0x7F` sync ignore rule, 4 `init-status` rules, 1 rejected result row, 1
    reject-loop rule, and 1 `#em` rule.
- The prelude currently replays `sc`, `sw/st/ms`, `rs`, and the first
  `ns/pa/m1/cl/dc/m2/we` preparation burst. This should let IMPACT pass the
  configuration/status screens before emulator result tests.
- The first prelude attempt used generic `match:any` sequence rules and a stale
  emulator process was still listening on port `3460`. That caused new launches
  to create only `trace_open` entries without `listen/connect`. The launcher now
  stops stale `Start-ArlEmulator.ps1` PowerShell processes before starting a new
  emulator, and prelude rules now match concrete command patterns (`sc`, `#sw`,
  `#rs`, `ns`) instead of arbitrary bytes.
- A later live emulator run still stuck in "Configuring ICS" showed only
  repeated `0x7F` bytes every 10 seconds. Comparing against the real ARL trace
  showed the ARL sends `#` after the sync byte, and that `#` appears to unlock
  IMPACT so it sends `sc`. `Start-ArlEmulator.ps1` now handles a standalone
  `0x7F` immediately instead of waiting for the generic transaction-idle path,
  using the profile rule `impact-sync-7f-ready` with response `#`.
- After the sync fix, IMPACT sent `sc 2,0,1,0,1,0,0,0,0,0 134\r` but the
  emulator did not process it while IMPACT remained on the configuration
  screen. `Start-ArlEmulator.ps1` now also processes any buffered transaction
  immediately when it receives carriage return (`0x0D`), matching the ARL
  protocol's command terminator instead of depending only on idle timing.
- Cleaned IMPACT transient files after backing them up to
  `C:\ARL\diagnostics\impact-temp-backup-20260709-002351`. Files actually found
  and deleted were `telex.dat`, `telex.def`, and `report.x`; manifest includes
  hashes and paths.

2026-07-09 AUTOEXEC/CONFIG audit:

- Current `C:\ARL\IMPLUS\AUTOEXEC.BAT`:
  - sets `PATH=.;\;\LOCALE`;
  - runs EGA/codepage/keyboard setup;
  - runs `mode com2:4800,n,8,1`;
  - runs `mode lpt2:=com2:`;
  - has legacy `FILES=30` and `buffers=30` lines;
  - loads `mouse`;
  - changes to `C:\IMPLUS` and runs `implus`.
- Older `C:\ARL\IMPLUS\18_01_05\AUTOEXEC.BAT` is similar but simpler:
  `path c:\;c:\dos`, `mode com2:4800,n,8,1`, `mode lpt2:=com2:`, `doskey`,
  `mouse`, then `implus`.
- `IMP.BAT`/`IMPLUS.BAT` delete transient files such as `impact.dbf`,
  `telex.sav`, `temp.tmp`, `result.tmp`, `qafile.flg`, `qanofile.flg`,
  `spc.flg`, `telex.dat`, and `telex.def`; then they run `impact 1 2` on
  first entry and `impact 1` on internal cycles.
- Hypothesis: stale transient files and IMPACT's own `Temp Opt`/`Temp Choice`
  in `IMPACT.INI` can explain state that persists across an IMPACT restart
  inside the same DOSBox-mounted directory. Do not delete production files
  blindly; preserve before cleanup tests.
- Hypothesis for later, separate launcher: a "legacy DOS startup" profile could
  set DOSBox-X `[config] files=30` and emulate the old startup more closely.
  Do not add `mode com2` to the main baseline until we decide whether IMPACT is
  actually using COM1 or COM2 under DOSBox-X.

Next emulator interpretation:

- Run `91 EMU REJECT-FIRST` first when the ARL is not needed. If IMPACT rejects
  that row as the first result, content/format/range becomes likely.
- Then run `90 EMU GOOD-THEN-REJECT`. If IMPACT accepts several emulated rows
  and then rejects the same transition, accumulated IMPACT state becomes likely.
- If emulator behavior does not match real ARL behavior, improve the emulator
  with more pre-`#rd` context from traces before touching real COM settings.
