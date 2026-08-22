#!/bin/bash
# Xcode 到位前的编译门禁：用 CLT 的 swiftc 对全部 app 源码做类型检查。
# 抓得到：全部类型/并发/API 可用性错误。
# 抓不到：资源目录、Info.plist、entitlements、签名、ShareExtension 打包。
set -uo pipefail
cd "$(dirname "$0")/.."
exec swiftc -typecheck \
	-sdk "$(xcrun --show-sdk-path)" \
	-target arm64-apple-macos26.0 \
	-swift-version 6 \
	-I .typecheck/.build/arm64-apple-macosx/debug/Modules \
	.typecheck/Shims.swift \
	Plash/*.swift
