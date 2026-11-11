"""Prepare generated Flutter platform projects without storing generated build output."""
from pathlib import Path
import plistlib
import shutil
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
target = sys.argv[1]

if target == "android":
    android = root / "android/app/src/main"
    manifest = android / "AndroidManifest.xml"
    ns = "http://schemas.android.com/apk/res/android"
    ET.register_namespace("android", ns)
    tree = ET.parse(manifest)
    element = tree.getroot()
    if not any(x.attrib.get(f"{{{ns}}}name") == "android.permission.INTERNET" for x in element.findall("uses-permission")):
        ET.SubElement(element, "uses-permission", {f"{{{ns}}}name": "android.permission.INTERNET"})
    app = element.find("application")
    app.set(f"{{{ns}}}label", "Almutlaq Furniture")
    app.set(f"{{{ns}}}networkSecurityConfig", "@xml/network_security_config")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    security = android / "res/xml/network_security_config.xml"
    security.parent.mkdir(parents=True, exist_ok=True)
    security.write_text("""<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false" />
  <domain-config cleartextTrafficPermitted="true">
    <domain>127.0.0.1</domain><domain>localhost</domain>
  </domain-config>
</network-security-config>
""", encoding="utf-8")
elif target == "ios":
    ios = root / "ios/Runner"
    source = ios / "AppDelegate.swift"
    text = source.read_text(encoding="utf-8")
    modern = "GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)"
    legacy = "GeneratedPluginRegistrant.register(with: self)"
    if "RoomScanPlugin.register" not in text:
        if modern in text:
            text = text.replace(modern, modern + """
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlmutlaqRoomScan") {
      RoomScanPlugin.register(with: registrar)
    }""")
        elif legacy in text:
            text = text.replace(legacy, legacy + """
    if let registrar = self.registrar(forPlugin: "AlmutlaqRoomScan") {
      RoomScanPlugin.register(with: registrar)
    }""")
        else:
            raise SystemExit("Unknown Flutter AppDelegate template. Review native plugin registration.")
        source.write_text(text, encoding="utf-8")
    shutil.copyfile(root / "native/ios/RoomScanPlugin.swift", ios / "RoomScanPlugin.swift")
    info = ios / "Info.plist"
    with info.open("rb") as file:
        value = plistlib.load(file)
    value["CFBundleDisplayName"] = "Almutlaq Furniture"
    value["NSCameraUsageDescription"] = "Scan your room to review its dimensions and plan furniture."
    value["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    with info.open("wb") as file:
        plistlib.dump(value, file)
else:
    raise SystemExit("Use android or ios")
