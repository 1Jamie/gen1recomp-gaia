local input, output = ...
local running, fatal = pcall(function()
  require("love.filesystem")
  require("love.image")
  require("love.data")
  require("love.timer")
  table.insert(package.searchers or package.loaders, 1, function(name)
    local path = name:gsub("%.", "/") .. ".lua"
    if love.filesystem.getInfo(path) then return assert(love.filesystem.load(path)) end
  end)
  local D = require("src.core.game3.asset_decode")
  while true do
    local job = input:demand()
    if job.stop then break end
    local start = love.timer.getTime()
    local ok, data, err = pcall(D[job.kind], D.cache(job.spec, job.cancelSignal), job.root, job.key)
    output:push({ id = job.id, data = ok and data or nil, error = ok and err or tostring(data),
      seconds = love.timer.getTime() - start })
  end

end)
if not running then output:push({ fatal = tostring(fatal) }) end
