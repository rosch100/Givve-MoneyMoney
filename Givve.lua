--
-- Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
-- givve Card — MoneyMoney Web Banking Extension
-- Portal: https://card.givve.com  API: https://www.givve.com
-- Dokumentation: README.md (Hub: https://github.com/rosch100/moneymoney-extensions)
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 0.91,
  url         = "https://card.givve.com",
  services    = {"givve Card"},
  description = "givve Card — E-Mail/Passwort + E-Mail-OTP"
}

local CONSTANTS = {
  baseUrl = "https://card.givve.com",
  authorizationsUrl = "https://www.givve.com/api/authorizations",
  vouchersUrl = "https://www.givve.com/api/voucher_owners/me/vouchers",
  clientId = "givve-card-web",
  acceptVersion = "v2",
  allowedHosts = { "card.givve.com", "www.givve.com" },
  serviceName = "givve Card",
  userAgent = "givve Card/8.1.1 (web)",
}

local CREDENTIAL_REJECTION_MARKERS = {
  "invalid email or password",
  "invalid credentials",
  "unauthorized",
  "falsche",
  "login failed",
}

local connection
local session = {}

function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function normalizeEmail(raw)
  return trim(tostring(raw or "")):lower()
end

function normalizeAccountKey(raw)
  return normalizeEmail(raw)
end

function accountNumberForEmail(email)
  local e = normalizeEmail(email)
  if e == "" then
    error("givve Card: E-Mail für Kontonummer fehlt")
  end
  return "givve." .. (e:gsub("@", "."))
end

function accountNameForEmail(email)
  local e = normalizeEmail(email)
  if e == "" then
    error("givve Card: E-Mail für Kontoname fehlt")
  end
  return "givve Card (" .. e .. ")"
end

function hostAllowed(urlOrHost)
  if type(urlOrHost) ~= "string" or urlOrHost == "" then
    return false
  end
  local host = urlOrHost
  if host:match("^https?://") then
    host = host:match("^https?://([^/?#]+)") or ""
  end
  host = host:lower():gsub(":443$", ""):gsub(":80$", "")
  for _, allowed in ipairs(CONSTANTS.allowedHosts) do
    if host == allowed then
      return true
    end
  end
  return false
end

function assertAllowedUrl(url)
  if type(url) ~= "string" or url == "" then
    error("givve Card: URL fehlt")
  end
  if not url:match("^https://") then
    error("givve Card: nur https:// erlaubt")
  end
  if not hostAllowed(url) then
    error("givve Card: Host nicht erlaubt: " .. tostring(url))
  end
  return url
end

function jsonEscapeString(value)
  if value == nil then
    return ""
  end
  return tostring(value)
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
end

function buildAuthorizationBody(identifier, password, otp)
  local parts = {
    '"identifier":"' .. jsonEscapeString(identifier) .. '"',
    '"password":"' .. jsonEscapeString(password) .. '"',
    '"accessors":["voucher_owner"]',
    '"client_id":"' .. jsonEscapeString(CONSTANTS.clientId) .. '"',
  }
  if type(otp) == "string" and trim(otp) ~= "" then
    parts[#parts + 1] = '"otp":"' .. jsonEscapeString(trim(otp)) .. '"'
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function parseJson(str)
  if type(str) ~= "string" or str == "" then
    return nil
  end
  local ok, result = pcall(function()
    return JSON(str):dictionary()
  end)
  if ok then
    return result
  end
  return nil
end

function classifyAuthPayload(payload)
  if type(payload) ~= "table" then
    return "unknown"
  end
  local data = payload.data
  if type(data) ~= "table" then
    data = payload
  end
  local status = data.auth_status
  if status == "otp_required" then
    return "mfa"
  end
  if status == "authenticated" and type(data.access_token) == "string" and data.access_token ~= "" then
    return "ok"
  end
  local errText = ""
  if type(payload.error) == "string" then
    errText = payload.error
  elseif type(payload.message) == "string" then
    errText = payload.message
  elseif type(data.message) == "string" then
    errText = data.message
  end
  local lower = errText:lower()
  for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
    if lower:find(marker, 1, true) then
      return "login_failed"
    end
  end
  return "unknown"
end

function classifyAuthJson(jsonText)
  local payload = parseJson(jsonText)
  if not payload then
    if type(jsonText) == "string" then
      local lower = jsonText:lower()
      if lower:find("otp_required", 1, true) then
        return "mfa"
      end
      if lower:find('"auth_status":"authenticated"', 1, true)
          or lower:find('"auth_status": "authenticated"', 1, true) then
        return "ok"
      end
      for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
        if lower:find(marker, 1, true) then
          return "login_failed"
        end
      end
    end
    return "unknown"
  end
  return classifyAuthPayload(payload)
end

function extractAccessToken(payload)
  if type(payload) ~= "table" then
    return nil
  end
  local data = payload.data
  if type(data) ~= "table" then
    data = payload
  end
  if type(data.access_token) == "string" and data.access_token ~= "" then
    return data.access_token
  end
  return nil
end

function extractRefreshToken(payload)
  if type(payload) ~= "table" then
    return nil
  end
  local data = payload.data
  if type(data) ~= "table" then
    data = payload
  end
  if type(data.refresh_token) == "string" and data.refresh_token ~= "" then
    return data.refresh_token
  end
  return nil
end

function emailMfaChallenge(message)
  return {
    title = "givve Card Authentifizierung",
    challenge = message or "Bitte den Code aus der givve-E-Mail eingeben.",
    label = "E-Mail-Code"
  }
end

function centsToAmount(cents)
  if type(cents) ~= "number" then
    return nil
  end
  return cents / 100
end

function parseBalanceFromVoucher(voucher)
  if type(voucher) ~= "table" then
    return nil
  end
  local balance = voucher.balance
  if type(balance) == "table" and type(balance.cents) == "number" then
    return centsToAmount(balance.cents)
  end
  return nil
end

function parseIsoDateTimeToTimestamp(iso)
  if type(iso) ~= "string" or iso == "" then
    return nil
  end
  local y, m, d, hh, mm, ss = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then
    y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    hh, mm, ss = 12, 0, 0
  end
  if not y then
    return nil
  end
  return os.time({
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(hh) or 12,
    min = tonumber(mm) or 0,
    sec = tonumber(ss) or 0,
  })
end

function transactionNameFromGroup(group)
  if type(group) ~= "table" then
    return nil
  end
  if type(group.merchant_name) == "string" and trim(group.merchant_name) ~= "" then
    return trim(group.merchant_name)
  end
  if type(group.description) == "string" and trim(group.description) ~= "" then
    local desc = trim(group.description)
    if desc:match("^[Ll]oad") then
      return "Aufladung"
    end
    return desc
  end
  return nil
end

function mapTransactionGroup(group)
  if type(group) ~= "table" then
    return nil
  end
  local amountTable = group.amount
  if type(amountTable) ~= "table" or type(amountTable.cents) ~= "number" then
    return nil
  end
  local amount = centsToAmount(amountTable.cents)
  local name = transactionNameFromGroup(group)
  local ts = parseIsoDateTimeToTimestamp(group.first_booked_at or group.latest_booked_at)
  if not name or amount == nil or not ts then
    return nil
  end
  local currency = "EUR"
  if type(amountTable.currency) == "string" and amountTable.currency ~= "" then
    currency = amountTable.currency
  end
  return {
    bookingDate = ts,
    name = name,
    amount = amount,
    bookingKey = group.id,
    currency = currency,
  }
end

function parseTransactionsFromGroupsPayload(payload, sinceTimestamp)
  local out = {}
  if type(payload) ~= "table" then
    return out
  end
  local data = payload.data
  if type(data) ~= "table" then
    return out
  end
  for i = 1, #data do
    local mapped = mapTransactionGroup(data[i])
    if mapped then
      if sinceTimestamp == nil or mapped.bookingDate >= sinceTimestamp then
        out[#out + 1] = mapped
      end
    end
  end
  return out
end

function firstVoucherFromListPayload(payload)
  if type(payload) ~= "table" or type(payload.data) ~= "table" then
    return nil
  end
  local data = payload.data
  if #data >= 1 and type(data[1]) == "table" then
    return data[1]
  end
  return nil
end

function stripNonSerializableConnections(storage)
  if type(storage) ~= "table" then
    return
  end
  storage.connection = nil
  if type(storage.connectionsByAccount) == "table" then
    for _, entry in pairs(storage.connectionsByAccount) do
      if type(entry) == "table" then
        entry.connection = nil
      end
    end
  end
end

function getConnectionEntry(storage, accountKey)
  if not storage then
    return nil
  end
  storage.connectionsByAccount = storage.connectionsByAccount or {}
  local entry = storage.connectionsByAccount[accountKey]
  if not entry then
    entry = {}
    storage.connectionsByAccount[accountKey] = entry
  end
  return entry
end

function persistTokens(storage, accountKey, accessToken, refreshToken)
  local entry = getConnectionEntry(storage, accountKey)
  if not entry then
    return
  end
  entry.accessToken = accessToken
  entry.refreshToken = refreshToken
  storage.connectionAccountKey = accountKey
  storage.accessToken = accessToken
  storage.refreshToken = refreshToken
end

function restoreTokens(storage, accountKey)
  if not storage or accountKey == "" then
    return nil, nil
  end
  local entry = storage.connectionsByAccount and storage.connectionsByAccount[accountKey]
  local access = entry and entry.accessToken
  local refresh = entry and entry.refreshToken
  if (not access or access == "") and storage.connectionAccountKey == accountKey then
    access = storage.accessToken
    refresh = storage.refreshToken
  end
  if type(access) == "string" and access ~= "" then
    session.accessToken = access
    session.refreshToken = refresh
    return access, refresh
  end
  return nil, nil
end

function apiHeaders(accessToken)
  local headers = {
    ["Accept"] = "*/*",
    ["Accept-Language"] = "de,en-US;q=0.9,en;q=0.8",
    ["Accept-Version"] = CONSTANTS.acceptVersion,
    ["Content-Type"] = "application/json",
    ["Origin"] = CONSTANTS.baseUrl,
    ["Referer"] = CONSTANTS.baseUrl .. "/",
    ["User-Agent"] = CONSTANTS.userAgent,
  }
  if type(accessToken) == "string" and accessToken ~= "" then
    headers["Authorization"] = "Bearer " .. accessToken
  end
  return headers
end

function apiRequest(method, url, body, accessToken)
  assertAllowedUrl(url)
  local headers = apiHeaders(accessToken)
  return connection:request(method, url, body, body and "application/json" or nil, headers)
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == CONSTANTS.serviceName
end

function ensureConnection()
  if not connection then
    connection = Connection()
  end
  connection.language = "de-DE"
  connection.useragent = CONSTANTS.userAgent
end

function loginWithPassword(email, password, interactive)
  local body = buildAuthorizationBody(email, password, nil)
  local response = apiRequest("POST", CONSTANTS.authorizationsUrl, body, nil)
  local kind = classifyAuthJson(response)
  if kind == "login_failed" then
    return LoginFailed
  end
  if kind == "mfa" then
    if interactive == false then
      return "givve Card: E-Mail-OTP erforderlich — bitte interaktiv anmelden."
    end
    session.awaitingMfa = true
    session.pendingEmail = email
    session.pendingPassword = password
    return emailMfaChallenge(nil)
  end
  if kind == "ok" then
    local payload = parseJson(response)
    local access = extractAccessToken(payload)
    local refresh = extractRefreshToken(payload)
    if not access then
      return "givve Card: Login ohne access_token."
    end
    session.accessToken = access
    session.refreshToken = refresh
    session.awaitingMfa = false
    local storage = rawget(_G, "LocalStorage")
    if storage then
      persistTokens(storage, session.accountKey, access, refresh)
    end
    return nil
  end
  if type(response) == "string" and #response > 0 then
    local lower = response:lower()
    for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
      if lower:find(marker, 1, true) then
        return LoginFailed
      end
    end
  end
  return "givve Card: Unerwartete Login-Antwort."
end

function submitEmailMfaCode(code)
  local email = session.pendingEmail
  local password = session.pendingPassword
  if not email or not password then
    session.awaitingMfa = false
    return "Anmeldesitzung für OTP abgelaufen. Bitte erneut anmelden."
  end
  if type(code) ~= "string" or trim(code) == "" then
    session.awaitingMfa = true
    return emailMfaChallenge("Bitte den E-Mail-Code eingeben.")
  end
  local body = buildAuthorizationBody(email, password, code)
  local response = apiRequest("POST", CONSTANTS.authorizationsUrl, body, nil)
  local kind = classifyAuthJson(response)
  if kind == "mfa" then
    session.awaitingMfa = true
    return emailMfaChallenge("Code ungültig oder abgelaufen. Bitte neuen Code prüfen.")
  end
  if kind == "login_failed" then
    session.awaitingMfa = false
    session.pendingEmail = nil
    session.pendingPassword = nil
    return LoginFailed
  end
  if kind == "ok" then
    local payload = parseJson(response)
    local access = extractAccessToken(payload)
    local refresh = extractRefreshToken(payload)
    if not access then
      return "givve Card: OTP-Login ohne access_token."
    end
    session.accessToken = access
    session.refreshToken = refresh
    session.awaitingMfa = false
    session.pendingEmail = nil
    session.pendingPassword = nil
    local storage = rawget(_G, "LocalStorage")
    if storage then
      persistTokens(storage, session.accountKey, access, refresh)
    end
    return nil
  end
  return "givve Card: Unerwartete OTP-Antwort."
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local email = normalizeEmail(credentials and credentials[1])
  local password = credentials and credentials[2] or ""
  local storage = rawget(_G, "LocalStorage")

  if step == 1 then
    if email == "" then
      return "Bitte die givve-E-Mail-Adresse eingeben."
    end
    session = { accountKey = email }
    if storage then
      stripNonSerializableConnections(storage)
      getConnectionEntry(storage, email)
      storage.connectionAccountKey = email
    end
    ensureConnection()

    local access = select(1, restoreTokens(storage, email))
    if access then
      session.accessToken = access
      local probe = apiRequest("GET", CONSTANTS.vouchersUrl, nil, access)
      local vouchers = parseJson(probe)
      if vouchers and type(vouchers.data) == "table" then
        session.vouchersPayload = vouchers
        return nil
      end
      session.accessToken = nil
    end

    if password == "" then
      return "Bitte das givve-Passwort eingeben."
    end
    return loginWithPassword(email, password, interactive)
  end

  ensureConnection()
  if session.awaitingMfa then
    -- Folgeschritt: MoneyMoney liefert den Challenge-Wert als credentials[1]
    return submitEmailMfaCode(credentials and credentials[1])
  end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end

function isoTimestampForApi(unixTs)
  if type(unixTs) ~= "number" then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%S.000", unixTs)
end

function transactionGroupsUrl(voucherId, sinceTimestamp)
  local url = CONSTANTS.vouchersUrl
    .. "/"
    .. voucherId
    .. "/transaction_groups?page%5Bnumber%5D=1&page%5Bsize%5D=250&skip_meta_totals=true"
  local iso = isoTimestampForApi(sinceTimestamp)
  if iso then
    url = url .. "&filter%5Blatest_booked_at%5D%5B%24gte%5D=" .. MM.urlencode(iso)
  end
  return url
end

function ListAccounts(knownAccounts)
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "givve Card: Session fehlt — bitte anmelden."
  end
  ensureConnection()
  local vouchersPayload = session.vouchersPayload
  if not vouchersPayload then
    local raw = apiRequest("GET", CONSTANTS.vouchersUrl, nil, session.accessToken)
    vouchersPayload = parseJson(raw)
    if not vouchersPayload then
      return "givve Card: Kontenliste konnte nicht gelesen werden."
    end
    session.vouchersPayload = vouchersPayload
  end
  local voucher = firstVoucherFromListPayload(vouchersPayload)
  if not voucher then
    return "givve Card: Keine Karte (Voucher) im Konto gefunden."
  end
  local balance = parseBalanceFromVoucher(voucher)
  if balance == nil then
    return "givve Card: Saldo konnte nicht gelesen werden."
  end
  session.voucherId = voucher.id
  local email = session.accountKey or ""
  return {
    {
      name = accountNameForEmail(email),
      accountNumber = accountNumberForEmail(email),
      currency = (voucher.currency or "EUR"),
      balance = balance,
      type = AccountTypeCreditCard,
    }
  }
end

function RefreshAccount(account, since)
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "givve Card: Session fehlt — bitte anmelden."
  end
  ensureConnection()
  local voucherId = session.voucherId
  if type(voucherId) ~= "string" or voucherId == "" then
    local rawList = apiRequest("GET", CONSTANTS.vouchersUrl, nil, session.accessToken)
    local listPayload = parseJson(rawList)
    local voucher = firstVoucherFromListPayload(listPayload)
    if not voucher or type(voucher.id) ~= "string" then
      return "givve Card: Karte für Umsätze nicht gefunden."
    end
    voucherId = voucher.id
    session.voucherId = voucherId
    session.vouchersPayload = listPayload
  end

  local voucherRaw = apiRequest("GET", CONSTANTS.vouchersUrl .. "/" .. voucherId, nil, session.accessToken)
  local voucherPayload = parseJson(voucherRaw)
  local voucher = voucherPayload and voucherPayload.data or nil
  local balance = parseBalanceFromVoucher(voucher)
  if balance == nil then
    return "givve Card: Saldo konnte nicht gelesen werden."
  end

  local txUrl = transactionGroupsUrl(voucherId, since)
  local txRaw = apiRequest("GET", txUrl, nil, session.accessToken)
  local txPayload = parseJson(txRaw)
  if not txPayload then
    return "givve Card: Umsätze konnten nicht gelesen werden."
  end
  local txs = parseTransactionsFromGroupsPayload(txPayload, since)
  return {
    balance = balance,
    transactions = txs,
  }
end

function EndSession()
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
  end
  session.pendingPassword = nil
  session.pendingEmail = nil
  session.awaitingMfa = false
  -- Tokens in Map behalten für Multi-Login / Neustart
  connection = nil
end
