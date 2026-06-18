#!/usr/bin/env bash
# Cleanly tear down any leftover wifiman Teleport WireGuard tunnel.
# Idempotent and safe to run anytime. Intended as ExecStopPost for
# wifiman-desktop.service so `systemctl stop` never orphans DNS.
#
# Background: `systemctl stop` kills wifiman-desktopd but not the Teleport
# tunnel it brought up with wg-quick. The orphaned wgXXXXXXXX interface keeps
# a "~." DNS capture pointing at a now-dead tunnel resolver, black-holing all
# name resolution. This restores the state the daemon's own Teleport.Off would.
#
# Does NOT touch Tailscale (tailscale0 / fwmark 0x80000 / table 52).
set -u

log() { echo "wifiman-teleport-down: $*"; }

# 1) Remove leftover kernel WireGuard interfaces created by Teleport.
#    Teleport names them wgXXXXXXXX. Never match tailscale0.
for ifc in $(ip -o link show type wireguard 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1); do
  [ "$ifc" = "tailscale0" ] && continue
  case "$ifc" in
    wg[0-9a-f]*)
      log "reverting + deleting $ifc"
      resolvectl revert "$ifc" 2>/dev/null || true
      ip link delete "$ifc" 2>/dev/null || true
      ;;
  esac
done

# 2) Prune wg-quick's orphaned policy rules for the Teleport table (51820).
#    Leaves Tailscale's 0x80000 / table-52 rules intact.
for fam in -4 -6; do
  while ip "$fam" rule del table 51820 2>/dev/null; do :; done
  ip "$fam" rule del table main suppress_prefixlength 0 2>/dev/null || true
done

# 3) Flush the resolver so the 127.0.0.53 stub answers immediately again.
resolvectl flush-caches 2>/dev/null || true
log "done"
