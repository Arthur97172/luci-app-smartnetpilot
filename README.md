# 智能网络向导（luci-app-smartnetpilot）

简体中文 | [English](README.en.md)

一个面向 OpenWrt / LuCI 的「傻瓜式」网络设置向导。选一种上网方式，按页面提示填写必要信息，点一下「保存并应用」即可完成 WAN、LAN、IPv6、DNS、无线和 HTTPS 的配置——全程不需要输入 Linux 命令。

插件位于 **网络 → 智能网络向导**（`admin/network/smartnetpilot`）。首页是三张模式卡片：

| 模式 | 适用场景 |
| --- | --- |
| 宽带拨号（PPPoE） | 运营商提供了宽带账号和密码，线路需要 PPPoE 认证 |
| 连接现有路由器（DHCP） | 新路由器接在光猫或已有网关后面，WAN 自动获取地址（也可以固定 IP） |
| 旁路由（Side Router） | 保留现有主路由器，把本设备当作旁路由或附加服务 |

选好模式后进入四个标签页：**网络模式**、**WAN 设置**、**无线设置**、**其他设置**。

## 安装

### 从 Releases 安装

1. 打开 [Releases](https://github.com/Arthur97172/luci-app-smartnetpilot/releases) 页面，下载安装包。
2. 把安装包上传到设备（例如 `/tmp`），然后安装：

   **OpenWrt 24.10 及更早（opkg）**

   ```sh
   opkg install /tmp/luci-app-smartnetpilot_*.ipk

   #可选，安装简体中文语言包：

   opkg install /tmp/luci-i18n-smartnetpilot-zh-cn_*.ipk
   ```

   **OpenWrt 25.12+（apk）**

   ```sh
   apk add --allow-untrusted /tmp/luci-app-smartnetpilot-*.apk

   #可选，安装简体中文语言包：

   apk add --allow-untrusted /tmp/luci-i18n-smartnetpilot-zh-cn-*.apk
   ```

3. 刷新 LuCI，入口出现在「网络 → 智能网络向导」。

> 未安装语言包时界面显示英文。安装包架构为 `all`，ARM / x86 / MIPS 等平台通用。

### 从源码编译

```sh
cd openwrt
./scripts/feeds update -a
./scripts/feeds install -a
git clone https://github.com/Arthur97172/luci-app-smartnetpilot.git package/luci-app-smartnetpilot
make menuconfig     # LuCI → Applications → luci-app-smartnetpilot
make package/luci-app-smartnetpilot/compile V=s
```

编译产物位于 `bin/packages/<架构>/base/` 目录下。

## 使用方法

1. 打开「网络 → 智能网络向导」，在首页三张卡片里选择接入方式。当前正在使用的模式会标注「当前」。
2. 在「WAN 设置」里按所选模式填写内容：
   - **宽带拨号**：宽带账号、密码；可指定 WAN 物理端口，也可以自定义 DNS。
   - **连接现有路由器**：WAN 用 DHCP 自动获取，或选择「静态 IPv4 地址」后填写地址、掩码、网关和 DNS。
   - **旁路由**：设置本机 LAN 地址（静态或由上级分配），并填写主路由器地址作为网关；「Side router DNS servers」会下发给局域网客户端。
3. 需要改 Wi-Fi 时填写「无线设置」里的名称（SSID）和密码（WPA2-PSK，至少 8 位）。留空则不改动现有无线配置。
4. 「其他设置」可以开启 IPv6、关闭 LAN 的 DHCP 服务器、向客户端通告指定 DNS、把管理页面重定向到 HTTPS、开启 SYN Flood 防护。
5. 点击页面底部的「保存并应用」。只想暂存修改时，可以先点「保存」。
6. 如果改动会影响你访问设备的方式（管理地址变化、LAN 变成 DHCP 客户端、HTTPS 开关切换、无线名称或密码变化），页面会先弹出确认框，逐条列出将会发生什么。确认后配置开始应用；管理地址变化时当前页面会断开，并自动打开新地址。

> 旁路由模式下，如果主路由器已经在提供 DHCP，记得打开「关闭 LAN DHCP 服务器」，同一网络中只应有一个 DHCP 服务器。

## 工作原理

前端只把易读的 UCI 选项写入 `/etc/config/smartnetpilot`，例如
`smartnetpilot.default.wan_proto=pppoe`、`smartnetpilot.default.lan_ipaddr=192.168.2.1`，浏览器本身不执行任何命令。

`/etc/init.d/smartnetpilot` 在应用时（由 ucitrack 触发）读取这些选项，翻译成系统真正使用的配置：

- **network**：按模式重建 `wan` / `wan6`（PPPoE、DHCP 或静态地址），旁路由模式下改写 LAN；自动识别物理网口并挑选 WAN 口，单网口设备同一个口同时承担 LAN 与 WAN。
- **firewall**：重建 WAN 区域和 lan→wan 转发，写入 SYN Flood 开关；检测到 `dockerd` 时补上 Docker 区域与相关转发。
- **dhcp**：按需关闭 LAN 的 DHCP 服务器，或通过 `dhcp_option 6` 向客户端下发指定 DNS。
- **wireless**：把 SSID / 密码写入所有 AP 接口和默认 radio，加密方式为 WPA2-PSK。
- **uhttpd 或 nginx**：HTTPS 开关与 HTTP→HTTPS 重定向；没有 nginx 时用 uhttpd，并生成 10 年有效期的本地自签证书。
- 提交前把 `network`、`firewall`、`dhcp`、`wireless`、`system`、`uhttpd`、`nginx` 备份到 `/tmp/smartnetpilot_backup_<时间戳>`，提交失败会自动恢复。
- 提交成功后，在后台重启 network，并按需 reload WiFi、system、rpcd、uhttpd、dnsmasq 和 firewall。

写入 IPv4 之前会校验格式（4 段、每段 0–255），非法值只记录日志并跳过。

开机时 `boot()` 钩子直接返回，不会重新套用向导设置，避免重启后覆盖你后来手动做的调整。

前端通过 RPC `luci.smartnetpilot get_ip` 读取当前 LAN 地址，只用于在页面上显示和管理地址变化提示。

## 主题与兼容性

- 支持 LuCI 亮色 / 暗色主题，无需手动切换。
- 已适配 `luci-theme-bootstrap`（OpenWrt 24.10 / 25.12 默认主题）与 `luci-theme-argon` 2.x / 3.x。
- 明暗判断依次尝试：主题显式标记（`data-theme`、`dark` 类名）→ 页面背景亮度 → `prefers-color-scheme`，并监听主题切换与系统设置变化。
- 样式表放在插件自己的作用域内，只改变本页外观，不影响其他 LuCI 页面。

## 安全说明

- 每次应用前自动备份相关配置，提交失败立即恢复。
- IPv4 地址先校验再写入，非法值不会被写进 UCI。
- 会影响访问方式的修改（管理地址、LAN DHCP 角色、HTTPS、无线密码）先确认再应用。
- 管理地址变化或 LAN 变成 DHCP 客户端时走 LuCI 的 unchecked 应用路径，避免浏览器连不上新地址而触发自动回滚，把网络配置又改回去。
- HTTPS 使用本机生成的自签证书，浏览器首次访问会提示不受信任，属正常现象；设备已安装 nginx 时优先通过 nginx 完成跳转。
- 应用过程有锁文件保护（`/var/lock/smartnetpilot-boot.lock`），300 秒后视为残留并自动清理，避免两个应用流程同时改网络配置。
- 除管理系统本身外，向导不额外开放任何端口或服务。

## 文件结构

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

## 依赖

- OpenWrt 24.10 或更新版本，带 LuCI（JavaScript 视图，`luci-base`）
- `uhttpd`（默认）或 `nginx`：HTTPS 管理在两者之一上生效
- `openssl`：开启 HTTPS 时生成本地证书
- `dnsmasq` 与系统防火墙（`firewall4` / `firewall3`）：随 OpenWrt 自带
- 无线设置需要设备存在 `/etc/config/wireless` 与 `wifi` 命令；无无线的设备会自动隐藏该标签页

## 许可证

GPL-3.0-only
