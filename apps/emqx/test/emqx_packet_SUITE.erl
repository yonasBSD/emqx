%%--------------------------------------------------------------------
%% Copyright (c) 2018-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_packet_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").

-include_lib("eunit/include/eunit.hrl").

-define(PACKETS, [
    {?CONNECT, 'CONNECT', ?CONNECT_PACKET(#mqtt_packet_connect{})},
    {?CONNACK, 'CONNACK', ?CONNACK_PACKET(?RC_SUCCESS)},
    {?PUBLISH, 'PUBLISH', ?PUBLISH_PACKET(?QOS_1)},
    {?PUBACK, 'PUBACK', ?PUBACK_PACKET(1)},
    {?PUBREC, 'PUBREC', ?PUBREC_PACKET(1)},
    {?PUBREL, 'PUBREL', ?PUBREL_PACKET(1)},
    {?PUBCOMP, 'PUBCOMP', ?PUBCOMP_PACKET(1)},
    {?SUBSCRIBE, 'SUBSCRIBE', ?SUBSCRIBE_PACKET(1, [])},
    {?SUBACK, 'SUBACK', ?SUBACK_PACKET(1, [0])},
    {?UNSUBSCRIBE, 'UNSUBSCRIBE', ?UNSUBSCRIBE_PACKET(1, [])},
    {?UNSUBACK, 'UNSUBACK', ?UNSUBACK_PACKET(1)},
    {?DISCONNECT, 'DISCONNECT', ?DISCONNECT_PACKET(?RC_SUCCESS)},
    {?AUTH, 'AUTH', ?AUTH_PACKET()}
]).

all() -> emqx_common_test_helpers:all(?MODULE).

t_type(_) ->
    lists:foreach(
        fun({Type, _Name, Packet}) ->
            ?assertEqual(Type, emqx_packet:type(Packet))
        end,
        ?PACKETS
    ).

t_type_name(_) ->
    lists:foreach(
        fun({_Type, Name, Packet}) ->
            ?assertEqual(Name, emqx_packet:type_name(Packet))
        end,
        ?PACKETS
    ).

t_dup(_) ->
    ?assertEqual(false, emqx_packet:dup(?PUBLISH_PACKET(?QOS_1))).

t_qos(_) ->
    lists:foreach(
        fun(QoS) ->
            ?assertEqual(QoS, emqx_packet:qos(?PUBLISH_PACKET(QoS)))
        end,
        [?QOS_0, ?QOS_1, ?QOS_2]
    ).

t_retain(_) ->
    ?assertEqual(false, emqx_packet:retain(?PUBLISH_PACKET(?QOS_1))).

t_proto_name(_) ->
    lists:foreach(
        fun({Ver, Name}) ->
            ConnPkt = ?CONNECT_PACKET(#mqtt_packet_connect{
                proto_ver = Ver,
                proto_name = Name
            }),
            ?assertEqual(Name, emqx_packet:proto_name(ConnPkt))
        end,
        ?PROTOCOL_NAMES
    ).

t_proto_ver(_) ->
    lists:foreach(
        fun(Ver) ->
            ConnPkt = ?CONNECT_PACKET(#mqtt_packet_connect{proto_ver = Ver}),
            ?assertEqual(Ver, emqx_packet:proto_ver(ConnPkt))
        end,
        [?MQTT_PROTO_V3, ?MQTT_PROTO_V4, ?MQTT_PROTO_V5]
    ).

t_connect_info(_) ->
    ConnPkt = #mqtt_packet_connect{
        will_flag = true,
        clientid = <<"clientid">>,
        username = <<"username">>,
        will_retain = true,
        will_qos = ?QOS_2,
        will_topic = <<"topic">>,
        will_payload = <<"payload">>
    },
    ?assertEqual(<<"MQTT">>, emqx_packet:info(proto_name, ConnPkt)),
    ?assertEqual(4, emqx_packet:info(proto_ver, ConnPkt)),
    ?assertEqual(false, emqx_packet:info(is_bridge, ConnPkt)),
    ?assertEqual(true, emqx_packet:info(clean_start, ConnPkt)),
    ?assertEqual(true, emqx_packet:info(will_flag, ConnPkt)),
    ?assertEqual(?QOS_2, emqx_packet:info(will_qos, ConnPkt)),
    ?assertEqual(true, emqx_packet:info(will_retain, ConnPkt)),
    ?assertEqual(0, emqx_packet:info(keepalive, ConnPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, ConnPkt)),
    ?assertEqual(<<"clientid">>, emqx_packet:info(clientid, ConnPkt)),
    ?assertEqual(#{}, emqx_packet:info(will_props, ConnPkt)),
    ?assertEqual(<<"topic">>, emqx_packet:info(will_topic, ConnPkt)),
    ?assertEqual(<<"payload">>, emqx_packet:info(will_payload, ConnPkt)),
    ?assertEqual(<<"username">>, emqx_packet:info(username, ConnPkt)),
    ?assertEqual(undefined, emqx_packet:info(password, ConnPkt)).

t_connack_info(_) ->
    AckPkt = #mqtt_packet_connack{ack_flags = 0, reason_code = 0},
    ?assertEqual(0, emqx_packet:info(ack_flags, AckPkt)),
    ?assertEqual(0, emqx_packet:info(reason_code, AckPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, AckPkt)).

t_publish_info(_) ->
    PubPkt = #mqtt_packet_publish{topic_name = <<"t">>, packet_id = 1},
    ?assertEqual(1, emqx_packet:info(packet_id, PubPkt)),
    ?assertEqual(<<"t">>, emqx_packet:info(topic_name, PubPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, PubPkt)).

t_puback_info(_) ->
    AckPkt = #mqtt_packet_puback{packet_id = 1, reason_code = 0},
    ?assertEqual(1, emqx_packet:info(packet_id, AckPkt)),
    ?assertEqual(0, emqx_packet:info(reason_code, AckPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, AckPkt)).

t_subscribe_info(_) ->
    TopicFilters = [{<<"t/#">>, #{}}],
    SubPkt = #mqtt_packet_subscribe{packet_id = 1, topic_filters = TopicFilters},
    ?assertEqual(1, emqx_packet:info(packet_id, SubPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, SubPkt)),
    ?assertEqual(TopicFilters, emqx_packet:info(topic_filters, SubPkt)).

t_suback_info(_) ->
    SubackPkt = #mqtt_packet_suback{packet_id = 1, reason_codes = [0]},
    ?assertEqual(1, emqx_packet:info(packet_id, SubackPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, SubackPkt)),
    ?assertEqual([0], emqx_packet:info(reason_codes, SubackPkt)).

t_unsubscribe_info(_) ->
    UnsubPkt = #mqtt_packet_unsubscribe{packet_id = 1, topic_filters = [<<"t/#">>]},
    ?assertEqual(1, emqx_packet:info(packet_id, UnsubPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, UnsubPkt)),
    ?assertEqual([<<"t/#">>], emqx_packet:info(topic_filters, UnsubPkt)).

t_unsuback_info(_) ->
    AckPkt = #mqtt_packet_unsuback{packet_id = 1, reason_codes = [0]},
    ?assertEqual(1, emqx_packet:info(packet_id, AckPkt)),
    ?assertEqual([0], emqx_packet:info(reason_codes, AckPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, AckPkt)).

t_disconnect_info(_) ->
    DisconnPkt = #mqtt_packet_disconnect{reason_code = 0},
    ?assertEqual(0, emqx_packet:info(reason_code, DisconnPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, DisconnPkt)).

t_auth_info(_) ->
    AuthPkt = #mqtt_packet_auth{reason_code = 0},
    ?assertEqual(0, emqx_packet:info(reason_code, AuthPkt)),
    ?assertEqual(#{}, emqx_packet:info(properties, AuthPkt)).

t_set_props(_) ->
    Pkts = [
        #mqtt_packet_connect{},
        #mqtt_packet_connack{},
        #mqtt_packet_publish{},
        #mqtt_packet_puback{},
        #mqtt_packet_subscribe{},
        #mqtt_packet_suback{},
        #mqtt_packet_unsubscribe{},
        #mqtt_packet_unsuback{},
        #mqtt_packet_disconnect{},
        #mqtt_packet_auth{}
    ],
    Props = #{'A-Fake-Props' => true},
    lists:foreach(
        fun(Pkt) ->
            ?assertEqual(Props, emqx_packet:info(properties, emqx_packet:set_props(Props, Pkt)))
        end,
        Pkts
    ).

t_check_publish(_) ->
    Props = #{'Response-Topic' => <<"responsetopic">>, 'Topic-Alias' => 1},
    ok = emqx_packet:check(?PUBLISH_PACKET(?QOS_1, <<"topic">>, 1, Props, <<"payload">>)),
    ok = emqx_packet:check(#mqtt_packet_publish{packet_id = 1, topic_name = <<"t">>}),

    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(#mqtt_packet_publish{
        topic_name = <<>>,
        properties = #{'Topic-Alias' => 0}
    }),
    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(
        ?PUBLISH_PACKET(?QOS_1, <<>>, 1, #{}, <<"payload">>)
    ),
    {error, ?RC_TOPIC_NAME_INVALID} = emqx_packet:check(
        ?PUBLISH_PACKET(?QOS_1, <<"+/+">>, 1, #{}, <<"payload">>)
    ),
    {error, ?RC_TOPIC_ALIAS_INVALID} = emqx_packet:check(
        ?PUBLISH_PACKET(1, <<"topic">>, 1, #{'Topic-Alias' => 0}, <<"payload">>)
    ),
    %% TODO::
    %% {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(
    %%    ?PUBLISH_PACKET(1, <<"topic">>, 1, #{'Subscription-Identifier' => 10}, <<"payload">>)
    %%),
    ok = emqx_packet:check(
        ?PUBLISH_PACKET(1, <<"topic">>, 1, #{'Subscription-Identifier' => 10}, <<"payload">>)
    ),
    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(
        ?PUBLISH_PACKET(1, <<"topic">>, 1, #{'Subscription-Identifier' => 0}, <<"payload">>)
    ),
    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(
        ?PUBLISH_PACKET(1, <<"topic">>, 1, #{'Response-Topic' => <<"+/+">>}, <<"payload">>)
    ).

t_check_subscribe(_) ->
    ok = emqx_packet:check(
        ?SUBSCRIBE_PACKET(
            1,
            #{'Subscription-Identifier' => 1},
            [{<<"topic">>, #{qos => ?QOS_0}}]
        )
    ),
    {error, ?RC_TOPIC_FILTER_INVALID} = emqx_packet:check(#mqtt_packet_subscribe{topic_filters = []}),
    {error, ?RC_SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED} =
        emqx_packet:check(
            ?SUBSCRIBE_PACKET(
                1,
                #{'Subscription-Identifier' => -1},
                [{<<"topic">>, #{qos => ?QOS_0, rp => 0}}]
            )
        ).

t_check_unsubscribe(_) ->
    ok = emqx_packet:check(?UNSUBSCRIBE_PACKET(1, [<<"topic">>])),
    {error, ?RC_TOPIC_FILTER_INVALID} = emqx_packet:check(?UNSUBSCRIBE_PACKET(1, [])).

t_check_connect(_) ->
    Opts = #{max_clientid_len => 5, mqtt_retain_available => false},
    ok = emqx_packet:check(#mqtt_packet_connect{}, Opts),
    ok = emqx_packet:check(
        ?CONNECT_PACKET(#mqtt_packet_connect{
            clientid = <<1>>,
            properties = #{'Receive-Maximum' => 1},
            will_flag = true,
            will_topic = <<"will_topic">>
        }),
        Opts
    ),
    ConnPkt1 = #mqtt_packet_connect{
        proto_name = <<"MQIsdp">>,
        proto_ver = ?MQTT_PROTO_V5
    },
    {error, ?RC_UNSUPPORTED_PROTOCOL_VERSION} = emqx_packet:check(ConnPkt1, Opts),

    ConnPkt2 = #mqtt_packet_connect{
        proto_ver = ?MQTT_PROTO_V3,
        proto_name = <<"MQIsdp">>,
        clientid = <<>>
    },
    {error, ?RC_CLIENT_IDENTIFIER_NOT_VALID} = emqx_packet:check(ConnPkt2, Opts),

    ConnPkt3 = #mqtt_packet_connect{clientid = <<"123456">>},
    {error, ?RC_CLIENT_IDENTIFIER_NOT_VALID} = emqx_packet:check(ConnPkt3, Opts),

    ConnPkt4 = #mqtt_packet_connect{
        will_flag = true,
        will_retain = true
    },
    {error, ?RC_RETAIN_NOT_SUPPORTED} = emqx_packet:check(ConnPkt4, Opts),

    ConnPkt5 = #mqtt_packet_connect{
        will_flag = true,
        will_topic = <<"#">>
    },
    {error, ?RC_TOPIC_NAME_INVALID} = emqx_packet:check(ConnPkt5, Opts),

    ConnPkt6 = ?CONNECT_PACKET(#mqtt_packet_connect{
        properties = #{'Request-Response-Information' => -1}
    }),
    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(ConnPkt6, Opts),

    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(
        ?CONNECT_PACKET(#mqtt_packet_connect{
            properties = #{'Request-Problem-Information' => 2}
        }),
        Opts
    ),
    {error, ?RC_PROTOCOL_ERROR} = emqx_packet:check(
        ?CONNECT_PACKET(#mqtt_packet_connect{
            properties = #{'Receive-Maximum' => 0}
        }),
        Opts
    ),
    ConnPkt7 = #mqtt_packet_connect{clientid = <<>>, clean_start = false},
    {error, ?RC_CLIENT_IDENTIFIER_NOT_VALID} = emqx_packet:check(ConnPkt7, Opts).

t_from_to_message(_) ->
    ExpectedMsg = emqx_message:make(<<"clientid">>, ?QOS_0, <<"topic">>, <<"payload">>),
    ExpectedMsg1 = emqx_message:set_flags(#{dup => false, retain => false}, ExpectedMsg),
    ExpectedMsg2 = emqx_message:set_headers(
        #{
            peerhost => {127, 0, 0, 1},
            protocol => mqtt,
            properties => #{},
            username => <<"test">>
        },
        ExpectedMsg1
    ),
    Pkt = #mqtt_packet{
        header = #mqtt_packet_header{
            type = ?PUBLISH,
            qos = ?QOS_0,
            retain = false,
            dup = false
        },
        variable = #mqtt_packet_publish{
            topic_name = <<"topic">>,
            packet_id = 10,
            properties = #{}
        },
        payload = <<"payload">>
    },
    MsgFromPkt = emqx_packet:to_message(
        Pkt,
        <<"clientid">>,
        #{
            protocol => mqtt,
            username => <<"test">>,
            peerhost => {127, 0, 0, 1}
        }
    ),
    ?assertEqual(ExpectedMsg2, MsgFromPkt#message{
        id = emqx_message:id(ExpectedMsg),
        timestamp = emqx_message:timestamp(ExpectedMsg)
    }).

t_will_msg(_) ->
    ?assertEqual(undefined, emqx_packet:will_msg(#mqtt_packet_connect{will_flag = false})),
    Pkt = #mqtt_packet_connect{
        will_flag = true,
        clientid = <<"clientid">>,
        username = "test",
        will_retain = true,
        will_qos = ?QOS_2,
        will_topic = <<"topic">>,
        will_props = #{},
        will_payload = <<"payload">>
    },
    Msg = emqx_packet:will_msg(Pkt),
    ?assertEqual(<<"clientid">>, Msg#message.from),
    ?assertEqual(<<"topic">>, Msg#message.topic),
    Pkt2 = #mqtt_packet_connect{
        will_flag = true,
        clientid = <<"clientid">>,
        username = "test",
        will_retain = true,
        will_qos = ?QOS_2,
        will_topic = <<"topic">>,
        will_payload = <<"payload">>
    },
    Msg2 = emqx_packet:will_msg(Pkt2),
    ?assertEqual(<<"clientid">>, Msg2#message.from),
    ?assertEqual(<<"topic">>, Msg2#message.topic).

t_format(_) ->
    io:format("~ts", [
        emqx_packet:format(
            #mqtt_packet{
                header = #mqtt_packet_header{type = ?CONNACK, retain = true, dup = 0},
                variable = undefined
            },
            text
        )
    ]),
    io:format(
        "~ts",
        [
            emqx_packet:format(
                #mqtt_packet{
                    header = #mqtt_packet_header{type = ?CONNACK},
                    variable = 1,
                    payload = <<"payload">>
                },
                text
            )
        ]
    ),
    io:format("~ts", [
        emqx_packet:format(
            ?CONNECT_PACKET(
                #mqtt_packet_connect{
                    will_flag = true,
                    will_retain = true,
                    will_qos = ?QOS_2,
                    will_topic = <<"topic">>,
                    will_payload = <<"payload">>
                }
            ),
            text
        )
    ]),
    io:format("~ts", [
        emqx_packet:format(?CONNECT_PACKET(#mqtt_packet_connect{password = password}), text)
    ]),
    io:format("~ts", [emqx_packet:format(?CONNACK_PACKET(?CONNACK_SERVER), text)]),
    io:format("~ts", [emqx_packet:format(?PUBLISH_PACKET(?QOS_1, 1), text)]),
    io:format("~ts", [
        emqx_packet:format(?PUBLISH_PACKET(?QOS_2, <<"topic">>, 10, <<"payload">>), text)
    ]),
    io:format("~ts", [emqx_packet:format(?PUBACK_PACKET(?PUBACK, 98), text)]),
    io:format("~ts", [emqx_packet:format(?PUBREL_PACKET(99), text)]),
    io:format("~ts", [
        emqx_packet:format(
            ?SUBSCRIBE_PACKET(15, [{<<"topic">>, ?QOS_0}, {<<"topic1">>, ?QOS_1}]), text
        )
    ]),
    io:format("~ts", [emqx_packet:format(?SUBACK_PACKET(40, [?QOS_0, ?QOS_1]), text)]),
    io:format("~ts", [emqx_packet:format(?UNSUBSCRIBE_PACKET(89, [<<"t">>, <<"t2">>]), text)]),
    io:format("~ts", [emqx_packet:format(?UNSUBACK_PACKET(90), text)]),
    io:format("~ts", [emqx_packet:format(?DISCONNECT_PACKET(128), text)]).

t_parse_empty_publish(_) ->
    %% 52: 0011(type=PUBLISH) 0100 (QoS=2)
    Packet = #mqtt_packet_publish{topic_name = <<>>},
    ?assertEqual({error, ?RC_PROTOCOL_ERROR}, emqx_packet:check(Packet)).
