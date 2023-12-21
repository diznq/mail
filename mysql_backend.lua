require("aio.aio")
local mysql = require("aio.lib.mysql")
local orm = require("aio.lib.orm")
local smtp_backends = require("mail.backends")

local direction = { inbound = 0, outbound = 1 }

--- @class mysql_backend : smtp_mail_repository, smtp_user_repository
mysql_backend_ = mysql_backend_ or {
    --- @type mysql
    connection = nil,
    orm_users = nil,
    host_name = "localhost"
}

local initialize_query = [[
create table if not exists users(
    id int primary key auto_increment,
    handle varchar(120) not null,
    name text not null,
    password varchar(100) not null,
    unique(handle)
);

create table if not exists mails(
    id varchar(96) primary key,
    user_id int not null,
    subfolder varchar(64) not null,
    mail_from text not null,
    mail_from_display text not null,
    mail_subject text not null,
    mail_raw text not null,
    mail_sender text not null,
    direction int default 0,
    received_at datetime default current_timestamp,
    unread int default 1,
    foreign key (user_id) references users(id),
    index(subfolder)
);
]]

--- Initialize MySQL backend
---@param params {user: string, password: string, db: string, host: string|nil, port: integer|nil, salt: string|nil}
function mysql_backend_:init(params)
    self.connect_params = params
    self.salt = params.salt or "salt"
    if self.connection then return end
    self.connection = mysql:new()
    self.connection:connect(params.user, params.password, params.db, params.host, params.port)(function (ok, err)
        if not ok then
            print("[mysql_backend] failed to connect to MySQL server: ", err)
            self.ok = false
        else
            self.ok = true
        end
    end)

    self.users = orm:create(self.connection, {
        source = "users",
        index = {"id", "email"},
        --- @type ormentity
        entity = {
            id = { field = "id", type = orm.t.int },
            handle = { field = "handle", type = orm.t.varchar(120) },
            name = { field = "name", type = orm.t.text },
            password = { field = "password", type = orm.t.varchar(100) }
        },
        findById = true,
        findByHandle = true,
        findByHandlePassword = true
    })

    self.mails = orm:create(self.connection, {
        source = "mails",
        index = {"id"},
        --- @type ormentity
        entity = {
            id = { field = "id", type = orm.t.text },
            userId = { field = "user_id", type = orm.t.int },
            subfolder = { field = "subfolder", type = orm.t.varchar(64) },
            mailFrom = { field = "mail_from", type = orm.t.text },
            mailFromDisplay = { field = "mail_from_display", type = orm.t.text },
            mailSubject = { field = "mail_subject", type = orm.t.text },
            mailSender = { field = "mail_sender", type = orm.t.text },
            mailRaw = { field = "mail_raw", type = orm.t.text },
            direction = { field = "direction", type = orm.t.int },
            receivedAt = { field = "received_at", type = orm.t.datetime },
            unread = { field = "unread", type = orm.t.int },
        },
        findById = true,
        findByUserIdId = true,
        findByUserId = "SELECT id, user_id, subfolder, mail_from, mail_from_display, mail_subject, mail_sender, direction, received_at, unread FROM mails WHERE user_id='%d'",
        findByUserIdSubfolder = "SELECT id, user_id, subfolder, mail_from, mail_from_display, mail_subject, mail_sender, direction, received_at, unread FROM mails WHERE user_id = '%d' AND subfolder = '%s'"
    })
end

--- Resolve e-mail into real e-mail and subfolder
---@param email string targeted e-mail
---@return string email
---@return string subfolder
function mysql_backend_:resolve_email(email)
    local subfolder, real_email = email:match("^(.-).mbox.(.+)$")
    if subfolder then
        return real_email, subfolder
    end
    return email, ""
end

--- Get user by e-mail address
---@param email string user e-mail address
---@return aiopromise<smtp_user> user
function mysql_backend_:get_user(email)
    local resolve, resolver = aio:prepare_promise()
    local real_email, subfolder = self:resolve_email(email)
    if real_email == nil then
        resolve(make_error("failed to resolve e-mail address (" .. email .. ") into address and folder"))
        return resolver
    end
    self.users.one:byHandle(real_email)(function (result)
        if result == nil then
            resolve(make_error("user not found: " .. tostring(real_email) .. ", " .. tostring(subfolder)))
        elseif iserror(result) then
            resolve(result)
        else
            resolve({
                id = self.to_user_id(result.id),
                subfolder = subfolder,
                email = result.handle,
                name = result.name
            })
        end
    end)
    return resolver
end

--- Get user by ID
---@param user_id string user e-mail address
---@return aiopromise<smtp_user> user
function mysql_backend_:get_user_by_id(user_id)
    local resolve, resolver = aio:prepare_promise()
    self.users.one:byId(self.from_user_id(user_id))(function (result)
        if result == nil then
            resolve(make_error("user not found"))
        elseif iserror(result) then
            resolve(result)
        else
            resolve({
                id = self.to_user_id(result.id),
                subfolder = "",
                email = result.handle,
                name = result.name
            })
        end
    end)
    return resolver
end

--- Login with username (or e-mail) and password
---@param email string username or e-mail
---@param password string password
---@return aiopromise<smtp_user> user logged user
function mysql_backend_:login(email, password)
    local resolve, resolver = aio:prepare_promise()
    self.users.one:byHandlePassword(email, self:encode_password(email, password))(function (result)
        if result == nil then
            resolve(make_error("invalid user or password"))
        elseif iserror(result) then
            resolve(make_error("invalid user or password"))
        else
            resolve({
                id = self.to_user_id(result.id),
                subfolder = "",
                email = result.handle,
                name = result.handle
            })
        end
    end)
    return resolver
end

function mysql_backend_:encode_password(email, password)
    local pass = codec.hex_encode(crypto.hmac_sha256(crypto.hmac_sha256(password, email), self.salt))
    return pass
end


--- Store e-mail into repository
---@param user smtp_user user that we save e-mail for
---@param mail mailparam e-mail
---@param outbound boolean|nil true if outbound
---@return aiopromise<{error: string|nil, ok: boolean|nil}> success
function mysql_backend_:store_mail(user, mail, outbound)
    local resolve, resolver = aio:prepare_promise()
    self.mails:insert({
        id = mail.id,
        userId = self.from_user_id(user.id),
        subfolder=user.subfolder,
        mailFrom = mail.from.email,
        mailFromDisplay = mail.from.name or mail.from.email,
        mailSubject = mail.subject,
        mailSender = mail.sender,
        mailRaw = mail.body,
        direction = outbound and direction.outbound or direction.inbound,
        receivedAt = mail.received,
        unread = mail.unread and 1 or 0
    })(function (result)
        if iserror(result) then
            resolve({error = result.error, ok = false})
        else
            resolve({ok = true})
        end
    end)
    return resolver
end

--- Get user's e-mail subfolders
---@param user_id string user ID
---@return aiopromise<{error: string|nil, subfolders: smtp_subfolder[]}> subfolders
function mysql_backend_:get_subfolders(user_id)
    local resolve, resolver = aio:prepare_promise()
    self.connection:select("SELECT subfolder, COUNT(*) as c, SUM(unread) as u FROM mails WHERE user_id = '%s' GROUP BY subfolder", user_id)(function (rows, errorOrColumns)
        if rows == nil then
            resolve(make_error("failed to select subfolders"))
        else
            resolve({
                subfolders = aio:map(rows, function (result, index, ...)
                    return {
                        name = result.subfolder == "" and "[direct]" or result.subfolder,
                        count = tonumber(result.c),
                        unread = tonumber(result.u),
                        link = result.subfolder == "" and "[direct]" or result.subfolder,
                        system = result.subfolder == ""
                    }
                end)
            })
        end
    end)
    return resolver
end

--- Retrieve all e-mails for e-mail address
---@param user_id string user ID
---@param subfolder string|nil subfolder
---@param pivot string|nil pivot point
---@param size integer|nil limit
---@return aiopromise<{mails: mailparam[], error: string?, pivot: string}> mails
function mysql_backend_:load_mails(user_id, subfolder, pivot, size)
    local resolve, resolver = aio:prepare_promise()
    local promise = nil
    if subfolder ~= nil then
        promise = self.mails.all:byUserIdSubfolder(user_id, subfolder, {orderBy = "received_at DESC"})
    else
        promise = self.mails.all:byUserId(user_id, {orderBy = "received_at DESC"})
    end
    promise(function (mails)
        if iserror(mails) then
            resolve(mails)
        else
            resolve({mails = aio:map(mails, self.transform_mail)})
        end
    end)
    return resolver
end

function mysql_backend_.transform_mail(mail)
    return {
        from = {
            name = mail.mailFromDisplay,
            email = mail.mailFrom
        },
        to = {
            email = mysql_backend_.to_user_id(mail.userId),
        },
        received = mail.receivedAt,
        subfolder = mail.subfolder,
        sender = mail.mailSender,
        id = mail.id,
        subject = mail.mailSubject,
        body = mail.mailRaw,
        inbound = mail.direction == direction.inbound,
        unread = mail.unread > 0
    }
end

--- Retrieve full e-mail
---@param user_id string user ID
---@param mail_id string mail ID
---@return aiopromise<mailparam> mail
function mysql_backend_:load_mail(user_id, mail_id)
    local resolve, resolver = aio:prepare_promise()
    self.mails.one:byUserIdId(self.from_user_id(user_id), mail_id)(function (mail)
        if mail == nil or iserror(mail) then
            resolve(mail or make_error("invalid e-mail"))
        else
            self.mails:update(mail, {unread = 0})(function (result)
                resolve(self.transform_mail(mail))
            end)
        end
    end)
    return resolver
end

function mysql_backend_.to_user_id(num_id)
    return string.format("%d", num_id)
end

function mysql_backend_.from_user_id(str_id)
    return tonumber(str_id, 10)
end

return {
    users = mysql_backend_,
    mails = mysql_backend_,
    backend = mysql_backend_
}