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


## Core ML-generatie (experimenteel)
De StableDiffusion Swift-package van Apple is toegevoegd via XcodeGen. De promptknop probeert nu **tekst-naar-afbeelding** te genereren en kan het resultaat als laag invoegen.

Vereist: een compleet gecompileerd Core ML **Stable Diffusion v1.x Resources**-pakket met TextEncoder.mlmodelc, VAEDecoder.mlmodelc, UnetChunk1+2.mlmodelc (of Unet.mlmodelc) en tokenizerbestanden. Een rechtstreeks downloadbaar ZIP-archief mag deze Resources-map bevatten; de modelmanager pakt ZIP-bestanden uit.

**Niet ondersteund in deze fase:** image-to-image en inpainting, losse GGUF of safetensors, en niet-gecompileerde .mlpackage modellen. Modellicenties en herkomst vooraf controleren. Op iPhone 14 bestaat reëel risico op geheugentekort.

Start een nieuwe GitHub Actions-build om de nieuwe Swift-packageintegratie te valideren; build en uitvoering op een iPhone zijn nog niet bevestigd.
