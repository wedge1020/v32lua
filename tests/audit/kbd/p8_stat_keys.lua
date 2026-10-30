--#api pico8
--#keyboard 0
--@ PICO-8 stat(30) / stat(31): the typed-character queue from the v32kbd layer.
--@ Played by p8_stat_keys.py (a scripted keyboard on gamepad 0).
n = 0
text = ""
function _update()
  n = n + 1
  if n == 1 then idle_waiting = stat(30) idle_char = stat(31) end
  if n == 40 then
    waiting1 = stat(30)
    waiting2 = stat(30)          -- stat(30) does not consume
    while stat(30) do text = text .. stat(31) end
    after_waiting = stat(30)
    after_char = stat(31)
  end
end
function _draw() end
