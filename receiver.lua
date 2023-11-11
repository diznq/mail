local smtp = require("aio.lib.smtp")
local backend = require("mail.backends")

local mail = {
    --- @type smtp_user_repository
    user_repository = backend.users,
    --- @type smtp_mail_repository
    mail_repository = backend.mails
}

---Initialize the mail component
---@param params {users: smtp_user_repository|nil, mails: smtp_mail_repository|nil} params
function mail:init(params)
    smtp:default_initialize()
    self.user_repository = params.users or backend.users
    self.mail_repository = params.mails or backend.mails

    smtp:set_logging(true)

    smtp:register_handler("main", function (mail, handler)
        aio:async(function ()
            local promises = aio:map(mail.to, function (user, id)
                return self.user_repository:get_user(user.email)
            end)
            aio:gather(unpack(promises))(function (...)
                for _, user in ipairs({...}) do
                    if iserror(user) then
                        return handler.error("delivery failed")
                    end
                end
                local mail_promises = aio:map({...}, function (user)
                    return self.mail_repository:store_mail(user, mail)
                end)
                aio:gather(unpack(mail_promises))(function (...)
                    for _, state in ipairs({...}) do
                        if iserror(state) then return handler.error("storing failed") end
                    end
                    handler.ok()
                end)
            end)
        end)
    end)
end

if not ... then
    mail:init({})
end

return mail