// pdf-extract — read a PDF for the lfg MCP server's read_file (src/mcp-lfg-tools.ts).
//
//   pdf-extract <pdf> <out-dir> <first-page> <max-pages> <max-px>
//
// Prints one JSON object: page count, per-page text, every form field with its
// filled value (AcroForm widgets — PDFKit's page text leaves these out, and they
// are the whole point of a filled form), and the paths of JPEG renders of the
// requested pages, with the filled fields drawn in. Compiled on first use into
// ~/.lfg/cache/pdf-extract by `ensurePdfHelper`.

import AppKit
import Foundation
import PDFKit

func fail(_ message: String) -> Never {
  let data = try! JSONSerialization.data(withJSONObject: ["error": message])
  FileHandle.standardOutput.write(data)
  exit(1)
}

let args = CommandLine.arguments
guard args.count == 6 else { fail("usage: pdf-extract <pdf> <out-dir> <first-page> <max-pages> <max-px>") }
guard let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else { fail("cannot open the PDF") }
if doc.isLocked { fail("the PDF is password-protected") }
let outDir = URL(fileURLWithPath: args[2])
let firstPage = max(1, Int(args[3]) ?? 1)
let maxPages = max(0, Int(args[4]) ?? 10)
let maxPx = CGFloat(Double(args[5]) ?? 1600)

func fieldValue(_ a: PDFAnnotation) -> String {
  switch a.widgetFieldType {
  case .button:
    // Checkboxes and radios: report the state, not the export name.
    if a.widgetControlType == .pushButtonControl { return "" }
    return a.buttonWidgetState == .onState ? "checked" : "unchecked"
  default:
    return a.widgetStringValue ?? ""
  }
}

var fields: [[String: Any]] = []
var pages: [[String: Any]] = []
let lastPage = min(doc.pageCount, firstPage + maxPages - 1)

for i in 0..<doc.pageCount {
  guard let page = doc.page(at: i) else { continue }
  for a in page.annotations where a.type == "Widget" {
    let type: String
    switch a.widgetFieldType {
    case .text: type = "text"
    case .button: type = a.widgetControlType == .radioButtonControl ? "radio" : "checkbox"
    case .choice: type = "choice"
    case .signature: type = "signature"
    default: type = "other"
    }
    if a.widgetControlType == .pushButtonControl { continue }
    fields.append(["page": i + 1, "name": a.fieldName ?? "", "type": type, "value": fieldValue(a)])
  }
  let n = i + 1
  guard n >= firstPage, n <= lastPage else { continue }
  var entry: [String: Any] = ["page": n, "text": page.string ?? ""]
  // thumbnail(of:for:) honours page rotation and draws annotations, so the
  // render shows the form as filled.
  let box = page.bounds(for: .mediaBox)
  let rotated = page.rotation % 180 != 0
  let w = rotated ? box.height : box.width
  let h = rotated ? box.width : box.height
  let scale = min(maxPx / max(w, h), 3)
  let image = page.thumbnail(of: NSSize(width: w * scale, height: h * scale), for: .mediaBox)
  if let tiff = image.tiffRepresentation,
     let rep = NSBitmapImageRep(data: tiff),
     let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) {
    let url = outDir.appendingPathComponent("page-\(n).jpg")
    if (try? jpeg.write(to: url)) != nil { entry["image"] = url.path }
  }
  pages.append(entry)
}

let out: [String: Any] = ["pageCount": doc.pageCount, "pages": pages, "fields": fields]
FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: out))
