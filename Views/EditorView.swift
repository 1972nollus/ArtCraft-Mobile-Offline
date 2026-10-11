import SwiftUI
import PhotosUI
import UIKit

struct EditorView: View {
    @EnvironmentObject private var store: EditorStore
    @State private var photo: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var confirmPhoto = false
    @State private var fullscreenCanvas = false
    @State private var originalForComparison: UIImage?
    @State private var exportImage: UIImage?
    @State private var shareVisible = false
    @State private var prompt = ""
    @AppStorage("editorMode") private var editorMode = "Nieuw beeld"
    @State private var editStrength = 0.2
    @State private var sceneStrength = 0.65
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
                if let generated = engine.generatedImage {
                    VStack(spacing: 12) {
                        if let original = originalForComparison {
                            BeforeAfterCompareView(original: original, generated: generated)
                                .padding(.horizontal, 6)
                        } else {
                            Image(uiImage: generated)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .padding(.horizontal, 6)
                        }
                        HStack(spacing: 8) {
                            Button("Annuleer") {
                                engine.generatedImage = nil
                                originalForComparison = nil
                            }.buttonStyle(.bordered)
                            Button("Opnieuw") { startGeneration() }
                                .buttonStyle(.bordered)
                                .disabled(engine.isGenerating)
                            Button("Gebruik resultaat") {
                                if let data = generated.pngData(),
                                   store.replaceSelectedImage(with: data) {
                                    engine.generatedImage = nil
                                    originalForComparison = nil
                                }
                            }.buttonStyle(.borderedProminent)
                        }.font(.subheadline)
                    }
                } else {
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
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bewerkmodus").font(.headline)
                    Picker("Bewerkmodus", selection: $editorMode) {
                        Text("Nieuw beeld").tag("Nieuw beeld")
                        Text("Subtiel aanpassen").tag("Subtiel aanpassen")
                        Text("Gebied bewerken (Inpaint)").tag("Inpaint")
                        Text("Nieuwe scène").tag("Nieuwe scène")
                    }.pickerStyle(.menu)
                    .onChange(of: editorMode) { _, _ in
                        engine.generatedImage = nil
                        originalForComparison = nil
                    }
                }.padding(.horizontal)
                HStack(spacing: 8) {
                    TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                        .focused($promptFocused).submitLabel(.done)
                        .onSubmit { promptFocused = false }
                    Button(engine.isGenerating ? "Bezig..." : "AI genereren") { startGeneration() }
                        .buttonStyle(.borderedProminent)
                        .disabled(engine.isGenerating || editorMode == "Inpaint" || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal)
                if editorMode == "Subtiel aanpassen" && !store.project.layers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Aanpassingssterkte")
                            Slider(value: $editStrength, in: 0.1...0.5, step: 0.05)
                            Text("\(Int(editStrength * 100))%").monospacedDigit()
                        }
                        Text("Lager verandert minder van het origineel. Gezichtsbehoud is niet gegarandeerd.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal)
                } else if editorMode == "Nieuwe scène" {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Scènewijziging")
                            Slider(value: $sceneStrength, in: 0.3...0.9, step: 0.05)
                            Text("\(Int(sceneStrength * 100))%").monospacedDigit()
                        }
                        Text("Experimenteel: je gezicht kan veranderen. Echt identiteitsbehoud vraagt een face-reference-model.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal)
                } else if editorMode == "Inpaint" {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Maskerbewerking is nog in ontwikkeling", systemImage: "paintbrush.pointed")
                        Text("Het penseel en lokaal genereren volgen later. De AI-knop is in deze modus uitgeschakeld.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal)
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
                if !store.project.layers.isEmpty && editorMode != "Nieuw beeld" && editorMode != "Inpaint" {
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
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Kies foto", systemImage: "photo.badge.plus")
                    }
                    if store.project.layers.count > 1 {
                    Button { store.moveSelected(-1) } label: { Image(systemName: "arrow.down.to.line") }
                    Button { store.moveSelected(1) } label: { Image(systemName: "arrow.up.to.line") }
                    }
                    Button(role: .destructive) { store.deleteSelected() } label: { Image(systemName: "trash") }
                    Spacer()
                    Button {
                        exportImage = store.renderedImage()
                        shareVisible = true
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                if engine.generatedImage == nil && store.project.layers.count > 1 {
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

    private func startGeneration() {
        dismissKeyboard()
        let original = selectedUIImage()
        guard editorMode == "Nieuw beeld" || original != nil else {
            store.errorMessage = "Kies eerst een bestaande foto voor image-to-image."
            return
        }
        originalForComparison = original
        Task {
            await engine.generate(prompt: effectivePrompt,
                                  startingImage: editorMode == "Nieuw beeld" ? nil : selectedInputImage(),
                                  strength: editorMode == "Nieuwe scène" ? sceneStrength : editStrength)
        }
    }

    private func selectedUIImage() -> UIImage? {
        guard let layer = store.project.layers.first(where: { $0.id == store.selectedLayerID })
                ?? store.project.layers.last else { return nil }
        return store.image(for: layer)
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

    private var promptPlaceholder: String {
        switch editorMode {
        case "Subtiel aanpassen": return "Bijvoorbeeld: maak alleen het haar blond"
        case "Inpaint": return "Bijvoorbeeld: voeg hier een zonnebril toe"
        case "Nieuwe scène": return "Bijvoorbeeld: zet deze persoon op het strand"
        default: return "Beschrijf een nieuwe afbeelding…"
        }
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
        if editorMode == "Subtiel aanpassen" { parts.append("Edit the existing photo of the same subject. Only the requested small change; keep pose, clothes, background.") }
        if editorMode == "Nieuwe scène" { parts.append("Place the person from the reference photo into the described scene. Try to preserve facial identity.") }
        if editorMode != "Nieuw beeld" && !store.project.layers.isEmpty {
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
