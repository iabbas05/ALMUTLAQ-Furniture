using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.TestTools.TestRunner.Api;
using UnityEngine;

// Uses the already-open licensed Editor. No headset or ADB connection is needed.
public sealed class BuildFromEditor : ICallbacks
{
    private static TestRunnerApi runner;
    private static BuildFromEditor listener;
    private static bool busy;
    private string outputDirectory;

    [MenuItem("Almutlaq/Test and build PICO APK")]
    public static void StartBuild()
    {
        if (busy) throw new BuildFailedException("A PICO test/build is already running.");
        if (EditorApplication.isCompiling || EditorApplication.isPlayingOrWillChangePlaymode)
            throw new BuildFailedException("Stop Play Mode and let compilation finish first.");
        if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
            throw new BuildFailedException("Select Android in File > Build Profiles and switch the active platform first. Then run Almutlaq > Test and build PICO APK again.");
        if (!EditorSceneManagerSave()) return;
        foreach (var sku in new[] { "10_14_3", "6_14_5" })
            if (!File.Exists("Assets/Resources/Models/london-" + sku + ".json"))
                throw new BuildFailedException("Generate the model resources with Build-Headset.ps1 before using the Editor build menu.");

        listener = new BuildFromEditor {
            outputDirectory = Path.GetFullPath(Path.Combine(Application.dataPath, "../../builds"))
        };
        Directory.CreateDirectory(listener.outputDirectory);
        var report = Path.Combine(listener.outputDirectory, "unity-editor-tests.xml");
        if (File.Exists(report)) File.Delete(report);
        runner = ScriptableObject.CreateInstance<TestRunnerApi>();
        runner.RegisterCallbacks(listener);
        busy = true;
        try {
            runner.Execute(new ExecutionSettings(new Filter {
                testMode = TestMode.EditMode,
                assemblyNames = new[] { "Almutlaq.Showroom.Tests" }
            }));
        }
        catch { Cleanup(); throw; }
        Debug.Log("PICO build: running showroom edit-mode tests before APK packaging.");
    }

    private static bool EditorSceneManagerSave() =>
        UnityEditor.SceneManagement.EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo();

    public void RunStarted(ITestAdaptor testsToRun) { }
    public void TestStarted(ITestAdaptor test) { }
    public void TestFinished(ITestResultAdaptor result) { }
    public void RunFinished(ITestResultAdaptor result)
    {
        try {
            TestRunnerApi.SaveResultToFile(result, Path.Combine(outputDirectory, "unity-editor-tests.xml"));
            if (result.ResultState != "Passed" || result.PassCount < 1 || result.FailCount != 0) {
                Debug.LogError("PICO build stopped: showroom tests failed or no tests passed. Read builds/unity-editor-tests.xml.");
                Cleanup();
                return;
            }
            // Build after the test-runner callback has unwound.
            EditorApplication.delayCall += PackageApk;
        }
        catch { Cleanup(); throw; }
    }

    private void PackageApk()
    {
        var previous = Environment.GetEnvironmentVariable("SHOWROOM_APK_OUTPUT");
        var pending = Path.Combine(outputDirectory, "ShowroomVR-Editor.pending.apk");
        var final = Path.Combine(outputDirectory, "ShowroomVR-Linked.apk");
        try {
            if (File.Exists(pending)) File.Delete(pending);
            Environment.SetEnvironmentVariable("SHOWROOM_APK_OUTPUT", pending);
            BuildShowroom.Android();
            if (!File.Exists(pending) || new FileInfo(pending).Length == 0)
                throw new BuildFailedException("Unity did not produce a new nonempty APK.");
            if (File.Exists(final)) File.Replace(pending, final, null);
            else File.Move(pending, final);
            Debug.Log("PICO_APK_READY " + final + ". Untested on device.");
            EditorUtility.RevealInFinder(final);
        }
        finally { Environment.SetEnvironmentVariable("SHOWROOM_APK_OUTPUT", previous); Cleanup(); }
    }

    private static void Cleanup()
    {
        if (runner != null) {
            if (listener != null) runner.UnregisterCallbacks(listener);
            UnityEngine.Object.DestroyImmediate(runner);
        }
        listener = null; runner = null; busy = false;
    }
}
