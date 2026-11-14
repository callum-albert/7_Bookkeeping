#!/usr/bin/env python3
"""
生成可直接导入的 .shortcut 文件（7记账）

- 侧边按钮：截屏 → 识别截图记账
- 账单文本： 接收输入 → 解析账单文本记账（给银行「信息」自动化用）

格式依据：https://github.com/frontboat/shortcutkit/blob/main/docs/shortcut-file-format.md
App Intent 动作的 identifier 为 <bundleID>.<IntentTypeName>，参数键为 Swift 参数名。
"""
import os
import plistlib
import uuid

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "shortcuts")
os.makedirs(OUT, exist_ok=True)

BUNDLE = "com.seven.bookkeeping"
APP_NAME = "7记账"

# 快捷指令图标：深紫 #4B4EE8 -> WFWorkflowIconStartColor (RGB int)
ICON_COLOR = 0x4B4EE8


def descriptor(intent: str):
    return {
        "BundleIdentifier": BUNDLE,
        "Name": APP_NAME,
        "AppIntentIdentifier": intent,
        "ActionRequiresAppInstallation": True,
    }


def intent_action(intent: str, params: dict, uid: str):
    p = {"UUID": uid, "AppIntentDescriptor": descriptor(intent)}
    p.update(params)
    return {
        "WFWorkflowActionIdentifier": f"{BUNDLE}.{intent}",
        "WFWorkflowActionParameters": p,
    }


def attachment(uid: str, name: str):
    """引用上一步的输出"""
    return {
        "Value": {"OutputName": name, "OutputUUID": uid, "Type": "ActionOutput"},
        "WFSerializationType": "WFTextTokenAttachment",
    }


def shortcut_input():
    """引用「快捷指令输入」"""
    return {
        "Value": {"Type": "ExtensionInput"},
        "WFSerializationType": "WFTextTokenAttachment",
    }


def base_dict(actions, name, glyph=59511, input_types=None):
    d = {
        "WFWorkflowName": name,
        "WFWorkflowActions": actions,
        "WFWorkflowClientRelease": "3.0",
        "WFWorkflowClientVersion": "1230",
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": glyph,
            "WFWorkflowIconStartColor": ICON_COLOR,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": ["NCWidget", "WatchKit"],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
    }
    if input_types:
        d["WFWorkflowInputContentItemClasses"] = input_types
        d["WFQuickActionSurfaces"] = ["Share Sheet"]
    return d


def write(name, payload):
    path = os.path.join(OUT, name)
    with open(path, "wb") as f:
        plistlib.dump(payload, f, fmt=plistlib.FMT_BINARY, sort_keys=False)
    print("生成:", path, os.path.getsize(path), "bytes")


# ── 1. 侧边按钮：截屏 → 识别截图记账
screenshot_uid = str(uuid.uuid4()).upper()
shot = {
    "WFWorkflowActionIdentifier": "is.workflow.actions.takescreenshot",
    "WFWorkflowActionParameters": {"UUID": screenshot_uid},
}
recognize = intent_action("RecordFromImageIntent", {
    "image": attachment(screenshot_uid, "截屏"),
}, str(uuid.uuid4()).upper())
write("7记账-侧边按钮.shortcut",
      base_dict([shot, recognize], "7记账-侧边按钮", glyph=59683))

# ── 2. 账单文本记账（接收输入，给银行短信自动化用）
text = intent_action("RecordFromTextIntent", {
    "text": shortcut_input(),
}, str(uuid.uuid4()).upper())
write("7记账-账单文本记账.shortcut",
      base_dict([text], "7记账-账单文本记账", glyph=59511,
                input_types=["WFStringContentItem"]))

print("\n完成：以上为未签名源文件；先用 shortcuts sign 签名后分发，或按 App 内说明手动创建。")
