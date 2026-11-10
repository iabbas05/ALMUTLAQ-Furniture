"""Version 2 room contract, metres, X right, Z down the plan, yaw clockwise."""
import copy
import math

class ValidationError(ValueError):
    pass

def number(value, low, high, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError(f"Invalid {label}")
    if not math.isfinite(value) or not low <= value <= high:
        raise ValidationError(f"Invalid {label}")
    return float(value)

def validate_room(data, products):
    if not isinstance(data, dict) or data.get("schemaVersion") != 2 or data.get("unit") != "m":
        raise ValidationError("Expected schemaVersion 2 and unit m")
    room = data.get("room")
    if not isinstance(room, dict):
        raise ValidationError("Missing room")
    w = number(room.get("width"), 1, 25, "room width")
    d = number(room.get("depth"), 1, 25, "room depth")
    h = number(room.get("height"), 2, 10, "room height")
    openings, items = data.get("openings"), data.get("items")
    if not isinstance(openings, list) or len(openings) > 32:
        raise ValidationError("Expected up to 32 openings")
    if not isinstance(items, list) or len(items) > 50:
        raise ValidationError("Expected up to 50 items")
    clean_cuts = []
    for row in openings:
        if not isinstance(row, dict):
            raise ValidationError("Invalid opening")
        wall, kind = row.get("wall"), row.get("kind")
        if wall not in ("top", "right", "bottom", "left") or kind not in ("window", "door"):
            raise ValidationError("Invalid wall or opening type")
        span = w if wall in ("top", "bottom") else d
        offset = number(row.get("offset"), 0, span, "opening offset")
        width = number(row.get("width"), .1, span, "opening width")
        sill = number(row.get("sill"), 0, h, "sill")
        height = number(row.get("height"), .1, h, "opening height")
        if offset + width > span + 1e-6 or sill + height > h + 1e-6:
            raise ValidationError("Opening crosses the wall")
        if kind == "door" and sill != 0:
            raise ValidationError("A door starts at floor level")
        if type(row.get("reverse")) is not bool:
            raise ValidationError("Invalid door hinge")
        if any(o["wall"] == wall and offset < o["offset"] + o["width"] - 1e-6
               and o["offset"] < offset + width - 1e-6 for o in clean_cuts):
            raise ValidationError("Openings overlap")
        clean_cuts.append(dict(wall=wall, kind=kind, offset=offset, width=width,
                               sill=sill, height=height, reverse=row["reverse"]))
    clean_items, seen = [], set()
    for row in items:
        if not isinstance(row, dict):
            raise ValidationError("Invalid item")
        instance = row.get("instanceId")
        if not isinstance(instance, str) or not 1 <= len(instance) <= 80 or instance in seen:
            raise ValidationError("Invalid or repeated instance ID")
        seen.add(instance)
        key = row.get("productId")
        product = products.get(key) if isinstance(key, str) else None
        if not product or product.get("status") != "published":
            raise ValidationError("The product needs a published model")
        pos = row.get("position")
        if not isinstance(pos, dict):
            raise ValidationError("Missing position")
        x = number(pos.get("x"), 0, w, "item X")
        z = number(pos.get("z"), 0, d, "item Z")
        yaw = number(row.get("rotationY"), -36000, 36000, "item yaw") % 360
        dims = product["dimensions"]
        pw, pd, ph = dims["width"], dims["depth"], dims["height"]
        theta = math.radians(yaw)
        ex = (abs(math.cos(theta)) * pw + abs(math.sin(theta)) * pd) / 2
        ez = (abs(math.sin(theta)) * pw + abs(math.cos(theta)) * pd) / 2
        if x - ex < -1e-6 or x + ex > w + 1e-6 or z - ez < -1e-6 or z + ez > d + 1e-6 or ph > h:
            raise ValidationError("The whole item must fit inside the room")
        version = row.get("modelVersion") or product["modelVersion"]
        if version not in product.get("versions", {product["modelVersion"]: {}}):
            raise ValidationError("Unknown model version")
        clean_items.append(dict(instanceId=instance, productId=key, position=dict(x=x, z=z),
                                rotationY=yaw, modelVersion=version))
    # Whitelist fields. Customer identity and arbitrary keys never reach devices.
    return dict(schemaVersion=2, unit="m", room=dict(width=w, depth=d, height=h),
                openings=clean_cuts, items=clean_items)

def initial_room():
    return dict(schemaVersion=2, unit="m", room=dict(width=4, depth=5, height=2.8),
                openings=[dict(wall="top", kind="window", offset=1.4, width=1.2, sill=.95,
                               height=1.1, reverse=False),
                          dict(wall="left", kind="door", offset=3.6, width=.9, sill=0,
                               height=2.1, reverse=False)],
                items=[dict(instanceId="london-1", productId="factory:10_14_3",
                            position=dict(x=2, z=1.2), rotationY=0)])

def detached(value):
    return copy.deepcopy(value)
