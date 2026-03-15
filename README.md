# vibeboy-cartridge

A [CartridgeOS](https://github.com/Strizzo/Cartridge) app for remotely controlling the [VibeBoy daemon](https://github.com/Strizzo/vibeboy-daemon). Manage tmux sessions and Claude Code from your cyberdeck.

## Features

- Connect to a VibeBoy daemon over the network
- Built-in SSH tunnel support for secure remote access
- Browse and switch between tmux sessions
- View live terminal output
- Send commands, respond to prompts, interrupt processes
- Create and kill sessions

## Setup

Install as a CartridgeOS cartridge, or run directly:

```bash
cargo run -- run --path /path/to/vibeboy-cartridge
```

## Controls

| Button | Action |
|--------|--------|
| D-pad | Navigate / adjust values |
| A | Connect / confirm |
| B | Back |
| Y | Toggle SSH tunnel |
| START | Edit fields |
| L1/R1 | Switch sessions |

## Configuration

Host, port, and SSH toggle are configured on the connect screen and persisted automatically.

### SSH Tunnel

When SSH is enabled, VibeBoy tunnels the daemon port through SSH so the daemon doesn't need to be exposed publicly.

**Setup (no SSH into the device needed):**

1. Turn off the device and insert the SD card into your computer
2. Create a `Cartridge/ssh/` folder on the SD card
3. Copy your SSH private key there (e.g., `id_ed25519`)
4. Eject, put the SD card back, boot the device
5. In VibeBoy: set the server IP, set the SSH user, enable SSH with Y, press A to connect

The cartridge auto-detects keys from `Cartridge/ssh/` on the SD card, falling back to `~/.ssh/` on the device. The SSH user can be cycled with the d-pad in edit mode (press START to switch fields).

## License

MIT
