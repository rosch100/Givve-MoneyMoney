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

dofile("Givve Prepaid.lua")

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
assertEq(normalizeAccountKey("  User@Firma.DE "), "user@firma.de", "accountKey")
assertEq(SupportsBank(ProtocolWebBanking, "Givve Prepaid"), true, "SupportsBank.ok")
assertEq(SupportsBank(ProtocolWebBanking, "Givve Card"), false, "SupportsBank.builtinCollision")
assertEq(SupportsBank(ProtocolWebBanking, "givve Card"), false, "SupportsBank.legacyLower")
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
local list = vouchersFromListPayload(vouchers)
assertEq(#list, 2, "vouchers.count")
local voucher = list[1]
assertNear(parseBalanceFromVoucher(voucher), 42.66, "balance")
assertEq(accountNumberForVoucher(voucher), "521965******6363", "accountNumber.voucher")
assertEq(accountNameForVoucher(voucher, 1), "givve", "accountName.single")
assertEq(accountNameForVoucher(voucher, 2), "givve ****6363", "accountName.multi")
assertEq(isLegacyVoucherAccountNumber("givve.690de7f35968df76c8af5168"), true, "legacy.hex")
assertEq(isLegacyVoucherAccountNumber("521965******6363"), false, "legacy.pan")
assertEq(voucherIdFromLegacyAccountNumber("givve.voucher-test-1"), "voucher-test-1", "legacy.parse")
assertEq(findVoucherForAccountNumber(list, "521965******6363").id, "voucher-test-1", "find.byPan")
assertEq(findVoucherForAccountNumber(list, "givve.voucher-test-2").id, "voucher-test-2", "find.byLegacy")
assertEq(firstDuplicateVoucherNumber(list), nil, "dup.none")
assertEq(
  firstDuplicateVoucherNumber({
    { id = "a", number = "521965******6363" },
    { id = "b", number = "521965******6363" },
  }),
  "521965******6363",
  "dup.samePan"
)
assertEq(last4FromVoucher(list[2]), "9999", "last4.second")
assertNear(parseBalanceFromVoucher(list[2]), 10.00, "balance.second")
assertEq(accountNumberForVoucher(list[2]), "521965******9999", "accountNumber.second")
assertEq(accountNameForVoucher(list[2], 2), "givve ****9999", "accountName.second")

local groups = parseJson(readFixture("transaction_groups.json"))
local txs = parseTransactionsFromGroupsPayload(groups, nil)
assertEq(#txs, 3, "tx.count")
assertEq(txs[1].name, "REWE Filialen Voll", "tx1.name")
assertEq(txs[1].purpose, "Muenchen DEU", "tx1.purpose")
assertNear(txs[1].amount, -53.30, "tx1.amount")
assertEq(txs[1].bookingKey, "tx-purchase-1", "tx1.key")
assertEq(txs[1].booked, true, "tx1.booked")
assertEq(txs[1].valueDate ~= nil, true, "tx1.valueDate")
assertEq(txs[1].bookingText, "Grocery Stores, Supermarkets", "tx1.bookingText")
assertEq(txs[2].name, "REWE Filialen Voll", "tx2.name")
assertEq(txs[2].purpose, "Falkenstr. 9 Muenchen 81541 DEU", "tx2.purpose")
assertNear(txs[2].amount, -33.78, "tx2.amount")
assertEq(txs[2].bookingDate ~= txs[2].valueDate, true, "tx2.datesDiffer")
assertEq(txs[3].name, "Load : LoadOrder : PL1846238 -", "tx3.name")
assertEq(txs[3].purpose, "6a8bb0e567fbbf287caaad9e - 6a8bb0e567fbbf287caaada0", "tx3.purpose")
assertNear(txs[3].amount, 50.00, "tx3.amount")
assertEq(txs[3].bookingText, "Aufladung", "tx3.bookingText")

assertEq(purposeFromMerchantDescription("REWE Filialen Voll", "REWE Filialen Voll     Muenchen      DEU"), "Muenchen DEU", "purpose.space")
assertEq(
  purposeFromMerchantDescription("REWE Filialen Voll", "REWE Filialen Voll\\Falkenstr. 9\\Muenchen\\81541        DEU"),
  "Falkenstr. 9 Muenchen 81541 DEU",
  "purpose.backslash"
)
local loadName, loadPurpose = splitLoadDescription("Load : LoadOrder : PL1846238 - abc - def")
assertEq(loadName, "Load : LoadOrder : PL1846238 -", "load.split.name")
assertEq(loadPurpose, "abc - def", "load.split.purpose")

local ownerMe = parseJson(readFixture("voucher_owner_me.json"))
assertEq(parseOwnerNameFromMePayload(ownerMe), "Test Owner", "owner.name")

local empty = parseTransactionsFromGroupsPayload({ data = {} }, nil)
assertEq(#empty, 0, "tx.empty")
assertEq(parseBalanceFromVoucher({}), nil, "balance.missing")

local txUrl = transactionGroupsUrl("voucher-test-1", nil)
assertEq(txUrl:find("page%5Bnumber%5D=1", 1, true) ~= nil, true, "txUrl.pagination")
assertEq(txUrl:find("skip_meta_totals=true", 1, true) ~= nil, true, "txUrl.skipMeta")
local txUrlSince = transactionGroupsUrl("voucher-test-1", os.time({ year = 2026, month = 8, day = 6, hour = 11, min = 54, sec = 3 }))
assertEq(txUrlSince:find("filter%5Blatest_booked_at%5D", 1, true) ~= nil, true, "txUrl.sinceFilter")

print("test_givve OK")
