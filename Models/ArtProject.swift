import Foundation
struct ArtLayer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var fileName: String
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 1
    var rotation: Double = 0
    var opacity: Double = 1
    var isVisible: Bool = true
}
struct ArtProject: Codable {
    var name = "Nieuw project"
    var canvasWidth = 1024
    var canvasHeight = 1024
    var layers: [ArtLayer] = []
}
