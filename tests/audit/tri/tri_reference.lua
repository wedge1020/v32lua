function tri(x1, y1, x2, y2, x3, y3, c)
  local area = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
  if math.floor(area) == 0 then return end
  if area < 0 then
    local tx, ty = x2, y2
    x2, y2, x3, y3 = x3, y3, tx, ty
    area = -area
  end
  local x0 = math.max(math.floor(math.min(x1, x2, x3)), 0)
  local y0 = math.max(math.floor(math.min(y1, y2, y3)), 0)
  local xe = math.min(math.ceil(math.max(x1, x2, x3)), 240)
  local ye = math.min(math.ceil(math.max(y1, y2, y3)), 136)
  if x0 >= xe or y0 >= ye then return end
  local px, py = x0 + 0.49999988, y0 + 0.49999988
  local inv = 1 / area
  local ax1, ay1 = (y2 - y3) * inv, (x3 - x2) * inv
  local b1 = ((x3 - x2) * (py - y2) - (y3 - y2) * (px - x2)) * inv
  local ax2, ay2 = (y3 - y1) * inv, (x1 - x3) * inv
  local b2 = ((x1 - x3) * (py - y3) - (y1 - y3) * (px - x3)) * inv
  local ax3, ay3 = (y1 - y2) * inv, (x2 - x1) * inv
  local b3 = ((x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)) * inv
  local last, r0, r1 = xe - x0 - 1, 0, ye - y0 - 1
  local k1, k2, k3, c1, c2, c3, m1, m2, m3 = 0, 0, 0, 0, 0, 0, 0, 0, 0
  if ax1 > 0 then k1 = 1 elseif ax1 < 0 then k1 = 2
  elseif ay1 > 0 then r0 = math.max(r0, math.ceil(-b1 / ay1))
  elseif ay1 < 0 then r1 = math.min(r1, math.floor(-b1 / ay1))
  elseif b1 < 0 then return end
  if k1 ~= 0 then c1, m1 = -b1 / ax1, -ay1 / ax1 end
  if ax2 > 0 then k2 = 1 elseif ax2 < 0 then k2 = 2
  elseif ay2 > 0 then r0 = math.max(r0, math.ceil(-b2 / ay2))
  elseif ay2 < 0 then r1 = math.min(r1, math.floor(-b2 / ay2))
  elseif b2 < 0 then return end
  if k2 ~= 0 then c2, m2 = -b2 / ax2, -ay2 / ax2 end
  if ax3 > 0 then k3 = 1 elseif ax3 < 0 then k3 = 2
  elseif ay3 > 0 then r0 = math.max(r0, math.ceil(-b3 / ay3))
  elseif ay3 < 0 then r1 = math.min(r1, math.floor(-b3 / ay3))
  elseif b3 < 0 then return end
  if k3 ~= 0 then c3, m3 = -b3 / ax3, -ay3 / ax3 end
  for row = r0, r1 do
    local lo, hi = 0, last
    if k1 == 1 then lo = math.max(lo, math.ceil(c1 + m1 * row))
    elseif k1 == 2 then hi = math.min(hi, math.floor(c1 + m1 * row)) end
    if k2 == 1 then lo = math.max(lo, math.ceil(c2 + m2 * row))
    elseif k2 == 2 then hi = math.min(hi, math.floor(c2 + m2 * row)) end
    if k3 == 1 then lo = math.max(lo, math.ceil(c3 + m3 * row))
    elseif k3 == 2 then hi = math.min(hi, math.floor(c3 + m3 * row)) end
    if hi >= lo then rect(x0 + lo, y0 + row, hi - lo + 1, 1, c) end
  end
end
