# MTP Emulator for Testing

This document describes how to set up a Kindle MTP emulator on Proxmox for testing the Filler scripts without a physical Kindle device.

## Architecture

```
Proxmox Host (pve)
  └── LXC 305 (mtp-emulator)
       ├── USB Gadget (configfs)
       │   ├── libcomposite
       │   ├── usb_f_mass_storage
       │   └── usbip-vudc (virtual UDC)
       └── Backing file (8GB FAT32, label "Kindle")
```

The emulator creates a USB gadget that appears as a Kindle mass storage device. It uses:
- **configfs** for USB gadget configuration
- **usb_f_mass_storage** for the mass storage function
- **usbip-vudc** as the virtual USB device controller
- A **FAT32 backing file** (8GB) as the virtual disk

## Setup

### Prerequisites

- Proxmox host with `libcomposite`, `usb_f_mass_storage`, `usbip-vudc` kernel modules
- LXC container 305 (mtp-emulator) running Debian 13

### Quick Start

```bash
# On the Proxmox host:
/mnt/storage/mtp-emulator/setup-emulator.sh start
```

### Manual Setup

```bash
# Load kernel modules
modprobe libcomposite
modprobe usb_f_mass_storage
modprobe usbip-vudc

# Mount configfs
mount -t configfs none /sys/kernel/config

# Create backing file
dd if=/dev/zero of=/mnt/storage/mtp-emulator/kindle-disk.img bs=1 count=0 seek=8G
mkfs.vfat -n Kindle -F 32 /mnt/storage/mtp-emulator/kindle-disk.img

# Mount locally for testing
mkdir -p /mnt/kindle-emulator
mount -o loop,rw /mnt/storage/mtp-emulator/kindle-disk.img /mnt/kindle-emulator

# Set up USB gadget
GADGET_DIR="/sys/kernel/config/usb_gadget/kindle_emulator"
mkdir -p "$GADGET_DIR"
cd "$GADGET_DIR"
echo 0x1949 > idVendor    # Amazon Technologies
echo 0x0004 > idProduct   # Kindle
echo 0x0200 > bcdUSB      # USB 2.0
mkdir -p strings/0x409
echo "Amazon" > strings/0x409/manufacturer
echo "Kindle Internal Storage" > strings/0x409/product
echo "0123456789ABCDEF" > strings/0x409/serialnumber
mkdir -p configs/c.1/strings/0x409
echo "Mass Storage" > configs/c.1/strings/0x409/configuration
echo 120 > configs/c.1/MaxPower
mkdir -p functions/mass_storage.0/lun.0
echo "/mnt/storage/mtp-emulator/kindle-disk.img" > functions/mass_storage.0/lun.0/file
echo 1 > functions/mass_storage.0/lun.0/removable
ln -s functions/mass_storage.0 configs/c.1/
echo "usbip-vudc.0" > UDC
```

## Testing

### Test Detection

```bash
# On Proxmox host:
findmnt -rn -o TARGET -S LABEL=Kindle
# Should output: /mnt/kindle-emulator

df -Pm /mnt/kindle-emulator
# Should show ~8GB free
```

### Test Filler Script

```bash
# Copy the script to the host
scp NoMTP/Filler.sh pve:/tmp/

# Run against the emulator
ssh pve "bash /tmp/Filler.sh"
```

### Reset Emulator

```bash
# Stop and recreate
/mnt/storage/mtp-emulator/setup-emulator.sh reset
```

## Status Commands

```bash
# Check emulator status
/mnt/storage/mtp-emulator/setup-emulator.sh status

# Stop emulator
/mnt/storage/mtp-emulator/setup-emulator.sh stop
```

## Limitations

- **Mass storage only**: The Proxmox kernel does not include `usb_f_mtp.ko`, so MTP emulation requires a custom kernel module or functionfs userspace implementation.
- **Network USB**: The `usbip-vudc` gadget creates a virtual USB device, but sharing it over the network requires additional usbip server setup.
- **No physical USB**: The Dell Pro Micro host has no USB OTG port, so the gadget is virtual only.

## Future: MTP Emulation

To test MTP detection, you would need to:

1. Compile `usb_f_mtp.ko` for the Proxmox kernel, OR
2. Use functionfs (`usb_f_fs.ko`) with a userspace MTP server (e.g., `libmtp-server`), OR
3. Connect a real Android device in MTP mode

Option 3 is the simplest for testing MTP detection.
