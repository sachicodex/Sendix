# Sendix

<p align="center">
  <img src="assets/Logo/Sendix.png" alt="Sendix Logo" width="140" />
</p>

<p align="center">
  A fast local file and text sharing app for nearby devices - with LAN discovery, drag-and-drop sending, clipboard paste, live transfer controls, and a polished Android + desktop experience.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter Badge" />
  <img src="https://img.shields.io/badge/Dart-3.10+-0175C2?logo=dart" alt="Dart Badge" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Desktop-2ea44f" alt="Platform Badge" />
  <img src="https://img.shields.io/badge/Transfer-Local%20Network-F57C2F" alt="Transfer Badge" />
</p>

## Download

| Platform | Package | Link | Notes |
|---|---|---|---|
| Android | APK | [Latest Release](https://github.com/sachicodex/Sendix/releases/latest) | Install from the release assets on your device. |
| Windows | MSIX | [Latest Release](https://github.com/sachicodex/Sendix/releases/latest) | Recommended install for the best desktop and share-target experience. |
| Linux / macOS / iOS / Web | Build from source | [Run From Source](#run-from-source) | Use Flutter build commands for your target platform. |

## About

Sendix lets you move content between nearby devices on the same local network:
- Discover nearby devices automatically over Wi-Fi or LAN.
- Send files, folders, images, text snippets, and app packages.
- Paste clipboard content or drag and drop files on desktop.
- Accept, pause, resume, cancel, and track transfers in real time.
- Choose a custom receive folder or reset to the default Sendix path.
- Mark trusted devices as favourites and optionally auto-accept them.
- Share into Sendix from the Android share sheet or the Windows share target flow.

## Preview

<p align="center">
  <img src="assets/Logo/Sendix-windows.png" alt="Sendix Brand Preview" width="420" />
</p>

> Add `assets/img/preview-desktop.png` and `assets/img/preview-mobile.png` for full UI screenshots in this section.

## Features

| Icon | Feature | What you get |
|---|---|---|
| Devices | Nearby discovery | See devices on the same network appear automatically. |
| Files | File and folder sending | Send single files or full folders with preserved relative paths. |
| Text | Text sharing | Quickly send text snippets or clipboard content. |
| App | App package sharing | Send APK, AAB, or IPA files, and export installed Android apps. |
| Desktop | Desktop workflows | Drag-and-drop support, preview, and clipboard paste on desktop. |
| Queue | Transfer controls | Pause, resume, cancel, and monitor live progress and speed. |
| Favorites | Trusted devices | Save devices as favourites and skip approval when enabled. |
| Storage | Flexible save location | Pick a custom receive folder or reset to the default location. |

## Mobile Gestures

| Gesture | Action |
|---|---|
| Swipe left/right on the main shell | Switch tabs: Send -> Receive -> Settings. |
| Share from another app | Open Sendix with the shared files or text ready to send. |
| Tap a transfer card in Receive | Open pause, resume, cancel, open location, and delete actions. |

## Desktop Shortcuts

| Key | Action |
|---|---|
| `Ctrl`/`Cmd` + `V` | Paste text or file paths into Send on desktop. |
| Drag and drop | Add files directly to the send selection. |
| Window controls | Minimize, maximize, and close from the custom Windows title bar. |

## How to Use

1. Open Sendix on both devices.
2. Make sure both devices are on the same Wi-Fi or LAN.
3. On the sender, add files, folders, images, text, or clipboard content.
4. Select the nearby device from the list.
5. Accept the transfer on the receiver, unless auto-accept is enabled for that favourite device.
6. Track progress in the Receive view and open the saved location when complete.
7. Use Settings to change your device name, receive folder, and favourite-device behavior.

## Run From Source

### Prerequisites

- Flutter SDK with Dart `3.10+`
- Devices connected to the same local network
- Android SDK for Android builds
- Visual Studio with the Desktop C++ workload for Windows builds

### Setup

```bash
git clone https://github.com/sachicodex/Sendix.git
cd Sendix
flutter pub get
flutter run
```

### Common run targets

```bash
flutter run -d android
flutter run -d windows
flutter run -d linux
flutter run -d macos
```

### Build release packages

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# Windows MSIX
dart run msix:create
```

## Setup A-Z

### 1. Get the app running

Open Sendix on both devices and keep them on the same local network.

### 2. Pick a send source

On the Send screen, you can:
- Browse for files or folders.
- Add images from the picker.
- Paste text or file paths with `Ctrl`/`Cmd` + `V` on desktop.
- Add installed Android apps as APK files.
- Drag and drop files on desktop.

### 3. Send to a nearby device

Wait for nearby devices to appear, choose one, and Sendix will start the transfer.

### 4. Approve incoming transfers

When another device sends to you, a confirmation dialog appears with the file list and the chosen save location.

### 5. Tune receive behavior

In Settings you can:
- Rename the device.
- Change the default receive folder.
- Enable auto-accept for favourite devices.

### 6. Share into Sendix

Sendix can receive shared content from the Android share sheet and from the Windows share-target flow when packaged correctly.

## Transfer Flow

- Device discovery happens on the local network.
- Sendix establishes a direct socket connection between peers.
- Files are transferred with chunking, compression, encryption, and integrity checks.
- Progress is shown live with speed tracking and completion feedback.

## Supported Content

- Files of any type
- Entire folders
- Images
- Text snippets
- Clipboard content
- Android app packages

## Project Structure

```text
lib/
  core/                 Networking, file handling, platform bridges, settings storage
  features/             Send and receive controllers
  models/               Device and transfer models
  ui/                   Pages, theme, splash, and shared widgets
assets/
  Logo/                 App logos and branding
  lottie/               Loading and success animations
  svg/                  Navigation and action icons
  fonts/                Montserrat font family
```

## Tech Stack

| Area | Tech |
|---|---|
| App | Flutter |
| Language | Dart |
| UI state | Controller-based state with `ValueNotifier` |
| Device discovery | UDP broadcast on the local network |
| Transfer transport | TCP socket transfer with a framed protocol |
| Data handling | Gzip compression + SHA-256 integrity checks |
| File input | `file_picker`, `desktop_drop` |
| Desktop/mobile UI | `flutter_svg`, `lottie` |
| Desktop shell | `window_manager`, `window_size` |
| Windows packaging | `msix` |

## Publisher

| Field | Value |
|---|---|
| Display name | Sendix |
| Publisher | Sachicodex |
| Package ID | `com.sachicodex.sendix` |
| Version | `2.17.4` |

## Support

- Issues: [GitHub Issues](https://github.com/sachicodex/Sendix/issues)
- Repository: [github.com/sachicodex/Sendix](https://github.com/sachicodex/Sendix)
