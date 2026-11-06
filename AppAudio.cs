using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

// Per-app mute using the same Windows audio sessions the volume mixer shows.
public static class AppAudio {
    const int RenderDevices = 0, ActiveDevices = 1, AllContexts = 23, SessionIdle = 0, SessionActive = 1;

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class DeviceEnumerator {}

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int flow, int state, out IMMDeviceCollection devices);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object result);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        [PreserveSig] int GetAudioSessionControl(IntPtr group, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr group, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr context);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr context);
        [PreserveSig] int GetGroupingParam(out Guid group);
        [PreserveSig] int SetGroupingParam(ref Guid group, IntPtr context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out uint pid);
        [PreserveSig] int IsSystemSoundsSession();
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume {
        [PreserveSig] int SetMasterVolume(float level, IntPtr context);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, IntPtr context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    static IEnumerable<IAudioSessionControl2> Sessions() {
        var enumerator = (IMMDeviceEnumerator)new DeviceEnumerator();
        IMMDeviceCollection devices;
        Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(RenderDevices, ActiveDevices, out devices));
        int deviceCount;
        devices.GetCount(out deviceCount);
        for (int d = 0; d < deviceCount; d++) {
            IMMDevice device;
            if (devices.Item(d, out device) != 0) continue;
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object manager;
            if (device.Activate(ref iid, AllContexts, IntPtr.Zero, out manager) != 0) continue;
            IAudioSessionEnumerator sessions;
            if (((IAudioSessionManager2)manager).GetSessionEnumerator(out sessions) != 0) continue;
            int sessionCount;
            sessions.GetCount(out sessionCount);
            for (int s = 0; s < sessionCount; s++) {
                IAudioSessionControl2 session;
                if (sessions.GetSession(s, out session) == 0) yield return session;
            }
        }
    }

    // The app behind a session, or null for Windows' own sounds. It comes from the session's identifier,
    // {device}|\Device\HarddiskVolume3\...\brave.exe%b{guid}, so it still works after the app has closed.
    static string AppName(IAudioSessionControl2 session) {
        IntPtr text;
        if (session.IsSystemSoundsSession() == 0 || session.GetSessionIdentifier(out text) != 0) return null;
        string id = Marshal.PtrToStringUni(text);
        Marshal.FreeCoTaskMem(text);
        int end = id.LastIndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        if (end < 0) return null;
        int start = id.LastIndexOf('\\', end) + 1;
        return id.Substring(start, end - start);
    }

    // Mutes these apps and returns the ones it changed, so an app you muted yourself stays muted afterwards.
    public static string[] Mute(string[] apps) {
        var names = new HashSet<string>(apps, StringComparer.OrdinalIgnoreCase);
        var changed = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var session in Sessions()) {
            string app = AppName(session);
            var volume = session as ISimpleAudioVolume;
            if (app == null || volume == null || !names.Contains(app)) continue;
            bool muted;
            if (volume.GetMute(out muted) == 0 && !muted && volume.SetMute(true, IntPtr.Zero) == 0) changed.Add(app);
        }
        return new List<string>(changed).ToArray();
    }

    public static void Unmute(string[] apps) {
        var names = new HashSet<string>(apps, StringComparer.OrdinalIgnoreCase);
        foreach (var session in Sessions()) {
            string app = AppName(session);
            var volume = session as ISimpleAudioVolume;
            if (app != null && volume != null && names.Contains(app)) volume.SetMute(false, IntPtr.Zero);
        }
    }

    // Apps that are playing right now and aren't muted.
    public static string[] AudibleApps() {
        var apps = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var session in Sessions()) {
            string app = AppName(session);
            var volume = session as ISimpleAudioVolume;
            int state;
            bool muted;
            if (app != null && volume != null && session.GetState(out state) == 0 && state == SessionActive
                && volume.GetMute(out muted) == 0 && !muted) apps.Add(app);
        }
        return new List<string>(apps).ToArray();
    }

    // One line per session, for checking what the volume mixer holds.
    public static string[] Describe() {
        var lines = new List<string>();
        foreach (var session in Sessions()) {
            var volume = session as ISimpleAudioVolume;
            int state;
            bool muted = false;
            session.GetState(out state);
            if (volume != null) volume.GetMute(out muted);
            lines.Add((AppName(session) ?? "(system)") + ": " + (state == SessionActive ? "playing" : state == SessionIdle ? "idle" : "closed") + (muted ? ", muted" : ""));
        }
        return lines.ToArray();
    }
}
