//
//  OrbitalDynamics.swift
//  DragTests
//
//  Created by Til Blechschmidt on 17.03.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import CoreGraphics

enum OrbitError: Error {
    case hyperbolicOrbit
}

typealias CartesianState = (position: Vector, velocity: Vector)

struct OrbitalParameters {
    let semiMajorAxis: CGFloat               // a [m]
    let eccentricity: CGFloat                // e [1]
    let argumentOfPeriapsis: CGFloat         // ω [rad]
    let longitudeOfAscendingNode: CGFloat    // Ω [rad] - not needed for a 2D simulation but kept for future-proofing
    let inclination: CGFloat                 // i [rad]
    let meanAnomaly: CGFloat                 // M [rad]

    let standardGravitationalParameter: CGFloat  // μ

    var apoapsis: CartesianState {
        return cartesianState(atAnomaly: CGFloat.pi)
    }

    var periapsis: CartesianState {
        return cartesianState(atAnomaly: 0)
    }

    var apoapsisHeight: CGFloat {
        return semiMajorAxis * (1 + eccentricity)
    }

    var periapsisHeight: CGFloat {
        return semiMajorAxis * (1 - eccentricity)
    }

    var orbitalPeriod: TimeInterval {
        return Double(2 * CGFloat.pi * sqrt(pow(semiMajorAxis, 3) / standardGravitationalParameter))
    }

    var isHyperbolic: Bool {
        return eccentricity > 1
    }

    init(semiMajorAxis: CGFloat, eccentricity: CGFloat, gravitationalConstant μ: CGFloat) {
        // Set everything unrelated to 0
        self.argumentOfPeriapsis = 0.0
        self.longitudeOfAscendingNode = 0.0
        self.inclination = 0.0
        self.meanAnomaly = CGFloat.pi

        // Initialize with parameters
        self.semiMajorAxis = semiMajorAxis
        self.eccentricity = eccentricity
        self.standardGravitationalParameter = μ
    }

    init(positionVector r: Vector, velocityVector ṙ: Vector, gravitationalConstant μ: CGFloat) {
        // Orbital momentum
        let h = r * ṙ

        // Eccentricity vector
        let e = (ṙ * h / μ) - r / r.length

        // Vector pointing towards the ascending node
        let n = [0, 0, 1] * h

        // True anomaly
        let v: CGFloat
        if r • ṙ >= 0.0 {
            v = acos((e • r) / (e.length * r.length))
        } else {
            v = 2 * CGFloat.pi - acos((e • r) / (e.length * r.length))
        }

        // Orbital inclination
        let i = acos(h.z / h.length)

        // Orbit eccentricity
        let ec = e.length

        // Eccentric anomaly
        let E = 2 * atan(
            tan(v / 2) / sqrt((1 + ec) / (1 - ec))
        )

        // Longitude of the ascending node
        let Ω: CGFloat
        if i == 0.0 || i == CGFloat.pi {
            Ω = 0 // Zero by convention for non-inclined orbits
        } else if n.y >= 0 {
            Ω = acos(n.x / n.length)
        } else {
            Ω = 2 * CGFloat.pi - acos(n.x / n.length)
        }

        // Argument of the periapsis
        let ω: CGFloat
        if ec == 0.0 {
            ω = 0 // Zero for elliptic orbits
        } else if (r * ṙ).z >= 0 {
            ω = atan2(e.y, e.x)
        } else {
            ω = 2 * CGFloat.pi - atan2(e.y, e.x)
        }

        // Mean anomaly
        let M = E - ec * sin(E)

        // Semi-major axis
        let a = 1 / (
            2 / r.length - pow(ṙ.length, 2) / μ
        )

        self.semiMajorAxis = a
        self.eccentricity = ec
        self.argumentOfPeriapsis = ω
        self.longitudeOfAscendingNode = Ω
        self.inclination = i
        self.meanAnomaly = M
        self.standardGravitationalParameter = μ
    }

    func eccentricAnomaly(after interval: TimeInterval) throws -> CGFloat {
        if isHyperbolic {
            throw OrbitError.hyperbolicOrbit
        }

        // Few redeclarations for readability
        let μ = standardGravitationalParameter
        let e = eccentricity
        let M0 = meanAnomaly

        // Mean anomaly after interval
        let M: CGFloat
        if interval == 0 {
            M = M0
        } else {
            M = M0 + CGFloat(interval) * sqrt(μ / pow(semiMajorAxis, 3))
        }

        // Solve for eccentric anomaly E(t) with Newton-Raphson method
        var E = M
        while true {
            let dE = (E - e * sin(E) - M) / (1 - e * cos(E))
            E -= dE
            if abs(dE) < 1e-6 { break }
        }

        return E
    }

    func cartesianState(atAnomaly eccentricAnomaly: CGFloat) -> CartesianState {
        // Few redeclarations for readability
        let a = semiMajorAxis
        let e = eccentricity
        let μ = standardGravitationalParameter
        let i = inclination
        let ω = argumentOfPeriapsis
        let Ω = longitudeOfAscendingNode

        // Eccentric anomaly
        let E = eccentricAnomaly

        // True anomaly
        let v = 2 * atan2(
            sqrt(1 + e) * sin(E / 2),
            sqrt(1 - e) * cos(E / 2)
        )

        // Distance to central body
        let rc = a * (1 - e * cos(E))

        // Position vector
        let o = rc * Vector(cos(v), sin(v), 0)

        // Velocity vector
        let ȯ = (sqrt(μ * a) / rc) * Vector(-sin(E), sqrt(1 - pow(e, 2)) * cos(E), 0)

        // Rotate position and velocity vectors
        func rotate(vector v: Vector) -> Vector {
            return Vector(
                v.x * (cos(ω) * cos(Ω) - sin(ω) * cos(i) * sin(Ω)) - v.y * (sin(ω) * cos(Ω) + cos(ω) * cos(i) * sin(Ω)),
                v.x * (cos(ω) * sin(Ω) + sin(ω) * cos(i) * cos(Ω)) + v.y * (cos(ω) * cos(i) * cos(Ω) - sin(ω) * sin(Ω)),
                v.x * (sin(ω) * sin(i)) + v.y * (cos(ω) * sin(i))
            )
        }

        let r = rotate(vector: o)
        let ṙ = rotate(vector: ȯ)

        // Return the cartesian state vectors
        return (position: r, velocity: ṙ)
    }

    func cartesianState(after interval: TimeInterval) throws -> CartesianState {
        return cartesianState(atAnomaly: try eccentricAnomaly(after: interval))
    }

    func orbitPath() -> [CGPoint] {
        let stepSize: CGFloat = 0.001
        var eccentricAnomaly: CGFloat = 0.0
        var points: [CGPoint] = []

        while eccentricAnomaly < 2 * CGFloat.pi {
            let (position, _) = cartesianState(atAnomaly: eccentricAnomaly)
            points.append(CGPoint(x: position.x, y: position.y))

            eccentricAnomaly += stepSize
        }

        return points
    }

    func orbitPath(atScale scale: CGFloat, translation: CGVector) -> CGPath {
        let path = CGMutablePath()
        let points = orbitPath().map { CGPoint(x: $0.x * scale + translation.dx, y: $0.y * scale + translation.dy) }
        path.addLines(between: points)
        path.closeSubpath()

        return path
    }
}
