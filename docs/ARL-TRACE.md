# DOSBox-X ARL Toolkit

This fork keeps the ARL 3460 work as a small observability patch stack on top of
upstream DOSBox-X. The current base is the normal upstream release
`DOSBox-X 2026.07.02` at tag `dosbox-x-v2026.07.02`.

Scope is intentionally conservative: trace, status, manual marks, rotation,
offline analysis, and a safe localhost-only emulator harness. The emulator is a
bench tool for IMPACT/TICS state-machine testing; it does not open COM5 and it
must not be treated as a replacement for the real ARL until protocol bytes are
confirmed from lab traces. Do not add manual ICS command senders, synchronize, or
reset helpers.

For the chronological lab handoff log, including tests, hypotheses, failed
paths, trace evidence, and next steps, read
[`ARL-LAB-HISTORY-2026-07.md`](./ARL-LAB-HISTORY-2026-07.md).

## Current Lab Build

As of 2026-07-08, the HP bench PC (`LABORATORIO-ARL`) is using ARL trace build
`96994b1`:

- `C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe`
- `C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe`
- SHA256:
  `499A1F9D992F28CD022429F6F2CCAAFA0F03D898F68B606B7659CA29819571DA`
- previous backup:
  `C:\ARL\DOSBox-X-ARL\dosbox-x-arl-b1f648f.exe`

The public desktop shortcut `ARL IMPACT+ UARTDATA TRACE` launches
`Launch-ArlImpactUartDataTrace.ps1`, which uses `arltracelevel:uartdata`,
`cycles=fixed 8000`, `rxdelay:3000`, and COM5. Use it only for short,
operator-attended diagnostic burns because it records guest UART `THR/RHR`
activity in addition to host TX/RX bytes.

After the 2026-07-08 successful-first-burn / stuck-second-burn evidence, keep
that shortcut for deep UART-consumption proof only. The normal retry path should
use the side-by-side `ARL IMPACT+ STABILITY TRACE` launcher, which calls
`Launch-ArlImpactStabilityTrace.ps1` with `arltracelevel:basic`,
`cycles=fixed 8000`, `rxdelay:3000`, `arltracehangms:30000`, and LPT
auto-print enabled. This keeps TX/RX protocol evidence while reducing trace
overhead.

For the next conservative serial retry, use `ARL IMPACT+ SAFE SERIAL TRACE`.
It keeps the same low-overhead trace and `cycles=fixed 8000`, but raises
`rxdelay` to `10000`, the highest value accepted by DOSBox-X directserial. This
tests whether IMPACT needs a longer grace window after post-spark result bursts
before DOSBox-X forces receive/overrun behavior.

The 2026-07-08 `SAFE SERIAL TRACE` run
`C:\ARL\diagnostics\sample-analysis-20260708-154724` did not improve the
analysis path. IMPACT showed no accepted readings, while the trace showed
`TX bytes: 788`, `RX bytes: 10694`, no RX framing/parity/overrun errors, and a
single `#rd 246` result transaction followed by 104 `?` polls. The ARL repeated
a parseable numeric result row, but IMPACT never sent `#em`. Treat
`rxdelay:10000` as worse than the current `rxdelay:3000` stability profile
unless later evidence contradicts this.

The next tuning step is `ARL IMPACT+ RX4000 TRACE`, which keeps the same
`cycles=fixed 8000` and low-overhead trace but raises `rxdelay` only slightly
from 3000 to 4000. This tests whether a modest grace window helps without the
long blocked-UART behavior observed at 10000.

After the UARTDATA evidence showed that valid rows can be received and read but
still rejected by IMPACT, the next lab matrix should hold `rxdelay:3000`
constant and vary only CPU timing. Use one burn per DOSBox launch:

- `Launch-ArlImpactStabilityTrace.ps1`: `cycles=fixed 8000`, `rxdelay:3000`
- `Launch-ArlImpactCycles6000Trace.ps1`: `cycles=fixed 6000`, `rxdelay:3000`
- `Launch-ArlImpactCycles10000Trace.ps1`: `cycles=fixed 10000`, `rxdelay:3000`

After `3500` accepted only one burn and `4000` failed status reads, do not keep
walking cycles downward. The next useful no-rebuild tests keep the best observed
transport setting and change the emulated DOS machine profile:

- `Launch-ArlImpactCycles6000SimpleTrace.ps1`: `core=simple`, `cputype=486`,
  `cycles=fixed 6000`, `rxdelay:3000`
- `Launch-ArlImpactCycles6000Cpu386Trace.ps1`: `core=normal`, `cputype=386`,
  `cycles=fixed 6000`, `rxdelay:3000`
- `Launch-ArlImpactCycles6000Simple386Trace.ps1`: `core=simple`,
  `cputype=386`, `cycles=fixed 6000`, `rxdelay:3000`

Memory-layout variants are also available because IMPACT may change parser or
buffer paths when EMS/XMS/UMB are present:

- `Launch-ArlImpactCycles6000NoEmsTrace.ps1`: `memsize=16`, `xms=true`,
  `ems=false`, `umb=true`
- `Launch-ArlImpactCycles6000NoUmbTrace.ps1`: `memsize=16`, `xms=true`,
  `ems=true`, `umb=false`
- `Launch-ArlImpactCycles6000NoMouseTrace.ps1`: `memsize=16`, `xms=true`,
  `ems=true`, `umb=true`, does not load `DOS\MOUSE.COM`
- `Launch-ArlImpactCycles6000LowMemTrace.ps1`: `memsize=4`, `xms=true`,
  `ems=false`, `umb=true`
- `Launch-ArlImpactCycles6000ConventionalTrace.ps1`: `memsize=4`,
  `xms=false`, `ems=false`, `umb=false`

Use `NOEMS`, `NOUMB`, then `NOMOUSE` before `LOWMEM` or `CONVENTIONAL`; they
change less while testing the most suspicious old-DOS memory variables.

`UARTDATA` launchers are diagnostic-only. A failed `CYCLES6000 UARTDATA TRACE`
run does not prove that `NOEMS` failed, and it should not be used as a stability
setting because the UART register trace volume can perturb timing.

`CYCLES6000 SIMPLE TRACE` produced a successful first analysis and then two
completed analyses were reported by the operator. Its run metadata confirmed
`core=simple`, `cputype=486`, `cycles=fixed 6000`, and `rxdelay:3000`.

The same run proved LPT capture worked: `LPTCAP.PRN` contained 5242 bytes. A
watcher-launch bug was fixed after this run: `Start-ArlTraceRun.ps1` now writes
named hashtable splatting for `Watch-ArlLptCapture.ps1` instead of positional
array splatting. If a RAW print job reaches the `EPSON LX-350` queue but does
not physically print, troubleshoot Windows/USB/printer state rather than IMPACT
LPT capture.

Before each burn, close DOSBox-X, confirm no `dosbox` process remains, and have
the operator reinitialize ARL/ICS. A passing run is a result row followed by
`#em`, `INTERFAC.DAT` update, and LPT capture/print job if IMPACT reaches print.

Later 2026-07-08 runs with both `rxdelay:3000` and `rxdelay:4000` reproduced the
same post-result loop: IMPACT sent `#rd 246`, the ARL returned repeated numeric
result rows at 2400 baud, and IMPACT kept sending `?` without sending `#em`.
The trailing result-row checksum bytes matched the modulo-256 checksum rule
used by commands such as `#rd 246` and `#em 242`, so the repeated rows were not
obviously corrupt at the ASCII protocol level. The next controlled diagnostic
burn should therefore use `ARL IMPACT+ UARTDATA TRACE` to prove whether IMPACT
is consuming the UART receive register cleanly or whether emulated UART/FIFO
state diverges before IMPACT accepts the packet.

If DOSBox-X is closed while this loop is active, the ARL/ICS side can remain in
the result-read state. A subsequent IMPACT launch may then send status commands
at 9600 baud while the instrument/interface is still effectively in the
post-result 2400-baud conversation, producing RX framing/parity errors and a
new hang at "Reading status channels". Clear/reinitialize the ARL/ICS state
before treating that later status-read hang as a separate failure.

Build `96994b1` moved THR/RHR `uartdata` tracing to `CSerial::Write_THR()` and
`CSerial::Read_RHR()`. That matters because IMPACT can use BIOS/INT14 paths that
do not necessarily pass through the I/O-port wrappers where earlier builds
logged UART data-register access.

Do not use `10.30.1.6` for this lab PC; that address was observed to be a
different Linux host. Use `LABORATORIO-ARL` / `10.5.18.101` for SSH access when
reachable.

Remote HP operations are documented in
[`ARL-HP-REMOTE-OPS.md`](./ARL-HP-REMOTE-OPS.md). Use `svc-claude` with
`~/.ssh/svc-claude`, place user-facing launchers in `C:\Users\Public\Desktop`,
and prefer uploading `.ps1` files over inline PowerShell in SSH commands.

## Branches

- `upstream-master` tracks `joncampbell123/dosbox-x` `master` and is treated as
  read-only.
- `arl-trace` is the active CloudIngenium branch.
- ARL releases use tags like `arltrace-v2026.07.02-1`.

Enable conflict reuse in local maintenance clones:

```bash
git config rerere.enabled true
```

## Trace v2 Options

`directserial` accepts these ARL observability options:

```ini
serial1 = directserial realport:COM5 rxdelay:1000 arltracelevel:basic arltracesession:impact arltracehangms:15000 arltrace:C:\ARL\diagnostics\serial.ndjson
```

- `arltrace:<file>` appends one NDJSON event per line. Omitting it preserves
  upstream `directserial` behavior.
- `arltracelevel:basic|uartdata|uart|full` controls detail. `basic` records
  TX/RX, config, modem lines, and errors. `uartdata` adds only guest UART data
  register access (`THR` writes and `RHR` reads), which is the preferred mode
  for short post-spark IMPACT diagnosis. `uart` adds every guest UART register
  read/write. `full` adds host serial DCB, timeout, and modem-control snapshots.
  Use `basic` for normal lab runs. Use `uartdata` for controlled diagnostic
  burns. Use `uart` or `full` only for very short windows because a disconnected
  or waiting DOS program can poll UART registers fast enough to create multi-GB
  traces.
- `arltracesession:<label>` labels the run, for example `impact`, `tics`,
  `status-only`, or `sample-analysis`.
- `arltracehangms:<ms>` emits `hang_snapshot` when no relevant TX/RX occurs for
  the configured interval.
- `arltracemaxmb:<mb>` closes the trace after the file reaches the configured
  size limit. `Start-ArlTraceRun.ps1` uses `64` MB by default so a stuck polling
  loop preserves evidence without filling the disk. Use `0` only for short,
  supervised captures where an unlimited trace is intentional.
- `arlresultobserve:1` arms only after IMPACT transmits `#rd`, reconstructs the
  returned row through `CR`, validates its 8-bit additive checksum, classifies
  it as `low_000_099` or `high_100_255`, and records IMPACT's later `#em` or
  `?`. It is observe-only and never changes RX bytes.
- `arlresultretrylow:1` implies observation and enables a reactive physical
  retry. The first result is always delivered unchanged. Only after IMPACT
  transmits `?` is the repeated row buffered and respelled with decimal-safe
  ASCII formatting targeting confirmed checksums `099`, `089`, `055`, `023`,
  then `000`. Every original/presented pair is traced with
  `decimal_equal:true`; initialization, status and command frames are untouched.
- `arlforcects:1`, `arlforcedsr:1`, and `arlforcedcd:1` force the
  guest-visible modem input lines high. Use only for compatibility tests after
  installing a build that contains these options.
- `arlholdrts:1` and `arlholddtr:1` keep the host RTS/DTR output lines high
  toward the ARL/ICS while tracing the effective line state.

The physical five-burn reference captured on 2026-07-10 is stored in
`contrib/arl/fixtures/accepted-five-burns-20260710.json`. IMPACT accepted
checksums `099`, `045`, `045`, `054`, and `024` with zero UART errors. This
supports low-checksum acceptance but does not by itself prove that every
checksum above `099` is rejected.

Trace v2 includes:

- wall-clock epoch milliseconds, DOSBox elapsed milliseconds, and PIC time
- guest COM number, real host port, session label, and trace level
- TX and RX bytes as decimal, hex, and printable ASCII
- baud rate, data bits, parity, and stop bits requested by the DOS program
- RX error bits for break, framing, parity, and overrun
- RTS, DTR, CTS, DSR, DCD, RI, and break state
- guest UART data-register access for THR/RHR in `uartdata`
- guest UART register access for THR/RHR, IER, ISR/FCR, LCR, MCR, LSR, MSR, SPR
  in `uart` and `full`
- FIFO usage, IRQ state, `rx_state`, `rx_retry`, and error counters
- Windows host DCB, timeouts, flow-control flags, and modem status in `full`

## SIMPLE386 Reject Matrix

The current best evidence run is
`C:\ARL\diagnostics\sample-analysis-20260708-205041\snapshot-20260708-205610`.
It used `core=simple`, `cputype=386`, `cycles=fixed 6000`, `rxdelay:3000`,
accepted three result rows, then rejected a fourth complete checksum-valid row
with `?` instead of `#em`.

Use this no-rebuild order next, one variable per fresh DOSBox/IMPACT session:

1. `01 NOAUTOPRINT - 6000 SIMPLE386`
2. `02 NO MOUSE.COM - 6000 SIMPLE386`
3. `03 NOUMB - 6000 SIMPLE386`
4. `04 EMSBOARD - 6000 SIMPLE386`
5. `05 EMM386 - 6000 SIMPLE386`

Observed on 2026-07-08/09:

- `01` accepted the first burn, then rejected the second checksum-valid row.
- `02` through `05` each rejected the first checksum-valid result row.
- `02` only disables `DOS\MOUSE.COM`; DOSBox-X still exposes its internal
  `INT 33h`/PS2/AUX mouse path unless the generated config disables it.

Next preferred isolation test:

- `00 BASELINE - 6000 486`
  - restores the best-known good profile from
    `sample-analysis-20260708-173311`
  - `core=normal`, `cputype=486`, `cycles=fixed 6000`, `rxdelay:3000`
  - uses normal mouse/EMS/XMS/UMB, auto-print, and old default video scaling
- `11 NOINT33 - 6000 SIMPLE386`
  - `core=simple`, `cputype=386`, `cycles=fixed 6000`, `rxdelay:3000`
  - disables `DOS\MOUSE.COM`, `int33`, `biosps2`, and keyboard `aux`
  - disables auto-print to remove LPT watcher side effects for this test

## Operator Window Size

Generated ARL configs use a larger operator window by default:

- `[sdl] windowresolution = 1280x960`
- `[sdl] output = openglnb`
- `[render] aspect = true`
- `[render] scaler = none`

This scales DOSBox-X output for readability while keeping the DOS video mode
seen by IMPACT unchanged. If the HP/RDP display is too small, lower
`WindowResolution` in the launcher call, for example `1024x768`.

If those do not move the failure, use the deeper DOS compatibility launchers:

- `ARL IMPACT+ CYCLES6000 SIMPLE386 ZEROEMS TRACE`
- `ARL IMPACT+ CYCLES6000 SIMPLE386 ZEROXMS TRACE`
- `ARL IMPACT+ CYCLES6000 SIMPLE386 MCBCOMPAT TRACE`
- `ARL IMPACT+ CYCLES6000 SIMPLE386 NOSHARE TRACE`
- `ARL IMPACT+ CYCLES6000 SIMPLE386 UNMASKDISKIO TRACE`

The following require a build with modem-line options. They are installed on the
HP as of build `9663306`, but the first lab result did not make either one a
better default:

- `ARL IMPACT+ CYCLES6000 SIMPLE386 FORCELINES TRACE`
- `ARL IMPACT+ CYCLES6000 SIMPLE386 HOLDRTS-DTR TRACE`

Observed 2026-07-08:

- `FORCELINES` received a checksum-valid result row and then IMPACT sent `?`
  repeatedly instead of `#em`.
- `HOLDRTS-DTR` did not produce a useful analysis/result-read transaction.
- Continue with `NOAUTOPRINT`, then the DOS memory-layout launchers, before
  returning to modem-line forcing.

Emulator profiles derived from the run:

- `profiles\impact-simple386-four-row-sequence.json`
- `profiles\impact-simple386-rejected-row-first.json`

## ARLTRACE.COM

The fork adds a safe DOS internal command:

```dos
ARLTRACE STATUS
ARLTRACE MARK before-spark
ARLTRACE ROTATE
```

- `STATUS` prints active trace path, last TX/RX, modem lines, retry state, and
  last error.
- `MARK <text>` writes a manual `mark` event to the active trace.
- `ROTATE` closes the current trace and opens a timestamped NDJSON file.

There are no `SEND`, `RESET`, `SYNC`, or direct ICS commands.

## Lab Runs

Install side-by-side:

```powershell
New-Item -ItemType Directory -Force C:\ARL\DOSBox-X-ARL
Copy-Item .\DOSBox-X-ARL\dosbox-x-arl.exe C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe
Copy-Item .\DOSBox-X-ARL\contrib\arl\* C:\ARL\DOSBox-X-ARL\ -Recurse -Force
New-Item -ItemType Directory -Force C:\ARL\diagnostics
```

Preferred launcher:

```powershell
C:\ARL\DOSBox-X-ARL\Start-ArlTraceRun.ps1 -Session impact
C:\ARL\DOSBox-X-ARL\Start-ArlTraceRun.ps1 -Session tics
C:\ARL\DOSBox-X-ARL\Start-ArlTraceRun.ps1 -Session sample-analysis
C:\ARL\DOSBox-X-ARL\Launch-ArlImpactStabilityTrace.ps1
C:\ARL\DOSBox-X-ARL\Launch-ArlImpactCycles6000Trace.ps1
C:\ARL\DOSBox-X-ARL\Launch-ArlImpactCycles10000Trace.ps1
```

Each run creates `C:\ARL\diagnostics\<session>-<timestamp>\` with:

- generated DOSBox-X config
- `serial.ndjson`
- `dosbox.log`
- `run-metadata.json`
- `calibration-access.ndjson`, containing successful guest opens of `.CAL` and
  `.REG` files with timestamps, DOS paths, and access modes
- `LPTCAP.PRN` if IMPACT prints to LPT1
- `print-jobs\*.prn` plus manifests/logs when LPT auto-print is enabled
- copied `INTERFAC.DAT.after` when `-Wait` is used and the file exists

`calibration-access.ndjson` is evidence for resolving the actual IMPACT curve.
Do not infer a curve from the alloy label alone. Downstream importers may assign
the curve only when the file-access timeline identifies one unambiguous `.CAL`
file for the analysis group; ambiguous runs must retain a null curve. The trace
records names and access events only and never reads or changes calibration
contents.

Preserve important runs before cleanup or repeated retries:

```powershell
C:\ARL\DOSBox-X-ARL\Preserve-ArlTraceRun.ps1 `
  -RunPath C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS `
  -Label first-good-second-stuck
```

The preserved copy includes a manifest and `SHA256SUMS.txt` under
`C:\ARL\diagnostics\preserved\`.

The lab profile intentionally captures LPT1 to `LPTCAP.PRN` instead of printing
directly:

```ini
parallel1 = file append:C:\ARL\diagnostics\<run>\LPTCAP.PRN timeout:2000
```

This preserves the raw IMPACT report. To print a captured report after
confirming it is the desired run:

```powershell
C:\ARL\DOSBox-X-ARL\Print-ArlLptCapture.ps1 `
  -RunPath C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS

C:\ARL\DOSBox-X-ARL\Print-ArlLptCapture.ps1 `
  -RunPath C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS `
  -PrinterName "EPSON LX-350" `
  -Send
```

The first command is a dry run and shows a preview. The second sends the raw
captured bytes to the installed Windows printer. On 2026-07-08 the HP bench PC
had `EPSON LX-350` installed on `USB001`.

When `Start-ArlTraceRun.ps1` is launched with `-AutoPrintLpt`, it starts
`Watch-ArlLptCapture.ps1` alongside DOSBox-X. The watcher keeps `LPTCAP.PRN` as
the full raw capture, copies each stable append window to `print-jobs\*.prn`,
writes JSON/SHA256 metadata for later processing, and sends that job to
`Print-ArlLptCapture.ps1 -Send`. Auto-print appends a form-feed byte only to
the bytes sent to the Epson so matrix-printer pages eject immediately; the
captured `LPTCAP.PRN` and saved `print-jobs\*.prn` remain unchanged.

This per-append printing is diagnostic-only because IMPACT can emit a detailed
stage block after each individual burn. The physical operator launcher keeps it
disabled by default and still captures the complete `LPTCAP.PRN`. Use
`Launch-ArlImpactPhysicalReference.ps1 -LegacyDebugPrintLpt` only for a
supervised debugging session. Production printing belongs to Chispa.Agent,
which creates one saved-group report after the 2-5 burn workflow is complete.

Keep the current lab serial settings while diagnosing:

- ARL cable on `COM5`
- WCH FIFO disabled or minimized in Device Manager
- `cycles = fixed 8000` as baseline, then 6000 and 10000 only as single-variable tests
- `rxdelay:3000` for the current matrix
- `arltracelevel:basic` for normal burns; `uartdata` only for short proof captures

The pass/fail gate is post-spark completion: IMPACT must exit the busy state and
rewrite `C:\ARL\IMPLUS\INTERFAC.DAT`.

### 2026-07-08 Post-Spark Finding

Run `C:\ARL\diagnostics\sample-analysis-20260708-131347\serial.ndjson` captured
the symptom where "Please Run Sample" stopped blinking but IMPACT did not load
analysis values on screen.

Key facts from that trace:

- ARL/Windows/DOSBox received post-spark result bytes.
- RX continued with `rx_error_bits=0`.
- `INTERFAC.DAT` did not update.
- The ARL repeatedly returned numeric result lines after `we 252` and `#rd 246`.
- Earlier `uartdata` instrumentation only saw guest RHR/THR activity near the
  initial status read, so it could not prove whether IMPACT consumed the later
  post-spark bytes.

The next controlled burn must use build `96994b1` or later. If that build shows
RX continuing for several seconds after the last guest `RHR` read, classify the
failure as "ARL data reaches DOSBox, but IMPACT stops consuming it." If it shows
guest `RHR` reads consuming the result bytes but no screen/`INTERFAC.DAT` update,
classify the failure as an IMPACT result parsing/state-machine problem rather
than a Windows serial receive problem.

Run `C:\ARL\diagnostics\sample-analysis-20260708-135100\serial.ndjson` captured
a stronger signal with build `96994b1`:

- IMPACT completed the first burn and displayed analysis values.
- During the second burn, DOSBox-X kept receiving ARL bytes and IMPACT kept
  reading guest UART `RHR`; `RX bytes` and `Guest RHR reads` matched in the
  analyzer snapshot.
- The analyzer saw no framing, parity, overrun, or write error.
- The second post-result phase entered a repeated `#rd 246` / `?` polling
  pattern: IMPACT sent `#rd 246` and many `?` bytes while the ARL repeatedly
  returned the same numeric result row.

That pattern is now classified as `post_result_poll_loop`. Treat it as evidence
that the serial receive path is alive. The next diagnosis target is why IMPACT
does not accept the repeated result/status sequence after a prior successful
burn: missing terminator, expected ACK/status transition, stale run state, or a
checksum/result-format mismatch.

Run `C:\ARL\diagnostics\sample-analysis-20260708-145951\serial.ndjson` captured
the best mixed evidence so far: three result transactions completed and the next
result entered the post-result poll loop. `Compare-ArlResultTransactions.ps1`
showed that the good `#rd` transactions were followed by `#em`, while the loop
candidate had 136 `?` polls and no `#em`. The ARL kept sending a parseable
numeric result row, so this is not a silent-instrument or Windows RX-loss
failure.

The same run also captured `LPTCAP.PRN` with a complete ASCII IMPACT report.
The HP bench PC validated dry-run printing to `EPSON LX-350` on `USB001`;
`Watch-ArlLptCapture.ps1` now preserves each stable append as
`print-jobs\*.prn` plus JSON/SHA256 metadata before optionally sending the raw
bytes to the printer. That real report had no form-feed byte, so the toolkit
adds form-feed on send by default while preserving the raw capture on disk.

## Safe ARL Emulator

The V1 emulator is external to DOSBox-X. It listens on localhost TCP and DOSBox-X
connects through `nullmodem`, so no real Windows serial port is opened.

Start the emulator first:

```powershell
C:\ARL\DOSBox-X-ARL\Start-ArlEmulator.ps1 `
  -Mode happy-path `
  -ProfilePath C:\ARL\DOSBox-X-ARL\profiles\arl3460-baseline.json `
  -LogPath C:\ARL\diagnostics\impact-emulator\emulator.ndjson
```

Then start IMPACT or TICS against the emulator:

```powershell
C:\ARL\DOSBox-X-ARL\Start-ArlTraceRun.ps1 -Session impact-emulator
C:\ARL\DOSBox-X-ARL\Start-ArlTraceRun.ps1 -Session tics-emulator
```

The generated emulator config uses:

```ini
serial1 = nullmodem server:127.0.0.1 port:3460 transparent:1 rxdelay:1000
```

Static configs are also provided:

- `dosbox-impact-emulator.conf`
- `dosbox-tics-emulator.conf`

Emulator modes:

- `happy-path`: responds from the profile.
- `silent-after-spark`: suppresses `analysis-result` responses.
- `delayed-result`: delays `analysis-result` responses.
- `line-drop`: closes the TCP nullmodem connection at `analysis-result`.
- `bad-response`: returns NAK-style bad bytes from the profile.

The default `profiles\arl3460-baseline.json` is synthetic. Replace its
responses only with bytes confirmed by real `serial.ndjson` traces.

Trace-derived profiles are now generated with:

```powershell
C:\ARL\DOSBox-X-ARL\New-ArlEmulatorProfileFromTrace.ps1 `
  -RunPath C:\ARL\diagnostics\sample-analysis-20260708-173311 `
  -OutPath C:\ARL\DOSBox-X-ARL\profiles\impact-6000-good7-then-reject.json `
  -Name impact-6000-good7-then-reject `
  -Mode sequence `
  -LineEnding CR
```

Current HP profiles:

- `profiles\impact-6000-good7-then-reject.json`: seven accepted result rows
  followed by the checksum-valid row that IMPACT rejected with `?`.
- `profiles\impact-6000-rejectfirst-current.json`: the current baseline
  reject row as the first emulator result.
- Both profiles include a trace-derived protocol prelude before the result
  rules: `sc`, `sw`, `st`, `rs`, and the first `ns/pa/m1/cl/dc/m2/we`
  preparation burst. This is required because IMPACT must pass ICS
  configuration/status before it ever asks for `#rd`.
- Profiles also include an initial `0x7F` sync rule that responds with `#`.
  `Start-ArlEmulator.ps1` handles that standalone sync byte immediately, because
  IMPACT otherwise repeats `0x7F` every 10 seconds and never sends `sc`. If an
  old emulator is still listening on port `3460`, the launcher stops it before
  starting the next emulated run.
- The emulator also processes buffered input immediately on command terminator
  `CR` (`0x0D`), because IMPACT can wait on the next response without leaving
  enough idle time for a timer-only transaction splitter.

Operator emulator shortcuts:

- `90 EMU GOOD-THEN-REJECT`: starts the localhost emulator automatically and
  runs IMPACT through DOSBox-X `nullmodem`.
- `91 EMU REJECT-FIRST`: same transport, but returns the rejected row first.

Both shortcuts are safe for hardware: they never open `COM5`; generated configs
must show `serial1 = nullmodem server:127.0.0.1 port:3460 ...`.

Use these tests to distinguish row content from accumulated IMPACT state:

- If `91 EMU REJECT-FIRST` is rejected immediately, suspect row content,
  format, checksum interpretation, range checks, or alloy/curve-specific
  acceptance logic.
- If `91 EMU REJECT-FIRST` is accepted but `90 EMU GOOD-THEN-REJECT` fails
  later, suspect accumulated IMPACT session state, memory/layout, or result
  counter state.
- If both emulator profiles behave differently from the real ARL trace, suspect
  unmodeled status/control-line/timing context before `#rd`.

## TICS Diagnosis

Use TICS separately from IMPACT to validate the ACS/ICS link. Close IMPACT before
running TICS and keep the instrument operator present.

TICS expects a few legacy filenames and folders to exist inside the mounted
IMPLUS tree:

- DOS path `C:\TICS\PROC` maps to Windows path `C:\ARL\IMPLUS\TICS\PROC`.
- `TICS.EXE` looks for `DBTICS.DBI`, `DBTICS.TXT`, and `DBTICS.HLP`.
- The ARL install may only include `DBTICSOE.*`; `Start-ArlTraceRun.ps1`
  creates `DBTICS.*` aliases from those files before launching TICS.

Start with communication parameters and passive/read-only checks:

- communication statistics
- `TL` link test
- `VE` ICS version
- `SI` and `RS` status reads

Observed TICS command database notes:

- Main menu option 3 is single-command mode.
- Main menu option 4 shows communication statistics: characters sent, ICS
  commands sent, ACK, NAK, timeout, and alarms.
- Main menu option 5 sends `BREAK DEL DEL` to synchronize/reset ICS. Avoid it
  during passive diagnostics.
- Main menu option 7 sets communication parameters before ICS jobs.
- `TL` is "Test ACS/ICS link" and accepts an alphanumeric text string up to 16
  characters.
- `VE` is "Get ICS release version"; ICS identity code is `0`.
- `RS` is "Read status channels"; status channel is `0..14`, type is `0..1`.
- `SI` is "Read a status channel"; status channel is `0..14`, result type is
  `0..1`.

Save TICS screenshots/logs plus the ARL trace under:

```text
C:\ARL\diagnostics\tics-<timestamp>\
```

Do not use TICS synchronize or reset commands unless a controlled diagnostic
step explicitly calls for them.

## Offline Analysis

Run the analyzer after each diagnostic session:

```powershell
C:\ARL\DOSBox-X-ARL\Analyze-ArlTrace.ps1 -TracePath C:\ARL\diagnostics\impact-20260707-123000\serial.ndjson
```

Or analyze the newest trace without typing the timestamped folder:

```powershell
C:\ARL\DOSBox-X-ARL\contrib\arl\Analyze-LatestArlTrace.ps1 -Session sample-analysis
```

It writes:

- `summary.md`
- `timeline.csv`
- `suspect.json`
- `protocol-candidates.md`
- `protocol-candidates.json`

Automatic classifications include:

- `arl_silent_after_tx`
- `rx_received_but_guest_did_not_read`
- `rx_continues_after_guest_rhr_reads_stop`
- `fifo_or_uart_error`
- `modem_line_drop_or_low` for CTS/DSR lows that coincide with a terminal
  `hang_snapshot` or write failure. DCD lows are still recorded in
  `suspect.json` because many lab cables do not assert DCD and it is noisy as a
  standalone root-cause signal.
- `baud_or_parity_rejected`
- `write_failed`
- `hang_without_clear_serial_fault`

`protocol-candidates.*` groups TX/RX bytes into candidate transactions using a
configurable idle gap. Use it to populate emulator profile rules after comparing
IMPACT, TICS, and known-good native FreeDOS captures.

For post-spark diagnosis, check these fields in `suspect.json` and `summary.md`:

- `last_rx_after_last_rhr_ms`
- `last_rx_after_last_uart_ms`
- `last_uart_rhr_read`
- `last_uart_thr_write`
- `post_result_poll_loop`

Large positive deltas mean bytes are still arriving from the host side after the
guest stopped reading the UART data register. With build `96994b1` or later,
that is stronger evidence than earlier builds because THR/RHR logging is emitted
inside the common serial register methods.

`post_result_poll_loop` means IMPACT sent `#rd` followed by many `?` bytes and
the ARL repeatedly returned the same numeric result row. This points away from
Windows serial loss and toward IMPACT/ARL post-result state or protocol
acceptance.

Use `Compare-ArlResultTransactions.ps1` to compare successful `#rd` result
transactions against the first loop:

```powershell
C:\ARL\DOSBox-X-ARL\Compare-ArlResultTransactions.ps1 `
  -RunPath C:\ARL\diagnostics\sample-analysis-YYYYMMDD-HHMMSS
```

The comparison highlights whether a good transaction included `#em`, `pa`, or
`we` transitions that are absent in the loop candidate.

## Update Workflow

For a new upstream release:

```bash
git fetch upstream --tags --prune
git switch arl-trace
git rebase dosbox-x-vYYYY.MM.DD
git format-patch dosbox-x-vYYYY.MM.DD..HEAD -o arl-patches
```

Review manually if upstream changed:

- `src/hardware/serialport/directserial.cpp`
- `src/hardware/serialport/directserial.h`
- `src/hardware/serialport/serialport.cpp`
- `src/hardware/serialport/libserial.cpp`
- `src/hardware/serialport/libserial.h`
- `src/dos/dos_programs.cpp`
- `src/dosbox.cpp`
- `dosbox-x.reference.conf`
- `dosbox-x.reference.full.conf`

Then build Windows x64, smoke-test `directserial` with and without `arltrace`,
and tag:

```bash
git tag -a arltrace-vYYYY.MM.DD-N -m "ARL trace build YYYY.MM.DD-N"
```

## CI Artifact

### Finalized directserial evidence

Directserial launchers start `Finalize-ArlDirectSerialRun.ps1` in the
background. It waits for the exact DOSBox process instance to exit, snapshots
final legacy artifacts, and atomically writes `directserial-finalized.json`.
Chispa Agent ignores a run until this marker exists, so an open trace is never
ingested. The finalizer does not open the serial port and does not alter trace
or result bytes.

### Checksum decision corpus

`contrib/arl/fixtures/checksum-decision-corpus.json` is the byte-exact decision
corpus. Every replayable row has a real-trace provenance, 15 numeric fields, a
recomputed additive checksum, and the observed IMPACT reply. Checksums mentioned
in lab notes without a recovered row remain under `reported_only` and are
explicitly forbidden from replay.

`Validate-ArlChecksumCorpus.mjs` enforces those invariants. The Windows artifact
workflow also runs `Run-ArlEmulatorOfflineMatrix.mjs 50`, which sends 50 result
requests over localhost TCP, compares every returned byte, replays the recorded
`#em`/`?` decisions, and verifies that the profile contains no `COM`,
`directserial`, or `realport` reference. This is a transport/emulator integrity
gate; a synthetic client does not prove how IMPACT itself will classify a new
row.

### Physical return launchers

The operator desktop exposes three physical paths with the
same timing and display settings:

- `00 DIRECTSERIAL BYPASS`: known recovery path with no result observer.
- `01 OBSERVE ONLY`: adds `arlresultobserve:1`; every observer event records
  `mutated:false` and the serial bytes are unchanged.
- `02 REACTIVE SAFE`: adds `arlresultretrylow:1`; it passes the first row
  unchanged and intervenes only after IMPACT rejects it with `?`.

Both use `cycles=fixed 12000`, `rxdelay:3000`, basic bounded trace, and LPT
capture. Do not install or run `01` until the ARL is explicitly returned from
the Dell to the HP and the physical preflight passes.

`.github/workflows/arl-trace-win64.yml` builds a Windows x64 SDL2 artifact. The
artifact contains:

- `DOSBox-X-ARL/dosbox-x-arl.exe`
- `DOSBox-X-ARL/contrib/arl/*.conf`
- `DOSBox-X-ARL/contrib/arl/*.ps1`
- `DOSBox-X-ARL/contrib/arl/fixtures/*.ndjson`
- `DOSBox-X-ARL/contrib/arl/profiles/*.json`
- `DOSBox-X-ARL/ARL-TRACE.md`
- `BUILD-MANIFEST.txt`
- `SHA256SUMS.txt`
- `arl-patches/*.patch` plus `arl-patches/manifest.txt`

## Acceptance

The ARL path is accepted when either:

- five consecutive reference-sample analyses complete, `INTERFAC.DAT` updates
  after each run, and values match the native FreeDOS machine within normal lab
  spread; or
- the trace identifies the first failure cause after the spark.
