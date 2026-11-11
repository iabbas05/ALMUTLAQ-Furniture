using System;
using System.IO;
using Almutlaq.Showroom;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEditor.XR.Management;
using UnityEditor.XR.Management.Metadata;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.XR.Management;
using Unity.XR.PXR;

public static class BuildShowroom
{
    [MenuItem("Almutlaq/Prepare measured showroom")]
    public static void Prepare()
    {
        foreach (var sku in new[] { "10_14_3", "6_14_5" })
            if (!File.Exists("Assets/Resources/Models/london-" + sku + ".json"))
                throw new BuildFailedException("Run Build-Headset.ps1 first to generate both model resources.");
        Directory.CreateDirectory("Assets/XR");
        if (!EditorBuildSettings.TryGetConfigObject(XRGeneralSettings.k_SettingsKey, out XRGeneralSettingsPerBuildTarget perTarget))
        {
            perTarget = ScriptableObject.CreateInstance<XRGeneralSettingsPerBuildTarget>();
            AssetDatabase.CreateAsset(perTarget, "Assets/XR/Settings.asset");
            EditorBuildSettings.AddConfigObject(XRGeneralSettings.k_SettingsKey, perTarget, true);
        }
        var general = perTarget.SettingsForBuildTarget(BuildTargetGroup.Android);
        if (general == null)
        {
            general = ScriptableObject.CreateInstance<XRGeneralSettings>();
            AssetDatabase.AddObjectToAsset(general, perTarget);
            perTarget.SetSettingsForBuildTarget(BuildTargetGroup.Android, general);
        }
        if (general.Manager == null)
        {
            var manager = ScriptableObject.CreateInstance<XRManagerSettings>();
            AssetDatabase.AddObjectToAsset(manager, perTarget);
            general.AssignedSettings = manager;
        }
        general.InitManagerOnStart = true;
        if (!XRPackageMetadataStore.AssignLoader(general.Manager, "Unity.XR.PXR.PXR_Loader", BuildTargetGroup.Android))
            throw new BuildFailedException("PICO loader could not be assigned. Check the pinned SDK package.");
        EditorUtility.SetDirty(perTarget);
        EditorUtility.SetDirty(general);
        EditorUtility.SetDirty(general.Manager);

        PlayerSettings.companyName = "ShowroomXR";
        PlayerSettings.productName = "Almutlaq Showroom";
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.showroomxr.measuredroom");
        PlayerSettings.bundleVersion = "0.8.1";
        PlayerSettings.Android.bundleVersionCode = 9;
        PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel29;
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
        PlayerSettings.Android.forceInternetPermission = true;
        // USB reverse maps the device loopback to the local staff service.
        PlayerSettings.insecureHttpOption = InsecureHttpOption.DevelopmentOnly;
        PlayerSettings.colorSpace = ColorSpace.Linear;
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
        PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
        PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.OpenGLES3 });
        PlayerSettings.stereoRenderingPath = StereoRenderingPath.SinglePass;
        QualitySettings.antiAliasing = 2;
        QualitySettings.shadowDistance = 12;
        QualitySettings.shadows = ShadowQuality.All;
        QualitySettings.vSyncCount = 0;
        Directory.CreateDirectory("Assets/Resources");
        // Keep the shader required by downloaded models in every player build.
        if (!File.Exists("Assets/Resources/FurnitureStandard.mat"))
            AssetDatabase.CreateAsset(new Material(Shader.Find("Standard")), "Assets/Resources/FurnitureStandard.mat");
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var rig = new GameObject("Standing viewpoint");
        rig.transform.position = new Vector3(2, 0, 4);
        rig.transform.rotation = Quaternion.Euler(0, 180, 0);
        rig.AddComponent<PXR_Manager>();
        var cameraObject = new GameObject("Head", typeof(Camera), typeof(AudioListener), typeof(HeadPose));
        cameraObject.tag = "MainCamera";
        cameraObject.transform.SetParent(rig.transform, false);
        cameraObject.transform.localPosition = new Vector3(0, 1.65f, 0);
        var camera = cameraObject.GetComponent<Camera>();
        camera.nearClipPlane = .05f;
        camera.farClipPlane = 50;
        camera.backgroundColor = new Color(.73f, .79f, .83f);
        camera.clearFlags = CameraClearFlags.SolidColor;
        var light = new GameObject("Daylight", typeof(Light));
        light.transform.rotation = Quaternion.Euler(48, -28, 0);
        light.GetComponent<Light>().type = LightType.Directional;
        light.GetComponent<Light>().intensity = 1.1f;
        light.GetComponent<Light>().shadows = LightShadows.Soft;
        new GameObject("Room", typeof(RoomScene), typeof(RoomBootstrap), typeof(RoomInput), typeof(RoomLink));
        Directory.CreateDirectory("Assets/Scenes");
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/MeasuredShowroom.unity");
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene("Assets/Scenes/MeasuredShowroom.unity", true) };
        AssetDatabase.SaveAssets();
    }

    public static void Android()
    {
        Prepare();
        var target = Environment.GetEnvironmentVariable("SHOWROOM_APK_OUTPUT");
        if (string.IsNullOrEmpty(target)) target = "../builds/ShowroomVR-Linked.apk";
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(target)));
        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions {
            scenes = new[] { "Assets/Scenes/MeasuredShowroom.unity" },
            locationPathName = target, target = BuildTarget.Android, options = BuildOptions.Development
        });
        if (report.summary.result != BuildResult.Succeeded)
            throw new BuildFailedException("Headset APK failed. Read the Unity build log.");
        Debug.Log("HEADSET_APK_BUILT " + Path.GetFullPath(target));
    }
}
