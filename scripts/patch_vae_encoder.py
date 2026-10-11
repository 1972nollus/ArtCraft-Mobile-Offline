#!/usr/bin/env python3
"""Fix Apple StableDiffusion Encoder choosing a scalar instead of RGB model input.

The stock Encoder.inputDescription uses the first entry in the Core ML input
dictionary. Some converted VAEs expose [1,1] conditioning input first.
The encoder must select the [1,3,H,W] planar RGB input.
Fail loudly when upstream source changes rather than silently shipping an
unpatched app.
"""
from pathlib import Path
import sys

roots = list(Path("build/SourcePackages/checkouts").glob("ml-stable-diffusion/swift/StableDiffusion/pipeline/Encoder.swift"))
if len(roots) != 1:
    sys.exit(f"Cannot find Apple Encoder.swift in resolved packages: {roots}")
file = roots[0]
source = file.read_text()
old = "model.modelDescription.inputDescriptionsByName.first!.value"
new = """model.modelDescription.inputDescriptionsByName.values.first(where: { description in
                guard let shape = description.multiArrayConstraint?.shape.map({ $0.intValue }) else {
                    return false
                }
                return shape.count == 4 && shape[0] == 1 && shape[1] == 3 &&
                       shape[2] > 0 && shape[3] > 0
            })!"""
if old not in source:
    sys.exit("Upstream Encoder.inputDescription changed; manual review required")
source = source.replace(old, new, 1)

# Some Core ML VAE conversions require an auxiliary 'noise' input. Provide a
# zero-filled tensor of exactly the declared shape and dtype, so Core ML does
# not reject prediction with "Feature noise is required but not specified".
old_provider = "let dict = [inputName: MLMultiArray(imageData)]"
new_provider = """var dict: [String: MLMultiArray] = [inputName: MLMultiArray(imageData)]
        try model.perform { loadedModel in
            // These inputs are required by certain Core ML VAE conversions.
            // With a zero-valued noise tensor and noise coefficient, the
            // encoder follows a deterministic no-extra-noise path.
            for (name, feature) in loadedModel.modelDescription.inputDescriptionsByName {
                guard name != inputName else { continue }
                guard let constraint = feature.multiArrayConstraint else {
                    throw NSError(domain: "ArtCraftVAE", code: 301,
                                  userInfo: [NSLocalizedDescriptionKey: "VAE auxiliary input has unsupported type: " + name])
                }
                let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
                // Diffusion coefficients: preserve the encoded image without
                // injecting additional diffusion noise at this stage.
                let value: Double = name == "sqrt_alphas_cumprod" ? 1.0 : 0.0
                for index in 0..<array.count { array[index] = NSNumber(value: value) }
                dict[name] = array
            }
        }"""
if old_provider not in source:
    sys.exit("Upstream Encoder feature provider changed; manual review required")
source = source.replace(old_provider, new_provider, 1)
file.chmod(file.stat().st_mode | 0o200)
file.write_text(source)
print(f"Patched Apple VAE encoder RGB input selection: {file}")
