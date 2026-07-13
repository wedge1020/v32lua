-- ==========================================
-- Vircon32 Lua Compiler: Feature Demo
-- ==========================================

function main()
	-- 1. Test Type Coercion & Negative Numbers
	print("--- TYPES & COERCION ---")
	print(42)            -- Positive integer float
	print(-987)          -- Negative integer float (Testing the ftoa sign flip)
	print(true)          -- Special Tag: True
	print(false)         -- Special Tag: False
	print(nil)           -- Special Tag: Nil

	-- 2. Test Strings & The Length Operator
	print("--- STRINGS & LENGTH ---")
	local greeting = "Hello Vircon32!"
	print(greeting)
	print("String Length:")
	print(#greeting)     -- Should print 15

	-- 3. Test Table Construction & Insertion
	print("--- TABLE WRITES ---")
	local vm = {}

	-- String key via bracket syntax
	vm["name"] = "Retro Console"

	-- String key via dot syntax (syntactic sugar)
	vm.cpu = "32-bit"

	-- Numeric keys
	vm[1] = "First element"
	vm[-5] = "Negative index"

	print("Table writes complete.")

	-- 4. Test Table Retrieval
	print("--- TABLE READS ---")
	print(vm.name)       -- Should print "Retro Console"
	print(vm["cpu"])     -- Should print "32-bit"
	print(vm[1])         -- Should print "First element"
	print(vm[-5])        -- Should print "Negative index"
	print(vm.missing)    -- Should print nil (Testing unmapped keys)

	-- 5. Test Terminal Scrolling
	-- At this point, we have printed exactly 16 lines.
	-- The next print calls should trigger the history shift loop.
	print("--- SCROLL TEST ---")
	print("Scrolling line 1")
	print("Scrolling line 2")
	print("End of demo.")
end
