#!/usr/bin/env python3
"""
Proxy: stdio (Claude Code) ↔ TCP socket (SQLcl MCP)
Uruchamia SQLcl MCP, czeka aż otworzy port, łączy się i przekazuje ruch.
"""
import sys, socket, subprocess, threading, time, re

# Uruchom SQLcl MCP
proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL
)

# Czekaj na komunikat z portem w stderr
port = None
for i in range(30):  # 30 sekund timeout
    line = proc.stderr.readline().decode()
    sys.stderr.write(line)
    # Szukaj portu w stdout/stderr (Oracle może wypisać "listening on port 12345")
    match = re.search(r'(?:port|PORT)\s*[:\s]*(\d+)', line)
    if match:
        port = int(match.group(1))
        sys.stderr.write(f"[proxy] Found port: {port}\n")
        break
    time.sleep(0.1)

if not port:
    sys.stderr.write("[proxy] ERROR: SQLcl didn't report port\n")
    proc.kill()
    sys.exit(1)

# Połącz z socketem
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(('127.0.0.1', port))
sys.stderr.write(f"[proxy] Connected to 127.0.0.1:{port}\n")

# Forward stdin → socket
def forward_in():
    while True:
        data = sys.stdin.buffer.read(4096)
        if not data:
            break
        sock.sendall(data)

# Forward socket → stdout
def forward_out():
    while True:
        data = sock.recv(4096)
        if not data:
            break
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()

t1 = threading.Thread(target=forward_in, daemon=True)
t2 = threading.Thread(target=forward_out, daemon=True)
t1.start()
t2.start()
t1.join()
t2.join()
