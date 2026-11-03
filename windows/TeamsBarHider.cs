using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Teams Bar Hider")]
[assembly: System.Reflection.AssemblyVersion("0.5.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.5.0.0")]
[assembly: System.Reflection.AssemblyInformationalVersion("0.5.0")]

internal static class Native
{
    internal delegate bool Enumerate(IntPtr window, IntPtr state);
    [DllImport("user32.dll")] internal static extern bool EnumWindows(Enumerate callback, IntPtr state);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetClassName(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(IntPtr window, int command);
    internal static string Text(IntPtr window, bool className)
    {
        var buffer = new StringBuilder(2048);
        if (className) GetClassName(window, buffer, buffer.Capacity);
        else GetWindowText(window, buffer, buffer.Capacity);
        return buffer.ToString();
    }
}

internal static class Policy
{
    // Exact toolbar prefixes are deliberate. Never match a main meeting window by size.
    internal static bool IsToolbar(string process, string windowClass, string title)
    {
        bool teams = string.Equals(process, "ms-teams", StringComparison.OrdinalIgnoreCase)
            || string.Equals(process, "Teams", StringComparison.OrdinalIgnoreCase)
            || string.Equals(process, "msteams", StringComparison.OrdinalIgnoreCase);
        if (!teams || !windowClass.StartsWith("TeamsWebView", StringComparison.Ordinal)) return false;
        return title.Equals("Sharing control bar", StringComparison.OrdinalIgnoreCase)
            || title.StartsWith("Sharing control bar |", StringComparison.OrdinalIgnoreCase)
            || title.Equals("Paylaşım denetim çubuğu", StringComparison.OrdinalIgnoreCase)
            || title.StartsWith("Paylaşım denetim çubuğu |", StringComparison.OrdinalIgnoreCase);
    }
}

internal sealed class WindowIdentity
{
    internal IntPtr Handle;
    internal int Pid;
    internal long Started;
    internal static WindowIdentity Read(IntPtr handle, bool requireToolbar)
    {
        try
        {
            uint pid;
            Native.GetWindowThreadProcessId(handle, out pid);
            using (var process = Process.GetProcessById((int)pid))
            {
                if (process.SessionId != Process.GetCurrentProcess().SessionId) return null;
                if (requireToolbar && !Policy.IsToolbar(process.ProcessName, Native.Text(handle, true), Native.Text(handle, false))) return null;
                return new WindowIdentity { Handle = handle, Pid = (int)pid, Started = process.StartTime.ToUniversalTime().Ticks };
            }
        }
        catch (ArgumentException) { return null; }
        catch (InvalidOperationException) { return null; }
        catch (System.ComponentModel.Win32Exception) { return null; }
    }
    internal bool StillMatches()
    {
        var current = Read(Handle, true);
        return current != null && current.Pid == Pid && current.Started == Started;
    }
}

internal static class Startup
{
    private const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "TeamsBarHider";
    internal static bool Enabled
    {
        get
        {
            using (var key = Registry.CurrentUser.OpenSubKey(RunPath))
                return key != null && string.Equals(key.GetValue(ValueName) as string,
                    "\"" + Application.ExecutablePath + "\"", StringComparison.OrdinalIgnoreCase);
        }
        set
        {
            using (var key = Registry.CurrentUser.CreateSubKey(RunPath))
            {
                if (value) key.SetValue(ValueName, "\"" + Application.ExecutablePath + "\"");
                else key.DeleteValue(ValueName, false);
            }
        }
    }
}

internal sealed class Tray : ApplicationContext
{
    private readonly NotifyIcon icon = new NotifyIcon();
    private readonly Icon applicationIcon;
    private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    private readonly Dictionary<IntPtr, WindowIdentity> hidden = new Dictionary<IntPtr, WindowIdentity>();
    private readonly EventWaitHandle stop;
    private readonly ToolStripMenuItem enabled = new ToolStripMenuItem("Otomatik gizle / Auto-hide");
    private readonly ToolStripMenuItem startup = new ToolStripMenuItem("Oturum açıldığında başlat / Start at login");
    private readonly ToolStripMenuItem status = new ToolStripMenuItem();
    private bool active = true;
    internal Tray(EventWaitHandle stopEvent)
    {
        stop = stopEvent;
        var menu = new ContextMenuStrip();
        status.Enabled = false;
        enabled.Checked = true;
        enabled.Click += delegate { SetActive(!active); };
        startup.Checked = Startup.Enabled;
        startup.Click += delegate
        {
            try { Startup.Enabled = !Startup.Enabled; startup.Checked = Startup.Enabled; }
            catch (Exception error) { MessageBox.Show(error.Message, "Teams Bar Hider"); }
        };
        menu.Items.Add(status);
        menu.Items.Add(enabled);
        menu.Items.Add("Çubuğu geri getir ve duraklat / Restore and pause", null, delegate { SetActive(false); });
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Çıkış / Quit", null, delegate { ExitThread(); });
        using (var stream = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("TeamsBarHider.AppIcon.ico"))
        {
            if (stream == null) throw new InvalidOperationException("The application icon is missing.");
            using (var source = new Icon(stream, SystemInformation.SmallIconSize))
                applicationIcon = (Icon)source.Clone();
        }
        icon.Icon = applicationIcon;
        icon.Text = "Teams Bar Hider";
        icon.ContextMenuStrip = menu;
        icon.DoubleClick += delegate { SetActive(!active); };
        icon.Visible = true;
        timer.Interval = 750;
        timer.Tick += delegate { if (stop.WaitOne(0)) ExitThread(); else Scan(); };
        Scan();
        timer.Start();
    }
    private void SetActive(bool value)
    {
        active = value;
        enabled.Checked = value;
        if (!value) Restore();
        Scan();
    }
    private void Scan()
    {
        foreach (var handle in new List<IntPtr>(hidden.Keys))
            if (!hidden[handle].StillMatches()) hidden.Remove(handle);
        if (active)
        {
            Native.EnumWindows(delegate(IntPtr handle, IntPtr state)
            {
                if (!Native.IsWindowVisible(handle)) return true;
                // Cheap class filter before resolving the owning process.
                if (!Native.Text(handle, true).StartsWith("TeamsWebView", StringComparison.Ordinal)) return true;
                var identity = WindowIdentity.Read(handle, true);
                if (identity == null) return true;
                Native.ShowWindow(handle, 0);
                if (!Native.IsWindowVisible(handle)) hidden[handle] = identity;
                return true;
            }, IntPtr.Zero);
        }
        status.Text = !active ? "Duraklatıldı / Paused" : hidden.Count > 0
            ? "Paylaşım çubuğu gizlendi / Toolbar hidden"
            : "Paylaşım çubuğu bekleniyor / Waiting for toolbar";
    }
    private void Restore()
    {
        foreach (var identity in hidden.Values)
            if (identity.StillMatches()) Native.ShowWindow(identity.Handle, 4); // no activation
        hidden.Clear();
    }
    protected override void ExitThreadCore()
    {
        timer.Stop();
        Restore();
        icon.Visible = false;
        base.ExitThreadCore();
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) { timer.Dispose(); icon.Dispose(); applicationIcon.Dispose(); }
        base.Dispose(disposing);
    }
}

internal static class Program
{
    [STAThread]
    internal static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        string identity = WindowsIdentity.GetCurrent().User.Value;
        string stopName = @"Local\TeamsBarHider.Stop." + identity;
        if (Array.IndexOf(args, "--stop") >= 0 || Array.IndexOf(args, "--uninstall") >= 0)
        {
            if (Array.IndexOf(args, "--uninstall") >= 0) Startup.Enabled = false;
            try { using (var signal = EventWaitHandle.OpenExisting(stopName)) signal.Set(); }
            catch (WaitHandleCannotBeOpenedException) { }
            return 0;
        }
        if (Array.IndexOf(args, "--inspect") >= 0)
        {
            var lines = new List<string> { "Teams Bar Hider: local window inspection (meeting titles omitted)" };
            Native.EnumWindows(delegate(IntPtr handle, IntPtr state)
            {
                string windowClass = Native.Text(handle, true);
                if (!windowClass.StartsWith("TeamsWebView", StringComparison.Ordinal)) return true;
                uint pid; Native.GetWindowThreadProcessId(handle, out pid);
                var candidate = WindowIdentity.Read(handle, true);
                lines.Add("pid=" + pid + " class=" + windowClass + " recognizedToolbar=" + (candidate != null) + " visible=" + Native.IsWindowVisible(handle));
                return true;
            }, IntPtr.Zero);
            File.WriteAllLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "inspection.txt"), lines);
            return 0;
        }
        if (Array.IndexOf(args, "--install") >= 0) Startup.Enabled = true;
        bool created;
        using (var mutex = new Mutex(true, @"Local\TeamsBarHider.Instance." + identity, out created))
        {
            if (!created) return 0;
            using (var signal = new EventWaitHandle(false, EventResetMode.AutoReset, stopName))
            using (var tray = new Tray(signal)) Application.Run(tray);
            mutex.ReleaseMutex();
        }
        return 0;
    }
}
