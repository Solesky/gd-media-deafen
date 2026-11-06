using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// Watches for a key or key combination anywhere in Windows using Raw Input, which only observes: keys still
// reach the app they were meant for. Every other key is ignored, and nothing is recorded.
public class RawKeyWatcher : NativeWindow {
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort UsagePage, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint Type, Size; public IntPtr Device, WParam; }
    [StructLayout(LayoutKind.Sequential)] struct RAWKEYBOARD { public ushort MakeCode, Flags, Reserved, VKey; public uint Msg, Extra; }

    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);
    [DllImport("user32.dll")] static extern uint MsgWaitForMultipleObjectsEx(uint count, IntPtr handles, uint ms, uint wake, uint flags);

    const int WM_INPUT = 0xFF;
    const uint RID_INPUT = 0x10000003, RIDEV_INPUTSINK = 0x100, QS_ALLINPUT = 0x4FF, MWMO_INPUTAVAILABLE = 4;

    readonly HashSet<int> keys = new HashSet<int>();
    readonly HashSet<int> held = new HashSet<int>();
    bool allHeld;
    int presses;

    public RawKeyWatcher(int[] virtualKeys) {
        foreach (int key in virtualKeys) keys.Add(Normalize(key));
        CreateHandle(new CreateParams());
        var device = new RAWINPUTDEVICE { UsagePage = 1, Usage = 6, Flags = RIDEV_INPUTSINK, Target = Handle };
        if (!RegisterRawInputDevices(new[] { device }, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) throw new Win32Exception();
    }

    // Left and right Shift, Ctrl and Alt count as the same key.
    static int Normalize(int key) {
        return key >= 0xA0 && key <= 0xA5 ? 0x10 + (key - 0xA0) / 2 : key;
    }

    // Waits up to ms for input and returns how many presses arrived.
    public int Wait(int ms) {
        MsgWaitForMultipleObjectsEx(0, IntPtr.Zero, (uint)ms, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        Application.DoEvents();
        int count = presses;
        presses = 0;
        return count;
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_INPUT) ReadKey(m.LParam);
        base.WndProc(ref m);
    }

    void ReadKey(IntPtr input) {
        uint header = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER)), size = 0;
        GetRawInputData(input, RID_INPUT, IntPtr.Zero, ref size, header);
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try {
            if (GetRawInputData(input, RID_INPUT, buffer, ref size, header) != size) return;
            var keyboard = (RAWKEYBOARD)Marshal.PtrToStructure(buffer + (int)header, typeof(RAWKEYBOARD));
            int key = Normalize(keyboard.VKey);
            if (!keys.Contains(key)) return;
            if ((keyboard.Flags & 1) == 0) held.Add(key); else held.Remove(key);
            // A press is the moment every key of the combination is down, so holding it down counts once.
            bool all = held.Count == keys.Count;
            if (all && !allHeld) presses++;
            allHeld = all;
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
    }
}
