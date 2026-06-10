using System.Runtime.InteropServices;

namespace PrintoCrypt.App.Services;

internal static class PrintSpoolerUserResolver
{
    private const uint JobStatusSpooling = 0x00000002;
    private const uint JobStatusPrinting = 0x00000010;

    public static string? ResolvePrintingUser(string printerName)
    {
        if (string.IsNullOrWhiteSpace(printerName))
        {
            return null;
        }

        if (!NativeSpooler.OpenPrinter(printerName, out var printerHandle, IntPtr.Zero))
        {
            return GetInteractiveUserName();
        }

        try
        {
            NativeSpooler.EnumJobs(printerHandle, 0, uint.MaxValue, 2, IntPtr.Zero, 0, out var bytesNeeded, out var jobsReturned);
            if (bytesNeeded == 0 || jobsReturned == 0)
            {
                return GetInteractiveUserName();
            }

            var buffer = Marshal.AllocHGlobal((int)bytesNeeded);
            try
            {
                if (!NativeSpooler.EnumJobs(
                        printerHandle,
                        0,
                        uint.MaxValue,
                        2,
                        buffer,
                        bytesNeeded,
                        out _,
                        out jobsReturned))
                {
                    return GetInteractiveUserName();
                }

                var entrySize = Marshal.SizeOf<NativeSpooler.JobInfo2>();
                string? selectedUser = null;
                uint selectedJobId = 0;

                for (var index = 0; index < jobsReturned; index++)
                {
                    var entryPtr = buffer + (index * entrySize);
                    var jobInfo = Marshal.PtrToStructure<NativeSpooler.JobInfo2>(entryPtr);
                    var isActive = (jobInfo.Status & (JobStatusSpooling | JobStatusPrinting)) != 0;
                    var isRecentCandidate = jobInfo.JobId >= selectedJobId;

                    if (isActive && isRecentCandidate)
                    {
                        selectedJobId = jobInfo.JobId;
                        selectedUser = ReadString(jobInfo.pUserName);
                        continue;
                    }

                    if (selectedUser is null && isRecentCandidate)
                    {
                        selectedJobId = jobInfo.JobId;
                        selectedUser = ReadString(jobInfo.pUserName);
                    }
                }

                return string.IsNullOrWhiteSpace(selectedUser)
                    ? GetInteractiveUserName()
                    : selectedUser;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            NativeSpooler.ClosePrinter(printerHandle);
        }
    }

    public static string? GetInteractiveUserName()
    {
        var sessionId = NativeSession.WTSGetActiveConsoleSessionId();
        if (sessionId == 0xFFFFFFFF)
        {
            return null;
        }

        var result = NativeSession.WTSQuerySessionInformation(
            IntPtr.Zero,
            sessionId,
            NativeSession.WtsInfoClass.UserName,
            out var buffer,
            out _);

        if (!result || buffer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            return Marshal.PtrToStringUni(buffer);
        }
        finally
        {
            NativeSession.WTSFreeMemory(buffer);
        }
    }

    private static string? ReadString(IntPtr pointer)
        => pointer == IntPtr.Zero ? null : Marshal.PtrToStringUni(pointer);

    private static class NativeSpooler
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        internal struct JobInfo2
        {
            public uint JobId;
            public IntPtr pPrinterName;
            public IntPtr pMachineName;
            public IntPtr pUserName;
            public IntPtr pDocument;
            public IntPtr pNotifyName;
            public IntPtr pDatatype;
            public IntPtr pPrintProcessor;
            public IntPtr pParameters;
            public IntPtr pDriverName;
            public IntPtr pDevMode;
            public IntPtr pStatus;
            public IntPtr pSecurityDescriptor;
            public uint Status;
            public uint Priority;
            public uint Position;
            public uint StartTime;
            public uint UntilTime;
            public uint TotalPages;
            public uint Size;
            public uint SubmittedYear;
            public uint SubmittedMonth;
            public ushort SubmittedDayOfWeek;
            public ushort SubmittedDay;
            public uint SubmittedHour;
            public uint SubmittedMinute;
            public uint SubmittedSecond;
            public uint SubmittedMilliseconds;
            public uint Time;
            public uint PagesPrinted;
        }

        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

        [DllImport("winspool.drv", SetLastError = true)]
        public static extern bool ClosePrinter(IntPtr hPrinter);

        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool EnumJobs(
            IntPtr hPrinter,
            uint FirstJob,
            uint NoJobs,
            uint Level,
            IntPtr pJob,
            uint cbBuf,
            out uint pcbNeeded,
            out uint pcReturned);
    }

    private static class NativeSession
    {
        internal enum WtsInfoClass
        {
            UserName = 5
        }

        [DllImport("kernel32.dll")]
        public static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool WTSQuerySessionInformation(
            IntPtr hServer,
            uint sessionId,
            WtsInfoClass wtsInfoClass,
            out IntPtr ppBuffer,
            out uint pBytesReturned);

        [DllImport("wtsapi32.dll")]
        public static extern void WTSFreeMemory(IntPtr pointer);
    }
}
