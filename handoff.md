# Handoff
**Last updated:** 2026-10-24
**Current project / stage:** The Platform, Stage A1: network connectivity monitor (TCP/UDP echo servers as probe targets, moving to AWS now)

**Done so far:**
- Repo folder currently named `TCP and UDP Server` (rename to `net-monitor`, no spaces, still pending). Layout: `servers/` (deployed code), `tools/` (test clients + report), `probe/` (the monitor).
- `servers/tcp_echo.py`: threaded TCP echo server, port 5000, one thread per caller.
- `servers/udp_echo.py`: UDP echo server, port 5001.
- `tools/tcp_client.py`, `tools/udp_client.py`: throwaway test clients. `tools/report.py`: GROUP BY summary per host and check type.
- `probe/probe.py`: TCP and/or UDP checks (`--checks tcp udp`, optional host argument), one SQLite row per check in `monitor.db`, exit code 0 only if the checks that ran passed. UDP check sends 10 sequence-numbered packets and records avg latency, loss %, jitter.
- UDP loss mystery SOLVED: it was a bug in the probe. A late reply was counted as lost and shifted every following reply by one. Fixed by ignoring replies that don't match the current packet and waiting until the deadline. Verified: 0% loss in 9 of 9 runs laptop -> PC. Found by counting packets on the server (all 10 arrived) while ping showed 0% loss.
- Schema (the contract for Stage B): `checks(id, ts, source_host, target, check_type, ok, latency_ms, loss_pct, jitter_ms, error)`. `ts` is UTC ISO 8601. `monitor.db` is gitignored.
- README.md written for the repo in the same style as the LogAnalyzer README.
- AWS account created on the Free plan: root MFA, daily-use IAM user with MFA, budget alert.

**In progress:**
- About to launch the first EC2 instance by hand (step 11): Amazon Linux 2023, free-tier-eligible type, new ED25519 key pair, security group with SSH 22, TCP 5000, UDP 5001, source "My IP".
- TCP check laptop -> PC currently times out in every run while UDP works. Most likely the Windows firewall rule for TCP 5000 was deleted after the earlier test, or `tcp_echo.py` isn't running on the PC. Low priority, since the PC stops being the target once the servers are on AWS.

**Next steps:**
1. Launch the EC2 instance, note the public IPv4 address, stop the instance at the end of each session to save credits.
2. SSH in with the key, copy `servers/`, run both echo servers as systemd services.
3. Probe the EC2 target from the hotspot (`python probe/probe.py <ec2-ip>`), compare against the PC results.
4. Rebuild the instance and security group with Terraform (destroy and recreate).
5. Then: systemd timer for the probe on Fedora, TCP every minute and UDP every five.

**Decisions made and why:**
- Echo servers are the A1 probe targets: ICMP is unreliable on mobile links, and UDP echo with sequence numbers measures loss and jitter.
- One probe program with selectable checks (`--checks`), not one script per protocol.
- The loop lives outside the script (systemd timer on Fedora). Scheduling is deferred until the servers are on AWS, so only the probe machine has to be on.
- AWS is the remote vantage point. The hotspot is behind carrier NAT, so servers can't be hosted on it, but outbound probes from it work normally. Do it by hand once, then Terraform. Azure later with the same concepts.
- A2 (port scanner against a Docker lab network) is deferred until A1 is done. Monitor and scanner use separate SQLite files.
- Stage B (dashboard) is a separate repo and reads the SQLite file read-only.
- Hotspot is metered: keep probes tiny.
- The UDP echo server on the internet should ignore packets without a valid token (reflection abuse), to be added when it goes on AWS.

**Known issues / open questions:**
- TCP latency was 700-900 ms in some earlier laptop -> PC runs while ping was 6-12 ms. Not explained yet, check the individual rows in `monitor.db`.
- Possible bug: `check_udp_echo` does not catch an `OSError` from `sendto` when the network is completely down (untested).
- Both machines may report the same `source_host` (laptop hostname is `CicadaKatz`); check the PC's hostname and add a `--name` option if they match.

**Where I am as a learner:**
- Understood: sockets, bind/listen/accept, why a single-threaded server blocks, threads per client, TCP vs UDP semantics, why UDP loss is only detected by timeout, how a late reply can corrupt loss counting, debugging by measuring from both ends, SQL GROUP BY summaries, exit codes.
- New and untouched: Terraform, systemd timers, AWS networking (security groups, VPC), IAM details.