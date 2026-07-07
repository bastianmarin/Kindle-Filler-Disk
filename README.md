# Kindle Disk Filler

Fill Kindle storage to block automatic updates on unregistered tablets. Useful for jailbreak preparation.

## Quick Run

**Linux / macOS:**
```bash
curl -fsSL https://github.com/iiroak/Kindle-Filler-Disk/raw/main/NoMTP/Filler.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://github.com/iiroak/Kindle-Filler-Disk/raw/main/NoMTP/Filler.ps1 | iex
```

**Windows (CMD):**
```cmd
powershell -Command "irm https://github.com/iiroak/Kindle-Filler-Disk/raw/main/NoMTP/Filler.ps1 | iex"
```

## Supported Devices

| Kindle Model | Connection | Supported |
|-------------|------------|-----------|
| Kindle Basic (older) | Mass Storage | Yes |
| Kindle Paperwhite (up to 11th gen) | Mass Storage | Yes |
| Kindle Paperwhite 12th gen | MTP | Yes (Linux/Windows) |
| Kindle Basic 2024 | MTP | Yes (Linux/Windows) |
| Kindle Scribe | MTP | Yes (Linux/Windows) |

## How It Works

The script **automatically detects** your Kindle's connection type:

1. **Mass Storage** (older Kindles): appears as a regular USB drive. Files are created directly on the device.
2. **MTP** (modern Kindles): appears as a portable device. Files are created locally then transferred via MTP protocol.

### Detection Methods

| OS | Mass Storage Detection | MTP Detection |
|----|----------------------|---------------|
| Linux | `findmnt` by volume label "Kindle" | `gio mount -l` (requires `gvfs`) |
| macOS | `/Volumes/Kindle` | Not supported (macOS lacks MTP) |
| Windows | Drive with volume name "Kindle" | `Shell.Application` COM (portable devices) |

## MTP Support (Linux)

For newer Kindles that use MTP protocol, you need `gvfs` installed:

```bash
# Ubuntu/Debian
sudo apt install gvfs gvfs-backends

# Fedora
sudo dnf install gvfs gvfs-mtp

# Arch Linux
sudo pacman -S gvfs gvfs-mtp
```

## Notes

- Recommended free space: 20-50 MB to block updates
- Multiple runs are safe — continues from where it left off
- Delete `fill_disk/` folder to free space after jailbreak
- The script **will not** create files on your PC — it only targets the Kindle device
- If no Kindle is detected, the script aborts with a clear error message

## Running from File (Windows)

If you download `Filler.ps1` and run it locally, PowerShell may block it with an execution policy error. Solutions:

```powershell
# Option A: Run with bypass (one-time)
powershell -ExecutionPolicy Bypass -File .\Filler.ps1

# Option B: Change policy permanently (recommended)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

The `irm | iex` command works without any changes because it runs in the current session.

## Troubleshooting

### "No Kindle device detected"
- Ensure your Kindle is connected via USB cable
- Unlock the Kindle and make sure it shows the home screen
- For MTP Kindles on Linux: install `gvfs gvfs-backends`
- Try disconnecting and reconnecting the USB cable

### Script fills PC storage instead of Kindle (FIXED in v2.1)
This issue was fixed in v2.1. The script now detects the Kindle device before creating any files.

### "El archivo no está firmado digitalmente" (Windows)
See [Running from File](#running-from-file-windows) above.

### MTP is slow
MTP transfers are inherently slower than mass storage. The script uses 100MB chunks for MTP to balance speed and reliability.

## Manual

Copy `Filler.ps1` (Windows) or `Filler.sh` (Linux/macOS) to Kindle root via USB, then run.

## Credits

- [iiroak](https://github.com/iiroak) — Original author
- [vinaooo](https://github.com/vinaooo) — MTP detection and auto-detection for Linux ([#8](https://github.com/iiroak/Kindle-Filler-Disk/issues/8))
- [simoneeti](https://github.com/simoneeti) — gio-based MTP approach for Linux ([#34](https://github.com/iiroak/Kindle-Filler-Disk/issues/34))
- [johnabs](https://github.com/johnabs) — dd single-file suggestion ([#18](https://github.com/iiroak/Kindle-Filler-Disk/issues/18))
- [zhangyoufu](https://github.com/zhangyoufu) — mkfile performance issue on macOS ([#19](https://github.com/iiroak/Kindle-Filler-Disk/issues/19))
