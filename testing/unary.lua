-- =========================================================
-- Vircon32 Lua Compiler: Unary Operations Test Suite
-- =========================================================

function game_loop()
	local y = 0
	print(0, y, "--- 1. UNARY MINUS (-) ---")
	y = y + 20
	local a = 42
	local b = -x
	print(0, y, b)             -- Expected: -42 (Variable negation)
	y = y + 20
	print(0, y, -0)            -- Expected: 0 or -0 (IEEE 754 sign flip test)
	y = y + 20
	print(0, y, -(-987))       -- Expected: 987 (Double negation)
	y = y + 20
	print(0, y, -(10 + 15))    -- Expected: -25 (Expression negation)
	y = y + 20

	print(0, y, "--- 2. LOGICAL NOT (not) ---")
	y = y + 20
	-- In Lua, ONLY false and nil are falsy! Everything else is truthy.
	print(0, y, not false)     -- Expected: true
	y = y + 20
	print(0, y, not nil)       -- Expected: true
	y = y + 20
	print(0, y, not not false) -- Expected: false (Double not)
	y = y + 20

	print(0, y, "--- 3. TRUTHINESS EDGE CASES ---")
	y = y + 20
	-- Testing that numbers and strings are evaluated as truthy
	print(0, y, not true)      -- Expected: false
	y = y + 20
	print(0, y, not 0)         -- Expected: false (0 is truthy in Lua!)
	y = y + 20
	print(0, y, not -1)        -- Expected: false
	y = y + 20
	print(0, y, not "hello")   -- Expected: false (Strings are truthy!)
	y = y + 20

	y = 0
	print(320, y, "--- 4. LENGTH OPERATOR (#) ---")
	y = y + 20
	local str = "Vircon32"
	print(320, y, #str)          -- Expected: 8
	y = y + 20
	print(320, y, #"")           -- Expected: 0 (Empty string literal)
	y = y + 20
	print(320, y, #("Super" .. "CPU")) -- Expected: 8 (If concat is enabled, otherwise test variable)
	y = y + 20

	print(320, y, "--- 5. COMBINED UNARY LOGIC ---")
	y = y + 20
	-- Combining them into complex expressions
	local val = -50
	print(320, y, not (val == -50)) -- Expected: false
	y = y + 20
	print(320, y, -( #str ))        -- Expected: -8 (Negating a length result)
	y = y + 20

	print(320, y, "--- UNARY TESTS COMPLETE ---")

	system.halt()
end
