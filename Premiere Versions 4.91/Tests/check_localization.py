"""Require translations for literal app-owned messages and interpolation templates."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]

def literal(source, start):
    out=[];i=start+1
    while i<len(source):
        c=source[i]
        if c=='"':return ''.join(out),i+1
        if c=='\\':
            i+=1
            if source[i]=='(':
                depth=1;i+=1
                while depth:
                    if source[i]=='"':_,i=literal(source,i);continue
                    if source[i]=='(':depth+=1
                    if source[i]==')':depth-=1
                    i+=1
                out.append('%@');continue
            out.append({'n':'\n','t':'\t','r':'\r','0':'\0'}.get(source[i],source[i]));i+=1;continue
        out.append(c);i+=1
    raise AssertionError('Unterminated Swift string')

entries=json.loads((root/'Premiere Versions/Translations.json').read_text())
by_ru={e['ru']:e['en'] for e in entries}
assert len(by_ru)==len(entries),'Duplicate localization keys'
for entry in entries:
    assert entry['ru'] and entry['en'], 'Empty translation'
    assert entry['ru'].count('%@')==entry['en'].count('%@'), 'Interpolation placeholder count mismatch'
    assert entry['en'] in {'Русский', 'Language / Язык'} or not re.search('[А-Яа-яЁё]',entry['en']), 'Cyrillic in English app-owned text'
missing=[]
for file in (root/'Premiere Versions').glob('*.swift'):
    source=file.read_text()
    for match in re.finditer(r'\bPVL\(\s*(")',source):
        text,_=literal(source,match.start(1))
        if re.search('[А-Яа-яЁё]',text) and text not in by_ru:
            missing.append((file.name,text))
if missing:
    for file,text in missing:print('MISSING',file,repr(text))
    raise SystemExit(1)
print('PASS: English coverage of literal app messages and dynamic templates; placeholder parity and unique keys')

# Exercise the actual Swift localizer: all strings, templates and user values.
import subprocess,tempfile,shutil
with tempfile.TemporaryDirectory(prefix='pv49-language-') as directory:
    directory=Path(directory)
    test=directory/'Checks.swift'
    test.write_text((root/'Premiere Versions/Localization.swift').read_text()+r'''
setbuf(stdout,nil)
let file = Bundle.main.url(forResource: "Translations", withExtension: "json")!
let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [[String:String]]
for entry in entries {
    let russian = entry["ru"]!, english = entry["en"]!
    for (input, language, expected) in [(russian,"en",english),(english,"ru",russian)] {
        let value = "рэн_проект 你好 user's v014"
        let message = input.replacingOccurrences(of: "%@", with: value)
        let translated = PVLocalization.text(message, language: language)
        if language == "ru" && entries.contains(where: { $0["en"] == input && $0["ru"]?.replacingOccurrences(of: "%@", with: value) == translated }) { continue }
        if translated != expected.replacingOccurrences(of: "%@", with: value) { print("MISMATCH", language, input, "EXPECTED", expected, "GOT", translated);exit(1) }
    }
}
precondition(PVLocalization.text("рэн_проект_v014", language:"en") == "рэн_проект_v014")
print("PASS: actual Swift localizer translates both directions and preserves project names, comments and template values")
''')
    shutil.copy(root/'Premiere Versions/Translations.json',directory/'Translations.json')
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(directory/'modules'),'-swift-version','5',str(test),'-o',str(directory/'Checks')],check=True)
    subprocess.run([str(directory/'Checks')],check=True)
