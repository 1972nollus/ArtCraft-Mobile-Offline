# ArtCraft Mobile Offline

Zelfstandige offline iPhone-foto-editor (SwiftUI, iOS 17+).

## Huidige functies
- Foto's importeren, lagen, draaien, schalen en exporteren
- Promptveld voor toekomstige AI-fotobewerking
- Instellingen voor lokale modeldownloads met voortgang
- Lokale opslag van Core ML modelarchieven

## Nog niet geïmplementeerd
- Werkelijke Core ML Stable Diffusion inferentie
- Image-to-image en inpainting
- Installatie/uitpakken en validatie van Core ML ZIP-pipelines
- Een geverifieerde catalogus van compatibele modellen (inclusief NSFW-modellen)

Dit prototype voert nog **geen** AI-fotoaanpassingen uit. De promptknop laat dat expliciet zien. Een .gguf of losse .safetensors is geen compatibele Core ML Stable Diffusion-pipeline.

## Build
Open Actions > Build iOS IPA > Run workflow. Download daarna het unsigned IPA-artifact en onderteken het via een eigen iOS signing-methode. Buildstatus moet in GitHub Actions gecontroleerd worden.

De modeldownloadmanager bewaart bestanden in Documents/CoreMLModels en gebruikt uitsluitend HTTPS. Een download impliceert geen werkende modelintegratie. Lange downloads kunnen bij opschorten van de app onderbroken worden.
