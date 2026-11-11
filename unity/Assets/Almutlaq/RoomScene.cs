using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Almutlaq.Showroom
{
    public sealed class RoomScene : MonoBehaviour
    {
        public RoomState Current { get; private set; }
        public readonly Dictionary<string, ModelAsset> Models = new Dictionary<string, ModelAsset>();
        public IReadOnlyList<GameObject> Furniture => furniture;
        public int Selected { get; private set; }
        public event Action LocalChanged;
        private List<GameObject> furniture = new List<GameObject>();
        private GameObject sceneRoot;
        private readonly List<Material> finishes = new List<Material>();
        private Material wallMaterial, floorMaterial, frameMaterial, glassMaterial;

        private Material Finish(string label, Color color, float smooth = .15f)
        {
            var material = new Material(Shader.Find("Standard")) { name = label, color = color };
            material.SetFloat("_Glossiness", smooth);
            finishes.Add(material);
            return material;
        }
        private void Awake()
        {
            wallMaterial = Finish("Warm plaster", new Color(.86f, .84f, .79f));
            floorMaterial = Finish("Oak floor", new Color(.69f, .51f, .32f), .2f);
            frameMaterial = Finish("Oak frames", new Color(.53f, .39f, .25f));
            glassMaterial = Finish("Window glass", new Color(.61f, .77f, .81f, .28f), .75f);
            glassMaterial.SetFloat("_Mode", 3);
            glassMaterial.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
            glassMaterial.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            glassMaterial.SetInt("_ZWrite", 0);
            glassMaterial.EnableKeyword("_ALPHAPREMULTIPLY_ON");
            glassMaterial.renderQueue = 3000;
            var grain = new Texture2D(128, 128, TextureFormat.RGB24, true) { name = "Procedural oak", wrapMode = TextureWrapMode.Repeat };
            for (int y = 0; y < 128; y++)
                for (int x = 0; x < 128; x++)
                {
                    float n = .91f + .07f * Mathf.Sin(y * .75f + Mathf.Sin(x * .04f) * 2) + .02f * Mathf.Sin(x * 2.1f + y);
                    if (y < 2 || (x < 2 && y > 63)) n *= .73f;
                    grain.SetPixel(x, y, new Color(n, n, n));
                }
            grain.Apply();
            floorMaterial.mainTexture = grain;
        }

        public void Apply(RoomState state)
        {
            state.Validate(Models);
            var stage = new GameObject("Measured room revision " + state.revision);
            stage.SetActive(false);
            var next = new List<GameObject>();
            try
            {
                var room = state.room;
                var floor = Box("Floor", stage.transform, new Vector3(room.width / 2, -.04f, room.depth / 2),
                    new Vector3(room.width, .08f, room.depth), floorMaterial);
                floor.GetComponent<Renderer>().sharedMaterial.mainTextureScale = new Vector2(room.width / 1.3f, room.depth / 1.3f);
                foreach (var side in new[] { "top", "right", "bottom", "left" }) BuildWall(stage.transform, state, side);
                foreach (var item in state.items)
                {
                    var model = Models[item.modelVersion];
                    var root = model.Instantiate(stage.transform, item.productId);
                    SetPose(root.transform, item);
                    next.Add(root);
                }
            }
            catch { Release(stage); throw; }
            var old = sceneRoot;
            sceneRoot = stage; furniture = next; Current = state.Copy();
            Selected = Mathf.Clamp(Selected, 0, Mathf.Max(0, next.Count - 1));
            stage.SetActive(true);
            if (old != null) { old.SetActive(false); Release(old); }
            Highlight();
        }

        private void BuildWall(Transform parent, RoomState data, string side)
        {
            var r = data.room;
            bool horizontal = side == "top" || side == "bottom";
            float span = horizontal ? r.width : r.depth;
            Vector3 At(float t, float y) => side == "top" ? new Vector3(t, y, 0)
                : side == "bottom" ? new Vector3(t, y, r.depth)
                : side == "left" ? new Vector3(0, y, t) : new Vector3(r.width, y, t);
            void Panel(string label, float a, float b, float bottom, float top, Material material, float thick = .08f)
            {
                if (b - a < .0001f || top - bottom < .0001f) return;
                Box(label, parent, At((a + b) / 2, (bottom + top) / 2),
                    horizontal ? new Vector3(b - a, top - bottom, thick) : new Vector3(thick, top - bottom, b - a), material);
            }
            float cursor = 0;
            foreach (var o in data.openings.Where(o => o.wall == side).OrderBy(o => o.offset))
            {
                float a = o.offset, b = a + o.width;
                Panel("Plaster wall", cursor, a, 0, r.height, wallMaterial);
                Panel("Lower wall", a, b, 0, o.sill, wallMaterial);
                Panel("Upper wall", a, b, o.sill + o.height, r.height, wallMaterial);
                const float frame = .045f;
                Panel("Opening frame", a - frame, a, o.sill, o.sill + o.height + frame, frameMaterial, .11f);
                Panel("Opening frame", b, b + frame, o.sill, o.sill + o.height + frame, frameMaterial, .11f);
                Panel("Opening lintel", a, b, o.sill + o.height, o.sill + o.height + frame, frameMaterial, .11f);
                if (o.kind == "window")
                {
                    Panel("Window sill", a, b, o.sill - frame, o.sill, frameMaterial, .14f);
                    Panel("Window pane", a, b, o.sill, o.sill + o.height, glassMaterial, .012f);
                    Panel("Window mullion", (a + b) / 2 - .012f, (a + b) / 2 + .012f,
                        o.sill, o.sill + o.height, frameMaterial, .035f);
                }
                else
                {
                    var hinge = new GameObject("Door hinge").transform;
                    hinge.SetParent(parent, false);
                    hinge.localPosition = At(o.reverse ? b : a, 0);
                    float direction = side == "top" ? 0 : side == "bottom" ? 180 : side == "left" ? -90 : 90;
                    if (o.reverse) direction += 180;
                    hinge.localRotation = Quaternion.Euler(0, direction + 55, 0);
                    Box("Door leaf", hinge, new Vector3(o.width / 2, o.height / 2, 0),
                        new Vector3(o.width, o.height, .035f), frameMaterial);
                }
                cursor = b;
            }
            Panel("Plaster wall", cursor, span, 0, r.height, wallMaterial);
        }

        private static GameObject Box(string label, Transform parent, Vector3 position, Vector3 size, Material finish)
        {
            var box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            box.name = label; box.transform.SetParent(parent, false);
            box.transform.localPosition = position; box.transform.localScale = size;
            box.GetComponent<Renderer>().sharedMaterial = finish;
            return box;
        }
        private static void SetPose(Transform target, RoomItem item)
        {
            target.localPosition = new Vector3(item.position.x, 0, item.position.z);
            // Positive room yaw is clockwise in the top-down plan. Unity Y rotation uses the opposite sign.
            target.localRotation = Quaternion.Euler(0, -item.rotationY, 0);
            target.localScale = Vector3.one;
        }

        public void Select(int index)
        {
            if (furniture.Count == 0) return;
            Selected = ((index % furniture.Count) + furniture.Count) % furniture.Count;
            Highlight();
        }
        private void Highlight()
        {
            for (int i = 0; i < furniture.Count; i++)
            {
                var block = new MaterialPropertyBlock();
                block.SetColor("_EmissionColor", i == Selected ? new Color(.015f, .055f, .035f) : Color.black);
                foreach (var renderer in furniture[i].GetComponentsInChildren<Renderer>()) renderer.SetPropertyBlock(block);
            }
        }
        public bool MoveSelected(Vector3 delta, float yawDelta)
        {
            if (Current == null || furniture.Count == 0) return false;
            var item = Current.items[Selected]; var model = Models[item.modelVersion];
            float yaw = Mathf.Repeat(item.rotationY + yawDelta, 360);
            var e = RoomState.Extents(model.Width, model.Depth, yaw);
            if (e.x * 2 > Current.room.width || e.y * 2 > Current.room.depth) return false;
            float x = Mathf.Clamp(item.position.x + delta.x, e.x, Current.room.width - e.x);
            float z = Mathf.Clamp(item.position.z + delta.z, e.y, Current.room.depth - e.y);
            if (Mathf.Abs(x - item.position.x) + Mathf.Abs(z - item.position.z) + Mathf.Abs(yawDelta) < .00001f) return false;
            item.position.x = x; item.position.z = z; item.rotationY = yaw;
            SetPose(furniture[Selected].transform, item);
            LocalChanged?.Invoke();
            return true;
        }
        private void OnDestroy()
        {
            foreach (var model in Models.Values) model.Dispose();
            foreach (var finish in finishes)
            {
                if (finish.mainTexture != null) Release(finish.mainTexture);
                Release(finish);
            }
        }
        private static void Release(UnityEngine.Object value)
        {
            if (Application.isPlaying) UnityEngine.Object.Destroy(value);
            else UnityEngine.Object.DestroyImmediate(value);
        }
    }
}
