#!/usr/bin/env python3
"""
Attachment Viewer
A comprehensive viewer for study attachments including DICOM studies, 
PDFs, Word documents, and images
"""

import os
import sys
import json
import mimetypes
import tempfile
import subprocess
from pathlib import Path

# Add Django project to path
sys.path.append('/workspace')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'noctis_pro.settings')

import django
django.setup()

from django.shortcuts import get_object_or_404
from django.http import JsonResponse, HttpResponse, FileResponse
from django.contrib.auth.decorators import login_required
from django.views.decorators.csrf import csrf_exempt
from django.template.response import TemplateResponse
from django.conf import settings

from worklist.models import StudyAttachment
from dicom_viewer.views import view_study
import pydicom
from PIL import Image
import fitz  # PyMuPDF for PDF handling
import docx  # python-docx for Word documents
from io import BytesIO
import base64

class AttachmentViewer:
    """Unified attachment viewer for different file types"""
    
    def __init__(self):
        self.supported_types = {
            'pdf_document': self.view_pdf,
            'word_document': self.view_word,
            'dicom_study': self.view_dicom,
            'image': self.view_image,
            'document': self.view_text,
            'previous_study': self.view_previous_study,
        }
    
    def can_view(self, attachment):
        """Check if attachment can be viewed"""
        return attachment.file_type in self.supported_types
    
    def view_attachment(self, attachment, page=1, options=None):
        """Main method to view attachment based on type"""
        if not self.can_view(attachment):
            return {
                'error': f'Unsupported file type: {attachment.file_type}',
                'download_url': attachment.file.url
            }
        
        viewer_func = self.supported_types[attachment.file_type]
        return viewer_func(attachment, page, options or {})
    
    def view_pdf(self, attachment, page=1, options=None):
        """View PDF documents"""
        try:
            pdf_path = attachment.file.path
            pdf_doc = fitz.open(pdf_path)
            
            total_pages = len(pdf_doc)
            if page > total_pages:
                page = total_pages
            if page < 1:
                page = 1
            
            # Get page
            pdf_page = pdf_doc[page - 1]
            
            # Convert to image
            zoom = options.get('zoom', 1.0)
            mat = fitz.Matrix(zoom, zoom)
            pix = pdf_page.get_pixmap(matrix=mat)
            img_data = pix.tobytes("png")
            
            # Convert to base64
            img_base64 = base64.b64encode(img_data).decode()
            
            # Extract text for search
            page_text = pdf_page.get_text()
            
            # Get page info
            page_info = {
                'width': pix.width,
                'height': pix.height,
                'rotation': pdf_page.rotation
            }
            
            pdf_doc.close()
            
            return {
                'type': 'pdf',
                'page': page,
                'total_pages': total_pages,
                'image_data': f"data:image/png;base64,{img_base64}",
                'text_content': page_text,
                'page_info': page_info,
                'zoom': zoom,
                'file_name': attachment.name,
                'file_size': attachment.file_size
            }
            
        except Exception as e:
            return {'error': f'Error viewing PDF: {str(e)}'}
    
    def view_word(self, attachment, page=1, options=None):
        """View Word documents"""
        try:
            doc_path = attachment.file.path
            doc = docx.Document(doc_path)
            
            # Extract all text content
            full_text = []
            for paragraph in doc.paragraphs:
                full_text.append(paragraph.text)
            
            # Extract tables
            tables_content = []
            for table in doc.tables:
                table_data = []
                for row in table.rows:
                    row_data = []
                    for cell in row.cells:
                        row_data.append(cell.text)
                    table_data.append(row_data)
                tables_content.append(table_data)
            
            # Get document properties
            props = doc.core_properties
            metadata = {
                'title': props.title or '',
                'author': props.author or '',
                'subject': props.subject or '',
                'created': props.created.isoformat() if props.created else '',
                'modified': props.modified.isoformat() if props.modified else '',
            }
            
            return {
                'type': 'word',
                'content': '\n'.join(full_text),
                'tables': tables_content,
                'metadata': metadata,
                'paragraph_count': len(doc.paragraphs),
                'table_count': len(doc.tables),
                'file_name': attachment.name,
                'file_size': attachment.file_size
            }
            
        except Exception as e:
            return {'error': f'Error viewing Word document: {str(e)}'}
    
    def view_dicom(self, attachment, page=1, options=None):
        """View DICOM files"""
        try:
            if attachment.attached_study:
                # If linked to a study, redirect to DICOM viewer
                return {
                    'type': 'dicom_redirect',
                    'study_id': attachment.attached_study.id,
                    'redirect_url': f'/dicom-viewer/study/{attachment.attached_study.id}/'
                }
            
            # Handle standalone DICOM file
            dicom_path = attachment.file.path
            ds = pydicom.dcmread(dicom_path)
            
            # Extract DICOM metadata
            metadata = {}
            for elem in ds:
                if elem.tag.group < 0x7FE0:  # Skip pixel data
                    metadata[str(elem.tag)] = {
                        'name': elem.name,
                        'value': str(elem.value)
                    }
            
            # Convert pixel data to image if available
            image_data = None
            if hasattr(ds, 'pixel_array'):
                pixel_array = ds.pixel_array
                
                # Normalize to 0-255
                if pixel_array.max() > pixel_array.min():
                    normalized = ((pixel_array - pixel_array.min()) / 
                                (pixel_array.max() - pixel_array.min()) * 255).astype('uint8')
                else:
                    normalized = pixel_array.astype('uint8')
                
                # Convert to PIL Image
                image = Image.fromarray(normalized, mode='L')
                
                # Convert to base64
                buffer = BytesIO()
                image.save(buffer, format='PNG')
                img_base64 = base64.b64encode(buffer.getvalue()).decode()
                image_data = f"data:image/png;base64,{img_base64}"
            
            return {
                'type': 'dicom',
                'metadata': metadata,
                'image_data': image_data,
                'patient_name': str(getattr(ds, 'PatientName', 'Unknown')),
                'study_date': getattr(ds, 'StudyDate', ''),
                'modality': getattr(ds, 'Modality', ''),
                'study_description': getattr(ds, 'StudyDescription', ''),
                'file_name': attachment.name,
                'file_size': attachment.file_size
            }
            
        except Exception as e:
            return {'error': f'Error viewing DICOM: {str(e)}'}
    
    def view_image(self, attachment, page=1, options=None):
        """View image files"""
        try:
            image_path = attachment.file.path
            
            # Open image
            image = Image.open(image_path)
            
            # Get image info
            info = {
                'format': image.format,
                'mode': image.mode,
                'size': image.size,
                'has_transparency': image.mode in ('RGBA', 'LA') or 'transparency' in image.info
            }
            
            # Apply options
            zoom = options.get('zoom', 1.0)
            if zoom != 1.0:
                new_size = (int(image.size[0] * zoom), int(image.size[1] * zoom))
                image = image.resize(new_size, Image.Resampling.LANCZOS)
            
            # Convert to base64
            buffer = BytesIO()
            format_to_save = 'PNG' if image.mode in ('RGBA', 'LA') else 'JPEG'
            image.save(buffer, format=format_to_save)
            img_base64 = base64.b64encode(buffer.getvalue()).decode()
            
            return {
                'type': 'image',
                'image_data': f"data:image/{format_to_save.lower()};base64,{img_base64}",
                'info': info,
                'zoom': zoom,
                'file_name': attachment.name,
                'file_size': attachment.file_size
            }
            
        except Exception as e:
            return {'error': f'Error viewing image: {str(e)}'}
    
    def view_text(self, attachment, page=1, options=None):
        """View text documents"""
        try:
            with open(attachment.file.path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
            
            # Basic text statistics
            lines = content.split('\n')
            words = content.split()
            
            return {
                'type': 'text',
                'content': content,
                'line_count': len(lines),
                'word_count': len(words),
                'char_count': len(content),
                'file_name': attachment.name,
                'file_size': attachment.file_size
            }
            
        except Exception as e:
            return {'error': f'Error viewing text: {str(e)}'}
    
    def view_previous_study(self, attachment, page=1, options=None):
        """View previous study attachment"""
        if attachment.attached_study:
            return {
                'type': 'study_redirect',
                'study_id': attachment.attached_study.id,
                'redirect_url': f'/worklist/study/{attachment.attached_study.id}/',
                'study_info': {
                    'accession_number': attachment.attached_study.accession_number,
                    'patient_name': attachment.attached_study.patient.full_name,
                    'study_date': attachment.attached_study.study_date.isoformat(),
                    'modality': attachment.attached_study.modality.code,
                    'description': attachment.attached_study.study_description
                }
            }
        else:
            return {'error': 'No linked study found'}

# Django views for attachment viewer
@login_required
@csrf_exempt
def api_view_attachment(request, attachment_id):
    """API endpoint to view attachment"""
    attachment = get_object_or_404(StudyAttachment, id=attachment_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and attachment.study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    # Check role-based permissions
    if not attachment.is_public and attachment.allowed_roles:
        if user.role not in attachment.allowed_roles:
            return JsonResponse({'error': 'Insufficient permissions'}, status=403)
    
    # Get viewing options from request
    page = int(request.GET.get('page', 1))
    zoom = float(request.GET.get('zoom', 1.0))
    options = {
        'zoom': zoom,
        'page': page
    }
    
    # Initialize viewer and view attachment
    viewer = AttachmentViewer()
    result = viewer.view_attachment(attachment, page, options)
    
    # Track access
    attachment.increment_access_count()
    
    return JsonResponse(result)

@login_required
def attachment_viewer_page(request, attachment_id):
    """Full page attachment viewer"""
    attachment = get_object_or_404(StudyAttachment, id=attachment_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and attachment.study.facility != user.facility:
        return HttpResponse('Permission denied', status=403)
    
    # Check role-based permissions
    if not attachment.is_public and attachment.allowed_roles:
        if user.role not in attachment.allowed_roles:
            return HttpResponse('Insufficient permissions', status=403)
    
    context = {
        'attachment': attachment,
        'study': attachment.study,
        'user': user,
    }
    
    return TemplateResponse(request, 'attachment_viewer/viewer.html', context)

@login_required
@csrf_exempt
def api_attachment_search(request, attachment_id):
    """Search within attachment content"""
    attachment = get_object_or_404(StudyAttachment, id=attachment_id)
    user = request.user
    
    # Check permissions
    if user.is_facility_user() and attachment.study.facility != user.facility:
        return JsonResponse({'error': 'Permission denied'}, status=403)
    
    query = request.GET.get('q', '').strip()
    if not query:
        return JsonResponse({'results': []})
    
    viewer = AttachmentViewer()
    
    # Get content based on file type
    if attachment.file_type == 'pdf_document':
        try:
            pdf_doc = fitz.open(attachment.file.path)
            results = []
            
            for page_num in range(len(pdf_doc)):
                page = pdf_doc[page_num]
                text = page.get_text()
                
                # Simple text search (can be enhanced with regex, highlighting, etc.)
                if query.lower() in text.lower():
                    # Find context around matches
                    lines = text.split('\n')
                    for i, line in enumerate(lines):
                        if query.lower() in line.lower():
                            context_start = max(0, i - 2)
                            context_end = min(len(lines), i + 3)
                            context = '\n'.join(lines[context_start:context_end])
                            
                            results.append({
                                'page': page_num + 1,
                                'line': i + 1,
                                'context': context,
                                'match_line': line
                            })
            
            pdf_doc.close()
            return JsonResponse({'results': results})
            
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=500)
    
    elif attachment.file_type == 'word_document':
        try:
            doc = docx.Document(attachment.file.path)
            results = []
            
            for para_idx, paragraph in enumerate(doc.paragraphs):
                if query.lower() in paragraph.text.lower():
                    results.append({
                        'paragraph': para_idx + 1,
                        'text': paragraph.text,
                        'type': 'paragraph'
                    })
            
            return JsonResponse({'results': results})
            
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=500)
    
    else:
        return JsonResponse({'error': 'Search not supported for this file type'})

if __name__ == '__main__':
    # For standalone testing
    viewer = AttachmentViewer()
    print("Attachment Viewer initialized")
    print(f"Supported types: {list(viewer.supported_types.keys())}")