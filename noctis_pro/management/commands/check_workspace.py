from django.core.management.base import BaseCommand
from noctis_pro.workspace_detector import print_workspace_report

class Command(BaseCommand):
    help = 'Display workspace detection report'

    def handle(self, *args, **options):
        print_workspace_report()