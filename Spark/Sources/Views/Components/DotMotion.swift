import SwiftUI

/// Timing of the dot bar and ring motion (docs/design/rules.md, "Motion"). Pure, so it is
/// unit tested; `DotMotion` only drives it.
enum DotFillSequence {
    /// The whole fill, however many dots it adds.
    static let duration = 0.3
    /// The gap between two dots when only a few are added.
    static let maxStagger = 0.025
    /// One full breath of the hollow dots, out and back in.
    static let breathPeriod = 2.0

    /// How far a fill has run, 0 to 1, from the animated `phase` and the `target` it runs to.
    /// Every fill moves the target up by one, so the fraction left is the fill still to come.
    static func progress(phase: Double, target: Double) -> Double {
        min(max(1 - (target - phase), 0), 1)
    }

    /// Filled dots shown at `progress` of a fill from `from` to `to` filled dots. The new dots
    /// follow each other at 25 ms, closer when more of them have to fit into 300 ms. A fall
    /// shows at once.
    static func revealed(from: Int, to: Int, progress: Double) -> Int {
        guard to > from, progress < 1 else { return to }
        let stagger = min(maxStagger, duration / Double(to - from))
        // The epsilon keeps a dot that is due exactly now from slipping to the next frame.
        let shown = Int((max(progress, 0) * duration / stagger + 1e-9).rounded(.down))
        return min(from + shown, to)
    }

    /// Where a fill starts when the value changes from `old` to `new`: at the old value when it
    /// rose, `nil` (no fill) when it fell or stayed.
    static func start(old: Double, new: Double) -> Double? {
        old.isFinite && new > old ? max(old, 0) : nil
    }

    /// What a dot draws during a fill: a filled dot that is not revealed yet is still track.
    static func dot(_ dot: DotBarLayout.Dot, at position: Int, revealed: Int) -> DotBarLayout.Dot {
        dot == .filled && position >= revealed ? .track : dot
    }

    /// Opacity of the hollow dots while they breathe; `breath` runs from 0 to 1 and back.
    static func projectionOpacity(breath: Double) -> Double {
        1 - 0.65 * min(max(breath, 0), 1)
    }

    /// The hollow dots breathe only on a layer that is asked to, once it has settled, and never
    /// under Reduce Motion.
    static func shouldBreathe(isActive: Bool, reduceMotion: Bool, isSettled: Bool) -> Bool {
        isActive && !reduceMotion && isSettled
    }
}

/// One frame of the dot motion, handed to the bar or ring that draws it.
struct DotMotionFrame {
    let fillFrom: Double
    let progress: Double

    /// The layout's dots as they show in this frame.
    func dots(of layout: DotBarLayout) -> [DotBarLayout.Dot] {
        guard progress < 1 else { return layout.dots }
        let from = DotBarLayout(count: layout.dots.count, value: fillFrom).filledCount
        let revealed = DotFillSequence.revealed(from: from, to: layout.filledCount, progress: progress)
        return layout.dots.enumerated().map { DotFillSequence.dot($1, at: $0, revealed: revealed) }
    }
}

/// Runs the fill motion of a dot bar or ring: with `animates`, the filled dots appear in sequence
/// on appear and when the value rises. Under Reduce Motion it draws the end state.
struct DotMotion<Content: View>: View {
    let value: Double
    let animates: Bool
    let content: (DotMotionFrame) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var fillFrom: Double = 0
    @State private var fillTarget: Double = 0

    private var isMoving: Bool { animates && !reduceMotion }

    var body: some View {
        let target = fillTarget
        let from = fillFrom
        let isWaiting = isMoving && !hasAppeared
        AnimatedValue(value: fillTarget) { phase in
            let progress = isWaiting ? 0 : DotFillSequence.progress(phase: phase, target: target)
            content(DotMotionFrame(fillFrom: from, progress: progress))
        }
        .onAppear {
            hasAppeared = true
            fill(from: 0)
        }
        .onChange(of: value) { old, new in
            if let start = DotFillSequence.start(old: old, new: new) { fill(from: start) }
        }
    }

    private func fill(from start: Double) {
        guard isMoving else { return }
        fillFrom = start
        withAnimation(.linear(duration: DotFillSequence.duration)) { fillTarget += 1 }
    }
}

/// Lets a layer breathe: its opacity swings between full and 35 % in its own phase loop, so
/// re-renders and animations around it cannot re-target it, and nothing under it is redrawn.
/// The loop starts 300 ms after the view appears, like the live dot's halo.
private struct Breathing: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    func body(content: Content) -> some View {
        Group {
            if DotFillSequence.shouldBreathe(isActive: isActive, reduceMotion: reduceMotion, isSettled: isSettled) {
                PhaseAnimator([0.0, 1.0]) { breath in
                    content.opacity(DotFillSequence.projectionOpacity(breath: breath))
                } animation: { _ in
                    .easeInOut(duration: DotFillSequence.breathPeriod / 2)
                }
                .transaction { $0.animation = nil }
            } else {
                content
            }
        }
        .task(id: isActive) {
            // Every activation waits for the layout to settle again, not only the first.
            isSettled = false
            guard isActive else { return }
            isSettled = await LiveDotHalo.settle()
        }
    }
}

extension View {
    func breathing(isActive: Bool) -> some View {
        modifier(Breathing(isActive: isActive))
    }
}

/// Hands an animated value to its content frame by frame, so a `Canvas` can draw it.
private struct AnimatedValue<Content: View>: View, Animatable {
    var value: Double
    let content: (Double) -> Content

    init(value: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.value = value
        self.content = content
    }

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        content(value)
    }
}
