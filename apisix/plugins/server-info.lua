--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local require = require
local core = require("apisix.core")
local timers = require("apisix.timers")

local ngx_time = ngx.time
local ngx_timer_at = ngx.timer.at
local type = type

local boot_time = os.time()
local plugin_name = "server-info"
local schema = {
    type = "object",
    additionalProperties = false,
}
local attr_schema = {
    type = "object",
    properties = {
        report_interval = {
            type = "integer",
            description = "server info reporting interval (unit: second)",
            default = 60,
            minimum = 60,
            maximum = 3600,
        },
        report_ttl = {
            type = "integer",
            description = "live time for server info in etcd",
            default = 7200,
            minimum = 3600,
            maximum = 86400,
        }
    }
}

local internal_status = ngx.shared.internal_status
if not internal_status then
    error("lua_shared_dict \"internal_status\" not configured")
end


local _M = {
    version = 0.1,
    priority = 990,
    name = plugin_name,
    schema = schema,
}


local function uninitialized_server_info()
    return {
        etcd_version     = "unknown",
        hostname         = core.utils.gethostname(),
        id               = core.id.get(),
        version          = core.version.VERSION,
        up_time          = ngx_time() - boot_time,
        boot_time        = boot_time,
        last_report_time = -1,
    }
end


-- server information will be saved into shared memory only if the key
-- "server_info" not exist if excl is true.
local function save(data, excl)
    local handler = excl and internal_status.add or internal_status.set

    local ok, err = handler(internal_status, "server_info", data)
    if not ok then
        if excl and err == "exists" then
            return true
        end

        return nil, err
    end

    return true
end


local function encode_and_save(server_info, excl)
    local data, err = core.json.encode(server_info)
    if not data then
        return nil, err
    end

    return save(data, excl)
end


local function get()
    local data, err = internal_status:get("server_info")
    if err ~= nil then
        return nil, err
    end

    if not data then
        return uninitialized_server_info()
    end

    local server_info, err = core.json.decode(data)
    if not server_info then
        return nil, err
    end

    server_info.up_time = ngx_time() - server_info.boot_time
    return server_info
end


local function report(premature, report_ttl)
    if premature then
        return
    end

    local server_info, err = get()
    if not server_info then
        core.log.error("failed to get server_info: ", err)
        return
    end

    if server_info.etcd_version == "unknown" then
        local res, err = core.etcd.server_version()
        if not res then
            core.log.error("failed to fetch etcd version: ", err)
            return

        elseif type(res.body) ~= "table" then
            core.log.error("failed to fetch etcd version: bad version info")
            return

        else
            server_info.etcd_version = res.body.etcdcluster
        end
    end

    server_info.last_report_time = ngx_time()

    local data, err = core.json.encode(server_info)
    if not data then
        core.log.error("failed to encode server_info: ", err)
        return
    end

    local key = "/data_plane/server_info/" .. server_info.id
    local ok, err = core.etcd.set(key, data, report_ttl)
    if not ok then
        core.log.error("failed to report server info to etcd: ", err)
        return
    end

    local ok, err = save(data, false)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
        return
    end
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.init()
    local ok, err = encode_and_save(uninitialized_server_info(), true)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
    end

    core.log.info("server info: ", core.json.delay_encode(get()))

    if core.config ~= require("apisix.core.config_etcd") then
        -- we don't need to report server info if etcd is not in use.
        return
    end

    local local_conf = core.config.local_conf()
    local attr = core.table.try_read_attr(local_conf, "plugin_attr",
                                          plugin_name)
    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("failed to check plugin_attr: ", err)
        return
    end

    local report_ttl = attr.report_ttl
    local start_at = ngx_time()

    local fn = function()
        local now = ngx_time()
        if now - start_at >= attr.report_interval then
            start_at = now
            report(nil, report_ttl)
        end
    end

    local ok, err = ngx_timer_at(0, report, report_ttl)
    if not ok then
        core.log.error("failed to create initial timer to report server info: ", err)
        return
    end

    timers.register_timer("plugin#server-info", fn, true)

    core.log.info("timer created to report server info, interval: ",
                  attr.report_interval)
end


function _M.destory()
    timers.unregister_timer("plugin#server-info", true)
end


return _M
