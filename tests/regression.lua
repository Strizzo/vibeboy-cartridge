-- Pure Lua checks: all UI, HTTP, SSH and storage are in-memory mocks.
-- Run this file as the entry in a scratch copy of the app. Do not change the
-- production manifest. No network request or SSH process is created.
local native_screen = screen
local colors = _G.ui.public.C
local drawn, replies, requests, saved = {}, {}, {}, {}
local U = {C = colors}
local function record(value) drawn[#drawn + 1] = tostring(value or "") end
for _, method in ipairs({"rect", "rule", "panel", "tabs", "footer"}) do U[method] = function() end end
U.text = record; U.display = record
U.header = function(title, kicker, status) record(title); record(kicker); record(status) end
U.metric = function(_, _, _, _, label, value, unit) record(label); record(value); record(unit) end
U.wrap = function(value) return {tostring(value or "")} end
U.empty = function(title, body) record(title); record(body) end
U.row = function(_, _, _, _, selected) return selected and colors.bg or colors.paper, colors.muted end
_G.ui.public = U
screen = {draw_image = function() end, draw_circle = function() end,
    get_text_width = function(value, size) return #value * size / 2 end}
app = {set_idle_fps = function(value) assert(value == 1) end}
http = {
    get_async = function(url)
        local id = #requests + 1
        requests[id] = {id = id, url = url}
        return id
    end,
    poll = function() local result = replies; replies = {}; return result end,
    get = function() error("Synchronous HTTP is forbidden") end,
    get_cached = function() error("Synchronous HTTP is forbidden") end,
    post = function() error("Action messages are forbidden in these checks") end,
    post_async = function() error("Action messages are forbidden in these checks") end,
}
local function respond(id, value, status)
    replies[#replies + 1] = {id = id, status = status or 200,
        ok = status == nil or status == 200, body = json.encode(value)}
end
local function contains(value)
    for _, text in ipairs(drawn) do if text:find(value, 1, true) then return true end end
    return false
end
local function render()
    drawn = {}; on_render()
end

local tunnel_calls, close_calls, ssh_replies = 0, 0, {}
ssh = {
    tunnel = function() error("Blocking SSH is forbidden") end,
    tunnel_async = function(options)
        tunnel_calls = tunnel_calls + 1
        assert(options.key_dir == "/roms/Cartridge/ssh")
        assert(options.host == "10.0.0.0" and options.remote_port == 8766 and options.user == "root")
        return tunnel_calls
    end,
    poll = function() local result = ssh_replies; ssh_replies = {}; return result end,
    close = function() close_calls = close_calls + 1 end,
}
storage = {
    load = function(key) assert(key == "vibeboy_settings"); return nil end,
    save = function(key, value) assert(key == "vibeboy_settings"); saved[#saved + 1] = value end,
}
require("main")
on_init(); render(); assert(contains("Your server, in hand."))
on_input("a", "press"); on_input("start", "press"); on_input("x", "press")
on_input("a", "press"); on_input("x", "press")
on_input("y", "press"); on_input("y", "repeat")
on_input("start", "press"); on_input("start", "press"); on_input("dpad_right", "press")
on_input("b", "press"); on_input("a", "press"); render(); on_update(0.033333)
assert(tunnel_calls == 1 and #requests == 0, "HTTP must wait for SSH")
assert(on_update(0.033333) == false, "Pending tunnel remains responsive and idle")
ssh_replies = {{id = 1, ok = true, local_port = 8766}}
on_update(0.033333)
assert(#requests == 1 and requests[1].url == "http://127.0.0.1:8766/api/state")
local function session(name, status, keys)
    return {name = name, status = status, terminal = "Fixture output", session_type = "claude_code",
        response_options = {{text = "Fixture response", category = "clarify", keys = keys}},
        detected_choices = {{label = "Fixture choice", keys = "Escape"}}}
end
respond(1, {sessions = {a = session("Alpha", "idle"), b = session("Beta", "waiting", "Enter")}})
on_update(0.033333); render()
assert(contains("Remote sessions") and #saved == 1)
assert(saved[1].host == "10.0.0.0" and saved[1].ssh_enabled and saved[1].ssh_user == "root")
on_input("a", "press"); render(); assert(contains("Beta"))
-- Reordering must not retarget a session currently being viewed.
on_update(1.1)
respond(2, {sessions = {a = session("Alpha", "waiting"), b = session("Beta", "idle", "Enter")}})
on_update(0.033333); render()
assert(contains("Beta"), "Reordering must retain the selected session identity")
-- Cancel SSH, ignore a late result, then cancel from field edit and HTTP phase.
on_input("b", "press"); on_input("b", "press")
on_input("a", "press"); render(); on_update(0.033333)
assert(tunnel_calls == 2 and #requests == 2)
on_input("b", "press")
ssh_replies = {{id = 2, ok = true, local_port = 8766}}
on_update(0.033333); render()
assert(#requests == 2 and contains("Connection settings"), "Late cancelled tunnel must not start HTTP")
on_input("a", "press"); render(); on_update(0.033333)
on_input("start", "press")
ssh_replies = {{id = 3, ok = false, error = "Late SSH error"}}
on_update(0.033333); render()
assert(not contains("Late SSH error") and #requests == 2)
on_input("b", "press"); on_input("a", "press"); render(); on_update(0.033333)
ssh_replies = {{id = 4, ok = true, local_port = 8766}}
on_update(0.033333)
assert(#requests == 3)
on_input("y", "press")
respond(3, {sessions = {a = session("Late HTTP session", "waiting")}})
on_update(0.033333); render()
assert(contains("Connection settings") and not contains("Late HTTP session"))
-- Payload checks call the controller module directly. They never call /api/action.
local view = require("screens.session")
local local_session = {session_id = "fixture", response_options = {{text = "Fixture response", keys = "Enter"}},
    detected_choices = {{text = "Fixture choice", keys = "Escape"}}, status = "waiting"}
local state = {current_session = local_session, option_index = 1, terminal_scroll = 0}
local action = view.on_input(state, "a", "press")
assert(action.action == "send_keys" and action.payload.keys == "Enter")
view.on_input(state, "r2", "press"); action = view.on_input(state, "a", "press")
assert(action.payload.keys == "Escape")
state.current_session.response_options, state.current_session.detected_choices = {}, {}
state.option_index = 10
assert(view.on_input(state, "a", "press").payload.keys == "C-c", "Fallback must match displayed option")
assert(view.on_input(state, "y", "press").action == "interrupt")
assert(view.on_input(state, "x", "press").payload.keys == "C-c")
view.on_input(state, "dpad_up", "press"); assert(state.terminal_scroll == 3)
view.on_input(state, "dpad_down", "press"); assert(state.terminal_scroll == 0)
assert(view.on_input(state, "l1", "press") == "prev_session")
assert(view.on_input(state, "r1", "press") == "next_session")
assert(view.on_input(state, "b", "press") == "dashboard")
assert(view.on_input(state, "select", "press") == "dashboard")
on_destroy(); assert(close_calls >= 4)
print("PASS VibeBoy: setup, IP/SSH fields, async SSH gating/cancellation/late results, storage/security contract, session identity, option/key payloads, fallback, controller bindings")
function on_init() end
function on_update() return false end
function on_render() native_screen.clear(18, 22, 24) end
