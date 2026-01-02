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
      description => <<"MCP server with RAG (Retrieval-Augmented Generation) tools implemented."
                       " The main purpose of the RAG server is storing some documents (guides, books, code)."
                       " LLM can use the documents to analyze or as source of information."
                       " Also LLM can use the RAG as a long-term storage for generated information that"
                       " will be useful in future">>,
      tools       => tools_info(),
      resources   => resources_info()
     }.


tools_info() ->
    [
        #{ definition =>
             #{ name        => <<"search_chunks">>,
                description => <<"Search text chunks in the RAG. The API searches for chunks"
                                    " matching the provided text. Optional filters include"
                                    " document ID and source type (file, web, LLM, project)."
                                    " Returns a list of relevant text chunks. It's possible to increase"
                                    " the number of returned chunks by setting the limit parameter.">>,
                inputSchema => #{
                    type       => object,
                    properties => #{
                        <<"text">>   => #{ type => string, description => <<"The text to search for.">> },
                        <<"limit">>  => #{ type => integer, description => <<"The maximum number of chunks in the response.">>,
                                                default => 10 },
                        <<"doc_id">> => #{ type => integer, description => <<"Optional document ID to filter chunks.">> },
                        <<"source">> => #{ type => string, description => <<"Optional source to filter chunks.">>,
                                                enum => [<<"file">>, <<"web">>, <<"LLM">>, <<"project">>] },
                        <<"project_name">> => #{ type => string, description => <<"Optional project name to filter chunks.">> }
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
                                    <<"content">> => #{ type => string, description => <<"The text content of the chunk.">> },
                                    <<"content_type">> => #{ type => string, description => <<"The MIME type of the content.">> },
                                    <<"distance">> => #{ type => number, description => <<"The distance metric indicating relevance.">> },
                                    <<"doc_id">> => #{ type => integer, description => <<"The ID of the document the chunk belongs to.">> },
                                    <<"filename">> => #{ type => string, description => <<"The filename from which the chunk was extracted.">> },
                                    <<"id">> => #{ type => integer, description => <<"The unique ID of the chunk.">> },
                                    <<"idx">> => #{ type => integer, description => <<"The index of the chunk within the document.">> },
                                    <<"source">> => #{ type => string, description => <<"The source of the chunk (e.g., file, web, LLM).">> },
                                    <<"updated_at">> => #{ type => string, description => <<"The timestamp when the chunk was last updated.">> },
                                    <<"url">> => #{ type => [string, null], description => <<"The URL associated with the chunk, if any.">> },
                                    <<"project_name">> => #{ type => [string, null], description => <<"The name of the project the chunk is associated with.">> },
                                    <<"doc_total_chunks">> => #{
                                        type => integer, 
                                        description => <<"Total number of chunks in the document corresponding to the retrieved chunks. (Useful for range calculations).">>}
                                }
                            },
                            description => <<"List of matching text chunks with their details.">>
                        }
                    }
                }
              },
            function => fun search_chunks/3
         },

        #{ definition =>
             #{ name        => <<"get_chunk_neighbors">>,
                description => <<"Retrieves a specified chunk and an optional number of adjacent chunks (neighbors) before and after it.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"chunk_id">> => #{
                                type => integer,
                                description => <<"The **ID** of the **central chunk** to retrieve and find neighbors for.">> },
                            <<"max_succeeding_chunks">> => #{
                                type => integer,
                                description => <<"The maximum **non-negative count** of chunks immediately **following** the central chunk to include.">>,
                                default => 1 },
                            <<"max_preceding_chunks">> => #{
                                type => integer,
                                description => <<"The maximum **non-negative count** of chunks immediately **preceding** the central chunk to include.">>,
                                default => 1 }
                    },
                    required => [<<"chunk_id">>]
                }
             },
           function    => fun get_chunk_neighbors/3
        },

        #{ definition =>
             #{ name        => <<"add_document">>,
                description => <<"Store a text document to the RAG. The document will be chunked"
                                    " and indexed for future retrieval. The source of the document"
                                    " will be \"LLM\". The markdown format is preferred for better chunking."
                                    " It's recommended to add to the document some metadata: Date/time of"
                                    " creation, document name or short description.">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"text">>      => #{ type => string, description => <<"The content of the document">> },
                            <<"filename">>  => #{ type => string, description => <<"The optional filename of the document">>}
                    },
                    required => [<<"text">>, <<"filename">>]
                }
             },
           function    => fun add_document/3
        },

        #{ definition => 
             #{ name => <<"get_project_files_list">>,
                description => <<"Get the list of files associated with a specific project."
                                    " A project_id or project_name should be provided. If not - all documents"
                                    " that not related to any document will be returned">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"project_id">> => #{ type => integer, description => <<"The ID of the project to retrieve files for.">> },
                            <<"project_name">> => #{ type => string, description => <<"The name of the project to retrieve files for.">> }
                    }
                }
             },
           function    => fun get_project_files_list/3
        },

        #{ definition =>
             #{ name        => <<"get_document_content">>,
                description => <<"Retrieves a structural summary of the document, returned as a list of selected chunks. "
                                    "This method avoids full document reconstruction and is designed to provide "
                                    "essential structural context (imports, headers, footer functions) within the size limit. "
                                    "The result includes the N first and M last chunks, which may contain overlap (ignored by LLM).">>,
                inputSchema => #{
                    type => object,
                    properties => #{
                            <<"doc_id">> => #{
                                type => integer,
                                description => <<"The ID of the document to retrieve.">>
                            },
                            
                            <<"first_chunks">> => #{ 
                                type => integer, 
                                description => <<"The number of chunks to retrieve from the beginning of the document (N).">>, 
                                default => 3 
                            },
                            <<"last_chunks">> => #{ 
                                type => integer, 
                                description => <<"The number of chunks to retrieve from the end of the document (M).">>, 
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
                            description => <<"List of N starting chunks and M ending chunks, ordered by index. Overlap must be ignored by the LLM.">> 
                        },
                        <<"message">> => #{ type => string, description => <<"A status message indicating how many chunks were skipped in the middle.">> }
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
    Limit = maps:get(<<"limit">>, Args, 10),
    DocId = maps:get(<<"doc_id">>, Args, null),
    Source = maps:get(<<"source">>, Args, null),

    Request = {<<RagUrl/binary, "/search">>,
               [{"authorization", ["Bearer ", RagApiKey]}], 
               "application/json",
               jsx:encode(#{<<"content">> => Text,
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
