# DARE•MOTO — by Ianus Project · Asset di brand (direzione D)

## Palette
| Ruolo | HEX |
|---|---|
| Cobalto (primario, fondi) | `#1F3BE0` |
| Lime (accento, solo su fondi scuri/cobalto) | `#D4F53C` |
| Blu notte (punto su fondo chiaro, testi) | `#0B1033` |
| Bianco | `#FFFFFF` |
| Firma "by Ianus Project" su chiaro / su scuro | `#0B1033` / `#FFFFFF` |

Regola: il lime non va mai su fondo bianco, perché il contrasto è troppo basso. Su fondo chiaro il punto diventa blu notte.

## Font
- Wordmark: **Unbounded Bold 700**
- Firma: **Inter**, maiuscolo, spaziato. "BY" in Medium 500, "IANUS PROJECT" in Bold 700. Nel logo è a 36 px con il nome DARE•MOTO a 64 px (56%)
- Testi: **Inter Medium 500**

Entrambi sono Google Fonts con licenza SIL OFL. Negli SVG il testo è già convertito in tracciati, quindi i font non servono per usare gli asset.

## Contenuto
- `logo/`: logo completo (simbolo + nome + firma) e versione header senza firma, ognuno in variante `light` (per fondi chiari) e `dark` (per fondi scuri). Ogni logo c'è in SVG, PNG e PNG @2x con fondo trasparente. C'è anche il solo simbolo ‹•›.
- `icon/`
  - `daremoto-icon.svg`: master vettoriale
  - `daremoto-icon.ico`: Windows, 16–256 px
  - `daremoto-icon.icns`: macOS
  - `daremoto-icon-macos-1024.png`: icona macOS con il margine previsto da Apple
  - `png/`: 16, 24, 32, 48, 64, 128, 256, 512, 1024 px
  - `svg/`: varianti semplificate per le misure piccole (16, 32, 64), con tratti più spessi
- `tray/`
  - `daremoto-tray.ico`: area di notifica Windows/Linux, a colori
  - `daremoto-tray-mac-template*.png`: barra dei menu macOS, nero su trasparente da usare come template image (22 px e @2x 44 px)
- `background/`: sfondo in SVG e PNG a 1920×1080, 2560×1440 e 3840×2160

## Dove vanno nel fork RustDesk (indicativo)
I nomi esatti dipendono dalla versione del fork: verificateli nella cartella `res/` e in `flutter/assets/`.
- `res/icon.ico` ← `icon/daremoto-icon.ico`
- `res/icon.png`, `res/128x128.png`, `res/64x64.png`, `res/32x32.png`, `res/128x128@2x.png` ← i PNG corrispondenti in `icon/png/` (per @2x usare il 256)
- `res/mac-icon.png` ← `icon/daremoto-icon-macos-1024.png`
- `res/tray-icon.ico` ← `tray/daremoto-tray.ico`
- `res/mac-tray-*.png` ← `tray/daremoto-tray-mac-template@2x.png` (e la variante white se il fork la usa)
- `res/logo.svg`, `res/logo-header.svg`, `flutter/assets/logo.svg` ← i file corrispondenti in `logo/`
- Icone Android/iOS: rigenerarle dal master `icon/daremoto-icon-1024.png` con flutter_launcher_icons
