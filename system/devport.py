"""Helper behind `devport check` and the devport-watch user service.

  check [--all] [--json]   (root) every non-loopback listening socket and
                           whether the firewall lets the LAN reach it.
  watch                    (user) desktop notification, with an "Open" button,
                           when a program starts listening on a blocked port.

Wired up in system/firewall.nix.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import threading
import time

EPHEMERAL = 32768  # net.ipv4.ip_local_port_range starts here
# Tokens of an accept rule that do not narrow who may connect.
NEUTRAL = {"-A", "-p", "-m", "--dport", "--comment", "-j"}


def listeners(with_procs):
    """{(proto, port): {"addrs": set, "procs": set}} for non-loopback sockets."""
    out = subprocess.run(
        ["ss", "-Hltnu" + ("p" if with_procs else "")],
        capture_output=True, text=True, check=True,
    ).stdout
    found = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) < 5 or f[0] not in ("tcp", "udp"):
            continue
        addr, _, port = f[4].rpartition(":")
        addr = addr.split("%")[0]
        if not port.isdigit():
            continue
        if addr.startswith("127.") or addr == "[::1]":
            continue
        if addr.startswith("224.") or addr.startswith("[ff"):
            continue  # multicast group membership, not a service
        entry = found.setdefault(
            (f[0], int(port)), {"addrs": set(), "procs": set()})
        entry["addrs"].add(addr)
        entry["procs"].update(re.findall(r'\("([^"]+)",pid=', line))
    return found


def accept_rules():
    """nixos-fw accept rules as dicts: proto, lo, hi, limit, devport."""
    out = subprocess.run(
        ["iptables", "-S", "nixos-fw"],
        capture_output=True, text=True, check=True,
    ).stdout
    rules = []
    for line in out.splitlines():
        tok = shlex.split(line)
        if tok[:1] != ["-A"] or tok[-2:] != ["-j", "nixos-fw-accept"]:
            continue
        opts = {}
        negated = False
        i = 2
        while i < len(tok):
            if tok[i] == "!":
                negated = True
                i += 1
            elif tok[i].startswith("-") and i + 1 < len(tok):
                opts.setdefault(tok[i], tok[i + 1])
                i += 2
            else:
                i += 1
        if opts.get("-i") == "lo":
            continue
        extra = set(opts) - NEUTRAL
        # Stateful/odd rules (conntrack, source ports, ...) say nothing about
        # whether a fresh connection to a port gets in.
        if negated or extra - {"-i", "-s"}:
            continue
        lo, _, hi = opts.get("--dport", "1:65535").partition(":")
        limit = [opts[k] for k in ("-i", "-s") if k in opts]
        if "--dport" not in opts and not limit:
            continue
        rules.append({
            "proto": opts.get("-p"),
            "lo": int(lo), "hi": int(hi or lo),
            "limit": " ".join(
                ("from " if k == "-s" else "") + opts[k].removesuffix("/32")
                for k in ("-i", "-s") if k in opts),
            "devport": opts.get("--comment") == "devport",
        })
    return rules


def classify(proto, port, procs, rules):
    if "docker-proxy" in procs:
        return "open", "docker publish bypasses the firewall"
    limited = []
    state = None
    for r in rules:
        if r["proto"] not in (None, proto) or not r["lo"] <= port <= r["hi"]:
            continue
        if r["limit"]:
            limited.append(r["limit"])
        elif r["devport"]:
            state = state or ("open", "devport, until reboot/rebuild")
        else:
            state = ("open", "")
    if state:
        return state
    if limited:
        return "limited", "only " + ", ".join(dict.fromkeys(limited))
    return "blocked", ""


def check(argv):
    if os.geteuid() != 0:
        sys.exit("devport check: must run as root (use `devport check`)")
    rules = accept_rules()
    rows = []
    for (proto, port), e in sorted(listeners(True).items()):
        if proto == "udp" and port >= EPHEMERAL and "--all" not in argv:
            continue  # client sockets (QUIC, mDNS replies, ...), not services
        status, note = classify(proto, port, e["procs"], rules)
        rows.append({
            "proto": proto, "port": port,
            "procs": sorted(e["procs"]), "addrs": sorted(e["addrs"]),
            "status": status, "note": note,
        })
    if "--json" in argv:
        json.dump(rows, sys.stdout)
        return
    color = {"open": "32", "limited": "33", "blocked": "31"}
    tty = sys.stdout.isatty()
    print(f"{'PROTO':<5} {'PORT':<5} {'PROCESS':<18} {'LISTENING ON':<24} LAN")
    for r in rows:
        lan = r["status"] + (f" ({r['note']})" if r["note"] else "")
        if tty:
            lan = f"\033[{color[r['status']]}m{lan}\033[0m"
        print(f"{r['proto']:<5} {r['port']:<5} "
              f"{', '.join(r['procs']) or '-':<18.18} "
              f"{', '.join(r['addrs']):<24.24} {lan}")
    if not rows:
        print("(nothing is listening on a non-loopback address)")


# ---- watch -----------------------------------------------------------------

DEVPORT = os.environ.get("DEVPORT_BIN", "/run/current-system/sw/bin/devport")
IGNORE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "devport", "ignore")


def ignored():
    try:
        with open(IGNORE) as f:
            return {line.strip() for line in f if line.strip()}
    except FileNotFoundError:
        return set()


def notify(*args):
    return subprocess.run(
        ["notify-send", "--app-name=devport", "--icon=network-server", *args],
        capture_output=True, text=True,
    ).stdout.strip()


def ask(row):
    port, proto = row["port"], row["proto"]
    proc = (row["procs"] or ["?"])[0]
    reach = (f"Reachable {row['note']}." if row["status"] == "limited"
             else "The firewall blocks it.")
    actions = ["--action=open=Open until reboot"]
    if row["procs"]:
        actions.append(f"--action=ignore=Never ask for {proc}")
    choice = notify(
        "--wait", *actions,
        f"{proc} is listening on {proto}/{port}",
        f"{reach} Other devices on the LAN cannot connect.")
    if choice == "open":
        done = subprocess.run(
            ["/run/wrappers/bin/pkexec", DEVPORT, "open", str(port), proto],
            capture_output=True, text=True)
        if done.returncode == 0:
            notify(f"{proto}/{port} is open to the LAN",
                   f"Until reboot or rebuild. Close: devport close {port}")
        else:
            notify("--urgency=critical", f"{proto}/{port} was not opened",
                   (done.stderr or done.stdout).strip()[-300:])
    elif choice == "ignore":
        os.makedirs(os.path.dirname(IGNORE), exist_ok=True)
        with open(IGNORE, "a") as f:
            f.write(proc + "\n")


def watch():
    # Whatever is already listening at login is the baseline: only sockets
    # that appear afterwards are asked about, each port once per session.
    seen = {k for k in listeners(False) if k[0] == "tcp"}
    asked = set()
    while True:
        time.sleep(3)
        try:
            now = {k for k in listeners(False) if k[0] == "tcp"}
        except subprocess.CalledProcessError:
            continue
        new = now - seen - asked
        seen = now
        if not new:
            continue
        # The firewall rules are root-only; this one read-only command is
        # NOPASSWD. Only run when a new listener shows up, so the sudo log
        # stays quiet.
        res = subprocess.run(
            ["/run/wrappers/bin/sudo", "-n", DEVPORT, "check", "--json"],
            capture_output=True, text=True)
        if res.returncode != 0:
            print("devport check failed:", res.stderr.strip(), flush=True)
            continue
        skip = ignored()
        for row in json.loads(res.stdout):
            key = (row["proto"], row["port"])
            if key not in new or row["status"] == "open":
                continue
            if skip & set(row["procs"]):
                continue
            asked.add(key)
            print(f"asking about {key[0]}/{key[1]} {row['procs']}", flush=True)
            threading.Thread(target=ask, args=(row,), daemon=True).start()


if __name__ == "__main__":
    cmd = sys.argv[1:2]
    if cmd == ["check"]:
        check(sys.argv[2:])
    elif cmd == ["watch"]:
        watch()
    else:
        sys.exit("usage: devport.py check [--all] [--json] | watch")
