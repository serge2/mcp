-module(mcp_impl_rag).
-behaviour(emcp).

-export([schema/0]).
-export([start/0]).

start() ->
    AllowedApiKeys = application:get_env(mcp, api_keys, []),
    {ok, RagUrl} = application:get_env(mcp, rag_url),
    {ok, RagApiKey} = application:get_env(mcp, rag_api_key),
    emcp:start(ragmcp, mcp_impl_rag, {0,0,0,0}, 8085, "/mcp", false, AllowedApiKeys,
        #{rag_url      => unicode:characters_to_binary(RagUrl),
          rag_api_key  => RagApiKey
         }).


schema() ->
    #{
      name        => <<"MCP RAG Server">>,
      version     => <<"0.1.0">>,
      title       => <<"Advanced RAG Knowledge Base">>,
      instructions => <<"### RAG & KNOWLEDGE MANAGEMENT GUIDELINES:\n\n"
                        "1. **Proactive Retrieval (CRITICAL)**: You are NOT a closed system. "
                        "If a task involves specific project rules, technical guides, or unknown "
                        "operational procedures, you MUST use `search_chunks` BEFORE assuming "
                        "you know the answer. For complex goals, search RAG for similar past tasks "
                        "or architectural decisions to ensure consistency.\n\n"
                        "2. **Search & Context Strategy**: Use `search_chunks` for conceptual queries. "
                        "If a result is truncated or refers to other sections, you MUST use "
                        "`get_chunk_neighbors` to get the full context. Never rely on partial data.\n\n"
                        "3. **Strict Filtering Rule**: Use the `source_type` filter ONLY if you are "
                        "100% certain the target document has that attribute. If searching for "
                        "instructions, rules, or guides, DO NOT filter (especially by `web`) — "
                        "search across ALL sources instead.\n\n"
                        "4. **Source Type Definitions**:\n"
                        "   - `file`: Manuals, PDFs, and uploaded guides (Primary for instructions).\n"
                        "   - `project`: Local source code and technical assets.\n"
                        "   - `web`: External content previously crawled from the internet.\n"
                        "   - `LLM`: Saved summaries and strategic decisions from previous sessions.\n\n"
                        "5. **Memory Commitment**: After solving complex problems or making "
                        "strategic decisions, you MUST use `add_document` to save a summary "
                        "to the `LLM` source. This is vital for long-term session continuity.">>,
      tools       => tools_info(),
      resources   => resources_info()
     }.


tools_info() ->
    [
        #{ definition =>
             #{ name        => <<"search_chunks">>,
                description => <<"Performs a semantic vector search across the knowledge base. "
                                 "Use this to find relevant information by meaning, not just keywords. "
                                 "Higher 'limit' (e.g., 15-20) is better for complex technical tasks.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"text">>   => #{ type => string, description => <<"The search query in natural language.">> },
                        <<"max_distance">> => #{ type => number, minimum => 0.0, maximum => 2.0, default => 0.49,
                                                 description => <<"Cosine distance threshold. Lower (0.3-0.4) for strict matches, higher (0.5-0.6) for broad conceptual matches.">>},
                        <<"limit">>  => #{ type => integer, description => <<"Maximum chunks to return. Use higher values for better coverage.">>,
                                                default => 10 },
                        <<"doc_id">> => #{ type => integer, description => <<"Filter results to a specific document ID.">> },
                        <<"source">> => #{ type => string, 
                                                description => <<"Filter by content origin: "
                                                                 "'file' (general docs), "
                                                                 "'web' (online resources), "
                                                                 "'LLM' (previously stored assistant summaries/logic), "
                                                                 "'project' (source code).">>,
                                                enum => [<<"file">>, <<"web">>, <<"LLM">>, <<"project">>] },
                        <<"project_name">> => #{ type => string, description => <<"Search only within a specific project.">> }
                    },
                    required => [<<"text">>]
                },
                outputSchema => #{
                    type       => object,
                    properties => #{
                        <<"chunks">> => #{
                            type => array,
                            items => #{
                                type => object,
                                properties => #{
                                    <<"content">> => #{ type => string, description => <<"Text fragment content.">> },
                                    <<"content_type">> => #{ type => string, description => <<"MIME type.">> },
                                    <<"distance">> => #{ type => number, description => <<"Relevance score (lower is better).">> },
                                    <<"doc_id">> => #{ type => integer, description => <<"Parent document ID.">> },
                                    <<"filename">> => #{ type => string, description => <<"Source filename.">> },
                                    <<"id">> => #{ type => integer, description => <<"The unique identifier of this chunk. Use this value as 'chunk_id' when calling get_chunk_neighbors.">> },
                                    <<"idx">> => #{ type => integer, description => <<"Position index in document.">> },
                                    <<"source">> => #{ type => string, description => <<"Origin source.">> },
                                    <<"updated_at">> => #{ type => string, description => <<"Last update timestamp.">> },
                                    <<"url">> => #{ type => [string, <<"null">>], description => <<"Source URL if applicable.">> },
                                    <<"project_name">> => #{ type => [string, <<"null">>], description => <<"Associated project.">> },
                                    <<"doc_total_chunks">> => #{
                                        type => integer, 
                                        description => <<"Total chunks in this document. Compare with 'idx' to see how deep you are.">>}
                                }
                            },
                            description => <<"Array of relevant fragments.">>
                        }
                    }
                }
              },
            function => fun search_chunks/3
         },

        #{ definition =>
             #{ name        => <<"get_chunk_neighbors">>,
                description => <<"MANDATORY for code analysis. Retrieves chunks immediately preceding and following a specific chunk. "
                                 "Use this whenever a code block or text seems cut off to see the full implementation or logic.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"chunk_id">> => #{
                                type => integer,
                                description => <<"The ID of the chunk to expand context from.">> },
                            <<"max_succeeding_chunks">> => #{
                                type => integer,
                                description => <<"How many chunks to read AFTER the target chunk. Default is 1.">>,
                                default => 1 },
                            <<"max_preceding_chunks">> => #{
                                type => integer,
                                description => <<"How many chunks to read BEFORE the target chunk. Default is 1.">>,
                                default => 1 }
                    },
                    required => [<<"chunk_id">>]
                }
             },
           function    => fun get_chunk_neighbors/3
        },

        #{ definition =>
             #{ name        => <<"add_document">>,
                description => <<"Saves a new document to the RAG. Use this to 'remember' important summaries, "
                                 "API specifications, or architectural decisions made during the conversation. "
                                 "Format: Markdown. Always include a descriptive filename. Source is automatically set to 'LLM'.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"text">>      => #{ type => string, description => <<"The content to be stored. Use Markdown.">> },
                            <<"filename">>  => #{ type => string, description => <<"Descriptive name for the entry (e.g., 'auth-logic-summary.md').">>}
                    },
                    required => [<<"text">>, <<"filename">>]
                }
             },
           function    => fun add_document/3
        },

        #{ definition => 
             #{ name => <<"get_project_files_list">>,
                description => <<"Lists all files within a project. Use this as your FIRST STEP to understand "
                                 "what files are available for analysis. Provides doc_id for further content retrieval. "
                                 "MANDATORY: You must provide either 'project_id' or 'project_name'.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"project_id">> => #{ type => integer, description => <<"The numeric project ID.">> },
                            <<"project_name">> => #{ type => string, description => <<"The project name string.">> }
                    }
                }
             },
           function    => fun get_project_files_list/3
        },

        #{ definition =>
             #{ name        => <<"get_document_content">>,
                description => <<"Provides a structural 'sandwich' overview of a document: the very beginning and the very end. "
                                 "Perfect for checking file imports, class definitions at the top, or export logic at the bottom. "
                                 "Does not return the whole file to save context window.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"doc_id">> => #{
                                type => integer,
                                description => <<"The document ID to inspect.">>
                            },
                            
                            <<"first_chunks">> => #{ 
                                type => integer, 
                                description => <<"Number of chunks to read from the top (usually 3-5).">>, 
                                default => 3 
                            },
                            <<"last_chunks">> => #{ 
                                type => integer, 
                                description => <<"Number of chunks to read from the bottom (usually 2-3).">>, 
                                default => 2
                            }
                    },
                    required => [<<"doc_id">>]
                },
                outputSchema => #{
                    type => object,
                    properties => #{
                        <<"summary_chunks">> => #{ 
                            type => array, 
                            items => #{ type => object,
                                        properties => #{ <<"id">> => #{ type => integer },
                                                        <<"idx">> => #{ type => integer },
                                                        <<"content">> => #{ type => string } } }, 
                            description => <<"Ordered list of starting and ending chunks. Middle part is omitted.">> 
                        },
                        <<"message">> => #{ type => string, description => <<"Information about the omitted middle section.">> }
                    }
                }
           },
         function    => fun get_document_content/3
        }
    ].

resources_info() ->
    [
        % {uri => <<"resource://sys/datetime">>,
        %   name => <<"System date and time">>,
        %   description => <<"Current local time, UTC time and Time-zone">>,
        %   mimeType => <<"text/plain">>,
        %   function => fun resources_read/2
        %  }
    ].
    
%% Tool implementations

search_chunks(_Name, Args, #{rag_api_key := RagApiKey, rag_url := RagUrl}) ->
    Text = maps:get(<<"text">>, Args),
    MaxDistance = maps:get(<<"max_distance">>, Args, 0.49),
    Limit = maps:get(<<"limit">>, Args, 10),
    DocId = maps:get(<<"doc_id">>, Args, null),
    Source = maps:get(<<"source">>, Args, null),

    Request = {<<RagUrl/binary, "/search">>,
               [{"authorization", ["Bearer ", RagApiKey]}], 
               "application/json",
               jsx:encode(#{<<"content">> => Text,
                            <<"max_distance">> => MaxDistance,
                            <<"limit">> => Limit,
                            <<"doc_id">> => DocId,
                            <<"source">> => Source})},

    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            R = jsx:decode(RespBody),
            {structured_ok, R};
        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.


get_chunk_neighbors(_Name, Args, #{rag_api_key := RagApiKey, rag_url := RagUrl}) ->
    ChunkId = maps:get(<<"chunk_id">>, Args),
    Next = maps:get(<<"max_succeeding_chunks">>, Args, 1),
    Previous = maps:get(<<"max_preceding_chunks">>, Args, 1),

    Request = {<<RagUrl/binary, "/get_neighbors">>,
               [{"authorization", ["Bearer ", RagApiKey]}], 
               "application/json",
               jsx:encode(#{<<"chunk_id">> => ChunkId,
                            <<"next">> => Next,
                            <<"previous">> => Previous})},

    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            R = jsx:decode(RespBody),
            {structured_ok, R};
        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

add_document(_Name, Args, #{rag_api_key := RagApiKey, rag_url := RagUrl}) ->
    Text = maps:get(<<"text">>, Args),
    Filename = maps:get(<<"filename">>, Args, null),

    Request = {<<RagUrl/binary, "/add_document">>,
               [{"authorization", ["Bearer ", RagApiKey]}], 
               "application/json",
               jsx:encode(#{<<"source">> => <<"LLM">>,
                            <<"content">> => base64:encode(Text),
                            <<"filename">> => Filename
                           })},

    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            R = jsx:decode(RespBody),
            {structured_ok, R};
        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

get_project_files_list(_Name, Args, #{rag_api_key := RagApiKey, rag_url := RagUrl}) ->
    ProjectId = maps:get(<<"project_id">>, Args, undefined),   
    ProjectName = maps:get(<<"project_name">>, Args, undefined),   

    NArgs = case {ProjectId, ProjectName} of
        {undefined, undefined} -> error(<<"At least one of project_id or project_name must be provided">>);
        {_, undefined} -> #{<<"project_id">> => ProjectId};
        {undefined, _} -> #{<<"project_name">> => ProjectName}
    end,

    Request = {<<RagUrl/binary, "/get_project_files_list">>,
            [{"authorization", ["Bearer ", RagApiKey]}], 
            "application/json",
            jsx:encode(NArgs)},
            
    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            R = jsx:decode(RespBody),
            {structured_ok, R};
        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.

get_document_content(_Name, Args, #{rag_api_key := RagApiKey, rag_url := RagUrl}) ->
    DocId = maps:get(<<"doc_id">>, Args),
    FirstChunks = maps:get(<<"first_chunks">>, Args, 3),
    LastChunks = maps:get(<<"last_chunks">>, Args, 2),

    Request = {<<RagUrl/binary, "/get_document_content">>,
               [{"authorization", ["Bearer ", RagApiKey]}], 
               "application/json",
               jsx:encode(#{<<"doc_id">> => DocId,
                            <<"first_chunks">> => FirstChunks,
                            <<"last_chunks">> => LastChunks})},

    case httpc:request(post, Request, [], [{body_format, binary}]) of
        {ok, {{_HttpVersion, 200, _StatusString}, _RespHeaders, RespBody}} ->
            R = jsx:decode(RespBody),
            {structured_ok, R};
        {error, Reason} ->
            {error, unicode:characters_to_binary([ <<"Request failed: ">>, io_lib:format("~p", [Reason])])}
    end.
