using System.Runtime.InteropServices;

namespace PrintoCrypt.App.Services;

internal static class UserSessionProcessLauncher
{
    private const int WtsCurrentServerHandle = 0;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint CreateNoWindow = 0x08000000;

    public static bool TryLaunchInUserSession(
        string userName,
        string applicationPath,
        string? workingDirectory = null,
        string? arguments = null)
    {
        if (string.IsNullOrWhiteSpace(userName) ||
            string.IsNullOrWhiteSpace(applicationPath) ||
            !File.Exists(applicationPath))
        {
            return false;
        }

        var sessionId = FindActiveSessionId(userName);
        if (sessionId is null)
        {
            return false;
        }

        if (!NativeMethods.WTSQueryUserToken(sessionId.Value, out var userToken))
        {
            return false;
        }

        try
        {
            var commandLine = string.IsNullOrWhiteSpace(arguments)
                ? $"\"{applicationPath}\""
                : $"\"{applicationPath}\" {arguments}";
            var startInfo = new NativeMethods.StartupInfo
            {
                cb = Marshal.SizeOf<NativeMethods.StartupInfo>(),
                lpDesktop = "winsta0\\default"
            };

            var workingDir = string.IsNullOrWhiteSpace(workingDirectory)
                ? Path.GetDirectoryName(applicationPath)
                : workingDirectory;

            if (!NativeMethods.CreateEnvironmentBlock(out var environment, userToken, false))
            {
                return false;
            }

            try
            {
                var created = NativeMethods.CreateProcessAsUser(
                    userToken,
                    applicationPath,
                    commandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    CreateUnicodeEnvironment | CreateNoWindow,
                    environment,
                    workingDir,
                    ref startInfo,
                    out var processInfo);

                if (!created)
                {
                    return false;
                }

                NativeMethods.CloseHandle(processInfo.hThread);
                NativeMethods.CloseHandle(processInfo.hProcess);
                return true;
            }
            finally
            {
                NativeMethods.DestroyEnvironmentBlock(environment);
            }
        }
        finally
        {
            NativeMethods.CloseHandle(userToken);
        }
    }

    private static uint? FindActiveSessionId(string userName)
    {
        var (domain, account) = SplitAccountName(userName);
        var consoleSessionId = NativeMethods.WTSGetActiveConsoleSessionId();
        if (consoleSessionId != 0xFFFFFFFF &&
            SessionBelongsToUser(consoleSessionId, domain, account))
        {
            return consoleSessionId;
        }

        if (!NativeMethods.WTSEnumerateSessions(
                IntPtr.Zero,
                0,
                1,
                out var sessionInfo,
                out var sessionCount))
        {
            return null;
        }

        try
        {
            var entrySize = Marshal.SizeOf<NativeMethods.WtsSessionInfo>();
            for (var index = 0; index < sessionCount; index++)
            {
                var entryPtr = sessionInfo + (index * entrySize);
                var session = Marshal.PtrToStructure<NativeMethods.WtsSessionInfo>(entryPtr);
                if (session.State != NativeMethods.WtsConnectState.Active)
                {
                    continue;
                }

                if (SessionBelongsToUser(session.SessionId, domain, account))
                {
                    return session.SessionId;
                }
            }
        }
        finally
        {
            NativeMethods.WTSFreeMemory(sessionInfo);
        }

        return null;
    }

    private static bool SessionBelongsToUser(uint sessionId, string? expectedDomain, string expectedAccount)
    {
        if (!NativeMethods.WTSQuerySessionInformation(
                IntPtr.Zero,
                sessionId,
                NativeMethods.WtsInfoClass.UserName,
                out var userNamePtr,
                out _))
        {
            return false;
        }

        try
        {
            var sessionUser = Marshal.PtrToStringUni(userNamePtr);
            if (string.IsNullOrWhiteSpace(sessionUser))
            {
                return false;
            }

            if (sessionUser.Contains('\\', StringComparison.Ordinal))
            {
                var (domain, account) = SplitAccountName(sessionUser);
                return AccountMatches(domain, account, expectedDomain, expectedAccount);
            }

            return sessionUser.Equals(expectedAccount, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            NativeMethods.WTSFreeMemory(userNamePtr);
        }
    }

    private static (string? Domain, string Account) SplitAccountName(string userName)
    {
        var separatorIndex = userName.IndexOf('\\');
        if (separatorIndex < 0)
        {
            return (null, userName);
        }

        return (userName[..separatorIndex], userName[(separatorIndex + 1)..]);
    }

    private static bool AccountMatches(
        string? leftDomain,
        string leftAccount,
        string? rightDomain,
        string rightAccount)
    {
        if (!leftAccount.Equals(rightAccount, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(leftDomain) || string.IsNullOrWhiteSpace(rightDomain))
        {
            return true;
        }

        return leftDomain.Equals(rightDomain, StringComparison.OrdinalIgnoreCase) ||
               leftDomain.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase) ||
               rightDomain.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase);
    }

    private static class NativeMethods
    {
        internal enum WtsConnectState
        {
            Active = 0
        }

        internal enum WtsInfoClass
        {
            UserName = 5
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct WtsSessionInfo
        {
            public uint SessionId;
            public IntPtr pWinStationName;
            public WtsConnectState State;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        internal struct StartupInfo
        {
            public int cb;
            public string? lpReserved;
            public string? lpDesktop;
            public string? lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct ProcessInformation
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("kernel32.dll")]
        public static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSQueryUserToken(uint sessionId, out IntPtr phToken);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSEnumerateSessions(
            IntPtr hServer,
            int reserved,
            int version,
            out IntPtr ppSessionInfo,
            out int pCount);

        [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool WTSQuerySessionInformation(
            IntPtr hServer,
            uint sessionId,
            WtsInfoClass wtsInfoClass,
            out IntPtr ppBuffer,
            out uint pBytesReturned);

        [DllImport("wtsapi32.dll")]
        public static extern void WTSFreeMemory(IntPtr pointer);

        [DllImport("userenv.dll", SetLastError = true)]
        public static extern bool CreateEnvironmentBlock(out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

        [DllImport("userenv.dll", SetLastError = true)]
        public static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CreateProcessAsUser(
            IntPtr hToken,
            string? lpApplicationName,
            string lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandles,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            string? lpCurrentDirectory,
            ref StartupInfo lpStartupInfo,
            out ProcessInformation lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);
    }
}
