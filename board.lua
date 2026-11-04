-- Cave puzzle board
-- Rules:
--   1. Shaded cells form a connected group touching the border.
--   2. Unshaded cells (the cave interior) are all orthogonally connected.
--   3. No 2x2 area is fully shaded.
--   4. Clue numbers = how many cells visible from that cell in 4 directions (incl. self).

local grid_utils = require("grid_utils")
local Hint      = require("hint")

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
-- Uniqueness counter. checkWin() is a literal full-grid comparison to
-- self.solution -- uniqueness means: given only the revealed visibility
-- clues (all on cells known to be unshaded), is there only one shaded/
-- unshaded assignment satisfying every rule as the Rules screen states
-- them (every shaded cell reaches the grid edge through shaded cells,
-- unshaded connected, no 2x2 shaded, every clue's visibility count
-- matches)?
--
-- Backtracking with propagation to a fixpoint at every node (each rule
-- below only ever forces what every solution extending the current
-- partial grid must contain, so solutions are counted exactly):
--   - per-clue ray bounds: a ray's length lies between its run of known-
--     clear cells and the next known-shaded cell (or the edge). Against
--     the clue's target, the other three rays' bounds give each ray a
--     tighter [lo, hi]: its first lo cells must be clear, and once lo ==
--     hi the cell right after must be shaded.
--   - 2x2: a block with three shaded cells has its fourth clear.
--   - connectivity, for both colours: cells that can no longer reach the
--     colour's decided cells through (that colour or undecided) cells
--     take the other colour; a decided cell cut off is a contradiction.
--     The area beyond the edge counts as one extra shaded cell next to
--     every border cell (1.6.0: before, the shaded cells had to form a
--     single group, stricter than the rules a player is given, so a grid
--     with two shaded groups each touching the edge was never counted).
-- The search branches on the cell right past a clue's known-clear run
-- (the most constrained choice), else the first undecided cell. Cell
-- state: 0 undecided, 1 shaded, 2 clear. node_budget counts search
-- nodes, so a seed gives the same verdict on every device.
-- 1.5.0: replaces a plain cell-by-cell backtracker that only checked the
-- bounds (seconds at 8x8, minutes on an e-reader).
-- ---------------------------------------------------------------------------

local function countSolutions(clues, n, limit, node_budget)
    local N = n * n
    local OUT = N + 1
    local state = {}
    for i = 1, N do state[i] = 0 end

    -- Precomputed geometry: neighbours, 2x2 blocks, each clue's four rays.
    local nbrs = {}
    for r = 1, n do for c = 1, n do
        local l = {}
        for _, d in ipairs(DIRS) do
            local nr, nc = r + d[1], c + d[2]
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n then l[#l + 1] = (nr - 1) * n + nc end
        end
        if r == 1 or r == n or c == 1 or c == n then l[#l + 1] = OUT end
        nbrs[(r - 1) * n + c] = l
    end end
    -- OUT stands for everything beyond the grid edge: always shaded and
    -- next to every border cell, so "every shaded cell reaches the edge"
    -- becomes "shaded cells and OUT form one connected group".
    local out = {}
    for r = 1, n do for c = 1, n do
        if r == 1 or r == n or c == 1 or c == n then out[#out + 1] = (r - 1) * n + c end
    end end
    nbrs[OUT] = out
    state[OUT] = 1
    local blocks = {}
    for r = 1, n - 1 do for c = 1, n - 1 do
        local i = (r - 1) * n + c
        blocks[#blocks + 1] = { i, i + 1, i + n, i + n + 1 }
    end end
    local clue_list = {}
    for r = 1, n do for c = 1, n do
        if clues[r][c] then
            local rays = {}
            for k, d in ipairs(DIRS) do
                local ray = {}
                local nr, nc = r + d[1], c + d[2]
                while nr >= 1 and nr <= n and nc >= 1 and nc <= n do
                    ray[#ray + 1] = (nr - 1) * n + nc
                    nr, nc = nr + d[1], nc + d[2]
                end
                rays[k] = ray
            end
            clue_list[#clue_list + 1] = { target = clues[r][c] - 1, rays = rays }
            state[(r - 1) * n + c] = 2
        end
    end end

    local trail, tn = {}, 0
    local changed = false
    -- Returns false on a contradiction.
    local function set(i, v)
        local s = state[i]
        if s == v then return true end
        if s ~= 0 then return false end
        state[i] = v
        tn = tn + 1; trail[tn] = i
        changed = true
        return true
    end
    local function undo(mark)
        while tn > mark do state[trail[tn]] = 0; trail[tn] = nil; tn = tn - 1 end
    end

    local conf, mx = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
    local function cluesProp()
        for _, cl in ipairs(clue_list) do
            local rays, target = cl.rays, cl.target
            local sum_min, sum_max = 0, 0
            for k = 1, 4 do
                local ray = rays[k]
                local len, j = #ray, 1
                while j <= len and state[ray[j]] == 2 do j = j + 1 end
                local cf = j - 1
                while j <= len and state[ray[j]] ~= 1 do j = j + 1 end
                conf[k], mx[k] = cf, j - 1
                sum_min, sum_max = sum_min + cf, sum_max + j - 1
            end
            if target < sum_min or target > sum_max then return false end
            for k = 1, 4 do
                local lo = target - (sum_max - mx[k])
                local hi = target - (sum_min - conf[k])
                if lo < conf[k] then lo = conf[k] end
                if hi > mx[k] then hi = mx[k] end
                if lo > hi then return false end
                local ray = rays[k]
                for j = conf[k] + 1, lo do
                    if not set(ray[j], 2) then return false end
                end
                if lo == hi and ray[hi + 1] then
                    if not set(ray[hi + 1], 1) then return false end
                end
            end
        end
        return true
    end

    local function blocksProp()
        for _, b in ipairs(blocks) do
            local shaded, free = 0, nil
            for k = 1, 4 do
                local s = state[b[k]]
                if s == 1 then shaded = shaded + 1 elseif s == 0 then free = b[k] end
            end
            if shaded == 4 then return false end
            if shaded == 3 and free then
                if not set(free, 2) then return false end
            end
        end
        return true
    end

    local seen, stamp, queue = {}, 0, {}
    for i = 1, OUT do seen[i] = 0 end
    local function regionProp(want)
        local start, decided = nil, 0
        for i = OUT, 1, -1 do
            if state[i] == want then
                decided = decided + 1
                start = i
            end
        end
        if decided == 0 then return true end
        stamp = stamp + 1
        local qh, qt = 1, 1
        queue[1] = start
        seen[start] = stamp
        local found = 1
        while qh <= qt do
            local i = queue[qh]; qh = qh + 1
            for _, j in ipairs(nbrs[i]) do
                if seen[j] ~= stamp then
                    local v = state[j]
                    if v == want or v == 0 then
                        seen[j] = stamp
                        qt = qt + 1; queue[qt] = j
                        if v == want then found = found + 1 end
                    end
                end
            end
        end
        if found ~= decided then return false end
        local other = 3 - want
        for i = 1, N do
            if state[i] == 0 and seen[i] ~= stamp then
                if not set(i, other) then return false end
            end
        end
        return true
    end

    local function propagate()
        repeat
            changed = false
            if not cluesProp() or not blocksProp()
                or not regionProp(1) or not regionProp(2) then
                return false
            end
        until not changed
        return true
    end

    local function pickCell()
        for _, cl in ipairs(clue_list) do
            for k = 1, 4 do
                local ray = cl.rays[k]
                local j = 1
                while ray[j] and state[ray[j]] == 2 do j = j + 1 end
                if ray[j] and state[ray[j]] == 0 then return ray[j] end
            end
        end
        for i = 1, N do if state[i] == 0 then return i end end
        return nil
    end

    local solutions, nodes, exhausted = 0, 0, false
    local function search()
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end
        if not propagate() then return end
        local i = pickCell()
        if not i then
            -- A full grid that passed propagate() follows every rule.
            solutions = solutions + 1
            return
        end
        for v = 2, 1, -1 do
            local mark = tn
            set(i, v)
            search()
            undo(mark)
            if solutions >= limit or exhausted then return end
        end
    end
    search()
    return solutions, exhausted, nodes
end

-- ---------------------------------------------------------------------------
-- Deduction solver (1.6.0). Applies only the rules a player uses on paper,
-- never "suppose this cell is shaded and look for a contradiction"; each
-- rule only marks what every valid grid must contain, so a grid it fills
-- in completely has exactly one solution. The generator uses it both to
-- prove uniqueness and to grade difficulty.
--   tier 1  clue rays (how far each clue can and must see), 2x2 blocks
--           (three shaded cells force the fourth clear) and walled-off
--           cells (a cell that can no longer reach the rest of its colour
--           takes the other one)
--   tier 2  + bottlenecks: a cell whose shading would split the clear
--           cells (or whose clearing would split the shaded ones) keeps
--           its colour
-- Cheaper rules run first; a rule is only tried when the ones before it
-- are stuck. Returns solved, stats: stats.uses = { rays, walls, necks }
-- counts the cells each rule decided, stats.rounds the number of passes.
-- ---------------------------------------------------------------------------

local function deduce(clues, n, tier)
    local N = n * n
    local OUT = N + 1
    local state = {}
    for i = 1, N do state[i] = 0 end

    local nbrs = {}
    for r = 1, n do for c = 1, n do
        local l = {}
        for _, d in ipairs(DIRS) do
            local nr, nc = r + d[1], c + d[2]
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n then l[#l + 1] = (nr - 1) * n + nc end
        end
        if r == 1 or r == n or c == 1 or c == n then l[#l + 1] = OUT end
        nbrs[(r - 1) * n + c] = l
    end end
    -- OUT stands for everything beyond the grid edge: always shaded and
    -- next to every border cell, so "every shaded cell reaches the edge"
    -- becomes "shaded cells and OUT form one connected group".
    local out = {}
    for r = 1, n do for c = 1, n do
        if r == 1 or r == n or c == 1 or c == n then out[#out + 1] = (r - 1) * n + c end
    end end
    nbrs[OUT] = out
    state[OUT] = 1
    local blocks = {}
    for r = 1, n - 1 do for c = 1, n - 1 do
        local i = (r - 1) * n + c
        blocks[#blocks + 1] = { i, i + 1, i + n, i + n + 1 }
    end end
    local clue_list = {}
    for r = 1, n do for c = 1, n do
        if clues[r][c] then
            local rays = {}
            for k, d in ipairs(DIRS) do
                local ray = {}
                local nr, nc = r + d[1], c + d[2]
                while nr >= 1 and nr <= n and nc >= 1 and nc <= n do
                    ray[#ray + 1] = (nr - 1) * n + nc
                    nr, nc = nr + d[1], nc + d[2]
                end
                rays[k] = ray
            end
            clue_list[#clue_list + 1] = { target = clues[r][c] - 1, rays = rays }
            state[(r - 1) * n + c] = 2
        end
    end end

    local changed, bad = 0, false
    local function set(i, v)
        local s = state[i]
        if s == v then return end
        if s ~= 0 then bad = true; return end
        state[i] = v
        changed = changed + 1
    end

    local conf, mx = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
    local function cluesProp()
        for _, cl in ipairs(clue_list) do
            local rays, target = cl.rays, cl.target
            local sum_min, sum_max = 0, 0
            for k = 1, 4 do
                local ray = rays[k]
                local len, j = #ray, 1
                while j <= len and state[ray[j]] == 2 do j = j + 1 end
                local cf = j - 1
                while j <= len and state[ray[j]] ~= 1 do j = j + 1 end
                conf[k], mx[k] = cf, j - 1
                sum_min, sum_max = sum_min + cf, sum_max + j - 1
            end
            if target < sum_min or target > sum_max then bad = true; return end
            for k = 1, 4 do
                local lo = target - (sum_max - mx[k])
                local hi = target - (sum_min - conf[k])
                if lo < conf[k] then lo = conf[k] end
                if hi > mx[k] then hi = mx[k] end
                if lo > hi then bad = true; return end
                local ray = rays[k]
                for j = conf[k] + 1, lo do set(ray[j], 2) end
                if lo == hi and ray[hi + 1] then set(ray[hi + 1], 1) end
            end
        end
    end

    local function blocksProp()
        for _, b in ipairs(blocks) do
            local shaded, free = 0, nil
            for k = 1, 4 do
                local s = state[b[k]]
                if s == 1 then shaded = shaded + 1 elseif s == 0 then free = b[k] end
            end
            if shaded == 4 then bad = true; return end
            if shaded == 3 and free then set(free, 2) end
        end
    end

    local seen, stamp, queue = {}, 0, {}
    for i = 1, OUT do seen[i] = 0 end
    local function regionProp(want)
        local start, decided = nil, 0
        for i = OUT, 1, -1 do
            if state[i] == want then
                decided = decided + 1
                start = i
            end
        end
        if decided == 0 then return end
        stamp = stamp + 1
        local qh, qt = 1, 1
        queue[1] = start
        seen[start] = stamp
        local found = 1
        while qh <= qt do
            local i = queue[qh]; qh = qh + 1
            for _, j in ipairs(nbrs[i]) do
                if seen[j] ~= stamp then
                    local v = state[j]
                    if v == want or v == 0 then
                        seen[j] = stamp
                        qt = qt + 1; queue[qt] = j
                        if v == want then found = found + 1 end
                    end
                end
            end
        end
        if found ~= decided then bad = true; return end
        local other = 3 - want
        for i = 1, N do
            if state[i] == 0 and seen[i] ~= stamp then set(i, other) end
        end
    end

    -- Bottlenecks: articulation points (Tarjan) of the want-or-undecided
    -- graph, rooted at a decided cell. An undecided cell u cutting off a
    -- subtree that holds a decided cell must take colour want (the root,
    -- itself decided, is on the other side).
    local disc, low, dsub, timer = {}, {}, {}, 0
    local function articulation(want)
        local root
        for i = OUT, 1, -1 do if state[i] == want then root = i; break end end
        if not root then return end
        for i = 1, OUT do disc[i] = 0 end
        timer = 0
        local forced = {}
        local function dfs(u)
            timer = timer + 1
            disc[u], low[u] = timer, timer
            dsub[u] = (state[u] == want) and 1 or 0
            for _, v in ipairs(nbrs[u]) do
                local s = state[v]
                if s == want or s == 0 then
                    if disc[v] == 0 then
                        dfs(v)
                        dsub[u] = dsub[u] + dsub[v]
                        if low[v] < low[u] then low[u] = low[v] end
                        if state[u] == 0 and low[v] >= disc[u] and dsub[v] > 0 then
                            forced[#forced + 1] = u
                        end
                    elseif disc[v] < low[u] then
                        low[u] = disc[v]
                    end
                end
            end
        end
        dfs(root)
        for _, u in ipairs(forced) do set(u, want) end
    end

    local uses, rounds = { 0, 0, 0 }, 0
    while true do
        changed = 0
        rounds = rounds + 1
        cluesProp(); if bad then break end
        blocksProp(); if bad then break end
        if changed > 0 then
            uses[1] = uses[1] + changed
        else
            regionProp(1); if bad then break end
            regionProp(2); if bad then break end
            if changed > 0 then
                uses[2] = uses[2] + changed
            elseif tier >= 2 then
                articulation(2); if bad then break end
                articulation(1); if bad then break end
                if changed > 0 then uses[3] = uses[3] + changed end
            end
        end
        if changed == 0 then break end
    end
    local stats = { uses = uses, rounds = rounds }
    if bad then return false, stats end
    for i = 1, N do if state[i] == 0 then return false, stats end end
    return true, stats
end

-- Per difficulty: the deduction tier the player may need, the share of
-- clear cells that stays numbered (digging stops there), and how many dig
-- orders are tried (the sparsest result is kept). Hard digs as far as the
-- bottleneck rule allows.
local LEVELS = {
    easy   = { tier = 1, floor = 0.80, tries = { 1, 1, 1 } },
    medium = { tier = 1, floor = 0.60, tries = { 1, 1, 1 } },
    hard   = { tier = 2, floor = 0.0,  tries = { 8, 5, 3 } }, -- per size 6, 7, 8

}

-- ---------------------------------------------------------------------------
-- Generate
-- ---------------------------------------------------------------------------

-- Random cave shape (1.6.0): the cave grows one cell at a time from the
-- centre, border included; a cell is only dug out if the shaded cells
-- stay one connected group touching the edge (digging more never
-- reconnects them, so a refused cell stays refused). Once the target size
-- is reached it keeps growing only to open shaded 2x2 blocks. Returns
-- the shaded grid, or nil if the attempt got stuck with a 2x2 left.
-- (Before 1.6.0 the border ring was always shaded and the dig was
-- validated only at the end, rejecting most attempts at 8x8.)
local function buildShape(n)
    local shaded = {}
    for r = 1, n do
        shaded[r] = {}
        for c = 1, n do shaded[r][c] = true end
    end
    local target = math.floor(n * n * (0.42 + math.random() * 0.18))
    local cr, cc = math.floor(n / 2) + 1, math.floor(n / 2) + 1
    shaded[cr][cc] = false
    local count = 1
    local refused = {}
    for r = 1, n do refused[r] = {} end

    local function inBlock(r, c)
        for dr = -1, 0 do for dc = -1, 0 do
            local r0, c0 = r + dr, c + dc
            if r0 >= 1 and r0 < n and c0 >= 1 and c0 < n
                and shaded[r0][c0] and shaded[r0 + 1][c0]
                and shaded[r0][c0 + 1] and shaded[r0 + 1][c0 + 1] then
                return true
            end
        end end
        return false
    end

    while true do
        local need_block = count >= target
        if need_block and not has2x2Shaded(shaded, n) then return shaded end
        local cand, cand_block = {}, {}
        for r = 1, n do for c = 1, n do
            if shaded[r][c] and not refused[r][c] then
                local touches = false
                for _, d in ipairs(DIRS) do
                    local nr, nc = r + d[1], c + d[2]
                    if nr >= 1 and nr <= n and nc >= 1 and nc <= n and not shaded[nr][nc] then
                        touches = true
                    end
                end
                if touches then
                    cand[#cand + 1] = { r, c }
                    if need_block and inBlock(r, c) then cand_block[#cand_block + 1] = { r, c } end
                end
            end
        end end
        if #cand_block > 0 then cand = cand_block end
        if #cand == 0 then return nil end
        local pick = cand[math.random(#cand)]
        local r, c = pick[1], pick[2]
        shaded[r][c] = false
        if allShadedConnected(shaded, n) and allShadedTouchBorder(shaded, n) then
            count = count + 1
        else
            shaded[r][c] = true
            refused[r][c] = true
        end
    end
end

-- 1.6.0: start from every clear cell numbered (always solvable at tier 1)
-- and remove clues one at a time in random order, keeping a removal only
-- if the level's deductions still fill in the whole grid. Before, a flat
-- share of clues was drawn at random and only all-but-full sets ever
-- proved unique, so every difficulty ended up nearly fully numbered.
-- on_progress(fraction), optional: called after every dig step
-- (screen.lua wires it to the shared "Generating puzzle…" bar).
function CaveBoard:generate(difficulty, on_progress)
    self.difficulty = difficulty or self.difficulty
    local level = LEVELS[self.difficulty] or LEVELS.medium
    local n = self.n

    local shaded
    for _ = 1, 50 do
        shaded = buildShape(n)
        if shaded then break end
    end
    if not shaded then
        -- Never reached in practice (the repair pass makes every attempt
        -- valid); a plain ring keeps the board playable regardless.
        shaded = {}
        for r = 1, n do
            shaded[r] = {}
            for c = 1, n do shaded[r][c] = isBorder(r, c, n) end
        end
    end
    for r = 1, n do
        for c = 1, n do
            self.solution[r][c] = shaded[r][c]
            self.user[r][c] = 0
        end
    end

    local cells, full = {}, {}
    for r = 1, n do
        full[r] = {}
        for c = 1, n do
            if not shaded[r][c] then
                full[r][c] = self:computeVisibility(r, c)
                cells[#cells + 1] = { r, c }
            end
        end
    end
    local keep_min = math.ceil(#cells * level.floor)
    local tries = level.tries[n - 5] or 1
    local steps, done = #cells * tries, 0
    local best, best_left, best_necks
    for _ = 1, tries do
        local clues = {}
        for r = 1, n do
            clues[r] = {}
            for c = 1, n do clues[r][c] = full[r][c] end
        end
        grid_utils.shuffle(cells)
        local left = #cells
        for _, cell in ipairs(cells) do
            done = done + 1
            if left > keep_min then
                local r, c = cell[1], cell[2]
                local v = clues[r][c]
                clues[r][c] = nil
                if deduce(clues, n, level.tier) then
                    left = left - 1
                else
                    clues[r][c] = v
                end
                if on_progress then on_progress(done / steps) end
            end
        end
        local _, stats = deduce(clues, n, level.tier)
        local necks = stats.uses[3]
        if not best or left < best_left or (left == best_left and necks > best_necks) then
            best, best_left, best_necks = clues, left, necks
        end
    end
    local clues = best
    for r = 1, n do
        for c = 1, n do self.clues[r][c] = clues[r][c] end
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

-- Like cycleCell(), but goes straight to a state. Used by the Hint button.
function CaveBoard:setCellState(r, c, v)
    if self.clues[r][c] then return false end
    self.user[r][c] = v
    return true
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

-- Marking a cell "definitely clear" is optional (checkWin only looks at
-- shading), so the solution reports non-shaded cells as empty and equals()
-- compares shaded-ness.
Hint.install(CaveBoard, {
    getUser     = function(b, r, c) return b.user[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] and 1 or 0 end,
    isEmpty     = function(v) return v == 0 end,
    equals      = function(u, s) return (u == 1) == (s == 1) end,
    isGiven     = function(b, r, c) return b.clues[r][c] == true end,
    setCell     = function(b, r, c, v) return b:setCellState(r, c, v) end,
    blank       = 0,
})

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
    CaveBoard      = CaveBoard,
    SIZES          = SIZES,
    countSolutions = countSolutions, -- exposed for the specs
    deduce         = deduce,
    LEVELS         = LEVELS,
}
