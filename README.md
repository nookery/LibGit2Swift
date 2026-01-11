# LibGit2Swift

A type-safe Swift wrapper around [libgit2](https://libgit2.org/), providing a native Swift interface for Git operations without relying on shell commands.

## Overview

LibGit2Swift is a Swift library that wraps the libgit2 C library, offering a clean, Swifty API for programmatic Git operations. It's designed for applications that need to interact with Git repositories directly, such as IDEs, version control clients, or developer tools.

## Features

### Repository Management
- Create new Git repositories
- Check if a path is a Git repository
- Get repository root directory
- Get HEAD reference and current branch
- Check if HEAD is detached
- Get repository status and path information

### Configuration Management
- Get and set Git configuration values
- Manage user configuration (name, email)
- Handle both repository-specific and global configuration

### Branch Operations
- List local and remote branches
- Create, delete, and rename branches
- Get current branch information
- Manage branch upstream relationships

### Commit Operations
- Get commit history with pagination support
- Create new commits
- Amend existing commits
- Add files and commit in one operation
- Get detailed commit information including references and tags

### File Operations
- Add files to staging area (single files or all changes)
- Checkout files, branches, or specific commits
- Check for uncommitted changes
- Get file status and diff information

### Remote Management
- List remote repositories
- Add, remove, and configure remotes
- Get and set remote URLs
- Rename remotes

### Diff Operations
- Get diff between working tree and index
- Get diff between index and HEAD
- Compare commits and show changes
- Get file content from specific commits

### Additional Features
- Tag operations (create, list, delete)
- Reset operations (soft, mixed, hard)
- Merge operations
- Stash operations
- Network operations (fetch, pull, push)

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Installation

### Swift Package Manager

Add LibGit2Swift as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Coffic/LibGit2Swift.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/Coffic/LibGit2Swift.git`
3. Select the version rule

## Usage

### Initialize a Repository

```swift
import LibGit2Swift

// Create a new repository
let repository = try LibGit2.createRepository(at: "/path/to/project")

// Open an existing repository
let repository = try LibGit2.Repository(at: "/path/to/existing/repo")
```

### Get Repository Status

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// Get HEAD
let head = try repository.getHead()
print("Current branch: \(head.branchName)")

// Check if there are uncommitted changes
let hasChanges = try repository.hasUncommittedChanges()
```

### Branch Operations

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// List branches
let branches = try repository.getBranches()

// Create a new branch
try repository.createBranch(name: "feature-branch")

// Delete a branch
try repository.deleteBranch(name: "old-branch")

// Rename a branch
try repository.renameBranch(oldName: "old-name", newName: "new-name")
```

### Commit Operations

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// Get commit history
let commits = try repository.getCommits(maxCount: 10)

// Create a commit
try repository.commit(message: "Add new feature", authorName: "John Doe", authorEmail: "john@example.com")

// Add file and commit in one operation
try repository.addAndCommit(path: "file.swift", message: "Add file.swift", authorName: "John Doe", authorEmail: "john@example.com")
```

### Working with Files

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// Stage a file
try repository.add(path: "file.swift")

// Stage all changes
try repository.addAll()

// Get file status
let status = try repository.getStatus()
```

### Remote Operations

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// List remotes
let remotes = try repository.getRemotes()

// Add a remote
try repository.addRemote(name: "origin", url: "https://github.com/user/repo.git")

// Get remote URL
if let url = try repository.getRemoteURL(name: "origin") {
    print("Remote URL: \(url)")
}
```

### Diff Operations

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// Get working tree vs index diff
let diff = try repository.getDiffWorkingTreeVsIndex()

// Get index vs HEAD diff
let diff = try repository.getDiffIndexVsHEAD()

// Get diff between commits
let diff = try repository.getDiffCommit(commitOid: "abc123", parentCommitOid: "def456")
```

## Error Handling

LibGit2Swift provides comprehensive error handling with meaningful error messages:

```swift
do {
    let repository = try LibGit2.Repository(at: "/path/to/repo")
    // Perform operations...
} catch LibGit2.Error.repositoryNotFound(let path) {
    print("Repository not found at: \(path)")
} catch LibGit2.Error.invalidReference(let message) {
    print("Invalid reference: \(message)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

## Project Structure

```
Sources/LibGit2Swift/
├── LibGit2Swift.swift       # Public API entry point
├── LibGit2Wrapper.swift      # Core wrapper with configuration
├── LibGit2Models.swift       # Data models (GitBranch, GitCommit, etc.)
├── Repository.swift         # Repository operations
├── Branch.swift             # Branch management
├── Commit.swift              # Commit history and details
├── Commit+Write.swift        # Commit creation and modification
├── Add.swift                 # File staging operations
├── Status.swift             # Status checking
├── Checkout.swift           # Branch and file checkout
├── Remote.swift              # Remote repository management
├── Diff.swift                # Diff operations
├── Tag.swift                 # Tag operations
├── Reset.swift               # Reset operations
├── Merge.swift               # Merge operations
├── Stash.swift               # Stash operations
└── Network.swift             # Network operations
```

## Design Principles

1. **Type Safety**: Swift enums and structs provide compile-time safety
2. **Automatic Memory Management**: Proper cleanup of C library resources
3. **Swift Native API**: Swift-friendly design patterns and conventions
4. **Comprehensive Error Handling**: Meaningful error messages and recovery suggestions
5. **Modular Structure**: Each Git operation has its own Swift file for organization

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available under the MIT license. See the LICENSE file for more info.

## Acknowledgments

- Built on top of [libgit2](https://libgit2.org/)
- Inspired by the need for a pure Swift Git library without shell dependencies
