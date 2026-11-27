using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR;

namespace Almutlaq.Showroom
{
    public sealed class HeadPose : MonoBehaviour
    {
        private readonly List<XRInputSubsystem> systems = new List<XRInputSubsystem>();
        private float nextOriginCheck;
        private void Update()
        {
            if (Time.unscaledTime >= nextOriginCheck)
            {
                nextOriginCheck = Time.unscaledTime + 5;
                SubsystemManager.GetSubsystems(systems);
                foreach (var system in systems)
                    if (system.running) system.TrySetTrackingOriginMode(TrackingOriginModeFlags.Floor);
            }
        }
        private void LateUpdate()
        {
            if (!XRSettings.isDeviceActive) return;
            var head = InputDevices.GetDeviceAtXRNode(XRNode.Head);
            if (head.TryGetFeatureValue(CommonUsages.devicePosition, out var position)) transform.localPosition = position;
            if (head.TryGetFeatureValue(CommonUsages.deviceRotation, out var rotation)) transform.localRotation = rotation;
        }
    }
}
