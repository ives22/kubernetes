-- Redis 相关配置
local redis_host = "redis.default.svc.cluster.local"
local redis_port = 6379
local redis_password = "nR7H1CCelXOxOoSwsZlDe4SrNv"
local redis_key_white_list = "map_request_white_list"

-- 获取客户端 IP
local client_ip = ngx.var.remote_addr
ngx.log(ngx.ERR, "Client IP is: ", client_ip)

-- 引入 Redis 模块
local redis = require "resty.redis"

--  连接 Redis 并进行认证
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)  -- 1秒超时

    -- 连接 Redis
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        return nil
    end

    -- 进行 Redis 认证
    if redis_password and redis_password ~= "" then
        local auth_ok, auth_err = red:auth(redis_password)
        if not auth_ok then
            ngx.log(ngx.ERR, "Failed to authenticate with Redis: ", auth_err)
            red:close() -- 认证失败关闭连接
            return nil
        end
    end

    return red
end

-- 查询 Redis，检查IP是否在白名单中，先查 Redis 缓存，再查白名单**
local function is_ip_allowed(ip)
    local red = connect_redis()
    if not red then
        ngx.log(ngx.ERR, "Redis connection failed, defaulting to deny")
        return false
    end

    local res, err = red:sismember(redis_key_white_list, ip)
    if err then
        ngx.log(ngx.ERR, "Failed to query Redis whitelist: ", err)
        red:set_keepalive(10000, 100)
        return false
    end

    ngx.log(ngx.INFO, "IP ", ip, " is in whitelist: ", res)
    red:set_keepalive(10000, 100) -- 连接复用

    return res == 1
end

-- 逻辑判断
if is_ip_allowed(client_ip) then
    ngx.log(ngx.INFO, "Access granted for IP: ", client_ip)
else
    ngx.log(ngx.WARN, "Access denied for IP: ", client_ip)

    -- 设置返回的 HTTP 状态码
    ngx.status = ngx.HTTP_FORBIDDEN

    -- 设置 JSON 响应
    ngx.header.content_type = "application/json"
    ngx.say('{"error": "Forbidden", "message": "Your IP is not allowed"}')

    -- 结束请求
    ngx.exit(ngx.HTTP_FORBIDDEN)
end