local Blitbuffer  = require("ffi/blitbuffer")
local Font        = require("ui/font")
local Geom        = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local RenderText  = require("ui/rendertext")
local UIManager   = require("ui/uimanager")

local gw_module      = require("grid_widget_base")
local GridWidgetBase = gw_module.GridWidgetBase
local drawLine       = gw_module.drawLine

local CaveBoardWidget = GridWidgetBase:extend{
    board      = nil,
    size_ratio = 0.78,
}

function CaveBoardWidget:init()
    local n   = self.board.n
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)

    -- Override gesture events so the range covers our paint_rect
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            }
        },
    }
end

function CaveBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then return false end
    if self.onCellTap then self:onCellTap(row, col) end
    return true
end

function CaveBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

function CaveBoardWidget:paintTo(bb, x, y)
    if not self.board then return end

    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local n   = self.board.n
    local cw  = self.cell_w
    local ch  = self.cell_h

    -- Background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)

    local shade_color = Blitbuffer.COLOR_GRAY_4
    local dot_color   = Blitbuffer.COLOR_GRAY_9

    for r = 1, n do
        for c = 1, n do
            local cx  = x + math.floor((c - 1) * cw)
            local cy  = y + math.floor((r - 1) * ch)
            local cew = math.ceil(cw)
            local ceh = math.ceil(ch)

            local state = self.board.user[r][c]
            local clue  = self.board.clues[r][c]

            if clue then
                -- Clue cell: white background with number
                bb:paintRect(cx, cy, cew, ceh, Blitbuffer.COLOR_WHITE)
                local txt  = tostring(clue)
                local face = self.number_face
                local m    = RenderText:sizeUtf8Text(0, cew, face, txt, true, false)
                local tx   = cx + math.floor((cew - m.x) / 2)
                local ty   = cy + math.floor(ceh / 2) - math.floor((m.y_bottom - m.y_top) / 2) - m.y_top
                RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, Blitbuffer.COLOR_BLACK)
            elseif state == 1 then
                -- User marked shaded
                bb:paintRect(cx, cy, cew, ceh, shade_color)
            elseif state == 2 then
                -- User marked unshaded: white with small dot
                bb:paintRect(cx, cy, cew, ceh, Blitbuffer.COLOR_WHITE)
                local dot_r = math.max(1, math.floor(math.min(cew, ceh) / 8))
                local dot_x = cx + math.floor(cew / 2) - dot_r
                local dot_y = cy + math.floor(ceh / 2) - dot_r
                bb:paintRect(dot_x, dot_y, dot_r * 2, dot_r * 2, dot_color)
            else
                -- Unknown: white
                bb:paintRect(cx, cy, cew, ceh, Blitbuffer.COLOR_WHITE)
            end
        end
    end

    -- Grid lines
    local thin  = 1
    local thick = math.max(2, math.floor(math.min(cw, ch) / 10))
    local gsize = self.size

    for i = 0, n do
        local px = x + math.floor(i * cw)
        local py = y + math.floor(i * ch)
        local lw = (i == 0 or i == n) and thick or thin
        drawLine(bb, px, y,  lw, gsize, Blitbuffer.COLOR_BLACK)
        drawLine(bb, x,  py, gsize, lw, Blitbuffer.COLOR_BLACK)
    end
end

return CaveBoardWidget
