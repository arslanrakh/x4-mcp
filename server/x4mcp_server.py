#!/usr/bin/env python3
"""
MCP server for X4: Foundations.

Exposes one code-execution tool rather than a tool per game concept, and the
game side exposes exactly one operation behind it. Nothing here wraps a game
feature: X4's own API is already fully reachable from Lua, so a wrapper could
only ever offer a subset chosen by whoever wrote it.

The price of that choice is discoverability -- with one tool there is no schema
for the model to read. It is paid back in the tool description, which carries
the full reference, and by x4.help() returning the same text on demand.

Usage:
    x4mcp_server.py                      # stdio, for Claude Desktop / Code
    x4mcp_server.py --transport http     # streamable HTTP on 127.0.0.1:8766
    x4mcp_server.py --game-port 8765     # port the game dials into
"""

from __future__ import annotations

import argparse
import ast
import io
import os
import sys
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from bridge import GameBridge, GameNotConnected  # noqa: E402
from mcp.server.mcpserver import MCPServer  # noqa: E402
from x4api import API_REFERENCE, X4  # noqa: E402

MAX_OUTPUT = 60_000     # characters returned to the model


class CodeSession:
    """A persistent Python namespace, in the spirit of a notebook cell.

    Kept across calls on purpose: a plan computed in one call has to be usable
    in the next without recomputing it, which is what makes the two-step
    "look, ask the player, then act" flow possible at all.
    """

    def __init__(self, x4: X4):
        self.ns: dict = {"x4": x4}
        self.calls = 0

    def _banner(self) -> str:
        """Stamp every result with where it came from.

        Without it neither the agent nor the player can tell a real reading of
        the running game from something the model produced on its own, and an
        answer about someone's save is worthless if its provenance is unclear.
        Also surfaces staleness, which is the other thing that quietly makes an
        answer wrong.
        """
        x4 = self.ns["x4"]
        try:
            st = x4.status()
        except Exception:
            return "[X4 MCP | live game | link status unknown]"

        if not st.get("connected"):
            state = "NOT CONNECTED - the game is not running or the extension is not loaded"
        elif not st.get("savegame_loaded"):
            state = "connected, no savegame loaded (main menu)"
        elif not st.get("ticking"):
            state = "connected but NOT TICKING - the game window is in the background"
        else:
            state = "connected, savegame loaded"

        age = st.get("snapshot_age_seconds")
        freshness = "no snapshot yet" if age is None else f"snapshot {age}s old"
        if st.get("paused"):
            freshness += ", game paused"
        return f"[X4 MCP | live game | {state} | {freshness}]"

    def run(self, code: str) -> str:
        self.calls += 1
        out = io.StringIO()

        try:
            tree = ast.parse(code, mode="exec")
        except SyntaxError:
            return "SyntaxError:\n" + traceback.format_exc(limit=0)

        # Trailing expression is evaluated separately so its value shows up
        # without the model having to wrap everything in print().
        tail = None
        last = tree.body[-1] if tree.body else None
        if isinstance(last, ast.Expr):
            tree.body.pop()
            tail = ast.Expression(last.value)

        try:
            with redirect_stdout(out), redirect_stderr(out):
                if tree.body:
                    exec(compile(tree, "<x4_exec>", "exec"), self.ns)
                if tail is not None:
                    value = eval(compile(tail, "<x4_exec>", "eval"), self.ns)
                    if value is not None:
                        print(repr(value), file=out)
        except GameNotConnected as e:
            out.write(f"\nGameNotConnected: {e}\n")
        except Exception:
            out.write("\n" + traceback.format_exc())

        body = out.getvalue() or "(no output)"
        text = self._banner() + "\n" + body
        if len(text) > MAX_OUTPUT:
            head = text[: MAX_OUTPUT // 2]
            tail_text = text[-MAX_OUTPUT // 2:]
            text = (f"{head}\n\n... [{len(text) - MAX_OUTPUT} characters trimmed; "
                    f"filter or aggregate in code instead of printing everything] ...\n\n"
                    f"{tail_text}")
        return text


def prepare_artifacts(game_dir: str | None, language: str) -> dict:
    """Rebuild the game-derived data from the local installation.

    Done at every start rather than shipped in the repository: it takes under a
    second and guarantees the ship catalogue and API index match the player's
    own version, DLC and mods instead of whatever the author happened to have.
    """
    from gamefiles import ensure_artifacts, find_game_dir

    game = find_game_dir(game_dir)
    cache = Path(__file__).resolve().parent / "generated"
    info = ensure_artifacts(game, cache, language)
    return info


def build_server(game_port: int, artifacts: dict | None = None) -> MCPServer:
    bridge = GameBridge(port=game_port)
    x4 = X4(bridge, game_dir=(artifacts or {}).get("game_dir"))
    session = CodeSession(x4)
    artifacts = artifacts or {}

    server = MCPServer(
        name="x4",
        title="X4: Foundations — read and control the game",
        instructions=(
            "Live connection to the player's running X4: Foundations game. "
            "You can both read it and CONTROL it: inspect ships, stations and "
            "fleets, and give orders -- dock, move, attack, mine, trade, "
            "escort, reorganise fleets. When the player asks for something to "
            "happen in X4, do it with these tools instead of explaining which "
            "buttons to click. Work through x4_exec, writing Lua with "
            "x4.lua(...); use "
            "x4_status if something looks wrong. Never match ships or sectors "
            "by displayed names -- the game may run in any language."
        ),
    )

    @server.tool(
        name="x4_exec",
        title="Read and control X4: run Python against the live game",
        description=(
            "Read from and write to a running X4: Foundations game -- query the "
            "player's empire and give ships orders.\n\n" + API_REFERENCE),
    )
    def x4_exec(code: str) -> str:
        return session.run(code)

    @server.tool(
        name="x4_status",
        title="Link status",
        description=(
            "Cheap health check of the bridge: whether X4 is connected, whether "
            "it is ticking (it stalls while its window is in the background), "
            "whether a savegame is loaded, and how old the last snapshot is. "
            "Use this to explain a failure instead of retrying blindly."
        ),
    )
    def x4_status() -> dict:
        st = x4.status()
        st["install"] = artifacts
        return st

    @server.prompt(
        name="x4_playbook",
        title="How to work with the X4 bridge",
        description="Working rules for answering questions about the player's empire.",
    )
    def x4_playbook() -> str:
        return (
            "You are looking at a live X4: Foundations save through x4_exec.\n\n"
            + API_REFERENCE
            + "\nWORKING RULES\n"
            "  1. Start with x4.refresh(). One call, then work locally.\n"
            "  2. Answer with what the player can see: use .label for ships and\n"
            "     the localised sector names, since that is what is on their\n"
            "     screen. Match on .model / .macro / .owner internally.\n"
            "  3. If a request is ambiguous -- 'make a fleet' out of one ship,\n"
            "     'send it to the argon' with a dozen argon sectors -- print what\n"
            "     you found and ask the player before acting.\n"
            "  4. Never break an existing fleet by accident: a ship with a\n"
            "     commander already answers to somebody.\n"
            "  5. On a traceback, fix your own code and retry rather than\n"
            "     reporting the error to the player.\n"
        )

    return server


def _env(name: str, default):
    """Environment first, so a .env file can drive everything in Docker."""
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return type(default)(value) if isinstance(default, int) else value


def main():
    ap = argparse.ArgumentParser(
        description="MCP server for X4: Foundations. Every option can also be "
                    "set through the environment (see .env.example).")
    ap.add_argument("--transport", choices=["stdio", "http"],
                    default=_env("X4MCP_TRANSPORT", "http"))
    ap.add_argument("--game-port", type=int, default=_env("X4MCP_GAME_PORT", 8765),
                    help="port the X4 extension connects to")
    ap.add_argument("--http-port", type=int, default=_env("X4MCP_HTTP_PORT", 8766))
    ap.add_argument("--host", default=_env("X4MCP_HTTP_HOST", "127.0.0.1"),
                    help="bind address for MCP; 0.0.0.0 inside a container")
    ap.add_argument("--game-dir", default=_env("X4_DIR", None),
                    help="X4 install folder (default: autodetect)")
    ap.add_argument("--language", default=_env("X4MCP_LANGUAGE", "en"),
                    help="language for canonical ship names in the catalogue")
    args = ap.parse_args()

    try:
        artifacts = prepare_artifacts(args.game_dir, args.language)
        print(f"x4mcp: {artifacts['api_functions']} API signatures indexed "
              f"from {artifacts['game_dir']}; orders, order parameters and "
              f"ship models are asked of the running game", file=sys.stderr)
    except FileNotFoundError as e:
        # Not fatal: the bridge still works, only the canonical-name catalogue
        # and API index are missing. Say so loudly instead of failing silently.
        print(f"x4mcp: {e}", file=sys.stderr)
        artifacts = {"error": str(e)}

    server = build_server(args.game_port, artifacts)
    if args.transport == "http":
        print(f"x4mcp: MCP on http://{args.host}:{args.http_port}/mcp; "
              f"the game dials into port {args.game_port}", file=sys.stderr)
        server.run(transport="streamable-http", host=args.host, port=args.http_port)
    else:
        server.run(transport="stdio")


if __name__ == "__main__":
    main()
