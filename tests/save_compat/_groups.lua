local Groups = {}

Groups.valid = { codecs = true, records = true, world = true }
Groups.named = {
  gen3_sec_frextra_test = "records",
  gen3_sec_records_test = "records",
  gen3_sec_town_test = "world",
  gen3_sec_tv_test = "world",
}

function Groups.of(path)
  local name = path:match("([^/]+)%.lua$")
  -- New codec suites stay covered without updating a hand-maintained list.
  return Groups.named[name] or "codecs"
end

return Groups
