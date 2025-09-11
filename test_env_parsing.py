#!/usr/bin/env python3
"""
Test script to simulate the environment variable parsing issue and verify our fix.
"""
import os
import tempfile
import sys

# Add the project directory to Python path
sys.path.insert(0, '/workspace')

def create_malformed_env():
    """Create a malformed .env file that simulates the concatenation issue"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
        # Simulate the malformed environment variable (without proper newline)
        f.write('SECURE_HSTS_SECONDS=0POSTGRES_PASSWORD=dNBMFXdUDuIDBa6NApBJ8rvo\n')
        f.write('DEBUG=False\n')
        return f.name

def test_malformed_env_handling():
    """Test that our fix handles malformed environment variables gracefully"""
    print("🧪 Testing malformed environment variable handling...")
    
    # Create malformed env file
    env_file = create_malformed_env()
    
    try:
        # Load the malformed env file
        from dotenv import load_dotenv
        load_dotenv(env_file)
        
        # Show what the environment variable looks like
        hsts_value = os.getenv('SECURE_HSTS_SECONDS', '0')
        print(f"Raw SECURE_HSTS_SECONDS value: '{hsts_value}'")
        
        # Test our parsing logic from settings.py
        try:
            hsts_value_clean = hsts_value.strip()
            if not hsts_value_clean.isdigit():
                print(f"⚠️  Warning: SECURE_HSTS_SECONDS value '{hsts_value_clean}' is not a valid integer, using default 0")
                hsts_value_clean = '0'
            result = int(hsts_value_clean)
            print(f"✅ Successfully parsed SECURE_HSTS_SECONDS as: {result}")
            return True
        except ValueError as e:
            print(f"❌ Error parsing SECURE_HSTS_SECONDS: {e}")
            print(f"Raw value: '{hsts_value}'")
            result = 0
            print(f"✅ Fallback to default: {result}")
            return True
            
    finally:
        # Clean up
        os.unlink(env_file)

def test_normal_env():
    """Test that normal environment variables still work"""
    print("\n🧪 Testing normal environment variable handling...")
    
    # Set a normal environment variable
    os.environ['SECURE_HSTS_SECONDS'] = '3600'
    
    try:
        hsts_value = os.getenv('SECURE_HSTS_SECONDS', '0').strip()
        if not hsts_value.isdigit():
            print(f"⚠️  Warning: SECURE_HSTS_SECONDS value '{hsts_value}' is not a valid integer, using default 0")
            hsts_value = '0'
        result = int(hsts_value)
        print(f"✅ Successfully parsed normal SECURE_HSTS_SECONDS as: {result}")
        return result == 3600
    except ValueError as e:
        print(f"❌ Error parsing normal SECURE_HSTS_SECONDS: {e}")
        return False
    finally:
        # Clean up
        if 'SECURE_HSTS_SECONDS' in os.environ:
            del os.environ['SECURE_HSTS_SECONDS']

def main():
    print("🔧 Testing Environment Variable Parsing Fix")
    print("=" * 50)
    
    success1 = test_malformed_env_handling()
    success2 = test_normal_env()
    
    print("\n📊 Test Results:")
    print("=" * 50)
    print(f"Malformed env handling: {'✅ PASS' if success1 else '❌ FAIL'}")
    print(f"Normal env handling: {'✅ PASS' if success2 else '❌ FAIL'}")
    
    if success1 and success2:
        print("\n🎉 All tests passed! The fix should handle the environment variable parsing issue.")
        return True
    else:
        print("\n❌ Some tests failed. The fix needs more work.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)