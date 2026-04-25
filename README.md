# AutoWindows
PowerShell script to quickly deploy and roll back a Windows penetration testing lab configuration with reduced security controls for internal testing environments.
# Atom Windows Penetration Testing Test Box Setup

This repository contains a menu-driven PowerShell script for configuring a Windows host as an internal penetration testing test box. It can also roll back the changes when testing is complete.

> **Warning**
> This script intentionally weakens or disables multiple Windows security controls during deployment. Use it only on authorized, isolated, internal lab systems. Do not run it on production systems, domain controllers, employee workstations, internet-facing hosts, or unmanaged networks.

## Purpose

The script helps prepare a Windows test box for authorized penetration testing, malware simulation, payload testing, exploit validation, tooling validation, and other internal lab activities.

It provides a simple front-end menu with options to:

1. Deploy the lab configuration
2. Roll back the lab configuration
3. Show the current status of key settings
4. Exit

## What Deploy Mode Changes

Deploy mode applies the following lab-oriented settings:

- Sets the PowerShell execution policy to `Unrestricted`
- Disables UAC elevation prompts for local administrators
- Disables Windows Firewall for Domain, Public, and Private profiles
- Adds a Microsoft Defender exclusion for the `X:\` drive
- Disables Microsoft Defender real-time monitoring
- Sets Microsoft Defender policy registry values to disable antivirus/antispyware behavior
- Sets the system time zone to Eastern Standard Time
- Changes power settings to keep the system awake during testing
- Disables Bluetooth network adapters
- Disables the Windows News and Interests taskbar widget for the current user
- Disables IPv6 bindings on all network adapters
- Disables and stops the Windows Update service

## What Rollback Mode Changes

Rollback mode attempts to reverse the deployment changes by applying safer default-style settings:

- Sets the PowerShell execution policy to `RemoteSigned`
- Restores default UAC consent prompts for local administrators
- Re-enables Windows Firewall for Domain, Public, and Private profiles
- Removes the Microsoft Defender exclusion for `X:\`
- Re-enables Microsoft Defender real-time monitoring
- Removes the Defender policy registry values created by deploy mode
- Restores common balanced/default-style power settings
- Re-enables Bluetooth network adapters
- Re-enables the Windows News and Interests taskbar widget for the current user
- Re-enables IPv6 bindings on all network adapters
- Sets Windows Update to manual/demand start and starts the service

## Important Rollback Notes

Rollback mode is a best-effort reversal. It does not track the exact pre-deployment state of every setting.

For example:

- Bluetooth adapters with `bluetooth` in the name are re-enabled, even if they were already disabled before deployment.
- Power settings are restored to common default-style values, not necessarily the host's previous custom values.
- Windows Update is set to manual/demand start to avoid overriding environments with custom update policies.
- Defender policy changes may require a reboot before they fully apply.
- Organization-managed systems may have Group Policy, MDM, EDR, or security tooling that overrides these settings.

The safest rollback option is still to revert a VM snapshot or rebuild the test box from a clean image.

## Intended Use

Use this only when all of the following are true:

- You are working in an authorized penetration testing or lab environment
- The target system is an internal test box
- The system is isolated from untrusted networks
- You understand the security impact of each setting
- You have approval to weaken host security controls for testing purposes

## Requirements

- Windows 10, Windows 11, or a compatible Windows Server version
- Local administrator privileges
- Elevated PowerShell session
- Internal network or isolated lab environment

## Usage

1. Open PowerShell as Administrator.
2. Review the script before running it.
3. Execute the script:

```powershell
.\AtomWindowsSetupV0.4.ps1
```

4. Choose an option from the menu:

```text
1. Deploy lab configuration
2. Roll back lab configuration
3. Show current status
4. Exit
```

For safety, deploy and rollback actions require typed confirmation:

- Type `DEPLOY` to deploy the lab configuration
- Type `ROLLBACK` to roll back the lab configuration

## Recommended Deployment Workflow

For repeatable lab builds:

1. Start from a clean Windows VM or dedicated test host.
2. Take a VM snapshot before running the script.
3. Run the script and choose deploy mode.
4. Perform authorized testing.
5. Run rollback mode, revert the VM snapshot, or rebuild the host after testing.

Recommended safeguards:

- Keep the host on an isolated VLAN or lab-only network
- Do not reuse the configured system for production work
- Document when and why the script was run
- Reboot after deployment or rollback if Defender, UAC, or Windows Update behavior does not immediately reflect the change

## Security Impact

Deploy mode makes the system significantly less secure. In particular:

- Disabling Defender may allow malicious files to run without detection
- Disabling Firewall may expose services to the network
- Disabling Windows Update prevents patch installation
- Disabling UAC prompts reduces protection against privilege misuse
- Disabling IPv6 may break modern Windows networking functionality
- Disabling Bluetooth adapters may affect peripherals or wireless lab equipment

These tradeoffs may be acceptable in a controlled penetration testing lab, but they are not appropriate for standard endpoints.

## Troubleshooting

### The script will not run

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\AutoWindows.ps1
```

This changes execution policy only for the current PowerShell process.

### Some settings do not change immediately

Reboot the system. Defender, UAC, service, and registry-policy changes may not fully apply until after restart.

### Defender settings are reverted automatically

The host may be managed by Group Policy, MDM, EDR, or another endpoint security platform. Confirm whether centralized policy is overriding local settings.

### Rollback does not restore the exact original settings

Rollback mode restores safer default-style settings. For exact restoration, use a VM snapshot or rebuild from a clean image.

## Disclaimer

This project is for authorized internal penetration testing and lab use only. You are responsible for ensuring that use of this script complies with your organization’s policies, client authorization, and applicable laws.
