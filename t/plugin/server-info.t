#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

master_on();
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: sanity check
--- yaml_config
plugins:
    - server-info
plugin_attr:
    server-info:
        report_interval: 60
--- config
location /t {
    content_by_lua_block {
        local json_decode = require("cjson.safe").decode
        local t = require("lib.test_admin").test
        local code, _, body = t('/apisix/server_info', ngx.HTTP_GET)
        if code >= 300 then
            ngx.status = code
        end

        local keys = {}
        body = json_decode(body)
        for k in pairs(body) do
            keys[#keys + 1] = k
        end

        table.sort(keys)
        for i = 1, #keys do
            ngx.say(keys[i], ": ", body[keys[i]])
        end
    }
}
--- request
GET /t
--- response_body eval
qr{^etcd_version: [\d\.]+
hostname: [a-zA-Z\-0-9\.]+
id: [a-zA-Z\-0-9]+
last_report_time: \d+
up_time: \d+
version: [\d\.]+
$}
--- no_error_log
[error]
--- error_log
timer created to report server info, interval: 60



=== TEST 2: disable server info plugin
--- yaml_config
plugins: {}
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code = t('/apisix/server_info', ngx.HTTP_GET)
        return ngx.exit(code)
    }
}
--- request
GET /t
--- error_code: 404
--- no_error_log
[error]
