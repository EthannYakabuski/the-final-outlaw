"""Package reviewed illustrated originals offline. Does not generate or edit artwork."""
from pathlib import Path
from PIL import Image
import hashlib,json

def main():
    here=Path(__file__).resolve().parent
    manifest=json.loads((here/'source_art/round-two/manifest.json').read_text(encoding='utf-8'))
    outputs=[]
    for row in manifest['assets']:
        original=here/row['original'];prompt=here/row['prompt']
        assert hashlib.sha256(original.read_bytes()).hexdigest()==row['original_sha256']
        assert hashlib.sha256(prompt.read_bytes()).hexdigest()==row['prompt_sha256']
        for out in row['outputs']:
            target=here/out['file'];target.parent.mkdir(parents=True,exist_ok=True)
            Image.open(original).convert('RGB').resize(tuple(out['size']),Image.Resampling.LANCZOS).save(target)
            outputs.append(out['file'])
    records=[]
    for p in sorted(here.rglob('*.png')):
        with Image.open(p) as im: dims=list(im.size);mode=im.mode
        records.append({'file':p.relative_to(here).as_posix(),'dimensions':dims,'mode':mode,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    (here/'asset-manifest.json').write_bytes((json.dumps(records,indent=2)+'\n').encode('utf-8'))
    print(json.dumps({'packaged_illustrations':len(outputs),'manifest_pngs':len(records),'screenshots_modified':False}))

if __name__=='__main__':main()
