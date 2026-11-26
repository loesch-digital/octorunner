"""Stage the static Pages site with the shared dashboard screenshot."""

from pathlib import Path
import shutil
import sys


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    output = Path(sys.argv[1])
    shutil.copytree(root / "website", output)
    shutil.copyfile(root / "docs/assets/app-screens/dashboard.png", output / "assets/dashboard.png")
