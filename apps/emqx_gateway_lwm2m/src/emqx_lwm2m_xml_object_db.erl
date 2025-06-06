%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_lwm2m_xml_object_db).

-include("emqx_lwm2m.hrl").
-include_lib("xmerl/include/xmerl.hrl").
-include_lib("emqx/include/logger.hrl").

% This module is for future use. Disabled now.

%% API
-export([
    start_link/1,
    stop/0,
    find_name/1,
    find_objectid/1
]).

%% gen_server.
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(LWM2M_OBJECT_DEF_TAB, lwm2m_object_def_tab).
-define(LWM2M_OBJECT_NAME_TO_ID_TAB, lwm2m_object_name_to_id_tab).

-type xmlElement() :: tuple().

-record(state, {}).

-elvis([{elvis_style, atom_naming_convention, disable}]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-spec start_link(string()) ->
    {ok, pid()}
    | ignore
    | {error, no_xml_files_found}
    | {error, term()}.
start_link(XmlDir) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [XmlDir], []).

-spec find_objectid(integer()) -> {error, no_xml_definition} | xmlElement().
find_objectid(ObjectId) ->
    ObjectIdInt =
        case is_list(ObjectId) of
            true -> list_to_integer(ObjectId);
            false -> ObjectId
        end,
    case ets:lookup(?LWM2M_OBJECT_DEF_TAB, ObjectIdInt) of
        [] -> {error, no_xml_definition};
        [{_ObjectId, Xml}] -> Xml
    end.

-spec find_name(string()) -> {error, no_xml_definition} | xmlElement().
find_name(Name) ->
    NameBinary =
        case is_list(Name) of
            true -> list_to_binary(Name);
            false -> Name
        end,
    case ets:lookup(?LWM2M_OBJECT_NAME_TO_ID_TAB, NameBinary) of
        [] ->
            {error, no_xml_definition};
        [{_NameBinary, ObjectId}] ->
            find_objectid(ObjectId)
    end.

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([XmlDir]) ->
    _ = ets:new(?LWM2M_OBJECT_DEF_TAB, [set, named_table, protected]),
    _ = ets:new(?LWM2M_OBJECT_NAME_TO_ID_TAB, [set, named_table, protected]),
    case load(XmlDir) of
        ok ->
            {ok, #state{}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ets:delete(?LWM2M_OBJECT_DEF_TAB),
    ets:delete(?LWM2M_OBJECT_NAME_TO_ID_TAB),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
load(BaseDir) ->
    Wild = filename:join(BaseDir, "*.xml"),
    Wild2 =
        case is_binary(Wild) of
            true ->
                erlang:binary_to_list(Wild);
            false ->
                Wild
        end,
    case filelib:wildcard(Wild2) of
        [] -> {error, no_xml_files_found};
        AllXmlFiles -> load_loop(AllXmlFiles)
    end.

load_loop([]) ->
    ok;
load_loop([FileName | T]) ->
    ObjectXml = load_xml(FileName),
    [#xmlText{value = ObjectIdString}] = xmerl_xpath:string("ObjectID/text()", ObjectXml),
    [#xmlText{value = Name}] = xmerl_xpath:string("Name/text()", ObjectXml),
    ObjectId = list_to_integer(ObjectIdString),
    NameBinary = list_to_binary(Name),
    ?SLOG(debug, #{
        msg => "load_object_succeed",
        filename => FileName,
        object_id => ObjectId,
        object_name => NameBinary
    }),
    ets:insert(?LWM2M_OBJECT_DEF_TAB, {ObjectId, ObjectXml}),
    ets:insert(?LWM2M_OBJECT_NAME_TO_ID_TAB, {NameBinary, ObjectId}),
    load_loop(T).

load_xml(FileName) ->
    {Xml, _Rest} = xmerl_scan:file(FileName),
    [ObjectXml] = xmerl_xpath:string("/LWM2M/Object", Xml),
    ObjectXml.
