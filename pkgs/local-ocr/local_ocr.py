"""On-demand local OCR for images and native/scanned PDFs."""

import argparse
import os
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

MODEL_REPO = "PaddlePaddle/PaddleOCR-VL-1.6"
MODEL_REVISION = "132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd"
# Keep this manifest in sync when changing MODEL_REVISION. local_files_only
# can return an existing but incomplete snapshot, so file presence matters.
MODEL_SNAPSHOT_FILES = frozenset({
    ".eval_results/real5_omnidocbench.yaml",
    ".gitattributes",
    "LICENSE",
    "README.md",
    "added_tokens.json",
    "chat_template.jinja",
    "config.json",
    "configuration_paddleocr_vl.py",
    "generation_config.json",
    "image_processing_paddleocr_vl.py",
    "inference.yml",
    "model.safetensors",
    "modeling_paddleocr_vl.py",
    "preprocessor_config.json",
    "processing_paddleocr_vl.py",
    "processor_config.json",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer.model",
    "tokenizer_config.json",
})
MAX_NEW_TOKENS = 4096


class UserError(Exception):
    """An input or dependency error suitable for concise CLI output."""


def handle_sigterm(signum, _frame):
    """Turn termination into normal stack unwinding and temporary-file cleanup."""
    raise SystemExit(128 + signum)


def parse_page_spec(spec, total_pages):
    """Return unique 1-indexed pages in request order, defaulting to all pages."""
    if total_pages < 1:
        raise ValueError("The PDF has no pages")
    if spec is None:
        return list(range(1, total_pages + 1))

    pages = []
    seen = set()
    for raw_part in spec.split(","):
        part = raw_part.strip()
        match = re.fullmatch(r"(\d+)(?:\s*-\s*(\d+))?", part)
        if not match:
            raise ValueError(f"Invalid page range: {raw_part!r}")
        first = int(match.group(1))
        last = int(match.group(2) or first)
        if first < 1 or last < first or last > total_pages:
            raise ValueError(f"Page range must be within 1-{total_pages}: {raw_part!r}")
        for page in range(first, last + 1):
            if page not in seen:
                pages.append(page)
                seen.add(page)
    if not pages:
        raise ValueError("No pages selected")
    return pages


def split_pdf_text(raw, expected_pages):
    """Split pdftotext form-feed output without losing blank pages."""
    parts = raw.split("\f")
    if parts and not parts[-1].strip():
        parts.pop()
    if len(parts) != expected_pages:
        raise ValueError(
            f"Poppler returned {len(parts)} page text blocks; expected {expected_pages}"
        )
    return [part.strip("\r\n") for part in parts]


def pages_needing_ocr(page_texts, raster_pages=None):
    """Return pages with no native text or with raster regions needing OCR."""
    raster_pages = raster_pages or ()
    return [
        index
        for index, text in enumerate(page_texts)
        if index in raster_pages or not any(character.isalnum() for character in text)
    ]


def merge_ocr_text(native_text, ocr_text):
    """Keep native text when full-page OCR supplements image-region text."""
    if any(character.isalnum() for character in native_text):
        return (
            f"{native_text.strip()}\n\n"
            "Additional OCR output (may repeat native text):\n"
            f"{ocr_text.strip() or '[No text detected]'}"
        )
    return ocr_text.strip()


def run_command(arguments):
    """Run a local document utility without a shell."""
    try:
        return subprocess.run(
            arguments,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout
    except FileNotFoundError as error:
        raise UserError(f"Required command is unavailable: {arguments[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or str(error)
        raise UserError(f"{arguments[0]} failed: {detail}") from error


def ensure_model_snapshot():
    """Ensure the complete pinned snapshot exists, resuming partial downloads."""
    import huggingface_hub
    from huggingface_hub.errors import LocalEntryNotFoundError

    try:
        snapshot = Path(huggingface_hub.snapshot_download(
            MODEL_REPO,
            revision=MODEL_REVISION,
            local_files_only=True,
        ))
        if all((snapshot / filename).is_file() for filename in MODEL_SNAPSHOT_FILES):
            return str(snapshot)
    except LocalEntryNotFoundError:
        pass

    print(
        "local-ocr: downloading PaddleOCR-VL-1.6 (approximately 1.9 GB)...",
        file=sys.stderr,
    )
    # Hugging Face's per-file locks serialize concurrent first-use downloads.
    return huggingface_hub.snapshot_download(
        MODEL_REPO,
        revision=MODEL_REVISION,
        local_files_only=False,
    )


class OcrEngine:
    """Lazy, single-invocation owner of the CPU model and processor."""

    def __init__(self):
        self._model = None
        self._processor = None
        self._torch = None

    def _load(self):
        if self._model is not None:
            return

        os.environ["CUDA_VISIBLE_DEVICES"] = ""
        ensure_model_snapshot()

        # Model loading is deliberately offline after ensuring the exact snapshot exists.
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        import torch
        from transformers import AutoModelForImageTextToText, AutoProcessor

        torch.set_num_threads(max(1, min(8, os.cpu_count() or 1)))
        self._torch = torch
        self._processor = AutoProcessor.from_pretrained(
            MODEL_REPO, revision=MODEL_REVISION
        )
        self._model = AutoModelForImageTextToText.from_pretrained(
            MODEL_REPO,
            revision=MODEL_REVISION,
            dtype=torch.bfloat16,
        ).to("cpu").eval()

    def image_to_text(self, path):
        """Extract original text from one image with deterministic decoding."""
        try:
            from PIL import Image
            with Image.open(path) as source:
                image = source.convert("RGB")
        except Exception as error:
            raise UserError(f"Cannot read image {path}: {error}") from error

        self._load()
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image", "image": image},
                    {"type": "text", "text": "OCR:"},
                ],
            }
        ]
        inputs = self._processor.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
        ).to("cpu")
        with self._torch.inference_mode():
            outputs = self._model.generate(
                **inputs,
                max_new_tokens=MAX_NEW_TOKENS,
                do_sample=False,
                use_cache=True,
            )
        generated = outputs[0][inputs["input_ids"].shape[-1] :]
        return self._processor.decode(generated, skip_special_tokens=True).strip()


def pdf_page_count(path):
    info = run_command(["pdfinfo", str(path)])
    match = re.search(r"^Pages:\s+(\d+)\s*$", info, re.MULTILINE)
    if not match:
        raise UserError(f"Cannot determine the page count for {path}")
    return int(match.group(1))


def native_pdf_pages(path, pages):
    """Extract native text in PDF order, then restore the requested page order."""
    contiguous_pages = list(range(min(pages), max(pages) + 1))
    raw = run_command(
        [
            "pdftotext",
            "-f",
            str(min(pages)),
            "-l",
            str(max(pages)),
            "-layout",
            str(path),
            "-",
        ]
    )
    texts = split_pdf_text(raw, len(contiguous_pages))
    by_page = dict(zip(contiguous_pages, texts))
    return [by_page[page] for page in pages]


def raster_pdf_page_indexes(path, pages):
    """Map PDF pages containing raster images to zero-based selected indexes."""
    listing = run_command(
        ["pdfimages", "-f", str(min(pages)), "-l", str(max(pages)), "-list", str(path)]
    )
    raster_pages = {
        int(match.group(1))
        for match in re.finditer(r"^\s*(\d+)\s+\d+\s+image\b", listing, re.MULTILINE)
    }
    return {index for index, page in enumerate(pages) if page in raster_pages}


def pdf_to_text(path, page_spec):
    pages = parse_page_spec(page_spec, pdf_page_count(path))
    results = native_pdf_pages(path, pages)
    raster_indexes = raster_pdf_page_indexes(path, pages)
    ocr_indexes = pages_needing_ocr(results, raster_indexes)

    if ocr_indexes:
        engine = OcrEngine()
        with tempfile.TemporaryDirectory(prefix="local-ocr-") as temporary_directory:
            for index in ocr_indexes:
                page = pages[index]
                output_base = Path(temporary_directory) / f"page-{page}"
                run_command(
                    [
                        "pdftoppm",
                        "-f",
                        str(page),
                        "-l",
                        str(page),
                        "-r",
                        "200",
                        "-png",
                        "-singlefile",
                        str(path),
                        str(output_base),
                    ]
                )
                rendered_page = output_base.with_suffix(".png")
                if not rendered_page.is_file():
                    raise UserError(f"Poppler did not render PDF page {page}")
                print(f"local-ocr: reading PDF page {page}...", file=sys.stderr)
                results[index] = merge_ocr_text(
                    results[index], engine.image_to_text(rendered_page)
                )

    return "\n\n".join(
        f"--- Page {page} ---\n{results[index].strip() or '[No text detected]'}"
        for index, page in enumerate(pages)
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="local-ocr",
        description="Last-resort local image/PDF text extraction using PaddleOCR-VL-1.6.",
    )
    subparsers = parser.add_subparsers(dest="input_type", required=True)
    image_parser = subparsers.add_parser("image", help="OCR one local image")
    image_parser.add_argument("path")
    pdf_parser = subparsers.add_parser("pdf", help="Extract text from a local PDF")
    pdf_parser.add_argument("path")
    pdf_parser.add_argument(
        "--pages",
        help="Optional 1-indexed pages/ranges, for example: 1,3-5 (default: all)",
    )
    args = parser.parse_args(argv)

    try:
        path = Path(args.path).expanduser()
        if not path.is_file():
            raise UserError(f"File not found: {path}")
        if args.input_type == "image":
            output = OcrEngine().image_to_text(path)
        else:
            output = pdf_to_text(path, args.pages)
        print(output or "[No text detected]")
        return 0
    except Exception as error:
        print(f"local-ocr: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_sigterm)
    raise SystemExit(main())
