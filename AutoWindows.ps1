<#
.SYNOPSIS
    Menu-driven setup and rollback script for an internal Windows penetration testing test box.

.DESCRIPTION
    This script can either deploy or roll back common lab-oriented Windows configuration
    changes used on an internal penetration testing test box.

    Deploy mode reduces friction for authorized security testing by disabling or relaxing
    several Windows controls that commonly interfere with controlled lab activity. A snapshot
    of pre-deploy settings is saved to lab_snapshot.json so that rollback can restore the
    actual original values rather than hardcoded defaults.

    Rollback mode restores settings from the snapshot where available, falling back to
    safe defaults for any value not captured at deploy time.

    This script is intended for isolated, internal test systems only. Do not use it on
    production systems, user workstations, domain controllers, internet-facing hosts,
    or unmanaged networks.

.NOTES
    Run from an elevated PowerShell session.
    A reboot may be required for some registry and security-policy changes to fully apply.
    A transcript log is written to the same directory as this script on each run.
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
# Transcript logging
# -------------------------------------------------------------------------------------------------

$transcriptPath = Join-Path $PSScriptRoot "AutoWindows_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -Append | Out-Null
Write-Host "Transcript logging to: $transcriptPath" -ForegroundColor DarkGray

# -------------------------------------------------------------------------------------------------
# Result tracking (used for end-of-run summary)
# -------------------------------------------------------------------------------------------------

# Each entry: [string]StepName, [bool]Success, [string]Detail
$script:RunResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Result {
    param(
        [string]$Step,
        [bool]$Success,
        [string]$Detail = ""
    )
    $script:RunResults.Add([PSCustomObject]@{
        Step    = $Step
        Success = $Success
        Detail  = $Detail
    })
}

function Show-RunSummary {
    <#
    .SYNOPSIS
        Displays a colour-coded summary table of every step attempted in the last operation.
    #>
    if ($script:RunResults.Count -eq 0) { return }

    Write-Section "Run Summary"

    $succeeded = $script:RunResults | Where-Object { $_.Success }
    $failed    = $script:RunResults | Where-Object { -not $_.Success }

    foreach ($r in $script:RunResults) {
        if ($r.Success) {
            $icon  = "[OK]  "
            $color = "Green"
        } else {
            $icon  = "[FAIL]"
            $color = "Red"
        }
        $line = "$icon $($r.Step)"
        if ($r.Detail) { $line += " — $($r.Detail)" }
        Write-Host $line -ForegroundColor $color
    }

    Write-Host ""
    Write-Host ("Completed: {0} succeeded, {1} failed." -f $succeeded.Count, $failed.Count) -ForegroundColor $(
        if ($failed.Count -gt 0) { "Yellow" } else { "Green" }
    )

    # Reset for next operation
    $script:RunResults.Clear()
}

# -------------------------------------------------------------------------------------------------
# Snapshot helpers
# -------------------------------------------------------------------------------------------------

$snapshotPath = Join-Path $PSScriptRoot "lab_snapshot.json"

function Save-LabSnapshot {
    <#
    .SYNOPSIS
        Captures pre-deploy settings to JSON so rollback can restore actual values.
    #>
    Write-Host "  Capturing pre-deploy snapshot..." -ForegroundColor DarkGray

    try {
        $uacVal = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -Name ConsentPromptBehaviorAdmin -ErrorAction Stop).ConsentPromptBehaviorAdmin
    } catch { $uacVal = 5 }

    try {
        $execPolicy = (Get-ExecutionPolicy -Scope LocalMachine).ToString()
    } catch { $execPolicy = "RemoteSigned" }

    try {
        $feedsVal = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" `
            -Name ShellFeedsTaskbarViewMode -ErrorAction Stop).ShellFeedsTaskbarViewMode
    } catch { $feedsVal = 0 }

    try {
        $tz = (Get-TimeZone).Id
    } catch { $tz = "Eastern Standard Time" }

    try {
        $btAdapters = @(
            Get-NetAdapter |
            Where-Object { $_.Name -like "*bluetooth*" } |
            Select-Object -ExpandProperty Name
        )
    } catch { $btAdapters = @() }

    $snapshot = @{
        CapturedAt              = (Get-Date -Format "o")
        ExecutionPolicy         = $execPolicy
        UACConsentPrompt        = $uacVal
        FeedsTaskbarViewMode    = $feedsVal
        TimeZone                = $tz
        BluetoothAdapterNames   = $btAdapters
    }

    try {
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $snapshotPath -Encoding UTF8
        Write-Host "  Snapshot saved to $snapshotPath" -ForegroundColor DarkGray
        Add-Result -Step "Save pre-deploy snapshot" -Success $true
    } catch {
        Write-Warning "  Could not save snapshot: $_"
        Add-Result -Step "Save pre-deploy snapshot" -Success $false -Detail $_
    }
}

function Get-LabSnapshot {
    <#
    .SYNOPSIS
        Loads the snapshot from disk; returns $null if none exists.
    #>
    if (-not (Test-Path $snapshotPath)) { return $null }
    try {
        return (Get-Content -Path $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Warning "Could not read snapshot file: $_"
        return $null
    }
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
    $script:RunResults.Clear()

    # Capture original settings before making any changes.
    Save-LabSnapshot

    # -- Execution Policy -----------------------------------------------------------------
    try {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Stop
        Add-Result -Step "Set ExecutionPolicy: Unrestricted" -Success $true
    } catch {
        Write-Warning "ExecutionPolicy change failed: $_"
        Add-Result -Step "Set ExecutionPolicy: Unrestricted" -Success $false -Detail $_
    }

    # -- UAC ------------------------------------------------------------------------------
    # Disable UAC elevation prompts for local administrators.
    # Lab note: This makes automation easier but reduces protection against accidental or malicious elevation.
    try {
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -Name ConsentPromptBehaviorAdmin -Value 0 -ErrorAction Stop
        Add-Result -Step "Disable UAC prompt (ConsentPromptBehaviorAdmin=0)" -Success $true
    } catch {
        Write-Warning "UAC change failed: $_"
        Add-Result -Step "Disable UAC prompt (ConsentPromptBehaviorAdmin=0)" -Success $false -Detail $_
    }

    # -- Windows Firewall -----------------------------------------------------------------
    # Lab note: Use only on isolated internal networks where exposure is controlled.
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction Stop
        Add-Result -Step "Disable Windows Firewall (all profiles)" -Success $true
    } catch {
        Write-Warning "Firewall change failed: $_"
        Add-Result -Step "Disable Windows Firewall (all profiles)" -Success $false -Detail $_
    }

    # -- Defender: X:\ exclusion ----------------------------------------------------------
    # Lab note: X:\ is used for mounted tooling, payload staging, or test artifacts.
    # The X:\ exclusion is intentional regardless of whether the drive is currently mounted.
    try {
        Add-MpPreference -ExclusionPath "X:\" -ErrorAction Stop
        Add-Result -Step "Add Defender exclusion: X:\" -Success $true
    } catch {
        Write-Warning "Defender exclusion (X:\) failed: $_"
        Add-Result -Step "Add Defender exclusion: X:\" -Success $false -Detail $_
    }

    # -- Defender: real-time monitoring ---------------------------------------------------
    # Lab note: Prevents Defender from interfering with authorized testing tools and payloads.
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction Stop
        Add-Result -Step "Disable Defender real-time monitoring" -Success $true
    } catch {
        Write-Warning "Defender real-time monitoring change failed: $_"
        Add-Result -Step "Disable Defender real-time monitoring" -Success $false -Detail $_
    }

    # -- Defender: policy registry keys ---------------------------------------------------
    # Lab note: These policy-based settings persist across reboots; revert before reuse outside the lab.
    $defenderPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    foreach ($entry in @(
        @{ Name = "DisableAntiSpyware"; Value = 1 },
        @{ Name = "DisableAntiVirus";   Value = 1 },
        @{ Name = "ServiceKeepAlive";   Value = 0 }
    )) {
        try {
            New-ItemProperty -Path $defenderPolicyPath -Name $entry.Name -Value $entry.Value `
                -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Add-Result -Step "Set Defender policy: $($entry.Name)=$($entry.Value)" -Success $true
        } catch {
            Write-Warning "Defender policy key '$($entry.Name)' failed: $_"
            Add-Result -Step "Set Defender policy: $($entry.Name)=$($entry.Value)" -Success $false -Detail $_
        }
    }

    # -- Time zone ------------------------------------------------------------------------
    # Lab note: Adjust if your reporting, logs, or team operate in a different time zone.
    try {
        Set-TimeZone -Name "Eastern Standard Time" -ErrorAction Stop
        Add-Result -Step "Set time zone: Eastern Standard Time" -Success $true
    } catch {
        Write-Warning "Time zone change failed: $_"
        Add-Result -Step "Set time zone: Eastern Standard Time" -Success $false -Detail $_
    }

    # -- Power settings -------------------------------------------------------------------
    # AC monitor timeout: 60 min | Battery monitor timeout: never
    # AC sleep: never            | Battery sleep: never
    $powerSettings = @(
        @{ Flag = "monitor-timeout-ac"; Value = 60  },
        @{ Flag = "monitor-timeout-dc"; Value = 0   },
        @{ Flag = "standby-timeout-ac"; Value = 0   },
        @{ Flag = "standby-timeout-dc"; Value = 0   }
    )
    foreach ($ps in $powerSettings) {
        try {
            $result = Powercfg /Change $ps.Flag $ps.Value 2>&1
            if ($LASTEXITCODE -ne 0) { throw "powercfg exit code $LASTEXITCODE`: $result" }
            Add-Result -Step "Power: $($ps.Flag)=$($ps.Value)" -Success $true
        } catch {
            Write-Warning "Power setting '$($ps.Flag)' failed: $_"
            Add-Result -Step "Power: $($ps.Flag)=$($ps.Value)" -Success $false -Detail $_
        }
    }

    # -- Bluetooth ------------------------------------------------------------------------
    # Lab note: Reduces unnecessary wireless attack surface and prevents accidental peripheral connections.
    try {
        $btAdapters = @(Get-NetAdapter | Where-Object { $_.Name -like "*bluetooth*" })
        if ($btAdapters.Count -gt 0) {
            $btAdapters | Disable-NetAdapter -Confirm:$false -ErrorAction Stop
            Add-Result -Step "Disable Bluetooth adapter(s) ($($btAdapters.Count) found)" -Success $true
        } else {
            Add-Result -Step "Disable Bluetooth adapters" -Success $true -Detail "None found — skipped"
        }
    } catch {
        Write-Warning "Bluetooth disable failed: $_"
        Add-Result -Step "Disable Bluetooth adapter(s)" -Success $false -Detail $_
    }

    # -- News/Interests taskbar widget ----------------------------------------------------
    # Value: 0 = icon+text, 1 = icon only, 2 = disabled
    $feedsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"
    try {
        if (Test-Path $feedsPath) {
            Set-ItemProperty -Path $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value 2 -ErrorAction Stop
            Add-Result -Step "Disable taskbar News/Interests widget" -Success $true
        } else {
            Add-Result -Step "Disable taskbar News/Interests widget" -Success $true -Detail "Registry path not found — skipped"
        }
    } catch {
        Write-Warning "Taskbar feeds change failed: $_"
        Add-Result -Step "Disable taskbar News/Interests widget" -Success $false -Detail $_
    }

    # -- IPv6 -----------------------------------------------------------------------------
    # Lab note: Simplifies IPv4-only lab testing; may break services that depend on IPv6.
    try {
        Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6 -ErrorAction Stop
        Add-Result -Step "Disable IPv6 on all adapters" -Success $true
    } catch {
        Write-Warning "IPv6 disable failed: $_"
        Add-Result -Step "Disable IPv6 on all adapters" -Success $false -Detail $_
    }

    # -- Windows Update service -----------------------------------------------------------
    # Lab note: Preserves a stable test configuration; the host will stop receiving patches.
    foreach ($op in @(
        @{ Desc = "Disable Windows Update service (start=disabled)"; Args = @("config","wuauserv","start=","disabled") },
        @{ Desc = "Stop Windows Update service";                     Args = @("stop","wuauserv") }
    )) {
        try {
            $output = & sc.exe @($op.Args) 2>&1
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1062) {
                # 1062 = service not started (acceptable for stop)
                throw "sc.exe exit code $LASTEXITCODE`: $output"
            }
            Add-Result -Step $op.Desc -Success $true
        } catch {
            Write-Warning "$($op.Desc) failed: $_"
            Add-Result -Step $op.Desc -Success $false -Detail $_
        }
    }

    Write-Host "`nDeployment complete. Reboot the system if any Defender, UAC, or service-policy changes do not appear to apply immediately." -ForegroundColor Green
    Show-RunSummary
}

# -------------------------------------------------------------------------------------------------
# Rollback functions
# -------------------------------------------------------------------------------------------------

function Restore-AtomWindowsLabConfig {
    <#
    .SYNOPSIS
        Attempts to reverse the internal penetration testing lab configuration changes,
        restoring original values from the snapshot where available.
    #>

    Write-Section "Rolling back internal pentest test box configuration"
    $script:RunResults.Clear()

    $snapshot = Get-LabSnapshot
    if ($snapshot) {
        Write-Host "  Snapshot found (captured $($snapshot.CapturedAt)) — restoring original values." -ForegroundColor DarkGray
    } else {
        Write-Warning "No snapshot found at '$snapshotPath'. Falling back to safe hardcoded defaults."
    }

    # -- Execution Policy -----------------------------------------------------------------
    $targetPolicy = if ($snapshot) { $snapshot.ExecutionPolicy } else { "RemoteSigned" }
    try {
        Set-ExecutionPolicy -ExecutionPolicy $targetPolicy -Scope LocalMachine -Force -ErrorAction Stop
        Add-Result -Step "Restore ExecutionPolicy: $targetPolicy" -Success $true
    } catch {
        Write-Warning "ExecutionPolicy restore failed: $_"
        Add-Result -Step "Restore ExecutionPolicy: $targetPolicy" -Success $false -Detail $_
    }

    # -- UAC ------------------------------------------------------------------------------
    # Default value 5 = prompt for consent for non-Windows binaries.
    $targetUAC = if ($snapshot) { $snapshot.UACConsentPrompt } else { 5 }
    try {
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -Name ConsentPromptBehaviorAdmin -Value $targetUAC -ErrorAction Stop
        Add-Result -Step "Restore UAC prompt (ConsentPromptBehaviorAdmin=$targetUAC)" -Success $true
    } catch {
        Write-Warning "UAC restore failed: $_"
        Add-Result -Step "Restore UAC prompt (ConsentPromptBehaviorAdmin=$targetUAC)" -Success $false -Detail $_
    }

    # -- Windows Firewall -----------------------------------------------------------------
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
        Add-Result -Step "Re-enable Windows Firewall (all profiles)" -Success $true
    } catch {
        Write-Warning "Firewall restore failed: $_"
        Add-Result -Step "Re-enable Windows Firewall (all profiles)" -Success $false -Detail $_
    }

    # -- Defender: X:\ exclusion ----------------------------------------------------------
    try {
        Remove-MpPreference -ExclusionPath "X:\" -ErrorAction Stop
        Add-Result -Step "Remove Defender exclusion: X:\" -Success $true
    } catch {
        Write-Warning "Defender exclusion removal (X:\) failed: $_"
        Add-Result -Step "Remove Defender exclusion: X:\" -Success $false -Detail $_
    }

    # -- Defender: real-time monitoring ---------------------------------------------------
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction Stop
        Add-Result -Step "Re-enable Defender real-time monitoring" -Success $true
    } catch {
        Write-Warning "Defender real-time monitoring restore failed: $_"
        Add-Result -Step "Re-enable Defender real-time monitoring" -Success $false -Detail $_
    }

    # -- Defender: policy registry keys ---------------------------------------------------
    $defenderPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    foreach ($name in @("DisableAntiSpyware", "DisableAntiVirus", "ServiceKeepAlive")) {
        try {
            if (Test-Path $defenderPolicyPath) {
                Remove-ItemProperty -Path $defenderPolicyPath -Name $name -ErrorAction Stop
            }
            Add-Result -Step "Remove Defender policy key: $name" -Success $true
        } catch {
            Write-Warning "Defender policy key '$name' removal failed: $_"
            Add-Result -Step "Remove Defender policy key: $name" -Success $false -Detail $_
        }
    }

    # -- Time zone ------------------------------------------------------------------------
    # Restore the original time zone from snapshot; fall back to Eastern Standard Time.
    $targetTZ = if ($snapshot -and $snapshot.TimeZone) { $snapshot.TimeZone } else { "Eastern Standard Time" }
    try {
        Set-TimeZone -Name $targetTZ -ErrorAction Stop
        Add-Result -Step "Restore time zone: $targetTZ" -Success $true
    } catch {
        Write-Warning "Time zone restore failed: $_"
        Add-Result -Step "Restore time zone: $targetTZ" -Success $false -Detail $_
    }

    # -- Power settings -------------------------------------------------------------------
    # Restore balanced/default-style values.
    $powerSettings = @(
        @{ Flag = "monitor-timeout-ac"; Value = 10  },
        @{ Flag = "monitor-timeout-dc"; Value = 5   },
        @{ Flag = "standby-timeout-ac"; Value = 30  },
        @{ Flag = "standby-timeout-dc"; Value = 15  }
    )
    foreach ($ps in $powerSettings) {
        try {
            $result = Powercfg /Change $ps.Flag $ps.Value 2>&1
            if ($LASTEXITCODE -ne 0) { throw "powercfg exit code $LASTEXITCODE`: $result" }
            Add-Result -Step "Power: $($ps.Flag)=$($ps.Value)" -Success $true
        } catch {
            Write-Warning "Power setting '$($ps.Flag)' restore failed: $_"
            Add-Result -Step "Power: $($ps.Flag)=$($ps.Value)" -Success $false -Detail $_
        }
    }

    # -- Bluetooth ------------------------------------------------------------------------
    # Re-enable only the adapters that were present (and by implication enabled) before deploy.
    # If no snapshot exists, re-enable all adapters named *bluetooth*.
    # Note: if an adapter was already disabled before deploy, this may unintentionally enable it.
    $btNames = if ($snapshot -and $snapshot.BluetoothAdapterNames) {
        $snapshot.BluetoothAdapterNames
    } else {
        @(Get-NetAdapter | Where-Object { $_.Name -like "*bluetooth*" } | Select-Object -ExpandProperty Name)
    }

    if ($btNames.Count -gt 0) {
        foreach ($name in $btNames) {
            try {
                Enable-NetAdapter -Name $name -Confirm:$false -ErrorAction Stop
                Add-Result -Step "Re-enable Bluetooth adapter: $name" -Success $true
            } catch {
                Write-Warning "Could not re-enable Bluetooth adapter '$name': $_"
                Add-Result -Step "Re-enable Bluetooth adapter: $name" -Success $false -Detail $_
            }
        }
    } else {
        Add-Result -Step "Re-enable Bluetooth adapters" -Success $true -Detail "None recorded in snapshot — skipped"
    }

    # -- News/Interests taskbar widget ----------------------------------------------------
    $targetFeeds = if ($snapshot) { $snapshot.FeedsTaskbarViewMode } else { 0 }
    $feedsPath   = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"
    try {
        if (Test-Path $feedsPath) {
            Set-ItemProperty -Path $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value $targetFeeds -ErrorAction Stop
            Add-Result -Step "Restore taskbar News/Interests widget (mode=$targetFeeds)" -Success $true
        } else {
            Add-Result -Step "Restore taskbar News/Interests widget" -Success $true -Detail "Registry path not found — skipped"
        }
    } catch {
        Write-Warning "Taskbar feeds restore failed: $_"
        Add-Result -Step "Restore taskbar News/Interests widget (mode=$targetFeeds)" -Success $false -Detail $_
    }

    # -- IPv6 -----------------------------------------------------------------------------
    try {
        Enable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6 -ErrorAction Stop
        Add-Result -Step "Re-enable IPv6 on all adapters" -Success $true
    } catch {
        Write-Warning "IPv6 re-enable failed: $_"
        Add-Result -Step "Re-enable IPv6 on all adapters" -Success $false -Detail $_
    }

    # -- Windows Update service -----------------------------------------------------------
    # Use 'demand' start rather than 'auto' to avoid overriding any custom update policy.
    foreach ($op in @(
        @{ Desc = "Set Windows Update service start type: demand"; Args = @("config","wuauserv","start=","demand") },
        @{ Desc = "Start Windows Update service";                  Args = @("start","wuauserv") }
    )) {
        try {
            $output = & sc.exe @($op.Args) 2>&1
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1056) {
                # 1056 = service already running (acceptable for start)
                throw "sc.exe exit code $LASTEXITCODE`: $output"
            }
            Add-Result -Step $op.Desc -Success $true
        } catch {
            Write-Warning "$($op.Desc) failed: $_"
            Add-Result -Step $op.Desc -Success $false -Detail $_
        }
    }

    Write-Host "`nRollback complete. Reboot the system to ensure Defender policy, UAC, and service changes fully apply." -ForegroundColor Green
    Show-RunSummary
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
    Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name ConsentPromptBehaviorAdmin | Select-Object ConsentPromptBehaviorAdmin

    Write-Host "`nFirewall Profiles:" -ForegroundColor Yellow
    Get-NetFirewallProfile -Profile Domain,Public,Private | Select-Object Name, Enabled

    Write-Host "`nDefender Preferences:" -ForegroundColor Yellow
    Get-MpPreference | Select-Object DisableRealtimeMonitoring, ExclusionPath

    Write-Host "`nDefender Policy Registry Values:" -ForegroundColor Yellow
    $defenderPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (Test-Path $defenderPolicyPath) {
        Get-ItemProperty -Path $defenderPolicyPath | Select-Object DisableAntiSpyware, DisableAntiVirus, ServiceKeepAlive
    } else {
        Write-Host "No Defender policy path found."
    }

    Write-Host "`nIPv6 Adapter Bindings:" -ForegroundColor Yellow
    Get-NetAdapterBinding -ComponentID ms_tcpip6 | Select-Object Name, Enabled

    Write-Host "`nBluetooth Adapters:" -ForegroundColor Yellow
    $btAdapters = @(Get-NetAdapter | Where-Object { $_.Name -like "*bluetooth*" })
    if ($btAdapters.Count -gt 0) {
        $btAdapters | Select-Object Name, Status
    } else {
        Write-Host "No Bluetooth adapters found."
    }

    Write-Host "`nPower Timeouts:" -ForegroundColor Yellow
    Write-Host "  (Use 'powercfg /query' for full details)"
    Powercfg /Query SCHEME_CURRENT SUB_SLEEP 2>$null | Select-String "Current AC Power Setting Index|Current DC Power Setting Index"

    Write-Host "`nWindows Update Service:" -ForegroundColor Yellow
    Get-Service wuauserv | Select-Object Name, Status, StartType

    Write-Host "`nTime Zone:" -ForegroundColor Yellow
    Get-TimeZone | Select-Object Id, DisplayName

    Write-Host "`nSnapshot file:" -ForegroundColor Yellow
    if (Test-Path $snapshotPath) {
        Write-Host "  Found: $snapshotPath"
        $snap = Get-LabSnapshot
        if ($snap) { Write-Host "  Captured at: $($snap.CapturedAt)" }
    } else {
        Write-Host "  Not found (no deploy has been run from this directory)."
    }
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
                $confirm = Read-Host "Rollback will attempt to restore original/safer settings. Type ROLLBACK to continue"
                if ($confirm -eq "ROLLBACK") {
                    Restore-AtomWindowsLabConfig
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
Stop-Transcript | Out-Null
