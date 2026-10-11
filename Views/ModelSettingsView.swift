import SwiftUI

struct ModelSettingsView: View {
    @StateObject private var models = ModelDownloadStore()

    var body: some View {
        Form {
            Section("Modelcatalogus") {
                ForEach(ModelPreset.all) { preset in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preset.title).font(.headline)
                        Text(preset.note).font(.caption).foregroundStyle(.secondary)
                        Button("Selecteer download") { models.usePreset(preset) }
                    }
                }
            }
            Section("Lokale beeldmodellen") {
                Text("Alle modellen worden op je iPhone opgeslagen. Internet is alleen nodig om ze te downloaden.")
                    .font(.footnote)
                TextField("Directe HTTPS-link naar Core ML-model", text: $models.urlText)
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
                if !models.status.isEmpty { Text(models.status).font(.footnote) }
            }
            Section("Gedownloade bestanden") {
                if models.models.isEmpty {
                    Text("Nog geen Core ML-modelbestanden.").foregroundStyle(.secondary)
                }
                ForEach(models.models, id: \.self) { name in
                    HStack {
                        Image(systemName: "externaldrive")
                        Text(name).lineLimit(2)
                        Spacer()
                        Button(role: .destructive) { models.delete(name) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Modelcontrole") {
                Button("Controleer huidige Core ML Resources") {
                    let folder = models.modelDirectory.appendingPathComponent("Resources", isDirectory: true)
                    models.status = CoreMLModelValidator.check(folder).details
                }
                Text("Een gewone Unet zonder chunking wordt als risicovol voor iPhone gemarkeerd. Deze controle garandeert geen succesvolle generatie.")
                    .font(.footnote)
            }
            Section("Compatibiliteit") {
                Text("Voor beeldgeneratie is een volledige Core ML Stable Diffusion-pipeline nodig. Een ZIP downloaden betekent niet dat het model al geladen kan worden. GGUF-taalmodellen en losse .safetensors-checkpoints werken niet in deze Core ML-engine.")
                    .font(.footnote)
                Text("NSFW-capabele Stable Diffusion-modellen kunnen later worden toegevoegd als compatibele geconverteerde Core ML-pipeline. De app biedt momenteel geen geteste NSFW-modelcatalogus.")
                    .font(.footnote)
            }
        }
        .navigationTitle("AI-modellen")
        .onAppear { models.scan() }
    }
}
