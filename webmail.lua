local httpd = require("aio.lib.httpd")

--- @class webmail
webmail = webmail or {
    --- @type core_mail
    mail = nil
}


function isodate(time)
    if type(time) == "table" then
        return string.format("%04d-%02d-%02dT%02d:%02d:%02d", time.year, time.month, time.day, time.hour, time.min, time.sec)
    end
    local ok, result = pcall(os.date, "!%Y-%m-%dT%T", time)
    if ok then return result end
    -- windows compatibility
    local ok, result = pcall(os.date, "%Y-%m-%dT%H:%I:%S", time)
    if ok then return result end
    return os.date()
end

--- Initialize webmail
---@param params {mail: core_mail}
function webmail:init(params)
    self.mail = params.mail
    httpd:initialize({
        root = "mail/webmail/",
        master_key = codec.hex_encode(crypto.sha256(os.getenv("MASTER_KEY") or "webmail")),
        base_prefix = "/mail"
    })
end

return webmail