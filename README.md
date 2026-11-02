# SignalRGB controller for the MSI MEG X870E GODLIKE X EDITION

A replacement SignalRGB plugin for this board's Mystic Light controller (USB `0DB0:0076`, MS-7E48), plus fixes for problems that stop SignalRGB from controlling the board and RAM.

Community project, not affiliated with MSI or WhirlwindFX. Use at your own risk.

## Status

| Item | Status |
|---|---|
| RAM lighting (4x G.Skill Trident Z5 Neo) | Fixed and confirmed on real hardware |
| Stall in SignalRGB's built-in plugin | Fixed: 5-second errors stopped in testing |
| Logo lighting | **Not working yet.** See [Board logos stay dark](#board-logos-stay-dark) |
| Dynamic Dashboard LCD | Not started. See [LCD notes](#lcd-notes) |

## What was wrong

**The built-in plugin stalls the board, and that also blocks the RAM.** After each color update it reads feature report `0x51` with a 727-byte buffer, smaller than the board's largest feature report (761 bytes). The read fails with Windows error 121 (semaphore timeout) after 5 seconds, repeatedly. While that was happening, SignalRGB raised "I2C Bus Disabled" and the RAM ignored all colors, even Forced mode. With this plugin the errors stopped, each stick's scan went from about 10 seconds to 1.3 seconds, and all four sticks followed SignalRGB. The plugin never reads that report.

**L-Connect 3 corrupts the RAM scan.** L-Connect-Service starts a bundled copy of OpenRGB that also drives RAM, GPU, keyboard and Mystic Light. SignalRGB read garbled RAM model names while it ran (`AUD05-5-010` instead of `AUDA0-E6K5-0101`), rejected the sticks and removed them from its device list. `scripts/disable-lconnect-openrgb.ps1` turns off only that copy by renaming it. L-Connect keeps running fans, pump and LCDs. Updating L-Connect may restore the file.

**The built-in table turns on a zone this board doesn't report.** The board reports JPIPE1-3, while SignalRGB's table also turns on JPIPE4. OpenRGB's source notes that on the similar GODLIKE MAX, JPIPE4 turns all logo LEDs dark. This plugin leaves JPIPE4 off. That alone did not light the logos here.

## Install

1. Create `Documents\WhirlwindFX\Plugins\MSI_Godlike_X`.
2. Copy `plugin\MSI_185Byte_Controller_0x0DB0.js` into it. The file name must stay the same so it replaces the built-in plugin.
3. If you run L-Connect 3, run `scripts\disable-lconnect-openrgb.ps1` as administrator.
4. Fully restart SignalRGB.

SignalRGB's log should show `Custom Plugin File Loaded` with this path. To undo, delete the folder and restart SignalRGB. `scripts\enable-lconnect-openrgb.ps1` restores OpenRGB.

## Safety

SignalRGB's own MSI plugin warns that one wrong packet can brick this RGB controller, so this plugin is deliberately small:

- It writes only on `MEG X870E GODLIKE X EDITION (MS-7E48)`, checked by name. On any other board it sends nothing.
- It has two kinds of write, the same report types SignalRGB already sends: the 290-byte setup report `0x50` and the 727-byte per-LED report `0x51`.
- It does not read from the board or send any other command.

`test/sim.cjs` checks all of this against a fake device. Run it with `node test/sim.cjs`.

## Board logos stay dark

The logos stay dark even in Forced mode with this plugin, so canvas placement isn't the cause. The controller answers query `01 BA` with byte 6 = `00`, which SignalRGB treats as "EZ LED disabled", even with EZ LED Control on in the BIOS. This persisted after a full power-off.

Check the physical EZ LED switch on the board first. MSI's manuals for sibling boards ([Z790 GODLIKE MAX](https://www.manualowl.com/m/MSI/MEG-Z790-GODLIKE-MAX/Manual/723715?page=25)) describe `LED_SW1`, which switches off all of the board's LEDs. Its position on the X870E X Edition isn't confirmed here, so use your board's manual. If you can get the logos working on this board, please open an issue.

## LCD notes

The screen is a separate HID device, `0DB0:F53A`, named `DYNAMIC DASHBOARD III` (input 64 bytes, output 1024). [godlike-dashboard-linux](https://github.com/nulltty/godlike-dashboard-linux) documents the regular GODLIKE's screen (`0DB0:84DF`), which takes uploaded 400x864 H.264 video rather than live frames. Whether the X Edition uses the same protocol is untested.

## Claude Code and the SignalRGB MCP

SignalRGB's MCP server (`http://127.0.0.1:16037/mcp`) replies without a `Content-Type` header, which Claude's HTTP client rejects with `Unexpected content type: null`. `tools/mcp-bridge.cjs` is a small stdio bridge that avoids this:

```bash
claude mcp add SignalRGB -s user -- node /path/to/mcp-bridge.cjs
```

## Credits

Protocol facts came from reading SignalRGB's MSI plugin and [openrgb-headless](https://github.com/hello-nexus/openrgb-headless) (GPL-2.0-or-later). No code was copied from either.
