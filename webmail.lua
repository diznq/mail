local httpd = require("aio.lib.httpd")

--- @class webmail
webmail = webmail or {
    --- @type core_mail
    mail = nil
}

--- Initialize webmail
---@param params {mail: core_mail}
function webmail:init(params)
    self.mail = params.mail
    httpd:initialize({
        root = "mail/webmail/",
        master_key = codec.hex_encode(crypto.sha256(os.getenv("MASTER_KEY") or "webmail"))
    })
end

return webmail