using System.Globalization;
using System.Resources;

namespace PrintoCrypt.App.Localization;

public static class L
{
    private static readonly ResourceManager Manager = new(
        "PrintoCrypt.App.Resources.Strings",
        typeof(L).Assembly);

    private static CultureInfo _culture = CultureInfo.CurrentUICulture;

    public static void Use(CultureInfo culture) => _culture = culture;

    public static string Get(string name) =>
        Manager.GetString(name, _culture) ?? name;

    public static string Format(string name, params object[] args) =>
        string.Format(_culture, Get(name), args);
}
