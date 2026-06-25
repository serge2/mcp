-module(mcp_sandbox_docker).
-export([start_session/2, run_in_session/2, close_session/1]).

-define(DOCKER_BIN, "/usr/bin/docker").
-define(WORKSPACE, "workspace").

%% -----------------------------
%% START LONG-RUNNING SESSION
%% -----------------------------
-spec start_session(Root::string(), SessionId::binary()) -> ok | {error, binary()}.
start_session(Root, SessionId) ->
    HostWorkspace = filename:join(Root, ?WORKSPACE),
    ok = filelib:ensure_path(HostWorkspace),
    ContainerName = container_name(SessionId),

    %% Fetch real host UID and GID for user mapping inside the container
    {HostUid, HostGid} = get_host_ids(),

    DockerArgs = [
        "run", "-d",
        "--name", ContainerName,

        %% Host network is used for easy local development (e.g., accessing local tools/services).
        %% WARNING: In production or untrusted environments, change this to an isolated 
        %% bridge network (e.g., "mcp_isolated_net") to prevent SSRF vulnerabilities.
        "--network", "host",

        %% For agressive zombie cleanup
        "--init",

        %% Linux capabilities hardening for Sandbox
        "--cap-drop=ALL",                  %% Drop all default kernel capabilities
        "--cap-add=CHOWN",                 %% Required for apt to change file ownership during install
        "--cap-add=DAC_OVERRIDE",          %% Required for apt to bypass file permission checks
        "--cap-add=SETUID",                %% Required for gosu to switch from root to sandbox user
        "--cap-add=SETGID",                %% Required for gosu to switch group context

        %% Resource constraints to prevent DoS/Fork-bombs
        "--memory", "512m",
        "--memory-swap", "512m",
        "--cpus", "1.0",
        "--pids-limit", "100",

        "-v", HostWorkspace ++ ":/workspace",
        "-w", "/workspace",
        "mcp-sandbox-env",
        "tail", "-f", "/dev/null" %% Keeps the container running in the background
    ],

    Port = open_port({spawn_executable, ?DOCKER_BIN},
                     [exit_status, use_stdio, stderr_to_stdout, binary, {args, DockerArgs}]),
    case collect_output(Port, []) of
        {ok, _ContainerId, 0} ->
            %% CONTEXT PROVISIONING: Setup the host-mapped user right after container starts
            SetupCmd = lists:flatten(io_lib:format(
                "getent passwd ~s >/dev/null && userdel -r $(getent passwd ~s | cut -d: -f1) 2>/dev/null; "
                "groupadd -g ~s mcp_group && "
                "useradd -m -u ~s -g ~s -s /bin/bash mcp_user && "
                "echo 'mcp_user ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get' >> /etc/sudoers && "
                "chown -R mcp_user:mcp_group /workspace",
                [HostUid, HostUid, HostGid, HostUid, HostGid]
            )),
            
            SetupArgs = ["exec", ContainerName, "bash", "-c", SetupCmd],
            SetupPort = open_port({spawn_executable, ?DOCKER_BIN},
                                  [exit_status, use_stdio, stderr_to_stdout, binary, {args, SetupArgs}]),
            case collect_output(SetupPort, []) of
                {ok, _, 0} -> ok;
                {ok, SetupErr, _} -> {error, <<"Setup failed: ">>, SetupErr}
            end;
        {ok, Error, _Code} -> {error, Error}
    end.

%% -----------------------------
%% EXECUTE COMMAND INSIDE ACTIVE SESSION
%% -----------------------------
-spec run_in_session(SessionId::binary(), Cmd::binary()) -> {ok, Output::binary()} | {error, binary()}.
run_in_session(SessionId, Cmd) ->
    ContainerName = container_name(SessionId),
    
    
    %% Use docker exec to execute a command inside the existing container
    DockerArgs = [
        "exec",
        "-i",
        "--user", "mcp_user", %% Run as the sandbox user to avoid root privileges
        "-w", "/workspace",
        ContainerName,
        "bash", "-c", unicode:characters_to_list(Cmd)
    ],

    Port = open_port({spawn_executable, ?DOCKER_BIN},
                     [exit_status, use_stdio, stderr_to_stdout, binary, {args, DockerArgs}]),
    collect_output(Port, []).

%% -----------------------------
%% CLOSE SESSION AND REMOVE CONTAINER
%% -----------------------------
-spec close_session(SessionId::binary()) -> ok | {error, binary()}.
close_session(SessionId) ->
    ContainerName = container_name(SessionId),
    %% rm -f forcefully stops and removes the container
    DockerArgs = ["rm", "-f", ContainerName],
    
    Port = open_port({spawn_executable, ?DOCKER_BIN},
                     [exit_status, use_stdio, stderr_to_stdout, binary, {args, DockerArgs}]),
    case collect_output(Port, []) of
        {ok, _, 0} -> ok;
        {ok, Error, _Code} -> {error, Error}
    end.

%% -----------------------------
%% HELPER FUNCTIONS
%% -----------------------------

-spec container_name(SessionId::binary()) -> ContainerName::string().
container_name(SessionId) ->
    "mcp-sandbox-" ++ binary_to_list(SessionId).

-spec collect_output(Port::port(), Acc::[binary()]) -> {ok, Output::binary(), ExitCode::integer()}.
collect_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_output(Port, [Data | Acc]);
        {Port, {exit_status, Code}} ->
            {ok, string:trim(binary:list_to_bin(lists:reverse(Acc))), Code}
    end.

%% @doc Gets the current host user's UID and GID to prevent file permission issues
%% inside the mounted workspace.
-spec get_host_ids() -> {Uid::string(), Gid::string()}.
get_host_ids() ->
    Uid = string:trim(os:cmd("id -u")),
    Gid = string:trim(os:cmd("id -g")),
    {Uid, Gid}.
