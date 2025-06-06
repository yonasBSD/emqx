%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @doc The frame parser for MQTT-SN protocol
-module(emqx_mqttsn_frame).

-behaviour(emqx_gateway_frame).

-include("emqx_mqttsn.hrl").

-export([
    initial_parse_state/1,
    serialize_opts/0,
    parse/2,
    serialize_pkt/2,
    message_type/1,
    format/1,
    type/1,
    is_message/1
]).

-define(flag, 1 / binary).
-define(byte, 8 / big - integer).
-define(short, 16 / big - integer).

-type parse_state() :: #{}.
-type serialize_opts() :: #{}.

-export_type([
    parse_state/0,
    serialize_opts/0
]).

%%--------------------------------------------------------------------
%% Initial

initial_parse_state(_) ->
    #{}.

serialize_opts() ->
    #{}.

%%--------------------------------------------------------------------
%% Parse MQTT-SN Message
%%--------------------------------------------------------------------

parse(<<16#01:?byte, Len:?short, Type:?byte, Var/binary>>, State) ->
    {ok, parse(Type, Len - 4, Var), <<>>, State};
parse(<<Len:?byte, Type:?byte, Var/binary>>, State) ->
    {ok, parse(Type, Len - 2, Var), <<>>, State}.

parse(Type, Len, Var) when Len =:= size(Var) ->
    #mqtt_sn_message{type = Type, variable = parse_var(Type, Var)};
parse(_Type, _Len, _Var) ->
    error(malformed_message_len).

parse_var(?SN_ADVERTISE, <<GwId:?byte, Duration:?short>>) ->
    {GwId, Duration};
parse_var(?SN_SEARCHGW, <<Radius:?byte>>) ->
    Radius;
parse_var(?SN_GWINFO, <<GwId:?byte, GwAdd/binary>>) ->
    {GwId, GwAdd};
parse_var(?SN_CONNECT, <<Flags:?flag, ProtocolId:?byte, Duration:?short, ClientId/binary>>) ->
    {parse_flags(?SN_CONNECT, Flags), ProtocolId, Duration, ClientId};
parse_var(?SN_CONNACK, <<ReturnCode:?byte>>) ->
    ReturnCode;
parse_var(?SN_WILLTOPICREQ, <<>>) ->
    undefined;
parse_var(?SN_WILLTOPIC, <<>>) ->
    undefined;
parse_var(?SN_WILLTOPIC, <<Flags:?flag, WillTopic/binary>>) ->
    {parse_flags(?SN_WILLTOPIC, Flags), WillTopic};
parse_var(?SN_WILLMSGREQ, <<>>) ->
    undefined;
parse_var(?SN_WILLMSG, <<WillMsg/binary>>) ->
    WillMsg;
parse_var(?SN_REGISTER, <<TopicId:?short, MsgId:?short, TopicName/binary>>) ->
    {TopicId, MsgId, TopicName};
parse_var(?SN_REGACK, <<TopicId:?short, MsgId:?short, ReturnCode:?byte>>) ->
    {TopicId, MsgId, ReturnCode};
parse_var(?SN_PUBLISH, <<FlagsBin:?flag, Topic:2/binary, MsgId:?short, Data/binary>>) ->
    #mqtt_sn_flags{topic_id_type = IdType} = Flags = parse_flags(?SN_PUBLISH, FlagsBin),
    {Flags, parse_topic(IdType, Topic), MsgId, Data};
parse_var(?SN_PUBACK, <<TopicId:?short, MsgId:?short, ReturnCode:?byte>>) ->
    {TopicId, MsgId, ReturnCode};
parse_var(PubRec, <<MsgId:?short>>) when
    PubRec == ?SN_PUBREC; PubRec == ?SN_PUBREL; PubRec == ?SN_PUBCOMP
->
    MsgId;
parse_var(Sub, <<FlagsBin:?flag, MsgId:?short, Topic/binary>>) when
    Sub == ?SN_SUBSCRIBE; Sub == ?SN_UNSUBSCRIBE
->
    #mqtt_sn_flags{topic_id_type = IdType} = Flags = parse_flags(Sub, FlagsBin),
    {Flags, MsgId, parse_topic(IdType, Topic)};
parse_var(?SN_SUBACK, <<Flags:?flag, TopicId:?short, MsgId:?short, ReturnCode:?byte>>) ->
    {parse_flags(?SN_SUBACK, Flags), TopicId, MsgId, ReturnCode};
parse_var(?SN_UNSUBACK, <<MsgId:?short>>) ->
    MsgId;
parse_var(?SN_PINGREQ, ClientId) ->
    ClientId;
parse_var(?SN_PINGRESP, _) ->
    undefined;
parse_var(?SN_DISCONNECT, <<>>) ->
    undefined;
parse_var(?SN_DISCONNECT, <<Duration:?short>>) ->
    Duration;
parse_var(?SN_WILLTOPICUPD, <<>>) ->
    {undefined, undefined};
parse_var(?SN_WILLTOPICUPD, <<Flags:?flag, WillTopic/binary>>) ->
    {parse_flags(?SN_WILLTOPICUPD, Flags), WillTopic};
parse_var(?SN_WILLMSGUPD, WillMsg) ->
    WillMsg;
parse_var(?SN_WILLTOPICRESP, <<ReturnCode:?byte>>) ->
    ReturnCode;
parse_var(?SN_WILLMSGRESP, <<ReturnCode:?byte>>) ->
    ReturnCode;
parse_var(_Type, _Var) ->
    error(unkown_message_type).

parse_flags(?SN_CONNECT, <<_D:1, _Q:2, _R:1, Will:1, CleanStart:1, _IdType:2>>) ->
    #mqtt_sn_flags{will = bool(Will), clean_start = bool(CleanStart)};
parse_flags(?SN_WILLTOPIC, <<_D:1, QoS:2, Retain:1, _Will:1, _C:1, _:2>>) ->
    #mqtt_sn_flags{qos = QoS, retain = bool(Retain)};
parse_flags(?SN_PUBLISH, <<Dup:1, QoS:2, Retain:1, _Will:1, _C:1, IdType:2>>) ->
    #mqtt_sn_flags{dup = bool(Dup), qos = QoS, retain = bool(Retain), topic_id_type = IdType};
parse_flags(Sub, <<Dup:1, QoS:2, _R:1, _Will:1, _C:1, IdType:2>>) when
    Sub == ?SN_SUBSCRIBE; Sub == ?SN_UNSUBSCRIBE
->
    #mqtt_sn_flags{dup = bool(Dup), qos = QoS, topic_id_type = IdType};
parse_flags(?SN_SUBACK, <<_D:1, QoS:2, _R:1, _W:1, _C:1, _Id:2>>) ->
    #mqtt_sn_flags{qos = QoS};
parse_flags(?SN_WILLTOPICUPD, <<_D:1, QoS:2, Retain:1, _W:1, _C:1, _Id:2>>) ->
    #mqtt_sn_flags{qos = QoS, retain = bool(Retain)};
parse_flags(_Type, _) ->
    error(malformed_message_flags).

parse_topic(2#00, Topic) -> Topic;
parse_topic(2#01, <<Id:16>>) -> Id;
parse_topic(2#10, Topic) -> Topic;
parse_topic(2#11, Topic) -> Topic.

%%--------------------------------------------------------------------
%% Serialize MQTT-SN Message
%%--------------------------------------------------------------------

serialize_pkt(#mqtt_sn_message{type = Type, variable = Var}, Opts) ->
    VarBin = serialize(Type, Var, Opts),
    VarLen = size(VarBin),
    case VarLen < 254 of
        true ->
            <<(VarLen + 2), Type, VarBin/binary>>;
        false ->
            <<16#01, (VarLen + 4):?short, Type, VarBin/binary>>
    end.

serialize(?SN_ADVERTISE, {GwId, Duration}, _Opts) ->
    <<GwId, Duration:?short>>;
serialize(?SN_SEARCHGW, Radius, _Opts) ->
    <<Radius>>;
serialize(?SN_GWINFO, {GwId, GwAdd}, _Opts) ->
    <<GwId, GwAdd/binary>>;
serialize(?SN_CONNECT, {Flags, ProtocolId, Duration, ClientId}, _Opts) ->
    <<(serialize_flags(Flags))/binary, ProtocolId, Duration:?short, ClientId/binary>>;
serialize(?SN_CONNACK, ReturnCode, _Opts) ->
    <<ReturnCode>>;
serialize(?SN_WILLTOPICREQ, _, _Opts) ->
    <<>>;
serialize(?SN_WILLTOPIC, undefined, _Opts) ->
    <<>>;
serialize(?SN_WILLTOPIC, {Flags, Topic}, _Opts) ->
    %% The WillTopic must a short topic name
    <<(serialize_flags(Flags))/binary, Topic/binary>>;
serialize(?SN_WILLMSGREQ, _, _Opts) ->
    <<>>;
serialize(?SN_WILLMSG, WillMsg, _Opts) ->
    WillMsg;
serialize(?SN_REGISTER, {TopicId, MsgId, TopicName}, _Opts) ->
    <<TopicId:?short, MsgId:?short, TopicName/binary>>;
serialize(?SN_REGACK, {TopicId, MsgId, ReturnCode}, _Opts) ->
    <<TopicId:?short, MsgId:?short, ReturnCode>>;
serialize(
    ?SN_PUBLISH,
    {Flags = #mqtt_sn_flags{topic_id_type = ?SN_NORMAL_TOPIC}, TopicId, MsgId, Data},
    _Opts
) ->
    <<(serialize_flags(Flags))/binary, TopicId:?short, MsgId:?short, Data/binary>>;
serialize(
    ?SN_PUBLISH,
    {Flags = #mqtt_sn_flags{topic_id_type = ?SN_PREDEFINED_TOPIC}, TopicId, MsgId, Data},
    _Opts
) ->
    <<(serialize_flags(Flags))/binary, TopicId:?short, MsgId:?short, Data/binary>>;
serialize(
    ?SN_PUBLISH,
    {Flags = #mqtt_sn_flags{topic_id_type = ?SN_SHORT_TOPIC}, STopicName, MsgId, Data},
    _Opts
) ->
    <<(serialize_flags(Flags))/binary, STopicName:2/binary, MsgId:?short, Data/binary>>;
serialize(?SN_PUBACK, {TopicId, MsgId, ReturnCode}, _Opts) ->
    <<TopicId:?short, MsgId:?short, ReturnCode>>;
serialize(PubRec, MsgId, _Opts) when
    PubRec == ?SN_PUBREC; PubRec == ?SN_PUBREL; PubRec == ?SN_PUBCOMP
->
    <<MsgId:?short>>;
serialize(Sub, {Flags = #mqtt_sn_flags{topic_id_type = IdType}, MsgId, Topic}, _Opts) when
    Sub == ?SN_SUBSCRIBE; Sub == ?SN_UNSUBSCRIBE
->
    <<(serialize_flags(Flags))/binary, MsgId:16, (serialize_topic(IdType, Topic))/binary>>;
serialize(?SN_SUBACK, {Flags, TopicId, MsgId, ReturnCode}, _Opts) ->
    <<(serialize_flags(Flags))/binary, TopicId:?short, MsgId:?short, ReturnCode>>;
serialize(?SN_UNSUBACK, MsgId, _Opts) ->
    <<MsgId:?short>>;
serialize(?SN_PINGREQ, ClientId, _Opts) ->
    ClientId;
serialize(?SN_PINGRESP, _, _Opts) ->
    <<>>;
serialize(?SN_WILLTOPICUPD, {Flags, WillTopic}, _Opts) ->
    <<(serialize_flags(Flags))/binary, WillTopic/binary>>;
serialize(?SN_WILLMSGUPD, WillMsg, _Opts) ->
    WillMsg;
serialize(?SN_WILLTOPICRESP, ReturnCode, _Opts) ->
    <<ReturnCode>>;
serialize(?SN_WILLMSGRESP, ReturnCode, _Opts) ->
    <<ReturnCode>>;
serialize(?SN_DISCONNECT, undefined, _Opts) ->
    <<>>;
serialize(?SN_DISCONNECT, Duration, _Opts) ->
    <<Duration:?short>>.

serialize_flags(#mqtt_sn_flags{
    dup = Dup,
    qos = QoS,
    retain = Retain,
    will = Will,
    clean_start = CleanStart,
    topic_id_type = IdType
}) ->
    <<
        (bool(Dup)):1,
        (i(QoS)):2,
        (bool(Retain)):1,
        (bool(Will)):1,
        (bool(CleanStart)):1,
        (i(IdType)):2
    >>.

serialize_topic(2#00, Topic) -> Topic;
serialize_topic(2#01, Id) -> <<Id:?short>>;
serialize_topic(2#10, Topic) -> Topic;
serialize_topic(2#11, Topic) -> Topic.

bool(0) -> false;
bool(1) -> true;
bool(false) -> 0;
bool(true) -> 1;
bool(undefined) -> 0.

i(undefined) -> 0;
i(I) when is_integer(I) -> I.

message_type(16#00) ->
    "SN_ADVERTISE";
message_type(16#01) ->
    "SN_SEARCHGW";
message_type(16#02) ->
    "SN_GWINFO";
message_type(16#04) ->
    "SN_CONNECT";
message_type(16#05) ->
    "SN_CONNACK";
message_type(16#06) ->
    "SN_WILLTOPICREQ";
message_type(16#07) ->
    "SN_WILLTOPIC";
message_type(16#08) ->
    "SN_WILLMSGREQ";
message_type(16#09) ->
    "SN_WILLMSG";
message_type(16#0a) ->
    "SN_REGISTER";
message_type(16#0b) ->
    "SN_REGACK";
message_type(16#0c) ->
    "SN_PUBLISH";
message_type(16#0d) ->
    "SN_PUBACK";
message_type(16#0e) ->
    "SN_PUBCOMP";
message_type(16#0f) ->
    "SN_PUBREC";
message_type(16#10) ->
    "SN_PUBREL";
message_type(16#12) ->
    "SN_SUBSCRIBE";
message_type(16#13) ->
    "SN_SUBACK";
message_type(16#14) ->
    "SN_UNSUBSCRIBE";
message_type(16#15) ->
    "SN_UNSUBACK";
message_type(16#16) ->
    "SN_PINGREQ";
message_type(16#17) ->
    "SN_PINGRESP";
message_type(16#18) ->
    "SN_DISCONNECT";
message_type(16#1a) ->
    "SN_WILLTOPICUPD";
message_type(16#1b) ->
    "SN_WILLTOPICRESP";
message_type(16#1c) ->
    "SN_WILLMSGUPD";
message_type(16#1d) ->
    "SN_WILLMSGRESP";
message_type(Type) ->
    io_lib:format("Unknown Type ~p", [Type]).

format(?SN_CONNECT_MSG(Flags, ProtocolId, Duration, ClientId)) ->
    #mqtt_sn_flags{
        will = Will,
        clean_start = CleanStart
    } = Flags,
    io_lib:format(
        "SN_CONNECT(W~w, C~w, ProtocolId=~w, Duration=~w, "
        "ClientId=~ts)",
        [
            bool(Will),
            bool(CleanStart),
            ProtocolId,
            Duration,
            ClientId
        ]
    );
format(?SN_CONNACK_MSG(ReturnCode)) ->
    io_lib:format("SN_CONNACK(ReturnCode=~w)", [ReturnCode]);
format(?SN_WILLTOPICREQ_MSG()) ->
    "SN_WILLTOPICREQ()";
format(?SN_WILLTOPIC_MSG(Flags, Topic)) ->
    #mqtt_sn_flags{
        qos = QoS,
        retain = Retain
    } = Flags,
    io_lib:format(
        "SN_WILLTOPIC(Q~w, R~w, Topic=~s)",
        [QoS, bool(Retain), Topic]
    );
format(?SN_WILLTOPIC_EMPTY_MSG) ->
    "SN_WILLTOPIC(_)";
format(?SN_WILLMSGREQ_MSG()) ->
    "SN_WILLMSGREQ()";
format(?SN_WILLMSG_MSG(Msg)) ->
    io_lib:format("SN_WILLMSG_MSG(Msg=~p)", [Msg]);
format(?SN_PUBLISH_MSG(Flags, TopicId, MsgId, Data)) ->
    #mqtt_sn_flags{
        dup = Dup,
        qos = QoS,
        retain = Retain,
        topic_id_type = TopicIdType
    } = Flags,
    io_lib:format(
        "SN_PUBLISH(D~w, Q~w, R~w, TopicIdType=~w, TopicId=~w, "
        "MsgId=~w, Payload=~p)",
        [
            bool(Dup),
            QoS,
            bool(Retain),
            TopicIdType,
            TopicId,
            MsgId,
            Data
        ]
    );
format(?SN_PUBACK_MSG(TopicId, MsgId, ReturnCode)) ->
    io_lib:format(
        "SN_PUBACK(TopicId=~w, MsgId=~w, ReturnCode=~w)",
        [TopicId, MsgId, ReturnCode]
    );
format(?SN_PUBREC_MSG(?SN_PUBCOMP, MsgId)) ->
    io_lib:format("SN_PUBCOMP(MsgId=~w)", [MsgId]);
format(?SN_PUBREC_MSG(?SN_PUBREC, MsgId)) ->
    io_lib:format("SN_PUBREC(MsgId=~w)", [MsgId]);
format(?SN_PUBREC_MSG(?SN_PUBREL, MsgId)) ->
    io_lib:format("SN_PUBREL(MsgId=~w)", [MsgId]);
format(?SN_SUBSCRIBE_MSG(Flags, Msgid, Topic)) ->
    #mqtt_sn_flags{
        dup = Dup,
        qos = QoS,
        topic_id_type = TopicIdType
    } = Flags,
    io_lib:format(
        "SN_SUBSCRIBE(D~w, Q~w, TopicIdType=~w, MsgId=~w, "
        "TopicId=~w)",
        [bool(Dup), QoS, TopicIdType, Msgid, Topic]
    );
format(?SN_SUBACK_MSG(Flags, TopicId, MsgId, ReturnCode)) ->
    #mqtt_sn_flags{qos = QoS} = Flags,
    io_lib:format(
        "SN_SUBACK(GrantedQoS=~w, MsgId=~w, TopicId=~w, "
        "ReturnCode=~w)",
        [QoS, MsgId, TopicId, ReturnCode]
    );
format(?SN_UNSUBSCRIBE_MSG(Flags, Msgid, Topic)) ->
    #mqtt_sn_flags{topic_id_type = TopicIdType} = Flags,
    io_lib:format(
        "SN_UNSUBSCRIBE(TopicIdType=~w, MsgId=~w, TopicId=~w)",
        [TopicIdType, Msgid, Topic]
    );
format(?SN_UNSUBACK_MSG(MsgId)) ->
    io_lib:format("SN_UNSUBACK(MsgId=~w)", [MsgId]);
format(?SN_REGISTER_MSG(TopicId, MsgId, TopicName)) ->
    io_lib:format(
        "SN_REGISTER(TopicId=~w, MsgId=~w, TopicName=~s)",
        [TopicId, MsgId, TopicName]
    );
format(?SN_REGACK_MSG(TopicId, MsgId, ReturnCode)) ->
    io_lib:format(
        "SN_REGACK(TopicId=~w, MsgId=~w, ReturnCode=~w)",
        [TopicId, MsgId, ReturnCode]
    );
format(?SN_PINGREQ_MSG(ClientId)) ->
    io_lib:format("SN_PINGREQ(ClientId=~s)", [ClientId]);
format(?SN_PINGRESP_MSG()) ->
    "SN_PINGRESP()";
format(?SN_DISCONNECT_MSG(Duration)) ->
    io_lib:format("SN_DISCONNECT(Duration=~w)", [Duration]);
format(#mqtt_sn_message{type = Type, variable = Var}) ->
    io_lib:format(
        "mqtt_sn_message(type=~s, Var=~w)",
        [emqx_mqttsn_frame:message_type(Type), Var]
    ).

is_message(#mqtt_sn_message{type = Type}) when
    Type == ?SN_PUBLISH
->
    true;
is_message(_) ->
    false.

type(#mqtt_sn_message{type = Type}) ->
    type(Type);
type(?SN_ADVERTISE) ->
    advertise;
type(?SN_SEARCHGW) ->
    serachgw;
type(?SN_GWINFO) ->
    gwinfo;
type(?SN_CONNECT) ->
    connect;
type(?SN_CONNACK) ->
    connack;
type(?SN_WILLTOPICREQ) ->
    willtopicreq;
type(?SN_WILLTOPIC) ->
    willtopic;
type(?SN_WILLMSGREQ) ->
    willmsgreq;
type(?SN_WILLMSG) ->
    willmsg;
type(?SN_REGISTER) ->
    register;
type(?SN_REGACK) ->
    regack;
type(?SN_PUBLISH) ->
    publish;
type(?SN_PUBACK) ->
    puback;
type(?SN_PUBCOMP) ->
    pubcomp;
type(?SN_PUBREC) ->
    pubrec;
type(?SN_PUBREL) ->
    pubrel;
type(?SN_SUBSCRIBE) ->
    subscribe;
type(?SN_SUBACK) ->
    suback;
type(?SN_UNSUBSCRIBE) ->
    unsubscribe;
type(?SN_UNSUBACK) ->
    unsuback;
type(?SN_PINGREQ) ->
    pingreq;
type(?SN_PINGRESP) ->
    pingresp;
type(?SN_DISCONNECT) ->
    disconnect;
type(?SN_WILLTOPICUPD) ->
    willtopicupd;
type(?SN_WILLTOPICRESP) ->
    willtopicresp;
type(?SN_WILLMSGUPD) ->
    willmsgupd;
type(?SN_WILLMSGRESP) ->
    willmsgresp.
