import Foundation
import Testing

@testable import ColibriKit

@Suite("Running commands")
struct ProcessTests {
    @Test func capturesOutput() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"], environment: [:])
        #expect(out.succeeded)
        #expect(out.stdout == "hello\n")
    }

    @Test func reportsExitCodeAndStderr() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo oops >&2; exit 3"], environment: [:])
        #expect(out.exitCode == 3)
        #expect(!out.succeeded)
        #expect(out.stderr == "oops\n")
    }

    @Test func passesOnlyTheGivenEnvironment() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"), environment: ["FOO": "bar"])
        #expect(out.stdout == "FOO=bar\n")
    }

    @Test func stopsACommandThatRunsTooLong() async throws {
        await #expect(throws: ProcessError.timedOut) {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: [:],
                timeout: .milliseconds(300))
        }
    }

    @Test func doesNotWaitForABackgroundChild() async throws {
        // `coli start` leaves a server running. Reading from a pipe would block until it exited.
        let clock = ContinuousClock()
        let started = clock.now
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 3 & echo started"], environment: [:])
        #expect(out.stdout == "started\n")
        #expect(clock.now - started < .seconds(2))
    }

    @Test func reportsAMissingExecutable() async {
        await #expect(throws: ProcessError.self) {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/nonexistent/tool"), environment: [:])
        }
    }
}

@Suite("coli launcher")
struct LauncherTests {
    let cli = ColiCLI(
        launcher: ColiLauncher(
            python: URL(fileURLWithPath: "/bin/echo"), script: URL(fileURLWithPath: "/opt/colibri/c/coli")))

    @Test func runsTheScriptWithItsArguments() async throws {
        let out = try await cli.run(["status", "--json"])
        #expect(out.stdout == "/opt/colibri/c/coli status --json\n")
    }

    @Test func buildsACleanEnvironmentForOneSetupHome() {
        let home = URL(fileURLWithPath: "/tmp/Application Support/colibri-glm-5.3")
        let env = cli.environment(setupHome: home)
        #expect(env["COLI_SETUP_HOME"] == home.path)
        #expect(env["PATH"]?.hasPrefix("/opt/homebrew/bin") == true)
        #expect(Set(env.keys).isSubset(of: ["PATH", "HOME", "LANG", "TMPDIR", "COLI_SETUP_HOME"]))
        #expect(cli.environment(setupHome: nil)["COLI_SETUP_HOME"] == nil)
    }

    @Test func dropsTextBeforeTheJSON() {
        let data = ColiCLI.jsonData(in: "  note: starting\n{\"a\": 1}", opener: "{")
        #expect(String(decoding: data, as: UTF8.self) == "{\"a\": 1}")
    }

    @Test func parsesPythonVersions() throws {
        let new = try #require(LauncherLocator.parsePythonVersion("Python 3.15.2\n"))
        #expect(new.0 == 3 && new.1 == 15)
        let old = try #require(LauncherLocator.parsePythonVersion("Python 3.9.6"))
        #expect(old.0 == 3 && old.1 == 9)
        #expect(LauncherLocator.parsePythonVersion("not python") == nil)
    }

    @Test func readsTheInstalledColibriVersion() {
        let text = "\"\"\"Single source of truth for the colibri version number.\"\"\"\n\n__version__ = \"2.1.0\"\n"
        #expect(ColiLauncher.parseVersion(text) == "2.1.0")
        #expect(ColiLauncher.parseVersion("nothing here") == nil)
    }

    @Test func findsNothingWithoutAColiScript() {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(LauncherLocator.locate(hints: [], home: empty, environment: [:]) == nil)
    }
}
