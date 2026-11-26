"""Write optional public Roomle build defines without shell interpolation."""
import json
import os
from pathlib import Path


def main():
    configurator = os.environ.get("ROOMLE_CONFIGURATOR_ID", "").strip()
    tag = os.environ.get("ROOMLE_CATALOG_ROOT_TAG", "").strip()
    raw = os.environ.get("ROOMLE_PRODUCT_IDS", "").strip() or "{}"
    try:
        products = json.loads(raw)
    except json.JSONDecodeError:
        raise SystemExit("ROOMLE_PRODUCT_IDS must be a JSON object") from None
    if not isinstance(products, dict) or any(
        not isinstance(k, str) or not k.strip()
        or not isinstance(v, str) or not v.strip()
        for k, v in products.items()
    ):
        raise SystemExit("ROOMLE_PRODUCT_IDS requires nonempty SKU and item strings")
    if (tag or products) and not configurator:
        raise SystemExit("Roomle catalogue/product configuration requires ROOMLE_CONFIGURATOR_ID")
    target = Path("build/roomle-defines.json")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({
        "ROOMLE_CONFIGURATOR_ID": configurator,
        "ROOMLE_CATALOG_ROOT_TAG": tag,
        "ROOMLE_PRODUCT_IDS": json.dumps(products, ensure_ascii=False),
    }, ensure_ascii=False), encoding="utf-8")
    print("Roomle public build configuration prepared")


if __name__ == "__main__":
    main()
