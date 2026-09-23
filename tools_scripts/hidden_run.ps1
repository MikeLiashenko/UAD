<#
  Runs a command on a separate, never-shown Windows desktop ("UADCapture" in the user's window
  station): its windows cannot appear on the screen, in the taskbar or take the keyboard focus,
  yet they keep the GPU. Used to render screenshots of the game (tools_scripts/shots.sh).
  Output goes to -Log; the exit code is the command's.
    powershell -File tools_scripts/hidden_run.ps1 -Command '"C:\x\godot.exe" --path .' -Log out.txt
#>
param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$Log,
    [string]$Dir = (Get-Location).Path,
    [int]$TimeoutSec = 300
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class UadHiddenDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr mode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool CloseDesktop(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags,
        IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@

$GENERIC_ALL = [uint32]0x10000000
$desk = [UadHiddenDesktop]::CreateDesktop('UADCapture', [IntPtr]::Zero, [IntPtr]::Zero, 0, $GENERIC_ALL, [IntPtr]::Zero)
if ($desk -eq [IntPtr]::Zero) { Write-Error "CreateDesktop failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 90 }
try {
    $si = New-Object UadHiddenDesktop+STARTUPINFO
    $si.cb = [Runtime.InteropServices.Marshal]::SizeOf([type][UadHiddenDesktop+STARTUPINFO])
    $si.lpDesktop = 'WinSta0\UADCapture'
    $pi = New-Object UadHiddenDesktop+PROCESS_INFORMATION
    $cmdExe = [IO.Path]::Combine([Environment]::SystemDirectory, 'cmd.exe')
    $cmdline = "`"$cmdExe`" /d /c `"$Command > `"$Log`" 2>&1`""
    $ok = [UadHiddenDesktop]::CreateProcess($cmdExe, $cmdline, [IntPtr]::Zero, [IntPtr]::Zero, $false, 0, [IntPtr]::Zero, $Dir, [ref]$si, [ref]$pi)
    if (-not $ok) { Write-Error "CreateProcess failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error()) (app $cmdExe, dir $Dir)"; exit 91 }
    $r = [UadHiddenDesktop]::WaitForSingleObject($pi.hProcess, [uint32]($TimeoutSec * 1000))
    if ($r -ne 0) {
        # stop the whole tree started here (cmd, the console wrapper, the game) and nothing else
        taskkill.exe /T /F /PID $pi.dwProcessId | Out-Null
    }
    $code = [uint32]0
    [UadHiddenDesktop]::GetExitCodeProcess($pi.hProcess, [ref]$code) | Out-Null
    [UadHiddenDesktop]::CloseHandle($pi.hProcess) | Out-Null
    [UadHiddenDesktop]::CloseHandle($pi.hThread) | Out-Null
    exit [int]$code
} finally {
    [UadHiddenDesktop]::CloseDesktop($desk) | Out-Null
}
