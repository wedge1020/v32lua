-- ==========================================
-- Vircon32 Lua Compiler: Feature Demo
-- ==========================================

function main()
	-- 1. Test Type Coercion & Negative Numbers
	print(0, 0, "--- TYPES & COERCION ---")
	print(0, 20, 42)            -- Positive integer float
	print(0, 40, -987)          -- Negative integer float (Testing the ftoa sign flip)
	print(0, 60, true)          -- Special Tag: True
	print(0, 80, false)         -- Special Tag: False
	print(0, 100, nil)           -- Special Tag: Nil

	-- 2. Test Strings & The Length Operator
	print(0, 140, "--- STRINGS & LENGTH ---")
	local greeting = "Hello Vircon32!"
	print(0, 160, greeting)
	print(0, 180, "String Length:")
	print(160, 180, #greeting)     -- Should print 15

	-- 3. Test Table Construction & Insertion
	print(320, 0, "--- TABLE WRITES ---")
	local vm = {}

	-- String key via bracket syntax
	vm["name"] = "Retro Console"

	-- String key via dot syntax (syntactic sugar)
	vm.cpu = "32-bit"

	-- Numeric keys
	vm[1] = "First element"
	vm[-5] = "Negative index"

	print(320, 20, "Table writes complete.")

	-- 4. Test Table Retrieval
	print(320, 60, "--- TABLE READS ---")
	print(320, 80, vm.name)       -- Should print "Retro Console"
	print(320, 100, vm["cpu"])     -- Should print "32-bit"
	print(320, 120, vm[1])         -- Should print "First element"
	print(320, 140, vm[-5])        -- Should print "Negative index"
	print(320, 160, vm.missing)    -- Should print nil (Testing unmapped keys)
end
