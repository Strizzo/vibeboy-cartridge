# VibeBoy

A [CartridgeOS](https://github.com/Strizzo/Cartridge) app for managing tmux sessions on a remote server from your handheld. Perfect for monitoring Claude Code, long-running builds, or any terminal workflow from your handheld remote panel.

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
| A | Connect outside edit mode; +10 to the selected IP octet inside the IP editor |
| B | Exit edit mode / cancel a pending connection |

### Dashboard

| Button | Action |
|--------|--------|
| D-pad | Select session |
| A | Open session |
| X | Refresh session list |
| L2/R2 | Page through sessions |
| B | Disconnect and return to connection settings |

### Session View

| Button | Action |
|--------|--------|
| D-pad Up/Down | Scroll terminal output |
| L2/R2 | Cycle response options and detected choices |
| A | Execute selected action |
| L1/R1 | Switch to prev/next session |
| B / SELECT | Back to dashboard |
| Y | Interrupt (Ctrl+C) |
| X | Quick deny (Ctrl+C) while waiting |

## Public UI and validation

Requires the runtime's `ui.public` components. The connection form, session dashboard and terminal use a 720 px layout with large labels and explicit focus. Requires runtime 0.7.0. SSH tunnel creation uses `ssh.tunnel_async` and `ssh.poll`; HTTP starts after the tunnel succeeds. B, editing fields, toggling SSH, or disconnecting cancels a pending connection and ignores late results. The SSH key directory remains `/roms/Cartridge/ssh`. Initial HTTP connection and polling are asynchronous; action responses report failures.

The displayed response and A-button payload share one option list, including supplied key sequences and the fallback interrupt. Session identity is retained when daemon updates reorder the dashboard. No sample sessions are included in the app.

Controller capture scenarios: fresh setup; START/X IP editing; Y/START SSH-user field; connected empty dashboard; populated dashboard with D-pad and L2/R2; A terminal; L2/R2 response selection; D-pad scrollback; L1/R1 session switching; B/SELECT return; failed connection; pending SSH cancellation and late SSH/HTTP results. Validation uses in-memory SSH/HTTP mocks and local fixtures, with action sends disabled. The scoped regression checks are in `tests/regression.lua`; run them as the entry in a scratch copy without changing the production manifest.

## License

MIT

## Public app refresh

Requires **CartridgeOS 0.7.0 or newer**. The display uses the CartridgeOS app components at 720×720, larger type and flat graphite/paper panels. Controls remain usable while requests are pending; idle screens do not continuously animate.

Install or update from the signed CartridgeOS Store after updating the runtime. Source releases are also available in this repository's GitHub Releases. Preferences remain under the same app data keys.

SSH connection opens run on a worker. B or connection-setting edits cancel a pending connection, and late results cannot retarget the panel. The server daemon and a matching SSH key are still required. Headless checks use mocked SSH and do not send actions to real sessions.
