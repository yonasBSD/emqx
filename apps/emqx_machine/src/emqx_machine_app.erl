%%--------------------------------------------------------------------
%% Copyright (c) 2021-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_machine_app).

-include_lib("emqx/include/logger.hrl").

-export([
    start/2,
    stop/1
]).

-behaviour(application).

start(_Type, _Args) ->
    ok = emqx_machine:start(),
    _ = emqx_restricted_shell:set_prompt_func(),
    emqx_machine_sup:start_link().

stop(_State) ->
    ok.
