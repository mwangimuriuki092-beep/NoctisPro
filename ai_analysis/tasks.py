from celery import shared_task
from django.utils import timezone
from .models import AIAnalysis
from .views import simulate_ai_analysis

@shared_task
def run_ai_analysis_task(analysis_id: int):
    try:
        analysis = AIAnalysis.objects.get(id=analysis_id)
        analysis.start_processing()
        results = simulate_ai_analysis(analysis)
        analysis.complete_analysis(results)
        model = analysis.ai_model
        model.total_analyses += 1
        if analysis.processing_time:
            if model.avg_processing_time > 0:
                model.avg_processing_time = (model.avg_processing_time + analysis.processing_time) / 2
            else:
                model.avg_processing_time = analysis.processing_time
        model.save()
        return {'success': True, 'analysis_id': analysis_id}
    except Exception as e:
        try:
            analysis = AIAnalysis.objects.get(id=analysis_id)
            analysis.status = 'failed'
            analysis.error_message = str(e)
            analysis.save()
        except Exception:
            pass
        return {'success': False, 'error': str(e)}

