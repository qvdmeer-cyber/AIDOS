[CmdletBinding()]
param(
    [string]$ProcessName='ChatGPT'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){ throw 'Desktop session topology probe is Windows-only.' }

if(-not ('AidosSessionTopologyNativeV1' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public enum AidosTopoState : int {
    Active=0, Connected=1, ConnectQuery=2, Shadow=3, Disconnected=4,
    Idle=5, Listen=6, Reset=7, Down=8, Init=9
}

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct AidosTopoSessionInfo {
    public Int32 SessionId;
    [MarshalAs(UnmanagedType.LPWStr)] public string WinStationName;
    public AidosTopoState State;
}

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct AidosTopoInfoExLevel1 {
    public UInt32 SessionId;
    public AidosTopoState SessionState;
    public Int32 SessionFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=33)] public string WinStationName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=21)] public string UserName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=18)] public string DomainName;
    public Int64 LogonTime;
    public Int64 ConnectTime;
    public Int64 DisconnectTime;
    public Int64 LastInputTime;
    public Int64 CurrentTime;
    public UInt32 IncomingBytes;
    public UInt32 OutgoingBytes;
    public UInt32 IncomingFrames;
    public UInt32 OutgoingFrames;
    public UInt32 IncomingCompressedBytes;
    public UInt32 OutgoingCompressedBytes;
}

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct AidosTopoInfoEx {
    public UInt32 Level;
    public AidosTopoInfoExLevel1 Data;
}

public sealed class AidosTopoSession {
    public int SessionId;
    public string ConnectionState;
    public string WinStationName;
    public string UserName;
    public string DomainName;
    public int ProtocolType=-1;
    public string LockState="UNKNOWN";
    public bool InfoExOk;
}

public static class AidosSessionTopologyNativeV1 {
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WTSEnumerateSessionsW(IntPtr server, int reserved, int version, out IntPtr sessions, out int count);
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WTSQuerySessionInformationW(IntPtr server, int sessionId, int infoClass, out IntPtr buffer, out int bytesReturned);
    [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr memory);
    [DllImport("kernel32.dll")] public static extern UInt32 WTSGetActiveConsoleSessionId();

    static string QueryString(int sessionId, int infoClass) {
        IntPtr p; int bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, infoClass, out p, out bytes)) return null;
        try { return p == IntPtr.Zero ? null : Marshal.PtrToStringUni(p); }
        finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }

    static int QueryProtocol(int sessionId) {
        IntPtr p; int bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, 16, out p, out bytes)) return -1;
        try { return (p == IntPtr.Zero || bytes < 2) ? -1 : (UInt16)Marshal.ReadInt16(p); }
        finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }

    static bool QueryInfoEx(int sessionId, out AidosTopoInfoEx info) {
        info = new AidosTopoInfoEx(); IntPtr p; int bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, 25, out p, out bytes)) return false;
        try {
            if(p == IntPtr.Zero || bytes < Marshal.SizeOf(typeof(AidosTopoInfoEx))) return false;
            info=(AidosTopoInfoEx)Marshal.PtrToStructure(p,typeof(AidosTopoInfoEx));
            return info.Level == 1;
        } finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }

    public static AidosTopoSession[] Enumerate() {
        IntPtr p; int count;
        if(!WTSEnumerateSessionsW(IntPtr.Zero,0,1,out p,out count))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try {
            var result=new List<AidosTopoSession>();
            int size=Marshal.SizeOf(typeof(AidosTopoSessionInfo));
            for(int i=0;i<count;i++) {
                var item=(AidosTopoSessionInfo)Marshal.PtrToStructure(IntPtr.Add(p,i*size),typeof(AidosTopoSessionInfo));
                var s=new AidosTopoSession();
                s.SessionId=item.SessionId;
                s.ConnectionState=item.State.ToString().ToUpperInvariant();
                s.WinStationName=item.WinStationName;
                s.UserName=QueryString(item.SessionId,5);
                s.DomainName=QueryString(item.SessionId,7);
                s.ProtocolType=QueryProtocol(item.SessionId);
                AidosTopoInfoEx ex;
                s.InfoExOk=QueryInfoEx(item.SessionId,out ex);
                if(s.InfoExOk) {
                    s.LockState=ex.Data.SessionFlags==0 ? "LOCKED" : (ex.Data.SessionFlags==1 ? "UNLOCKED" : "UNKNOWN");
                    if(String.IsNullOrWhiteSpace(s.WinStationName)) s.WinStationName=ex.Data.WinStationName;
                    if(String.IsNullOrWhiteSpace(s.UserName)) s.UserName=ex.Data.UserName;
                    if(String.IsNullOrWhiteSpace(s.DomainName)) s.DomainName=ex.Data.DomainName;
                }
                result.Add(s);
            }
            return result.ToArray();
        } finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }
}
'@
}

$current=[System.Diagnostics.Process]::GetCurrentProcess()
$consoleId=[uint32][AidosSessionTopologyNativeV1]::WTSGetActiveConsoleSessionId()
$chatgpt=@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        process_id=$_.Id
        session_id=$_.SessionId
        main_window_handle=[int64]$_.MainWindowHandle
        main_window_title=[string]$_.MainWindowTitle
        has_main_window=([int64]$_.MainWindowHandle -ne 0)
    }
})

$sessions=@([AidosSessionTopologyNativeV1]::Enumerate() | ForEach-Object {
    $kind=switch([int]$_.ProtocolType){0{'CONSOLE'};2{'RDP'};default{'UNKNOWN'}}
    [pscustomobject]@{
        session_id=[int]$_.SessionId
        is_physical_console=([uint32]$_.SessionId -eq $consoleId)
        is_current_process_session=([int]$_.SessionId -eq [int]$current.SessionId)
        connection_state=[string]$_.ConnectionState
        lock_state=[string]$_.LockState
        session_kind=$kind
        protocol_type=if($_.ProtocolType -ge 0){[int]$_.ProtocolType}else{$null}
        user_name=[string]$_.UserName
        domain_name=[string]$_.DomainName
        winstation_name=[string]$_.WinStationName
        chatgpt_processes=@($chatgpt | Where-Object session_id -eq [int]$_.SessionId)
    }
})

$console=@($sessions | Where-Object is_physical_console | Select-Object -First 1)
$currentSession=@($sessions | Where-Object is_current_process_session | Select-Object -First 1)
$recommendation='INSPECT_REQUIRED'
if($console.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$console[0].user_name)){
    if([string]$console[0].lock_state -eq 'UNLOCKED'){
        $recommendation='CONSOLE_INTERACTIVE_AGENT_CANDIDATE'
    } elseif([string]$console[0].lock_state -eq 'LOCKED'){
        $recommendation='CONSOLE_PRESENT_BUT_LOCKED'
    }
} elseif($console.Count -eq 1){
    $recommendation='NO_USER_LOGGED_ON_AT_CONSOLE'
}

[pscustomobject]@{
    observed_at=[DateTimeOffset]::UtcNow.ToString('o')
    machine_name=$env:COMPUTERNAME
    current_user="$env:USERDOMAIN\$env:USERNAME"
    current_process_id=$current.Id
    current_process_session_id=$current.SessionId
    active_console_session_id=if($consoleId -eq [uint32]::MaxValue){$null}else{[int]$consoleId}
    recommendation=$recommendation
    sessions=$sessions
    invariants=[pscustomobject]@{
        rdp_must_not_own_runtime=$true
        local_agent_requires_existing_interactive_token=$true
        locked_session_blocks_desktop_actions=$true
        noninteractive_task_is_not_valid_for_chatgpt_uia=$true
    }
} | ConvertTo-Json -Depth 20
