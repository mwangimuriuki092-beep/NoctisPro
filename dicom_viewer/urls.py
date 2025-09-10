from django.urls import path
from . import views

app_name = 'dicom_viewer'

urlpatterns = [
    # Main viewer interface
    path('', views.viewer, name='viewer'),
    path('standalone/', views.standalone_viewer, name='standalone_viewer'),
    path('study/<int:study_id>/', views.view_study, name='view_study'),
    
    # API endpoints
    path('api/study/<int:study_id>/data/', views.api_study_data, name='api_study_data'),
    path('api/image/<int:image_id>/data/', views.api_image_data, name='api_image_data'),
    
    # Advanced reconstruction endpoints
    path('api/series/<int:series_id>/mpr/', views.api_mpr_reconstruction, name='api_mpr_reconstruction'),
    path('api/series/<int:series_id>/mip/', views.api_mip_reconstruction, name='api_mip_reconstruction'),
    path('api/series/<int:series_id>/bone/', views.api_bone_reconstruction, name='api_bone_reconstruction'),
    
    # Real-time features
    path('api/realtime/studies/', views.api_realtime_studies, name='api_realtime_studies'),
    path('api/study/<int:study_id>/progress/', views.api_study_progress, name='api_study_progress'),
    path('api/series/<int:series_id>/slices/', views.api_series_slices, name='api_series_slices'),
    path('api/series/<int:series_id>/images/', views.api_series_images_chunk, name='api_series_images_chunk'),
    
    # Measurements and annotations
    path('api/study/<int:study_id>/measurements/', views.api_measurements, name='api_measurements'),
    path('api/study/<int:study_id>/annotations/', views.api_annotations, name='api_annotations'),
    
    # DICOM file upload and processing
    path('upload/', views.upload_dicom, name='upload_dicom'),
    path('api/upload/progress/<str:upload_id>/', views.api_upload_progress, name='api_upload_progress'),
    path('api/process/study/<int:study_id>/', views.api_process_study, name='api_process_study'),

    # Printing
    path('print/settings/', views.print_settings_view, name='print_settings'),
    path('print/printers/', views.get_available_printers, name='get_available_printers'),
    path('print/image/', views.print_dicom_image, name='print_dicom_image'),
]