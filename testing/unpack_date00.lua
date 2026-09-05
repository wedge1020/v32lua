-- === EXPECTED OUTPUT ===
-- test8:  addr -> "2026-09-06"
-- test9:  addr -> "2024-02-29"   (leap-year boundary)
-- test10: addr -> "2026-01-01"

hex_result_test8_addr  = 0
hex_result_test9_addr  = 0
hex_result_test10_addr = 0

function main()
	-- --- test8: (2026, 9, 6) ---
	__rawasm__("
		MOV R0, 2026
		PUSH R0
		MOV R0, 9
		PUSH R0
		MOV R0, 6
		PUSH R0
		CALL __builtin_format_date_string
		IADD SP, 3
		AND  R0, BOXED_PAYLOAD
		MOV  {hex_result_test8_addr}, R0
	")
	__rawasm__("__debug8:")

	-- --- test9: (2024, 2, 29) -- leap-year boundary ---
	__rawasm__("
		MOV R0, 2024
		PUSH R0
		MOV R0, 2
		PUSH R0
		MOV R0, 29
		PUSH R0
		CALL __builtin_format_date_string
		IADD SP, 3
		AND  R0, BOXED_PAYLOAD
		MOV  {hex_result_test9_addr}, R0
	")
	__rawasm__("__debug9:")

	-- --- test10: (2026, 1, 1) ---
	__rawasm__("
		MOV R0, 2026
		PUSH R0
		MOV R0, 1
		PUSH R0
		MOV R0, 1
		PUSH R0
		CALL __builtin_format_date_string
		IADD SP, 3
		AND  R0, BOXED_PAYLOAD
		MOV  {hex_result_test10_addr}, R0
	")
	__rawasm__("__debug10:")
end
