//
//  PersistedModels.swift
//  meter-gnome
//
//  SwiftData @Model classes that mirror the MetronomeCore value types.
//  Each @Model has a conversion to/from its value-type counterpart so the
//  rest of the app (engine, view model, views) keeps working with the
//  pure-data types and only the store layer touches SwiftData.
//
//  Storage strategy: primitive fields (String, Int, Double, Bool, UUID)
//  are stored natively; complex Codable types (AccentPattern, SongDuration,
//  SetlistAdvanceMode, [Song]) are JSON-encoded into Data columns. Native
//  SwiftData support for nested Codable is uneven in this Xcode; the Data
//  fallback is reliable and fast at our data size.
//

import Foundation
import SwiftData
import MetronomeCore

// MARK: - Settings (singleton)

@Model
final class PersistedEngineSettings {
    var masterVolume: Double
    var latencyOffsetSeconds: Double
    var mixWithOthers: Bool
    var countInRaw: Int
    var bpmPrecisionMode: Bool
    var autoResumeAfterInterruption: Bool
    /// `ClickSound.rawValue`. Stored as String for SwiftData compatibility
    /// and to make values stable across enum case reorderings.
    var clickSoundRaw: String
    /// Whether MIDI Clock output is enabled (spec §12.2).
    var midiClockEnabled: Bool
    /// Whether MIDI Clock slave mode is enabled (spec §12.2).
    var midiClockReceiveEnabled: Bool
    /// Name of the MIDI source the receiver listens to (spec §12.2
    /// source picker). nil = all sources (legacy behavior). Optional
    /// String — SwiftData lightweight migration covers the new column
    /// with a nil default for existing rows.
    var midiReceiveSourceName: String? = nil
    /// `VoiceCountMode.rawValue`. Spec §5.
    var voiceCountModeRaw: String
    /// Random-mute percentage 0–50 (spec §6.4). 0 = off. New in v2 of the
    /// schema; old rows decode as 0 via SwiftData's nullable-column
    /// migration with a default value.
    var randomMutePercentage: Int = 0
    /// `HapticMode.rawValue` (spec §9). Defaults to `.off` so existing
    /// users don't suddenly start feeling buzz on every beat.
    var hapticModeRaw: String = HapticMode.off.rawValue
    /// Per-accent haptic intensity (spec §9). Stored as 4 scalar fields
    /// rather than an embedded Codable so SwiftData's nullable-column
    /// migration covers each one individually. Mute always 0 — no field.
    var hapticIntensitySoft: Double = 0.3
    var hapticIntensityNormal: Double = 0.6
    var hapticIntensityLoud: Double = 0.85
    var hapticIntensityAccent: Double = 1.0
    /// Default `true` per EngineSettings — preserves the in-spec default
    /// for existing rows that pre-date v0.8.3.
    var keepScreenAwakeDuringPlayback: Bool = true
    /// Default `false` (spec §10.2) — auto-start on app launch is
    /// opt-in to avoid surprise audio when users open the app.
    var startOnLaunch: Bool = false
    /// Daily practice goal in minutes (spec §11). 0 = no goal.
    var dailyPracticeGoalMinutes: Int = 0
    /// Weekly practice goal in minutes (spec §11). 0 = no goal. New
    /// column in v0.23.0; SwiftData lightweight migration adds it
    /// with default 0 for existing rows.
    var weeklyPracticeGoalMinutes: Int = 0
    /// Monthly practice goal in minutes (spec §11). 0 = no goal.
    var monthlyPracticeGoalMinutes: Int = 0
    /// JSON-encoded `[Subdivision: SubdivisionConfig]` (spec §2.3,
    /// shipped v0.16.0). Stored as Data so SwiftData lightweight
    /// migration adds the column with a nil default — existing rows
    /// see an empty config map and fall through to legacy per-level
    /// behavior, identical to pre-feature behavior. Encoded using
    /// `[String: SubdivisionConfig]` because JSONEncoder only allows
    /// string keys; decoder maps back to the enum-keyed dictionary.
    var subdivisionConfigsData: Data? = nil
    /// "Large Display" Stage hero mode (spec §10.3, shipped v0.16.2).
    /// Defaults `false` so existing rows boot with the original Stage
    /// hero size.
    var largeDisplayMode: Bool = false
    /// JSON-encoded `PolyrhythmConfig?` (spec §2.4). Stored as Data so
    /// SwiftData lightweight migration adds the column with a nil
    /// default — existing rows boot with polyrhythm off, identical to
    /// pre-feature behavior.
    var polyrhythmData: Data? = nil

    init(
        masterVolume: Double = 1.0,
        latencyOffsetSeconds: Double = 0.0,
        mixWithOthers: Bool = true,
        countInRaw: Int = CountIn.off.rawValue,
        bpmPrecisionMode: Bool = false,
        autoResumeAfterInterruption: Bool = false,
        clickSoundRaw: String = ClickSound.digitalBeep.rawValue,
        midiClockEnabled: Bool = false,
        midiClockReceiveEnabled: Bool = false,
        midiReceiveSourceName: String? = nil,
        voiceCountModeRaw: String = VoiceCountMode.off.rawValue,
        randomMutePercentage: Int = 0,
        hapticModeRaw: String = HapticMode.off.rawValue,
        hapticIntensitySoft: Double = 0.3,
        hapticIntensityNormal: Double = 0.6,
        hapticIntensityLoud: Double = 0.85,
        hapticIntensityAccent: Double = 1.0,
        keepScreenAwakeDuringPlayback: Bool = true,
        startOnLaunch: Bool = false,
        dailyPracticeGoalMinutes: Int = 0,
        weeklyPracticeGoalMinutes: Int = 0,
        monthlyPracticeGoalMinutes: Int = 0,
        subdivisionConfigsData: Data? = nil,
        largeDisplayMode: Bool = false,
        polyrhythmData: Data? = nil
    ) {
        self.masterVolume = masterVolume
        self.latencyOffsetSeconds = latencyOffsetSeconds
        self.mixWithOthers = mixWithOthers
        self.countInRaw = countInRaw
        self.bpmPrecisionMode = bpmPrecisionMode
        self.autoResumeAfterInterruption = autoResumeAfterInterruption
        self.clickSoundRaw = clickSoundRaw
        self.midiClockEnabled = midiClockEnabled
        self.midiClockReceiveEnabled = midiClockReceiveEnabled
        self.midiReceiveSourceName = midiReceiveSourceName
        self.voiceCountModeRaw = voiceCountModeRaw
        self.randomMutePercentage = randomMutePercentage
        self.hapticModeRaw = hapticModeRaw
        self.hapticIntensitySoft = hapticIntensitySoft
        self.hapticIntensityNormal = hapticIntensityNormal
        self.hapticIntensityLoud = hapticIntensityLoud
        self.hapticIntensityAccent = hapticIntensityAccent
        self.keepScreenAwakeDuringPlayback = keepScreenAwakeDuringPlayback
        self.startOnLaunch = startOnLaunch
        self.dailyPracticeGoalMinutes = dailyPracticeGoalMinutes
        self.weeklyPracticeGoalMinutes = weeklyPracticeGoalMinutes
        self.monthlyPracticeGoalMinutes = monthlyPracticeGoalMinutes
        self.subdivisionConfigsData = subdivisionConfigsData
        self.largeDisplayMode = largeDisplayMode
        self.polyrhythmData = polyrhythmData
    }

    private static func encodePolyrhythm(_ poly: PolyrhythmConfig?) -> Data? {
        guard let poly else { return nil }
        return try? JSONEncoder().encode(poly)
    }

    private static func decodePolyrhythm(_ data: Data?) -> PolyrhythmConfig? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PolyrhythmConfig.self, from: data)
    }

    /// JSON shape for `subdivisionConfigsData`. String-keyed because
    /// JSONEncoder only accepts string keys; the receiver maps back to
    /// the `Subdivision` enum.
    private static func encode(_ configs: [Subdivision: SubdivisionConfig]) -> Data? {
        guard !configs.isEmpty else { return nil }
        let stringKeyed = configs.reduce(into: [String: SubdivisionConfig]()) { acc, kv in
            acc[kv.key.rawValue] = kv.value
        }
        return try? JSONEncoder().encode(stringKeyed)
    }

    private static func decodeSubdivisionConfigs(_ data: Data?) -> [Subdivision: SubdivisionConfig] {
        guard let data,
              let stringKeyed = try? JSONDecoder().decode([String: SubdivisionConfig].self, from: data)
        else { return [:] }
        return stringKeyed.reduce(into: [Subdivision: SubdivisionConfig]()) { acc, kv in
            if let key = Subdivision(rawValue: kv.key) {
                acc[key] = kv.value
            }
        }
    }

    convenience init(from settings: EngineSettings) {
        self.init(
            masterVolume: settings.masterVolume,
            latencyOffsetSeconds: settings.latencyOffsetSeconds,
            mixWithOthers: settings.mixWithOthers,
            countInRaw: settings.countIn.rawValue,
            bpmPrecisionMode: settings.bpmPrecisionMode,
            autoResumeAfterInterruption: settings.autoResumeAfterInterruption,
            clickSoundRaw: settings.clickSound.rawValue,
            midiClockEnabled: settings.midiClockEnabled,
            midiClockReceiveEnabled: settings.midiClockReceiveEnabled,
            midiReceiveSourceName: settings.midiReceiveSourceName,
            voiceCountModeRaw: settings.voiceCountMode.rawValue,
            randomMutePercentage: settings.randomMutePercentage,
            hapticModeRaw: settings.hapticMode.rawValue,
            hapticIntensitySoft: settings.hapticIntensity.soft,
            hapticIntensityNormal: settings.hapticIntensity.normal,
            hapticIntensityLoud: settings.hapticIntensity.loud,
            hapticIntensityAccent: settings.hapticIntensity.accent,
            keepScreenAwakeDuringPlayback: settings.keepScreenAwakeDuringPlayback,
            startOnLaunch: settings.startOnLaunch,
            dailyPracticeGoalMinutes: settings.dailyPracticeGoalMinutes,
            weeklyPracticeGoalMinutes: settings.weeklyPracticeGoalMinutes,
            monthlyPracticeGoalMinutes: settings.monthlyPracticeGoalMinutes,
            subdivisionConfigsData: Self.encode(settings.subdivisionConfigs),
            largeDisplayMode: settings.largeDisplayMode,
            polyrhythmData: Self.encodePolyrhythm(settings.polyrhythm)
        )
    }

    func toEngineSettings() -> EngineSettings {
        EngineSettings(
            masterVolume: masterVolume,
            latencyOffsetSeconds: latencyOffsetSeconds,
            mixWithOthers: mixWithOthers,
            countIn: CountIn(rawValue: countInRaw) ?? .off,
            bpmPrecisionMode: bpmPrecisionMode,
            autoResumeAfterInterruption: autoResumeAfterInterruption,
            clickSound: ClickSound(rawValue: clickSoundRaw) ?? .digitalBeep,
            midiClockEnabled: midiClockEnabled,
            midiClockReceiveEnabled: midiClockReceiveEnabled,
            midiReceiveSourceName: midiReceiveSourceName,
            voiceCountMode: VoiceCountMode(rawValue: voiceCountModeRaw) ?? .off,
            randomMutePercentage: randomMutePercentage,
            hapticMode: HapticMode(rawValue: hapticModeRaw) ?? .off,
            hapticIntensity: HapticIntensity(
                soft: hapticIntensitySoft,
                normal: hapticIntensityNormal,
                loud: hapticIntensityLoud,
                accent: hapticIntensityAccent
            ),
            keepScreenAwakeDuringPlayback: keepScreenAwakeDuringPlayback,
            startOnLaunch: startOnLaunch,
            dailyPracticeGoalMinutes: dailyPracticeGoalMinutes,
            weeklyPracticeGoalMinutes: weeklyPracticeGoalMinutes,
            monthlyPracticeGoalMinutes: monthlyPracticeGoalMinutes,
            subdivisionConfigs: Self.decodeSubdivisionConfigs(subdivisionConfigsData),
            largeDisplayMode: largeDisplayMode,
            polyrhythm: Self.decodePolyrhythm(polyrhythmData)
        )
    }

    func update(from settings: EngineSettings) {
        masterVolume = settings.masterVolume
        latencyOffsetSeconds = settings.latencyOffsetSeconds
        mixWithOthers = settings.mixWithOthers
        countInRaw = settings.countIn.rawValue
        bpmPrecisionMode = settings.bpmPrecisionMode
        autoResumeAfterInterruption = settings.autoResumeAfterInterruption
        clickSoundRaw = settings.clickSound.rawValue
        midiClockEnabled = settings.midiClockEnabled
        midiClockReceiveEnabled = settings.midiClockReceiveEnabled
        midiReceiveSourceName = settings.midiReceiveSourceName
        voiceCountModeRaw = settings.voiceCountMode.rawValue
        randomMutePercentage = settings.randomMutePercentage
        hapticModeRaw = settings.hapticMode.rawValue
        hapticIntensitySoft = settings.hapticIntensity.soft
        hapticIntensityNormal = settings.hapticIntensity.normal
        hapticIntensityLoud = settings.hapticIntensity.loud
        hapticIntensityAccent = settings.hapticIntensity.accent
        keepScreenAwakeDuringPlayback = settings.keepScreenAwakeDuringPlayback
        startOnLaunch = settings.startOnLaunch
        dailyPracticeGoalMinutes = settings.dailyPracticeGoalMinutes
        weeklyPracticeGoalMinutes = settings.weeklyPracticeGoalMinutes
        monthlyPracticeGoalMinutes = settings.monthlyPracticeGoalMinutes
        subdivisionConfigsData = Self.encode(settings.subdivisionConfigs)
        largeDisplayMode = settings.largeDisplayMode
        polyrhythmData = Self.encodePolyrhythm(settings.polyrhythm)
    }
}

// MARK: - Song (library entry, standalone)

@Model
final class PersistedSong {
    @Attribute(.unique) var id: UUID
    var title: String
    var bpmValue: Double
    var timeSigNumerator: Int
    var timeSigDenominatorRaw: Int
    var subdivisionRaw: String
    var soundPreset: String?
    var notes: String?
    /// JSON-encoded `SongDuration?` (nil when no auto-stop is set).
    var durationData: Data?
    /// JSON-encoded `AccentPattern?` (nil when using the default downbeat-only rule).
    var accentPatternData: Data?
    /// JSON-encoded `TempoAutomation?` (nil when no ramp is configured).
    /// New in v2 of the schema — old rows decode as nil via SwiftData's
    /// implicit-nullable-column migration.
    var automationData: Data?
    /// JSON-encoded `[SongSection]?` (nil for single-section songs).
    /// Added in the §7.3 multi-section commit; SwiftData lightweight
    /// migration handles old rows defaulting to nil.
    var sectionsData: Data?

    init(
        id: UUID,
        title: String,
        bpmValue: Double,
        timeSigNumerator: Int,
        timeSigDenominatorRaw: Int,
        subdivisionRaw: String,
        soundPreset: String? = nil,
        notes: String? = nil,
        durationData: Data? = nil,
        accentPatternData: Data? = nil,
        automationData: Data? = nil,
        sectionsData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.bpmValue = bpmValue
        self.timeSigNumerator = timeSigNumerator
        self.timeSigDenominatorRaw = timeSigDenominatorRaw
        self.subdivisionRaw = subdivisionRaw
        self.soundPreset = soundPreset
        self.notes = notes
        self.durationData = durationData
        self.accentPatternData = accentPatternData
        self.automationData = automationData
        self.sectionsData = sectionsData
    }

    convenience init?(from song: Song) {
        let durationData = song.duration.flatMap { try? JSONEncoder().encode($0) }
        let patternData = song.accentPattern.flatMap { try? JSONEncoder().encode($0) }
        let automationData = song.automation.flatMap { try? JSONEncoder().encode($0) }
        let sectionsData = song.sections.flatMap { try? JSONEncoder().encode($0) }
        self.init(
            id: song.id,
            title: song.title,
            bpmValue: song.bpm.value,
            timeSigNumerator: song.timeSignature.numerator,
            timeSigDenominatorRaw: song.timeSignature.denominator.rawValue,
            subdivisionRaw: song.subdivision.rawValue,
            soundPreset: song.soundPreset,
            notes: song.notes,
            durationData: durationData,
            accentPatternData: patternData,
            automationData: automationData,
            sectionsData: sectionsData
        )
    }

    func toSong() -> Song? {
        guard let denominator = TimeSignature.Denominator(rawValue: timeSigDenominatorRaw),
              let timeSignature = TimeSignature(numerator: timeSigNumerator, denominator: denominator),
              let subdivision = Subdivision(rawValue: subdivisionRaw)
        else { return nil }
        let pattern = accentPatternData.flatMap {
            try? JSONDecoder().decode(AccentPattern.self, from: $0)
        }
        let duration = durationData.flatMap {
            try? JSONDecoder().decode(SongDuration.self, from: $0)
        }
        let automation = automationData.flatMap {
            try? JSONDecoder().decode(TempoAutomation.self, from: $0)
        }
        let sections = sectionsData.flatMap {
            try? JSONDecoder().decode([SongSection].self, from: $0)
        }
        return Song(
            id: id,
            title: title,
            bpm: BPM(bpmValue),
            timeSignature: timeSignature,
            subdivision: subdivision,
            accentPattern: pattern,
            soundPreset: soundPreset,
            notes: notes,
            duration: duration,
            automation: automation,
            sections: sections
        )
    }
}

// MARK: - AccentPattern preset library (spec §3.2)

/// A named accent pattern saved to the library, independent of any song.
/// Allows reuse — "rock 4/4" once, applied to many songs without re-
/// editing per song.
@Model
final class PersistedAccentPatternPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    /// JSON-encoded `AccentPattern`. Same approach as `PersistedSong`'s
    /// patterns — the value type's Codable handles the scoping invariant.
    var patternData: Data

    init(id: UUID, name: String, patternData: Data) {
        self.id = id
        self.name = name
        self.patternData = patternData
    }

    /// Returns nil if either argument fails (`pattern` encoding failure
    /// shouldn't happen in practice).
    convenience init?(id: UUID = UUID(), name: String, pattern: AccentPattern) {
        guard let data = try? JSONEncoder().encode(pattern) else { return nil }
        self.init(id: id, name: name, patternData: data)
    }

    func toPattern() -> AccentPattern? {
        try? JSONDecoder().decode(AccentPattern.self, from: patternData)
    }
}

// MARK: - PracticeSession (spec §11)

@Model
final class PersistedPracticeSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var bpmAtStartValue: Double
    var bpmAtStopValue: Double
    /// Min/max BPM seen during the session (spec §11 "BPM range"). Added
    /// in v0.8.6. Legacy rows have these defaulted from start/stop via
    /// SwiftData column defaults so reading them is safe.
    var bpmMinValue: Double = 0
    var bpmMaxValue: Double = 0
    var songID: UUID?
    var songTitle: String?
    var setlistID: UUID?
    var setlistName: String?

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        bpmAtStartValue: Double,
        bpmAtStopValue: Double,
        bpmMinValue: Double = 0,
        bpmMaxValue: Double = 0,
        songID: UUID? = nil,
        songTitle: String? = nil,
        setlistID: UUID? = nil,
        setlistName: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bpmAtStartValue = bpmAtStartValue
        self.bpmAtStopValue = bpmAtStopValue
        self.bpmMinValue = bpmMinValue
        self.bpmMaxValue = bpmMaxValue
        self.songID = songID
        self.songTitle = songTitle
        self.setlistID = setlistID
        self.setlistName = setlistName
    }

    convenience init(from session: PracticeSession) {
        self.init(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            bpmAtStartValue: session.bpmAtStart.value,
            bpmAtStopValue: session.bpmAtStop.value,
            bpmMinValue: session.bpmMin.value,
            bpmMaxValue: session.bpmMax.value,
            songID: session.songID,
            songTitle: session.songTitle,
            setlistID: session.setlistID,
            setlistName: session.setlistName
        )
    }

    func toPracticeSession() -> PracticeSession {
        // Legacy rows (pre-v0.8.6) have bpmMin/bpmMax stored as 0; the
        // PracticeSession init's nil-fallback derives them from start/stop
        // when we pass nil for the optionals, which is what we want.
        let storedMin = bpmMinValue > 0 ? BPM(bpmMinValue) : nil
        let storedMax = bpmMaxValue > 0 ? BPM(bpmMaxValue) : nil
        return PracticeSession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            bpmAtStart: BPM(bpmAtStartValue),
            bpmAtStop: BPM(bpmAtStopValue),
            bpmMin: storedMin,
            bpmMax: storedMax,
            songID: songID,
            songTitle: songTitle,
            setlistID: setlistID,
            setlistName: setlistName
        )
    }
}

// MARK: - Setlist

@Model
final class PersistedSetlist {
    @Attribute(.unique) var id: UUID
    var name: String
    /// JSON-encoded `SetlistAdvanceMode`. Stored as Data rather than as
    /// a relationship because the enum has associated values.
    var advanceModeData: Data
    /// JSON-encoded `[Song]`. Stored inline (value-copy) so editing a
    /// song in the standalone library doesn't mutate setlist snapshots.
    var songsData: Data

    init(id: UUID, name: String, advanceModeData: Data, songsData: Data) {
        self.id = id
        self.name = name
        self.advanceModeData = advanceModeData
        self.songsData = songsData
    }

    convenience init(from setlist: Setlist) {
        let modeData = (try? JSONEncoder().encode(setlist.advanceMode)) ?? Data()
        let songsData = (try? JSONEncoder().encode(setlist.songs)) ?? Data()
        self.init(
            id: setlist.id,
            name: setlist.name,
            advanceModeData: modeData,
            songsData: songsData
        )
    }

    func toSetlist() -> Setlist {
        let mode = (try? JSONDecoder().decode(SetlistAdvanceMode.self, from: advanceModeData))
            ?? .pause
        let songs = (try? JSONDecoder().decode([Song].self, from: songsData)) ?? []
        return Setlist(id: id, name: name, songs: songs, advanceMode: mode)
    }

    func update(from setlist: Setlist) {
        name = setlist.name
        advanceModeData = (try? JSONEncoder().encode(setlist.advanceMode)) ?? Data()
        songsData = (try? JSONEncoder().encode(setlist.songs)) ?? Data()
    }
}
