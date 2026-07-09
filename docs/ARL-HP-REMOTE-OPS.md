# ARL HP Remote Ops Notes

These notes exist because inline PowerShell over SSH is fragile and repeatedly
caused avoidable friction during the ARL/DOSBox-X tests.

## Known-Good Access

- Host: `LABORATORIO-ARL` / `10.5.18.101`.
- SSH user: `svc-claude`.
- SSH key: `~/.ssh/svc-claude`.
- Interactive lab user is normally `JC`, so operator-facing shortcuts must go
  to the public desktop:

```powershell
C:\Users\Public\Desktop
```

Use explicit SSH args:

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/svc-claude svc-claude@LABORATORIO-ARL hostname
```

Do not assume `jcarlos@LABORATORIO-ARL`; that reaches the host but is not the
working automation account.

## 2026-07-08 Remote Access Blocker

During the SIMPLE386 matrix deployment attempt, all remote execution paths were
partially broken:

- Direct SSH authenticated by host name but the configured shell emitted
  `No se pudo iniciar CLR, HRESULT: 80004005`.
- `scp` closed the connection before upload.
- Azure Arc `run-command` reached the machine, but Windows PowerShell failed
  inside the run-command host with internal error `800705af`.
- SMB enumerated `C$` and `IMPLUS$`, but denied directory listing/content access
  from this macOS session even when mounting with the service account.

Treat this as a remote-management issue, not an ARL toolkit issue. The toolkit
package can still be installed from the interactive RDP session as user `JC`.

Manual install fallback:

1. Copy `arl-toolkit-simple386-matrix-20260708.zip` to the HP.
2. Extract it over `C:\ARL\DOSBox-X-ARL`.
3. From an interactive PowerShell window on the HP, run:

```powershell
C:\ARL\DOSBox-X-ARL\Create-ArlHpShortcuts.ps1
```

This creates only the no-rebuild operator shortcuts. Do not pass
`-IncludeBuildRequired` until a build newer than `96994b1` is installed.

## Avoid Inline PowerShell Quoting

Avoid this pattern for anything non-trivial:

```bash
ssh svc-claude@LABORATORIO-ARL 'powershell -Command "... $variables ... $_ ..."'
```

The quoting crosses Bash, SSH, Windows command parsing, and PowerShell. `$`,
quotes, and script blocks are easy to corrupt.

Prefer this pattern:

1. Generate a local `.ps1`.
2. Copy it to `C:\ARL\DOSBox-X-ARL\_remote\`.
3. Execute with `powershell -NoProfile -ExecutionPolicy Bypass -File`.

Helper:

```powershell
pwsh -NoProfile -File contrib/arl/Invoke-ArlHpRemoteScript.ps1 `
  -LocalScriptPath /tmp/my-arl-task.ps1
```

## Shortcut Rules

- Create shortcuts as `.lnk` in `C:\Users\Public\Desktop`.
- Point shortcuts to `.cmd` wrappers, not directly to `.ps1`, so they do not
  show as raw PowerShell files and can leave a console open on failure.
- Working directory should be `C:\ARL\DOSBox-X-ARL`.
- Use the DOSBox-X executable icon when present:

```powershell
C:\ARL\DOSBox-X-ARL\dosbox-x-arl-96994b1.exe,0
```

## Quick Verification

Run remote script verification instead of inline one-liners when checking
shortcuts:

```powershell
$wsh = New-Object -ComObject WScript.Shell
Get-ChildItem 'C:\Users\Public\Desktop' -Filter 'ARL IMPACT+ *.lnk' |
  ForEach-Object {
    $s = $wsh.CreateShortcut($_.FullName)
    [pscustomobject]@{ Name = $_.Name; Target = $s.TargetPath; Exists = Test-Path $s.TargetPath }
  }
```
