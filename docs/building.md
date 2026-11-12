# Building and running

Run commands from this repository's root. A standalone checkout includes the icons, fonts, asset catalogs, and browser preview; no desktop Rust checkout is needed.

## Xcode on macOS

1. Install Xcode with Swift 6.2 or later and XcodeGen.
2. Run `xcodegen generate` using `project.yml`.
3. Open `Sonora.xcodeproj`, select a development team, and choose an iPhone or simulator.
4. Build and run. The deployment target is iOS 17.0.

Edit `project.yml` rather than the generated Xcode project. Xcode uses `Sonora/Supporting/Info.plist`; xtool uses `Config/Info.plist` through `xtool.yml`.

The tested cross-build environment used Swift 6.4.1 and an iOS 27.1 SDK through xtool 1.22.2/WSL. This records the development environment, not compatibility with every older toolchain. The Xcode route is configured but was not independently exercised in that WSL session.

## xtool on Linux or WSL

Install Swift and xtool using the [xtool project instructions](https://github.com/xtool-org/xtool). Complete `xtool setup` with your own Apple developer credentials and SDK. SDKs, signing identities, profiles, and signed apps are not included here.

```sh
swift --version
swift sdk list
xtool --version
bash scripts/deploy.sh build
```

The helper expects `rsync`, xtool under `~/.local/bin`, and the Swiftly environment at `~/.local/share/swiftly/env.sh`. If your installation differs, adjust the helper locally or use a checkout on the Linux filesystem:

```sh
xtool dev build  # compile only
xtool dev        # build, sign, install
```

The helper syncs to `~/sonora-ios` with `rsync --delete`, preserving that folder's build caches. Do not keep unrelated work in that destination. The built app is `~/sonora-ios/xtool/Sonora.app`. Building directly from a Windows-mounted checkout can fail when the compiler writes outputs.

Installation requires your own account, a trusted/unlocked iPhone, and Developer Mode where required. Provisioning expiration depends on your account and Apple tooling; inspect your profile if a development build stops opening.

## Windows USB connection through WSL

The working setup used Windows Apple Devices for USB access and a local WSL relay, rather than passing the USB device into Linux.

1. Install Apple Devices on Windows; connect, unlock, and trust the phone.
2. Install Linux tools:

```sh
sudo apt-get update
sudo apt-get install -y libimobiledevice-utils usbmuxd socat rsync
```

3. If needed to reach Windows' localhost service, enable mirrored networking in `.wslconfig` in your Windows user directory:

```ini
[wsl2]
networkingMode=mirrored
```

Apply it by shutting down and reopening WSL after finishing other WSL work.

4. Check the Windows service in PowerShell:

```powershell
Get-NetTCPConnection -LocalPort 27015
```

5. Stop the Linux usbmuxd instance and remove its stale socket before starting the relay. This interrupts other Linux device sessions:

```sh
sudo pkill usbmuxd
sudo rm -f /var/run/usbmuxd
sudo socat UNIX-LISTEN:/var/run/usbmuxd,fork,mode=660,group="$(id -gn)" TCP:127.0.0.1:27015
```

The relay uses the calling user's group for local access. Run the commands in WSL; keep that terminal open. In another WSL terminal:

```sh
idevice_id -l
bash scripts/deploy.sh
```

Do not publish your device identifier. Enable Developer Mode and trust your development profile on the phone if prompted. Updating the same bundle in place preserved data in the tested workflow; keep the same signing identity and bundle ID. Uninstalling can remove local data.

## Resources

Xcode uses the asset catalog; SwiftPM uses committed PNG icons. After editing SVG sources, install ImageMagick with SVG support and run:

```sh
bash scripts/rasterize-icons.sh
```

This replaces `Sonora/Resources/Icons`. Commit source and generated changes together and preserve their license notices.

## Troubleshooting

| Problem | Check |
| --- | --- |
| Build output permission errors under `/mnt/c` | Use the helper or a Linux-filesystem checkout. |
| Swift/xtool not found | Activate Swiftly and check installation paths against the helper. |
| No phone appears | Unlock/reconnect, check Windows trust, and check relay/service access. |
| Signing/profile error | Check your own authentication and provisioning. |
| Provider song fails | See [limitations](limitations.md); test an imported local song separately. |
| Offline lookup fails | Check Offline music and include the exact app error, not credentials or a container backup. |
