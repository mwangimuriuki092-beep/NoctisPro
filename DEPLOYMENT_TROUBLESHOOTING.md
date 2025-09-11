# NoctisPro Deployment Troubleshooting Guide

## Issue Summary
The deployment was failing due to:
1. **Syntax error in .env file** - Special characters in SECRET_KEY were not properly escaped
2. **Environment variables not loading** - Django settings.py was not configured to load .env files

## 🔧 Quick Fix

### Option 1: Use the Fix Script (Recommended)
```bash
# Copy the fix script to your server
scp fix-deployment.sh noctispacs@192.168.100.15:~/

# Run the fix script as root
sudo bash ~/fix-deployment.sh
```

### Option 2: Manual Fix

1. **Fix the .env file syntax:**
```bash
sudo cp /opt/noctis/.env /opt/noctis/.env.backup
sudo tee /opt/noctis/.env > /dev/null << 'EOF'
# Production Environment Variables for NoctisPro
DEBUG=false
SECRET_KEY="i6?^Dq/Bzs+-_pC)Zy0Z.g\$=haU+(mnd6V.D=LnWUl2}{gW@l~Bw#}94Y*c9L/\$l"
ALLOWED_HOSTS=localhost,127.0.0.1,192.168.100.15
CSRF_TRUSTED_ORIGINS=http://localhost:8000,http://127.0.0.1:8000,https://192.168.100.15
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:8000,http://127.0.0.1:8000
DATABASE_URL=postgresql://noctis:noctis@localhost:5432/noctis
REDIS_URL=redis://localhost:6379/0
SECURE_SSL_REDIRECT=false
SESSION_COOKIE_SECURE=false
CSRF_COOKIE_SECURE=false
SECURE_HSTS_SECONDS=0
EOF
```

2. **Set proper permissions:**
```bash
sudo chown www-data:www-data /opt/noctis/.env
sudo chmod 600 /opt/noctis/.env
```

3. **Test and restart services:**
```bash
cd /opt/noctis
source .venv/bin/activate
python manage.py migrate
sudo systemctl restart noctis-web.service
sudo systemctl status noctis-web.service
```

## 🔍 Root Cause Analysis

### Problem 1: .env File Syntax Error
**Original error:**
```
.env: line 3: syntax error near unexpected token `)'
.env: line 3: `SECRET_KEY=i6?^Dq/Bzs+-_pC)Zy0Z.g$=haU+(mnd6V.D=LnWUl2}{gW@l~Bw#}94Y*c9L/$l'
```

**Cause:** The SECRET_KEY contained special shell characters that needed to be escaped or quoted properly.

**Solution:** Wrapped the SECRET_KEY in double quotes and escaped the dollar signs.

### Problem 2: Django Settings Not Loading .env
**Original error:**
```
ValueError: SECRET_KEY environment variable must be set in production
```

**Cause:** The Django settings.py file was using `os.getenv()` but wasn't loading the .env file first.

**Solution:** Added `python-dotenv` loading to settings.py:
```python
from dotenv import load_dotenv
load_dotenv(BASE_DIR / '.env')
```

## 🧪 Testing the Fix

### 1. Test Environment Variable Loading
```bash
cd /opt/noctis
source .venv/bin/activate
python -c "
from dotenv import load_dotenv
load_dotenv('.env')
import os
print('SECRET_KEY loaded:', bool(os.getenv('SECRET_KEY')))
print('DEBUG:', os.getenv('DEBUG'))
"
```

### 2. Test Django Configuration
```bash
cd /opt/noctis
source .venv/bin/activate
python manage.py check
```

### 3. Test Database Connection
```bash
cd /opt/noctis
source .venv/bin/activate
python manage.py migrate --dry-run
```

## 🚀 Verification Steps

After applying the fix, verify everything works:

1. **Check service status:**
```bash
sudo systemctl status noctis-web.service
sudo systemctl status noctis-worker.service
```

2. **Check logs:**
```bash
sudo journalctl -u noctis-web.service -f
```

3. **Test HTTP endpoint:**
```bash
curl -I http://192.168.100.15:8000
```

4. **Check database connectivity:**
```bash
sudo -u postgres psql -c "\l" | grep noctis
```

## 🔧 Environment File Template

For future deployments, use this template for `/opt/noctis/.env`:

```bash
# Production Environment Variables for NoctisPro
DEBUG=false
SECRET_KEY="your-secret-key-here-properly-escaped"
ALLOWED_HOSTS=localhost,127.0.0.1,your-server-ip
CSRF_TRUSTED_ORIGINS=http://localhost:8000,https://your-domain.com
CORS_ALLOWED_ORIGINS=http://localhost:3000,https://your-frontend-domain.com
DATABASE_URL=postgresql://username:password@localhost:5432/database
REDIS_URL=redis://localhost:6379/0
SECURE_SSL_REDIRECT=true  # Set to true for HTTPS
SESSION_COOKIE_SECURE=true  # Set to true for HTTPS
CSRF_COOKIE_SECURE=true  # Set to true for HTTPS
SECURE_HSTS_SECONDS=31536000  # Set for HTTPS
```

## 🚨 Common Pitfalls

1. **Don't use unescaped special characters** in environment variables
2. **Always quote complex strings** in .env files
3. **Set proper file permissions** (600) for .env files
4. **Test environment loading** before running migrations
5. **Check systemd service logs** for detailed error messages

## 📞 Support

If issues persist:
1. Check Django logs: `sudo journalctl -u noctis-web.service -f`
2. Verify database connectivity: `sudo -u postgres psql noctis`
3. Test Redis: `redis-cli ping`
4. Check file permissions: `ls -la /opt/noctis/.env`

The fix addresses the core issues that were preventing the deployment from succeeding.