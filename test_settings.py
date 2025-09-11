#!/usr/bin/env python3
"""
Test script to verify Django settings can be loaded without errors.
This helps debug environment variable parsing issues.
"""
import os
import sys

# Add the project directory to Python path
sys.path.insert(0, '/workspace')

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'noctis_pro.settings')

def test_settings():
    try:
        print("Testing Django settings import...")
        
        # Try to import Django and configure settings
        import django
        from django.conf import settings
        
        print("✓ Django imported successfully")
        
        # Test specific problematic setting
        hsts_seconds = settings.SECURE_HSTS_SECONDS
        print(f"✓ SECURE_HSTS_SECONDS = {hsts_seconds}")
        
        # Test other security settings
        print(f"✓ SECURE_HSTS_INCLUDE_SUBDOMAINS = {settings.SECURE_HSTS_INCLUDE_SUBDOMAINS}")
        print(f"✓ SECURE_HSTS_PRELOAD = {settings.SECURE_HSTS_PRELOAD}")
        print(f"✓ SECURE_REFERRER_POLICY = {settings.SECURE_REFERRER_POLICY}")
        
        # Test database configuration
        print(f"✓ DATABASE_URL from env = {os.getenv('DATABASE_URL', 'Not set')}")
        print(f"✓ POSTGRES_PASSWORD from env = {os.getenv('POSTGRES_PASSWORD', 'Not set')}")
        
        print("\n🎉 All settings loaded successfully!")
        return True
        
    except Exception as e:
        print(f"❌ Error loading settings: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_settings()
    sys.exit(0 if success else 1)