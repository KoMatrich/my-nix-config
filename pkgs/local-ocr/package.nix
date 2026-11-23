{
  lib,
  stdenv,
  makeWrapper,
  python3Packages,
  poppler-utils,
}:

let
  python = python3Packages.python.withPackages (
    packages: with packages; [
      huggingface-hub
      pillow
      safetensors
      sentencepiece
      torch
      torchvision
      transformers
    ]
  );
in
stdenv.mkDerivation {
  pname = "local-ocr";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    ${python}/bin/python -m unittest -v test_local_ocr.py
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    makeWrapper ${python}/bin/python $out/bin/local-ocr \
      --add-flags "$src/local_ocr.py" \
      --prefix PATH : ${lib.makeBinPath [ poppler-utils ]} \
      --set CUDA_VISIBLE_DEVICES "" \
      --set HF_HUB_DISABLE_TELEMETRY 1
    runHook postInstall
  '';

  meta = {
    description = "Last-resort local image and PDF OCR with PaddleOCR-VL-1.6";
    license = lib.licenses.asl20;
    mainProgram = "local-ocr";
    platforms = lib.platforms.linux;
  };
}
