#!/usr/bin/env python3
"""
生成 App Intents 元数据（Metadata.appintents/extract.actionsdata）

Xcode 构建时会用 appintentsmetadataprocessor 生成这个文件，系统据此把 App 的动作
索引到「快捷指令」的动作库里。纯命令行构建没有这个工具，所以这里按 Apple 的
JSON 格式直接生成（格式参考系统 App 的 Metadata.appintents）。

用法: python3 tools/make_appintents_metadata.py <App.app 路径>
"""
import json
import os
import sys

MODULE = "Seven7"
TOOLS_VERSION = "27A225b"
FORMAT_VERSION = "3.0"

# 已注册的 App Intent：intent 类型名 / 显示标题 / 描述 / 参数
INTENTS = [
    {
        "identifier": "ParseClipboardIntent",
        "title": "从剪贴板自动记账",
        "description": "读取剪贴板里的微信/支付宝/银行账单并自动入账",
        "parameters": [],
    },
    {
        "identifier": "RecordFromTextIntent",
        "title": "解析账单文本记账",
        "description": "把账单文本交给 7记账 识别金额、商户与分类后入账",
        "parameters": [
            {
                "name": "text",
                "primitive": 0,      # 0 = String
                "optional": False,
            }
        ],
    },
]

# 参数条目的公共字段（照系统样本）
def param_entry(p):
    return {
        "capabilities": 0,
        "dynamicOptionsSupport": 0,
        "inputConnectionBehavior": 0,
        "isInput": False,
        "isOptional": p.get("optional", True),
        "name": p["name"],
        "resolvableInputTypes": [],
        "typeSpecificMetadata": [],
        "valueType": {"primitive": {"wrapper": {"typeIdentifier": p["primitive"]}}},
    }


def mangled(identifier: str) -> str:
    # Swift mangling: <模块名长度><模块名><类型名长度><类型名>V
    return f"{len(MODULE)}{MODULE}{len(identifier)}{identifier}V"


def intent_entry(it):
    ident = it["identifier"]
    m = mangled(ident)
    return {
        "assistantDefinedSchemaTraits": [],
        "assistantDefinedSchemas": [],
        "authenticationPolicy": 0,
        "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
        "descriptionMetadata": {
            "descriptionText": {"alternatives": [], "key": it["description"]},
            "searchKeywords": [],
        },
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": f"{MODULE}.{ident}",
        "identifier": ident,
        "isAuthPolExplicit": False,
        "isDiscoverable": True,
        "mangledTypeName": m,
        "mangledTypeNameByBundleIdentifier": {},
        "mangledTypeNameByBundleIdentifierV2": {},
        "mangledTypeNameV2": m,
        "openAppWhenRun": False,
        "outputFlags": 4,
        "parameters": [param_entry(p) for p in it["parameters"]],
        "presentationStyle": 0,
        "requiredCapabilities": [],
        "supportedModes": 1,
        "systemProtocolMetadata": [],
        "systemProtocolMetadataV2": [],
        "systemProtocols": [],
        "title": {"alternatives": [], "key": it["title"]},
        "typeSpecificMetadata": [],
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": True},
    }


def main(app_path: str):
    payload = {
        "actions": {it["identifier"]: intent_entry(it) for it in INTENTS},
        "assistantEntities": [],
        "assistantIntentNegativePhrases": [],
        "assistantIntents": [],
        "autoShortcutProviderMangledName": f"{len(MODULE)}{MODULE}"
                                          f"{len('BookkeepingShortcuts')}BookkeepingShortcutsV",
        "autoShortcuts": [],
        "entities": {},
        "enums": [],
        "generator": {"name": "xcode-tools", "version": TOOLS_VERSION},
        "negativePhrases": [],
        "queries": {},
        "shortcutTileColor": 2,
        "version": 1,
    }

    out_dir = os.path.join(app_path, "Metadata.appintents")
    os.makedirs(out_dir, exist_ok=True)

    with open(os.path.join(out_dir, "extract.actionsdata"), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    with open(os.path.join(out_dir, "version.json"), "w", encoding="utf-8") as f:
        json.dump({"toolsVersion": TOOLS_VERSION, "version": FORMAT_VERSION}, f, indent=2)

    print(f"   Metadata.appintents: {len(INTENTS)} 个动作")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: make_appintents_metadata.py <App.app>", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1])
