import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerName as String] as? String) == "Valance" {
  let b = w[kCGWindowBounds as String] as! [String: Any]
  print(w[kCGWindowLayer as String]!, w[kCGWindowIsOnscreen as String] ?? "-", b["X"]!, b["Y"]!, b["Width"]!)
}
