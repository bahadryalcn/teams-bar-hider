# Teams Bar Hider

[![Build and test](https://github.com/bahadryalcn/teams-bar-hider/actions/workflows/ci.yml/badge.svg)](https://github.com/bahadryalcn/teams-bar-hider/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Keep the Microsoft Teams screen-sharing toolbar out of the way. Teams Bar Hider runs in the system tray on Windows or the menu bar on macOS, with controls to pause hiding and bring the toolbar back.

It targets recognized Teams sharing-toolbars only. Meeting windows, the compact call view and operating-system privacy indicators stay visible. It does not send keyboard shortcuts, stop screen sharing or hide the entire Teams application.

## Install

Download a package from a successful [Build and test run](https://github.com/bahadryalcn/teams-bar-hider/actions/workflows/ci.yml). Expand **Artifacts**, download the package for your platform and extract both the artifact archive and the package inside it. GitHub requires sign-in to download workflow artifacts; these development builds expire after 14 days. Alternatively, build from source below.

### Windows

Requires Windows 10 or 11 with .NET Framework 4.x. No administrator access or additional runtime download is needed.

1. Extract the Windows package into a folder.
2. Open PowerShell in that folder and run `./Install.ps1`.
3. Find **Teams Bar Hider** in the notification area, including the hidden-icons menu.

The installer copies the helper to `%LOCALAPPDATA%\TeamsBarHider`, starts it and enables startup for your account. To run without installation or automatic startup, launch `TeamsBarHider.exe` directly.

Right-click the tray icon to pause, restore the toolbar, change startup behavior or quit. Double-click to toggle automatic hiding. **Restore and pause** attempts to bring the toolbar back without immediately hiding it again. Normal quit also attempts to restore toolbars hidden by the running helper.

Run `Uninstall.ps1` to request shutdown and remove automatic startup. Application files remain available for reuse and can be deleted after the helper exits.

### macOS

Requires macOS 12 or later. Packages run on the architecture named in the filename; building from source uses your Mac's architecture.

1. Extract the macOS package.
2. Open `Install.command` to copy the app to `~/Applications` and enable startup for your account.
3. Allow **Teams Bar Hider** in **System Settings → Privacy & Security → Accessibility** when prompted.

Use the menu-bar icon to pause, restore the toolbar, change startup behavior or quit. To run without automatic startup, open the app directly instead of using the installer.

Run `Uninstall.command` to request shutdown and remove its login agent. The app remains in `~/Applications` and can be deleted after it exits.

Builds are not notarized with Apple or signed with a Windows publisher certificate. macOS builds use an ad-hoc signature, so Gatekeeper may prevent opening a downloaded copy. Follow your organization's security policy; building locally is an alternative.

## Compatibility

Teams updates can change window titles and accessibility behavior. Recognition currently covers English and Turkish sharing-toolbar titles. Other languages and Teams versions may need additional verified patterns.

On Windows, the helper checks the process, window class and toolbar title before hiding a window. It restores only windows that still match the original process identity.

On macOS, the helper uses Accessibility to minimize a recognized toolbar or, if unsupported, move it beyond the desktop. Restoration attempts to reverse the change. If Teams or macOS prevents either hiding method, the menu reports that the toolbar cannot be hidden. Apple's native screen-sharing and recording indicators remain visible.

Hiding the toolbar removes its direct sharing controls from view. Restore and pause the helper whenever you need them. A forced termination, permission change or Teams window change can prevent cleanup. If necessary, stop and restart sharing from Teams to recreate the toolbar.

## Build from source

Clone this repository, then run the command for your platform from its root. There are no third-party runtime dependencies.

**Windows** — requires the .NET Framework C# compiler:

```powershell
./windows/build.ps1
```

The build compiles the helper, runs 11 targeting and native hide/restore checks, and places the app, installation scripts and notices in `dist/windows/`. Test logs go to `temp/verification/`.

**macOS** — requires Xcode Command Line Tools:

```sh
bash macos/build.sh
```

The build compiles for macOS 12 or later, runs seven targeting checks, verifies the ad-hoc signature and places the app, installation scripts and notices in `dist/macos/`.

CI runs both builds for pushes to `main` and pull requests. These checks exercise targeting rules and platform primitives; actual toolbar behavior needs an active Teams screen-sharing session on the target machine.

## Privacy

The helper makes no network requests and does not record meeting content or participant names. Window titles are read locally to identify the sharing toolbar.

On Windows, `TeamsBarHider.exe --inspect` writes process IDs, window classes and recognition flags to `inspection.txt` beside the executable. On macOS, `--inspect` prints counts and match flags; the running app writes local state to `~/Library/Application Support/TeamsBarHider/status.json`.

When reporting a compatibility issue, include your OS version, Teams version and toolbar language. Avoid sharing meeting titles, participant details or unredacted captures.

## License

[MIT](LICENSE). See [third-party notices](THIRD-PARTY-NOTICES.md) for prior work and platform references. This project is independent of Microsoft and is not affiliated with or endorsed by Microsoft.
