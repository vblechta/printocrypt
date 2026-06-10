using System.Diagnostics;
using System.Windows;
using PrintoCrypt.Core.Models;
using PrintoCrypt.Core.Services;

namespace PrintoCrypt.App.Services;

public sealed class JobCoordinator
{
    private readonly PrintJobProcessor _processor;
    private readonly AppSettings _settings;
    private readonly AnalyticsService _analytics;

    public event EventHandler<JobCompletionInfo>? JobCompleted;
    public event EventHandler<string>? JobCancelled;
    public event EventHandler<(PrintJobInfo Job, Exception Error)>? JobFailed;

    public JobCoordinator(
        PrintJobProcessor processor,
        AppSettings settings,
        AnalyticsService analytics)
    {
        _processor = processor;
        _settings = settings;
        _analytics = analytics;
    }

    public async Task HandleJobAsync(
        PrintJobInfo job,
        Func<PrintJobInfo, Task<PasswordSubmission?>> requestPasswordAsync)
    {
        try
        {
            var submission = await requestPasswordAsync(job);
            if (submission is null)
            {
                JobCancelled?.Invoke(this, job.DocumentTitle ?? job.JobId);
                TryDelete(job.SourcePath);
                return;
            }

            _analytics.TrackUsage();

            var displayName = SanitizeDisplayName(job.DocumentTitle ?? job.JobId);

            if (_settings.OpenOutlookAfterSave)
            {
                var subject = ResolveEmailSubject(submission, job, displayName);
                var body = ResolveEmailBody(submission, job, displayName);

                await Application.Current.Dispatcher.InvokeAsync(() =>
                {
                    var tempPath = _processor.Process(job, submission.Password, outputDirectory: null);

                    try
                    {
                        OutlookEmailService.CreateDraftWithAttachment(tempPath, subject, body);
                        TryDelete(tempPath);

                        JobCompleted?.Invoke(this, new JobCompletionInfo
                        {
                            DisplayName = displayName,
                            OutlookDraftOpened = true
                        });
                    }
                    catch (Exception ex)
                    {
                        TryDelete(tempPath);
                        JobFailed?.Invoke(this, (job, ex));
                    }
                });

                return;
            }

            var outputPath = await Application.Current.Dispatcher.InvokeAsync(() =>
                _processor.Process(job, submission.Password, _settings.OutputDirectory));

            JobCompleted?.Invoke(this, new JobCompletionInfo
            {
                DisplayName = displayName,
                SavedPath = outputPath
            });

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

    private static string? ResolveEmailSubject(
        PasswordSubmission submission,
        PrintJobInfo job,
        string displayName)
    {
        if (submission.EmailTemplate is null)
        {
            return job.DocumentTitle;
        }

        return EmailTemplateFormatter.Apply(submission.EmailTemplate.Subject, job, displayName);
    }

    private static string? ResolveEmailBody(
        PasswordSubmission submission,
        PrintJobInfo job,
        string displayName)
    {
        if (submission.EmailTemplate is null)
        {
            return null;
        }

        return EmailTemplateFormatter.Apply(submission.EmailTemplate.Body, job, displayName);
    }

    private static string SanitizeDisplayName(string name)
    {
        var cleaned = name.Trim();
        return string.IsNullOrWhiteSpace(cleaned) ? "Document" : cleaned;
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
