#!/usr/bin/env python3
"""
DICOM Receiver Service
Handles incoming DICOM images from remote imaging modalities
"""

import os
import sys
import logging
import threading
import time
from datetime import datetime
from pathlib import Path

# Add Django project to path
sys.path.append('/workspace')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'noctis_pro.settings')

import django
django.setup()

from pynetdicom import AE, evt, AllStoragePresentationContexts, VerificationPresentationContexts
from pynetdicom.sop_class import Verification
from pydicom import dcmread
from pydicom.errors import InvalidDicomError

from worklist.models import Patient, Study, Series, DicomImage, Modality, Facility
from accounts.models import User
from django.utils import timezone
from django.db import transaction

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/workspace/dicom_receiver.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('dicom_receiver')

class DicomReceiver:
    """DICOM SCP (Service Class Provider) for receiving DICOM images"""
    
    def __init__(self, port=11112, aet='NOCTIS_SCP'):
        self.port = port
        self.aet = aet
        self.ae = AE(ae_title=aet)
        
        # Add supported presentation contexts
        self.ae.supported_contexts = AllStoragePresentationContexts
        self.ae.supported_contexts.extend(VerificationPresentationContexts)
        
        # Storage directory
        self.storage_dir = Path('/workspace/media/dicom/received')
        self.storage_dir.mkdir(parents=True, exist_ok=True)
        
        # Event handlers
        self.ae.on_c_store = self.handle_store
        self.ae.on_c_echo = self.handle_echo
        
        logger.info(f"DICOM Receiver initialized - AET: {aet}, Port: {port}")
    
    def handle_echo(self, event):
        """Handle C-ECHO requests (DICOM ping)"""
        logger.info(f"Received C-ECHO from {event.assoc.requestor.ae_title}")
        return 0x0000  # Success
    
    def handle_store(self, event):
        """Handle C-STORE requests (DICOM image storage)"""
        try:
            # Get the dataset
            ds = event.dataset
            
            # Log the incoming study
            logger.info(f"Receiving DICOM object: "
                       f"Study UID: {getattr(ds, 'StudyInstanceUID', 'Unknown')}, "
                       f"Series UID: {getattr(ds, 'SeriesInstanceUID', 'Unknown')}, "
                       f"SOP Instance UID: {getattr(ds, 'SOPInstanceUID', 'Unknown')}")
            
            # Process the DICOM object
            with transaction.atomic():
                result = self.process_dicom_object(ds, event)
                
            if result:
                logger.info("DICOM object stored successfully")
                return 0x0000  # Success
            else:
                logger.error("Failed to store DICOM object")
                return 0xA700  # Out of Resources
                
        except Exception as e:
            logger.error(f"Error handling C-STORE: {str(e)}")
            return 0xA700  # Out of Resources
    
    def process_dicom_object(self, ds, event):
        """Process and store the DICOM object"""
        try:
            # Extract DICOM metadata
            study_uid = getattr(ds, 'StudyInstanceUID', None)
            series_uid = getattr(ds, 'SeriesInstanceUID', None)
            sop_instance_uid = getattr(ds, 'SOPInstanceUID', None)
            
            if not all([study_uid, series_uid, sop_instance_uid]):
                logger.error("Missing required DICOM UIDs")
                return False
            
            # Extract patient information
            patient_id = getattr(ds, 'PatientID', 'UNKNOWN')
            patient_name = str(getattr(ds, 'PatientName', 'UNKNOWN')).replace('^', ' ')
            patient_birth_date = getattr(ds, 'PatientBirthDate', None)
            patient_sex = getattr(ds, 'PatientSex', 'O')
            
            # Parse patient name
            name_parts = patient_name.split(' ', 1)
            first_name = name_parts[0] if name_parts else 'Unknown'
            last_name = name_parts[1] if len(name_parts) > 1 else ''
            
            # Parse birth date
            birth_date = None
            if patient_birth_date:
                try:
                    birth_date = datetime.strptime(patient_birth_date, '%Y%m%d').date()
                except ValueError:
                    birth_date = timezone.now().date()
            else:
                birth_date = timezone.now().date()
            
            # Get or create patient
            patient, created = Patient.objects.get_or_create(
                patient_id=patient_id,
                defaults={
                    'first_name': first_name,
                    'last_name': last_name,
                    'date_of_birth': birth_date,
                    'gender': patient_sex if patient_sex in ['M', 'F'] else 'O'
                }
            )
            
            if created:
                logger.info(f"Created new patient: {patient}")
            
            # Extract study information
            study_date = getattr(ds, 'StudyDate', None)
            study_time = getattr(ds, 'StudyTime', '000000')
            study_description = getattr(ds, 'StudyDescription', 'DICOM Study')
            referring_physician = str(getattr(ds, 'ReferringPhysicianName', 'UNKNOWN')).replace('^', ' ')
            modality_code = getattr(ds, 'Modality', 'OT')
            accession_number = getattr(ds, 'AccessionNumber', f"ACC_{int(time.time())}")
            
            # Parse study datetime
            if study_date:
                try:
                    study_datetime = datetime.strptime(f"{study_date}{study_time[:6]}", '%Y%m%d%H%M%S')
                    study_datetime = timezone.make_aware(study_datetime)
                except ValueError:
                    study_datetime = timezone.now()
            else:
                study_datetime = timezone.now()
            
            # Get or create modality
            modality, _ = Modality.objects.get_or_create(
                code=modality_code,
                defaults={'name': modality_code, 'description': f'{modality_code} Modality'}
            )
            
            # Use default facility for received studies
            default_facility = Facility.objects.filter(is_active=True).first()
            if not default_facility:
                logger.error("No active facility found for storing DICOM study")
                return False
            
            # Get or create study
            study, created = Study.objects.get_or_create(
                study_instance_uid=study_uid,
                defaults={
                    'accession_number': accession_number,
                    'patient': patient,
                    'facility': default_facility,
                    'modality': modality,
                    'study_description': study_description,
                    'study_date': study_datetime,
                    'referring_physician': referring_physician,
                    'status': 'completed',
                    'priority': 'normal'
                }
            )
            
            if created:
                logger.info(f"Created new study: {study}")
            
            # Extract series information
            series_number = getattr(ds, 'SeriesNumber', 1)
            series_description = getattr(ds, 'SeriesDescription', f'Series {series_number}')
            slice_thickness = getattr(ds, 'SliceThickness', None)
            pixel_spacing = str(getattr(ds, 'PixelSpacing', ''))
            image_orientation = str(getattr(ds, 'ImageOrientationPatient', ''))
            
            # Get or create series
            series, created = Series.objects.get_or_create(
                series_instance_uid=series_uid,
                defaults={
                    'study': study,
                    'series_number': series_number,
                    'series_description': series_description,
                    'modality': modality_code,
                    'slice_thickness': slice_thickness,
                    'pixel_spacing': pixel_spacing,
                    'image_orientation': image_orientation
                }
            )
            
            if created:
                logger.info(f"Created new series: {series}")
            
            # Extract image information
            instance_number = getattr(ds, 'InstanceNumber', 1)
            image_position = str(getattr(ds, 'ImagePositionPatient', ''))
            slice_location = getattr(ds, 'SliceLocation', None)
            
            # Create file path
            file_dir = self.storage_dir / study_uid / series_uid
            file_dir.mkdir(parents=True, exist_ok=True)
            file_path = file_dir / f"{sop_instance_uid}.dcm"
            
            # Save DICOM file
            ds.save_as(file_path, write_like_original=False)
            file_size = file_path.stat().st_size
            
            # Create relative path for database storage
            relative_path = str(file_path.relative_to(Path('/workspace/media')))
            
            # Create DICOM image record
            dicom_image, created = DicomImage.objects.get_or_create(
                sop_instance_uid=sop_instance_uid,
                defaults={
                    'series': series,
                    'instance_number': instance_number,
                    'image_position': image_position,
                    'slice_location': slice_location,
                    'file_path': relative_path,
                    'file_size': file_size,
                    'processed': False
                }
            )
            
            if created:
                logger.info(f"Created new DICOM image: {dicom_image}")
            else:
                logger.info(f"DICOM image already exists: {dicom_image}")
            
            return True
            
        except Exception as e:
            logger.error(f"Error processing DICOM object: {str(e)}")
            return False
    
    def start(self):
        """Start the DICOM receiver service"""
        logger.info(f"Starting DICOM receiver on port {self.port}")
        try:
            self.ae.start_server(('', self.port), block=True)
        except KeyboardInterrupt:
            logger.info("DICOM receiver stopped by user")
        except Exception as e:
            logger.error(f"Error starting DICOM receiver: {str(e)}")
    
    def stop(self):
        """Stop the DICOM receiver service"""
        logger.info("Stopping DICOM receiver")
        self.ae.shutdown()

def main():
    """Main function to run the DICOM receiver"""
    import argparse
    
    parser = argparse.ArgumentParser(description='DICOM Receiver Service')
    parser.add_argument('--port', type=int, default=11112, help='Port to listen on (default: 11112)')
    parser.add_argument('--aet', default='NOCTIS_SCP', help='Application Entity Title (default: NOCTIS_SCP)')
    
    args = parser.parse_args()
    
    receiver = DicomReceiver(port=args.port, aet=args.aet)
    
    try:
        receiver.start()
    except KeyboardInterrupt:
        receiver.stop()
        logger.info("DICOM receiver service stopped")

if __name__ == '__main__':
    main()