#!/usr/bin/env python3
"""Generates Hardset.xcodeproj.

Hand-written rather than Tuist/XcodeGen (no extra tooling, per the project decisions), but
generated from a script rather than typed so it is reproducible and reviewable in a diff.

Regenerate with:  python3 Tools/generate_project.py
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Deterministic 24-hex-char object IDs, so regenerating produces an identical file.
_used = {}
def oid(name):
    if name in _used: return _used[name]
    h = 0xCAFE
    for ch in name: h = (h * 131 + ord(ch)) & 0xFFFFFFFFFFFFFFFFFFFFFFFF
    v = f"{h:024X}"
    assert v not in _used.values(), f"id collision for {name}"
    _used[name] = v
    return v

BUNDLE_ID = "com.hardset.app"
IOS_MIN = "26.1"
SWIFT_VERSION = "6.0"

APP, WIDGET, TESTS = "Hardset", "HardsetWidget", "HardsetTests"

# (file name, group dir, target)
SOURCES = [
    ("HardsetApp.swift", "Hardset", APP),
    ("HardsetWidgetBundle.swift", "HardsetWidget", WIDGET),
    ("AppSmokeTests.swift", "HardsetTests", TESTS),
]
RESOURCES = [
    ("PrivacyInfo.xcprivacy", "Hardset", APP),
    ("Assets.xcassets", "Hardset", APP),
]

def build_settings(target):
    """Shared settings. The concurrency trio is set from commit 1 on every target --
    retrofitting strict concurrency later is a rewrite."""
    s = {
        "SWIFT_VERSION": SWIFT_VERSION,
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "IPHONEOS_DEPLOYMENT_TARGET": IOS_MIN,
        "SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
    }
    if target == APP:
        s.update({
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
            "PRODUCT_NAME": "Hardset",
            "INFOPLIST_FILE": "Hardset/Info.plist",
            "CODE_SIGN_ENTITLEMENTS": "Hardset/Hardset.entitlements",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ENABLE_PREVIEWS": "YES",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        })
    elif target == WIDGET:
        s.update({
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.widget",
            "PRODUCT_NAME": "HardsetWidget",
            "INFOPLIST_FILE": "HardsetWidget/Info.plist",
            "SKIP_INSTALL": "YES",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
        })
    else:
        s.update({
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
            "PRODUCT_NAME": "HardsetTests",
            "GENERATE_INFOPLIST_FILE": "YES",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/Hardset.app/$(BUNDLED_BINARY_NAME_PREFIX)Hardset"',
            "BUNDLE_LOADER": '"$(TEST_HOST)"',
        })
    return s

def fmt_settings(d, indent):
    pad = "\t" * indent
    return "".join(f"{pad}{k} = {v};\n" for k, v in sorted(d.items()))

# Package products each target links.
PRODUCTS = {
    APP: ["HardsetCore", "HardsetStore", "HardsetUI", "HardsetAlarm", "HardsetFeature"],
    WIDGET: ["HardsetCore", "HardsetUI", "HardsetAlarm"],
    TESTS: ["HardsetCore"],
}

L = []
w = L.append
w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {\n\t};")
w("\tobjectVersion = 60;")
w("\tobjects = {\n")

# ---- PBXBuildFile ----
w("/* Begin PBXBuildFile section */")
for fname, group, target in SOURCES + RESOURCES:
    w(f"\t\t{oid('bf_'+target+fname)} /* {fname} in {target} */ = {{isa = PBXBuildFile; fileRef = {oid('fr_'+group+fname)} /* {fname} */; }};")
for target, prods in PRODUCTS.items():
    for p in prods:
        w(f"\t\t{oid('bfp_'+target+p)} /* {p} */ = {{isa = PBXBuildFile; productRef = {oid('pd_'+target+p)} /* {p} */; }};")
w(f"\t\t{oid('bf_embed_widget')} /* HardsetWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {oid('prod_'+WIDGET)} /* HardsetWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
w("/* End PBXBuildFile section */\n")

# ---- PBXContainerItemProxy (target deps) ----
w("/* Begin PBXContainerItemProxy section */")
for dep, name in ((WIDGET, "HardsetWidget"), (APP, "Hardset")):
    w(f"\t\t{oid('proxy_'+dep)} /* PBXContainerItemProxy */ = {{")
    w("\t\t\tisa = PBXContainerItemProxy;")
    w(f"\t\t\tcontainerPortal = {oid('project')} /* Project object */;")
    w("\t\t\tproxyType = 1;")
    w(f"\t\t\tremoteGlobalIDString = {oid('target_'+dep)};")
    w(f"\t\t\tremoteInfo = {name};")
    w("\t\t};")
w("/* End PBXContainerItemProxy section */\n")

# ---- PBXCopyFilesBuildPhase (embed the extension) ----
w("/* Begin PBXCopyFilesBuildPhase section */")
w(f"\t\t{oid('embed_phase')} /* Embed Foundation Extensions */ = {{")
w("\t\t\tisa = PBXCopyFilesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w('\t\t\tdstPath = "";')
w("\t\t\tdstSubfolderSpec = 13;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{oid('bf_embed_widget')} /* HardsetWidget.appex in Embed Foundation Extensions */,")
w("\t\t\t);")
w("\t\t\tname = \"Embed Foundation Extensions\";")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXCopyFilesBuildPhase section */\n")

# ---- PBXFileReference ----
w("/* Begin PBXFileReference section */")
seen = set()
for fname, group, target in SOURCES + RESOURCES:
    key = group + fname
    if key in seen: continue
    seen.add(key)
    if fname.endswith(".swift"): ftype = "sourcecode.swift"
    elif fname.endswith(".xcassets"): ftype = "folder.assetcatalog"
    else: ftype = "text.plist.xml"
    w(f"\t\t{oid('fr_'+key)} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {fname}; sourceTree = \"<group>\"; }};")
for fname, group in (("Info.plist", "Hardset"), ("Hardset.entitlements", "Hardset"), ("Info.plist", "HardsetWidget")):
    key = group + fname
    if key in seen: continue
    seen.add(key)
    t = "text.plist.entitlements" if fname.endswith("entitlements") else "text.plist.xml"
    w(f"\t\t{oid('fr_'+key)} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {fname}; sourceTree = \"<group>\"; }};")
w(f"\t\t{oid('prod_'+APP)} /* Hardset.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Hardset.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{oid('prod_'+WIDGET)} /* HardsetWidget.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = HardsetWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{oid('prod_'+TESTS)} /* HardsetTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = HardsetTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
w("/* End PBXFileReference section */\n")

# ---- XCLocalSwiftPackageReference ----
w("/* Begin XCLocalSwiftPackageReference section */")
w(f"\t\t{oid('localpkg')} /* XCLocalSwiftPackageReference \"Packages/HardsetKit\" */ = {{")
w("\t\t\tisa = XCLocalSwiftPackageReference;")
w("\t\t\trelativePath = Packages/HardsetKit;")
w("\t\t};")
w("/* End XCLocalSwiftPackageReference section */\n")

# ---- XCSwiftPackageProductDependency ----
w("/* Begin XCSwiftPackageProductDependency section */")
for target, prods in PRODUCTS.items():
    for p in prods:
        w(f"\t\t{oid('pd_'+target+p)} /* {p} */ = {{")
        w("\t\t\tisa = XCSwiftPackageProductDependency;")
        w(f"\t\t\tproductName = {p};")
        w("\t\t};")
w("/* End XCSwiftPackageProductDependency section */\n")

# ---- PBXFrameworksBuildPhase ----
w("/* Begin PBXFrameworksBuildPhase section */")
for target in (APP, WIDGET, TESTS):
    w(f"\t\t{oid('fw_'+target)} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for p in PRODUCTS[target]:
        w(f"\t\t\t\t{oid('bfp_'+target+p)} /* {p} */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */\n")

# ---- PBXGroup ----
w("/* Begin PBXGroup section */")
w(f"\t\t{oid('grp_root')} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for g in ("Hardset", "HardsetWidget", "HardsetTests"):
    w(f"\t\t\t\t{oid('grp_'+g)} /* {g} */,")
w(f"\t\t\t\t{oid('grp_products')} /* Products */,")
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
group_children = {
    "Hardset": ["HardsetApp.swift", "Assets.xcassets", "Info.plist", "Hardset.entitlements", "PrivacyInfo.xcprivacy"],
    "HardsetWidget": ["HardsetWidgetBundle.swift", "Info.plist"],
    "HardsetTests": ["AppSmokeTests.swift"],
}
for g, children in group_children.items():
    w(f"\t\t{oid('grp_'+g)} /* {g} */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for c in children:
        w(f"\t\t\t\t{oid('fr_'+g+c)} /* {c} */,")
    w("\t\t\t);")
    w(f"\t\t\tpath = {g};")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
w(f"\t\t{oid('grp_products')} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for t, prod in ((APP, "Hardset.app"), (WIDGET, "HardsetWidget.appex"), (TESTS, "HardsetTests.xctest")):
    w(f"\t\t\t\t{oid('prod_'+t)} /* {prod} */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */\n")

# ---- PBXNativeTarget ----
w("/* Begin PBXNativeTarget section */")
meta = {
    APP: ("Hardset", "com.apple.product-type.application", "Hardset.app", oid('prod_'+APP)),
    WIDGET: ("HardsetWidget", "com.apple.product-type.app-extension", "HardsetWidget.appex", oid('prod_'+WIDGET)),
    TESTS: ("HardsetTests", "com.apple.product-type.bundle.unit-test", "HardsetTests.xctest", oid('prod_'+TESTS)),
}
for target in (APP, WIDGET, TESTS):
    name, ptype, pref, prodid = meta[target]
    w(f"\t\t{oid('target_'+target)} /* {name} */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {oid('cfglist_'+target)};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{oid('src_'+target)} /* Sources */,")
    w(f"\t\t\t\t{oid('fw_'+target)} /* Frameworks */,")
    w(f"\t\t\t\t{oid('res_'+target)} /* Resources */,")
    if target == APP:
        w(f"\t\t\t\t{oid('embed_phase')} /* Embed Foundation Extensions */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (\n\t\t\t);")
    w("\t\t\tdependencies = (")
    if target == APP:
        w(f"\t\t\t\t{oid('dep_'+WIDGET)} /* PBXTargetDependency */,")
    if target == TESTS:
        w(f"\t\t\t\t{oid('dep_'+APP)} /* PBXTargetDependency */,")
    w("\t\t\t);")
    w(f"\t\t\tname = {name};")
    w("\t\t\tpackageProductDependencies = (")
    for p in PRODUCTS[target]:
        w(f"\t\t\t\t{oid('pd_'+target+p)} /* {p} */,")
    w("\t\t\t);")
    w(f"\t\t\tproductName = {name};")
    w(f"\t\t\tproductReference = {prodid} /* {pref} */;")
    w(f"\t\t\tproductType = \"{ptype}\";")
    w("\t\t};")
w("/* End PBXNativeTarget section */\n")

# ---- PBXProject ----
w("/* Begin PBXProject section */")
w(f"\t\t{oid('project')} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 2640;")
w("\t\t\t\tLastUpgradeCheck = 2640;")
w("\t\t\t\tTargetAttributes = {")
for target in (APP, WIDGET, TESTS):
    w(f"\t\t\t\t\t{oid('target_'+target)} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;\n\t\t\t\t\t}};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {oid('cfglist_project')};")
w('\t\t\tcompatibilityVersion = "Xcode 15.0";')
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
w(f"\t\t\tmainGroup = {oid('grp_root')};")
w("\t\t\tpackageReferences = (")
w(f"\t\t\t\t{oid('localpkg')} /* XCLocalSwiftPackageReference \"Packages/HardsetKit\" */,")
w("\t\t\t);")
w(f"\t\t\tproductRefGroup = {oid('grp_products')} /* Products */;")
w('\t\t\tprojectDirPath = "";')
w('\t\t\tprojectRoot = "";')
w("\t\t\ttargets = (")
for target in (APP, WIDGET, TESTS):
    w(f"\t\t\t\t{oid('target_'+target)} /* {meta[target][0]} */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */\n")

# ---- PBXResourcesBuildPhase ----
w("/* Begin PBXResourcesBuildPhase section */")
for target in (APP, WIDGET, TESTS):
    w(f"\t\t{oid('res_'+target)} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for fname, group, t in RESOURCES:
        if t == target:
            w(f"\t\t\t\t{oid('bf_'+t+fname)} /* {fname} in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXResourcesBuildPhase section */\n")

# ---- PBXSourcesBuildPhase ----
w("/* Begin PBXSourcesBuildPhase section */")
for target in (APP, WIDGET, TESTS):
    w(f"\t\t{oid('src_'+target)} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for fname, group, t in SOURCES:
        if t == target:
            w(f"\t\t\t\t{oid('bf_'+t+fname)} /* {fname} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXSourcesBuildPhase section */\n")

# ---- PBXTargetDependency ----
w("/* Begin PBXTargetDependency section */")
for dep in (WIDGET, APP):
    w(f"\t\t{oid('dep_'+dep)} /* PBXTargetDependency */ = {{")
    w("\t\t\tisa = PBXTargetDependency;")
    w(f"\t\t\ttarget = {oid('target_'+dep)} /* {meta[dep][0]} */;")
    w(f"\t\t\ttargetProxy = {oid('proxy_'+dep)} /* PBXContainerItemProxy */;")
    w("\t\t};")
w("/* End PBXTargetDependency section */\n")

# ---- XCBuildConfiguration ----
w("/* Begin XCBuildConfiguration section */")
PROJECT_BASE = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": IOS_MIN,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": SWIFT_VERSION,
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}
for cfg in ("Debug", "Release"):
    w(f"\t\t{oid('cfg_project_'+cfg)} /* {cfg} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    s = dict(PROJECT_BASE)
    if cfg == "Debug":
        s.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                  "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES",
                  "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
                  "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"})
    else:
        s.update({"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
                  "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
    w(fmt_settings(s, 4), )
    w("\t\t\t};")
    w(f"\t\t\tname = {cfg};")
    w("\t\t};")
for target in (APP, WIDGET, TESTS):
    for cfg in ("Debug", "Release"):
        w(f"\t\t{oid('cfg_'+target+cfg)} /* {cfg} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        w(fmt_settings(build_settings(target), 4))
        w("\t\t\t};")
        w(f"\t\t\tname = {cfg};")
        w("\t\t};")
w("/* End XCBuildConfiguration section */\n")

# ---- XCConfigurationList ----
w("/* Begin XCConfigurationList section */")
for key in ("project", APP, WIDGET, TESTS):
    w(f"\t\t{oid('cfglist_'+key)} = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    for cfg in ("Debug", "Release"):
        name = f"cfg_project_{cfg}" if key == "project" else f"cfg_{key}{cfg}"
        w(f"\t\t\t\t{oid(name)} /* {cfg} */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
w("/* End XCConfigurationList section */\n")

w("\t};")
w(f"\trootObject = {oid('project')} /* Project object */;")
w("}")

proj = os.path.join(ROOT, "Hardset.xcodeproj")
os.makedirs(proj, exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write("\n".join(L) + "\n")

# Shared scheme so `xcodebuild -scheme Hardset` works from a clean checkout.
sd = os.path.join(proj, "xcshareddata", "xcschemes")
os.makedirs(sd, exist_ok=True)
with open(os.path.join(sd, "Hardset.xcscheme"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid('target_'+APP)}"
               BuildableName="Hardset.app" BlueprintName="Hardset" ReferencedContainer="container:Hardset.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid('target_'+TESTS)}"
               BuildableName="HardsetTests.xctest" BlueprintName="HardsetTests" ReferencedContainer="container:Hardset.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0"
      useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"
      debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid('target_'+APP)}"
            BuildableName="Hardset.app" BlueprintName="Hardset" ReferencedContainer="container:Hardset.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier=""
      useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid('target_'+APP)}"
            BuildableName="Hardset.app" BlueprintName="Hardset" ReferencedContainer="container:Hardset.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("generated", proj)
