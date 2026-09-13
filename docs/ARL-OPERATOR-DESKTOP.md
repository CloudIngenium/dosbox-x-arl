# ARL operator desktop

`contrib/arl/Set-ArlOperatorDesktop.ps1` builds the ARL floor desktop so a
technician can tell, at a glance, which launcher is theirs. It replaces the old
numbered-jargon shortcuts (`00 DIRECTSERIAL BYPASS` ... `90 EMULATOR`, created by
the now-retired `Create-ArlHpShortcuts.ps1`) with four public shortcuts (three
plain Spanish launchers plus the Ayuda guide card) and admin-only folders that hold everything else out of the way.

Everything an operator sees is Spanish (Mexico), plain words, no English jargon.

## What it lays down

**Public desktop** — `C:\Users\Public\Desktop` (the shared desktop the Piso login
sees). Exactly four `.lnk` files, in this order:

| Launcher | For whom | Runs |
|---|---|---|
| `Analizar colada` | Floor technicians, every day | `Chispa.Operator.exe`, the daily colada analysis (`sample-analysis-`) |
| `Ayuda - Que icono uso` | Anyone unsure | opens the guide card in Edge |
| `Ing. Serrano - Estandarizacion con muestras de ajuste` | Ing. Serrano only | `Launch-ArlStandardizationPassiveTrace.cmd` |
| `Ing. Serrano - Normalizacion` | Ing. Serrano only | `Launch-ArlNormalizationPassiveTrace.cmd` |

The launcher the operator opens decides the run-id prefix a burn gets
(`sample-analysis-`, `standardization-`, `normalization-`), which is why the
names have to be unambiguous.

**Guide card** — `C:\ARL\Guia-Operador\cual-uso.html` plus its `iconos\` images.
The folder is admin-owned but world-readable (`BU` read), so the card opens for
the Piso login and cannot be edited by it. Source of truth for the card is
`contrib/arl/operator-desktop/cual-uso.html`.

**Diagnostics / everything-else** — `C:\ARL\Herramientas-Admin\`, admin-only
(`BUILTIN\Administrators` full, no inherited user access). Old and technical
shortcuts found on the desktops are *moved* here, never deleted, into one of four
group folders:

- `Simuladores` — emulator / nullmodem launchers (tagged `SIMULA VALORES`)
- `Diagnostico` — raw DOSBox-X / IMPACT / serial-trace launchers
- `Verificacion-y-aprobacion` — the preflight and approve-report tools
- `Accesos-anteriores` — the previous daily launchers, kept for reference

**Undo archive** — `C:\ARL\_staging\desktop-archive\<timestamp>\`, admin-only,
holding `move-manifest.json` and the originals of anything replaced or moved
(`reemplazados\`, `duplicados\`, `carpetas-vacias\`, `nuevos\`). The manifest is
the single record `-Undo` reads to reverse a run.

## How to apply / review / undo

Run from an **elevated** PowerShell on the host (PS 5.1 or pwsh 7). The default
action is a dry run — it changes nothing.

```powershell
# Revisar (default): print the plan, touch nothing.
C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1

# Aplicar: execute the plan under a crash-safe manifest.
C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1 -Apply

# Deshacer: reverse the most recent run (or a named manifest).
C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1 -Undo
C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1 -Undo -Manifest 'C:\ARL\_staging\desktop-archive\<timestamp>\move-manifest.json'

# Autoprueba: run the self-test (all controls, or a subset).
C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1 -SelfTest
C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1 -SelfTest -Controls C13,C14,C15
```

`-Apply` supports `-WhatIf`: it walks the apply path and reports what it would do
without writing. A dry-run `revisar` that finds the desktop already correct
reports `sin-cambios`.

## Result line and exit codes

Every run prints one machine-readable line before exiting:

```
ARL-DESKTOP-RESULT {"schema":"arl-desktop-result-v1","status":"...", ...}
```

The exit code is derived from `status`:

| Exit | Meaning | Statuses |
|---|---|---|
| 0 | success / nothing to do | `sin-cambios`, `cambios-pendientes`, `aplicado`, `deshecho`, `autoprueba-ok` |
| 1 | error | `error`, `autoprueba-fallo` |
| 2 | refused a precondition (see the refusal code Rn) | `rechazado` |
| 3 | undo reversed only part of a run | `deshecho-parcial` |

A `rechazado` result carries a refusal code (`R1`..`R11`) naming the
precondition that failed and changing nothing — e.g. `R9` (must run on 64-bit
Windows PowerShell), `R1` (must run elevated / as administrator), `R3` (a
required source file such as the card or a launcher is missing), `R6`/`R8`
(a root is a reparse point or otherwise untrusted), `R11` (the `-Undo` manifest
is missing, out of place, or not in a reversible state).

## Tests and CI

- `contrib/arl/tests/Test-SetArlOperatorDesktop.ps1` — static parse + control
  self-test; `-Mutants` runs the mutation suite (each planted defect must be
  caught by a named control).
- `contrib/arl/tests/Test-ArlOperatorPreflightCmd.ps1` — pins the preflight
  launcher's Spanish, jargon-free text and cross-checks the launcher names it
  points to against this script's final rows.

Both are wired into `.github/workflows/arl-trace-win64.yml` (the windows-latest
`build-win64-sdl2` job, `shell: pwsh`). The dynamic controls, the mutation suite
and PS 5.1 itself only exercise fully on Windows; off Windows the self-test
prints `SKIP` and the mutation step is skipped. There is no separate PS 5.1 job —
the mutation test invokes `powershell.exe` (5.1) directly where it is present.

## Encoding

`Set-ArlOperatorDesktop.ps1` is ASCII with no BOM (control `C13` proves it), so
it runs identically on PS 5.1 and pwsh 7. Everything an operator reads that
needs accents lives in the HTML card, which uses HTML entities. The `.cmd`
launchers are ASCII (cmd.exe prints the OEM codepage); the two passive launchers
set a Spanish console title with unaccented text for the same reason.
