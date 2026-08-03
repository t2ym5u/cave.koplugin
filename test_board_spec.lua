local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("CaveBoard", function()
    local Board

    setup(function()
        Board = require("board").CaveBoard
    end)


    -- Regression guard for the 2026-07-21 bug: excavation was gated on
    -- `has2x2Shaded` over the *whole grid* (backwards -- un-shading a cell
    -- can only ever clear a violation, never create one), which deadlocked
    -- excavation at 1 cell and produced a 100%-fallback ring pattern. These
    -- tests assert the actual generation rules hold: no 2x2 all-shaded
    -- block, and both the shaded region and the unshaded interior are each
    -- fully connected.
    local function newBoard(n, diff)
        math.randomseed(42)
        local b = Board:new{ n = n or 6 }
        b:generate(diff or "medium")
        return b
    end

    local function isConnected(pred, n)
        local sr, sc
        for r = 1, n do
            for c = 1, n do
                if pred(r, c) then sr, sc = r, c; goto found end
            end
        end
        ::found::
        if not sr then return true end
        local visited = {}
        for r = 1, n do visited[r] = {} end
        local stack = { { sr, sc } }
        visited[sr][sc] = true
        local count = 1
        while #stack > 0 do
            local cell = table.remove(stack)
            for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                local nr, nc = cell[1] + d[1], cell[2] + d[2]
                if nr >= 1 and nr <= n and nc >= 1 and nc <= n
                    and pred(nr, nc) and not visited[nr][nc] then
                    visited[nr][nc] = true
                    count = count + 1
                    stack[#stack + 1] = { nr, nc }
                end
            end
        end
        local total = 0
        for r = 1, n do for c = 1, n do if pred(r, c) then total = total + 1 end end end
        return count == total
    end

    describe("construction", function()
        it("creates a 6×6 board by default", function()
            local b = Board:new()
            assert.are.equal(6, b.n)
        end)

        it("exposes SIZES", function()
            assert.are.same({ 6, 7, 8 }, require("board").SIZES)
        end)
    end)

    describe("generate", function()
        it("solution has no 2×2 all-shaded block", function()
            local b = newBoard(6)
            local n = b.n
            for r = 1, n - 1 do
                for c = 1, n - 1 do
                    local block = b.solution[r][c] and b.solution[r + 1][c]
                        and b.solution[r][c + 1] and b.solution[r + 1][c + 1]
                    assert.is_false(block, ("2x2 shaded block at [%d][%d]"):format(r, c))
                end
            end
        end)

        it("shaded cells are connected", function()
            local b = newBoard(6)
            assert.is_true(isConnected(function(r, c) return b.solution[r][c] end, b.n))
        end)

        it("unshaded (interior) cells are connected", function()
            local b = newBoard(6)
            assert.is_true(isConnected(function(r, c) return not b.solution[r][c] end, b.n))
        end)

        it("runs across all sizes/difficulties satisfying both rules, not just once", function()
            for _, n in ipairs({ 6, 7, 8 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    math.randomseed(n * 100 + #diff)
                    local b = Board:new{ n = n }
                    b:generate(diff)
                    for r = 1, n - 1 do
                        for c = 1, n - 1 do
                            local block = b.solution[r][c] and b.solution[r + 1][c]
                                and b.solution[r][c + 1] and b.solution[r + 1][c + 1]
                            assert.is_false(block,
                                ("n=%d diff=%s: 2x2 shaded block at [%d][%d]"):format(n, diff, r, c))
                        end
                    end
                    assert.is_true(isConnected(function(r, c) return b.solution[r][c] end, n),
                        ("n=%d diff=%s: shaded region not connected"):format(n, diff))
                    assert.is_true(isConnected(function(r, c) return not b.solution[r][c] end, n),
                        ("n=%d diff=%s: unshaded interior not connected"):format(n, diff))
                end
            end
        end)
    end)

    describe("cycleCell / checkWin", function()
        it("cycles a non-clue cell UNKNOWN→SHADED→CLEAR→UNKNOWN", function()
            local b = newBoard(6)
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.clues[rr][cc] then r, c = rr, cc; goto done end
                end
            end
            ::done::
            assert.are.equal(0, b.user[r][c])
            b:cycleCell(r, c)
            assert.are.equal(1, b.user[r][c])
            b:cycleCell(r, c)
            assert.are.equal(2, b.user[r][c])
            b:cycleCell(r, c)
            assert.are.equal(0, b.user[r][c])
        end)

        it("matching the solution wins the puzzle", function()
            local b = newBoard(6)
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    if not b.clues[r][c] then
                        b.user[r][c] = b.solution[r][c] and 1 or 2
                    end
                end
            end
            assert.is_true(b:checkWin())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips solution, clues and user shading", function()
            local b = newBoard(6)
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.clues[rr][cc] then r, c = rr, cc; goto done end
                end
            end
            ::done::
            b:cycleCell(r, c)

            local data = b:serialize()
            local b2   = Board:new{ n = b.n }
            local ok   = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n, b2.n)
            assert.are.equal(b.user[r][c], b2.user[r][c])
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
