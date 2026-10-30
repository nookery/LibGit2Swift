import Foundation
import Clibgit2
import OSLog

extension LibGit2 {
    /// Unstage specified files (equivalent to `git reset HEAD -- <paths>`).
    ///
    /// Restages the index entries for the specified files to match HEAD.
    /// - For tracked files: the index entry is reset to the HEAD version.
    /// - For new files (not in HEAD): the entry is removed from the index.
    ///
    /// The working directory content is **not** modified.
    ///
    /// - Parameters:
    ///   - filePaths: Relative paths (to the repo workdir) to unstage.
    ///                Empty strings in the array are silently skipped.
    ///   - path: Path to the Git repository.
    ///   - verbose: Whether to emit log messages. Defaults to `true`.
    /// - Throws: `LibGit2Error` if the repository cannot be opened or the
    ///           reset operation fails.
    public static func unstageFiles(
        _ filePaths: [String],
        at path: String,
        verbose: Bool = true
    ) throws {
        let paths = filePaths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }

        try LibGit2.serialized(at: path) {
            if verbose {
                os_log("\(self.t)Unstaging \(paths.count) file(s)")
            }

            let repo = try openRepositoryUnlocked(at: path)
            defer { git_repository_free(repo) }

            // Resolve HEAD — nil target means "remove matching index entries"
            // (used for empty repos with no commits yet).
            let target = resolveHEADObject(repo: repo)
            defer {
                if let target { git_object_free(target) }
            }

            // Build a git_strarray from the path list.
            var cStrings = paths.map { strdup($0) }
            defer { cStrings.forEach { free($0) } }

            let result = cStrings.withUnsafeMutableBufferPointer { buffer -> Int32 in
                var pathspecs = git_strarray(
                    strings: buffer.baseAddress,
                    count: paths.count
                )
                return git_reset_default(repo, target, &pathspecs)
            }

            guard result == 0 else {
                throw LibGit2Error.cannotGetIndex
            }

            if verbose {
                os_log("\(self.t)Files unstaged successfully")
            }
        }
    }

    /// Unstage a single file (equivalent to `git reset HEAD -- <path>`).
    ///
    /// - Parameters:
    ///   - filePath: Relative path to the file to unstage.
    ///   - path: Path to the Git repository.
    ///   - verbose: Whether to emit log messages. Defaults to `true`.
    public static func unstageFile(
        _ filePath: String,
        at path: String,
        verbose: Bool = true
    ) throws {
        try unstageFiles([filePath], at: path, verbose: verbose)
    }

    // MARK: - Private Helpers

    /// Resolve HEAD to a commit object, or return `nil` if the repository
    /// has no commits yet (empty / unborn branch).
    private static func resolveHEADObject(repo: OpaquePointer) -> OpaquePointer? {
        var headOID = git_oid()
        guard git_reference_name_to_id(&headOID, repo, "HEAD") == 0 else {
            return nil
        }

        var object: OpaquePointer?
        guard git_object_lookup(&object, repo, &headOID, GIT_OBJECT_ANY) == 0 else {
            return nil
        }

        return object
    }
}
