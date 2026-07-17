-- single line comment: 7777 will not be seen in the resulting assembly
--[[ multi-line comment: 8888 will not be seen in the resulting assembly
--   blah
--   blah
--   1
--   2
--   3
--   and now wrapping it up --]]

function game_loop()

	-- indented comment: 9999 will not be seen in the resulting assembly
	a=5
	b=a+4

	--@ 4444 should be seen
	--
	--
	c=7
	--@[[ another multi-line comment, which should be seen
	-- let us see
	-- 2222 should be seen
	-- --]]
end
