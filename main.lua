local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase  = require("plugin_base")
local _           = require("gettext")
local CaveScreen  = lrequire("screen")

local CavePlugin = PluginBase:extend{
    name      = "cave",
    menu_text = _("Cave"),
    menu_hint = "tools",
}

function CavePlugin:createScreen()
    return CaveScreen:new{ plugin = self }
end

return CavePlugin
