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
    local term_h = 392  -- 68 to 460
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
-- Shows one suggestion at a time as a card. L2/R2 to navigate.

local function build_options(session)
    local options = session.response_options or {}
    local choices = session.detected_choices or {}
    local all_opts = {}
    for _, o in ipairs(options) do
        all_opts[#all_opts + 1] = {
            text = o.text or "?",
            category = o.category or "custom",
            kind = o.keys and "keys" or "response",
            key_sequence = o.keys,
        }
    end
    for _, c in ipairs(choices) do
        all_opts[#all_opts + 1] = {
            text = c.label or c.text or "?",
            category = c.is_default and "approve" or "custom",
            kind = "choice",
            key_sequence = c.key_sequence or c.keys,
        }
    end
    if #all_opts == 0 then
        all_opts[1] = {
            text = "Interrupt (Ctrl+C)",
            category = "danger",
            kind = "keys",
            key_sequence = "C-c",
        }
    end
    return all_opts
end

local function draw_options(session, state)
    local opts_y = 460
    local opts_h = 200  -- 460 to 660
    local W = 720

    screen.draw_line(0, opts_y, W, opts_y, {color = theme.border})

    local all_opts = build_options(session)
    local n = #all_opts
    state.option_index = math.max(1, math.min(state.option_index, n))
    local opt = all_opts[state.option_index]

    -- Card container
    local card_x = 10
    local card_y = opts_y + 8
    local card_w = W - 20
    local card_h = opts_h - 16
    screen.draw_card(card_x, card_y, card_w, card_h, {
        bg = theme.card_bg,
        border = theme.card_border,
        radius = 8,
        shadow = false,
    })

    -- Header row: category pill + page indicator
    local header_y = card_y + 8
    local pw = ui.draw_category_pill(opt.category, card_x + 10, header_y)

    local page_text = string.format("%d / %d", state.option_index, n)
    local ptw = screen.get_text_width(page_text, 12, true)
    screen.draw_text(page_text, card_x + card_w - ptw - 12, header_y + 1, {
        color = theme.text_dim, size = 12, bold = true,
    })

    -- Suggestion text wrapped across multiple lines
    local text_x = card_x + 14
    local text_y = header_y + 28
    local text_max_w = card_w - 28
    local size = 14
    local lh = screen.get_line_height(size, true)
    local lines = ui.word_wrap(opt.text or "", text_max_w, size, true)

    local max_lines = math.floor((card_h - 50) / lh)
    for i = 1, math.min(#lines, max_lines) do
        screen.draw_text(lines[i], text_x, text_y, {
            color = theme.text, size = size, bold = true,
        })
        text_y = text_y + lh
    end
    -- Show ellipsis if truncated
    if #lines > max_lines then
        screen.draw_text("...", text_x, text_y, {color = theme.text_dim, size = size})
    end

    -- Page navigation hints inside the card (bottom)
    local hint_y = card_y + card_h - 20
    if n > 1 then
        local left_hint = state.option_index > 1 and "< L2  " or ""
        local right_hint = state.option_index < n and "  R2 >" or ""
        local nav = left_hint .. string.format("%d/%d", state.option_index, n) .. right_hint
        local nw = screen.get_text_width(nav, 11, false)
        screen.draw_text(nav, card_x + (card_w - nw) / 2, hint_y, {
            color = theme.text_dim, size = 11,
        })
    end
end

-- ── Footer Hints ────────────────────────────────────────────────────────────

local function get_session_hints(session)
    local hints = {
        {"A", "Run", theme.btn_a},
        {"Y", "Ctrl+C", theme.btn_y},
        {"L2/R2", "Options", theme.btn_l},
        {"B", "Back", theme.btn_b},
        {"L1/R1", "Session", theme.btn_l},
        {"\226\134\145\226\134\147", "Scroll"},
    }

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

    -- All session types use the same option selection logic
    -- L2/R2: cycle options, A: execute selected, Y: interrupt
    if button == "l2" then
        state.option_index = math.max(1, state.option_index - 1)
        return nil
    elseif button == "r2" then
        local options = session.response_options or {}
        local choices = session.detected_choices or {}
        local n = math.max(1, #options + #choices)
        state.option_index = math.min(n, state.option_index + 1)
        return nil
    elseif button == "a" then
        local opt = get_selected_option(state, session)
        if opt then
            if opt.key_sequence then
                return {action = "send_keys", session_id = sid, payload = {keys = opt.key_sequence}}
            else
                return {action = "send_response", session_id = sid, payload = {text = opt.text}}
            end
        end
    elseif button == "y" then
        return {action = "interrupt", session_id = sid}
    elseif button == "x" then
        -- Quick deny/no for prompts
        if status == "waiting" then
            return {action = "send_keys", session_id = sid, payload = {keys = "C-c"}}
        end
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
