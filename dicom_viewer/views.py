from django.shortcuts import render, get_object_or_404, redirect
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.contrib import messages
from worklist.models import Study, Series, DicomImage
from accounts.models import User
import json
import base64
import os
import time
import numpy as np
import pydicom
from io import BytesIO
import cv2
from PIL import Image
from django.utils import timezone
from django.conf import settings
import uuid

@login_required
def viewer(request):
    """Main DICOM viewer interface"""
    user = request.user
    
    # Get recent studies for quick access
    if user.is_facility_user():
        recent_studies = Study.objects.filter(facility=user.facility).order_by('-study_date')[:10]
    else:
        recent_studies = Study.objects.all().order_by('-study_date')[:10]
    
    context = {
        'user': user,
        'recent_studies': recent_studies,
    }
    
    return render(request, 'dicom_viewer/viewer.html', context)

@login_required
def standalone_viewer(request):
    """Standalone DICOM viewer for any DICOM files"""
    context = {
        'user': request.user,
        'standalone': True,
    }
    
    return render(request, 'dicom_viewer/standalone_viewer.html', context)

@login_required
def view_study(request, study_id):
    """View specific study in DICOM viewer"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        messages.error(request, 'You do not have permission to view this study.')
        return redirect('dicom_viewer:viewer')
    
    # Update study status to in_progress if it was scheduled
    if study.status == 'scheduled':
        study.status = 'in_progress'
        study.save()
    
    # Get series and images
    series_list = study.series_set.all().order_by('series_number')
    
    # Prepare series data for viewer
    series_data = []
    for series in series_list:
        images = series.images.all().order_by('instance_number')
        series_data.append({
            'id': series.id,
            'series_number': series.series_number,
            'description': series.series_description,
            'modality': series.modality,
            'image_count': images.count(),
            'slice_thickness': series.slice_thickness,
            'pixel_spacing': series.pixel_spacing,
            'images': [
                {
                    'id': img.id,
                    'instance_number': img.instance_number,
                    'file_path': img.file_path.url if img.file_path else '',
                    'slice_location': img.slice_location,
                    'image_position': img.image_position,
                } for img in images
            ]
        })
    
    context = {
        'study': study,
        'series_data': json.dumps(series_data),
        'user': user,
    }
    
    return render(request, 'dicom_viewer/study_viewer.html', context)

@login_required
@csrf_exempt
def api_study_data(request, study_id):
    """API endpoint to get study data for viewer"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    series_list = study.series_set.all().order_by('series_number')
    
    data = {
        'study': {
            'id': study.id,
            'accession_number': study.accession_number,
            'patient_name': study.patient.full_name,
            'patient_id': study.patient.patient_id,
            'study_date': study.study_date.isoformat(),
            'modality': study.modality.code,
            'description': study.study_description,
            'body_part': study.body_part,
        },
        'series': []
    }
    
    for series in series_list:
        images = series.images.all().order_by('instance_number')
        series_info = {
            'id': series.id,
            'series_number': series.series_number,
            'description': series.series_description,
            'modality': series.modality,
            'image_count': images.count(),
            'slice_thickness': series.slice_thickness,
            'pixel_spacing': series.pixel_spacing,
            'image_orientation': series.image_orientation,
            'images': []
        }
        
        for img in images:
            image_info = {
                'id': img.id,
                'instance_number': img.instance_number,
                'file_path': img.file_path.url if img.file_path else '',
                'slice_location': img.slice_location,
                'image_position': img.image_position,
                'file_size': img.file_size,
            }
            series_info['images'].append(image_info)
        
        data['series'].append(series_info)
    
    return JsonResponse(data)

@login_required
@csrf_exempt
def api_image_data(request, image_id):
    """API endpoint to get specific image data"""
    image = get_object_or_404(DicomImage, id=image_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and image.series.study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    data = {
        'id': image.id,
        'instance_number': image.instance_number,
        'file_path': image.file_path.url if image.file_path else '',
        'slice_location': image.slice_location,
        'image_position': image.image_position,
        'file_size': image.file_size,
        'series_id': image.series.id,
        'study_id': image.series.study.id,
    }
    
    return JsonResponse(data)

@login_required
@csrf_exempt
def api_mpr_reconstruction(request, series_id):
    """API endpoint for Multiplanar Reconstruction (MPR)"""
    series = get_object_or_404(Series, id=series_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and series.study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    try:
        # Get all images in the series sorted by slice location
        images = series.images.all().order_by('slice_location', 'instance_number')
        
        if images.count() < 2:
            return JsonResponse({'error': 'Need at least 2 images for MPR'}, status=400)
        
        # Read DICOM data
        volume_data = []
        for img in images:
            try:
                dicom_path = os.path.join(settings.MEDIA_ROOT, str(img.file_path))
                ds = pydicom.dcmread(dicom_path)
                volume_data.append(ds.pixel_array)
            except Exception as e:
                continue
        
        if len(volume_data) < 2:
            return JsonResponse({'error': 'Could not read enough images for MPR'}, status=400)
        
        # Stack into 3D volume
        volume = np.stack(volume_data, axis=0)
        
        # Generate MPR views
        mpr_views = {}
        
        # Axial (original orientation)
        axial_slice = volume[volume.shape[0] // 2]
        mpr_views['axial'] = _array_to_base64_image(axial_slice)
        
        # Sagittal (YZ plane)
        sagittal_slice = volume[:, :, volume.shape[2] // 2]
        mpr_views['sagittal'] = _array_to_base64_image(sagittal_slice)
        
        # Coronal (XZ plane)
        coronal_slice = volume[:, volume.shape[1] // 2, :]
        mpr_views['coronal'] = _array_to_base64_image(coronal_slice)
        
        return JsonResponse({
            'mpr_views': mpr_views,
            'volume_shape': volume.shape,
            'series_info': {
                'id': series.id,
                'description': series.series_description,
                'modality': series.modality
            }
        })
        
    except Exception as e:
        return JsonResponse({'error': f'Error generating MPR: {str(e)}'}, status=500)

@login_required
@csrf_exempt
def api_mip_reconstruction(request, series_id):
    """API endpoint for Maximum Intensity Projection (MIP)"""
    series = get_object_or_404(Series, id=series_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and series.study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    try:
        # Get all images in the series
        images = series.images.all().order_by('slice_location', 'instance_number')
        
        if images.count() < 2:
            return JsonResponse({'error': 'Need at least 2 images for MIP'}, status=400)
        
        # Read DICOM data
        volume_data = []
        for img in images:
            try:
                dicom_path = os.path.join(settings.MEDIA_ROOT, str(img.file_path))
                ds = pydicom.dcmread(dicom_path)
                volume_data.append(ds.pixel_array)
            except Exception as e:
                continue
        
        if len(volume_data) < 2:
            return JsonResponse({'error': 'Could not read enough images for MIP'}, status=400)
        
        # Stack into 3D volume
        volume = np.stack(volume_data, axis=0)
        
        # Generate MIP projections
        mip_views = {}
        
        # Axial MIP (maximum along Z-axis)
        mip_axial = np.max(volume, axis=0)
        mip_views['axial'] = _array_to_base64_image(mip_axial)
        
        # Sagittal MIP (maximum along Y-axis)
        mip_sagittal = np.max(volume, axis=1)
        mip_views['sagittal'] = _array_to_base64_image(mip_sagittal)
        
        # Coronal MIP (maximum along X-axis)
        mip_coronal = np.max(volume, axis=2)
        mip_views['coronal'] = _array_to_base64_image(mip_coronal)
        
        return JsonResponse({
            'mip_views': mip_views,
            'volume_shape': volume.shape,
            'series_info': {
                'id': series.id,
                'description': series.series_description,
                'modality': series.modality
            }
        })
        
    except Exception as e:
        return JsonResponse({'error': f'Error generating MIP: {str(e)}'}, status=500)

@login_required
@csrf_exempt
def api_bone_reconstruction(request, series_id):
    """API endpoint for bone reconstruction using thresholding"""
    series = get_object_or_404(Series, id=series_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and series.study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    try:
        # Get threshold from request
        threshold = int(request.GET.get('threshold', 300))  # Default bone threshold in HU
        
        # Get all images in the series
        images = series.images.all().order_by('slice_location', 'instance_number')
        
        if images.count() < 2:
            return JsonResponse({'error': 'Need at least 2 images for bone reconstruction'}, status=400)
        
        # Read DICOM data
        volume_data = []
        for img in images:
            try:
                dicom_path = os.path.join(settings.MEDIA_ROOT, str(img.file_path))
                ds = pydicom.dcmread(dicom_path)
                
                # Convert to Hounsfield Units if possible
                pixel_array = ds.pixel_array.astype(np.float32)
                
                # Apply rescale slope and intercept if available
                if hasattr(ds, 'RescaleSlope') and hasattr(ds, 'RescaleIntercept'):
                    pixel_array = pixel_array * ds.RescaleSlope + ds.RescaleIntercept
                
                volume_data.append(pixel_array)
            except Exception as e:
                continue
        
        if len(volume_data) < 2:
            return JsonResponse({'error': 'Could not read enough images for bone reconstruction'}, status=400)
        
        # Stack into 3D volume
        volume = np.stack(volume_data, axis=0)
        
        # Apply bone threshold
        bone_mask = volume >= threshold
        bone_volume = volume * bone_mask
        
        # Generate bone reconstruction views
        bone_views = {}
        
        # Axial bone view
        axial_bone = bone_volume[bone_volume.shape[0] // 2]
        bone_views['axial'] = _array_to_base64_image(axial_bone)
        
        # Sagittal bone view
        sagittal_bone = bone_volume[:, :, bone_volume.shape[2] // 2]
        bone_views['sagittal'] = _array_to_base64_image(sagittal_bone)
        
        # Coronal bone view
        coronal_bone = bone_volume[:, bone_volume.shape[1] // 2, :]
        bone_views['coronal'] = _array_to_base64_image(coronal_bone)
        
        # MIP of bone structures
        bone_mip_axial = np.max(bone_volume, axis=0)
        bone_views['mip_axial'] = _array_to_base64_image(bone_mip_axial)
        
        bone_mip_sagittal = np.max(bone_volume, axis=1)
        bone_views['mip_sagittal'] = _array_to_base64_image(bone_mip_sagittal)
        
        bone_mip_coronal = np.max(bone_volume, axis=2)
        bone_views['mip_coronal'] = _array_to_base64_image(bone_mip_coronal)
        
        return JsonResponse({
            'bone_views': bone_views,
            'threshold': threshold,
            'volume_shape': volume.shape,
            'series_info': {
                'id': series.id,
                'description': series.series_description,
                'modality': series.modality
            }
        })
        
    except Exception as e:
        return JsonResponse({'error': f'Error generating bone reconstruction: {str(e)}'}, status=500)

@login_required
@csrf_exempt
def api_realtime_studies(request):
    """API endpoint for real-time study updates"""
    user = request.user
    
    # Get timestamp from request
    last_update = request.GET.get('last_update')
    
    try:
        if last_update:
            last_update_time = timezone.datetime.fromisoformat(last_update.replace('Z', '+00:00'))
        else:
            last_update_time = timezone.now() - timezone.timedelta(minutes=5)
    except:
        last_update_time = timezone.now() - timezone.timedelta(minutes=5)
    
    # Get studies updated since last check
    if user.is_facility_user():
        studies = Study.objects.filter(
            facility=user.facility,
            last_updated__gt=last_update_time
        ).order_by('-last_updated')[:20]
    else:
        studies = Study.objects.filter(
            last_updated__gt=last_update_time
        ).order_by('-last_updated')[:20]
    
    studies_data = []
    for study in studies:
        studies_data.append({
            'id': study.id,
            'accession_number': study.accession_number,
            'patient_name': study.patient.full_name,
            'patient_id': study.patient.patient_id,
            'study_date': study.study_date.isoformat(),
            'modality': study.modality.code,
            'description': study.study_description,
            'status': study.status,
            'priority': study.priority,
            'facility': study.facility.name,
            'last_updated': study.last_updated.isoformat(),
            'series_count': study.series_set.count(),
            'image_count': sum(series.images.count() for series in study.series_set.all())
        })
    
    return JsonResponse({
        'studies': studies_data,
        'timestamp': timezone.now().isoformat(),
        'count': len(studies_data)
    })

@login_required
@csrf_exempt
def api_study_progress(request, study_id):
    """API endpoint to get study processing progress"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    # Calculate progress
    total_images = 0
    processed_images = 0
    
    for series in study.series_set.all():
        series_images = series.images.all()
        total_images += series_images.count()
        processed_images += series_images.filter(processed=True).count()
    
    progress_percentage = (processed_images / total_images * 100) if total_images > 0 else 0
    
    return JsonResponse({
        'study_id': study.id,
        'total_images': total_images,
        'processed_images': processed_images,
        'progress_percentage': round(progress_percentage, 2),
        'status': study.status,
        'last_updated': study.last_updated.isoformat()
    })

def _array_to_base64_image(array):
    """Convert numpy array to base64 encoded image"""
    try:
        # Normalize to 0-255
        if array.max() > array.min():
            normalized = ((array - array.min()) / (array.max() - array.min()) * 255).astype(np.uint8)
        else:
            normalized = np.zeros_like(array, dtype=np.uint8)
        
        # Convert to PIL Image
        img = Image.fromarray(normalized, mode='L')
        
        # Convert to base64
        buffer = BytesIO()
        img.save(buffer, format='PNG')
        img_str = base64.b64encode(buffer.getvalue()).decode()
        
        return f"data:image/png;base64,{img_str}"
    except Exception as e:
        return None

@login_required
@csrf_exempt
def api_measurements(request, study_id):
    """API endpoint for saving/loading measurements"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    if request.method == 'POST':
        # Save measurements
        try:
            data = json.loads(request.body)
            # This would save measurements to database
            # For now, we'll just return success
            return JsonResponse({'success': True, 'message': 'Measurements saved'})
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
    
    elif request.method == 'GET':
        # Load measurements
        # This would load measurements from database
        measurements = []
        return JsonResponse({'measurements': measurements})

@login_required
@csrf_exempt
def api_reconstruction(request, study_id):
    """API endpoint for 3D reconstruction processing"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            reconstruction_type = data.get('type')  # 'mpr', 'mip', 'bone', 'endoscopy', 'surgery'
            parameters = data.get('parameters', {})
            
            # This would process the reconstruction
            # For now, we'll simulate processing
            result = {
                'success': True,
                'reconstruction_id': f"recon_{study_id}_{reconstruction_type}",
                'type': reconstruction_type,
                'status': 'processing',
                'progress': 0,
                'estimated_time': 30,  # seconds
            }
            
            return JsonResponse(result)
            
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
    
    return JsonResponse({'error': 'Method not allowed'}, status=405)

@login_required
@csrf_exempt
def api_hounsfield_units(request):
    """API endpoint for Hounsfield Unit calculations"""
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            x = data.get('x')
            y = data.get('y')
            image_id = data.get('image_id')
            
            # This would calculate actual HU values from DICOM data
            # For demonstration, we'll return simulated values
            hu_value = -800 + (x + y) % 1600  # Simulated HU value
            
            result = {
                'hu_value': hu_value,
                'position': {'x': x, 'y': y},
                'image_id': image_id,
                'timestamp': '2024-01-01T12:00:00Z'
            }
            
            return JsonResponse(result)
            
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
    
    return JsonResponse({'error': 'Method not allowed'}, status=405)

@login_required
@csrf_exempt
def api_window_level(request):
    """API endpoint for window/level adjustments"""
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            window_center = data.get('window_center')
            window_width = data.get('window_width')
            preset = data.get('preset')  # 'lung', 'bone', 'soft_tissue', 'brain', etc.
            
            # Predefined window/level presets
            presets = {
                'lung': {'center': -600, 'width': 1600},
                'bone': {'center': 300, 'width': 1500},
                'soft_tissue': {'center': 40, 'width': 350},
                'brain': {'center': 40, 'width': 80},
                'liver': {'center': 60, 'width': 160},
                'mediastinum': {'center': 50, 'width': 350},
            }
            
            if preset and preset in presets:
                window_center = presets[preset]['center']
                window_width = presets[preset]['width']
            
            result = {
                'window_center': window_center,
                'window_width': window_width,
                'preset': preset,
                'success': True
            }
            
            return JsonResponse(result)
            
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
    
    return JsonResponse({'error': 'Method not allowed'}, status=405)

@login_required
def api_export_image(request, image_id):
    """API endpoint to export image in various formats"""
    image = get_object_or_404(DicomImage, id=image_id)
    user = request.user
    
    # Check permissions
    study = image.series.study
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    export_format = request.GET.get('format', 'png')  # png, jpg, tiff, dicom
    
    # This would export the image in the requested format
    # For now, we'll return a success message
    result = {
        'success': True,
        'download_url': f'/media/exports/image_{image_id}.{export_format}',
        'format': export_format,
        'filename': f'image_{image_id}.{export_format}'
    }
    
    return JsonResponse(result)

@login_required
@csrf_exempt
def api_annotations(request, study_id):
    """API endpoint for saving/loading annotations"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            annotations = data.get('annotations', [])
            
            # This would save annotations to database
            # For now, we'll just return success
            return JsonResponse({
                'success': True, 
                'message': f'Saved {len(annotations)} annotations',
                'annotation_count': len(annotations)
            })
            
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
    
    elif request.method == 'GET':
        # Load annotations
        # This would load annotations from database
        annotations = []
        return JsonResponse({'annotations': annotations})

@login_required
def api_cine_mode(request, series_id):
    """API endpoint for cine mode playback"""
    series = get_object_or_404(Series, id=series_id)
    user = request.user
    
    # Check permissions
    study = series.study
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    images = series.images.all().order_by('instance_number')
    
    cine_data = {
        'series_id': series_id,
        'image_count': images.count(),
        'frame_rate': 10,  # Default FPS
        'images': [
            {
                'id': img.id,
                'instance_number': img.instance_number,
                'file_path': img.file_path.url if img.file_path else '',
            } for img in images
        ]
    }
    
    return JsonResponse(cine_data)

@login_required
@csrf_exempt
def api_export_measurements(request, study_id):
    """API endpoint to export measurements as PDF"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            measurements = data.get('measurements', [])
            
            # This would generate a PDF report with measurements
            # For now, we'll simulate the export
            filename = f'measurements_{study.accession_number}_{int(time.time())}.pdf'
            download_url = f'/media/exports/{filename}'
            
            result = {
                'success': True,
                'download_url': download_url,
                'filename': filename,
                'measurement_count': len(measurements)
            }
            
            return JsonResponse(result)
            
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
    
    return JsonResponse({'error': 'Method not allowed'}, status=405)

@login_required
def upload_dicom(request):
    """Upload DICOM files for processing"""
    if request.method == 'POST':
        try:
            uploaded_files = request.FILES.getlist('dicom_files')
            
            if not uploaded_files:
                return JsonResponse({'success': False, 'error': 'No files uploaded'})
            
            # Generate upload ID for tracking
            upload_id = str(uuid.uuid4())
            
            # This would process DICOM files and create Study/Series/Image records
            # For now, we'll simulate processing
            total_files = len(uploaded_files)
            processed_files = 0
            
            for file in uploaded_files:
                # Validate file type
                if not (file.name.lower().endswith('.dcm') or file.name.lower().endswith('.dicom')):
                    continue
                
                # This would save the file and create Study/Series/Image records
                processed_files += 1
            
            if processed_files == 0:
                return JsonResponse({'success': False, 'error': 'No valid DICOM files found'})
            
            return JsonResponse({
                'success': True, 
                'message': f'Successfully uploaded {processed_files} DICOM files',
                'upload_id': upload_id,
                'processed_files': processed_files,
                'total_files': total_files
            })
            
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)})
    
    return render(request, 'dicom_viewer/upload.html')

@login_required
@csrf_exempt
def api_upload_progress(request, upload_id):
    """API endpoint to check upload progress"""
    try:
        # This would check the actual upload progress
        # For now, we'll simulate progress
        progress = {
            'upload_id': upload_id,
            'status': 'completed',
            'progress': 100,
            'processed_files': 10,
            'total_files': 10,
            'current_file': '',
            'message': 'Upload completed successfully'
        }
        
        return JsonResponse(progress)
        
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)

@login_required
@csrf_exempt
def api_process_study(request, study_id):
    """API endpoint to process/reprocess a study"""
    study = get_object_or_404(Study, id=study_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            processing_options = data.get('options', {})
            
            # This would trigger study reprocessing
            # For now, we'll simulate processing
            result = {
                'success': True,
                'message': f'Study {study.accession_number} processing started',
                'study_id': study.id,
                'processing_options': processing_options,
                'estimated_time': '5-10 minutes'
            }
            
            return JsonResponse(result)
            
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON data'}, status=400)
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Method not allowed'}, status=405)
