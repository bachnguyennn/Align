import sys
from pathlib import Path

# Make `align_reference` importable regardless of where pytest is started from.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
