-- test_while_break.lua

function main()
    local counter = 0
    local max_limit = 10
    local break_point = 5

    -- If your compiler doesn't support print yet, you can replace 
    -- these with whatever standard library output function you have.
    print("Starting the while loop test...")

    while counter < max_limit do
        counter = counter + 1
        print("Counter is at: " .. counter)

        -- Test the break statement
        if counter == break_point then
            print("Break point reached! Exiting the loop.")
            break
        end
    end

    -- Verify that the execution resumes correctly after the loop
    print("Loop finished. Final counter value: " .. counter)
end

function print(msg)
	x = 1
end
