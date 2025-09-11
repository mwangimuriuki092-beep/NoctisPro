#!/bin/bash
set -euo pipefail

echo "🧪 Testing Environment Variable Functions"
echo "========================================"

# Create test directory
TEST_DIR="/tmp/noctis-env-test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Define the functions from our script
clean_env() {
  if [[ -f .env ]]; then
    # Remove lines that don't follow KEY=VALUE format
    grep -E '^[A-Z_][A-Z0-9_]*=' .env > .env.tmp || touch .env.tmp
    mv .env.tmp .env
    # Ensure file ends with newline
    [[ -s .env && $(tail -c1 .env | wc -l) -eq 0 ]] && echo "" >> .env
  fi
}

set_env() {
  local key="$1"; shift
  local value="$*"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    # Ensure the .env file ends with a newline before appending
    [[ -s .env && $(tail -c1 .env | wc -l) -eq 0 ]] && echo "" >> .env
    echo "${key}=${value}" >> .env
  fi
}

# Test malformed .env file (simulating the original issue)
echo "📝 Creating malformed .env file (simulating the original bug)..."
cat > .env << 'EOF'
SECURE_HSTS_SECONDS=0POSTGRES_PASSWORD=dNBMFXdUDuIDBa6NApBJ8rvo
DEBUG=False
VALID_VAR=test123
INVALID_LINE_WITH_NO_EQUALS
EOF

echo "Before clean_env:"
echo "=================="
cat .env | sed 's/^/  /'

echo -e "\n🧹 Running clean_env..."
clean_env

echo -e "\nAfter clean_env:"
echo "================"
cat .env | sed 's/^/  /'

echo -e "\n🔧 Testing set_env function..."
set_env SECURE_HSTS_SECONDS 3600
set_env POSTGRES_PASSWORD "securepassword123"
set_env NEW_VAR "test_value"

echo -e "\nFinal .env file:"
echo "================"
cat .env | sed 's/^/  /'

echo -e "\n✅ Verification:"
success=true

if grep -q "^SECURE_HSTS_SECONDS=3600$" .env; then
    echo "  ✓ SECURE_HSTS_SECONDS properly set"
else
    echo "  ❌ SECURE_HSTS_SECONDS not properly set"
    success=false
fi

if grep -q "^POSTGRES_PASSWORD=securepassword123$" .env; then
    echo "  ✓ POSTGRES_PASSWORD properly set"
else
    echo "  ❌ POSTGRES_PASSWORD not properly set"
    success=false
fi

if grep -q "^DEBUG=False$" .env; then
    echo "  ✓ DEBUG properly preserved"
else
    echo "  ❌ DEBUG not properly preserved"
    success=false
fi

# Test that malformed lines are removed
if grep -q "INVALID_LINE_WITH_NO_EQUALS" .env; then
    echo "  ❌ Invalid line not removed"
    success=false
else
    echo "  ✓ Invalid line properly removed"
fi

# Test environment variable loading
echo -e "\n🔍 Testing environment variable loading..."
set -a
source .env 2>/dev/null || echo "Warning: Some env vars might have issues"
set +a

echo "  SECURE_HSTS_SECONDS from env: '${SECURE_HSTS_SECONDS:-NOT_SET}'"
echo "  POSTGRES_PASSWORD from env: '${POSTGRES_PASSWORD:-NOT_SET}'"
echo "  DEBUG from env: '${DEBUG:-NOT_SET}'"

# Verify no concatenated values
if [[ "${SECURE_HSTS_SECONDS:-}" == "3600" ]]; then
    echo "  ✓ SECURE_HSTS_SECONDS correctly parsed"
else
    echo "  ❌ SECURE_HSTS_SECONDS incorrectly parsed: '${SECURE_HSTS_SECONDS:-NOT_SET}'"
    success=false
fi

# Clean up
cd /
rm -rf "$TEST_DIR"

if [[ "$success" == "true" ]]; then
    echo -e "\n🎉 All tests passed! Environment variable fix works correctly!"
    exit 0
else
    echo -e "\n❌ Some tests failed!"
    exit 1
fi