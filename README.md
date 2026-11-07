# VPN Bar

Connect to the VPNs configured on your Mac from the menu bar or Control Center.

VPN Bar doesn't store VPN settings of its own. It lists whatever macOS has set up, so VPNs you add in System Settings or through another VPN's app appear automatically.

## Install

Requires macOS 26 or later.

1. Download the latest zip from [Releases](../../releases).
2. Unzip it and move **VPN Bar** to Applications.
3. Open it, then look for the shield in the menu bar.

To add a toggle to Control Center, open **Control Center > Edit Controls** and add **VPN**. Add it once per VPN and choose which VPN each toggle controls. A toggle with no VPN chosen follows the one you used most recently.

## Features

- **Notifications:** VPN Bar tells you when a VPN connects, disconnects or drops. Turn this off with **Notify When VPNs Connect or Drop**.
- **Reconnect Dropped VPNs:** when a VPN you connected through VPN Bar disconnects without you turning it off there, VPN Bar tries to reconnect it three times. This is off until you turn it on. Disconnect from VPN Bar or Control Center so it isn't treated as a drop.
- **Keyboard shortcut:** press Control-Option-V in any app to connect or disconnect the VPN you used most recently. Turn this off with **Toggle Last VPN with ⌃⌥V**.

## Development

Open `VPNBar.xcodeproj` in Xcode and run the **VPNBar** scheme. Signing is set to your Apple Development certificate and team `GV6ATLNHPQ`.

To change the app icon, edit `Design/make-icon.swift`, then run:

```bash
swift Design/make-icon.swift Shared/AppIcon.icon
```

## Releasing

Pushing a version tag builds, signs and notarizes the app, then publishes a GitHub Release:

```bash
git tag v1.0.0
```

```bash
git push origin v1.0.0
```

### Required repository secrets

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12` | Your Developer ID Application certificate, exported as `.p12` and base64-encoded |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |
| `NOTARY_KEY_P8` | An App Store Connect API key (`.p8`), base64-encoded |
| `NOTARY_KEY_ID` | That API key's ID |
| `NOTARY_ISSUER_ID` | Your App Store Connect issuer ID |
| `SPARKLE_PRIVATE_KEY` | The private half of the update signing key, whose public half is `SUPublicEDKey` in `Config/App-Info.plist` |

### Updates

Release builds check daily for new versions using [Sparkle](https://sparkle-project.org) and offer to install them. Each release publishes an `appcast.xml` describing itself, and the app reads it from the latest release.

Back up the update signing key. If it's lost, installed copies can't verify new versions, and everyone would need to download the next version by hand.
