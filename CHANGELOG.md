# Changelog

All notable changes to this project are documented in this file.

## [1.0.1] - 2026-06-22

### Added

- **PrintoCryptBroker** Windows service — receives print jobs as SYSTEM and routes them to the correct user session.
- Per-user tray app launch when a user prints while PrintoCrypt is not already running.
- Active Setup registration so each user gets the tray app on first logon (local and domain accounts).

### Fixed

- Multi-user and domain scenarios where print jobs were delivered to the wrong session or failed silently.
- Install analytics reporting a unique version per build (`1.0.0+commit`) instead of the release version.
- Installer build failure from incomplete splash-screen code.

### Changed

- Split runtime into a system **broker service** and a per-user **tray app** (password dialog, PDF encryption).
- Installer registers the printer before copying app files and uses a self-contained publish.
- Per-user **Start with Windows** via HKCU Run instead of a machine-wide Run entry for the tray app.

## [1.0.0] - 2026-06-18

### Added

- Virtual Windows printer that saves password-protected PDFs.
- WPF tray app with password dialog, XPS-to-PDF conversion, and AES-128 PDF encryption.
- GUI installer (Inno Setup) with silent install and upgrade detection.
- Portable setup folder and zip package.
- Czech and English UI strings.
- Optional Outlook draft with the encrypted PDF attached after printing.
