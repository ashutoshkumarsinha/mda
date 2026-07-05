#!/usr/bin/env python3
"""Adds Share, Widget, and Watch extension targets to mde.xcodeproj."""

from pathlib import Path

PBX = Path(__file__).resolve().parents[1] / "mde.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

if "mdeShareExtension" in text:
    print("Extension targets already present.")
    raise SystemExit(0)

ADDITIONS = {
    "file_refs": """
\t\tA1D001010001 /* mdeShareExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = mdeShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
\t\tA1D001020001 /* mdeWidgetExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = mdeWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
\t\tA1D001030001 /* mdeWatchApp.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = mdeWatchApp.app; sourceTree = BUILT_PRODUCTS_DIR; };
""",
    "exceptions": """
/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section additions */
\t\tA1D001010002 /* Exceptions for "mdeShareExtension" folder in "mdeShareExtension" target */ = {
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tInfo.plist,
\t\t\t);
\t\t\ttarget = A1D001010003 /* mdeShareExtension */;
\t\t};
\t\tA1D001020002 /* Exceptions for "mdeWidgetExtension" folder in "mdeWidgetExtension" target */ = {
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tInfo.plist,
\t\t\t);
\t\t\ttarget = A1D001020003 /* mdeWidgetExtension */;
\t\t};
""",
    "sync_groups": """
\t\tA1D001010004 /* mdeShareExtension */ = {
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\texceptions = (
\t\t\t\tA1D001010002 /* Exceptions for "mdeShareExtension" folder in "mdeShareExtension" target */,
\t\t\t);
\t\t\tpath = mdeShareExtension;
\t\t\tsourceTree = "<group>";
\t\t};
\t\tA1D001020004 /* mdeWidgetExtension */ = {
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\texceptions = (
\t\t\t\tA1D001020002 /* Exceptions for "mdeWidgetExtension" folder in "mdeWidgetExtension" target */,
\t\t\t);
\t\t\tpath = mdeWidgetExtension;
\t\t\tsourceTree = "<group>";
\t\t};
\t\tA1D001030004 /* mdeWatchApp */ = {
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = mdeWatchApp;
\t\t\tsourceTree = "<group>";
\t\t};
""",
    "embed_phase": """
/* Begin PBXCopyFilesBuildPhase section */
\t\tA1D001010020 /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\tA1D001010021 /* mdeShareExtension.appex in Embed Foundation Extensions */,
\t\t\t\tA1D001020021 /* mdeWidgetExtension.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXCopyFilesBuildPhase section */
""",
    "build_files": """
\t\tA1D001010021 /* mdeShareExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = A1D001010001 /* mdeShareExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
\t\tA1D001020021 /* mdeWidgetExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = A1D001020001 /* mdeWidgetExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
""",
    "proxies": """
\t\tA1D001010030 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 027480F92FED070800B678AB /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = A1D001010003;
\t\t\tremoteInfo = mdeShareExtension;
\t\t};
\t\tA1D001020030 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 027480F92FED070800B678AB /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = A1D001020003;
\t\t\tremoteInfo = mdeWidgetExtension;
\t\t};
""",
    "dependencies": """
\t\tA1D001010031 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = A1D001010003 /* mdeShareExtension */;
\t\t\ttargetProxy = A1D001010030 /* PBXContainerItemProxy */;
\t\t};
\t\tA1D001020031 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = A1D001020003 /* mdeWidgetExtension */;
\t\t\ttargetProxy = A1D001020030 /* PBXContainerItemProxy */;
\t\t};
""",
    "native_targets": """
\t\tA1D001010003 /* mdeShareExtension */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = A1D001010040 /* Build configuration list for PBXNativeTarget "mdeShareExtension" */;
\t\t\tbuildPhases = (
\t\t\t\tA1D001010005 /* Sources */,
\t\t\t\tA1D001010006 /* Frameworks */,
\t\t\t\tA1D001010007 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\tA1D001010004 /* mdeShareExtension */,
\t\t\t);
\t\t\tname = mdeShareExtension;
\t\t\tproductName = mdeShareExtension;
\t\t\tproductReference = A1D001010001 /* mdeShareExtension.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t};
\t\tA1D001020003 /* mdeWidgetExtension */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = A1D001020040 /* Build configuration list for PBXNativeTarget "mdeWidgetExtension" */;
\t\t\tbuildPhases = (
\t\t\t\tA1D001020005 /* Sources */,
\t\t\t\tA1D001020006 /* Frameworks */,
\t\t\t\tA1D001020007 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\tA1D001020004 /* mdeWidgetExtension */,
\t\t\t);
\t\t\tname = mdeWidgetExtension;
\t\t\tproductName = mdeWidgetExtension;
\t\t\tproductReference = A1D001020001 /* mdeWidgetExtension.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t};
\t\tA1D001030003 /* mdeWatchApp */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = A1D001030040 /* Build configuration list for PBXNativeTarget "mdeWatchApp" */;
\t\t\tbuildPhases = (
\t\t\t\tA1D001030005 /* Sources */,
\t\t\t\tA1D001030006 /* Frameworks */,
\t\t\t\tA1D001030007 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\tA1D001030004 /* mdeWatchApp */,
\t\t\t);
\t\t\tname = mdeWatchApp;
\t\t\tproductName = mdeWatchApp;
\t\t\tproductReference = A1D001030001 /* mdeWatchApp.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
""",
    "build_phases": """
\t\tA1D001010005 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001010006 /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001010007 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001020005 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001020006 /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001020007 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001030005 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001030006 /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
\t\tA1D001030007 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
""",
    "xcconfigs": """
\t\tA1D001010041 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = mdeShareExtension/mdeShareExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = mdeShareExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = name.aks.mde.share;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tA1D001010042 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = mdeShareExtension/mdeShareExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = mdeShareExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = name.aks.mde.share;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\tA1D001010040 /* Build configuration list for PBXNativeTarget "mdeShareExtension" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ( A1D001010041 /* Debug */, A1D001010042 /* Release */ );
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\tA1D001020041 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = mdeWidgetExtension/mdeWidgetExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = mdeWidgetExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks", "@executable_path/../../../../Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = name.aks.mde.widget;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tA1D001020042 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = mdeWidgetExtension/mdeWidgetExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = mdeWidgetExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks", "@executable_path/../../../../Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = name.aks.mde.widget;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\tA1D001020040 /* Build configuration list for PBXNativeTarget "mdeWidgetExtension" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ( A1D001020041 /* Debug */, A1D001020042 /* Release */ );
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\tA1D001030041 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = name.aks.mde.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tA1D001030042 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = name.aks.mde.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\tA1D001030040 /* Build configuration list for PBXNativeTarget "mdeWatchApp" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ( A1D001030041 /* Debug */, A1D001030042 /* Release */ );
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
""",
}

text = text.replace(
    "/* End PBXBuildFile section */",
    ADDITIONS["build_files"] + "/* End PBXBuildFile section */",
)
text = text.replace(
    "0274811B2FED070900B678AB /* mdeUITests.xctest */ = {isa = PBXFileReference;",
    ADDITIONS["file_refs"] + "\t\t0274811B2FED070900B678AB /* mdeUITests.xctest */ = {isa = PBXFileReference;",
)
text = text.replace(
    "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
    ADDITIONS["exceptions"] + "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
)
text = text.replace(
    "/* End PBXFileSystemSynchronizedRootGroup section */",
    ADDITIONS["sync_groups"] + "/* End PBXFileSystemSynchronizedRootGroup section */",
)
text = text.replace(
    "\t\t\tbuildPhases = (\n\t\t\t\t027480FD2FED070800B678AB /* Sources */,\n\t\t\t\t027480FE2FED070800B678AB /* Frameworks */,\n\t\t\t\t027480FF2FED070800B678AB /* Resources */,\n\t\t\t);",
    "\t\t\tbuildPhases = (\n\t\t\t\t027480FD2FED070800B678AB /* Sources */,\n\t\t\t\t027480FE2FED070800B678AB /* Frameworks */,\n\t\t\t\t027480FF2FED070800B678AB /* Resources */,\n\t\t\t\tA1D001010020 /* Embed Foundation Extensions */,\n\t\t\t);",
)
text = text.replace(
    "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t027481032FED070800B678AB /* mde */,",
    "\t\t\tdependencies = (\n\t\t\t\tA1D001010031 /* PBXTargetDependency */,\n\t\t\t\tA1D001020031 /* PBXTargetDependency */,\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t027481032FED070800B678AB /* mde */,",
)
text = text.replace(
    "/* End PBXNativeTarget section */",
    ADDITIONS["native_targets"] + "/* End PBXNativeTarget section */",
)
text = text.replace(
    "\t\t\tchildren = (\n\t\t\t\t027481AB2FED099900B678AB /* Config */,\n\t\t\t\t027481032FED070800B678AB /* mde */,\n\t\t\t\t027481142FED070900B678AB /* mdeTests */,\n\t\t\t\t0274811E2FED070900B678AB /* mdeUITests */,",
    "\t\t\tchildren = (\n\t\t\t\t027481AB2FED099900B678AB /* Config */,\n\t\t\t\t027481032FED070800B678AB /* mde */,\n\t\t\t\tA1D001010004 /* mdeShareExtension */,\n\t\t\t\tA1D001020004 /* mdeWidgetExtension */,\n\t\t\t\tA1D001030004 /* mdeWatchApp */,\n\t\t\t\t027481142FED070900B678AB /* mdeTests */,\n\t\t\t\t0274811E2FED070900B678AB /* mdeUITests */,",
)
text = text.replace(
    "\t\t\tchildren = (\n\t\t\t\t027481012FED070800B678AB /* mde.app */,\n\t\t\t\t027481112FED070900B678AB /* mdeTests.xctest */,\n\t\t\t\t0274811B2FED070900B678AB /* mdeUITests.xctest */,",
    "\t\t\tchildren = (\n\t\t\t\t027481012FED070800B678AB /* mde.app */,\n\t\t\t\tA1D001010001 /* mdeShareExtension.appex */,\n\t\t\t\tA1D001020001 /* mdeWidgetExtension.appex */,\n\t\t\t\tA1D001030001 /* mdeWatchApp.app */,\n\t\t\t\t027481112FED070900B678AB /* mdeTests.xctest */,\n\t\t\t\t0274811B2FED070900B678AB /* mdeUITests.xctest */,",
)
text = text.replace(
    "\t\t\ttargets = (\n\t\t\t\t027481002FED070800B678AB /* mde */,\n\t\t\t\t027481102FED070900B678AB /* mdeTests */,\n\t\t\t\t0274811A2FED070900B678AB /* mdeUITests */,",
    "\t\t\ttargets = (\n\t\t\t\t027481002FED070800B678AB /* mde */,\n\t\t\t\tA1D001010003 /* mdeShareExtension */,\n\t\t\t\tA1D001020003 /* mdeWidgetExtension */,\n\t\t\t\tA1D001030003 /* mdeWatchApp */,\n\t\t\t\t027481102FED070900B678AB /* mdeTests */,\n\t\t\t\t0274811A2FED070900B678AB /* mdeUITests */,",
)
text = text.replace(
    "/* End PBXContainerItemProxy section */",
    ADDITIONS["proxies"] + "/* End PBXContainerItemProxy section */",
)
text = text.replace(
    "/* End PBXTargetDependency section */",
    ADDITIONS["dependencies"] + "/* End PBXTargetDependency section */",
)
text = text.replace(
    "/* End PBXResourcesBuildPhase section */",
    ADDITIONS["embed_phase"] + "/* End PBXResourcesBuildPhase section */",
)
text = text.replace(
    "/* End PBXSourcesBuildPhase section */",
    ADDITIONS["build_phases"] + "/* End PBXSourcesBuildPhase section */",
)
text = text.replace(
    "/* End XCConfigurationList section */",
    ADDITIONS["xcconfigs"] + "/* End XCConfigurationList section */",
)

PBX.write_text(text)
print("Added extension targets to project.pbxproj")
