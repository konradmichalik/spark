import SwiftUI

struct UsageGraphView: View {
    let history: [UsageSnapshot]

    private var recentHistory: [UsageSnapshot] {
        let cutoff = Date().addingTimeInterval(-3600 * 6) // last 6 hours
        return history.filter { $0.timestamp > cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("History (6h)")
                .font(.caption2)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                let data = recentHistory
                if data.count >= 2 {
                    ZStack {
                        // Background grid lines
                        ForEach([25.0, 50.0, 75.0], id: \.self) { threshold in
                            Path { path in
                                let y = geometry.size.height * (1 - threshold / 100)
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                        }

                        // Warning zone
                        Rectangle()
                            .fill(Color.red.opacity(0.05))
                            .frame(height: geometry.size.height * 0.1)

                        // Session line
                        UsageLine(
                            data: data.map(\.sessionUtilization),
                            size: geometry.size,
                            color: .blue
                        )

                        // Weekly line
                        UsageLine(
                            data: data.map(\.weeklyUtilization),
                            size: geometry.size,
                            color: .purple
                        )
                    }
                } else {
                    Text("Not enough data yet")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text("Session").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.purple).frame(width: 6, height: 6)
                    Text("Weekly").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct UsageLine: View {
    let data: [Double]
    let size: CGSize
    let color: Color

    var body: some View {
        Path { path in
            guard data.count >= 2 else { return }
            let stepX = size.width / CGFloat(data.count - 1)

            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height * (1 - min(value, 100) / 100)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, lineWidth: 1.5)
    }
}
