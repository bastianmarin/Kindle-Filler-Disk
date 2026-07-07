#!/bin/bash
# Kindle Disk Filler Utility for Linux/macOS
# Author: iiroak (https://github.com/iiroak)
# Contributors: vinaooo, simoneeti
# This tool fills the disk to prevent automatic updates on tablets
# that have not been registered. Useful for jailbreak preparation.
#
# Supports:
# - Mass Storage (older Kindles mounted as filesystem)
# - MTP protocol (modern Kindles via gio/gvfs, Linux only)
# - macOS (mass storage only, no MTP support)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR=""
KINDLE_PATH=""
CONNECTION_TYPE=""
FILE_COUNTER=0

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        echo ""
        echo "[!] Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
    if [ "$CONNECTION_TYPE" = "mtp" ] && [ -d "${KINDLE_PATH}/fill_disk" ]; then
        echo "[!] Removing partially filled directory on Kindle..."
        gio trash "${KINDLE_PATH}/fill_disk" 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo ""
echo "  +=============================================================+"
echo "  |           Kindle Disk Filler Utility v2.1                   |"
echo "  +=============================================================+"
echo "  |  Fills disk to prevent auto-updates on unregistered         |"
echo "  |  tablets. Useful for jailbreak preparation.                 |"
echo "  +=============================================================+"
echo ""

# --- DETECT KINDLE DEVICE ---
detect_kindle() {
    echo "[*] Detecting Kindle device..."

    if [ "$(uname)" = "Darwin" ]; then
        # macOS: only mass storage, no MTP support
        local kindle_mount=$(ls /Volumes/ 2>/dev/null | grep -i "kindle" | head -1)
        if [ -n "$kindle_mount" ]; then
            KINDLE_PATH="/Volumes/$kindle_mount"
            CONNECTION_TYPE="mass_storage"
            return 0
        fi
        return 1
    fi

    # Linux: try mass storage first (faster, direct filesystem)
    local kindle_mount=$(findmnt -rn -o TARGET -S LABEL=Kindle 2>/dev/null | head -1)
    if [ -n "$kindle_mount" ]; then
        KINDLE_PATH="$kindle_mount"
        CONNECTION_TYPE="mass_storage"
        return 0
    fi

    # Linux: try MTP via gio (modern Kindles)
    if command -v gio >/dev/null 2>&1; then
        local mtp_uri=$(gio mount -l 2>/dev/null | grep -i "kindle" | grep -o 'mtp://[^ ]*' | head -1)
        if [ -n "$mtp_uri" ]; then
            # Normalize URI (remove trailing slash)
            mtp_uri="${mtp_uri%/}"
            # Check for "Internal Storage" subfolder
            if gio list "$mtp_uri" 2>/dev/null | grep -q "Internal Storage"; then
                KINDLE_PATH="${mtp_uri}/Internal Storage"
            else
                KINDLE_PATH="$mtp_uri"
            fi
            CONNECTION_TYPE="mtp"
            return 0
        fi

        # Try auto-mounting MTP device
        gio mount -d 2>/dev/null | grep -i "kindle" >/dev/null 2>&1 && sleep 1
        mtp_uri=$(gio mount -l 2>/dev/null | grep -i "kindle" | grep -o 'mtp://[^ ]*' | head -1)
        if [ -n "$mtp_uri" ]; then
            mtp_uri="${mtp_uri%/}"
            if gio list "$mtp_uri" 2>/dev/null | grep -q "Internal Storage"; then
                KINDLE_PATH="${mtp_uri}/Internal Storage"
            else
                KINDLE_PATH="$mtp_uri"
            fi
            CONNECTION_TYPE="mtp"
            return 0
        fi
    fi

    # Linux: try gvfs fallback path
    local gvfs_path="/run/user/$(id -u)/gvfs"
    if [ -d "$gvfs_path" ]; then
        local kindle_gvfs=$(find "$gvfs_path" -maxdepth 2 -iname "*kindle*" -type d 2>/dev/null | head -1)
        if [ -n "$kindle_gvfs" ]; then
            if [ -d "$kindle_gvfs/Internal Storage" ]; then
                KINDLE_PATH="$kindle_gvfs/Internal Storage"
            else
                KINDLE_PATH="$kindle_gvfs"
            fi
            CONNECTION_TYPE="mtp"
            return 0
        fi
    fi

    return 1
}

# --- MANUAL DEVICE SELECTION ---
pick_device_manual() {
    echo ""
    echo "[*] No Kindle found. Listing all available devices..."
    echo ""

    local devices=()
    local idx=1

    # List mounted drives (mass storage)
    if [ "$(uname)" = "Darwin" ]; then
        for vol in /Volumes/*/; do
            local name=$(basename "$vol")
            [ "$name" = "Macintosh HD" ] && continue
            devices+=("mass_storage|$vol|$name")
            printf "  [%d] %s (mass storage: %s)\n" "$idx" "$name" "$vol"
            idx=$((idx + 1))
        done
    else
        while IFS= read -r line; do
            local target=$(echo "$line" | awk '{print $1}')
            local source=$(echo "$line" | awk '{print $2}')
            local label=$(echo "$line" | awk '{print $3}')
            [ -z "$label" ] && label="$(basename "$target")"
            # Skip root, boot, system mounts
            [[ "$target" == "/" ]] && continue
            [[ "$target" == /boot* ]] && continue
            [[ "$target" == /sys* ]] && continue
            [[ "$target" == /proc* ]] && continue
            [[ "$target" == /dev* ]] && continue
            [[ "$source" == /dev/loop* ]] && continue
            devices+=("mass_storage|$target|$label")
            printf "  [%d] %s (mass storage: %s)\n" "$idx" "$label" "$target"
            idx=$((idx + 1))
        done < <(findmnt -rn -o TARGET,SOURCE,LABEL 2>/dev/null | grep -v "tmpfs\|devtmpfs\|squashfs")
    fi

    # List MTP devices via gio
    if command -v gio >/dev/null 2>&1; then
        while IFS= read -r line; do
            local uri=$(echo "$line" | grep -o 'mtp://[^ ]*' | sed 's|/$||')
            [ -z "$uri" ] && continue
            local name=$(echo "$line" | sed 's|.*→ *||' | sed 's| *$||')
            [ -z "$name" ] && name="$uri"
            devices+=("mtp|$uri|$name")
            printf "  [%d] %s (MTP: %s)\n" "$idx" "$name" "$uri"
            idx=$((idx + 1))
        done < <(gio mount -l 2>/dev/null | grep "mtp://")
    fi

    if [ ${#devices[@]} -eq 0 ]; then
        echo "    No devices found."
        return 1
    fi

    echo ""
    read -p "  Select device (1-$((idx-1))): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ]; then
        local selected="${devices[$((choice-1))]}"
        CONNECTION_TYPE=$(echo "$selected" | cut -d'|' -f1)
        local path=$(echo "$selected" | cut -d'|' -f2)

        if [ "$CONNECTION_TYPE" = "mtp" ]; then
            # Try to find Internal Storage subfolder
            if gio list "$path" 2>/dev/null | grep -q "Internal Storage"; then
                KINDLE_PATH="${path}/Internal Storage"
            else
                KINDLE_PATH="$path"
            fi
        else
            KINDLE_PATH="$path"
        fi
        return 0
    fi

    echo "    Invalid selection."
    return 1
}

# --- FREE SPACE ---
get_free_mb() {
    case "$CONNECTION_TYPE" in
        mass_storage)
            df -Pm "$KINDLE_PATH" 2>/dev/null | awk 'NR==2 {print $4}'
            ;;
        mtp)
            local device_root=$(echo "$KINDLE_PATH" | sed 's|/Internal Storage||')
            local free_bytes=$(gio info -a "filesystem::free" "$device_root" 2>/dev/null | awk -F': ' '/filesystem::free/ {print $2}')
            if [ -n "$free_bytes" ] && [ "$free_bytes" -gt 0 ] 2>/dev/null; then
                echo $((free_bytes / 1024 / 1024))
            else
                free_bytes=$(gio info -a "filesystem::free" "$KINDLE_PATH" 2>/dev/null | awk -F': ' '/filesystem::free/ {print $2}')
                if [ -n "$free_bytes" ] && [ "$free_bytes" -gt 0 ] 2>/dev/null; then
                    echo $((free_bytes / 1024 / 1024))
                else
                    echo ""
                fi
            fi
            ;;
    esac
}

# --- FILE CREATION ---
create_file() {
    local size="$1" path="$2"
    # Normalize to MB for dd (works on all platforms)
    local mb_size
    if [[ "$size" == *G ]]; then
        mb_size=$((${size%G} * 1024))
    elif [[ "$size" == *M ]]; then
        mb_size=${size%M}
    else
        mb_size=$((size / 1024 / 1024))
    fi
    [ "$mb_size" -lt 1 ] && mb_size=1

    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${mb_size}M" "$path" 2>/dev/null && return 0
    fi
    if command -v truncate >/dev/null 2>&1; then
        # macOS-compatible: instant sparse file
        truncate -s "${mb_size}M" "$path" 2>/dev/null && return 0
    fi
    if command -v mkfile >/dev/null 2>&1; then
        mkfile "${mb_size}m" "$path" 2>/dev/null && return 0
    fi
    dd if=/dev/zero of="$path" bs=1M count="$mb_size" status=none 2>/dev/null
}

create_file_mtp() {
    local size="$1" dest_path="$2"
    local tmp_file="${TEMP_DIR}/file_${FILE_COUNTER}"

    create_file "$size" "$tmp_file"

    if [ ! -f "$tmp_file" ]; then
        echo "[!] Failed to create temporary file"
        return 1
    fi

    if gio copy "$tmp_file" "$dest_path" 2>/dev/null; then
        rm -f "$tmp_file"
        return 0
    else
        rm -f "$tmp_file"
        return 1
    fi
}

# --- PROGRESS BAR ---
render_progress() {
    local percent=$1 status=$2 detail=$3
    local width=32
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local bar empty_bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '=')
    empty_bar=$(printf '%*s' "$empty" '' | tr ' ' '-')
    printf '\r\033[2K  [%s%s] %3d%%  %s%s' "$bar" "$empty_bar" "$percent" "$status" "$detail"
}

# --- DETECT ---
if ! detect_kindle; then
    if ! pick_device_manual; then
        echo ""
        echo "[!] No devices available."
        echo ""
        echo "    If your Kindle uses MTP (newer models), install 'gvfs':"
        echo "    Ubuntu/Debian:  sudo apt install gvfs gvfs-backends"
        echo "    Fedora:         sudo dnf install gvfs gvfs-mtp"
        echo "    Arch:           sudo pacman -S gvfs gvfs-mtp"
        echo ""
        read -p "Press Enter to exit..." _
        exit 1
    fi
fi

echo "[OK] Device selected"
echo "     Connection type: $CONNECTION_TYPE"
echo "     Path: $KINDLE_PATH"

# --- VALIDATE DIRECTORY ---
if [ "$CONNECTION_TYPE" = "mass_storage" ]; then
    if [ ! -d "$KINDLE_PATH" ]; then
        echo "[!] Error: Kindle path $KINDLE_PATH is not accessible."
        read -p "Press Enter to exit..." _
        exit 1
    fi
    # Verify it's writable
    if ! touch "$KINDLE_PATH/.test_write" 2>/dev/null; then
        echo "[!] Error: Cannot write to $KINDLE_PATH. Check permissions."
        read -p "Press Enter to exit..." _
        exit 1
    fi
    rm -f "$KINDLE_PATH/.test_write"
elif [ "$CONNECTION_TYPE" = "mtp" ]; then
    if ! gio info "$KINDLE_PATH" >/dev/null 2>&1; then
        echo "[!] Error: Cannot access Kindle via MTP at $KINDLE_PATH"
        echo "    Try disconnecting and reconnecting your Kindle."
        read -p "Press Enter to exit..." _
        exit 1
    fi
    TEMP_DIR="/tmp/kindle_filler_$$"
    mkdir -p "$TEMP_DIR"
fi

echo ""

# --- CREATE DIRECTORY ON KINDLE ---
dir="fill_disk"
echo "[*] Preparing fill_disk directory on Kindle..."

case "$CONNECTION_TYPE" in
    mass_storage)
        if mkdir -p "$KINDLE_PATH/$dir" 2>/dev/null; then
            echo "[OK] Directory ready: $KINDLE_PATH/$dir"
        elif [ -d "$KINDLE_PATH/$dir" ]; then
            echo "[OK] Directory already exists: $KINDLE_PATH/$dir"
        else
            echo "[!] Warning: Could not create directory, but continuing..."
        fi
        ;;
    mtp)
        # Check if directory already exists
        if gio list "$KINDLE_PATH" 2>/dev/null | grep -q "^$dir$"; then
            echo "[OK] Directory already exists on Kindle"
        elif gio mkdir "$KINDLE_PATH/$dir" 2>/dev/null; then
            echo "[OK] Directory created on Kindle via MTP"
        else
            echo "[!] Warning: Could not create directory via MTP, but continuing..."
        fi
        ;;
esac

echo ""

# --- GET FREE SPACE ---
initialFreeMB=$(get_free_mb)
if [ -z "$initialFreeMB" ] || [ "$initialFreeMB" -le 0 ] 2>/dev/null; then
    echo "[!] Error: Cannot determine free space on Kindle."
    echo "    This may be a temporary MTP connection issue."
    echo "    Try disconnecting and reconnecting your Kindle."
    read -p "Press Enter to exit..." _
    exit 1
fi

echo "[OK] Available space: ${initialFreeMB} MB"

# --- USER INPUT ---
echo ""
echo "How much free space (in MB) do you want to leave on disk?"
echo "It is highly recommended to leave only 20-50 MB (no more) to prevent updates."
echo ""
echo "  [1] 20 MB (default)"
echo "  [2] 50 MB"
echo "  [3] 100 MB"
echo "  [4] Custom value"
echo ""
read -p "  Enter your choice (1-4) [1]: " choice

case "$choice" in
    2) minFreeMB=50 ;;
    3) minFreeMB=100 ;;
    4)
        read -p "  Enter the minimum free space in MB (e.g., 30): " custom
        if [[ "$custom" =~ ^[0-9]+$ ]] && [ "$custom" -gt 0 ]; then
            minFreeMB=$custom
        else
            echo "Invalid input. Using default (20 MB)."
            minFreeMB=20
        fi
        ;;
    *) minFreeMB=20 ;;
esac

targetFillMB=$((initialFreeMB - minFreeMB))
if [ "$targetFillMB" -le 0 ]; then
    echo "[!] The requested free space ($minFreeMB MB) is >= current free space ($initialFreeMB MB)."
    echo "    Nothing to do."
    read -p "Press Enter to exit..." _
    exit 0
fi

echo ""
echo "[>] Starting disk fill process..."
echo "    Target: fill ~${targetFillMB} MB, leave ${minFreeMB} MB free"
echo "    Mode: $CONNECTION_TYPE"
echo ""

# --- MAIN LOOP ---
while true; do
    freeMB=$(get_free_mb)
    [ -z "$freeMB" ] && break
    fillableMB=$((freeMB - minFreeMB))
    [ "$fillableMB" -le 0 ] && break

    # Determine file size
    if [ "$fillableMB" -ge 1024 ]; then
        fileSize=1G
    elif [ "$fillableMB" -ge 100 ]; then
        fileSize=100M
    elif [ "$fillableMB" -ge 10 ]; then
        fileSize=10M
    else
        fileSize="${fillableMB}M"
    fi

    # Progress
    usedMB=$((initialFreeMB - freeMB))
    percent=$((usedMB * 100 / targetFillMB))
    [ "$percent" -gt 100 ] && percent=100
    [ "$percent" -lt 0 ] && percent=0
    render_progress "$percent" "Creating: " "file_${FILE_COUNTER} ($fileSize)"

    # Create file
    case "$CONNECTION_TYPE" in
        mass_storage)
            create_file "$fileSize" "$KINDLE_PATH/$dir/file_${FILE_COUNTER}"
            if [ ! -f "$KINDLE_PATH/$dir/file_${FILE_COUNTER}" ]; then
                break
            fi
            ;;
        mtp)
            if ! create_file_mtp "$fileSize" "$KINDLE_PATH/$dir/file_${FILE_COUNTER}"; then
                echo ""
                echo "[!] Write failed. Storage might be completely full."
                break
            fi
            ;;
    esac

    FILE_COUNTER=$((FILE_COUNTER + 1))

    # Update progress
    freeMB=$(get_free_mb)
    [ -z "$freeMB" ] && break
    usedMB=$((initialFreeMB - freeMB))
    percent=$((usedMB * 100 / targetFillMB))
    [ "$percent" -gt 100 ] && percent=100
    [ "$percent" -lt 0 ] && percent=0

    remainingLabel="${freeMB} MB"
    [ "$freeMB" -ge 1024 ] && remainingLabel="$(awk "BEGIN {printf \"%.1f\", $freeMB/1024}") GB"

    render_progress "$percent" "Done:     " "file_$((FILE_COUNTER-1)) | Free: $remainingLabel"

    # Small delay for MTP to prevent overwhelming the connection
    [ "$CONNECTION_TYPE" = "mtp" ] && sleep 0.3
done

# --- DONE ---
printf '\n'
echo "  +---------------------------------------------------------+"
echo "  |  Disk fill complete!                                    |"
echo "  |  Files created: $FILE_COUNTER"
echo "  |  Connection: $CONNECTION_TYPE"
if [ "$CONNECTION_TYPE" = "mass_storage" ]; then
    echo "  |  Directory: $KINDLE_PATH/$dir"
else
    echo "  |  Directory: $KINDLE_PATH/$dir"
    echo "  |  (files transferred via MTP)"
fi
echo "  +---------------------------------------------------------+"
echo ""
read -p "Press Enter to exit..." _
