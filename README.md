# SignalRGB controller for the MSI MEG X870E GODLIKE X EDITION

A replacement SignalRGB plugin for this board's Mystic Light controller (USB `0DB0:0076`, MS-7E48), plus fixes for problems that stop SignalRGB from controlling the board and RAM.

Community project, not affiliated with MSI or WhirlwindFX. Use at your own risk.

## Status

| Item | Status |
|---|---|
| RAM lighting (4x G.Skill Trident Z5 Neo) | Fixed and confirmed on real hardware |
| Logo lighting | Working and confirmed. See [Board logos stay dark](#board-logos-stay-dark) if yours don't light |
| MSI's software taking the board back | Fixed. See [MSI keeps taking over](#msi-keeps-taking-over) |
| RAM stutter on animated effects | Cause found and fixable. See [RAM stutter](#ram-stutter-on-animated-effects) |
| Dynamic Dashboard LCD | Experimental upload tool, not working yet. See [The LCD](#the-lcd). MSI Center is still the way to change this screen |

## What was wrong

**The built-in plugin stalls the board, and that also blocks the RAM.** After each color update it reads feature report `0x51` with a 727-byte buffer, smaller than the board's largest feature report (761 bytes). The read fails with Windows error 121 (semaphore timeout) after 5 seconds, repeatedly. While that was happening, SignalRGB raised "I2C Bus Disabled" and the RAM ignored all colors, even Forced mode. With this plugin that read is gone, each stick's scan went from about 10 seconds to 1.3 seconds, and all four sticks followed SignalRGB.

**L-Connect 3 corrupts the RAM scan.** L-Connect-Service starts a bundled copy of OpenRGB that also drives RAM, GPU, keyboard and Mystic Light. SignalRGB read garbled RAM model names while it ran (`AUD05-5-010` instead of `AUDA0-E6K5-0101`), rejected the sticks and removed them from its device list. `scripts/disable-lconnect-openrgb.ps1` turns off only that copy by renaming it. L-Connect keeps running fans, pump and LCDs. Updating L-Connect may restore the file.

**The built-in table turns on a zone this board doesn't report.** The board reports JPIPE1-3, while SignalRGB's table also turns on JPIPE4. OpenRGB's source notes that on the similar GODLIKE MAX, JPIPE4 turns all logo LEDs dark. This plugin leaves JPIPE4 off. That alone did not light the logos here.

## Install

1. In SignalRGB, open **Settings**, then **Add-ons**, paste this repo's URL and restart SignalRGB:

   ```
   https://github.com/iamjosssssh/signalrgb-msi-x870e-godlike-xedition-controller
   ```

2. Run the setup from PowerShell. It asks for admin rights:

   ```powershell
   & (Get-ChildItem "$env:LOCALAPPDATA\WhirlwindFX\SignalRgb\cache\addons" -Recurse -Filter setup-msi.ps1 | Select-Object -First 1).FullName
   ```

3. Restart SignalRGB. Its log should show `Custom Plugin File Loaded` with the plugin's path.

**Step 2 is required.** The add-on only delivers the files. A plugin in an add-on loses to SignalRGB's downloaded copy of the same plugin, so without the setup you'd still run the built-in plugin with the RAM stall.

**The setup makes these changes to your PC:**

| Change | Why | Effect you'll notice |
|---|---|---|
| Copies the plugin to `Documents\WhirlwindFX\Plugins\MSI_Godlike_X` | Only that folder can replace a built-in plugin | Your board uses this plugin. It won't get SignalRGB's plugin updates |
| Adds the task `Keep MSI CC_Engine Closed`, running as admin at sign-in | `CC_Engine` causes the RAM stutter | MSI Center's overclocking and gaming-mode features only work while its window is open |
| If MSI Center is installed: disables `LightKeeperService` and `Mystic_Light_Service`, blocks `LEDKeeper2.exe`, stops MSI Center starting at sign-in | They take the board and RAM back | MSI Center's Mystic Light page stops working. You have to open MSI Center yourself |
| If L-Connect 3 is installed: renames its bundled `OpenRGB.exe` | It corrupts SignalRGB's RAM scan | L-Connect keeps working without OpenRGB |

`setup-msi.ps1 -DryRun` lists the steps without changing anything. `setup-msi.ps1 -Remove` undoes them, then remove the add-on.

**Warnings**

- The plugin writes only on `MEG X870E GODLIKE X EDITION (MS-7E48)`, and does nothing on any other board.
- An MSI Center or L-Connect update can undo some of these changes. Run the setup again if the board or RAM stop following SignalRGB.
- This repo can't change the Dynamic Dashboard LCD. Keep using MSI Center for it. See [The LCD](#the-lcd).

See [MSI keeps taking over](#msi-keeps-taking-over) and [RAM stutter](#ram-stutter-on-animated-effects) for the details.

### Device pictures

Add `-DevicePictures` to the setup to show real pictures for G.Skill Trident Z5 Neo RAM and the Razer Basilisk V3 Pro's dongle. It's optional because those devices use SignalRGB's own plugins, and the RAM picture applies to all RAM on that plugin. `tools\apply-device-images.ps1` makes a local copy of each current plugin with only the image changed. Run it again after a SignalRGB update, and restart SignalRGB after it prints `True`.

## Safety

SignalRGB's own MSI plugin warns that one wrong packet can brick this RGB controller, so this plugin is deliberately small:

- It writes only on `MEG X870E GODLIKE X EDITION (MS-7E48)`, checked by name. On any other board it sends nothing.
- It has two kinds of write, the same report types SignalRGB already sends: the 290-byte setup report `0x50` and the 727-byte per-LED report `0x51`.
- It does not read from the board or send any other command.

`test/sim.cjs` checks all of this against a fake device. Run it with `node test/sim.cjs`.

## MSI keeps taking over

MSI's `LEDKeeper2.exe` and the MSI Center app (`DCv2.exe`) take the board and RAM back from SignalRGB. Disabling the Mystic Light services isn't enough, because MSI Center re-registers and re-enables its `LEDKeeper2` logon task at every boot.

`scripts\disable-msi-mystic-light.ps1`, run as administrator, disables the services and task, blocks `LEDKeeper2.exe` by file name through Image File Execution Options so this survives MSI Center updates, and stops MSI Center starting at sign-in. MSI Center's other features still work when you open it, but its Mystic Light page won't. `scripts\enable-msi-mystic-light.ps1` undoes all of it.

SignalRGB's "Conflicting RGB Software" alert still appears if you keep apps it lists running, such as MSI Center's core services, SteelSeries GG or Razer Synapse. With their lighting off, it didn't stop anything from working here.

## RAM stutter on animated effects

MSI's `CC_Engine_x64.exe` competes with SignalRGB for the Mystic Light controller. When both use it, a color write can take 5 seconds to fail with Windows error 121, and SignalRGB's RAM updates wait during that time.

| Test on this board, Rainbow effect | Stalls |
|---|---|
| Plugin sending at 4 updates a second, `CC_Engine` running | 6 in 4 minutes |
| Plugin writes turned off | 0 in 5 minutes |
| Plugin sending at 4 updates a second, `CC_Engine` stopped | 0 in 4 minutes |
| Plugin sending at 10 updates a second, `CC_Engine` stopped | 0 in 4 minutes |

`CC_Engine` is MSI Center's overclocking and gaming-mode engine. `scripts\stop-msi-engine.ps1` keeps it closed unless MSI Center is open, and the setup runs it at sign-in. It needs admin, because `MSI.CentralServer` starts the engine elevated and a normal process gets Access denied. MSI Center's overclocking features need it, so don't use this if you rely on them.

## Board logos stay dark

Check the physical EZ LED switch on the board first. On this board it was off, which kept the logos dark even in Forced mode and with EZ LED Control on in the BIOS. The controller reports this by answering query `01 BA` with byte 6 = `00`. MSI's manuals for sibling boards ([Z790 GODLIKE MAX](https://www.manualowl.com/m/MSI/MEG-Z790-GODLIKE-MAX/Manual/723715?page=25)) describe the switch as `LED_SW1`.

## The LCD

The screen is a separate HID device, `0DB0:F53A`, named `DYNAMIC DASHBOARD III`. MSI's own `API_DYNAMIC DASHBOARD.dll` handles it and the regular GODLIKE's `0DB0:84DF` with one class, and [godlike-dashboard-linux](https://github.com/nulltty/godlike-dashboard-linux) documents the protocol. One correction to that project: the command it calls "set name" (`0x2A`) is `DEL_FILE_NODE` in MSI's code.

```powershell
tools\godlike-lcd.ps1 -Info                 # read-only status
tools\godlike-lcd.ps1 -Image photo.jpg      # any image Windows can read, fitted to 400x864
tools\godlike-lcd.ps1 -Video clip.mp4       # see below
tools\godlike-lcd.ps1 -Brightness 60
```

**Not working yet.** On a board already playing a video set in MSI Center, `-Image` uploaded a picture and the panel reported it as selected, but the screen kept playing the video. `-Video` is untested. Keep using MSI Center's Dynamic Dashboard page to change this screen.

The panel stores uploads as files and plays them itself, so a picture or video stays with nothing running on the PC. For the same reason this isn't a live SignalRGB screen: streaming would mean a file write per frame, and the storage wear from that is unknown.

Videos need to be H.264 baseline MP4 at 400x864, which `ffmpeg` can produce:

```powershell
ffmpeg -i in.mp4 -vf "scale=400:864:force_original_aspect_ratio=decrease,pad=400:864:(ow-iw)/2:(oh-ih)/2:black,setsar=1" -r 30 -an -c:v libx264 -profile:v baseline -level 3.0 -g 300 -sc_threshold 0 -pix_fmt yuvj420p -movflags +faststart out.mp4
```

The tool has no firmware update or reset commands.

## Claude Code and the SignalRGB MCP

SignalRGB's MCP server (`http://127.0.0.1:16037/mcp`) replies without a `Content-Type` header, which Claude's HTTP client rejects with `Unexpected content type: null`. `tools/mcp-bridge.cjs` is a small stdio bridge that avoids this:

```bash
claude mcp add SignalRGB -s user -- node /path/to/mcp-bridge.cjs
```

## Credits

Protocol facts came from reading SignalRGB's MSI plugin and [openrgb-headless](https://github.com/hello-nexus/openrgb-headless) (GPL-2.0-or-later). No code was copied from either.
