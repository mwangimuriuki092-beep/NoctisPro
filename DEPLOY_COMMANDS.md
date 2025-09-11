# 🚀 NOCTIS PRO - DEPLOYMENT COMMANDS

## Your PageKite Configuration
- **Subdomain**: `noctispro.pagekite.me`
- **Email**: `mwangimuriuki092@gmail.com`
- **External URL**: `https://noctispro.pagekite.me`

## 🎯 Ready-to-Use Commands

### Option 1: Deploy with Your Current PageKite Secret
```bash
# SSH to your Ubuntu 22.04 server
ssh user@your-server-ip

# Clone/upload the repository and cd into it
git clone <repository-url> noctis_pro
cd noctis_pro

# Deploy with PageKite (using your current secret)
sudo bash quick-deploy.sh root123
```

### Option 2: Deploy with Your Default PageKite Secret (Recommended)
```bash
# SSH to your Ubuntu 22.04 server
ssh user@your-server-ip

# Clone/upload the repository and cd into it
git clone <repository-url> noctis_pro
cd noctis_pro

# Deploy with PageKite (using your default secret - more secure)
sudo bash quick-deploy.sh zzkfzcx46xxx49d87xkxf6fc87c28az8
```

### Option 3: Deploy for Local Access Only
```bash
# SSH to your Ubuntu 22.04 server
ssh user@your-server-ip

# Clone/upload the repository and cd into it
git clone <repository-url> noctis_pro
cd noctis_pro

# Deploy without external access
sudo bash quick-deploy.sh
```

## 📋 What Happens After Deployment

### ✅ You'll Get:
- **Local Access**: `http://SERVER_IP:8000`
- **External Access**: `https://noctispro.pagekite.me`
- **Admin Panel**: `https://noctispro.pagekite.me/admin/`
- **Auto-generated admin credentials** (displayed after deployment)

### 🔧 Services Installed:
- **Web Server**: Caddy with HTTPS
- **Database**: PostgreSQL
- **Cache**: Redis
- **Background Tasks**: Celery workers
- **Tunnel**: PageKite for external access
- **Security**: Firewall + Fail2ban

### 📊 File Upload Limits:
- **Max File Size**: 5GB (handles very large DICOM studies)
- **Memory Buffer**: 512MB
- **Processing Timeout**: 10 minutes

## 🚀 Recommended Deployment Command

**For production with external HTTPS access:**

```bash
sudo bash quick-deploy.sh zzkfzcx46xxx49d87xkxf6fc87c28az8
```

This uses your default PageKite secret which is more secure than the simple "root123" one.

## ✨ After Deployment

1. **Access your app**: `https://noctispro.pagekite.me`
2. **Login to admin**: Use the credentials shown after deployment
3. **Upload DICOM files**: Up to 1GB per file supported
4. **Monitor services**: `sudo systemctl status noctis-web noctis-worker caddy noctis-tunnel`

## 🔍 Troubleshooting

If PageKite tunnel doesn't work immediately:
```bash
# Check tunnel status
sudo systemctl status noctis-tunnel

# Restart tunnel
sudo systemctl restart noctis-tunnel

# Test manually
sudo journalctl -u noctis-tunnel -f
```

Your PageKite configuration is already set up perfectly in the scripts! 🎉