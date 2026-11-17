# Handoff
**Last updated:** 2026-10-28
**Current project / stage:** The Platform, Stage A1: network connectivity monitor (TCP/UDP echo servers as probe targets, running on AWS, built with Terraform)

**Done so far:**
- Repo folder: `TCP-and-UDP-Servers` (first GitHub push still pending). Layout: `servers/` (deployed code), `tools/` (test clients + report), `probe/` (the monitor), `infra/` (Terraform).
- `servers/tcp_echo.py`: threaded TCP echo server, port 5000, one thread per caller.
- `servers/udp_echo.py`: UDP echo server, port 5001.
- `tools/tcp_client.py`, `tools/udp_client.py`: throwaway test clients. `tools/report.py`: GROUP BY summary per host and check type.
- `probe/probe.py`: TCP and/or UDP checks (`--checks tcp udp`, optional host argument), one SQLite row per check in `monitor.db`, exit code 0 only if the checks that ran passed. UDP check sends 10 sequence-numbered packets and records avg latency, loss %, jitter.
- UDP loss mystery SOLVED: it was a bug in the probe. A late reply was counted as lost and shifted every following reply by one. Fixed by ignoring replies that don't match the current packet and waiting until the deadline. Verified: 0% loss in 9 of 9 runs laptop -> PC. Found by counting packets on the server (all 10 arrived) while ping showed 0% loss.
- Schema (the contract for Stage B): `checks(id, ts, source_host, target, check_type, ok, latency_ms, loss_pct, jitter_ms, error)`. `ts` is UTC ISO 8601. `monitor.db` is gitignored.
- README.md written for the repo in the same style as the LogAnalyzer README.
- AWS account created on the Free plan: root MFA, daily-use IAM user with MFA, budget alert.
- Echo servers copied to the EC2 instance (scp) and started with nohup. First probe from the hotspot laptop to EC2 (Frankfurt): TCP 114 ms, UDP 54 ms avg, 0% loss, 10 ms jitter. TCP is about 2x UDP because of the handshake. Laptop -> PC for comparison was 6-8 ms.
- Both echo servers on the EC2 instance now run as systemd services (tcp-echo, udp-echo) and survived a stop/start, probed from the hotspot afterwards.
- README.md updated with the AWS deployment, the resolved UDP bug, and sample results.
- Terraform installed on the Fedora laptop. `infra/main.tf` builds the security group (SSH, TCP 5000, UDP 5001 from `my_ip`) and an EC2 instance (t3.micro, AL2023 via SSM parameter, existing key pair `Key-Pair`, standard CPU credits); `infra/userdata.sh.tftpl` writes the two servers and their systemd units on first boot; `public_ip` is an output. Verified: apply, probe the output IP, destroy, apply again, probe again with no manual steps. `.gitignore` covers `.terraform/`, state files, keys and `monitor.db`; `.terraform.lock.hcl` is committed.

**In progress:**
- Nothing in flight. Remaining housekeeping: first push to GitHub (README.md, handoff.md, infra/), terminate the old manually built `echo-test` instance and its manual security group in the console, and make sure no instance is left running (`terraform destroy` when done for the day).
- TCP check laptop -> PC may still time out (missing Windows firewall rule). Low priority.

**Next steps:**
1. Push the repo to GitHub, after checking `git add --dry-run .` shows no keys, state files, logs or `monitor.db`.
2. Terminate the manual instance and its security group.
3. Harden the echo servers: require a shared token (UDP: packets without it are ignored; TCP: first message must carry it). Needed before opening ports beyond a single source IP.
4. Then open TCP 5000 / UDP 5001 to the world, so a probe from a changing hotspot IP keeps working unattended.
5. systemd timer for the probe on Fedora (TCP every minute, UDP every five) to start collecting data.
6. Stage B dashboard (separate repo) reading `monitor.db`, then Stage C.

**Decisions made and why:**
- Echo servers are the A1 probe targets: ICMP is unreliable on mobile links, and UDP echo with sequence numbers measures loss and jitter.
- One probe program with selectable checks (`--checks`), not one script per protocol.
- The loop lives outside the script (systemd timer on Fedora). Scheduling is deferred until the servers are on AWS, so only the probe machine has to be on.
- AWS is the remote vantage point. The hotspot is behind carrier NAT, so servers can't be hosted on it, but outbound probes from it work normally. Do it by hand once, then Terraform. Azure later with the same concepts.
- A2 (port scanner against a Docker lab network) is deferred until A1 is done. Monitor and scanner use separate SQLite files.
- Stage B (dashboard) is a separate repo and reads the SQLite file read-only.
- Hotspot is metered: keep probes tiny.
- The UDP echo server on the internet should ignore packets without a valid token (reflection abuse), to be added when it goes on AWS.
- The Terraform instance gets the servers through `user_data` (`templatefile` + base64), no scp. The existing key pair is referenced by name, not created by Terraform.
- The token check comes before the scheduled probe: the hotspot's public IP changes, so a /32 security group rule would make unattended probes fail. The fix is to open the echo ports and protect them with the token instead.

**Known issues / open questions:**
- TCP latency was 700-900 ms in some earlier laptop -> PC runs while ping was 6-12 ms. Not explained yet, check the individual rows in `monitor.db`.
- Possible bug: `check_udp_echo` does not catch an `OSError` from `sendto` when the network is completely down (untested).
- Both machines may report the same `source_host` (laptop hostname is `CicadaKatz`); check the PC's hostname and add a `--name` option if they match.
- AWS region confirmed as eu-central-1 (Frankfurt) from the instance's public DNS name. Security group source is "My IP", and the hotspot's public IP changes, so SSH may time out later until the rule is updated.

**Where I am as a learner:**
- Understood: sockets, bind/listen/accept, why a single-threaded server blocks, threads per client, TCP vs UDP semantics, why UDP loss is only detected by timeout, how a late reply can corrupt loss counting, debugging by measuring from both ends, SQL GROUP BY summaries, exit codes.
- Typed in but only partly understood: the new `check_udp_echo` loop with the deadline, list comprehensions, parameterized SQL, `argparse` (used before in LogAnalyzer).
- New and untouched: Terraform, systemd timers, AWS networking (security groups, VPC), IAM details.
