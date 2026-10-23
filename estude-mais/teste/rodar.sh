#!/bin/bash
# recria o banco, reinicia o servidor de teste e roda o e2e
cd "$(dirname "$0")"
for pid in $(pgrep -f "^node --experimental-strip-types server.mjs"); do kill $pid; done; sleep 0.5
./reset_db.sh >/dev/null
for pid in $(pgrep -f "^node --experimental-strip-types server.mjs"); do kill $pid; done; sleep 0.5
nohup node --experimental-strip-types server.mjs > server.log 2>&1 &
echo $! > server.pid
sleep 1.5
timeout 400 python3 e2e.py
node --experimental-strip-types seguranca.mjs 2>&1 | grep -v ExperimentalWarning
