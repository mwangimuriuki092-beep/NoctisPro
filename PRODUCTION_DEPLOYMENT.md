# 🚀 NOCTIS PRO - PRODUCTION DEPLOYMENT GUIDE

Complete production deployment guide for Ubuntu Server 22.04 with HTTPS access and large file support for medical imaging (DICOM files).

## 📋 Prerequisites

- **Fresh Ubuntu Server 22.04** (recommended: 4GB+ RAM, 50GB+ storage)
- **Root access** (sudo privileges)
- **Internet connection**
- **PageKite account** (optional, for external HTTPS access without port forwarding)

## 🎯 Quick Start (One Command)

### Option 1: Deploy with External HTTPS Access (PageKite)
```bash
# 1. SSH to your Ubuntu 22.04 server
ssh user@your-server-ip

# 2. Clone or upload this repository
git clone <repository-url> noctis_pro
cd noctis_pro

# 3. Run one-command deployment with PageKite
sudo bash quick-deploy.sh YOUR_PAGEKITE_SECRET
```

### Option 2: Deploy for Local Network Only
```bash
# 1. SSH to your Ubuntu 22.04 server
ssh user@your-server-ip

# 2. Clone or upload this repository
git clone <repository-url> noctis_pro
cd noctis_pro

# 3. Run one-command deployment (local only)
sudo bash quick-deploy.sh
```

## 🔧 Advanced Deployment Options

### Deploy with Custom Domain
```bash
sudo bash deploy/deploy-production.sh --domain noctis.yourdomain.com
```

### Deploy to Custom Directory
```bash
sudo bash deploy/deploy-production.sh --app-dir /custom/path --pagekite-subdomain mysubdomain --pagekite-secret SECRET
```

### Skip System Provisioning (if already done)
```bash
sudo bash deploy/deploy-production.sh --skip-provision --pagekite-subdomain mysubdomain --pagekite-secret SECRET
```

## 📊 Production Features

### ✅ **Security & Hardening**
- **Firewall**: UFW configured (SSH, HTTP, HTTPS only)
- **Fail2ban**: Protection against brute force attacks
- **HTTPS/TLS**: Automatic SSL certificates via Let's Encrypt
- **Security Headers**: HSTS, CSP, XSS protection
- **Service Isolation**: Systemd security features
- **File Permissions**: Proper ownership and permissions

### ✅ **Performance & Scalability**
- **Database**: PostgreSQL (production-ready)
- **Caching**: Redis for sessions and caching
- **Static Files**: Optimized serving via Caddy
- **Process Management**: Systemd with auto-restart
- **Resource Limits**: Memory and CPU limits configured
- **File Uploads**: Support for 1GB files (DICOM studies)

### ✅ **Monitoring & Maintenance**
- **Health Checks**: Built-in health endpoints
- **Logging**: Centralized logging via systemd journal
- **Log Rotation**: Automatic log rotation
- **Service Management**: Easy start/stop/restart commands

### ✅ **Large File Support (DICOM)**
- **Upload Limit**: 1GB per file
- **Memory Handling**: 256MB memory buffer
- **Processing Timeout**: 5 minutes for large studies
- **Storage**: Efficient file storage and serving

## 🌐 Access Methods

### Local Network Access
- **HTTP**: `http://SERVER_IP:8000`
- **Admin**: `http://SERVER_IP:8000/admin/`

### External HTTPS Access (PageKite)
- **HTTPS**: `https://SUBDOMAIN.pagekite.me`
- **Admin**: `https://SUBDOMAIN.pagekite.me/admin/`
- **Benefits**: No port forwarding needed, automatic HTTPS

### Custom Domain Access
- **HTTPS**: `https://your-domain.com`
- **Admin**: `https://your-domain.com/admin/`
- **Requirements**: DNS pointing to your server, ports 80/443 open

## 👤 Default Admin Credentials

After deployment, you'll receive automatically generated credentials:

```
Username: admin
Password: [auto-generated, shown after deployment]
Email: mwangimuriuki092@gmail.com
```

**🔒 Security Note**: Change the default password after first login!

## 🛠️ Post-Deployment Management

### Service Management
```bash
# Check service status
sudo systemctl status noctis-web noctis-worker caddy

# View logs
sudo journalctl -u noctis-web -f
sudo journalctl -u noctis-worker -f

# Restart services
sudo systemctl restart noctis-web
sudo systemctl restart noctis-worker
sudo systemctl restart caddy

# PageKite tunnel (if enabled)
sudo systemctl status noctis-tunnel
sudo systemctl restart noctis-tunnel
```

### Configuration
```bash
# Edit environment variables
sudo nano /opt/noctis/.env

# Restart services after config changes
sudo systemctl restart noctis-web noctis-worker
```

### File Management
```bash
# Application directory
cd /opt/noctis

# Media files (uploads)
ls -la /opt/noctis/media/

# Logs
sudo journalctl -u noctis-web --since "1 hour ago"
```

## 🔍 Troubleshooting

### Health Checks
```bash
# Local health check
curl -I http://localhost:8000/health/

# External health check (PageKite)
curl -I https://SUBDOMAIN.pagekite.me/health/

# Custom domain health check
curl -I https://your-domain.com/health/
```

### Common Issues

#### 1. Service Not Starting
```bash
# Check service status and logs
sudo systemctl status noctis-web
sudo journalctl -u noctis-web -n 50

# Common fixes
sudo systemctl restart postgresql
sudo systemctl restart redis-server
sudo systemctl restart noctis-web
```

#### 2. Database Connection Issues
```bash
# Check PostgreSQL
sudo systemctl status postgresql
sudo -u postgres psql -c "\l"

# Reset database connection
sudo systemctl restart noctis-web
```

#### 3. File Upload Issues
```bash
# Check disk space
df -h

# Check file permissions
ls -la /opt/noctis/media/

# Fix permissions
sudo chown -R www-data:www-data /opt/noctis/media/
```

#### 4. PageKite Tunnel Issues
```bash
# Check tunnel status
sudo systemctl status noctis-tunnel
sudo journalctl -u noctis-tunnel -n 20

# Test PageKite manually
sudo -u www-data pagekite --clean --defaults --service_on=SUBDOMAIN.pagekite.me:443 https:127.0.0.1:8000 EMAIL SECRET
```

### Log Locations
```bash
# Application logs
sudo journalctl -u noctis-web -f
sudo journalctl -u noctis-worker -f

# Web server logs
sudo journalctl -u caddy -f

# System logs
sudo tail -f /var/log/syslog
```

## 🔄 Updates and Maintenance

### Application Updates
```bash
# 1. Stop services
sudo systemctl stop noctis-web noctis-worker

# 2. Backup current installation
sudo cp -r /opt/noctis /opt/noctis.backup.$(date +%Y%m%d)

# 3. Update code
cd /path/to/new/code
sudo bash deploy/install-native.sh /path/to/new/code /opt/noctis

# 4. Start services
sudo systemctl start noctis-web noctis-worker
```

### Database Backup
```bash
# Create backup
sudo -u postgres pg_dump noctis_pro > noctis_backup_$(date +%Y%m%d).sql

# Restore backup
sudo -u postgres psql noctis_pro < noctis_backup_YYYYMMDD.sql
```

## 📈 Performance Tuning

### For High-Volume Usage
```bash
# Edit /opt/noctis/.env
CONN_MAX_AGE=3600                    # Longer DB connections
DICOM_MEMORY_LIMIT=1024             # More memory for DICOM processing

# Restart services
sudo systemctl restart noctis-web noctis-worker
```

### Database Optimization
```bash
# PostgreSQL tuning (adjust for your server specs)
sudo nano /etc/postgresql/14/main/postgresql.conf

# Recommended changes for 4GB+ RAM servers:
# shared_buffers = 1GB
# effective_cache_size = 3GB
# work_mem = 64MB
# maintenance_work_mem = 256MB

sudo systemctl restart postgresql
```

## 🆘 Support

### Getting Help
1. **Check logs first**: `sudo journalctl -u noctis-web -f`
2. **Verify configuration**: Check `/opt/noctis/.env`
3. **Test health endpoints**: `curl -I http://localhost:8000/health/`
4. **Check service status**: `sudo systemctl status noctis-web noctis-worker caddy`

### System Information
```bash
# After deployment, find this information in:
cat /opt/noctis/DEPLOYMENT_INFO.txt
```

---

## 🎉 Success!

Your Noctis Pro DICOM medical imaging viewer is now running in production with:

- ✅ **Secure HTTPS access** (local and/or external)
- ✅ **Large file upload support** (up to 1GB for DICOM studies)
- ✅ **Production-grade security** and performance
- ✅ **Automatic service management** and monitoring
- ✅ **Admin interface** ready for use

**Access your application at the URLs provided after deployment!**