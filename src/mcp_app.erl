-module(mcp_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    logger:info("MCP application starting..."),
    mcp_impl:start(),
    mcp_impl_rag:start(),
    mcp_sup:start_link().

stop(_State) ->
    ok.

