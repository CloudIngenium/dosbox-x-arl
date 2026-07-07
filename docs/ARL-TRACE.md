# DOSBox-X ARL Trace Fork

This fork keeps the ARL 3460 work as a small patch stack on top of upstream
DOSBox-X. The current base is the normal upstream release `DOSBox-X 2026.07.02`
at tag `dosbox-x-v2026.07.02`.

## Branches

- `upstream-master` tracks `joncampbell123/dosbox-x` `master` and is treated as
  read-only.
- `arl-trace` is the active CloudIngenium branch.
- ARL releases use tags like `arltrace-v2026.07.02-1`.

Enable conflict reuse in local maintenance clones:

```bash
git config rerere.enabled true
```

## Trace Option

`directserial` accepts one extra optional parameter:

```ini
serial1 = directserial realport:COM5 rxdelay:1000 arltrace:C:\ARL\diagnostics\serial-trace.ndjson
```

When `arltrace:` is omitted, `directserial` follows upstream behavior. When it is
present, the file is opened in append mode and each event is flushed as one
NDJSON line.

The trace includes:

- wall-clock epoch milliseconds and DOSBox elapsed milliseconds
- guest COM number and real host port
- TX and RX bytes as decimal, hex, and printable ASCII
- baud rate, data bits, parity, and stop bits requested by the DOS program
- RX error bits for break, framing, parity, and overrun
- RTS, DTR, CTS, DSR, DCD, RI, and break state
- COM write failures and unsupported port configuration attempts

## Lab Install

Install the ARL build beside the stock DOSBox-X copy:

```powershell
New-Item -ItemType Directory -Force C:\ARL\DOSBox-X-ARL
Copy-Item .\dosbox-x.exe C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe
Copy-Item .\contrib\arl\dosbox-arl-trace.conf C:\ARL\dosbox-arl-trace.conf
New-Item -ItemType Directory -Force C:\ARL\diagnostics
C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe -conf C:\ARL\dosbox-arl-trace.conf
```

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
C:\ARL\diagnostics\tics\<timestamp>\
```

Do not use TICS synchronize or reset commands unless a controlled diagnostic
step explicitly calls for them.

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
- `src/dosbox.cpp`
- `dosbox-x.reference.conf`
- `dosbox-x.reference.full.conf`

Then build Windows x64, smoke-test `directserial` with and without `arltrace`,
and tag:

```bash
git tag -a arltrace-vYYYY.MM.DD-N -m "ARL trace build YYYY.MM.DD-N"
```

## Acceptance

The ARL path is accepted when either:

- five consecutive reference-sample analyses complete, `INTERFAC.DAT` updates
  after each run, and values match the native FreeDOS machine within normal lab
  spread; or
- the trace identifies the first failure cause after the spark.
