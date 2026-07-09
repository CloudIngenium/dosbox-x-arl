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

Important lab build:

- HP uses `C:\ARL\DOSBox-X-ARL\dosbox-x-arl-96994b1.exe` for the current trace
  tests.
- This build moved UART data-register tracing to the code paths IMPACT actually
  uses, so `uartdata` can prove guest `THR/RHR` access.

Recent commits in the fork:

- `fa2f6e8` - Add ARL safe serial trace launcher.
- `55a49f7` - Fix ARL trace launchers parameter splatting.
- `f7c0d5e` - Fix ARL LPT watcher argument quoting.
- `6948cc7` - Document ARL safe serial trace regression.
- `c3b2ebc` - Add ARL RX4000 tuning launcher.
- `fc3851b` - Add ARL UARTDATA diagnostic launcher.
- `1cc500d` - Validate ARL UARTDATA launcher in CI.
- `85fcc41` - Cap ARL serial trace size.

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

Recommended test order:

1. Close the stuck DOSBox-X window to stop the `?` loop.
2. Restart/reinitialize the ARL/ICS side if the lab procedure allows it.
3. Run `CYCLES5000 TRACE` on the same SS-413BD workflow and try five burns.
4. If 5000 fails, run `CYCLES7000 TRACE` under the same workflow.
5. Only after those two tests, revisit `rxdelay` changes.

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
  - UARTDATA only if 6000 fails again.

Updated recommended test order:

1. After ARL service, launch `ARL IMPACT+ CYCLES6000 TRACE`.
2. Use a fresh DOSBox/IMPACT session.
3. Run one reference burn.
4. If it passes, run up to four burns maximum, then close/reopen IMPACT before
   attempting more.
5. If it fails with `?`, capture with UARTDATA at 6000/3000; do not keep
   moving cycles blindly.
