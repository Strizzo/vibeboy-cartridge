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

When SSH is enabled, VibeBoy tunnels the daemon port through SSH so the daemon doesn't need to be exposed publicly. Authentication is handled by the system SSH client using `~/.ssh/config`.

To set it up, SSH into your device and configure the remote server:

```
# ~/.ssh/config on the device
Host myserver
  HostName 123.45.67.89
  User youruser
  IdentityFile ~/.ssh/id_ed25519
```

Then in VibeBoy, set the server IP, enable SSH with Y, and press A to connect.

## License

MIT
