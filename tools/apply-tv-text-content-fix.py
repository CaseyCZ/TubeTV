from pathlib import Path

path = Path("TubeTV/InnerTubeService.swift")
text = path.read_text()

old = '''        if let dictionary = value as? [String: Any] {
            if let simpleText = dictionary["simpleText"] as? String {
                return simpleText
            }

            if let runs = dictionary["runs"] as? [[String: Any]] {
'''
new = '''        if let dictionary = value as? [String: Any] {
            if let simpleText = dictionary["simpleText"] as? String {
                return simpleText
            }

            // Current TV TextItem objects often carry their visible value in
            // `content` instead of the legacy `simpleText`/`runs` shapes.
            // SmartTube's TextItem.getText() handles this representation too.
            if let content = dictionary["content"] as? String,
               !content.isEmpty {
                return content
            }

            if let runs = dictionary["runs"] as? [[String: Any]] {
'''

if old not in text:
    raise SystemExit("text(from:) block not found")

text = text.replace(old, new, 1)
path.write_text(text)
