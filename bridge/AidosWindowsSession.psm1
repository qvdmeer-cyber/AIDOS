Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Initialize-AidosWindowsSessionNative {
    if(-not $IsWindows){ throw 'Windows interactive session inspection is Windows-only.' }
    if(-not ('AidosNativeSessionV2' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public enum AidosWtsConnectStateV2 : int {
    Active=0, Connected=1, ConnectQuery=2, Shadow=3, Disconnected=4,
    Idle=5, Listen=6, Reset=7, Down=8, Init=9
}

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct AidosWtsInfoExLevel1V2 {
    public UInt32 SessionId;
    public AidosWtsConnectStateV2 SessionState;
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
public struct AidosWtsInfoExV2 {
    public UInt32 Level;
    public AidosWtsInfoExLevel1V2 Data;
}

public sealed class AidosSessionSnapshotNativeV2 {
    public bool ProcessSessionOk;
    public UInt32 SessionId;
    public UInt32 ActiveConsoleSessionId;
    public bool InfoExOk;
    public int ConnectionState = -1;
    public int SessionFlags = -1;
    public bool ProtocolOk;
    public int ProtocolType = -1;
    public bool InputDesktopAvailable;
    public string UserName;
    public string DomainName;
    public string WinStationName;
    public string Error;
}

public static class AidosNativeSessionV2 {
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ProcessIdToSessionId(UInt32 processId, out UInt32 sessionId);
    [DllImport("kernel32.dll")] static extern UInt32 WTSGetActiveConsoleSessionId();
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool WTSQuerySessionInformationW(IntPtr server, UInt32 sessionId, int infoClass, out IntPtr buffer, out UInt32 bytesReturned);
    [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr memory);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr OpenInputDesktop(UInt32 flags, bool inherit, UInt32 desiredAccess);
    [DllImport("user32.dll", SetLastError=true)] static extern bool CloseDesktop(IntPtr desktop);

    static string QueryString(UInt32 sessionId, int infoClass) {
        IntPtr p; UInt32 bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, infoClass, out p, out bytes)) return null;
        try { return p == IntPtr.Zero ? null : Marshal.PtrToStringUni(p); }
        finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }

    static bool TryQueryProtocol(UInt32 sessionId, out int protocol) {
        protocol = -1; IntPtr p; UInt32 bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, 16, out p, out bytes)) return false;
        try {
            if(p == IntPtr.Zero || bytes < 2) return false;
            protocol = (UInt16)Marshal.ReadInt16(p);
            return true;
        }
        finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }

    static bool TryQueryInfoEx(UInt32 sessionId, out AidosWtsInfoExV2 info) {
        info = new AidosWtsInfoExV2(); IntPtr p; UInt32 bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, 25, out p, out bytes)) return false;
        try {
            if(p == IntPtr.Zero || bytes < Marshal.SizeOf(typeof(AidosWtsInfoExV2))) return false;
            info = (AidosWtsInfoExV2)Marshal.PtrToStructure(p, typeof(AidosWtsInfoExV2));
            return info.Level == 1;
        }
        finally { if(p != IntPtr.Zero) WTSFreeMemory(p); }
    }

    public static AidosSessionSnapshotNativeV2 Inspect(UInt32 processId) {
        var result = new AidosSessionSnapshotNativeV2();
        try {
            UInt32 sid;
            result.ProcessSessionOk = ProcessIdToSessionId(processId, out sid);
            if(!result.ProcessSessionOk) {
                result.Error = "ProcessIdToSessionId failed with Win32 error " + Marshal.GetLastWin32Error();
                return result;
            }
            result.SessionId = sid;
            result.ActiveConsoleSessionId = WTSGetActiveConsoleSessionId();

            AidosWtsInfoExV2 info;
            result.InfoExOk = TryQueryInfoEx(sid, out info);
            if(result.InfoExOk) {
                result.ConnectionState = (int)info.Data.SessionState;
                result.SessionFlags = info.Data.SessionFlags;
                result.WinStationName = info.Data.WinStationName;
                result.UserName = info.Data.UserName;
                result.DomainName = info.Data.DomainName;
            }

            int protocol;
            result.ProtocolOk = TryQueryProtocol(sid, out protocol);
            if(result.ProtocolOk) result.ProtocolType = protocol;

            if(String.IsNullOrWhiteSpace(result.UserName)) result.UserName = QueryString(sid,5);
            if(String.IsNullOrWhiteSpace(result.DomainName)) result.DomainName = QueryString(sid,7);
            if(String.IsNullOrWhiteSpace(result.WinStationName)) result.WinStationName = QueryString(sid,6);

            IntPtr desktop = OpenInputDesktop(0,false,0x0101);
            result.InputDesktopAvailable = desktop != IntPtr.Zero;
            if(desktop != IntPtr.Zero) CloseDesktop(desktop);
            return result;
        }
        catch(Exception ex) {
            result.Error = ex.GetType().Name + ": " + ex.Message;
            return result;
        }
    }
}
'@
    }
}

function Get-AidosInteractiveSessionSnapshot {
    [CmdletBinding()]
    param()
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    if(-not $IsWindows){
        return [pscustomobject]@{
            observed_at=$now; session_id=$null; process_session_id=$null; active_console_session_id=$null
            connection_state='UNKNOWN'; lock_state='UNKNOWN'; session_kind='UNKNOWN'; protocol_type=$null
            input_desktop_available=$false; user_name=$null; domain_name=$null; winstation_name=$null
            observation_status='ERROR'; error='WINDOWS_REQUIRED'
        }
    }
    try {
        Initialize-AidosWindowsSessionNative
        $native=[AidosNativeSessionV2]::Inspect([uint32][System.Diagnostics.Process]::GetCurrentProcess().Id)
        $connection=switch([int]$native.ConnectionState){
            0 {'ACTIVE'}; 1 {'CONNECTED'}; 2 {'CONNECTQUERY'}; 3 {'SHADOW'}; 4 {'DISCONNECTED'}
            5 {'IDLE'}; 6 {'LISTEN'}; 7 {'RESET'}; 8 {'DOWN'}; 9 {'INIT'}; default {'UNKNOWN'}
        }
        $lock=switch([int]$native.SessionFlags){ 0 {'LOCKED'}; 1 {'UNLOCKED'}; default {'UNKNOWN'} }
        $kind=switch([int]$native.ProtocolType){ 0 {'CONSOLE'}; 2 {'RDP'}; default {'UNKNOWN'} }
        $complete=[bool]$native.ProcessSessionOk -and [bool]$native.InfoExOk -and [bool]$native.ProtocolOk
        [pscustomobject]@{
            observed_at=$now
            session_id=if($native.ProcessSessionOk){[int]$native.SessionId}else{$null}
            process_session_id=if($native.ProcessSessionOk){[int]$native.SessionId}else{$null}
            active_console_session_id=if($native.ProcessSessionOk){[uint32]$native.ActiveConsoleSessionId}else{$null}
            connection_state=$connection
            lock_state=$lock
            session_kind=$kind
            protocol_type=if($native.ProtocolOk){[int]$native.ProtocolType}else{$null}
            input_desktop_available=[bool]$native.InputDesktopAvailable
            user_name=[string]$native.UserName
            domain_name=[string]$native.DomainName
            winstation_name=[string]$native.WinStationName
            observation_status=if($complete){'OK'}elseif($native.ProcessSessionOk){'PARTIAL'}else{'ERROR'}
            error=[string]$native.Error
        }
    } catch {
        [pscustomobject]@{
            observed_at=$now; session_id=$null; process_session_id=$null; active_console_session_id=$null
            connection_state='UNKNOWN'; lock_state='UNKNOWN'; session_kind='UNKNOWN'; protocol_type=$null
            input_desktop_available=$false; user_name=$null; domain_name=$null; winstation_name=$null
            observation_status='ERROR'; error=$_.Exception.Message
        }
    }
}

function Test-AidosInteractiveSessionPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$Policy='SUPERVISED'
    )
    $reason='NONE'
    if(-not $Snapshot -or [string]$Snapshot.observation_status -ne 'OK'){ $reason='SESSION_STATE_UNKNOWN' }
    elseif([string]$Snapshot.connection_state -ne 'ACTIVE'){ $reason=if([string]$Snapshot.connection_state -eq 'DISCONNECTED'){'SESSION_DISCONNECTED'}else{'NO_INTERACTIVE_SESSION'} }
    elseif([string]$Snapshot.lock_state -eq 'LOCKED'){ $reason='SESSION_LOCKED' }
    elseif([string]$Snapshot.lock_state -ne 'UNLOCKED'){ $reason='SESSION_STATE_UNKNOWN' }
    elseif([string]$Snapshot.session_kind -notin @('CONSOLE','RDP')){ $reason='SESSION_STATE_UNKNOWN' }
    elseif(-not [bool]$Snapshot.input_desktop_available){ $reason='INPUT_DESKTOP_UNAVAILABLE' }
    [pscustomobject]@{
        allowed=($reason -eq 'NONE')
        policy=$Policy
        reason=$reason
        snapshot=$Snapshot
    }
}

function Wait-AidosInteractiveSession {
    [CmdletBinding()]
    param(
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$Policy='SUPERVISED',
        [int]$PollSeconds=2,
        [int]$TimeoutSeconds=0,
        [scriptblock]$SnapshotProvider
    )
    if($PollSeconds -lt 1){ $PollSeconds=1 }
    $started=[DateTimeOffset]::UtcNow
    while($true){
        $snapshot=if($SnapshotProvider){ & $SnapshotProvider }else{ Get-AidosInteractiveSessionSnapshot }
        $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $Policy
        if($decision.allowed){ return $decision }
        if($TimeoutSeconds -gt 0 -and ([DateTimeOffset]::UtcNow-$started).TotalSeconds -ge $TimeoutSeconds){ return $decision }
        Start-Sleep -Seconds $PollSeconds
    }
}

Export-ModuleMember -Function Get-AidosInteractiveSessionSnapshot,Test-AidosInteractiveSessionPolicy,Wait-AidosInteractiveSession
