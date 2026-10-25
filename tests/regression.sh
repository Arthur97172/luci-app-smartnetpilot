#!/bin/sh
# Regression checks for the install-time network corruption bug.
#
# These tests source the init script (which only defines functions) and
# exercise the safety gates directly. They never touch the host network.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INIT="$ROOT/root/etc/init.d/smartnetpilot"
RPC="$ROOT/root/usr/libexec/rpcd/luci.smartnetpilot"
JS="$ROOT/htdocs/luci-static/resources/view/smartnetpilot/smartnetpilot.js"
TMP=$(mktemp -d)

trap 'rm -rf "$TMP"' EXIT

FAILS=0

ok() {
    printf 'ok - %s\n' "$1"
}

fail() {
    printf 'FAIL - %s\n' "$1"
    FAILS=$((FAILS + 1))
}

assert_eq() {
    if [ "$1" = "$2" ]; then
        ok "$3"
    else
        fail "$3 (expected '$2', got '$1')"
    fi
}

assert_file_contains() {
    if grep -q -- "$2" "$1"; then
        ok "$3"
    else
        fail "$3"
    fi
}

assert_file_lacks() {
    if grep -q -- "$2" "$1"; then
        fail "$3"
    else
        ok "$3"
    fi
}

assert_function_lacks() {
    if sed -n "/^$1() {/,/^}/p" "$INIT" | grep -q -- "$2"; then
        fail "$3"
    else
        ok "$3"
    fi
}

# Fake uci used by resolve_wan_interface().
uci() {
    case "$*" in
        *"get network.wan.device"*) printf '%s' "${FAKE_WAN_DEVICE:-}" ;;
        *"get network.wan.ifname"*) printf '%s' "${FAKE_WAN_IFNAME:-}" ;;
        *) return 1 ;;
    esac
}

. "$INIT"
log() { :; }
SYS_CLASS_NET="$TMP/net"
APPLY_MARKER="$TMP/apply.marker"

# ---------------------------------------------------------------- install/boot
APPLY_CALLED=0
apply_config() { APPLY_CALLED=1; }

start
assert_eq "$APPLY_CALLED" 0 "start() is a no-op (package install/upgrade)"

boot
assert_eq "$APPLY_CALLED" 0 "boot() does not replay the configuration"

assert_function_lacks start 'config_load' "start() never loads smartnetpilot"
assert_function_lacks start 'configure_network' "start() never writes network config"

# ---------------------------------------------------------------------- reload
APPLY_CALLED=0
rm -f "$APPLY_MARKER"
reload
assert_eq "$APPLY_CALLED" 0 "reload() without an apply request does nothing"

APPLY_CALLED=0
: > "$APPLY_MARKER"
reload
assert_eq "$APPLY_CALLED" 1 "reload() applies when the UI requested it"
if [ -e "$APPLY_MARKER" ]; then
    fail "apply request is consumed exactly once"
else
    ok "apply request is consumed exactly once"
fi

APPLY_CALLED=0
: > "$APPLY_MARKER"
touch -d '10 minutes ago' "$APPLY_MARKER" 2>/dev/null || touch -t 200001010000 "$APPLY_MARKER"
reload
assert_eq "$APPLY_CALLED" 0 "reload() ignores a stale apply request"

# preflight_config() reads the caller's locals (ash/dash use dynamic scoping).
# Guard that assumption so a shell change cannot silently break every apply.
SCOPE_OUT=$(sh -c 'f() { local x=ok; g; }; g() { printf "%s" "$x"; }; f')
assert_eq "$SCOPE_OUT" "ok" "shell exposes caller locals to called functions"

# ------------------------------------------------------------------- preflight
reset_cfg() {
    wan_proto=""
    wan_pppoe_user=""
    wan_pppoe_pass=""
    dhcp_proto="dhcp"
    wan_ipaddr=""
    wan_netmask=""
    lan_proto="static"
    lan_ipaddr=""
    lan_netmask="255.255.255.0"
    setlan="0"
}

reset_cfg
if preflight_config; then
    fail "empty mode is rejected"
else
    ok "empty mode is rejected"
fi

reset_cfg
wan_proto="pppoe"
wan_pppoe_user="user"
if preflight_config; then
    fail "PPPoE without password is rejected"
else
    ok "PPPoE without password is rejected"
fi

reset_cfg
wan_proto="pppoe"
wan_pppoe_user="user"
wan_pppoe_pass="pass"
if preflight_config; then
    ok "valid PPPoE config is accepted"
else
    fail "valid PPPoE config is accepted"
fi

reset_cfg
wan_proto="dhcp"
dhcp_proto="static"
wan_ipaddr="999.1.1.1"
wan_netmask="255.255.255.0"
if preflight_config; then
    fail "invalid static WAN address is rejected"
else
    ok "invalid static WAN address is rejected"
fi

reset_cfg
wan_proto="dhcp"
dhcp_proto="static"
wan_ipaddr="192.168.100.2"
wan_netmask="255.255.255.0"
if preflight_config; then
    ok "valid static WAN config is accepted"
else
    fail "valid static WAN config is accepted"
fi

reset_cfg
wan_proto="siderouter"
lan_proto="static"
lan_ipaddr="192.168.1.1"
lan_netmask="255.255.255.0"
if preflight_config; then
    ok "valid static side-router LAN is accepted"
else
    fail "valid static side-router LAN is accepted"
fi

reset_cfg
wan_proto="siderouter"
lan_proto="static"
lan_ipaddr="not-an-address"
if preflight_config; then
    fail "invalid side-router LAN address is rejected"
else
    ok "invalid side-router LAN address is rejected"
fi

reset_cfg
wan_proto="dhcp"
setlan="1"
lan_ipaddr="bad"
if preflight_config; then
    fail "invalid LAN address with setlan=1 is rejected"
else
    ok "invalid LAN address with setlan=1 is rejected"
fi

reset_cfg
wan_proto="dhcp"
dhcp_proto="carrier-pigeon"
if preflight_config; then
    fail "unknown WAN mode is rejected"
else
    ok "unknown WAN mode is rejected"
fi

reset_cfg
wan_proto="siderouter"
lan_proto="carrier-pigeon"
if preflight_config; then
    fail "unknown side-router LAN mode is rejected"
else
    ok "unknown side-router LAN mode is rejected"
fi

# The shipped config must stay unconfigured so a package install cannot apply.
assert_file_lacks "$ROOT/root/etc/config/smartnetpilot" 'option wan_proto' \
    "shipped default config has no access mode"

# End-to-end guard: applying the shipped (unconfigured) config must not issue
# a single mutating uci call. Runs in a clean shell with uci stubbed out.
NOAPPLY_OUT=$(INIT="$INIT" TMP="$TMP" sh -c '
    set -u
    . "$INIT"
    log() { :; }
    LOCK="$TMP/lock"
    RECORD="$TMP/uci-calls"
    : > "$RECORD"

    uci() {
        [ "$1" = "-q" ] && shift
        case "$1" in
            get)
                [ "$2" = "smartnetpilot.default" ] && return 0
                return 1
                ;;
            set|delete|add|add_list|commit|revert)
                printf "%s\n" "$*" >> "$RECORD"
                ;;
            *)
                return 1
                ;;
        esac
    }

    config_load() { :; }
    config_get() {
        case "$3" in
            lan_netmask) eval "$1=255.255.255.0" ;;
            lan_proto)   eval "$1=static" ;;
            *)           eval "$1=" ;;
        esac
    }
    config_foreach() { configure_network default; }
    backup_configs() { echo "$TMP/backup"; }

    apply_config
    echo "failed=$APPLY_FAILED"
    echo "writes=$(wc -l < "$RECORD")"
')

case "$NOAPPLY_OUT" in
    *failed=1*writes=0*)
        ok "unconfigured config performs zero UCI writes"
        ;;
    *)
        fail "unconfigured config performs zero UCI writes ($(printf '%s' "$NOAPPLY_OUT" | tr '\n' ' '))"
        ;;
esac

# Same guard with a stale UI marker: it must not be treated as consent.
STALE_OUT=$(INIT="$INIT" TMP="$TMP" sh -c '
    set -u
    . "$INIT"
    log() { :; }
    LOCK="$TMP/lock2"
    RECORD="$TMP/uci-calls2"
    APPLY_MARKER="$TMP/stale.marker"
    : > "$RECORD"
    : > "$APPLY_MARKER"
    touch -t 200001010000 "$APPLY_MARKER"

    uci() {
        [ "$1" = "-q" ] && shift
        case "$1" in
            get)
                [ "$2" = "smartnetpilot.default" ] && return 0
                return 1
                ;;
            set|delete|add|add_list|commit|revert)
                printf "%s\n" "$*" >> "$RECORD"
                ;;
            *)
                return 1
                ;;
        esac
    }

    config_load() { :; }
    config_get() {
        case "$3" in
            lan_netmask) eval "$1=255.255.255.0" ;;
            lan_proto)   eval "$1=static" ;;
            *)           eval "$1=" ;;
        esac
    }
    config_foreach() { configure_network default; }
    backup_configs() { echo "$TMP/backup"; }

    reload
    echo "writes=$(wc -l < "$RECORD")"
')

case "$STALE_OUT" in
    *writes=0*)
        ok "stale marker performs zero UCI writes"
        ;;
    *)
        fail "stale marker performs zero UCI writes ($(printf '%s' "$STALE_OUT" | tr '\n' ' '))"
        ;;
esac

# --------------------------------------------------------- WAN port detection
mkdir -p "$TMP/net/wan" "$TMP/net/lan1" "$TMP/net/eth0" "$TMP/net/eth9" "$TMP/net/usb0"

wan_interface=""
FAKE_WAN_DEVICE=""
FAKE_WAN_IFNAME=""
resolve_wan_interface
assert_eq "$wan_interface" "wan" "auto-detects the DSA wan port"

wan_interface=""
FAKE_WAN_DEVICE="eth9"
resolve_wan_interface
assert_eq "$wan_interface" "eth9" "honours the existing network.wan.device"

wan_interface="usb0"
FAKE_WAN_DEVICE="eth9"
resolve_wan_interface
assert_eq "$wan_interface" "usb0" "honours the explicit interface choice"

wan_interface="bogus"
FAKE_WAN_DEVICE=""
FAKE_WAN_IFNAME=""
resolve_wan_interface
assert_eq "$wan_interface" "wan" "ignores a missing explicit interface"

mkdir -p "$TMP/net2/lan1" "$TMP/net2/eth0"
SYS_CLASS_NET="$TMP/net2"
wan_interface=""
FAKE_WAN_DEVICE=""
FAKE_WAN_IFNAME=""
if resolve_wan_interface; then
    fail "refuses to guess eth0 on a DSA device without a wan port"
else
    ok "refuses to guess eth0 on a DSA device without a wan port"
fi

# --------------------------------------------------------------- static checks
assert_file_lacks "$INIT" 'network.@device[0].ports' "never rewrites br-lan ports"
assert_file_lacks "$INIT" 'wan_proto=$(uci' "never infers the mode from network.wan.proto"
assert_file_contains "$INIT" 'consume_apply_request' "reload is gated by an explicit apply request"
assert_file_contains "$RPC" 'arm_apply' "rpcd exposes the apply-request method"
assert_file_contains "$JS" 'callArmApply' "the view arms an apply before committing"

if [ "$FAILS" -ne 0 ]; then
    printf '\n%d check(s) failed\n' "$FAILS"
    exit 1
fi

printf '\nAll regression checks passed.\n'
