//
//  AsyncImage.swift
//
//
//  Created by Mario Heubach on 17.04.24.
//

import SwiftUI
import Combine
import ImageTools

class ViewModel: ObservableObject {
    @Published var image: NSImage?
    private var cancellables: Set<AnyCancellable> = []

    func loadImage(url: URL, maxDimension: CGFloat) {
        ImageCache.shared.imagePublisher(for: url, maxDimension: maxDimension)
            .receive(on: RunLoop.main) // Stellt sicher, dass das UI auf dem Hauptthread aktualisiert wird
            .sink(receiveValue: { [weak self] in self?.image = $0 })
            .store(in: &cancellables)
    }
}
