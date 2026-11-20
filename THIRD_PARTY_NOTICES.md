# Third-party notices

Mini Whisper ships the following third-party components and credits them in its Credits window, opened from About.

## WeSpeaker voice model

- **Component:** WeSpeaker ResNet34-LM speaker embedding model, bundled as `wespeaker_v2.mlmodelc`.
- **Authors:** the WeSpeaker authors (https://github.com/wenet-e2e/wespeaker); published by pyannote
  (https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM); converted to Core ML by Fluid Inference
  (https://huggingface.co/FluidInference/speaker-diarization-coreml).
- **Changes:** bundled as a modified Core ML conversion.
- **Licence:** Creative Commons Attribution 4.0 International (CC BY 4.0),
  https://creativecommons.org/licenses/by/4.0

## Sparkle

- **Component:** Sparkle, the update framework (https://sparkle-project.org).
- **Authors:** Andy Matuschak and the Sparkle contributors. It includes bsdiff (Colin Percival), sais-lite
  (Yuta Mori), a portable Ed25519 implementation (Orson Peters) and `SUSignatureVerifier.m` (Mark Hamlin), each under
  its own notice.
- **Licence:** MIT-style. The full text, with the external licences, is `App/Resources/Sparkle-LICENSE.txt`, copied
  verbatim from Sparkle's `LICENSE` and shipped inside the app.
