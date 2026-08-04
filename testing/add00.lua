function main()
	ioports.gpu.clear("black")

	-- Test 1: Basic append
	t = {}
	add(t, 42)
	add(t, 43)
	print(0, 0, "Test 1 - Append:")   -- Title
	__rawasm__("__debug:")
	print(0, 20, t[1])              -- Should print: 42
	print(0, 40, t[2])              -- Should print: 43

	-- Test 2: Insert at position
	t2 = {10, 20, 30}
	add(t2, 15, 2)
	print(0, 80, "Test 2 - Insert at pos 2:")  -- Title
	print(0, 100, t2[1])             -- Should print: 10
	print(0, 120, t2[2])             -- Should print: 15
	print(0, 140, t2[3])             -- Should print: 20
	print(0, 160, t2[4])             -- Should print: 30

	-- Test 3: Return value check
	x = add(t, 99)
	print(0, 200, "Test 3 - Return value:") -- Title
	print(0, 220, x)                -- Should print: 99

	-- Test 4: Insert at beginning
	t3 = {1, 2, 3}
	add(t3, 0, 1)
	print(0, 260, "Test 4 - Insert at pos 1:") -- Title
	print(0, 280, t3[1])             -- Should print: 0
	print(0, 300, t3[2])             -- Should print: 1
	print(0, 320, t3[3])             -- Should print: 2
	print(0, 340, t3[4])             -- Should print: 3

	-- Test 5: Table length verification
	t4 = {}
	add(t4, 100)
	add(t4, 200)
	add(t4, 300)
	print(320, 0, "Test 5 - Length:")   -- Title
	print(320, 20, #t4)                -- Should print: 3
end
