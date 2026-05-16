import Testing
import Foundation
@testable import MetronomeCore

// Test helper
private func makeSong(_ title: String, bpm: Double = 120) -> Song {
    Song(title: title, bpm: BPM(bpm))!
}

// MARK: - Construction

@Test func emptySetlistDefaults() {
    let s = Setlist(name: "Tonight")
    #expect(s.name == "Tonight")
    #expect(s.isEmpty)
    #expect(s.count == 0)
    #expect(s.advanceMode == .pause)
}

@Test func setlistInitialContents() {
    let s = Setlist(name: "Set 1", songs: [makeSong("A"), makeSong("B"), makeSong("C")])
    #expect(s.count == 3)
    #expect(s[0].title == "A")
    #expect(s[2].title == "C")
}

@Test func advanceModeCases() {
    #expect(SetlistAdvanceMode.pause == .pause)
    #expect(SetlistAdvanceMode.countdown(measures: 2) == .countdown(measures: 2))
    #expect(SetlistAdvanceMode.countdown(measures: 2) != .countdown(measures: 4))
    #expect(SetlistAdvanceMode.immediate != .pause)
}

// MARK: - Append / index

@Test func appendAddsToEnd() {
    var s = Setlist(name: "X")
    s.append(makeSong("first"))
    s.append(makeSong("second"))
    #expect(s.count == 2)
    #expect(s[0].title == "first")
    #expect(s[1].title == "second")
}

// MARK: - Next / previous

@Test func nextSongReturnsNeighbor() {
    let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
    let s = Setlist(name: "X", songs: [a, b, c])
    #expect(s.song(after: a.id)?.id == b.id)
    #expect(s.song(after: b.id)?.id == c.id)
    #expect(s.song(after: c.id) == nil)
}

@Test func previousSongReturnsNeighbor() {
    let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
    let s = Setlist(name: "X", songs: [a, b, c])
    #expect(s.song(before: c.id)?.id == b.id)
    #expect(s.song(before: b.id)?.id == a.id)
    #expect(s.song(before: a.id) == nil)
}

@Test func nextReturnsNilForUnknownId() {
    let s = Setlist(name: "X", songs: [makeSong("A")])
    #expect(s.song(after: UUID()) == nil)
    #expect(s.song(before: UUID()) == nil)
}

// MARK: - Remove

@Test func removeByIdReturnsTheSong() {
    let a = makeSong("A"), b = makeSong("B")
    var s = Setlist(name: "X", songs: [a, b])
    let removed = s.remove(id: a.id)
    #expect(removed?.id == a.id)
    #expect(s.count == 1)
    #expect(s[0].id == b.id)
}

@Test func removeUnknownIdReturnsNil() {
    var s = Setlist(name: "X", songs: [makeSong("A")])
    let removed = s.remove(id: UUID())
    #expect(removed == nil)
    #expect(s.count == 1)
}

// MARK: - Move (drag-reorder)

@Test func moveReordersInPlace() {
    let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
    var s = Setlist(name: "X", songs: [a, b, c])
    s.move(id: a.id, to: 2)
    #expect(s[0].id == b.id)
    #expect(s[1].id == c.id)
    #expect(s[2].id == a.id)
}

@Test func moveBackwardsWorks() {
    let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
    var s = Setlist(name: "X", songs: [a, b, c])
    s.move(id: c.id, to: 0)
    #expect(s[0].id == c.id)
    #expect(s[1].id == a.id)
    #expect(s[2].id == b.id)
}

@Test func moveToSameIndexIsNoop() {
    let a = makeSong("A"), b = makeSong("B")
    var s = Setlist(name: "X", songs: [a, b])
    s.move(id: a.id, to: 0)
    #expect(s[0].id == a.id)
    #expect(s[1].id == b.id)
}

@Test func moveOutOfBoundsIsNoop() {
    let a = makeSong("A"), b = makeSong("B")
    var s = Setlist(name: "X", songs: [a, b])
    s.move(id: a.id, to: 99)
    s.move(id: a.id, to: -1)
    #expect(s[0].id == a.id)
    #expect(s[1].id == b.id)
}

@Test func moveUnknownIdIsNoop() {
    let a = makeSong("A"), b = makeSong("B")
    var s = Setlist(name: "X", songs: [a, b])
    s.move(id: UUID(), to: 1)
    #expect(s[0].id == a.id)
    #expect(s[1].id == b.id)
}
