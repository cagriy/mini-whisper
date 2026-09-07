import sys
from pathlib import Path

# The script under test lives one level up and is not an installed package.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
