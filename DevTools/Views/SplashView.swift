import SwiftUI

/// Animated launch experience: aurora background, floating particles, the app icon
/// dropping in with a 3D tilt, orbit rings drawing themselves, the title revealed
/// letter by letter, a growing chart line and a live progress bar that follows
/// the real first data load. Exits with a zoom/fade (handled by the parent).
struct SplashView: View {
    let progress: Double
    let phase: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconIn = false
    @State private var ringDraw: CGFloat = 0
    @State private var titleIn = false
    @State private var chartDraw: CGFloat = 0
    @State private var footerIn = false

    private let title = Array("DevTools")

    var body: some View {
        ZStack {
            AuroraBackground(animated: !reduceMotion)
            GridGlow()
            if !reduceMotion { ParticleField() }

            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.cyan.opacity(0.55), Color.blue.opacity(0.0)], center: .center, startRadius: 10, endRadius: 150))
                        .frame(width: 300, height: 300)
                        .scaleEffect(iconIn ? 1 : 0.4)
                        .opacity(iconIn ? 1 : 0)
                    OrbitRings(draw: ringDraw, animated: !reduceMotion)
                        .frame(width: 236, height: 236)
                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(color: Color.black.opacity(0.45), radius: 24, y: 14)
                        .shadow(color: Theme.cyan.opacity(0.5), radius: 30)
                        .scaleEffect(iconIn ? 1 : 0.35)
                        .rotation3DEffect(.degrees(iconIn ? 0 : 38), axis: (x: 1, y: -0.6, z: 0), perspective: 0.6)
                        .opacity(iconIn ? 1 : 0)
                        .offset(y: iconIn ? 0 : -40)
                }
                .frame(width: 260, height: 260)

                HStack(spacing: 0) {
                    ForEach(Array(title.enumerated()), id: \.offset) { item in
                        Text(String(item.element))
                            .opacity(titleIn ? 1 : 0)
                            .offset(y: titleIn ? 0 : 18)
                            .blur(radius: titleIn ? 0 : 8)
                            .animation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.5 + Double(item.offset) * 0.05), value: titleIn)
                    }
                }
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, Color(rgb: 0xBFE9FF)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.cyan.opacity(0.45), radius: 18)

                Text("App Store Connect · TestFlight · Insights")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .opacity(titleIn ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.95), value: titleIn)

                SparkLine()
                    .trim(from: 0, to: chartDraw)
                    .stroke(LinearGradient(colors: [Theme.cyan, .white], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 190, height: 46)
                    .shadow(color: Theme.cyan.opacity(0.8), radius: 8)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(.white).frame(width: 9, height: 9)
                            .shadow(color: Theme.cyan, radius: 6)
                            .offset(x: 4, y: -4)
                            .opacity(chartDraw >= 1 ? 1 : 0)
                            .scaleEffect(chartDraw >= 1 ? 1 : 0.2)
                            .animation(.spring(response: 0.4, dampingFraction: 0.5), value: chartDraw)
                    }
                    .padding(.top, 4)

                Spacer()

                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule()
                                .fill(LinearGradient(colors: [Color(rgb: 0x2F6BFF), Theme.cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * CGFloat(min(max(progress, 0.04), 1))))
                                .shadow(color: Theme.cyan.opacity(0.8), radius: 6)
                        }
                    }
                    .frame(width: 180, height: 5)
                    .animation(.easeInOut(duration: 0.35), value: progress)

                    Text(phase)
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: phase)
                        .lineLimit(1)
                }
                .opacity(footerIn ? 1 : 0)
                .padding(.bottom, 54)
            }
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
        .onAppear(perform: start)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DevTools wordt geladen")
    }

    private func start() {
        if reduceMotion {
            iconIn = true; ringDraw = 1; titleIn = true; chartDraw = 1; footerIn = true
            return
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62).delay(0.08)) { iconIn = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.25)) { ringDraw = 1 }
        titleIn = true
        withAnimation(.easeInOut(duration: 1.0).delay(1.05)) { chartDraw = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(1.2)) { footerIn = true }
    }
}

/// Slowly drifting blurred colour blobs on a deep navy background.
struct AuroraBackground: View {
    var animated = true

    private struct Blob {
        let color: Color
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let speed: Double
        let phase: Double
    }

    private let blobs: [Blob] = [
        Blob(color: Color(rgb: 0x0A4FE0), size: 1.15, x: -0.25, y: -0.30, speed: 0.22, phase: 0),
        Blob(color: Color(rgb: 0x18B7F2), size: 0.95, x: 0.35, y: -0.10, speed: 0.31, phase: 1.7),
        Blob(color: Color(rgb: 0x6A3DF0), size: 0.85, x: -0.20, y: 0.35, speed: 0.27, phase: 3.1),
        Blob(color: Color(rgb: 0x0E7BFF), size: 0.75, x: 0.30, y: 0.42, speed: 0.35, phase: 4.4)
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Color(rgb: 0x030A1C)
                    ForEach(0..<blobs.count, id: \.self) { i in
                        let b = blobs[i]
                        let dx = CGFloat(sin(t * b.speed + b.phase)) * w * 0.12
                        let dy = CGFloat(cos(t * b.speed * 0.8 + b.phase)) * h * 0.08
                        Circle()
                            .fill(b.color)
                            .frame(width: w * b.size, height: w * b.size)
                            .position(x: w / 2 + b.x * w + dx, y: h / 2 + b.y * h + dy)
                            .opacity(0.55)
                    }
                }
                .blur(radius: 70)
                .overlay(
                    LinearGradient(colors: [.clear, Color(rgb: 0x030A1C).opacity(0.65)], startPoint: .center, endPoint: .bottom)
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Faint perspective grid fading towards the top.
struct GridGlow: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                let step: CGFloat = 36
                var x: CGFloat = 0
                while x <= w { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)); x += step }
                var y: CGFloat = 0
                while y <= h { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)); y += step }
            }
            .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
            .mask(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 40, endRadius: max(w, h) * 0.6))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Small glowing particles rising slowly.
struct ParticleField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for i in 0..<46 {
                    let seed = Double(i) * 12.9898
                    let rx = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let speed = 0.015 + abs(sin(seed * 1.7)).truncatingRemainder(dividingBy: 1) * 0.04
                    let ry = (abs(cos(seed) * 23421.631).truncatingRemainder(dividingBy: 1) - t * speed).truncatingRemainder(dividingBy: 1)
                    let y = (ry < 0 ? ry + 1 : ry) * size.height
                    let x = rx * size.width + CGFloat(sin(t * 0.6 + seed)) * 10
                    let r = 1.0 + (Double(i % 4)) * 0.6
                    let alpha = 0.15 + 0.35 * abs(sin(t * 0.9 + seed))
                    let rect = CGRect(x: x, y: y, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Two orbit rings that draw themselves, then keep rotating with satellites.
struct OrbitRings: View {
    let draw: CGFloat
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animated)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let a1 = (t * 40).truncatingRemainder(dividingBy: 360)
            let a2 = (-t * 26).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle()
                    .trim(from: 0, to: draw * 0.82)
                    .stroke(AngularGradient(colors: [Theme.cyan.opacity(0), Theme.cyan, .white], center: .center),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(a1))
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.cyan, radius: 6)
                    .offset(y: -118)
                    .rotationEffect(.degrees(a1 + 295))
                    .opacity(draw >= 1 ? 1 : 0)
                Circle()
                    .trim(from: 0, to: draw * 0.6)
                    .stroke(AngularGradient(colors: [Color(rgb: 0x6A3DF0).opacity(0), Color(rgb: 0x8F7BFF), Color(rgb: 0x2F6BFF)], center: .center),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
                    .padding(22)
                    .rotationEffect(.degrees(a2))
                Circle()
                    .fill(Color(rgb: 0x8F7BFF))
                    .frame(width: 6, height: 6)
                    .offset(y: -96)
                    .rotationEffect(.degrees(a2 + 216))
                    .opacity(draw >= 1 ? 1 : 0)
            }
        }
    }
}

/// Upward trending chart line used on the splash.
struct SparkLine: Shape {
    func path(in rect: CGRect) -> Path {
        let values: [CGFloat] = [0.78, 0.62, 0.70, 0.48, 0.55, 0.36, 0.42, 0.20, 0.26, 0.0]
        var p = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1), y: rect.minY + rect.height * v)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
