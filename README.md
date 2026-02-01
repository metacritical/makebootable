# makebootable

Create a Linux bootable USB from macOS.

This tool uses macOS utilities (`diskutil`, `hdiutil`) and is intended for macOS.

## Install (portable)

Install to a bin directory on your `PATH`:

```bash
./install.sh
```

By default, `install.sh` installs to `~/.oh_my_bash/bin` if it exists (or `$OH_MY_BASH/bin`), otherwise it falls back to `~/.local/bin`.

Install system-wide (may prompt for sudo):

```bash
./install.sh --prefix /usr/local/bin
```

If `makeboot` isn’t found after install, ensure the chosen directory is on your `PATH`.

## Usage

```bash
makeboot /path/to/linux.iso
```
