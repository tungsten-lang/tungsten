#!/bin/bash
# HTTP Server Benchmark Suite
# Uses Hammer to benchmark various HTTP servers with identical settings
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
HAMMER="$ROOT/hammer"
PORT=8080
URL="http://127.0.0.1:$PORT/"
CONNS=100
DURATION=5
PIPELINE=256

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

wait_for_server() {
    for i in $(seq 1 30); do
        if curl -s -o /dev/null "$URL" 2>/dev/null; then return 0; fi
        sleep 0.1
    done
    echo "ERROR: Server failed to start on port $PORT"
    return 1
}

kill_server() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    # Kill anything still on the port
    lsof -ti :$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 1
}

run_benchmark() {
    local name="$1"
    echo -e "\n${BOLD}${CYAN}=== $name ===${NC}"
    if ! wait_for_server; then
        echo "SKIP: $name (failed to start)"
        kill_server
        return
    fi
    # Warm up
    $HAMMER -c $CONNS -d 2 -b $PIPELINE "$URL" > /dev/null 2>&1
    sleep 1
    # Real run
    $HAMMER -c $CONNS -d $DURATION -b $PIPELINE "$URL" 2>&1
    kill_server
}

echo -e "${BOLD}HTTP Server Benchmark${NC}"
echo -e "${DIM}Hammer: $CONNS connections, $PIPELINE pipeline, ${DURATION}s${NC}"
echo -e "${DIM}All servers return 'Hello World\\n' (12 bytes)${NC}"
echo ""

# 1. Forge (Tungsten)
echo -e "${GREEN}Starting Forge...${NC}"
$ROOT/forge_hello &
SERVER_PID=$!
run_benchmark "Forge (Tungsten — goroutines + kqueue)"

# 2. Rust / hyper
echo -e "${GREEN}Starting Rust (hyper + tokio)...${NC}"
$DIR/rust_server/target/release/rust_server &
SERVER_PID=$!
run_benchmark "Rust (hyper 1.x + tokio)"

# 3. Go net/http
echo -e "${GREEN}Starting Go...${NC}"
$DIR/go_server_bin &
SERVER_PID=$!
run_benchmark "Go (net/http)"

# 4. Bun
echo -e "${GREEN}Starting Bun...${NC}"
bun run $DIR/bun_server.js &
SERVER_PID=$!
run_benchmark "Bun (Bun.serve)"

# 5. Node.js (single)
echo -e "${GREEN}Starting Node.js...${NC}"
node $DIR/node_server.js &
SERVER_PID=$!
run_benchmark "Node.js (http, single thread)"

# 6. Node.js (cluster)
echo -e "${GREEN}Starting Node.js cluster...${NC}"
node $DIR/node_cluster.js &
SERVER_PID=$!
run_benchmark "Node.js (http, cluster)"

# 7. Ruby raw socket
echo -e "${GREEN}Starting Ruby (raw socket)...${NC}"
ruby $DIR/ruby_server.rb &
SERVER_PID=$!
run_benchmark "Ruby (raw socket + threads)"

# 8. Puma
echo -e "${GREEN}Starting Puma...${NC}"
cd $DIR && puma -p $PORT -t 8:32 -w 0 --preload puma_server.ru > /dev/null 2>&1 &
SERVER_PID=$!
run_benchmark "Ruby (Puma)"

# 9. Python asyncio
echo -e "${GREEN}Starting Python...${NC}"
python3 $DIR/python_server.py &
SERVER_PID=$!
run_benchmark "Python (asyncio)"

echo -e "\n${BOLD}Done.${NC}"
