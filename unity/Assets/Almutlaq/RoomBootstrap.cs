using UnityEngine;
using UnityEngine.Rendering;

namespace Almutlaq.Showroom
{
    [DefaultExecutionOrder(-50)]
    [RequireComponent(typeof(RoomScene))]
    public sealed class RoomBootstrap : MonoBehaviour
    {
        private void Start()
        {
            var scene = GetComponent<RoomScene>();
            var a = Resources.Load<TextAsset>("Models/london-10_14_3");
            var b = Resources.Load<TextAsset>("Models/london-6_14_5");
            if (a == null || b == null)
            {
                Debug.LogError("Generate and copy the two demo models before building.");
                return;
            }
            string ah = ModelAsset.Checksum(a.bytes), bh = ModelAsset.Checksum(b.bytes);
            scene.Models[ah] = ModelAsset.Load(a.bytes, ah, new RoomSize { width = 2.1f, depth = 1.03f, height = 1 });
            scene.Models[bh] = ModelAsset.Load(b.bytes, bh, new RoomSize { width = .84f, depth = .95f, height = .94f });
            scene.Apply(new RoomState {
                schemaVersion = 2, unit = "m", revision = 0, sessionId = "offline-preview",
                room = new RoomSize { width = 4, depth = 5, height = 2.8f },
                openings = new[] {
                    new RoomOpening { wall = "top", kind = "window", offset = 1.4f, width = 1.2f, sill = .95f, height = 1.1f },
                    new RoomOpening { wall = "left", kind = "door", offset = 3.6f, width = .9f, height = 2.1f },
                },
                items = new[] {
                    new RoomItem { instanceId = "sofa", productId = "factory:10_14_3", modelVersion = ah, position = new PlanPosition { x = 2, z = 1.2f } },
                    new RoomItem { instanceId = "chair", productId = "factory:6_14_5", modelVersion = bh, position = new PlanPosition { x = 2.85f, z = 3 } },
                },
            });
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(.78f, .81f, .84f);
            RenderSettings.ambientEquatorColor = new Color(.66f, .64f, .60f);
            RenderSettings.ambientGroundColor = new Color(.34f, .30f, .26f);
        }
    }
}
