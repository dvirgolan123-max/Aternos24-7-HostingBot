#!/usr/bin/env python3
"""Generates Ashvale.xcodeproj (one iOS app target, automatic signing) from the
files under Ashvale/. Re-run after adding or removing source files:

    python3 Tools/xcodegen/generate_project.py
"""
import hashlib, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "Ashvale")
PROJ = os.path.join(ROOT, "Ashvale.xcodeproj")
NAME = "Ashvale"
BUNDLE_ID = "com.dvirgolan123.ashvale"
DEPLOYMENT = "16.0"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(s):
    """Quotes a value for the OpenStep plist format when needed."""
    if s and all(c.isalnum() or c in "._/$" for c in s) and not s.startswith("$("):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".metal": "sourcecode.metal",
    ".plist": "text.plist.xml",
    ".xcassets": "folder.assetcatalog",
}

# Collect the tree (folders become groups; .xcassets is a leaf).
def scan(rel):
    full = os.path.join(SRC, rel) if rel else SRC
    groups, files = [], []
    for name in sorted(os.listdir(full)):
        if name.startswith("."):
            continue
        p = os.path.join(full, name)
        r = os.path.join(rel, name) if rel else name
        if os.path.isdir(p) and not name.endswith(".xcassets"):
            groups.append((name, r))
        elif os.path.splitext(name)[1] in FILE_TYPES:
            files.append((name, r))
    return groups, files

objects = {}
group_children = {}
sources, resources = [], []
file_refs = {}

def build_group(rel, name):
    gid = oid("group", rel or "<root>")
    groups, files = scan(rel)
    children = []
    for gname, grel in groups:
        children.append(build_group(grel, gname))
    for fname, frel in files:
        ext = os.path.splitext(fname)[1]
        fid = oid("file", frel)
        file_refs[frel] = fid
        objects[fid] = f"{{isa = PBXFileReference; lastKnownFileType = {FILE_TYPES[ext]}; path = {q(fname)}; sourceTree = \"<group>\"; }}"
        children.append(fid)
        if ext in (".swift", ".metal"):
            bid = oid("build", frel)
            objects[bid] = f"{{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }}"
            sources.append((bid, fname))
        elif ext == ".xcassets":
            bid = oid("build", frel)
            objects[bid] = f"{{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }}"
            resources.append((bid, fname))
    path = f"path = {q(name)}; " if name else ""
    objects[gid] = ("{isa = PBXGroup; children = (" + ", ".join(children) + "); " + path + "sourceTree = \"<group>\"; }")
    return gid

app_group = build_group("", NAME)
product_ref = oid("product")
objects[product_ref] = f"{{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }}"
products_group = oid("group", "Products")
objects[products_group] = f"{{isa = PBXGroup; children = ({product_ref}); name = Products; sourceTree = \"<group>\"; }}"
main_group = oid("group", "main")
objects[main_group] = f"{{isa = PBXGroup; children = ({app_group}, {products_group}); sourceTree = \"<group>\"; }}"

src_phase, fw_phase, res_phase = oid("phase", "sources"), oid("phase", "frameworks"), oid("phase", "resources")
objects[src_phase] = ("{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ("
                      + ", ".join(f"{b} /* {n} in Sources */" for b, n in sources) + "); runOnlyForDeploymentPostprocessing = 0; }")
objects[fw_phase] = "{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }"
objects[res_phase] = ("{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ("
                      + ", ".join(f"{b} /* {n} in Resources */" for b, n in resources) + "); runOnlyForDeploymentPostprocessing = 0; }")

def settings(d):
    return "{" + " ".join(f"{k} = {v};" for k, v in d.items()) + "}"

def lst(*items):
    return "(" + ", ".join(q(i) for i in items) + ")"

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": lst("DEBUG=1", "$(inherited)"),
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    # World generation and the simulation are heavy; keep Debug builds optimized so the game stays playable.
    "SWIFT_OPTIMIZATION_LEVEL": q("-O"),
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": q("dwarf-with-dsym"),
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": q("-O"),
    "VALIDATE_PRODUCT": "YES",
})
target_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": q(""),
    "ENABLE_PREVIEWS": "NO",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Ashvale/App/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
    "LD_RUNPATH_SEARCH_PATHS": lst("$(inherited)", "@executable_path/Frameworks"),
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": q("$(TARGET_NAME)"),
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": q("iphoneos iphonesimulator"),
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}

cfg = {}
for scope, variants in (("project", (project_debug, project_release)), ("target", (target_common, target_common))):
    ids = []
    for conf, s in zip(("Debug", "Release"), variants):
        i = oid("config", scope, conf)
        objects[i] = f"{{isa = XCBuildConfiguration; buildSettings = {settings(s)}; name = {conf}; }}"
        ids.append(i)
    lid = oid("configlist", scope)
    objects[lid] = ("{isa = XCConfigurationList; buildConfigurations = (" + ", ".join(ids)
                    + "); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }")
    cfg[scope] = lid

target = oid("target", NAME)
objects[target] = (f"{{isa = PBXNativeTarget; buildConfigurationList = {cfg['target']}; buildPhases = ({src_phase}, {fw_phase}, {res_phase}); "
                   f"buildRules = (); dependencies = (); name = {NAME}; productName = {NAME}; productReference = {product_ref}; "
                   f"productType = \"com.apple.product-type.application\"; }}")
project = oid("project", NAME)
objects[project] = (f"{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; "
                    f"TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 15.0; }}; }}; }}; buildConfigurationList = {cfg['project']}; "
                    f"compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); "
                    f"mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({target}); }}")

lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for k in sorted(objects):
    lines.append(f"\t\t{k} = {objects[k]};")
lines += ["\t};", f"\trootObject = {project};", "}", ""]
os.makedirs(PROJ, exist_ok=True)
open(os.path.join(PROJ, "project.pbxproj"), "w").write("\n".join(lines))

ws = os.path.join(PROJ, "project.xcworkspace")
os.makedirs(ws, exist_ok=True)
open(os.path.join(ws, "contents.xcworkspacedata"), "w").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

schemes = os.path.join(PROJ, "xcshareddata", "xcschemes")
os.makedirs(schemes, exist_ok=True)
ref = (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" '
       f'BuildableName = "{NAME}.app" BlueprintName = "{NAME}" ReferencedContainer = "container:{NAME}.xcodeproj"></BuildableReference>')
open(os.path.join(schemes, f"{NAME}.xcscheme"), "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""")
print(f"Generated {PROJ}: {len(sources)} sources, {len(resources)} resources")
