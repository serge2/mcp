-module(mcp_sandbox).
-export([init_fs/1, run/3]).

-define(WORKSPACE, "workspace").
-define(TMP, "tmp").

%% -----------------------------
%% ИНИЦИАЛИЗАЦИЯ ПЕСОЧНИЦЫ
%% -----------------------------
init_fs(Chroot) ->
    ensure_dir(Chroot, ""),
    ensure_dir(Chroot, ?WORKSPACE),
    ensure_dir(Chroot, ?TMP),
    io:format("✅ MCP sandbox ready at ~s~n", [Chroot]),
    ok.

%% -----------------------------
%% ВЫПОЛНЕНИЕ КОМАНД ЧЕРЕЗ TMP-ФАЙЛ ВНУТРИ ПЕСОЧНИЦЫ
%% -----------------------------
run(Root, ChDir, Cmd) ->
    %% создаём временный скрипт внутри песочницы
    TmpDir = filename:join(Root, ?TMP),
    ok = filelib:ensure_path(TmpDir),
    Rand = integer_to_list(binary:decode_unsigned(crypto:strong_rand_bytes(8)), 36),
    TmpFileName = filename:join(TmpDir, Rand),
    logger:info("MCP sandbox: writing temp script ~p", [TmpFileName]),
    logger:info("MCP sandbox: command to run: ~s", [Cmd]),
    ok = file:write_file(TmpFileName, ["#!/bin/bash\nset -e\n", Cmd, "\n"]),
    _ = os:cmd("chmod 700 " ++ TmpFileName),

    %% вычисляем путь внутри песочницы
    TmpPathInside = filename:join(["/", ?TMP, Rand]),

    %% собираем bubblewrap команду
    BwrapCmd = [
        "bwrap",
        "--bind", unicode:characters_to_list(Root), "/",
        "--dev-bind", "/dev", "/dev",
        "--proc", "/proc",
        "--ro-bind", "/usr", "/usr",
        "--ro-bind", "/bin", "/bin",
        "--ro-bind", "/lib", "/lib",
        "--ro-bind", "/lib64", "/lib64",
        "--ro-bind", "/home/serge/bin", "/home/user/bin",
        "--bind", unicode:characters_to_list(filename:join(Root, ?WORKSPACE)), "/workspace",
        "--bind", unicode:characters_to_list(filename:join(Root, ?TMP)), "/tmp",
        "--unshare-all",
        "--die-with-parent",
        "--chdir",  unicode:characters_to_list(ChDir),
        "--setenv", "PATH", "/usr/bin:/bin:/home/user/bin",
        "bash", TmpPathInside
    ],

    %% теперь просто напрямую вызываем bubblewrap без кавычек и без bash -c
    Port = open_port({spawn, unicode:characters_to_list(string:join(BwrapCmd, " "))},
                     [exit_status, use_stdio, stderr_to_stdout, binary]),

    Result = collect_output(Port, []),

    %% удаляем временный файл после выполнения
    file:delete(TmpFileName),

    Result.

%% -----------------------------
%% ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
%% -----------------------------
collect_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_output(Port, [Data | Acc]);
        {Port, {exit_status, Code}} ->
            {ok, binary:list_to_bin(lists:reverse(Acc)), Code}
    end.

ensure_dir(Chroot, Dir) ->
    filelib:ensure_path(filename:join(Chroot, Dir)).
