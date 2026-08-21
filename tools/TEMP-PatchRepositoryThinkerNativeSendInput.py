from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)

binding_path = Path('bridge/AidosRepositoryThinkerBinding.psm1')
binding = binding_path.read_text(encoding='utf-8')

anchor = 'function Find-AidosRepositoryThinkerSubmitElement {'
helper = r'''function Initialize-AidosRepositoryThinkerNativeInput {
    [CmdletBinding()]
    param()
    if('AidosRepositoryThinkerNativeInputV1' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class AidosRepositoryThinkerNativeInputV1 {
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT {
        public uint type;
        public INPUTUNION U;
    }

    [DllImport("user32.dll", SetLastError=true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private static INPUT Keyboard(ushort vk, uint flags) {
        return new INPUT {
            type = INPUT_KEYBOARD,
            U = new INPUTUNION {
                ki = new KEYBDINPUT {
                    wVk = vk,
                    wScan = 0,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };
    }

    private static void Send(INPUT[] inputs) {
        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        if(sent != (uint)inputs.Length) {
            int error = Marshal.GetLastWin32Error();
            throw new Win32Exception(error, "SendInput accepted " + sent + " of " + inputs.Length + " keyboard events.");
        }
    }

    public static void SendChord(ushort modifier, ushort key) {
        Send(new INPUT[] {
            Keyboard(modifier, 0),
            Keyboard(key, 0),
            Keyboard(key, KEYEVENTF_KEYUP),
            Keyboard(modifier, KEYEVENTF_KEYUP)
        });
    }

    public static void SendKey(ushort key) {
        Send(new INPUT[] {
            Keyboard(key, 0),
            Keyboard(key, KEYEVENTF_KEYUP)
        });
    }
}
'@
}
function Invoke-AidosRepositoryThinkerNativeChord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][UInt16]$Modifier,[Parameter(Mandatory)][UInt16]$Key)
    Initialize-AidosRepositoryThinkerNativeInput
    [AidosRepositoryThinkerNativeInputV1]::SendChord($Modifier,$Key)
}
function Invoke-AidosRepositoryThinkerNativeKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][UInt16]$Key)
    Initialize-AidosRepositoryThinkerNativeInput
    [AidosRepositoryThinkerNativeInputV1]::SendKey($Key)
}

'''
if 'function Initialize-AidosRepositoryThinkerNativeInput {' not in binding:
    binding = replace_once(binding, anchor, helper + anchor, 'native input helper anchor')

binding = replace_once(
    binding,
    "    if(-not('System.Windows.Forms.SendKeys' -as [type])){Add-Type -AssemblyName System.Windows.Forms}\n",
    '',
    'remove Windows Forms SendKeys dependency',
)

binding = replace_once(
    binding,
    "    [System.Windows.Forms.SendKeys]::SendWait('^a')\n    Start-Sleep -Milliseconds 50\n    [System.Windows.Forms.SendKeys]::SendWait('^v')",
    "    Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x41\n    Start-Sleep -Milliseconds 50\n    Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x56",
    'native Ctrl+A/Ctrl+V hydration',
)

binding = replace_once(
    binding,
    "        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')\n        $sendMethod='KEYBOARD_ENTER'",
    "        Invoke-AidosRepositoryThinkerNativeKey -Key 0x0D\n        $sendMethod='NATIVE_SENDINPUT_ENTER'",
    'native Enter fallback',
)

binding_path.write_text(binding, encoding='utf-8')

test_path = Path('tests/RepositoryThinkerBinding.Tests.ps1')
test = test_path.read_text(encoding='utf-8')

old = '''Assert-Binding ($bindingSource.Contains("[System.Windows.Forms.SendKeys]::SendWait('^a')") -and $bindingSource.Contains("[System.Windows.Forms.SendKeys]::SendWait('^v')")) 'Repository Thinker rehydrates the composer through real keyboard/clipboard input events'\n'''
new = '''Assert-Binding ($bindingSource.Contains('[DllImport("user32.dll", SetLastError=true)]') -and $bindingSource.Contains('private static extern uint SendInput')) 'Repository Thinker uses native Win32 SendInput for keyboard injection'\nAssert-Binding ($bindingSource.Contains('Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x41') -and $bindingSource.Contains('Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x56')) 'Repository Thinker hydrates the composer with native Ctrl+A and Ctrl+V keyboard events'\nAssert-Binding (-not$bindingSource.Contains('System.Windows.Forms.SendKeys') -and -not$bindingSource.Contains('SendWait(')) 'Repository Thinker no longer depends on unstable Windows Forms SendKeys'\n'''
test = replace_once(test, old, new, 'native hydration regression')

old_enter = '''Assert-Binding ($bindingSource.Contains("SendWait('{ENTER}')")) 'Repository Thinker has a keyboard Enter fallback after exact composer proof'\n'''
new_enter = '''Assert-Binding ($bindingSource.Contains('Invoke-AidosRepositoryThinkerNativeKey -Key 0x0D') -and $bindingSource.Contains("sendMethod='NATIVE_SENDINPUT_ENTER'")) 'Repository Thinker has a native SendInput Enter fallback after exact composer proof'\nAssert-Binding ($bindingSource.Contains('if(sent != (uint)inputs.Length)') -and $bindingSource.Contains('Marshal.GetLastWin32Error()')) 'Repository Thinker fails closed unless Windows accepts every native keyboard event'\n'''
test = replace_once(test, old_enter, new_enter, 'native Enter regression')

test_path.write_text(test, encoding='utf-8')
