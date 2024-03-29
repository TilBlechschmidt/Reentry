//
//  OrbitingNode.swift
//  DragTests
//
//  Created by Til Blechschmidt on 18.03.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import SpriteKit

class OrbitingNode: CapsuleNode {

    var highestAcceleration: CGFloat = 0.0
    var remainingBurnTime: TimeInterval = Capsule.secondsOfThrust
    var heat: CGFloat = 0.0
    var remainingHeatShield: CGFloat = Capsule.heatShieldCapacity

    var thrusterState: Bool = false

    var onRails: Bool = true {
        didSet {
            physicsBody?.allowsRotation = !onRails
            physicsBody?.collisionBitMask = onRails ? 0 : 0xFFFFFFFF

            if !oldValue {
                updateOrbit()
            }
        }
    }

    var displayState: DisplayState {
        didSet {
            redrawOrbit()
            redrawPosition()
        }
    }

    var heightAboveTerrain: CGFloat {
        return (Vector(position) - Vector(reference.position)).length - reference.bodyRadius
    }

    var insideAtmosphere: Bool {
        return heightAboveTerrain < reference.atmosphereHeight
    }

    var apoapsisHeight: CGFloat {
        return orbitalParameters.apoapsisHeight - reference.bodyRadius
    }

    var periapsisHeight: CGFloat {
        return orbitalParameters.periapsisHeight - reference.bodyRadius
    }

    var landed: Bool {
        let touchedDown = self.physicsBody!.allContactedBodies().contains(reference.physicsBody!)
        let settled = Vector(self.physicsBody!.velocity).length < Game.settlingVelocityThreshold
        return touchedDown && settled
    }

    var currentReferenceAngle: CGFloat {
        let positionVector = Vector(position) - Vector(reference.position)
        let referenceAngle: Vector = [1, 0, 0]
        let angle = atan2(positionVector.y - referenceAngle.y, positionVector.x - referenceAngle.x)
        return angle
    }

    var orbitalParameters: OrbitalParameters! {
        didSet {
            redrawOrbit()
            redrawPosition()
        }
    }
    private(set) var orbitalLine: SKShapeNode
    private(set) var periapsisMarker: OrbitMarker = OrbitMarker(label: "Periapsis")
    private(set) var apoapsisMarker: OrbitMarker = OrbitMarker(label: "Apoapsis")
    private(set) var positionMarker: SKShapeNode = SKShapeNode(circleOfRadius: 20.0)

    private var localTime: TimeInterval = 0
    private let reference: PlanetNode

    private let gravitationalConstant: CGFloat = Simulation.gravitationalConstant

    private let deorbitParticles = SKEmitterNode(fileNamed: Emitter.deorbit)!
    private let thrusterParticles1 = SKEmitterNode(fileNamed: Emitter.thruster)!
    private let thrusterParticles2 = SKEmitterNode(fileNamed: Emitter.thruster)!

    init(reference: PlanetNode, displayState: DisplayState) {
        orbitalLine = SKShapeNode()
        orbitalLine.strokeColor = SKColor.lightGray.withAlphaComponent(0.5)
        orbitalLine.lineWidth = 0.5

        self.reference = reference

        self.displayState = displayState

        super.init(scale: 0.05)

        zPosition = Layer.entity
        
        physicsBody?.mass = Capsule.mass
        physicsBody?.linearDamping = 0
        physicsBody?.angularDamping = 0
        physicsBody?.velocity = CGVector(dx: 0, dy: 7666) // ISS Orbital speed
        physicsBody?.isDynamic = true
        physicsBody?.allowsRotation = !onRails
        physicsBody?.collisionBitMask = onRails ? 0 : 0xFFFFFFFF
        physicsBody?.usesPreciseCollisionDetection = true

        deorbitParticles.particleBirthRate = 0
        deorbitParticles.zPosition = Layer.particles
        deorbitParticles.particleZPosition = Layer.particles
        addChild(deorbitParticles)

        // Thruster
        thrusterParticles1.particleBirthRate = 0
        thrusterParticles2.particleBirthRate = 0

        thrusterParticles1.zPosition = Layer.particles
        thrusterParticles2.zPosition = Layer.particles
        thrusterParticles1.particleZPosition = Layer.particles
        thrusterParticles2.particleZPosition = Layer.particles

        thrusterParticles1.position = CGPoint(x: super.width / 2, y: 0)
        thrusterParticles2.position = CGPoint(x: -super.width / 2, y: 0)

        addChild(thrusterParticles1)
        addChild(thrusterParticles2)

        let headingMarker = SKShapeNode(circleOfRadius: 4)
        headingMarker.fillColor = SKColor.white
        headingMarker.position = CGPoint(x: 0, y: 18)
        positionMarker.addChild(headingMarker)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(deltaTime: TimeInterval) throws {
        guard let physicsBody = self.physicsBody else { return }

        let dT = deltaTime * Double(speed)
        localTime += dT

        // Reduce the heat according to dT
        heat = max(0, heat - CGFloat(dT) * Capsule.heatDissapationPerSecond)

        if onRails {
            let (position, speed) = try orbitalParameters.cartesianState(after: localTime)
            let referencePosition = Vector(reference.position)

            self.position = (position + referencePosition).cgPoint
            physicsBody.velocity = speed.cgVector
        } else {
            // Update the orbital parameters in order for the orbitalLine to get updated
            if !(orbitalParameters?.isHyperbolic ?? false) {
                updateOrbit()
            }

            // Calculate and apply the gravitational force
            let G: CGFloat = gravitationalConstant
            let m1 = physicsBody.mass
            guard let m2 = reference.physicsBody?.mass else { return }
            let pVec = Vector(position) - Vector(reference.position)
            let npVecNorm = pVec.normalized()
            let r = pVec.length
            let F = (G * m1 * m2) / pow(r, 2)
            let FVec = npVecNorm * -F
            physicsBody.applyForce(FVec.cgVector)

            // Calculate and apply the drag force
            let altitude = heightAboveTerrain
            let densityAtSeaLevel: CGFloat = Planet.atmosphereDensity
            let gravitationalAcceleration: CGFloat = Planet.gravitationalAcc
            let molarMassOfAir: CGFloat = Simulation.molarMassOfAir
            let universalGasConstant: CGFloat = Simulation.universalGasConstant
            let temperature: CGFloat = Simulation.averageAirTemperature
            let airDensity = densityAtSeaLevel * exp(-gravitationalAcceleration * molarMassOfAir * altitude / (universalGasConstant * temperature)) // Pa

            let referenceArea: CGFloat = 12.0 // m^2
            let dragCoefficient: CGFloat = 1.05
            let velocity = Vector(physicsBody.velocity)
            let dragForce = dragCoefficient / 2 * airDensity * pow(velocity.length, 2) * referenceArea
            let dragForceVector = dragForce * -velocity.normalized()
            physicsBody.applyForce(dragForceVector.cgVector)

            let dragAcceleration = dragForce / physicsBody.mass
            if dragAcceleration > highestAcceleration {
                highestAcceleration = dragAcceleration
            }

            // Spawn fire particles
            let burnRate = max(dragAcceleration - 30, 0) * max(1 - airDensity, 0)
            deorbitParticles.targetNode = parent
            deorbitParticles.particleBirthRate = burnRate * 100
            deorbitParticles.alpha = min(1, burnRate * 0.5 - 150)

            // Calculate heat
            let addedHeat = burnRate * speed
            let pointingVector = Vector(-1 * sin(zRotation), 1 * cos(zRotation), 0)
            let heatShieldAbsorptionPercentage = 1 - ((velocity.normalized() • pointingVector) + 1) / 2
            let heatShieldPart = heatShieldAbsorptionPercentage * addedHeat
            var remainingPart = addedHeat - heatShieldPart
            remainingHeatShield -= heatShieldPart

            // If the heat shield got depleted add the remaining heat back to the capsule
            if remainingHeatShield < 0.0 {
                remainingPart += abs(remainingHeatShield)
                remainingHeatShield = 0.0
            }
            
            heat += remainingPart

            // Disable the thruster when there is no burn time remaining
            if remainingBurnTime <= 0.0 {
                thrusterState = false
            }

            // Apply thruster force
            let rotation = self.zRotation
            let force = CGVector(dx: 0, dy: Capsule.thrust)
            let rotatedForce = CGVector(
                dx: force.dx * cos(rotation) - force.dy * sin(rotation),
                dy: force.dx * sin(rotation) + force.dy * cos(rotation)
            )

            if thrusterState {
                physicsBody.applyForce(rotatedForce)
                remainingBurnTime -= dT
                thrusterParticles1.particleBirthRate = 450
                thrusterParticles2.particleBirthRate = 450
            } else {
                thrusterParticles1.particleBirthRate = 0
                thrusterParticles2.particleBirthRate = 0
            }
        }

        redrawPosition()
    }

    func updateOrbit() {
        let planetPosition = Vector(reference.position)
        let entityPosition = Vector(position)

        let G = gravitationalConstant
        let mu = G * reference.bodyMass
        let eci = entityPosition - planetPosition
        let velocity = Vector(physicsBody!.velocity)

        localTime = 0
        orbitalParameters = OrbitalParameters(positionVector: eci, velocityVector: velocity, gravitationalConstant: mu)
    }

    func redrawOrbit() {
        guard !orbitalParameters.isHyperbolic else {
            orbitalLine.path = nil
            // TODO Hide the apo-/periapsis markers
            return
        }

        let (scale, translation, rotation, vp) = displayState

        // Fade out the orbit when zooming in
        let orbitAlpha = 1.0 - scale * 2
        orbitalLine.alpha = orbitAlpha
        apoapsisMarker.alpha = orbitAlpha
        periapsisMarker.alpha = orbitAlpha

        if orbitAlpha > 0.0 {
            // Update the apoapsis and periapsis markers
            apoapsisMarker.position = (orbitalParameters.apoapsis.position * scale + translation).cgPoint.rotated(by: rotation)
            periapsisMarker.position = (orbitalParameters.periapsis.position * scale + translation).cgPoint.rotated(by: rotation)

            // Orbit path that is in the viewport
            // (although the way of only drawing the visible portion is kinda crude ... sorry)
            let path = CGMutablePath()
            let points = orbitalParameters.orbitPath().map {
                CGPoint(x: $0.x * scale + translation.x, y: $0.y * scale + translation.y).rotated(by: rotation)
            }.filter { $0.isWithin(rect: vp, marginOfError: 5000.0) }
            path.addLines(between: points)
            orbitalLine.path = path
        }
    }

    func redrawPosition() {
        positionMarker.position = (Vector(position) * displayState.scale + displayState.translation).cgPoint.rotated(by: displayState.rotation)
        positionMarker.zRotation = zRotation + displayState.rotation
    }
}
