#!/usr/bin/env python3
"""
End-to-end check of the MCP layer against the live game.

Drives the server in-process through the SDK's own client, which exercises the
real tool schemas and serialisation rather than calling the functions directly.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mcp  # noqa: E402
from x4mcp_server import build_server  # noqa: E402


def text_of(result) -> str:
    parts = []
    for block in getattr(result, "content", []) or []:
        parts.append(getattr(block, "text", str(block)))
    return "\n".join(parts)


async def main():
    server = build_server(game_port=8765)
    async with mcp.Client(server) as client:
        tools = await client.list_tools()
        print("tools:", [t.name for t in tools.tools])
        desc = next(t for t in tools.tools if t.name == "x4_exec").description or ""
        print(f"x4_exec description: {len(desc)} chars, ~{len(desc)//4} tokens")

        prompts = await client.list_prompts()
        print("prompts:", [p.name for p in prompts.prompts])

        print("\n--- waiting for the game to connect ---")
        status_text = ""
        for _ in range(60):
            status_text = text_of(await client.call_tool("x4_status", {}))
            if '"savegame_loaded": true' in status_text.lower():
                break
            await asyncio.sleep(1)
        print(status_text)

        cases = [
            ("refresh + counts", """
x4.refresh()
print(x4.summary())
"""),
            # The localised query is taken from the snapshot rather than
            # written here, so the test works whatever language is installed.
            ("language-independent lookup", """
sample = next((s for s in x4.ships if s.model and s.name), None)
queries = [sample.model, sample.name, sample.kind] if sample else []
for q in queries:
    print(repr(q), "->", [s.label for s in x4.find(q)])
"""),
            ("fleet structure", """
for s in x4.ships:
    if s.subordinates:
        print(s.model, s.idcode, "commands", [m.model for m in x4.fleet_of(s)])
print("free ships:", [(s.model, s.idcode) for s in x4.free_ships()])
"""),
            ("sector identity by macro", """
hq = x4.stations[0]
sec = x4.sector_of(hq)
print("HQ:", hq.label, "| sector:", sec.name if sec else None,
      "| macro:", hq.sector_macro)
print("argon sectors:", [s.name for s in x4.sectors_of_owner("argon")][:5])
"""),
            ("namespace persists", "print('calls so far, hyps still bound:', len(x4.find('Hyperion')))"),
            ("traceback is returned", "x4.no_such_method()"),
        ]
        for title, code in cases:
            print(f"\n--- {title} ---")
            res = await client.call_tool("x4_exec", {"code": code})
            print(text_of(res).strip()[:1200])


if __name__ == "__main__":
    asyncio.run(main())
