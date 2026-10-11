import SwiftUI
import UniformTypeIdentifiers

struct ModelSettingsView: View {
    @EnvironmentObject private var models: ModelDownloadStore
    @State private var choosingLocalFile = false
    @AppStorage("showAdultModels") private var showAdultModels = false
    @State private var compatibilityExpanded = false

    var body: some View {
        Form {
            Section("Volwassen modellen (NSFW)") {
                Toggle("Toon NSFW-modellen", isOn: $showAdultModels)
                Text("Toont volwassen modellen in de catalogus. Dit is geen inhoudsfilter voor gegenereerde afbeeldingen.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Modelcatalogus") {
                if showAdultModels {
                ForEach(ModelPreset.all) { preset in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preset.title).font(.headline)
                        Text(preset.note).font(.caption).foregroundStyle(.secondary)
                        Button("Selecteer download") { models.usePreset(preset) }
                    }
                }
                }
                if !showAdultModels { Text("Schakel NSFW-modellen in om Realistic Vision, Deliberate v2 en ReV Animated te tonen.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Model downloaden") {
                TextField("Directe HTTPS-link naar Core ML ZIP", text: $models.urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if models.downloading {
                    ProgressView(value: models.progress)
                    Button("Annuleer download", role: .destructive) { models.cancel() }
                } else {
                    Button("Download model") { models.download() }
                        .disabled(models.urlText.isEmpty)
                }
                Text("Downloads kunnen op de achtergrond doorgaan zolang iOS de transfer toestaat.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Lokaal model importeren") {
                Button {
                    choosingLocalFile = true
                } label: {
                    Label("Kies lokaal bestand", systemImage: "folder")
                }
                Text("Gebruik een eerder opgeslagen Core ML ZIP of Resources-map. Opnieuw downloaden is niet nodig.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !models.status.isEmpty {
                Section("Status") {
                    Text(models.status).font(.footnote)
                }
            }
            Section("Gedownloade bestanden") {
                if models.models.isEmpty {
                    Text("Nog geen Core ML-modelbestanden.").foregroundStyle(.secondary)
                }
                ForEach(models.models, id: \.self) { name in
                    HStack {
                        Image(systemName: "externaldrive")
                        VStack(alignment: .leading) {
                            Text(name).lineLimit(2)
                            Text(models.validation(name)).font(.caption2).foregroundStyle(.secondary)
                            Button(models.selectedModel == name ? "Actief model" : "Gebruik model") { models.activate(name) }
                                .disabled(models.selectedModel == name)
                        }
                        Spacer()
                        Button(role: .destructive) { models.delete(name) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Modelcontrole") {
                Button("Controleer huidige Core ML Resources") {
                    if !models.selectedModel.isEmpty { models.status = models.validation(models.selectedModel) } else { models.status = "Selecteer eerst een geïnstalleerd model." }
                }
                Text("Een gewone Unet zonder chunking wordt als risicovol voor iPhone gemarkeerd. Deze controle garandeert geen succesvolle generatie.")
                    .font(.footnote)
            }
            Section {
                DisclosureGroup("Compatibiliteit", isExpanded: $compatibilityExpanded) {
                Text("Voor beeldgeneratie is een volledige Core ML Stable Diffusion-pipeline nodig. Een ZIP downloaden betekent niet dat het model al geladen kan worden. GGUF-taalmodellen en losse .safetensors-checkpoints werken niet in deze Core ML-engine.")
                    .font(.footnote)
                Text("Realistic Vision v2.0, Deliberate v2 en ReV Animated zijn Core ML-modelpresets. De modellen zijn niet allemaal op deze iPhone getest. De NSFW-schakelaar bepaalt alleen welke presets zichtbaar zijn; het is geen inhoudsfilter.")
                    .font(.footnote)
                }
            }
        }
        .navigationTitle("AI-modellen")
        .onAppear { models.scan() }
        .fileImporter(isPresented: $choosingLocalFile, allowedContentTypes: [.zip, .folder]) { result in
            switch result {
            case .success(let url):
                models.importLocal(from: url)
            case .failure(let error):
                models.status = "Bestandskiezer: " + error.localizedDescription
            }
        }
    }
}
