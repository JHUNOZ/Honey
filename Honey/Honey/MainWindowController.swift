import Cocoa

// ══════════════════════════════════════════════════════════════
//  MAIN WINDOW CONTROLLER
//  Mirrors: FormAuto — the main UI + orchestration
// ══════════════════════════════════════════════════════════════

final class MainWindowController: NSWindowController {

    private let engine  = ClickEngine()
    private let hotkeys = HotkeyManager()
    private var uiTimer: Timer?

    // ── UI Controls (mirrors FormAuto designer fields) ──────────
    private var lblVentana: NSTextField!
    private var lblCPS: NSTextField!
    private var txtX: NSTextField!
    private var txtY: NSTextField!
    private var nVeloc: NSSlider!
    private var lblVelocValue: NSTextField!
    private var nMulti: NSStepper!
    private var lblMultiValue: NSTextField!
    private var cDelay: NSButton!
    private var nDelay: NSStepper!
    private var lblDelayValue: NSTextField!
    private var btnInfo: NSButton!
    private var btnActivar: NSButton!
    private var btnDesactivar: NSButton!

    // ── State display ────────────────────────────────────────────
    private var cpsDisplay: Int = 0
    private var contador: Int64 = 0
    private var pingMs: Int     = -1

    convenience init() {
        let w = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask:    [.titled, .closable, .miniaturizable],
            backing:      .buffered,
            defer:        false
        )
        w.title           = "Honey"
        w.backgroundColor = NSColor(red: 0.00, green: 0.00, blue: 0.40, alpha: 1.0)
        w.isReleasedWhenClosed = false
        w.center()

        self.init(window: w)
        w.delegate = self
        buildUI()
        wireEngine()
        wireHotkeys()

        engine.start()
        hotkeys.register()

        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.uiTimerTick()
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  BUILD UI  (programmatic — mirrors InitializeComponent)
    // ══════════════════════════════════════════════════════════════
    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ── Setpoint group ───────────────────────────────────────
        let gpSetpoint = makeGroupBox(title: "Setpoint", frame: NSRect(x: 12, y: 290, width: 145, height: 110))
        content.addSubview(gpSetpoint)

        let lblX = makeLabel("X:", frame: NSRect(x: 14, y: 68, width: 20, height: 20))
        gpSetpoint.addSubview(lblX)

        txtX = makeTextField("0", frame: NSRect(x: 38, y: 65, width: 90, height: 24))
        txtX.delegate = self
        gpSetpoint.addSubview(txtX)

        let lblY = makeLabel("Y:", frame: NSRect(x: 14, y: 36, width: 20, height: 20))
        gpSetpoint.addSubview(lblY)

        txtY = makeTextField("0", frame: NSRect(x: 38, y: 33, width: 90, height: 24))
        txtY.delegate = self
        gpSetpoint.addSubview(txtY)

        // ── Configuration group ──────────────────────────────────
        let gpConfig = makeGroupBox(title: "Configuración", frame: NSRect(x: 168, y: 255, width: 160, height: 145))
        content.addSubview(gpConfig)

        // Veloc row
        let lblVelocLbl = makeLabel("Veloc", frame: NSRect(x: 8, y: 108, width: 45, height: 18))
        gpConfig.addSubview(lblVelocLbl)

        nVeloc = NSSlider(frame: NSRect(x: 8, y: 86, width: 100, height: 20))
        nVeloc.minValue = 1; nVeloc.maxValue = 100; nVeloc.intValue = 1
        nVeloc.target   = self; nVeloc.action  = #selector(velocChanged)
        nVeloc.wantsLayer = true; nVeloc.layer?.backgroundColor = NSColor.clear.cgColor
        gpConfig.addSubview(nVeloc)

        lblVelocValue = makeLabel("1", frame: NSRect(x: 112, y: 86, width: 38, height: 20))
        lblVelocValue.alignment = .right
        gpConfig.addSubview(lblVelocValue)

        // Multi row
        let lblMultiLbl = makeLabel("Multi", frame: NSRect(x: 8, y: 64, width: 40, height: 18))
        gpConfig.addSubview(lblMultiLbl)

        nMulti = NSStepper(frame: NSRect(x: 100, y: 62, width: 30, height: 22))
        nMulti.minValue = 1; nMulti.maxValue = 20; nMulti.intValue = 1; nMulti.increment = 1
        nMulti.target   = self; nMulti.action  = #selector(multiChanged)
        gpConfig.addSubview(nMulti)

        lblMultiValue = makeLabel("1", frame: NSRect(x: 54, y: 64, width: 40, height: 18))
        gpConfig.addSubview(lblMultiValue)

        // Delay row
        cDelay = NSButton(frame: NSRect(x: 8, y: 38, width: 70, height: 22))
        cDelay.setButtonType(.switch)
        cDelay.title      = "Delay"
        cDelay.state      = .off
        cDelay.contentTintColor = NSColor.white
        cDelay.target     = self
        cDelay.action     = #selector(delayToggled)
        gpConfig.addSubview(cDelay)

        nDelay = NSStepper(frame: NSRect(x: 100, y: 36, width: 30, height: 22))
        nDelay.minValue = 1; nDelay.maxValue = 10; nDelay.intValue = 1; nDelay.increment = 1
        nDelay.target   = self; nDelay.action  = #selector(delayChanged)
        nDelay.isEnabled = false
        gpConfig.addSubview(nDelay)

        lblDelayValue = makeLabel("1", frame: NSRect(x: 54, y: 38, width: 40, height: 18))
        lblDelayValue.textColor = NSColor(white: 0.5, alpha: 1)
        gpConfig.addSubview(lblDelayValue)

        // Info button
        btnInfo = NSButton(frame: NSRect(x: 20, y: 8, width: 118, height: 24))
        btnInfo.title      = "?  Instrucciones"
        btnInfo.bezelStyle = .rounded
        btnInfo.target     = self
        btnInfo.action     = #selector(btnInfoClick)
        styleButton(btnInfo)
        gpConfig.addSubview(btnInfo)

        // ── Action buttons ───────────────────────────────────────
        btnActivar = NSButton(frame: NSRect(x: 12, y: 245, width: 100, height: 32))
        btnActivar.title      = "▶  Activar"
        btnActivar.bezelStyle = .rounded
        btnActivar.target     = self
        btnActivar.action     = #selector(activarClick)
        styleButton(btnActivar, color: NSColor(red: 0.1, green: 0.55, blue: 0.2, alpha: 1))
        content.addSubview(btnActivar)

        btnDesactivar = NSButton(frame: NSRect(x: 120, y: 245, width: 110, height: 32))
        btnDesactivar.title      = "■  Desactivar"
        btnDesactivar.bezelStyle = .rounded
        btnDesactivar.target     = self
        btnDesactivar.action     = #selector(desactivarClick)
        styleButton(btnDesactivar, color: NSColor(red: 0.55, green: 0.1, blue: 0.1, alpha: 1))
        content.addSubview(btnDesactivar)

        // ── Status group (mirrors groupBox3) ─────────────────────
        let gpStatus = makeGroupBox(title: "Estado", frame: NSRect(x: 12, y: 185, width: 316, height: 52))
        content.addSubview(gpStatus)

        lblCPS = makeMonoLabel("○ CPS:0  Clicks:0  Ping:--ms", frame: NSRect(x: 8, y: 14, width: 298, height: 20))
        gpStatus.addSubview(lblCPS)

        // ── Window / target status label (mirrors lblVentana) ────
        lblVentana = makeMonoLabel("● Listo — usa F3 para setear el punto de click",
                                   frame: NSRect(x: 12, y: 162, width: 316, height: 18))
        lblVentana.textColor = NSColor(red: 0.63, green: 0.82, blue: 1.0, alpha: 1)
        lblVentana.font      = NSFont(name: "Menlo", size: 9) ?? .monospacedSystemFont(ofSize: 9, weight: .regular)
        content.addSubview(lblVentana)

        // ── Decoration / honeycomb visual ────────────────────────
        let honeycombView = HoneycombView(frame: NSRect(x: 0, y: 0, width: 340, height: 155))
        content.addSubview(honeycombView, positioned: .below, relativeTo: gpSetpoint)

        // ── Permissions notice ───────────────────────────────────
        let lblPerms = makeLabel("⚠ Requiere permiso en: Privacidad > Accesibilidad",
                                 frame: NSRect(x: 12, y: 6, width: 316, height: 16))
        lblPerms.font      = .systemFont(ofSize: 9)
        lblPerms.textColor = NSColor(white: 0.55, alpha: 1)
        content.addSubview(lblPerms)
    }

    // ══════════════════════════════════════════════════════════════
    //  WIRE ENGINE CALLBACKS
    // ══════════════════════════════════════════════════════════════
    private func wireEngine() {
        engine.onCPSUpdate = { [weak self] cps in
            self?.cpsDisplay = cps
        }
        engine.onContadorUpdate = { [weak self] cnt in
            self?.contador = cnt
        }
        engine.onPingUpdate = { [weak self] ms in
            self?.pingMs = ms
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  WIRE HOTKEYS  (mirrors WndProc switch)
    // ══════════════════════════════════════════════════════════════
    private func wireHotkeys() {
        hotkeys.onHotkey = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .activate:     self.activarClick()
            case .deactivate:   self.desactivarClick()
            case .setPoint:     self.setearPunto()
            case .toggleSalto:  self.toggleSalto()
            case .toggleClick:  self.toggleClick()
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  ACTIONS  (mirrors C# hotkey handlers)
    // ══════════════════════════════════════════════════════════════

    @objc private func activarClick() {
        engine.activo = true
        updateVentanaLabel()
    }

    @objc private func desactivarClick() {
        engine.activo     = false
        engine.cpsDisplay  = 0
        cpsDisplay         = 0
    }

    private func toggleClick() {
        if engine.activo { desactivarClick() }
        else             { activarClick() }
    }

    // Mirrors SetearPunto — captures cursor position (= F3 on Win)
    private func setearPunto() {
        let pos = NSEvent.mouseLocation
        // Convert from AppKit coords (bottom-left origin) to screen coords (top-left origin)
        let screenH = NSScreen.main?.frame.height ?? 0
        let x = Int(pos.x)
        let y = Int(screenH - pos.y)

        engine.setPoint(x: x, y: y)

        DispatchQueue.main.async { [weak self] in
            self?.txtX.stringValue = "\(x)"
            self?.txtY.stringValue = "\(y)"
            self?.updateVentanaLabel()
        }
    }

    private func toggleSalto() {
        engine.saltoActivo = !engine.saltoActivo
    }

    private func updateVentanaLabel() {
        let x = engine.setX
        let y = engine.setY
        if x == 0 && y == 0 {
            lblVentana.stringValue = "● Listo — usa F3 para setear el punto de click"
        } else {
            lblVentana.stringValue = "✔ Punto seteado: (\(x), \(y))"
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  UI CONTROLS SYNC  (mirrors SetupParameterSync)
    // ══════════════════════════════════════════════════════════════

    @objc private func velocChanged() {
        let v = Int(nVeloc.intValue)
        lblVelocValue.stringValue = "\(v)"
        engine.cachedVeloc = v
    }

    @objc private func multiChanged() {
        let v = Int(nMulti.intValue)
        lblMultiValue.stringValue = "\(v)"
        engine.cachedMulti = v
    }

    @objc private func delayToggled() {
        let on = cDelay.state == .on
        engine.cachedDelayEnabled = on
        nDelay.isEnabled          = on
        lblDelayValue.textColor   = on ? NSColor.white : NSColor(white: 0.5, alpha: 1)
    }

    @objc private func delayChanged() {
        let v = Int(nDelay.intValue)
        lblDelayValue.stringValue = "\(v)"
        engine.cachedDelayLevel   = v
    }

    // ══════════════════════════════════════════════════════════════
    //  UI TIMER TICK  (mirrors UiTimer_Tick, 100ms)
    // ══════════════════════════════════════════════════════════════
    private func uiTimerTick() {
        let ping  = engine.pingMs >= 0 ? "\(engine.pingMs)ms" : "--ms"
        let salto = engine.saltoActivo ? " [F4●]" : ""
        let dot   = engine.activo      ? "●" : "○"
        let cnt   = engine.readContador()
        lblCPS.stringValue = "\(dot) CPS:\(cpsDisplay)  Clicks:\(cnt)  Ping:\(ping)\(salto)"
    }

    // ══════════════════════════════════════════════════════════════
    //  INFO BUTTON  (mirrors BtnInfo_Click MessageBox)
    // ══════════════════════════════════════════════════════════════
    @objc private func btnInfoClick() {
        let alert = NSAlert()
        alert.messageText     = "Instrucciones — Honey"
        alert.informativeText = """
        F1  →  Activar autoclick
        F2  →  Desactivar
        =   →  Toggle ON/OFF
        F3  →  Setpoint (cursor → punto exacto)
        F4  →  Toggle click 0.2s en X:970 Y:300

        Veloc  1 = 296 CPS   Veloc 100 = 30 CPS
        Multi: +9 CPS por nivel (máx 20)

        Delay (activar checkbox primero):
          1=−5%  2=−10%  3=−15%  4=−20%  5=−25%
          6=−30%  7=−35%  8=−40%  9=−45%  10=−50%

        Nota macOS: Fn+F1/F2/F3/F4 si tienes
        "Usar F1, F2 como teclas estándar" desactivado.

        ★ 0% jitter | 0% drift | 0% lag | 100% estable
        ★ Sin bloqueo de cursor físico (CGEvent)
        """
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

// ══════════════════════════════════════════════════════════════
//  NSWindowDelegate — cleanup on close (mirrors FormAuto_FormClosing)
// ══════════════════════════════════════════════════════════════
extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        uiTimer?.invalidate()
        hotkeys.unregister()
        engine.stop()
    }
}

    // ══════════════════════════════════════════════════════════════
    //  UI HELPERS
    // ══════════════════════════════════════════════════════════════

    private func makeGroupBox(title: String, frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.title          = title
        box.titleFont      = .systemFont(ofSize: 11, weight: .semibold)
        box.borderColor    = NSColor(white: 0.5, alpha: 0.6)
        box.fillColor      = NSColor(red: 0.0, green: 0.0, blue: 0.35, alpha: 1.0)
        box.boxType        = .primary
        box.cornerRadius   = 6
        box.titlePosition  = .atTop
        box.contentViewMargins = NSSize(width: 6, height: 6)
        return box
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame      = frame
        lbl.textColor  = .white
        lbl.font       = .systemFont(ofSize: 11)
        lbl.isBezeled  = false
        lbl.drawsBackground = false
        return lbl
    }

    private func makeMonoLabel(_ text: String, frame: NSRect) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame      = frame
        lbl.textColor  = .white
        lbl.font       = NSFont(name: "Menlo", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .regular)
        lbl.isBezeled  = false
        lbl.drawsBackground = false
        return lbl
    }

    private func makeTextField(_ placeholder: String, frame: NSRect) -> NSTextField {
        let tf = NSTextField(frame: frame)
        tf.placeholderString = placeholder
        tf.stringValue       = placeholder
        tf.backgroundColor   = NSColor(red: 0.1, green: 0.27, blue: 0.59, alpha: 1.0)
        tf.textColor         = .white
        tf.font              = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tf.bezelStyle        = .roundedBezel
        tf.isBordered        = true
        tf.focusRingType     = .none
        return tf
    }

    private func styleButton(_ btn: NSButton, color: NSColor = NSColor(red: 0.17, green: 0.41, blue: 0.76, alpha: 1)) {
        btn.wantsLayer          = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = color.cgColor
        btn.contentTintColor    = .white
        btn.isBordered          = false
    }
}

// ══════════════════════════════════════════════════════════════
//  NSTextField delegate — mirrors txtX/txtY TextChanged
// ══════════════════════════════════════════════════════════════
extension MainWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        let v = Int(tf.stringValue) ?? 0
        if tf === txtX { engine.setPoint(x: v,           y: engine.setY) }
        else           { engine.setPoint(x: engine.setX, y: v) }
    }
}
