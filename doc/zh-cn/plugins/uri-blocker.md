<!--
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
-->

- [English](../../plugins/uri-blocker.md)

# 目录

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**启用方式**](#启用方式)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 定义

该插件可帮助我们拦截用户请求，只需要指定`block_rules`即可。

## 属性列表

|Name          |Requirement  |Description|
|---------     |--------|-----------|
|block_rules  |必须|正则过滤数组。它们都是正则规则，如果当前请求 URI 命中任何一个，请将响应代码设置为 rejected_code 以退出当前用户请求。例如: `["root.exe", "root.m+"]`。|
|rejected_code |可选|当请求 URI 命中`block_rules`中的任何一个时，将返回的 HTTP 状态代码，默认为 `403`。|

## 启用方式

这是一个示例，在指定的路由上启用`uri blocker`插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "plugins": {
        "uri-blocker": {
            "block_rules": ["root.exe", "root.m+"]
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

```shell
$ curl -i http://127.0.0.1:9080/root.exe?a=a
HTTP/1.1 403 Forbidden
Date: Wed, 17 Jun 2020 13:55:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 150
Connection: keep-alive
Server: APISIX web server

... ...
```

## 禁用插件

当想禁用`uri blocker`插件时，非常简单，只需要在插件配置中删除相应的 json 配置，无需重启服务，即可立即生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

 `uri blocker` 插件现在已被禁用，它也适用于其他插件。
