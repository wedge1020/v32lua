-- test_while_break.lua

function main()
    local counter = 0
    local max_limit = 10
    local break_point = 5

    -- If your compiler doesn't support print yet, you can replace 
    -- these with whatever standard library output function you have.
    print(0, 0, "Starting the while loop test...")

	local y = 20
    while counter < max_limit do
        counter = counter + 1
        print(10, y, "Counter is at: " .. counter)
		y = y + 20

        -- Test the break statement
        if counter == break_point then
            print(0, y, "Break point reached! Exiting the loop.")
            break
        end
    end

    -- Verify that the execution resumes correctly after the loop
    print(0, 340, "Loop finished. Final counter value: " .. counter)
end
