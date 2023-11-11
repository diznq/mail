local httpd = require("aio.lib.httpd")

--- @class webmail
webmail = webmail or {
    --- @type mail
    mail = nil
}

--- Initialize webmail
---@param params {mail: mail}
function webmail:init(params)
    self.mail = params.mail
    httpd:initialize({
        root = "mail/webmail/"
    })
end

return webmail