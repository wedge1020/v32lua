--#api pico8
player_spawn = {a=1}
other = 5
function _init()
  local n = "player" .. "_spawn"
  r_a = _ENV[n] == player_spawn
  r_b = _ENV["other"]
  _ENV["other"] = 7
  r_c = other
  local t = split("1,player_spawn")
  r_d = _ENV[t[2]] == player_spawn
  r_e = t[2] == "player_spawn"
end
function _update() end
