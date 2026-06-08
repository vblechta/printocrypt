using System.Windows;
using System.Windows.Input;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Views;

public partial class PasswordDialog : Window
{
    public string Password { get; private set; } = string.Empty;

    public PasswordDialog(PrintJobInfo job)
    {
        InitializeComponent();
        DocumentTitleText.Text = string.IsNullOrWhiteSpace(job.DocumentTitle)
            ? "Untitled document"
            : job.DocumentTitle;
        Loaded += (_, _) => PasswordBox.Focus();
    }

    private void SaveButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (!Validate())
        {
            return;
        }

        Password = PasswordBox.Password;
        DialogResult = true;
    }

    private void PasswordBox_OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            if (Validate())
            {
                Password = PasswordBox.Password;
                DialogResult = true;
            }
        }
    }

    private bool Validate()
    {
        ErrorText.Text = string.Empty;

        if (string.IsNullOrWhiteSpace(PasswordBox.Password))
        {
            ErrorText.Text = "Enter a password.";
            PasswordBox.Focus();
            return false;
        }

        if (PasswordBox.Password.Length < 4)
        {
            ErrorText.Text = "Password must be at least 4 characters.";
            PasswordBox.Focus();
            return false;
        }

        if (PasswordBox.Password != ConfirmPasswordBox.Password)
        {
            ErrorText.Text = "Passwords do not match.";
            ConfirmPasswordBox.Focus();
            return false;
        }

        return true;
    }
}
