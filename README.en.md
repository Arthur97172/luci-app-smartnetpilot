# Smart NetPilot (luci-app-smartnetpilot)

[简体中文](README.md) | English

A fool-proof network setup wizard for OpenWrt / LuCI. Pick a connection mode,
fill in the few fields the page asks for, and click **Save & Apply** — WAN,
LAN, IPv6, DNS, wireless and HTTPS are configured for you, without typing a
single Linux command.

The package lives under **Network → Smart NetPilot**
(`admin/network/smartnetpilot`). The start page offers three mode cards:

| Mode | When to use it |
| --- | --- |
| PPPoE Dial-up | Your ISP gave you a broadband account and the line needs PPPoE authentication |
| DHCP Client | The router sits behind a modem or an existing gateway and gets its WAN address automatically (a static address is possible too) |
| Side Router | Keep the existing main router and use this device for additional services |

After choosing a mode you get four tabs: **Network Mode**, **WAN Settings**,
**Wireless Settings** and **Other Settings**.

## Installation

### From Releases

1. Open the [Releases](https://github.com/Arthur97172/luci-app-smartnetpilot/releases)
   page and download the package for your firmware.
2. Upload it to the device (for example `/tmp`), then install:

   **OpenWrt 24.10 and older (opkg)**

   ```sh
   opkg install /tmp/luci-app-smartnetpilot_*.ipk

   #Optional, Simplified Chinese language pack:

   opkg install /tmp/luci-i18n-smartnetpilot-zh-cn_*.ipk
   ```

   **OpenWrt 25.12+ (apk)**

   ```sh
   apk add --allow-untrusted /tmp/luci-app-smartnetpilot-*.apk

   #Optional, Simplified Chinese language pack:

   apk add --allow-untrusted /tmp/luci-i18n-smartnetpilot-zh-cn-*.apk
   ```

3. Refresh LuCI; the entry appears under **Network → Smart NetPilot**.

> Without the language pack the interface stays in English. The package is
> architecture independent (`all`), so one artifact works on ARM, x86, MIPS
> and every other platform.

### From source

```sh
cd openwrt
./scripts/feeds update -a
./scripts/feeds install -a
git clone https://github.com/Arthur97172/luci-app-smartnetpilot.git package/luci-app-smartnetpilot
make menuconfig     # LuCI → Applications → luci-app-smartnetpilot
make package/luci-app-smartnetpilot/compile V=s
```

The built packages end up in `bin/packages/<arch>/base/`.

## Usage

1. Open **Network → Smart NetPilot** and pick a mode on the start page. The
   mode currently in use is marked **Current**.
2. Fill in the **WAN Settings** tab according to that mode:
   - **PPPoE Dial-up**: broadband username and password; you may pick the WAN
     port and add custom DNS servers.
   - **DHCP Client**: let WAN obtain an address automatically, or choose
     **Static IPv4 address** and enter address, netmask, gateway and DNS.
   - **Side Router**: set this device's LAN address (static or assigned by the
     upstream router) and enter the main router as the gateway; **Side router
     DNS servers** are handed to LAN clients.
3. To change Wi-Fi, fill in the SSID and password under **Wireless Settings**
   (WPA2-PSK, at least 8 characters). Leave them empty to keep the current
   wireless configuration untouched.
4. **Other Settings** toggles IPv6, the LAN DHCP server, the DNS server
   advertised to clients, HTTPS redirection and SYN-flood protection.
5. Click **Save & Apply** at the bottom of the page. Use **Save** first if you
   only want to stage the changes.
6. If a change affects how you reach the device — the management address, the
   LAN DHCP role, the HTTPS setting, or the wireless name/password — a
   confirmation dialog lists what will happen before anything is applied. When
   the management address changes, the page disconnects and then opens the new
   address.

> In side-router mode, turn on **Disable the LAN DHCP server** when the main
> router already runs one: a network should only have a single DHCP server.

## How it works

The frontend only writes friendly UCI options to `/etc/config/smartnetpilot`,
e.g. `smartnetpilot.default.wan_proto=pppoe` or
`smartnetpilot.default.lan_ipaddr=192.168.2.1`. Nothing is executed by the
browser.

`/etc/init.d/smartnetpilot` translates those options into the settings the
system actually uses. It does so **only** when you click **Save & Apply**:

- Before committing, the view calls the RPC method `arm_apply`, which creates a
  one-shot request marker at `/tmp/smartnetpilot.apply`.
- The ucitrack `reload` hook writes configuration only when that marker exists.
  The marker is deleted as soon as it is consumed, and a marker older than
  300 seconds is ignored.
- Installation, upgrade (the package manager runs `start`), boot (the `boot`
  hook) and any other configuration commit therefore never touch the network.

Checks performed before anything is written:

- **Mode**: an empty `wan_proto`, or one that is not `pppoe` / `dhcp` /
  `siderouter`, is rejected — which is the state of a fresh install.
- **Required fields**: missing PPPoE credentials or an invalid static WAN/LAN
  address or netmask rejects the whole apply.
- **WAN port**: the explicitly chosen port wins, then the existing
  `network.wan` `device`/`ifname`, then the DSA `wan` port. If none is usable
  the apply is refused; it never guesses a port or rewrites the `br-lan` bridge
  port list.

What gets written:

- **network**: rebuilds `wan` / `wan6` for the chosen mode (PPPoE, DHCP or
  static), or rewrites LAN in side-router mode.
- **firewall**: recreates the WAN zone and the lan→wan forwarding, applies the
  SYN-flood switch, and adds Docker zones and forwardings when `dockerd` is
  present.
- **dhcp**: disables the LAN DHCP server on request, or advertises the chosen
  DNS server through `dhcp_option 6`.
- **wireless**: writes the SSID and password (WPA2-PSK) to every AP interface
  and to the default radios.
- **uhttpd or nginx**: toggles HTTPS and the HTTP→HTTPS redirect; without nginx
  it uses uhttpd and generates a local self-signed certificate valid for
  10 years.
- Before committing, `network`, `firewall`, `dhcp`, `wireless`, `system`,
  `uhttpd` and `nginx` are backed up to
  `/tmp/smartnetpilot_backup_<timestamp>`; if the commit fails, the backup is
  restored.
- After a successful commit, network is restarted in the background and WiFi,
  system, rpcd, uhttpd, dnsmasq and firewall are reloaded as needed.

Every IPv4 value is validated (four octets, each 0–255) before it is written;
invalid values are logged and skipped.

The `boot()` hook returns immediately, so a reboot never re-applies the
wizard's settings and cannot overwrite changes you made later by hand. The
package manager calls `start()` on install or upgrade; that hook is a no-op
too, so installing the plugin by itself never changes the network.

The frontend calls the RPC method `luci.smartnetpilot get_ip` only to display
the current LAN address and to warn about management-address changes.

## Themes and compatibility

- Works in both the light and the dark variant of the LuCI theme, with no
  manual switch.
- Adapted to `luci-theme-bootstrap` (the default in OpenWrt 24.10 / 25.12) and
  to `luci-theme-argon` 2.x / 3.x.
- Theme detection tries, in order: explicit theme markers (`data-theme`, dark
  class names), the page background luminance, then `prefers-color-scheme`; it
  also listens for theme switches and system changes.
- The stylesheet is scoped to this page, so other LuCI pages are unaffected.

## Safety notes

- Installing, upgrading and booting never apply configuration; only **Save &
  Apply** in the wizard does, and it requires a one-shot request marker.
- An apply is refused when no access mode was chosen or required fields are
  missing, so a fresh default config cannot be translated into broken network
  settings.
- An apply is refused when no usable WAN port can be determined; the code never
  guesses a port or overwrites the LAN bridge.
- Relevant configuration files are backed up before every apply and restored
  if the commit fails.
- IPv4 values are validated before being written; invalid values never reach
  UCI.
- Changes that affect how you reach the device (management address, LAN DHCP
  role, HTTPS, wireless password) are confirmed before they are applied.
- When the management address changes or LAN becomes a DHCP client, the apply
  uses LuCI's unchecked path, so the browser cannot trigger an automatic
  rollback that would undo the new network configuration.
- HTTPS uses a locally generated self-signed certificate; browsers warn about
  it on first visit, which is expected. When nginx is installed, the redirect
  is configured through nginx instead.
- Applying takes a lock (`/var/lock/smartnetpilot-boot.lock`) that is treated
  as stale and removed after 300 seconds, so two apply runs never rewrite the
  network configuration at the same time.
- The wizard opens no ports or services beyond the management interface
  itself.

## Files

```
.
├── Makefile
├── htdocs/luci-static/resources/view/smartnetpilot/
│   ├── smartnetpilot.js
│   └── smartnetpilot.css
├── po/templates/smartnetpilot.pot
├── po/zh_Hans/smartnetpilot.po
└── root/
    ├── etc/config/smartnetpilot
    ├── etc/init.d/smartnetpilot
    ├── etc/uci-defaults/40-luci-smartnetpilot
    ├── usr/libexec/rpcd/luci.smartnetpilot
    └── usr/share/
        ├── luci/menu.d/luci-app-smartnetpilot.json
        ├── rpcd/acl.d/luci-app-smartnetpilot.json
        └── ucitrack/luci-app-smartnetpilot.json
```

## Requirements

- OpenWrt 24.10 or newer with LuCI (JavaScript views, `luci-base`)
- `uhttpd` (default) or `nginx` — HTTPS management is configured on whichever
  one is present
- `openssl` to generate the local certificate when HTTPS is enabled
- `dnsmasq` and the system firewall (`firewall4` / `firewall3`), both ship
  with OpenWrt
- The wireless settings need `/etc/config/wireless` and the `wifi` command; on
  a device without wireless the tab is hidden automatically

## License

GPL-3.0-only
