-- screens/dashboard.lua — Session list overview

local ui = require("ui")

local M = {}

local ROW_HEIGHT = 56
local CARD_RADIUS = 6

--- Sort sessions: waiting first, then alphabetical by name.
local function sort_sessions(sessions)
    table.sort(sessions, function(a, b)
        local a_waiting = a.status == "waiting" and 0 or 1
        local b_waiting = b.status == "waiting" and 0 or 1
        if a_waiting ~= b_waiting then
            return a_waiting < b_waiting
        end
        return (a.session_name or "") < (b.session_name or "")
    end)
end

--- Draw a single session card.
local function draw_session_card(session, y, is_selected, card_x, card_w)
    local card_h = ROW_HEIGHT - 4

    if is_selected then
        screen.draw_card(card_x, y, card_w, card_h, {
            bg = theme.card_highlight, border = theme.accent, radius = CARD_RADIUS,
        })
    else
        screen.draw_card(card_x, y, card_w, card_h, {
            bg = theme.card_bg, radius = CARD_RADIUS,
        })
    end

    -- Type pill
    local px = card_x + 10
    local pill_w = ui.draw_type_pill(session.session_type, px, y + 8)

    -- Session name
    local name_x = px + pill_w + 8
    local name = (session.session_name or "unknown"):gsub("[\128-\255]", "?")
    local max_name_w = card_w - pill_w - 120
    local nw = screen.get_text_width(name, 14, is_selected)
    if nw > max_name_w then
        while #name > 1 and screen.get_text_width(name .. "..", 14, is_selected) > max_name_w do
            name = name:sub(1, -2)
        end
        name = name .. ".."
    end
    screen.draw_text(name, name_x, y + 6, {color = theme.text, size = 14, bold = is_selected})

    -- Command (second line)
    local cmd = session.pane_command or ""
    if cmd ~= "" then
        local cmd_max_w = card_w - pill_w - 120
        local cw = screen.get_text_width(cmd, 11, false)
        if cw > cmd_max_w then
            while #cmd > 1 and screen.get_text_width(cmd .. "..", 11, false) > cmd_max_w do
                cmd = cmd:sub(1, -2)
            end
            cmd = cmd .. ".."
        end
        screen.draw_text(cmd, name_x, y + 26, {color = theme.text_dim, size = 11})
    end

    -- Status pill (right side)
    local status = session.status or (session.attached and "attached" or "idle")
    ui.draw_status_pill(status, card_x + card_w - 70, y + 14, status)
end

--- Draw the dashboard screen.
function M.draw(state)
    local sessions = state.sessions or {}
    local n = #sessions

    ui.draw_header("VIBEBOY", n .. " sessions", n > 0 and {100, 220, 100} or theme.text_dim)

    local content_y = 44
    local footer_y = 684
    local content_h = footer_y - content_y
    local card_x = 6
    local card_w = 708

    if state.loading then
        ui.draw_loading("Connecting...", content_y, content_h)
    elseif n == 0 then
        ui.draw_loading("No sessions found", content_y, content_h)
    else
        local visible = math.max(1, math.floor(content_h / ROW_HEIGHT))
        state.dashboard_cursor = math.max(1, math.min(state.dashboard_cursor, n))

        local start_idx
        if n <= visible then
            start_idx = 1
        else
            start_idx = math.max(1, math.min(state.dashboard_cursor - 1, n - visible + 1))
        end
        local end_idx = math.min(start_idx + visible - 1, n)

        local y = content_y + 2
        for idx = start_idx, end_idx do
            draw_session_card(sessions[idx], y, idx == state.dashboard_cursor, card_x, card_w)
            y = y + ROW_HEIGHT
        end

        ui.draw_scroll_indicator(content_y, content_h, state.dashboard_cursor, n, visible)
    end

    ui.draw_footer({
        {"\226\134\145\226\134\147", "Navigate", theme.btn_l},
        {"A", "Open", theme.btn_a},
        {"X", "Refresh", theme.btn_x},
    })
end

--- Handle input on dashboard screen.
-- @return string|nil  "open_session", "refresh", or nil
function M.on_input(state, button, action)
    if action ~= "press" and action ~= "repeat" then return nil end
    local sessions = state.sessions or {}
    local n = #sessions

    if button == "dpad_up" then
        state.dashboard_cursor = math.max(1, state.dashboard_cursor - 1)
    elseif button == "dpad_down" then
        state.dashboard_cursor = math.min(math.max(1, n), state.dashboard_cursor + 1)
    elseif button == "a" and n > 0 then
        return "open_session"
    elseif button == "x" then
        return "refresh"
    elseif button == "l2" then
        local visible = math.max(1, math.floor(640 / ROW_HEIGHT))
        state.dashboard_cursor = math.max(1, state.dashboard_cursor - visible)
    elseif button == "r2" then
        local visible = math.max(1, math.floor(640 / ROW_HEIGHT))
        state.dashboard_cursor = math.min(math.max(1, n), state.dashboard_cursor + visible)
    end

    return nil
end

--- Sort the sessions list in state.
function M.sort_sessions(sessions)
    sort_sessions(sessions)
end

return M
