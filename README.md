# ddc

Minimal command-line tool to control an external monitor over DDC/CI from an Apple Silicon Mac: brightness, contrast, input source, volume, and any other VCP code the monitor supports.

Single Swift file, no dependencies.

## Requirements

- Apple Silicon Mac (M1 or later). Intel Macs are not supported.
- An external monitor with DDC/CI enabled (often a setting in the monitor's OSD menu).
- Xcode or the Command Line Tools, to build.

## Build

```bash
swiftc -O ddc.swift -o ddc
```

## Usage

```bash
ddc get <vcp>
ddc set <vcp> <value>
```

`<vcp>` and `<value>` accept decimal or `0x`-prefixed hex.

```bash
./ddc get 0x10          # current=70 max=100
./ddc set 0x10 40       # brightness to 40
./ddc set 0x12 50       # contrast to 50
./ddc get 0x60          # current input source
./ddc set 0x60 0x0f     # switch input (value is monitor-specific)
```

Common VCP codes:

| Code   | Feature        |
|--------|----------------|
| `0x10` | Brightness     |
| `0x12` | Contrast       |
| `0x60` | Input source   |
| `0x62` | Audio volume   |
| `0x8D` | Audio mute     |
| `0xD6` | Power mode     |

Input source values vary between monitors. Typical ones are `0x0f` (DisplayPort 1), `0x10` (DisplayPort 2), `0x11` (HDMI 1), `0x12` (HDMI 2) and `0x1b` (USB-C). Run `ddc get 0x60` on each input to find yours.

### Exit codes

| Code | Meaning                                          |
|------|--------------------------------------------------|
| `0`  | Success                                          |
| `1`  | No DDC-capable display found, or read/write failed |
| `2`  | Invalid arguments                                |

## How it works

`ddc` uses the private `IOAVService` API from IOKit to send I2C messages to the display through Apple Silicon's display coprocessor. It looks at every external AV service and uses the first one that answers a DDC read. It then sends standard DDC/CI "Get VCP Feature" or "Set VCP Feature" packets.

Some monitors ignore a single write, so each write is sent twice. Writes and reads are retried a few times.

## Limitations

- Only one external display is used: the first one that responds.
- It relies on undocumented Apple APIs that could change in a future macOS release.
- Monitors connected through some docks or adapters may not pass DDC through.
