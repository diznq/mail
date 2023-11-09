local smtp = require("aio.lib.smtp")
local backend = require("mail.backends")

local mail = {
    --- @type smtp_user_repository
    user_repository = backend.users
}

---Initialize the mail component
---@param params {users: smtp_user_repository|nil, mails: smtp_mail_repository|nil} params
function mail:init(params)
    smtp:default_initialize()
    self.user_repository = params.users or backend.users
    self.mail_repository = params.mails or backend.mails

    smtp:register_handler("main", function (mail)
        return self.mail_repository:store_mail(mail)
    end)
end

if not ... then
    mail:init({})
end

return mail