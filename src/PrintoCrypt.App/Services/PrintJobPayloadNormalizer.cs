using PrintoCrypt.Core.Localization;
using System.IO.Packaging;
using System.Text;

namespace PrintoCrypt.App.Services;

internal static class PrintJobPayloadNormalizer
{
    internal static (byte[] Payload, string? Title) ExtractPrintPayload(byte[] data)
    {
        if (data.Length == 0)
        {
            return (Array.Empty<byte>(), null);
        }

        var headerSampleLength = Math.Min(data.Length, 8192);
        var headerText = Encoding.ASCII.GetString(data, 0, headerSampleLength);
        string? title = null;

        if (headerText.Contains("@PJL", StringComparison.OrdinalIgnoreCase))
        {
            title = ExtractPjlValue(headerText, "TITLE");

            var markerIndex = headerText.IndexOf("@PJL ENTER LANGUAGE", StringComparison.OrdinalIgnoreCase);
            if (markerIndex >= 0)
            {
                var payloadStart = FindPayloadStartAfterLine(data, markerIndex);
                if (payloadStart >= 0 && payloadStart < data.Length)
                {
                    return (data[payloadStart..], title);
                }
            }

            var zipOffset = FindZipOffset(data);
            if (zipOffset >= 0)
            {
                return (data[zipOffset..], title);
            }
        }

        if (IsZipPayload(data))
        {
            return (data, title);
        }

        return (data, title);
    }

    public static byte[] NormalizeFile(string sourcePath)
    {
        var raw = File.ReadAllBytes(sourcePath);
        return NormalizeBytes(raw);
    }

    public static byte[] NormalizeBytes(byte[] raw)
    {
        if (raw.Length == 0)
        {
            return raw;
        }

        if (IsPostScript(raw))
        {
            throw new InvalidOperationException(M.Get("Error_PostScriptFromPrinter"));
        }

        if (IsValidXpsPackage(raw))
        {
            return raw;
        }

        var (stripped, _) = ExtractPrintPayload(raw);
        if (IsValidXpsPackage(stripped))
        {
            return stripped;
        }

        foreach (var offset in FindZipOffsets(raw))
        {
            var candidate = raw[offset..];
            if (IsValidXpsPackage(candidate))
            {
                return candidate;
            }
        }

        if (stripped.Length > 0)
        {
            foreach (var offset in FindZipOffsets(stripped))
            {
                var candidate = stripped[offset..];
                if (IsValidXpsPackage(candidate))
                {
                    return candidate;
                }
            }
        }

        return stripped.Length > 0 ? stripped : raw;
    }

    public static void WriteNormalizedCopy(string sourcePath)
    {
        var normalized = NormalizeFile(sourcePath);
        if (!normalized.AsSpan().SequenceEqual(File.ReadAllBytes(sourcePath)))
        {
            File.WriteAllBytes(sourcePath, normalized);
        }
    }

    private static bool IsPostScript(byte[] data)
    {
        var sampleLength = Math.Min(data.Length, 4096);
        var sample = Encoding.ASCII.GetString(data, 0, sampleLength);
        return sample.Contains("%!PS", StringComparison.Ordinal);
    }

    private static IEnumerable<int> FindZipOffsets(byte[] data)
    {
        for (var index = 0; index < data.Length - 3; index++)
        {
            if (data[index] == 0x50 &&
                data[index + 1] == 0x4B &&
                data[index + 2] is 0x03 or 0x05 or 0x07 &&
                data[index + 3] == 0x04)
            {
                yield return index;
            }
        }
    }

    private static bool IsValidXpsPackage(byte[] data)
    {
        if (data.Length < 4)
        {
            return false;
        }

        try
        {
            using var stream = new MemoryStream(data, writable: false);
            using var package = Package.Open(stream, FileMode.Open, FileAccess.Read);
            return package.GetParts().Any(IsXpsPart);
        }
        catch
        {
            return false;
        }
    }

    private static bool IsXpsPart(PackagePart part)
    {
        var uri = part.Uri.OriginalString;
        if (uri.EndsWith(".fdseq", StringComparison.OrdinalIgnoreCase) ||
            uri.EndsWith(".fdoc", StringComparison.OrdinalIgnoreCase) ||
            uri.EndsWith(".fpage", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return part.ContentType.Contains("xps", StringComparison.OrdinalIgnoreCase);
    }

    private static int FindPayloadStartAfterLine(byte[] data, int markerIndex)
    {
        for (var index = markerIndex; index < data.Length; index++)
        {
            if (data[index] is (byte)'\n' or (byte)'\r')
            {
                var payloadStart = index + 1;
                while (payloadStart < data.Length && data[payloadStart] is (byte)'\n' or (byte)'\r')
                {
                    payloadStart++;
                }

                return payloadStart;
            }
        }

        return -1;
    }

    private static int FindZipOffset(byte[] data)
    {
        for (var index = 0; index < data.Length - 1; index++)
        {
            if (data[index] == (byte)'P' && data[index + 1] == (byte)'K')
            {
                return index;
            }
        }

        return -1;
    }

    private static bool IsZipPayload(byte[] data)
    {
        return data.Length >= 2 && data[0] == (byte)'P' && data[1] == (byte)'K';
    }

    private static string? ExtractPjlValue(string header, string key)
    {
        foreach (var line in header.Split('\n', '\r'))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith("@PJL", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var eq = trimmed.IndexOf('=');
            if (eq < 0)
            {
                continue;
            }

            var name = trimmed[4..eq].Trim();
            if (!name.Equals(key, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            return trimmed[(eq + 1)..].Trim().Trim('"');
        }

        return null;
    }
}
