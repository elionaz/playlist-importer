> [!NOTE]
> **Historical note.** The freemium / StoreKit / Mac App Store plan described in section 3 was dropped on 2026-11-14 ([#1](https://github.com/elionaz/playlist-importer/pull/1)). The app is now free and unlimited, and none of `EntitlementManager`, `PaywallView` or `Configuration.storekit` exist anymore. The performance and macOS 26 notes (sections 1–2) still apply.

# Session 2026-05-11 — Performance fix, macOS 26 bug, Freemium + MAS prep

Resumen ejecutivo de los cambios hechos en esta sesión.

---

## 1. Crash con playlists grandes (4 000+ tracks) — RESUELTO

### Causa raíz

Todo el matching corría en `@MainActor`. `StringSimilarity.normalize` ejecutaba 5 `replacingOccurrences(...options:.regularExpression)` por llamada, cada uno generando `NSString`/`NSRegularExpression` autoreleased. Como el runloop no podía drenar entre iteraciones, los temporales se acumulaban hasta agotar la memoria.

Además:
- `metadataScore` re-normalizaba título/artista/álbum de cada PlexTrack candidato en cada comparación.
- `findCandidates` en fallback escaneaba `allTracks` completo aplicando normalize por track.
- `currentTrackIndex = ti` disparaba `@Observable` 4 000 veces en una ráfaga.

### Cambios

- `Sources/PlaylistImporter/Services/TrackMatchingService.swift`
  - Nuevo `PlexTrackNorm` con `normTitle`/`normArtist`/`normAlbum` precomputados en `buildIndex`.
  - Nuevo `MusicTrackNorm` análogo para el track de entrada.
  - `MatchIndex.artistIndex` ahora tipa `[String: [PlexTrackNorm]]`.
  - `matchAll(tracks:index:onProgress:)` procesa en chunks de 100 envueltos en `autoreleasepool`.
  - Fallback por título usa `break` temprano al llegar a `titleFallbackLimit = 200` (antes hacía `.filter().prefix(200)` materializando el array completo).
- `Sources/PlaylistImporter/Helpers/StringSimilarity.swift`
  - Añadido `scoreNormalized(_:_:)` que asume inputs ya normalizados (sin regex). `score` sigue como wrapper compatible con tests.
- `Sources/PlaylistImporter/Managers/ImportManager.swift`
  - Loop de matching por playlist movido a `Task.detached(priority: .userInitiated)`. El MainActor queda libre para SwiftUI y el autorelease pool drena entre chunks.
  - Progress callback throttleado a cada 100 tracks.
- `Sources/PlaylistImporter/Views/ImportProgressView.swift`
  - Durante `.matching`: muestra `Matching track X / Y` en monoespaciada.
  - Si la playlist tiene ≥ 1 000 tracks: subtexto `Large playlist — this can take a few minutes`.
  - Subtexto `Building search index…` durante `.buildingIndex`.

### Compatibilidad

API pública del servicio se mantuvo: `metadataScore(track:plex:)`, `match`, `matchAll`, `buildIndex`, `MatchIndex.trackCount`, `MatchIndex.indexedPathCount`. **70/70 tests pasan**.

---

## 2. Bug crítico macOS 26 Tahoe — `persistentID` corrupto

### Síntoma

Consola escupía decenas de:
```
String(format:locale:arguments:): Provided argument types ["__NSCFNumber"]
do not match the format string's specifiers
Format '%llX' does not match expected '%@'
Connection to amplibraryd invalidated. clientName:iTunesLibrary(Music2PLX)
```

### Causa

En macOS 26, `ITLibMediaItem.persistentID` se entrega como `NSNumber` y Swift dejó de auto-desempaquetar para `String(format: "%llX", ...)`. El `persistentID` quedaba corrupto, lo que rompía el matching y hacía que `amplibraryd` cerrara la conexión por exceso de errores.

### Fix

`Sources/PlaylistImporter/Services/MusicLibraryService.swift:117`

```swift
// roto en macOS 26:
let persistentID = String(format: "%llX", item.persistentID)

// portable:
let persistentID = String(item.persistentID.uint64Value, radix: 16, uppercase: true)
```

Esta es la API nativa Swift y evita todo el camino por `NSString` format strings.

---

## 3. Freemium + StoreKit + preparación para Mac App Store

### Decisión de modelo

- Compra única (no suscripción) ~200 MXN (Tier 7 MAS México = $199 MXN).
- 5 imports gratis, después paywall.
- Distribución vía Mac App Store con sandbox + StoreKit 2.
- Producto: `com.playlistimporter.app.pro_unlock` (NonConsumable, family shareable).

### Archivos nuevos

#### `Sources/PlaylistImporter/Managers/EntitlementManager.swift`

`@MainActor @Observable`. Owns:
- `isPro: Bool` — derivado de `Transaction.currentEntitlements`.
- `freeImportsUsed: Int` — persistido en `UserDefaults` (`playlistimporter.freeImportsUsed`).
- `proProduct: Product?` — cargado vía `Product.products(for:)`.
- `canImport`, `freeImportsRemaining` — derivados.
- Listener permanente de `Transaction.updates` (con `[weak self]` para evitar retención).
- `buyPro()`, `restorePurchases()`, `recordImportCompleted()`.

Tiene `print("[Entitlement] ...")` en init, bootstrap, refreshProducts, transaction updates — para debug en la consola de Xcode.

#### `Sources/PlaylistImporter/Views/PaywallView.swift`

Sheet con hero, 4 features (unlimited imports, smart matching, export CSV, one-time purchase), precio dinámico (`product.displayPrice`), botón **Buy Pro**, link **Restore Purchases**, botón **Retry** si la carga falla. Estado del botón explícito (`Loading…` / `Product Unavailable` / `Buy Pro`) en lugar de "gris silencioso".

#### `Configuration.storekit` (raíz del repo)

Config local para probar sin App Store Connect. UUIDs reales, `settings: {}` vacío. Producto `com.playlistimporter.app.pro_unlock` a $9.99 USD, NonConsumable, family shareable.

**Para usarlo**: Edit Scheme → Run → Options → StoreKit Configuration → `Configuration.storekit`.

### Cambios de integración

- `PlaylistImporterApp.swift` — instancia `EntitlementManager`, lo inyecta vía `.environment`.
- `ImportManager.swift` — recibe `entitlement: EntitlementManager?` opcional. Al cerrar `.done` con trabajo real (al menos una playlist con `plexPlaylistID != nil`), llama `entitlement.recordImportCompleted()`. No cuenta si se canceló o falló.
- `ImportProgressView.swift`:
  - Píldora `Pro` / `Upgrade` en la barra del título.
  - Botón Start cambia entre "Start Import" y "Upgrade to Pro to Import" según `canImport`.
  - "X free imports remaining" debajo del botón cuando no es Pro.
  - Sheet `.sheet(isPresented: $showPaywall) { PaywallView() }`.
- `MainView.swift`:
  - **Botón "Upgrade to Pro" siempre visible en la toolbar global** (color prominent, junto al engrane). Si es Pro, se reemplaza por badge "Pro". Click abre el paywall sin necesidad de gastar imports.
  - Sheet montado a nivel MainView también.
- `ContentView.swift` — preview actualizado.
- `gen_xcodeproj.py` — registra `EntitlementManager.swift` y `PaywallView.swift` en SOURCES + managers_refs + views_refs.

### Entitlements para sandbox (preparación MAS)

`Sources/PlaylistImporter/PlaylistImporter-Release.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>          <true/>
<key>com.apple.security.network.client</key>       <true/>
<key>com.apple.security.assets.music.read-only</key> <true/>   <!-- NUEVO -->
<key>com.apple.security.files.user-selected.read-write</key> <true/>   <!-- NUEVO (CSV export) -->
```

`Sources/PlaylistImporter/PlaylistImporter.entitlements` (Debug) se mantuvo con sandbox=false para ciclo de dev rápido.

---

## Pendiente al cerrar esta sesión

- [ ] Validar que `Configuration.storekit` esté enlazado al scheme y `Got 1 product(s)` aparezca en consola.
- [ ] Spike de sandbox end-to-end con Release: confirmar que iTunesLibrary, LAN/Plex, Keychain y CSV export siguen funcionando con sandbox=true en macOS 26.
- [ ] Apple Developer / App Store Connect: crear el app record, productos IAP, certificados de MAS distribution.
- [ ] Decidir si el contador free se sincroniza también a iCloud KVS (resistente a reinstall) — actualmente solo `UserDefaults`.

## Cómo regresar a este estado

- Memoria del proyecto (auto-cargada): `~/.claude/projects/-Users-elionaz-Dev-playlist-importer/memory/`.
- Build SwiftPM: `swift build` → limpio. Tests: `swift test` → 70/70.
- Para correr en Xcode: regenerar xcodeproj con `python3 gen_xcodeproj.py` **o** añadir manualmente al target los archivos nuevos (`EntitlementManager.swift`, `PaywallView.swift`, `Configuration.storekit`).
