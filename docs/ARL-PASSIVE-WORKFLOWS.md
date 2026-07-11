# Passive standardization and normalization capture

The `03 STANDARDIZATION PASSIVE` and `04 NORMALIZATION PASSIVE` launchers are
observe-only evidence tools. They start normal IMPACT, capture serial/LPT, and
never send a Chispa command or alter an ARL response.

Before IMPACT starts, the launcher snapshots every top-level `.CAL` and `.REG`
file plus `WORK.DAT`, `QUA.DAT`, `MAT.DAT` and `MESS.DAT`. After DOSBox closes,
the directserial finalizer captures the same files, writes
`workflow-file-diff.json`, adds every copy to the immutable marker, and only
then publishes `directserial-finalized.json` for Agent ingestion.

## Operator procedure

1. Close every DOSBox-X process and confirm the ARL is idle.
2. Run exactly one passive launcher.
3. Perform only the matching normal IMPACT workflow.
4. Do not use TICS reset/synchronize or any Chispa active command.
5. Close DOSBox after IMPACT returns to its menu.
6. Preserve screenshots of the workflow start, result and any error dialog.

The two workflows must use separate sessions so file changes and protocol
commands can be attributed without guessing.
