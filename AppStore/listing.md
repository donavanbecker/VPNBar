# App Store listing

Text for App Store Connect. Keep it here so it's easy to update with each release.

## Name

VPN Bar - Quick Toggle

"VPN Bar" and "VPNBar" were already taken. The app still shows as VPN Bar on the Mac.

## Subtitle (30 characters max)

VPN control from the menu bar

## Category

Utilities

## Promotional text (170 characters max)

Connect and disconnect the VPNs already set up on your Mac from the menu bar, Control Center, or a keyboard shortcut.

## Description

VPN Bar puts the VPNs configured on your Mac one click away.

VPN Bar doesn't provide a VPN service. It works with the VPNs you've already set up in System Settings or through a VPN provider's app, and lists them automatically as you add or remove them.

- Menu bar: see every VPN and turn each one on or off.
- Control Center: add a toggle for any VPN, or one that follows the VPN you used last.
- Keyboard shortcut: press Control-Option-V in any app to connect or disconnect your most recent VPN.
- Connection time: see how long each VPN has been connected.
- Notifications: find out when a VPN connects, disconnects, or drops unexpectedly.
- Reconnect: optionally reconnect a VPN automatically when it drops.

VPN Bar collects no data and contains no analytics or tracking.

## Keywords (100 characters max)

vpn,menu bar,control center,toggle,connect,disconnect,network,ikev2,wireguard,shortcut

## Support URL

https://github.com/donavanbecker/VPNBar

## Privacy policy URL

https://github.com/donavanbecker/VPNBar/blob/main/PRIVACY.md

## App Privacy

Data Not Collected.

## Notes for App Review

VPN Bar is a controller for VPN configurations the user has already set up in macOS. It doesn't provide a VPN service, create VPN configurations, or route any traffic, so guideline 5.4 shouldn't apply. It doesn't use NEVPNManager.

How it works: the app runs /usr/sbin/scutil --nc list, start and stop to read and change the state of the Mac's existing VPN services. The Control Center control is a WidgetKit extension that asks the app to make the change.

Temporary exception: inside the App Sandbox, scutil can't reach the VPN session manager and reports every VPN as disconnected. The app asks for com.apple.security.temporary-exception.mach-lookup.global-name for com.apple.nesessionmanager only, so it can show the real status and connect and disconnect. It uses no other exceptions.

To test, the Mac needs at least one VPN configuration. If yours has none, open System Settings > VPN > Add VPN Configuration > IKEv2, enter any name and server address, and save. It appears in VPN Bar right away. Connecting to a made-up server fails, and VPN Bar reports that, but the configuration shows the app reading and controlling VPN state.

VPN Bar is a menu bar app with no Dock icon. After launching it, click the shield in the menu bar.
