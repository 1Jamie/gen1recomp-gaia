-- Content gate for Switch CI iOS-parity (SWCI-01..09).
-- Self-contained: luajit tests/switch_ci_workflows_test.lua

local T = require("tests.harness")
local check = T.check

local function read(path)
  local f, err = io.open(path, "r")
  if not f then error("cannot read " .. path .. ": " .. tostring(err)) end
  local s = f:read("*a")
  f:close()
  return s
end

local function mustContain(body, needle, label)
  check(body:find(needle, 1, true) ~= nil,
    label .. " must contain " .. string.format("%q", needle))
end

local function mustNotContain(body, needle, label)
  check(body:find(needle, 1, true) == nil,
    label .. " must not contain " .. string.format("%q", needle))
end

-- Exact path regex contract from design.md (SWCI-01 / 4A).
local SWITCH_PATH_REGEX =
  [[^(scripts/build_switch\.sh$|scripts/switch/|docs/switch-build\.md$|\.github/workflows/(ci|release|switch-artifact-comment)\.yml$)]]

local ci = read(".github/workflows/ci.yml")
local release = read(".github/workflows/release.yml")

-- --- SWCI-01: path detector ---
mustContain(ci, "switch-changes:", "ci.yml")
mustContain(ci, "detect Switch changes", "ci.yml")
mustContain(ci, SWITCH_PATH_REGEX, "ci.yml path regex")
mustContain(ci, 'echo "changed=true"', "ci.yml BASE_SHA fallback")
mustContain(ci, "0000000000000000000000000000000000000000", "ci.yml all-zero BASE_SHA")

-- --- SWCI-02 / SWCI-03: offline selftest job ---
mustContain(ci, "switch-selftest:", "ci.yml")
mustContain(ci, "needs: switch-changes", "ci.yml")
mustContain(ci, "needs.switch-changes.outputs.changed == 'true'", "ci.yml")
mustContain(ci, "scripts/switch/selftest_build_switch.sh", "ci.yml")
mustContain(ci, "scripts/switch/verify_payload.sh --self-test", "ci.yml")
mustContain(ci, "luajit tests/switch_ci_workflows_test.lua", "ci.yml")

-- switch-selftest must be ubuntu-latest (fork-safe); pin via job block scan
do
  local start = ci:find("switch-selftest:", 1, true)
  check(start ~= nil, "switch-selftest job present")
  local rest = ci:sub(start)
  local nextJob = rest:find("\n  [%w_-]+:", 2)
  local block = nextJob and rest:sub(1, nextJob - 1) or rest
  mustContain(block, "runs-on: ubuntu-latest", "switch-selftest")
  mustContain(block, "selftest_build_switch.sh", "switch-selftest")
  mustContain(block, "verify_payload.sh --self-test", "switch-selftest")
  mustContain(block, "tests/switch_ci_workflows_test.lua", "switch-selftest")
end

-- --- SWCI-08: release Switch hard-fail (no continue-on-error on build/stage) ---
do
  local start = release:find("- name: Build Switch", 1, true)
  check(start ~= nil, "release Build Switch step present")
  local rest = release:sub(start)
  local nextStep = rest:find("\n      - name:", 2)
  local block = nextStep and rest:sub(1, nextStep - 1) or rest
  mustContain(block, "scripts/build_switch.sh --fetch --fused", "release Build Switch")
  mustNotContain(block, "continue-on-error", "release Build Switch")
end

T.finish("switch_ci_workflows_test")
