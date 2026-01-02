-module(mcp_impl).
-behaviour(emcp).

-export([schema/0]).
-export([start/0]).

start() ->
    AllowedApiKeys = application:get_env(mcp, api_keys, []),
    {ok, RootDir} = application:get_env(mcp, root_dir),
    emcp:start(mymcp, mcp_impl, {0,0,0,0}, 8080, "/mcp", false, AllowedApiKeys, #{root_dir => RootDir}).


schema() ->
    #{
      name => <<"MCP Server">>,
      version => <<"0.1.0">>,
      description => <<"MCP server with linux console tools (sandboxed) and with a headless browser">>,
      tools => tools_info()
     }.


tools_info() ->
    [
        #{ definition =>
             #{ name        => <<"exec">>,
                description => <<"Run a command in a sandbox. The environment is Ubuntu.\n"
                                    "Runs the supplied string with bash -c internally; therefore the command "
                                    "argument must be a complete Bash command line as you would type it in a shell, "
                                    "including any redirections, pipelines, or other shell syntax. Do not wrap "
                                    "the whole command in an extra sh -c …; just provide the exact Bash statement to be executed.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"chdir">>  => #{ type => string, description => <<"The work directory">> },
                        <<"command">> => #{ type => string, description => <<"The command to run">> }
                    },
                    required => [<<"chdir">>, <<"command">>]
                }
             },
           function => fun exec/3
        },

        #{ definition =>
             #{ name        => <<"sys_datetime">>,
                description => <<"Get current local time, UTC time and Time-zone">>,
                inputSchema => #{ type => object, properties => #{} }
             },
           function    => fun sys_datetime/3
        },

        #{ definition =>
             #{ name        => <<"http_call">>,
                description => <<"Make arbitrary HTTP-calls to analyze sites and fetch data from Internet">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"method">>  => #{ type => string, default => <<"GET">>, description => <<"A HTTP method">> },
                        <<"url">>     => #{ type => string, description => <<"An escaped HTTP URL">> },
                        <<"headers">> => #{ type => object, default => #{}, description => <<"The Request's HTTP headers">> },
                        <<"body">>    => #{ type => string, description => <<"The Request's body, if any">> }
                    },
                    required => [<<"url">>]
                },
                outputSchema => #{
                    type       => object,
                    properties => #{
                        <<"http_version">> => #{ type => string,  description => <<"The Response's HTTP version">> },
                        <<"status_code">>  => #{ type => integer, description => <<"The Response's status code">> },
                        <<"status_string">>=> #{ type => string,  description => <<"The Response's status string">> },
                        <<"headers">>      => #{ type => object,  description => <<"The Response's HTTP headers">> },
                        <<"body">>         => #{ type => string,  description => <<"The Response's body, if any">> }
                    },
                    required => [<<"http_version">>, <<"status_code">>, <<"status_string">>, <<"headers">>]
                }
             },
           function => fun http_call/3
        },

        #{ definition => 
             #{ name        => <<"http_call_f">>,
                description => <<"Make arbitrary HTTP-calls to analyze sites and fetch data from Internet. The response body is saved to a file.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"method">>  => #{ type => string, default => <<"GET">>, description => <<"A HTTP method">> },
                        <<"url">>     => #{ type => string, description => <<"An escaped HTTP URL">> },
                        <<"headers">> => #{ type => object, default => #{}, description => <<"The Request's HTTP headers">> },
                        <<"body">>    => #{ type => string, description => <<"The Request's body, if any">> },
                        <<"path">>    => #{ type => string, description => <<"The file path to save response body">> }
                    },
                    required => [<<"url">>, <<"path">>]
                },
                outputSchema => #{
                    type       => object,
                    properties => #{
                        <<"http_version">> => #{ type => string,  description => <<"The Response's HTTP version">> },
                        <<"status_code">>  => #{ type => integer, description => <<"The Response's status code">> },
                        <<"status_string">>=> #{ type => string,  description => <<"The Response's status string">> },
                        <<"headers">>      => #{ type => object,  description => <<"The Response's HTTP headers">> }
                    },
                    required => [<<"http_version">>, <<"status_code">>, <<"status_string">>, <<"headers">>]
                }
             },
           function => fun http_call_f/3
        },

        #{ definition =>
             #{ name        => <<"http_session_create">>,
                description => <<"Create a session to connect to Internet site, using a headless browser">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                        <<"width">>        => #{ type => integer, description => <<"Viewport width in pixels">>, default => 1280 },
                        <<"height">>       => #{ type => integer, description => <<"Viewport height in pixels">>, default => 800 },
                        <<"mobile">>       => #{ type => boolean, description => <<"Emulate mobile device">>, default => false },
                        <<"locale">>       => #{ type => string,  description => <<"The browser locale">>, default => <<"en_US">> },
                        <<"idle_timeout">> => #{ type => integer, description => <<"Idle timeout in seconds">>, default => 600 }
                    }
                }
             },
           function    => fun http_session_create/3
        },

        #{ definition =>
             #{ name        => <<"http_session_close">>,
                description => <<"Close the session to Internet site in the headless browser">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The session id">> }
                    },
                    required => [<<"session_id">>]
                }
             },
           function => fun http_session_close/3
         },

        #{ definition =>
             #{ name        => <<"http_session_goto">>,
                description => <<"Open the Internet site, using a headless browser">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The session id">> },
                        <<"url">>        => #{ type => string, description => <<"The URL of the site">> }
                    },
                    required => [<<"session_id">>, <<"url">>]
                }
             },
           function => fun http_session_goto/3
         },

        #{ definition =>
             #{ name        => <<"http_session_wait">>,
                description => <<"Wait for an element on the page using headless browser">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string,  description => <<"The session id">> },
                        <<"selector">>   => #{ type => string,  description => <<"CSS selector of element">> },
                        <<"timeout">>    => #{ type => integer, description => <<"Timeout in ms">>, default => 30000 }
                    },
                    required => [<<"session_id">>, <<"selector">>]
                }
             },
           function => fun http_session_wait/3
         },

        #{ definition =>
             #{ name        => <<"http_session_eval">>,
                description => <<"Evaluate a javascript on the site, using a headless browser">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The session id">> },
                        <<"script">>     => #{ type => string, description => <<"The script (javascript)">> }
                    },
                    required => [<<"session_id">>, <<"script">>]
                }
             },
           function => fun http_session_eval/3
         },

        #{ definition =>
             #{ name        => <<"http_session_extract">>,
                description => <<"Extract a text (inner_text) of elements on the site, using a headless browser">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The session id">> },
                        <<"selector">>   => #{ type => string, description => <<"CSS selector of element">> }
                    },
                    required => [<<"session_id">>, <<"selector">>]
                }
             },
           function => fun http_session_extract/3
         },

       #{ definition =>
             #{ name        => <<"http_session_fill">>,
                description => <<"Fill a field on the site, using a headless browser">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The session id">> },
                        <<"selector">>   => #{ type => string, description => <<"CSS selector of element">> },
                        <<"value">>      => #{ type => string, description => <<"The value to fill">> }
                    },
                    required => [<<"session_id">>, <<"selector">>, <<"value">>]
                }
             },
           function => fun http_session_fill/3
         },


        #{ definition =>
             #{ name        => <<"http_session_screenshot">>,
                description => <<"Make a screenshot of the headless browser page">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The session id">> },
                        <<"selector">>   => #{ type => string, description => <<"The element for screenshot">>},
                        <<"full_page">>  => #{ type => boolean, description => <<"If true then a full page screenshot will be done">>},
                        <<"type">>       => #{ type => string, enum => [<<"png">>, <<"jpeg">>], description => <<"The image type: png or jpeg">>},
                        <<"quality">>    => #{ type => integer, min => 1, max => 100, description => <<"The image quality for jpeg (1-100)">>},
                        <<"path">>       => #{ type => string, description => <<"The file to save the screenshot">> }
                    },
                    required => [<<"session_id">>, <<"path">>]
                }
             },
           function => fun http_session_screenshot/3
         },

        #{ definition =>
             #{ name        => <<"http_session_click">>,
                description => <<"Make a click on an element in the headless browser page">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">>     => #{ type => string, description => <<"The session id">> },
                        <<"selector">>       => #{ type => string, description => <<"The element for click">>},
                        <<"human">>          => #{ type => boolean, description => <<"If true then emulate human behavior">>, default => false},
                        <<"button">>         => #{ type => string, enum => [<<"left">>, <<"right">>], description => <<"The mouse button to use">>, default => <<"left">>},
                        <<"click_count">>    => #{ type => integer, min => 1, max => 5, description => <<"Number of clicks">>, default => 1},
                        <<"hover_before">>   => #{ type => boolean, description => <<"Initiate a hover event before the click">>, default => true},
                        <<"move_duration_ms">> => #{ type => integer, description => <<"move_duration_ms">> },
                        <<"move_steps">>     => #{ type => integer, description => <<"move_steps">> },
                        <<"pre_delay_ms">>   => #{ type => integer, description => <<"pre_delay_ms">> },
                        <<"post_delay_ms">>  => #{ type => integer, description => <<"post_delay_ms">> },
                        <<"press_delay_ms">> => #{ type => integer, description => <<"press_delay_ms">> }
                    },
                    required => [<<"session_id">>, <<"selector">>]
                }
             },
           function => fun http_session_click/3
         },

        #{ definition =>
             #{ name => <<"read_image">>,
                description => <<"Read an image-file">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                        <<"path">> => #{ type => string, description => <<"The path to an image-file.">> }
                    },
                    required => [<<"path">>]
                }
             },
            function => fun read_image/3    
         }

    ].


    
%% Tool implementations

sys_datetime(_Name, _Args, _ExtraParams) ->
    Info=unicode:characters_to_binary(os:cmd("LC_ALL=C timedatectl | head -n4 |grep -v 'RTC time' | sed s/^[[:space:]]*//")),
    {ok, [#{<<"type">> => <<"text">>, <<"text">> => Info}]}.

http_call(_Name, #{<<"url">> := URL} = Args, _ExtraParams) ->
    Method = maps:get(<<"method">>, Args, <<"GET">>),
    Method1=case Method of
                <<"HEAD">> -> head;
                <<"GET">> -> get;
                <<"POST">> -> post;
                <<"PUT">> -> put;
                <<"DELETE">> -> delete;
                <<"OPTIONS">> -> options;
                <<"PATCH">> -> patch;
                <<"TRACE">> -> trace
            end,
    Headers = maps:get(<<"headers">>, Args, #{}),
    Headers1 = [{binary_to_list(N), V} || {N, V} <- maps:to_list(Headers)],

    Request = case maps:get(<<"body">>, Args, null) of
                  null ->
                     {URL, Headers1};
                  Body when is_binary(Body) ->
                     ContentType = maps:get(<<"content-type">>, Headers, <<"text/plain">>),
                     {URL, Headers1, ContentType, Body}
              end,

    case httpc:request(Method1, Request, [], [{body_format, binary}]) of
        {ok, {{HttpVersion, StatusCode, StatusString}, RespHeaders}} ->
            R = #{<<"http_version">> => list_to_binary(HttpVersion),
                  <<"status_code">> => StatusCode,
                  <<"status_string">> => list_to_binary(StatusString),
                  <<"headers">> => maps:from_list([{list_to_binary(H), list_to_binary(V)} || {H, V} <- RespHeaders])
                },
            {structured_ok, R};
        {ok, {{HttpVersion, StatusCode, StatusString}, RespHeaders, RespBody}} ->
            R = #{<<"http_version">> => list_to_binary(HttpVersion),
                  <<"status_code">> => StatusCode,
                  <<"status_string">> => list_to_binary(StatusString),
                  <<"headers">> => maps:from_list([{list_to_binary(H), list_to_binary(V)} || {H, V} <- RespHeaders]),
                  <<"body">> => RespBody
                },
            {structured_ok, R};
        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_call_f(_Name, #{<<"url">> := URL, <<"path">> :=Path} = Args, ExtraParams) ->
    Method = maps:get(<<"method">>, Args, <<"GET">>),
    Method1=case Method of
                <<"HEAD">> -> head;
                <<"GET">> -> get;
                <<"POST">> -> post;
                <<"PUT">> -> put;
                <<"DELETE">> -> delete;
                <<"OPTIONS">> -> options;
                <<"PATCH">> -> patch;
                <<"TRACE">> -> trace
            end,
    Headers = maps:get(<<"headers">>, Args, #{}),
    Headers1 = [{binary_to_list(N), V} || {N, V} <- maps:to_list(Headers)],

    Request = case maps:get(<<"body">>, Args, null) of
                  null ->
                     {URL, Headers1};
                  Body when is_binary(Body) ->
                     ContentType = maps:get(<<"content-type">>, Headers, <<"text/plain">>),
                     {URL, Headers1, ContentType, Body}
              end,

    case httpc:request(Method1, Request, [], [{body_format, binary}]) of
        {ok, {{HttpVersion, StatusCode, StatusString}, RespHeaders}} ->
            R = #{<<"http_version">> => list_to_binary(HttpVersion),
                  <<"status_code">> => StatusCode,
                  <<"status_string">> => list_to_binary(StatusString),
                  <<"headers">> => maps:from_list([{list_to_binary(H), list_to_binary(V)} || {H, V} <- RespHeaders])
                },
            {structured_ok, R};

        {ok, {{HttpVersion, StatusCode, StatusString}, RespHeaders, RespBody}} ->
            R = #{<<"http_version">> => list_to_binary(HttpVersion),
                  <<"status_code">> => StatusCode,
                  <<"status_string">> => list_to_binary(StatusString),
                  <<"headers">> => maps:from_list([{list_to_binary(H), list_to_binary(V)} || {H, V} <- RespHeaders])
                },
            Root = maps:get(root_dir, ExtraParams),
            case safe_path(Root, Path) of
                {ok, Abs} ->
                    ok = file:write_file(Abs, RespBody),
                    {structured_ok, R};
                {error, _} ->
                    {error, <<"outside_root">>}
            end;

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_create(_Name, Args, _ExtraParams) ->
    ExtraArgs = maps:with([<<"width">>, <<"height">>, <<"mobile">>, <<"locale">>, <<"idle_timeout">>], Args),
    ReqBody = jsx:encode(ExtraArgs),
    Request = {<<"http://localhost:8000/session/create">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, _RespCode, _StatusString}, _RespHeaders, _RespBody} = Resp} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~tp", [Resp])])};

        {error, Reason} ->
            logger:error("Request error:~n~p~n", [Reason]),
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_close(_Name, #{<<"session_id">> := Session} = _Args, _ExtraParams) ->
    Request = {<<"http://localhost:8000/session/", Session/binary, "/close">>, [], "application/json", <<>>},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, _RespCode, _StatusString}, _RespHeaders, _RespBody} = Resp} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~tp", [Resp])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_goto(_Name, #{<<"session_id">> := Session, <<"url">> := URL} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"goto">>,
                           <<"url">> => URL}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};
 
        {ok, {{_HttpVersion, _RespCode, _StatusString}, _RespHeaders, _RespBody} = Resp} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~tp", [Resp])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_wait(_Name, #{<<"session_id">> := Session, <<"selector">> := Selector} = Args, _ExtraParams) ->
    ReqBody = case maps:get(<<"timeout">>, Args, null) of
                  null ->
                      jsx:encode(#{<<"action">> => <<"wait">>,
                                   <<"selector">> => Selector});
                  Timeout ->
                      jsx:encode(#{<<"action">> => <<"wait">>,
                                   <<"selector">> => Selector,
                                   <<"timeout">> => Timeout})
             end,
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, RespStatusCode, _StatusString}, _RespHeaders, RespBody}} ->
            {error, unicode:characters_to_binary(io_lib:format("Request failed:~n~p~n~ts", [RespStatusCode, RespBody]))};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_eval(_Name, #{<<"session_id">> := Session, <<"script">> := Script} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"evaluate">>,
                           <<"script">> => Script}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, _Status, _StatusString}, _RespHeaders, RespBody}} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~ts", [RespBody])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_extract(_Name, #{<<"session_id">> := Session, <<"selector">> := Selector} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"extract">>,
                           <<"selector">> => Selector}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, _Status, _StatusString}, _RespHeaders, RespBody}} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~ts", [RespBody])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_fill(_Name, #{<<"session_id">> := Session, <<"selector">> := Selector, <<"value">> := Value} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"fill">>,
                           <<"selector">> => Selector,
                           <<"value">> => Value}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, _Status, _StatusString}, _RespHeaders, RespBody}} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~ts", [RespBody])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_screenshot(_Name, #{<<"session_id">> := Session} = Args, ExtraParams) ->
    ExtraArgs = maps:with([<<"selector">>, <<"full_page">>, <<"type">>, <<"quality">>], Args),
    ReqBody = jsx:encode(ExtraArgs#{<<"action">> => <<"screenshot">>}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            Resp = jsx:decode(RespBody),
            case maps:get(<<"image_data">>, Resp, null) of
                null ->
                    {error, <<"No image data in response">>};
                ImageDataB64 ->
                    Path = maps:get(<<"path">>, Args, <<"/tmp/screenshot.png">>),
                    ImageData = base64:decode(ImageDataB64),
                    Root = maps:get(root_dir, ExtraParams),
                    case safe_path(Root, Path) of
                        {ok, Abs} ->
                            ok = filelib:ensure_dir(Abs),
                            ok = file:write_file(Abs, ImageData),
                            {structured_ok, #{<<"saved_to">> => Path}};
                        {error, _} ->
                            {error, <<"outside_root">>}
                    end
            end;

        {ok, {{_HttpVersion, _Status, _StatusString}, _RespHeaders, RespBody}} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~ts", [RespBody])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

http_session_click(_Name, #{<<"session_id">> := Session} = Args, _ExtraParams) ->
    ExtraArgs = maps:with([<<"selector">>, <<"human">>, <<"button">>, <<"click_count">>,
         <<"hover_before">>, <<"move_duration_ms">>, <<"move_steps">>, <<"pre_delay_ms">>, 
         <<"post_delay_ms">>, <<"press_delay_ms">>], Args),
    ReqBody = jsx:encode(ExtraArgs#{<<"action">> => <<"click">>}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            {structured_ok, jsx:decode(RespBody)};

        {ok, {{_HttpVersion, _Status, _StatusString}, _RespHeaders, RespBody}} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~ts", [RespBody])])};

        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

exec(_Name, #{<<"chdir">> := Path0, <<"command">> :=Command}, ExtraParams) ->
    Root = maps:get(root_dir, ExtraParams),
    {ok, Output, Code} = mcp_sandbox:run(Root, Path0, Command),
    logger:info("Exec chdir:~ts~ncommand:~ts~nCode: ~p~nOutput:~n~tp~n", [Path0, Command, Code, Output]),
    {ok, [#{<<"type">> => <<"text">>, <<"text">> => jsx:encode(#{output => Output, code => Code})}]}.


read_image(_Name, #{<<"path">> := Path0}, ExtraParams) ->
    Root = maps:get(root_dir, ExtraParams),
    case safe_path(Root, Path0) of
        {ok, Abs} ->
            case file:read_file(Abs) of
                {ok, Data} ->
                    Encoded = base64:encode(Data),
                    {ok, [#{<<"type">> => <<"image">>, <<"data">> => Encoded, <<"mimeType">> => filename_to_mime(Abs)}]};
                {error, Reason} ->
                    {error, unicode:characters_to_binary([ <<"File read error: ">>, io_lib:format("~p", [Reason])])}
            end;
        {error, _} ->
            {error, <<"outside_root">>}
    end.




%%--------------------------------------------------------------------
%% @doc
%%   Проверяет, что пользовательский путь находится внутри заданного корня.
%%
%%   Возвращает {ok, AbsPath} если всё ОК,
%%            {error, Reason} иначе.
%%
%%   Пример:
%%       Root = "/var/www/public",
%%       safe_path(Root, "../etc/passwd") -> {error, outside_root}
%%--------------------------------------------------------------------
-spec safe_path(Root::string(), RelPath::string()) ->
          {ok, AbsPath::string()} | {error, outside_root}.

safe_path(Root, RelPath) ->
    RelPath0 = case unicode:characters_to_binary(RelPath) of
                    <<"/", Rest/binary>> -> %% absolute path given, make it relative
                        Rest;
                    RP ->
                        RP
                end,
    case filelib:safe_relative_path(RelPath0, Root) of
        unsafe -> {error, outside_root};
        Path -> {ok, filename:absname_join(Root, Path)}
    end.



-spec filename_to_mime(Filename::binary()) -> MIME::binary().
 filename_to_mime(Filename) ->
    case string:lowercase(filename:extension(Filename)) of
       
        %% --- Изображения ---
        <<".jpg">> -> <<"image/jpeg">>;
        <<".jpeg">> -> <<"image/jpeg">>;
        <<".png">> -> <<"image/png">>;
        <<".gif">> -> <<"image/gif">>;
        <<".tiff">> -> <<"image/tiff">>;
       
        %% --- По умолчанию ---
        _ -> <<"application/octet-stream">>
    end.
