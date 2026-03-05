-- api.lua — HTTP client wrapper for VibeBoy daemon

local M = {}

--- Poll full state from daemon.
-- @param host string  e.g. "192.168.1.100"
-- @param port number  e.g. 8766
-- @return table|nil   parsed state table, or nil on error
-- @return string|nil  error message on failure
function M.poll_state(host, port)
    local url = "http://" .. host .. ":" .. tostring(port) .. "/api/state"
    local ok, resp = pcall(http.get, url)
    if not ok then
        return nil, "Connection failed"
    end
    if not resp.ok then
        return nil, "HTTP " .. tostring(resp.status or "error")
    end
    local dok, data = pcall(json.decode, resp.body)
    if not dok or not data then
        return nil, "Invalid JSON"
    end
    return data, nil
end

--- Send an action to the daemon.
-- @param host    string
-- @param port    number
-- @param action  string   e.g. "send_response", "interrupt"
-- @param session_id string
-- @param payload table|nil  optional payload
-- @return boolean success
-- @return string|nil error message
function M.send_action(host, port, action, session_id, payload)
    local url = "http://" .. host .. ":" .. tostring(port) .. "/api/action"
    local body = json.encode({
        action = action,
        session_id = session_id,
        payload = payload or {},
    })
    local ok, resp = pcall(http.post, url, body)
    if not ok then
        return false, "Connection failed"
    end
    if not resp.ok then
        return false, "HTTP " .. tostring(resp.status or "error")
    end
    return true, nil
end

return M
