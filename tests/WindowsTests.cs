using System;
using System.Windows.Forms;
internal static class WindowsTests
{
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    [STAThread]
    public static int Main()
    {
        Require(Policy.IsToolbar("ms-teams", "TeamsWebView", "Sharing control bar | Microsoft Teams"), "New Teams toolbar");
        Require(Policy.IsToolbar("Teams", "TeamsWebView", "Paylaşım denetim çubuğu | Microsoft Teams"), "Turkish toolbar");
        Require(!Policy.IsToolbar("chrome", "TeamsWebView", "Sharing control bar | Microsoft Teams"), "Other process must remain visible");
        Require(!Policy.IsToolbar("ms-teams", "OtherWindow", "Sharing control bar | Microsoft Teams"), "Other class must remain visible");
        Require(!Policy.IsToolbar("ms-teams", "TeamsWebView", "Daily meeting | Microsoft Teams"), "Meeting must remain visible");
        Require(!Policy.IsToolbar("ms-teams", "TeamsWebView", "Meeting compact view | Microsoft Teams"), "Compact call must remain visible");
        Require(!Policy.IsToolbar("ms-teams", "TeamsWebView", "Sharing control bar fake title"), "Prefix boundaries");
        using (var form = new Form())
        {
            form.Opacity = 0;
            form.ShowInTaskbar = false;
            form.Show(); Application.DoEvents();
            Require(Native.IsWindowVisible(form.Handle), "Native fixture is visible");
            Require(WindowIdentity.Read(form.Handle, true) == null, "Our app is never a Teams target");
            Native.ShowWindow(form.Handle, 0);
            Require(!Native.IsWindowVisible(form.Handle), "Native hide works");
            Native.ShowWindow(form.Handle, 4);
            Require(Native.IsWindowVisible(form.Handle), "Native restore works");
            form.Hide();
        }
        Console.WriteLine("11 checks passed: target isolation and native hide/restore.");
        return 0;
    }
}
