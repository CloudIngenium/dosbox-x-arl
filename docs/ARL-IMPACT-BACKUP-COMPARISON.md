# IMPACT backup comparison

Use `contrib/arl/Compare-ArlImpactBackups.ps1` to compare a historical IMPACT
backup with a read-only snapshot of the active installation. Inputs may be ZIP
files or directories.

```powershell
pwsh -File contrib/arl/Compare-ArlImpactBackups.ps1 `
  -ReferencePath C:\ARL\evidence\before.zip `
  -CandidatePath C:\ARL\evidence\after.zip `
  -OutputDirectory C:\ARL\evidence\comparison
```

The tool locates the most likely active IMPACT directory, then compares only
top-level `.CAL`, `.REG`, `WORK.DAT`, `QUA.DAT`, `MAT.DAT`, `MESS.DAT`,
`INTERFAC.DAT`, and `0.RES`. It reports created, deleted, modified and unchanged
files with SHA-256 hashes. Modified files also include the first differing byte
offset and total differing-byte count.

The tool is read-only. It never restores files, writes into either input, or
starts IMPACT/DOSBox. Review every difference before any laboratory restore.
