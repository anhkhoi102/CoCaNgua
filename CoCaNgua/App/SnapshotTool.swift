#if os(macOS)
import AppKit
#endif
import GameCore
import OnlineCore
import SpriteKit

/// Công cụ gỡ lỗi cho Scripts/snapshot.sh: tự chạy qua các màn hình, lưu ảnh PNG của cửa sổ vào thư mục tmp
/// của sandbox rồi thoát. Chỉ hoạt động ở bản Debug khi có biến môi trường COCANGUA_SNAPSHOT.
@MainActor
enum SnapshotTool {
    static func runIfRequested(coordinator: AppCoordinator) async {
        #if DEBUG
        // Mở thẳng một thế cờ giữa ván, người chơi (Đỏ) đổ ra 2 và phải chọn quân: để thử thao tác trên bàn cờ
        // (dùng được trên iOS Simulator: SIMCTL_CHILD_COCANGUA_DEBUG_MIDGAME=1 xcrun simctl launch …).
        if ProcessInfo.processInfo.environment["COCANGUA_DEBUG_MIDGAME"] != nil {
            var mid = GameState(colors: PlayerColor.allCases, rules: .traditional)
            mid.players[0].horses = [.track(3), .track(20), .home(4), .stable]
            mid.players[1].horses = [.track(5), .track(40), .track(13), .home(6)]
            mid.players[2].horses = [.track(30), .home(5), .home(2), .stable]
            mid.players[3].horses = [.track(44), .track(55), .stable, .stable]
            coordinator.settings.lastHumanColor = .red
            coordinator.startSinglePlayer(initialState: mid, generator: FixedDice(values: [2]))
            return
        }
        #endif
        #if DEBUG && os(macOS)
        if ProcessInfo.processInfo.environment["COCANGUA_ROOM_TEST"] != nil {
            await roomTest(coordinator: coordinator)
            return
        }
        if ProcessInfo.processInfo.environment["COCANGUA_ENGLISH_SHOTS"] != nil {
            await englishShots(coordinator: coordinator)
            return
        }
        if let mode = ProcessInfo.processInfo.environment["COCANGUA_BACKGROUND_TEST"] {
            await backgroundTest(coordinator: coordinator, mode: mode)
            return
        }
        guard ProcessInfo.processInfo.environment["COCANGUA_SNAPSHOT"] != nil else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
        // Chạy từ dòng lệnh thì cửa sổ thường bị che; không có dòng này macOS sẽ giãn bộ hẹn giờ (App Nap)
        // và các khoảng chờ trong kịch bản chụp bị lệch.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Chụp ảnh gỡ lỗi")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func shot(_ name: String, after seconds: Double = 0.6, includeScene: Bool = true) async {
            try? await Task.sleep(for: .seconds(seconds))
            capture(folder.appendingPathComponent("\(name).png"), includeScene: includeScene)
        }
        // Chờ cửa sổ hiện ra rồi mới lấy, nếu không các ảnh đổi cỡ cửa sổ sẽ bị bỏ qua.
        var window = NSApp.windows.first(where: { $0.isVisible })
        for _ in 0..<20 where window == nil {
            try? await Task.sleep(for: .seconds(0.1))
            window = NSApp.windows.first(where: { $0.isVisible })
        }
        let savedFrame = window?.frame
        window?.setContentSize(NSSize(width: 1180, height: 800))
        let savedSpeed = coordinator.settings.animationSpeed
        let savedSound = coordinator.settings.soundVolume, savedMusic = coordinator.settings.musicVolume
        coordinator.settings.soundVolume = 0
        coordinator.settings.musicVolume = 0
        coordinator.applyAudioSettings()
        coordinator.settings.animationSpeed = .fast

        await shot("01-menu", after: 1.2)
        coordinator.showSettings()
        await shot("02-settings")
        coordinator.showSinglePlayerSetup()
        await shot("02b-setup")
        coordinator.showOnlineLobby()
        await shot("02c-online-lobby", after: 3.0)
        coordinator.showMainMenu()
        let savedSetup = (coordinator.settings.lastHumanColor, coordinator.settings.lastOpponentCount)
        coordinator.settings.lastHumanColor = .red
        coordinator.settings.lastOpponentCount = 3

        // Ván mới: chụp lúc chờ người chơi đổ xúc xắc.
        coordinator.startSinglePlayer(generator: SeededGenerator(seed: 11))
        await shot("03-game-start", after: 1.0)

        // Giữa ván: dựng sẵn một thế cờ có đủ loại vị trí, người chơi đang phải chọn quân.
        var mid = GameState(colors: PlayerColor.allCases, rules: coordinator.settings.rules)
        mid.players[0].horses = [.track(3), .track(20), .home(4), .stable]
        mid.players[1].horses = [.track(5), .track(40), .track(13), .home(6)]
        mid.players[2].horses = [.track(30), .home(5), .home(2), .stable]
        mid.players[3].horses = [.track(44), .track(55), .stable, .stable]
        coordinator.startSinglePlayer(initialState: mid, generator: FixedDice(values: [2]))
        try? await Task.sleep(for: .seconds(0.8))
        coordinator.session?.humanRoll()
        await shot("04-choose-horse", after: 1.6)
        // Nước này đá quân: chụp một khung giữa cảnh zoom, rồi chụp sau khi xong.
        if let move = coordinator.session?.selectableMoves.first { coordinator.session?.humanChose(move) }
        await shot("05a-capture-zoom", after: 0.75)
        await shot("05-after-capture", after: 1.6)
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(0.25))
            coordinator.session?.humanRoll()
            if let move = coordinator.session?.selectableMoves.first { coordinator.session?.humanChose(move) }
        }
        await shot("06-mid-game", after: 0.2)

        // Kết thúc: Đỏ chỉ cần đổ 3 để thắng.
        var end = GameState(colors: PlayerColor.allCases, rules: .traditional)
        end.players[0].horses = [.home(6), .home(5), .home(4), .home(2)]
        end.players[1].horses = [.track(22), .home(3), .stable, .stable]
        end.players[2].horses = [.home(6), .home(5), .track(31), .track(2)]
        end.players[3].horses = [.track(50), .stable, .stable, .stable]
        coordinator.startSinglePlayer(initialState: end, generator: FixedDice(values: [3]))
        try? await Task.sleep(for: .seconds(0.8))
        coordinator.session?.humanRoll()
        await shot("07-win-effects", after: 1.3)
        await shot("08-result", after: 2.0)
        // Lớp phủ kết quả nằm trên bàn cờ; chụp riêng phần SwiftUI để thấy thẻ kết quả.
        await shot("08b-result-card", after: 0.1, includeScene: false)

        // Cửa sổ nhỏ nhất và cửa sổ rộng: bàn cờ phải giữ tỉ lệ.
        coordinator.startSinglePlayer(initialState: mid, generator: SeededGenerator(seed: 5))
        if let window {
            window.setContentSize(NSSize(width: 960, height: 680))
            await shot("09-small-window", after: 1.0)
            window.setContentSize(NSSize(width: 1500, height: 760))
            await shot("10-wide-window", after: 1.0)
        }

        // Kiểu quân cá ngựa trên cùng thế cờ.
        let savedStyle = coordinator.settings.pieceStyle
        window?.setContentSize(NSSize(width: 1180, height: 800))
        coordinator.settings.pieceStyle = .seahorse
        coordinator.startSinglePlayer(initialState: mid, generator: FixedDice(values: [2]))
        try? await Task.sleep(for: .seconds(0.8))
        coordinator.session?.humanRoll()
        await shot("11-seahorse-style", after: 1.6)
        coordinator.settings.pieceStyle = savedStyle
        // Chế độ nhanh: đổ ra 4 và 1, chọn một quân để hiện các ô đích (đi 4, đi 1, cộng 5, bay).
        let savedRules = coordinator.settings.rules
        var speed = mid
        speed.rules.diceCount = 2
        // Quân đỏ #1 (ô 20) có đủ bốn lựa chọn: đi 4, đi 1, cộng 5, bay.
        coordinator.startSinglePlayer(initialState: speed, generator: FixedDice(values: [4, 1]))
        try? await Task.sleep(for: .seconds(0.8))
        coordinator.session?.humanRoll()
        // Chờ tới khi phiên chơi yêu cầu chọn nước (xúc xắc lăn xong).
        let rollStarted = Date()
        while coordinator.session?.awaitingHumanMove != true, Date().timeIntervalSince(rollStarted) < 6 {
            try? await Task.sleep(for: .seconds(0.05))
        }
        coordinator.session?.scene.focus(HorseID(.red, 1))
        await shot("13-speed-mode-options", after: 0.4)
        if let flight = coordinator.session?.selectableMoves.first(where: { $0.kind == .fly && $0.horse == HorseID(.red, 0) }) {
            coordinator.session?.humanChose(flight)
        }
        await shot("14-speed-mode-after-flight", after: 1.6)
        coordinator.settings.rules = savedRules

        // Ván 2 người, người chơi cầm Xanh dương, máy mức Khó: để máy tự đi vài lượt.
        let savedDifficulty = coordinator.settings.lastDifficulty
        coordinator.settings.lastHumanColor = .blue
        coordinator.settings.lastOpponentCount = 1
        coordinator.settings.lastDifficulty = .hard
        coordinator.startSinglePlayer(generator: SeededGenerator(seed: 4))
        coordinator.session?.scene.resetFrameIntervals()
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(0.25))
            coordinator.session?.humanRoll()
            if let move = coordinator.session?.selectableMoves.first { coordinator.session?.humanChose(move) }
        }
        // Đo tốc độ khung hình trong 15 giây chơi liên tục (quân nhảy, đá quân, zoom).
        if let frames = coordinator.session?.scene.frameIntervals.sorted(), !frames.isEmpty {
            let mean = frames.reduce(0, +) / Double(frames.count)
            let slow = frames.filter { $0 > 1.0 / 30 }.count
            print(String(format: "FRAMES %d, trung bình %.1f ms (%.0f fps), p99 %.1f ms, chậm nhất %.1f ms, số khung dưới 30 fps: %d",
                         frames.count, mean * 1000, 1 / mean, frames[Int(Double(frames.count) * 0.99)] * 1000, frames.last! * 1000, slow))
        }
        await shot("12-two-players-blue", after: 0.2)
        coordinator.settings.lastDifficulty = savedDifficulty
        coordinator.settings.lastHumanColor = savedSetup.0
        coordinator.settings.lastOpponentCount = savedSetup.1
        if let savedFrame { window?.setFrame(savedFrame, display: true) }
        coordinator.settings.animationSpeed = savedSpeed
        coordinator.settings.soundVolume = savedSound
        coordinator.settings.musicVolume = savedMusic
        NSApp.terminate(nil)
        #endif
    }

    #if DEBUG && os(macOS)
    /// Tái hiện lỗi "đơ sau khi chuyển sang app khác": tự chơi, ẩn (hoặc thu nhỏ) ứng dụng vài giây rồi hiện lại,
    /// in số lượt trước và sau để thấy ván có chạy tiếp không.
    private static func backgroundTest(coordinator: AppCoordinator, mode: String) async {
        let began = Date()
        func report(_ label: String) {
            let scene = coordinator.session?.scene
            print(String(format: "BG %5.1fs %@ lượt=%d sceneTạmDừng=%@ viewTạmDừng=%@ chờĐổ=%@ chờĐi=%@", Date().timeIntervalSince(began), label,
                         coordinator.session?.state.turnNumber ?? -1, "\(scene?.isPaused ?? false)", "\(scene?.view?.isPaused ?? false)",
                         "\(coordinator.session?.awaitingHumanRoll ?? false)", "\(coordinator.session?.awaitingHumanMove ?? false)"))
        }
        func play(seconds: Double) async {
            let until = Date().addingTimeInterval(seconds)
            while Date() < until {
                try? await Task.sleep(for: .seconds(0.25))
                coordinator.session?.humanRoll()
                if let move = coordinator.session?.selectableMoves.first { coordinator.session?.humanChose(move) }
            }
        }
        coordinator.settings.soundVolume = 0
        coordinator.settings.musicVolume = 0
        coordinator.applyAudioSettings()
        try? await Task.sleep(for: .seconds(1))
        let menus = (NSApp.mainMenu?.items ?? []).map { item in
            "\(item.title)[" + (item.submenu?.items ?? []).filter { !$0.isSeparatorItem }.map(\.title).joined(separator: ", ") + "]"
        }
        print("BG MENU " + menus.joined(separator: " "))
        coordinator.startSinglePlayer(generator: SeededGenerator(seed: 4))
        NSApp.activate(ignoringOtherApps: true)
        await play(seconds: 5)
        report("trước khi ẩn")
        let window = NSApp.windows.first(where: { $0.isVisible })
        if mode == "resize" {
            // Đổi kích thước cửa sổ liên tục trong lúc quân đang nhảy: cảnh phải dựng lại mà không làm kẹt ván.
            for step in 0..<24 {
                window?.setContentSize(NSSize(width: 1000 + (step % 2) * 160, height: 700 + (step % 2) * 80))
                await play(seconds: 0.3)
            }
        } else if mode == "miniaturize" { window?.miniaturize(nil) } else { NSApp.hide(nil) }
        await play(seconds: Double(ProcessInfo.processInfo.environment["COCANGUA_BACKGROUND_SECONDS"] ?? "") ?? 8)
        report("đang ẩn")
        if mode == "miniaturize" { window?.deminiaturize(nil) } else { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<4 {
            await play(seconds: 3)
            report("sau khi hiện lại")
        }
        NSApp.terminate(nil)
    }

    /// Chạy thử giao thức phòng trực tiếp bằng đường truyền giả lập: một chủ phòng, một khách, hai bot (phòng 4 chỗ).
    /// Kiểm tra hai máy thấy cùng một ván, bot của chủ phòng chơi thay khi khách rời, và khách bị đưa ra khi chủ phòng rời.
    private static func roomTest(coordinator: AppCoordinator) async {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Thử phòng")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let settings = coordinator.settings
        let saved = (settings.soundVolume, settings.musicVolume, settings.animationSpeed)
        settings.soundVolume = 0
        settings.musicVolume = 0
        settings.animationSpeed = .fast
        coordinator.applyAudioSettings()
        guard let code = RoomCode("412345") else { return }

        func pair() -> (host: RoomManager, guest: RoomManager, guestLink: LoopbackRoomTransport) {
            let hostLink = LoopbackRoomTransport(id: "host", name: "Chủ phòng")
            let guestLink = LoopbackRoomTransport(id: "guest", name: "Khách")
            hostLink.others = [guestLink]
            guestLink.others = [hostLink]
            let host = RoomManager(settings: settings), guest = RoomManager(settings: settings)
            host.debugAttach(hostLink, code: code, asHost: true)
            guest.debugAttach(guestLink, code: code, asHost: false)
            return (host, guest, guestLink)
        }
        func play(_ sessions: [GameSession?], seconds: Double) async {
            let until = Date().addingTimeInterval(seconds)
            while Date() < until {
                try? await Task.sleep(for: .seconds(0.1))
                for session in sessions {
                    session?.humanRoll()
                    if let move = session?.selectableMoves.first { session?.humanChose(move) }
                }
            }
        }

        // 1. Sảnh chờ và bắt đầu.
        let room = pair()
        var hostSession: GameSession?, guestSession: GameSession?
        room.host.onOpenSession = { hostSession = $0; $0.start() }
        room.guest.onOpenSession = { guestSession = $0; $0.start() }
        try? await Task.sleep(for: .seconds(0.5))
        print("ROOM sảnh: chủ thấy \(room.host.members.count) người, khách thấy \(room.guest.members.count) người, khách biết chủ phòng=\(room.guest.members.contains { $0.isHost && !$0.isLocal }), bắt đầu được=\(room.host.canStart)")
        room.host.start()
        try? await Task.sleep(for: .seconds(0.5))
        let seats = hostSession?.configuration.seats.map { "\($0.color):\($0.controller)" }.joined(separator: " ") ?? "-"
        print("ROOM chỗ ngồi máy chủ phòng: \(seats)")
        print("ROOM chỗ ngồi máy khách: \(guestSession?.configuration.seats.map { "\($0.color):\($0.controller)" }.joined(separator: " ") ?? "-")")

        // 2. Chơi: hai máy phải thấy cùng một chuỗi hành động.
        await play([hostSession, guestSession], seconds: 25)
        try? await Task.sleep(for: .seconds(2))
        let hostLog = hostSession?.log.bytes ?? [], guestLog = guestSession?.log.bytes ?? []
        let shared = min(hostLog.count, guestLog.count)
        print("ROOM sau 25 giây: lượt chủ=\(hostSession?.state.turnNumber ?? -1) lượt khách=\(guestSession?.state.turnNumber ?? -1) hành động chủ=\(hostLog.count) khách=\(guestLog.count) khớp=\(shared > 0 && Array(hostLog.prefix(shared)) == Array(guestLog.prefix(shared))) lệch=\(abs(hostLog.count - guestLog.count))")

        // 3. Khách rời: bot của chủ phòng chơi thay, ván chạy tiếp.
        let turnBefore = hostSession?.state.turnNumber ?? 0
        room.guest.leave()
        await play([hostSession], seconds: 12)
        print("ROOM khách rời: chỗ ngồi máy chủ phòng: \(hostSession?.configuration.seats.map { "\($0.color):\($0.controller)" }.joined(separator: " ") ?? "-"); lượt \(turnBefore) → \(hostSession?.state.turnNumber ?? -1); khách còn trong phòng=\(room.guest.isActive)")
        room.host.leave()

        // 4. Chủ phòng rời giữa ván: khách bị đưa ra khỏi ván kèm thông báo.
        let second = pair()
        var closed = false
        second.host.onOpenSession = { $0.start() }
        second.guest.onOpenSession = { $0.start() }
        second.guest.onRoomClosed = { closed = true }
        try? await Task.sleep(for: .seconds(0.5))
        second.host.start()
        try? await Task.sleep(for: .seconds(1.5))
        second.host.leave()
        try? await Task.sleep(for: .seconds(0.5))
        print("ROOM chủ phòng rời: khách được báo=\(closed) khách còn trong phòng=\(second.guest.isActive) thông báo=\(second.guest.errorMessage ?? "-")")

        settings.soundVolume = saved.0
        settings.musicVolume = saved.1
        settings.animationSpeed = saved.2
        NSApp.terminate(nil)
    }

    /// Chụp các màn hình chính bằng tiếng Anh để soát bản dịch và bố cục, rồi trả ngôn ngữ về như cũ.
    private static func englishShots(coordinator: AppCoordinator) async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Chụp ảnh gỡ lỗi")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        func shot(_ name: String, after seconds: Double = 0.8) async {
            try? await Task.sleep(for: .seconds(seconds))
            capture(folder.appendingPathComponent("\(name).png"), includeScene: true)
        }
        let saved = (coordinator.settings.language, coordinator.settings.soundVolume, coordinator.settings.musicVolume)
        coordinator.settings.soundVolume = 0
        coordinator.settings.musicVolume = 0
        coordinator.applyAudioSettings()
        try? await Task.sleep(for: .seconds(1))
        NSApp.windows.first(where: { $0.isVisible })?.setContentSize(Device.isPhone ? NSSize(width: 852, height: 393) : NSSize(width: 1180, height: 800))
        if Device.isPhone {
            // Soát bố cục iPhone (chạy kèm COCANGUA_PHONE_PREVIEW=1): giữ ngôn ngữ đang chọn.
            coordinator.showMainMenu()
            await shot("phone-01-menu")
            coordinator.showSinglePlayerSetup()
            await shot("phone-02-setup")
            coordinator.showSettings()
            await shot("phone-03-settings")
            coordinator.showOnlineLobby()
            await shot("phone-04-lobby", after: 3)
            coordinator.startSinglePlayer(generator: SeededGenerator(seed: 11))
            try? await Task.sleep(for: .seconds(1))
            coordinator.session?.humanRoll()
            await shot("phone-05-game", after: 2.5)
            var end = GameState(colors: PlayerColor.allCases, rules: .traditional)
            end.players[0].horses = [.home(6), .home(5), .home(4), .home(2)]
            coordinator.startSinglePlayer(initialState: end, generator: FixedDice(values: [3]))
            try? await Task.sleep(for: .seconds(0.8))
            coordinator.session?.humanRoll()
            await shot("phone-06-result", after: 4.5)
            capture(folder.appendingPathComponent("phone-06b-result-card.png"), includeScene: false)
            coordinator.settings.soundVolume = saved.1
            coordinator.settings.musicVolume = saved.2
            NSApp.terminate(nil)
            return
        }
        coordinator.showSettings()
        await shot("en-00-settings-vi")
        coordinator.settings.language = .en
        await shot("en-01-settings")
        coordinator.showMainMenu()
        await shot("en-02-menu")
        coordinator.showSinglePlayerSetup()
        await shot("en-03-setup")
        coordinator.showOnlineLobby()
        await shot("en-04-lobby", after: 3)
        coordinator.startSinglePlayer(generator: SeededGenerator(seed: 11))
        try? await Task.sleep(for: .seconds(1))
        coordinator.session?.humanRoll()
        await shot("en-05-game", after: 2.5)
        coordinator.settings.language = saved.0
        coordinator.settings.soundVolume = saved.1
        coordinator.settings.musicVolume = saved.2
        NSApp.terminate(nil)
    }

    private static func capture(_ url: URL, includeScene: Bool) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let root = window.contentView,
              let ui = root.bitmapImageRepForCachingDisplay(in: root.bounds),
              let out = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: ui)
        guard let context = NSGraphicsContext(bitmapImageRep: out)?.cgContext else { return }
        let full = CGRect(origin: .zero, size: root.bounds.size)
        // SwiftUI vẽ nền và HUD; SKView vẽ bằng Metal nên phải lấy ảnh riêng rồi ghép vào giữa.
        if let overlay = ui.cgImage { context.draw(overlay, in: full) }
        if includeScene, let view = findSKView(in: root), let scene = view.scene, let texture = view.texture(from: scene) {
            context.draw(texture.cgImage(), in: view.convert(view.bounds, to: nil))
        }
        if let data = out.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("SNAPSHOT \(url.lastPathComponent)")
        }
    }

    private static func findSKView(in view: NSView) -> SKView? {
        if let found = view as? SKView { return found }
        for child in view.subviews {
            if let found = findSKView(in: child) { return found }
        }
        return nil
    }
    #endif
}

#if DEBUG
/// Bộ sinh số có hạt giống, chỉ dùng cho ảnh chụp gỡ lỗi để kết quả lặp lại được.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Ép vài lần đổ đầu ra giá trị định trước (chỉ cho ảnh chụp gỡ lỗi), sau đó ngẫu nhiên thật.
struct FixedDice: RandomNumberGenerator {
    var values: [Int]
    private var fallback = SystemRandomNumberGenerator()
    init(values: [Int]) { self.values = values }
    mutating func next() -> UInt64 {
        guard !values.isEmpty else { return fallback.next() }
        // Int.random(in: 1...6) lấy phần cao của số 64 bit nhân với 6; đặt giá trị vào giữa khoảng tương ứng.
        let value = UInt64(values.removeFirst() - 1)
        return (value &* (UInt64.max / 6)) &+ (UInt64.max / 12)
    }
}
#endif
