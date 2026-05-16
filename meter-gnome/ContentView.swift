//
//  ContentView.swift
//  meter-gnome
//

import SwiftUI
import MetronomeCore

struct ContentView: View {
    private let bpm = BPM(120)
    private let timeSignature = TimeSignature.fourFour

    var body: some View {
        VStack(spacing: 16) {
            Text("\(bpm.displayInt)")
                .font(.system(size: 96, weight: .bold, design: .monospaced))
                .monospacedDigit()
            Text("BPM")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(timeSignature.numerator) / \(timeSignature.denominator.rawValue)")
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .padding(.top, 32)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
