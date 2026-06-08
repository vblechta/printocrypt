using System.Globalization;
using System.Threading;
using PrintoCrypt.Core.Localization;

namespace PrintoCrypt.App.Localization;

public static class LocalizationSetup
{
    public static CultureInfo ApplySystemLanguage()
    {
        var culture = ResolveCulture(CultureInfo.CurrentUICulture);
        Thread.CurrentThread.CurrentUICulture = culture;
        Thread.CurrentThread.CurrentCulture = culture;
        L.Use(culture);
        M.Use(culture);
        return culture;
    }

    private static CultureInfo ResolveCulture(CultureInfo systemCulture)
    {
        if (string.Equals(systemCulture.TwoLetterISOLanguageName, "cs", StringComparison.OrdinalIgnoreCase))
        {
            return CultureInfo.GetCultureInfo("cs");
        }

        return CultureInfo.GetCultureInfo("en");
    }
}
