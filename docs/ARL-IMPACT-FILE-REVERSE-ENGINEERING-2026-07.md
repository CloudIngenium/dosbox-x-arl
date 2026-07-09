# ARL IMPACT+ File Reverse Engineering - July 2026

This note captures what can be reconstructed from IMPACT+ working files,
temporary files, print captures, and emulator artifacts on the HP lab PC.

## Files Collected

Source machine: `LABORATORIO-ARL`.

Collection snapshot:

- `C:\ARL\IMPLUS\INTERFAC.DAT`
- `C:\ARL\IMPLUS\IMPACT.INI`
- `C:\ARL\IMPLUS\TELEX.DEF`
- `C:\ARL\IMPLUS\TELEX.DAT`
- `C:\ARL\IMPLUS\NOTDONE.FLG`
- `C:\ARL\IMPLUS\AUTOEXEC.BAT`
- `C:\ARL\IMPLUS\CONFIG.SYS`
- representative `.RES`, `.CAL`, `.REG`, and `.RP1` files
- latest emulator run artifacts from `C:\ARL\diagnostics\impact-emulator-20260709-084028`

The latest emulator run used profile:

`C:\ARL\DOSBox-X-ARL\profiles\impact-format-equivalence-safe-sweep.json`

## File Roles

### `INTERFAC.DAT`

`INTERFAC.DAT` is the small text interface file consumed by external programs.
It is the cleanest target for a future IMPACT replacement or Zap integration.

Observed structure:

```text
:DATE
09-Jul-2026
08:46

:ALLOY
Al

:SAMPLEID
1
2
3
4
5

:QUALITY
;QUA1

:NBELE
14
Mn      : .4443149: 3
...

:FLAGS
M

:END
```

Implications:

- We can generate `INTERFAC.DAT` independently once we can parse accepted ARL
  result rows and apply the same element ordering/precision rules.
- The element line format is `name padded to 8 : value : displayed decimals`.
- This file contains the final result surface, not the full raw intensity audit.

### `.RES`

The `.RES` files are plain ASCII historical result stores. Each stored result is
a compact record:

```text
<alloy or group>
<sample id 1>
<sample id 2>
<sample id 3>
<sample id 4>
<sample id 5>
<date/time>
<element count>
<element name> <value>
...
```

Observed examples include production alloys such as `SS-413BD` and `Al`. The
large `0.RES` file also includes the July 2026 DOSBox/emulator test results.

Implications:

- `.RES` gives us a long real-world corpus of expected final values, alloy names,
  sample-id layouts, and element ordering.
- It is useful for validating our future `INTERFAC.DAT` generator and report
  renderer.
- It does not contain raw serial frames or enough information to reconstruct the
  ARL protocol by itself.

### `LPTCAP.PRN`

`LPTCAP.PRN` is a DOSBox-X parallel-port capture of IMPACT's print output. It is
plain ASCII and includes:

- Absolute Intensities
- Ratioed Intensities
- Drift Corrected Intensities
- Calibration Curve Evaluation
- Interelement Interference Corrections
- Type Standardization
- 100% normalization
- Final Concentration

The latest `98` run produced an `LPTCAP.PRN` of `81720` bytes, proving that the
emulator can drive IMPACT through store/print flows.

Implications:

- LPT capture is the best audit artifact for comparing our replacement to
  IMPACT's calculations and report formatting.
- If we replace IMPACT, we should initially emit both `INTERFAC.DAT` and an
  IMPACT-like text report so operators can compare output.

### `.CAL`

`AL.CAL` and `SS-413BD.CAL` are dBase/FoxBase DBF files.

Observed DBF properties:

- `AL.CAL`: 14 records, 121 fields, record length 969
- `SS-413BD.CAL`: 1 record, 121 fields, record length 969
- Field names begin with `STDNAME`, then `ELEM1` through at least `ELEM39`
- Records include standard names and the element ordering for the curve

First record examples:

- `AL.CAL`: standard `WE_1000`, elements `Si Mn Ni Cr Cu Ti Pb Mg Al Fe1 Sr Zn Sn P`
- `SS-413BD.CAL`: standard `ALSI11`, same element family/order

Implications:

- A future replacement can read calibration metadata directly from DBF instead
  of hardcoding element order.
- Full concentration calculation replacement will require deeper DBF decoding
  beyond the current serial-protocol goal.

### `IMPACT.INI`

Important observed flags:

```text
Use Bootup Status = ON
Use Offline Mode = OFF
Use Trace Mode = ON
Use Single Shot Analysis = OFF
Store Partial Results = OFF
ICS Delay Time = 100
Temp Opt = 5
Temp Choice = 1
```

`Instrument Config` also defines status-channel ranges and scaling, including
vacuum, temperatures, mains, and voltage rails.

Implications:

- `ICS Delay Time` is a candidate knob if status initialization remains fragile.
- `Use Trace Mode = ON` is useful and should stay enabled while diagnosing.
- `Store Partial Results = OFF` helps explain why rejected rows do not update the
  output files.

### `TELEX.DAT`, `TELEX.DEF`, `NOTDONE.FLG`

These are small transient state files produced during IMPACT startup/operation.

Observed cleanup behavior for the latest emulator run:

```json
{
  "deleted_count": 3,
  "deleted_names": ["notdone.flg", "telex.dat", "telex.def"]
}
```

This cleanup, combined with more complete emulator acknowledgements, made the
`98` profile load on the first IMPACT launch.

Implications:

- These files are part of the "sticky first-launch" state.
- Launchers should continue backing them up and deleting them before controlled
  emulator or diagnostic runs.
- We should not delete `.RES`, `.CAL`, `.GPX`, `.REG`, or `.RP1` files as part of
  routine cleanup.

### `AUTOEXEC.BAT` and `CONFIG.SYS`

The copied FreeDOS startup files show legacy setup:

```bat
mode com2:4800,n,8,1
mode lpt2:=com2:
mouse
c:\
cd c:\implus
implus
```

Implications:

- The legacy environment redirects `LPT2` to `COM2`, which may explain older
  print routing behavior on the Dell/FreeDOS setup.
- This does not directly control the ARL ICS link used by DOSBox-X `serial1`,
  but it is useful context for printer troubleshooting.

## Latest `98` Result

Run: `C:\ARL\diagnostics\impact-emulator-20260709-084028`

Profile: `impact-format-equivalence-safe-sweep.json`

Outcome:

- 32 format-equivalence cases presented
- 32 accepted by IMPACT with `#em`
- 0 rejected with `?`
- final `Please Run Sample` occurred after profile exhaustion on a new
  `#rd 246\r`
- print capture generated: `LPTCAP.PRN` `81720` bytes

Interpretation:

- The safe formatting strategy is viable in the emulator.
- IMPACT accepts chemically equivalent ASCII rows with leading zeros, plus signs,
  and precision adjustments when leading whitespace is avoided.
- The final stall was not a protocol rejection; the emulator simply had no
  `case33` response.

## Replacement Path

The file analysis supports a staged replacement plan:

1. Parse ARL result rows from trace/emulator data.
2. Generate `INTERFAC.DAT.test` and compare it against IMPACT's `INTERFAC.DAT`.
3. Parse `LPTCAP.PRN` final concentration sections and compare against generated
   reports.
4. Read `.CAL` DBF metadata for element ordering and curve names.
5. Only later implement concentration math, using LPT/RES output as a regression
   corpus.

## Open Questions

- Whether IMPACT's row acceptance failure on real ARL data is purely checksum/
  formatting or also tied to values, alloy state, or hidden run state.
- Whether a receive-side canonicalization filter in DOSBox-X-ARL can transform
  real ARL rows into accepted safe formatting without changing numeric chemistry.
- Whether `ICS Delay Time` or other `IMPACT.INI` options affect real status-read
  reliability.
- Whether the FreeDOS `LPT2:=COM2` path is still needed for the Dell printer or
  whether DOSBox-X LPT capture plus Windows printing is the better modern path.

## IMPACT.INI Flags And Test Candidates

The flags below were confirmed both in `IMPACT.INI` and in strings embedded in
`IMPACT.EXE` / `INIFILE.EXE`, so IMPACT itself reads them.

### Most Relevant To ARL Communication

| Setting | Current | Evidence | Risk | Recommendation |
|---|---:|---|---|---|
| `ICS Delay Time` | `100` | Explicit setting; name directly references ICS timing | Low if varied in small steps | Best first config knob. Test `150`, `200`, `300`, then maybe `50`. |
| `Use Bootup Status` | `ON` | Strings show `recover,status` and status UI paths | Medium | Test `OFF` only to isolate first-launch/status hangs; do not use as production default unless status reads are replaced elsewhere. |
| `Use Trace Mode` | `ON` | Strings show `display,trace` / `recover,trace` | Low | Keep `ON` while diagnosing. Test `OFF` only if trace mode changes timing or writes temp files that affect state. |
| `Store Partial Results` | `OFF` | Strings show flag; output files do not update on rejected rows | Medium | Test `ON` only in emulator first. Could reveal rejected/partial values but may pollute `.RES`/output files. |
| `Use Offline Mode` | `OFF` | Strings show `display,offline` / `recover,offline`; UI calls it Offline Teacher | Medium | Useful for emulator/teaching only. Not a real ARL communication fix. |
| `Stand 1`, `Source 1` | `1`, `1` | Used in ICS configuration/startup | High | Do not change unless matching ARL hardware configuration from TICS/manual. |
| `Stand 2`, `Source 2` | `0`, `0` | Used in ICS configuration/startup | High | Do not change unless ARL hardware has second stand/source configured. |

### Probably Not Communication Fixes

| Setting | Current | Notes |
|---|---:|---|
| `Use Kilopulses` | `ON` | Measurement/counting presentation; likely affects analysis parameters or display, not serial transport. |
| `Use Single Shot Analysis` | `OFF` | Could change sample workflow, but not checksum/status protocol. Test only after emulator confirms behavior. |
| `Use Programmable Attenuators` | `OFF` | Hardware/optics feature. Do not toggle during production ARL tests. |
| `Use Quality Sort` | `OFF` | Post-analysis quality classification. It can spawn `QA.EXE`; not a serial fix. |
| `Use Charge Correction` | `OFF` | Post-analysis charge calculation. Not a serial fix. |
| `Use QS/CC in auto mode` | `OFF` | Automation for quality/charge modules. Not a serial fix. |
| `Q34000 Support` | `OFF` | Instrument-family support flag. Leave off unless docs prove ARL 3460 needs it. |
| `Use Impact in EGA mode` | `OFF` | Video/UI only. |
| `Use Compac & Telex` | `OFF` | Old external transmission path. Older INIs had this `ON`, current is `OFF`; not likely to improve ARL serial, but it creates `TELEX.*` state files. |
| `Automaticly transmit runs` | `OFF` | External transmission after result, not ARL communication. |
| `Transmit Average Only` | `ON` | External transmission/report behavior. |
| `Temp Opt`, `Temp Choice` | `5`, `1` | IMPACT marks these as temporary operating variables. Do not edit directly. |

### Old INI Comparison

Archived INIs in `18_01_05` and `ROMAN` match the current flag set except:

- `Use Trace Mode`: old `OFF`, current `ON`
- `Use Compac & Telex`: old `ON`, current `OFF`
- status-channel limits differ:
  - `Vacuum` high limit old `35`, current `45`
  - `Vacuum` offset old `2.7964072`, current `2.6964072`
  - `C-temp` low limit old `20`, current `15`

Interpretation:

- The old INIs do not reveal a magic serial setting.
- Current `Trace Mode = ON` is intentional for diagnosis.
- Current `Compac & Telex = OFF` likely reduces extra file/state noise.

## Reversible INI Overrides

`Start-ArlTraceRun.ps1` now supports temporary IMPACT.INI overrides:

```powershell
-ImpactIniSet "ICS Delay Time=200"
```

Multiple assignments are allowed:

```powershell
-ImpactIniSet "ICS Delay Time=200","Use Trace Mode=OFF"
```

Safety behavior:

- backs up `IMPACT.INI` under the run directory;
- writes only keys that already exist;
- records old/new lines in `run-metadata.json`;
- starts a restore watcher that restores `IMPACT.INI` after the DOSBox process
  exits.

Recommended first tests:

1. Real ARL, one variable only: `ICS Delay Time=200`.
2. If status reads improve but result rows still reject, test
   `ICS Delay Time=300`.
3. If first-launch status hangs return, test `Use Bootup Status=OFF` only as an
   isolation experiment, then restore the normal status path.
4. Test `Use Trace Mode=OFF` only if we suspect IMPACT's own trace/file writes
   perturb timing. Keep DOSBox-X-ARL serial tracing enabled.

## Compac/Telex Offline Tests

`Use Compac & Telex` is unlikely to fix ARL/ICS communication directly. The
strings in `SAMPANAL.EXE` point to result export/reporting:

- `TELEX.DAT`
- `TELEX.DEF`
- `TELEX.SAV`
- `Send This Run to Compac or Telex?`
- `Automaticly transmit runs`
- `Transmit Average Only`

This makes it useful for reverse engineering the post-analysis export layer and
for a future IMPACT replacement.

Prepared emulator-only shortcuts:

| Shortcut | Purpose | INI overrides |
|---|---|---|
| `80 EMU SAFE LOOP` | Long-running safe accepted-row loop, no Compac/Telex changes | none |
| `81 EMU COMPAC ON SAFE LOOP` | See files/prompts generated when Compac/Telex is enabled but automatic transmit is disabled | `Use Compac & Telex=ON`, `Automaticly transmit runs=OFF`, `Transmit Average Only=ON` |
| `82 EMU COMPAC AUTO SAFE LOOP` | See whether IMPACT writes/sends additional export state automatically after accepted runs | `Use Compac & Telex=ON`, `Automaticly transmit runs=ON`, `Transmit Average Only=ON` |
| `83 EMU STORE PARTIAL SAFE LOOP` | Learn whether rejected/partial result paths write additional files | `Store Partial Results=ON` |

All four use `serial1=nullmodem` through the emulator and never open `COM5`.

When an INI override is active, the runner now captures these post-run files
under the diagnostic folder before restoring `IMPACT.INI`:

- `INTERFAC.DAT`
- `TELEX.DAT`
- `TELEX.DEF`
- `TELEX.SAV`
- `TEMP.TMP`
- `RESULT.TMP`
- `IMPACT.DBF`
- `SENTFILE.DAT`
- `NOTDONE.FLG`
- `REPORT.X`

Use `Analyze-ArlEmulatorLog.ps1 -WriteFiles` after a run to classify the
emulator outcome and write `emulator-summary.json` plus `emulator-summary.md`.
