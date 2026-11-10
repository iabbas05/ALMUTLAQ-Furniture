"""Optional offline copies of the two company-provided demo product photos."""
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
photos = {
    "london-sofa.jpg": "https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-1.jpg",
    "london-chair.jpg": "https://thefactoryfurniture.com/wp-content/uploads/2026/11/06-14-00005-1.jpg",
}
results = []
for name, url in photos.items():
    target = ROOT / "assets" / name
    try:
        with urlopen(Request(url, headers={"User-Agent":"AlmutlaqDemo/0.8"}), timeout=20) as response:
            if not response.headers.get_content_type().startswith("image/"):
                raise ValueError("Expected an image")
            data = response.read(5*1024*1024+1)
            if not 100 <= len(data) <= 5*1024*1024:
                raise ValueError("Unexpected image size")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        results.append(dict(file=name, copied=True, source=url))
    except Exception as error:
        results.append(dict(file=name, copied=False, source=url, error=type(error).__name__))
print(json.dumps(results, indent=2))
(ROOT / "photo-fetch-status.json").write_text(json.dumps(results), encoding="utf-8")
