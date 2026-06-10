using System.Text.Json;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.Core.Services;

public sealed class MachineSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly string _settingsPath;

    public MachineSettingsStore(string? settingsPath = null)
    {
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "PrintoCrypt");
        Directory.CreateDirectory(folder);
        _settingsPath = settingsPath ?? Path.Combine(folder, "machine-settings.json");
    }

    public MachineSettings Load()
    {
        if (!File.Exists(_settingsPath))
        {
            return new MachineSettings();
        }

        try
        {
            var json = File.ReadAllText(_settingsPath);
            return JsonSerializer.Deserialize<MachineSettings>(json, JsonOptions) ?? new MachineSettings();
        }
        catch
        {
            return new MachineSettings();
        }
    }

    public void Save(MachineSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        File.WriteAllText(_settingsPath, json);
    }
}
