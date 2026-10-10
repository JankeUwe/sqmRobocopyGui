<#
	C#-Helfer, die in reinem PowerShell nicht sauber gehen:
	- FolderPicker: moderner Explorer-Ordnerdialog (IFileOpenDialog) mit Adressleiste, Schnellzugriff,
	  Mehrfachauswahl und Dark Mode. Der WinForms-FolderBrowserDialog von .NET Framework (PS 5.1)
	  ist nur der alte Baumdialog.
	- Runner: startet robocopy mit umgeleiteter Ausgabe auf Hintergrund-Threads. PowerShell-Scriptblocks
	  duerfen dort nicht laufen, deshalb sammelt der Runner Zeilen in einer Liste, die ein
	  WinForms-Timer auf dem UI-Thread abholt. robocopy ueberschreibt die Prozentanzeige mit CR -
	  solche Segmente landen in Progress statt im Protokoll.
	- PathProbe: Verzeichnispruefung mit Zeitlimit (Test-Path auf eine tote Freigabe blockiert sonst
	  die Oberflaeche bis zu 20 s).
#>

function Initialize-srgHelper {
	if ('Srg.Runner' -as [type]) { return }
	Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace Srg
{
    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    internal class FileOpenDialogCom { }

    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileOpenDialog
    {
        [PreserveSig] int Show(IntPtr parent);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(uint fos);
        void GetOptions(out uint pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
        void GetResults(out IShellItemArray ppenum);
        void GetSelectedItems(out IShellItemArray ppsai);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport, Guid("b63ea76d-1f85-456f-a19c-48159efa858b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItemArray
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppvOut);
        void GetPropertyStore(int flags, ref Guid riid, out IntPtr ppv);
        void GetPropertyDescriptionList(IntPtr keyType, ref Guid riid, out IntPtr ppv);
        void GetAttributes(int dwAttribFlags, uint sfgaoMask, out uint psfgaoAttribs);
        void GetCount(out uint pdwNumItems);
        void GetItemAt(uint dwIndex, out IShellItem ppsi);
        void EnumItems(out IntPtr ppenumShellItems);
    }

    public static class FolderPicker
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc, ref Guid riid, out IShellItem ppv);

        private const uint FOS_PICKFOLDERS = 0x20, FOS_FORCEFILESYSTEM = 0x40, FOS_NOCHANGEDIR = 0x8,
                           FOS_ALLOWMULTISELECT = 0x200, FOS_PATHMUSTEXIST = 0x800;
        private const uint SIGDN_FILESYSPATH = 0x80058000;

        // null = abgebrochen
        public static string[] Pick(IntPtr owner, string title, string initialPath, bool multi)
        {
            IFileOpenDialog dlg = (IFileOpenDialog)new FileOpenDialogCom();
            try
            {
                uint opt;
                dlg.GetOptions(out opt);
                opt |= FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR | FOS_PATHMUSTEXIST;
                if (multi) opt |= FOS_ALLOWMULTISELECT;
                dlg.SetOptions(opt);
                if (!string.IsNullOrEmpty(title)) dlg.SetTitle(title);
                if (!string.IsNullOrEmpty(initialPath))
                {
                    try
                    {
                        Guid iid = typeof(IShellItem).GUID;
                        IShellItem folder;
                        SHCreateItemFromParsingName(initialPath, IntPtr.Zero, ref iid, out folder);
                        dlg.SetFolder(folder);
                    }
                    catch { }
                }
                if (dlg.Show(owner) != 0) return null;
                IShellItemArray items;
                dlg.GetResults(out items);
                uint count;
                items.GetCount(out count);
                List<string> paths = new List<string>();
                for (uint i = 0; i < count; i++)
                {
                    IShellItem it;
                    items.GetItemAt(i, out it);
                    string p;
                    it.GetDisplayName(SIGDN_FILESYSPATH, out p);
                    if (!string.IsNullOrEmpty(p)) paths.Add(p);
                }
                return paths.ToArray();
            }
            finally { Marshal.ReleaseComObject(dlg); }
        }
    }

    public static class PathProbe
    {
        // 1 = vorhanden, 0 = nicht vorhanden, -1 = keine Antwort innerhalb des Zeitlimits
        public static int DirectoryExists(string path, int timeoutMs)
        {
            bool result = false;
            Thread t = new Thread(() => { try { result = Directory.Exists(path); } catch { } });
            t.IsBackground = true;
            t.Start();
            if (!t.Join(timeoutMs)) return -1;
            return result ? 1 : 0;
        }
    }

    public class Runner
    {
        private Process _p;
        private readonly object _lock = new object();
        private List<string> _lines = new List<string>();
        private static readonly Regex Percent = new Regex(@"^\s*\d+(\.\d+)?%\s*$");

        public volatile string Progress = "";
        public volatile string Current = "";
        public volatile bool Finished;
        public volatile bool Cancelled;
        public int ExitCode = -1;
        public DateTime Started;
        public DateTime Ended;
        public long LineCount;

        public void Start(string fileName, string arguments, int codePage)
        {
            ProcessStartInfo psi = new ProcessStartInfo(fileName, arguments);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            Encoding enc;
            try { enc = Encoding.GetEncoding(codePage); } catch { enc = Encoding.Default; }
            psi.StandardOutputEncoding = enc;
            psi.StandardErrorEncoding = enc;
            _p = new Process();
            _p.StartInfo = psi;
            _p.Start();
            Started = DateTime.Now;
            Thread t1 = new Thread(() => Pump(_p.StandardOutput)); t1.IsBackground = true; t1.Start();
            Thread t2 = new Thread(() => Pump(_p.StandardError)); t2.IsBackground = true; t2.Start();
            Thread t3 = new Thread(() =>
            {
                t1.Join(); t2.Join();
                _p.WaitForExit();
                try { ExitCode = _p.ExitCode; } catch { }
                Ended = DateTime.Now;
                Finished = true;
            });
            t3.IsBackground = true;
            t3.Start();
        }

        private void Pump(StreamReader reader)
        {
            StringBuilder sb = new StringBuilder();
            bool lastCr = false;
            int c;
            while ((c = reader.Read()) != -1)
            {
                char ch = (char)c;
                if (ch == '\r') { Flush(sb, true); lastCr = true; continue; }
                if (ch == '\n') { if (!(lastCr && sb.Length == 0)) Flush(sb, false); lastCr = false; continue; }
                lastCr = false;
                sb.Append(ch);
            }
            if (sb.Length > 0) Flush(sb, false);
        }

        private void Flush(StringBuilder sb, bool cr)
        {
            string s = sb.ToString();
            sb.Length = 0;
            if (cr && Percent.IsMatch(s)) { Progress = s.Trim(); return; }
            if (s.Trim().Length > 0 && s.IndexOf('\t') >= 0) { Current = s.Trim(); Progress = ""; }
            lock (_lock) { _lines.Add(s); LineCount++; }
        }

        public string[] Drain(int max)
        {
            lock (_lock)
            {
                if (_lines.Count == 0) return new string[0];
                int n = Math.Min(max, _lines.Count);
                string[] r = _lines.GetRange(0, n).ToArray();
                _lines.RemoveRange(0, n);
                return r;
            }
        }

        public int Pending { get { lock (_lock) { return _lines.Count; } } }

        public void Stop()
        {
            Cancelled = true;
            try { if (_p != null && !_p.HasExited) _p.Kill(); } catch { }
        }
    }
}
'@
}
