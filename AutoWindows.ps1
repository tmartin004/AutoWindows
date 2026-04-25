<#
.SYNOPSIS
    Menu-driven setup and rollback script for an internal Windows penetration testing test box.

.DESCRIPTION
    This script can either deploy or roll back common lab-oriented Windows configuration
    changes used on an internal penetration testing test box.

    Deploy mode reduces friction for authorized security testing by disabling or relaxing
    several Windows controls that commonly interfere with controlled lab activity.

    Rollback mode attempts to restore safer default-style settings, including Windows
    Firewall, Microsoft Defender preferences/policies, IPv6 bindings, Windows Update,
    UAC prompts, Bluetooth adapters, taskbar feed settings, and common power settings.

    This script is intended for isolated, internal test systems only. Do not use it on
    production systems, user workstations, domain controllers, internet-facing hosts,
    or unmanaged networks.

.NOTES
    Run from an elevated PowerShell session.
    A reboot may be required for some registry and security-policy changes to fully apply.
#>

# -------------------------------------------------------------------------------------------------
# Safety / privilege checks
# -------------------------------------------------------------------------------------------------

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Returns True when the current PowerShell session is running as Administrator.
    #>
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Section {
    <#
    .SYNOPSIS
        Prints a consistent section header for readability during deployment or rollback.
    #>
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Pause-ForReview {
    <#
    .SYNOPSIS
        Pauses the menu before returning to the main prompt.
    #>
    Write-Host ""
    Read-Host "Press Enter to return to the menu"
}

# Stop early if the script is not running with local administrator privileges.
if (-not (Test-IsAdministrator)) {
    Write-Error "This script must be run from an elevated PowerShell session. Right-click PowerShell and choose 'Run as administrator'."
    exit 1
}

# -------------------------------------------------------------------------------------------------
# Deployment functions
# -------------------------------------------------------------------------------------------------

function Deploy-AtomWindowsLabConfig {
    <#
    .SYNOPSIS
        Applies internal penetration testing lab configuration changes.
    #>

    Write-Section "Deploying internal pentest test box configuration"

    # Allow local PowerShell scripts to run without execution policy prompts.
    # Lab note: Unrestricted is convenient for test boxes but should not be used on production endpoints.
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force

    # Disable UAC elevation prompts for local administrators.
    # Lab note: This makes automation easier but reduces protection against accidental or malicious elevation.
    Set-ItemProperty -Path REGISTRY::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorAdmin -Value 0

    # Disable Windows Firewall across Domain, Public, and Private profiles.
    # Lab note: Use only on isolated internal networks where exposure is controlled.
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

    # Add a Microsoft Defender exclusion for the X:\ drive.
    # Lab note: Use this for mounted tooling, payload staging, or test artifacts in a controlled lab.
    Add-MpPreference -ExclusionPath X:\ -ErrorAction SilentlyContinue

    # Disable Microsoft Defender real-time monitoring.
    # Lab note: This prevents Defender from interfering with authorized testing tools and payloads.
    Set-MpPreference -DisableRealtimeMonitoring $true -Force

    # Disable Microsoft Defender AntiSpyware by policy.
    # Lab note: This policy-based setting may persist across reboots and should be reverted before reuse outside the lab.
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware' -Value 1 -PropertyType DWord -Force | Out-Null

    # Disable Microsoft Defender Antivirus by policy.
    # Lab note: This intentionally weakens endpoint protection for controlled testing scenarios.
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiVirus' -Value 1 -PropertyType DWord -Force | Out-Null

    # Prevent the Defender service keep-alive behavior from restoring protection automatically.
    # Lab note: This supports repeatable lab behavior but should not be applied to normal workstations.
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'ServiceKeepAlive' -Value 0 -PropertyType DWord -Force | Out-Null

    # Set the system time zone to Eastern Standard Time.
    # Lab note: Adjust this value if your reporting, logs, or team operate in a different time zone.
    Set-TimeZone -Name "Eastern Standard Time"

    # Configure power settings to keep the test box available during longer assessments.
    # AC monitor timeout: 60 minutes
    # Battery monitor timeout: never
    # AC sleep timeout: never
    # Battery sleep timeout: never
    Powercfg /Change monitor-timeout-ac 60
    Powercfg /Change monitor-timeout-dc 0
    Powercfg /Change standby-timeout-ac 0
    Powercfg /Change standby-timeout-dc 0

    # Disable Bluetooth network adapters.
    # Lab note: Reduces unnecessary wireless attack surface and prevents accidental peripheral connections.
    Get-NetAdapter | Where-Object { $_.Name -like "*bluetooth*" } | Disable-NetAdapter -Confirm:$false

    # Disable the Windows News and Interests taskbar widget for the current user.
    # Value reference: 0 = show icon/text, 1 = show icon only, 2 = disabled.
    $feedsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"
    if (Test-Path $feedsPath) {
        Set-ItemProperty -Path $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value 2
    }

    # Disable IPv6 on all network adapters.
    # Lab note: This can simplify IPv4-only lab testing, but may break services that depend on IPv6.
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6

    # Disable and stop the Windows Update service.
    # Lab note: This helps preserve a stable test configuration, but the host will stop receiving patches.
    sc.exe config wuauserv start= disabled | Out-Host
    sc.exe stop wuauserv | Out-Host

    Write-Host "`nDeployment complete. Reboot the system if any Defender, UAC, or service-policy changes do not appear to apply immediately." -ForegroundColor Green
}

# -------------------------------------------------------------------------------------------------
# Rollback functions
# -------------------------------------------------------------------------------------------------

function Rollback-AtomWindowsLabConfig {
    <#
    .SYNOPSIS
        Attempts to reverse the internal penetration testing lab configuration changes.
    #>

    Write-Section "Rolling back internal pentest test box configuration"

    # Restore a safer PowerShell execution policy for general Windows use.
    # Note: RemoteSigned is a common default-style policy for administrative systems.
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

    # Re-enable default UAC elevation prompts for local administrators.
    # Value 5 is the Windows default: prompt for consent for non-Windows binaries.
    Set-ItemProperty -Path REGISTRY::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorAdmin -Value 5

    # Re-enable Windows Firewall across Domain, Public, and Private profiles.
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

    # Remove the Microsoft Defender exclusion for X:\ if it exists.
    # This prevents the drive from remaining exempt from security scanning after lab use.
    Remove-MpPreference -ExclusionPath X:\ -ErrorAction SilentlyContinue

    # Re-enable Microsoft Defender real-time monitoring.
    Set-MpPreference -DisableRealtimeMonitoring $false -Force

    # Remove Defender policy values created during deployment.
    # Removing the values allows Windows/organizational policy to control Defender normally again.
    $defenderPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (Test-Path $defenderPolicyPath) {
        Remove-ItemProperty -Path $defenderPolicyPath -Name 'DisableAntiSpyware' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $defenderPolicyPath -Name 'DisableAntiVirus' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $defenderPolicyPath -Name 'ServiceKeepAlive' -ErrorAction SilentlyContinue
    }

    # Re-apply Eastern Standard Time as a known value.
    # Change this manually if the host should use a different local time zone after testing.
    Set-TimeZone -Name "Eastern Standard Time"

    # Restore common balanced/default-style power settings.
    # AC monitor timeout: 10 minutes
    # Battery monitor timeout: 5 minutes
    # AC sleep timeout: 30 minutes
    # Battery sleep timeout: 15 minutes
    Powercfg /Change monitor-timeout-ac 10
    Powercfg /Change monitor-timeout-dc 5
    Powercfg /Change standby-timeout-ac 30
    Powercfg /Change standby-timeout-dc 15

    # Re-enable Bluetooth network adapters that were disabled by deployment.
    # Note: This enables all adapters with "bluetooth" in the name, even if one was disabled before deployment.
    Get-NetAdapter | Where-Object { $_.Name -like "*bluetooth*" } | Enable-NetAdapter -Confirm:$false

    # Restore the Windows News and Interests taskbar widget for the current user.
    # Value reference: 0 = show icon/text, 1 = show icon only, 2 = disabled.
    $feedsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"
    if (Test-Path $feedsPath) {
        Set-ItemProperty -Path $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value 0
    }

    # Re-enable IPv6 bindings on all network adapters.
    Enable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6

    # Re-enable Windows Update and start the service.
    # Demand start is a safer rollback than forcing Automatic in environments with custom update policy.
    sc.exe config wuauserv start= demand | Out-Host
    sc.exe start wuauserv | Out-Host

    Write-Host "`nRollback complete. Reboot the system to ensure Defender policy, UAC, and service changes fully apply." -ForegroundColor Green
}

function Show-CurrentStatus {
    <#
    .SYNOPSIS
        Displays a quick status summary for key settings controlled by this script.
    #>

    Write-Section "Current configuration summary"

    Write-Host "Execution Policy:" -ForegroundColor Yellow
    Get-ExecutionPolicy -List

    Write-Host "`nUAC ConsentPromptBehaviorAdmin:" -ForegroundColor Yellow
    Get-ItemProperty -Path REGISTRY::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorAdmin | Select-Object ConsentPromptBehaviorAdmin

    Write-Host "`nFirewall Profiles:" -ForegroundColor Yellow
    Get-NetFirewallProfile -Profile Domain,Public,Private | Select-Object Name, Enabled

    Write-Host "`nDefender Preferences:" -ForegroundColor Yellow
    Get-MpPreference | Select-Object DisableRealtimeMonitoring, ExclusionPath

    Write-Host "`nDefender Policy Registry Values:" -ForegroundColor Yellow
    $defenderPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (Test-Path $defenderPolicyPath) {
        Get-ItemProperty -Path $defenderPolicyPath | Select-Object DisableAntiSpyware, DisableAntiVirus, ServiceKeepAlive
    } else {
        Write-Host "No Defender policy path found."
    }

    Write-Host "`nIPv6 Adapter Bindings:" -ForegroundColor Yellow
    Get-NetAdapterBinding -ComponentID ms_tcpip6 | Select-Object Name, Enabled

    Write-Host "`nWindows Update Service:" -ForegroundColor Yellow
    Get-Service wuauserv | Select-Object Name, Status, StartType
}

# -------------------------------------------------------------------------------------------------
# Front-end menu
# -------------------------------------------------------------------------------------------------

function Show-MainMenu {
    <#
    .SYNOPSIS
        Presents a simple front-end menu for deploy, rollback, status, or exit.
    #>

    do {
        Clear-Host
        Write-Host "Atom Windows Internal Pentest Test Box Setup" -ForegroundColor Cyan
        Write-Host "================================================"
        Write-Host "1. Deploy lab configuration"
        Write-Host "2. Roll back lab configuration"
        Write-Host "3. Show current status"
        Write-Host "4. Exit"
        Write-Host ""
        Write-Host "Use only on authorized, internal, isolated test systems." -ForegroundColor Yellow
        Write-Host ""

        $choice = Read-Host "Select an option [1-4]"

        switch ($choice) {
            "1" {
                $confirm = Read-Host "Deploy will weaken host security controls for lab use. Type DEPLOY to continue"
                if ($confirm -eq "DEPLOY") {
                    Deploy-AtomWindowsLabConfig
                } else {
                    Write-Host "Deployment cancelled." -ForegroundColor Yellow
                }
                Pause-ForReview
            }
            "2" {
                $confirm = Read-Host "Rollback will attempt to restore safer settings. Type ROLLBACK to continue"
                if ($confirm -eq "ROLLBACK") {
                    Rollback-AtomWindowsLabConfig
                } else {
                    Write-Host "Rollback cancelled." -ForegroundColor Yellow
                }
                Pause-ForReview
            }
            "3" {
                Show-CurrentStatus
                Pause-ForReview
            }
            "4" {
                Write-Host "Exiting."
            }
            default {
                Write-Host "Invalid selection." -ForegroundColor Red
                Pause-ForReview
            }
        }
    } while ($choice -ne "4")
}

Show-MainMenu
