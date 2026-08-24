# Kino Studio — Feature Matrix

**Research date:** 2026-08-24
**Target reference:** CapCut iOS app (App Store US listing, Bytedance Pte. Ltd.), current version **19.1.0** (released ~Aug 18, 2026; requires iOS 13+; 804.9 MB; #1 Photo & Video, 1.1M ratings, 4.6★)

**Sources researched:**

1. Apple App Store listing — `apps.apple.com/us/app/capcut-video-editor/id1500855883` (feature copy, version history, IAP pricing $9.99/$19.99/mo, $89.99/yr, privacy labels)
2. `capcut.com` homepage (2026-08 fetch — product/AI tool catalog, template marketplaces)
3. `capcut.com/help` Help Center & articles: `/help/log-in-to-capcut`, `/help/auto-cut-not-working` (Auto Cut = Mobile+Desktop only, v12+, Templates→AI Creation), `/help/capcut-transitions` (2026 trending transitions), `/help/export-clip-of-video` (In/Out markers), `/help/feature-difference-between-capcut-app-and-ipad`, `/help/problem-of-search-template` (search Mobile+Web only), `/help/change-profile-picture-in-capcut` (Mobile only), `/help/make-account-private` (no private account as of Jan 2026), `/help/remove-watermark-when-exporting-video` (watermark source = template end-clip), `/help/capcut-replaced-ipad`, `/help/capcut-for-ipad`, `/help/standard-version-access-to-diamond-items`
4. `capcut.com/tools/ai-caption-generator` (20+ languages, SRT import, caption templates, customize style/font/size/color/position/animation)
5. `capcut.com/tools/video-transition` + `capcut.com/tools/keyframe-animation` (position/scale/rotation/shape/opacity/color keys; combine with speed curve)
6. `capcut.com/clause/material-license-agreement` (Sounds = personal, non-commercial licensing)
7. DuckDuckGo searches: transition families, keyframe properties, music/commercial-use licensing
8. Local repo inspection: `/root/kino-video/KinoEngine` (sources + tests; `.build` artifacts present; **no Swift toolchain in this environment** — tests not re-run today, but `KinoEngineTests/KTimeTests.swift` covers KTime/Rational/TimeRange and prior build artifacts exist)

**Conventions:**
- **iOS?** = `✔ iOS` (mobile app, verified), `✖ Desktop-only`, `Web` (online editor), or `✔iOS/Web` etc. `UNVERIFIED` = could not confirm platform split from sources.
- **Status** ∈ {NOT STARTED, PARTIAL, FUNCTIONAL, VERIFIED, BLOCKED}. PARTIAL is used only where KinoEngine data structures + tests already exist (time model, project model, effects/filters/masks/keyframes/speed specs — engine under construction; no editor UI or renderer yet). Everything else is NOT STARTED.
- "Implementation (this app)" references current engine files: `KinoEngine/Sources/KinoEngine/{CoreTime/KTime.swift, Model/ProjectModel.swift, Effects/Effects.swift, Keyframes/Keyframes.swift, Speed/SpeedMath.swift, Geometry/KGeometry.swift}`.

---

## 1. Onboarding & Account

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Onboarding & Account | Sign-up flows | Login via phone/email, Apple ID, Google, TikTok, Facebook; guest mode with "continue as guest" prompt; age assurance gate (13+ / In-App Controls per App Store) | ✔ iOS | P3 | NOT STARTED — no auth layer in repo | none | NOT STARTED — no auth or social accounting code exists |
| Onboarding & Account | Synced profile | Avatar + nickname editable **only on Mobile** (not Web/Desktop per Help Center Jan 2026); UID/DID identifiers shown in settings | ✔ iOS (mobile-only editing) | P3 | NOT STARTED | none | NOT STARTED — no profile/identifiers |
| Onboarding & Account | Cloud login sync | Account syncs projects/templates/cloud drafts across Mobile & Desktop; Standard plan is NOT supported on the mobile app/PC (Pro-only stack per Help Center Apr 2026) | ✔ iOS | P3 | NOT STARTED | none | NOT STARTED — no cloud layer |
| Onboarding & Account | Age/content controls | 13+ rating; developer-managed in-app controls for mature template content; age assurance flow | ✔ iOS | P3 | NOT STARTED | none | NOT STARTED — no age assurance |
| Onboarding & Account | Privacy profile setting | As of Jan 2026 CapCut offers **no** "private account" toggle on any platform | ✔iOS/Web/Desktop | P3 | NOT STARTED — n/a | n/a | NOT STARTED — misalignment risk; skip private toggle by design |
| Onboarding & Account | Pro subscription | Monthly $9.99 / Pro monthly $19.99 / yearly $89.99 (IAP); diamond-icon items gated per plan; auto-renewals, price varies by account promo | ✔ iOS | P3 | NOT STARTED — no IAP/entitlements | none | NOT STARTED |
| Onboarding & Account | Terms/privacy acceptance | First-launch terms, privacy & cookies policy disclosure (capcut.com/clause/…) | ✔ iOS | P3 | NOT STARTED | none | NOT STARTED |
| Onboarding & Account | Tutorial/ghost tour | First-open onboarding carousel highlighting template-first usage; no forced tutorial in editor (UNVERIFIED — marketing assertions only) | ✔ iOS | P3 | NOT STARTED | none | NOT STARTED — UNVERIFIED specifics |
| Onboarding & Account | Legal watermarks/age warnings | Warnings when exporting templates containing licensed elements | ✔ iOS | P3 | NOT STARTED | none | NOT STARTED |

## 2. Home & Projects

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Home & Projects | Home feed | Home tab with big "+" new project button, templates/trends carousel, personal space vs templates | ✔ iOS | P2 | NOT STARTED | none | NOT STARTED |
| Home & Projects | Project list / "My Projects" | Grid of saved drafts: thumbnail, duration, aspect; tap to reopen; long-press for actions | ✔ iOS | P0 | NOT STARTED — model: `KinoProject.meta` (name/id/dates) exists | none | PARTIAL — project meta model exists; no list UI or store |
| Home & Projects | Rename project | Tap title in editor header or context menu; renames save in project meta | ✔ iOS | P0 | `KinoProject.Meta.name` | none | PARTIAL — field exists; no rename flow |
| Home & Projects | Copy project | Long-press → "Duplicate/Create copy"; new UUID + copy of timeline | ✔ iOS | P1 | none | none | NOT STARTED |
| Home & Projects | Delete project | Move to trash/bin; recoverable trash; permanent delete | ✔ iOS | P0 | none | none | NOT STARTED |
| Home & Projects | Search projects | Home/My Projects search by text; template search exists on Mobile+Web (NOT Desktop) | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED project-name search specifics |
| Home & Projects | Draft autosave | Unnamed autosaved draft created on exiting editor ("Untitled" handled); CapCut keeps local drafts offline | ✔ iOS | P0 | `KinoProject` Codable JSON + `schemaVersion` migrations | none | PARTIAL — serialization & migration stubs exist; no persistence layer |
| Home & Projects | Resumable edit state | Re-open restores last playhead + selection | ✔ iOS | P0 | `lastPlayhead`, `lastSelectedClipID` | none | PARTIAL — fields exist in model; no restore flow |
| Home & Projects | Local storage management | Manage cache/local projects to free storage (reviewers report storage pressure on mobile) | ✔ iOS | P2 | none | none | NOT STARTED |
| Home & Projects | Team collab | CapCut Teams/team projects (Pro tier) — collab editing live cursors | ✔iOS/Web | P3 | none | none | NOT STARTED — collab is Pro/desktop-centric; skip (UNVERIFIED mobile extent) |

## 3. Media Import & Options

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Media Import | Photos library import | Multi-select from Photos; thumbnails with duration; select multiple clips in one add | ✔ iOS | P0 | `MediaAsset` (uri, kind, resolution, duration, fps) | none | PARTIAL — asset model exists; no picker |
| Media Import | "Select multiple" | Multi-select mode on import page; iPad variant explicitly supports multiple selections at once | ✔ iOS | P1 | none | none | NOT STARTED |
| Media Import | Files/Files app import | Import video/audio/images from Files; local font import supported (App Store copy: "Fonts can be imported locally") | ✔ iOS | P1 | none | none | NOT STARTED |
| Media Import | Import from cloud | iCloud/Google Drive/Dropbox pickers | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED full provider list |
| Media Import | Import from camera roll to canvas | Add media appends to end of main track; media page shows "add to timeline" | ✔ iOS | P0 | none | none | NOT STARTED |
| Media Import | Project aspect from first clip | New project ratio picker (9:16/16:9/1:1/4:3 etc.); importing mixed ratios keeps canvas | ✔ iOS | P0 | `KCanvasPreset` ratios (9 presets) | none | PARTIAL — presets exist; no canvas-aspect flow |
| Media Import | Imported image duration | Images get default duration (~3-5s) adjustable by dragging clip edge | ✔ iOS | P1 | `Clip.duration` = speed-projected `sourceRange`; image sourceRange any | none | NOT STARTED — UNVERIFIED default seconds |
| Media Import | Slow/fast mixed fps | Videos of differing fps (24/29.97/30/60/120/240) coexist; project fps fixed at export | ✔ iOS | P1 | `Rational` fps24/25/30/50/60/120/240 + 2397/2997 | ✔ present (frame math tests) | PARTIAL — fps model + tests exist; import split not implemented |
| Media Import | HEVC/H.265 + HDR assets | Import HEVC/HLG footage; displayed in real time; smart HDR export | ✔ iOS | P1 | none | none | NOT STARTED |
| Media Import | Live Photo support | Live Photos import as video or still (UNVERIFIED) | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED |
| Media Import | Duplicate asset entries | Same file can be added multiple times as separate MediaAsset entries | ✔ iOS | P1 | `MediaAsset(id: UUID())` unique per import | none | PARTIAL — model supports; no flow |
| Media Import | Asset metadata | Sort by date; name display in import page; duration badge | ✔ iOS | P2 | `addedAt`, `name`, `duration` fields | none | PARTIAL — fields exist; no UI |

## 4. Camera (in-app recorder)

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Camera | Built-in camera | Recorder on home (camera icon) — record then instantly add to a project | ✔ iOS | P3 | none | none | NOT STARTED — low priority (uses system camera) |
| Camera | Front/back flip | One-tap lens flip, zoom by pinch | ✔ iOS | P3 | none | none | NOT STARTED |
| Camera | Filters & beauty in camera | Live camera filters; make-up/fairy filters removed from Camera per 2024 review — current list UNVERIFIED | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED current beauty set |
| Camera | Timer & flash | Countdown timer + torch toggle (UNVERIFIED — no doc evidence found) | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED |
| Camera | Slow-mo capture option | Record in slow-motion quality directly (UNVERIFIED in current version) | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED |
| Camera | Aspect/frame guides for capture | Grid + ratio guides while recording (UNVERIFIED) | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED |

## 5. Canvas & Aspect

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Canvas | Project ratio presets | 9:16, 16:9, 1:1, 4:5, 3:4, 4:3, 3:2, 2:3, 21:9; custom (UNVERIFIED for custom on mobile) | ✔ iOS | P0 | `KCanvasPreset` 9 variants | none | PARTIAL — preset model exists; no picker |
| Canvas | Canvas scaling/geometry | Preview shows canvas at chosen ratio; assets auto fit, letterboxed with background | ✔ iOS | P0 | `KFitMath` fit/fill/offset/crop; `KTransform.center` normalized | none | PARTIAL — fit math implemented; no preview |
| Canvas | Background fill styles | Solid color, template/image background, blurred background | ✔ iOS | P1 | `KBackground` (solid/blurAssets/image) | none | PARTIAL — enum exists; renderer absent |
| Canvas | Canvas color/fps metadata | Project stores ratio dimensions + fps for export | ✔ iOS | P0 | `CanvasConfig.renderSize`, `.fps` (1080px long-edge baseline) | none | PARTIAL — model + tests for fps math |
| Canvas | Zoom / fit view | Pinch-to-zoom preview, double-tap fit (UNVERIFIED gestures) | ✔ iOS | P1 | none | none | NOT STARTED |
| Canvas | Safe-zones / margins | UNVERIFIED in mobile; absent per reviewer evidence | ✔ iOS | P3 | none | none | NOT STARTED — UNVERIFIED |
| Canvas | Background color picker | Custom background color with hue wheel + presets | ✔ iOS | P1 | `KBackground.solid(colorHex:)` | none | PARTIAL — field exists; no UI |

## 6. Timeline & Multi-track Editing

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Timeline | Main track video | Video clips land sequentially on main track; gaps possible after trim | ✔ iOS | P0 | `Track(kind: .main)` + `clips` sorted by `start` | none | PARTIAL — track model exists; no editor |
| Timeline | Secondary/overlay tracks | Overlay track(s) for PiP video/image above main | ✔ iOS (multi-track at least overlay-level); full multi-track emphasized on iPad | P1 | `KTrackKind.overlay`; z-order `upperClips(at:orderedBy:)` | none | PARTIAL — model exists; no UI/UX |
| Timeline | Audio track | Dedicated audio track(s) below main; music/SFX layers | ✔ iOS | P1 | `KTrackKind.audio` | none | PARTIAL — model exists |
| Timeline | Text track | Captions/titles live on text track, trimmable/movable like media | ✔ iOS | P1 | `KTrackKind.text`, `Clip.kind == .text` | none | PARTIAL — model exists |
| Timeline | Sticker track | Stickers have their own track layer | ✔ iOS | P2 | `KTrackKind.sticker` | none | PARTIAL — model exists |
| Timeline | Multi-track zoom/scroll | Pinch-zoom timeline density, two-finger horizontal scroll; snap to playhead | ✔ iOS | P1 | none | none | NOT STARTED |
| Timeline | Ripple edits (auto-close gaps) | Deleting/trimming non-edge clip pulls following clips left (ripple); CapCut mobile: deleting clip closes gap automatically | ✔ iOS | P0 | none | none | NOT STARTED — key UX decision |
| Timeline | Magnetic/ripple off option | Desktop has switch; mobile auto-ripple by default (UNVERIFIED toggle) | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED |
| Timeline | Lock tracks | Lock a track to prevent edits | ✔iOS/Desktop | P2 | `Track.isLocked` | none | PARTIAL — field exists; no flow |
| Timeline | Hide tracks | Eye-toggle hides track content (keep audible/video control) | ✔iOS/Desktop | P2 | `Track.isHidden` | none | PARTIAL — field exists |
| Timeline | Clip visibility on/off | Per-clip hide (`VisibilityEyeShut` icon) in editor | ✔ iOS | P1 | none (needs Clip-level hidden flag — gap to add) | none | NOT STARTED — model gap |
| Timeline | Clip locking | Per-clip lock (UNVERIFIED on mobile; desktop has it) | ✖ mostly Desktop | P3 | none | none | NOT STARTED |
| Timeline | Timeline end / small markers | "Time" of project = max track end; export range by In/Out markers (Shift+X desktop; mobile has In/Out via toolbar per Help Center) | ✔iOS/Desktop | P1 | `KinoProject.duration` computed | none | PARTIAL — duration query implemented; markers not modeled |
| Timeline | Track cross-readiness | Clips on distinct tracks can overlap freely; overlap rules per kind | ✔ iOS | P0 | `Track.clips(in:)`, start/duration model | none | PARTIAL — model supports; no constraint validation |
| Timeline | Undo/redo | Multi-step undo/redo stack (history) | ✔ iOS | P0 | none | none | NOT STARTED — P0 gap |
| Timeline | Copy/paste clips | Select clip → copy, paste across projects (UNVERIFIED pasting across projects) | ✔ iOS | P1 | none | none | NOT STARTED — UNVERIFIED cross-project |

## 7. Trim / Split / Reorder / Duplicate

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Trim | Edge-drag trim | Drag clip edge; in/out candidates limited to source material; green handles preview | ✔ iOS | P0 | `sourceRange` (start/end on asset) | none | PARTIAL — range model + tests; no gesture |
| Trim | Numeric trim | Trim panel with exact in/out timestamps (desktop); mobile drag-only + ±step (UNVERIFIED exact) | ✔ iOS | P1 | none | none | NOT STARTED |
| Trim | Ripple on trim | Trimming start edge moves clip + ripples timeline (CapCut trims ripple to avoid gaps) | ✔ iOS | P0 | none | none | NOT STARTED |
| Split | Scissors split at playhead | Split tool cuts clip at playhead into two adjacent clips (keeps source ranges) | ✔ iOS | P0 | none | none | NOT STARTED — needs `split` engine op |
| Split | Split at trimmed clip | Splitting preserves trims, speed, effects on both halves | ✔ iOS | P0 | `SpeedSpec`, `effects` per Clip | none | NOT STARTED |
| Reorder | Drag to reorder | Long-press drag clips left/right; adjacent swap reflows timeline; overlay tracks reorder vertically | ✔ iOS | P0 | `Track.clips` array order is data order, not time order | none | PARTIAL — model supports; no op |
| Reorder | Rotate/swap overlay | Change overlay layer order | ✔ iOS | P1 | `upperClips` order param | none | PARTIAL — render-order helper exists |
| Duplicate | Duplicate clip | Duplicate = copy with same transform/fx; appended after original | ✔ iOS | P1 | none | none | NOT STARTED |
| Delete | Delete clip | Delete selected clip(s); ripple closes gap | ✔ iOS | P0 | none | none | NOT STARTED |
| Delete | Delete section (select range in clip) | Range-delete via free select loop (desktop "free select"); mobile base is clip-level × split first | ✖ mostly Desktop | P2 | none | none | NOT STARTED |
| Assemble | Auto-cut / beat-split | "Auto Cut" AI trims & syncs clips to music beats, speech pauses or text prompts; Mobile+Desktop (not Web); requires v12+; Templates→AI Creation; phased rollout | ✔ iOS (mobile+desktop) | P2 | none | none | NOT STARTED |
| Assemble | Speech-pause cutting | Auto Cut "speech pauses" mode; jump-cuts pause segments | ✔ iOS | P2 | none | none | NOT STARTED |
| Assemble | Text-prompt cutting | Auto Cut driven by pasted script/text instructions | ✔ iOS | P2 | none | none | NOT STARTED |
| Assemble | Freeze frame | "Freeze" feature holids a frame (creates still); App Store lists freeze among basic features | ✔ iOS | P2 | none | none | NOT STARTED |

## 8. Transforms & Cropping

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Transform | Position/scale/rotate gestures | Drag to move, corner handles to scale, rotate wheel; all normalized to canvas | ✔ iOS | P0 | `KTransform.center/scale/rotation` | none | PARTIAL — model + hit-test math exists; gestures absent |
| Transform | Flip & mirror | Flip horizontal/vertical toggle in transform panel | ✔ iOS | P1 | `KTransform.flipX/flipY` | none | PARTIAL — fields exist |
| Transform | Opacity | Clip opacity slider 0–100% | ✔ iOS | P1 | `KTransform.opacity` | none | PARTIAL — field exists |
| Transform | Rotate 90° | Quick 90° rotate button | ✔ iOS | P1 | rotation field; no helper | none | PARTIAL |
| Transform | Re-center / reset transform | Reset to full frame (fits canvas) | ✔ iOS | P1 | `KTransform.identity` | none | PARTIAL — identity defined; no flow |
| Crop | Free-form crop | Crop tool with drag corners, aspect presets, 9:16→1:1 etc. | ✔ iOS | P1 | `KTransform.crop: KCropRect` (normalized) | none | PARTIAL — crop rect model + clamp |
| Crop | Fixed-ratio crop lock | Aspect lock handles in crop UI | ✔ iOS | P1 | none | none | NOT STARTED |
| Crop | Canvas ratio vs crop distinct | Canvas fills background beyond crop (blur/solid) | ✔ iOS | P1 | `KFitMath.fillCrop` + KBackground | none | PARTIAL |
| Transform | Blend modes | Overlay blend modes (normal/multiply/screen/…) | ✔iOS/Desktop | P2 | `KBlendMode` 17 modes | none | PARTIAL — enum exists; no UI |
| Transform | Canvas-aware snapping | Snap to edges/center lines while dragging (UNVERIFIED on mobile) | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED |
| Transform | Mask-combined transform | Masks applied inside clip transform space, move together | ✔ iOS | P1 | `Clip.masks` + `KTransform` | none | PARTIAL — model exists |

## 9. Speed, Curves & Slow-mo

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Speed | Constant speed | Speed 0.1x–100x (App Store: "0.1x to 100x"); typical presets 0.25/0.5/1/2/3/4 steps + slider | ✔ iOS | P0 | `SpeedSpec.rate` (Float) | none | PARTIAL — model + `displayDuration` math exist |
| Speed | Audio pitch follow | Slow-mo lowers pitch; "preserve pitch" toggle exists in audio settings | ✔ iOS | P1 | `SpeedSpec.preservePitch`, `AudioSpec.allowPitchCorrection` | none | PARTIAL — fields exist |
| Speed | Reverse | Play clip backward (speed panel "Reverse"); reversed audio behavior toggles | ✔ iOS | P1 | `SpeedSpec.reversed` | none | PARTIAL — field exists; no render op |
| Speed | Speed curve (keyframe curve) | Custom speed curve editor: add points along duration, drag rate, smooth ramp; combined with snapshots 0.5x/2x | ✔ iOS | P1 | `SpeedCurvePoint(position,rate)` + `SpeedMath` integration | none | PARTIAL — curve spec + math (averageRate, rateAt, source/timeline maps) implemented; no editor UI |
| Speed | Velocity ramp presets | Preset ramps (ease-in/out; slow-fast-slow) — UNVERIFIED exact mini-suite | ✔ iOS | P1 | none | none | NOT STARTED |
| Speed | Optical flow smooth slow-mo | "Get smooth slow-motion with optical flow"; PRO-gated in some regions (reviewer note "smooth slow motion became Pro") | ✔ iOS | P1 | none | none | NOT STARTED |
| Speed | Frame freeze in slow-mo | Freeze + speed combo | ✔ iOS | P2 | none | none | NOT STARTED |
| Speed | Time remapping in reverse | Reverse + curve combination support | ✔ iOS | P1 | curve + reversed coexist in model | none | PARTIAL — model allows; semantics unverified |
| Speed | 100x timelapse | Speed up to 100x (timelapse-style) | ✔ iOS | P2 | rate cap exists (model float; curve points clamp 0.02..8 BUT rate itself uncapped — gap) | none | PARTIAL — cap mismatch between constant rate and curve points |
| Speed | Speed frame-rate implications | Changing clip speed changes its timeline duration; project fps unchanged | ✔ iOS | P0 | `SpeedMath.displayDuration` | none | PARTIAL — implemented; no tests for speed (gap: add SpeedMathTests) |

## 10. Stabilization & Anti-shake

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Stabilization | Anti-shake on clip | "The stabilizing feature keeps video footage steady" (App Store); applies to selected clip; slider 1–5 strength (UNVERIFIED exact range) | ✔ iOS | P2 | none | none | NOT STARTED |
| Stabilization | Stabilize export vs preview | Preview approximate; full analysis at export (UNVERIFIED) | ✔ iOS | P2 | none | none | NOT STARTED |
| Stabilization | Cropping tradeoff | Stabilization crops edges; visible zoom on export (UNVERIFIED) | ✔ iOS | P2 | none | none | NOT STARTED |
| Stabilization | Auto-stabilize checkbox | Per-clip toggle only; no project-wide (UNVERIFIED) | ✔ iOS | P2 | none | none | NOT STARTED |

## 11. Audio Editing & Voice-over

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Audio | Clip volume | Volume slider 0–100% (+200% amplify on some clips) | ✔ iOS | P1 | `AudioSpec.volume` 0..2 | none | PARTIAL — field + `gain(progress:)` exists |
| Audio | Mute / unmute | Quick mute button on clip audio | ✔ iOS | P0 | `AudioSpec.muted` | none | PARTIAL |
| Audio | Audio fade in/out | Fade curves (0.5/1/2s presets or drag handles) | ✔ iOS | P1 | `AudioSpec.fadeIn/fadeOut` + gain curve | none | PARTIAL — implemented in `gain()` |
| Audio | Detach audio ("extract audio") | "Extract audio, clips and recordings from videos" — separate audio clip onto its own track; also "Convert audio to" panel | ✔ iOS | P1 | none | none | NOT STARTED |
| Audio | Audio timeline trim | Draggable in/out on audio clips | ✔ iOS | P1 | sourceRange on audio clips | none | PARTIAL — model supports |
| Audio | Audio velocity | Move audio relative to video (audio offset) | ✔ iOS | P1 | `AudioSpec.offset` | none | PARTIAL |
| Audio | Voice-over recording | Record-voiceover button: count-in 3-2-1, mic from camera, waveform appears, splits at stop | ✔ iOS | P1 | none | none | NOT STARTED |
| Audio | Voice-over edit | Trim VO clip; adjust volume separately | ✔ iOS | P1 | `KMediaKind.generated` asset kind | none | PARTIAL — generated kind exists |
| Audio | Audio editing (trim inside audio clip) | "Audio editing" splits audio includes cut within a track; waveform ± (UNVERIFIED split behaviors) | ✔ iOS | P1 | none | none | NOT STARTED |
| Audio | Pitch/Speed audio | Adjust audio speed separate from video; pitch correction toggle | ✔ iOS | P2 | `SpeedSpec` per clip + pitch flags | none | PARTIAL — flags exist |
| Audio | Separate clip audio | Audio track with its own start alignment; sync lock vs video (UNVERIFIED lock) | ✔ iOS | P1 | none | none | NOT STARTED |
| Audio | Better voice / enhance voice | AI voice enhancer for clarity (listed on capcut.com tools; mobile availability UNVERIFIED) | ✔iOS?/Web | P2 | none | none | NOT STARTED — UNVERIFIED mobile availability |
| Audio | Noise reduction | AI reduce background noise (listed web tool; mobile "Reduce Noise" per SOM list — UNVERIFIED platform) | ✔iOS?/Web | P2 | none | none | NOT STARTED |
| Audio | Audio normalization | One-tap normalize loudness (UNVERIFIED mobile) | ✔ iOS | P2 | none | none | NOT STARTED |
| Audio | Ducking/fade under VO | Auto-duck music under voiceover (UNVERIFIED mobile) | ✔ iOS | P2 | none | none | NOT STARTED |
| Audio | Sound-clip library | Tap "Sound" icon: millions music + SFX; search, favorites, "my sound" tab | ✔ iOS | P1 | none | none | NOT STARTED |
| Audio | Remove audio | Clear clip audio leaving silent video (keeps in project) | ✔ iOS | P1 | `AudioSpec.muted` | none | PARTIAL |

## 12. Music & SFX Library, Copyright

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Music | Music search | Search music library by title/artist/trend; categories (pop/EDM/vlog/cinematic) | ✔ iOS | P1 | none | none | NOT STARTED |
| Music | Trending music | Trend carousel synced to TikTok trends; "Trending" list updates | ✔ iOS | P2 | none | none | NOT STARTED |
| Music | Favorites | Heart/star library songs; saved to My Sounds | ✔ iOS | P2 | none | none | NOT STARTED |
| Music | Beat icon | Beat markers: use audio beat-sync when adding music clip ("beat sync" transitions trend) | ✔ iOS | P2 | none | none | NOT STARTED |
| Music | Copyright flags | "Commercial use: TikTok and CapCut" badges on some tracks; some songs monetization-restricted (Material License: library Sounds = personal/non-commercial only) | ✔ iOS | P2 | none | none | NOT STARTED — license model needed |
| Music | Music trim/loop | Music clip trims to project duration; loop segment or single phrase (via tap "loop") | ✔ iOS | P2 | none | none | NOT STARTED |
| Music | Extract audio from video | Select clip → "Extract audio" separates audio as a new clip | ✔ iOS | P1 | none | none | NOT STARTED |
| Music | SFX categories | SFX library with categories (whoosh, beats, vox) + watermark-free SFX | ✔ iOS | P2 | none | none | NOT STARTED |
| Music | Commercial-use UI notice | In-app license notice before export when commercial flag set (UNVERIFIED exact UX) | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED |

## 13. Text (Titles, Styles, Templates)

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Text | Add text | Text tool adds a default title layer on text track above canvas | ✔ iOS | P1 | `Clip(kind: .text, text: TextContent)` | none | PARTIAL — model exists |
| Text | Text styles | Cappuccino-style animation settings: style bundles (font/color/outline/shadows); "Text style preset" with name classification | ✔ iOS | P1 | `TextContent` (fontName, size, weight, color, opacity, alignment, stroke, shadow, background…) | none | PARTIAL — rich text model exists |
| Text | Text templates | Text template catalog — choose template with animation & style; new templates weekly | ✔ iOS | P1 | none | none | NOT STARTED |
| Text | Fonts | Font gallery with many in-app fonts; import local fonts (custom fonts) | ✔ iOS | P1 | `fontName` resolved by app | none | PARTIAL — field exists |
| Text | Font size / style | Font size slider; front style toggle for line wrappings | ✔ iOS | P1 | fontSize normalized; spacing | none | PARTIAL |
| Text | Color / border / background | Color pickers, outlines/borders, background color card, shadow | ✔ iOS | P1 | `colorHex/strokeColorHex/shadowColorHex/backgroundColorHex` | none | PARTIAL |
| Text | Curved text | Text follows arc: curved path parameter | ✔ iOS | P2 | `curvedPath: [KVec2]` | none | PARTIAL — field exists; no UI |
| Text | Uppercase / align | Auto-uppercase, align left/center/right | ✔ iOS | P1 | `uppercase`, `alignment` | none | PARTIAL |
| Text | Letter/line spacing | Character spacing & line spacing sliders | ✔ iOS | P1 | `letterSpacing`, `lineSpacing` | none | PARTIAL |
| Text | Animations for text | Text-in/text-out animation library (fade/typewriter/wiggle/style); loop text animation | ✔ iOS | P1 | `AnimationRef(phase: .entrance/.exit/.looped)` | none | PARTIAL — ref exists; preset catalog absent |
| Text | Text duration & move | Drag text on timeline to move, trim handles for duration | ✔ iOS | P1 | clip start/duration per text clip | none | PARTIAL |
| Text | Edit in viewport | Tap text in preview to edit inline; double-tap to re-edit | ✔ iOS | P1 | none | none | NOT STARTED |
| Text | Save style | Save created style as custom text style | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED |
| Text | Preset one-click edit | Styles applied one-click via double-tap text | ✔ iOS | P1 | none | none | NOT STARTED |

## 14. Auto Captions / Subtitles

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Captions | Auto captions engine | Automatic speech recognition; single click generate for entire timeline | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Language selection | 20+ languages incl. dialect selection before generating | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Accuracy & overlap | High accuracy on casual/fast speech; adjusts for accents/dialects | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Caption tracks | Subtitles added to timeline as a text track; move as a block, trim as one, split segments | ✔ iOS | P2 | `Track(kind: .text)` | none | PARTIAL — text track exists; caption grouping absent |
| Captions | Style customization | Caption template styles; caption font/size/color/position; animations per segment | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Caption templates | CapCut caption templates gallery (Karaoke etc. in templates) | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Word highlight / karaoke | Animated word-by-word highlight styles | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Manual edits | Tap caption, edit wording; refresh/auto-fix; "Click to edit" | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | SRT import (mobile) | SRT import from Files replaces/generated captions (help article covers mobile; Web SRT upload verified) | ✔iOS/Web | P2 | none | none | NOT STARTED — UNVERIFIED mobile SRT extent |
| Captions | Export captions file | Export SRT separate from video (desktop/web verified; mobile UNVERIFIED) | ✔iOS/Web | P2 | none | none | NOT STARTED — UNVERIFIED |
| Captions | Auto-caption detection per clip | Generate captions on selected clip or all (segment-level) | ✔ iOS | P2 | none | none | NOT STARTED |
| Captions | Caption merge text | Two captions merge with combined text (desktop verbatim; mobile tap merge) | ✔ iOS | P2 | none | none | NOT STARTED |

## 15. Text-to-Speech & AI Voice

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| TTS | Add TTS to text | Select text → Text-to-speech; generates a new audio clip from text content | ✔ iOS | P2 | `KMediaKind.generated` | none | PARTIAL — kind exists |
| TTS | Voice selection | Many human-sounding voices & characters (male/female/celebrity-like); language-aware list | ✔ iOS | P2 | none | none | NOT STARTED |
| TTS | Multi-language voices | Voices per language (EN/ES/JP/KR/…); App Store: "multiple languages and voices" | ✔ iOS | P2 | none | none | NOT STARTED |
| TTS | Custom voice / clone voice | "Custom voices" area on capcut.com; mobile clone-voice feature UNVERIFIED | ✔iOS?/Web | P2 | none | none | NOT STARTED — UNVERIFIED |
| TTS | Voice speed/pitch | Adjust TTS clip speed en separately (clip speed normally 0.5–2x) | ✔ iOS | P2 | `SpeedSpec` | none | PARTIAL |
| TTS | Timed text alignment | TTS positions audio at text clip's start; movement aligns text | ✔ iOS | P2 | none | none | NOT STARTED |
| TTS | Regeneration | Replace generated voice clip by re-running TTS with different voice | ✔ iOS | P2 | none | none | NOT STARTED |
| TTS | AI voiceover script | Longer AI voiceover from script text w/ model voices (help article Add Voiceover & Captions to Ad Videos) | ✔iOS/Web | P2 | none | none | NOT STARTED |

## 16. Stickers & Graphics

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Stickers | Sticker library | Massive sticker library (emoji style, trending, effects stickers, GIF-like) | ✔ iOS | P2 | `StickerContent(atlasID)` | none | PARTIAL — reference model exists |
| Stickers | Text stickers | Text sticker collections (letters stickers) with string parameter | ✔ iOS | P2 | `StickerContent.string` | none | PARTIAL |
| Stickers | Sticker behavior/animation | Some stickers emit animation effects (swipe, erasing) — "sticker behaviors" | ✔ iOS | P2 | none | none | NOT STARTED |
| Stickers | Sticker position/scale/rotate | Drag, pinch scale, rotate like clips | ✔ iOS | P1 | KTransform on clip | none | PARTIAL |
| Stickers | Tint/color overlay | Color overlay tint on sticker | ✔ iOS | P2 | `tintHex` | none | PARTIAL |
| Stickers | Search | Sticker search box | ✔ iOS | P2 | none | none | NOT STARTED |
| Stickers | Trending/fresh sets | Set updated daily/recent; new sticker packs badges | ✔ iOS | P3 | none | none | NOT STARTED |

## 17. Filters & Adjustments

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Filters | Basic filters | Filter strip per clip; swipe presets; "None" default | ✔ iOS | P1 | `FilterPreset.catalogue` (11 presets) | none | PARTIAL — preset catalog + adjustments exist |
| Filters | Weekly trend updates | "Diverse filters updated weekly with latest trends" | ✔ iOS | P2 | none | none | NOT STARTED — catalog refresh infra |
| Filters | Style categories | Categories like Classic/Cinematic/Film matched per video | ✔ iOS | P1 | catalog families (`natura/video/portrait/scene`) | none | PARTIAL |
| Filters | Filter strength | Filter strength slider 0–100% per clip | ✔ iOS | P1 | `ColorAdjust.mixed(_:_:)` interpolation | none | PARTIAL |
| Adjustments | Exposure | -:0–2 EV range | ✔ iOS | P1 | `exposure` | none | PARTIAL |
| Adjustments | Brightness / contrast | Sliders often paired in toolbar | ✔ iOS | P1 | `brightness`, `contrast` | none | PARTIAL |
| Adjustments | Highlights/shadows | Tone curve splits | ✔ iOS | P1 | `highlights`, `shadows` | none | PARTIAL |
| Adjustments | Saturation / vibrance | Color intensity push | ✔ iOS | P1 | `saturation`, `vibrance` | none | PARTIAL |
| Adjustments | Temperature / tint | White balance adjustment | ✔ iOS | P1 | `temperature`, `tint` | none | PARTIAL |
| Adjustments | Fade / grain / sharpen | Film-fade, grain, sharpening knobs | ✔ iOS | P1 | `fade`, `grain`, `sharpen` | none | PARTIAL |
| Adjustments | Vignette | Vignette amount in adjustments | ✔ iOS | P1 | `vignette` | none | PARTIAL |
| Adjustments | HSL / curves | Advanced HSL & curve tool; per-channel color curves (UNVERIFIED mobile depth; desktop/web full) | ✖ richest on Desktop | P1 | `hueShift` only | none | PARTIAL — simplified HSL only |
| Adjustments | Auto adjust | AI auto-adjust photo/video color (auto-frame + auto-adjust) | ✔ iOS | P2 | none | none | NOT STARTED |
| Adjustments | Copy adjustments to clip | Copy filter/adjustments to multiple clips (UNVERIFIED mobile; desktop "copy to" exists) | ✔iOS/Desktop | P1 | none | none | NOT STARTED |
| Adjustments | Color match | Match color between clips (web "AI Color Matcher"; mobile UNVERIFIED) | ✔iOS?/Web | P2 | `ColorAdjust.mixed` | none | PARTIAL — math exists; feature absent |

## 18. Effects (library + families)

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Effects | Effect library | Hundreds of effects by category (App Store: Glitch, Blur, 3D); new/trending badges | ✔ iOS | P1 | `EffectSpec.catalogue` (Blur/Light/Distort/Color/Grain/Vignette/Edge/Glitch/Retro families) | none | PARTIAL — catalogue defined; renderers absent |
| Effects | Effect families — Glitch | RGB split, slice/line glitch, static noise, jitter | ✔ iOS | P1 | `glitch.*` specs (RGB Split, Slice Glitch, Static) | none | PARTIAL |
| Effects | Effect families — Retro | VHS, CRT, 90s-style retro effects (App Store trend list mentions retro effects; retro aesthetics trending) | ✔ iOS | P1 | `retro.vhs`, `retro.crt` | none | PARTIAL |
| Effects | Effect families — Blur | Gaussian/radial/motion blur & focus zoom-pull | ✔ iOS | P1 | `blur.*` (4 specs) | none | PARTIAL |
| Effects | Effect families — 3D-ish | 3D effects & 3D zoom/IMAX-cinematic (App Store/trends mention 3D) | ✔ iOS | P1 | none (gap: no 3D transform model) | none | NOT STARTED |
| Effects | Effect families — Pixel, distort, colors, arts, stylistic | Pixelate, twist, smears, chromatic aberration, pixel art, arts conversion, X-ray, old film | ✔ iOS | P1 | `distort.*`, `color.*`, `edge.*` specs | none | PARTIAL |
| Effects | Effect families — Motion | Moving-lines, noise, light-leak, letterbox, camera-move (legacy categories) | ✔ iOS | P1 | `light.*`, `grain.*` | none | PARTIAL |
| Effects | Per-clip effect stack | Apply multiple effects to one clip; each with strength | ✔ iOS | P1 | `Clip.effects: [EffectInstance]` ordered stack; `strength` | none | PARTIAL |
| Effects | Effect parameter controls | Effect-specific params (amount, radius, angle, speed…) | ✔ iOS | P2 | `ParamSpec` metadata | none | PARTIAL |
| Effects | Effect time range | Effects on clip with start/end markers (some effects have time-len) | ✔ iOS | P2 | none (effect has no in/out range — model gap) | none | NOT STARTED |
| Effects | Effect animation | Effects can be keyed (animated parameters) | ✔ iOS | P2 | `animatable` flag + KeyframeStore | none | PARTIAL |
| Effects | Saved effects | "Save/appear in collections" favorites | ✔ iOS | P2 | none | none | NOT STARTED |

## 19. Transitions

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Transitions | Where to apply | Between adjacent clips (also to whole project gap with templates); selected clip shows small box icon | ✔ iOS | P1 | `KClipSeries.transition` placeholder on clip boundary | none | PARTIAL — placeholder only |
| Transitions | Dissolve / fade family | Dissolve, fade to black, white, pan, slide, blur | ✔ iOS | P1 | none | none | NOT STARTED |
| Transitions | Zoom family | App Store: "zoom in/out effects"; zoom transitions: Zoom, Zoom-in-out, Quick zoom | ✔ iOS | P1 | `distort.zoom` effect spec exists (as effect) | none | PARTIAL — as effect, not transition |
| Transitions | Slide/swipe family | Slide up/down/left/right incl. hand-swipe styles (trend: "Smooth Swipe & Motion") | ✔ iOS | P1 | none | none | NOT STARTED |
| Transitions | 3D family | 3D spin / cube / classic 3D transitions (listed in CapCut trend + App Store "3D") | ✔ iOS | P1 | none | none | NOT STARTED |
| Transitions | Lights family | Flash/light transitions (LED, light leaks) | ✔ iOS | P2 | `light.*` effect specs | none | PARTIAL — effect analog |
| Transitions | Chaos / glitch / rich | Trending: Glitch & Digital Distortion (RGB split, flicker, data-mosh) | ✔ iOS | P1 | `glitch.*` specs | none | PARTIAL |
| Transitions | Physical family | Physical dynamics; "chaotic" groups with particle-based motion (UNVERIFIED exact family names 2026) | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED names |
| Transitions | Velocity speed-ramp transitions | Speed ramp at cut (trend #1): slow-mo → abrupt speed + beat | ✔ iOS | P1 | SpeedSpec curves | none | PARTIAL — speed model exists; ramp-at-transition UI absent |
| Transitions | Beat-sync transitions | Auto-sync cut to music beat (AI audio analysis; templates have beat) | ✔ iOS | P2 | none | none | NOT STARTED |
| Transitions | AI smart transitions | AI generates transitions from clip content (2026 trend; rollout phase) | ✔ iOS | P2 | none | none | NOT STARTED — rollout UNVERIFIED |
| Transitions | Before/after & transformation | Style: quick cut + mask/blur transformation | ✔ iOS | P2 | masks model present | none | PARTIAL — masks model as building block |
| Transitions | Transition duration | Transition length editable (duration slider); or 0.5s | ✔ iOS | P1 | none | none | NOT STARTED |
| Transitions | Apply-to-all/randomize | Randomize or apply same to all cuts (desktop verified; mobile UNVERIFIED) | ✔iOS/Desktop | P2 | none | none | NOT STARTED |
| Transitions | Transition-free export | Export always applies transition; no re-render issues | ✔ iOS | P1 | none | none | NOT STARTED |

## 20. Animations (entrance/exit/loop)

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Animations | Entrance animations | Clip animate-in panel: fade, zoom, slide, bounce, swing (groups like Basic/Cool) | ✔ iOS | P1 | `AnimationRef(phase: .entrance, presetID, duration)` | none | PARTIAL — phase+duration modeled; no presets |
| Animations | Exit animations | Animate-out presets (basic/3d/zoom groups) | ✔ iOS | P1 | `AnimationRef(phase: .exit)` | none | PARTIAL |
| Animations | Loop/looping animations | Combo loop animations for endless (bounce/rotate/woobly) | ✔ iOS | P1 | `AnimationRef(phase: .looped)` | none | PARTIAL |
| Animations | Animation duration | Entrance/exit duration adjustable (equals or shorter than clip) | ✔ iOS | P1 | `AnimationRef.duration` | none | PARTIAL |
| Animations | Zoom in/out clip animate | One-tap zoom-in/zoom-out animate presets (App Store explicitly) | ✔ iOS | P1 | model supports via AnimationRef | none | PARTIAL |
| Animations | Text animation styles + loop | Text-specific animation set (typewriter, stutter, turn) | ✔ iOS | P1 | same ref slots | none | PARTIAL |
| Animations | Auto-animated stickers | Stickers come with embedded animation | ✔ iOS | P2 | none | none | NOT STARTED |
| Animations | Animation preview | Playhead preview loop with selected animation | ✔ iOS | P1 | none | none | NOT STARTED |

## 21. Keyframes

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Keyframes | Keyframe availability | App Store: "Keyframe video animation is available for all settings" | ✔ iOS | P1 | `KeyframeStore` per clip | none | PARTIAL — store + channels modeled; no tests |
| Keyframes | Animate position | Diamond key on Transform position | ✔ iOS | P1 | `KChannel(property:)` float channels (x/y) | none | PARTIAL — implementation supports; no tests |
| Keyframes | Animate scale / rotation / opacity | Property keys; easing between keys | ✔ iOS | P1 | channels for scale/rotation/opacity; `KCurveSpec` easing | none | PARTIAL |
| Keyframes | Animate color/effects | Effect parameter + color keys (capcut.com keyframe-animation: "shape, opacity, and color") | ✔ iOS | P1 | EffectInstance values can key via store | none | PARTIAL |
| Keyframes | Animate speed (via curve) | Speed is NOT keyframes; speed curve tool separate (verdict: curve+keyframe combo for elasticity) | ✔ iOS | P1 | SpeedCurvePoint model (separate) | none | PARTIAL |
| Keyframes | Easing presets | Linear/ease-in/out/etc. per key | ✔ iOS | P1 | KCurveKind linear/easeIn/easeOut/easeInOut/cubicBezier/hold | none | PARTIAL — eased() math written; no tests |
| Keyframes | Keyframe editing UI | Diamond icon toggle; move/delete key; tap key to change value | ✔ iOS | P1 | upsert/remove/nearestKey ops | none | PARTIAL — ops exist; no UI |
| Keyframes | Keyframe interpolation preview | Live curve chart (desktop); mobile shows playhead-diamond | ✔ iOS | P1 | none | none | NOT STARTED |
| Keyframes | Keyframes on filters+audio | Filters, audio settings (Fade/volume/detach signal) also keyable | ✔ iOS | P1 | channels map generic | none | PARTIAL |

## 22. Masks

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Masks | Mask library | Mask tool on clip; types: Linear, Circle, Rect, Split, Brush, Star, Freeform/Featured, Custom (shape) | ✔ iOS | P1 | `KMaskKind` rectangle/circle/linear/split/freeform/custom | none | PARTIAL — kinds modeled; no shader |
| Masks | Mask area adjustments | Drag mask center; resize via handles; rotate round handle | ✔ iOS | P1 | center/size/rotation fields | none | PARTIAL |
| Masks | Feather control | Soft edge slider 0–100% | ✔ iOS | P1 | `feather` | none | PARTIAL |
| Masks | Inverted mask | Invert toggle (show outside mask) | ✔ iOS | P1 | `inverted` | none | PARTIAL |
| Masks | Multiple masks | Stack ≥2 masks per clip; modes per mask (Alpha, Subtract, Add, Intersect — desktop dominates) | ✖ mostly Desktop | P1 | `Clip.masks: [MaskSpec]` | none | PARTIAL — array exists; union semantics absent |
| Masks | Keyframed masks | Animate mask (keyframes on mask params) | ✔ iOS | P2 | KeyframeStore generic | none | PARTIAL |
| Masks | Select mask filter/effect | Masks apply to effects/filters too (e.g., apply filter in mask) | ✔ iOS | P2 | mask lives at clip level | none | PARTIAL |
| Masks | Animated-sticker mask separation | Mask removal of sticker requires trimming (UNVERIFIED) | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED |

## 23. Chroma Key & Greenery Keys

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Chroma | Chroma key on clip | Select clip → "Chroma key" (palette icon) | ✔ iOS | P2 | `ChromaKeySpec` on clip? (currently separate struct; needs wiring to Clip) | none | PARTIAL — spec exists; not attached to Clip model |
| Chroma | Color picker | Pipette sample any point on video to choose key color | ✔ iOS | P2 | `KRGB` + colorHex constructors | none | PARTIAL |
| Chroma | Similarity/tolerance | "Similarity" slider widens matched color range | ✔ iOS | P2 | `similarity` | none | PARTIAL |
| Chroma | Smoothness | "Smoothness" cleans edges | ✔ iOS | P2 | `smoothness` | none | PARTIAL |
| Chroma | Spill suppression | "Spill" removes green reflections | ✔ iOS | P2 | `spill` | none | PARTIAL |
| Chroma | Edge feather | Feather edges of keyed cutout | ✔ iOS | P2 | `edgeFeather` | none | PARTIAL |
| Chroma | Invert key | Copy keying to flip (UNVERIFIED on mobile) | ✔ iOS | P2 | none | none | NOT STARTED |
| Chroma | Keying + cutout combo | Use cutout to make own background + chroma | ✔ iOS | P2 | none | none | NOT STARTED |

## 24. Overlays, PiP & Compositing

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Overlay | Overlay layer | Add image/video overlay above main; scalable/draggable in preview | ✔ iOS | P1 | `KTrackKind.overlay` | none | PARTIAL |
| Overlay | Picture-in-picture | PiP video on top of main video; clip audio stays? (can mute) | ✔ iOS | P1 | same overlay mechanism | none | PARTIAL |
| Overlay | Overlay camera / greenscreen | Greenscreen overlay = chroma key source | ✔ iOS | P1 | chroma spec | none | PARTIAL |
| Overlay | Overlay image | Photo overlay with opacity; white background removal | ✔ iOS | P1 | `KMediaKind.image` | none | PARTIAL |
| Overlay | Blend modes | Overlay blend (compare normal/overlap; blend overlay cover) | ✔iOS/Desktop | P2 | KBlendMode | none | PARTIAL |
| Overlay | Toggle visibility | Eye icon on overlay clip | ✔ iOS | P1 | none (Clip-level hide gap) | none | NOT STARTED |
| Overlay | Smart overlay animation | Some overlay clips have entry animations | ✔ iOS | P1 | AnimationRef | none | PARTIAL |

## 25. Background Removal / Cutout

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Cutout | Auto background removal | "Background removal: automatically remove backgrounds" (App Store) — tap clip → cutout; AI models running device/cloud hybrid | ✔ iOS | P2 | none | none | NOT STARTED |
| Cutout | Cutout refine | Refine edges (erase/restore strokes) white-mask background | ✔ iOS | P2 | none | none | NOT STARTED |
| Cutout | Cutout + all effects | Cutout placeholder with outline; overlay with normal (outline) | ✔ iOS | P2 | none | none | NOT STARTED |
| Cutout | Cutout white background | Handy white background; export PNG image | ✔ iOS | P2 | none | none | NOT STARTED |
| Cutout | Smart cutout of clip region | Select region → background remove for key sections | ✔ iOS | P2 | none | none | NOT STARTED |
| Cutout | Photo cutout separate | Photo cutout available as separate tool | ✔ iOS | P2 | none | none | NOT STARTED |

## 26. Auto Reframe, Smart Crop & Tracking

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Auto reframe | Auto reframe to aspect | AI reframes 16:9 to 9:16 following subjects (auto-reframe); App Store/help references auto frame | ✔ iOS | P2 | none (crop math exists: KFitMath/KCropRect) | none | PARTIAL — crop math; no reframe AI |
| Auto reframe | Manual crop override | Tweak reframed pans with keyframes | ✔ iOS | P2 | KeyframeStore | none | PARTIAL |
| Smart crop | Smart crop assistant | Detects subjects and crops tighter (UNVERIFIED exact naming mobile) | ✔ iOS | P2 | none | none | NOT STARTED — UNVERIFIED |
| Tracking | Motion tracking | Track subject; Attach text/stickers follow subject (motion tracking listed in App Store) | ✔ iOS | P2 | none | none | NOT STARTED |
| Tracking | Track to add effects | Effects crop to moving region (AI movement tracking web tool; mobile UNVERIFIED) | ✔iOS?/Web | P2 | none | none | NOT STARTED |

## 27. 3D Zoom / Motion / IMAX-style

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| 3D | 3D zoom effect | "3D" listed with trending effects (App Store); 3D zoom photos (from static frame) via zoom keyframes; store motion-cam IMAX-style — desktop/web has "3D zoom" templates; mobile extent UNVERIFIED | ✔iOS/Desktop | P1 | none (transform+depth unsupported) | none | NOT STARTED — UNVERIFIED mobile scope |
| 3D | 3D motion animation | 3D motion pan on photos (perspective) — UNVERIFIED mobile | ✔iOS/Web | P2 | none | none | NOT STARTED |
| Motion | Ken Burns-style | Zoom in shot presets (a part of "motion" transitions) | ✔ iOS | P1 | transform keyframes | none | PARTIAL |

## 28. AI Features (current shipping set)

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| AI | AI captions | Auto captions (ASR) + edit | ✔ iOS | P2 | none | none | NOT STARTED |
| AI | AI voiceover | TTS; AI script voiceover; "Custom voices" | ✔ iOS | P2 | none | none | NOT STARTED |
| AI | AI cutout | One-click background/people removal | ✔ iOS | P2 | none | none | NOT STARTED |
| AI | AI auto-cut (Auto Cut) | Auto Cut templates: AI trimming to beats/speech/text; Mobile+Desktop; v12+; rollout | ✔ iOS | P2 | none | none | NOT STARTED |
| AI | AI reframe | Auto-reframe (see §26) | ✔ iOS | P3 | none | none | NOT STARTED |
| AI | AI template editing | Edit-in-template: replace placeholder clips with own media; keep effects/transitions built-in | ✔ iOS | P3 | none | none | NOT STARTED |
| AI | AI writer / script | AI script writer / hook generator for talking-heads (available in some AI edit flows UNVERIFIED mobile) | ✔iOS?/Web | P3 | none | none | NOT STARTED — UNVERIFIED |
| AI | AI avatar | Avatar creator (Web/Desktop Video Studio; mobile UNVERIFIED) | ✖ mostly Web | P3 | none | none | NOT STARTED — Web-centric |
| AI | AI dubbing | AI video translation/dubbing (web tool; mobile UNVERIFIED) | ✔iOS?/Web | P3 | none | none | NOT STARTED |
| AI | AI image/video generation | Gen tools (Dreamina, Seedance, Nano Banana / text-to-video) — companions, not core mobile editor | ✔iOS? | P3 | none | none | NOT STARTED — companion apps |
| AI | AI skin/beauty tools | Beauty/retouch for photos (Hypic companion) | ✖ companion apps | P3 | none | none | NOT STARTED — out of scope |
| AI | AI noise reduction | See §11 | ✔ iOS | P2 | none | none | NOT STARTED |
| AI | AI smart transitions | See §19 | ✔ iOS | P3 | none | none | NOT STARTED |
| AI | AI chat/command edit | Pippit-style creative agent (web ecosystem; mobile UNVERIFIED) | ✖ Web | P3 | none | none | NOT STARTED |
| AI | AI stickers/images for canvas | AI-generated sticker packs (UNVERIFIED mobile) | ✔iOS? | P3 | none | none | NOT STARTED |
| AI | AI text remover | Remove text/objects from clips (web tools; mobile UNVERIFIED) | ✔iOS?/Web | P3 | none | none | NOT STARTED |

## 29. Templates & Community Feed

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Templates | Template home feed | Templates tab on home: trending, viral, creator-made; preview with music | ✔ iOS | P2 | none | none | NOT STARTED |
| Templates | Use template | "Use template" button → choose media → auto-builds timeline | ✔ iOS | P2 | none | none | NOT STARTED |
| Templates | Replace clips | In template edit: replacements added, effects stay anchored | ✔ iOS | P2 | none | none | NOT STARTED |
| Templates | Template search | Template search on Mobile + Web (NOT Desktop — Help Center Jan 2026) | ✔ iOS | P3 | none | none | NOT STARTED |
| Templates | Creator profiles/view templates | Public creator pages with template feeds (UNVERIFIED privacy; no private account) | ✔ iOS | P3 | none | none | NOT STARTED |
| Templates | My templates | Downloaded templates saved offline; duplicate of project as template | ✔ iOS | P2 | none | none | NOT STARTED |
| Templates | Trending template (fits trend hashtag) | Trending labels + # for each template | ✔ iOS | P3 | none | none | NOT STARTED |
| Templates | Template content / music copyright | Template music usage restricted (watermark/end-clip issue per Help Center); template end-clip watermark detection | ✔ iOS | P2 | none | none | NOT STARTED |
| Templates | AI Creation hub | Templates → "AI Creation" (Auto Cut/Beat Cut/Smart Edit) landing | ✔ iOS | P2 | none | none | NOT STARTED |
| Templates | Template edit in timeline | Templates open in the full editor (multi-track re-edit) | ✔ iOS | P2 | none | none | NOT STARTED |

## 30. Export

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Export | Resolution ladder | 720p / 1080p / 2K / 4K selectable (App Store: custom resolution; 4K 60fps verified) | ✔ iOS | P0 | `CanvasConfig.renderSize` (1080 base) | none | PARTIAL — model; no encoder |
| Export | Frame rate options | 24/25/30/60 fps at export (4K 60fps official) | ✔ iOS | P0 | `CanvasConfig.fps` Rational | ✔ fps math tests | PARTIAL — fps model+tests |
| Export | Bitrate | Quality/bitrate selector (Low/Recommended/High) UNVERIFIED exact ladder | ✔ iOS | P1 | none | none | NOT STARTED — UNVERIFIED ladder |
| Export | Codec | MP4 H.264 encoded; H.265/HEVC option on Pro (UNVERIFIED) | ✔ iOS | P1 | none | none | NOT STARTED — UNVERIFIED |
| Export | Smart HDR | "smart HDR" export for HDR footage (App Store verified) | ✔ iOS | P1 | none | none | NOT STARTED |
| Export | Export range (In/Out) | In/Out markers restrict exported range (mobile + desktop per Help Center; desktop has I/O keyboard, Shift+X) | ✔ iOS | P1 | none | none | NOT STARTED |
| Export | Save to Photos | Export to camera roll directly (default) | ✔ iOS | P0 | none | none | NOT STARTED |
| Export | Save cover/frame | Renaming + cover selection at export | ✔ iOS | P1 | none | none | NOT STARTED |
| Export | Watermark policy | No inherent CapCut export watermark; template end-clip watermark removable by deleting end clip (Help Center) | ✔ iOS | P1 | none | none | NOT STARTED |
| Export | Cloud upload (CapCut cloud) | Export to cloud drafts/storage (Pro) for cross-device continuation; UNVERIFIED mobile scope | ✔iOS? | P2 | none | none | NOT STARTED — UNVERIFIED |
| Export | Upload to CapCut sharing page | Publish to CapCut community feed — mark public/private toggle (UNVERIFIED; no private account exists) | ✔ iOS | P3 | none | none | NOT STARTED |
| Export | Background export | Export continues in background with notification | ✔ iOS | P1 | none | none | NOT STARTED |
| Export | Export ad/noise | Estimating time + high-load warning (PRO) | ✔ iOS | P1 | none | none | NOT STARTED |
| Export | Frame loss/correctness | Exported video must match preview exactly (frame-accurate pipeline; export "optimal 1080p" WFT) | ✔ iOS | P0 | SpeedMath guarantees preview≡export mapping (comment in code) | none | PARTIAL — design invariant; verify |

## 31. Sharing & Social Feeds

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Sharing | Share sheet | Share to TikTok, YouTube, Instagram, WhatsApp, Facebook (App Store reads); system share sheet | ✔ iOS | P1 | none | none | NOT STARTED |
| Sharing | Direct platform posting | One-tap post; TikTok link stored; trimming preview with song | ✔ iOS | P1 | none | none | NOT STARTED |
| Sharing | Save draft per platform | "Saved drafts" to upload later | ✔ iOS | P1 | none | none | NOT STARTED |
| Sharing | Companion share within app | Share project with song/branded overlay to group | ✔ iOS | P2 | none | none | NOT STARTED |
| Sharing | TikTok-specific link flow | "TikTok notification after upload" (TikTok-CapCut deep link) — UNVERIFIED 2026 | ✔ iOS | P3 | none | none | NOT STARTED |
| Sharing | Export filename | Rename file before sharing | ✔ iOS | P2 | `meta.name` | none | PARTIAL |
| Sharing | Community/Discover feed | Discover tab: other creators' videos via personal/creator space (Help Center "videos you can see are templates") | ✔ iOS | P3 | none | none | NOT STARTED |
| Sharing | Share templates | Publish own project as template (creator program) | ✔ iOS | P3 | none | none | NOT STARTED |

## 32. Settings, Storage & Misc

| Category | Feature | Expected behavior (as observed in CapCut iOS) | iOS? | Priority | Implementation (in THIS app) | Tests | Status |
|---|---|---|---|---|---|---|---|
| Settings | Language | English + 20 more locales | ✔ iOS | P2 | none | none | NOT STARTED |
| Settings | Dark/light theme | Editor dark; OS-adaptive theme | ✔ iOS | P1 | `Theme.swift` exists in app target | none | NOT STARTED — theme scaffolding exists |
| Settings | Storage check | Storage usage page; clear cache | ✔ iOS | P2 | none | none | NOT STARTED |
| Settings | Push notifications | Templates/news/project notifications | ✔ iOS | P3 | none | none | NOT STARTED |
| Settings | Version/About | Version string & disclaimer; check updates | ✔ iOS | P2 | `schemaVersion` | none | PARTIAL |
| Settings | Notifications/Terms/Privacy in-app pages | In-app Privacy choice center (Your Privacy Choices) | ✔ iOS | P3 | none | none | NOT STARTED |
| Settings | Restore purchase / Trial | Restore subscription (StoreKit) | ✔ iOS | P3 | none | none | NOT STARTED |
| Settings | Free/Pro gating surfaces | Feature icons with diamond badge for Pro content | ✔ iOS | P2 | none | none | NOT STARTED |
| Settings | Localization of time math | Time values in editor persisted as milliseconds (KTime ns, not float) | ✔ iOS | P0 | KTime (ns int) | ✔ KTimeTests | PARTIAL — exact, cross-platform deterministic |
| Settings | Crash/analytics | Diagnostics + crash analytics opt-out (App Store privacy) | ✔ iOS | P3 | none | none | NOT STARTED |

---

## Notes on Engine Status (research date)

- **Verified in repo (KinoEngine, Swift package):** `KTime`/`Rational`/`TimeRange` (frame-accurate ns time, NTSC-safe fps math, exact mul-div) with `KinoEngineTests/KTimeTests.swift` (10+ tests; build artifacts exist at `.build/x86_64-unknown-linux-gnu/debug` — **swift not installed in this env**, tests not re-run today).
- **Data structures only (no renderer/UI):** `KinoProject` (meta/assets/tracks/clips, JSON serialization + migration), `Clip`+`Track` (kinds: main/overlay/audio/text/sticker), `SpeedSpec`+`SpeedMath` (curve-integrated source↔timeline mapping), `AudioSpec` (volume/mute/fade/offset/pitch), `TextContent` (full typography), `StickerContent`, `EffectSpec`/`EffectInstance` catalogue (Blur/Light/Distort/Color/Grain/Vignette/Edge/Glitch/Retro), `FilterPreset` + `ColorAdjust`, `MaskSpec` (6 kinds), `ChromaKeySpec` (key color/similarity/smoothness/spill/feather), `KeyframeStore` (channels, easing curves), `KTransform` (center/scale/rotation/opacity/flip/crop/blend 17 modes), `KCanvasPreset` (9 aspects), `KFitMath`.
- **Known model gaps found in review:** no per-clip visibility flag, no effect in/out time ranges, no transition instance model (placeholder only), `ChromaKeySpec` not attached to `Clip`, constant speed `rate` uncapped while curve points clamp 0.02–8, no undo/redo, no markers model.

*End of matrix.*
