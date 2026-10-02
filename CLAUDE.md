# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`ddc` is a single-file Swift CLI (`ddc.swift`) that reads/writes DDC/CI VCP codes on an external monitor from an Apple Silicon Mac (e.g. brightness `0x10`, contrast `0x12`, input source `0x60`). The compiled arm64 binary `ddc` is committed alongside the source.

## Build & run

No package manifest, no tests, no linter — just `swiftc`:

```bash
swiftc -O ddc.swift -o ddc        # rebuild the committed binary after editing the source
./ddc get 0x10                     # prints "current=<n> max=<n>"
./ddc set 0x10 50                  # VCP and value accept decimal or 0x-prefixed hex
```

Testing requires a real DDC-capable external display; there is no mock. Exit codes: `0` ok, `1` no display / I/O failure, `2` usage error.

## How it works

- **Private IOKit API**: `IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C` are undocumented symbols bound via `@_silgen_name`. They only exist on Apple Silicon (DCP); there is no Intel path.
- **Display discovery**: iterates `DCPAVServiceProxy` registry entries with `Location == "External"`. Several may exist (unused ports), so the first one that answers a read of VCP `0x60` is selected — every invocation therefore performs a probe read before the real command.
- **DDC/CI framing**: I2C chip address `0x37`, register offset `0x51`. `packet()` builds `[0x80|len, payload…, checksum]` where the checksum is XOR seeded with `0x6E ^ 0x51` (destination address ^ source address). Get = opcode `0x01`, set = opcode `0x03` with a 16-bit big-endian value.
- **Timing/retries are deliberate**: each write is sent twice in a row (some monitors ignore a single write), with up to 5 write attempts and 3 read attempts, and `usleep` delays between them. Changing these delays or retry counts can break flaky monitors — keep them unless there is a specific reason.
- **Read reply layout** (11 bytes): `reply[2] == 0x02` (VCP reply opcode), `reply[3] == 0` (no error), max at bytes 6–7, current at bytes 8–9.
