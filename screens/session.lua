-- screens/session.lua — Main session view (terminal + options + actions)

local ui = require("ui")

local M = {}

local SCROLL_STEP = 3

--- Strip any non-ASCII bytes from a string to prevent UTF-8 errors.
local function safe_ascii(s)
    if not s then return "" end
    return s:gsub("[\128-\255]", "?")
end

-- ── Status Bar ──────────────────────────────────────────────────────────────

local function draw_status_bar(session)
    local bar_y = 40
    local bar_h = 28
    screen.draw_rect(0, bar_y, 720, bar_h, {color = theme.bg_header, filled = true})

    local x = 10
    -- Type pill
    local pw = ui.draw_type_pill(session.session_type, x, bar_y + 4)
    x = x + pw + 6

    -- Status pill
    local sw = ui.draw_status_pill(session.status, x, bar_y + 4, session.status)
    x = x + sw + 8

    -- Command
    local cmd = safe_ascii(session.pane_command or "")
    if cmd ~= "" then
        local max_cmd_w = 400
        local cw = screen.get_text_width(cmd, 11, false)
        if cw > max_cmd_w then
            while #cmd > 1 and screen.get_text_width(cmd .. "..", 11, false) > max_cmd_w do
                cmd = cmd:sub(1, -2)
            end
            cmd = cmd .. ".."
        end
        screen.draw_text(cmd, x, bar_y + 7, {color = theme.text_dim, size = 11})
        x = x + screen.get_text_width(cmd, 11, false) + 8
    end

    -- Permission mode
    if session.permission_mode then
        local pm = session.permission_mode
        local pm_bg_r, pm_bg_g, pm_bg_b = 60, 60, 80
        if pm == "bypass" then
            pm_bg_r, pm_bg_g, pm_bg_b = 200, 60, 60
        elseif pm == "plan" then
            pm_bg_r, pm_bg_g, pm_bg_b = 60, 120, 200
        end
        screen.draw_pill(pm, x, bar_y + 4, pm_bg_r, pm_bg_g, pm_bg_b, {
            text_color = {255, 255, 255}, size = 9,
        })
    end

    screen.draw_line(0, bar_y + bar_h, 720, bar_y + bar_h, {color = theme.border})
end

-- ── Terminal Area ────────────────────────────────────────────────────────────

local function draw_terminal(session, state)
    local term_y = 68
    local term_h = 412  -- 68 to 480
    local lines = session.screen_content or {}
    local n = #lines

    -- Background
    screen.draw_rect(0, term_y, 720, term_h, {color = theme.bg, filled = true})

    if n == 0 then
        ui.draw_loading("No terminal content", term_y, term_h)
        return
    end

    local lh = screen.get_line_height(12, false)
    local visible_lines = math.max(1, math.floor(term_h / lh))

    -- Scroll from bottom: show last N lines, adjustable with terminal_scroll
    local max_scroll = math.max(0, n - visible_lines)
    state.terminal_scroll = math.max(0, math.min(state.terminal_scroll, max_scroll))

    -- Start line: scroll=0 means bottom (latest), scroll=max means top
    local start_line = math.max(1, n - visible_lines - state.terminal_scroll + 1)
    local end_line = math.min(n, start_line + visible_lines - 1)

    local y = term_y + 4
    for i = start_line, end_line do
        local line = safe_ascii(lines[i] or "")
        -- Truncate long lines
        screen.draw_text(line, 8, y, {color = theme.text, size = 12, max_width = 704})
        y = y + lh
    end

    -- Scroll indicator for terminal
    if n > visible_lines then
        local ind_x = 715
        local bar_top = term_y + 4
        local bar_h2 = term_h - 8
        screen.draw_line(ind_x, bar_top, ind_x, bar_top + bar_h2, {color = theme.border})
        local thumb_h = math.max(8, math.floor(bar_h2 * visible_lines / n))
        local progress = max_scroll > 0 and (state.terminal_scroll / max_scroll) or 0
        local thumb_y = bar_top + math.floor((bar_h2 - thumb_h) * (1 - progress))
        screen.draw_rect(ind_x - 1, thumb_y, 3, thumb_h, {color = theme.text_dim, filled = true, radius = 1})
    end
end

-- ── Options Area ────────────────────────────────────────────────────────────

local function draw_options(session, state)
    local opts_y = 480
    local opts_h = 160  -- 480 to 640
    local options = session.response_options or {}
    local choices = session.detected_choices or {}

    screen.draw_line(0, opts_y, 720, opts_y, {color = theme.border})

    -- Combine response options and detected choices
    local all_opts = {}
    for _, o in ipairs(options) do
        all_opts[#all_opts + 1] = {text = o.text, category = o.category, kind = "response"}
    end
    for _, c in ipairs(choices) do
        all_opts[#all_opts + 1] = {
            text = c.label,
            category = c.is_default and "approve" or "custom",
            kind = "choice",
            key_sequence = c.key_sequence,
        }
    end

    -- For plain sessions with no options, show default tmux actions
    if #all_opts == 0 then
        all_opts = {
            {text = "Interrupt (Ctrl+C)", category = "danger", kind = "keys", key_sequence = "C-c"},
            {text = "Clear screen", category = "custom", kind = "keys", key_sequence = "clear"},
            {text = "List files", category = "custom", kind = "keys", key_sequence = "ls -la"},
            {text = "Top processes", category = "custom", kind = "keys", key_sequence = "top -bn1 | head -20"},
        }
    end

    local n = #all_opts
    if n == 0 then
        local msg = "No options"
        local mw = screen.get_text_width(msg, 12, false)
        screen.draw_text(msg, (720 - mw) / 2, opts_y + opts_h / 2 - 6, {color = theme.text_dim, size = 12})
        return
    end

    local row_h = 28
    local visible = math.max(1, math.floor(opts_h / row_h))
    state.option_index = math.max(1, math.min(state.option_index, n))

    local start_idx
    if n <= visible then
        start_idx = 1
    else
        start_idx = math.max(1, math.min(state.option_index - 1, n - visible + 1))
    end
    local end_idx = math.min(start_idx + visible - 1, n)

    local y = opts_y + 4
    for idx = start_idx, end_idx do
        local opt = all_opts[idx]
        local is_selected = (idx == state.option_index)

        if is_selected then
            screen.draw_rect(4, y, 712, row_h - 2, {color = theme.card_highlight, filled = true, radius = 4})
        end

        local x = 10
        -- Category pill
        local pw = ui.draw_category_pill(opt.category, x, y + 4)
        x = x + pw + 6

        -- Cursor indicator
        if is_selected then
            screen.draw_text("\226\150\182", x - 2, y + 4, {color = theme.accent, size = 12})
        end

        -- Option text
        local opt_text = opt.text or ""
        local max_text_w = 700 - x - 10
        local tw = screen.get_text_width(opt_text, 12, false)
        if tw > max_text_w then
            while #opt_text > 1 and screen.get_text_width(opt_text .. "..", 12, false) > max_text_w do
                opt_text = opt_text:sub(1, -2)
            end
            opt_text = opt_text .. ".."
        end
        screen.draw_text(opt_text, x + 6, y + 5, {
            color = is_selected and theme.text or theme.text_dim,
            size = 12,
        })

        y = y + row_h
    end

    -- Scroll indicator for options
    if n > visible then
        ui.draw_scroll_indicator(opts_y, opts_h, state.option_index, n, visible)
    end
end

-- ── Footer Hints ────────────────────────────────────────────────────────────

local function get_session_hints(session)
    local stype = session.session_type
    local status = session.status
    local hints = {}

    if stype == "claude_code" then
        if status == "waiting" then
            hints = {
                {"A", "Send", theme.btn_a},
                {"B", "Escape", theme.btn_b},
                {"Y", "Ghost", theme.btn_y},
                {"\226\134\145\226\134\147", "Options", theme.btn_l},
            }
        elseif status == "thinking" then
            hints = {
                {"B", "Interrupt", theme.btn_b},
            }
        else
            hints = {}
        end
    elseif stype == "interactive_prompt" then
        hints = {
            {"A", "Enter", theme.btn_a},
            {"B", "Ctrl+C", theme.btn_b},
            {"Y", "y", theme.btn_y},
            {"X", "n", theme.btn_x},
        }
    elseif stype == "running_process" then
        hints = {
            {"B", "Ctrl+C", theme.btn_b},
            {"Y", "Ctrl+Z", theme.btn_y},
        }
    elseif stype == "idle_shell" then
        hints = {
            {"A", "Run", theme.btn_a},
            {"Y", "Ctrl+C", theme.btn_y},
            {"L2/R2", "Options", theme.btn_l},
        }
    end

    -- Always show navigation hints
    hints[#hints + 1] = {"B", "Back", theme.btn_b}
    hints[#hints + 1] = {"L1/R1", "Session", theme.btn_l}
    hints[#hints + 1] = {"\226\134\145\226\134\147", "Scroll"}

    return hints
end

-- ── Main Draw ───────────────────────────────────────────────────────────────

--- Draw the full session screen.
function M.draw(state)
    local session = state.current_session
    if not session then
        ui.draw_header("No Session")
        ui.draw_loading("Select a session from dashboard", 68, 550)
        ui.draw_footer({{"SEL", "Dashboard", theme.btn_r}})
        return
    end

    -- Header: "< L1  [session_name]  R1 >"
    local idx_display = tostring(state.session_index) .. "/" .. tostring(#state.sessions)
    ui.draw_header(safe_ascii(session.session_name or "Session"), idx_display)

    -- Status bar
    draw_status_bar(session)

    -- Terminal content
    draw_terminal(session, state)

    -- Options area
    draw_options(session, state)

    -- Footer
    ui.draw_footer(get_session_hints(session))
end

-- ── Input Handling ──────────────────────────────────────────────────────────

--- Handle input on session screen.
-- @return table|nil  {action=..., ...} action to send, or
--         string     "dashboard" to go back, "prev_session"/"next_session" to switch
function M.on_input(state, button, action)
    if action ~= "press" and action ~= "repeat" then return nil end
    local session = state.current_session
    if not session then
        if button == "select" then return "dashboard" end
        return nil
    end

    local sid = session.session_id

    -- Universal controls
    if button == "b" then return "dashboard" end
    if button == "l1" then return "prev_session" end
    if button == "r1" then return "next_session" end
    if button == "dpad_up" then
        state.terminal_scroll = state.terminal_scroll + SCROLL_STEP
        return nil
    end
    if button == "dpad_down" then
        state.terminal_scroll = math.max(0, state.terminal_scroll - SCROLL_STEP)
        return nil
    end
    if button == "select" then return "dashboard" end

    -- Mode-specific controls
    local stype = session.session_type
    local status = session.status

    if stype == "claude_code" then
        return handle_claude(state, button, session, sid, status)
    elseif stype == "interactive_prompt" then
        return handle_interactive(button, sid)
    elseif stype == "running_process" then
        return handle_running(button, sid)
    else
        return handle_idle(state, button, session, sid)
    end
end

function handle_claude(state, button, session, sid, status)
    if status == "waiting" then
        if button == "dpad_up" then
            state.option_index = math.max(1, state.option_index - 1)
        elseif button == "dpad_down" then
            local options = session.response_options or {}
            local choices = session.detected_choices or {}
            local n = #options + #choices
            state.option_index = math.min(math.max(1, n), state.option_index + 1)
        elseif button == "a" then
            local opt = get_selected_option(state, session)
            if opt then
                if opt.kind == "choice" then
                    return {action = "send_keys", session_id = sid, payload = {keys = opt.key_sequence}}
                else
                    return {action = "send_response", session_id = sid, payload = {text = opt.text}}
                end
            end
        elseif button == "y" then
            return {action = "accept_ghost", session_id = sid}
        elseif button == "b" then
            return {action = "escape", session_id = sid}
        end
    elseif status == "thinking" then
        if button == "b" then
            return {action = "interrupt", session_id = sid}
        end
    end
    return nil
end

function handle_interactive(button, sid)
    if button == "a" then
        return {action = "send_keys", session_id = sid, payload = {keys = "Enter"}}
    elseif button == "b" then
        return {action = "interrupt", session_id = sid}
    elseif button == "y" then
        return {action = "send_keys", session_id = sid, payload = {keys = "y"}}
    elseif button == "x" then
        return {action = "send_keys", session_id = sid, payload = {keys = "n"}}
    elseif button == "dpad_up" then
        return {action = "send_keys", session_id = sid, payload = {keys = "Up"}}
    elseif button == "dpad_down" then
        return {action = "send_keys", session_id = sid, payload = {keys = "Down"}}
    end
    return nil
end

function handle_running(button, sid)
    if button == "b" then
        return {action = "interrupt", session_id = sid}
    elseif button == "y" then
        return {action = "suspend", session_id = sid}
    end
    return nil
end

function handle_idle(state, button, session, sid)
    if button == "a" then
        local opt = get_selected_option(state, session)
        if opt and opt.key_sequence then
            return {action = "send_keys", session_id = sid, payload = {keys = opt.key_sequence}}
        end
    elseif button == "l2" then
        state.option_index = math.max(1, state.option_index - 1)
    elseif button == "r2" then
        local n = 4 -- default options count
        state.option_index = math.min(n, state.option_index + 1)
    elseif button == "y" then
        return {action = "interrupt", session_id = sid}
    end
    return nil
end

function get_selected_option(state, session)
    local options = session.response_options or {}
    local choices = session.detected_choices or {}
    local all = {}
    for _, o in ipairs(options) do
        all[#all + 1] = {text = o.text, category = o.category, kind = "response"}
    end
    for _, c in ipairs(choices) do
        all[#all + 1] = {
            text = c.label,
            category = c.is_default and "approve" or "custom",
            kind = "choice",
            key_sequence = c.key_sequence,
        }
    end
    if state.option_index >= 1 and state.option_index <= #all then
        return all[state.option_index]
    end
    return nil
end

return M
