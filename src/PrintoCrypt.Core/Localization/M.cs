using System.Globalization;
using System.Resources;

namespace PrintoCrypt.Core.Localization;

public static class M
{
    private static readonly ResourceManager Manager = new(
        "PrintoCrypt.Core.Resources.Messages",
        typeof(M).Assembly);

    private static CultureInfo _culture = CultureInfo.CurrentUICulture;

    public static void Use(CultureInfo culture) => _culture = culture;

    public static string Get(string name) =>
        Manager.GetString(name, _culture) ?? name;
}
