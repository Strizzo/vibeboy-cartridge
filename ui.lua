-- ui.lua — Shared drawing helpers (header, footer, pills, scroll indicator)

local M = {}

local W = 720
local HEADER_H = 40
local FOOTER_Y = 684
local FOOTER_H = 36

--- Draw gradient header bar with title and optional right text.
function M.draw_header(title, right_text, right_color)
    screen.draw_gradient_rect(0, 0, W, HEADER_H,
        theme.header_gradient_top.r, theme.header_gradient_top.g, theme.header_gradient_top.b,
        theme.header_gradient_bottom.r, theme.header_gradient_bottom.g, theme.header_gradient_bottom.b)
    screen.draw_line(0, 0, W, 0, {color = theme.accent})
    screen.draw_text(title, 12, 10, {color = theme.text, size = 20, bold = true})
    if right_text then
        local rc = right_color or theme.text_dim
        local rw = screen.get_text_width(right_text, 12, false)
        screen.draw_text(right_text, W - 16 - rw, 14, {color = rc, size = 12})
    end
end

--- Draw footer bar with button hints.
-- hints = {{label, action, color}, ...}
function M.draw_footer(hints)
    screen.draw_rect(0, FOOTER_Y, W, FOOTER_H, {color = theme.bg_header, filled = true})
    screen.draw_line(0, FOOTER_Y, W, FOOTER_Y, {color = theme.border})
    local x = 10
    for _, h in ipairs(hints) do
        local w = screen.draw_button_hint(h[1], h[2], x, FOOTER_Y + 8, {color = h[3], size = 12})
        x = x + w + 14
    end
end

--- Draw a status pill with category-based coloring.
function M.draw_status_pill(text, x, y, status)
    local bg_r, bg_g, bg_b = 80, 80, 100
    local tc = {255, 255, 255}
    if status == "waiting" then
        bg_r, bg_g, bg_b = 60, 160, 80
    elseif status == "thinking" then
        bg_r, bg_g, bg_b = 180, 140, 40
        tc = {30, 30, 30}
    elseif status == "running" then
        bg_r, bg_g, bg_b = 60, 120, 200
    elseif status == "error" then
        bg_r, bg_g, bg_b = 200, 60, 60
    elseif status == "idle" then
        bg_r, bg_g, bg_b = 80, 80, 100
    elseif status == "stale" then
        bg_r, bg_g, bg_b = 100, 80, 80
    end
    return screen.draw_pill(text, x, y, bg_r, bg_g, bg_b, {text_color = tc, size = 10})
end

--- Draw a session type pill.
function M.draw_type_pill(session_type, x, y)
    local label = "?"
    local bg_r, bg_g, bg_b = 80, 80, 100
    local tc = {255, 255, 255}
    if session_type == "claude_code" then
        label = "CC"
        bg_r, bg_g, bg_b = 180, 100, 255
    elseif session_type == "interactive_prompt" then
        label = "?>"
        bg_r, bg_g, bg_b = 100, 180, 255
    elseif session_type == "running_process" then
        label = ">>"
        bg_r, bg_g, bg_b = 255, 180, 60
        tc = {30, 30, 30}
    elseif session_type == "idle_shell" then
        label = "$"
        bg_r, bg_g, bg_b = 100, 220, 140
        tc = {30, 30, 30}
    elseif session_type == "stale" then
        label = ".."
        bg_r, bg_g, bg_b = 100, 80, 80
    end
    return screen.draw_pill(label, x, y, bg_r, bg_g, bg_b, {text_color = tc, size = 10})
end

--- Draw a category pill for response options.
function M.draw_category_pill(category, x, y)
    local bg_r, bg_g, bg_b = 60, 60, 80
    local tc = {200, 200, 220}
    if category == "approve" then
        bg_r, bg_g, bg_b = 40, 140, 60
        tc = {255, 255, 255}
    elseif category == "approve_plus" then
        bg_r, bg_g, bg_b = 60, 180, 80
        tc = {255, 255, 255}
    elseif category == "redirect" then
        bg_r, bg_g, bg_b = 200, 140, 40
        tc = {30, 30, 30}
    elseif category == "clarify" then
        bg_r, bg_g, bg_b = 100, 140, 220
        tc = {255, 255, 255}
    elseif category == "extend" then
        bg_r, bg_g, bg_b = 140, 100, 220
        tc = {255, 255, 255}
    elseif category == "pivot" then
        bg_r, bg_g, bg_b = 220, 100, 60
        tc = {255, 255, 255}
    elseif category == "abort" then
        bg_r, bg_g, bg_b = 200, 40, 40
        tc = {255, 255, 255}
    elseif category == "custom" then
        bg_r, bg_g, bg_b = 80, 80, 120
        tc = {200, 200, 255}
    end
    return screen.draw_pill(category, x, y, bg_r, bg_g, bg_b, {text_color = tc, size = 9})
end

--- Draw scroll indicator bar.
function M.draw_scroll_indicator(y_start, height, position, total, visible)
    if total <= visible then return end
    local ind_x = 715
    local bar_top = y_start + 4
    local bar_h = height - 8
    screen.draw_line(ind_x, bar_top, ind_x, bar_top + bar_h, {color = theme.border})
    local thumb_h = math.max(8, math.floor(bar_h * visible / total))
    local max_pos = math.max(1, total - visible)
    local progress = (position - 1) / max_pos
    if progress > 1 then progress = 1 end
    local thumb_y = bar_top + math.floor((bar_h - thumb_h) * progress)
    screen.draw_rect(ind_x - 1, thumb_y, 3, thumb_h, {color = theme.text_dim, filled = true, radius = 1})
end

--- Draw centered loading message.
function M.draw_loading(msg, y, h)
    local text = msg or "Loading..."
    local tw = screen.get_text_width(text, 16, false)
    screen.draw_text(text, (W - tw) / 2, y + h / 2 - 8, {color = theme.text_dim, size = 16})
end

--- Draw centered error message.
function M.draw_error(msg, y, h)
    local tw = screen.get_text_width(msg, 14, false)
    screen.draw_text(msg, (W - tw) / 2, y + h / 2 - 8, {color = theme.negative, size = 14})
end

--- Word-wrap text to fit within max_width pixels.
function M.word_wrap(text, max_width, font_size, bold)
    if not text or text == "" then return {""} end
    local words = {}
    for w in text:gmatch("%S+") do
        words[#words + 1] = w
    end
    if #words == 0 then return {""} end

    local lines = {}
    local current = ""
    for _, word in ipairs(words) do
        local test = current == "" and word or (current .. " " .. word)
        local tw = screen.get_text_width(test, font_size, bold or false)
        if tw <= max_width then
            current = test
        else
            if current ~= "" then
                lines[#lines + 1] = current
            end
            if screen.get_text_width(word, font_size, bold or false) > max_width then
                local chunk = ""
                for i = 1, #word do
                    local c = word:sub(i, i)
                    if screen.get_text_width(chunk .. c, font_size, bold or false) > max_width then
                        lines[#lines + 1] = chunk
                        chunk = c
                    else
                        chunk = chunk .. c
                    end
                end
                current = chunk
            else
                current = word
            end
        end
    end
    if current ~= "" then
        lines[#lines + 1] = current
    end
    if #lines == 0 then return {""} end
    return lines
end

return M
