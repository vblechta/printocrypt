using System.IO.Packaging;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Windows.Xps.Packaging;
using PdfSharp.Drawing;
using PdfSharp.Pdf;
using PrintoCrypt.Core.Localization;
using PrintoCrypt.Core.Services;

namespace PrintoCrypt.App.Services;

public sealed class WpfXpsToPdfConverter : IPrintDocumentConverter
{
    private const double Dpi = 96.0;

    public void ConvertToPdf(string sourcePath, string pdfPath)
    {
        if (!File.Exists(sourcePath))
        {
            throw new FileNotFoundException(M.Get("Error_PrintJobNotFound"), sourcePath);
        }

        var dispatcher = Application.Current?.Dispatcher
            ?? throw new InvalidOperationException(M.Get("Error_NotReadyToConvert"));

        if (dispatcher.CheckAccess())
        {
            ConvertToPdfCore(sourcePath, pdfPath);
            return;
        }

        dispatcher.Invoke(() => ConvertToPdfCore(sourcePath, pdfPath), DispatcherPriority.Normal);
    }

    private static void ConvertToPdfCore(string sourcePath, string pdfPath)
    {
        var directory = Path.GetDirectoryName(pdfPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var normalizedPath = Path.Combine(
            Path.GetTempPath(),
            $"printocrypt_{Guid.NewGuid():N}.oxps");

        try
        {
            File.WriteAllBytes(normalizedPath, PrintJobPayloadNormalizer.NormalizeFile(sourcePath));
            RenderXpsToPdf(normalizedPath, pdfPath);
        }
        finally
        {
            TryDelete(normalizedPath);
        }
    }

    private static void RenderXpsToPdf(string xpsPath, string pdfPath)
    {
        var fullPath = Path.GetFullPath(xpsPath);
        using var package = Package.Open(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var xpsDocument = new XpsDocument(package, CompressionOption.NotCompressed, fullPath);

        var pdfDocument = new PdfDocument();
        var pagesRendered = 0;

        var sequence = xpsDocument.GetFixedDocumentSequence();
        if (sequence is not null)
        {
            foreach (DocumentReference documentReference in sequence.References)
            {
                pagesRendered += RenderFixedDocument(pdfDocument, documentReference.GetDocument(false));
            }
        }
        else
        {
            pagesRendered += RenderFixedPages(pdfDocument, package);
        }

        if (pagesRendered == 0)
        {
            throw new InvalidOperationException(M.Get("Error_InvalidXpsDocument"));
        }

        pdfDocument.Save(pdfPath);
    }

    private static int RenderFixedPages(PdfDocument pdfDocument, Package package)
    {
        var pagesRendered = 0;

        foreach (var part in package.GetParts()
                     .Where(IsFixedPagePart)
                     .OrderBy(part => part.Uri.OriginalString, StringComparer.OrdinalIgnoreCase))
        {
            using var stream = part.GetStream(FileMode.Open, FileAccess.Read);
            if (XamlReader.Load(stream) is not FixedPage fixedPage)
            {
                throw new InvalidOperationException(M.Get("Error_UnreadablePage"));
            }

            AddPage(pdfDocument, fixedPage);
            pagesRendered++;
        }

        return pagesRendered;
    }

    private static bool IsFixedPagePart(PackagePart part)
    {
        return part.Uri.OriginalString.EndsWith(".fpage", StringComparison.OrdinalIgnoreCase) ||
               part.ContentType.Contains("fixedpage+xml", StringComparison.OrdinalIgnoreCase);
    }

    private static int RenderFixedDocument(PdfDocument pdfDocument, FixedDocument fixedDocument)
    {
        var pagesRendered = 0;

        foreach (PageContent pageContent in fixedDocument.Pages)
        {
            var fixedPage = pageContent.GetPageRoot(false)
                ?? throw new InvalidOperationException(M.Get("Error_UnreadablePage"));

            AddPage(pdfDocument, fixedPage);
            pagesRendered++;
        }

        return pagesRendered;
    }

    private static void AddPage(PdfDocument pdfDocument, FixedPage fixedPage)
    {
        var width = fixedPage.Width > 0 ? fixedPage.Width : 816;
        var height = fixedPage.Height > 0 ? fixedPage.Height : 1056;

        var pdfPage = pdfDocument.AddPage();
        pdfPage.Width = XUnit.FromPoint(width * 72.0 / Dpi);
        pdfPage.Height = XUnit.FromPoint(height * 72.0 / Dpi);

        var surface = new Canvas
        {
            Width = width,
            Height = height,
            Background = Brushes.White
        };
        surface.Children.Add(fixedPage);

        surface.Measure(new Size(width, height));
        surface.Arrange(new Rect(0, 0, width, height));
        surface.UpdateLayout();

        var bitmap = new RenderTargetBitmap(
            Math.Max(1, (int)Math.Ceiling(width)),
            Math.Max(1, (int)Math.Ceiling(height)),
            Dpi,
            Dpi,
            PixelFormats.Pbgra32);
        bitmap.Render(surface);

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));

        using var imageStream = new MemoryStream();
        encoder.Save(imageStream);
        imageStream.Position = 0;

        using var gfx = XGraphics.FromPdfPage(pdfPage);
        using var image = XImage.FromStream(imageStream);
        gfx.DrawImage(image, 0, 0, pdfPage.Width.Point, pdfPage.Height.Point);
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }
}
