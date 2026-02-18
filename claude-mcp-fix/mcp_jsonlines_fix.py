#!/usr/bin/env python3
"""Simple proxy: JSON lines in/out, only fixes schema"""
import sys, json, subprocess, threading

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

proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr,
    bufsize=0
)

def forward_stdin():
    for line in sys.stdin:
        proc.stdin.write(line.encode())
        proc.stdin.flush()

t = threading.Thread(target=forward_stdin, daemon=True)
t.start()

for line in iter(proc.stdout.readline, b''):
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        if 'result' in data and 'tools' in data.get('result', {}):
            for tool in data['result']['tools']:
                if 'inputSchema' in tool:
                    fix_schema(tool['inputSchema'])
        sys.stdout.write(json.dumps(data) + '\n')
        sys.stdout.flush()
    except:
        pass
