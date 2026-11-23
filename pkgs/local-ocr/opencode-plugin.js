import { execFile } from "node:child_process"
import { resolve } from "node:path"

// Home Manager symlinks this file into the Nix store. Resolve OpenCode's
// existing ESM dependency from its global config, not from that symlink.
const { tool } = await import(resolve(
  process.env.HOME ?? "",
  ".config/opencode/node_modules/@opencode-ai/plugin/dist/index.js",
))

const LOCAL_OCR = "__LOCAL_OCR__"
const IMAGE_TIMEOUT_MS = 30 * 60 * 1000
const PDF_TIMEOUT_MS = 24 * 60 * 60 * 1000
const MAX_OUTPUT_BYTES = 16 * 1024 * 1024

function runLocalOcr(arguments_, timeoutMs = IMAGE_TIMEOUT_MS) {
  return new Promise((resolveOutput, reject) => {
    execFile(
      LOCAL_OCR,
      arguments_,
      {
        timeout: timeoutMs,
        maxBuffer: MAX_OUTPUT_BYTES,
        env: { ...process.env, HF_HUB_DISABLE_TELEMETRY: "1" },
      },
      (error, stdout, stderr) => {
        if (error) {
          if (error.killed && error.signal === "SIGTERM") {
            reject(new Error(`OCR timed out after ${Math.round(timeoutMs / 60000)} minutes`))
          } else {
            reject(new Error(stderr.trim() || error.message))
          }
          return
        }
        resolveOutput(stdout.trimEnd())
      },
    )
  })
}

export default async ({ directory }) => ({
  tool: {
    ocr_image: tool({
      description:
        "LAST RESORT ONLY: extract text from a local image when the current model cannot read the image directly. Use for transcription, not general image description. Processing and model inference stay on this computer.",
      args: {
        path: tool.schema
          .string()
          .min(1)
          .describe("Local image path, absolute or relative to the current workspace"),
      },
      async execute({ path }) {
        return runLocalOcr(["image", resolve(directory, path)])
      },
    }),
    ocr_pdf: tool({
      description:
        "LAST RESORT ONLY: extract text from a local PDF when the current model cannot read the PDF directly. Uses an existing text layer where possible and local PaddleOCR for scanned pages. Processing stays on this computer.",
      args: {
        path: tool.schema
          .string()
          .min(1)
          .describe("Local PDF path, absolute or relative to the current workspace"),
        pages: tool.schema
          .string()
          .optional()
          .describe("Optional 1-indexed pages/ranges such as '1,3-5'; defaults to every page"),
      },
      async execute({ path, pages }) {
        const arguments_ = ["pdf", resolve(directory, path)]
        if (pages !== undefined) arguments_.push("--pages", pages)
        return runLocalOcr(arguments_, PDF_TIMEOUT_MS)
      },
    }),
  },
})
