#!/usr/bin/env python3
import sys, json, subprocess, threading, time

DEBUG = True
def log(msg):
    if DEBUG:
        with open('/tmp/mcp_proxy_debug.log', 'a') as f:
            f.write(f"[{time.strftime('%H:%M:%S')}] {msg}\n")

def read_lsp(stream):
    headers = {}
    while True:
        line = stream.readline()
        if not line or line in (b'\r\n', b'\n'):
            break
        if b':' in line:
            k, v = line.decode().split(':', 1)
            headers[k.strip()] = v.strip()
    length = int(headers.get('Content-Length', 0))
    data = stream.read(length) if length else None
    log(f"read_lsp: headers={headers}, data={data[:100] if data else None}")
    return data

def write_lsp(data):
    msg = data.encode() if isinstance(data, str) else data
    out = f'Content-Length: {len(msg)}\r\n\r\n'.encode() + msg
    log(f"write_lsp: len={len(msg)}, data={msg[:100]}")
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

log("=== PROXY START ===")
proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr,
    bufsize=0
)
log(f"SQLcl started, PID={proc.pid}")

def forward_stdin():
    log("forward_stdin: thread started")
    while True:
        msg = read_lsp(sys.stdin.buffer)
        if msg is None:
            log("forward_stdin: EOF")
            break
        log(f"forward_stdin: sending to SQLcl: {msg[:100]}")
        proc.stdin.write(msg.rstrip() + b'\n')
        proc.stdin.flush()

t = threading.Thread(target=forward_stdin, daemon=True)
t.start()

log("Starting stdout read loop")
for line in iter(proc.stdout.readline, b''):
    line = line.strip()
    log(f"stdout from SQLcl: {line[:100]}")
    if not line:
        continue
    try:
        data = json.loads(line)
        if 'result' in data and 'tools' in data.get('result', {}):
            for tool in data['result']['tools']:
                if 'inputSchema' in tool:
                    fix_schema(tool['inputSchema'])
        write_lsp(json.dumps(data))
    except Exception as e:
        log(f"ERROR parsing JSON: {e}, line={line[:200]}")
