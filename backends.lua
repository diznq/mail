require("aio.aio")

--- @class smtp_user
local smtp_user = {
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
---@param email string user's e-mail address
---@return aiopromise<smtp_user> user
function smtp_user_repository:get_user(email)
    local resolve, resolver = aio:prepare_promise()
    resolve({name = email, email = email})
    return resolver
end

--- Login with username (or e-mail) and password
---@param email string username or e-mail
---@param password string password
---@return aiopromise<smtp_user> user logged user
function smtp_user_repository:login(email, password)
    local resolve, resolver = aio:prepare_promise()
    resolve({name = email, email = email})
    return resolver
end

--- Store e-mail into repository
---@param user smtp_user
---@param mail mailparam e-mail
---@return aiopromise<{error: string|nil, ok: boolean|nil}> success
function smtp_mail_repository:store_mail(user, mail)
    local resolve, resolver = aio:prepare_promise()
    local to = user.email
    self.mails[to] = self.mails[to] or {}
    self.mails[to][#self.mails[to]+1] = mail
    resolve({ok = true})
    return resolver
end

--- Retrieve all e-mails for e-mail address
---@param address string e-mail address
---@param pivot string|nil pivot point
---@param size integer|nil limit
---@return aiopromise<{mails: mailparam[], error: string?, pivot: string}> mails
function smtp_mail_repository:load_mails(address, pivot, size)
    local resolve, resolver = aio:prepare_promise()
    local mails = self.mails[address] or {}
    resolve({
        mails = mails,
        pivot = "0"
    })
    return resolver
end

return {
    users = smtp_user_repository,
    mails = smtp_mail_repository,
    user = smtp_user
}