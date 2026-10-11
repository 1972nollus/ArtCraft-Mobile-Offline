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
file.chmod(file.stat().st_mode | 0o200)
file.write_text(source)
print(f"Patched Apple VAE encoder RGB input selection: {file}")
