-module(mcp_sandbox_docker).
-export([start_session/2, run_in_session/4, close_session/1]).

-define(DOCKER_BIN, "/usr/bin/docker").
-define(WORKSPACE, "workspace").

%% -----------------------------
%% ЗАПУСК ДОЛГОЖИВУЩЕЙ СЕССИИ
%% -----------------------------
start_session(Root, SessionId) ->
    HostWorkspace = filename:join(Root, ?WORKSPACE),
    ok = filelib:ensure_path(HostWorkspace),
    ContainerName = container_name(SessionId),

    %% Запускаем контейнер в фоне (-d), который держит bash открытым
    DockerArgs = [
        "run", "-d",
        "--name", ContainerName,
        "--network", "host",
        "-v", HostWorkspace ++ ":/workspace",
        "-w", "/workspace",
        "mcp-sandbox-env",
        "tail", "-f", "/dev/null" %% Держит контейнер запущенным
    ],
    
    Port = open_port({spawn_executable, ?DOCKER_BIN},
                     [exit_status, use_stdio, stderr_to_stdout, binary, {args, DockerArgs}]),
    case collect_output(Port, []) of
        {ok, _ContainerId, 0} -> ok;
        {ok, Error, _Code} -> {error, Error}
    end.

%% -----------------------------
%% ВЫПОЛНЕНИЕ КОМАНДЫ ВНУТРИ ЖИВОЙ СЕССИИ
%% -----------------------------
run_in_session(SessionId, ChDir, Cmd, _Root) ->
    ContainerName = container_name(SessionId),
    
    %% Используем docker exec для выполнения команды в существующем контейнере
    DockerArgs = [
        "exec",
        "-i",
        "-w", unicode:characters_to_list(ChDir),
        ContainerName,
        "bash", "-c", unicode:characters_to_list(Cmd)
    ],

    Port = open_port({spawn_executable, ?DOCKER_BIN},
                     [exit_status, use_stdio, stderr_to_stdout, binary, {args, DockerArgs}]),
    collect_output(Port, []).

%% -----------------------------
%% ЗАКРЫТИЕ СЕССИИ И УДАЛЕНИЕ КОНТЕЙНЕРА
%% -----------------------------
close_session(SessionId) ->
    ContainerName = container_name(SessionId),
    %% rm -f принудительно останавливает и удаляет контейнер
    DockerArgs = ["rm", "-f", ContainerName],
    
    Port = open_port({spawn_executable, ?DOCKER_BIN},
                     [exit_status, use_stdio, stderr_to_stdout, binary, {args, DockerArgs}]),
    case collect_output(Port, []) of
        {ok, _, 0} -> ok;
        {ok, Error, _Code} -> {error, Error}
    end.

%% -----------------------------
%% ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
%% -----------------------------
container_name(SessionId) ->
    "mcp-sandbox-" ++ binary_to_list(SessionId).

collect_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_output(Port, [Data | Acc]);
        {Port, {exit_status, Code}} ->
            {ok, string:trim(binary:list_to_bin(lists:reverse(Acc))), Code}
    end.
