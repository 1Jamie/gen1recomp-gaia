local E = {}

local function load()
  return require("tests.save_compat._expected_failures")
end

local function matches(value, pattern)
  if type(pattern) == "table" then
    for _, p in ipairs(pattern) do
      if value:match(p) then return true end
    end
    return false
  end
  return value:match(pattern) ~= nil
end
E.matches = matches

function E.new(check)
  local t = { check = check, cases = {}, caseOrder = {}, observed = {} }

  function t.case(id)
    if not t.cases[id] then
      t.cases[id] = true
      t.caseOrder[#t.caseOrder + 1] = id
    end
  end

  function t.fail(caseId, key, detail)
    t.case(caseId)
    t.observed[#t.observed + 1] = { case = caseId, key = key, detail = detail }
  end

  function t.finish(T)
    local entries = {}
    for _, e in ipairs(load()) do
      if e.check == t.check then
        for _, c in ipairs(t.caseOrder) do
          if matches(c, e.case) then entries[#entries + 1] = e; break end
        end
      end
    end
    local hits = {}
    local byId = {}
    for _, o in ipairs(t.observed) do
      local claimed
      for _, e in ipairs(entries) do
        if matches(o.case, e.case) and matches(o.key, e.key) then
          claimed = claimed or e
          hits[e] = (hits[e] or 0) + 1
        end
      end
      if claimed then
        byId[claimed.id] = (byId[claimed.id] or 0) + 1
        if os.getenv("SAVE_COMPAT_VERBOSE") == "1" then
          print(("xfail %s %s :: %s -- %s"):format(claimed.id, o.case, o.key, tostring(o.detail)))
        end
      else
        T.check(false, ("[%s] unexpected failure %s :: %s -- %s"):format(t.check, o.case, o.key, tostring(o.detail)))
      end
    end
    for _, e in ipairs(entries) do
      T.check(hits[e] ~= nil, ("[%s] %s now passes for %s :: %s; remove it from tests/save_compat/_expected_failures.lua")
        :format(t.check, e.id, table.concat(type(e.case) == "table" and e.case or { e.case }, "|"),
          table.concat(type(e.key) == "table" and e.key or { e.key }, "|")))
    end
    local ids = {}
    for id in pairs(byId) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = ("%s x%d"):format(id, byId[id]) end
    print(("[%s] %d cases, %d expected failures (%s)"):format(t.check, #t.caseOrder, #t.observed,
      #parts > 0 and table.concat(parts, ", ") or "none"))
  end

  return t
end

return E
