local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase      = require("screen_base")
local MenuHelper      = require("menu_helper")
local board_module    = lrequire("board")
local CaveBoardWidget = lrequire("board_widget")

local CaveBoard = board_module.CaveBoard
local SIZES     = board_module.SIZES

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Cave Puzzle — Rules

Shade some cells black to reveal a "cave" of connected white cells.

Rules:
• All white (unshaded) cells must form one single orthogonally connected group.
• Black cells must not be completely surrounded by white cells (no black cell can be enclosed in the cave).
• Numbered white cells show exactly how many white cells are visible from that position in all four orthogonal directions (including itself), until blocked by a black cell or the grid edge.

Tap a cell to shade it black. Tap again to unshade.
]])

local GAME_RULES_FR = [[
Grotte — Règles

Noircissez certaines cases pour révéler une "grotte" de cases blanches connectées.

Règles :
• Toutes les cases blanches (non noircies) doivent former un seul groupe orthogonalement connecté.
• Les cases noires ne doivent pas être complètement entourées par des cases blanches (aucune case noire ne peut être enfermée dans la grotte).
• Les cases blanches numérotées indiquent exactement combien de cases blanches sont visibles depuis cette position dans les quatre directions orthogonales (elle-même incluse), jusqu'à être bloquée par une case noire ou le bord de la grille.

Appuyez sur une case pour la noircir. Appuyez à nouveau pour la dénoircir.
]]

local CaveScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function CaveScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", 6)
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = CaveBoard:new{ n = n, difficulty = diff }
    if not self.board:load(state) then
        self.board:generate(diff)
    end
    ScreenBase.init(self)
end

function CaveScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function CaveScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Cave"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:getSizeButtonText(), callback = function() self:openSizeMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Check"), callback = function() self:onCheck() end },
            { text = _("Hint"),  callback = function() self:onHint() end },
            { text = _("Clear"), callback = function() self:onClear() end },
        }),
    }

    local frame_pad = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = CaveBoardWidget:new{
        board     = self.board,
        max_size  = math.min(budget_w, budget_h) - frame_extra,
        onCellTap = function(r, c) self:onCellTap(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function CaveScreen:onCellTap(r, c)
    self.board:cycleCell(r, c)
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    if self.board:checkWin() then
        self:updateStatus(_("Solved!"))
        self:showMessage(_("Puzzle solved!"), 3)
    else
        self:updateStatus()
    end
    self:refreshActionBar()
end

function CaveScreen:isRoundOver()
    return self.board:checkWin()
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function CaveScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "medium")
    local n    = self.plugin:getSetting("grid_n", 6)
    self.board = CaveBoard:new{ n = n, difficulty = diff }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    if n ~= self.board_widget.cols then
        self:buildLayout()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    else
        self.board_widget.board = self.board
        self.board_widget:refresh()
    end
    self:refreshActionBar()
    self:updateStatus(_("New game started."))
end

function CaveScreen:onCheck()
    if self.board:checkWin() then
        self:updateStatus(_("Solved!"))
        self:showMessage(_("Puzzle solved!"), 3)
    else
        self:updateStatus(_("Not solved yet."))
        self:showMessage(_("Not solved yet."), 2)
    end
end

function CaveScreen:onClear()
    self.board:clearUser()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:refreshActionBar()
    self:updateStatus(_("Board cleared."))
end

function CaveScreen:onGridChange(n)
    self.plugin:saveSetting("grid_n", n)
    local diff = self.plugin:getSetting("difficulty", "medium")
    self.board = CaveBoard:new{ n = n, difficulty = diff }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function CaveScreen:openSizeMenu()
    local sizes = {}
    for _, n in ipairs(SIZES) do
        sizes[#sizes + 1] = { id = n, text = n .. "\xC3\x97" .. n }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.board.n,
        parent    = self,
        on_select = function(n) self:onGridChange(n) end,
    }
end

function CaveScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Status / button text
-- ---------------------------------------------------------------------------

function CaveScreen:getSizeButtonText()
    return T(_("Size: %1"), T("%1×%2", self.board.n, self.board.n))
end

function CaveScreen:getDiffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    return MenuHelper.DIFFICULTY_LABELS[diff] or diff
end

function CaveScreen:getDiffButtonText()
    return T(_("Difficulty: %1"), self:getDiffLabel())
end

function CaveScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:checkWin() then
        status = _("Solved!")
    else
        status = self:joinStatus(
            T("%1×%1", self.board.n),
            self:getDiffLabel(),
            T(_("Shaded: %1"), self.board:countShaded()))
    end
    ScreenBase.updateStatus(self, status)
end

return CaveScreen
