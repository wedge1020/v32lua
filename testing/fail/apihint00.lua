-- Mentioning --#api pico8 in a comment does NOT enable PICO-8 syntax, so the
-- then-less if below must be a syntax error (it used to be expanded silently).
function main()
    local x = 1
    if (x == 1) x = 2
    system.wait()
end
