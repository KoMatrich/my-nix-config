# Local OCR Design

## Intent

Give text-only OpenCode models explicit last-resort tools for extracting text from local images and PDFs. All inference and document processing must stay on BLACK-BOX; files must never be uploaded to an OCR API.

## Goals

- Install PaddleOCR-VL-1.6 (Apache-2.0, 0.9B, revision `132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd`) for image-to-text extraction.
- Expose separate `ocr_image` and `ocr_pdf` OpenCode tools accepting local paths.
- Run inference on demand on CPU, with no daemon and no model kept resident.
- Preserve PDF page boundaries and an optional 1-indexed page range.
- Use a PDF text layer when usable; OCR only selected pages needing it.
- Cache model weights under persistent `/home` and support offline reuse.

## Non-goals

- Do not automatically OCR every attachment or invoke OCR when the current model can read images itself.
- Do not add image description, VQA, hosted inference, GPU inference, or document-editing features.
- Do not change existing Ollama models or other OpenCode provider settings.

## Constraints

- BLACK-BOX has 4 GB VRAM, so OCR must not contend with Ollama for GPU memory.
- The first model load downloads approximately 1.9 GB; later loads use the pinned local snapshot.
- Temporary rendered PDF pages must be deleted after each invocation.
- OpenCode integration is global through `~/.config/opencode/plugins/`; restart OpenCode after activation.

## Approaches

1. **PaddleOCR-VL-1.6 plus direct Transformers inference (selected).** Best documented local accuracy for this use case, unrestricted Apache-2.0 weights, CPU-capable, and no competing service is needed.
2. **Surya 2.5 through llama.cpp.** Easier serving and strong OCR, but more restrictive model licensing and lower reported olmOCR-bench accuracy.
3. **dots.mocr.** Strong broader capabilities, but its 3B setup is a poor fit for the 4 GB GPU.

For PDFs, Poppler handles native text and scanned-page rendering. Reusing the same OCR model avoids installing the much larger full PaddleOCR document-serving stack while still supporting both requested input types.

## Implementation decisions

- Add `pkgs/local-ocr/` with a small Python CLI, unit tests, Nix package, and legacy OpenCode plugin compatible with the installed OpenCode 1.19.x API.
- Install `local-ocr` and the generated global plugin declaratively through Home Manager.
- The plugin invokes an absolute store path with `execFile`, never through a shell, and its tool descriptions explicitly say last resort only.
- Verify pure parsing/PDF decisions with unit tests, then test actual image OCR, native-text PDF extraction, scanned PDF OCR, Czech characters, and offline model reuse before building and switching BLACK-BOX.
