#!/usr/bin/env python3
"""Generates ZIKR.xcodeproj (Xcode 16+ format with file-system synchronized folders).

Folders are synchronized, so adding or removing Swift files never requires editing the project.
Run again only when targets or build settings change:  python3 tools/gen_project.py
"""
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJ = ROOT / "ZIKR.xcodeproj"


def oid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def q(value) -> str:
    if isinstance(value, list):
        return "(\n" + "".join(f"\t\t\t\t\t{q(v)},\n" for v in value) + "\t\t\t\t)"
    s = str(value)
    if s and all(c.isalnum() or c in "._/" for c in s) and not s.startswith("/"):
        return s
    return '"' + s.replace('"', '\\"') + '"'


def settings(d: dict) -> str:
    return "".join(f"\t\t\t\t{k} = {q(v)};\n" for k, v in sorted(d.items()))


COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "MARKETING_VERSION": "1.0.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "ZIKR_BUNDLE_ID": "com.example.zikr",
    "ZIKR_PRIVACY_URL": "",
    "ZIKR_SUPPORT_URL": "",
}
PROJECT_DEBUG = {**COMMON,
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}
PROJECT_RELEASE = {**COMMON,
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
}
PLATFORM = {
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
}
APP = {**PLATFORM,
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/ZIKR.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Config/ZIKR-Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "$(ZIKR_BUNDLE_ID)",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
WIDGETS = {**PLATFORM,
    "CODE_SIGN_ENTITLEMENTS": "Config/ZIKRWidgets.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Config/ZIKRWidgets-Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "$(ZIKR_BUNDLE_ID).widgets",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
TESTS = {**PLATFORM,
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(ZIKR_BUNDLE_ID).tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ZIKR.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ZIKR",
}

I = {k: oid(k) for k in [
    "project", "main", "products", "g.ZIKR", "g.Shared", "g.ZIKRWidgets", "g.ZIKRTests", "g.Config",
    "p.app", "p.widgets", "p.tests", "t.app", "t.widgets", "t.tests",
    "src.app", "fw.app", "res.app", "embed.app", "src.widgets", "fw.widgets", "res.widgets",
    "src.tests", "fw.tests", "res.tests", "bf.embed", "proxy.widgets", "proxy.app", "dep.widgets", "dep.app",
    "cl.project", "cl.app", "cl.widgets", "cl.tests",
    "c.project.d", "c.project.r", "c.app.d", "c.app.r", "c.widgets.d", "c.widgets.r", "c.tests.d", "c.tests.r",
]}


def group(key, path):
    return f"""\t\t{I[key]} /* {path} */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = {path};
\t\t\tsourceTree = "<group>";
\t\t}};
"""


def phase(key, isa, files=""):
    return f"""\t\t{I[key]} = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""


def target(key, name, phases, deps, groups, product, ptype, cl):
    return f"""\t\t{I[key]} /* {name} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I[cl]};
\t\t\tbuildPhases = (
{''.join(f"				{I[p]},\n" for p in phases)}\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
{''.join(f"				{I[d]},\n" for d in deps)}\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
{''.join(f"				{I[g]},\n" for g in groups)}\t\t\t);
\t\t\tname = {name};
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = {name};
\t\t\tproductReference = {I[product]};
\t\t\tproductType = "{ptype}";
\t\t}};
"""


def config(key, name, values):
    return f"""\t\t{I[key]} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings(values)}\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""


def config_list(key, d, r):
    return f"""\t\t{I[key]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I[d]},
\t\t\t\t{I[r]},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""


def pbxproj() -> str:
    o = []
    o.append("/* Begin PBXBuildFile section */\n")
    o.append(f"\t\t{I['bf.embed']} /* ZIKRWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['p.widgets']}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    o.append("/* End PBXBuildFile section */\n\n/* Begin PBXContainerItemProxy section */\n")
    for key, tgt, name in (("proxy.widgets", "t.widgets", "ZIKRWidgets"), ("proxy.app", "t.app", "ZIKR")):
        o.append(f"""\t\t{I[key]} = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['project']};
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I[tgt]};
\t\t\tremoteInfo = {name};
\t\t}};
""")
    o.append("/* End PBXContainerItemProxy section */\n\n/* Begin PBXCopyFilesBuildPhase section */\n")
    o.append(f"""\t\t{I['embed.app']} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{I['bf.embed']},
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")
    o.append("/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXFileReference section */\n")
    o.append(f"\t\t{I['p.app']} /* ZIKR.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ZIKR.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    o.append(f"\t\t{I['p.widgets']} /* ZIKRWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ZIKRWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    o.append(f"\t\t{I['p.tests']} /* ZIKRTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ZIKRTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    o.append("/* End PBXFileReference section */\n\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    for name in ("ZIKR", "Shared", "ZIKRWidgets", "ZIKRTests", "Config"):
        o.append(group(f"g.{name}", name))
    o.append("/* End PBXFileSystemSynchronizedRootGroup section */\n\n/* Begin PBXFrameworksBuildPhase section */\n")
    for t in ("app", "widgets", "tests"):
        o.append(phase(f"fw.{t}", "PBXFrameworksBuildPhase"))
    o.append("/* End PBXFrameworksBuildPhase section */\n\n/* Begin PBXGroup section */\n")
    o.append(f"""\t\t{I['main']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['g.ZIKR']},
\t\t\t\t{I['g.Shared']},
\t\t\t\t{I['g.ZIKRWidgets']},
\t\t\t\t{I['g.ZIKRTests']},
\t\t\t\t{I['g.Config']},
\t\t\t\t{I['products']},
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['products']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['p.app']},
\t\t\t\t{I['p.widgets']},
\t\t\t\t{I['p.tests']},
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
""")
    o.append("/* End PBXGroup section */\n\n/* Begin PBXNativeTarget section */\n")
    o.append(target("t.app", "ZIKR", ["src.app", "fw.app", "res.app", "embed.app"], ["dep.widgets"],
                    ["g.ZIKR", "g.Shared"], "p.app", "com.apple.product-type.application", "cl.app"))
    o.append(target("t.widgets", "ZIKRWidgets", ["src.widgets", "fw.widgets", "res.widgets"], [],
                    ["g.ZIKRWidgets", "g.Shared"], "p.widgets", "com.apple.product-type.app-extension", "cl.widgets"))
    o.append(target("t.tests", "ZIKRTests", ["src.tests", "fw.tests", "res.tests"], ["dep.app"],
                    ["g.ZIKRTests"], "p.tests", "com.apple.product-type.bundle.unit-test", "cl.tests"))
    o.append("/* End PBXNativeTarget section */\n\n/* Begin PBXProject section */\n")
    o.append(f"""\t\t{I['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{I['t.app']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['t.widgets']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['t.tests']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tTestTargetID = {I['t.app']};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['cl.project']};
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\tru,
\t\t\t\tuz,
\t\t\t\t"uz-Cyrl",
\t\t\t);
\t\t\tmainGroup = {I['main']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I['products']};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['t.app']},
\t\t\t\t{I['t.widgets']},
\t\t\t\t{I['t.tests']},
\t\t\t);
\t\t}};
""")
    o.append("/* End PBXProject section */\n\n/* Begin PBXResourcesBuildPhase section */\n")
    for t in ("app", "widgets", "tests"):
        o.append(phase(f"res.{t}", "PBXResourcesBuildPhase"))
    o.append("/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */\n")
    for t in ("app", "widgets", "tests"):
        o.append(phase(f"src.{t}", "PBXSourcesBuildPhase"))
    o.append("/* End PBXSourcesBuildPhase section */\n\n/* Begin PBXTargetDependency section */\n")
    for key, tgt, proxy in (("dep.widgets", "t.widgets", "proxy.widgets"), ("dep.app", "t.app", "proxy.app")):
        o.append(f"""\t\t{I[key]} = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {I[tgt]};
\t\t\ttargetProxy = {I[proxy]};
\t\t}};
""")
    o.append("/* End PBXTargetDependency section */\n\n/* Begin XCBuildConfiguration section */\n")
    o.append(config("c.project.d", "Debug", PROJECT_DEBUG))
    o.append(config("c.project.r", "Release", PROJECT_RELEASE))
    for t, values in (("app", APP), ("widgets", WIDGETS), ("tests", TESTS)):
        o.append(config(f"c.{t}.d", "Debug", values))
        o.append(config(f"c.{t}.r", "Release", values))
    o.append("/* End XCBuildConfiguration section */\n\n/* Begin XCConfigurationList section */\n")
    o.append(config_list("cl.project", "c.project.d", "c.project.r"))
    for t in ("app", "widgets", "tests"):
        o.append(config_list(f"cl.{t}", f"c.{t}.d", f"c.{t}.r"))
    o.append("/* End XCConfigurationList section */\n")
    body = "".join(o)
    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

{body}\t}};
\trootObject = {I['project']} /* Project object */;
}}
"""


def scheme() -> str:
    def ref(t, product, name):
        return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I[t]}" '
                f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:ZIKR.xcodeproj"></BuildableReference>')
    app = ref("t.app", "ZIKR.app", "ZIKR")
    tests = ref("t.tests", "ZIKRTests.xctest", "ZIKRTests")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "YES">
            {tests}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "NO">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main():
    (PROJ / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (PROJ / "project.pbxproj").write_text(pbxproj(), encoding="utf-8")
    (PROJ / "xcshareddata" / "xcschemes" / "ZIKR.xcscheme").write_text(scheme(), encoding="utf-8")
    print("ZIKR.xcodeproj generated")


if __name__ == "__main__":
    main()
