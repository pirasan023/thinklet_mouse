"""Small filesystem transaction used by the installer and tested without /Applications."""
import os
from pathlib import Path

def replace_app(staging: Path, destination: Path, previous: Path):
    if previous.exists():
        raise FileExistsError(previous)
    moved_old = False
    if destination.exists():
        os.rename(destination, previous)
        moved_old = True
    try:
        os.rename(staging, destination)
    except OSError:
        if moved_old:
            os.rename(previous, destination)
        raise
    return previous if moved_old else None
