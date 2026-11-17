# TCP-and-UDP echo servers

I'm building two small echo servers to learn Python, sockets and DevOps stuff. It sends TCP and UDP messages to two echo servers and writes down how long the replies took and how many never came back.

## What's in here

```
infra/
  main.tf         EC2 instance, security group, and bootstrap setup
servers/
  tcp_echo.py     TCP echo server, port 5000, one thread per caller
  udp_echo.py     UDP echo server, port 5001
tools/
  tcp_client.py   quick test client for the TCP server
  udp_client.py   quick test client for the UDP server
  report.py       prints a summary of what's in the database
probe/
  probe.py        the actual monitor
```

No pip install needed, it's all standard library. Python 3 only.

## Running it

Start the servers, each in its own terminal:

```
python servers/tcp_echo.py
python servers/udp_echo.py
```

On Windows use `py` instead of `python`.

Then run the probe, on the same machine or another one on the same network:

```
python probe/probe.py                          # both checks against 127.0.0.1
python probe/probe.py 192.168.1.50             # both checks against another machine
python probe/probe.py 192.168.1.50 --checks udp
python probe/probe.py --checks tcp
```

The exit code is 0 if every check that ran passed. The exit code is 1 otherwise, so it can be scheduled later without changing anything.

To see what it recorded:

```
python tools/report.py
```

If it works on localhost but not from another machine, it might be the firewall. I personally tested it on a Windows PC and a Fedora KDE Plasma laptop I have. They communicated well with no problem. No ports needed to be open.
## What it measures

- **TCP check:** connects, sends a message, waits for the echo, and times the whole thing.
- **UDP check:** sends 10 numbered packets, 0.2 seconds apart, and records average round trip time, loss percentage, and jitter.

## The database

Results go into a SQLite file called `monitor.db`, one row per check. This table is the contract for the dashboard later.

| column      | what it is                                 |
|-------------|--------------------------------------------|
| ts          | timestamp when the check ran, UTC          |
| source_host | which machine ran the probe                |
| target      | what it checked, like `10.0.0.5:5000`      |
| check_type  | `tcp_echo` or `udp_echo`                   |
| ok          | 1 if it worked, 0 if it didnt              |
| latency_ms  | round trip time (average for UDP)          |
| loss_pct    | UDP only, how many packets never came back |
| jitter_ms   | UDP only                                   |
| error       | what went wrong, if anything               |

## Running it on AWS

The servers also run on a small EC2 instance in Frankfurt (eu-central-1), so I can probe them from my phone hotspot at home. My hotspot is behind carrier NAT so I can't host anything on it, but connecting outward to AWS works fine.

I first built it by hand in the console so I'd understand every piece, then rebuilt the same thing with Terraform. Now all of it comes from the `infra/` folder:

```
cd infra
terraform init
terraform apply -var="my_ip=$(curl -4 -s https://checkip.amazonaws.com)/32"
```

When it's done it prints the public IP. Give it a couple of minutes for the first boot, then probe it:

```
python probe/probe.py <that ip>
```

And when I'm finished for the day I run `terraform destroy` with the same `-var`, so nothing sits there using up credits.

- t3.micro with Amazon Linux 2023, the newest image gets looked up automatically
- The first-boot script copies the two servers onto the instance and sets them up as systemd services (`tcp-echo` and `udp-echo`), so they start on boot and get restarted if they crash
- The security group only allows SSH (22), TCP 5000 and UDP 5001 from my own IP. A hotspot's public IP changes, so I pass the current one in every time I run Terraform
- The public IP is different for every new instance, so Terraform prints it as an output and I pass it to the probe on the command line
- The SSH key and Terraform's state files are in `.gitignore`. The state can contain secrets

## Things I ran into

- When I first started making the TCP Server it could only talk to one client. A second client would just freeze until the first one hung up, because the server was stuck waiting on the first connection to stop. This is where I learned about threads, now each connection has its own thread.
- First major-ish problem I encountered was stopping the UDP server and then running the client gave a `ConnectionResetError` on Windows, while on Linux it just gave the response that no one was listening... Windows turns the nobody is listening reply into an error, but Linux doesn't, it just times out. So the probe treats both as a failure and stores which one it saw.
- For some reason while probing from my laptop to my PC, all of a sudden the UDP loss numbers looked way too high while ping showed 0% loss, I counted the packets on the server and all 10 arrived, so the loss wasn't real. It turned out to be a bug in my probe. It waited 1 second for each reply, if one was late it would send another, and when the late one would show up it would throw it away as a wrong packet. After that it was a domino effect of each one falling behind and all of them got counted as lost too. The fix was to ignore replies that don't match the packet I'm waiting for and keep waiting untile the deadline. After that I started getting 0% loss.
- One thing I learned about how to better future-proof your code is, when it came down to actually probing it would always run both the udp and tcp checks. But maybe I just wanted to test one. So because I learned about argparse in my LogAnalyzer project I was able to use that to make --check udp or tcp. Why I say this was for future proofing is because I was ready to just make them seperate scripts. But that would be reusing the same code which wouldn't be very efficient.
- First attempt at using SSH to get into the instance timed out. The security group rule said "My IP". I was using a hotspot at the time and public IP's for hotspots change all the time. Had to update the rules as I was getting connection refused.
- My first attempt at pasting new blocks into a Terraform file got stumped by the classic curly bracket. Learned what terraform validate does real quickly.
- Doing terraform destroy and then terraform apply and watching a fresh server come up working, with nothing done on my end by hand so to speak. It made me understand infrastructure as code a lot more.
- There is also something I learned from a OpenAI workshop & hackathon that was organized recently that I used here. As I am also using AI to shepherd me through this. Mainly Claude Code and Codex. The man handling the workshop kept talking about how to use AI Agents the best. Something that stuck with me was the file structure that was very important. But also handoff.md. Makes switching from one agent to the next much easier.

## Where this is going

- [x] TCP and UDP echo servers
- [x] Probe that writes to SQLite
- [x] Test between two machines over a phone hotspot
- [x] Host the servers on AWS (EC2, Frankfurt) and probe them from the hotspot
- [x] Rebuild that setup with Terraform
- [ ] Run the probe on a timer (systemd) instead of by hand
- [ ] Dashboard (separate repo)
