# PrintoCrypt

Virtual Windows printer that saves every print job as a **password-protected PDF**. When you print, PrintoCrypt prompts for a password before writing the file.

## How it works

```mermaid
flowchart LR
    App[Any Windows app] -->|Print| Printer[PrintoCrypt printer]
    Printer -->|XPS over TCP| Server[PrintoCrypt app]
    Server -->|Password dialog| User[You]
    User -->|Password| Encrypt[AES-128 PDF encryption]
    Encrypt --> PDF[Encrypted PDF in Documents/PrintoCrypt]
```

1. Windows sends the print job to a **virtual XPS printer** on `127.0.0.1:9150`.
2. The PrintoCrypt tray app receives the job.
3. A **password dialog** appears (print is paused until you confirm or cancel).
4. The job is converted to PDF with **built-in Windows XPS rendering**, then encrypted with **PDFsharp** (128-bit AES, all permissions restricted).
5. The encrypted PDF is saved to your output folder.
6. **Outlook** opens a new email draft with the PDF attached (if installed).

## Requirements

- **Windows 10/11**
- **[.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0)** (if not using self-contained build)
- **Microsoft Outlook** (optional) — for attaching encrypted PDFs to a new email after printing

## Build

On Windows with the .NET 8 SDK:

```powershell
dotnet restore PrintoCrypt.sln
dotnet build PrintoCrypt.sln -c Release
dotnet publish src/PrintoCrypt.App/PrintoCrypt.App.csproj -c Release -r win-x64 -o publish
```

Build a setup package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/Build-Installer.ps1
```

This creates:

- `artifacts/PrintoCrypt-Setup/` — portable setup folder
- `artifacts/PrintoCrypt-Setup.zip` — same content as a zip
- `artifacts/PrintoCrypt-Setup.exe` — GUI installer (requires [Inno Setup 6](https://jrsoftware.org/isinfo.php))

Build the GUI installer locally:

```powershell
winget install --id JRSoftware.InnoSetup --source winget
```

If `winget` fails on the Microsoft Store source (`msstore` certificate error), always pass `--source winget` as above, or download Inno Setup from https://jrsoftware.org/isdl.php .

```powershell
powershell -ExecutionPolicy Bypass -File scripts/Build-Installer.ps1
```

## Install

### GUI installer (recommended)

Run **`PrintoCrypt-Setup.exe`** and follow the wizard.

Quiet/unattended install:

```powershell
PrintoCrypt-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

Progress-only install (no wizard pages):

```powershell
PrintoCrypt-Setup.exe /SILENT
```

Optional custom folder:

```powershell
PrintoCrypt-Setup.exe /VERYSILENT /DIR="C:\Tools\PrintoCrypt"
```

### Portable setup folder

Double-click **`Install.cmd`** in the setup folder (approves UAC once).

Or run as administrator:

```powershell
powershell -ExecutionPolicy Bypass -File Install.ps1
```

Quiet install from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File Install.ps1 -Quiet
```

The installer:

- Installs PrintoCrypt to `%ProgramFiles%\PrintoCrypt`
- Registers the **PrintoCrypt** printer for **all users** on the PC
- Enables **Start with Windows** for the logged-on user
- Creates Start Menu shortcuts
- Starts the tray app

## Uninstall

Double-click **`Uninstall.cmd`**, or run as administrator:

```powershell
powershell -ExecutionPolicy Bypass -File Uninstall.ps1
```

This removes the app, printer, port, shortcuts, and startup entry.

From the app, **Settings → Install/Uninstall printer** only changes the printer (uses `-PrinterOnly`).

## Usage

1. Keep PrintoCrypt running in the tray.
2. Print from any application and choose **PrintoCrypt**.
3. Enter and confirm a password in the dialog.
4. Find the encrypted PDF in `Documents\PrintoCrypt` (default).

## Settings

| Option | Description |
|--------|-------------|
| Output folder | Where encrypted PDFs are saved |
| Listen port | TCP port for the virtual printer (default `9150`) |
| Open Outlook after saving | Compose a new Outlook email with the PDF attached |
| Open output folder after saving | Show the saved file in Explorer |
| Start with Windows | Register PrintoCrypt in the current-user Run key |

## Project structure

```
src/
  PrintoCrypt.Core/     PDF encryption, settings, job processing
  PrintoCrypt.App/      WPF tray app, XPS-to-PDF conversion, TCP print server
scripts/
  Build-Installer.ps1   Create setup zip and GUI installer
  Install.ps1           Install app, printer, and launch
  Uninstall.ps1         Remove everything
installer/
  PrintoCrypt.iss       Inno Setup GUI installer script
Install.cmd             Double-click installer (requests admin)
Uninstall.cmd           Double-click uninstaller (requests admin)
```

## License

MIT
