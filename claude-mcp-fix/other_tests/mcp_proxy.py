#!/usr/bin/env python3
"""
MCP Proxy: translates between Content-Length (Claude Code) and JSON lines (SQLcl MCP).
Claude Code speaks LSP-style (Content-Length headers).
SQLcl MCP speaks JSON lines (one JSON object per line, no headers).
"""
import sys, os, json, subprocess, threading, time, signal

LOG = os.environ.get('MCP_PROXY_DEBUG', '') == '1'
def log(msg):
    if LOG:
        sys.stderr.write(f"[mcp-proxy {time.strftime('%H:%M:%S')}] {msg}\n")
        sys.stderr.flush()

def read_lsp_message(stream):
    """Read a Content-Length framed message from stream (Claude Code format)."""
    headers = {}
    while True:
        line = stream.readline()
        if not line:
            return None
        if line == b'\r\n' or line == b'\n':
            break
        if b':' in line:
            k, v = line.decode().split(':', 1)
            headers[k.strip()] = v.strip()
    length = int(headers.get('Content-Length', 0))
    if length == 0:
        return None
    return stream.read(length)

def write_lsp_message(msg):
    """Write a Content-Length framed message to stdout (Claude Code format)."""
    if isinstance(msg, str):
        msg = msg.encode()
    out = f'Content-Length: {len(msg)}\r\n\r\n'.encode() + msg
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()

def fix_schema(schema):
    if not isinstance(schema, dict):
        return
    for k in list(schema.keys()):
        if k not in ['type','properties','required','description','items',
                     'enum','default','title','anyOf','oneOf','allOf',
                     'not','format','minimum','maximum','minLength',
                     'maxLength','pattern','additionalProperties','const']:
            del schema[k]
    if 'properties' in schema and 'type' not in schema:
        schema['type'] = 'object'
    for v in schema.get('properties', {}).values():
        fix_schema(v)

log(f"Starting proxy with args: {sys.argv[1:]}")

proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    bufsize=0
)

log(f"SQLcl process started (PID {proc.pid})")

# Clean shutdown: kill SQLcl when proxy exits
def cleanup(signum=None, frame=None):
    log("Cleanup: killing SQLcl")
    try:
        proc.kill()
    except:
        pass
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

def forward_stdin():
    """Read Content-Length messages from Claude Code, forward as JSON lines to SQLcl."""
    try:
        while True:
            msg = read_lsp_message(sys.stdin.buffer)
            if msg is None:
                log("stdin: EOF")
                break
            log(f"stdin -> sqlcl: {msg[:200]}")
            proc.stdin.write(msg.rstrip() + b'\n')
            proc.stdin.flush()
    except Exception as e:
        log(f"stdin error: {e}")
    finally:
        log("stdin thread ending, killing SQLcl")
        try:
            proc.kill()
        except:
            pass

t = threading.Thread(target=forward_stdin, daemon=True)
t.start()

# Read JSON lines from SQLcl using readline() (not iterator - avoids buffering)
while True:
    line = proc.stdout.readline()
    if not line:
        log("SQLcl stdout closed")
        break
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        log(f"sqlcl -> stdout: id={data.get('id')} method={data.get('method','?')}")
        if 'result' in data and 'tools' in data.get('result', {}):
            for tool in data['result']['tools']:
                if 'inputSchema' in tool:
                    fix_schema(tool['inputSchema'])
        msg = json.dumps(data).encode()
    except Exception as e:
        log(f"sqlcl -> stdout (parse error: {e}): {line[:200]}")
        continue
    write_lsp_message(msg)

cleanup()
