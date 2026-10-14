import Foundation
import Vapor

/// Ensures a local Python venv + Trainer requirements are available for server-side training.
/// Mirrors the Docker image layout (`Trainer/.venv`, `TRAINER_PYTHON`).
enum TrainerBootstrap {
    static func ensureReady(app: Application) async {
        guard app.environment != .testing else { return }

        let root = TrainJobService.normalizedDirectory(app.directory.workingDirectory)
        let requirements = root + "Trainer/requirements.txt"
        guard FileManager.default.fileExists(atPath: requirements) else {
            app.logger.debug("Trainer requirements.txt missing; skipping Python bootstrap")
            return
        }

        // Respect an explicit absolute TRAINER_PYTHON (e.g. Docker) when it already works.
        if let configured = Environment.get("TRAINER_PYTHON"), configured.contains("/") {
            if FileManager.default.isExecutableFile(atPath: configured),
               await importsOK(python: configured, runner: app.processRunner).ok
            {
                return
            }
            app.logger.warning("TRAINER_PYTHON=\(configured) is not usable; bootstrapping Trainer/.venv")
        }

        let venvPython = root + "Trainer/.venv/bin/python"
        do {
            try await ensureVenv(
                root: root,
                venvPython: venvPython,
                requirements: requirements,
                runner: app.processRunner,
                logger: app.logger
            )
            setenv("TRAINER_PYTHON", venvPython, 1)
            app.logger.info("Trainer Python ready: \(venvPython)")
        } catch {
            app.logger.warning("Trainer Python bootstrap failed: \(error). Server training may be unavailable.")
        }
    }

    private static func ensureVenv(
        root: String,
        venvPython: String,
        requirements: String,
        runner: any ProcessRunning,
        logger: Logger
    ) async throws {
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            let check = await importsOK(python: venvPython, runner: runner)
            if check.ok { return }
            logger.info("Trainer venv present but imports failed; reinstalling requirements…")
            if let detail = check.detail, !detail.isEmpty {
                logger.debug("Import check: \(detail)")
            }
        }

        let venvDir = root + "Trainer/.venv"
        if !FileManager.default.fileExists(atPath: venvPython) {
            let basePython = preferredBasePython()
            logger.info("Creating Trainer/.venv with \(basePython)…")
            let create = try await runner.run(
                executable: basePython,
                arguments: ["-m", "venv", venvDir],
                timeout: .seconds(120)
            )
            guard create.exitCode == 0 else {
                throw PredictorError.msg("python -m venv failed: \(create.stderr)\(create.stdout)")
            }
        }

        guard FileManager.default.isExecutableFile(atPath: venvPython) else {
            throw PredictorError.msg("Trainer venv python missing at \(venvPython)")
        }

        logger.info("Installing Trainer requirements (first launch may take a minute)…")
        // Prefer `python -m pip` so we always install into this venv.
        let install = try await runner.run(
            executable: venvPython,
            arguments: [
                "-m", "pip", "install", "--disable-pip-version-check", "--upgrade", "pip",
            ],
            timeout: .seconds(180)
        )
        if install.exitCode != 0 {
            logger.warning("pip self-upgrade skipped: \(install.stderr)")
        }

        let deps = try await runner.run(
            executable: venvPython,
            arguments: [
                "-m", "pip", "install", "--disable-pip-version-check", "-r", requirements,
            ],
            timeout: .seconds(600)
        )
        guard deps.exitCode == 0 else {
            throw PredictorError.msg("pip install failed: \(deps.stderr)\(deps.stdout)")
        }

        let verify = await importsOK(python: venvPython, runner: runner)
        guard verify.ok else {
            let detail = verify.detail ?? "unknown import error"
            throw PredictorError.msg("Trainer venv missing required packages after install: \(detail)")
        }
    }

    /// Prefer a stable system interpreter over Xcode's bundled python3 when creating the venv.
    private static func preferredBasePython() -> String {
        if let override = Environment.get("TRAINER_BASE_PYTHON"), !override.isEmpty {
            return override
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") {
            return "/usr/bin/python3"
        }
        return "python3"
    }

    private static func importsOK(
        python: String,
        runner: any ProcessRunning
    ) async -> (ok: Bool, detail: String?) {
        do {
            let result = try await runner.run(
                executable: python,
                arguments: ["-c", "import pandas, sklearn, skl2onnx, onnx"],
                timeout: .seconds(120)
            )
            if result.exitCode == 0 { return (true, nil) }
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            return (false, detail.isEmpty ? "exit \(result.exitCode)" : detail)
        } catch {
            return (false, "\(error)")
        }
    }
}
