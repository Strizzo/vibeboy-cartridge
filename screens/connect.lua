-- screens/connect.lua — Connection settings screen

local ui = require("ui")

local M = {}

-- Common SSH users for cycling
local ssh_users = {"root", "srizzo", "pi", "admin", "ubuntu", "deck", "ark"}

local function cycle_value(list, current, delta)
    local idx = 1
    for i, v in ipairs(list) do
        if v == current then idx = i; break end
    end
    idx = idx + delta
    if idx < 1 then idx = #list end
    if idx > #list then idx = 1 end
    return list[idx]
end

local function parse_host(host)
    local parts = {}
    for p in host:gmatch("[^.]+") do
        parts[#parts + 1] = tonumber(p) or 0
    end
    while #parts < 4 do parts[#parts + 1] = 0 end
    return parts
end

local function build_host(parts)
    return parts[1] .. "." .. parts[2] .. "." .. parts[3] .. "." .. parts[4]
end

--- Draw the connect screen.
function M.draw(state)
    ui.draw_header("VibeBoy")

    local content_y = 50
    local W = 720
    local card_w = 400
    local card_x = (W - card_w) / 2

    -- Status card
    local status_y = content_y + 20
    local status_text, status_color
    if state.connected then
        status_text = "Connected"
        status_color = theme.positive
    elseif state.connecting then
        status_text = "Connecting..."
        status_color = theme.text_warning or theme.orange
    else
        status_text = "Disconnected"
        status_color = theme.negative
    end

    screen.draw_card(card_x, status_y, card_w, 50, {
        bg = theme.card_bg, border = theme.card_border, radius = 6,
    })
    local sw = screen.get_text_width(status_text, 18, true)
    screen.draw_text(status_text, (W - sw) / 2, status_y + 14, {
        color = status_color, size = 18, bold = true,
    })

    -- Server card
    local host_y = status_y + 70
    local editing_host = state.edit_field == "host"
    screen.draw_card(card_x, host_y, card_w, 60, {
        bg = theme.card_bg,
        border = editing_host and theme.accent or theme.card_border,
        radius = 6,
    })
    screen.draw_text("SERVER", card_x + 16, host_y + 6, {color = theme.text_dim, size = 11})

    if editing_host then
        -- Draw each octet separately, highlight the selected one
        local parts = parse_host(state.host)
        local ox = card_x + 16
        local octet = state.host_octet or 1
        for i = 1, 4 do
            local octet_str = tostring(parts[i])
            local is_sel = (i == octet)
            local c = is_sel and theme.accent or theme.text
            if is_sel then
                -- Underline the selected octet
                local ow = screen.get_text_width(octet_str, 18, true)
                screen.draw_rect(ox, host_y + 42, ow, 2, {color = theme.accent, filled = true})
            end
            screen.draw_text(octet_str, ox, host_y + 24, {color = c, size = 18, bold = true})
            ox = ox + screen.get_text_width(octet_str, 18, true)
            if i < 4 then
                screen.draw_text(".", ox, host_y + 24, {color = theme.text_dim, size = 18, bold = true})
                ox = ox + screen.get_text_width(".", 18, true)
            end
        end
        local hint = "\226\151\132\226\151\182 octet  \226\151\128\226\151\182 value"
        screen.draw_text(hint, card_x + card_w - 16 - screen.get_text_width(hint, 10, false), host_y + 28,
            {color = theme.text_dim, size = 10})
    else
        screen.draw_text(state.host, card_x + 16, host_y + 24, {color = theme.text, size = 18, bold = true})
    end

    -- Port card
    local port_y = host_y + 80
    screen.draw_card(card_x, port_y, card_w, 60, {
        bg = theme.card_bg,
        border = state.edit_field == "port" and theme.accent or theme.card_border,
        radius = 6,
    })
    screen.draw_text("DAEMON PORT", card_x + 16, port_y + 6, {color = theme.text_dim, size = 11})
    screen.draw_text(tostring(state.port), card_x + 16, port_y + 24, {color = theme.text, size = 18, bold = true})
    if state.edit_field == "port" then
        local hint = "\226\151\128 \226\151\182 adjust port"
        screen.draw_text(hint, card_x + card_w - 16 - screen.get_text_width(hint, 10, false), port_y + 28,
            {color = theme.text_dim, size = 10})
    end

    -- SSH card
    local ssh_y = port_y + 80
    local ssh_editing = state.edit_field == "ssh_user"
    local ssh_border = ssh_editing and theme.accent
        or state.ssh_enabled and theme.positive
        or theme.card_border
    screen.draw_card(card_x, ssh_y, card_w, 60, {
        bg = theme.card_bg, border = ssh_border, radius = 6,
    })

    local ssh_label = state.ssh_enabled and "SSH TUNNEL: ON" or "SSH TUNNEL: OFF"
    screen.draw_text(ssh_label, card_x + 16, ssh_y + 6, {
        color = state.ssh_enabled and theme.positive or theme.text_dim, size = 11,
    })

    if state.ssh_enabled then
        local user_str = "User: " .. state.ssh_user
        screen.draw_text(user_str, card_x + 16, ssh_y + 24, {
            color = theme.text, size = 14, bold = ssh_editing,
        })
        screen.draw_text("Key: auto from SD card or ~/.ssh/", card_x + 16, ssh_y + 42, {
            color = theme.text_dim, size = 11,
        })
        if ssh_editing then
            local hint = "\226\151\128 \226\151\182 cycle user"
            screen.draw_text(hint, card_x + card_w - 16 - screen.get_text_width(hint, 10, false), ssh_y + 28,
                {color = theme.text_dim, size = 10})
        end
    else
        screen.draw_text("Press Y to enable SSH tunneling", card_x + 16, ssh_y + 28, {
            color = theme.text_dim, size = 13,
        })
    end

    -- Connect button
    local btn_y = ssh_y + 80
    local btn_w = 200
    local btn_x = (W - btn_w) / 2
    local btn_bg = state.connecting and theme.card_bg or theme.accent
    screen.draw_card(btn_x, btn_y, btn_w, 44, {bg = btn_bg, radius = 8})
    local btn_label = state.connecting and "Connecting..." or "Connect"
    local bw = screen.get_text_width(btn_label, 16, true)
    screen.draw_text(btn_label, (W - bw) / 2, btn_y + 12, {
        color = {20, 20, 30}, size = 16, bold = true,
    })

    -- Error message
    if state.connect_error and state.connect_error ~= "" then
        local err_y = btn_y + 60
        local ew = screen.get_text_width(state.connect_error, 12, false)
        screen.draw_text(state.connect_error, math.max(10, (W - ew) / 2), err_y,
            {color = theme.negative, size = 12, max_width = W - 20})
    end

    -- Footer
    local hints = {{"A", "Connect", theme.btn_a}, {"Y", "SSH", theme.btn_y}}
    if state.edit_field then
        hints[#hints + 1] = {"B", "Done", theme.btn_b}
        hints[#hints + 1] = {"START", "Next field", theme.btn_r}
    else
        hints[#hints + 1] = {"START", "Edit", theme.btn_r}
    end
    ui.draw_footer(hints)
end

--- Handle input on connect screen.
function M.on_input(state, button, action)
    if action ~= "press" and action ~= "repeat" then return nil end

    -- Y toggles SSH
    if button == "y" and action == "press" then
        state.ssh_enabled = not state.ssh_enabled
        return nil
    end

    if state.edit_field then
        -- Editing mode
        if button == "b" then
            state.edit_field = nil
            return nil
        end
        if state.edit_field == "host" then
            local parts = parse_host(state.host)
            local octet = state.host_octet or 1
            if button == "dpad_right" then
                parts[octet] = math.min(255, parts[octet] + 1)
            elseif button == "dpad_left" then
                parts[octet] = math.max(0, parts[octet] - 1)
            elseif button == "dpad_up" then
                -- Move to previous octet
                state.host_octet = math.max(1, octet - 1)
            elseif button == "dpad_down" then
                -- Move to next octet
                state.host_octet = math.min(4, octet + 1)
            elseif button == "a" then
                -- Fast increment by 10
                parts[octet] = math.min(255, parts[octet] + 10)
            elseif button == "x" then
                -- Fast decrement by 10
                parts[octet] = math.max(0, parts[octet] - 10)
            end
            state.host = build_host(parts)
        elseif state.edit_field == "port" then
            if button == "dpad_right" then
                state.port = math.min(65535, state.port + 1)
            elseif button == "dpad_left" then
                state.port = math.max(1, state.port - 1)
            elseif button == "dpad_up" then
                state.port = math.min(65535, state.port + 100)
            elseif button == "dpad_down" then
                state.port = math.max(1, state.port - 100)
            end
        elseif state.edit_field == "ssh_user" then
            if button == "dpad_right" or button == "dpad_up" then
                state.ssh_user = cycle_value(ssh_users, state.ssh_user, 1)
            elseif button == "dpad_left" or button == "dpad_down" then
                state.ssh_user = cycle_value(ssh_users, state.ssh_user, -1)
            end
        end
        if button == "start" then
            -- Cycle through editable fields
            local fields = {"host", "port"}
            if state.ssh_enabled then
                fields[#fields + 1] = "ssh_user"
            end
            local idx = 1
            for i, f in ipairs(fields) do
                if f == state.edit_field then idx = i; break end
            end
            idx = idx + 1
            if idx > #fields then idx = 1 end
            state.edit_field = fields[idx]
            -- Reset octet selection when entering host
            if fields[idx] == "host" then
                state.host_octet = 1
            end
        end
        return nil
    end

    -- Normal mode
    if button == "a" then
        return "connect"
    elseif button == "start" then
        state.edit_field = "host"
        state.host_octet = 1
    end
    return nil
end

return M
