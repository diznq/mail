local backend = require("mail.backends")
local webmail = require("mail.webmail")
local mysql_backend = require("mail.mysql_backend")
local smtp = require("aio.lib.smtp")


---@class core_mail
core_mail = core_mail or {
    --- @type smtp_user_repository
    user_repository = backend.users,
    --- @type smtp_mail_repository
    mail_repository = backend.mails
}

---Initialize the core_mail component
---@param params {users: smtp_user_repository|nil, mails: smtp_mail_repository|nil, smtp: boolean|nil, webmail: boolean|nil, pop3: boolean|nil} params
function core_mail:init(params)
    self.user_repository = params.users or backend.users
    self.mail_repository = params.mails or backend.mails

    if params.smtp then
        self:smtp_init()
    end

    if params.webmail then
        self:webmail_init()
    end
end

function core_mail:webmail_init()
    webmail:init({mail = self})
end

function core_mail:smtp_init()
    smtp:default_initialize()
    smtp:set_logging(true)

    smtp:register_handler("main", function (mail, handler)
        aio:async(function ()
            local promises = aio:map(mail.to, function (user)
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

function core_mail:get_user(email)
    return self.user_repository:get_user(email)
end

function core_mail:get_user_by_id(id)
    return self.user_repository:get_user_by_id(id)
end

--- Log-in user
---@param email string user email
---@param password string user password
---@return aiopromise<smtp_user> user logged user
function core_mail:login(email, password)
    return self.user_repository:login(email, password)
end

--- Load mails
---@param user_id string user ID
---@param pivot string? pivot point
---@param size integer? how many e-mails to retrieve
---@return aiopromise<mailparam> emails list of all emails
function core_mail:load_mails(user_id, pivot, size)
    return self.mail_repository:load_mails(user_id, pivot, size)
end

--- Retrieve full e-core_mail
---@param user_id string user ID
---@param mail_id string core_mail ID
---@return aiopromise<mailparam> mail single email
function core_mail:load_mail(user_id, mail_id)
    return self.mail_repository:load_mail(user_id, mail_id)
end

if not ... then
    local email_backend = mysql_backend.backend
    email_backend:init({
        host = os.getenv("MYSQL_HOST"),
        port = tonumber(os.getenv("MYSQL_PORT") or "3306"),
        user = os.getenv("MYSQL_USER") or "mail",
        password = os.getenv("MYSQL_PASSWORD") or "smtp25",
        db = os.getenv("MYSQL_DB") or "mails"
    })
    core_mail:init({
        smtp = PORT % 1000 == 25,
        webmail = PORT >= 8000,
        users = mysql_backend.users,
        mails = mysql_backend.mails
    })
end

return core_mail