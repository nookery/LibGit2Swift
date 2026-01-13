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
    .package(url: "https://github.com/nookery/LibGit2Swift.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/nookery/LibGit2Swift.git`
3. Select the version rule

## Building

### Dependency Versions

- **libgit2**: v1.9.2 (December 2025)
- **OpenSSL**: 3.4.3
- **libssh2**: 1.11.1

### Initial Build Steps

For the first use or when updating dependency versions, you need to manually build `Clibgit2.xcframework`:

```bash
cd Scripts
./build-libgit2-framework.sh
```

#### Build Process Description

The script will automatically perform the following operations:

1. Download dependency source code:
   - OpenSSL 3.4.3
   - libssh2 1.11.1
   - libgit2 v1.9.2

2. Compile static libraries for the following platforms:
   - iOS (arm64)
   - iOS Simulator (x86_64)
   - macOS (arm64)
   - macOS (x86_64)
   - Mac Catalyst (arm64 + x86_64)

3. Create `Sources/Clibgit2.xcframework` and copy module map

#### Build Time

The entire build process takes approximately **10-20 minutes**, depending on your network speed and CPU performance.

#### System Requirements

- macOS 14.0+
- Xcode 15.0+
- CMake (usually installed with Xcode)
- wget (for downloading source code)

If wget is not installed:
```bash
brew install wget
```

### After Building

After successful build, the `Sources/Clibgit2.xcframework` file will be generated.

You can then use Swift Package Manager normally:

```bash
# In LibGit2Swift directory
swift build
```

Or in other projects:

```bash
cd /path/to/your/project
swift build
```

### Daily Development

Once `Clibgit2.xcframework` is built and committed to the repository, subsequent development doesn't require rebuilding unless:

1. Need to update dependency versions (modify version numbers in `Scripts/build-libgit2-framework.sh`)
2. Add new platform support
3. Regenerate xcframework

### Version Updates

If you need to update dependency versions:

1. Edit `Scripts/build-libgit2-framework.sh`
2. Modify the following version numbers:
   - `openssl-X.X.X`
   - `libssh2-X.X.X`
   - `vX.X.X` (libgit2)
3. Re-run the build script

### Troubleshooting

#### Build Failed: wget not found

```bash
brew install wget
```

#### Build Failed: CMake Error

Make sure Xcode command line tools are installed:
```bash
xcode-select --install
```

#### Package.swift Error: Clibgit2.xcframework not found

Please run the build script first to generate the xcframework:
```bash
cd Scripts
./build-libgit2-framework.sh
```

### Key Improvements

Advantages compared to using external `static-libgit2` packages:

1. ✅ **Latest libgit2** (v1.9.2 vs v1.3.0)
2. ✅ **Independent maintenance**, no longer dependent on external packages
3. ✅ **Better SSH support**, new libgit2 has better OpenSSH key format support
4. ✅ **Full control**, can customize build options
5. ✅ **Timely updates**, can update to latest versions anytime

### Technical Details

#### XCFramework Structure

The generated xcframework contains the following platforms:
- `ios-arm64` (iOS devices)
- `ios-x86_64-simulator` (iOS simulator)
- `macosx-arm64` (Apple Silicon Mac)
- `macosx-x86_64` (Intel Mac)
- `maccatalyst-arm64_x86_64` (Mac Catalyst universal)

#### Linker Settings

Package.swift configures the necessary linker settings:
```swift
linkerSettings: [
    .linkedLibrary("z"),      // zlib (compression library)
    .linkedLibrary("iconv")   // character encoding conversion library
]
```

These libraries are built into macOS and don't require separate installation.

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
