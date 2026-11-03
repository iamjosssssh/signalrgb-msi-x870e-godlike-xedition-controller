<#
Sets the picture or video on the MSI MEG X870E GODLIKE dashboard LCD, without MSI Center.

  godlike-lcd.ps1 -Info                 read-only: firmware, brightness, what is showing
  godlike-lcd.ps1 -Image photo.jpg      any image Windows can read, fitted to the panel
  godlike-lcd.ps1 -Video clip.mp4       H.264 baseline MP4 at 400x864 (see README)
  godlike-lcd.ps1 -Brightness 60        0-100

The plugin in plugin\MSI_Dynamic_Dashboard_LCD.js shows SignalRGB's LCD tab on this screen. This is for doing it by hand.

Same commands as MSI's own API_DYNAMIC DASHBOARD.dll, which handles USB IDs 0DB0:84DF and
0DB0:F53A with one class. The firmware update and reset commands are not in this file.
#>
param(
    [switch]$Info,
    [string]$Image,
    [string]$Video,
    [ValidateRange(0, 100)][int]$Brightness = -1
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public class GodlikeLcd : IDisposable {
    const int REPORT = 64, DATA = 1024;
    const byte GET_DEV_ID = 16, GET_DEV_INFO = 20, GET_DISPLAY_MODE = 82, SET_BACKLIGHT = 24, SET_DISPLAY_MODE = 80,
        SEND_FILE_NODE = 32, SEND_FILE_DATA_START = 34, SEND_FILE_DATA_END = 38, DEL_FILE_NODE = 42;

    [StructLayout(LayoutKind.Sequential)] struct IfaceData { public int cbSize; public Guid guid; public int flags; public IntPtr reserved; }
    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_SetOutputReport(SafeFileHandle h, byte[] b, int n);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_GetInputReport(SafeFileHandle h, byte[] b, int n);
    [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr p, int f);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref IfaceData o);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref IfaceData o, IntPtr b, int n, out int need, IntPtr d);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr p, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(SafeFileHandle h, byte[] b, int n, out int w, IntPtr o);

    SafeFileHandle h;

    static string FindPath() {
        Guid g; HidD_GetHidGuid(out g);
        IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
        try {
            for (int i = 0; ; i++) {
                IfaceData d = new IfaceData(); d.cbSize = Marshal.SizeOf(d);
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref d)) return null;
                int need; SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out need, IntPtr.Zero);
                IntPtr buf = Marshal.AllocHGlobal(need);
                try {
                    Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
                    if (SetupDiGetDeviceInterfaceDetail(set, ref d, buf, need, out need, IntPtr.Zero)) {
                        string path = Marshal.PtrToStringUni(new IntPtr(buf.ToInt64() + 4));
                        string low = path.ToLowerInvariant();
                        if (low.Contains("vid_0db0&pid_f53a") || low.Contains("vid_0db0&pid_84df")) return path;
                    }
                } finally { Marshal.FreeHGlobal(buf); }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
    }

    public GodlikeLcd() {
        string path = FindPath();
        if (path == null) throw new Exception("Dashboard LCD not found (USB 0DB0:F53A or 0DB0:84DF).");
        h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new Exception("Could not open the dashboard LCD: error " + Marshal.GetLastWin32Error());
    }

    public void Dispose() { h.Dispose(); }

    // Report 1: 01 6B 5A cmd 00 len(4 LE) params
    void Send(byte cmd, uint len, byte[] p) {
        byte[] r = new byte[REPORT];
        r[0] = 1; r[1] = 0x6B; r[2] = 0x5A; r[3] = cmd;
        BitConverter.GetBytes(len).CopyTo(r, 5);
        if (p != null) Array.Copy(p, 0, r, 9, Math.Min(p.Length, REPORT - 9));
        if (!HidD_SetOutputReport(h, r, REPORT)) throw new Exception("Command " + cmd + " failed: error " + Marshal.GetLastWin32Error());
        Thread.Sleep(10);
    }

    // Other programs may be talking to the panel too, so wait for the expected reply.
    byte[] Query(byte cmd, uint len, byte[] p, byte reply) {
        for (int attempt = 0; attempt < 5; attempt++) {
            Send(cmd, len, p);
            for (int i = 0; i < 20; i++) {
                byte[] r = new byte[REPORT]; r[0] = 1;
                // Replies come back without the report ID: 6B 5A cmd 00 len(4 LE) params
                if (HidD_GetInputReport(h, r, REPORT) && r[0] == 0x6B && r[1] == 0x5A && r[2] == reply) {
                    byte[] data = new byte[REPORT - 8];
                    Array.Copy(r, 8, data, 0, data.Length);
                    return data;
                }
                Thread.Sleep(20);
            }
        }
        throw new Exception("No reply to command " + cmd);
    }

    public string InfoText() {
        byte[] id = Query(GET_DEV_ID, 4, new byte[4], (byte)(GET_DEV_ID + 1));
        byte[] i = Query(GET_DEV_INFO, 4, new byte[4], (byte)(GET_DEV_INFO + 1));
        string text = "device id " + BitConverter.ToUInt16(id, 0) + ", flash " + BitConverter.ToUInt16(id, 2)
            + "\nfirmware " + BitConverter.ToUInt32(i, 0) + ", brightness " + BitConverter.ToUInt32(i, 4)
            + ", direction " + BitConverter.ToUInt32(i, 8) + ", status " + BitConverter.ToUInt32(i, 12);
        foreach (byte seek in new byte[] { 0, 1 }) {
            byte[] m = Query(GET_DISPLAY_MODE, 1, new byte[] { seek }, (byte)(GET_DISPLAY_MODE + 1));
            string screen = "";
            for (int k = 3; k < 19; k++) screen += m[k].ToString("X2") + " ";
            text += "\nmode query " + seek + ": mode " + m[0] + ", slideshow " + m[1] + ", count " + m[2] + ", screen " + screen.Trim();
        }
        return text;
    }

    public void SetBrightness(int percent) { Send(SET_BACKLIGHT, 4, BitConverter.GetBytes(percent)); }

    static byte[] Name(string node) { return System.Text.Encoding.ASCII.GetBytes(node); }

    void ShowSlot(int slot) {
        byte[] p = new byte[19];
        p[0] = 1; p[2] = 10; p[3 + slot] = 1;
        Send(SET_DISPLAY_MODE, 19, p);
    }

    void Delete(string node) {
        byte[] p = new byte[32];
        Name(node).CopyTo(p, 0);
        Send(DEL_FILE_NODE, 32, p);
        Thread.Sleep(1000);
    }

    // The slot being replaced can't be showing, so step off it first, as MSI Center does.
    public void Upload(byte[] file, string node, string[] replaces, int slot) {
        ShowSlot(slot - 1);
        Thread.Sleep(300);
        foreach (string old in replaces) Delete(old);

        byte[] name = Name(node);
        byte[] head = new byte[4 + name.Length];
        BitConverter.GetBytes(file.Length).CopyTo(head, 0);
        name.CopyTo(head, 4);
        Send(SEND_FILE_NODE, (uint)head.Length, head);
        Send(SEND_FILE_DATA_START, (uint)file.Length, null);
        for (int at = 0; at < file.Length; at += DATA - 1) {
            byte[] pkt = new byte[DATA];
            pkt[0] = 2;
            Array.Copy(file, at, pkt, 1, Math.Min(DATA - 1, file.Length - at));
            int written;
            if (!WriteFile(h, pkt, DATA, out written, IntPtr.Zero) || written != DATA)
                throw new Exception("Upload stopped at byte " + at + ": error " + Marshal.GetLastWin32Error());
        }
        Send(SEND_FILE_DATA_END, 0, null);
        Thread.Sleep(500);
        ShowSlot(slot);
    }
}
'@

$slot = 7
$imageNode = "M1-S$slot-O-R0.jpg"
$videoNode = "M1-S$slot-V-R0.mp4"
$imageNodes = 'png', 'jpg', 'bmp', 'gif' | ForEach-Object { "M1-S$slot-O-R0.$_" }
$panelWidth = 400
$panelHeight = 864

function Get-PanelJpeg($path) {
    Add-Type -AssemblyName System.Drawing
    $source = [Drawing.Image]::FromFile((Resolve-Path $path).Path)
    $panel = New-Object Drawing.Bitmap $panelWidth, $panelHeight
    $g = [Drawing.Graphics]::FromImage($panel)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([Drawing.Color]::Black)
    $scale = [Math]::Min($panelWidth / $source.Width, $panelHeight / $source.Height)
    $w = [int]($source.Width * $scale)
    $h = [int]($source.Height * $scale)
    $g.DrawImage($source, [int](($panelWidth - $w) / 2), [int](($panelHeight - $h) / 2), $w, $h)
    $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $quality = New-Object Drawing.Imaging.EncoderParameters 1
    $quality.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), 92L
    $out = New-Object IO.MemoryStream
    $panel.Save($out, $codec, $quality)
    $g.Dispose(); $panel.Dispose(); $source.Dispose()
    , $out.ToArray()
}

$lcd = New-Object GodlikeLcd
try {
    if ($Image) {
        $lcd.Upload((Get-PanelJpeg $Image), $imageNode, ($imageNodes + $videoNode), $slot)
        "Uploaded $Image."
    }
    if ($Video) {
        $lcd.Upload([IO.File]::ReadAllBytes((Resolve-Path $Video).Path), $videoNode, $imageNodes, $slot)
        "Uploaded $Video."
    }
    if ($Brightness -ge 0) {
        $lcd.SetBrightness($Brightness)
        "Brightness set to $Brightness."
    }
    if ($Info -or $Image -or $Video) {
        $lcd.InfoText()
    }
}
finally {
    $lcd.Dispose()
}
