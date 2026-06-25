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
      name => <<"Core Systems MCP Server">>,
      version => <<"0.1.0">>,
      title => <<"System & Browser Automation Server">>,
      instructions => <<"### SYSTEM & BROWSER AUTOMATION GUIDELINES:\n\n"
                        "1. **Persistent Sandboxed Shell (`exec`)**:\n"
                        "   - BEFORE running any CLI commands, you MUST create an environment session using `env_session_start`.\n"
                        "   - ALWAYS provide the received `session_id` to subsequent `exec` and `env_session_close` tools.\n"
                        "   - **User Privileges & Sudo Restrictions**: The sandbox runs under a **restricted, unprivileged user account**. Elevated privileges (`sudo`) are STRICTLY limited to `apt` and `apt-get` commands (e.g., `sudo apt-get update && sudo apt-get install -y package`). You CANNOT use `sudo` with any other commands. Do all your regular work as a non-root user.\n"
                        "   - **File Artifacts & Workspace (CRITICAL)**: Because of unprivileged access, all files, scripts, and generated artifacts MUST be created and stored strictly within the `/workspace` directory structure. Writing to system directories is forbidden. Files outside of `/workspace` will be destroyed when the session closes.\n"
                        "   - **File Operations**: Use heredocs (`cat << 'EOF' > file`) for file creation. For editing or modifying existing files, ALWAYS use either `patch` (unified diff via stdin) or `sed` to avoid rewriting entire files.\n"
                        "   - ALWAYS close your environment session using `env_session_close` when your task is complete.\n\n"
                        "2. **Web Browsing & Extraction (STRICT RULES)**:\n"
                        "   - **Eval Syntax (CRITICAL)**: In `http_session_eval`, DO NOT use `return` at the top level. "
                        "Simply write the expression (e.g., `document.documentElement.outerHTML.slice(0, 10000)`). "
                        "For complex logic, use IIFE: `(() => { const x = document.title; return x; })()`.\n"
                        "   - **Discovery Phase**: Use `document.documentElement.outerHTML` via `eval` to identify "
                        "page structure, links (href), and attributes that `innerText` hides.\n"
                        "   - **Wait for Load**: Always use `http_session_wait` for 'body' or a specific "
                        "element after navigation.\n"
                        "   - **Anti-Failure Strategy**: If `extract` returns empty results, DO NOT assume "
                        "protection. Assume your selectors are wrong. Re-verify with a fresh `outerHTML` slice.\n\n"
                        "3. **Large Content Handling (CRITICAL)**:\n"
                        "   - **Context Safety**: `outerHTML` is huge. DO NOT dump the entire content at once; "
                        "this will overflow the context window and cause goal loss.\n"
                        "   - **Iterative Strategy**: Process the page in chunks. Use JS `.slice()` via `eval` "
                        "to extract segments (e.g., 0-10000), analyze structure, save key data to a file, "
                        "then move to the next slice (10000-20000).\n"
                        "   - **State Management**: Keep track of processed segments and findings in a "
                        "local file or your reasoning to ensure full coverage without redundancy.\n\n"
                        "4. **Image & Vision**:\n"
                        "   - Only use `read_images` or screenshots if you have vision capabilities. "
                        "Otherwise, rely strictly on HTML/text dumps via `eval` and chunking.">>,
      tools => tools_info()
     }.



tools_info() ->
    [
        #{ definition =>
             #{ name        => <<"env_session_start">>,
                description => <<"Start a persistent, stateful sandbox environment session. Returns a session_id required for running CLI commands.">>,
                inputSchema => #{ type => object, properties => #{} }
             },
           function => fun env_session_start/3
        },

        #{ definition =>
             #{ name        => <<"env_session_close">>,
                description => <<"Close the active environment session and completely destroy its container. Call this when you finish your work.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The active environment session ID to destroy.">> }
                    },
                    required => [<<"session_id">>]
                }
             },
           function => fun env_session_close/3
        },

        #{ definition =>
             #{ name        => <<"exec">>,
                description => <<"Run a command in a restricted Ubuntu sandbox. Use for file operations, system tasks, or running scripts. Environment is non-interactive.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The active environment session ID.">> },
                        <<"command">> => #{ type => string, description => <<"The full Bash command to execute (e.g., 'ls -la', 'cat file.txt'). Support pipes and redirections.">> }
                    },
                    required => [<<"session_id">>, <<"command">>]
                }
             },
           function => fun exec/3
        },

        #{ definition =>
             #{ name        => <<"sys_datetime">>,
                description => <<"Get the current system local time, UTC time, and timezone information.">>,
                inputSchema => #{ type => object, properties => #{} }
             },
           function    => fun sys_datetime/3
        },

        #{ definition =>
             #{ name        => <<"http_call">>,
                description => <<"Make standard HTTP requests to fetch data or interact with APIs. Best for direct data retrieval.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"method">>  => #{ type => string, default => <<"GET">>, description => <<"HTTP method (GET, POST, PUT, DELETE, etc.)">> },
                        <<"url">>     => #{ type => string, description => <<"Fully qualified URL.">> },
                        <<"headers">> => #{ type => object, default => #{}, description => <<"HTTP request headers.">> },
                        <<"body">>    => #{ type => string, description => <<"Request payload for POST/PUT/PATCH.">> }
                    },
                    required => [<<"url">>]
                },
                outputSchema => #{
                    type       => object,
                    properties => #{
                        <<"http_version">> => #{ type => string,  description => <<"Response HTTP version">> },
                        <<"status_code">>  => #{ type => integer, description => <<"HTTP response status code">> },
                        <<"status_string">>=> #{ type => string,  description => <<"HTTP status message">> },
                        <<"headers">>      => #{ type => object,  description => <<"Response headers">> },
                        <<"body">>         => #{ type => string,  description => <<"Response body content">> }
                    },
                    required => [<<"http_version">>, <<"status_code">>, <<"status_string">>, <<"headers">>]
                }
             },
           function => fun http_call/3
        },

        #{ definition => 
             #{ name        => <<"http_call_f">>,
                description => <<"Make HTTP requests and save the response body directly to a file in the sandbox. Ideal for downloading large files or binaries.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"method">>  => #{ type => string, default => <<"GET">>, description => <<"HTTP method">> },
                        <<"url">>     => #{ type => string, description => <<"Target URL">> },
                        <<"headers">> => #{ type => object, default => #{}, description => <<"Request headers">> },
                        <<"body">>    => #{ type => string, description => <<"Request body">> },
                        <<"path">>    => #{ type => string, description => <<"Relative sandbox path where the body will be saved.">> }
                    },
                    required => [<<"url">>, <<"path">>]
                },
                outputSchema => #{
                    type       => object,
                    properties => #{
                        <<"http_version">> => #{ type => string,  description => <<"Response HTTP version">> },
                        <<"status_code">>  => #{ type => integer, description => <<"HTTP response status code">> },
                        <<"status_string">>=> #{ type => string,  description => <<"HTTP status message">> },
                        <<"headers">>      => #{ type => object,  description => <<"Response headers">> }
                    },
                    required => [<<"http_version">>, <<"status_code">>, <<"status_string">>, <<"headers">>]
                }
             },
           function => fun http_call_f/3
        },

        #{ definition =>
             #{ name        => <<"http_session_create">>,
                description => <<"Start a new headless browser session. Returns a session_id required for all other http_session tools.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                        <<"width">>        => #{ type => integer, description => <<"Viewport width in pixels">>, default => 1280 },
                        <<"height">>       => #{ type => integer, description => <<"Viewport height in pixels">>, default => 800 },
                        <<"mobile">>       => #{ type => boolean, description => <<"Emulate a mobile device view">>, default => false },
                        <<"locale">>       => #{ type => string,  description => <<"Browser locale setting">>, default => <<"en_US">> },
                        <<"idle_timeout">> => #{ type => integer, description => <<"Session auto-close timeout in seconds">>, default => 600 }
                    }
                }
             },
           function    => fun http_session_create/3
        },

        #{ definition =>
             #{ name        => <<"http_session_close">>,
                description => <<"Terminate a headless browser session and release its resources.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"The active session ID to close.">> }
                    },
                    required => [<<"session_id">>]
                }
             },
           function => fun http_session_close/3
         },

        #{ definition =>
             #{ name        => <<"http_session_goto">>,
                description => <<"Navigate the browser to a specific URL.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"Active session ID">> },
                        <<"url">>        => #{ type => string, description => <<"Target URL to load.">> }
                    },
                    required => [<<"session_id">>, <<"url">>]
                }
             },
           function => fun http_session_goto/3
         },

        #{ definition =>
             #{ name        => <<"http_session_wait">>,
                description => <<"Wait until a specific element matching the CSS selector is present on the page.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string,  description => <<"Active session ID">> },
                        <<"selector">>   => #{ type => string,  description => <<"CSS selector (e.g., 'div.result', '#login-btn')">> },
                        <<"timeout">>    => #{ type => integer, description => <<"Max wait time in milliseconds (default 30000)">>, default => 30000 }
                    },
                    required => [<<"session_id">>, <<"selector">>]
                }
             },
           function => fun http_session_wait/3
         },

        #{ definition =>
             #{ name        => <<"http_session_eval">>,
                description => <<"Execute JavaScript in the page context. Write the expression directly for simple values or use IIFE for logic. No 'return' at top level.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"Active session ID">> },
                        <<"script">>     => #{ type => string, description => <<"JS code to run.">> }
                    },
                    required => [<<"session_id">>, <<"script">>]
                }
             },
           function => fun http_session_eval/3
         },

        #{ definition =>
             #{ name        => <<"http_session_extract">>,
                description => <<"Extract text content (inner_text) from all elements matching the given CSS selector.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"Active session ID">> },
                        <<"selector">>   => #{ type => string, description => <<"CSS selector for elements to extract text from.">> }
                    },
                    required => [<<"session_id">>, <<"selector">>]
                }
             },
           function => fun http_session_extract/3
         },

       #{ definition =>
             #{ name        => <<"http_session_fill">>,
                description => <<"Enter text into an input field or form element.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"Active session ID">> },
                        <<"selector">>   => #{ type => string, description => <<"CSS selector for the target input.">> },
                        <<"value">>      => #{ type => string, description => <<"The text to be entered.">> }
                    },
                    required => [<<"session_id">>, <<"selector">>, <<"value">>]
                }
             },
           function => fun http_session_fill/3
         },


        #{ definition =>
             #{ name        => <<"http_session_screenshot">>,
                description => <<"Capture an image of the current page or a specific element. Saves to sandbox.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">> => #{ type => string, description => <<"Active session ID">> },
                        <<"selector">>   => #{ type => string, description => <<"Optional selector to capture only one element.">>},
                        <<"full_page">>  => #{ type => boolean, description => <<"Capture the whole scrollable page if true.">>},
                        <<"type">>       => #{ type => string, enum => [<<"png">>, <<"jpeg">>], description => <<"Format: png or jpeg">>},
                        <<"quality">>    => #{ type => integer, min => 1, max => 100, description => <<"Quality for jpeg (1-100)">>},
                        <<"path">>       => #{ type => string, description => <<"Sandbox file path to save the image (e.g., 'shot.png').">> }
                    },
                    required => [<<"session_id">>, <<"path">>]
                }
             },
           function => fun http_session_screenshot/3
         },

        #{ definition =>
             #{ name        => <<"http_session_click">>,
                description => <<"Click on a page element. Supports human-like mouse emulation.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"session_id">>     => #{ type => string, description => <<"Active session ID">> },
                        <<"selector">>       => #{ type => string, description => <<"CSS selector for the element to click.">>},
                        <<"human">>          => #{ type => boolean, description => <<"Emulate human behavior if true.">>, default => false},
                        <<"button">>         => #{ type => string, enum => [<<"left">>, <<"right">>], description => <<"Mouse button.">>, default => <<"left">>},
                        <<"click_count">>    => #{ type => integer, min => 1, max => 5, description => <<"Number of clicks.">>, default => 1},
                        <<"hover_before">>   => #{ type => boolean, description => <<"Perform hover before clicking.">>, default => true},
                        <<"move_duration_ms">> => #{ type => integer, description => <<"Duration of mouse move in ms.">> },
                        <<"move_steps">>     => #{ type => integer, description => <<"Steps in move animation.">> },
                        <<"pre_delay_ms">>   => #{ type => integer, description => <<"Delay before action.">> },
                        <<"post_delay_ms">>  => #{ type => integer, description => <<"Delay after action.">> },
                        <<"press_delay_ms">> => #{ type => integer, description => <<"Duration of click press.">> }
                    },
                    required => [<<"session_id">>, <<"selector">>]
                }
             },
           function => fun http_session_click/3
         },

        #{ definition =>
             #{ name => <<"read_images">>,
                description => <<"Load image files from the sandbox for processing. Use this when you need to 'see' an image you previously saved.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                        <<"paths">> => #{
                             type => array,
                             items => #{ type => string, description => <<"List of relative paths to image files.">> }
                        }
                    },
                    required => [<<"paths">>]
                }
             },
            function => fun read_images/3
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

%% Helper for processing headless browser API responses
process_response({ok, {{_, 200, _}, _, RespBody}}) ->
    {structured_ok, jsx:decode(RespBody)};
process_response({ok, {{_, Code, _}, _, RespBody}}) ->
    ErrorMsg = try 
        Data = jsx:decode(RespBody),
        maps:get(<<"error">>, Data, RespBody)
    catch _:_ -> 
        RespBody 
    end,
    {error, unicode:characters_to_binary(io_lib:format("Browser Error (Status ~p): ~ts", [Code, ErrorMsg]))};
process_response({error, Reason}) ->
    {error, unicode:characters_to_binary(io_lib:format("Request failed: ~p", [Reason]))}.

http_session_create(_Name, Args, _ExtraParams) ->
    ExtraArgs = maps:with([<<"width">>, <<"height">>, <<"mobile">>, <<"locale">>, <<"idle_timeout">>], Args),
    ReqBody = jsx:encode(ExtraArgs),
    Request = {<<"http://localhost:8000/session/create">>, [], "application/json", ReqBody},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

http_session_close(_Name, #{<<"session_id">> := Session} = _Args, _ExtraParams) ->
    Request = {<<"http://localhost:8000/session/", Session/binary, "/close">>, [], "application/json", <<>>},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

http_session_goto(_Name, #{<<"session_id">> := Session, <<"url">> := URL} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"goto">>,
                           <<"url">> => URL}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

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
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

http_session_eval(_Name, #{<<"session_id">> := Session, <<"script">> := Script} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"evaluate">>,
                           <<"script">> => Script}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

http_session_extract(_Name, #{<<"session_id">> := Session, <<"selector">> := Selector} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"extract">>,
                           <<"selector">> => Selector}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

http_session_fill(_Name, #{<<"session_id">> := Session, <<"selector">> := Selector, <<"value">> := Value} = _Args, _ExtraParams) ->
    ReqBody = jsx:encode(#{<<"action">> => <<"fill">>,
                           <<"selector">> => Selector,
                           <<"value">> => Value}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

http_session_screenshot(_Name, #{<<"session_id">> := Session} = Args, ExtraParams) ->
    ExtraArgs = maps:with([<<"selector">>, <<"full_page">>, <<"type">>, <<"quality">>], Args),
    ReqBody = jsx:encode(ExtraArgs#{<<"action">> => <<"screenshot">>}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, RespBody}} ->
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
        Other -> process_response(Other)
    end.

http_session_click(_Name, #{<<"session_id">> := Session} = Args, _ExtraParams) ->
    ExtraArgs = maps:with([<<"selector">>, <<"human">>, <<"button">>, <<"click_count">>,
         <<"hover_before">>, <<"move_duration_ms">>, <<"move_steps">>, <<"pre_delay_ms">>, 
         <<"post_delay_ms">>, <<"press_delay_ms">>], Args),
    ReqBody = jsx:encode(ExtraArgs#{<<"action">> => <<"click">>}),
    Request = {<<"http://localhost:8000/session/", Session/binary, "/run">>, [], "application/json", ReqBody},
    process_response(httpc:request(post, Request, [], [{body_format, binary}])).

env_session_start(_Name, _Args, ExtraParams) ->
    Root = maps:get(root_dir, ExtraParams),
    SessionId = integer_to_list(binary:decode_unsigned(crypto:strong_rand_bytes(12)), 36),
    SessionIdBin = list_to_binary(string:lowercase(SessionId)),
    case mcp_sandbox_docker:start_session(Root, SessionIdBin) of
        ok ->
            {structured_ok, #{<<"session_id">> => SessionIdBin, <<"status">> => <<"started">>}};
        {error, Reason} ->
            {error, unicode:characters_to_binary([<<"Failed to start env session: ">>, Reason])}
    end.

env_session_close(_Name, #{<<"session_id">> := SessionId}, _ExtraParams) ->
    case mcp_sandbox_docker:close_session(SessionId) of
        ok ->
            {structured_ok, #{<<"session_id">> => SessionId, <<"status">> => <<"destroyed">>}};
        {error, Reason} ->
            {error, unicode:characters_to_binary([<<"Failed to close env session: ">>, Reason])}
    end.

exec(_Name, #{<<"session_id">> := SessionId, <<"command">> :=Command}, _ExtraParams) ->
    case mcp_sandbox_docker:run_in_session(SessionId, Command) of
        {ok, Output, Code} ->
            logger:info("Exec command:~ts~nCode: ~p~nOutput:~n~ts~n", [Command, Code, Output]),
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => jsx:encode(#{output => Output, code => Code})}]};
        {error, Reason} ->
            {error, unicode:characters_to_binary([<<"Execution error: ">>, io_lib:format("~p", [Reason])])}
    end.


read_images(_Name, #{<<"paths">> := Paths}, ExtraParams) ->
    Root = maps:get(root_dir, ExtraParams),
    F = fun(_, {error, _} = E) ->
                E;
           (P, {ok, Acc}) ->
                case read_image_file(Root, P) of
                    {ok, Img} ->
                        {ok, [Img | Acc]};
                    {error, Reason} ->
                        {error, Reason}
                end
        end,
    case lists:foldl(F, {ok, []}, Paths) of
        {ok, GoodPathes} ->
            Res = [#{<<"type">> => <<"image">>, <<"data">> => ImgData, <<"mimeType">> => filename_to_mime(Abs)}
                || {Abs, ImgData} <- GoodPathes],
            {ok, Res};
        {error, Reason} ->
            {error, Reason}
    end.

read_image_file(Root, Path) ->
    case safe_path(Root, Path) of
        {ok, Abs} ->
            case file:read_file(Abs) of
                {ok, Data} ->
                    Encoded = base64:encode(Data),
                    {ok, {Abs, Encoded}};
                {error, Reason} ->
                    {error, unicode:characters_to_binary([ <<"File read error: ">>, io_lib:format("~p", [Reason])])}
            end;
        {error, _} ->
            {error, <<"outside_root">>}
    end.


%%--------------------------------------------------------------------
%% @doc
%%   Проверяет, что пользовательский путь находится внутри заданного корня.
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
        <<".svg">> -> <<"image/svg+xml">>;
       
        %% --- По умолчанию ---
        _ -> <<"application/octet-stream">>
    end.
