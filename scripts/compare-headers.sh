#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BEFORE_DIR="$ROOT_DIR/before"
AFTER_DIR="$ROOT_DIR/after"
PORT_BEFORE=4100
PORT_AFTER=4101

PID_BEFORE=""
PID_AFTER=""

cleanup() {
  echo ""
  echo "Cleaning up..."
  [ -n "$PID_BEFORE" ] && kill "$PID_BEFORE" 2>/dev/null || true
  [ -n "$PID_AFTER" ] && kill "$PID_AFTER" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

kill_port() {
  local port=$1
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill -9 2>/dev/null || true
    sleep 1
  fi
}

wait_for_server() {
  local port=$1
  local max_attempts=30
  local attempt=0
  while ! curl -sf -o /dev/null "http://localhost:$port/" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "ERROR: Server on port $port did not start within ${max_attempts}s"
      exit 1
    fi
    sleep 1
  done
}

capture_headers() {
  local dir=$1
  local port=$2
  local label=$3
  local version=$4

  echo "=== $label (Next.js $version) ==="
  echo ""

  kill_port "$port"

  echo "Cleaning previous build..."
  rm -rf "$dir/.next"

  echo "Building..."
  (cd "$dir" && npx next build) > /dev/null 2>&1

  local build_id
  build_id=$(cat "$dir/.next/BUILD_ID")
  echo "Build ID: $build_id"

  echo "Starting server on port $port..."
  (cd "$dir" && npx next start -p "$port") > /dev/null 2>&1 &
  local pid=$!

  if [ "$label" = "BEFORE" ]; then
    PID_BEFORE=$pid
  else
    PID_AFTER=$pid
  fi

  wait_for_server "$port"
  echo "Server ready."
  echo ""

  local data_url="http://localhost:$port/_next/data/$build_id/index.json"
  echo "Requesting: $data_url"
  echo ""
  echo "Response headers:"
  echo "---"
  curl -sD - -o /dev/null "$data_url"
  echo "---"
  echo ""

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  if [ "$label" = "BEFORE" ]; then
    PID_BEFORE=""
  else
    PID_AFTER=""
  fi

  sleep 1
}

echo "============================================"
echo "Next.js /_next/data/ Header Comparison"
echo "============================================"
echo ""

capture_headers "$BEFORE_DIR" "$PORT_BEFORE" "BEFORE" "15.4.0"
capture_headers "$AFTER_DIR" "$PORT_AFTER" "AFTER" "15.4.1"

echo "============================================"
echo "Summary"
echo "============================================"
echo ""
echo "BEFORE (v15.4.0): Should show Content-Length header"
echo "AFTER  (v15.4.1): Should show Transfer-Encoding: chunked (no Content-Length)"
echo ""
echo "CDNs like CloudFront require Content-Length to compress responses."
echo "The missing header means /_next/data/ responses are served uncompressed."
