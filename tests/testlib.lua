-- A tiny test helper: T.check(cond, name), T.near(a, b, eps, name), T.done(file) (exits 1 on any failure).
local T = { passed = 0, failed = 0 }

function T.check(cond, name)
  if cond then T.passed = T.passed + 1
  else T.failed = T.failed + 1 print('FAIL: ' .. tostring(name)) end
end

function T.near(a, b, eps, name)
  local ok = type(a) == 'number' and type(b) == 'number' and math.abs(a - b) <= eps
  T.check(ok, string.format('%s (%s vs %s)', name, tostring(a), tostring(b)))
end

function T.done(file)
  print(string.format('%s: %d passed, %d failed', file, T.passed, T.failed))
  if T.failed > 0 then os.exit(1) end
end

return T
