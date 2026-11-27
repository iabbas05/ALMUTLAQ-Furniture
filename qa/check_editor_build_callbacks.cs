// Execute the real BuildFromEditor callback code with a small Unity API test double.
// This checks orchestration only; it does not compile Unity/PICO or package Android.
using System;
using System.IO;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.TestTools.TestRunner.Api;

namespace UnityEngine {
    public class Object { public static void DestroyImmediate(Object value) { } }
    public class ScriptableObject : Object {
        public static T CreateInstance<T>() where T : new() { return new T(); }
    }
    public static class Application { public static string dataPath; }
    public static class Debug {
        public static void Log(string value) { }
        public static void LogError(string value) { }
    }
}
namespace UnityEditor {
    public class MenuItem : Attribute { public MenuItem(string value) { } }
    public enum BuildTarget { Android }
    public static class EditorUserBuildSettings { public static BuildTarget activeBuildTarget; }
    public static class EditorApplication {
        public static bool isCompiling, isPlayingOrWillChangePlaymode;
        public static Action delayCall;
        public static void Flush() { var pending = delayCall; delayCall = null; if (pending != null) pending(); }
    }
    public static class EditorUtility { public static void RevealInFinder(string path) { } }
}
namespace UnityEditor.Build {
    public class BuildFailedException : Exception { public BuildFailedException(string value) : base(value) { } }
}
namespace UnityEditor.SceneManagement {
    public static class EditorSceneManager { public static bool SaveCurrentModifiedScenesIfUserWantsTo() { return true; } }
}
namespace UnityEditor.TestTools.TestRunner.Api {
    public enum TestMode { EditMode }
    public class Filter { public TestMode testMode; public string[] assemblyNames; }
    public class ExecutionSettings { public ExecutionSettings(Filter filter) { } }
    public interface ITestAdaptor {
        string Id { get; }
        string Name { get; }
        bool IsTestAssembly { get; }
        IEnumerable<ITestAdaptor> Children { get; }
    }
    public interface ITestResultAdaptor {
        ITestAdaptor Test { get; }
        string ResultState { get; }
        int PassCount { get; }
        int FailCount { get; }
    }
    public interface IErrorCallbacks {
        void RunStarted(ITestAdaptor value);
        void RunFinished(ITestResultAdaptor value);
        void TestStarted(ITestAdaptor value);
        void TestFinished(ITestResultAdaptor value);
        void OnError(string value);
    }
    public class TestRunnerApi : UnityEngine.ScriptableObject {
        public static IErrorCallbacks Current;
        public static int Reports;
        public void RegisterCallbacks(IErrorCallbacks value) { Current = value; }
        public void UnregisterCallbacks(IErrorCallbacks value) { if (Current == value) Current = null; }
        public void Execute(ExecutionSettings settings) { }
        public static void SaveResultToFile(ITestResultAdaptor value, string path) { Reports++; File.WriteAllText(path, "synthetic"); }
    }
}
public static class BuildShowroom {
    public static int Calls;
    public static bool Fail;
    public static void Android() {
        Calls++;
        if (Fail) throw new InvalidOperationException("synthetic build failure");
        File.WriteAllText(Environment.GetEnvironmentVariable("SHOWROOM_APK_OUTPUT"), "synthetic apk");
    }
}
class TestTree : ITestAdaptor {
    public string Id { get; set; }
    public string Name { get; set; }
    public bool IsTestAssembly { get; set; }
    public IEnumerable<ITestAdaptor> Children { get; set; }
    public static TestTree Root(string id, string assembly = "Almutlaq.Showroom.Tests") {
        return new TestTree { Id = id, Name = "root", Children = new[] {
            new TestTree { Id = id + "-assembly", Name = assembly, IsTestAssembly = true, Children = new ITestAdaptor[0] }
        } };
    }
}
class TestResult : ITestResultAdaptor {
    public ITestAdaptor Test { get; set; }
    public string ResultState { get; set; }
    public int PassCount { get; set; }
    public int FailCount { get; set; }
    public static TestResult Passed(ITestAdaptor test) {
        return new TestResult { Test = test, ResultState = "Passed", PassCount = 2 };
    }
}
class CallbackChecks {
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static IErrorCallbacks Start() { BuildFromEditor.StartBuild(); return TestRunnerApi.Current; }
    static void Main(string[] args) {
        var temporary = Path.Combine(Path.GetTempPath(), "almutlaq-callback-" + Guid.NewGuid().ToString("N"));
        var previousDirectory = Directory.GetCurrentDirectory();
        var previousOutput = Environment.GetEnvironmentVariable("SHOWROOM_APK_OUTPUT");
        Directory.CreateDirectory(Path.Combine(temporary, "unity/Assets/Resources/Models"));
        try {
            Directory.SetCurrentDirectory(Path.Combine(temporary, "unity"));
            UnityEngine.Application.dataPath = Path.Combine(temporary, "unity/Assets");
            foreach (var sku in new[] { "10_14_3", "6_14_5" })
                File.WriteAllText("Assets/Resources/Models/london-" + sku + ".json", "{}");
            Environment.SetEnvironmentVariable("SHOWROOM_APK_OUTPUT", "TEST previous output");
            var own = TestTree.Root("own");
            var other = TestTree.Root("other", "Unrelated.Tests");
            var listener = Start();
            listener.RunStarted(other);
            listener.RunFinished(TestResult.Passed(other));
            Check(TestRunnerApi.Current == listener, "Unrelated completion cancelled pending build");
            listener.RunStarted(own);
            listener.RunStarted(TestTree.Root("other-showroom"));
            listener.RunFinished(TestResult.Passed(other));
            listener.RunFinished(null);
            Check(TestRunnerApi.Current == listener && EditorApplication.delayCall == null, "Wrong results changed ownership");
            listener.RunFinished(TestResult.Passed(own));
            listener.RunFinished(TestResult.Passed(own));
            Check(TestRunnerApi.Reports == 1 && EditorApplication.delayCall.GetInvocationList().Length == 1, "Duplicate completion queued extra build");
            EditorApplication.Flush();
            Check(BuildShowroom.Calls == 1 && TestRunnerApi.Current == null, "Successful build did not clean up");
            var final = Path.Combine(temporary, "builds/ShowroomVR-Linked.apk");
            Check(File.ReadAllText(final) == "synthetic apk", "Fresh output not promoted");
            Check(Environment.GetEnvironmentVariable("SHOWROOM_APK_OUTPUT") == "TEST previous output", "Output environment not restored");

            listener = Start();
            listener.RunStarted(own);
            listener.RunFinished(new TestResult { Test = own, ResultState = "Failed", PassCount = 1, FailCount = 1 });
            Check(EditorApplication.delayCall == null && TestRunnerApi.Current == null, "Failed tests queued a build");
            listener = Start();
            listener.RunStarted(own);
            listener.RunFinished(new TestResult { Test = own, ResultState = "Passed", PassCount = 0 });
            Check(EditorApplication.delayCall == null && TestRunnerApi.Current == null, "Zero tests queued a build");

            listener = Start();
            listener.RunStarted(own);
            listener.RunFinished(TestResult.Passed(own));
            listener.OnError("synthetic cancellation");
            Check(EditorApplication.delayCall == null && TestRunnerApi.Current == null, "Cleanup left a delayed build");
            var stale = listener;
            listener = Start();
            stale.OnError("stale callback");
            stale.RunFinished(TestResult.Passed(own));
            Check(TestRunnerApi.Current == listener, "Stale callback cancelled new build");
            listener.RunStarted(own);
            listener.RunFinished(TestResult.Passed(own));
            BuildShowroom.Fail = true;
            bool failed = false;
            try { EditorApplication.Flush(); } catch (InvalidOperationException) { failed = true; }
            Check(failed && TestRunnerApi.Current == null, "Packaging failure did not clean up");
            Check(File.ReadAllText(final) == "synthetic apk", "Failed build overwrote last artifact");
            Check(Environment.GetEnvironmentVariable("SHOWROOM_APK_OUTPUT") == "TEST previous output", "Failure leaked output environment");
            BuildShowroom.Fail = false;
            listener = Start();
            listener.OnError("test end");
            Console.WriteLine("EDITOR_BUILD_CALLBACK_CHECK_PASSED (Unity API doubles, no device build)");
        }
        finally {
            Directory.SetCurrentDirectory(previousDirectory);
            Environment.SetEnvironmentVariable("SHOWROOM_APK_OUTPUT", previousOutput);
            Directory.Delete(temporary, true);
        }
    }
}
