# Swift 注释规范

> 本规范定义了 LibGit2Swift 项目中 Swift 代码的注释编写方式和标准。

---

## 核心原则

**注释应当简洁、清晰、有用，解释"为什么"而不是"是什么"。**

---

## 文档注释

### 类型注释

```swift
/// 类型名称
///
/// 类型的功能描述，可以跨多行。
/// 支持 *Markdown* 格式。
///
/// ## 使用示例
///
/// ```swift
/// let instance = TypeName()
/// ```
///
/// - Note: 重要说明
/// - Warning: 警告信息
/// - SeeAlso: 相关类型
public class TypeName {
}
```

### 函数注释

```swift
/// 函数功能描述
///
/// 详细说明函数的行为和用途。
///
/// - Parameters:
///   - param1: 参数 1 描述
///   - param2: 参数 2 描述
///
/// - Returns: 返回值描述
///
/// - Throws: 可能抛出的错误
///
/// - Note: 重要说明
public func functionName(param1: Type, param2: Type) throws -> ReturnType {
}
```

### 属性注释

```swift
/// 属性描述
public var propertyName: Type
```

---

## 行内注释

### 使用规则

```swift
// ✅ 好：解释为什么
if repository.isBare {
    showBareWarning()  // 裸仓库没有工作区，状态查询无意义
}

// ❌ 避免：重复代码
repository.isBare  // 检查仓库是否裸库
```

### 待办事项

```swift
// TODO: 实现缓存逻辑
// FIXME: 修复内存泄漏
// NOTE: 这是一个临时解决方案
// HACK: 临时变通方案
```

---

## MARK 注释

用于代码分段组织：

```swift
// MARK: - 初始化

public init() {
}

// MARK: - 公开方法

public func publicMethod() {
}

// MARK: - 私有方法

private func privateMethod() {
}
```

---

## 库项目的具体约定

本项目对外暴露的是 **SPM 公共 API**，注释的首要读者是 API 使用者：

| 场景 | 要求 |
|------|------|
| **`public` 类型 / 方法** | **必须**有 `///` 文档注释，说明功能、参数、返回值、抛出的错误 |
| **`public` 方法抛出错误** | 必须用 `- Throws:` 说明**具体**错误类型与触发条件 |
| **libgit2 原始指针操作** | 必须注明内存管理责任（谁负责 `free`、何时释放） |
| **线程安全说明** | 若该 API 受 `LibGit2.serialized` 保护或可并发调用，需在注释中写明 |
| **`internal` / `private` 代码** | 关键决策处加行内注释解释「为什么」，不必写文档注释 |
| **协议实现** | 用 `// MARK: - <ProtocolName>` 标注，方便与协议声明对照 |

### 内存管理注释示例

```swift
/// 持有 libgit2 原始指针并在释放时自动回收。
///
/// 线程安全：不可跨线程共享同一实例。
public final class Reference<T> {
    /// 指向 libgit2 对象的原始指针。
    ///
    /// 生命周期由本类型管理，外部不得直接释放。
    private let pointer: UnsafeMutablePointer<T>
}
```

---

## 相关规范

- [代码组织规范](./swift-code-organization.md)
- [最少功能原则](./minimal-functionality.md)
