# ARL operator desktop

`contrib/arl/Set-ArlOperatorDesktop.ps1` builds the ARL floor desktop so a
technician can tell, at a glance, which launcher is theirs. It replaces the old
numbered-jargon shortcuts (`00 DIRECTSERIAL BYPASS`, `01 OBSERVE ONLY`,
`02 REACTIVE SAFE`, `90 EMULATOR`, `Diagnosticos ARL`, `01 PRECHECK` ...) with
four public shortcuts (three plain Spanish launchers plus the Ayuda guide card)
and admin-only folders that hold everything else out of the way.

Those old shortcuts are **not** gone just because this repo's
`Create-ArlHpShortcuts.ps1` is retired (it now throws). Chispa's
`deploy/Install-DosboxArlArtifact.ps1` re-creates `00 DIRECTSERIAL BYPASS`,
`01 OBSERVE ONLY`, `02 REACTIVE SAFE`, `90 EMULATOR` and `Diagnosticos ARL` on
the public desktop on **every DOSBox-X-ARL install**, and Chispa's
`Install-ArlOperatorShortcuts.ps1`, `Reset-ArlDesktopShortcuts.ps1` and
`Install-ArlOperatorExperience.ps1` (`ARL 3460 - Analizar`) put back their own
sets. A Chispa PR (branch `feat/operator-desktop-generators`, link to be added)
makes those scripts leave the desktop alone when `Set-ArlOperatorDesktop.ps1` is
present and only run its review mode. Until that PR is merged **and** deployed,
follow the [rollout gate](#rollout-gate).

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

**Undo archive** — `C:\ARL\_staging\desktop-archive\<timestamp>\` (the stamp is
UTC, `yyyyMMdd-HHmmss`), admin-only, holding `move-manifest.json` and the
originals of anything replaced or moved (`reemplazados\`, `duplicados\`,
`carpetas-vacias\`, `nuevos\`), plus `deshecho\<seq>-...` for what `-Undo` took
back off the desktop. The manifest is the single record `-Undo` reads to reverse
a run.

### What it changes, exactly

- **Files.** `-Apply` only *moves* desktop items (into `Herramientas-Admin\` or
  the archive) and writes its own new shortcuts, card and icons. It never deletes
  a file. `-Undo` never deletes a file either: a shortcut, card or icon that apply
  put down is moved aside into `deshecho\` and the original comes back from the
  archive. The only thing `-Undo` removes is a folder apply created that is empty
  again.
- **Permissions (ACLs).** Beyond the new admin folders (`Herramientas-Admin`,
  the archive), the script also
  - resets every *moved* item and every *created* public shortcut so it inherits
    from its new parent folder, and sets its owner to `BUILTIN\Administrators`;
  - gives `Guia-Operador` `BU` read (the Piso login must open the card);
  - on `-Undo`, puts back the ACL and owner a moved item had before, and on
    folders whose ACL it changed, restores the DACL first and the owner as a
    separate step (an owner such as SYSTEM or TrustedInstaller cannot be written
    together with the DACL). ACLs are compared by meaning, not by ACE order.
- **Existing folders.** `Herramientas-Admin`, `Guia-Operador` or the archive root
  that already exist and are owned by, or writable by, a non-admin (for example
  `Authenticated Users` inheriting Modify from `C:\ARL\_staging`) are refused
  (`R7`); a folder the script creates is read back and must carry the requested
  admin-only ACL.
- **Not detected.** The Piso desktop is assumed to be `C:\Users\Piso\Desktop`.
  Folder redirection or OneDrive Known Folder Move for Piso is not detected,
  because reading it means loading Piso's registry hive, which is a write-class
  operation on the host. Check it by hand before the first `-Apply`.

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

**Run `-Apply` and `-Undo` at the console of the host (or an RDP session), in
an elevated PowerShell — never through the ~105 s synchronous SSH relay.** A run
that is cut off is recoverable (below), but there is no reason to invite it. The
apply deadline scales with the plan (60 s plus 10 s per action).

### Interrupted runs and repeated undo

- The manifest is written before and after every action. A run that is killed
  or loses power part-way leaves the manifest in `applying` (or `undoing` for an
  undo); both states are reversible, so `-Undo` picks that manifest up instead
  of skipping past it to an older one.
- Each undo step looks at the disk before it acts (is the item at the source or
  the destination, does its sha256 match what apply recorded, is the backup
  present with the recorded hash). So it is safe for actions that finished,
  failed part-way or were cut off, and running `-Undo` twice does no harm.
- A backup is verified *before* anything is moved; a missing or changed backup
  leaves the current file in place and marks the step skipped.
- Steps an earlier `-Undo` skipped are retried on the next `-Undo`. The run is
  `deshecho` (exit 0) only when every action that ran is undone; otherwise it
  stays `deshecho-parcial` (exit 3) and lists each `NO SE DESHIZO` step with its
  reason.

### Rollout gate

**The first `-Apply` on Laboratorio-ARL waits** until the Chispa PR that stops
the generators (branch `feat/operator-desktop-generators`, link to be added) is
**merged and deployed** on the host. Before that, the next DOSBox-X-ARL install
(`Install-DosboxArlArtifact.ps1`) puts `00 DIRECTSERIAL BYPASS`, `01 OBSERVE
ONLY`, `02 REACTIVE SAFE`, `90 EMULATOR` and `Diagnosticos ARL` straight back on
the public desktop, and its delete-by-regex cleanup assumes it owns that desktop.

After that, and again after **every** DOSBox-X-ARL install or Chispa deploy, in
this order:

1. **Revisar** (the default dry run, no switch). Read the plan. Every old
   shortcut must show as `SE MUEVE` (to its admin group) or `SE ARCHIVA` (a
   duplicate of one already there); no old shortcut may show as `DESCONOCIDO`.
   `sin-cambios` means there is nothing to do: stop here.
2. **`-Apply -WhatIf`.** Walks the apply path without writing; it must end in
   `cambios-pendientes`, with no `RECHAZADO`.
3. **`-Apply`, only when idle:** IMPACT and DOSBox-X-ARL closed, no burn or
   session in progress, nobody working at the Piso login. Elevated, at the host
   console or over RDP (see above). The script never looks at processes (control
   `C09` forbids it), so "idle" is a person's check.

What each shortcut the installers put back becomes (engine control `C21` with
real `.lnk` files; planner check `generadores-chispa` on any OS):

| Put back by | Shortcut | Goes to |
|---|---|---|
| `Install-DosboxArlArtifact.ps1`, `Install-ArlOperatorShortcuts.ps1` | `00 DIRECTSERIAL BYPASS`, `01 OBSERVE ONLY`, `02 REACTIVE SAFE`, `Diagnosticos ARL` | `Diagnostico` |
| `Install-DosboxArlArtifact.ps1`, `Install-ArlOperatorShortcuts.ps1` | `90 EMULATOR` | `Simuladores` |
| `Reset-ArlDesktopShortcuts.ps1` | `01`-`03 Bridge Emulator - ...` | `Simuladores` |
| `Reset-ArlDesktopShortcuts.ps1` | `10 Direct Serial - Baseline`, `20 Inspect Last ARL Run`, `30`/`31 Print ...`, `Diagnostics - Serial Traces` | `Diagnostico` |
| `Install-ArlOperatorExperience.ps1` | `ARL 3460 - Analizar` | `Accesos-anteriores` |
| retired `Create-ArlHpShortcuts.ps1` (still on the host today) | `01 PRECHECK`, `03 APPROVE LAST REPORT` | `Verificacion-y-aprobacion` |
| retired `Create-ArlHpShortcuts.ps1` (still on the host today) | `04 STANDARDIZATION PASSIVE`, `05 NORMALIZATION PASSIVE` | `Accesos-anteriores` |

A shortcut whose launcher is already in its group goes to the run's
`duplicados\`; one with the same name but a different target is moved in with a
` (<timestamp>)` suffix. Nothing is deleted.

### Manual sign-off

The script cannot see or fix these. Tick each one before calling the rollout done:

- [ ] The Chispa generators PR (`feat/operator-desktop-generators`) is merged
      **and** deployed on Laboratorio-ARL (deployed version read, read-only).
- [ ] Revisar, `-Apply -WhatIf` and `-Apply` ran in that order, when idle, and a
      last revisar reports `sin-cambios`.
- [ ] The Piso taskbar pin **`DOSBox-X DOS Emulator`** is unpinned by hand. It
      starts `C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe` bare: no session, no run id,
      no Chispa capture, so it goes nowhere. The script only reports it
      (`PENDIENTE MANUAL ... desanclar a mano`); it never edits the taskbar.
- [ ] The Piso desktop is not redirected (see "Not detected").
- [ ] The Chispa agent version deployed on the host (read-only) matches the
      card's `arl-card-chispa` meta tag. The card text (the `ARL 3460 - AVISO: SIN
      CHISPA` steps, which sheets print for a standardization or normalization)
      was written against that Chispa commit; on an older or newer build, check
      the card against it first.
- [ ] The card, printed from Edge on the host (Ctrl+P, Letter), is exactly two
      pages, technicians first. A local Chrome render leaves about two lines free
      on page two, and Segoe UI on the host can wrap differently.

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
precondition that failed and changing nothing:

| Code | Refused because |
|---|---|
| `R1` | not elevated, or a read hit *access denied* (e.g. a non-elevated `revisar` after apply) |
| `R2` | a path parameter is invalid, has a junction, is outside the temp folder, or mixes temp paths with the real defaults; `-SelfTest` given paths or `-WhatIf` |
| `R3` | a required file is missing: Chispa, the passive launchers, DOSBox-X, the card or Edge |
| `R4` | an icon source could not be read |
| `R5` | the guide card is not ASCII, does not name every icon, or has links or scripts |
| `R6` | a junction or symlink in `_staging`'s chain, the admin folders or the desktops |
| `R7` | an existing admin folder is owned by, or writable by, a non-admin; or this run's archive folder already exists |
| `R8` | a file where a folder was expected, or the reverse |
| `R9` | not Windows, not 64-bit PowerShell, or a nested self-test |
| `R10` | `-Undo -Manifest` named a run older than one still not undone |
| `R11` | the `-Undo` manifest is missing, out of place, not reversible, from another computer, or has untrusted paths or owners |

Undo is LIFO: `-Undo` reverses the newest reversible run (`applying`, `applied`,
`failed-partial`, `undoing`, `undone-partial`).

## Tests and CI

- `contrib/arl/tests/Test-SetArlOperatorDesktop.ps1` — static parse + control
  self-test (22 controls, `C01`-`C21` plus `C04b`); `-Mutants` runs the engine
  mutation suite (23 mutants `M01`-`M23`). Each mutant runs its self-test with
  `-SelfTest -Controls <its control>`, so it counts as killed only when the
  control named for it fails. `C20` kills the child inside an action
  (`ARL_DESKTOP_FAIL_INSIDE_ACTION`: after a move, after a backup, after a
  shortcut lands but before its ACL reset) and checks that `-Undo` restores both
  desktops exactly. `C21` lays down the shortcuts Chispa's installers create,
  with their real names, targets, working folders and icon; `-Apply` must move
  each to its group (table above). It then lays down the next installer's set:
  revisar must report `cambios-pendientes`, `-Apply` must clear it, and a last
  revisar must report `sin-cambios`. At every depth the file also runs the card
  mutants `K01`-`K10` (`C15` must reject each; `K09` puts back the old "burn a
  sample in Analizar colada" spark check, `K10` drops the 1 kp stop) and the
  planner checks. The planner checks call the planner's own functions on
  in-memory items and a temp folder: three items with the same name get three
  distinct destinations (also when an alternate name is already on disk), a
  launcher planned twice in one run goes once to `duplicados\`, a shortcut whose
  target (or whose `cmd.exe /c` / `powershell.exe -File` script) is an Emulator or
  Bridge launcher goes to `Simuladores`, a token-named folder that holds a kept
  item (`Microsoft Edge.lnk`) is left in place, and every shortcut Chispa's
  installers put back goes to its group (`generadores-chispa`). Planner mutants
  `P01`-`P06` plant the defects the reviewers reported; each must fail its named
  check. The CI gate's log reader is checked there too, against a complete log
  and logs with one planted gap each.
- `contrib/arl/tests/Invoke-ArlOperatorDesktopCiGate.ps1` — the CI gate. It
  refuses to start off Windows or unelevated, runs the test above (`-Depth Motor`,
  or `-Depth Mutantes` for `-Mutants`), streams its output, and fails on a
  non-zero exit, on any `SKIP` or `FAIL` line, on any control without its
  `PASS` line under both `powershell` (5.1) and `pwsh` (7), on any engine mutant
  not killed by its named control, or without the final `all passed`. It reads
  the control and mutant lists from the test file, so there is one list to keep.
- `contrib/arl/tests/Test-ArlOperatorPreflightCmd.ps1` — pins the preflight
  launcher's Spanish, jargon-free text and cross-checks the launcher names it
  points to against this script's final rows.

All three run in `.github/workflows/arl-trace-win64.yml`, in its single
windows-latest job `build-win64-sdl2` (`shell: pwsh`). **There is no CI job off
Windows.** The engine controls (`C01`-`C08`, `C04b`, `C10`-`C12`, `C16`-`C21`,
and the run-time half of `C09`) and the engine mutants need Windows and an
elevated session. GitHub-hosted Windows runners run as an administrator with UAC
off, and both steps check it: without elevation the step exits 1, and the gate
fails the step on any `SKIP` or missing `PASS` instead of passing it green. The
static checks (`C09`, `C13`-`C15`), the card mutants, the planner checks and the
gate's own checks need no Windows API: they run in that same job, and they are
also what a developer machine off Windows can run (there the engine depths print
`SKIP`). The two desktop steps run only when the diff touches `contrib/arl/` or
the workflow; a step before them decides, and runs them whenever the diff cannot
be computed. The workflow is one job, so a job-level `paths` filter would skip
the build too. Timeouts: 30 minutes for the test step, 90 for the mutation step.
There is no separate PS 5.1 job; the tests invoke `powershell.exe` (5.1) directly.

## Encoding

`Set-ArlOperatorDesktop.ps1` is ASCII with no BOM (control `C13` proves it), so
it runs identically on PS 5.1 and pwsh 7. Everything an operator reads that
needs accents lives in the HTML card, which uses HTML entities. The `.cmd`
launchers are ASCII (cmd.exe prints the OEM codepage); the two passive launchers
set a Spanish console title with unaccented text for the same reason.
