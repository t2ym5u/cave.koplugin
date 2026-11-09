-- Difficulty guarantees for Cave (see docs/dev/TESTING.md, "Difficulty
-- specs"). Levels are graded by the board's no-guessing deduction solver
-- (deduce): tier 1 = clue rays, 2x2 blocks, walled-off cells; tier 2 = +
-- bottlenecks. Easy/Medium: tier 1, Easy keeps more numbers; Hard: tier 2,
-- dug as far as it allows.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Cave difficulty", function()
    local Board

    setup(function()
        Board = require("board").CaveBoard
    end)

    describe("uniqueness check and difficulty (1.6.0)", function()
        local countSolutions
        setup(function() countSolutions = require("board").countSolutions end)

        -- 1.6.0: every puzzle is proven unique by the no-guessing deduction
        -- solver at its level's tier (and re-checked by the counter), Hard
        -- leaves clearly fewer numbers than Medium, Medium fewer than Easy,
        -- and the worst generation stays well under a second on a Kobo
        -- (~25x a desktop; measured ~25 ms worst here).
        it("every puzzle is unique and solvable without guessing; levels differ; fast", function()
            local deduce, LEVELS = require("board").deduce, require("board").LEVELS
            for _, n in ipairs({ 6, 7, 8 }) do
                local ratio = {}
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    local worst, clues_sum, clear_sum = 0, 0, 0
                    for seed = 1, 30 do
                        math.randomseed(seed * 7919 + n)
                        local t0 = os.clock()
                        local b = Board:new{ n = n }
                        b:generate(diff)
                        worst = math.max(worst, os.clock() - t0)
                        local k, clear = 0, 0
                        for r = 1, n do for c = 1, n do
                            if b.clues[r][c] then k = k + 1 end
                            if not b.solution[r][c] then clear = clear + 1 end
                        end end
                        assert.is_true(clear >= n and k < clear,
                            ("n=%d diff=%s seed=%d: degenerate (%d clues, %d clear)"):format(n, diff, seed, k, clear))
                        clues_sum, clear_sum = clues_sum + k, clear_sum + clear
                        assert.is_true(deduce(b.clues, n, LEVELS[diff].tier),
                            ("n=%d diff=%s seed=%d: needs guessing"):format(n, diff, seed))
                        local solutions, exhausted = countSolutions(b.clues, n, 2, 1e6)
                        assert.is_false(exhausted)
                        assert.are.equal(1, solutions,
                            ("n=%d diff=%s seed=%d: not unique"):format(n, diff, seed))
                    end
                    ratio[diff] = clues_sum / clear_sum
                    assert.is_true(worst < 0.25, ("n=%d diff=%s took %.2fs"):format(n, diff, worst))
                end
                assert.is_true(ratio.easy > ratio.medium + 0.1,
                    ("n=%d: easy %.2f vs medium %.2f"):format(n, ratio.easy, ratio.medium))
                assert.is_true(ratio.medium > ratio.hard + 0.05,
                    ("n=%d: medium %.2f vs hard %.2f"):format(n, ratio.medium, ratio.hard))
            end
        end)

        it("Easy and Medium never need the bottleneck rule", function()
            local deduce = require("board").deduce
            for _, n in ipairs({ 6, 7, 8 }) do
                for _, diff in ipairs({ "easy", "medium" }) do
                    for seed = 1, 10 do
                        math.randomseed(seed * 31 + n)
                        local b = Board:new{ n = n }
                        b:generate(diff)
                        local ok, stats = deduce(b.clues, n, 1)
                        assert.is_true(ok)
                        assert.are.equal(0, stats.uses[3])
                    end
                end
            end
        end)

        it("same seed gives the same puzzle", function()
            local function gen()
                math.randomseed(2026)
                local b = Board:new{ n = 8 }
                b:generate("hard")
                return b:serialize()
            end
            assert.are.same(gen(), gen())
        end)

        it("the level table is ordered: numbers kept, tier, dig tries", function()
            local L = require("board").LEVELS
            assert.is_true(L.easy.floor > L.medium.floor and L.medium.floor > L.hard.floor)
            assert.is_true(L.easy.tier == 1 and L.medium.tier == 1 and L.hard.tier == 2)
            for i = 1, 3 do
                assert.is_true(L.easy.tries[i] <= L.medium.tries[i] and L.medium.tries[i] <= L.hard.tries[i])
            end
        end)

        -- Hard is the only level allowed the bottleneck rule: on averages
        -- over seeds it must actually use it.
        it("Hard uses the bottleneck rule on average", function()
            local deduce = require("board").deduce
            for _, n in ipairs({ 6, 7, 8 }) do
                local necks = 0
                for seed = 1, 8 do
                    math.randomseed(seed * 131 + n)
                    local b = Board:new{ n = n }
                    b:generate("hard")
                    local ok, stats = deduce(b.clues, n, 2)
                    assert.is_true(ok)
                    necks = necks + stats.uses[3]
                end
                assert.is_true(necks / 8 > 0, ("n=%d: hard necks avg %.2f"):format(n, necks / 8))
            end
        end)

        -- Generation is bounded by dig steps, never by time: with a clock
        -- that jumps 1000 s at every read, a seed still gives the same
        -- puzzle.
        it("generation never reads the clock", function()
            local oc, ot = os.clock, os.time
            local function gen(n, d)
                math.randomseed(4242 + n)
                local b = Board:new{ n = n }
                b:generate(d)
                return b:serialize()
            end
            for _, n in ipairs({ 6, 8 }) do
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local a = gen(n, d)
                    local t = 0
                    os.clock = function() t = t + 1000; return t end
                    os.time = function(x) if x then return ot(x) end; t = t + 1000; return t end
                    local ok, b = pcall(gen, n, d)
                    os.clock, os.time = oc, ot
                    assert.is_true(ok, tostring(b))
                    assert.are.same(a, b)
                end
            end
            local src = assert(io.open(DIR .. "board.lua")):read("*a")
            assert.is_nil(src:find("os%.clock"))
            assert.is_nil(src:find("os%.time"))
        end)
    end)
end)
