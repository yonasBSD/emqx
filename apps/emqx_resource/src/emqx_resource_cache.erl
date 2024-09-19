%%--------------------------------------------------------------------
%% Copyright (c) 2024 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_resource_cache).

%% CRUD APIs
-export([new/0, write/3, is_exist/1, read/1, safe_read/1, erase/1]).
%% For Config management
-export([all_ids/0, list_all/0, group_ids/1]).
%% For health checks etc.
-export([read_status/1, read_mod/1, read_manager_pid/1]).
%% Hot-path
-export([get_runtime/1]).

-include("emqx_resource_runtime.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-record(connector, {
    id :: binary(),
    group :: binary(),
    manager_pid :: pid(),
    st_err :: st_err(),
    config :: term(),
    extra = []
}).

-type chan_key() :: {ConnectorId :: binary(), ChannelID :: binary()}.

-record(channel, {
    id :: chan_key(),
    error :: term(),
    status :: channel_status(),
    extra = []
}).

-define(STATE_PT_KEY(ID), {?MODULE, ID}).

new() ->
    emqx_utils_ets:new(?RESOURCE_STATE_CACHE, [
        ordered_set,
        public,
        {read_concurrency, true},
        {keypos, 2}
    ]).

-spec write(pid(), binary(), resource_data()) -> ok.
write(ManagerPid, Group, Data) ->
    #{
        id := ID,
        mod := Mod,
        callback_mode := CallbackMode,
        query_mode := QueryMode,
        config := Config,
        error := Error,
        state := State,
        status := Status,
        added_channels := AddedChannels
    } = Data,
    Connector = #connector{
        id = ID,
        group = Group,
        manager_pid = ManagerPid,
        st_err = #{
            status => Status,
            error => external_error(Error)
        },
        config = Config,
        extra = []
    },
    Channels = lists:map(fun to_channel_record/1, maps:to_list(AddedChannels)),
    Stable = #{
        mod => Mod,
        callback_mode => CallbackMode,
        query_mode => QueryMode,
        state => State
    },
    %% erase old channels (if any)
    ok = erase_old_channels(ID, maps:keys(AddedChannels)),
    %% put stable state in persistent_term
    ok = put_state_pt(ID, Stable),
    %% insert connector and channel states
    true = ets:insert(?RESOURCE_STATE_CACHE, [Connector | Channels]),
    ok.

%% @doc Read cached pieces and return a externalized map.
%% NOTE: Do not call this in hot-path.
%% TODO: move `group' into `resource_data()'.
-spec read(resource_id()) -> {resource_group(), resource_data()}.
read(ID) ->
    case safe_read(ID) of
        [] ->
            error({not_found, ID});
        [{G, D}] ->
            {G, D}
    end.

-spec safe_read(resource_id()) -> [{resource_group(), resource_data()}].
safe_read(ID) ->
    case ets:lookup(?RESOURCE_STATE_CACHE, ID) of
        [] ->
            [];
        [#connector{group = G} = C] ->
            Channels = find_channels(ID),
            [{G, make_resource_data(ID, C, Channels)}]
    end.

-spec read_status(resource_id()) -> not_found | st_err().
read_status(ID) ->
    ets:lookup_element(?RESOURCE_STATE_CACHE, ID, #connector.st_err, not_found).

-spec read_manager_pid(resource_id()) -> not_found | pid().
read_manager_pid(ID) ->
    ets:lookup_element(?RESOURCE_STATE_CACHE, ID, #connector.manager_pid, not_found).

-spec read_mod(resource_id()) -> not_found | {ok, module()}.
read_mod(ID) ->
    case get_state_pt(ID) of
        undefined ->
            not_found;
        #{mod := Mod} ->
            {ok, Mod}
    end.

-spec erase(resource_id()) -> ok.
erase(ID) ->
    MS = ets:fun2ms(fun(#channel{id = {C, _}}) when C =:= ID -> true end),
    _ = ets:select_delete(?RESOURCE_STATE_CACHE, MS),
    _ = ets:delete(?RESOURCE_STATE_CACHE, ID),
    _ = del_state_pt(?STATE_PT_KEY(ID)),
    ok.

erase_old_channels(ID, NewChanIds) ->
    OldChanIds = maps:keys(find_channels(ID)),
    DelChanIds = OldChanIds -- NewChanIds,
    lists:foreach(fun erase_channel/1, DelChanIds).

erase_channel(ChanId) ->
    Key = split_channel_id(ChanId),
    ets:delete(?RESOURCE_STATE_CACHE, Key).

-spec list_all() -> [resource_data()].
list_all() ->
    IDs = all_ids(),
    lists:foldr(
        fun(ID, Acc) ->
            case safe_read(ID) of
                [] ->
                    Acc;
                [{_G, Data}] ->
                    [Data | Acc]
            end
        end,
        [],
        IDs
    ).

group_ids(Group) ->
    MS = ets:fun2ms(fun(#connector{id = ID, group = G}) when G =:= Group -> ID end),
    ets:select(?RESOURCE_STATE_CACHE, MS).

all_ids() ->
    MS = ets:fun2ms(fun(#connector{id = ID}) -> ID end),
    ets:select(?RESOURCE_STATE_CACHE, MS).

%% @doc The most performance-critical call.
%% NOTE: ID is the action ID, but not connector ID.
-spec get_runtime(resource_id()) -> {ok, runtime()} | {error, not_found}.
get_runtime(ID) ->
    ChanKey = {ConnectorId, _ChanID} = split_channel_id(ID),
    try
        Stable = get_state_pt(ConnectorId),
        ChannelStatus = get_channel_status(ChanKey),
        StErr = ets:lookup_element(?RESOURCE_STATE_CACHE, ConnectorId, #connector.st_err),
        {ok, #rt{
            st_err = StErr,
            stable = Stable,
            channel_status = ChannelStatus
        }}
    catch
        error:badarg ->
            {error, not_found}
    end.

get_channel_status({_, ?NO_CHANNEL}) ->
    ?NO_CHANNEL;
get_channel_status(ChanKey) ->
    ets:lookup_element(?RESOURCE_STATE_CACHE, ChanKey, #channel.status, ?NO_CHANNEL).

get_state_pt(ID) ->
    try
        persistent_term:get(?STATE_PT_KEY(ID))
    catch
        error:badarg ->
            undefined
    end.

to_channel_record({ID0, #{status := Status, error := Error}}) ->
    ID = split_channel_id(ID0),
    #channel{
        id = ID,
        status = Status,
        error = Error,
        extra = []
    }.

split_channel_id(Id) when is_binary(Id) ->
    case binary:split(Id, <<":">>, [global]) of
        [
            ChannelGlobalType,
            ChannelSubType,
            ChannelName,
            <<"connector">>,
            ConnectorType,
            ConnectorName
        ] ->
            ConnectorId = <<"connector:", ConnectorType/binary, ":", ConnectorName/binary>>,
            ChannelId =
                <<ChannelGlobalType/binary, ":", ChannelSubType/binary, ":", ChannelName/binary>>,
            {ConnectorId, ChannelId};
        _ ->
            %% this is not a per-channel query, e.g. for authn/authz
            {Id, ?NO_CHANNEL}
    end.

%% State can be quite bloated, caching it in ets means excessive large term copies,
%% for each and every query so we keep it in persistent_term instead.
%% Connector state is relatively static, so persistent_term update triggered GC is less of a concern
%% comparing to other fields such as `status' and `error', which may change very often.
put_state_pt(ID, State) ->
    case get_state_pt(ID) of
        S when S =:= State ->
            %% identical
            ok;
        _ ->
            _ = persistent_term:put(?STATE_PT_KEY(ID), State),
            ok
    end.

del_state_pt(ID) ->
    _ = persistent_term:erase(?STATE_PT_KEY(ID)),
    ok.

is_exist(ID) ->
    ets:member(?RESOURCE_STATE_CACHE, ID).

make_resource_data(ID, Connector, Channels) ->
    #connector{
        st_err = #{
            error := Error,
            status := Status
        },
        config = Config
    } = Connector,
    #{
        mod := Mod,
        callback_mode := CallbackMode,
        query_mode := QueryMode,
        state := State
    } = get_state_pt(ID),

    #{
        id => ID,
        mod => Mod,
        callback_mode => CallbackMode,
        query_mode => QueryMode,
        error => Error,
        status => Status,
        config => Config,
        added_channels => Channels,
        state => State
    }.

find_channels(ConnectorID) ->
    MS = ets:fun2ms(fun(#channel{id = {Cid, _}} = C) when Cid =:= ConnectorID -> C end),
    List = ets:select(?RESOURCE_STATE_CACHE, MS),
    lists:foldl(
        fun(
            #channel{
                id = {ConnectorId, ChannelId},
                status = Status,
                error = Error
            },
            Acc
        ) ->
            Key = iolist_to_binary([ChannelId, ":", ConnectorId]),
            Acc#{Key => #{status => Status, error => Error}}
        end,
        #{},
        List
    ).

external_error({error, Reason}) -> Reason;
external_error(Other) -> Other.
