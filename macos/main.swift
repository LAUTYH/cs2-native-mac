import AppKit
import CryptoKit
import Darwin
import Foundation

// This application starts Valve's Steam client. It never starts or patches cs2.exe.
let appVersion = "0.2.0"
let fm = FileManager.default

struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct Selection: Codable {
    var backend = "managed"
    var bottle: String? = nil
    var crossOverApp: String? = nil
}

struct Asset {
    let name: String
    let url: String
    let sha256: String
    let size: Int64
    let topLevel: String
}

let assets = [
    Asset(name: "WS12WineSikarugir10.0_6.tar.xz",
          url: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz",
          sha256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2",
          size: 166304096, topLevel: "wswine.bundle"),
    Asset(name: "Template-1.0.11.tar.xz",
          url: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.11.tar.xz",
          sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a",
          size: 84533420, topLevel: "Template-1.0.11.app"),
    Asset(name: "dxmt-v0.80-builtin.tar.gz",
          url: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz",
          sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d",
          size: 18681669, topLevel: "v0.80")
]

struct Check: Codable {
    let id: String
    let status: String
    let message: String
}

struct Diagnosis: Codable {
    let version: String
    let backend: String
    let execution: String
    let readyToOpenSteam: Bool
    let gameInstalled: Bool
    let liveOnlineSessionChecked: Bool
    let checks: [Check]
}

struct Launch: Codable {
    let backend: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let launchesGameDirectly: Bool
}

struct BootstrapState: Codable {
    let phase: String
    let updateReceiptTime: Double?
}

struct BootstrapRecovery: Codable {
    var handledReceipts: [Int64] = []
}

func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@discardableResult
func command(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw Failure("\(URL(fileURLWithPath: executable).lastPathComponent) terminó con código \(process.terminationStatus). \(output.suffix(1800))")
    }
    return output
}

func sha256(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var digest = SHA256()
    while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty { digest.update(data: block) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}

func regularFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
}

func merge(_ source: URL, into target: URL) throws {
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
        let destination = target.appendingPathComponent(child.lastPathComponent)
        let properties = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if properties.isDirectory == true && properties.isSymbolicLink != true {
            try merge(child, into: destination)
        } else {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: child, to: destination)
        }
    }
}

final class Controller {
    let home: URL
    let root: URL
    let log: (String) -> Void
    var configURL: URL { root.appendingPathComponent("selection.json") }
    var runtime: URL { root.appendingPathComponent("runtime/sikarugir-10-dxmt080/wswine.bundle") }
    var hostApp: URL { runtime.deletingLastPathComponent().appendingPathComponent("CS2 Steam.app") }
    var prefix: URL { root.appendingPathComponent("Steam") }
    var cache: URL { root.appendingPathComponent("cache") }
    var logURL: URL { root.appendingPathComponent("logs/steam.log") }

    init(root: URL? = nil, log: @escaping (String) -> Void = { print($0) }) {
        home = fm.homeDirectoryForCurrentUser
        self.root = root ?? home.appendingPathComponent("Library/Application Support/CS2Mac")
        self.log = log
    }

    func selection() throws -> Selection {
        guard fm.fileExists(atPath: configURL.path) else { return Selection() }
        let selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: configURL))
        guard ["managed", "crossover"].contains(selection.backend) else { throw Failure("Configuración de entorno desconocida.") }
        if selection.backend == "crossover" {
            guard let bottle = selection.bottle, validBottle(bottle), let app = selection.crossOverApp,
                  app.hasPrefix("/") else { throw Failure("Configuración de CrossOver inválida.") }
        }
        return selection
    }

    func validBottle(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    func chooseCrossOver(bottle: String, app: URL) throws {
        guard validBottle(bottle) else { throw Failure("Nombre de botella inválido.") }
        let candidate = Selection(backend: "crossover", bottle: bottle, crossOverApp: app.path)
        guard regularFile(wine(candidate)), regularFile(steam(candidate)) else {
            throw Failure("No encontré CrossOver y Steam en esa botella.")
        }
        try save(candidate)
    }

    func save(_ selection: Selection) throws {
        try withMutationLock {
            try Data(json(selection).utf8).write(to: configURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
    }

    private func withMutationLock<T>(_ operation: () throws -> T) throws -> T {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = Darwin.open(root.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Failure("No pude bloquear el control del entorno.") }
        defer { Darwin.close(fd) }
        guard cs2mac_flock(fd, LOCK_EX) == 0 else { throw Failure("No pude obtener el control del entorno.") }
        defer { cs2mac_flock(fd, LOCK_UN) }
        return try operation()
    }

    func bottleRoot(_ selected: Selection) -> URL {
        if selected.backend == "crossover" {
            return home.appendingPathComponent("Library/Application Support/CrossOver/Bottles").appendingPathComponent(selected.bottle!)
        }
        return prefix
    }

    func wine(_ selected: Selection) -> URL {
        if selected.backend == "crossover" {
            return URL(fileURLWithPath: selected.crossOverApp!).appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
        }
        return hostApp.appendingPathComponent("Contents/MacOS/wine")
    }

    func prepareHostApp() throws {
        let executable = hostApp.appendingPathComponent("Contents/MacOS/wine")
        if regularFile(executable) { return }
        let contents = hostApp.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: runtime.appendingPathComponent("bin/wine"), to: executable)
        // A real executable inside a bundle lets macOS identify Wine's windows as one application.
        // Keep the loader's ../lib and ../share layout without duplicating the large runtime.
        try fm.createSymbolicLink(atPath: contents.appendingPathComponent("lib").path, withDestinationPath: "../../wswine.bundle/lib")
        try fm.createSymbolicLink(atPath: contents.appendingPathComponent("share").path, withDestinationPath: "../../wswine.bundle/share")
        let info: [String: Any] = ["CFBundleIdentifier": "org.cs2mac.wine", "CFBundleName": "CS2 Steam",
                                  "CFBundleDisplayName": "CS2 Steam", "CFBundleExecutable": "wine",
                                  "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "10.0.6",
                                  "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": true]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        try command("/usr/bin/codesign", ["--force", "--sign", "-", "--preserve-metadata=entitlements", hostApp.path])
    }

    func steam(_ selected: Selection) -> URL {
        bottleRoot(selected).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }

    func game(_ selected: Selection) -> URL {
        steam(selected).deletingLastPathComponent().appendingPathComponent("steamapps/common/Counter-Strike Global Offensive")
    }

    func rosettaWorks() -> Bool { (try? command("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])) != nil }

    func runtimeReady() -> Bool {
        let receipt = runtime.deletingLastPathComponent().appendingPathComponent("verified-runtime.json")
        guard let data = try? Data(contentsOf: receipt),
              let recorded = try? JSONDecoder().decode([String: String].self, from: data),
              recorded == Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0.sha256) }) else { return false }
        return ["bin/wine", "bin/wineserver", "lib/wine/x86_64-unix/winemetal.so", "lib/wine/x86_64-windows/d3d11.dll"].allSatisfy {
            regularFile(runtime.appendingPathComponent($0))
        }
    }

    func diagnose() throws -> Diagnosis {
        let selected = try selection()
        let cpu = (try? command("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"]).trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
        let rosetta = rosettaWorks()
        let engine = fm.isExecutableFile(atPath: wine(selected).path)
        let installed = regularFile(steam(selected))
        let gameInstalled = regularFile(game(selected).appendingPathComponent("game/bin/win64/cs2.exe"))
        let disk = try? fm.attributesOfFileSystem(forPath: home.path)[.systemFreeSize] as? NSNumber
        let freeGB = (disk?.doubleValue ?? 0) / 1_073_741_824
        var checks = [
            Check(id: "apple-silicon", status: cpu ? "ok" : "error", message: cpu ? "Mac con Apple Silicon." : "Esta versión requiere Apple Silicon."),
            Check(id: "rosetta", status: rosetta ? "ok" : "error", message: rosetta ? "La traducción de aplicaciones Intel funciona." : "Rosetta no está disponible. Instalalo con el aviso oficial de macOS."),
            Check(id: "runtime", status: engine ? "ok" : "error", message: engine ? "Entorno de compatibilidad encontrado." : "Prepará el entorno con el botón Preparar Steam."),
            Check(id: "steam", status: installed ? "ok" : "error", message: installed ? "Steam de Windows instalado." : "Steam todavía no está instalado en este entorno."),
            Check(id: "game", status: gameInstalled ? "ok" : "info", message: gameInstalled ? "CS2 original encontrado." : "Instalá CS2 desde la biblioteca de Steam."),
            Check(id: "disk", status: freeGB < (gameInstalled ? 15 : 90) ? "warning" : "ok", message: String(format: gameInstalled ? "%.1f GiB libres para actualizaciones. Steam puede necesitar espacio adicional." : "%.1f GiB libres. Una instalación nueva de CS2 necesita aproximadamente 90 GB.", freeGB))
        ]
        if selected.backend == "managed" {
            let ready = runtimeReady()
            checks.append(Check(id: "runtime-verification", status: ready ? "ok" : "error", message: ready ? "Paquetes del entorno verificados por SHA-256." : "El entorno necesita completar su preparación."))
        }
        let ready = !checks.contains { $0.status == "error" }
        return Diagnosis(version: appVersion, backend: selected.backend, execution: "Original Windows x86_64 game through compatibility and Rosetta", readyToOpenSteam: ready,
                         gameInstalled: gameInstalled, liveOnlineSessionChecked: false, checks: checks)
    }

    func environment(_ selected: Selection) -> [String: String] {
        let inherited = Set(["HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "SHELL", "__CF_USER_TEXT_ENCODING", "DISPLAY"])
        var env = ProcessInfo.processInfo.environment.filter { inherited.contains($0.key) }
        env["WINEDEBUG"] = "-all"
        env["WINEMSYNC"] = "1"
        if selected.backend == "managed" {
            env["WINEPREFIX"] = prefix.path
            env["WINEARCH"] = "win64"
            env["WINELOADER"] = wine(selected).path
            env["WINESERVER"] = runtime.appendingPathComponent("bin/wineserver").path
        }
        return env
    }

    func launchPlan(play: Bool = false, shutdown: Bool = false, fixedSelection: Selection? = nil) throws -> Launch {
        let selected = try fixedSelection ?? selection()
        var args: [String] = []
        if selected.backend == "crossover" { args += ["--bottle", selected.bottle!, "--no-wait", "--cx-app"] }
        // CrossOver's --cx-app takes a Windows path; native absolute paths are not converted here.
        args.append(selected.backend == "crossover" ? "C:\\Program Files (x86)\\Steam\\steam.exe" : steam(selected).path)
        if shutdown { args.append("-shutdown") }
        else if play { args += ["-applaunch", "730"] }
        let planEnvironment = environment(selected).filter { $0.key.hasPrefix("WINE") }
        return Launch(backend: selected.backend, executable: wine(selected).path, arguments: args,
                      environment: planEnvironment, launchesGameDirectly: false)
    }

    func spawn(_ executable: URL, _ arguments: [String], selected: Selection,
               message: String = "Steam se está abriendo. Iniciá sesión y pulsá Jugar en CS2.") throws {
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment(selected)
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        let report = log
        process.terminationHandler = { finished in
            try? handle.close()
            if finished.terminationStatus != 0 {
                report("No se pudo completar la apertura o el cierre de Steam (código \(finished.terminationStatus)). El detalle quedó en el registro local.")
            }
        }
        try process.run()
        log(message)
    }

    func openSteam(play: Bool = false) throws {
        try withMutationLock {
            let selected = try selection()
            let diagnosis = try diagnose()
            guard diagnosis.readyToOpenSteam else {
                throw Failure(diagnosis.checks.filter { $0.status == "error" }.map(\.message).joined(separator: "\n"))
            }
            try recoverInitialBootstrapIfNeeded(selected)
            let plan = try launchPlan(play: play, fixedSelection: selected)
            try spawn(URL(fileURLWithPath: plan.executable), plan.arguments, selected: selected)
        }
    }

    // First-time Steam installs can finish win32/win64 updates without completing
    // the Wine process handoff. Never reset a prefix that has reached the frontend.
    func bootstrapState(now: Date = Date()) -> BootstrapState {
        let logs = steam(Selection()).deletingLastPathComponent().appendingPathComponent("logs")
        if regularFile(logs.appendingPathComponent("steamui_system.txt")) {
            return BootstrapState(phase: "frontend-started", updateReceiptTime: nil)
        }
        let bootstrap = logs.appendingPathComponent("bootstrap_log.txt")
        let package = steam(Selection()).deletingLastPathComponent().appendingPathComponent("package")
        let receipts = ["steam_client_win32.installed", "steam_client_win64.installed"].compactMap { name -> Date? in
            try? package.appendingPathComponent(name).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let receiptTime = receipts.max(),
              let logTime = try? bootstrap.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let handle = try? FileHandle(forReadingFrom: bootstrap) else {
            return BootstrapState(phase: "waiting", updateReceiptTime: nil)
        }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: end > 16384 ? end - 16384 : 0)) != nil,
              let tail = try? handle.readToEnd() else { return BootstrapState(phase: "waiting", updateReceiptTime: nil) }
        let text = String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let complete = text.hasSuffix("] Shutdown") && abs(logTime.timeIntervalSince(receiptTime)) < 60
        let settled = now.timeIntervalSince(logTime) >= 20
        guard complete && settled else { return BootstrapState(phase: "waiting", updateReceiptTime: nil) }
        let receipt = receiptTime.timeIntervalSince1970
        guard let recovery = try? recoveryRecord() else { return BootstrapState(phase: "recovery-blocked", updateReceiptTime: receipt) }
        let phase: String
        if recovery.handledReceipts.contains(Int64(receipt)) { phase = "already-recovered" }
        else if recovery.handledReceipts.count >= 2 { phase = "recovery-limit" }
        else { phase = "restart-required" }
        return BootstrapState(phase: phase, updateReceiptTime: receipt)
    }

    private func recoveryRecord() throws -> BootstrapRecovery {
        let path = root.appendingPathComponent("bootstrap-recovery.json")
        guard fm.fileExists(atPath: path.path) else { return BootstrapRecovery() }
        guard let size = try fm.attributesOfItem(atPath: path.path)[.size] as? NSNumber, size.intValue <= 4096 else {
            throw Failure("El registro de recuperación inicial es inválido.")
        }
        return try JSONDecoder().decode(BootstrapRecovery.self, from: Data(contentsOf: path))
    }

    // Called only inside the cross-process control lock, on an explicit open/play request.
    // No timers remain behind the user's back, and each completed receipt is handled once.
    private func recoverInitialBootstrapIfNeeded(_ selected: Selection) throws {
        guard selected.backend == "managed" else { return }
        let state = bootstrapState()
        guard state.phase == "restart-required", let receipt = state.updateReceiptTime else { return }
        let processes = try command("/bin/ps", ["-axo", "comm="])
        let currentState = bootstrapState()
        guard !processes.lowercased().split(separator: "\n").contains(where: { $0.hasSuffix("cs2.exe") }),
              currentState.phase == "restart-required", currentState.updateReceiptTime == receipt else { return }
        var recovery = try recoveryRecord()
        guard recovery.handledReceipts.count < 2, !recovery.handledReceipts.contains(Int64(receipt)) else { return }
        recovery.handledReceipts.append(Int64(receipt))
        let recordURL = root.appendingPathComponent("bootstrap-recovery.json")
        try Data(json(recovery).utf8).write(to: recordURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
        log("Retomando Steam después de su actualización inicial (\(recovery.handledReceipts.count)/2)…")
        try command(runtime.appendingPathComponent("bin/wineserver").path, ["-k"], environment: environment(selected))
    }

    func stop() throws {
        try withMutationLock {
            guard rosettaWorks() else { throw Failure("Rosetta no está disponible; no hay un entorno que pueda cerrar.") }
            let selected = try selection()
            let plan = try launchPlan(shutdown: true, fixedSelection: selected)
            try spawn(URL(fileURLWithPath: plan.executable), plan.arguments, selected: selected,
                      message: "Solicité el cierre normal de Steam y sus juegos en el entorno seleccionado.")
        }
    }

    func download(_ asset: Asset) throws -> URL {
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let destination = cache.appendingPathComponent(asset.name)
        if regularFile(destination), (try? sha256(destination)) == asset.sha256 { return destination }
        log("Descargando \(asset.name)…")
        let partial = cache.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? fm.removeItem(at: partial) }
        try command("/usr/bin/curl", ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https", "--retry", "2", "--connect-timeout", "20", "--max-time", "1200", "--max-filesize", String(asset.size), "--output", partial.path, asset.url])
        guard (try fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value == asset.size,
              try sha256(partial) == asset.sha256 else { throw Failure("La descarga no coincide con el SHA-256 publicado: \(asset.name).") }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: partial, to: destination)
        return destination
    }

    func unpack(_ archive: URL, asset: Asset, into directory: URL) throws {
        let listing = try command("/usr/bin/tar", ["-tf", archive.path])
        let names = listing.split(separator: "\n").map(String.init)
        guard !names.isEmpty, names.allSatisfy({ name in
            let parts = name.split(separator: "/")
            return !name.hasPrefix("/") && parts.first == Substring(asset.topLevel) && !parts.contains("..")
        }) else { throw Failure("El paquete contiene rutas inesperadas: \(asset.name).") }
        try command("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path, "--no-same-owner", "--no-same-permissions"])
    }

    func fetchRuntime() throws {
        let destination = runtime.deletingLastPathComponent()
        if runtimeReady() { try prepareHostApp(); log("El entorno ya está preparado."); return }
        guard !fm.fileExists(atPath: destination.path) else { throw Failure("Hay un entorno incompleto. Conservé sus archivos para revisión.") }
        let archives = try assets.map { try download($0) }
        let staging = root.appendingPathComponent(".runtime-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for (asset, archive) in zip(assets, archives) {
            log("Verificando y preparando \(asset.name)…")
            try unpack(archive, asset: asset, into: staging)
        }
        let engine = staging.appendingPathComponent("wswine.bundle")
        let frameworks = staging.appendingPathComponent("Template-1.0.11.app/Contents/Frameworks")
        try merge(frameworks, into: engine.appendingPathComponent("lib"))
        for name in ["x86_64-unix", "x86_64-windows", "i386-windows"] {
            try merge(staging.appendingPathComponent("v0.80/" + name), into: engine.appendingPathComponent("lib/wine/" + name))
        }
        guard regularFile(engine.appendingPathComponent("bin/wine")),
              regularFile(engine.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so")) else { throw Failure("El paquete no contiene el entorno esperado.") }
        let symbols = try command("/usr/bin/nm", ["-g", engine.appendingPathComponent("lib/wine/x86_64-unix/winemac.so").path])
        guard symbols.contains("_macdrv_functions") else { throw Failure("Este Wine no expone la interfaz necesaria para DXMT.") }
        let ready = staging.appendingPathComponent("ready")
        try fm.createDirectory(at: ready, withIntermediateDirectories: true)
        try fm.moveItem(at: engine, to: ready.appendingPathComponent("wswine.bundle"))
        let receipt = Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0.sha256) })
        try Data(json(receipt).utf8).write(to: ready.appendingPathComponent("verified-runtime.json"), options: .atomic)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: ready, to: destination)
        try prepareHostApp()
        log("Wine y DXMT preparados y verificados. No se ejecutó software de Windows.")
    }

    func setup() throws {
        guard rosettaWorks() else { throw Failure("Primero instalá Rosetta mediante el aviso oficial de macOS. Su instalación requiere aceptar la licencia de Apple.") }
        try fetchRuntime()
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        let managed = Selection()
        if !regularFile(prefix.appendingPathComponent("system.reg")) {
            log("Creando un entorno separado para Steam…")
            try command(wine(managed).path, ["wineboot", "-u"], environment: environment(managed))
        }
        for arch in ["x86_64-windows", "i386-windows"] {
            let directory = arch == "x86_64-windows" ? "system32" : "syswow64"
            let target = prefix.appendingPathComponent("drive_c/windows/" + directory + "/winemetal.dll")
            if !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: runtime.appendingPathComponent("lib/wine/" + arch + "/winemetal.dll"), to: target)
            }
        }
        try save(managed)
        if regularFile(steam(managed)) { log("Steam ya está instalado. Pulsá Abrir Steam."); return }
        log("Descargando el instalador oficial de Steam…")
        let installer = cache.appendingPathComponent("SteamSetup.exe")
        // Steam's bootstrap installer updates independently; HTTPS origin is retained, not a false fixed digest.
        try command("/usr/bin/curl", ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https", "--retry", "2", "--connect-timeout", "20", "--max-time", "300", "--output", installer.path, "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"])
        try spawn(wine(managed), [installer.path], selected: managed,
                  message: "Completá el instalador oficial de Steam en la ventana que se abrió.")
    }

    func importGame(_ source: URL) throws {
        guard (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw Failure("Elegí la carpeta real del juego, no un enlace simbólico.")
        }
        guard regularFile(source.appendingPathComponent("game/bin/win64/cs2.exe")) else { throw Failure("La carpeta seleccionada no contiene CS2 para Windows.") }
        var traversalError: Error? = nil
        guard let files = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, error in traversalError = error; return false }) else {
            throw Failure("No pude leer la instalación seleccionada.")
        }
        // A cloned symlink would still let a later Steam update write into somebody else's library.
        for case let file as URL in files {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw Failure("La instalación contiene enlaces simbólicos. No la importé para conservar independientes las dos bibliotecas.")
            }
        }
        if let error = traversalError { throw Failure("No pude revisar toda la instalación: \(error.localizedDescription)") }
        guard regularFile(steam(Selection())) else {
            throw Failure("Primero completá la instalación de Steam. Su instalador necesita una carpeta vacía; después podés reutilizar CS2.")
        }
        let destination = game(Selection())
        guard !fm.fileExists(atPath: destination.path) else { throw Failure("Ya hay una instalación en el entorno administrado. Conservé ambas copias.") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".import-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        log("Reutilizando los archivos mediante una copia APFS independiente…")
        // clonefile gives independent writes. No symlinks/hardlinks to the original Steam library.
        try command("/bin/cp", ["-cR", source.path, staging.path])
        let manifest = source.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("appmanifest_730.acf")
        let targetManifest = destination.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("appmanifest_730.acf")
        try fm.moveItem(at: staging, to: destination)
        if regularFile(manifest) && !fm.fileExists(atPath: targetManifest.path) {
            try fm.copyItem(at: manifest, to: targetManifest)
        }
        log("Copia independiente lista. Steam verificará y actualizará el juego cuando corresponda.")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let status = NSTextView()
    let primary = NSButton(title: "Abrir Steam", target: nil, action: nil)
    var controls: [NSButton] = []
    var busy = false
    var controller: Controller!
    let dataRoot: URL?

    init(root: URL?) { dataRoot = root }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Salir de CS2 en Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        controller = Controller(root: dataRoot) { [weak self] line in DispatchQueue.main.async { self?.append(line) } }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "CS2 en Mac"
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)])
        let title = NSTextField(labelWithString: "El CS2 original, con Steam.")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Abrí Steam, iniciá sesión con tu cuenta y pulsá Jugar. La compatibilidad online se comprueba jugando en los servidores oficiales.")
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        let row = NSStackView()
        row.spacing = 10
        primary.target = self; primary.action = #selector(openSteam)
        primary.bezelStyle = .rounded; primary.keyEquivalent = "\r"
        row.addArrangedSubview(primary); controls.append(primary)
        for (title, action) in [("Preparar Steam", #selector(setup)), ("Diagnóstico", #selector(diagnose)), ("Cerrar Steam", #selector(stop))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; controls.append(button); row.addArrangedSubview(button)
        }
        stack.addArrangedSubview(row)
        let extra = NSStackView(); extra.spacing = 10
        for (title, action) in [("Usar CrossOver existente…", #selector(crossOver)), ("Reutilizar CS2 instalado…", #selector(importGame))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; controls.append(button); extra.addArrangedSubview(button)
        }
        let rosetta = NSButton(title: "Instalar Rosetta…", target: self, action: #selector(installRosetta))
        rosetta.bezelStyle = .rounded; controls.append(rosetta); extra.addArrangedSubview(rosetta)
        stack.addArrangedSubview(extra)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        status.isEditable = false
        status.font = .systemFont(ofSize: 12)
        status.autoresizingMask = [.width]
        status.textContainer?.widthTracksTextView = true
        scroll.documentView = status
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        let footer = NSTextField(labelWithString: "Proyecto comunitario · Wine/DXMT y traducción Intel · No afiliado a Valve")
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        stack.addArrangedSubview(footer)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        diagnose()
    }

    func append(_ line: String) {
        status.string += line + "\n"
        status.scrollToEndOfDocument(nil)
    }

    func work(_ operation: @escaping () throws -> Void) {
        guard !busy else { return }
        busy = true; controls.forEach { $0.isEnabled = false }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do { try operation() }
            catch { DispatchQueue.main.async { self.append(error.localizedDescription) } }
            DispatchQueue.main.async { self.busy = false; self.controls.forEach { $0.isEnabled = true } }
        }
    }

    @objc func diagnose() { work { [self] in
        let diagnosis = try controller.diagnose()
        DispatchQueue.main.async { self.status.string = "" }
        for check in diagnosis.checks { controller.log("\(check.status == "ok" ? "✓" : "•") \(check.message)") }
    } }
    @objc func openSteam() { work { [self] in try controller.openSteam() } }
    @objc func setup() { work { [self] in try controller.setup() } }
    @objc func stop() { work { [self] in try controller.stop() } }

    @objc func installRosetta() {
        let updater = URL(fileURLWithPath: "/System/Library/CoreServices/Rosetta 2 Updater.app")
        if fm.fileExists(atPath: updater.path) {
            NSWorkspace.shared.open(updater)
            append("Completá el instalador de Apple y revisá su licencia. Después pulsá Diagnóstico.")
        } else {
            NSWorkspace.shared.open(URL(string: "https://support.apple.com/en-us/102527")!)
        }
    }

    @objc func crossOver() {
        let directory = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        let panel = NSOpenPanel()
        panel.title = "Elegí la botella de CrossOver que contiene Steam"
        panel.directoryURL = directory; panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let chosen = panel.url {
            guard chosen.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { append("Elegí una botella dentro de la carpeta Bottles de CrossOver."); return }
            work { [self] in
                try controller.chooseCrossOver(bottle: chosen.lastPathComponent, app: URL(fileURLWithPath: "/Applications/CrossOver.app"))
                controller.log("CrossOver seleccionado. Pulsá Abrir Steam.")
            }
        }
    }

    @objc func importGame() {
        let panel = NSOpenPanel()
        panel.title = "Elegí la carpeta Counter-Strike Global Offensive de Windows"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let source = panel.url { work { [self] in try controller.importGame(source) } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

func main() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    var root: URL? = nil
    if args.first == "--data-root" {
        guard args.count >= 2, args[1].hasPrefix("/") else { throw Failure("--data-root necesita una ruta absoluta.") }
        root = URL(fileURLWithPath: args[1]); args.removeFirst(2)
    }
    if args.isEmpty {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(root: root)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        return
    }
    let controller = Controller(root: root) { line in FileHandle.standardError.write(Data((line + "\n").utf8)) }
    switch args[0] {
    case "--version": print(appVersion)
    case "--help", "help":
        print("""
        cs2mac \(appVersion) — el CS2 original mediante compatibilidad en Apple Silicon
          doctor [--json]             Comprobar requisitos sin instalar ni abrir Steam
          bootstrap-status            Estado de la primera actualización de Steam (solo lectura)
          fetch-runtime               Descargar y verificar Wine/DXMT (no los ejecuta)
          setup                       Preparar entorno y abrir el instalador oficial de Steam
          use-crossover --bottle NAME [--app /Applications/CrossOver.app]
          use-managed                 Seleccionar el entorno abierto administrado
          import-game /ruta/al/juego   Copia APFS independiente después de instalar Steam
          steam [--dry-run]            Abrir Steam; pulsá Jugar dentro de Steam
          play [--dry-run]             Pedir a Steam que inicie el AppID 730
          stop [--dry-run]             Solicitar el cierre normal de Steam
        Sin argumentos abre la aplicación. --data-root /ruta permite otro directorio local.
        """)
    case "doctor":
        guard args.count == 1 || args == ["doctor", "--json"] else { throw Failure("Uso: doctor [--json]") }
        let report = try controller.diagnose()
        if args.contains("--json") { print(try json(report)) }
        else { for check in report.checks { print("[\(check.status)] \(check.message)") } }
        if !report.readyToOpenSteam { exit(1) }
    case "fetch-runtime": guard args.count == 1 else { throw Failure("Uso: fetch-runtime") }; try controller.fetchRuntime()
    case "bootstrap-status": guard args.count == 1 else { throw Failure("Uso: bootstrap-status") }; print(try json(controller.bootstrapState()))
    case "setup": guard args.count == 1 else { throw Failure("Uso: setup") }; try controller.setup()
    case "use-managed": guard args.count == 1 else { throw Failure("Uso: use-managed") }; try controller.save(Selection())
    case "use-crossover":
        guard (args.count == 3 || args.count == 5), args[1] == "--bottle",
              args.count == 3 || args[3] == "--app" else { throw Failure("Uso: use-crossover --bottle NAME [--app /Applications/CrossOver.app]") }
        let app = URL(fileURLWithPath: args.count == 5 ? args[4] : "/Applications/CrossOver.app")
        try controller.chooseCrossOver(bottle: args[2], app: app)
    case "import-game": guard args.count == 2 else { throw Failure("Uso: import-game /ruta/al/juego") }; try controller.importGame(URL(fileURLWithPath: args[1]))
    case "steam", "play", "stop":
        guard args.count == 1 || args == [args[0], "--dry-run"] else { throw Failure("Uso: \(args[0]) [--dry-run]") }
        if args.contains("--dry-run") { print(try json(controller.launchPlan(play: args[0] == "play", shutdown: args[0] == "stop"))) }
        else if args[0] == "stop" { try controller.stop() }
        else { try controller.openSteam(play: args[0] == "play") }
    default: throw Failure("Comando desconocido. Usá --help.")
    }
}

do { try main() }
catch {
    FileHandle.standardError.write(Data(("CS2 en Mac: " + error.localizedDescription + "\n").utf8))
    exit(2)
}
