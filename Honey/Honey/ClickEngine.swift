import Foundation
import CoreGraphics
import AppKit

// ══════════════════════════════════════════════════════════════
//  CLICK ENGINE — mirrors C# ClickLoop with same timing logic
// ══════════════════════════════════════════════════════════════

final class ClickEngine {

    // ── Shared state (mirrors C# volatile fields) ──────────────
    var activo: Bool = false {
        didSet { if !activo { cpsDisplay = 0 } }
    }
    var saltoActivo: Bool = false
    var running: Bool = true

    // Target click point (screen coordinates)
    private(set) var setX: Int = 0
    private(set) var setY: Int = 0

    // Cached params (mirrors _cachedVeloc, _cachedMulti, etc.)
    var cachedVeloc: Int = 1        { didSet { paramsChanged = true } }
    var cachedMulti: Int = 1        { didSet { paramsChanged = true } }
    var cachedDelayEnabled: Bool = false { didSet { paramsChanged = true } }
    var cachedDelayLevel: Int = 1   { didSet { paramsChanged = true } }

    // Display values (read from UI timer on main thread)
    var cpsDisplay: Int = 0
    var pingMs: Int     = -1

    // Internal
    private var paramsChanged: Bool = true
    private var clickThread: Thread?
    private var saltoThread: Thread?
    private var pingThread: Thread?

    // Salto fixed coords (mirrors SALTO_X / SALTO_Y)
    private let saltoX: Int = 970
    private let saltoY: Int = 300

    // ── Callbacks for UI updates ────────────────────────────────
    var onCPSUpdate: ((Int) -> Void)?
    var onContadorUpdate: ((Int64) -> Void)?
    var onPingUpdate: ((Int) -> Void)?

    // ── Counter (thread-safe via atomic-style OSAtomicIncrement) ─
    private var _contadorValue: Int64 = 0

    private func incrementContador() {
        OSAtomicIncrement64(&_contadorValue)
    }

    func readContador() -> Int64 {
        return _contadorValue
    }

    // ── Start all background threads ───────────────────────────
    func start() {
        startClickThread()
        startSaltoThread()
        startPingThread()
    }

    func stop() {
        running = false
        activo = false
        saltoActivo = false
    }

    func setPoint(x: Int, y: Int) {
        setX = x
        setY = y
        paramsChanged = true
    }

    // ══════════════════════════════════════════════════════════════
    //  CORE CLICK FUNCTION (via CGEvent — no physical cursor block)
    // ══════════════════════════════════════════════════════════════

    /// Posts a synthetic left-click at (x, y) WITHOUT moving the visible cursor.
    /// Mirrors: PostMessage(hwnd, WM_LBUTTONDOWN/UP, ...)
    @inline(__always)
    private func postClick(x: CGFloat, y: CGFloat) -> Bool {
        let pt = CGPoint(x: x, y: y)

        guard
            let evDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left),
            let evUp   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,   mouseCursorPosition: pt, mouseButton: .left)
        else { return false }

        // Post to HID session — does NOT move the physical cursor
        evDown.flags = []
        evUp.flags   = []
        evDown.post(tap: .cghidEventTap)
        evUp.post(tap: .cghidEventTap)
        return true
    }

    // ══════════════════════════════════════════════════════════════
    //  THREAD — CLICK ENGINE
    //  Mirrors C# ClickLoop timing with Stopwatch-equivalent mach_absolute_time
    // ══════════════════════════════════════════════════════════════
    private func startClickThread() {
        let t = Thread { [weak self] in
            guard let self = self else { return }
            self.clickLoop()
        }
        t.name = "ClickLoop"
        t.qualityOfService = .userInteractive
        t.start()
        clickThread = t
    }

    private func clickLoop() {
        // mach_timebase for nanosecond conversion (mirrors Stopwatch.Frequency)
        var tbInfo = mach_timebase_info_data_t()
        mach_timebase_info(&tbInfo)

        // Helper: ticks → nanoseconds
        func ticksToNs(_ ticks: UInt64) -> Double {
            return Double(ticks) * Double(tbInfo.numer) / Double(tbInfo.denom)
        }
        func nsToTicks(_ ns: Double) -> UInt64 {
            return UInt64(ns * Double(tbInfo.denom) / Double(tbInfo.numer))
        }

        var emaCps: Double       = 0.0
        let measWin              = nsToTicks(100_000_000.0)  // 100ms window
        var measCnt: Int         = 0
        var measStart            = mach_absolute_time()
        var tickErr: Double      = 0.0
        var cachedPeriod         = nsToTicks(1_000_000_000.0 / 296.0)  // default 296 CPS
        var nextAt               = mach_absolute_time()
        var failCount: Int       = 0

        while running {
            if !activo {
                Thread.sleep(forTimeInterval: 0.001)
                nextAt       = mach_absolute_time()
                measStart    = nextAt
                measCnt      = 0
                tickErr      = 0.0
                emaCps       = 0.0
                failCount    = 0
                continue
            }

            // Recalc period if params changed (mirrors _paramsChanged)
            if paramsChanged {
                paramsChanged = false

                let veloc = cachedVeloc
                let multi = cachedMulti
                let den   = cachedDelayEnabled
                let dlvl  = cachedDelayLevel

                let t_    = Double(veloc - 1) / 99.0
                let base_ = 296.0 - t_ * (296.0 - 30.0)
                let bonus = Double(multi - 1) * 9.0
                var target = base_ + bonus
                if den { target *= (1.0 - Double(dlvl) * 0.05) }

                cachedPeriod = nsToTicks(1_000_000_000.0 / target)
                tickErr = 0.0
            }

            // ── SpinWait calibrado (mirrors FIX #4+#20) ──────────
            let now = mach_absolute_time()
            let leftNs = nextAt > now ? ticksToNs(nextAt - now) : 0.0

            if leftNs > 1_500_000.0 {
                Thread.sleep(forTimeInterval: 0.001)
            } else if leftNs <= 0 {
                if nextAt < now &- cachedPeriod {
                    nextAt = now
                }
            }

            // Spin the last 500µs
            let target100us = nextAt &- nsToTicks(100_000.0)
            if leftNs > 500_000.0 {
                while mach_absolute_time() < target100us && activo && running { }
            }
            while mach_absolute_time() < nextAt && activo && running { }

            if !activo || !running { continue }

            // ── Post click (mirrors PostMessage WM_LBUTTONDOWN/UP) ──
            let t0 = mach_absolute_time()

            let cx = CGFloat(setX)
            let cy = CGFloat(setY)

            // micro-delay between down and up (mirrors FIX #5+#13 50µs)
            guard let evDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: CGPoint(x: cx, y: cy), mouseButton: .left),
                  let evUp   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                       mouseCursorPosition: CGPoint(x: cx, y: cy), mouseButton: .left)
            else {
                failCount += 1
                if failCount >= 3 { activo = false }
                continue
            }

            evDown.post(tap: .cghidEventTap)

            // 50µs micro delay (mirrors freqL / 20000)
            let delayTarget = mach_absolute_time() &+ nsToTicks(50_000.0)
            while mach_absolute_time() < delayTarget { }

            evUp.post(tap: .cghidEventTap)

            let clickOverheadTicks = mach_absolute_time() - t0
            failCount = 0

            incrementContador()
            measCnt += 1

            // ── tickErr drift correction (mirrors FIX #14+#15) ───
            let periodWithErr = Double(cachedPeriod) + tickErr - Double(clickOverheadTicks)
            var nextPeriod    = UInt64(max(0, periodWithErr))
            let minPeriod     = max(1, cachedPeriod / 2)
            if nextPeriod < minPeriod { nextPeriod = minPeriod }

            tickErr = periodWithErr - Double(nextPeriod)
            if tickErr > 1000 || tickErr < -1000 { tickErr = 0 }

            nextAt = nextAt &+ nextPeriod

            // ── EMA CPS update (mirrors FIX #6+#7) ──────────────
            let nowMeas = mach_absolute_time()
            if nowMeas - measStart >= measWin {
                let elapsed = ticksToNs(nowMeas - measStart)
                let inst    = Double(measCnt) * 1_000_000_000.0 / elapsed

                if emaCps < 1.0 {
                    emaCps = inst
                } else {
                    let delta = abs(inst - emaCps) / emaCps
                    let alpha: Double = delta > 0.30 ? 0.50 : 0.15
                    emaCps = alpha * inst + (1.0 - alpha) * emaCps
                }

                let cps = Int(emaCps.rounded())
                DispatchQueue.main.async { [weak self] in
                    self?.onCPSUpdate?(cps)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onContadorUpdate?(self?.readContador() ?? 0)
                }

                measCnt  = 0
                measStart = nowMeas
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  THREAD — SALTO (mirrors C# StartSaltoThread, period 200ms)
    // ══════════════════════════════════════════════════════════════
    private func startSaltoThread() {
        let t = Thread { [weak self] in
            guard let self = self else { return }
            self.saltoLoop()
        }
        t.name = "SaltoThread"
        t.qualityOfService = .userInteractive
        t.start()
        saltoThread = t
    }

    private func saltoLoop() {
        var tbInfo = mach_timebase_info_data_t()
        mach_timebase_info(&tbInfo)

        func nsToTicks(_ ns: Double) -> UInt64 {
            return UInt64(ns * Double(tbInfo.denom) / Double(tbInfo.numer))
        }
        func ticksToNs(_ ticks: UInt64) -> Double {
            return Double(ticks) * Double(tbInfo.numer) / Double(tbInfo.denom)
        }

        let period = nsToTicks(200_000_000.0)  // 200ms
        var nextAt = mach_absolute_time()

        while running {
            if !saltoActivo {
                Thread.sleep(forTimeInterval: 0.001)
                nextAt = mach_absolute_time()
                continue
            }

            // SpinWait (mirrors salto thread FIX)
            let now = mach_absolute_time()
            let leftNs = nextAt > now ? ticksToNs(nextAt - now) : 0.0

            if leftNs > 1_500_000.0 {
                Thread.sleep(forTimeInterval: 0.001)
            } else if leftNs <= 0 && nextAt < now &- period {
                nextAt = now
            }

            let target100us = nextAt &- nsToTicks(100_000.0)
            if leftNs > 500_000.0 {
                while mach_absolute_time() < target100us && saltoActivo && running { }
            }
            while mach_absolute_time() < nextAt && saltoActivo && running { }

            if !saltoActivo || !running { continue }

            // Post salto click
            let cx = CGFloat(saltoX)
            let cy = CGFloat(saltoY)

            if let evDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                    mouseCursorPosition: CGPoint(x: cx, y: cy), mouseButton: .left),
               let evUp   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                    mouseCursorPosition: CGPoint(x: cx, y: cy), mouseButton: .left) {
                evDown.post(tap: .cghidEventTap)
                let d = mach_absolute_time() &+ nsToTicks(50_000.0)
                while mach_absolute_time() < d { }
                evUp.post(tap: .cghidEventTap)
            }

            nextAt = nextAt &+ period
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  THREAD — PING (mirrors C# ICMP→HTTP fallback)
    // ══════════════════════════════════════════════════════════════
    private func startPingThread() {
        let t = Thread { [weak self] in
            guard let self = self else { return }
            self.pingLoop()
        }
        t.name = "PingThread"
        t.qualityOfService = .background
        t.start()
        pingThread = t
    }

    private func pingLoop() {
        while running {
            let ms = measurePing(host: "boombang.tv")
            pingMs = ms
            DispatchQueue.main.async { [weak self] in
                self?.onPingUpdate?(ms)
            }
            Thread.sleep(forTimeInterval: 3.0)
        }
    }

    private func measurePing(host: String) -> Int {
        // HTTP HEAD fallback (mirrors FIX #18)
        guard let url = URL(string: "http://\(host)") else { return -1 }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
        req.httpMethod = "HEAD"
        let start = mach_absolute_time()
        let sem   = DispatchSemaphore(value: 0)
        var result: Int = -1

        URLSession.shared.dataTask(with: req) { _, resp, _ in
            if (resp as? HTTPURLResponse) != nil {
                var tbInfo = mach_timebase_info_data_t()
                mach_timebase_info(&tbInfo)
                let elapsed = mach_absolute_time() - start
                let ms = Int(Double(elapsed) * Double(tbInfo.numer) / Double(tbInfo.denom) / 1_000_000.0)
                result = ms
            }
            sem.signal()
        }.resume()

        sem.wait()
        return result
    }
}
