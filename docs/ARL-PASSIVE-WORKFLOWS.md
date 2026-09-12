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

These launchers are never the first physical gate. Run the preflight launcher
first (it must end in `EQUIPO LISTO`), then confirm the instrument really sparks
with one analysis through `Analizar colada y estandar tipo` before capturing
standardization. Normalization is always a later, separate session, in Ing.
Serrano's own login. The operator desktop that lays down these launchers is
applied and undone by `Set-ArlOperatorDesktop.ps1`; see
`docs/ARL-OPERATOR-DESKTOP.md`. (`02 REACTIVE SAFE` no longer exists on the
host; `Install-ArlOperatorExperience.ps1` removes it.)
