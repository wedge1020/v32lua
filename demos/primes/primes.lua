--#title "v32lua prime number performance benchmark"
--
-- primes.lua: a CPU cycle evaluation attempt for v32opt validation
--
-- Calculate primes using trial by division method
-- Counts primes from 2 to N (inclusive)
--

--
-- global variables
--
qty    = { [0] = -1,   [1] = -1,   [2] = -1,   [3] = -1,
           [4] = -1,   [5] = -1,   [6] = -1,   [7] = -1    }
cycle  = { [0] = -1,   [1] = -1,   [2] = -1,   [3] = -1,
           [4] = -1,   [5] = -1,   [6] = -1,   [7] = -1    }
time   = { [0] = -1,   [1] = -1,   [2] = -1,   [3] = -1,
           [4] = -1,   [5] = -1,   [6] = -1,   [7] = -1    }
flag   = { [0] = true, [1] = true, [2] = true, [3] = true,
           [4] = true, [5] = true, [6] = true, [7] = true  }

-- Variant 1: Brute force - checks all divisors, no early exit
function brute(n)
    local count = 0
    for i = 2, n do
        local is_prime = true  -- Reset for each number
        for j = 2, i - 1 do
            if i % j == 0 then
                is_prime = false
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant 2: Break on composite - exits inner loop on first divisor found
function brute_b(n)
    local count = 0
    for i = 2, n do
        local is_prime = true
        for j = 2, i - 1 do
            if i % j == 0 then
                is_prime = false
                break
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant 3: Odds-only - assumes 2 is prime, checks only odd numbers in both loops
function brute_o(n)
    if n < 2 then return 0 end
    local count = 1  -- 2 is prime
    for i = 3, n, 2 do
        local is_prime = true
        for j = 3, i - 1, 2 do
            if i % j == 0 then
                is_prime = false
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant: Square root cap - only checks divisors up to sqrt(i)
function brute_s(n)
    local count = 0
    for i = 2, n do
        local is_prime = true
        local limit = math.floor(math.sqrt(i))
        for j = 2, limit do
            if i % j == 0 then
                is_prime = false
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant: break + odds - assumes 2 is prime, checks only odd numbers in both loops
function brute_bo(n)
    if n < 2 then return 0 end
    local count = 1  -- 2 is prime
    for i = 3, n, 2 do
        local is_prime = true
        for j = 3, i - 1, 2 do
            if i % j == 0 then
                is_prime = false
                break
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant: break on composite + Square root cap - only checks divisors up to sqrt(i)
function brute_bs(n)
    local count = 0
    for i = 2, n do
        local is_prime = true
        local limit = math.floor(math.sqrt(i))
        for j = 2, limit do
            if i % j == 0 then
                is_prime = false
                break
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant: odds + square root - assumes 2 is prime, checks only odd numbers in both loops, applies square root trick
function brute_os(n)
    if n < 2 then return 0 end
    local count = 1  -- 2 is prime
    for i = 3, n, 2 do
        local is_prime = true
        local limit = math.floor(math.sqrt(i))
        for j = 3, limit, 2 do
            if i % j == 0 then
                is_prime = false
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

-- Variant: brute + break + odds + sqrt
function brute_bos(n)
    if n < 2 then return 0 end
    local count = 1  -- 2 is prime
    for i = 3, n, 2 do
        local is_prime = true
        local limit     = math.floor(math.sqrt(i))
        for j = 3, limit, 2 do
            if i % j == 0 then
                is_prime = false
				break
            end
        end
        if is_prime then
            count = count + 1
        end
    end
    return count
end

--
-- Main
--
function main()

    ioports.gpu.clear("black")
    print(0,    0,  "Prime Number Computations (lua)")
    print(0,    6,  "_________________________________")
    print(0,    8,  "_________________________________")
    print(0,    24, "        qty  cycles     time(s)")
    print(0,    36, "------- ---- --------- --------")
    print(0,   184, "        qty  cycles     time(s)")
    print(0,   196, "------- ---- --------- --------")
    print(330,   6, "_________________________________")
    print(330,   8, "_________________________________")
    print(330,  24, "        qty  cycles     time(s)")
    print(330,  36, "------- ---- --------- --------")
    print(330, 184, "        qty  cycles     time(s)")
    print(330, 196, "------- ---- --------- --------")

    local start                 = 0
    local stop                  = 0
    local x                     = 0
    local xreset                = 0
    local y                     = 58
    local yreset                = 58
    
    local index                 = 1024
    while index                <= 8192 do

        --
        -- based on workload, determine x and y starting positions
        --
        if index               == 1024 then
            xreset              = 0
            yreset              = 48
        elseif index           == 2048 then
            xreset              = 0
            yreset              = 208
        elseif index           == 4096 then
            xreset              = 330
            yreset              = 48
        elseif index           == 8192 then
            xreset              = 330
            yreset              = 208
        end

        --
        -- display upper bound (workload)
        --
        x                       = x + 80
        print(xreset, yreset-22, index)

        --
        -- for each algorithm we are performing
        --
        y                       = yreset
        for alg                 = 0, 7 do

            --
            -- reset x, y for current line
            --
            x                   = xreset

            --
            -- display algorithm header
            --
            if alg             == 0 then
                print(x, y, " brute:")
            elseif alg         == 1 then
                print(x, y, "+b    :")
            elseif alg         == 2 then
                print(x, y, "  +o  :")
            elseif alg         == 3 then
                print(x, y, "    +s:")
            elseif alg         == 4 then
                print(x, y, "+b  +s:")
            elseif alg         == 5 then
                print(x, y, "+b+o  :")
            elseif alg         == 6 then
                print(x, y, "  +o+s:")
            elseif alg         == 7 then
                print(x, y, "+b+o+s:")
            end

            --
            -- conditionally perform the computation
            -- sample the frames elapsed
            --
            if flag[alg]       == true then
                if alg         == 0 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute(index)
                    stop        = system.frames
                elseif alg     == 1 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_b(index)
                    stop        = system.frames
                elseif alg     == 2 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_o(index)
                    stop        = system.frames
                elseif alg     == 3 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_s(index)
                    stop        = system.frames
                elseif alg     == 4 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_bs(index)
                    stop        = system.frames
                elseif alg     == 5 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_bo(index)
                    stop        = system.frames
                elseif alg     == 6 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_os(index)
                    stop        = system.frames
                elseif alg     == 7 then
                    start       = ioports.tim.frames
                    qty[alg]    = brute_bos(index)
                    stop        = system.frames
                end
            else
                print(x, y, "                         n/a")
                qty[alg]        = -1
                cycle[alg]      = -1
                time[alg]       = -1
            end

            --
            -- display qty of primes found in range
            --
            if flag[alg]       == true then
                x               = x + 80
                print(x, y, qty[alg])
            end

            --
            -- calculate cycles from frames transpired
            --
            if flag[alg]       == true then
                cycle[alg]      = stop - start
                cycle[alg]      = cycle[alg] * 250000
                x               = x + 50
            end

            --
            -- add in cycles in current frame, then print
            --
            if flag[alg]       == true then
                cycle[alg]      = cycle[alg] + ioports.tim.cycles
                print(x, y, cycle[alg])
            end

            --
            -- calculate and display total time for run
            --
            if flag[alg]       == true then
                time[alg]       = cycle[alg] / 250000.0 / 60.0
                x               = x + 100
                print(x, y, time[alg])

                if time[alg]   >  2.0 then
                    flag[alg]   = false
                end
            end

            --
            -- adjust y for next row of display
            --
            y                   = y + 16

            --
            -- sync and advance to next frame
            --
            ioports.gpu.sync()
        end
        print(xreset,  (y-4), "-------------------------------")
        index                   = index * 2
    end
end
