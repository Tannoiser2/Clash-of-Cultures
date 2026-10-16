#!/usr/bin/env python3
"""Prepara grafica e dati di Clash of Cultures dal modulo Tabletop Simulator.

Uso: python3 tools/prepara_asset.py <cartella sorgente>
La cartella sorgente contiene img/ (immagini del modulo già ridotte a 4096 px, nome = ultime 24
cifre dell'indirizzo), obj/ (modelli), tts.json (salvataggio del modulo), cards_*.json (testi delle
carte trascritti) e layouts.json (posizioni delle regioni ricavate dai tabelloni 2/3/4 giocatori).
Scrive assets/ e assets/data/tiles.json.
"""
import json, math, os, re, sys, glob, shutil
import numpy as np
from PIL import Image, ImageOps

SRC = sys.argv[1] if len(sys.argv) > 1 else '../src'
DST = os.path.join(os.path.dirname(__file__), '..', 'assets')

def img(key):
    return Image.open(os.path.join(SRC, 'img', key[-24:] + '.webp'))

def k(u):
    return re.sub(r'[^A-Za-z0-9]', '', u or '')[-24:]

def mk(*p):
    d = os.path.join(DST, *p)
    os.makedirs(d, exist_ok=True)
    return d

tts = json.load(open(os.path.join(SRC, 'tts.json')))

# ---------------------------------------------------------------- tessere regione
# Faccia scoperta delle tessere: centro delle 4 caselle nell'atlante (u, v dall'alto), raggio 0.1404
POS = {'T': (0.393, 0.593), 'B': (0.393, 0.837), 'L': (0.182, 0.715), 'R': (0.603, 0.715)}
RAD = 0.1404

def classify(a):
    m = a.reshape(-1, 3).mean(0); s = a.reshape(-1, 3).std(0).mean()
    r, g, b = m
    if b >= r and b > 90: return 'sea'
    if s > 40: return 'mountain'
    if r < 115 and g < 118: return 'forest'
    if r > g + 10: return 'barren'
    return 'plains'

tiles = []
def walk(objs, path):
    for o in objs:
        nk = o.get('Nickname', '')
        if o['Name'] == 'Custom_Model' and ('Region Tiles' in path):
            tiles.append(k(o['CustomMesh']['DiffuseURL']))
        if nk == 'Start Tile' and o['Name'] == 'Custom_Model':
            tiles.append('START:' + k(o['CustomMesh']['DiffuseURL']))
        walk(o.get('ContainedObjects') or [], path + '/' + nk)
walk(tts['ObjectStates'], '')
seen = []
for t in tiles:
    if t not in seen: seen.append(t)
tiles = seen
out_tiles = []
tdir = mk('tiles')
back_done = False
for i, t in enumerate(tiles):
    start = t.startswith('START:')
    key = t.split(':')[-1]
    im = img(key).convert('RGB'); W, H = im.size; a = np.asarray(im)
    name = 'start' if start else 't%02d' % len(out_tiles)
    ter = {}
    for p, (u, v) in POS.items():
        cx, cy, rr = u * W, v * H, RAD * W
        crop = im.crop((int(cx - rr), int(cy - rr), int(cx + rr), int(cy + rr))).resize((256, 256), Image.LANCZOS)
        crop.save(os.path.join(tdir, '%s_%s.jpg' % (name, p)), quality=88)
        inner = a[int(cy - rr * 0.6):int(cy + rr * 0.6), int(cx - rr * 0.6):int(cx + rr * 0.6)]
        ter[p] = classify(inner)
    if not back_done:
        # retro (pergamena): faccia superiore del modello, centro u=0.611 v=0.665 (dal basso)
        cx, cy, rr = 0.611 * W, (1 - 0.665) * H, RAD * W
        im.crop((int(cx - rr), int(cy - rr), int(cx + rr), int(cy + rr))).resize((256, 256), Image.LANCZOS).save(os.path.join(tdir, 'back.jpg'), quality=88)
        back_done = True
    out_tiles.append({'id': name, 'terrain': ter})
    print(name, ter)

# tessere di partenza alternative dell'espansione
for name, key in (('start_carthage', 'F80C00B28D2345AFD4A52855'), ('start_egypt', '4E0088F4B726032848CFCED6'),
                  ('start_maya', 'F91B6EF8236722345EF87A77'), ('start_phoenicia', '478A1E5BC5575292DB147F8B'),
                  ('start_viking', '8F26EFCDB53220F9ED8E31D0')):
    im = img(key).convert('RGB'); W, H = im.size; a = np.asarray(im)
    ter = {}
    for p, (u, v) in POS.items():
        cx, cy, rr = u * W, v * H, RAD * W
        im.crop((int(cx - rr), int(cy - rr), int(cx + rr), int(cy + rr))).resize((256, 256), Image.LANCZOS).save(os.path.join(tdir, '%s_%s.jpg' % (name, p)), quality=88)
        inner = a[int(cy - rr * 0.6):int(cy + rr * 0.6), int(cx - rr * 0.6):int(cx + rr * 0.6)]
        ter[p] = classify(inner)
    out_tiles.append({'id': name, 'terrain': ter})
    print(name, ter)

# ---------------------------------------------------------------- carte
cdir = mk('cards')
def cut(key, cols, rows, idx, w):
    im = img(key).convert('RGB'); W, H = im.size
    cw, ch = W / cols, H / rows
    x, y = idx % cols, idx // cols
    c = im.crop((round(x * cw), round(y * ch), round((x + 1) * cw), round((y + 1) * ch)))
    return c.resize((w, round(w * c.size[1] / c.size[0])), Image.LANCZOS)

acts = json.load(open(os.path.join(SRC, 'cards_actions.json')))
for c in acts:
    cut('E9E9379CD3D4BEECF8F7293C', 8, 6, c['idx'], 360).save(os.path.join(cdir, c['code'].lower() + '.jpg'), quality=86)
objs = json.load(open(os.path.join(SRC, 'cards_objectives.json')))
for c in objs:
    cut('FBE67BD5DB2E44AA9B5BD073', 8, 5, c['idx'], 360).save(os.path.join(cdir, 'o%d.jpg' % (c['idx'] + 1)), quality=86)
evs = json.load(open(os.path.join(SRC, 'cards_events.json')))
for c in evs:
    if c['sheet'] == 'evt':
        cut('5C2C9FF7B972D4E0FDA0A223', 8, 7, c['idx'], 360).save(os.path.join(cdir, c['code'].lower() + '.jpg'), quality=86)
    else:
        cut('0AA34B0FF8A82BB4F9511461', 4, 2, c['idx'], 360).save(os.path.join(cdir, c['code'].lower() + '.jpg'), quality=86)
for i in range(8):
    cut('2576FA9011D9D54AD81B7845', 4, 3, i, 420).save(os.path.join(cdir, 'w%d.jpg' % i), quality=86)
# capi e plance delle civiltà (espansione)
leaders = json.load(open(os.path.join(SRC, 'cards_leaders.json')))
for c in leaders:
    cut('652F00118DBE4D707BCF4556', 8, 6, c['idx'], 360).save(os.path.join(cdir, c['code'].lower() + '.jpg'), quality=86)
for i in range(15):
    cut('9D6CE53DBBA79BCCA864546D', 4, 4, i, 420).save(os.path.join(cdir, 'civ%d.jpg' % i), quality=86)
# dorsi
for name, key in (('back_action', 'A4D9B66A6D1D0C8344B28920'), ('back_objective', '26BF3D7FACD37CFEBD5F216F'),
                  ('back_event', '2E1F0D10C4B0DF22452C1429'), ('back_wonder', 'FEFDF03DCDEBB6B966158917')):
    im = img(key).convert('RGB')
    im.resize((360, round(360 * im.size[1] / im.size[0])), Image.LANCZOS).save(os.path.join(cdir, name + '.jpg'), quality=86)

# ---------------------------------------------------------------- gettoni
udir = mk('tokens')
for name, key in (('happy', '6B38025CFF15CE11470B8992'), ('angry', '9B0FDD70F64B137EBAEA4781'),
                  ('culture', '1FC8411CF7A644918FDEC30C'), ('exhausted', 'C5498FDEE4E3C64B7B4D908A'),
                  ('first', '77D1B65EC679ED0668A3CACA')):
    im = img(key).convert('RGBA'); im.thumbnail((256, 256), Image.LANCZOS)
    if name in ('happy', 'angry'):
        im = im.rotate(180)   # nella texture del modulo le facce sono capovolte
    im.save(os.path.join(udir, name + '.png'))

# ---------------------------------------------------------------- modelli 3D
mdir = mk('models')
MODELS = {
    'settlement': ('D1F6C4DEF79C36EF93E80946', '8C7FB73AB69414E61495F5CD'),
    'port': ('6E4135486121C3045463B45D', '583415CAE9476B5EDF0A469E'),
    'academy': ('20F1A2DE2900395A661A6945', '73DEF1E2805851D65CFB3863'),
    'fortress': ('338493AE81548582791E4C77', 'B5AB19378D3095C7BA3108B6'),
    'temple': ('49D19BBF8BCC2DEE735F194E', 'D0180E460E3A45DEEAE2922A'),
    'settler': ('C0BAF9F88AF05558DB5DDCC2', '8D541F1F84374312E2740FA7'),
    'infantry': ('7C7DB3AFC0C990CF1DD910A7', '1AA658E00E9097C4856435D3'),
    'ship': ('3D94E04B89B3A0E5F5A26BB9', '834013DED08CC7665E984D6D'),
    'great_wall': ('A1D3C1D55213C33B80A874E7', 'FC26DD87B56EAD95965888DC'),
    'great_arena': ('6DE2A5DD21F5A79EB44BCA91', '103500F676D6031DD84E1385'),
    'great_mausoleum': ('5F59569917BDF3EA75DB9178', '56D0FF6A50159C5E4E04CEF1'),
    'great_pyramids': ('124F0440EA7484CF0898691B', '9D85794FCF1D1FB52942960E'),
    'great_gardens': ('EAB0B7296E640ABDA2388999', '8C7AB41DA14A8FFF3F15510D'),
    'great_statue': ('F13900F5ADABD0925AE2D052', '878101FB86EC0EF667AAFA86'),
    'great_library': ('14477C694D80DAB384AABEBC', 'E9A1DCB9018D133DA193ED26'),
    'great_lighthouse': ('22CF82DDE94BA604AE4A77AB', '471432FC5DCB440FCDE7254E'),
    # espansione Civiltà
    'market': ('57CFA389BD60BAEA8449FA73', 'A6ACF4C4A4479BBF57DF79AB'),
    'obelisk': ('B318C4F71E06876385B91810', '390381D2920E6930291A7462'),
    'observatory': ('2020F8A372A69B27B41E382D', '621CA4AEB60571F5E11A5A82'),
    'cavalry': ('68F6BE4E42A627AEF723E07A', '5DC11849DDBFAD2E4764EB2F'),
    'elephant': ('E4F3D32F82BDEEFA718ECD58', 'ECB797BF67D1E656DF9AD3DA'),
    'leader': ('68712DD14FA5E67209E0B520', '0D42DDF183BF2E38FE48DC52'),
}
for name, (mesh, tex) in MODELS.items():
    src = [f for f in glob.glob(os.path.join(SRC, 'obj', '*.obj')) if f[:-4].endswith(mesh)][0]
    lines = []
    for l in open(src, errors='ignore'):
        if l.startswith(('mtllib', 'usemtl', 'o ', 'g ', 's ')):
            continue
        lines.append(l)
    open(os.path.join(mdir, name + '.obj'), 'w').write(''.join(lines))
    t = img(tex).convert('RGB'); t.thumbnail((512, 512), Image.LANCZOS); t.save(os.path.join(mdir, name + '.jpg'), quality=86)

# ---------------------------------------------------------------- tabellone e copertina
bdir = mk('board')
b = img('0CEE82F6626468F40C1C8FF0').convert('RGB')  # tabellone 2 giocatori: tanto mare
b.crop((60, 1300, 780, 2020)).resize((512, 512), Image.LANCZOS).save(os.path.join(bdir, 'sea.jpg'), quality=86)
for i, key in enumerate(('E1E1442C7E74E2D7267AC400', '0CEE82F6626468F40C1C8FF0', '7AA0D2E6822E22E424507F4E')):
    pass
uidir = mk('ui')
cov = Image.open(os.path.join(SRC, 'cover.webp')).convert('RGB')
cov.save(os.path.join(uidir, 'cover.jpg'), quality=90)
adv = img('C6828BB1774415DAF63B002A').convert('RGB')
adv.resize((2048, round(2048 * adv.size[1] / adv.size[0])), Image.LANCZOS).save(os.path.join(uidir, 'player_board.jpg'), quality=86)
# plancia degli avanzamenti senza la traccia delle risorse in alto (per la finestra degli avanzamenti)
pb = Image.open(os.path.join(uidir, 'player_board.jpg'))
pb.crop((0, 329, 2048, pb.size[1])).save(os.path.join(uidir, 'advances_board.jpg'), quality=88)

# ---------------------------------------------------------------- dati
lay = json.load(open(os.path.join(SRC, 'layouts.json')))
json.dump({'tiles': out_tiles, 'layouts': lay}, open(mk('data') + '/tiles.json', 'w'), indent=1)
print('fatto')
