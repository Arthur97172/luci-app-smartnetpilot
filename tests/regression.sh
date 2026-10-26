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
ACL="$ROOT/root/usr/share/rpcd/acl.d/luci-app-smartnetpilot.json"
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

assert_line() {
    if printf '%s\n' "$1" | grep -qx -- "$2"; then
        ok "$3"
    else
        fail "$3 (got: $(printf '%s' "$1" | tr '\n' ' '))"
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
CONFIG_DIR="$TMP/config"
STATE_DIR="$TMP/state"
RESULT_FILE="$TMP/result"

# Never touch the host when exercising the rollback paths.
reload_services() { :; }
start_rollback_waiter() { :; }

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

# Field report: a DSA device exposes only the CPU conduit eth0 (no physical
# eth0) and names its ports lan2..lan4/wan. Applying must leave br-lan alone
# instead of rebuilding its ports from the /sys/class/net enumeration.
mkdir -p "$TMP/net3/eth0" "$TMP/net3/lan2" "$TMP/net3/lan3" "$TMP/net3/lan4" \
         "$TMP/net3/wan" "$TMP/net3/wlan0"
DSA_OUT=$(INIT="$INIT" TMP="$TMP" sh -c '
    set -u
    . "$INIT"
    log() { :; }
    SYS_CLASS_NET="$TMP/net3"
    CONFIG_DIR="$TMP/config"
    RECORD="$TMP/uci-dsa"
    : > "$RECORD"

    uci() {
        [ "$1" = "-q" ] && shift
        case "$1" in
            get) return 1 ;;
            set|delete|add|add_list|commit|revert|batch)
                printf "%s\n" "$*" >> "$RECORD"
                ;;
            *) return 1 ;;
        esac
    }

    config_load() { :; }
    config_get() {
        case "$3" in
            wan_proto)   eval "$1=siderouter" ;;
            lan_proto)   eval "$1=static" ;;
            lan_ipaddr)  eval "$1=192.168.10.1" ;;
            lan_netmask) eval "$1=255.255.255.0" ;;
            ipv6|lan_dhcp|setlan|dnsset|synflood|https) eval "$1=0" ;;
            *)           eval "$1=" ;;
        esac
    }
    config_foreach() { configure_network default; }
    backup_configs() { mkdir -p "$TMP/backup-dsa"; echo "$TMP/backup-dsa"; }

    configure_network default
    echo "failed=$APPLY_FAILED"
    cat "$RECORD"
')
case "$DSA_OUT" in
    *failed=0*)
        if printf '%s\n' "$DSA_OUT" | grep -q 'ports'; then
            fail "a DSA device with only the eth0 CPU port keeps its bridge ports"
        else
            ok "a DSA device with only the eth0 CPU port keeps its bridge ports"
        fi
        ;;
    *)
        fail "a DSA device with only the eth0 CPU port keeps its bridge ports (apply failed)"
        ;;
esac

# board.json is the authoritative list of physical ports: a DSA CPU conduit
# (eth0) is absent from it while a real x86 NIC is present.
mkdir -p "$TMP/net4/eth0" "$TMP/net4/lan1" "$TMP/net4/lan2" "$TMP/net4/wan"
cat > "$TMP/fake-jshn.sh" <<'EOF'
json_init() { :; }
json_load_file() { [ -r "$1" ]; }
json_select() { [ "$1" = ".." ] || JSON_KEY="$1"; return 0; }
json_get_keys() { eval "$1='lan wan'"; }
json_get_values() {
    case "$BOARD_KIND:$JSON_KEY" in
        dsa:lan) eval "$1='lan1 lan2'" ;;
        x86:lan) eval "$1='eth0'" ;;
        *)       eval "$1=''" ;;
    esac
}
json_get_var() {
    case "$BOARD_KIND:$JSON_KEY:$2" in
        dsa:lan:device) eval "$1='br-lan'" ;;
        dsa:wan:device) eval "$1='wan'" ;;
        x86:lan:device) eval "$1='br-lan'" ;;
        x86:wan:device) eval "$1='eth1'" ;;
        *)              eval "$1=''" ;;
    esac
}
EOF
printf '%s\n' '{"network":{}}' > "$TMP/board.json"

board_probe() {
    INIT="$INIT" TMP="$TMP" BOARD_KIND="$1" BOARD_PATH="$2" sh -c '
        set -u
        . "$INIT"
        log() { :; }
        SYS_CLASS_NET="$TMP/net4"
        BOARD_JSON="$BOARD_PATH"
        JSHN_LIB="$TMP/fake-jshn.sh"
        BOARD_PORTS=""
        BOARD_PORTS_KNOWN=0
        uci() {
            case "$*" in
                *"get network.wan.device"*) printf "%s" "${FAKE_WAN_DEVICE:-}" ;;
                *"get network.wan.ifname"*) printf "%s" "${FAKE_WAN_IFNAME:-}" ;;
                *) return 1 ;;
            esac
        }
        board_interface_is_port eth0; printf "eth0=%s\n" "$?"
        board_interface_is_port lan1; printf "lan1=%s\n" "$?"
        board_interface_is_port wan;  printf "wan=%s\n" "$?"
        wan_interface="eth0"
        resolve_wan_interface; printf "explicit_rc=%s explicit=%s\n" "$?" "$wan_interface"
        wan_interface=""
        FAKE_WAN_DEVICE="eth0"
        resolve_wan_interface; printf "existing_rc=%s existing=%s\n" "$?" "$wan_interface"
    '
}

DSA_BOARD=$(board_probe dsa "$TMP/board.json")
assert_line "$DSA_BOARD" "eth0=1" "rejects the DSA CPU conduit as a WAN port"
assert_line "$DSA_BOARD" "lan1=0" "accepts a DSA lan port"
assert_line "$DSA_BOARD" "wan=0" "accepts the DSA wan port"
assert_line "$DSA_BOARD" "explicit_rc=0 explicit=wan" "an explicit CPU port falls back to wan"
assert_line "$DSA_BOARD" "existing_rc=0 existing=wan" "an existing CPU port WAN falls back to wan"

X86_BOARD=$(board_probe x86 "$TMP/board.json")
assert_line "$X86_BOARD" "eth0=0" "a real eth0 is a board port"
assert_line "$X86_BOARD" "lan1=1" "rejects an interface the board does not declare"
assert_line "$X86_BOARD" "explicit_rc=0 explicit=eth0" "a real eth0 stays selectable"

UNKNOWN_BOARD=$(board_probe unknown "$TMP/missing-board.json")
assert_line "$UNKNOWN_BOARD" "eth0=2" "cannot judge without board.json"
assert_line "$UNKNOWN_BOARD" "explicit_rc=0 explicit=eth0" "keeps the old behaviour without board.json"

# ------------------------------------------------ two-phase apply / rollback
mkdir -p "$CONFIG_DIR"
ORIG_NET="config interface 'lan'
	option ipaddr '192.168.1.1'"
printf '%s\n' "$ORIG_NET" > "$CONFIG_DIR/network"
printf "config smartnetpilot 'default'\n" > "$CONFIG_DIR/smartnetpilot"

field() {
    printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n 1
}

reset_rollback_state() {
    rm -rf "$STATE_DIR" "$STATE_DIR.lock" "$STATE_DIR.rollback"
    rm -f "$RESULT_FILE" "$APPLY_MARKER"
    printf '%s\n' "$ORIG_NET" > "$CONFIG_DIR/network"
}

# A normal apply snapshots the config before touching it.
reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
assert_eq "$(field "$PREP" rollback)" 1 "prepare_apply enables rollback by default"
assert_eq "$(field "$PREP" timeout)" 120 "prepare_apply keeps the requested timeout"
if [ -n "$TOK" ] && [ -f "$STATE_DIR/backup/network" ]; then
    ok "prepare_apply snapshots the current configuration"
else
    fail "prepare_apply snapshots the current configuration"
fi
assert_eq "$(field "$(apply_status)" status)" armed "apply_status reports an armed apply"

# The marker carries the token; reload arms the countdown instead of keeping
# the configuration unconditionally.
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
APPLY_CALLED=0
reload
assert_eq "$APPLY_CALLED" 1 "reload applies a token-carrying request"
STATUS=$(apply_status)
assert_eq "$(field "$STATUS" status)" pending "an unconfirmed apply is pending rollback"
assert_eq "$(field "$STATUS" token)" "$TOK" "apply_status reports the apply token"
REMAIN=$(field "$STATUS" remaining)
if [ "$REMAIN" -gt 0 ] && [ "$REMAIN" -le 120 ]; then
    ok "apply_status reports the remaining countdown"
else
    fail "apply_status reports the remaining countdown (got '$REMAIN')"
fi

# A second apply cannot overwrite the snapshot of the pending one.
PREP2=$(prepare_apply 1 120)
assert_eq "$(field "$PREP2" error)" pending "a pending apply blocks a second arm"
assert_eq "$(cat "$STATE_DIR/token")" "$TOK" "a pending apply keeps its snapshot"

# Rollback restores the snapshot and reports the outcome.
printf 'changed\n' > "$CONFIG_DIR/network"
if rollback_if_pending "$TOK"; then
    ok "rollback_if_pending restores an unconfirmed apply"
else
    fail "rollback_if_pending restores an unconfirmed apply"
fi
assert_eq "$(cat "$CONFIG_DIR/network")" "$ORIG_NET" "rollback restores the network config"
assert_eq "$(field "$(apply_status)" status)" rolledback "apply_status reports the rollback"
if rollback_if_pending "$TOK"; then
    fail "rolling back twice is rejected"
else
    ok "rolling back twice is rejected"
fi

# Confirmation keeps the new configuration and disarms the rollback.
reset_rollback_state
PREP=$(prepare_apply 1 60)
TOK=$(field "$PREP" token)
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
APPLY_CALLED=0
reload
if confirm_apply "$TOK"; then
    ok "confirm_apply keeps the applied configuration"
else
    fail "confirm_apply keeps the applied configuration"
fi
assert_eq "$(field "$(apply_status)" status)" confirmed "apply_status reports the confirmation"
if [ -d "$STATE_DIR" ]; then
    fail "confirmation clears the rollback state"
else
    ok "confirmation clears the rollback state"
fi
if rollback_if_pending "$TOK"; then
    fail "a confirmed apply cannot be rolled back"
else
    ok "a confirmed apply cannot be rolled back"
fi

# Unknown tokens are rejected and leave the real state untouched.
reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
if confirm_apply bogus-token; then
    fail "confirmation with a wrong token is rejected"
else
    ok "confirmation with a wrong token is rejected"
fi
if rollback_if_pending bogus-token; then
    fail "rollback with a wrong token is rejected"
else
    ok "rollback with a wrong token is rejected"
fi
assert_eq "$(field "$(apply_status)" status)" armed "a wrong token keeps the apply armed"

# Confirmation may arrive before ucitrack runs reload; the apply must still be
# kept and must not start a countdown afterwards.
reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
if confirm_apply "$TOK"; then
    ok "confirmation is accepted before reload runs"
else
    fail "confirmation is accepted before reload runs"
fi
assert_eq "$(field "$(apply_status)" status)" confirmed "an early confirmation is recorded"
APPLY_CALLED=0
reload
assert_eq "$APPLY_CALLED" 1 "an early confirmation still applies the configuration"
assert_eq "$(field "$(apply_status)" status)" confirmed "an early confirmation keeps the configuration"
if [ -d "$STATE_DIR" ]; then
    fail "an early confirmation clears the state after applying"
else
    ok "an early confirmation clears the state after applying"
fi

# Force mode applies immediately, without a snapshot or countdown.
reset_rollback_state
PREP=$(prepare_apply 0)
assert_eq "$(field "$PREP" rollback)" 0 "prepare_apply 0 disables rollback"
assert_eq "$(field "$PREP" token)" "" "force mode has no confirmation token"
if [ -d "$STATE_DIR" ]; then
    fail "force mode discards any rollback state"
else
    ok "force mode discards any rollback state"
fi
printf 'force\n' > "$APPLY_MARKER"
APPLY_CALLED=0
reload
assert_eq "$APPLY_CALLED" 1 "force mode applies the configuration"
assert_eq "$(field "$(apply_status)" status)" confirmed "force mode leaves the configuration in place"

# The waiter rolls back once the timeout expires.
reset_rollback_state
PREP=$(prepare_apply 1 30)
TOK=$(field "$PREP" token)
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
APPLY_CALLED=0
reload
printf 'changed\n' > "$CONFIG_DIR/network"
wait_rollback 0 "$TOK"
assert_eq "$(field "$(apply_status)" status)" rolledback "the timeout waiter rolls back an unconfirmed apply"
assert_eq "$(cat "$CONFIG_DIR/network")" "$ORIG_NET" "the timeout waiter restores the snapshot"

# A failed apply clears the countdown and reports the failure.
reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
apply_config() { APPLY_CALLED=1; return 1; }
APPLY_CALLED=0
reload
apply_config() { APPLY_CALLED=1; }
assert_eq "$(field "$(apply_status)" status)" failed "a failed apply reports the failure"
if [ -d "$STATE_DIR" ]; then
    fail "a failed apply clears the rollback state"
else
    ok "a failed apply clears the rollback state"
fi

# Never apply a token-bearing request without a matching snapshot: that
# would be exactly the unreachable-device case the rollback protects against.
reset_rollback_state
printf 'token=deadbeef\n' > "$APPLY_MARKER"
APPLY_CALLED=0
reload
assert_eq "$APPLY_CALLED" 0 "refuses to apply without a rollback snapshot"
assert_eq "$(field "$(apply_status)" status)" failed "a missing snapshot is reported as failed"

reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
printf 'token=not-%s\n' "$TOK" > "$APPLY_MARKER"
APPLY_CALLED=0
reload
assert_eq "$APPLY_CALLED" 0 "refuses to apply with a mismatched token"
assert_eq "$(field "$(apply_status)" status)" failed "a mismatched token is reported as failed"

# A failed commit cancels the apply before reload consumes the marker.
reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
if cancel_apply "$TOK"; then
    ok "cancel_apply discards an apply that has not started"
else
    fail "cancel_apply discards an apply that has not started"
fi
if [ -d "$STATE_DIR" ] || [ -f "$APPLY_MARKER" ]; then
    fail "cancelling clears the state and the request marker"
else
    ok "cancelling clears the state and the request marker"
fi
APPLY_CALLED=0
reload
assert_eq "$APPLY_CALLED" 0 "a cancelled apply never changes the network"
assert_eq "$(field "$(apply_status)" status)" idle "a cancelled apply leaves no result"

# Cancelling with a wrong token is rejected.
reset_rollback_state
PREP=$(prepare_apply 1 120)
TOK=$(field "$PREP" token)
printf 'token=%s\n' "$TOK" > "$APPLY_MARKER"
if cancel_apply bogus-token; then
    fail "cancelling with a wrong token is rejected"
else
    ok "cancelling with a wrong token is rejected"
fi
if [ -d "$STATE_DIR" ] && [ -f "$APPLY_MARKER" ]; then
    ok "a rejected cancel keeps the apply armed"
else
    fail "a rejected cancel keeps the apply armed"
fi

# Once reload has consumed the marker, cancel must not discard the rollback.
APPLY_CALLED=0
reload
if cancel_apply "$TOK"; then
    fail "an apply that already started cannot be cancelled"
else
    ok "an apply that already started cannot be cancelled"
fi
assert_eq "$(field "$(apply_status)" status)" pending "a started apply keeps its rollback"
rollback_if_pending "$TOK" >/dev/null 2>&1

# --------------------------------------------------------------- static checks
assert_file_lacks "$INIT" 'network.@device[0].ports' "never rewrites br-lan ports"
assert_file_lacks "$INIT" 'wan_proto=$(uci' "never infers the mode from network.wan.proto"
assert_file_contains "$INIT" 'board_interface_is_port' "init consults board.json for physical ports"
assert_file_contains "$RPC" 'physical_ports' "rpcd exposes the board port list"
assert_file_contains "$JS" 'physical_ports' "the UI validates the WAN port against board ports"
assert_file_contains "$INIT" 'consume_apply_request' "reload is gated by an explicit apply request"
assert_file_contains "$INIT" 'EXTRA_COMMANDS="prepare_apply' "the rollback actions are registered"
assert_file_contains "$INIT" 'start_rollback_waiter' "a detached timeout waiter is started"
assert_file_contains "$RPC" 'arm_apply' "rpcd exposes the apply-request method"
assert_file_contains "$RPC" 'apply_status' "rpcd exposes the rollback status"
assert_file_contains "$RPC" 'confirm_apply' "rpcd exposes confirmation"
assert_file_contains "$RPC" 'rollback_apply' "rpcd exposes manual rollback"
assert_file_contains "$RPC" 'cancel_apply' "rpcd exposes cancelling an apply"
assert_file_contains "$ACL" '"confirm_apply"' "the ACL allows confirming an apply"
assert_file_contains "$ACL" '"cancel_apply"' "the ACL allows cancelling an apply"
assert_file_contains "$ACL" '"rollback_apply"' "the ACL allows rolling an apply back"
assert_file_contains "$JS" 'callArmApply' "the view arms an apply before committing"
assert_file_contains "$JS" 'callApplyStatus' "the view polls the rollback state"
assert_file_contains "$JS" 'callConfirmApply' "the view can keep a new configuration"
assert_file_contains "$JS" 'callCancelApply' "the view can cancel an apply that failed to commit"
assert_file_contains "$JS" 'callRollbackApply' "the view can roll a configuration back"
assert_file_contains "$JS" 'apply_unchecked' "the view commits without LuCI's auto-reload"
assert_file_contains "$JS" '_showRollbackModal' "the view warns about an unconfirmed apply"
assert_file_contains "$JS" 'Apply without confirmation' "the view offers a force apply"
assert_file_contains "$ROOT/root/etc/uci-defaults/40-luci-smartnetpilot" 'smartnetpilot-rollback' \
    "install and upgrade drop stale rollback state"

if [ "$FAILS" -ne 0 ]; then
    printf '\n%d check(s) failed\n' "$FAILS"
    exit 1
fi

printf '\nAll regression checks passed.\n'
