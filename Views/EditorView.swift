import SwiftUI
import PhotosUI
import UIKit

struct EditorView: View {
    @EnvironmentObject private var store: EditorStore
    @State private var photo: PhotosPickerItem?
    @State private var exportImage: UIImage?
    @State private var shareVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                canvas.aspectRatio(1, contentMode: .fit).padding(.horizontal, 12)
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Foto", systemImage: "photo.badge.plus")
                    }
                    Button { store.moveSelected(-1) } label: { Image(systemName: "arrow.down.to.line") }
                    Button { store.moveSelected(1) } label: { Image(systemName: "arrow.up.to.line") }
                    Button(role: .destructive) { store.deleteSelected() } label: { Image(systemName: "trash") }
                    Spacer()
                    Button {
                        exportImage = store.renderedImage()
                        shareVisible = true
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                if let id = store.selectedLayerID,
                   let layer = store.project.layers.first(where: { $0.id == id }) {
                    VStack(alignment: .leading) {
                        Text("Laag: \(layer.name)").font(.headline)
                        HStack {
                            Text("Grootte")
                            Slider(value: Binding(get: { layer.scale },
                                set: { v in store.update(id) { $0.scale = v } }), in: 0.1...3)
                        }
                        HStack {
                            Text("Dekking")
                            Slider(value: Binding(get: { layer.opacity },
                                set: { v in store.update(id) { $0.opacity = v } }), in: 0...1)
                        }
                        HStack {
                            Text("Rotatie")
                            Slider(value: Binding(get: { layer.rotation },
                                set: { v in store.update(id) { $0.rotation = v } }), in: -180...180)
                        }
                    }.padding(.horizontal)
                }

                List {
                    Section("Lagen") {
                        ForEach(Array(store.project.layers.reversed())) { layer in
                            HStack {
                                Image(systemName: layer.id == store.selectedLayerID ? "checkmark.circle.fill" : "square.on.square")
                                Text(layer.name)
                                Spacer()
                                Button {
                                    store.update(layer.id) { $0.isVisible.toggle() }
                                } label: {
                                    Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                                }.buttonStyle(.borderless)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { store.selectedLayerID = layer.id }
                        }
                    }
                }.listStyle(.insetGrouped)
            }
            .navigationTitle("ArtCraft Offline")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nieuw leeg project", role: .destructive) { store.newProject() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onChange(of: photo) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    store.addImage(data)
                }
            }
            .sheet(isPresented: $shareVisible) {
                if let image = exportImage { ShareSheet(items: [image]) }
            }
            .alert("Fout", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                ForEach(store.project.layers) { layer in
                    if layer.isVisible, let image = store.image(for: layer) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * 0.75, height: proxy.size.height * 0.75)
                            .scaleEffect(layer.scale)
                            .rotationEffect(.degrees(layer.rotation))
                            .opacity(layer.opacity)
                            .position(x: proxy.size.width * layer.x, y: proxy.size.height * layer.y)
                            .onTapGesture { store.selectedLayerID = layer.id }
                            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                                store.update(layer.id) { item in
                                    item.x = min(1, max(0, item.x + value.translation.width / max(proxy.size.width, 1) * 0.02))
                                    item.y = min(1, max(0, item.y + value.translation.height / max(proxy.size.height, 1) * 0.02))
                                }
                            })
                    }
                }
            }
            .clipped()
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.5)))
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
