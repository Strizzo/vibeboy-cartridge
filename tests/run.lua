-- Run from the repository root with Lua 5.4. No network, SSH or disk writes.
package.path = "./?.lua;./?/init.lua;" .. package.path
local payloads, next_id = {}, 0
json = {
  encode = function(value)
    next_id = next_id + 1
    local token = "fixture-json:" .. next_id
    payloads[token] = value
    return token
  end,
  decode = function(token)
    assert(payloads[token] ~= nil, "Invalid fixture JSON")
    return payloads[token]
  end,
}
ui = {public = {C = {bg={18,22,24}, paper={242,237,228}, muted={166,174,170},
  quiet={120,133,127}, red={238,83,51}, green={153,195,119}, gold={231,185,88},
  teal={116,190,184}, panel={28,33,35}, panel2={40,45,47}, line={63,73,70}}}}
screen = {clear=function() end}
require("tests.regression")
