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
    host_octet = 1,    -- which IP octet is being edited (1-4)

    -- SSH tunnel
    ssh_enabled = false,
    ssh_user = "root",
    ssh_active = false,
    local_port = nil,

    -- Polling
    poll_timer = 0,
    poll_interval = 1.0,
    fail_count = 0,
    max_failures = 3,

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
    })
end

local function load_settings()
    local data = storage.load("vibeboy_settings")
    if data then
        state.host = data.host or state.host
        state.port = data.port or state.port
        if data.ssh_enabled ~= nil then state.ssh_enabled = data.ssh_enabled end
        state.ssh_user = data.ssh_user or state.ssh_user
    end
end

-- ── Session Management ─────────────────────────────────────────────────────

local function update_sessions(data)
    local sessions_map = data.sessions or {}
    local list = {}
    local ids = {}

    for sid, sdata in pairs(sessions_map) do
        sdata.session_id = sid
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

local function do_poll()
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

    -- Polling (only when connected and on dashboard/session)
    if state.connected and (state.screen == "dashboard" or state.screen == "session") then
        if state.force_poll then
            state.force_poll = false
            state.poll_timer = 0
            do_poll()
        else
            state.poll_timer = state.poll_timer + dt
            if state.poll_timer >= state.poll_interval then
                state.poll_timer = 0
                do_poll()
            end
        end
    end
end

function on_input(button, action)
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

function on_render()
    screen.clear(theme.bg.r, theme.bg.g, theme.bg.b)

    -- Deferred connect: trigger on first render frame
    if state.needs_initial_connect then
        state.needs_initial_connect = false
        state.ready_to_connect = true
    end

    if state.screen == "connect" then
        connect_screen.draw(state)
    elseif state.screen == "dashboard" then
        dashboard_screen.draw(state)
    elseif state.screen == "session" then
        session_screen.draw(state)
    end
end
