-- =========================================================
-- Vircon32 Lua Compiler: Unary Operations Test Suite
-- =========================================================

function main()
	print("--- 1. UNARY MINUS (-) ---")
	local x = 42
	local y = -x
	print(y)             -- Expected: -42 (Variable negation)
	print(-0)            -- Expected: 0 or -0 (IEEE 754 sign flip test)
	print(-(-987))       -- Expected: 987 (Double negation)
	print(-(10 + 15))    -- Expected: -25 (Expression negation)

	print("--- 2. LOGICAL NOT (not) ---")
	-- In Lua, ONLY false and nil are falsy! Everything else is truthy.
	print(not false)     -- Expected: true
	print(not nil)       -- Expected: true
	print(not not false) -- Expected: false (Double not)

	print("--- 3. TRUTHINESS EDGE CASES ---")
	-- Testing that numbers and strings are evaluated as truthy
	print(not true)      -- Expected: false
	print(not 0)         -- Expected: false (0 is truthy in Lua!)
	print(not -1)        -- Expected: false
	print(not "hello")   -- Expected: false (Strings are truthy!)

	print("--- 4. LENGTH OPERATOR (#) ---")
	local str = "Vircon32"
	print(#str)          -- Expected: 8
	print(#"")           -- Expected: 0 (Empty string literal)
	print(#("Super" .. "CPU")) -- Expected: 8 (If concat is enabled, otherwise test variable)

	print("--- 5. COMBINED UNARY LOGIC ---")
	-- Combining them into complex expressions
	local val = -50
	print(not (val == -50)) -- Expected: false
	print(-( #str ))        -- Expected: -8 (Negating a length result)

	print("--- UNARY TESTS COMPLETE ---")
end
