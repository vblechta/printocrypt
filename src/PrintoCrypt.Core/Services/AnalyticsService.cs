using System.Net.Http;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json.Serialization;

namespace PrintoCrypt.Core.Services;

public sealed class AnalyticsService
{
    private const string AnalyticsUrl = "https://analytics.printocrypt.ethercloud.io/api/install";
    private const string ApiKey = "B9ZwseWGrQNmcHOuYZjuiVftVAk01w";

    private static readonly HttpClient HttpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(10)
    };

    public void TrackUsage()
    {
        _ = TrackAsync("usage");
    }

    private static async Task TrackAsync(string action)
    {
        try
        {
            var payload = new AnalyticsPayload
            {
                Ip = await GetPublicIpAsync(),
                Hostname = Environment.MachineName,
                Version = GetAppVersion(),
                Action = action,
                Timestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            };

            using var request = new HttpRequestMessage(HttpMethod.Post, AnalyticsUrl)
            {
                Content = JsonContent.Create(payload)
            };
            request.Headers.Add("X-API-Key", ApiKey);

            using var response = await HttpClient.SendAsync(request);
        }
        catch
        {
            // Best effort; never interrupt printing.
        }
    }

    private static async Task<string> GetPublicIpAsync()
    {
        try
        {
            var ip = await HttpClient.GetStringAsync("https://api.ipify.org");
            return ip.Trim();
        }
        catch
        {
            return "unknown";
        }
    }

    private static string GetAppVersion()
    {
        var version = Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3);
        if (string.IsNullOrWhiteSpace(version))
        {
            version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3);
        }

        return string.IsNullOrWhiteSpace(version) ? "unknown" : version;
    }

    private sealed class AnalyticsPayload
    {
        [JsonPropertyName("ip")]
        public string Ip { get; set; } = "unknown";

        [JsonPropertyName("hostname")]
        public string Hostname { get; set; } = string.Empty;

        [JsonPropertyName("version")]
        public string Version { get; set; } = "unknown";

        [JsonPropertyName("action")]
        public string Action { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public string Timestamp { get; set; } = string.Empty;
    }
}
