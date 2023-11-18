require("aio.aio")
local mysql = require("aio.lib.mysql")
local orm = require("aio.lib.orm")
local smtp_backends = require("mail.backends")

local direction = { inbound = 0, outbound = 1 }

--- @class mysql_backend
mysql_backend_ = mysql_backend_ or {
    --- @type mysql
    connection = nil,
    orm_users = nil
}

local initialize_query = [[
create table if not exists users(
    id int primary key auto_increment,
    handle varchar(120),
    password varchar(100)
);

create table if not exists mails(
    id varchar(96) primary key,
    user_id int not null,
    mail_from text not null,
    mail_from_display text not null,
    mail_subject text not null,
    mail_raw text not null,
    direction int default 0,
    received_at datetime default current_timestamp,
    foreign key (user_id) references users(id)
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
            mailFrom = { field = "mail_from", type = orm.t.text },
            mailFromDisplay = { field = "mail_from_display", type = orm.t.text },
            mailSubject = { field = "mail_subject", type = orm.t.text },
            mailRaw = { field = "mail_raw", type = orm.t.text },
            direction = { field = "direction", type = orm.t.int },
            receivedAt = { field = "received_at", type = orm.t.datetime }
        },
        findById = true,
        findByUserIdId = true,
        findByUserId = true
    })
end

--- Get user by e-mail address
---@param email string user e-mail address
---@return aiopromise<smtp_user> user
function mysql_backend_:get_user(email)
    local resolve, resolver = aio:prepare_promise()
    self.users.one:byHandle(email)(function (result)
        if result == nil then
            resolve(make_error("user not found"))
        elseif iserror(result) then
            resolve(result)
        else
            resolve({
                id = self.to_user_id(result.id),
                email = result.handle,
                name = result.handle
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
                email = result.handle,
                name = result.handle
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
---@return aiopromise<{error: string|nil, ok: boolean|nil}> success
function mysql_backend_:store_mail(user, mail)
    local resolve, resolver = aio:prepare_promise()
    self.mails:insert({
        id = mail.id,
        userId = self.from_user_id(user.id),
        mailFrom = mail.from.email,
        mailFromDisplay = mail.from.name or mail.from.email,
        mailSubject = mail.subject,
        mailRaw = mail.body,
        direction = direction.inbound,
        receivedAt = mail.received
    })(function (result)
        if iserror(result) then
            resolve({error = result.error, ok = false})
        else
            resolve({ok = true})
        end
    end)
    return resolver
end

--- Retrieve all e-mails for e-mail address
---@param user_id string user ID
---@param pivot string|nil pivot point
---@param size integer|nil limit
---@return aiopromise<{mails: mailparam[], error: string?, pivot: string}> mails
function mysql_backend_:load_mails(user_id, pivot, size)
    local resolve, resolver = aio:prepare_promise()
    self.mails.all:byUserId(user_id, {orderBy = "received_at DESC"})(function (mails)
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
        id = mail.id,
        subject = mail.mailSubject,
        body = mail.mailRaw
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
            resolve(self.transform_mail(mail))
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