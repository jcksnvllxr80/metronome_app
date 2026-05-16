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

    init(
        masterVolume: Double = 1.0,
        latencyOffsetSeconds: Double = 0.0,
        mixWithOthers: Bool = true,
        countInRaw: Int = CountIn.off.rawValue,
        bpmPrecisionMode: Bool = false,
        autoResumeAfterInterruption: Bool = false,
        clickSoundRaw: String = ClickSound.digitalBeep.rawValue,
        midiClockEnabled: Bool = false,
        midiClockReceiveEnabled: Bool = false
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
            midiClockReceiveEnabled: settings.midiClockReceiveEnabled
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
            midiClockReceiveEnabled: midiClockReceiveEnabled
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
        accentPatternData: Data? = nil
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
    }

    convenience init?(from song: Song) {
        let durationData = song.duration.flatMap { try? JSONEncoder().encode($0) }
        let patternData = song.accentPattern.flatMap { try? JSONEncoder().encode($0) }
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
            accentPatternData: patternData
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
        return Song(
            id: id,
            title: title,
            bpm: BPM(bpmValue),
            timeSignature: timeSignature,
            subdivision: subdivision,
            accentPattern: pattern,
            soundPreset: soundPreset,
            notes: notes,
            duration: duration
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
