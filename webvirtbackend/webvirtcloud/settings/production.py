"""
Django production settings for WebVirtCloud project.

"""

from .base import *

# Django settings
DEBUG = False

try:
    from .local import *
except ImportError:
    pass
