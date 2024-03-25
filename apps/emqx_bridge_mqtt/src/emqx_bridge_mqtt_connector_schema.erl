%%-------------------------------------------------------------------
%% Copyright (c) 2020-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_bridge_mqtt_connector_schema).

-behaviour(emqx_connector_examples).

-include_lib("typerefl/include/types.hrl").
-include_lib("hocon/include/hoconsc.hrl").
-include_lib("emqx/include/logger.hrl").

-behaviour(hocon_schema).

-export([
    namespace/0,
    roots/0,
    fields/1,
    desc/1,
    parse_server/1
]).

-export([
    connector_examples/1
]).

-import(emqx_schema, [mk_duration/2]).

-import(hoconsc, [mk/2, ref/2]).

-define(CONNECTOR_TYPE, mqtt).
-define(MQTT_HOST_OPTS, #{default_port => 1883}).

namespace() -> "connector_mqtt".

roots() ->
    fields("config").

fields("config") ->
    fields("server_configs") ++
        [
            {"ingress",
                mk(
                    ref(?MODULE, "ingress"),
                    #{
                        required => {false, recursively},
                        desc => ?DESC("ingress_desc")
                    }
                )},
            {"egress",
                mk(
                    ref(?MODULE, "egress"),
                    #{
                        required => {false, recursively},
                        desc => ?DESC("egress_desc")
                    }
                )}
        ];
fields("config_connector") ->
    emqx_connector_schema:common_fields() ++ fields("specific_connector_config");
fields("specific_connector_config") ->
    [{pool_size, fun egress_pool_size/1}] ++
        emqx_connector_schema:resource_opts_ref(?MODULE, resource_opts) ++
        fields("server_configs");
fields(resource_opts) ->
    emqx_connector_schema:resource_opts_fields();
fields("server_configs") ->
    [
        {mode,
            mk(
                hoconsc:enum([cluster_shareload]),
                #{
                    default => cluster_shareload,
                    desc => ?DESC("mode"),
                    deprecated => {since, "v5.1.0 & e5.1.0"}
                }
            )},
        {server, emqx_schema:servers_sc(#{desc => ?DESC("server")}, ?MQTT_HOST_OPTS)},
        {clientid_prefix, mk(binary(), #{required => false, desc => ?DESC("clientid_prefix")})},
        {reconnect_interval, mk(string(), #{deprecated => {since, "v5.0.16"}})},
        {proto_ver,
            mk(
                hoconsc:enum([v3, v4, v5]),
                #{
                    default => v4,
                    desc => ?DESC("proto_ver")
                }
            )},
        {bridge_mode,
            mk(
                boolean(),
                #{
                    default => false,
                    desc => ?DESC("bridge_mode")
                }
            )},
        {username,
            mk(
                binary(),
                #{
                    desc => ?DESC("username")
                }
            )},
        {password,
            emqx_schema_secret:mk(
                #{
                    desc => ?DESC("password")
                }
            )},
        {clean_start,
            mk(
                boolean(),
                #{
                    default => true,
                    desc => ?DESC("clean_start")
                }
            )},
        {keepalive, mk_duration("MQTT Keepalive.", #{default => <<"300s">>})},
        {retry_interval,
            mk_duration(
                "Message retry interval. Delay for the MQTT bridge to retry sending the QoS1/QoS2 "
                "messages in case of ACK not received.",
                #{default => <<"15s">>}
            )},
        {max_inflight,
            mk(
                non_neg_integer(),
                #{
                    default => 32,
                    desc => ?DESC("max_inflight")
                }
            )}
    ] ++ emqx_connector_schema_lib:ssl_fields();
fields("ingress") ->
    [
        {pool_size, fun ingress_pool_size/1},
        %% array
        {remote,
            mk(
                ref(?MODULE, "ingress_remote"),
                #{desc => ?DESC("ingress_remote")}
            )},
        {local,
            mk(
                ref(?MODULE, "ingress_local"),
                #{
                    desc => ?DESC("ingress_local")
                }
            )}
    ];
fields(connector_ingress) ->
    [
        {remote,
            mk(
                ref(?MODULE, "ingress_remote"),
                #{desc => ?DESC("ingress_remote")}
            )},
        {local,
            mk(
                ref(?MODULE, "ingress_local"),
                #{
                    desc => ?DESC("ingress_local"),
                    importance => ?IMPORTANCE_HIDDEN
                }
            )}
    ];
fields("ingress_remote") ->
    [
        {topic,
            mk(
                binary(),
                #{
                    required => true,
                    validator => fun emqx_schema:non_empty_string/1,
                    desc => ?DESC("ingress_remote_topic")
                }
            )},
        {qos,
            mk(
                emqx_schema:qos(),
                #{
                    default => 1,
                    desc => ?DESC("ingress_remote_qos")
                }
            )}
    ];
fields("ingress_local") ->
    [
        {topic,
            mk(
                binary(),
                #{
                    validator => fun emqx_schema:non_empty_string/1,
                    desc => ?DESC("ingress_local_topic"),
                    required => false
                }
            )},
        {qos,
            mk(
                qos(),
                #{
                    default => <<"${qos}">>,
                    desc => ?DESC("ingress_local_qos")
                }
            )},
        {retain,
            mk(
                hoconsc:union([boolean(), binary()]),
                #{
                    default => <<"${retain}">>,
                    desc => ?DESC("retain")
                }
            )},
        {payload,
            mk(
                binary(),
                #{
                    default => undefined,
                    desc => ?DESC("payload")
                }
            )}
    ];
fields("egress") ->
    [
        {pool_size, fun egress_pool_size/1},
        {local,
            mk(
                ref(?MODULE, "egress_local"),
                #{
                    desc => ?DESC("egress_local"),
                    required => false
                }
            )},
        {remote,
            mk(
                ref(?MODULE, "egress_remote"),
                #{
                    desc => ?DESC("egress_remote"),
                    required => true
                }
            )}
    ];
fields("egress_local") ->
    [
        {topic,
            mk(
                binary(),
                #{
                    desc => ?DESC("egress_local_topic"),
                    required => false,
                    validator => fun emqx_schema:non_empty_string/1
                }
            )}
    ];
fields("egress_remote") ->
    [
        {topic,
            mk(
                binary(),
                #{
                    required => true,
                    validator => fun emqx_schema:non_empty_string/1,
                    desc => ?DESC("egress_remote_topic")
                }
            )},
        {qos,
            mk(
                qos(),
                #{
                    required => false,
                    default => 1,
                    desc => ?DESC("egress_remote_qos")
                }
            )},
        {retain,
            mk(
                hoconsc:union([boolean(), binary()]),
                #{
                    required => false,
                    default => false,
                    desc => ?DESC("retain")
                }
            )},
        {payload,
            mk(
                binary(),
                #{
                    default => undefined,
                    desc => ?DESC("payload")
                }
            )}
    ];
fields(Field) when
    Field == "get_connector";
    Field == "put_connector";
    Field == "post_connector"
->
    Fields = fields("specific_connector_config"),
    emqx_connector_schema:api_fields(Field, ?CONNECTOR_TYPE, Fields);
fields(What) ->
    error({?MODULE, missing_field_handler, What}).

ingress_pool_size(desc) ->
    ?DESC("ingress_pool_size");
ingress_pool_size(Prop) ->
    emqx_connector_schema_lib:pool_size(Prop).

egress_pool_size(desc) ->
    ?DESC("egress_pool_size");
egress_pool_size(Prop) ->
    emqx_connector_schema_lib:pool_size(Prop).

desc("server_configs") ->
    ?DESC("server_configs");
desc("config_connector") ->
    ?DESC("config_connector");
desc("ingress") ->
    ?DESC("ingress_desc");
desc("ingress_remote") ->
    ?DESC("ingress_remote");
desc("ingress_local") ->
    ?DESC("ingress_local");
desc("egress") ->
    ?DESC("egress_desc");
desc("egress_remote") ->
    ?DESC("egress_remote");
desc("egress_local") ->
    ?DESC("egress_local");
desc(resource_opts) ->
    ?DESC(emqx_resource_schema, <<"resource_opts">>);
desc(_) ->
    undefined.

qos() ->
    hoconsc:union([emqx_schema:qos(), binary()]).

parse_server(Str) ->
    #{hostname := Host, port := Port} = emqx_schema:parse_server(Str, ?MQTT_HOST_OPTS),
    {Host, Port}.

connector_examples(_Method) ->
    [#{}].
