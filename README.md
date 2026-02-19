# 🍯 Honey — AutoClick Engine for macOS

Puerto macOS de **Serenidad**, reescrito en Swift nativo con la misma lógica de timing de alta precisión.

---

## Características

| Feature | Serenidad (Windows) | Honey (macOS) |
|---|---|---|
| Click sintético | `PostMessage(WM_LBUTTONDOWN/UP)` | `CGEvent(.leftMouseDown/Up)` |
| Sin bloqueo de cursor | ✅ (PostMessage background) | ✅ (`CGEvent` no mueve el cursor físico) |
| Hotkeys globales | `RegisterHotKey` (Win32) | `RegisterEventHotKey` (Carbon) |
| Timer alta precisión | `Stopwatch + timeBeginPeriod(1)` | `mach_absolute_time()` |
| Thread timing | `THREAD_PRIORITY_TC=15` | `QualityOfService.userInteractive` |
| EMA CPS | ✅ (alpha 0.15/0.50) | ✅ (mismo algoritmo) |
| Drift correction tickErr | ✅ | ✅ (mismo algoritmo) |
| SpinWait calibrado | ✅ | ✅ (mismo patrón 500µs/100µs) |
| Thread Salto (200ms) | ✅ | ✅ |
| Ping HTTP fallback | ✅ | ✅ |
| Rango CPS | 30–296 CPS | 30–296 CPS |

---

## Requisitos

- macOS 13.0+ (Ventura o superior)
- Xcode 15+
- **Permiso de Accesibilidad** (ver abajo)

---

## Instalación

### 1. Abrir el proyecto
```bash
open Honey.xcodeproj
```

### 2. Configurar firma
En Xcode → Target **Honey** → **Signing & Capabilities**:
- Team: selecciona tu Apple ID personal (gratuito funciona)
- Bundle ID: `com.honey.autoclick` (o cambia al que quieras)

### 3. Build & Run
`Cmd+R`

### 4. Dar permiso de Accesibilidad ⚠️ OBLIGATORIO
Al primer lanzamiento, macOS mostrará un diálogo. Si no aparece:

**System Settings → Privacy & Security → Accessibility**
→ Hacer clic en **+** → Navegar a `Honey.app` → Agregar

Sin este permiso, `CGEvent.post()` no enviará clicks a otras aplicaciones.

---

## Teclas (idénticas a Serenidad)

| Tecla | Acción |
|---|---|
| **F1** | Activar autoclick |
| **F2** | Desactivar |
| **=** | Toggle ON/OFF |
| **F3** | Setpoint — captura posición del cursor |
| **F4** | Toggle salto (click en X:970 Y:300 cada 200ms) |

> **Nota:** En MacBooks sin la tecla Fn bloqueada, es posible que necesites presionar **Fn+F1**, **Fn+F2**, etc.  
> Para usar F1-F4 directamente: **System Settings → Keyboard → "Use F1, F2, etc. as standard function keys"** → activar.

---

## Parámetros

### Veloc (1–100)
- **1** = 296 CPS (máxima velocidad)
- **100** = 30 CPS (mínima velocidad)
- Fórmula: `base = 296 - t*(296-30)` donde `t = (veloc-1)/99`

### Multi (1–20)
- Bonus de `+9 CPS` por nivel
- Se suma sobre el valor de Veloc

### Delay
Activa con el checkbox, luego ajusta el nivel:
- 1=−5%, 2=−10%, 3=−15%, 4=−20%, 5=−25%
- 6=−30%, 7=−35%, 8=−40%, 9=−45%, 10=−50%

---

## Arquitectura

```
Honey/
├── AppDelegate.swift          # Punto de entrada, solicita permisos
├── ClickEngine.swift          # Motor de clicks — toda la lógica de timing
│   ├── clickLoop()            # ← Espejo de C# ClickLoop()
│   ├── saltoLoop()            # ← Espejo de C# StartSaltoThread()
│   └── pingLoop()             # ← Espejo de C# StartPingThread()
├── HotkeyManager.swift        # Hotkeys globales (Carbon RegisterEventHotKey)
├── MainWindowController.swift # UI — espejo de FormAuto
└── HoneycombView.swift        # Vista decorativa (reemplaza pictureBox1)
```

### Por qué CGEvent no bloquea el cursor físico

En Windows, `PostMessage(WM_LBUTTONDOWN)` envía mensajes directamente a la cola de mensajes de una ventana específica (HWND), **sin pasar por el sistema de input físico**. El cursor no se mueve porque el mensaje se inyecta directamente en el target.

En macOS, `CGEvent.post(tap: .cghidEventTap)` con coordenadas fijas logra el mismo efecto: el evento se inyecta en el HID event tap del sistema, pero el cursor visible **no se reposiciona** porque macOS solo actualiza la posición del cursor cuando el usuario mueve físicamente el ratón o trackpad. Los eventos sintéticos de click pasan por la posición especificada sin "mover" el cursor persistentemente.

---

## Diferencias respecto a Serenidad

1. **Sin detección de proceso**: Serenidad buscaba `BoombangLauncher.exe` por nombre. En macOS, los clicks van a las coordenadas de pantalla directamente (como hace `PostMessage` con las coordenadas convertidas). Si necesitas target específico por app, se puede agregar con `CGWindowListCopyWindowInfo`.

2. **Coordenadas**: macOS usa origen en esquina superior-izquierda para CGEvent, pero AppKit usa inferior-izquierda. La conversión se hace automáticamente en `setearPunto()`.

3. **Thread affinity**: `SetThreadAffinityMask` no existe en macOS. La QoS `.userInteractive` es el equivalente más cercano.

4. **`timeBeginPeriod(1)`**: No necesario en macOS — `mach_absolute_time()` ya tiene resolución sub-microsegundo de forma nativa.

---

## Troubleshooting

**Los clicks no funcionan / la app no hace nada:**
→ Verifica permiso de Accesibilidad (paso 4)

**Las teclas de función no responden:**
→ Activa "Use F1, F2 as standard function keys" en System Settings → Keyboard

**El build falla con "Sandbox" error:**
→ El entitlements tiene `app-sandbox = false` intencionalmente. Asegúrate de que Xcode no sobrescriba esto.

**CPS más bajo del esperado:**
→ El primer segundo puede ser inestable mientras el EMA se calibra. Es normal.
