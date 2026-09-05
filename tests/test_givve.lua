---@diagnostic disable: duplicate-set-field
-- Offline-Tests für givve Card (kein MoneyMoney-Host nötig).

function WebBanking(_) end

ProtocolWebBanking = "WebBanking"
AccountTypeCreditCard = 3
LoginFailed = "LoginFailed"

MM = {
  printStatus = function(msg)
    io.stderr:write("[STATUS] " .. msg .. "\n")
  end,
  urlencode = function(s)
    return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end,
}

function Connection()
  return {
    request = function()
      return nil
    end,
    get = function()
      return nil
    end,
    getCookies = function()
      return ""
    end,
    setCookie = function() end,
  }
end

-- Minimal-JSON für Fixture-Tests (nur Objekt/Array/String/Number/bool/null).
function JSON(str)
  local i = 1
  local function peek()
    return str:sub(i, i)
  end
  local function skip()
    while str:sub(i, i):match("%s") do
      i = i + 1
    end
  end
  local parseValue
  local function parseString()
    i = i + 1
    local start = i
    while true do
      local c = str:sub(i, i)
      if c == "" then
        error("unterminated string")
      end
      if c == "\\" then
        i = i + 2
      elseif c == '"' then
        local raw = str:sub(start, i - 1)
        i = i + 1
        return raw:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub('\\"', '"'):gsub("\\\\", "\\")
      else
        i = i + 1
      end
    end
  end
  local function parseNumber()
    local start = i
    if peek() == "-" then
      i = i + 1
    end
    while peek():match("%d") do
      i = i + 1
    end
    if peek() == "." then
      i = i + 1
      while peek():match("%d") do
        i = i + 1
      end
    end
    return tonumber(str:sub(start, i - 1))
  end
  local function parseArray()
    i = i + 1
    local arr = {}
    skip()
    if peek() == "]" then
      i = i + 1
      return arr
    end
    while true do
      arr[#arr + 1] = parseValue()
      skip()
      if peek() == "]" then
        i = i + 1
        return arr
      end
      if peek() ~= "," then
        error("expected comma in array")
      end
      i = i + 1
      skip()
    end
  end
  local function parseObject()
    i = i + 1
    local obj = {}
    skip()
    if peek() == "}" then
      i = i + 1
      return obj
    end
    while true do
      skip()
      if peek() ~= '"' then
        error("expected string key")
      end
      local key = parseString()
      skip()
      if peek() ~= ":" then
        error("expected colon")
      end
      i = i + 1
      obj[key] = parseValue()
      skip()
      if peek() == "}" then
        i = i + 1
        return obj
      end
      if peek() ~= "," then
        error("expected comma in object")
      end
      i = i + 1
    end
  end
  parseValue = function()
    skip()
    local c = peek()
    if c == '"' then
      return parseString()
    end
    if c == "{" then
      return parseObject()
    end
    if c == "[" then
      return parseArray()
    end
    if c == "t" and str:sub(i, i + 3) == "true" then
      i = i + 4
      return true
    end
    if c == "f" and str:sub(i, i + 4) == "false" then
      i = i + 5
      return false
    end
    if c == "n" and str:sub(i, i + 3) == "null" then
      i = i + 4
      return nil
    end
    if c == "-" or c:match("%d") then
      return parseNumber()
    end
    error("unexpected at " .. i)
  end
  local decoded = parseValue()
  return {
    dictionary = function()
      return decoded
    end,
  }
end

dofile("Givve.lua")

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print(
      "FAIL  "
        .. label
        .. ": expected="
        .. tostring(expected)
        .. ", actual="
        .. tostring(actual)
    )
    os.exit(1)
  end
end

local function assertNear(actual, expected, label)
  if type(actual) == "number" and math.abs(actual - expected) < 0.001 then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print(
      "FAIL  "
        .. label
        .. ": expected~"
        .. tostring(expected)
        .. ", actual="
        .. tostring(actual)
    )
    os.exit(1)
  end
end

local function readFixture(name)
  local f = assert(io.open("tests/fixtures/" .. name, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

assertEq(normalizeEmail("  User@Firma.DE "), "user@firma.de", "normalizeEmail.trim.lower")
assertEq(normalizeEmail(""), "", "normalizeEmail.empty")
assertEq(normalizeEmail(nil), "", "normalizeEmail.nil")
assertEq(accountNumberForEmail("user@firma.de"), "givve.user.firma.de", "accountNumber")
assertEq(accountNumberForEmail("  A@B.C "), "givve.a.b.c", "accountNumber.normalize")
assertEq(accountNameForEmail("user@firma.de"), "givve Card (user@firma.de)", "accountName")
assertEq(normalizeAccountKey("  User@Firma.DE "), "user@firma.de", "accountKey")
assertEq(SupportsBank(ProtocolWebBanking, "givve Card"), true, "SupportsBank.ok")
assertEq(SupportsBank(ProtocolWebBanking, "Other"), false, "SupportsBank.no")

assertEq(hostAllowed("https://card.givve.com/login"), true, "host.card")
assertEq(hostAllowed("https://www.givve.com/api/authorizations"), true, "host.www")
assertEq(hostAllowed("https://evil.example/login"), false, "host.evil")
assertEq(hostAllowed("card.givve.com"), true, "host.bare")
local okCall = pcall(function()
  assertAllowedUrl("https://evil.example/x")
end)
assertEq(okCall, false, "assertAllowedUrl.rejects")

assertEq(classifyAuthJson(readFixture("auth_otp_required.json")), "mfa", "classify.mfa")
assertEq(classifyAuthJson(readFixture("auth_ok.json")), "ok", "classify.ok")
assertEq(classifyAuthJson(readFixture("auth_failed.json")), "login_failed", "classify.failed")

local ch = emailMfaChallenge(nil)
assertEq(type(ch) == "table", true, "mfaChallenge.table")
assertEq(ch.label, "E-Mail-Code", "mfaChallenge.label")

local authBody = buildAuthorizationBody("user@example.com", "secret", nil)
assertEq(authBody:find('"identifier":"user@example.com"', 1, true) ~= nil, true, "authBody.id")
assertEq(authBody:find('"client_id":"givve-card-web"', 1, true) ~= nil, true, "authBody.client")
assertEq(authBody:find('"otp"', 1, true) == nil, true, "authBody.noOtp")
local authBodyOtp = buildAuthorizationBody("user@example.com", "secret", "123456")
assertEq(authBodyOtp:find('"otp":"123456"', 1, true) ~= nil, true, "authBody.otp")

local vouchers = parseJson(readFixture("vouchers_list.json"))
local voucher = firstVoucherFromListPayload(vouchers)
assertNear(parseBalanceFromVoucher(voucher), 42.66, "balance")

local groups = parseJson(readFixture("transaction_groups.json"))
local txs = parseTransactionsFromGroupsPayload(groups, nil)
assertEq(#txs, 2, "tx.count")
assertEq(txs[1].name, "REWE Filialen Voll", "tx1.name")
assertNear(txs[1].amount, -53.30, "tx1.amount")
assertEq(txs[1].bookingKey, "tx-purchase-1", "tx1.key")
assertEq(txs[2].name, "Aufladung", "tx2.name")
assertNear(txs[2].amount, 50.00, "tx2.amount")

local empty = parseTransactionsFromGroupsPayload({ data = {} }, nil)
assertEq(#empty, 0, "tx.empty")
assertEq(parseBalanceFromVoucher({}), nil, "balance.missing")

print("test_givve OK")
