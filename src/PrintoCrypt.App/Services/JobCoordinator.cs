using System.Diagnostics;
using PrintoCrypt.Core.Models;
using PrintoCrypt.Core.Services;

namespace PrintoCrypt.App.Services;

public sealed class JobCoordinator
{
    private readonly PrintJobProcessor _processor;
    private readonly AppSettings _settings;

    public event EventHandler<string>? JobCompleted;
    public event EventHandler<string>? JobCancelled;
    public event EventHandler<(PrintJobInfo Job, Exception Error)>? JobFailed;
    public event EventHandler<string>? OutlookOpenFailed;

    public JobCoordinator(PrintJobProcessor processor, AppSettings settings)
    {
        _processor = processor;
        _settings = settings;
    }

    public async Task HandleJobAsync(PrintJobInfo job, Func<PrintJobInfo, Task<string?>> requestPasswordAsync)
    {
        try
        {
            var password = await requestPasswordAsync(job);
            if (password is null)
            {
                JobCancelled?.Invoke(this, job.DocumentTitle ?? job.JobId);
                TryDelete(job.SourcePath);
                return;
            }

            var outputPath = await Task.Run(() =>
                _processor.Process(job, password, _settings.OutputDirectory));

            JobCompleted?.Invoke(this, outputPath);

            if (_settings.OpenOutlookAfterSave)
            {
                try
                {
                    OutlookEmailService.CreateDraftWithAttachment(outputPath, job.DocumentTitle);
                }
                catch (Exception ex)
                {
                    OutlookOpenFailed?.Invoke(this, ex.Message);
                }
            }

            if (_settings.OpenOutputFolderAfterSave)
            {
                OpenContainingFolder(outputPath);
            }
        }
        catch (Exception ex)
        {
            JobFailed?.Invoke(this, (job, ex));
            TryDelete(job.SourcePath);
        }
    }

    private static void OpenContainingFolder(string filePath)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{filePath}\"",
                UseShellExecute = true
            });
        }
        catch
        {
            // Explorer may be unavailable in some environments.
        }
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
            // Best effort cleanup.
        }
    }
}
