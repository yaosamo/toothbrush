import SwiftUI
import RealityKit
import UIKit

/// Drives Bao's animations. Clips are cut out of the single USDZ timeline
/// (see tools/build_panda.py, which prints these frame ranges).
@MainActor
final class PandaDirector: ObservableObject {
    enum Clip: String, CaseIterable {
        case idle = "Idle", wave = "Wave", brush = "Brush", jump = "Jump", yes = "Yes", giggle = "Giggle"
    }

    // Frame ranges at 30 fps, from build_panda.py output.
    private static let fps = 30.0
    private static let ranges: [Clip: (Double, Double)] = [
        .idle: (1, 61), .wave: (62, 122), .brush: (123, 153), .jump: (154, 194), .yes: (195, 235), .giggle: (236, 272),
    ]

    private var animated: Entity?
    private var clips: [Clip: AnimationResource] = [:]
    private var brushing = false
    private var queue: Task<Void, Never>?

    func attach(_ panda: Entity) {
        guard let target = Self.findAnimated(panda), let full = target.availableAnimations.first else {
            NSLog("[Panda] %@", " no animations found")
            return
        }
        animated = target
        for (clip, r) in Self.ranges {
            let view = AnimationView(source: full.definition, name: clip.rawValue,
                                     trimStart: (r.0 - 1) / Self.fps, trimEnd: (r.1 - 1) / Self.fps)
            do { clips[clip] = try AnimationResource.generate(with: view) }
            catch { NSLog("[Panda] %@", " clip \(clip.rawValue) failed: \(error)") }
        }
        NSLog("[Panda] %@", " animations on \(target.name): \(target.availableAnimations.count), full \(full.definition.duration)s, clips \(clips.count)")
        loop(.idle)
        perform([.wave])
    }

    func setBrushing(_ on: Bool) {
        brushing = on
        if on { queue?.cancel(); loop(.brush) } else { perform([.yes]) }
    }

    func celebrate() { perform([.jump, .jump, .wave]) }
    func poke() { if !brushing { perform([.giggle]) } }

    /// Plays one-shot clips in order, then returns to the looping state.
    private func perform(_ sequence: [Clip]) {
        queue?.cancel()
        queue = Task { [weak self] in
            for clip in sequence {
                guard let self, let res = self.clips[clip], let e = self.animated else { return }
                e.playAnimation(res, transitionDuration: 0.2)
                try? await Task.sleep(for: .seconds(max(0.3, res.definition.duration - 0.15)))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            self.loop(self.brushing ? .brush : .idle)
        }
    }

    private func loop(_ clip: Clip) {
        guard let res = clips[clip], let e = animated else { return }
        e.playAnimation(res.repeat(), transitionDuration: 0.25)
    }

    private static func findAnimated(_ e: Entity) -> Entity? {
        if !e.availableAnimations.isEmpty { return e }
        for c in e.children { if let f = findAnimated(c) { return f } }
        return nil
    }
}

struct TempleView: View {
    @ObservedObject var director: PandaDirector

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let world = Entity()
            content.add(world)
            await TempleScene.build(into: world, director: director)
        }
        .ignoresSafeArea()
        .onTapGesture { director.poke() }
    }
}

@MainActor
enum TempleScene {
    static func build(into world: Entity, director: PandaDirector) async {
        world.addChild(sky())

        // Ground: grass, with a warm stone courtyard in the middle.
        let grass = ModelEntity(mesh: .generatePlane(width: 80, depth: 80),
                                materials: [PhysicallyBasedMaterial.matte(UIColor(red: 0.42, green: 0.62, blue: 0.30, alpha: 1))])
        world.addChild(grass)
        let court = ModelEntity(mesh: .generateCylinder(height: 0.06, radius: 3.4),
                                materials: [PhysicallyBasedMaterial.matte(UIColor(red: 0.80, green: 0.74, blue: 0.64, alpha: 1))])
        court.position.y = 0.03
        world.addChild(court)
        let rug = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 1.0),
                              materials: [PhysicallyBasedMaterial.matte(UIColor(red: 0.72, green: 0.13, blue: 0.12, alpha: 1))])
        rug.position.y = 0.07
        world.addChild(rug)

        if let pavilion = try? await Entity(named: "Pavilion") {
            pavilion.position = [0, 0, -7.5]
            pavilion.orientation = simd_quatf(angle: .pi / 6, axis: [0, 1, 0])
            world.addChild(pavilion)
        }
        if let pagoda = try? await Entity(named: "Pagoda") {
            pagoda.position = [3.6, 0, -15]
            world.addChild(pagoda)
            let far = pagoda.clone(recursive: true)
            far.position = [-4.2, 0, -19]
            far.scale = [0.8, 0.8, 0.8]
            world.addChild(far)
        }
        if let lantern = try? await Entity(named: "Lantern") {
            for (i, x) in [Float(-1.15), 1.15].enumerated() {
                world.addChild(lanternPost(lantern.clone(recursive: true), at: [x, 0, -1.5], phase: Float(i)))
            }
            for (i, x) in [Float(-1.8), 1.8].enumerated() {
                world.addChild(lanternPost(lantern.clone(recursive: true), at: [x, 0, -4.0], phase: Float(i) + 0.5))
            }
        }

        if let panda = try? await Entity(named: "Bao") {
            panda.position = [0, 0.08, 0]
            panda.scale = [0.9, 0.9, 0.9]
            world.addChild(panda)
            director.attach(panda)
        }

        // Lighting: warm low sun with shadows, plus a soft cool fill.
        let sun = DirectionalLight()
        sun.light.color = UIColor(red: 1.0, green: 0.92, blue: 0.80, alpha: 1)
        sun.light.intensity = 4200
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 14, depthBias: 2)
        sun.look(at: [0, 0, -1], from: [3, 6, 7], relativeTo: nil)
        world.addChild(sun)
        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1)
        fill.light.intensity = 900
        fill.look(at: [0, 0, 0], from: [-5, 3, 4], relativeTo: nil)
        world.addChild(fill)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        camera.look(at: [0, 1.15, -3], from: [0, 1.4, 3.8], relativeTo: nil)
        world.addChild(camera)
    }

    /// A red wooden post with a lantern hanging from an arm; the lantern swings gently.
    private static func lanternPost(_ lantern: Entity, at p: SIMD3<Float>, phase: Float) -> Entity {
        let wood = PhysicallyBasedMaterial.matte(UIColor(red: 0.62, green: 0.12, blue: 0.10, alpha: 1))
        let post = Entity()
        post.position = p
        let pole = ModelEntity(mesh: .generateBox(width: 0.09, height: 1.9, depth: 0.09), materials: [wood])
        pole.position.y = 0.95
        post.addChild(pole)
        let arm = ModelEntity(mesh: .generateBox(width: 0.45, height: 0.06, depth: 0.06), materials: [wood])
        arm.position = [p.x < 0 ? 0.2 : -0.2, 1.86, 0]
        post.addChild(arm)

        let pivot = Entity()
        pivot.position = [p.x < 0 ? 0.38 : -0.38, 1.83, 0]
        lantern.scale = [1.7, 1.7, 1.7]
        lantern.position.y = -0.85
        pivot.addChild(lantern)
        let glow = PointLight()
        glow.light.color = UIColor(red: 1.0, green: 0.55, blue: 0.3, alpha: 1)
        glow.light.intensity = 1800
        glow.light.attenuationRadius = 2.5
        glow.position.y = -0.5
        pivot.addChild(glow)
        post.addChild(pivot)

        let swing = FromToByAnimation<Transform>(
            from: Transform(scale: .one, rotation: simd_quatf(angle: -0.07, axis: [0, 0, 1]), translation: pivot.position),
            to: Transform(scale: .one, rotation: simd_quatf(angle: 0.07, axis: [0, 0, 1]), translation: pivot.position),
            duration: 1.6 + Double(phase) * 0.3, timing: .easeInOut, bindTarget: .transform,
            repeatMode: .autoReverse)
        if let res = try? AnimationResource.generate(with: swing) { pivot.playAnimation(res) }
        return post
    }

    /// A huge inside-out sphere with a vertical sky gradient.
    private static func sky() -> Entity {
        var mat = UnlitMaterial(color: UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1))
        if let cg = gradient(top: UIColor(red: 0.36, green: 0.62, blue: 0.92, alpha: 1),
                             bottom: UIColor(red: 1.0, green: 0.87, blue: 0.72, alpha: 1)),
           let tex = try? TextureResource(image: cg, options: .init(semantic: .color)) {
            mat.color = .init(tint: .white, texture: .init(tex))
        }
        mat.faceCulling = .front
        return ModelEntity(mesh: .generateSphere(radius: 60), materials: [mat])
    }

    private static func gradient(top: UIColor, bottom: UIColor) -> CGImage? {
        let size = CGSize(width: 4, height: 256)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [top.cgColor, top.cgColor, bottom.cgColor, bottom.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return img.cgImage
    }
}

extension PhysicallyBasedMaterial {
    static func matte(_ color: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: 0.9)
        m.metallic = .init(floatLiteral: 0)
        return m
    }
}
