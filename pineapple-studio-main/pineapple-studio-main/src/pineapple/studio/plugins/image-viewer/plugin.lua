return {
  id = "pineapple.image-viewer",
  name = "Image Viewer",
  version = "0.1.0",
  main = "main.lua",
  description = "Shows .nfp, .nft and .bimg images (bimg animations play). Reopen With > Code Editor edits them.",
  activation = { "onOpen:*.nfp", "onOpen:*.nft", "onOpen:*.bimg" },
  contributes = {
    settings = {
      ["imageViewer.checkerboard"] = { type = "boolean", default = true, title = "Checkerboard behind transparent pixels" },
    },
  },
}
