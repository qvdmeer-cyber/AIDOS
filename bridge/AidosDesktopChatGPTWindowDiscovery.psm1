Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Initialize-AidosDesktopChatGPTWindowDiscovery {
    if(-not [OperatingSystem]::IsWindows()){throw 'Desktop ChatGPT window discovery is Windows-only.'}
    if(-not ('AidosWindowDiscoveryV1' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AidosWindowDiscoveryV1 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)] public static extern int GetWindowTextW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)] public static extern int GetClassNameW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
}
'@
    }
    if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
}

function Get-AidosWindowDiscoveryText {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    $sb=New-Object System.Text.StringBuilder 2048
    [void][AidosWindowDiscoveryV1]::GetWindowTextW($WindowHandle,$sb,$sb.Capacity)
    $sb.ToString()
}

function Get-AidosWindowDiscoveryClass {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    $sb=New-Object System.Text.StringBuilder 256
    [void][AidosWindowDiscoveryV1]::GetClassNameW($WindowHandle,$sb,$sb.Capacity)
    $sb.ToString()
}

function Get-AidosDesktopChatGPTFallbackProcessContexts {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic')
    Initialize-AidosDesktopChatGPTWindowDiscovery
    $sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $processes=@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $sessionId})
    if($processes.Count-eq0){return @()}
    $byPid=@{}
    foreach($process in $processes){$byPid[[int]$process.Id]=$process}
    $handles=[Collections.Generic.List[IntPtr]]::new()
    $callback=[AidosWindowDiscoveryV1+EnumWindowsProc]{
        param([IntPtr]$hWnd,[IntPtr]$lParam)
        $pid=0
        [void][AidosWindowDiscoveryV1]::GetWindowThreadProcessId($hWnd,[ref]$pid)
        if($byPid.ContainsKey([int]$pid)){$handles.Add($hWnd)}
        return $true
    }.GetNewClosure()
    [void][AidosWindowDiscoveryV1]::EnumWindows($callback,[IntPtr]::Zero)
    $contexts=[Collections.Generic.List[object]]::new()
    foreach($handle in @($handles)){
        $pid=0;[void][AidosWindowDiscoveryV1]::GetWindowThreadProcessId($handle,[ref]$pid)
        $process=$byPid[[int]$pid]
        if(-not$process){continue}
        if(-not[AidosWindowDiscoveryV1]::IsWindowVisible($handle)){continue}
        $windowText=Get-AidosWindowDiscoveryText $handle
        $windowClass=Get-AidosWindowDiscoveryClass $handle
        if([string]::IsNullOrWhiteSpace($windowText)-or$windowClass-ne'Chrome_WidgetWin_1'){continue}
        try{$uia=[Windows.Automation.AutomationElement]::FromHandle($handle)}catch{$uia=$null}
        if(-not$uia){continue}
        $uiaPid=[int]$uia.Current.ProcessId
        $uiaHandle=[int64]$uia.Current.NativeWindowHandle
        $uiaClass=[string]$uia.Current.ClassName
        $uiaType=[string]$uia.Current.ControlType.ProgrammaticName
        $uiaName=[string]$uia.Current.Name
        $typeOk=($uiaType -match '(^|\.|:)Window$' -or $uiaType -match 'Window$')
        $titleOk=(-not[string]::IsNullOrWhiteSpace($uiaName) -and [string]::Equals($uiaName,$windowText,[StringComparison]::Ordinal))
        $usable=([int]$process.SessionId-eq$sessionId -and $uiaPid-eq[int]$process.Id -and $uiaHandle-eq[int64]$handle.ToInt64() -and $uiaClass-eq$windowClass -and $typeOk -and $titleOk)
        if(-not$usable){continue}
        $contexts.Add([pscustomobject][ordered]@{
            present=$true;process_id=[int]$process.Id;process_name=[string]$process.ProcessName;session_id=[int]$process.SessionId;
            main_window_handle=[string](([IntPtr]$process.MainWindowHandle).ToInt64());window_handle=[string]$handle.ToInt64();window_title=$windowText;window_class_name=$windowClass;
            window_is_minimized=[AidosWindowDiscoveryV1]::IsIconic($handle);window_is_foreground=([AidosWindowDiscoveryV1]::GetForegroundWindow()-eq$handle);window_is_visible=$true;
            window_source='EnumWindowsFallback';uia_process_id=$uiaPid;uia_native_window_handle=[string]$uiaHandle;uia_class_name=$uiaClass;uia_control_type=$uiaType;uia_name=$uiaName;
            usable_application_window=$true;proof_reason='Accepted EnumWindows fallback shell candidate.';proof_failures=@()
        })
    }
    @($contexts)
}

function Get-AidosDesktopChatGPTResilientProcessContext {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic',[scriptblock]$PrimaryResolver)
    if($PrimaryResolver){
        try{$primary=& $PrimaryResolver $ProcessName;if($primary){return $primary}}catch{$primaryError=$_.Exception.Message}
    }elseif(Get-Command Get-AidosDesktopChatGPTProcessContext -ErrorAction SilentlyContinue){
        try{$primary=Get-AidosDesktopChatGPTProcessContext -ProcessName $ProcessName;if($primary){return $primary}}catch{$primaryError=$_.Exception.Message}
    }
    $fallback=@(Get-AidosDesktopChatGPTFallbackProcessContexts -ProcessName $ProcessName)
    if($fallback.Count-eq1){return $fallback[0]}
    if($fallback.Count-gt1){
        $details=($fallback|ForEach-Object{"pid=$($_.process_id);handle=$($_.window_handle);title=$($_.window_title)"})-join' | '
        throw "Multiple fallback ChatGPT shell windows were discovered: $details"
    }
    if([string]::IsNullOrWhiteSpace([string]$primaryError)){$primaryError='Primary ChatGPT shell discovery returned no usable window.'}
    throw "ChatGPT shell discovery failed. Primary: $primaryError Fallback: no exact PID/session/UIA-bound visible shell candidate."
}

Export-ModuleMember -Function Initialize-AidosDesktopChatGPTWindowDiscovery,Get-AidosDesktopChatGPTFallbackProcessContexts,Get-AidosDesktopChatGPTResilientProcessContext
