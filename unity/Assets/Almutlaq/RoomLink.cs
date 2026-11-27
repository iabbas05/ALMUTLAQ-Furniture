using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using UnityEngine;
using UnityEngine.Networking;

namespace Almutlaq.Showroom
{
    [RequireComponent(typeof(RoomScene))]
    public sealed class RoomLink : MonoBehaviour
    {
        private const string Endpoint = "http://127.0.0.1:8766";
        private RoomScene scene;
        private string token, attemptedCode;
        private float lastEdit;
        private bool dirty;
        private TextMesh hud;
        private readonly Dictionary<string, byte[]> volatileCache = new Dictionary<string, byte[]>();

        private sealed class NetResult { public long code; public byte[] bytes; public string Text => bytes == null ? "" : Encoding.UTF8.GetString(bytes); }
        [Serializable] private sealed class SavedConnection { public string token; }

        private IEnumerator Start()
        {
            scene = GetComponent<RoomScene>();
            scene.LocalChanged += Changed;
            CreateHud();
            try
            {
                string path = Path.Combine(Application.persistentDataPath, "connection.json");
                if (File.Exists(path)) token = JsonUtility.FromJson<SavedConnection>(File.ReadAllText(path)).token;
            }
            catch { token = null; }
            while (true)
            {
                if (string.IsNullOrEmpty(token))
                {
                    string code = IntentCode();
                    if (!string.IsNullOrEmpty(code) && code != attemptedCode)
                    {
                        attemptedCode = code;
                        var paired = new NetResult();
                        yield return Send("/api/pair", JsonUtility.ToJson(new PairingRequest { code = code }), false, paired);
                        if (paired.code == 200)
                        {
                            try
                            {
                                token = JsonUtility.FromJson<PairingResult>(paired.Text).token;
                                Directory.CreateDirectory(Application.persistentDataPath);
                                File.WriteAllText(Path.Combine(Application.persistentDataPath, "connection.json"),
                                    JsonUtility.ToJson(new SavedConnection { token = token }));
                            }
                            catch { token = null; }
                        }
                    }
                    if (string.IsNullOrEmpty(token))
                    {
                        Status("Offline preview\nPair from the PC launcher");
                        yield return new WaitForSecondsRealtime(1);
                        continue;
                    }
                }

                if (dirty && Time.unscaledTime - lastEdit < .45f)
                {
                    yield return new WaitForSecondsRealtime(.15f);
                    continue;
                }
                var response = new NetResult();
                if (dirty && scene.Current != null)
                {
                    var local = scene.Current.Copy();
                    // Phone plan controls use whole degrees. Snap once after a gesture, never scale furniture.
                    foreach (var item in local.items)
                    {
                        item.rotationY = Mathf.Round(item.rotationY);
                        var model = scene.Models[item.modelVersion];
                        var e = RoomState.Extents(model.Width, model.Depth, item.rotationY);
                        item.position.x = Mathf.Clamp(item.position.x, e.x, local.room.width - e.x);
                        item.position.z = Mathf.Clamp(item.position.z, e.y, local.room.depth - e.y);
                    }
                    local.expectedRevision = scene.Current.revision;
                    yield return Send("/api/state", JsonUtility.ToJson(local), true, response);
                    if (response.code == 409)
                    {
                        dirty = false;
                        Status("Staff changed the design\nReloading the latest revision");
                        yield return Send("/api/state", null, true, response);
                    }
                }
                else yield return Send("/api/state", null, true, response);

                if (response.code == 401)
                {
                    token = null; attemptedCode = null; Status("Pairing required");
                }
                else if (response.code == 200)
                {
                    RoomState incoming = null;
                    try { incoming = JsonUtility.FromJson<RoomState>(response.Text); }
                    catch { Status("Invalid room document\nPrevious scene retained"); }
                    if (incoming != null)
                    {
                        bool needsApply = dirty || scene.Current == null || incoming.sessionId != scene.Current.sessionId ||
                            incoming.revision != scene.Current.revision;
                        bool loaded = true;
                        if (needsApply)
                        {
                            foreach (var item in incoming.items ?? Array.Empty<RoomItem>())
                            {
                                if (string.IsNullOrEmpty(item.modelVersion) || !Regex.IsMatch(item.modelVersion, "^[a-f0-9]{64}$"))
                                { loaded = false; break; }
                                if (scene.Models.ContainsKey(item.modelVersion)) continue;
                                var info = new NetResult();
                                string query = "/api/model-version?id=" + UnityWebRequest.EscapeURL(item.productId) +
                                    "&version=" + item.modelVersion;
                                yield return Send(query, null, true, info);
                                ModelVersion metadata = null;
                                try
                                {
                                    if (info.code == 200) metadata = JsonUtility.FromJson<ModelVersion>(info.Text);
                                    if (metadata == null || metadata.sha256 != item.modelVersion ||
                                        !Regex.IsMatch(metadata.modelUrl ?? "", "^/models/[a-f0-9]{64}\\.mesh\\.json$"))
                                        throw new FormatException();
                                }
                                catch { loaded = false; break; }
                                byte[] bytes = ReadCache(metadata.sha256);
                                if (bytes == null)
                                {
                                    var file = new NetResult();
                                    yield return Send(metadata.modelUrl, null, true, file);
                                    if (file.code != 200) { loaded = false; break; }
                                    bytes = file.bytes;
                                }
                                try
                                {
                                    var model = ModelAsset.Load(bytes, metadata.sha256, metadata.dimensions);
                                    scene.Models[metadata.sha256] = model;
                                    WriteCache(metadata.sha256, bytes);
                                }
                                catch { loaded = false; break; }
                            }
                            if (loaded)
                            {
                                try { scene.Apply(incoming); dirty = false; }
                                catch { loaded = false; }
                            }
                        }
                        if (loaded)
                        {
                            var ack = new NetResult();
                            yield return Send("/api/ack", JsonUtility.ToJson(new AppliedScene {
                                sessionId = incoming.sessionId, revision = incoming.revision }), true, ack);
                            Status(ack.code == 200 ? "Scene applied · revision " + incoming.revision +
                                "\nLeft stick: move · right stick: rotate\nTrigger: select · B: next item"
                                : "Scene visible · confirmation pending");
                        }
                        else Status("Model or scene validation failed\nPrevious scene retained");
                    }
                }
                else Status("Connection unavailable\nPrevious scene retained");
                yield return new WaitForSecondsRealtime(.5f);
            }
        }
        private void Changed() { dirty = true; lastEdit = Time.unscaledTime; }
        private void CreateHud()
        {
            if (Camera.main == null) return;
            var root = new GameObject("Connection and controls").transform;
            root.SetParent(Camera.main.transform, false);
            root.localPosition = new Vector3(-.52f, .37f, 1.45f);
            hud = root.gameObject.AddComponent<TextMesh>();
            hud.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            hud.fontSize = 40; hud.characterSize = .016f;
            hud.anchor = TextAnchor.UpperLeft; hud.alignment = TextAlignment.Left;
            hud.color = new Color(.12f, .22f, .17f); hud.richText = false;
            root.GetComponent<MeshRenderer>().sharedMaterial = hud.font.material;
        }
        private void Status(string value) { if (hud != null) hud.text = value; }
        private static string IntentCode()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            try
            {
                using (var player = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
                using (var activity = player.GetStatic<AndroidJavaObject>("currentActivity"))
                using (var intent = activity.Call<AndroidJavaObject>("getIntent"))
                {
                    string code = intent.Call<string>("getStringExtra", "showroom_pair_code");
                    return Regex.IsMatch(code ?? "", "^[0-9]{6}$") ? code : null;
                }
            }
            catch { return null; }
#else
            return Environment.GetEnvironmentVariable("SHOWROOM_PAIR_CODE");
#endif
        }
        private IEnumerator Send(string path, string json, bool authenticated, NetResult result)
        {
            using (var request = new UnityWebRequest(Endpoint + path, json == null ? "GET" : "POST"))
            {
                request.timeout = 8;
                request.redirectLimit = 0;
                request.downloadHandler = new DownloadHandlerBuffer();
                if (json != null)
                {
                    request.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(json));
                    request.SetRequestHeader("Content-Type", "application/json");
                }
                if (authenticated) request.SetRequestHeader("Authorization", "Bearer " + token);
                yield return request.SendWebRequest();
                result.code = request.responseCode;
                result.bytes = request.downloadHandler.data;
            }
        }
        private byte[] ReadCache(string hash)
        {
            if (volatileCache.TryGetValue(hash, out var bytes)) return bytes;
            try
            {
                string path = Path.Combine(Application.persistentDataPath, "models", hash + ".json");
                if (File.Exists(path))
                {
                    bytes = File.ReadAllBytes(path);
                    if (ModelAsset.Checksum(bytes) == hash) return bytes;
                }
            }
            catch { }
            return null;
        }
        private void WriteCache(string hash, byte[] bytes)
        {
            // Only hash-named model bytes are cached, never customer identity.
            volatileCache[hash] = bytes;
            try
            {
                string directory = Path.Combine(Application.persistentDataPath, "models");
                Directory.CreateDirectory(directory);
                File.WriteAllBytes(Path.Combine(directory, hash + ".json"), bytes);
            }
            catch { }
        }
        private void OnDestroy() { if (scene != null) scene.LocalChanged -= Changed; }
    }
}
