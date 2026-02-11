<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Mirroreu Icon">
</p>

<h1 align="center">Mirroreu</h1>

<p align="center">
  Tired of waiting for iPhone Mirroring in the EU? Enable it now.

</p>

<p align="center">
  <a href="https://github.com/twttr/mirroreu/actions/workflows/ci.yml"><img src="https://github.com/twttr/mirroreu/actions/workflows/ci.yml/badge.svg?branch=develop" alt="CI"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015.2%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

## Features

- **One-Click Toggle**: Enable or disable iPhone Mirroring from the menu bar
- **Automatic Persistence**: Monitors and re-applies eligibility settings when the system resets them
- **Privileged Helper**: Uses a LaunchDaemon for secure, sandboxed system modifications
- **Full Disk Access Detection**: Guides you through granting the necessary permissions
- **Localized**: Supports 23 languages
- **Menu Bar App**: Runs as a lightweight accessory application (no dock icon)

## Installation

### Homebrew

```bash
brew tap twttr/apps
brew install --cask mirroreu
```

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/twttr/mirroreu.git
   cd mirroreu
   ```

2. Open in Xcode:
   ```bash
   open Mirroreu.xcodeproj
   ```

3. Build and run with `Cmd+R`

### Requirements

- macOS 15.2 or later
- Xcode 26.0 or later
- Full Disk Access (granted to the helper daemon)

## Prerequisites

On your iPhone, change the App Store country to any country outside the EU in **Settings > [Your Name] > Media & Purchases > Country/Region**.

## Usage

1. Launch Mirroreu — an iPhone icon appears in your menu bar
2. Click **Enable Mirroreu in Login Items** and approve the helper in System Settings
3. If prompted, grant Full Disk Access in **System Settings > Privacy & Security** (the app will restart)
4. Click **Enable iPhone Mirroring**

The menu bar icon turns green when enabled and red when disabled.

## How It Works

Mirroreu modifies the system eligibility plist (`/private/var/db/os_eligibility/eligibility.plist`) to set the iPhone Mirroring region flags. A privileged helper daemon watches the file and re-applies the settings if the system resets them. All changes are reverted when you disable or quit.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
