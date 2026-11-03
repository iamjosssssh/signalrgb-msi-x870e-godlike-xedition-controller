// Shows SignalRGB's LCD frames on the MSI MEG X870E GODLIKE Dynamic Dashboard (USB 0DB0:F53A or 0DB0:84DF).
//
// The panel takes commands as HID output reports over the control pipe, and a SignalRGB plugin can't
// send those. So the plugin sends its JPEGs here over 127.0.0.1, and this uploads them with the same
// commands as MSI's own API_DYNAMIC DASHBOARD.dll: upload to slot 7 of image mode, step off the slot,
// and step back on to show it.
//
// It builds only upload and display mode commands. The firmware update, reset and "save to flash"
// commands aren't in this file.
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

static class Bridge {
    const int Port = 51875;
    // The panel refuses an upload that comes less than about 100 ms after the last one.
    const int MinUploadGapMs = 1000;
    const int StuckUploadMs = 20000;
    static StreamWriter log;
    static readonly object gate = new object();
    static readonly AutoResetEvent wake = new AutoResetEvent(false);
    static byte[] pending;
    static long uploadStartedAt;

    public static void Log(string text) {
        lock (log) {
            log.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + text);
            log.Flush();
        }
    }

    static void OpenLog() {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MSIGodlikeSignalRGB");
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "lcd-bridge.log");
        if (File.Exists(path) && new FileInfo(path).Length > 200 * 1024) {
            File.Delete(path);
        }
        log = new StreamWriter(path, true);
    }

    static void Main(string[] args) {
        bool first;
        using (new Mutex(true, "GodlikeLcdBridge", out first)) {
            if (!first) {
                return;
            }
            OpenLog();
            string dump = args.Length > 0 ? args[0] : null;
            new Thread(() => Uploads(dump)) { IsBackground = true }.Start();
            new Thread(Watchdog) { IsBackground = true }.Start();
            Receive();
        }
    }

    // LLG1|frame|index|count|base64. Keeps only the newest frame.
    static void Receive() {
        UdpClient udp = new UdpClient(new IPEndPoint(IPAddress.Loopback, Port));
        udp.Client.ReceiveBufferSize = 8 * 1024 * 1024;
        Log("started on 127.0.0.1:" + Port);
        string frame = null;
        string[] chunks = null;
        int left = 0;
        while (true) {
            IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
            byte[] data = udp.Receive(ref from);
            try {
                string[] p = Encoding.ASCII.GetString(data).Split('|');
                if (p.Length != 5 || p[0] != "LLG1") {
                    continue;
                }
                int index = int.Parse(p[2]), count = int.Parse(p[3]);
                if (frame != p[1]) {
                    frame = p[1];
                    chunks = new string[Math.Max(1, Math.Min(count, 64))];
                    left = chunks.Length;
                }
                if (index < 0 || index >= chunks.Length) {
                    continue;
                }
                if (chunks[index] == null) {
                    left--;
                }
                chunks[index] = p[4];
                if (left == 0) {
                    byte[] jpeg = Convert.FromBase64String(string.Concat(chunks));
                    if (jpeg.Length > 4 && jpeg[0] == 0xFF && jpeg[1] == 0xD8) {
                        lock (gate) {
                            pending = jpeg;
                        }
                        wake.Set();
                    }
                }
            } catch (FormatException) {
                // Not ours, or a damaged frame. The next one replaces it.
            }
        }
    }

    static void Uploads(string dump) {
        Panel panel = null;
        long sent = 0;
        while (true) {
            wake.WaitOne();
            byte[] jpeg;
            lock (gate) {
                jpeg = pending;
                pending = null;
            }
            if (jpeg == null) {
                continue;
            }
            try {
                if (panel == null) {
                    panel = new Panel();
                    Log("panel opened");
                }
                if (dump != null) {
                    File.WriteAllBytes(dump, jpeg);
                }
                Interlocked.Exchange(ref uploadStartedAt, Environment.TickCount);
                panel.Show(Panel.ToPanelJpeg(jpeg));
                Interlocked.Exchange(ref uploadStartedAt, 0);
                sent++;
                if (sent == 1 || sent % 500 == 0) {
                    Log("frames shown " + sent + ", last " + jpeg.Length + " bytes");
                }
            } catch (Exception e) {
                Interlocked.Exchange(ref uploadStartedAt, 0);
                Log("upload failed: " + e.Message);
                if (panel != null) {
                    panel.Dispose();
                    panel = null;
                }
            }
            Thread.Sleep(MinUploadGapMs);
        }
    }

    // A HID write has no timeout. If one never returns, exit so the panel isn't left with half a job,
    // and the sign-in task or the next start brings this back.
    static void Watchdog() {
        while (true) {
            Thread.Sleep(2000);
            long started = Interlocked.Read(ref uploadStartedAt);
            if (started != 0 && Environment.TickCount - started > StuckUploadMs) {
                Log("an upload is stuck, exiting");
                Environment.Exit(1);
            }
        }
    }
}

class Panel : IDisposable {
    const int Report = 64, Data = 1024;
    const byte SendFileNode = 32, SendFileStart = 34, SendFileEnd = 38, SetDisplayMode = 80;
    const byte ModeImage = 1, ImageSlots = 10, SlotUser = 7, SlotOther = 6;
    const string Node = "M1-S7-O-R0.jpg";
    const int SettleMs = 300, StepOffMs = 60;

    [StructLayout(LayoutKind.Sequential)] struct IfaceData { public int cbSize; public Guid guid; public int flags; public IntPtr reserved; }
    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_SetOutputReport(SafeFileHandle h, byte[] b, int n);
    [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr p, int f);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref IfaceData o);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref IfaceData o, IntPtr b, int n, out int need, IntPtr d);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr p, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(SafeFileHandle h, byte[] b, int n, out int w, IntPtr o);

    readonly SafeFileHandle handle;

    public Panel() {
        string path = FindPath();
        if (path == null) {
            throw new IOException("panel not found");
        }
        handle = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (handle.IsInvalid) {
            throw new IOException("could not open the panel: error " + Marshal.GetLastWin32Error());
        }
    }

    public void Dispose() { handle.Dispose(); }

    // The panel's decoder is picky, and this encoder is the one it has been seen to show.
    public static byte[] ToPanelJpeg(byte[] jpeg) {
        using (MemoryStream input = new MemoryStream(jpeg))
        using (Image image = Image.FromStream(input))
        using (MemoryStream output = new MemoryStream()) {
            ImageCodecInfo codec = null;
            foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) {
                if (c.MimeType == "image/jpeg") {
                    codec = c;
                }
            }
            using (EncoderParameters quality = new EncoderParameters(1)) {
                quality.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 85L);
                image.Save(output, codec, quality);
            }
            return output.ToArray();
        }
    }

    static string FindPath() {
        Guid g;
        HidD_GetHidGuid(out g);
        IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
        try {
            for (int i = 0; ; i++) {
                IfaceData d = new IfaceData();
                d.cbSize = Marshal.SizeOf(d);
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref d)) {
                    return null;
                }
                int need;
                SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out need, IntPtr.Zero);
                IntPtr buf = Marshal.AllocHGlobal(need);
                try {
                    Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
                    if (SetupDiGetDeviceInterfaceDetail(set, ref d, buf, need, out need, IntPtr.Zero)) {
                        string path = Marshal.PtrToStringUni(new IntPtr(buf.ToInt64() + 4));
                        string low = path.ToLowerInvariant();
                        if (low.Contains("vid_0db0&pid_f53a") || low.Contains("vid_0db0&pid_84df")) {
                            return path;
                        }
                    }
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
            }
        } finally {
            SetupDiDestroyDeviceInfoList(set);
        }
    }

    // Report 1: 01 6B 5A cmd 00 length(4 LE) parameters
    void Send(byte command, uint length, byte[] parameters) {
        byte[] r = new byte[Report];
        r[0] = 1;
        r[1] = 0x6B;
        r[2] = 0x5A;
        r[3] = command;
        BitConverter.GetBytes(length).CopyTo(r, 5);
        if (parameters != null) {
            Array.Copy(parameters, 0, r, 9, Math.Min(parameters.Length, Report - 9));
        }
        if (!HidD_SetOutputReport(handle, r, Report)) {
            throw new IOException("command " + command + " failed: error " + Marshal.GetLastWin32Error());
        }
    }

    void Select(byte slot) {
        byte[] p = new byte[19];
        p[0] = ModeImage;
        p[2] = ImageSlots;
        p[3 + slot] = 1;
        Send(SetDisplayMode, (uint)p.Length, p);
    }

    public void Show(byte[] jpeg) {
        byte[] name = Encoding.ASCII.GetBytes(Node);
        byte[] head = new byte[4 + name.Length];
        BitConverter.GetBytes(jpeg.Length).CopyTo(head, 0);
        name.CopyTo(head, 4);
        Send(SendFileNode, (uint)head.Length, head);
        Send(SendFileStart, (uint)jpeg.Length, null);
        for (int at = 0; at < jpeg.Length; at += Data - 1) {
            byte[] packet = new byte[Data];
            packet[0] = 2;
            Array.Copy(jpeg, at, packet, 1, Math.Min(Data - 1, jpeg.Length - at));
            int written;
            if (!WriteFile(handle, packet, Data, out written, IntPtr.Zero) || written != Data) {
                throw new IOException("upload stopped at byte " + at + ": error " + Marshal.GetLastWin32Error());
            }
        }
        Send(SendFileEnd, 0, null);
        Thread.Sleep(SettleMs);
        Select(SlotOther);
        Thread.Sleep(StepOffMs);
        Select(SlotUser);
    }
}
