using System;
using System.Collections.Generic;
using Almutlaq.Showroom;
using NUnit.Framework;
using UnityEngine;

public class RoomValidationTests
{
    private static RoomState Valid() => new RoomState {
        schemaVersion = 2, unit = "m", revision = 1, sessionId = "test-room",
        room = new RoomSize { width = 4, depth = 5, height = 2.8f },
        openings = Array.Empty<RoomOpening>(), items = Array.Empty<RoomItem>()
    };

    [Test]
    public void RejectedRevisionLeavesCurrentSceneUntouched()
    {
        var root = new GameObject("TEST room");
        try
        {
            var scene = root.AddComponent<RoomScene>();
            scene.Apply(Valid());
            var accepted = scene.Current;
            var broken = Valid(); broken.revision = 2; broken.room.width = float.NaN;
            Assert.Throws<FormatException>(() => scene.Apply(broken));
            Assert.AreSame(accepted, scene.Current);
            Assert.AreEqual(1, scene.Current.revision);
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }

    [Test]
    public void ApplyingBeforePlayerAwakeCreatesAndReusesFinishes()
    {
        var root = new GameObject("TEST material lifecycle");
        // An inactive object cannot receive the normal player Awake yet.
        root.SetActive(false);
        try
        {
            var scene = root.AddComponent<RoomScene>();
            scene.Apply(Valid());
            var floor = root.transform.Find("Measured room revision 1/Floor");
            Assert.IsNotNull(floor);
            var finish = floor.GetComponent<Renderer>().sharedMaterial;
            Assert.IsNotNull(finish);
            Assert.IsNotNull(finish.mainTexture);

            var next = Valid(); next.revision = 2;
            scene.Apply(next);
            var nextFloor = root.transform.Find("Measured room revision 2/Floor");
            Assert.IsNotNull(nextFloor);
            Assert.AreSame(finish, nextFloor.GetComponent<Renderer>().sharedMaterial);
            Assert.IsNull(root.transform.Find("Measured room revision 1"));
            root.SetActive(true);
            Assert.AreSame(finish, nextFloor.GetComponent<Renderer>().sharedMaterial);
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }

    [Test]
    public void OverlappingOpeningsAreRejectedBeforeSceneApplication()
    {
        var state = Valid();
        state.openings = new[] {
            new RoomOpening { kind = "door", wall = "top", offset = 0, width = .9f, height = 2.1f },
            new RoomOpening { kind = "window", wall = "top", offset = .5f, width = 1, sill = 1, height = 1 }
        };
        Assert.Throws<FormatException>(() => state.Validate(new Dictionary<string, ModelAsset>()));
    }
}
