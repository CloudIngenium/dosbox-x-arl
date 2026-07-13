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

## 2026-07-08 Remote Access Repair

During the SIMPLE386 matrix deployment attempt, the first remote attempts looked
broken because they mixed fragile Windows paths, inline PowerShell quoting, and
Arc Run Command. The durable working path is:

- SSH key auth to `svc-claude@LABORATORIO-ARL`.
- Remote command probe through explicit `cmd.exe`:

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/svc-claude \
  svc-claude@LABORATORIO-ARL 'C:\Windows\System32\cmd.exe /c hostname'
```

- File transfer through SFTP-style Windows paths. Use `/C:/...`, not `C:/...`:

```bash
sftp -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/svc-claude \
  svc-claude@LABORATORIO-ARL
sftp> put local-file.zip /C:/ARL/DOSBox-X-ARL/_remote/local-file.zip
```

- Remote PowerShell through `-EncodedCommand`, never raw inline quoting.
  `contrib/arl/Invoke-ArlHpRemoteScript.ps1` now does this automatically.

Verification:

```powershell
pwsh -NoProfile -File contrib/arl/Test-ArlHpRemoteAccess.ps1
```

Expected checks:

- `ssh-cmd`
- `ssh-powershell-encoded`
- `remote-directory`
- `sftp-put-ls-rm`

Avoid Azure Arc Run Command for this HP unless SSH/SFTP are genuinely
unavailable. Arc may still show confusing `Succeeded` states while the embedded
PowerShell host writes errors, and it is slower than direct SSH/SFTP.

Manual install fallback:

1. Copy `arl-toolkit-simple386-matrix-20260708.zip` to the HP.
2. Extract it over `C:\ARL\DOSBox-X-ARL`.
3. From an interactive PowerShell window on the HP, run:

```powershell
C:\ARL\DOSBox-X-ARL\Create-ArlHpShortcuts.ps1
```

This creates only the no-rebuild operator shortcuts. Pass
`-IncludeBuildRequired` only after a build containing the ARL modem-line options
is installed:

```powershell
C:\ARL\DOSBox-X-ARL\Create-ArlHpShortcuts.ps1 -IncludeBuildRequired
```

Current status after repair:

- `arl-toolkit-simple386-matrix-20260708.zip` was uploaded to
  `C:\ARL\DOSBox-X-ARL\_remote`.
- The toolkit was expanded over `C:\ARL\DOSBox-X-ARL`.
- A backup was created under `C:\ARL\DOSBox-X-ARL\_backups`.
- Build `9663306eb639` was installed as both:
  - `C:\ARL\DOSBox-X-ARL\dosbox-x-arl-9663306.exe`
  - `C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe`
- The previous default executable hash
  `499A1F9D992F28CD022429F6F2CCAAFA0F03D898F68B606B7659CA29819571DA`
  was backed up under `C:\ARL\DOSBox-X-ARL\_backups\exe-20260708-220943`.
- Operator shortcuts under `C:\Users\Public\Desktop` are intentionally short and
  numbered. `Create-ArlHpShortcuts.ps1` removes old ARL/IMPACT research shortcuts
  and recreates only the active operational sequence:
  - `00 DIRECTSERIAL BYPASS`
  - `01 PRECHECK`
  - `02 REACTIVE SAFE`
  - `03 APPROVE LAST REPORT`
  - `04 STANDARDIZATION PASSIVE`
  - `05 NORMALIZATION PASSIVE`
  - `90 EMULATOR`
  - `Diagnostics - Serial Traces`
- `01 PRECHECK` only reads PnP/SERIALCOMM, process, disk, Agent health and Epson
  state. It never opens COM5.
- `03 APPROVE LAST REPORT` refuses zero or multiple pending reports, re-hashes
  the selected report, and requires the operator to type `APROBAR`.
- The no-launch verification directories were removed so they do not appear as
  real ARL diagnostic runs.
- Emulator shortcuts are hardware-safe: they use DOSBox-X `nullmodem` on
  `127.0.0.1:3460` and must not contain `directserial`, `realport`, or `COM5`.

## Avoid Inline PowerShell Quoting

Avoid this pattern for anything non-trivial:

```bash
ssh svc-claude@LABORATORIO-ARL 'powershell -Command "... $variables ... $_ ..."'
```

The quoting crosses Bash, SSH, Windows command parsing, and PowerShell. `$`,
quotes, and script blocks are easy to corrupt.

Prefer this pattern:

1. Generate a local `.ps1`.
2. Copy it to `/C:/ARL/DOSBox-X-ARL/_remote/` through SFTP/SCP.
3. Execute it through remote PowerShell `-EncodedCommand`.

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
C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe,0
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
