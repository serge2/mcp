# Core Systems MCP Server

An example of a Model Context Protocol (MCP) server implemented in Erlang using the `emcp` framework. This server provides advanced System Automation, Stateful Sandboxed CLI Environments, and Headless Browser Automation capabilities tailored for LLM agents.

> ⚠️ **DISCLAIMER: EXPERIMENTAL PURPOSES ONLY**
> This server is designed for research, prototyping, and rapid AI orchestration experimentation. Out of the box, it lacks the multi-tenant isolation, aggressive resource quotas, and absolute container hardening required for a secure production infrastructure. See the [Production Hardening Requirements](#production-hardening-requirements) section below.

---

## Key Implementation & Architecture Nuances

Before deploying this server or passing it to LLM agents, it is critical to understand its unique design choices, resource patterns, and security constraints:

### 1. Stateful CLI Environments (vs. Ephemeral Sandboxes)
Unlike conventional tools that spin up a fresh, short-lived container or shell for every single instruction, this server introduces the concept of **Persistent Environment Sessions** via the `env_session_start` and `env_session_close` tools.
* **State Retention:** Modifications to the system environment, background processes, environment variables, and installed packages (e.g., `sudo apt-get install -y nmap`) remain active and fully persistent across multiple execution turns within the same `session_id`.
* **Resource Warning:** Every active session keeps a dedicated, background-managed Docker container running on the host. If an LLM agent fails to trigger `env_session_close`, or encounters an unhandled runtime exception, containers will persist indefinitely, causing potential host CPU and memory leakage.

### 2. Sandbox Security & Unprivileged Execution Limits
The system boundaries are explicitly restricted to protect the host infrastructure from malicious or runaway LLM-generated operations:
* **Non-Root Execution:** The shell inside the container executes from the context of a restricted, unprivileged user account.
* **Strict Sudo Whitelisting:** Elevated privileges (`sudo`) are limited *exclusively* to package management binaries (`apt` and `apt-get`). Attempting to prefix any other command with `sudo` (e.g., `sudo chown`, `sudo python3`) will throw an immediate access violation error.
* **Directory Isolation (`/workspace`):** Due to unprivileged access, all file generation, code compilation, and script creation tasks MUST be restricted to the `/workspace` directory structure. Writing to other system paths is forbidden and fails inherently via DAC file permissions.
* **File Operations Strategy:** The LLM agent is instructed to use heredocs (`cat << 'EOF' > file`) exclusively for file creation, and `patch` or `sed` for file edits to avoid costly text rewrites.

### 3. External RAG Service Dependency
* Features and upcoming API scopes related to Retrieval-Augmented Generation (RAG) are **not** bundled natively within this core server.
* To leverage semantic knowledge extraction and vectors, you must run the companion **[RAG Service](https://github.com/serge2/rag)** microservice, which is maintained in a completely separate Git repository. The MCP server delegates embedding management and contextual lookups to that service over local service fabrics.

### 4. Browser & Large Content Constraints
* **JSON-RPC Bridge:** The headless browser engine uses an external bridge running on port `8000`. Stalled page elements or network delays can bottleneck individual tool execution steps.
* **Context Window Overflow Protections:** Because modern websites generate massive raw HTML trees, the system relies heavily on chunked data transfers. Web extraction tools use native JavaScript slicing techniques to force the model to ingest data iteratively rather than blowing past model context limits.

---

## Production Hardening Requirements

To safely bridge the gap between this experimental codebase and a hardened production topology, you must implement the following architectural boundaries:

1. **Deterministic Session Pruning:** Write an external host daemon or cron utility that constantly monitors and forcibly prunes (`docker rm -f`) inactive `mcp-sandbox-*` containers after a pre-defined idle timeout window.
2. **Hypervisor-Level Virtualization:** Replace standard shared-kernel Docker engines with microVM runtimes like **gVisor**, **Kata Containers**, or **AWS Firecracker** to mitigate the risk of container breakout vectors.
3. **Egress Traffic Restrictions:** Place the sandboxes behind a restrictive egress proxy or VPC firewall to prevent AI agents from calling corporate internal metadata endpoints, private databases, or unexpected internet relays.

---

## Getting Started

### Prerequisites
* Erlang/OTP 26 or higher
* **[emcp Framework](https://github.com/serge2/emcp)** (The core engine powering this server's MCP implementation)
* **[The RAG service](https://github.com/serge2/rag)** 
* Rebar3 build tool
* A local Docker daemon configured to allow the host network layer

### Building and Compilation
Compile the application, source modules, and external dependencies using Rebar3:
```bash
rebar3 compile
```

### Configuration
Configure your primary application parameters using your `sys.config` file based on the template below:

```erlang
{mcp, [
   {root_dir, "/var/mcp_sandbox_root"}, 
   {listen_ip, "0.0.0.0"},
   {listen_port, 8080},
   {api_keys, [
     <<"SecretAPIKey">>                     %% !!! Set your own API-keys
   ]},
   {rag_api_key, "RAGServiceAPIKey"},
   {rag_url, "https://localhost:8081/api"}
]}.
```

### Running the Server
Build the docker images:
```bash
$ ./build_docker.sh
```

Build the code:
```bash
$ compile.sh
```

Boot the server application node directly inside the Erlang shell interface:
```bash
$ ./start_all.sh
```
The server will boot and begin listening for incoming Server-Sent Events (SSE) / HTTP orchestration calls at `http://0.0.0.0:8080/mcp`.
