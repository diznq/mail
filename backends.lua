require("aio.aio")

--- @class smtp_user
local smtp_user = {
    id = "john.doe@80s",
    subfolder = "",
    email = "john.doe@80s",
    name = "John Doe",
    --- @type string|nil
    error = nil
}

--- @class smtp_user_repository
local smtp_user_repository = {
    users = {}
}

--- @class smtp_mail_repository
local smtp_mail_repository = {
    mails = {}
}

--- Get user by e-mail address
---@param email string user e-mail address
---@return aiopromise<smtp_user> user
function smtp_user_repository:get_user(email)
    local resolve, resolver = aio:prepare_promise()
    resolve({name = email, email = email})
    return resolver
end

--- Get user by ID
---@param id string user e-mail address
---@return aiopromise<smtp_user> user
function smtp_user_repository:get_user_by_id(id)
    local resolve, resolver = aio:prepare_promise()
    resolve({name = id, email = id})
    return resolver
end

--- Login with username (or e-mail) and password
---@param email string username or e-mail
---@param password string password
---@return aiopromise<smtp_user> user logged user
function smtp_user_repository:login(email, password)
    local resolve, resolver = aio:prepare_promise()
    resolve({name = email, email = email, id=email})
    return resolver
end

--- Store e-mail into repository
---@param user smtp_user user that we save e-mail for
---@param mail mailparam e-mail
---@return aiopromise<{error: string|nil, ok: boolean|nil}> success
function smtp_mail_repository:store_mail(user, mail)
    local resolve, resolver = aio:prepare_promise()
    local to = user.id
    self.mails[to] = self.mails[to] or {}
    self.mails[to][mail.id] = mail
    resolve({ok = true})
    return resolver
end

--- Retrieve all e-mails for e-mail address
---@param user_id string user ID
---@param pivot string|nil pivot point
---@param size integer|nil limit
---@return aiopromise<{mails: mailparam[], error: string?, pivot: string}> mails
function smtp_mail_repository:load_mails(user_id, pivot, size)
    local resolve, resolver = aio:prepare_promise()
    local mails = self.mails[user_id] or {}
    local mail_array = {}
    for _, mail in pairs(mails) do
        mail_array[#mail_array+1] = mail
    end
    resolve({
        mails = mail_array,
        pivot = "0"
    })
    return resolver
end

--- Retrieve full e-mail
---@param user_id string user ID
---@param mail_id string mail ID
---@return aiopromise<mailparam> mail
function smtp_mail_repository:load_mail(user_id, mail_id)
    local resolve, resolver = aio:prepare_promise()
    local mails = self.mails[user_id] or {}
    --- @type mailparam|nil
    local hit = mails[mail_id]
    if hit == nil then
        resolve(make_error("mail not found"))
    else
        resolve(hit)
    end
    return resolver
end

return {
    users = smtp_user_repository,
    mails = smtp_mail_repository,
    user = smtp_user
}