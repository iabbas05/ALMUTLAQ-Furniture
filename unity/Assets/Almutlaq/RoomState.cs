using System;
using System.Collections.Generic;
using UnityEngine;

namespace Almutlaq.Showroom
{
    [Serializable] public sealed class RoomSize { public float width, depth, height; }
    [Serializable] public sealed class PlanPosition { public float x, z; }
    [Serializable] public sealed class RoomOpening
    {
        public string wall, kind;
        public float offset, width, sill, height;
        public bool reverse;
    }
    [Serializable] public sealed class RoomItem
    {
        public string instanceId, productId, modelVersion;
        public PlanPosition position;
        public float rotationY;
    }
    [Serializable] public sealed class RoomState
    {
        public int schemaVersion, revision, appliedRevision;
        public string unit, sessionId;
        public RoomSize room;
        public RoomOpening[] openings;
        public RoomItem[] items;
        public int expectedRevision;

        public RoomState Copy() => JsonUtility.FromJson<RoomState>(JsonUtility.ToJson(this));

        public void Validate(Dictionary<string, ModelAsset> models)
        {
            if (schemaVersion != 2 || unit != "m" || room == null ||
                !InRange(room.width, 1, 25) || !InRange(room.depth, 1, 25) ||
                !InRange(room.height, 2, 10) || items == null || items.Length > 50 ||
                openings == null || openings.Length > 32)
                throw new FormatException("Invalid room document.");
            for (int i = 0; i < openings.Length; i++)
            {
                var o = openings[i];
                if (o == null || (o.wall != "top" && o.wall != "bottom" && o.wall != "left" && o.wall != "right") ||
                    (o.kind != "door" && o.kind != "window"))
                    throw new FormatException("Invalid opening.");
                float span = o.wall == "top" || o.wall == "bottom" ? room.width : room.depth;
                if (!InRange(o.offset, 0, span) || !InRange(o.width, .1f, span) ||
                    o.offset + o.width > span + .0001f || !InRange(o.height, .1f, room.height) ||
                    !InRange(o.sill, 0, room.height) || o.sill + o.height > room.height + .0001f ||
                    (o.kind == "door" && o.sill != 0))
                    throw new FormatException("Opening crosses the wall.");
                for (int j = 0; j < i; j++)
                {
                    var p = openings[j];
                    if (p.wall == o.wall && p.offset < o.offset + o.width - .0001f &&
                        o.offset < p.offset + p.width - .0001f) throw new FormatException("Openings overlap.");
                }
            }
            var ids = new HashSet<string>();
            foreach (var item in items)
            {
                if (item == null || string.IsNullOrEmpty(item.instanceId) || !ids.Add(item.instanceId) ||
                    item.position == null || !InRange(item.rotationY, -36000, 36000) ||
                    string.IsNullOrEmpty(item.modelVersion) || !models.TryGetValue(item.modelVersion, out var model))
                    throw new FormatException("Invalid furniture item or missing model.");
                var e = Extents(model.Width, model.Depth, item.rotationY);
                if (!InRange(item.position.x, e.x - .0001f, room.width - e.x + .0001f) ||
                    !InRange(item.position.z, e.y - .0001f, room.depth - e.y + .0001f) ||
                    model.Height > room.height)
                    throw new FormatException("The complete furniture footprint must fit.");
            }
        }

        public static Vector2 Extents(float width, float depth, float angle)
        {
            float t = angle * Mathf.Deg2Rad, c = Mathf.Abs(Mathf.Cos(t)), s = Mathf.Abs(Mathf.Sin(t));
            return new Vector2((width * c + depth * s) / 2, (width * s + depth * c) / 2);
        }
        public static bool InRange(float value, float min, float max) =>
            !float.IsNaN(value) && !float.IsInfinity(value) && value >= min && value <= max;
    }

    [Serializable] public sealed class ModelVersion
    {
        public string modelUrl, sha256;
        public RoomSize dimensions;
    }
    [Serializable] public sealed class PairingResult { public string token; }
    [Serializable] public sealed class PairingRequest { public string code; }
    [Serializable] public sealed class AppliedScene { public string sessionId; public int revision; }
}
