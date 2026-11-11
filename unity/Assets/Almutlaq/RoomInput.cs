using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR;

namespace Almutlaq.Showroom
{
    [RequireComponent(typeof(RoomScene))]
    public sealed class RoomInput : MonoBehaviour
    {
        private RoomScene room;
        private bool oldNext, oldTrigger;
        private void Awake() { room = GetComponent<RoomScene>(); }
        private void Update()
        {
            if (room.Current == null || Camera.main == null) return;
            var left = InputDevices.GetDeviceAtXRNode(XRNode.LeftHand);
            var right = InputDevices.GetDeviceAtXRNode(XRNode.RightHand);
            Vector2 move = Vector2.zero, turn = Vector2.zero;
            left.TryGetFeatureValue(CommonUsages.primary2DAxis, out move);
            right.TryGetFeatureValue(CommonUsages.primary2DAxis, out turn);
#if UNITY_EDITOR || UNITY_STANDALONE
            if (!XRSettings.isDeviceActive)
            {
                move += new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
                if (Input.GetKey(KeyCode.Q)) turn.x -= 1;
                if (Input.GetKey(KeyCode.E)) turn.x += 1;
            }
#endif
            var forward = Camera.main.transform.forward; forward.y = 0; forward.Normalize();
            var sideways = Camera.main.transform.right; sideways.y = 0; sideways.Normalize();
            var delta = move.sqrMagnitude > .04f ? (sideways * move.x + forward * move.y) * (.65f * Time.deltaTime) : Vector3.zero;
            float yaw = Mathf.Abs(turn.x) > .2f ? turn.x * 65f * Time.deltaTime : 0;
            room.MoveSelected(delta, yaw);
            right.TryGetFeatureValue(CommonUsages.secondaryButton, out bool next);
            if (next && !oldNext) room.Select(room.Selected + 1);
            oldNext = next;
            right.TryGetFeatureValue(CommonUsages.triggerButton, out bool trigger);
            if (trigger && !oldTrigger && right.TryGetFeatureValue(CommonUsages.devicePosition, out var local) &&
                right.TryGetFeatureValue(CommonUsages.deviceRotation, out var rotation))
            {
                var origin = Camera.main.transform.parent;
                var position = origin != null ? origin.TransformPoint(local) : local;
                var worldRotation = origin != null ? origin.rotation * rotation : rotation;
                if (Physics.Raycast(position, worldRotation * Vector3.forward, out var hit, 12, 1 << 8))
                    for (int i = 0; i < room.Furniture.Count; i++)
                        if (hit.collider.gameObject == room.Furniture[i]) { room.Select(i); break; }
            }
            oldTrigger = trigger;
        }
    }

}
