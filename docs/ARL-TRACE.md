# DOSBox-X ARL Toolkit

This fork keeps the ARL 3460 work as a small observability patch stack on top of
upstream DOSBox-X. The current base is the normal upstream release
`DOSBox-X 2026.07.02` at tag `dosbox-x-v2026.07.02`.

Scope is intentionally limited: trace, status, manual marks, rotation, and
offline analysis. Do not add replay, ARL emulation, or manual ICS command senders
until the lab has enough traces to identify the first failure.

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
serial1 = directserial realport:COM5 rxdelay:1000 arltracelevel:full arltracesession:impact arltracehangms:15000 arltrace:C:\ARL\diagnostics\serial.ndjson
```

- `arltrace:<file>` appends one NDJSON event per line. Omitting it preserves
  upstream `directserial` behavior.
- `arltracelevel:basic|uart|full` controls detail. `basic` records TX/RX,
  config, modem lines, and errors. `uart` adds guest UART register reads/writes.
  `full` adds host serial DCB, timeout, and modem-control snapshots.
- `arltracesession:<label>` labels the run, for example `impact`, `tics`,
  `status-only`, or `sample-analysis`.
- `arltracehangms:<ms>` emits `hang_snapshot` when no relevant TX/RX occurs for
  the configured interval.

Trace v2 includes:

- wall-clock epoch milliseconds, DOSBox elapsed milliseconds, and PIC time
- guest COM number, real host port, session label, and trace level
- TX and RX bytes as decimal, hex, and printable ASCII
- baud rate, data bits, parity, and stop bits requested by the DOS program
- RX error bits for break, framing, parity, and overrun
- RTS, DTR, CTS, DSR, DCD, RI, and break state
- guest UART register access for THR/RHR, IER, ISR/FCR, LCR, MCR, LSR, MSR, SPR
- FIFO usage, IRQ state, `rx_state`, `rx_retry`, and error counters
- Windows host DCB, timeouts, flow-control flags, and modem status in `full`

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
```

Each run creates `C:\ARL\diagnostics\<session>-<timestamp>\` with:

- generated DOSBox-X config
- `serial.ndjson`
- `dosbox.log`
- `run-metadata.json`
- copied `INTERFAC.DAT.after` when `-Wait` is used and the file exists

Keep the current lab serial settings while diagnosing:

- ARL cable on `COM5`
- WCH FIFO disabled or minimized in Device Manager
- `cycles = fixed 12000`
- `rxdelay:1000` as the first trace run

The pass/fail gate is post-spark completion: IMPACT must exit the busy state and
rewrite `C:\ARL\IMPLUS\INTERFAC.DAT`.

## TICS Diagnosis

Use TICS separately from IMPACT to validate the ACS/ICS link. Close IMPACT before
running TICS and keep the instrument operator present.

Start with communication parameters and passive/read-only checks:

- communication statistics
- `TL` link test
- `VE` ICS version
- `SI` and `RS` status reads

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

It writes:

- `summary.md`
- `timeline.csv`
- `suspect.json`

Automatic classifications include:

- `arl_silent_after_tx`
- `rx_received_but_guest_did_not_read`
- `fifo_or_uart_error`
- `modem_line_drop_or_low`
- `baud_or_parity_rejected`
- `write_failed`
- `hang_without_clear_serial_fault`

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

`.github/workflows/arl-trace-win64.yml` builds a Windows x64 SDL2 artifact. The
artifact contains:

- `DOSBox-X-ARL/dosbox-x-arl.exe`
- `DOSBox-X-ARL/contrib/arl/*.conf`
- `DOSBox-X-ARL/contrib/arl/*.ps1`
- `DOSBox-X-ARL/contrib/arl/fixtures/*.ndjson`
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
