# VibeBoy

A [CartridgeOS](https://github.com/Strizzo/Cartridge) app for managing tmux sessions on a remote server from your handheld. Perfect for monitoring Claude Code, long-running builds, or any terminal workflow from your cyberdeck.

## How It Works

```
[R36S Plus]                    [Your Server]
 VibeBoy  ---SSH tunnel--->  vibeboy-daemon ---> tmux sessions
```

VibeBoy connects to a small daemon running on your server. The daemon exposes your tmux sessions via HTTP. An SSH tunnel keeps the connection secure without exposing any ports.

## Setup

### 1. Install the daemon on your server

```bash
git clone https://github.com/Strizzo/vibeboy-daemon.git
cd vibeboy-daemon
pip install -r requirements.txt
python3 vibeboy_daemon.py
```

See the [daemon README](https://github.com/Strizzo/vibeboy-daemon) for running it as a persistent service.

### 2. Copy your SSH key to the SD card

Turn off the device, insert the SD card into your computer, and create a `Cartridge/ssh/` folder. Copy your private key there:

```
SD card/
  Cartridge/
    ssh/
      id_ed25519    <-- your SSH private key
```

This is the same key you use to SSH into your server. VibeBoy auto-detects it.

### 3. Connect from VibeBoy

1. Install VibeBoy from the CartridgeOS Store
2. Open it, press **START** to edit the server
3. Press **X** to enter a new IP address (d-pad adjusts octets, **X** to confirm)
4. Press **START** to move to PORT (default 8766 is fine)
5. Press **Y** to enable SSH tunnel
6. Press **START** to move to SSH USER, cycle to your username (or leave as "auto")
7. Press **B** to exit edit mode
8. Press **A** to connect

Once connected, your server is saved. Next time just press **A**.

## Controls

### Connect Screen

| Button | Action |
|--------|--------|
| START | Enter edit mode / cycle between fields |
| D-pad | Cycle servers or adjust values |
| X | Enter new IP (in server field) / Confirm IP (in IP editor) |
| Y | Toggle SSH tunnel |
| A | Connect |
| B | Exit edit mode |

### Dashboard

| Button | Action |
|--------|--------|
| D-pad | Select session |
| A | Open session |
| L1/R1 | Switch between sessions |
| B | Back to connect screen |

### Session View

| Button | Action |
|--------|--------|
| D-pad Up/Down | Scroll terminal output |
| D-pad Left/Right | Cycle actions (send command, interrupt, etc.) |
| A | Execute selected action |
| L1/R1 | Switch to prev/next session |
| B | Back to dashboard |

## License

MIT
