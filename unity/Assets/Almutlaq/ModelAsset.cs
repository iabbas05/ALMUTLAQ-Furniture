using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;
using UnityEngine.Rendering;

namespace Almutlaq.Showroom
{
    [Serializable] internal sealed class MeshPart
    {
        public string name;
        public float[] vertices, normals, color;
        public int[] triangles;
        public float roughness;
    }
    [Serializable] internal sealed class MeshDocument
    {
        public int formatVersion;
        public string unit;
        public float width, depth, height;
        public MeshPart[] parts;
    }

    public sealed class ModelAsset : IDisposable
    {
        public float Width { get; private set; }
        public float Depth { get; private set; }
        public float Height { get; private set; }
        public string Hash { get; private set; }
        private readonly List<Mesh> meshes = new List<Mesh>();
        private readonly List<Material> materials = new List<Material>();
        private readonly List<string> labels = new List<string>();

        public static string Checksum(byte[] bytes)
        {
            using (var sha = SHA256.Create())
            {
                var digest = sha.ComputeHash(bytes);
                var result = new StringBuilder(64);
                foreach (var b in digest) result.Append(b.ToString("x2"));
                return result.ToString();
            }
        }

        public static ModelAsset Load(byte[] bytes, string checksum, RoomSize expected)
        {
            if (bytes == null || bytes.Length > 25 * 1024 * 1024 ||
                !string.Equals(Checksum(bytes), checksum, StringComparison.Ordinal))
                throw new FormatException("Model checksum mismatch.");
            var data = JsonUtility.FromJson<MeshDocument>(Encoding.UTF8.GetString(bytes));
            if (data == null || data.formatVersion != 1 || data.unit != "m" || data.parts == null ||
                data.parts.Length == 0 || data.parts.Length > 512 || expected == null)
                throw new FormatException("Unsupported demo mesh.");
            if (Mathf.Abs(data.width - expected.width) > .005f || Mathf.Abs(data.depth - expected.depth) > .005f ||
                Mathf.Abs(data.height - expected.height) > .005f)
                throw new FormatException("Published model dimensions differ.");
            var output = new ModelAsset { Width = data.width, Depth = data.depth, Height = data.height, Hash = checksum };
            var bounds = new Bounds();
            bool first = true;
            int triangles = 0;
            try
            {
                foreach (var part in data.parts)
                {
                    if (part.vertices == null || part.vertices.Length < 9 || part.vertices.Length % 3 != 0 ||
                        part.vertices.Length > 450000 || part.triangles == null || part.triangles.Length % 3 != 0 ||
                        part.color == null || part.color.Length != 4)
                        throw new FormatException("Invalid mesh arrays.");
                    triangles += part.triangles.Length / 3;
                    if (triangles > 50000) throw new FormatException("Model triangle budget exceeded.");
                    var vertices = new Vector3[part.vertices.Length / 3];
                    for (int i = 0; i < vertices.Length; i++)
                    {
                        var v = new Vector3(part.vertices[i * 3], part.vertices[i * 3 + 1], part.vertices[i * 3 + 2]);
                        if (!RoomState.InRange(v.x, -10, 10) || !RoomState.InRange(v.y, -.005f, 10) ||
                            !RoomState.InRange(v.z, -10, 10)) throw new FormatException("Non-finite mesh positions.");
                        vertices[i] = v;
                        if (first) { bounds = new Bounds(v, Vector3.zero); first = false; } else bounds.Encapsulate(v);
                    }
                    foreach (var index in part.triangles)
                        if (index < 0 || index >= vertices.Length) throw new FormatException("Invalid mesh index.");
                    foreach (var channel in part.color)
                        if (!RoomState.InRange(channel, 0, 1)) throw new FormatException("Invalid material colour.");
                    var mesh = new Mesh { name = part.name, indexFormat = vertices.Length > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16 };
                    mesh.vertices = vertices;
                    mesh.triangles = part.triangles;
                    if (part.normals != null && part.normals.Length == part.vertices.Length)
                    {
                        var normals = new Vector3[vertices.Length];
                        for (int i = 0; i < normals.Length; i++)
                            normals[i] = new Vector3(part.normals[i * 3], part.normals[i * 3 + 1], part.normals[i * 3 + 2]);
                        mesh.normals = normals;
                    }
                    else mesh.RecalculateNormals();
                    var uv = new Vector2[vertices.Length];
                    var ns = mesh.normals;
                    for (int i = 0; i < vertices.Length; i++)
                    {
                        var v = vertices[i]; var n = ns[i];
                        uv[i] = Mathf.Abs(n.y) > .55f ? new Vector2(v.x * 4, v.z * 4)
                            : new Vector2((Mathf.Abs(n.x) > .55f ? v.z : v.x) * 4, v.y * 4);
                    }
                    mesh.uv = uv;
                    mesh.RecalculateBounds();
                    mesh.RecalculateTangents();
                    var shader = Shader.Find("Standard");
                    if (shader == null) throw new InvalidOperationException("Standard shader was not included.");
                    var material = new Material(shader) { name = "Furniture fabric" };
                    material.color = new Color(part.color[0], part.color[1], part.color[2], part.color[3]).gamma;
                    material.SetFloat("_Glossiness", 1 - Mathf.Clamp01(part.roughness));
                    material.EnableKeyword("_EMISSION");
                    output.materials.Add(material); output.meshes.Add(mesh); output.labels.Add(part.name);
                }
                if (Mathf.Abs(bounds.size.x - expected.width) > .005f || Mathf.Abs(bounds.size.z - expected.depth) > .005f ||
                    Mathf.Abs(bounds.size.y - expected.height) > .005f || Mathf.Abs(bounds.min.y) > .005f ||
                    Mathf.Abs(bounds.center.x) > .005f || Mathf.Abs(bounds.center.z) > .005f)
                    throw new FormatException("Model geometry differs from its declared footprint.");
                return output;
            }
            catch { output.Dispose(); throw; }
        }

        public GameObject Instantiate(Transform parent, string label)
        {
            var root = new GameObject(label);
            root.transform.SetParent(parent, false);
            for (int i = 0; i < meshes.Count; i++)
            {
                var part = new GameObject(labels[i]);
                part.transform.SetParent(root.transform, false);
                part.AddComponent<MeshFilter>().sharedMesh = meshes[i];
                part.AddComponent<MeshRenderer>().sharedMaterial = materials[i];
            }
            var collider = root.AddComponent<BoxCollider>();
            collider.size = new Vector3(Width, Height, Depth);
            collider.center = new Vector3(0, Height / 2, 0);
            root.layer = 8;
            return root;
        }
        public void Dispose()
        {
            foreach (var mesh in meshes) if (mesh != null) UnityEngine.Object.Destroy(mesh);
            foreach (var material in materials) if (material != null) UnityEngine.Object.Destroy(material);
            meshes.Clear(); materials.Clear();
        }
    }
}
