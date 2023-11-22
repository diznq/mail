local backend = require("mail.backends")
local webmail = require("mail.webmail")
local mysql_backend = require("mail.mysql_backend")
local smtp = require("aio.lib.smtp")
local mailer = require("aio.lib.smtp_client")
local dns = require("aio.lib.dns")

aio:set_dns(dns)


---@class core_mail
core_mail = {
    --- @type smtp_user_repository
    user_repository = backend.users,
    --- @type smtp_mail_repository
    mail_repository = backend.mails,
    mailer = mailer
}

---Initialize the core_mail component
---@param params {users: smtp_user_repository|nil, mails: smtp_mail_repository|nil, smtp: boolean|nil, webmail: boolean|nil, pop3: boolean|nil, host: string|nil, logging: boolean|nil} params
function core_mail:init(params)
    self.user_repository = params.users or backend.users
    self.mail_repository = params.mails or backend.mails
    
    self.mailer:init({host = params.host or "localhost", logging=params.logging, ssl=true})

    if params.smtp then
        self:smtp_init(params.host or "localhost")
    end

    if params.webmail then
        self:webmail_init()
    end
end

function core_mail:webmail_init()
    webmail:init({mail = self})
end

function core_mail:smtp_init(host)
    smtp:default_initialize()
    smtp:set_logging(true)
    smtp.host = host or "localhost"

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

--- Get user's e-mail subfolders
---@param user_id string user ID
---@return aiopromise<{error: string|nil, subfolders: smtp_subfolder[]}> subfolders
function core_mail:get_subfolders(user_id)
    local resolve, resolver = aio:prepare_promise()
    self.mail_repository:get_subfolders(user_id)(function (result)
        local all = {
            name = "All",
            count = 0,
            unread = 0,
            link = "[all]",
            system = true
        }
        if not iserror(result) then
            for _, subfolder in ipairs(result.subfolders) do
                all.count = all.count + subfolder.count
                all.unread = all.unread + subfolder.unread
            end
            table.insert(result.subfolders, 1, all)
        end
        resolve(result)
    end)
    return resolver
end

--- Load mails
---@param user_id string user ID
---@param subfolder string|nil subfolder
---@param pivot string? pivot point
---@param size integer? how many e-mails to retrieve
---@return aiopromise<mailparam> emails list of all emails
function core_mail:load_mails(user_id, subfolder, pivot, size)
    return self.mail_repository:load_mails(user_id, subfolder, pivot, size)
end

--- Retrieve full e-core_mail
---@param user_id string user ID
---@param mail_id string core_mail ID
---@return aiopromise<mailparam> mail single email
function core_mail:load_mail(user_id, mail_id)
    return self.mail_repository:load_mail(user_id, mail_id)
end

--- Send e-mail
---@param from_addr string sender e-mail
---@param to_addr string target e-mail
---@param subject string email subject
---@param body string email body
---@return aiopromise<{ok: boolean, error: string|nil}>
function core_mail:send_mail(from_addr, to_addr, subject, body)
    local resolve, resolver = aio:prepare_promise()
    local headers = {}
    local encoded = self.mailer:encode_message(from_addr, {to_addr}, headers, subject, body)
    self:get_user(from_addr)(function (sender)
        if iserror(sender) then
            resolve(make_error("sender (" .. from_addr .. ") is not a part of this server: " .. sender.error))
            return
        end
        self:get_user(to_addr)(function (target)
            --- @type mailparam
            local mail = {
                from = sender,
                to = target,
                id = headers["Message-ID"]:gsub("<(.*)>", "%1"),
                ---@diagnostic disable-next-line: assign-type-mismatch
                received = os.date("*t"),
                sender = "internal",
                subfolder = target.subfolder,
                subject = subject,
                unread = true,
                body = encoded
            }
            if not iserror(target) then
                -- if target is within this mail server store it right away
                self.mail_repository:store_mail(target, mail)(function (result)
                    if iserror(result) then
                        make_error("failed to store mail: " .. result.error)
                        return
                    end
                    mail.id = "o-" .. mail.id
                    mail.unread = false
                    self.mail_repository:store_mail(sender, mail, true)(function (result)
                        resolve(result)
                    end)
                end)
            else
                -- if target is outside, deliver the mail first and then store local outbound copy
                self.mailer:send_mail({
                    from = from_addr,
                    to = to_addr,
                    headers = headers,
                    subject = subject,
                    body = body
                })(function (result)
                    if iserror(result) then
                        make_error("sending mail faled: " .. result.error)
                        return
                    end
                    mail.id = "o-" .. mail.id
                    mail.unread = false
                    self.mail_repository:store_mail(sender, mail, true)(function (result)
                        resolve(result)
                    end)
                end)
            end
        end)
    end)
    return resolver
end

if not ... then
    local email_backend = mysql_backend.backend
    email_backend:init({
        host = os.getenv("MYSQL_HOST"),
        port = tonumber(os.getenv("MYSQL_PORT") or "3306"),
        user = os.getenv("MYSQL_USER") or "mail",
        password = os.getenv("MYSQL_PASSWORD") or "smtp25",
        db = os.getenv("MYSQL_DB") or "mails",
        salt = os.getenv("SALT") or "salt"
    })
    core_mail:init({
        smtp = PORT % 1000 == 25,
        webmail = PORT >= 8000,
        users = mysql_backend.users,
        mails = mysql_backend.mails,
        host = os.getenv("SMTP_HOST") or "localhost"
    })
end

return core_mail