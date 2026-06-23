using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using PrintoCrypt.App.Localization;
using PrintoCrypt.App.Services;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Views;

public partial class PasswordDialog : Window
{
    public string Password { get; private set; } = string.Empty;
    public EmailTemplate? SelectedEmailTemplate { get; private set; }

    public PasswordDialog(PrintJobInfo job, AppSettings settings)
    {
        InitializeComponent();
        ApplyLocalization();
        DocumentTitleText.Text = string.IsNullOrWhiteSpace(job.DocumentTitle)
            ? L.Get("UntitledDocument")
            : job.DocumentTitle;

        if (settings.UseEmailTemplates)
        {
            TemplatePanel.Visibility = Visibility.Visible;
            var options = BuildTemplateOptions(settings.EmailTemplates);
            TemplateComboBox.ItemsSource = options;
            TemplateComboBox.DisplayMemberPath = nameof(EmailTemplateOption.DisplayName);
            TemplateComboBox.SelectedItem = SelectInitialOption(options, settings.EmailTemplates);
        }

        Loaded += (_, _) =>
        {
            if (TemplatePanel.Visibility == Visibility.Visible)
            {
                TemplateComboBox.Focus();
            }
            else
            {
                PasswordBox.Focus();
            }
        };
    }

    private static List<EmailTemplateOption> BuildTemplateOptions(IEnumerable<EmailTemplate> templates)
    {
        var options = new List<EmailTemplateOption>
        {
            new()
            {
                DisplayName = L.Get("EmailTemplateNothing"),
                Template = null
            }
        };

        options.AddRange(templates.Select(template => new EmailTemplateOption
        {
            DisplayName = template.Name,
            Template = template
        }));

        return options;
    }

    private static EmailTemplateOption SelectInitialOption(
        IReadOnlyList<EmailTemplateOption> options,
        IReadOnlyList<EmailTemplate> templates)
    {
        var defaultTemplate = templates.FirstOrDefault(t => t.IsDefault);
        if (defaultTemplate is not null)
        {
            return options.FirstOrDefault(o => o.Template?.Id == defaultTemplate.Id) ?? options[0];
        }

        return options[0];
    }

    private void ApplyLocalization()
    {
        Title = L.Get("PasswordDialog_Title");
        HeaderText.Text = L.Get("EncryptPrintJob");
        TemplateLabel.Text = L.Get("EmailTemplateSelect");
        PasswordLabel.Text = L.Get("Password");
        ConfirmPasswordLabel.Text = L.Get("ConfirmPassword");
        CancelButton.Content = L.Get("Cancel");
        SubmitButton.Content = L.Get("Submit");
        VersionText.Text = L.Format("AppVersion", AppVersion.GetDisplayVersion());
    }

    private void SubmitButton_OnClick(object sender, RoutedEventArgs e) => TrySubmit();

    private void CancelButton_OnClick(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void PasswordBox_OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        if (sender == PasswordBox)
        {
            ConfirmPasswordBox.Focus();
            e.Handled = true;
            return;
        }

        TrySubmit();
        e.Handled = true;
    }

    private void TrySubmit()
    {
        if (!Validate())
        {
            return;
        }

        Password = PasswordBox.Password;
        SelectedEmailTemplate = TemplatePanel.Visibility == Visibility.Visible
            ? (TemplateComboBox.SelectedItem as EmailTemplateOption)?.Template
            : null;
        DialogResult = true;
        Close();
    }

    private bool Validate()
    {
        ErrorText.Text = string.Empty;

        if (string.IsNullOrWhiteSpace(PasswordBox.Password))
        {
            ErrorText.Text = L.Get("EnterPassword");
            PasswordBox.Focus();
            return false;
        }

        if (PasswordBox.Password.Length < 4)
        {
            ErrorText.Text = L.Get("PasswordMinLength");
            PasswordBox.Focus();
            return false;
        }

        if (PasswordBox.Password != ConfirmPasswordBox.Password)
        {
            ErrorText.Text = L.Get("PasswordsDoNotMatch");
            ConfirmPasswordBox.Focus();
            return false;
        }

        return true;
    }
}
