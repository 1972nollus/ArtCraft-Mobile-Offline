import SwiftUI
import PhotosUI
import UIKit

struct EditorView: View {
    @EnvironmentObject private var store: EditorStore
    @State private var photo: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var confirmPhoto = false
    @State private var fullscreenCanvas = false
    @State private var exportImage: UIImage?
    @State private var shareVisible = false
    @State private var prompt = ""
    @State private var editExistingPhoto = false
    @State private var editStrength = 0.4
    @AppStorage("generationStyle") private var generationStyle = "Realistisch"
    @AppStorage("preserveFace") private var preserveFace = true
    @AppStorage("preserveExpression") private var preserveExpression = true
    @FocusState private var promptFocused: Bool
    @StateObject private var engine = StableDiffusionEngine()
    @State private var showModelInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    canvas
                        .frame(width: UIScreen.main.bounds.width - 12,
                               height: UIScreen.main.bounds.width - 12)
                        .background(Color.white)
                        .onTapGesture { dismissKeyboard() }
                    Button {
                        dismissKeyboard()
                        fullscreenCanvas = true
                    } label: {
                        Label("Vergroot", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                            .padding(11)
                            .background(.black.opacity(0.7), in: Circle())
                    }
                    .accessibilityLabel("Foto schermvullend bekijken")
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    TextField("Beschrijf hoe je de foto wilt aanpassen...", text: $prompt, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($promptFocused)
                        .submitLabel(.done)
                        .onSubmit { promptFocused = false }
                    Button(engine.isGenerating ? "Bezig..." : "AI genereren") {
                        dismissKeyboard()
                        Task {
                            let source = editExistingPhoto ? selectedInputImage() : nil
                            await engine.generate(prompt: effectivePrompt, startingImage: source, strength: editStrength)
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(engine.isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal)
                if !store.project.layers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Bewerk bestaande foto (image-to-image)", isOn: $editExistingPhoto)
                        if editExistingPhoto {
                            HStack {
                                Text("Aanpassingssterkte")
                                Slider(value: $editStrength, in: 0.1...0.9, step: 0.05)
                                Text("\(Int(editStrength * 100))%").monospacedDigit()
                            }
                            Text("Lager behoudt doorgaans meer van de bronfoto. Gezichtsbehoud is niet gegarandeerd.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                HStack(spacing: 12) {
                    Picker("Stijl", selection: $generationStyle) {
                        Text("Standaard").tag("Standaard")
                        Text("Realistisch").tag("Realistisch")
                        Text("Illustratie").tag("Illustratie")
                        Text("Cinematisch").tag("Cinematisch")
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding(.horizontal)
                if !store.project.layers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Behoud gezicht", isOn: $preserveFace)
                        Toggle("Behoud gezichtsuitdrukking", isOn: $preserveExpression)
                        Text("Promptsturing; met image-to-image gebruikt de app ook de geselecteerde foto. Identiteit en expressie zijn niet gegarandeerd.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                if engine.isGenerating {
                    VStack(alignment: .leading, spacing: 6) {
                        if engine.currentStep > 0 {
                            ProgressView(value: engine.progress)
                            HStack {
                                Text("Stap \(engine.currentStep) van \(engine.totalSteps) · \(Int(engine.progress * 100))%")
                                Spacer()
                                Text("Verstreken: \(Int(engine.elapsedSeconds)) sec")
                            }
                            .font(.caption)
                            if let remaining = engine.remainingSeconds {
                                Text("Nog ongeveer \(Int(remaining.rounded())) sec")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ProgressView("Model laden / voorbereiding…")
                        }
                    }
                    .padding(.horizontal)
                }
                if !engine.message.isEmpty {
                    Text(engine.message).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(3).padding(.horizontal)
                }
                if let generated = engine.generatedImage {
                    VStack(spacing: 10) {
                        Text("AI-resultaat").font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(uiImage: generated)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button("Voeg toe als laag") {
                            if let data = generated.pngData() {
                                store.addGeneratedImage(data)
                                engine.generatedImage = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }.padding(.horizontal)
                }
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Kies foto", systemImage: "photo.badge.plus")
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lagen").font(.headline)
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
                }.padding(.horizontal)
              }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { dismissKeyboard() })
            .navigationTitle("ArtCraft Offline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: ModelSettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nieuw leeg project", role: .destructive) { store.newProject() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .alert("AI-engine nog niet actief", isPresented: $showModelInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("De prompt is klaar voor de Core ML image-to-image-integratie. In Instellingen kun je alvast modellen downloaden. De huidige versie bewerkt nog geen foto's met AI.")
            }
            .onChange(of: photo) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    await MainActor.run {
                        pendingPhoto = UIImage(data: data)
                        confirmPhoto = pendingPhoto != nil
                        dismissKeyboard()
                    }
                }
            }
            .fullScreenCover(isPresented: $fullscreenCanvas) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    GeometryReader { geometry in
                        canvas
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Button("Sluiten", systemImage: "xmark") { fullscreenCanvas = false }
                        .labelStyle(.iconOnly)
                        .padding()
                        .background(.ultraThinMaterial, in: Circle())
                        .padding()
                }
            }
            .sheet(isPresented: $confirmPhoto) {
                NavigationStack {
                    VStack(spacing: 18) {
                        if let pendingPhoto {
                            Image(uiImage: pendingPhoto)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 430)
                        }
                        Button("Gebruik deze foto") {
                            if let data = pendingPhoto?.pngData() { store.addImage(data) }
                            pendingPhoto = nil
                            photo = nil
                            confirmPhoto = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Foto kiezen")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Annuleer") {
                                pendingPhoto = nil
                                photo = nil
                                confirmPhoto = false
                            }
                        }
                    }
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

    private func dismissKeyboard() {
        promptFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func selectedInputImage() -> CGImage? {
        guard let layer = store.project.layers.first(where: { $0.id == store.selectedLayerID })
                ?? store.project.layers.last,
              let image = store.image(for: layer) else { return nil }
        let target = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: target)
        let normalized = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            let ratio = min(target.width / max(image.size.width, 1),
                            target.height / max(image.size.height, 1))
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (target.width - size.width) / 2,
                                  y: (target.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        return normalized.cgImage
    }

    private var effectivePrompt: String {
        var parts = [prompt.trimmingCharacters(in: .whitespacesAndNewlines)]
        switch generationStyle {
        case "Realistisch":
            parts.append("photorealistic photograph, natural lighting, lifelike textures, realistic skin details, natural proportions")
        case "Illustratie":
            parts.append("illustration, artistic rendering, cohesive colors")
        case "Cinematisch":
            parts.append("cinematic lighting, detailed composition, film still")
        default: break
        }
        if !store.project.layers.isEmpty {
            if preserveFace { parts.append("keep the same facial identity, preserve facial features") }
            if preserveExpression { parts.append("maintain the same facial expression") }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
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
                            .frame(width: proxy.size.width, height: proxy.size.height)
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
