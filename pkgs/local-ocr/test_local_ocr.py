import io
import signal
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

import local_ocr


class PageSpecTests(unittest.TestCase):
    def test_none_selects_every_page(self):
        self.assertEqual(local_ocr.parse_page_spec(None, 4), [1, 2, 3, 4])

    def test_comma_separated_pages_and_ranges_keep_request_order(self):
        self.assertEqual(local_ocr.parse_page_spec("5,1,3-4", 5), [5, 1, 3, 4])

    def test_duplicate_pages_are_processed_once(self):
        self.assertEqual(local_ocr.parse_page_spec("2,1-3,2", 3), [2, 1, 3])

    def test_malformed_ranges_are_rejected(self):
        for spec in ("", " ", "0", "-1", "2-1", "one", "1-", "-2", "1,,2", "1.5", "1;2"):
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                local_ocr.parse_page_spec(spec, 5)

    def test_out_of_range_pages_are_rejected(self):
        for spec in ("6", "1-6", "0-2"):
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                local_ocr.parse_page_spec(spec, 5)


class PdfTextTests(unittest.TestCase):
    def test_form_feeds_preserve_blank_pages_and_page_order(self):
        raw = "Native page one\n\f\n\fNative page three\n\f"
        self.assertEqual(
            local_ocr.split_pdf_text(raw, 3),
            ["Native page one", "", "Native page three"],
        )

    def test_missing_final_form_feed_is_accepted(self):
        self.assertEqual(local_ocr.split_pdf_text("One\n\fTwo", 2), ["One", "Two"])

    def test_wrong_page_count_is_rejected_instead_of_misaligning_text(self):
        with self.assertRaises(ValueError):
            local_ocr.split_pdf_text("Only one page\f", 2)

    def test_only_pages_without_native_text_need_ocr_without_raster_content(self):
        pages = [
            "This native page has selectable text to use directly.",
            "Invoice 42",
            " \n\t ",
            "Tento přehled obsahuje český text.",
        ]
        self.assertEqual(local_ocr.pages_needing_ocr(pages), [2])

    def test_raster_regions_require_ocr_even_when_native_text_exists(self):
        pages = ["Native heading plus an image", "Invoice 42", ""]
        self.assertEqual(local_ocr.pages_needing_ocr(pages, {0, 1}), [0, 1, 2])

    def test_ocr_supplements_instead_of_replacing_native_text(self):
        result = local_ocr.merge_ocr_text("Invoice 42", "Image text")
        self.assertEqual(
            result,
            "Invoice 42\n\nAdditional OCR output (may repeat native text):\nImage text",
        )

    def test_ocr_only_page_does_not_gain_native_section(self):
        self.assertEqual(local_ocr.merge_ocr_text(" \n", "Image text"), "Image text")


class ModelSnapshotTests(unittest.TestCase):
    @staticmethod
    def fake_hub(local_snapshot):
        module = types.ModuleType("huggingface_hub")

        class LocalEntryNotFoundError(Exception):
            pass

        calls = []

        def snapshot_download(repo, revision, local_files_only=False):
            calls.append((repo, revision, local_files_only))
            if local_files_only:
                if local_snapshot is None:
                    raise LocalEntryNotFoundError("incomplete or missing local snapshot")
                return local_snapshot
            return "/completed/snapshot"

        module.LocalEntryNotFoundError = LocalEntryNotFoundError
        module.snapshot_download = snapshot_download
        module.errors = types.SimpleNamespace(LocalEntryNotFoundError=LocalEntryNotFoundError)
        return module, calls

    def test_config_only_snapshot_is_resumed_in_online_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = Path(directory) / "snapshot"
            snapshot.mkdir()
            (snapshot / "config.json").write_text("{}")
            module, calls = self.fake_hub(local_snapshot=str(snapshot))
            with mock.patch.dict(sys.modules, {"huggingface_hub": module, "huggingface_hub.errors": module.errors}):
                result = local_ocr.ensure_model_snapshot()
        self.assertEqual(result, "/completed/snapshot")
        self.assertEqual(
            calls,
            [
                (local_ocr.MODEL_REPO, local_ocr.MODEL_REVISION, True),
                (local_ocr.MODEL_REPO, local_ocr.MODEL_REVISION, False),
            ],
        )

    def test_complete_snapshot_never_requires_network(self):
        required_files = [
            ".eval_results/real5_omnidocbench.yaml", ".gitattributes", "LICENSE", "README.md",
            "added_tokens.json", "chat_template.jinja", "config.json",
            "configuration_paddleocr_vl.py", "generation_config.json",
            "image_processing_paddleocr_vl.py", "inference.yml", "model.safetensors",
            "modeling_paddleocr_vl.py", "preprocessor_config.json",
            "processing_paddleocr_vl.py", "processor_config.json", "special_tokens_map.json",
            "tokenizer.json", "tokenizer.model", "tokenizer_config.json",
        ]
        with tempfile.TemporaryDirectory() as directory:
            snapshot = Path(directory) / "snapshot"
            for filename in required_files:
                path = snapshot / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            module, calls = self.fake_hub(local_snapshot=str(snapshot))
            with mock.patch.dict(sys.modules, {"huggingface_hub": module, "huggingface_hub.errors": module.errors}):
                result = local_ocr.ensure_model_snapshot()
        self.assertEqual(result, str(snapshot))
        self.assertEqual(calls, [(local_ocr.MODEL_REPO, local_ocr.MODEL_REVISION, True)])


class TerminationTests(unittest.TestCase):
    def test_sigterm_unwinds_rendered_page_directory(self):
        directory = None
        with self.assertRaises(SystemExit) as caught:
            with tempfile.TemporaryDirectory() as directory:
                local_ocr.handle_sigterm(signal.SIGTERM, None)
        self.assertEqual(caught.exception.code, 128 + signal.SIGTERM)
        assert directory is not None
        self.assertFalse(Path(directory).exists())


class CliValidationTests(unittest.TestCase):
    def test_missing_image_fails_before_model_loading(self):
        missing = Path(tempfile.gettempdir()) / "local-ocr-file-that-does-not-exist.png"
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            result = local_ocr.main(["image", str(missing)])
        self.assertEqual(result, 2)
        self.assertIn("File not found", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
