#!/usr/bin/env python3
import json
import os
import socket

path = os.environ["HERDR_SOCKET_PATH"]
ready = "/tmp/herdr-fake-socket-ready"
try:
    os.unlink(path)
except FileNotFoundError:
    pass
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
os.chmod(path, 0o600)
server.listen()
open(ready, "w").close()
while True:
    client, _ = server.accept()
    with client:
        request = json.loads(client.makefile().readline())
        if request.get("method") != "pane.split":
            response = {"id": request.get("id", ""), "error": {"code": "unknown_method"}}
        else:
            params = request["params"]
            open("/tmp/herdr-agent-pane", "w").close()
            names = " ".join(f"--env {name}" for name in sorted(params.get("env", {})))
            with open("/tmp/herdr-commands.log", "a") as log:
                log.write(
                    f"pane split {params['target_pane_id']} --direction {params['direction']} "
                    f"--ratio {params['ratio']} --cwd {params['cwd']} --no-focus {names}\n"
                )
            response = {
                "id": request.get("id", ""),
                "result": {
                    "pane": {
                        "pane_id": "agent-pane",
                        "terminal_id": "agent-terminal",
                        "tab_id": "tab-1",
                        "workspace_id": "ws-1",
                    }
                },
            }
        client.sendall((json.dumps(response) + "\n").encode())
