"""
Workspace Auto-Detection System for NoctisPro

This module automatically detects the current workspace environment and
configures the system accordingly. It supports:
- Development environments (local dev, Docker, etc.)
- Production environments (deployed instances)
- Testing environments (CI/CD, automated testing)
- Multiple deployment locations (/workspace, /opt/noctis, etc.)
"""

import os
import sys
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple
import socket
import platform


class WorkspaceDetector:
    """Automatically detects and configures workspace environments."""
    
    def __init__(self):
        self.current_path = Path.cwd()
        self.script_path = Path(__file__).resolve().parent.parent
        self.detected_workspace = None
        self.workspace_config = {}
        
    def detect_workspace(self) -> Dict[str, Any]:
        """
        Detect the current workspace environment and return configuration.
        
        Returns:
            Dict containing workspace configuration
        """
        # Try to detect workspace from multiple indicators
        workspace_indicators = [
            self._detect_from_path(),
            self._detect_from_environment(),
            self._detect_from_files(),
            self._detect_from_network(),
            self._detect_from_process()
        ]
        
        # Combine all detection results
        workspace_config = {
            'workspace_type': 'unknown',
            'base_path': self.script_path,
            'is_development': True,  # Default to development for safety
            'is_production': False,
            'is_testing': False,
            'is_docker': False,
            'is_ci': False,
            'debug': True,
            'allowed_hosts': ['localhost', '127.0.0.1'],
            'database_url': None,
            'redis_url': 'redis://localhost:6379/0',
            'static_root': None,
            'media_root': None,
            'log_level': 'DEBUG',
            'secure_ssl_redirect': False,
            'session_cookie_secure': False,
            'csrf_cookie_secure': False,
        }
        
        # Apply detection results in priority order
        for indicator in workspace_indicators:
            if indicator:
                workspace_config.update(indicator)
        
        # Final workspace type determination
        workspace_config['workspace_type'] = self._determine_workspace_type(workspace_config)
        
        # Apply workspace-specific configurations
        workspace_config = self._apply_workspace_specific_config(workspace_config)
        
        self.workspace_config = workspace_config
        return workspace_config
    
    def _detect_from_path(self) -> Optional[Dict[str, Any]]:
        """Detect workspace from file system paths."""
        current_path_str = str(self.current_path)
        script_path_str = str(self.script_path)
        
        config = {}
        
        # Check for common deployment paths
        if '/opt/noctis' in script_path_str or '/opt/noctis' in current_path_str:
            config.update({
                'workspace_type': 'production_opt',
                'base_path': Path('/opt/noctis'),
                'is_production': True,
                'is_development': False,
                'debug': False,
            })
        elif '/workspace' in script_path_str or current_path_str == '/workspace':
            config.update({
                'workspace_type': 'container_workspace',
                'base_path': Path('/workspace'),
                'is_docker': True,
            })
        elif 'venv' in script_path_str or '.venv' in script_path_str:
            config.update({
                'workspace_type': 'development_venv',
                'is_development': True,
                'debug': True,
            })
        elif '/home' in script_path_str and 'dev' in script_path_str.lower():
            config.update({
                'workspace_type': 'development_home',
                'is_development': True,
                'debug': True,
            })
        
        return config if config else None
    
    def _detect_from_environment(self) -> Optional[Dict[str, Any]]:
        """Detect workspace from environment variables."""
        config = {}
        
        # Check for container environments
        if os.getenv('DOCKER_CONTAINER') or os.path.exists('/.dockerenv'):
            config.update({
                'is_docker': True,
                'workspace_type': 'docker',
            })
        
        # Check for CI/CD environments
        ci_indicators = ['CI', 'CONTINUOUS_INTEGRATION', 'GITHUB_ACTIONS', 'GITLAB_CI', 'JENKINS_URL']
        if any(os.getenv(indicator) for indicator in ci_indicators):
            config.update({
                'is_ci': True,
                'is_testing': True,
                'workspace_type': 'ci_testing',
                'debug': False,
                'log_level': 'INFO',
            })
        
        # Check for production environment indicators
        if os.getenv('DJANGO_SETTINGS_MODULE') and 'prod' in os.getenv('DJANGO_SETTINGS_MODULE', '').lower():
            config.update({
                'is_production': True,
                'is_development': False,
                'debug': False,
            })
        
        # Check for development indicators
        if os.getenv('VIRTUAL_ENV') or os.getenv('CONDA_DEFAULT_ENV'):
            config.update({
                'is_development': True,
                'workspace_type': 'development_virtual_env',
            })
        
        return config if config else None
    
    def _detect_from_files(self) -> Optional[Dict[str, Any]]:
        """Detect workspace from file system indicators."""
        config = {}
        base_path = self.script_path
        
        # Check for development indicators
        dev_files = ['.git', 'requirements-dev.txt', 'pytest.ini', 'tox.ini']
        if any((base_path / file).exists() for file in dev_files):
            config.update({
                'is_development': True,
                'debug': True,
            })
        
        # Check for production indicators
        prod_files = ['gunicorn.conf.py', 'uwsgi.ini', 'supervisor.conf']
        if any((base_path / file).exists() for file in prod_files):
            config.update({
                'is_production': True,
                'is_development': False,
                'debug': False,
            })
        
        # Check for Docker indicators
        docker_files = ['Dockerfile', 'docker-compose.yml', '.dockerignore']
        if any((base_path / file).exists() for file in docker_files):
            config.update({
                'is_docker': True,
            })
        
        # Check for testing indicators
        test_files = ['pytest.ini', 'tox.ini', '.github/workflows', '.gitlab-ci.yml']
        if any((base_path / file).exists() for file in test_files):
            config.update({
                'is_testing': True,
            })
        
        return config if config else None
    
    def _detect_from_network(self) -> Optional[Dict[str, Any]]:
        """Detect workspace from network configuration."""
        config = {}
        
        try:
            hostname = socket.gethostname()
            
            # Check for development hostnames
            dev_hostnames = ['dev', 'development', 'local', 'localhost']
            if any(indicator in hostname.lower() for indicator in dev_hostnames):
                config.update({
                    'is_development': True,
                    'debug': True,
                })
            
            # Check for production hostnames
            prod_hostnames = ['prod', 'production', 'live', 'server']
            if any(indicator in hostname.lower() for indicator in prod_hostnames):
                config.update({
                    'is_production': True,
                    'is_development': False,
                    'debug': False,
                })
            
            # Add hostname to allowed hosts
            config['allowed_hosts'] = ['localhost', '127.0.0.1', hostname]
            
            # Try to get local IP
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.connect(("8.8.8.8", 80))
                local_ip = s.getsockname()[0]
                s.close()
                config['allowed_hosts'].append(local_ip)
            except Exception:
                pass
                
        except Exception:
            pass
        
        return config if config else None
    
    def _detect_from_process(self) -> Optional[Dict[str, Any]]:
        """Detect workspace from process information."""
        config = {}
        
        # Check if running under a web server
        if any(name in sys.argv[0].lower() for name in ['gunicorn', 'uwsgi', 'daphne']):
            config.update({
                'is_production': True,
                'is_development': False,
                'debug': False,
            })
        
        # Check if running in development server
        if 'runserver' in sys.argv:
            config.update({
                'is_development': True,
                'debug': True,
                'workspace_type': 'development_runserver',
            })
        
        # Check if running tests
        if any(name in sys.argv for name in ['test', 'pytest', 'unittest']):
            config.update({
                'is_testing': True,
                'debug': True,
                'workspace_type': 'testing',
            })
        
        return config if config else None
    
    def _determine_workspace_type(self, config: Dict[str, Any]) -> str:
        """Determine the final workspace type based on all indicators."""
        if config.get('is_ci'):
            return 'ci_testing'
        elif config.get('is_testing'):
            return 'testing'
        elif config.get('is_production') and config.get('is_docker'):
            return 'production_docker'
        elif config.get('is_production'):
            return 'production'
        elif config.get('is_docker'):
            return 'development_docker'
        elif config.get('is_development'):
            return 'development'
        else:
            return 'unknown'
    
    def _apply_workspace_specific_config(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Apply workspace-specific configurations."""
        workspace_type = config['workspace_type']
        base_path = config['base_path']
        
        # Production configurations
        if config.get('is_production'):
            config.update({
                'debug': False,
                'log_level': 'INFO',
                'secure_ssl_redirect': True,
                'session_cookie_secure': True,
                'csrf_cookie_secure': True,
                'static_root': base_path / 'staticfiles',
                'media_root': base_path / 'media',
            })
        
        # Development configurations
        if config.get('is_development'):
            config.update({
                'debug': True,
                'log_level': 'DEBUG',
                'secure_ssl_redirect': False,
                'session_cookie_secure': False,
                'csrf_cookie_secure': False,
                'static_root': base_path / 'static',
                'media_root': base_path / 'media',
            })
        
        # Docker configurations
        if config.get('is_docker'):
            config.update({
                'allowed_hosts': config['allowed_hosts'] + ['0.0.0.0', '*'],
                'database_url': os.getenv('DATABASE_URL', 'postgresql://noctis:noctis@db:5432/noctis'),
                'redis_url': os.getenv('REDIS_URL', 'redis://redis:6379/0'),
            })
        
        # Testing configurations
        if config.get('is_testing'):
            config.update({
                'database_url': 'sqlite:///:memory:',
                'redis_url': 'redis://localhost:6379/15',  # Use different Redis DB for tests
                'log_level': 'WARNING',
            })
        
        return config
    
    def get_django_settings(self) -> Dict[str, Any]:
        """Get Django-specific settings based on detected workspace."""
        if not self.workspace_config:
            self.detect_workspace()
        
        config = self.workspace_config
        
        django_settings = {
            'DEBUG': config.get('debug', True),
            'ALLOWED_HOSTS': config.get('allowed_hosts', ['localhost', '127.0.0.1']),
            'DATABASE_URL': config.get('database_url'),
            'REDIS_URL': config.get('redis_url', 'redis://localhost:6379/0'),
            'STATIC_ROOT': str(config.get('static_root', config['base_path'] / 'staticfiles')),
            'MEDIA_ROOT': str(config.get('media_root', config['base_path'] / 'media')),
            'SECURE_SSL_REDIRECT': config.get('secure_ssl_redirect', False),
            'SESSION_COOKIE_SECURE': config.get('session_cookie_secure', False),
            'CSRF_COOKIE_SECURE': config.get('csrf_cookie_secure', False),
            'LOG_LEVEL': config.get('log_level', 'DEBUG'),
        }
        
        return django_settings
    
    def print_detection_report(self):
        """Print a detailed workspace detection report."""
        if not self.workspace_config:
            self.detect_workspace()
        
        config = self.workspace_config
        
        print("=" * 60)
        print("WORKSPACE AUTO-DETECTION REPORT")
        print("=" * 60)
        print(f"Detected Workspace Type: {config['workspace_type']}")
        print(f"Base Path: {config['base_path']}")
        print(f"Current Working Directory: {self.current_path}")
        print(f"Script Path: {self.script_path}")
        print()
        print("Environment Flags:")
        print(f"  - Development: {config.get('is_development', False)}")
        print(f"  - Production: {config.get('is_production', False)}")
        print(f"  - Testing: {config.get('is_testing', False)}")
        print(f"  - Docker: {config.get('is_docker', False)}")
        print(f"  - CI/CD: {config.get('is_ci', False)}")
        print()
        print("Configuration:")
        print(f"  - Debug Mode: {config.get('debug', True)}")
        print(f"  - Log Level: {config.get('log_level', 'DEBUG')}")
        print(f"  - Allowed Hosts: {', '.join(config.get('allowed_hosts', []))}")
        print(f"  - Database URL: {config.get('database_url', 'Not set')}")
        print(f"  - Redis URL: {config.get('redis_url', 'redis://localhost:6379/0')}")
        print("=" * 60)


# Global detector instance
detector = WorkspaceDetector()


def get_workspace_config() -> Dict[str, Any]:
    """Get the current workspace configuration."""
    return detector.detect_workspace()


def get_django_settings() -> Dict[str, Any]:
    """Get Django-specific settings for the current workspace."""
    return detector.get_django_settings()


def print_workspace_report():
    """Print a workspace detection report."""
    detector.print_detection_report()


# Auto-detect on module import
if __name__ == "__main__":
    print_workspace_report()