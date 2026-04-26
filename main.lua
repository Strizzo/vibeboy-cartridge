-- VibeBoy Cartridge — Remote control for VibeBoy daemon
-- Manages tmux sessions and Claude Code via HTTP API

local api = require("api")
local ui = require("ui")
local connect_screen = require("screens.connect")
local dashboard_screen = require("screens.dashboard")
local session_screen = require("screens.session")

-- ── State ──────────────────────────────────────────────────────────────────

local state = {
    screen = "connect",  -- "connect", "dashboard", "session"

    -- Connection
    host = "192.168.1.100",
    port = 8766,
    connected = false,
    connecting = false,
    connect_error = "",
    edit_field = nil,  -- nil, "host", "port", "ssh_user"
    servers = {},      -- list of configured servers (hostnames or IPs)
    host_edit_ip = false, -- true = editing IP octets, false = cycling servers
    host_octet = 1,

    -- SSH tunnel
    ssh_enabled = false,
    ssh_user = "",  -- empty = auto (let SSH config decide)
    ssh_active = false,
    local_port = nil,

    -- Polling
    poll_timer = 0,
    poll_interval = 1.0,
    fail_count = 0,
    max_failures = 3,
    poll_in_flight = false,
    poll_request_id = nil,

    -- Dashboard
    sessions = {},           -- sorted list of session data
    session_ids = {},        -- ordered list of session IDs
    dashboard_cursor = 1,

    -- Session view
    current_session = nil,   -- current session data table
    session_index = 0,       -- 1-based index into session_ids
    option_index = 1,
    terminal_scroll = 0,

    -- Deferred actions
    pending_action = nil,    -- action to send on next update
    force_poll = false,      -- re-poll immediately after action
    loading = false,

    -- Deferred initial connect
    needs_initial_connect = false,
    ready_to_connect = false,

    -- First-run help
    show_help = false,
}

-- ── Persistence ────────────────────────────────────────────────────────────

-- SSH keys are looked up in this directory on the SD card.
-- Users drop their private key here from their computer.
local SSH_KEY_DIR = "/roms/Cartridge/ssh"

local function save_settings()
    storage.save("vibeboy_settings", {
        host = state.host, port = state.port,
        ssh_enabled = state.ssh_enabled,
        ssh_user = state.ssh_user,
        servers = state.servers,
    })
end

local function load_settings()
    local data = storage.load("vibeboy_settings")
    if data then
        state.host = data.host or state.host
        state.port = data.port or state.port
        if data.ssh_enabled ~= nil then state.ssh_enabled = data.ssh_enabled end
        state.ssh_user = data.ssh_user or state.ssh_user
        if data.servers and #data.servers > 0 then
            state.servers = data.servers
        end
    end

    -- Ensure server list is populated
    if #state.servers == 0 then
        state.servers = {state.host, "localhost"}
    end

    -- Add current host to list if not present
    local found = false
    for _, s in ipairs(state.servers) do
        if s == state.host then found = true; break end
    end
    if not found then
        table.insert(state.servers, 1, state.host)
    end
end

-- ── Session Management ─────────────────────────────────────────────────────

local function update_sessions(data)
    local sessions_map = data.sessions or {}
    local list = {}
    local ids = {}

    for sid, sdata in pairs(sessions_map) do
        sdata.session_id = sid
        -- Normalize fields from daemon API to what the UI expects
        sdata.session_name = sdata.session_name or sdata.name or sid
        sdata.status = sdata.status or (sdata.attached and "attached" or "idle")
        sdata.pane_command = sdata.pane_command or ""
        sdata.session_type = sdata.session_type or "idle_shell"
        sdata.response_options = sdata.response_options or {}
        -- Convert terminal string to lines array for the session screen
        if type(sdata.terminal) == "string" and sdata.terminal ~= "" then
            local lines = {}
            for line in (sdata.terminal .. "\n"):gmatch("(.-)\n") do
                lines[#lines + 1] = line
            end
            sdata.screen_content = lines
        else
            sdata.screen_content = sdata.screen_content or {}
        end
        list[#list + 1] = sdata
        ids[#ids + 1] = sid
    end

    dashboard_screen.sort_sessions(list)

    -- Rebuild ordered IDs from sorted list
    ids = {}
    for _, s in ipairs(list) do
        ids[#ids + 1] = s.session_id
    end

    state.sessions = list
    state.session_ids = ids

    -- Update current session if viewing one
    if state.screen == "session" and state.session_index >= 1 and state.session_index <= #ids then
        local current_sid = ids[state.session_index]
        state.current_session = sessions_map[current_sid]
        if state.current_session then
            state.current_session.session_id = current_sid
        end
    end
end

local function open_session(index)
    if index < 1 or index > #state.session_ids then return end
    state.session_index = index
    state.option_index = 1
    state.terminal_scroll = 0

    local sid = state.session_ids[index]
    for _, s in ipairs(state.sessions) do
        if s.session_id == sid then
            state.current_session = s
            break
        end
    end

    state.screen = "session"
end

local function switch_session(delta)
    local n = #state.session_ids
    if n == 0 then return end
    local new_idx = state.session_index + delta
    if new_idx < 1 then new_idx = n end
    if new_idx > n then new_idx = 1 end
    open_session(new_idx)
end

-- ── Polling ────────────────────────────────────────────────────────────────

local function api_host()
    if state.ssh_active and state.local_port then
        return "127.0.0.1"
    end
    return state.host
end

local function api_port()
    if state.ssh_active and state.local_port then
        return state.local_port
    end
    return state.port
end

local function close_tunnel()
    if state.ssh_active then
        ssh.close()
        state.ssh_active = false
        state.local_port = nil
    end
end

-- Trigger an async poll. Result is processed in process_poll_responses().
local function do_poll_async()
    if state.poll_in_flight then return end -- one in-flight at a time
    if not http.get_async then
        -- Fallback to sync poll if async API not available
        local data, err = api.poll_state(api_host(), api_port())
        if data then
            state.connected = true
            state.fail_count = 0
            update_sessions(data)
        else
            state.fail_count = state.fail_count + 1
            if state.fail_count >= state.max_failures then
                state.connected = false
                state.connect_error = err or "Connection lost"
                close_tunnel()
                state.screen = "connect"
                state.fail_count = 0
            end
        end
        return
    end
    state.poll_request_id = api.poll_state_async(api_host(), api_port())
    state.poll_in_flight = true
end

-- Drain async HTTP responses and update state for any matching poll request.
local function process_async_responses()
    if not http.poll then return end
    local responses = http.poll()
    for _, resp in ipairs(responses) do
        if resp.id == state.poll_request_id then
            state.poll_in_flight = false
            local data, err = api.parse_state(resp)
            if data then
                state.connected = true
                state.fail_count = 0
                update_sessions(data)
            else
                state.fail_count = state.fail_count + 1
                if state.fail_count >= state.max_failures then
                    state.connected = false
                    state.connect_error = err or "Connection lost"
                    close_tunnel()
                    state.screen = "connect"
                    state.fail_count = 0
                end
            end
        end
        -- Other request ids (action posts) are fire-and-forget.
    end
end

local function do_connect()
    state.connecting = true
    state.connect_error = ""

    -- Open SSH tunnel if enabled
    if state.ssh_enabled then
        local result = ssh.tunnel({
            host = state.host,
            user = state.ssh_user,
            key_dir = SSH_KEY_DIR,
            remote_port = state.port,
        })
        if not result.ok then
            state.connecting = false
            state.connect_error = result.error or "SSH tunnel failed"
            return
        end
        state.ssh_active = true
        state.local_port = result.local_port
    end

    local data, err = api.poll_state(api_host(), api_port())
    if data then
        state.connected = true
        state.connecting = false
        state.fail_count = 0
        save_settings()
        update_sessions(data)
        state.screen = "dashboard"
        state.dashboard_cursor = 1
    else
        state.connected = false
        state.connecting = false
        state.connect_error = err or "Connection failed"
        close_tunnel()
    end
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function on_init()
    load_settings()
    -- Show help on first launch (no saved settings yet)
    local saved = storage.load("vibeboy_settings")
    if not saved then
        state.show_help = true
    end
end

function on_update(dt)
    -- Deferred connect (after first frame renders)
    if state.ready_to_connect then
        state.ready_to_connect = false
        do_connect()
        return
    end

    -- Send pending action
    if state.pending_action then
        local act = state.pending_action
        state.pending_action = nil
        local ok, err = api.send_action(api_host(), api_port(), act.action, act.session_id, act.payload)
        if not ok then
            state.connect_error = err or "Action failed"
        end
        state.force_poll = true
    end

    -- Drain any completed async HTTP responses (cheap, non-blocking)
    process_async_responses()

    -- Polling (only when connected and on dashboard/session)
    if state.connected and (state.screen == "dashboard" or state.screen == "session") then
        if state.force_poll then
            state.force_poll = false
            state.poll_timer = 0
            do_poll_async()
        else
            state.poll_timer = state.poll_timer + dt
            if state.poll_timer >= state.poll_interval then
                state.poll_timer = 0
                do_poll_async()
            end
        end
    end
end

function on_input(button, action)
    -- Dismiss help overlay
    if state.show_help then
        if action == "press" then
            state.show_help = false
        end
        return
    end

    if state.screen == "connect" then
        local result = connect_screen.on_input(state, button, action)
        if result == "connect" then
            state.needs_initial_connect = true
        end

    elseif state.screen == "dashboard" then
        local result = dashboard_screen.on_input(state, button, action)
        if result == "open_session" then
            open_session(state.dashboard_cursor)
        elseif result == "refresh" then
            state.force_poll = true
        end

    elseif state.screen == "session" then
        local result = session_screen.on_input(state, button, action)
        if result == "dashboard" then
            state.screen = "dashboard"
        elseif result == "prev_session" then
            switch_session(-1)
        elseif result == "next_session" then
            switch_session(1)
        elseif type(result) == "table" and result.action then
            state.pending_action = result
        end
    end
end

local function draw_help()
    local W, H = 720, 720
    -- Dim background
    screen.draw_rect(0, 0, W, H, {color = {10, 10, 15}, filled = true})

    local cx = W / 2
    local y = 60

    -- Title
    local title = "VibeBoy Setup"
    local tw = screen.get_text_width(title, 22, true)
    screen.draw_text(title, (W - tw) / 2, y, {color = theme.accent, size = 22, bold = true})
    y = y + 40

    -- Description
    local lines = {
        "VibeBoy lets you manage tmux sessions on a",
        "remote server from your handheld.",
        "",
        "Before you start, you need:",
        "",
        "1. vibeboy-daemon running on your server",
        "   github.com/Strizzo/vibeboy-daemon",
        "",
        "2. Your SSH key on the SD card at:",
        "   Cartridge/ssh/id_ed25519",
        "",
        "Then in this app:",
        "",
        "  START    Edit connection settings",
        "  X        Enter a new server IP",
        "  Y        Enable SSH tunnel",
        "  START    Switch between fields",
        "  A        Connect",
        "",
        "The daemon listens on port 8766 by default.",
        "SSH tunneling keeps the connection secure.",
    }

    for _, line in ipairs(lines) do
        local color = theme.text_dim
        if line:match("^%d%.") then
            color = theme.text
        elseif line:match("^  %u") then
            color = theme.accent
        end
        screen.draw_text(line, 80, y, {color = color, size = 14, max_width = 560})
        y = y + 22
    end

    -- Footer
    y = H - 50
    local hint = "Press any button to continue"
    local hw = screen.get_text_width(hint, 14, false)
    screen.draw_text(hint, (W - hw) / 2, y, {color = theme.text_dim, size = 14})
end

function on_render()
    screen.clear(theme.bg.r, theme.bg.g, theme.bg.b)

    -- Deferred connect: trigger on first render frame
    if state.needs_initial_connect then
        state.needs_initial_connect = false
        state.ready_to_connect = true
    end

    if state.show_help then
        draw_help()
    elseif state.screen == "connect" then
        connect_screen.draw(state)
    elseif state.screen == "dashboard" then
        dashboard_screen.draw(state)
    elseif state.screen == "session" then
        session_screen.draw(state)
    end
end

function on_destroy()
    close_tunnel()
end
