# AutoWindows

A menu-driven PowerShell script for deploying and rolling back lab-oriented Windows configuration changes on an internal penetration testing test box.

> ⚠️ **For isolated, internal test systems only.** Do not use on production systems, user workstations, domain controllers, internet-facing hosts, or unmanaged networks.

---

## Features

- **Deploy** — weakens security controls to reduce friction for authorized lab testing
- **Rollback** — restores original settings captured at deploy time (not just hardcoded defaults)
- **Status view** — snapshot of every setting this script manages
- **Run summary** — colour-coded pass/fail table shown after every deploy or rollback
- **Transcript logging** — each run writes a timestamped `.log` file alongside the script

---

## Requirements

| Requirement | Detail |
|---|---|
| OS | Windows 10 / 11 or Windows Server 2016+ |
| PowerShell | 5.1 or later |
| Privileges | Must be run from an **elevated** (Administrator) session |

---

## Usage

1. Right-click PowerShell and choose **Run as administrator**.
2. Navigate to the directory containing the script.
3. Run:

```powershell
.\AutoWindows.ps1
```

4. Select an option from the menu:

```
Atom Windows Internal Pentest Test Box Setup
================================================
1. Deploy lab configuration
2. Roll back lab configuration
3. Show current status
4. Exit
```

Both **Deploy** and **Rollback** require you to type a confirmation word (`DEPLOY` or `ROLLBACK`) before making any changes.

---

## What Deploy Does

| Setting | Change |
|---|---|
| PowerShell Execution Policy | `Unrestricted` (LocalMachine scope) |
| UAC elevation prompt | Disabled (`ConsentPromptBehaviorAdmin = 0`) |
| Windows Firewall | Disabled on Domain, Public, and Private profiles |
| Microsoft Defender real-time monitoring | Disabled |
| Defender policy keys | `DisableAntiSpyware`, `DisableAntiVirus`, `ServiceKeepAlive` set via registry |
| Defender exclusion | `X:\` added (intentional — used for tool staging) |
| Time zone | Set to Eastern Standard Time |
| Power timeouts (AC) | Monitor: 60 min, Sleep: never |
| Power timeouts (battery) | Monitor: never, Sleep: never |
| Bluetooth adapters | Disabled |
| News/Interests taskbar widget | Disabled |
| IPv6 bindings | Disabled on all adapters |
| Windows Update service | Stopped and set to `disabled` |

A snapshot of the **original** values is saved to `lab_snapshot.json` in the same directory before any changes are made.

---

## What Rollback Does

Rollback reads `lab_snapshot.json` and restores the **original** values captured at deploy time. If no snapshot exists, it falls back to the safe defaults listed below.

| Setting | Fallback default (no snapshot) |
|---|---|
| Execution Policy | `RemoteSigned` |
| UAC elevation prompt | `5` (Windows default: consent for non-Windows binaries) |
| Windows Firewall | Re-enabled on all profiles |
| Defender real-time monitoring | Re-enabled |
| Defender policy keys | Removed |
| Defender exclusion `X:\` | Removed |
| Time zone | Eastern Standard Time |
| Power timeouts (AC) | Monitor: 10 min, Sleep: 30 min |
| Power timeouts (battery) | Monitor: 5 min, Sleep: 15 min |
| Bluetooth adapters | Re-enabled (snapshot-recorded adapters only) |
| News/Interests widget | Restored to `0` (icon + text) |
| IPv6 bindings | Re-enabled on all adapters |
| Windows Update service | Set to `demand` start and started |

> **Note:** Windows Update is restored to `demand` start rather than `automatic` to avoid overriding custom update policies in managed environments.

---

## Files Created at Runtime

| File | Description |
|---|---|
| `lab_snapshot.json` | Pre-deploy settings snapshot; used by rollback to restore original values |
| `AutoWindows_YYYYMMDD_HHmmss.log` | PowerShell transcript for each run |

Both files are written to the same directory as the script.

---

## Run Summary

After every deploy or rollback, a colour-coded summary is printed:

```
=== Run Summary ===
[OK]   Set ExecutionPolicy: Unrestricted
[OK]   Disable UAC prompt (ConsentPromptBehaviorAdmin=0)
[FAIL] Disable Windows Firewall (all profiles) — Access denied
...
Completed: 14 succeeded, 1 failed.
```

Failed steps include an error detail to aid troubleshooting. All output is also captured in the transcript log.

---

## Notes

- A **reboot** may be required for Defender policy, UAC, and service-related changes to fully take effect.
- The `X:\` Defender exclusion is added unconditionally during deploy regardless of whether the drive is mounted. This is intentional — the drive is typically attached after configuration.
- Bluetooth rollback re-enables only the adapters recorded in the snapshot. If deploy was run without a prior snapshot, all adapters matching `*bluetooth*` are re-enabled, which may include adapters that were already disabled before the script ran.
- This script does **not** back up or restore Windows Firewall rules — only the enabled/disabled state of each profile.

---

## License

For internal lab use only. Review your organization's policies before use.
