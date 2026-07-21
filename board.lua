-- Cave puzzle board
-- Rules:
--   1. Shaded cells form a connected group touching the border.
--   2. Unshaded cells (the cave interior) are all orthogonally connected.
--   3. No 2x2 area is fully shaded.
--   4. Clue numbers = how many cells visible from that cell in 4 directions (incl. self).

local grid_utils = require("grid_utils")

local SIZES = { 6, 7, 8 }

local DIRS = { {0,1},{0,-1},{1,0},{-1,0} }

local CaveBoard = {}
CaveBoard.__index = CaveBoard

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function CaveBoard:new(opts)
    opts = opts or {}
    local n = opts.n or 6
    local obj = {
        n          = n,
        difficulty = opts.difficulty or "medium",
        solution   = {},   -- solution[r][c] = true if shaded
        clues      = {},   -- clues[r][c] = number or nil
        user       = {},   -- user[r][c]: 0=unknown, 1=shaded, 2=unshaded
    }
    for r = 1, n do
        obj.solution[r] = {}
        obj.clues[r]    = {}
        obj.user[r]     = {}
        for c = 1, n do
            obj.solution[r][c] = false
            obj.clues[r][c]    = nil
            obj.user[r][c]     = 0
        end
    end
    setmetatable(obj, self)
    return obj
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function isBorder(r, c, n)
    return r == 1 or r == n or c == 1 or c == n
end

local function bfsCount(grid, n, start_r, start_c, value)
    -- Count cells reachable from (start_r, start_c) where grid[r][c] == value
    if grid[start_r][start_c] ~= value then return 0, {} end
    local visited = {}
    local queue   = { {start_r, start_c} }
    local head    = 1
    local count   = 0
    local cells   = {}
    local function key(r, c) return r * 100 + c end
    visited[key(start_r, start_c)] = true
    while head <= #queue do
        local cell = queue[head]; head = head + 1
        local r, c = cell[1], cell[2]
        count = count + 1
        cells[#cells + 1] = {r, c}
        for _, d in ipairs(DIRS) do
            local nr, nc = r + d[1], c + d[2]
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                local k = key(nr, nc)
                if not visited[k] and grid[nr][nc] == value then
                    visited[k] = true
                    queue[#queue + 1] = {nr, nc}
                end
            end
        end
    end
    return count, cells
end

local function totalShaded(shaded, n)
    local cnt = 0
    for r = 1, n do
        for c = 1, n do
            if shaded[r][c] then cnt = cnt + 1 end
        end
    end
    return cnt
end

local function has2x2Shaded(shaded, n)
    for r = 1, n - 1 do
        for c = 1, n - 1 do
            if shaded[r][c] and shaded[r+1][c] and shaded[r][c+1] and shaded[r+1][c+1] then
                return true
            end
        end
    end
    return false
end

local function allShadedConnected(shaded, n)
    -- Find one shaded cell
    local sr, sc
    for r = 1, n do
        for c = 1, n do
            if shaded[r][c] then sr, sc = r, c; break end
        end
        if sr then break end
    end
    if not sr then return true end  -- no shaded cells

    -- Convert to 0/1 grid for bfsCount
    local g = {}
    for r = 1, n do
        g[r] = {}
        for c = 1, n do g[r][c] = shaded[r][c] and 1 or 0 end
    end
    local cnt = bfsCount(g, n, sr, sc, 1)
    return cnt == totalShaded(shaded, n)
end

local function allUnshadedConnected(shaded, n)
    -- Find one unshaded cell
    local sr, sc
    for r = 1, n do
        for c = 1, n do
            if not shaded[r][c] then sr, sc = r, c; break end
        end
        if sr then break end
    end
    if not sr then return true end

    local g = {}
    local total = 0
    for r = 1, n do
        g[r] = {}
        for c = 1, n do
            g[r][c] = shaded[r][c] and 0 or 1
            if not shaded[r][c] then total = total + 1 end
        end
    end
    local cnt = bfsCount(g, n, sr, sc, 1)
    return cnt == total
end

local function allShadedTouchBorder(shaded, n)
    -- All shaded cells must be reachable from the border's shaded cells
    -- Since shaded is connected, just check one border shaded cell exists
    for r = 1, n do
        for c = 1, n do
            if shaded[r][c] and isBorder(r, c, n) then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Visibility (clue value)
-- ---------------------------------------------------------------------------

function CaveBoard:computeVisibility(r, c)
    local n = self.n
    local count = 1  -- self
    for _, d in ipairs(DIRS) do
        local nr, nc = r + d[1], c + d[2]
        while nr >= 1 and nr <= n and nc >= 1 and nc <= n and not self.solution[nr][nc] do
            count = count + 1
            nr = nr + d[1]
            nc = nc + d[2]
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Generate
-- ---------------------------------------------------------------------------

function CaveBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n

    local keep_clues
    if self.difficulty == "easy" then
        keep_clues = 0.6
    elseif self.difficulty == "hard" then
        keep_clues = 0.2
    else
        keep_clues = 0.4
    end

    local max_attempts = 50
    local ok = false

    for _attempt = 1, max_attempts do
        -- Start with all cells shaded
        local shaded = {}
        for r = 1, n do
            shaded[r] = {}
            for c = 1, n do shaded[r][c] = true end
        end

        -- Excavate interior cells starting from center
        local cr = math.floor(n / 2) + 1
        local cc = math.floor(n / 2) + 1

        -- Decide how many interior cells to unshade
        local interior_n = (n - 2) * (n - 2)
        local target_unshaded = math.floor(interior_n * (0.35 + math.random() * 0.25))
        target_unshaded = math.max(target_unshaded, 2)

        -- BFS excavation from center
        shaded[cr][cc] = false
        local frontier = { {cr, cc} }
        local unshaded_count = 1
        local visited = {}
        local function vkey(r, c) return r * 100 + c end
        visited[vkey(cr, cc)] = true

        local iter_limit = target_unshaded * 10
        local iters = 0
        while unshaded_count < target_unshaded and #frontier > 0 do
            iters = iters + 1
            if iters > iter_limit then break end

            local idx = math.random(#frontier)
            local cell = frontier[idx]
            local r, c = cell[1], cell[2]

            -- Try expanding to a neighbor
            local neighbors = {}
            for _, d in ipairs(DIRS) do
                local nr, nc = r + d[1], c + d[2]
                if nr >= 2 and nr <= n-1 and nc >= 2 and nc <= n-1 then
                    local k = vkey(nr, nc)
                    if not visited[k] and shaded[nr][nc] then
                        neighbors[#neighbors + 1] = {nr, nc}
                    end
                end
            end

            if #neighbors == 0 then
                -- Remove from frontier
                table.remove(frontier, idx)
            else
                local nb = neighbors[math.random(#neighbors)]
                local nr, nc = nb[1], nb[2]
                -- Un-shading a cell can only clear 2x2-shaded violations, never
                -- create one, so no per-step check is needed here — the final
                -- has2x2Shaded(shaded, n) check below (after excavation stops)
                -- is what actually gates acceptance of the whole attempt.
                shaded[nr][nc] = false
                local k = vkey(nr, nc)
                visited[k] = true
                frontier[#frontier + 1] = {nr, nc}
                unshaded_count = unshaded_count + 1
            end
        end

        -- Repair pass: the random-walk excavation above rarely reaches every
        -- interior cell (especially ones near a corner/edge, far from the
        -- center start point), so 2x2-shaded violations against the border
        -- ring are common at this point. Every such violation must include
        -- at least one interior cell (the border ring is only 1 cell thick),
        -- so unshading one interior cell per violating block always resolves
        -- it; a single raster-order pass fixes all of them since unshading
        -- only ever removes violations, never creates new ones.
        for r = 1, n - 1 do
            for c = 1, n - 1 do
                if shaded[r][c] and shaded[r+1][c] and shaded[r][c+1] and shaded[r+1][c+1] then
                    for _, pos in ipairs({{r,c},{r+1,c},{r,c+1},{r+1,c+1}}) do
                        local pr, pc = pos[1], pos[2]
                        if pr >= 2 and pr <= n-1 and pc >= 2 and pc <= n-1 then
                            shaded[pr][pc] = false
                            unshaded_count = unshaded_count + 1
                            break
                        end
                    end
                end
            end
        end

        -- Validate constraints
        if not has2x2Shaded(shaded, n)
            and allUnshadedConnected(shaded, n)
            and allShadedConnected(shaded, n)
            and allShadedTouchBorder(shaded, n)
            and unshaded_count >= 2
        then
            -- Store solution
            for r = 1, n do
                for c = 1, n do
                    self.solution[r][c] = shaded[r][c]
                end
            end

            -- Compute clues for unshaded cells
            for r = 1, n do
                for c = 1, n do
                    self.clues[r][c] = nil
                end
            end
            local clue_candidates = {}
            for r = 1, n do
                for c = 1, n do
                    if not shaded[r][c] then
                        clue_candidates[#clue_candidates + 1] = {r, c}
                    end
                end
            end
            -- Shuffle and keep some
            grid_utils.shuffle(clue_candidates)
            local keep = math.max(2, math.floor(#clue_candidates * keep_clues))
            for i = 1, keep do
                local r, c = clue_candidates[i][1], clue_candidates[i][2]
                self.clues[r][c] = self:computeVisibility(r, c)
            end

            -- Reset user grid
            for r = 1, n do
                for c = 1, n do self.user[r][c] = 0 end
            end

            ok = true
            break
        end
    end

    if not ok then
        -- Fallback: simple ring pattern
        for r = 1, n do
            for c = 1, n do
                self.solution[r][c] = isBorder(r, c, n)
                self.clues[r][c]    = nil
                self.user[r][c]     = 0
            end
        end
        -- Add one clue in the center
        local cr2 = math.ceil(n / 2)
        local cc2 = math.ceil(n / 2)
        self.clues[cr2][cc2] = self:computeVisibility(cr2, cc2)
    end
end

-- ---------------------------------------------------------------------------
-- User interaction
-- ---------------------------------------------------------------------------

function CaveBoard:cycleCell(r, c)
    -- Cannot shade clue cells
    if self.clues[r][c] then return end
    local cur = self.user[r][c]
    if cur == 0 then
        self.user[r][c] = 1
    elseif cur == 1 then
        self.user[r][c] = 2
    else
        self.user[r][c] = 0
    end
end

function CaveBoard:clearUser()
    local n = self.n
    for r = 1, n do
        for c = 1, n do self.user[r][c] = 0 end
    end
end

-- ---------------------------------------------------------------------------
-- Win check
-- ---------------------------------------------------------------------------

function CaveBoard:checkWin()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local sol_shaded  = self.solution[r][c]
            local user_shaded = (self.user[r][c] == 1)
            local user_clear  = (self.user[r][c] == 2)
            -- Clue cells are always unshaded
            if self.clues[r][c] then
                if user_shaded then return false end
            else
                if sol_shaded  and not user_shaded then return false end
                if not sol_shaded and user_shaded  then return false end
            end
        end
    end
    return true
end

function CaveBoard:countShaded()
    local n, cnt = self.n, 0
    for r = 1, n do
        for c = 1, n do
            if self.user[r][c] == 1 then cnt = cnt + 1 end
        end
    end
    return cnt
end

-- ---------------------------------------------------------------------------
-- Serialize / load
-- ---------------------------------------------------------------------------

function CaveBoard:serialize()
    local n = self.n
    local sol, usr, clues = {}, {}, {}
    for r = 1, n do
        sol[r]   = {}
        usr[r]   = {}
        clues[r] = {}
        for c = 1, n do
            sol[r][c]   = self.solution[r][c]
            usr[r][c]   = self.user[r][c]
            clues[r][c] = self.clues[r][c]
        end
    end
    return { n = n, difficulty = self.difficulty, solution = sol, user = usr, clues = clues }
end

function CaveBoard:load(data)
    if not data or not data.solution or not data.user or not data.n then return false end
    local n = data.n
    if n ~= 6 and n ~= 7 and n ~= 8 then return false end
    self.n          = n
    self.difficulty = data.difficulty or "medium"
    self.solution   = {}
    self.user       = {}
    self.clues      = {}
    for r = 1, n do
        self.solution[r] = {}
        self.user[r]     = {}
        self.clues[r]    = {}
        for c = 1, n do
            self.solution[r][c] = data.solution[r] and data.solution[r][c] or false
            self.user[r][c]     = data.user[r] and data.user[r][c] or 0
            self.clues[r][c]    = data.clues and data.clues[r] and data.clues[r][c] or nil
        end
    end
    return true
end

return {
    CaveBoard = CaveBoard,
    SIZES     = SIZES,
}
