"""
URL configuration for noctis_pro project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from django.shortcuts import redirect

def home_redirect(request):
    """Redirect home page to login or dashboard based on authentication"""
    if request.user.is_authenticated:
        # Temporarily redirect all authenticated users to worklist dashboard
        return redirect('worklist:dashboard')
    return redirect('accounts:login')

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', home_redirect, name='home'),
    path('', include('accounts.urls')),
    path('worklist/', include('worklist.urls')),
    path('viewer/', include('dicom_viewer.urls')),
    path('reports/', include('reports.urls')),
    path('admin-panel/', include('admin_panel.urls')),
    path('chat/', include('chat.urls')),  # Re-enabled to fix template URLs
    path('notifications/', include('notifications.urls')),  # Re-enabled to fix template URLs
    path('ai/', include('ai_analysis.urls')),
]

# Serve media files during development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
