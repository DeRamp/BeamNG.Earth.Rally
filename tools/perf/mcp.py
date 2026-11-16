"""A small retrying client for the MCP server BeamNG.drive runs (port 29292). Used only to load the bench and start a
suite: nothing is polled over it while a suite measures (docs/perf-plan-1.6.1.md)."""
import json
import sys
import time
import urllib.request

URL = "http://127.0.0.1:29292/mcp"


def rpc(method, params, timeout=60, tries=3):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(URL, body, {"Content-Type": "application/json",
                                                     "Accept": "application/json, text/event-stream"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                d = json.loads(r.read().decode("utf-8", "replace"), strict=False)
            if "error" in d:
                raise SystemExit(f"MCP error: {d['error']}")
            return d["result"]
        except (OSError, TimeoutError) as e:
            last = e
            time.sleep(2 + 2 * i)
    raise SystemExit(f"MCP: no answer after {tries} tries ({last}). Is the game running with its MCP server on?")


def lua(code, timeout=60):
    res = rpc("tools/call", {"name": "run_lua", "arguments": {"code": code}}, timeout=timeout)
    text = "\n".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
    if res.get("isError"):
        raise SystemExit("Lua error in game: " + text)
    return text


if __name__ == "__main__":
    print(lua(sys.argv[1]))
