# Swift 代码组织规范

> 本规范定义了 LibGit2Swift 项目中 Swift 文件的代码组织方式和结构约定。

---

## 核心原则

**代码组织清晰，遵循统一的层次结构，便于维护和扩展。**

---

## 文件结构模板

```swift
import Foundation

/// 类型名称
///
/// 类型的功能描述
public final class TypeName {

    // MARK: - 常量/静态属性

    static let constantName: Type = value

    // MARK: - 属性

    public let propertyName: Type

    // MARK: - 初始化

    public init() {
        // 初始化逻辑
    }

    // MARK: - 公开方法

    public func publicMethod() {
        // 实现
    }

    // MARK: - 私有方法

    private func privateMethod() {
        // 实现
    }

    // MARK: - 计算属性

    private var calculatedProperty: Type {
        // 实现
    }
}

// MARK: - 扩展

extension TypeName: ProtocolName {
    // 协议实现
}
```

---

## MARK 注释规范

### 标准分段顺序

1. `// MARK: - 常量/静态属性`
2. `// MARK: - 属性`
3. `// MARK: - 初始化`
4. `// MARK: - 公开方法`
5. `// MARK: - 私有方法`
6. `// MARK: - 计算属性`
7. `// MARK: - 扩展`

### 使用规则

- 每个主要分段使用 `// MARK: - 标题`
- 相关方法之间可用 `// MARK:` 分组（无标题）
- 分段之间保留一个空行

---

## 库项目的具体约定

本项目是 **SPM 库**（非 App），以下约定与 App 项目不同：

| 维度 | 约定 |
|------|------|
| **可见性** | 对外 API 一律 `public`；内部实现用 `internal` / `private`，不写 `open` |
| **资源管理** | libgit2 对象需显式释放（`deinit` 中 `free()`），封装类型优先用 `Reference` 模式持有原始指针 |
| **线程安全** | libgit2 非线程安全，公开 API 须走 `LibGit2.serialized` 串行化包装；并发场景用 `actor` 隔离 |
| **错误处理** | 对外 API 抛 `throws`，错误类型集中在 `GitError` 枚举，不要散落 `NSError` |
| **空值** | 避免 `force unwrap`；底层 C API 返回 nullable 时用可选绑定 + 明确错误信息 |
| **文档** | 所有 `public` 类型与方法必须有 `///` 文档注释（见 [Swift 注释规范](./swift-comment.md)） |

### 分层建议

```
Sources/LibGit2Swift/
├── LibGit2Swift.swift        # 库的公共入口与门面类型
├── Repository/               # 仓库级操作
│   ├── Repository.swift
│   ├── Commit.swift
│   ├── Branch.swift
│   └── ...
├── Support/                  # 底层封装与工具
│   ├── LibGit2.swift         # 初始化、串行化、生命周期
│   ├── Reference.swift       # 原始指针持有与释放
│   └── ...
└── Models/                   # 数据模型
    ├── GitStatus.swift
    └── ...
```

> 目录划分以「按功能域聚合」为准，不要求与文件名一一对应；
> 同一功能域的多个小类型可以放在同一文件内，但**一个文件只服务一个功能域**。

---

## 相关规范

- [Swift 注释规范](./swift-comment.md)
- [最少功能原则](./minimal-functionality.md)
- [单元测试规范](./unit-test-rules.md)
