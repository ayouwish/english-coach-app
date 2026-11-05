#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_ios.py — English Coach iOS 静态校验（只读，零第三方依赖）

用法（任意目录均可运行）：
    python ios/tools/check_ios.py
    python ios/tools/check_ios.py --selftest        # 只跑词法/配平自检用例
    python ios/tools/check_ios.py --limit-warn 0      # 不截断 WARN 明细
    python ios/tools/check_ios.py --list-declared     # 额外打印已声明类型（调试）

退出码：
    0  没有 ERROR（WARN 只提示，不阻断）
    1  存在 ERROR（或校验器自身无法完成检查）

约束：
    * 本脚本 **只读**：绝不创建/修改/删除任何文件，只向 stdout 打印。
    * 只用 Python 标准库；不要 import 第三方包。
    * 本机没有 macOS/Xcode/Swift 工具链，本脚本是唯一的验收手段（见
      ios/docs/port-contract.md §0.1 / §6）。**它不等于编译通过。**

校验项（契约 §6 的 8 类）：
    1. 词法/配平      Swift 词法扫描（注释、单行/多行/原始字符串、插值、转义），
                     括号配平、#if/#elseif/#else/#endif 配平、未闭合字符串/注释。
    2. 类型唯一       顶层类型名全仓唯一（private/fileprivate 文件级类型除外），
                     文件名与主类型名一致（仅 WARN）。
    3. 符号引用       引用了未声明的 *Service / *DTO → ERROR；
                     其余未知 UpperCamelCase 标识符 → WARN（系统框架白名单）。
                     契约 §3 要求存在但全仓找不到声明的类型 → WARN。
    4. 分层           Features/** 禁止 URLSession/URLRequest/import CryptoKit；
                     Core/DesignSystem/**、Features/Shared/** 禁止网络层类型；
                     Core/** 禁止引用 Features。
    5. 规范           print(TODO/FIXME/fatalError(/try!/as! → ERROR；
                     @unchecked Sendable、#available → WARN。
    6. 工程           project.yml 的 sources 覆盖 EnglishCoach/ 下全部 .swift；
                     Info.plist 必备键齐全；PrivacyInfo.xcprivacy 可被 plistlib 解析。
    7. 路由           AppRoute 的 case 与契约 §4/§3.14 表一致；
                     App/RootTabView.swift 或 App/AppRoot.swift 的 navigationDestination/switch
                     覆盖全部 case（文件未落地时逐条 WARN，落地后缺 case 为 ERROR）。
    8. API 一致性     XxxService 被页面调用的方法名存在于该 Service 的声明（启发式）。
    附加：页面入口    Features/<域>/ 至少有一个 *View.swift（缺页面时 WARN）；
                     契约 §3.15.1 冻结的根页面文件/类型名/init 参数（缺文件 WARN，
                     文件已存在但类型名或 init 参数不符 ERROR/WARN）；
                     Features/** 不得引用 AppEnvironment（契约 §3.15，M0 遗留 WARN）。

分级：ERROR 阻断（退出码 1）；WARN 提示；INFO 只提示、不计入 WARN 计数
（例如 fileprivate 类型在不同文件重名、可删除的空占位文件）。
"""

from __future__ import annotations

import bisect
import json
import plistlib
import re
import sys
from dataclasses import dataclass, field
from fnmatch import fnmatch
from pathlib import Path

# --------------------------------------------------------------------------- #
# 路径
# --------------------------------------------------------------------------- #

SCRIPT = Path(__file__).resolve()
TOOLS_DIR = SCRIPT.parent                 # ios/tools
IOS_ROOT = TOOLS_DIR.parent               # ios
SRC_ROOT = IOS_ROOT / "EnglishCoach"      # 源码根
CONTRACT = IOS_ROOT / "docs" / "port-contract.md"
PROJECT_YML = IOS_ROOT / "project.yml"
GITIGNORE = IOS_ROOT / ".gitignore"

ERROR = "ERROR"
WARN = "WARN"
INFO = "INFO"

#: 这些模块之外一律视为「非系统框架」，需要人工确认。
SYSTEM_MODULES = {
    "Foundation", "SwiftUI", "UIKit", "AVFoundation", "Charts", "PhotosUI",
    "Security", "OSLog", "Observation", "Combine", "CryptoKit", "CoreGraphics",
    "Dispatch", "UniformTypeIdentifiers", "Photos", "CoreMedia", "os", "Swift",
    "Darwin", "QuartzCore", "CoreFoundation", "AVFAudio", "MediaPlayer",
    "CoreLocation", "CoreImage", "CoreTransferable", "SwiftData", "CoreData",
    "CloudKit", "StoreKit", "WebKit", "MapKit", "Vision", "NaturalLanguage",
    "Speech", "AudioToolbox", "CoreAudio", "ImageIO", "UIKit", "SwiftUI",
}

#: 已确认的第三方依赖（零依赖策略，出现即 ERROR）。
THIRD_PARTY_MODULES = {
    "Alamofire", "Kingfisher", "SnapKit", "Moya", "RxSwift", "RxCocoa",
    "Firebase", "Sentry", "SDWebImage", "Nuke", "Lottie", "SwiftLint",
    "swift_charts", "SkeletonView", "IQKeyboardManager",
    "CombineCocoa", "SwiftyJSON", "ObjectMapper", "Realm", "RealmSwift",
    "SQLite", "GRDB", "SwiftCollections", "AsyncAlgorithms", "Factory",
    "TCA", "ComposableArchitecture", "SnapshotTesting", "Quick", "Nimble",
}

# --------------------------------------------------------------------------- #
# 系统框架符号白名单（启发式「未声明类型引用」用）
# 仅收录系统框架/标准库类型；项目自有类型必须靠声明，不在本表。
# --------------------------------------------------------------------------- #

SYSTEM_SYMBOLS = {
    # Swift 标准库 / 语言
    "Any", "AnyObject", "Array", "AsyncSequence", "AsyncStream",
    "AsyncThrowingStream", "Bool", "CaseIterable", "Character",
    "CheckedContinuation", "ClosedRange", "Codable", "CodingKey", "CodingKeys",
    "Collection", "Comparable", "ContiguousArray", "CustomDebugStringConvertible",
    "CustomStringConvertible", "Decoder", "Decodable", "DefaultStringInterpolation",
    "Dictionary", "Double", "Duration", "Encodable", "Encoder", "Equatable",
    "Error", "Float", "FloatingPoint", "Hashable", "Identifiable", "IndexPath",
    "IndexSet", "Int", "Int8", "Int16", "Int32", "Int64", "IteratorProtocol",
    "KeyPath", "KeyedDecodingContainer", "KeyedEncodingContainer",
    "LocalizedError", "LosslessStringConvertible", "Never", "ObjectIdentifier",
    "Optional", "PartialKeyPath", "Range", "RangeReplaceableCollection",
    "RandomAccessCollection", "RawRepresentable", "Result", "Self", "Sendable",
    "Sequence", "Set", "SingleValueDecodingContainer", "StaticString", "String",
    "StringProtocol", "Substring", "Task", "TaskGroup", "TaskPriority",
    "ThrowingTaskGroup", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Unicode", "UnsafeMutablePointer", "UnsafePointer", "Void", "Wrapped",
    "Actor", "GlobalActor", "MainActor", "TaskLocal", "UncheckedSendable",
    "CancellationError", "UnsafeContinuation", "CheckedContinuation",
    "ManagedBuffer", "WritableKeyPath", "ReferenceWritableKeyPath",
    "CaseIterable", "OptionSet", "Strideable", "Numeric", "BinaryInteger",
    "SignedInteger", "UnsignedInteger", "FixedWidthInteger", "ExpressibleByStringLiteral",
    # Foundation
    "NSObject", "NSObjectProtocol", "NSCoding", "NSCopying", "NSError", "NSNumber",
    "NSRange", "NSRegularExpression", "NSString", "NSLocalizedString",
    "NSLocalizedDescriptionKey", "NSLocalizedFailureReasonErrorKey",
    "NSUnderlyingErrorKey", "NSLock", "NSRecursiveLock", "NSCache", "NSNotification",
    "URL", "URLComponents", "URLQueryItem", "URLRequest", "URLResponse",
    "URLSession", "URLSessionConfiguration", "URLSessionTask", "URLSessionDataTask",
    "URLSessionUploadTask", "URLSessionDownloadTask", "URLSessionDelegate",
    "URLSessionTaskDelegate", "URLProtocol", "URLError", "HTTPURLResponse",
    "HTTPCookie", "UUID", "Data", "Date", "DateFormatter", "DateComponents",
    "ISO8601DateFormatter", "DateInterval", "Calendar", "Locale", "TimeZone",
    "TimeInterval", "Timer", "JSONEncoder", "JSONDecoder", "JSONSerialization",
    "PropertyListEncoder", "PropertyListDecoder", "FileManager", "FileAttributeKey",
    "FileProtectionType", "Bundle", "UserDefaults", "ProcessInfo", "Notification",
    "NotificationCenter", "NumberFormatter", "CharacterSet", "Scanner",
    "Measurement", "UnitDuration", "Decimal", "ByteCountFormatter",
    "ByteCountFormatStyle", "FormatStyle", "LocaleLanguage", "AttributedString",
    "NSAttributedString", "NSMutableAttributedString", "BundleIdentifier",
    "UndoManager", "OperationQueue", "Operation", "RunLoop", "DispatchQueue",
    # 并发
    "DispatchTime", "DispatchWorkItem", "DispatchSemaphore", "DispatchGroup",
    "DispatchQoS", "DispatchQueue", "OSAllocatedUnfairLock", "Mutex",
    # SwiftUI
    "App", "Scene", "WindowGroup", "Window", "ScenePhase", "View", "ViewBuilder",
    "ViewModifier", "AnyView", "AnyTransition", "Environment", "EnvironmentKey",
    "EnvironmentValues", "EnvironmentObject", "State", "Binding", "StateObject",
    "ObservedObject", "Observable", "ObservableObject", "Published",
    "Namespace", "FocusState", "AppStorage", "SceneStorage", "GestureState",
    "Text", "Label", "Image", "Button", "ButtonRole", "ButtonStyle",
    "ButtonBorderShape", "PrimitiveButtonStyle", "Link", "Menu", "Toggle",
    "ToggleStyle", "Slider", "Stepper", "Picker", "PickerStyle", "DatePicker",
    "ColorPicker", "TextField", "SecureField", "TextEditor", "Form", "List",
    "Section", "Group", "GroupBox", "DisclosureGroup", "LabeledContent",
    "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack", "LazyVGrid",
    "LazyHGrid", "Grid", "GridRow", "GridItem", "ScrollView", "ScrollViewReader",
    "ScrollViewProxy", "ScrollTargetBehavior", "ScrollPosition", "ScrollAnchor",
    "ScrollTarget", "ScrollBounceBehavior", "ScrollDismissesKeyboardMode",
    "NavigationStack", "NavigationView", "NavigationLink", "NavigationSplitView",
    "NavigationPath", "NavigationBarItem", "TabView", "Tab", "ToolbarItem",
    "ToolbarItemGroup", "ToolbarContent", "ToolbarContentBuilder", "ToolbarPlacement",
    "Spacer", "Divider", "ProgressView", "ProgressViewStyle", "Gauge", "GaugeStyle",
    "AsyncImage", "ShareLink", "ContentUnavailableView", "ContentUnavailableViewSearch",
    "GeometryReader", "GeometryProxy", "GeometryEffect", "Layout", "LayoutValueKey",
    "Align", "Alignment", "HorizontalAlignment", "VerticalAlignment", "Edge",
    "EdgeInsets", "EdgeInsetsMask", "SafeAreaRegions", "SafeAreaInsets",
    "Rectangle", "RoundedRectangle", "RoundedCornerStyle", "Capsule", "Circle",
    "Ellipse", "UnevenRoundedRectangle", "ContainerRelativeShape", "Shape",
    "ShapeStyle", "InsettableShape", "StrokeStyle", "Path", "Canvas",
    "GraphicsContext", "FillStyle", "Color", "Gradient", "LinearGradient",
    "RadialGradient", "AngularGradient", "EllipticalGradient", "Material",
    "ImagePaint", "Font", "FontWeight", "TextAlignment", "LineLimit",
    "TextTruncationMode", "TextInputAutocapitalization", "TextInputAutocapitalization",
    "KeyboardType", "SubmitLabel", "SubmitTriggers", "DynamicTypeSize",
    "ColorScheme", "ColorSchemeContrast", "Animation", "Transaction",
    "AnimationCurve", "AnimationTimingCurve", "Spring", "UnitCurve",
    "PlainButtonStyle", "DefaultButtonStyle", "BorderedButtonStyle",
    "BorderedProminentButtonStyle", "BorderlessButtonStyle", "LinkButtonStyle",
    "ScrollView", "SensoryFeedback", "Preview", "LocalizedStringKey",
    "OpenURLAction", "DismissAction", "RefreshAction", "Alert", "AlertButton",
    "ConfirmationDialog", "Sheet", "FullScreenCover", "Popover", "ContextMenu",
    "Toolbar", "ToolbarTitleDisplayMode", "NavigationBarTitleDisplayMode",
    "NavigationDestination", "NavigationPathWriter", "WindowGroup",
    "UIKit", "UIApplication", "UIApplicationDelegate", "UIApplicationDelegateAdaptor",
    "UIResponder", "UIWindow", "UIWindowScene", "UIScene", "UISceneDelegate",
    "UISceneSession", "UISceneConfiguration", "UIViewController", "UIView",
    "UIImage", "UIColor", "UIFont", "UIScreen", "UIDevice", "UIPasteboard",
    "UIImagePickerController", "UIImagePickerControllerSourceType",
    "UIImagePickerControllerDelegate", "UINavigationControllerDelegate",
    "UIActivityViewController", "UIDocumentPickerViewController",
    "UIImpactFeedbackGenerator", "UINotificationFeedbackGenerator",
    "UISelectionFeedbackGenerator", "UIGraphicsImageRenderer",
    "UIGraphicsImageRendererFormat", "UIInterfaceOrientation",
    "UIInterfaceOrientationMask", "UIImagePickerControllerCameraDevice",
    "UIKeyboardType", "UIStatusBarStyle",
    # Combine
    "AnyPublisher", "AnyCancellable", "CurrentValueSubject", "PassthroughSubject",
    "Published", "Publishers", "Subjects", "Cancellable", "ObservableObject",
    # Observation
    "ObservationRegistrar", "ObservationTracking", "Observable",
    # AVFoundation / AVFAudio
    "AVAudioSession", "AVAudioSessionCategory", "AVAudioSessionCategoryOptions",
    "AVAudioSessionCategoryMode", "AVAudioSessionRouteChangeReason",
    "AVAudioSessionInterruptionType", "AVAudioSessionInterruptionOptions",
    "AVAudioRecorder", "AVAudioPlayer", "AVAudioPlayerDelegate",
    "AVAudioRecorderDelegate", "AVAudioFile", "AVAudioFormat", "AVAudioEngine",
    "AVAudioPCMBuffer", "AVAudioTime", "AVAudioNode", "AVAudioConverter",
    "AVAudioApplication", "AVAudioVoiceProcessingIO", "AVAudioSessionPort",
    "AVAudioSessionPortDescription", "AVAudioSessionDataSourceDescription",
    "AVCaptureSession", "AVCaptureDevice", "AVCapturePhotoOutput",
    "AVCaptureVideoPreviewLayer", "AVCapturePhotoSettings",
    "AVAsset", "AVURLAsset", "AVPlayer", "AVPlayerItem", "AVPlayerLayer",
    "AVAssetExportSession", "AVSpeechSynthesizer", "AVSpeechUtterance",
    "AVSpeechSynthesisVoice", "AVAudioChannelLayout", "AVAudioFileType",
    "AVAudioQuality", "AVAudioCommonFormat", "AVAudioSessionRecordPermission",
    "AVAudioSessionDeactivationOptions",
    # Charts
    "Chart", "ChartContent", "ChartContentBuilder", "ChartProxy", "ChartPlotContent",
    "LineMark", "PointMark", "BarMark", "AreaMark", "RuleMark", "RectangleMark",
    "SectorMark", "AxisMarks", "AxisMarksValues", "AxisValue", "AxisValueLabel",
    "AxisGridLine", "AxisTick", "PlottableValue", "MarkDimension", "Annotation",
    "ChartLegend", "ChartLegendContent", "ChartXSelection", "ChartYSelection",
    "ChartScrollableAxes", "ChartScrollPosition", "ChartScrollTargetBehavior",
    # PhotosUI / Photos
    "PhotosPicker", "PhotosPickerItem", "PhotosPickerSelectionBehavior",
    "PhotosPickerItemProvider", "PHPickerViewController", "PHPickerConfiguration",
    "PHPickerFilter", "PHPickerResult", "PHPickerViewControllerDelegate",
    "PHPhotoLibrary", "PHAsset", "PHAssetResource",
    # Security
    "SecItemAdd", "SecItemCopyMatching", "SecItemDelete", "SecItemUpdate",
    "SecAccessControl", "SecKey", "SecCertificate", "SecTrust", "SecPolicy",
    "SecRandomCopyBytes", "SecCode", "OSStatus", "CFString", "CFDictionary",
    "CFData", "CFBoolean", "CFArray", "CFNumber", "CFTypeRef", "CFAllocator",
    "CFError", "CFURL", "CFUUID",
    # OSLog
    "Logger", "OSLogType", "OSLogMessage", "OSLogStore", "OSSignposter",
    "OSSignpostType", "OSLog", "OSLogPrivacy",
    # CoreGraphics / CoreMedia / UniformTypeIdentifiers
    "CGFloat", "CGPoint", "CGSize", "CGRect", "CGAffineTransform", "CGImage",
    "CGColor", "CGContext", "CGPath", "CGGradient", "CGBlendMode", "CGLineCap",
    "CGLineJoin", "CGRectEdge", "CGImageAlphaInfo", "CGBitmapInfo", "CGColorSpace",
    "CMTime", "CMTimeRange", "CMTimeScale", "UTType",
    # CryptoKit
    "SHA256", "SHA384", "SHA512", "SHA256Digest", "Insecure", "Hasher",
    "SymmetricKey", "Curve25519", "HMAC", "AES",
    # 其他
    "URLComponents", "ObjectIdentifier", "XCTestCase", "XCUIApplication",
    "XCTest", "UIApplication", "PreviewProvider", "XCTestObservation",
    # SwiftUI / Observation 宏与属性包装器
    "Bindable", "ObservationIgnored", "ForEach", "DynamicProperty",
    "PreferenceKey", "ViewModifierContent", "Configuration", "Content",
    "Body", "Element", "Key", "Value", "ID", "Index", "Iterator", "Base",
    "Output", "Failure", "Success", "Subject", "ObjectType", "CodingKey",
    # AVFoundation 录音设置键 / 通知 userInfo 键（均为框架全局常量，非项目类型）
    "AVFormatIDKey", "AVSampleRateKey", "AVNumberOfChannelsKey",
    "AVEncoderBitRateKey", "AVEncoderAudioQualityKey",
    "AVEncoderBitRateStrategyKey", "AVEncoderBitRatePerChannelKey",
    "AVLinearPCMBitDepthKey", "AVLinearPCMIsFloatKey",
    "AVLinearPCMIsBigEndianKey", "AVLinearPCMIsNonInterleavedKey",
    "AVLinearPCMIsSignedIntegerKey", "AVChannelLayoutKey", "AVFileType",
    "AVAudioQuality", "AVEncoderBitRateStrategy",
    "AVAudioSessionInterruptionTypeKey", "AVAudioSessionInterruptionOptionKey",
    "AVAudioSessionRouteChangeReasonKey", "AVAudioSessionRouteChangePreviousRouteKey",
    "AVAudioSessionSilenceSecondaryAudioHintTypeKey",
    "AVAudioSessionMediaServicesWereLostNotification",
    "AVAudioSessionMediaServicesWereResetNotification",
    "AVAudioSessionRouteChangeNotification",
    "AVAudioSessionInterruptionNotification",
    # CoreMedia / Foundation C 函数与键（UpperCamelCase 全局符号）
    "CMTimeGetSeconds", "CMTimeMake", "CMTimeMakeWithSeconds",
    "CMTimeCompare", "CMTimeGetSeconds", "CMTimeRangeMake",
    "URLResourceKey", "URLResourceValues", "URLFileResourceType",
    "FileAttributeKey", "FileProtectionType", "NSFileProtectionType",
    # SwiftUI Layout / 私有视图尺寸
    "ProposedViewSize", "Subviews", "LayoutSubviews", "LayoutSubview",
    # SwiftUI 手势 / 布局 / iOS 26 新 API（提前收录，避免 wave-2 大量白名单噪声）
    "Gesture", "TapGesture", "DragGesture", "LongPressGesture", "MagnifyGesture",
    "RotateGesture", "ExclusiveGesture", "SimultaneousGesture", "SequenceGesture",
    "SpatialTapGesture", "HoverGesture", "PanGesture", "AnyGesture",
    "AnyLayout", "HStackLayout", "VStackLayout", "ZStackLayout", "GridLayout",
    "ViewThatFits", "TimelineView", "TimelineSchedule", "PeriodicTimelineSchedule",
    "PhaseAnimator", "KeyframeAnimator", "AnimationCompletionCriteria",
    "PresentationDetent", "PresentationBackgroundInteraction",
    "ContentUnavailableView", "ScrollEdgeEffectStyle", "ScrollEdgeEffect",
    "TabSection", "TabContent", "PageTabViewStyle", "SidebarAdaptableTabViewStyle",
    "TabBarMinimizeBehavior", "TabViewStyle", "ImageRenderer",
    "EditButton", "PasteButton", "RenameButton", "HelpLink", "LabeledContent",
    "EmptyView", "EquatableView", "ConditionalContent", "TupleView",
    "TextSelection", "ContentMargins", "ScrollIndicators", "PinnedScrollableViews",
    "MatchedGeometryProperties", "GeometryProxy", "Anchor", "UnitPoint",
    "NSItemProvider", "NSItemProviderReading", "NSItemProviderWriting",
    "CGImageSource", "CGImageDestination", "CIImage", "CIFilter",
    # UIKit 桥接（UIImagePickerController / UIViewRepresentable）
    "UIViewControllerRepresentable", "UIViewRepresentable",
    "UIViewControllerRepresentableContext", "UIViewRepresentableContext",
    "UIHostingController", "Context", "Coordinator",
    # ImageIO / UIKit 的 C 函数（UpperCamelCase 全局符号，非项目类型）
    "CGImageSourceCreateWithData", "CGImageSourceCreateImageAtIndex",
    "CGImageSourceGetType", "CGImageSourceGetCount", "CGImageSourceCreateThumbnailAtIndex",
    "CGImageDestinationCreateWithData", "CGImageDestinationAddImage",
    "CGImageDestinationFinalize", "CGImageCreateWithImageInRect",
    "CGContextDrawImage", "UIImageJPEGRepresentation", "UIImagePNGRepresentation",
    "UIImageWriteToSavedPhotosAlbum", "UIGraphicsBeginImageContextWithOptions",
    "UIGraphicsGetImageFromCurrentImageContext", "UIGraphicsEndImageContext",
    # 框架名（出现位置可能不在 import 行，如 @_exported）
    "Foundation", "SwiftUI", "UIKit", "AVFoundation", "AVFAudio", "Charts",
    "PhotosUI", "Security", "OSLog", "Observation", "Combine", "CryptoKit",
    "CoreGraphics", "Dispatch", "UniformTypeIdentifiers", "Photos",
    "CoreMedia", "AudioToolbox", "os",
}

# --------------------------------------------------------------------------- #
# 契约里「必须存在」的类型（从 port-contract.md 提取，用于 WARN 提示）
# --------------------------------------------------------------------------- #

CONTRACT_TYPE_RE = re.compile(
    r"(?m)^[^\n`]{0,40}?\b(?:struct|class|enum|actor|protocol)\s+([A-Z][A-Za-z0-9_]*)\b"
)
CONTRACT_DECLARED_RE = re.compile(r"\b(?:struct|class|enum|actor|protocol)\s+([A-Z][A-Za-z0-9_]*)\b")

#: 契约 §3.14 / §4 的路由表。value = 关联值个数（用于 WARN 级别的一致性提示）。
EXPECTED_ROUTES = {
    "sentences": 0,
    "practice": 1,
    "practiceResult": 1,
    "flowSummary": 0,
    "chatScenarios": 0,
    "chatSession": 1,
    "chatHistory": 0,
    "chatDetail": 1,
    "chatCustom": 1,
    "storyRecord": 0,
    "storyDetail": 1,
    "storyReview": 2,
    "blindTest": 0,
    "diagnosis": 0,
    "review": 0,
    "parent": 0,
    "family": 0,
    "suggestions": 0,
    "avatar": 0,
    "voices": 0,
    "health": 0,
    "settings": 0,
}

# --------------------------------------------------------------------------- #
# 基础工具
# --------------------------------------------------------------------------- #


def rel(path: Path) -> str:
    try:
        return path.relative_to(IOS_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").lstrip("\ufeff")
    except OSError as exc:  # pragma: no cover - 只读失败极少见
        return f"/* check_ios: 无法读取 {path}: {exc} */"


def line_starts(text: str) -> list[int]:
    starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            starts.append(i + 1)
    return starts


def line_of(starts: list[int], offset: int) -> int:
    if not starts:
        return 1
    return bisect.bisect_right(starts, max(offset, 0))


def strip_yaml_comment(line: str) -> str:
    """去掉 YAML 行尾注释（不处理引号内的 #，够用即可）。"""
    out: list[str] = []
    quote: str | None = None
    for i, ch in enumerate(line):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out)


def split_top_level(text: str, sep: str = ",") -> list[str]:
    """按顶层分隔符切分（忽略 () [] <> {} 与字符串内的分隔符）。"""
    parts: list[str] = []
    depth = 0
    quote: str | None = None
    cur: list[str] = []
    for ch in text:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch == '"':
            quote = ch
            cur.append(ch)
            continue
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth = max(depth - 1, 0)
        if ch == sep and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
            continue
        cur.append(ch)
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return parts


# --------------------------------------------------------------------------- #
# 报告
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Issue:
    sev: str
    path: str
    line: int
    cat: str
    msg: str


class Report:
    def __init__(self) -> None:
        self.issues: list[Issue] = []
        self._seen: set[tuple[str, str, int, str, str]] = set()

    def add(self, sev: str, path: str, line: int, cat: str, msg: str) -> None:
        key = (sev, path, int(line), cat, msg)
        if key in self._seen:
            return
        self._seen.add(key)
        self.issues.append(Issue(sev, path, int(line), cat, msg))

    def error(self, path: str, line: int, cat: str, msg: str) -> None:
        self.add(ERROR, path, line, cat, msg)

    def warn(self, path: str, line: int, cat: str, msg: str) -> None:
        self.add(WARN, path, line, cat, msg)

    def info(self, path: str, line: int, cat: str, msg: str) -> None:
        """INFO 只提示，不计入 WARN 计数（避免淹没真问题）。"""
        self.add(INFO, path, line, cat, msg)

    def count(self, sev: str) -> int:
        return sum(1 for i in self.issues if i.sev == sev)


# --------------------------------------------------------------------------- #
# 1) Swift 词法扫描
# --------------------------------------------------------------------------- #


class Lexer:
    """把注释/字符串内容替换为空格（保留换行与位置），并记录未闭合项。"""

    def __init__(self, text: str) -> None:
        self.t = text
        self.n = len(text)
        self.mask: list[str] = list(text)
        self.unclosed_strings: list[tuple[int, str]] = []
        self.unclosed_comments: list[int] = []
        #: 已闭合的字符串字面量：(起始引号偏移, 结束偏移, 原始 # 数, 是否多行)
        self.strings: list[tuple[int, int, int, bool]] = []

    def blank(self, start: int, end: int) -> None:
        mask = self.mask
        n = self.n
        for k in range(max(0, start), min(end, n)):
            ch = mask[k]
            if ch != "\n" and ch != "\r":
                mask[k] = " "

    # -- 块注释（支持嵌套） ------------------------------------------------- #
    def scan_block_comment(self, i: int) -> tuple[int, bool]:
        depth = 1
        j = i + 2
        t = self.t
        n = self.n
        while j < n:
            if t.startswith("/*", j):
                depth += 1
                j += 2
            elif t.startswith("*/", j):
                depth -= 1
                j += 2
                if depth == 0:
                    return j, True
            else:
                j += 1
        return n, False

    # -- 字符串 -------------------------------------------------------------- #
    def scan_string(self, quote: int, hashes: int) -> tuple[int, bool, bool]:
        """quote 指向第一个引号；返回 (结束位置, 是否闭合, 是否多行)。"""
        t = self.t
        n = self.n
        multiline = t.startswith('"""', quote)
        j = quote + (3 if multiline else 1)
        close = ('"""' if multiline else '"') + "#" * hashes
        while j < n:
            ch = t[j]
            if not multiline and ch == "\n" and hashes == 0:
                return j, False, multiline
            if hashes == 0 and ch == "\\":
                if j + 1 < n and t[j + 1] == "(":
                    j = self.skip_interpolation(j + 2)
                    continue
                j += 2
                continue
            if hashes > 0 and ch == "\\" and t.startswith("#" * hashes + "(", j + 1):
                j = self.skip_interpolation(j + 1 + hashes + 1)
                continue
            if t.startswith(close, j):
                return j + len(close), True, multiline
            j += 1
        return n, False, multiline

    def skip_interpolation(self, j: int) -> int:
        """j 位于 `\\(` 之后；跳到配对的 `)`（跳过其中的字符串/注释/嵌套插值）。"""
        t = self.t
        n = self.n
        depth = 0
        while j < n:
            ch = t[j]
            if ch == "/" and j + 1 < n and t[j + 1] == "/":
                k = t.find("\n", j)
                j = n if k < 0 else k
                continue
            if ch == "/" and j + 1 < n and t[j + 1] == "*":
                j, _ = self.scan_block_comment(j)
                continue
            if ch in ('"', "#"):
                hashes = 0
                k = j
                while k < n and t[k] == "#":
                    hashes += 1
                    k += 1
                if k < n and t[k] == '"':
                    end, _, _ = self.scan_string(k, hashes)
                    j = end
                    continue
                j += max(hashes, 1)
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                if depth == 0:
                    return j + 1
                depth -= 1
            j += 1
        return n

    # -- 代码 ---------------------------------------------------------------- #
    def scan_code(self, i: int, stop_at_rparen: bool) -> int:
        t = self.t
        n = self.n
        depth = 0
        while i < n:
            ch = t[i]
            if ch == "/" and i + 1 < n and t[i + 1] == "/":
                k = t.find("\n", i)
                k = n if k < 0 else k
                self.blank(i, k)
                i = k
                continue
            if ch == "/" and i + 1 < n and t[i + 1] == "*":
                end, ok = self.scan_block_comment(i)
                self.blank(i, end)
                if not ok:
                    self.unclosed_comments.append(i)
                i = end
                continue
            if ch in ('"', "#"):
                hashes = 0
                k = i
                while k < n and t[k] == "#":
                    hashes += 1
                    k += 1
                if k < n and t[k] == '"':
                    end, closed, multiline = self.scan_string(k, hashes)
                    self.blank(i, end)
                    if not closed:
                        self.unclosed_strings.append((i, '"""' if multiline else '"'))
                        i = n
                        continue
                    self.strings.append((k, end, hashes, multiline))
                    i = end
                    continue
                i += max(hashes, 1)
                continue
            if ch == "(":
                depth += 1
                i += 1
                continue
            if ch == ")":
                if stop_at_rparen and depth == 0:
                    return i + 1
                if depth > 0:
                    depth -= 1
                i += 1
                continue
            i += 1
        return n

    def run(self) -> str:
        self.scan_code(0, False)
        return "".join(self.mask)


@dataclass
class Decl:
    name: str
    kind: str
    line: int
    rel_path: str
    private: bool
    top_level: bool


class SwiftFile:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.rel = rel(path)
        self.text = read_text(path)
        lexer = Lexer(self.text)
        self.masked = lexer.run()
        self.unclosed_strings = lexer.unclosed_strings
        self.unclosed_comments = lexer.unclosed_comments
        self.strings = lexer.strings
        self.starts = line_starts(self.text)
        self.decls: list[Decl] = []

    def line(self, offset: int) -> int:
        return line_of(self.starts, offset)

    def raw_line(self, line: int) -> str:
        lines = self.text.splitlines()
        if 1 <= line <= len(lines):
            return lines[line - 1]
        return ""


# --------------------------------------------------------------------------- #
# 声明解析
# --------------------------------------------------------------------------- #

TYPE_DECL_RE = re.compile(r"\b(struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)")
ASSOC_TYPE_RE = re.compile(r"\bassociatedtype\s+([A-Z][A-Za-z0-9_]*)")
DIRECTIVE_LINE_RE = re.compile(r"^[ \t]*#(?:if|elseif|else|endif)\b")

TOP_DECL_RE = re.compile(
    r"(?m)^[ \t]*(?P<prefix>"
    r"(?:(?:@[A-Za-z_][\w.]*(?:\([^()\n]*\))?|public|private|fileprivate|internal|"
    r"open|package|final|indirect|nonisolated|distributed|static)\s+)*"
    r")(?P<kind>struct|class|enum|actor|protocol|extension|typealias)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)


def top_level_text(masked: str) -> str:
    """把「不在顶层」的字符以及 #if 等指令行抹成空格，便于匹配顶层声明。"""
    lines = masked.split("\n")
    cleaned = "\n".join(
        " " * len(line) if DIRECTIVE_LINE_RE.match(line) else line for line in lines
    )
    out = list(cleaned)
    depth = 0
    for i, ch in enumerate(cleaned):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth > 0:
                depth -= 1
        elif depth > 0 and ch not in "\n\r":
            out[i] = " "
    return "".join(out)


def extract_decls(sf: SwiftFile) -> list[Decl]:
    decls: list[Decl] = []
    tl_text = top_level_text(sf.masked)
    tl_names: set[str] = set()
    for m in TOP_DECL_RE.finditer(tl_text):
        prefix = m.group("prefix") or ""
        name = m.group("name")
        kind = m.group("kind")
        decls.append(
            Decl(
                name=name,
                kind=kind,
                line=sf.line(m.start("name")),
                rel_path=sf.rel,
                private=("private" in prefix or "fileprivate" in prefix),
                top_level=True,
            )
        )
        tl_names.add(name)
    # 嵌套类型（也计入「已声明」集合，避免误报）
    for m in TYPE_DECL_RE.finditer(sf.masked):
        name = m.group(2)
        line = sf.line(m.start(2))
        if name in tl_names and any(d.line == line and d.name == name for d in decls):
            continue
        decls.append(
            Decl(
                name=name,
                kind=m.group(1),
                line=line,
                rel_path=sf.rel,
                private=False,
                top_level=False,
            )
        )
    sf.decls = decls
    return decls


# --------------------------------------------------------------------------- #
# 各类校验
# --------------------------------------------------------------------------- #

MATCH_OPEN = {"(": ")", "[": "]", "{": "}"}
MATCH_CLOSE = {")": "(", "]": "[", "}": "{"}


def bracket_errors(masked: str) -> list[tuple[int, str]]:
    """括号配平检查（只看代码；字符串/注释内容已被空格替换）。"""
    errors: list[tuple[int, str]] = []
    stack: list[tuple[str, int]] = []
    line = 1
    for ch in masked:
        if ch == "\n":
            line += 1
            continue
        if ch in MATCH_OPEN:
            stack.append((ch, line))
        elif ch in MATCH_CLOSE:
            if not stack:
                errors.append((line, f"多余的闭合括号 '{ch}'，没有可配对的开始括号"))
                continue
            open_ch, open_line = stack[-1]
            if MATCH_OPEN[open_ch] != ch:
                errors.append((line, f"括号不配对：第 {open_line} 行的 '{open_ch}' 与这里的 '{ch}' 不匹配"))
                stack.pop()
            else:
                stack.pop()
    for open_ch, open_line in stack:
        errors.append((open_line, f"未闭合的 '{open_ch}'（直到文件末尾都没有配对）"))
    return errors


def conditional_errors(masked: str) -> list[tuple[int, str]]:
    """#if / #elseif / #else / #endif 配平。"""
    errors: list[tuple[int, str]] = []
    cond_stack: list[tuple[str, int]] = []
    for lineno, text_line in enumerate(masked.split("\n"), 1):
        m = DIRECTIVE_LINE_RE.match(text_line)
        if not m:
            continue
        token = m.group(0).strip().lstrip("#")
        if token == "if":
            cond_stack.append(("if", lineno))
        elif token in ("elseif", "else"):
            if not cond_stack:
                errors.append((lineno, f"#if 缺失：孤立的 #{token}"))
            elif cond_stack[-1][0] == "else" and token == "elseif":
                errors.append((lineno, "#else 之后又出现 #elseif"))
            elif token == "else":
                cond_stack[-1] = ("else", cond_stack[-1][1])
        elif token == "endif":
            if not cond_stack:
                errors.append((lineno, "孤立的 #endif（没有对应的 #if）"))
            else:
                cond_stack.pop()
    for _, open_line in cond_stack:
        errors.append((open_line, "未配对的 #if（直到文件末尾都没有 #endif）"))
    return errors


def check_lexical(sf: SwiftFile, rep: Report) -> None:
    """括号 / #if 配平、未闭合字符串与注释。"""
    for line, msg in bracket_errors(sf.masked):
        rep.error(sf.rel, line, "括号", msg)
    for line, msg in conditional_errors(sf.masked):
        rep.error(sf.rel, line, "条件编译", msg)
    for start, kind in sf.unclosed_strings:
        if kind == "interp":
            continue
        rep.error(sf.rel, sf.line(start), "词法", f"未闭合的字符串字面量（{kind} 开始于此处）")
    for start in sf.unclosed_comments:
        rep.error(sf.rel, sf.line(start), "词法", "未闭合的块注释 '/*'（直到文件末尾都没有配对）")


CONVENTION_PATTERNS: list[tuple[str, str, str]] = [
    # (正则, 类别, 说明)
    (r"(?<![\w.])print\s*\(", "规范", "禁止 print(：日志请用 OSLog Logger"),
    (r"(?<![\w.])debugPrint\s*\(", "规范", "禁止 debugPrint("),
    (r"(?<![\w.])fatalError\s*\(", "规范", "禁止 fatalError(：请把错误映射成 UIMessage"),
    (r"\btry\s*!", "规范", "禁止 try!：必须处理错误"),
    (r"\bas\s*!", "规范", "禁止 as!：请用 as? + 兜底"),
    (r"@unchecked\s+Sendable", "规范", "禁止用 @unchecked Sendable 绕过严格并发检查"),
    (r"#available\s*\(", "规范", "目标 iOS 26，不应写 #available 兼容分支"),
    (r"if\s+#available", "规范", "目标 iOS 26，不应写 #available 兼容分支"),
]


def check_conventions(sf: SwiftFile, rep: Report) -> None:
    for pattern, cat, msg in CONVENTION_PATTERNS:
        for m in re.finditer(pattern, sf.masked):
            rep.error(sf.rel, sf.line(m.start()), cat, msg)
    # TODO / FIXME 出现在注释里，所以用原文扫描
    for m in re.finditer(r"\b(TODO|FIXME)\b", sf.text):
        rep.error(sf.rel, sf.line(m.start()), "规范", f"禁止 {m.group(1)}：未实现项写进 ios/README.md §0.5")
    check_hardcoded_english_ui(sf, rep)


#: 用户可见文案应为简体中文（契约 §2.4）；品牌名等例外。
#: 注意前导边界：`subScoreLabel(` 这类自定义函数不应被当成 `Label(`。
UI_TEXT_CALL_RE = re.compile(
    r"(?<![A-Za-z0-9_.])(?:Text|Label|Button|navigationTitle|navigationBarTitle|"
    r"accessibilityLabel|alert|confirmationDialog)\s*\(\s*$"
)
CJK_RE = re.compile(r"[\u3000-\u303f\u3400-\u9fff\uff00-\uffef]")
EN_UI_ALLOW = {
    "English Coach", "OK", "IPA", "CEFR", "A1", "A2", "B1", "B2", "C1",
    "iOS", "ID", "URL", "API",
}


def check_hardcoded_english_ui(sf: SwiftFile, rep: Report) -> None:
    """契约 §6.5：抽查硬编码英文 UI 文案（只检查 Text(...)/Label(...) 这类字面量）。"""
    for quote, end, hashes, multiline in sf.strings:
        if multiline or hashes or end - quote > 200:
            continue
        start_line = sf.line(quote)
        line_start = sf.starts[start_line - 1] if start_line - 1 < len(sf.starts) else 0
        prefix = sf.text[line_start:quote]
        if not UI_TEXT_CALL_RE.search(prefix):
            continue
        content = sf.text[quote + 1 : end - 1].strip()
        if not content or CJK_RE.search(content) or content in EN_UI_ALLOW:
            continue
        if len(re.findall(r"[A-Za-z]", content)) < 3:
            continue
        if not re.fullmatch(r"[A-Za-z0-9 .,!?'’·:;()/&%+\-–—…]+", content):
            continue
        rep.warn(
            sf.rel,
            start_line,
            "规范",
            f'疑似硬编码英文 UI 文案 "{content}"：用户可见字符串应为简体中文（契约 §2.4）',
        )


IMPORT_RE = re.compile(r"(?m)^[ \t]*(?:@preconcurrency\s+)?(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)")


def check_imports(sf: SwiftFile, rep: Report) -> None:
    for m in IMPORT_RE.finditer(sf.masked):
        module = m.group(1)
        line = sf.line(m.start())
        if module in THIRD_PARTY_MODULES:
            rep.error(sf.rel, line, "依赖", f"引入第三方依赖 '{module}'（契约 §8：零第三方依赖）")
        elif module not in SYSTEM_MODULES:
            rep.warn(sf.rel, line, "依赖", f"未知模块 '{module}'，请确认是系统框架")


def check_layering(sf: SwiftFile, rep: Report) -> None:
    rel_posix = sf.rel
    masked = sf.masked

    def first_match(pattern: str) -> int | None:
        m = re.search(pattern, masked)
        return sf.line(m.start()) if m else None

    if "/Features/" in rel_posix:
        for token in ("URLSession", "URLRequest"):
            line = first_match(rf"\b{token}\b")
            if line is not None:
                rep.error(
                    sf.rel,
                    line,
                    "分层",
                    f"Features/** 禁止出现 {token}：请扩展 Core 的 Service 能力",
                )
        line = first_match(r"import\s+CryptoKit")
        if line is not None:
            rep.error(sf.rel, line, "分层", "Features/** 禁止 import CryptoKit（缓存键等放 Core）")

    in_design = "/Core/DesignSystem/" in rel_posix
    in_shared = "/Features/Shared/" in rel_posix
    if in_design or in_shared:
        # 路由/导航文件允许携带 DTO 关联值（AppRoute 是跨层契约类型），不参与本规则。
        exempt_nav = (
            "/Navigation/" in rel_posix
            or rel_posix.endswith("AppRoute.swift")
            or rel_posix.endswith("AppRouter.swift")
        )
        if not exempt_nav:
            net_re = re.compile(
                r"\b(?:[A-Za-z_][A-Za-z0-9_]*(?:DTO|Service)|APITransport|APIError|"
                r"HTTPClient|Endpoint|URLSession|URLRequest|Networking)\b"
            )
            for m in net_re.finditer(masked):
                line = sf.line(m.start())
                rep.error(
                    sf.rel,
                    line,
                    "分层",
                    f"设计系统/共享层禁止引用网络层类型 '{m.group(0)}'（只接收已格式化数据）",
                )

    if "/Core/" in rel_posix:
        m = re.search(r"\bFeatures\b", masked)
        if m:
            rep.error(sf.rel, sf.line(m.start()), "分层", "Core/** 禁止引用 Features（依赖方向 App → Features → Core）")


# --------------------------------------------------------------------------- #
# 未声明符号 / 契约类型
# --------------------------------------------------------------------------- #

IDENT_RE = re.compile(r"(?<![A-Za-z0-9_])[A-Z][A-Za-z0-9_]*")


GENERIC_PARAM_RE = re.compile(
    r"(?:struct|class|enum|actor|protocol|func|typealias)\s+[A-Za-z_][A-Za-z0-9_]*\s*<([^<>\n]*)>"
)


def build_declared(models: list[SwiftFile]) -> set[str]:
    declared: set[str] = set()
    for m in models:
        for dm in TYPE_DECL_RE.finditer(m.masked):
            declared.add(dm.group(2))
        for dm in ASSOC_TYPE_RE.finditer(m.masked):
            declared.add(dm.group(1))
        # 泛型参数（如 `func read<Payload: Decodable>`）也是合法标识符，不该报未知类型
        for gm in GENERIC_PARAM_RE.finditer(m.masked):
            for part in gm.group(1).split(","):
                pm = re.match(r"\s*([A-Z][A-Za-z0-9_]*)", part)
                if pm:
                    declared.add(pm.group(1))
    return declared


def frozen_page_types() -> set[str]:
    """契约 §3.15.1 冻结表格里的根页面类型（缺文件时由「页面」检查统一聚合提示，避免刷屏）。"""
    if not CONTRACT.exists():
        return set()
    try:
        text = read_text(CONTRACT)
    except OSError:
        return set()
    return {m.group(2) for m in FROZEN_PAGE_ROW_RE.finditer(text)}


def check_symbol_refs(
    models: list[SwiftFile], declared: set[str], rep: Report, limit_warn: int
) -> None:
    unknown: dict[tuple[str, str], int] = {}
    pending_pages = frozen_page_types()
    for sf in models:
        masked = sf.masked
        for m in IDENT_RE.finditer(masked):
            name = m.group(0)
            if len(name) <= 1 or name in ("T", "E", "K", "V", "U", "W"):
                continue
            if name in declared or name in SYSTEM_SYMBOLS or name in SYSTEM_MODULES:
                continue
            if name in pending_pages:
                # 冻结页面尚未实现：由 check_frozen_pages 的聚合 WARN 统一说明
                continue
            start = m.start()
            after_dot = start > 0 and masked[start - 1] == "."
            # 契约 §6.3 的硬规则：Service / DTO 必须在本仓有声明。
            if name.endswith(("DTO", "Service")):
                rep.error(
                    sf.rel,
                    sf.line(start),
                    "符号",
                    f"引用了未声明的类型 '{name}'（契约 §6.3：*Service/*DTO 必须在仓内有声明）",
                )
                continue
            if after_dot:
                # 成员访问（`Some.Type` 的成员/枚举 case）不做启发式
                continue
            key = (sf.rel, name)
            if key not in unknown:
                unknown[key] = sf.line(start)

    total = len(unknown)
    shown = 0
    cap = limit_warn if limit_warn > 0 else total
    for (path, name), line in sorted(unknown.items(), key=lambda kv: (kv[0][0], kv[1], kv[0][1])):
        if shown >= cap:
            break
        rep.warn(path, line, "符号", f"未知类型 '{name}'（仓内无声明且不在系统框架白名单内；可能是拼写/未实现/白名单遗漏）")
        shown += 1
    if total > shown:
        rep.warn("-", 0, "符号", f"同类「未知类型」WARN 共 {total} 条，已截断显示 {shown} 条（用 --limit-warn 0 查看全部）")


#: 契约 §3 里以反引号形式出现的类型名（`` `XxxDTO` `` / `` `XxxService` ``）。
#: 注意：`` `PracticeDTO.swift` `` 这类是**文件名**，不是类型声明，必须跳过。
CONTRACT_BACKTICK_TYPE_RE = re.compile(r"`([A-Z][A-Za-z0-9]*(?:DTO|Service))`")


def _contract_section3() -> str:
    """只取契约 §3（Core 公共 API）区间，§1/§6 里的文件名与规则说明不应算作类型声明。"""
    if not CONTRACT.exists():
        return ""
    text = read_text(CONTRACT)
    m1 = re.search(r"(?m)^##\s*3\.", text)
    m2 = re.search(r"(?m)^##\s*4\.", text)
    if not m1:
        return text
    start = m1.start()
    end = m2.start() if m2 and m2.start() > start else len(text)
    return text[start:end]


def contract_required_types() -> set[str]:
    section = _contract_section3()
    if not section:
        return set()
    names: set[str] = set()
    for m in CONTRACT_BACKTICK_TYPE_RE.finditer(section):
        name = m.group(1)
        if name.startswith("Xxx") or name in {"SomeDTO", "SomeService"}:
            continue
        names.add(name)
    for m in CONTRACT_TYPE_RE.finditer(section):
        name = m.group(1)
        if name.startswith("Xxx"):
            continue
        names.add(name)
    for m in CONTRACT_DECLARED_RE.finditer(section):
        name = m.group(1)
        if name.startswith("Xxx"):
            continue
        names.add(name)
    return names


def check_contract_types(models: list[SwiftFile], declared: set[str], rep: Report) -> None:
    required = contract_required_types()
    pending_pages = frozen_page_types()
    missing = sorted(required - declared)
    for name in missing:
        if name in pending_pages:
            # 由「页面」检查聚合提示（契约 §3.15.1 冻结页面未落地）
            continue
        rep.warn(
            "docs/port-contract.md",
            0,
            "契约类型缺失",
            f"契约 §3 要求存在类型 '{name}'，但全仓未找到声明（缺文件或尚未落地）",
        )
    _ = models


# --------------------------------------------------------------------------- #
# 类型唯一 / 文件名
# --------------------------------------------------------------------------- #


def check_uniqueness(models: list[SwiftFile], rep: Report) -> None:
    top: dict[str, list[Decl]] = {}
    for sf in models:
        for d in sf.decls:
            if d.top_level and d.kind != "extension":
                top.setdefault(d.name, []).append(d)

    for name, decls in sorted(top.items()):
        public = [d for d in decls if not d.private]
        private = [d for d in decls if d.private]
        if len(public) > 1:
            for d in public[1:]:
                first = public[0]
                rep.error(
                    d.rel_path,
                    d.line,
                    "类型唯一",
                    f"顶层类型 '{name}' 重复声明（另见 {first.rel_path}:{first.line}）",
                )
        elif public and private:
            for d in private:
                rep.warn(
                    d.rel_path,
                    d.line,
                    "类型唯一",
                    f"文件级私有类型 '{name}' 与全局类型重名（全局声明见 {public[0].rel_path}:{public[0].line}）；"
                    f"若两处都是 private/fileprivate 则属合法重名，会降为 INFO、不占 WARN 计数",
                )
        elif len(private) > 1:
            # 全部是文件级私有类型：Swift 允许不同文件各自定义同名 private 类型，只作 INFO
            for d in private[1:]:
                first = private[0]
                rep.info(
                    d.rel_path,
                    d.line,
                    "类型唯一",
                    f"多个文件各自定义了私有类型 '{name}'（{first.rel_path}:{first.line} 与此处）；"
                    f"fileprivate 合法，但建议改名避免遮挡",
                )


FILE_STEM_OK = {
    "Extensions", "Helpers", "Models", "Shared", "Utilities", "Support",
    "Tokens", "Typography", "Theme", "AppTheme", "Components", "Navigation",
    "Config", "Preview", "Mocks", "Router", "Routes", "Constants",
    # 契约 §3.12 明确规定的一个文件多个组件（聚合文件）
    "StateViews", "ScoreViews", "Charts", "ChartsData", "EcBlocks", "Sheets",
    "WordText", "Formatters", "ScorePresenter", "ContentViews", "JSONCoding",
}


# 契约 §3.12 明确规定的「文件名 ≠ 类型名」配对，属规范内的命名，不报。
FILENAME_PAIRS_OK = {
    ("WordText", "WordTextView"),
}


def check_filenames(models: list[SwiftFile], rep: Report) -> None:
    """文件名 = 主类型名（契约 §2.3 / §6.2）；聚合文件（一个域一个 DTO 文件）不强求。"""
    for sf in models:
        stem = sf.path.stem
        decls = [d for d in sf.decls if d.top_level and d.kind not in ("extension", "typealias")]
        if not decls:
            if sf.decls:
                # 只有 extension 的文件：名字应与被扩展类型相关（宽松，不报）
                continue
            if not sf.masked.strip():
                # 无任何代码（只有注释/空白）的空文件：不影响编译，属无害占位
                rep.info(
                    sf.rel,
                    1,
                    "文件名",
                    "空占位文件（无代码）：契约 §3.15 允许保留为空占位，也不影响构建",
                )
                continue
            rep.warn(sf.rel, 1, "文件名", "文件中没有顶层类型声明（只有全局函数/变量）")
            continue
        public = [d for d in decls if not d.private]
        if len(public) >= 2:
            # 聚合文件：一个域一个 DTO 文件 / 组件聚合文件（契约 §1 允许），只要 stem 与其中之一有关联即可
            if stem in {d.name for d in decls}:
                continue
            if any(d.name.startswith(stem) or stem.startswith(d.name) for d in decls):
                continue
            if stem in FILE_STEM_OK or stem.endswith(
                ("DTO", "DTOs", "Service", "Services", "API", "APIs",
                 # 契约 README §4 的四件套：XxxModels / XxxStore / Components
                 "Models", "Model", "Store", "Stores", "ViewModels", "Components",
                 "Extensions", "Types", "Support", "Routes", "Router")
            ):
                continue
            rep.warn(
                sf.rel,
                public[0].line,
                "文件名",
                f"聚合文件 '{stem}.swift' 与其主类型 '{public[0].name}' 无命名关联（建议按域命名，如 PracticeDTO.swift）",
            )
            continue
        if not public:
            # 只有文件级私有类型 + extension：视为支持文件，跳过
            continue
        primary = public[0]
        names = {d.name for d in decls}
        if stem == primary.name or stem in names:
            continue
        if (stem, primary.name) in FILENAME_PAIRS_OK:
            continue
        if any(n.startswith(stem) or stem.startswith(n) for n in names):
            rep.warn(
                sf.rel,
                primary.line,
                "文件名",
                f"文件名 '{stem}.swift' 与主类型 '{primary.name}' 不完全一致（允许的复数/前缀命名，建议改名）",
            )
            continue
        if stem in FILE_STEM_OK:
            continue
        rep.warn(
            sf.rel,
            primary.line,
            "文件名",
            f"文件名 '{stem}.swift' 与主类型 '{primary.name}' 不一致（契约 §2.3：文件名=类型名）",
        )


# --------------------------------------------------------------------------- #
# 6) project.yml
# --------------------------------------------------------------------------- #


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def _parse_inline_list(value: str) -> list[str] | None:
    value = value.strip()
    if not value.startswith("["):
        return None
    body = value[1 : value.rfind("]")] if "]" in value else value[1:]
    return [_unquote(part) for part in body.split(",") if part.strip()]


def parse_project_targets(text: str) -> dict[str, dict]:
    """极简 YAML 子集解析：只关心 targets.<name>.sources / settings / type / platform。"""
    lines = text.split("\n")
    targets: dict[str, dict] = {}
    i = 0
    n = len(lines)
    while i < n and not re.match(r"^targets:\s*$", lines[i].rstrip()):
        i += 1
    if i >= n:
        return targets
    i += 1
    while i < n:
        raw = lines[i]
        if not raw.strip():
            i += 1
            continue
        if _indent_of(raw) < 2:
            break
        m = re.match(r"^  ([A-Za-z0-9_.\-]+):\s*$", strip_yaml_comment(raw).rstrip())
        if not m:
            i += 1
            continue
        name = m.group(1)
        i += 1
        info: dict = {"sources": [], "settings": {}, "type": None, "platform": None}
        while i < n:
            raw2 = lines[i]
            if not raw2.strip():
                i += 1
                continue
            ind = _indent_of(raw2)
            if ind <= 2:
                break
            content = strip_yaml_comment(raw2).strip()
            if ind == 4 and content.startswith("type:"):
                info["type"] = _unquote(content.split(":", 1)[1])
                i += 1
            elif ind == 4 and content.startswith("platform:"):
                info["platform"] = _unquote(content.split(":", 1)[1])
                i += 1
            elif ind == 4 and content == "sources:":
                info["sources"], i = _parse_sources(lines, i + 1, 4)
            elif ind == 4 and content == "settings:":
                parsed, i = _parse_settings(lines, i + 1, 4)
                info["settings"].update(parsed)
            else:
                i += 1
        targets[name] = info
    return targets


def _parse_settings(lines: list[str], i: int, parent_indent: int) -> tuple[dict[str, str], int]:
    settings: dict[str, str] = {}
    n = len(lines)
    while i < n:
        raw = lines[i]
        if not raw.strip():
            i += 1
            continue
        if _indent_of(raw) <= parent_indent:
            break
        content = strip_yaml_comment(raw).strip()
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", content)
        if m and m.group(2).strip():
            settings[m.group(1)] = _unquote(m.group(2))
        i += 1
    return settings, i


def _assign_source_key(
    cur: dict, content: str, key_indent: int, lines: list[str], idx: int, n: int
) -> int:
    """解析 sources 条目里的一个 key: value（支持 excludes 的 YAML 列表）。返回下一行下标。"""
    if ":" not in content:
        return idx + 1
    key, value = content.split(":", 1)
    key = key.strip()
    value = value.strip()
    if key == "path":
        cur["path"] = _unquote(value)
    elif key == "buildPhase":
        cur["build_phase"] = _unquote(value)
    elif key == "excludes":
        inline = _parse_inline_list(value)
        if inline is not None:
            cur["excludes"].extend(inline)
        else:
            k = idx + 1
            while k < n:
                raw = lines[k]
                if not raw.strip():
                    k += 1
                    continue
                content_k = strip_yaml_comment(raw).strip()
                if _indent_of(raw) > key_indent and content_k.startswith("- "):
                    cur["excludes"].append(_unquote(content_k[2:].strip()))
                    k += 1
                    continue
                break
            return k
    return idx + 1


def _parse_sources(lines: list[str], i: int, parent_indent: int) -> tuple[list[dict], int]:
    """解析 XcodeGen 风格的 sources: 列表。"""
    sources: list[dict] = []
    n = len(lines)
    while i < n:
        raw = lines[i]
        if not raw.strip():
            i += 1
            continue
        ind = _indent_of(raw)
        if ind <= parent_indent:
            break
        content = strip_yaml_comment(raw).strip()
        if not content.startswith("- "):
            i += 1
            continue
        item_indent = ind
        body = content[2:].strip()
        cur: dict = {"path": None, "excludes": [], "build_phase": None}
        sources.append(cur)
        if ":" in body:
            i = _assign_source_key(cur, body, item_indent, lines, i, n)
        else:
            cur["path"] = _unquote(body)
            i += 1
        while i < n:
            raw2 = lines[i]
            if not raw2.strip():
                i += 1
                continue
            ind2 = _indent_of(raw2)
            content2 = strip_yaml_comment(raw2).strip()
            if ind2 <= item_indent or content2.startswith("- "):
                break
            i = _assign_source_key(cur, content2, ind2, lines, i, n)
    cleaned: list[dict] = []
    for item in sources:
        path = item.get("path")
        if path:
            item["path"] = path.strip()
            cleaned.append(item)
    return cleaned, i


def _matches_exclude(rel_to_source: str, rel_to_project: str, pattern: str) -> bool:
    """XcodeGen 的 excludes 是相对 source path 的 glob；同时容忍目录式写法（`App/`、`Resources/`）。"""
    pattern = pattern.replace("\\", "/").strip()
    if pattern.startswith("./"):
        pattern = pattern[2:]
    if not pattern:
        return False
    plain = pattern.rstrip("/")
    variants = {pattern, plain}
    # fnmatch 把 `*` 当作可跨 `/` 的任意串，但 `**/` 需要显式补齐「零层目录」语义
    if "**/" in pattern:
        variants.add(pattern.replace("**/", ""))
        variants.add(pattern.replace("**/", "*/"))
    for rel in (rel_to_source, rel_to_project):
        rel = rel.replace("\\", "/")
        for variant in variants:
            if not variant:
                continue
            if rel == variant:
                return True
            if fnmatch(rel, variant):
                return True
        # 目录式排除（"App/" 覆盖其下所有文件）
        if rel.startswith(plain + "/"):
            return True
    return False


def _coverage(sources: list[dict], swift_files: list[Path]) -> dict[Path, bool]:
    covered = {p: False for p in swift_files}
    for item in sources:
        raw_path = item["path"]
        source_abs = (IOS_ROOT / raw_path).resolve()
        excludes = item.get("excludes") or []
        for swift in swift_files:
            try:
                swift_rel_source = swift.resolve().relative_to(source_abs).as_posix()
            except ValueError:
                if swift.resolve() != source_abs:
                    continue
                swift_rel_source = swift.name
            swift_rel_project = rel(swift.resolve())  # 例如 EnglishCoach/App/X.swift
            if any(_matches_exclude(swift_rel_source, swift_rel_project, pat) for pat in excludes):
                continue
            covered[swift] = True
    return covered


def check_project_yml(models: list[SwiftFile], rep: Report) -> None:
    path = PROJECT_YML
    if not path.exists():
        rep.error(rel(path), 0, "工程", "project.yml 不存在（XcodeGen 工程描述缺失）")
        return
    text = read_text(path)
    targets = parse_project_targets(text)
    app = targets.get("EnglishCoach")
    if not app:
        rep.error(rel(path), 0, "工程", "project.yml 中没有 EnglishCoach target")
        return
    if app.get("type") not in (None, "application"):
        rep.error(rel(path), 0, "工程", f"EnglishCoach target type 应为 application，实际是 {app.get('type')}")
    if app.get("platform") not in (None, "iOS"):
        rep.error(rel(path), 0, "工程", f"EnglishCoach target platform 应为 iOS，实际是 {app.get('platform')}")

    sources = app["sources"]
    if not sources:
        rep.error(rel(path), 0, "工程", "EnglishCoach target 未声明 sources（源码不会进 target）")
    else:
        swift_files = [m.path for m in models]
        covered = _coverage(sources, swift_files)
        missing = [p for p, ok in covered.items() if not ok]
        for p in missing:
            rep.error(rel(path), 0, "工程", f"sources 未覆盖 {rel(p)}（该文件不会参与构建）")

        # Info.plist 必须从资源里排除，否则 Xcode 会 "Multiple commands produce Info.plist"
        info_plist_rel = "EnglishCoach/Resources/Info.plist"
        excluded = False
        for item in sources:
            for pat in item.get("excludes") or []:
                if _matches_exclude("Resources/Info.plist", info_plist_rel, pat) or _matches_exclude(
                    info_plist_rel, info_plist_rel, pat
                ):
                    excluded = True
                    break
            if excluded:
                break
        if not excluded:
            rep.error(
                rel(path),
                0,
                "工程",
                "Info.plist 未从 sources 中排除（会作为资源复制，导致 Multiple commands produce）",
            )

    settings: dict[str, str] = dict(app.get("settings") or {})
    # 顶层 settings.base 也可能承载公共设置：在全文里做兜底搜索
    def setting_value(key: str) -> str | None:
        if key in settings:
            return settings[key]
        m = re.search(rf"(?m)^\s*{re.escape(key)}:\s*(\S+)", text)
        if m:
            return _unquote(m.group(1))
        return None

    swift_version = setting_value("SWIFT_VERSION") or ""
    if not swift_version.startswith("6"):
        rep.error(rel(path), 0, "工程", f"SWIFT_VERSION 应为 \"6.0\"，实际是 {swift_version or '缺失'}")
    strict = setting_value("SWIFT_STRICT_CONCURRENCY") or ""
    if strict != "complete":
        rep.error(rel(path), 0, "工程", f"SWIFT_STRICT_CONCURRENCY 应为 complete，实际是 {strict or '缺失'}")
    bundle = setting_value("PRODUCT_BUNDLE_IDENTIFIER") or ""
    if bundle != "top.dreamsearch.englishcoach":
        rep.error(
            rel(path),
            0,
            "工程",
            f"PRODUCT_BUNDLE_IDENTIFIER 应为 top.dreamsearch.englishcoach，实际是 {bundle or '缺失'}",
        )
    info_file = setting_value("INFOPLIST_FILE") or ""
    if info_file != "EnglishCoach/Resources/Info.plist":
        rep.error(
            rel(path),
            0,
            "工程",
            f"INFOPLIST_FILE 应为 EnglishCoach/Resources/Info.plist，实际是 {info_file or '缺失'}",
        )
    # 部署目标：options.deploymentTarget.iOS / target.deploymentTarget / IPHONEOS_DEPLOYMENT_TARGET 都必须是 iOS 26.0
    deploy_values: list[tuple[str, str]] = []
    for pattern, label in (
        (r'(?m)^\s*iOS:\s*"?([0-9]+(?:\.[0-9]+)?)', "options.deploymentTarget.iOS"),
        (r'(?m)^\s*deploymentTarget:\s*"?([0-9]+(?:\.[0-9]+)?)', "target.deploymentTarget"),
        (r'(?m)^\s*IPHONEOS_DEPLOYMENT_TARGET:\s*"?([0-9]+(?:\.[0-9]+)?)', "IPHONEOS_DEPLOYMENT_TARGET"),
    ):
        for m in re.finditer(pattern, text):
            deploy_values.append((label, m.group(1)))
    if not deploy_values:
        rep.error(rel(path), 0, "工程", "未声明 deploymentTarget（契约 §0：最低 iOS 26.0）")
    for label, value in deploy_values:
        if not value.startswith("26"):
            rep.error(rel(path), 0, "工程", f"{label} 应为 26.0（最低 iOS 26），实际是 {value}")

    if not re.search(r"(?m)^schemes:\s*$", text):
        rep.warn(rel(path), 0, "工程", "没有 schemes 段：Xcode 里需要手动建 scheme")
    elif not re.search(r"(?m)^  EnglishCoach:\s*$", text):
        rep.warn(rel(path), 0, "工程", "schemes 中没有 EnglishCoach scheme")

    # 有测试源码却没配置测试 target → ERROR（测试被静默漏掉）
    tests_root = IOS_ROOT / "Tests"
    test_swifts = sorted(tests_root.rglob("*.swift")) if tests_root.exists() else []
    if test_swifts and "Tests/" not in text:
        rep.error(
            rel(path),
            0,
            "工程",
            f"Tests/ 下有 {len(test_swifts)} 个 Swift 测试文件，但 project.yml 未配置测试 target",
        )


# --------------------------------------------------------------------------- #
# 6) Info.plist / PrivacyInfo.xcprivacy / 资源
# --------------------------------------------------------------------------- #


def _plist_key_line(text: str, key: str) -> int:
    m = re.search(rf"<key>\s*{re.escape(key)}\s*</key>", text)
    if not m:
        return 0
    return text.count("\n", 0, m.start()) + 1


INFO_PLIST_PATH = SRC_ROOT / "Resources" / "Info.plist"
PRIVACY_PLIST_PATH = SRC_ROOT / "Resources" / "PrivacyInfo.xcprivacy"


def check_info_plist(rep: Report) -> None:
    path = INFO_PLIST_PATH
    rpath = rel(path)
    if not path.exists():
        rep.error(rpath, 0, "资源", "Info.plist 不存在（契约 §5）")
        return
    raw = read_text(path)
    try:
        plist = plistlib.loads(path.read_bytes())
    except Exception as exc:  # noqa: BLE001 - plistlib 抛多种异常
        rep.error(rpath, 0, "资源", f"Info.plist 不是合法 plist：{exc}")
        return
    if not isinstance(plist, dict):
        rep.error(rpath, 0, "资源", "Info.plist 根节点必须是 dict")
        return
    validate_info_plist(plist, raw, rpath, rep)


def validate_info_plist(plist: dict, raw: str, rpath: str, rep: Report) -> None:
    """Info.plist 必备键校验（独立函数便于自检/单测，不读文件）。"""
    def need(key: str) -> None:
        if key not in plist:
            rep.error(rpath, _plist_key_line(raw, key), "资源", f"Info.plist 缺少必备键 {key}")

    for key in (
        "CFBundleIdentifier",
        "CFBundleName",
        "CFBundleDisplayName",
        "CFBundleExecutable",
        "CFBundlePackageType",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "CFBundleDevelopmentRegion",
        "CFBundleInfoDictionaryVersion",
        "LSRequiresIPhoneOS",
    ):
        need(key)

    def non_empty_str(key: str) -> str | None:
        value = plist.get(key)
        if isinstance(value, str) and value.strip():
            return value
        rep.error(rpath, _plist_key_line(raw, key), "资源", f"Info.plist 键 {key} 缺失或不是非空字符串")
        return None

    mic = non_empty_str("NSMicrophoneUsageDescription")
    if mic:
        if "上传" not in mic:
            rep.error(
                rpath,
                _plist_key_line(raw, "NSMicrophoneUsageDescription"),
                "资源",
                "麦克风文案必须如实写明「录音会上传到服务器」（契约 §5 / README §7）",
            )
        if not any(word in mic for word in ("云端", "语音服务", "Azure", "云服务")):
            rep.error(
                rpath,
                _plist_key_line(raw, "NSMicrophoneUsageDescription"),
                "资源",
                "麦克风文案未提及音频会转发云端语音服务（hybrid 模式音频会离开家庭网络）",
            )
        for bad in ("不出户", "只留在", "不会离开", "仅保存在本机"):
            if bad in mic:
                rep.error(
                    rpath,
                    _plist_key_line(raw, "NSMicrophoneUsageDescription"),
                    "资源",
                    f"麦克风文案与事实不符：包含「{bad}」（音频会经服务器转发云端）",
                )
    for key in ("NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSLocalNetworkUsageDescription"):
        non_empty_str(key)

    bg = plist.get("UIBackgroundModes")
    if not isinstance(bg, list) or "audio" not in bg:
        rep.error(rpath, _plist_key_line(raw, "UIBackgroundModes"), "资源", "UIBackgroundModes 必须包含 audio")
    elif [str(x) for x in bg] != ["audio"]:
        rep.warn(
            rpath,
            _plist_key_line(raw, "UIBackgroundModes"),
            "资源",
            f"UIBackgroundModes 当前为 {bg}，契约只声明后台播放 audio（不要用于后台录音）",
        )

    if plist.get("ITSAppUsesNonExemptEncryption") is not False:
        rep.error(
            rpath,
            _plist_key_line(raw, "ITSAppUsesNonExemptEncryption"),
            "资源",
            "ITSAppUsesNonExemptEncryption 必须为 false（无自定义加密）",
        )

    portrait = {"UIInterfaceOrientationPortrait"}
    orient = plist.get("UISupportedInterfaceOrientations")
    if not isinstance(orient, list) or set(map(str, orient)) != portrait:
        rep.error(
            rpath,
            _plist_key_line(raw, "UISupportedInterfaceOrientations"),
            "资源",
            "UISupportedInterfaceOrientations 必须只包含 UIInterfaceOrientationPortrait（仅竖屏）",
        )
    ipad_orient = plist.get("UISupportedInterfaceOrientations~ipad")
    if ipad_orient is not None and (not isinstance(ipad_orient, list) or set(map(str, ipad_orient)) != portrait):
        rep.error(
            rpath,
            _plist_key_line(raw, "UISupportedInterfaceOrientations~ipad"),
            "资源",
            "iPad 方向也必须只允许竖屏（契约 §5）",
        )

    ats = plist.get("NSAppTransportSecurity")
    if isinstance(ats, dict):
        if ats.get("NSAllowsArbitraryLoads"):
            rep.error(rpath, _plist_key_line(raw, "NSAllowsArbitraryLoads"), "资源", "禁止开启 ATS 例外 NSAllowsArbitraryLoads")
        if ats.get("NSExceptionDomains"):
            rep.error(rpath, _plist_key_line(raw, "NSExceptionDomains"), "资源", "禁止 ATS 例外域（NSExceptionDomains）")
        if ats.get("NSAllowsLocalNetworking"):
            rep.warn(
                rpath,
                _plist_key_line(raw, "NSAllowsLocalNetworking"),
                "资源",
                "声明了 NSAllowsLocalNetworking：M0 要求 ATS 不加例外，仅排障期临时使用",
            )
    if "UILaunchScreen" not in plist:
        rep.warn(rpath, 0, "资源", "缺少 UILaunchScreen（iOS 26 上会影响启动屏/兼容尺寸）")
    if "UIApplicationSceneManifest" not in plist:
        rep.warn(rpath, 0, "资源", "缺少 UIApplicationSceneManifest（SwiftUI life cycle 建议显式声明）")


REQUIRED_ACCESS_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"E174.1"},
}
REQUIRED_COLLECTED = {
    "NSPrivacyCollectedDataTypeAudioData",
    "NSPrivacyCollectedDataTypeEmailAddress",
}


def check_privacy(rep: Report) -> None:
    path = PRIVACY_PLIST_PATH
    rpath = rel(path)
    if not path.exists():
        rep.error(rpath, 0, "隐私", "PrivacyInfo.xcprivacy 不存在（TestFlight/上架必需）")
        return
    try:
        data = plistlib.loads(path.read_bytes())
    except Exception as exc:  # noqa: BLE001
        rep.error(rpath, 0, "隐私", f"PrivacyInfo.xcprivacy 不是合法 plist：{exc}")
        return
    if not isinstance(data, dict):
        rep.error(rpath, 0, "隐私", "PrivacyInfo.xcprivacy 根节点必须是 dict")
        return
    validate_privacy(data, rpath, rep)


def validate_privacy(data: dict, rpath: str, rep: Report) -> None:
    """PrivacyInfo.xcprivacy 内容校验（独立函数便于自检，不读文件）。"""
    if data.get("NSPrivacyTracking") is not False:
        rep.error(rpath, 0, "隐私", "NSPrivacyTracking 必须为 false（本 App 不做跟踪）")
    if not isinstance(data.get("NSPrivacyTrackingDomains"), list):
        rep.warn(rpath, 0, "隐私", "缺少 NSPrivacyTrackingDomains 数组（无跟踪时给空数组）")

    collected = data.get("NSPrivacyCollectedDataTypes")
    by_type: dict[str, dict] = {}
    if not isinstance(collected, list):
        rep.error(rpath, 0, "隐私", "缺少 NSPrivacyCollectedDataTypes 数组")
    else:
        for entry in collected:
            if isinstance(entry, dict) and isinstance(entry.get("NSPrivacyCollectedDataType"), str):
                by_type[entry["NSPrivacyCollectedDataType"]] = entry
    for name in sorted(REQUIRED_COLLECTED):
        entry = by_type.get(name)
        if entry is None:
            rep.error(rpath, 0, "隐私", f"NSPrivacyCollectedDataTypes 缺少 {name}")
            continue
        if entry.get("NSPrivacyCollectedDataTypeLinked") is not True:
            rep.error(rpath, 0, "隐私", f"{name} 的 NSPrivacyCollectedDataTypeLinked 应为 true")
        if entry.get("NSPrivacyCollectedDataTypeTracking") is not False:
            rep.error(rpath, 0, "隐私", f"{name} 的 NSPrivacyCollectedDataTypeTracking 应为 false")
        purposes = entry.get("NSPrivacyCollectedDataTypePurposes")
        if not isinstance(purposes, list) or "NSPrivacyCollectedDataTypePurposeAppFunctionality" not in purposes:
            rep.error(
                rpath,
                0,
                "隐私",
                f"{name} 的 Purposes 必须包含 NSPrivacyCollectedDataTypePurposeAppFunctionality",
            )

    accessed = data.get("NSPrivacyAccessedAPITypes")
    access_map: dict[str, set[str]] = {}
    if not isinstance(accessed, list):
        rep.error(rpath, 0, "隐私", "缺少 NSPrivacyAccessedAPITypes 数组")
    else:
        for entry in accessed:
            if isinstance(entry, dict) and isinstance(entry.get("NSPrivacyAccessedAPIType"), str):
                reasons = entry.get("NSPrivacyAccessedAPITypeReasons")
                access_map[entry["NSPrivacyAccessedAPIType"]] = (
                    set(map(str, reasons)) if isinstance(reasons, list) else set()
                )
    for api, required_reasons in sorted(REQUIRED_ACCESS_APIS.items()):
        reasons = access_map.get(api)
        if reasons is None:
            rep.error(rpath, 0, "隐私", f"NSPrivacyAccessedAPITypes 缺少 {api}")
            continue
        missing = required_reasons - reasons
        if missing:
            rep.error(rpath, 0, "隐私", f"{api} 缺少 reason code {sorted(missing)}")


def check_assets(rep: Report) -> None:
    assets = SRC_ROOT / "Resources" / "Assets.xcassets"
    if not assets.exists():
        rep.warn(rel(assets), 0, "资源", "缺少 Assets.xcassets（App Icon 缺失，TestFlight 前必须补）")
        return
    for contents in sorted(assets.rglob("Contents.json")):
        try:
            json.loads(read_text(contents))
        except json.JSONDecodeError as exc:
            rep.error(rel(contents), 0, "资源", f"非法 JSON：{exc}")
    icon = assets / "AppIcon.appiconset"
    if not icon.exists():
        rep.warn(rel(assets), 0, "资源", "缺少 AppIcon.appiconset（ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon）")


def check_gitignore(rep: Report) -> None:
    if not GITIGNORE.exists():
        rep.warn(rel(GITIGNORE), 0, "工程", ".gitignore 不存在（.xcodeproj/build/DerivedData 会被误提交）")
        return
    text = read_text(GITIGNORE)
    checks = [".xcodeproj", "build", "DerivedData", "*.xcuserstate", ".DS_Store"]
    for token in checks:
        if token not in text:
            rep.warn(rel(GITIGNORE), 0, "工程", f".gitignore 未覆盖 {token}")


# --------------------------------------------------------------------------- #
# 7) 路由
# --------------------------------------------------------------------------- #

CASE_LINE_RE = re.compile(r"(?m)^[ \t]*case[ \t]+(.+)$")


def parse_app_route(models: list[SwiftFile]) -> tuple[dict[str, int] | None, str, int]:
    """返回 ({case: 关联值个数}, rel_path, 行号)。"""
    route_file: SwiftFile | None = None
    match = None
    for sf in models:
        m = re.search(r"\benum\s+AppRoute\b", sf.masked)
        if m:
            route_file = sf
            match = m
            break
    if route_file is None or match is None:
        return None, "", 0

    masked = route_file.masked
    brace = masked.find("{", match.end())
    if brace < 0:
        return None, route_file.rel, route_file.line(match.start())
    depth = 0
    end = len(masked)
    for idx in range(brace, len(masked)):
        if masked[idx] == "{":
            depth += 1
        elif masked[idx] == "}":
            depth -= 1
            if depth == 0:
                end = idx
                break
    body = masked[brace + 1 : end]
    body_start_line = route_file.line(brace)

    cases: dict[str, int] = {}
    # 逐行处理 case 行（case 可能跨行，先按顶层逗号合并）
    for m in CASE_LINE_RE.finditer(body):
        chunk = m.group(1)
        base_line = body_start_line + body.count("\n", 0, m.start())
        for part in split_top_level(chunk):
            part = part.strip()
            if not part or part.startswith("//"):
                continue
            nm = re.match(r"([A-Za-z_][A-Za-z0-9_]*)", part)
            if not nm:
                continue
            name = nm.group(1)
            rest = part[nm.end():]
            assoc = 0
            if rest.startswith("("):
                inner = rest[1:]
                paren_depth = 1
                buf: list[str] = []
                for ch in inner:
                    if ch == "(":
                        paren_depth += 1
                    elif ch == ")":
                        paren_depth -= 1
                        if paren_depth == 0:
                            break
                    buf.append(ch)
                inner_text = "".join(buf).strip()
                if inner_text:
                    assoc = len(split_top_level(inner_text))
            cases[name] = assoc
        _ = base_line
    return cases, route_file.rel, route_file.line(match.start())


def check_routes(models: list[SwiftFile], rep: Report) -> None:
    cases, route_rel, route_line = parse_app_route(models)
    if cases is None:
        rep.warn(
            "ios/EnglishCoach/App/Navigation/AppRoute.swift",
            0,
            "路由",
            "未找到 enum AppRoute（M0 尚未实现；契约 §3.14 要求 App/Navigation/AppRoute.swift）",
        )
        return

    missing = sorted(set(EXPECTED_ROUTES) - set(cases))
    extra = sorted(set(cases) - set(EXPECTED_ROUTES))
    for name in missing:
        rep.error(route_rel, route_line, "路由", f"AppRoute 缺少契约 §4 的 case '{name}'")
    for name in extra:
        rep.warn(route_rel, route_line, "路由", f"AppRoute 多出契约 §4 之外的 case '{name}'")
    for name, expected in sorted(EXPECTED_ROUTES.items()):
        if name in cases and cases[name] != expected:
            rep.warn(
                route_rel,
                route_line,
                "路由",
                f"case '{name}' 关联值个数为 {cases[name]}，契约要求 {expected}",
            )

    # ---- 分发覆盖：只认 App/RootTabView.swift 与 App/AppRoot.swift（契约 §6.7 / Lead 口径） ----
    dispatch_targets = [SRC_ROOT / "App" / "RootTabView.swift", SRC_ROOT / "App" / "AppRoot.swift"]
    existing = [p for p in dispatch_targets if p.exists()]
    route_blockers = sorted(cases)  # AppRoute 已声明的 case 都必须有分发（缺 case 已在上方报 ERROR）

    if not existing:
        for name in route_blockers:
            rep.warn(
                "ios/EnglishCoach/App/RootTabView.swift",
                0,
                "路由",
                f"AppRoute case '{name}' 无分发：App/RootTabView.swift 与 App/AppRoot.swift 均未落地（契约 §6.7）",
            )
        return

    covered: set[str] = set()
    dispatch_found = False
    for path in existing:
        sf = next((m for m in models if m.path.resolve() == path.resolve()), None)
        if sf is None:
            sf = SwiftFile(path)
            extract_decls(sf)
        if "navigationDestination" in sf.masked or re.search(
            r"switch\s+(?:route|appRoute|\$0|route\.self)", sf.masked
        ):
            dispatch_found = True
        for m in re.finditer(r"\bcase\s+\.?([A-Za-z_][A-Za-z0-9_]*)", sf.masked):
            covered.add(m.group(1))
        for m in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|:|,|\))", sf.masked):
            covered.add(m.group(1))

    missing_dispatch = sorted(set(EXPECTED_ROUTES) - covered)
    if not dispatch_found:
        # 文件已落地但分发结构还没写：逐条列出，不阻断（WARN）
        for name in missing_dispatch:
            rep.warn(
                rel(existing[0]),
                0,
                "路由",
                f"AppRoute case '{name}' 尚未在 App/RootTabView.swift / App/AppRoot.swift 中分发"
                f"（两个文件里都还没有 navigationDestination/switch）",
            )
        return
    for name in missing_dispatch:
        rep.error(
            rel(existing[0]),
            0,
            "路由",
            f"AppRoute case '{name}' 在 App/RootTabView.swift / App/AppRoot.swift 的 navigationDestination/switch 中缺失（契约 §6.7）",
        )


# --------------------------------------------------------------------------- #
# 页面入口（契约 §4：每个 Feature 域至少有一个页面）
# --------------------------------------------------------------------------- #


def check_feature_views(models: list[SwiftFile], rep: Report) -> None:
    features = SRC_ROOT / "Features"
    if not features.exists():
        return
    for domain in sorted(p for p in features.iterdir() if p.is_dir()):
        if domain.name.startswith(".") or domain.name == "Shared":
            # Shared 是跨域工具（Presenter/Formatter/图表数据），不是页面域
            continue
        files = list(domain.rglob("*.swift"))
        rel_dir = rel(domain)
        if not files:
            rep.warn(rel_dir, 0, "页面", f"Features/{domain.name}/ 存在但没有任何 Swift 文件（声明了目录却没页面）")
            continue
        view_files = [p for p in files if p.name.endswith("View.swift")]
        if not view_files:
            names = ", ".join(sorted(p.name for p in files)[:6])
            rep.warn(
                rel_dir,
                0,
                "页面",
                f"Features/{domain.name}/ 暂无 *View.swift（现有文件：{names}），缺少页面入口",
            )
    _ = models


# --------------------------------------------------------------------------- #
# 契约 §3.15 / §3.15.1：依赖注入约定 + 冻结的 Feature 根页面
# --------------------------------------------------------------------------- #

#: 契约 §3.15.1 冻结表格行：| Practice/PracticeView.swift | `PracticeView` | `(services: ...)` | ... |
FROZEN_PAGE_ROW_RE = re.compile(
    r"(?m)^\|\s*([A-Za-z][A-Za-z0-9_]*/[A-Za-z0-9_]+\.swift)\s*\|\s*`([A-Za-z][A-Za-z0-9_]*)`\s*\|\s*`([^`]*)`\s*\|"
)


def _type_body(masked: str, type_name: str) -> str | None:
    m = re.search(rf"\b(?:struct|final\s+class|class|actor)\s+{re.escape(type_name)}\b[^{{]*\{{", masked)
    if not m:
        return None
    start = m.end() - 1
    depth = 0
    for idx in range(start, len(masked)):
        ch = masked[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return masked[start : idx + 1]
    return None


def _init_param_labels(body: str) -> list[str] | None:
    m = re.search(r"\binit\s*\(", body)
    if not m:
        return None
    i = m.end() - 1
    depth = 0
    for j in range(i, len(body)):
        ch = body[j]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                inner = body[i + 1 : j]
                labels = re.findall(r"(?:^|,)\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", inner)
                return labels
    return None


def check_frozen_pages(models: list[SwiftFile], rep: Report) -> None:
    if not CONTRACT.exists():
        return
    text = read_text(CONTRACT)
    rows = [
        (m.group(1), m.group(2), m.group(3)) for m in FROZEN_PAGE_ROW_RE.finditer(text)
    ]
    if len(rows) < 5:
        rep.info(rel(CONTRACT), 0, "页面", "契约 §3.15.1 冻结页面表格解析失败（布局可能变了），本次跳过该检查")
        return

    by_path = {sf.path.resolve(): sf for sf in models}
    missing_files: list[str] = []
    for page_file, type_name, signature in rows:
        expected_path = (SRC_ROOT / "Features" / page_file).resolve()
        sf = by_path.get(expected_path)
        if sf is None:
            missing_files.append(f"{page_file}({type_name})")
            continue
        # 文件存在：必须声明契约冻结的类型名
        body = _type_body(sf.masked, type_name)
        if body is None:
            rep.error(
                sf.rel,
                1,
                "页面",
                f"契约 §3.15.1 冻结的页面类型 '{type_name}' 未在该文件中声明（B5 的 dispatcher 依赖此类型名）",
            )
            continue
        labels = _init_param_labels(body)
        if labels is None:
            rep.warn(
                sf.rel,
                1,
                "页面",
                f"'{type_name}' 没有显式 init(services:audio:...)（契约 §3.15.1 要求根页面自己声明 init）",
            )
            continue
        expected_labels = re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", signature)
        missing_labels = [label for label in expected_labels if label not in labels and label != "_"]
        if missing_labels:
            rep.warn(
                sf.rel,
                1,
                "页面",
                f"'{type_name}' 的 init 缺少契约 §3.15.1 要求的参数：{', '.join(missing_labels)}"
                f"（期望 {signature}，实际 {labels}）",
            )

    if missing_files:
        shown = "、".join(missing_files[:8])
        more = f" 等 {len(missing_files)} 个" if len(missing_files) > 8 else ""
        rep.warn(
            "ios/EnglishCoach/Features",
            0,
            "页面",
            f"契约 §3.15.1 冻结的根页面尚无对应文件：{shown}{more}（wave-2 未落地，属预期）",
        )
    # Core/AppServices.swift：契约 §3.15 明确要求 B5 放在 Core
    if not (SRC_ROOT / "Core" / "AppServices.swift").exists():
        rep.warn(
            "ios/EnglishCoach/Core/AppServices.swift",
            0,
            "页面",
            "契约 §3.15 要求 Core/AppServices.swift（struct AppServices，B5 实现）",
        )
    # 契约 §3.15：Features 只能通过构造参数拿依赖，禁止引用 AppEnvironment
    for sf in models:
        if "/Features/" not in sf.rel:
            continue
        m = re.search(r"\bAppEnvironment\b", sf.masked)
        if m:
            rep.warn(
                sf.rel,
                sf.line(m.start()),
                "分层",
                "契约 §3.15：Features 禁止引用 AppEnvironment（只能走构造参数 AppServices/AudioCoordinator）；M0 遗留代码需在 wave-2 改写",
            )


# --------------------------------------------------------------------------- #
# 8) API 一致性（启发式）
# --------------------------------------------------------------------------- #

SERVICE_DECL_RE = re.compile(r"\b(?:struct|final\s+class|class|actor|enum)\s+([A-Z][A-Za-z0-9_]*Service)\b")
SERVICE_EXT_RE = re.compile(r"\bextension\s+([A-Z][A-Za-z0-9_]*Service)\b")
FUNC_DECL_RE = re.compile(r"\bfunc\s+([a-zA-Z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\(")
SERVICE_CALL_RE = re.compile(
    r"\b([a-z][A-Za-z0-9_]*Service)\s*(?:\?|!)?\s*\.\s*([a-zA-Z_][A-Za-z0-9_]*)\s*\("
)


def check_api_calls(models: list[SwiftFile], rep: Report) -> None:
    service_funcs: dict[str, set[str]] = {}
    service_files: dict[str, str] = {}
    for sf in models:
        declared_here = set()
        for m in SERVICE_DECL_RE.finditer(sf.masked):
            service_funcs.setdefault(m.group(1), set())
            service_files.setdefault(m.group(1), sf.rel)
        for m in SERVICE_EXT_RE.finditer(sf.masked):
            service_funcs.setdefault(m.group(1), set())
            service_files.setdefault(m.group(1), sf.rel)
        # 只把「本文件声明/扩展的 Service」里的 func 归给该 Service
        for m in SERVICE_DECL_RE.finditer(sf.masked):
            declared_here.add(m.group(1))
        for m in SERVICE_EXT_RE.finditer(sf.masked):
            declared_here.add(m.group(1))
        for svc in declared_here:
            for fm in FUNC_DECL_RE.finditer(sf.masked):
                service_funcs[svc].add(fm.group(1))
        _ = declared_here

    if not service_funcs:
        return

    for sf in models:
        for m in SERVICE_CALL_RE.finditer(sf.masked):
            var = m.group(1)
            method = m.group(2)
            svc = var[0].upper() + var[1:]
            if svc not in service_funcs:
                # 可能是协议/局部变量，交给「符号」规则
                continue
            if method in service_funcs[svc] or method in {"init", "self"}:
                continue
            if service_files.get(svc) == sf.rel:
                continue
            rep.warn(
                sf.rel,
                sf.line(m.start(2)),
                "API",
                f"调用了 {svc} 上未声明的方法 '{method}'（契约 §3 的方法签名必须逐字一致）",
            )


# --------------------------------------------------------------------------- #
# 词法/配平自检（--selftest，只读）
# --------------------------------------------------------------------------- #

#: (名称, 源码, 期望括号错误数, 期望条件编译错误数, 期望未闭合字符串数, 期望未闭合注释数)
SELFTEST_CASES: list[tuple[str, str, int, int, int, int]] = [
    ("字符串里的括号", 'let a = "("\n', 0, 0, 0, 0),
    ("行注释里的括号", 'let a = foo("x") // )\n', 0, 0, 0, 0),
    ("嵌套块注释", "/* /* */ */\nlet x = 1\n", 0, 0, 0, 0),
    ("多行字符串", 'let s = """\n{ ( [\n"""\n', 0, 0, 0, 0),
    ("原始字符串", 'let s = #"a " b"#\n', 0, 0, 0, 0),
    ("字符串转义", 'let s = "a \\" b"\n', 0, 0, 0, 0),
    ("字符串插值", 'let s = "\\(view.map { $0 })"\n', 0, 0, 0, 0),
    ("注释里的 #if", "// #if DEBUG\n", 0, 0, 0, 0),
    ("未闭合字符串", 'let s = "abc\n', 0, 0, 1, 0),
    ("未闭合多行字符串", 'let s = """\nabc\n', 0, 0, 1, 0),
    ("未闭合块注释", "/* 未闭合\nlet x = 1\n", 0, 0, 0, 1),
    ("未闭合左花括号", "func f() {\n", 1, 0, 0, 0),
    ("多余右括号", "let x = 1)\n", 1, 0, 0, 0),
    ("#if 配平", "#if DEBUG\nlet a = 1\n#else\nlet b = 2\n#endif\n", 0, 0, 0, 0),
    ("#if 未闭合", "#if DEBUG\nlet a = 1\n", 0, 1, 0, 0),
    ("孤立 #endif", "let a = 1\n#endif\n", 0, 1, 0, 0),
]


def selftest() -> int:
    failures = 0
    for name, source, want_br, want_cond, want_str, want_comment in SELFTEST_CASES:
        lexer = Lexer(source)
        masked = lexer.run()
        br = bracket_errors(masked)
        cond = conditional_errors(masked)
        unclosed_str = [x for x in lexer.unclosed_strings if x[1] != "interp"]
        got = (len(br), len(cond), len(unclosed_str), len(lexer.unclosed_comments))
        want = (want_br, want_cond, want_str, want_comment)
        if got == want:
            print(f"PASS  {name}")
        else:
            failures += 1
            print(f"FAIL  {name}: 期望 (括号,条件编译,字符串,注释)={want}，实际 {got}")
            if br:
                print(f"      括号: {br}")
            if cond:
                print(f"      条件编译: {cond}")
    print()
    if failures:
        print(f"selftest FAILED：{failures} 个用例失败")
        return 1
    print(f"selftest OK：{len(SELFTEST_CASES)} 个词法/配平用例全部通过")
    return 0


# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #


def collect_swift_files() -> list[Path]:
    if not SRC_ROOT.exists():
        return []
    files: list[Path] = []
    for path in sorted(SRC_ROOT.rglob("*.swift")):
        parts = set(path.parts)
        if parts & {".build", "DerivedData", ".git", "build"}:
            continue
        files.append(path)
    return files


def main(argv: list[str]) -> int:
    limit_warn = 200
    list_declared = False
    selftest_mode = False
    i = 1
    while i < len(argv):
        arg = argv[i]
        if arg == "--selftest":
            selftest_mode = True
            i += 1
            continue
        if arg == "--limit-warn" and i + 1 < len(argv):
            try:
                limit_warn = int(argv[i + 1])
            except ValueError:
                pass
            i += 2
            continue
        if arg.startswith("--limit-warn="):
            try:
                limit_warn = int(arg.split("=", 1)[1])
            except ValueError:
                pass
            i += 1
            continue
        if arg == "--list-declared":
            list_declared = True
            i += 1
            continue
        if arg in ("-h", "--help"):
            print(__doc__)
            return 0
        i += 1

    try:  # Windows 控制台默认 GBK，强制 UTF-8 以便中文/箭头正常显示
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:  # noqa: BLE001 - 旧环境不支持就算了
        pass

    if selftest_mode:
        return selftest()

    rep = Report()
    paths = collect_swift_files()
    if not paths:
        rep.error(rel(SRC_ROOT), 0, "工程", "未找到任何 Swift 源文件（EnglishCoach/ 是否存在？）")
        models: list[SwiftFile] = []
    else:
        models = [SwiftFile(p) for p in paths]

    for sf in models:
        check_lexical(sf, rep)
        extract_decls(sf)
        check_conventions(sf, rep)
        check_imports(sf, rep)
        check_layering(sf, rep)

    declared = build_declared(models)
    check_uniqueness(models, rep)
    check_filenames(models, rep)
    check_symbol_refs(models, declared, rep, limit_warn)
    check_contract_types(models, declared, rep)
    check_project_yml(models, rep)
    check_info_plist(rep)
    check_privacy(rep)
    check_assets(rep)
    check_gitignore(rep)
    check_routes(models, rep)
    check_api_calls(models, rep)
    check_feature_views(models, rep)
    check_frozen_pages(models, rep)

    if list_declared:
        print("declared types:")
        for name in sorted(declared):
            print(f"  {name}")

    # ---------------- 输出（按 file:line 分组） ----------------
    print("English Coach iOS 静态校验（只读；本机无 Xcode，未经编译验证）")
    print(f"源码根: {rel(SRC_ROOT)}  |  .swift 文件: {len(models)}  |  契约: {rel(CONTRACT)}")
    print()

    sev_order = {ERROR: 0, WARN: 1, INFO: 2}
    issues = sorted(rep.issues, key=lambda it: (it.path, it.line, sev_order.get(it.sev, 9), it.cat, it.msg))
    cap_categories = {"符号": limit_warn, "契约类型缺失": 80}
    shown_per_cat: dict[str, int] = {}
    truncated: dict[str, tuple[int, int]] = {}
    for it in issues:
        cap = cap_categories.get(it.cat)
        if cap is not None and cap > 0:
            used = shown_per_cat.get(it.cat, 0)
            if used >= cap:
                total = truncated.get(it.cat, (cap, 0))
                truncated[it.cat] = (total[0], total[1] + 1)
                continue
            shown_per_cat[it.cat] = used + 1
        loc = it.path if it.line <= 0 else f"{it.path}:{it.line}"
        print(f"{it.sev:5s} {loc}  [{it.cat}] {it.msg}")
    for cat, (cap, extra) in sorted(truncated.items()):
        print(f"WARN  （{cat} 类另有 {extra} 条未列出；--limit-warn 0 可展开）")

    errors = rep.count(ERROR)
    warnings = rep.count(WARN)
    infos = rep.count(INFO)
    if errors == 0 and warnings == 0:
        print(f"OK：未发现 ERROR / WARN" + (f"（另有 {infos} 条 INFO 提示，不计入 WARN）" if infos else ""))
    elif errors == 0:
        print(f"OK：没有 ERROR（有 {warnings} 条 WARN 提示，不阻断）")
    else:
        print(f"FAILED：存在 {errors} 条 ERROR（必须修复后才能算通过静态校验）")
    if infos:
        print(f"INFO 提示（不计入 WARN 计数）= {infos}")
    print(f"SUMMARY errors={errors} warnings={warnings} files={len(models)}")
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
