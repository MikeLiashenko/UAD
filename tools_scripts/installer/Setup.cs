// The Windows installer of Ukraine Air Defense, and (built with /define:UNINSTALLER) its uninstaller.
// Compiled by tools_scripts/installer/make_installer.ps1 with the C# compiler of the .NET Framework
// that every Windows 10/11 has (C# 5: no string interpolation, no "?."). The game itself rides at
// the end of the installer's own file: [the .exe][entries][trailer] — see Payload below.
//
// Installs for the current user only (no administrator rights, no UAC prompt), by default into
// %LOCALAPPDATA%\Programs\Ukraine Air Defense: UAD.exe, the uninstaller, a Start menu shortcut, a
// desktop shortcut and an entry in Settings → Apps. Run again over an installed game, it updates
// it in place (closing the running game first). Worlds and settings live in the game's own user
// folder (%APPDATA%\Godot\app_userdata\...) and are never touched.
//
// Command line: /S silent install, /D=folder the folder, /desktop a desktop shortcut in silent mode,
// /shot=prefix pictures of the three pages (prefix_1.png …) instead of a window, for checks;
// /lang=uk|ru|en overrides the language of Windows.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

static class Product
{
	public const string Name = "Ukraine Air Defense";
	public const string Exe = "UAD.exe";
	public const string Uninstaller = "Uninstall UAD.exe";
	public const string Key = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\UkraineAirDefense";
	public const string Site = "https://mikeliashenko.github.io/UAD/";
	public const string Publisher = "Mike Liashenko";

	public static string DefaultDir()
	{
		return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", Name);
	}

	public static string StartMenuLink()
	{
		return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), Name + ".lnk");
	}

	public static string DesktopLink()
	{
		return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), Name + ".lnk");
	}

	/// The folder of an earlier installation, or null.
	public static string Installed()
	{
		using (RegistryKey k = Registry.CurrentUser.OpenSubKey(Key))
		{
			if (k == null) return null;
			string dir = k.GetValue("InstallLocation") as string;
			return dir != null && File.Exists(Path.Combine(dir, Exe)) ? dir : null;
		}
	}

	/// Closes copies of the game started from this folder. False if the player said no.
	public static bool CloseGame(string dir, bool ask)
	{
		List<Process> found = new List<Process>();
		foreach (Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(Exe)))
		{
			try
			{
				if (string.Equals(Path.GetDirectoryName(p.MainModule.FileName).TrimEnd('\\'), dir.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
					found.Add(p);
			}
			catch (Exception) { }
		}
		if (found.Count == 0) return true;
		if (ask && MessageBox.Show(L.T("running"), Name, MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK)
			return false;
		foreach (Process p in found)
		{
			try
			{
				p.CloseMainWindow();
				if (!p.WaitForExit(6000)) { p.Kill(); p.WaitForExit(4000); }
			}
			catch (Exception) { }
		}
		return true;
	}
}

/// Ukrainian, Russian or English, after the language of Windows.
static class L
{
	static int lang = -1;
	static readonly Dictionary<string, string[]> S = new Dictionary<string, string[]>
	{
		{ "install", new[] { "ВСТАНОВИТИ", "УСТАНОВИТЬ", "INSTALL" } },
		{ "update", new[] { "ОНОВИТИ", "ОБНОВИТЬ", "UPDATE" } },
		{ "cancel", new[] { "Скасувати", "Отмена", "Cancel" } },
		{ "folder", new[] { "ПАПКА ГРИ", "ПАПКА ИГРЫ", "INSTALL FOLDER" } },
		{ "change", new[] { "Змінити…", "Изменить…", "Change…" } },
		{ "desktop", new[] { "Ярлик на робочому столі", "Ярлык на рабочем столе", "Desktop shortcut" } },
		{ "launch", new[] { "Запустити гру після встановлення", "Запустить игру после установки", "Launch the game when done" } },
		{ "tagline", new[] { "Нічне чергування ППО над містами України", "Ночное дежурство ПВО над городами Украины", "Night air-defense duty over the cities of Ukraine" } },
		{ "isupdate", new[] { "Гру вже встановлено — її буде оновлено. Світи й налаштування збережуться.", "Игра уже установлена — она будет обновлена. Миры и настройки сохранятся.", "The game is already installed and will be updated. Your worlds and settings stay." } },
		{ "installing", new[] { "Встановлення…", "Установка…", "Installing…" } },
		{ "unpacking", new[] { "Розпаковую гру", "Распаковываю игру", "Unpacking the game" } },
		{ "links", new[] { "Створюю ярлики", "Создаю ярлыки", "Creating shortcuts" } },
		{ "done", new[] { "Готово!", "Готово!", "All set!" } },
		{ "donetext", new[] { "Ukraine Air Defense встановлено. Ярлик — у меню «Пуск». Вдалого чергування!", "Ukraine Air Defense установлена. Ярлык — в меню «Пуск». Удачного дежурства!", "Ukraine Air Defense is installed; it is in the Start menu. Good hunting." } },
		{ "play", new[] { "ГРАТИ", "ИГРАТЬ", "PLAY" } },
		{ "close", new[] { "Закрити", "Закрыть", "Close" } },
		{ "running", new[] { "Гра зараз запущена. Закрити її, щоб продовжити?", "Игра сейчас запущена. Закрыть её, чтобы продолжить?", "The game is running. Close it to continue?" } },
		{ "noaccess", new[] { "Немає доступу до цієї папки. Оберіть іншу — наприклад, у своїй папці користувача.", "Нет доступа к этой папке. Выберите другую — например, в своей папке пользователя.", "This folder is not writable. Pick another one, for example inside your user folder." } },
		{ "failed", new[] { "Не вдалося встановити гру:", "Не удалось установить игру:", "The game could not be installed:" } },
		{ "pick", new[] { "Оберіть папку — гру буде встановлено в «Ukraine Air Defense» у ній.", "Выберите папку — игра будет установлена в «Ukraine Air Defense» внутри неё.", "Pick a folder: the game goes into «Ukraine Air Defense» inside it." } },
		{ "broken", new[] { "Файл інсталятора пошкоджено — завантажте його ще раз.", "Файл установщика повреждён — скачайте его заново.", "The installer file is damaged. Please download it again." } },
		{ "unask", new[] { "Видалити Ukraine Air Defense з цього комп'ютера?\n\nВаші світи й налаштування залишаться: якщо встановите гру знову, вони повернуться.", "Удалить Ukraine Air Defense с этого компьютера?\n\nВаши миры и настройки останутся: если установите игру снова, они вернутся.", "Remove Ukraine Air Defense from this computer?\n\nYour worlds and settings stay: install the game again and they are back." } },
		{ "undone", new[] { "Гру видалено.", "Игра удалена.", "The game has been removed." } },
	};

	/// /lang=uk|ru|en on the command line (for checking the pictures of every language).
	public static void Force(string two)
	{
		lang = two == "uk" ? 0 : two == "ru" ? 1 : 2;
	}

	public static string T(string key)
	{
		if (lang < 0)
		{
			string two = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
			lang = two == "uk" ? 0 : two == "ru" ? 1 : 2;
		}
		return S[key][lang];
	}
}

/// The files at the end of the installer: [entries][start: int64][count: int32]["UADSETUP"].
/// An entry: [name length: int32][name: UTF-8][size: int64][packed size: int64][gzip data].
class Payload
{
	public class Entry { public string Name; public long Size, Packed, Offset; }
	public List<Entry> Entries = new List<Entry>();
	public long Total;
	readonly string path;

	public Payload(string file)
	{
		path = file;
		using (FileStream fs = File.OpenRead(file))
		using (BinaryReader r = new BinaryReader(fs))
		{
			fs.Seek(-20, SeekOrigin.End);
			long start = r.ReadInt64();
			int count = r.ReadInt32();
			if (Encoding.ASCII.GetString(r.ReadBytes(8)) != "UADSETUP") throw new InvalidDataException("no payload");
			fs.Seek(start, SeekOrigin.Begin);
			for (int i = 0; i < count; i++)
			{
				Entry e = new Entry();
				e.Name = Encoding.UTF8.GetString(r.ReadBytes(r.ReadInt32()));
				e.Size = r.ReadInt64();
				e.Packed = r.ReadInt64();
				e.Offset = fs.Position;
				fs.Seek(e.Packed, SeekOrigin.Current);
				Entries.Add(e);
				Total += e.Size;
			}
		}
	}

	/// Unpacks one entry beside its final place, then swaps it in. progress(bytes) after each block.
	public void Extract(Entry e, string dest, Action<long> progress)
	{
		string tmp = dest + ".new";
		using (FileStream fs = File.OpenRead(path))
		{
			fs.Seek(e.Offset, SeekOrigin.Begin);
			using (GZipStream gz = new GZipStream(new Bounded(fs, e.Packed), CompressionMode.Decompress))
			using (FileStream o = File.Create(tmp))
			{
				byte[] buf = new byte[1 << 20];
				int n;
				while ((n = gz.Read(buf, 0, buf.Length)) > 0)
				{
					o.Write(buf, 0, n);
					progress(n);
				}
			}
		}
		if (new FileInfo(tmp).Length != e.Size) throw new InvalidDataException(L.T("broken"));
		if (File.Exists(dest)) File.Delete(dest);
		File.Move(tmp, dest);
	}

	/// A window onto part of a stream, so the decompressor stops at the end of its entry.
	class Bounded : Stream
	{
		readonly Stream s;
		long left;
		public Bounded(Stream inner, long length) { s = inner; left = length; }
		public override int Read(byte[] b, int off, int count)
		{
			if (left <= 0) return 0;
			int n = s.Read(b, off, (int)Math.Min(count, left));
			left -= n;
			return n;
		}
		public override bool CanRead { get { return true; } }
		public override bool CanSeek { get { return false; } }
		public override bool CanWrite { get { return false; } }
		public override long Length { get { throw new NotSupportedException(); } }
		public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
		public override void Flush() { }
		public override long Seek(long o, SeekOrigin so) { throw new NotSupportedException(); }
		public override void SetLength(long v) { throw new NotSupportedException(); }
		public override void Write(byte[] b, int o, int c) { throw new NotSupportedException(); }
	}
}

static class Shell
{
	/// A .lnk through the Windows Script Host (late bound: no extra references to compile against).
	public static void Shortcut(string lnk, string target, string description)
	{
		Type t = Type.GetTypeFromProgID("WScript.Shell");
		object sh = Activator.CreateInstance(t);
		try
		{
			object s = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { lnk });
			Type st = s.GetType();
			st.InvokeMember("TargetPath", BindingFlags.SetProperty, null, s, new object[] { target });
			st.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, s, new object[] { Path.GetDirectoryName(target) });
			st.InvokeMember("IconLocation", BindingFlags.SetProperty, null, s, new object[] { target + ",0" });
			st.InvokeMember("Description", BindingFlags.SetProperty, null, s, new object[] { description });
			st.InvokeMember("Save", BindingFlags.InvokeMethod, null, s, null);
			Marshal.FinalReleaseComObject(s);
		}
		finally { Marshal.FinalReleaseComObject(sh); }
	}

	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] public static extern bool ReleaseCapture();
	[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
	[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
	[DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, int f, IntPtr a, IntPtr b);
}

#if UNINSTALLER
static class Program
{
	[STAThread]
	static int Main(string[] args)
	{
		bool quiet = Array.Exists(args, a => a.Equals("/quiet", StringComparison.OrdinalIgnoreCase) || a.Equals("/S", StringComparison.OrdinalIgnoreCase));
		string dir = Path.GetDirectoryName(Application.ExecutablePath);
		if (!quiet && MessageBox.Show(L.T("unask"), Product.Name, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
			return 1;
		if (!Product.CloseGame(dir, !quiet)) return 1;
		foreach (string f in new[] { Product.StartMenuLink(), Product.DesktopLink(), Path.Combine(dir, Product.Exe) })
		{
			try { if (File.Exists(f)) File.Delete(f); } catch (Exception) { }
		}
		try { Registry.CurrentUser.DeleteSubKeyTree(Product.Key, false); } catch (Exception) { }
		Shell.SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
		if (!quiet) MessageBox.Show(L.T("undone"), Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
		// this file and its folder go once it has quit; "rd" without /s only removes an empty folder,
		// so nothing the player may have put there is ever lost
		ProcessStartInfo psi = new ProcessStartInfo("cmd.exe",
			"/c ping 127.0.0.1 -n 3 > nul & del /f /q \"" + Application.ExecutablePath + "\" & rd \"" + dir + "\"");
		psi.CreateNoWindow = true;
		psi.WindowStyle = ProcessWindowStyle.Hidden;
		psi.UseShellExecute = false;
		Process.Start(psi);
		return 0;
	}
}
#else
static class Program
{
	[STAThread]
	static int Main(string[] args)
	{
		string dir = null, shot = null;
		bool silent = false, desktop = false;
		foreach (string a in args)
		{
			if (a.Equals("/S", StringComparison.OrdinalIgnoreCase)) silent = true;
			else if (a.Equals("/desktop", StringComparison.OrdinalIgnoreCase)) desktop = true;
			else if (a.StartsWith("/D=", StringComparison.OrdinalIgnoreCase)) dir = a.Substring(3).Trim('"');
			else if (a.StartsWith("/shot=", StringComparison.OrdinalIgnoreCase)) shot = a.Substring(6).Trim('"');
			else if (a.StartsWith("/lang=", StringComparison.OrdinalIgnoreCase)) L.Force(a.Substring(6));
		}
		Payload payload = null;
		try { payload = new Payload(Application.ExecutablePath); }
		catch (Exception)
		{
			if (shot == null)
			{
				if (!silent) MessageBox.Show(L.T("broken"), Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				return 2;
			}
		}
		if (dir == null) dir = Product.Installed() ?? Product.DefaultDir();
		if (silent)
		{
			try
			{
				Installer.Run(payload, dir, desktop, delegate (string s, double f) { });
				return 0;
			}
			catch (Exception e) { Console.Error.WriteLine(e.Message); return 3; }
		}
		Shell.SetProcessDPIAware();
		Application.EnableVisualStyles();
		Application.SetCompatibleTextRenderingDefault(false);
		if (shot != null)
		{
			try { new SetupForm(payload, dir).Shots(shot); }
			catch (Exception e) { File.WriteAllText(shot + "_error.txt", e.ToString()); return 4; }
			return 0;
		}
		Application.Run(new SetupForm(payload, dir));
		return 0;
	}
}

/// The work itself, the same for the window and for /S.
static class Installer
{
	public static void Run(Payload payload, string dir, bool desktop, Action<string, double> report)
	{
		Directory.CreateDirectory(dir);
		long done = 0;
		report(L.T("unpacking"), 0);
		foreach (Payload.Entry e in payload.Entries)
		{
			payload.Extract(e, Path.Combine(dir, e.Name), delegate (long n)
			{
				done += n;
				report(L.T("unpacking"), 0.95 * done / Math.Max(1, payload.Total));
			});
		}
		report(L.T("links"), 0.96);
		string exe = Path.Combine(dir, Product.Exe);
		Shell.Shortcut(Product.StartMenuLink(), exe, L.T("tagline"));
		if (desktop) Shell.Shortcut(Product.DesktopLink(), exe, L.T("tagline"));
		using (RegistryKey k = Registry.CurrentUser.CreateSubKey(Product.Key))
		{
			k.SetValue("DisplayName", Product.Name);
			k.SetValue("DisplayVersion", AppVersion.Number);
			k.SetValue("DisplayIcon", exe + ",0");
			k.SetValue("Publisher", Product.Publisher);
			k.SetValue("InstallLocation", dir);
			k.SetValue("UninstallString", "\"" + Path.Combine(dir, Product.Uninstaller) + "\"");
			k.SetValue("QuietUninstallString", "\"" + Path.Combine(dir, Product.Uninstaller) + "\" /quiet");
			k.SetValue("URLInfoAbout", Product.Site);
			k.SetValue("NoModify", 1, RegistryValueKind.DWord);
			k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
			k.SetValue("EstimatedSize", (int)(payload.Total / 1024), RegistryValueKind.DWord);
			k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
		}
		Shell.SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
		report(L.T("done"), 1.0);
	}
}

/// The window: the night city across the top, then one of three pages — ready, installing, done.
class SetupForm : Form
{
	static readonly Color Bg = Color.FromArgb(8, 15, 32);
	static readonly Color Panel = Color.FromArgb(16, 27, 52);
	static readonly Color Text1 = Color.FromArgb(236, 241, 255);
	static readonly Color Text2 = Color.FromArgb(150, 168, 200);
	static readonly Color Yellow = Color.FromArgb(255, 213, 0);
	static readonly Color Blue = Color.FromArgb(0, 87, 183);

	readonly Payload payload;
	readonly bool update;
	readonly Image hero;
	string dir;
	int page;
	double progress;
	string status = "";
	readonly List<Control> pageReady = new List<Control>(), pageWork = new List<Control>(), pageDone = new List<Control>();
	TextBox folder;
	Tick desktop, launch;
	Label statusLabel;
	Button installBtn;

	public SetupForm(Payload p, string installDir)
	{
		payload = p;
		dir = installDir;
		update = Product.Installed() != null;
		using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("hero.png"))
			hero = Image.FromStream(s);
		SuspendLayout();
		AutoScaleDimensions = new SizeF(96F, 96F);
		AutoScaleMode = AutoScaleMode.Dpi;
		FormBorderStyle = FormBorderStyle.None;
		StartPosition = FormStartPosition.CenterScreen;
		ClientSize = new Size(720, 470);
		BackColor = Bg;
		Text = Product.Name;
		Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
		DoubleBuffered = true;
		Font = UiFont(10f, FontStyle.Regular);

		Label x = new Label();
		x.Text = "✕";
		x.Font = UiFont(13f, FontStyle.Regular);
		x.ForeColor = Text1;
		x.BackColor = Color.Transparent;
		x.TextAlign = ContentAlignment.MiddleCenter;
		x.Bounds = new Rectangle(678, 6, 36, 32);
		x.Cursor = Cursors.Hand;
		x.Click += delegate { if (page != 1) Close(); };
		Controls.Add(x);

		// ready
		Label tag = MakeLabel(update ? L.T("isupdate") : L.T("tagline"), 10.5f, FontStyle.Regular, Text1, new Rectangle(28, 262, 664, 26));
		Label cap = MakeLabel(L.T("folder"), 8.5f, FontStyle.Bold, Text2, new Rectangle(28, 300, 400, 18));
		folder = new TextBox();
		folder.Text = dir;
		folder.BorderStyle = BorderStyle.FixedSingle;
		folder.BackColor = Panel;
		folder.ForeColor = Text1;
		folder.Font = UiFont(10f, FontStyle.Regular);
		folder.Bounds = new Rectangle(28, 321, 524, 28);
		folder.ReadOnly = update;
		Controls.Add(folder);
		Button change = MakeButton(L.T("change"), false, new Rectangle(562, 319, 130, 30));
		change.Enabled = !update;
		change.Click += delegate { PickFolder(); };
		desktop = MakeCheck(L.T("desktop"), new Rectangle(28, 362, 400, 24), !update || File.Exists(Product.DesktopLink()));
		launch = MakeCheck(L.T("launch"), new Rectangle(28, 388, 400, 24), true);
		Button cancel = MakeButton(L.T("cancel"), false, new Rectangle(400, 410, 120, 44));
		cancel.Click += delegate { Close(); };
		installBtn = MakeButton(update ? L.T("update") : L.T("install"), true, new Rectangle(530, 410, 162, 44));
		installBtn.Click += delegate { Start(); };
		pageReady.AddRange(new Control[] { tag, cap, folder, change, desktop, launch, cancel, installBtn });

		// installing: the status line; the bar is painted by the form
		statusLabel = MakeLabel(L.T("installing"), 11f, FontStyle.Regular, Text1, new Rectangle(28, 300, 664, 26));
		pageWork.Add(statusLabel);

		// done
		Label dt = MakeLabel(L.T("done"), 20f, FontStyle.Bold, Yellow, new Rectangle(28, 276, 664, 40));
		Label dx = MakeLabel(L.T("donetext"), 10.5f, FontStyle.Regular, Text1, new Rectangle(28, 322, 664, 48));
		Button close = MakeButton(L.T("close"), false, new Rectangle(400, 410, 120, 44));
		close.Click += delegate { Close(); };
		Button play = MakeButton(L.T("play"), true, new Rectangle(530, 410, 162, 44));
		play.Click += delegate { Launch(); Close(); };
		pageDone.AddRange(new Control[] { dt, dx, close, play });

		ShowPage(0);
		ActiveControl = installBtn;
		ResumeLayout(false);
		MouseDown += delegate (object s, MouseEventArgs e)
		{
			if (e.Button == MouseButtons.Left) { Shell.ReleaseCapture(); Shell.SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); }
		};
	}

	protected override CreateParams CreateParams
	{
		get { CreateParams cp = base.CreateParams; cp.ClassStyle |= 0x20000; return cp; } // a drop shadow
	}

	protected override void OnHandleCreated(EventArgs e)
	{
		base.OnHandleCreated(e);
		int round = 2; // Windows 11: rounded corners on a borderless window
		try { Shell.DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch (Exception) { }
	}

	static Font UiFont(float size, FontStyle style)
	{
		foreach (FontFamily f in FontFamily.Families)
			if (f.Name == "Bahnschrift") return new Font("Bahnschrift", size, style);
		return new Font("Segoe UI", size, style);
	}

	Label MakeLabel(string text, float size, FontStyle style, Color color, Rectangle r)
	{
		Label l = new Label();
		l.Text = text;
		l.Font = UiFont(size, style);
		l.ForeColor = color;
		l.BackColor = Color.Transparent;
		l.Bounds = r;
		Controls.Add(l);
		return l;
	}

	Tick MakeCheck(string text, Rectangle r, bool on)
	{
		Tick c = new Tick();
		c.Text = text;
		c.Checked = on;
		c.ForeColor = Text1;
		c.Font = UiFont(10f, FontStyle.Regular);
		c.Bounds = r;
		Controls.Add(c);
		return c;
	}

	/// A checkbox in the game's colours: a yellow box with a dark tick when on.
	public class Tick : Control
	{
		bool on;
		public bool Checked { get { return on; } set { on = value; Invalidate(); } }

		public Tick()
		{
			SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
			BackColor = Color.Transparent;
			Cursor = Cursors.Hand;
			Click += delegate { Checked = !Checked; };
		}

		protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }

		protected override void OnPaint(PaintEventArgs e)
		{
			Graphics g = e.Graphics;
			g.SmoothingMode = SmoothingMode.AntiAlias;
			g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
			int b = (int)(Height * 0.72);
			Rectangle box = new Rectangle(1, (Height - b) / 2, b, b);
			using (GraphicsPath p = Round(box, b * 0.22f))
			{
				if (on)
					using (Brush br = new SolidBrush(Yellow)) g.FillPath(br, p);
				else
					using (Pen pen = new Pen(Text2, Math.Max(1f, b / 12f))) g.DrawPath(pen, p);
			}
			if (on)
				using (Pen pen = new Pen(Color.FromArgb(10, 18, 36), Math.Max(2f, b / 7f)))
				{
					pen.StartCap = pen.EndCap = LineCap.Round;
					pen.LineJoin = LineJoin.Round;
					g.DrawLines(pen, new PointF[] {
						new PointF(box.X + b * 0.22f, box.Y + b * 0.52f),
						new PointF(box.X + b * 0.42f, box.Y + b * 0.72f),
						new PointF(box.X + b * 0.78f, box.Y + b * 0.30f) });
				}
			TextRenderer.DrawText(g, Text, Font, new Rectangle(box.Right + b / 2, 0, Width - box.Right - b / 2, Height), ForeColor,
				TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
		}
	}

	Button MakeButton(string text, bool primary, Rectangle r)
	{
		Button b = new Button();
		b.Text = text;
		b.FlatStyle = FlatStyle.Flat;
		b.FlatAppearance.BorderSize = primary ? 0 : 1;
		b.FlatAppearance.BorderColor = Color.FromArgb(60, 80, 120);
		b.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(255, 226, 70) : Color.FromArgb(28, 44, 80);
		b.FlatAppearance.MouseDownBackColor = primary ? Color.FromArgb(230, 190, 0) : Color.FromArgb(36, 56, 100);
		b.BackColor = primary ? Yellow : Panel;
		b.ForeColor = primary ? Color.FromArgb(10, 18, 36) : Text1;
		b.Font = UiFont(primary ? 12f : 10f, primary ? FontStyle.Bold : FontStyle.Regular);
		b.Bounds = r;
		b.Cursor = Cursors.Hand;
		b.UseVisualStyleBackColor = false;
		Controls.Add(b);
		return b;
	}

	void ShowPage(int n)
	{
		page = n;
		foreach (Control c in pageReady) c.Visible = n == 0;
		foreach (Control c in pageWork) c.Visible = n == 1;
		foreach (Control c in pageDone) c.Visible = n == 2;
		if (n == 2) AcceptButton = (IButtonControl)pageDone[3];
		else if (n == 0) AcceptButton = installBtn;
		Invalidate();
	}

	void PickFolder()
	{
		using (FolderBrowserDialog d = new FolderBrowserDialog())
		{
			d.Description = L.T("pick");
			d.SelectedPath = Path.GetDirectoryName(folder.Text.TrimEnd('\\')) ?? "";
			if (d.ShowDialog(this) == DialogResult.OK)
			{
				string pick = d.SelectedPath;
				// never straight into a shared folder: the uninstaller removes only its own folder
				if (!Path.GetFileName(pick.TrimEnd('\\')).Equals(Product.Name, StringComparison.OrdinalIgnoreCase))
					pick = Path.Combine(pick, Product.Name);
				folder.Text = pick;
			}
		}
	}

	void Start()
	{
		dir = folder.Text.Trim();
		try
		{
			Directory.CreateDirectory(dir);
			string probe = Path.Combine(dir, ".probe");
			File.WriteAllText(probe, "");
			File.Delete(probe);
		}
		catch (Exception)
		{
			MessageBox.Show(this, L.T("noaccess"), Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Warning);
			return;
		}
		if (!Product.CloseGame(dir, true)) return;
		ShowPage(1);
		bool withDesktop = desktop.Checked;
		Thread t = new Thread(delegate ()
		{
			try
			{
				Installer.Run(payload, dir, withDesktop, delegate (string s, double f)
				{
					BeginInvoke((MethodInvoker)delegate { status = s; progress = f; statusLabel.Text = s + "  ·  " + (int)(f * 100) + "%"; Invalidate(BarRect()); });
				});
				if (!withDesktop && update && File.Exists(Product.DesktopLink())) File.Delete(Product.DesktopLink());
				BeginInvoke((MethodInvoker)delegate
				{
					if (launch.Checked) { Launch(); Close(); }
					else ShowPage(2);
				});
			}
			catch (Exception e)
			{
				BeginInvoke((MethodInvoker)delegate
				{
					MessageBox.Show(this, L.T("failed") + "\n\n" + e.Message, Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
					ShowPage(0);
				});
			}
		});
		t.IsBackground = true;
		t.Start();
	}

	void Launch()
	{
		try
		{
			ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(dir, Product.Exe));
			psi.WorkingDirectory = dir;
			Process.Start(psi);
		}
		catch (Exception) { }
	}

	Rectangle BarRect()
	{
		float k = ScreenDpi() / 96f;
		return new Rectangle((int)(28 * k), (int)(340 * k), (int)(664 * k), (int)(12 * k));
	}

	float ScreenDpi()
	{
		using (Graphics g = CreateGraphics()) return g.DpiX;
	}

	protected override void OnPaint(PaintEventArgs e)
	{
		Graphics g = e.Graphics;
		g.SmoothingMode = SmoothingMode.AntiAlias;
		g.InterpolationMode = InterpolationMode.HighQualityBicubic;
		g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
		float k = g.DpiX / 96f;
		Rectangle top = new Rectangle(0, 0, ClientSize.Width, (int)(250 * k));
		g.DrawImage(hero, top);
		// the picture sinks into the window
		Rectangle fade = new Rectangle(0, (int)(170 * k), ClientSize.Width, (int)(81 * k));
		using (LinearGradientBrush b = new LinearGradientBrush(fade, Color.FromArgb(0, Bg), Bg, LinearGradientMode.Vertical))
			g.FillRectangle(b, fade);
		using (Font f = UiFont(9f, FontStyle.Regular))
		using (Brush b = new SolidBrush(Text2))
		{
			string v = AppVersion.Label;
			SizeF sz = g.MeasureString(v, f);
			g.DrawString(v, f, b, ClientSize.Width - sz.Width - 14 * k, 226 * k);
		}
		// the flag's two colours as a thin rule
		g.FillRectangle(new SolidBrush(Blue), 0, ClientSize.Height - 4 * k, ClientSize.Width, 2 * k);
		g.FillRectangle(new SolidBrush(Yellow), 0, ClientSize.Height - 2 * k, ClientSize.Width, 2 * k);
		if (page == 1)
		{
			Rectangle r = BarRect();
			using (GraphicsPath p = Round(r, r.Height / 2f))
			using (Brush b = new SolidBrush(Panel))
				g.FillPath(b, p);
			if (progress > 0.002)
			{
				Rectangle f = new Rectangle(r.X, r.Y, Math.Max(r.Height, (int)(r.Width * progress)), r.Height);
				using (GraphicsPath p = Round(f, r.Height / 2f))
				using (LinearGradientBrush b = new LinearGradientBrush(r, Color.FromArgb(40, 120, 230), Yellow, LinearGradientMode.Horizontal))
					g.FillPath(b, p);
			}
		}
		base.OnPaint(e);
	}

	static GraphicsPath Round(Rectangle r, float rad)
	{
		GraphicsPath p = new GraphicsPath();
		float d = rad * 2;
		p.AddArc(r.X, r.Y, d, d, 180, 90);
		p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
		p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
		p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
		p.CloseFigure();
		return p;
	}

	/// Pictures of the three pages for checking the design (no window is shown).
	public void Shots(string prefix)
	{
		// child controls are only drawn in a window that has been shown: show it far off-screen
		// (and run this on the hidden desktop, tools_scripts/hidden_run.ps1)
		StartPosition = FormStartPosition.Manual;
		Location = new Point(-32000, -32000);
		ShowInTaskbar = false;
		Show();
		Application.DoEvents();
		for (int n = 0; n < 3; n++)
		{
			ShowPage(n);
			if (n == 1) { progress = 0.62; statusLabel.Text = L.T("unpacking") + "  ·  62%"; }
			Refresh();
			Application.DoEvents();
			using (Bitmap bmp = new Bitmap(ClientSize.Width, ClientSize.Height))
			{
				DrawToBitmap(bmp, new Rectangle(Point.Empty, ClientSize));
				bmp.Save(prefix + "_" + (n + 1) + ".png", System.Drawing.Imaging.ImageFormat.Png);
			}
		}
	}
}
#endif
