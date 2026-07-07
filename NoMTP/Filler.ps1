# Kindle Disk Filler Utility for Windows/PowerShell
# Author: iiroak (https://github.com/iiroak)
# Supports Mass Storage and MTP (newer Kindles)

Write-Host ""
Write-Host "  +=============================================================+"
Write-Host "  |               Kindle Disk Filler Utility v2.1               |"
Write-Host "  +=============================================================+"
Write-Host "  |     Fills disk to prevent auto-updates on unregistered      |"
Write-Host "  |         tablets. Useful for jailbreak preparation.          |"
Write-Host "  +=============================================================+"
Write-Host ""

# --- DETECT KINDLE ---
function Find-Kindle {
    Write-Host "[*] Detecting Kindle device..."

    # 1. Try Mass Storage (older Kindles with drive letter)
    $drives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue
    foreach ($drive in $drives) {
        if ($drive.VolumeName -eq "Kindle") {
            $label = $drive.VolumeName
            Write-Host "[OK] Kindle found as Mass Storage: $($drive.DeviceID)\"
            return @{
                Path = "$($drive.DeviceID)\"
                Type = "mass_storage"
                DriveLetter = $drive.DeviceID[0]
                Name = "$label ($($drive.DeviceID))"
            }
        }
    }

    # 2. Try MTP via Shell.Application COM
    try {
        $shell = New-Object -ComObject Shell.Application
        $thisPC = $shell.Namespace(0x11)
        if ($thisPC) {
            foreach ($item in $thisPC.Items()) {
                if ($item.Name -match "Kindle") {
                    Write-Host "[OK] Kindle found as MTP device: $($item.Name)"
                    return @{
                        Path = $item.Path
                        Type = "mtp"
                        ShellItem = $item
                        DeviceName = $item.Name
                        Name = $item.Name
                    }
                }
            }
        }
    } catch {
        Write-Host "[!] Shell.Application MTP detection failed: $_"
    }

    return $null
}

# --- MANUAL DEVICE SELECTION ---
function Select-Device {
    Write-Host ""
    Write-Host "[*] No Kindle found. Listing all available devices..."
    Write-Host ""

    $devices = @()
    $idx = 1
    $driveLetters = @()

    # List all logical disks
    $drives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue
    foreach ($drive in $drives) {
        if ($drive.DriveType -ne 3 -and $drive.DriveType -ne 2) { continue }
        $label = if ($drive.VolumeName) { $drive.VolumeName } else { "Unnamed" }
        $sizeGB = if ($drive.Size) { [math]::Round($drive.Size / 1GB, 1) } else { 0 }
        $freeGB = if ($drive.FreeSpace) { [math]::Round($drive.FreeSpace / 1GB, 1) } else { 0 }
        $driveLetters += $drive.DeviceID[0]
        $devices += @{
            Type = "mass_storage"
            Path = "$($drive.DeviceID)\"
            DriveLetter = $drive.DeviceID[0]
            Name = "$label ($($drive.DeviceID)) - ${freeGB}GB free / ${sizeGB}GB"
        }
        Write-Host "  [$idx] $label ($($drive.DeviceID)) - ${freeGB}GB free / ${sizeGB}GB"
        $idx++
    }

    # List MTP/WPD devices via Shell COM (only real portable devices, not drives)
    try {
        $shell = New-Object -ComObject Shell.Application
        $thisPC = $shell.Namespace(0x11)
        if ($thisPC) {
            foreach ($item in $thisPC.Items()) {
                # Skip items that are drives (name contains drive letter like "(C:)")
                $isDrive = $false
                foreach ($dl in $driveLetters) {
                    if ($item.Name -match "\($dl`:\)") { $isDrive = $true; break }
                }
                if ($isDrive) { continue }
                # Skip UNC/network paths (name contains "\\")
                if ($item.Name -match "\\\\") { continue }
                # Skip items that look like "This PC" itself
                if ($item.Name -eq "This PC" -or $item.Name -eq "Este equipo") { continue }

                $devices += @{
                    Type = "mtp"
                    Path = $item.Path
                    ShellItem = $item
                    DeviceName = $item.Name
                    Name = "$($item.Name) (MTP)"
                }
                Write-Host "  [$idx] $($item.Name) (MTP)"
                $idx++
            }
        }
    } catch {}

    if ($devices.Count -eq 0) {
        Write-Host "    No devices found."
        return $null
    }

    Write-Host ""
    $choice = Read-Host "  Select device (1-$($devices.Count))"
    $choiceNum = 0
    if ([int]::TryParse($choice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $devices.Count) {
        return $devices[$choiceNum - 1]
    }

    Write-Host "    Invalid selection."
    return $null
}

# --- FREE SPACE ---
function Get-FreeBytes($kindle) {
    if ($kindle.Type -eq "mass_storage") {
        $drive = Get-PSDrive -Name $kindle.DriveLetter -ErrorAction SilentlyContinue
        if ($drive) { return $drive.Free }
        return 0
    }
    # MTP: Shell COM cannot reliably report free space on MTP devices
    # Return 0 to indicate we need a different approach
    return 0
}

function Get-FreeBytesMTP($kindle) {
    # Try WMI approach for MTP free space
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace($kindle.Path)
        if ($folder) {
            # GetDetailsOf with index 2 sometimes works for free space on MTP
            $freeStr = $folder.GetDetailsOf($folder.Items(), 2)
            if ($freeStr -and $freeStr -match '([\d,.]+)\s*(GB|MB|KB|B)') {
                $val = [double]($matches[1] -replace ',','.')
                switch ($matches[2]) {
                    'GB' { return [long]($val * 1GB) }
                    'MB' { return [long]($val * 1MB) }
                    'KB' { return [long]($val * 1KB) }
                    'B'  { return [long]$val }
                }
            }
        }
    } catch {}
    return 0
}

# --- HELPERS ---
function Get-PrettySize($bytes) {
    $suffix = "B", "KB", "MB", "GB", "TB"
    $index = 0
    $size = [double]$bytes
    while ($size -ge 1KB -and $index -lt 4) {
        $size = $size / 1KB
        $index++
    }
    return "{0:N1} {1}" -f $size, $suffix[$index]
}

function Get-PrettySizeMB($mb) {
    if ($mb -ge 1024) { return "{0:N1} GB" -f ($mb / 1024) }
    return "$mb MB"
}

function Draw-Bar {
    param([int]$Percent, [int]$Total = 32)
    $filled = [math]::Floor($Percent * $Total / 100)
    $empty = $Total - $filled
    return ("=" * $filled) + ("-" * $empty)
}

function Write-ProgressLine {
    param([int]$Percent, [string]$Status, [string]$Detail)
    $bar = Draw-Bar -Percent $Percent -Total 32
    $line = "  [{0}] {1,3}%  {2}{3}" -f $bar, $Percent, $Status, $Detail
    $width = [Math]::Max([Console]::WindowWidth - 1, $line.Length)
    [Console]::Write(("`r{0}" -f $line.PadRight($width)))
}

function Find-NextFreeIndex($dir) {
    $index = 0
    while ($true) {
        $filePath = Join-Path $dir "file_$index"
        if (-not (Test-Path $filePath)) { return $index }
        $index++
    }
}

# --- DETECT ---
$kindle = Find-Kindle
if (-not $kindle) {
    $kindle = Select-Device
    if (-not $kindle) {
        Write-Host ""
        Write-Host "[!] No devices available."
        Write-Host ""
        Write-Host "    For MTP Kindles on Linux, install: gvfs gvfs-backends"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit
    }
}

Write-Host ""
Write-Host "[OK] Device selected: $($kindle.Name)"

# --- VALIDATE ---
$dir = "fill_disk"

if ($kindle.Type -eq "mass_storage") {
    # Mass storage: work directly on the drive
    $targetDir = Join-Path $kindle.Path $dir
    if (-not (Test-Path $targetDir)) {
        try {
            New-Item -ItemType Directory -Path $targetDir -ErrorAction Stop | Out-Null
            Write-Host "[OK] Directory created: $targetDir"
        } catch {
            Write-Host "[!] Error creating directory: $_"
            Read-Host "Press Enter to exit"
            exit
        }
    } else {
        Write-Host "[OK] Directory exists: $targetDir"
    }
} else {
    # MTP: create temp directory locally, files will be copied via Shell COM
    $tempDir = Join-Path $env:TEMP "kindle_filler_$PID"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
    }
    Write-Host "[OK] Using temp directory: $tempDir"
    Write-Host "[*] Files will be created locally then copied via MTP"

    # Get the device folder via Shell COM
    $mtpDeviceFolder = $null
    try {
        $shellItem = $kindle.ShellItem
        if ($shellItem) {
            $mtpDeviceFolder = $shellItem.GetFolder()
        }
    } catch {
        Write-Host "[!] Warning: Could not access MTP device folder: $_"
    }

    if (-not $mtpDeviceFolder) {
        Write-Host "[!] Cannot access MTP device."
        Read-Host "Press Enter to exit"
        exit
    }

    Write-Host "[OK] Connected to: $($kindle.DeviceName)"
    Write-Host "[*] Files will be created locally then copied to device root"
}

Write-Host ""

# --- GET FREE SPACE ---
$totalFreeBytes = Get-FreeBytes $kindle
$mtpFreeKnown = $totalFreeBytes -gt 0

if ($mtpFreeKnown) {
    Write-Host "[OK] Available space: $(Get-PrettySize $totalFreeBytes)"
} elseif ($kindle.Type -eq "mtp") {
    # Try MTP free space detection
    $totalFreeBytes = Get-FreeBytesMTP $kindle
    if ($totalFreeBytes -gt 0) {
        $mtpFreeKnown = $true
        Write-Host "[OK] Available space (MTP): $(Get-PrettySize $totalFreeBytes)"
    } else {
        Write-Host "[!] Cannot determine free space via MTP."
        Write-Host "    The script will fill until the device reports errors."
    }
}

# --- USER INPUT ---
Write-Host ""
Write-Host "How much free space (in MB) do you want to leave on disk?"
Write-Host "It is highly recommended to leave only 20-50 MB (no more) to prevent updates."
Write-Host ""
Write-Host "  [1] 20 MB (default)"
Write-Host "  [2] 50 MB"
Write-Host "  [3] 100 MB"
Write-Host "  [4] Custom value"
Write-Host ""
$choice = Read-Host "  Enter your choice (1-4) [1]"

if ($choice -eq "2") {
    $minFreeMB = 50
} elseif ($choice -eq "3") {
    $minFreeMB = 100
} elseif ($choice -eq "4") {
    $custom = Read-Host "  Enter the minimum free space in MB (e.g., 30)"
    $customValue = 0
    if ([int]::TryParse($custom, [ref]$customValue) -and $customValue -gt 0) {
        $minFreeMB = $customValue
    } else {
        Write-Host "Invalid input. Using default (20 MB)."
        $minFreeMB = 20
    }
} else {
    $minFreeMB = 20
}

$minFreeBytes = [long]$minFreeMB * 1MB

# Validate free space if known
if ($mtpFreeKnown) {
    $targetFillBytes = $totalFreeBytes - $minFreeBytes
    if ($targetFillBytes -le 0) {
        Write-Host "[!] The requested free space ($minFreeMB MB) is >= current free space. Nothing to do."
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit
    }
    Write-Host ""
    Write-Host "[>] Starting disk fill process..."
    Write-Host "    Target: fill ~$(Get-PrettySize $targetFillBytes), leave $minFreeMB MB free"
} else {
    $targetFillBytes = 0  # Unknown
    Write-Host ""
    Write-Host "[>] Starting disk fill process (free space unknown)..."
    Write-Host "    Will fill until $minFreeMB MB remaining or write errors"
}

Write-Host "    Mode: $($kindle.Type)"
Write-Host ""

# --- MAIN LOOP ---
$i = 0
$maxFileSize = 1GB

if ($kindle.Type -eq "mass_storage") {
    # ---- MASS STORAGE MODE ----
    $targetDir = Join-Path $kindle.Path $dir

    while ($true) {
        $currentFree = Get-FreeBytes $kindle
        $fillableBytes = $currentFree - $minFreeBytes
        if ($fillableBytes -le 0) { break }

        $fileSize = [Math]::Min([long]$maxFileSize, [long]$fillableBytes)
        if ($fileSize -le 0) { break }

        $fileLabel = Get-PrettySize $fileSize
        $filePath = Join-Path $targetDir "file_$i"

        # Progress
        if ($mtpFreeKnown) {
            $usedBytes = $totalFreeBytes - $currentFree
            $percent = [math]::Floor(($usedBytes * 100) / $targetFillBytes)
            if ($percent -lt 0) { $percent = 0 }
            if ($percent -gt 100) { $percent = 100 }
        } else {
            $percent = 0
        }

        Write-ProgressLine -Percent $percent -Status "Creating: " -Detail "file_$i ($fileLabel)"

        # Create file
        fsutil file createnew $filePath $fileSize | Out-Null

        if (-not (Test-Path $filePath)) { break }

        $i++

        # Progress update
        $currentFree = Get-FreeBytes $kindle
        $remainingLabel = Get-PrettySize $currentFree
        if ($mtpFreeKnown) {
            $usedBytes = $totalFreeBytes - $currentFree
            $percent = [math]::Floor(($usedBytes * 100) / $targetFillBytes)
            if ($percent -lt 0) { $percent = 0 }
            if ($percent -gt 100) { $percent = 100 }
        } else {
            $percent = 0
        }

        Write-ProgressLine -Percent $percent -Status "Done:     " -Detail "file_$($i-1) | Free: $remainingLabel"
    }

} else {
    # ---- MTP MODE ----
    # Copy files directly to device root (MTP doesn't reliably support subdirectories)
    $targetFolder = $mtpDeviceFolder
    Write-Host "[OK] Target: $($kindle.DeviceName) root"

    while ($true) {
        # Check free space if known
        if ($mtpFreeKnown) {
            $currentFree = Get-FreeBytesMTP $kindle
            if ($currentFree -gt 0) {
                $fillableBytes = $currentFree - $minFreeBytes
                if ($fillableBytes -le 0) { break }
            }
        }

        # File size: use chunks for MTP (smaller for reliability)
        if ($mtpFreeKnown -and $currentFree -gt 0) {
            $fillableBytes = $currentFree - $minFreeBytes
            if ($fillableBytes -le 0) { break }
            $fileSize = [Math]::Min([long]100MB, [long]$fillableBytes)  # Cap at 100MB for MTP
        } else {
            $fileSize = 100MB  # Default chunk for unknown space
        }
        if ($fileSize -le 0) { break }

        $fileLabel = Get-PrettySize $fileSize

        # Progress
        if ($mtpFreeKnown -and $totalFreeBytes -gt 0) {
            $usedBytes = $totalFreeBytes - $currentFree
            $percent = [math]::Floor(($usedBytes * 100) / [Math]::Max([long]$targetFillBytes, 1))
            if ($percent -lt 0) { $percent = 0 }
            if ($percent -gt 100) { $percent = 100 }
        } else {
            $percent = 0
        }

        Write-ProgressLine -Percent $percent -Status "Creating: " -Detail "file_$i ($fileLabel)"

        # Create temp file locally
        $tmpFile = Join-Path $tempDir "file_$i"
        fsutil file createnew $tmpFile $fileSize | Out-Null

        if (-not (Test-Path $tmpFile)) {
            Write-Host "`n[!] Failed to create temporary file"
            break
        }

        # Copy to Kindle via MTP (Shell COM)
        $copySuccess = $false
        if ($targetFolder) {
            try {
                # Use Shell.Application CopyHere
                # 0x10 = overwrite, 0x4 = no progress dialog, 0x100 = no UI
                $targetFolder.CopyHere($tmpFile, 0x14)

                # Wait for copy to complete (check if file appears on device)
                $timeout = 120  # seconds
                $waited = 0
                while ($waited -lt $timeout) {
                    Start-Sleep -Seconds 1
                    $waited++
                    $found = $false
                    try {
                        foreach ($item in $targetFolder.Items()) {
                            if ($item.Name -eq "file_$i") {
                                $found = $true
                                break
                            }
                        }
                    } catch {}
                    if ($found) {
                        $copySuccess = $true
                        break
                    }
                    # Show progress dots
                    if ($waited % 5 -eq 0) {
                        Write-ProgressLine -Percent $percent -Status "Copying:  " -Detail "file_$i ($fileLabel) - ${waited}s"
                    }
                }
            } catch {
                Write-Host "`n[!] MTP copy failed: $_"
            }
        } else {
            Write-Host "`n[!] No target folder on Kindle"
        }

        # Cleanup temp file
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue

        if (-not $copySuccess) {
            Write-Host "`n[!] Failed to copy file_$i to Kindle. Storage may be full."
            break
        }

        $i++

        # Progress update
        if ($mtpFreeKnown) {
            $currentFree = Get-FreeBytesMTP $kindle
            if ($currentFree -gt 0) {
                $remainingLabel = Get-PrettySize $currentFree
                $usedBytes = $totalFreeBytes - $currentFree
                $percent = [math]::Floor(($usedBytes * 100) / [Math]::Max([long]$targetFillBytes, 1))
                if ($percent -lt 0) { $percent = 0 }
                if ($percent -gt 100) { $percent = 100 }
                Write-ProgressLine -Percent $percent -Status "Done:     " -Detail "file_$($i-1) | Free: $remainingLabel"
            }
        }

        # Small delay for MTP stability
        Start-Sleep -Milliseconds 300
    }

    # Cleanup temp dir
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- DONE ---
Write-Host ""
Write-Host "  +---------------------------------------------------------+"
Write-Host "  |  Disk fill complete!                                    |"
Write-Host "  |  Files created: $i"
Write-Host "  |  Connection: $($kindle.Type)"
if ($kindle.Type -eq "mass_storage") {
    Write-Host "  |  Directory: $($kindle.Path)$dir"
} else {
    Write-Host "  |  Directory: $($kindle.Path)\$dir"
    Write-Host "  |  (files transferred via MTP)"
}
Write-Host "  +---------------------------------------------------------+"
Write-Host ""
Read-Host "Press Enter to exit"
