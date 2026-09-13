# Passive standardization and normalization capture

The `Ing. Serrano - Estandarizacion con muestras de ajuste` and
`Ing. Serrano - Normalizacion` launchers are observe-only evidence tools. They
start normal IMPACT, capture serial/LPT, and never send a Chispa command or
alter an ARL response. (Both were named `04 STANDARDIZATION PASSIVE` /
`05 NORMALIZATION PASSIVE` before the 2026-09 operator desktop; the `.cmd`
wrappers behind them are unchanged, and each now sets a Spanish console title so
the black window is unmistakably Ing. Serrano's.)

Before IMPACT starts, the launcher snapshots every top-level `.CAL`, `.REG` and
`.GPX` file plus `WORK.DAT`, `QUA.DAT`, `MAT.DAT`, `MESS.DAT` and `IMPACT.INI`.
The `.GPX` files matter most: `AL.GPX` holds the drift coefficients and the
type-standardization values, so it is what a standardization changes. Copies
are byte-exact (CP437, never re-encoded). After DOSBox closes, the directserial
finalizer captures the same files, writes `workflow-file-diff.json`, adds every
copy to the immutable marker, and only then publishes
`directserial-finalized.json` for Agent ingestion.

IMPACT normally opens no `.RES` result file during these workflows, so the
finalizer has no guest open event to tell it which result file belongs to the
session. It then captures only the `.RES` files that differ from
`result-files-before.json` (written before DOSBox starts) and whose last write
falls inside the session window. A changed file outside the window is not
copied; it is listed in `finalizer-result-selection.json` and in the marker
metadata (`result_fallback_skipped`), so the decision is never silent.

## Operator procedure

1. Close every DOSBox-X process and confirm the ARL is idle.
2. Run exactly one passive launcher.
3. Perform only the matching normal IMPACT workflow.
4. Do not use TICS reset/synchronize or any Chispa active command.
5. Close DOSBox after IMPACT returns to its menu.
6. Preserve screenshots of the workflow start, result and any error dialog.

The two workflows must use separate sessions so file changes and protocol
commands can be attributed without guessing.

These launchers are never the first physical gate. The gate is the spark check,
and it never creates a colada record (a sample burnt in `Analizar colada` prints
a colada sheet that is sent to the portal). Ing. Serrano first looks at the last
colada sheet printed today: `ARL 3460 - REPORTE DE ANALISIS` with numbers means
the instrument sparked; `ARL 3460 - AVISO: SIN CHISPA` means do not start. If no
colada was analyzed today, he checks the channel intensities on IMPACT's screen
in his first normal burn of the Serrano launcher, before accepting anything: a
burn with spark reaches tens of kp (107.7 kp on 2026-09-09), a burn without it
stays near 0.2 kp on every channel. If every channel stays below 1 kp he stops,
accepts no factors and follows the card's `SIN CHISPA` steps. The preflight launcher (`Run-ArlOperatorPreflight.cmd`, formerly `01 PRECHECK`)
now lives in the admin-only
`C:\ARL\Herramientas-Admin\Verificacion-y-aprobacion` folder, so the Piso
session cannot open it; an administrator may still run it, but it is no longer
a step the floor or Ing. Serrano is asked to do. There is no separate Serrano
Windows account on the host: "separate session" means close IMPACT first and
never continue after coladas in the same IMPACT window. Normalization is always
a later, separate session. The operator desktop that lays down these launchers
is applied and undone by `Set-ArlOperatorDesktop.ps1`; see
`docs/ARL-OPERATOR-DESKTOP.md`. (`Install-ArlOperatorExperience.ps1` removed
`02 REACTIVE SAFE` from the public desktop, but Chispa's
`Install-DosboxArlArtifact.ps1` puts it back, with `00 DIRECTSERIAL BYPASS`,
`01 OBSERVE ONLY`, `90 EMULATOR` and `Diagnosticos ARL`, on every DOSBox-X-ARL
install until the Chispa generators PR is merged and deployed; the rollout gate
in that doc covers it.)
