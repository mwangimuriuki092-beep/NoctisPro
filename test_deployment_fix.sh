#!/bin/bash
set -euo pipefail

# Test script to verify our deployment fixes work
echo "🧪 Testing Deployment Environment Variable Fix"
echo "=============================================="

# Create a test directory
TEST_DIR="/tmp/noctis-env-test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Copy our fixed scripts
cp /workspace/deploy/install-native.sh .
cp /workspace/.env.example .

echo "📝 Testing environment variable creation..."

# Source the functions from our script
source install-native.sh

# Test the clean_env function
echo "🧹 Testing clean_env function..."
cat > .env << 'EOF'
SECURE_HSTS_SECONDS=0POSTGRES_PASSWORD=dNBMFXdUDuIDBa6NApBJ8rvo
DEBUG=False
VALID_VAR=test123
INVALID_LINE_WITH_NO_EQUALS
EOF

echo "Before clean_env:"
cat .env

clean_env

echo -e "\nAfter clean_env:"
cat .env

# Test the set_env function
echo -e "\n🔧 Testing set_env function..."
set_env SECURE_HSTS_SECONDS 3600
set_env POSTGRES_PASSWORD "securepassword123"
set_env NEW_VAR "test_value"

echo -e "\nFinal .env file:"
cat .env

# Test that the environment variables are properly formatted
echo -e "\n✅ Verification:"
if grep -q "^SECURE_HSTS_SECONDS=3600$" .env; then
    echo "✓ SECURE_HSTS_SECONDS properly set"
else
    echo "❌ SECURE_HSTS_SECONDS not properly set"
fi

if grep -q "^POSTGRES_PASSWORD=securepassword123$" .env; then
    echo "✓ POSTGRES_PASSWORD properly set"
else
    echo "❌ POSTGRES_PASSWORD not properly set"
fi

# Test loading the environment variables
echo -e "\n🔍 Testing environment variable loading..."
set -a
source .env
set +a

echo "SECURE_HSTS_SECONDS from env: '$SECURE_HSTS_SECONDS'"
echo "POSTGRES_PASSWORD from env: '$POSTGRES_PASSWORD'"

# Clean up
cd /
rm -rf "$TEST_DIR"

echo -e "\n🎉 Environment variable fix test completed successfully!"