#!/usr/bin/env bash
# E2E Smoke Test for Zeke
# Tests health, OMEN routing, and Glyph MCP integration

set -euo pipefail

BASE_URL="${ZEKE_BASE_URL:-http://localhost:7878}"
TIMEOUT="${TIMEOUT:-5}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🧪 Zeke E2E Smoke Tests"
echo "Base URL: $BASE_URL"
echo ""

# Test 1: Health check
echo -n "→ Health check... "
if curl -fsS --max-time "$TIMEOUT" "$BASE_URL/health" | grep -q "ok"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    exit 1
fi

# Test 2: Chat via OMEN
echo -n "→ Chat (OMEN routing)... "
CHAT_RESPONSE=$(curl -fsS --max-time 30 "$BASE_URL/api/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"say ok"}')

if echo "$CHAT_RESPONSE" | grep -qi "ok" && echo "$CHAT_RESPONSE" | grep -q "provider"; then
    echo -e "${GREEN}✓${NC}"
    PROVIDER=$(echo "$CHAT_RESPONSE" | grep -o '"provider":"[^"]*"' | cut -d'"' -f4)
    echo "  Provider: $PROVIDER"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Response: $CHAT_RESPONSE"
    exit 1
fi

# Test 3: Code completion
echo -n "→ Code completion... "
COMPLETE_RESPONSE=$(curl -fsS --max-time 15 "$BASE_URL/api/complete" \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"def hello():","language":"python","max_tokens":50}')

if echo "$COMPLETE_RESPONSE" | grep -q "completion" && echo "$COMPLETE_RESPONSE" | grep -q "provider"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Response: $COMPLETE_RESPONSE"
    exit 1
fi

# Test 4: Code explanation
echo -n "→ Code explanation... "
EXPLAIN_RESPONSE=$(curl -fsS --max-time 15 "$BASE_URL/api/explain" \
    -H 'Content-Type: application/json' \
    -d '{"code":"const x = 42;","language":"javascript"}')

if echo "$EXPLAIN_RESPONSE" | grep -q "explanation" && echo "$EXPLAIN_RESPONSE" | grep -q "provider"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Response: $EXPLAIN_RESPONSE"
    exit 1
fi

# Test 5: Code edit
echo -n "→ Code edit... "
EDIT_RESPONSE=$(curl -fsS --max-time 20 "$BASE_URL/api/edit" \
    -H 'Content-Type: application/json' \
    -d '{"code":"def foo():\n    pass","instruction":"add a docstring","language":"python"}')

if echo "$EDIT_RESPONSE" | grep -q "edited_code" && echo "$EDIT_RESPONSE" | grep -q "provider"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Response: $EDIT_RESPONSE"
    exit 1
fi

# Test 6: Status endpoint
echo -n "→ Status check... "
STATUS_RESPONSE=$(curl -fsS --max-time "$TIMEOUT" "$BASE_URL/api/status")

if echo "$STATUS_RESPONSE" | grep -q "status"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Response: $STATUS_RESPONSE"
    exit 1
fi

# Summary
echo ""
echo -e "${GREEN}✅ All E2E tests passed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Check routing metrics: sqlite3 ~/.local/share/zeke/routing.db 'SELECT * FROM routing_stats ORDER BY created_at DESC LIMIT 5;'"
echo "  2. Verify provider distribution"
echo "  3. Test MCP tools integration (when available)"
