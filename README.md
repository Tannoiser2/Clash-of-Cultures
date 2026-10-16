# Clash of Cultures — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Clash of Cultures: Monumental Edition** di Christian Marcussen
(© Lautapelit.fi / WizKids). Componenti, illustrazioni e regole © dei rispettivi autori: immagini e modelli
3D vengono dal modulo Tabletop Simulator e non vanno distribuiti pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/Clash-of-Cultures/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **Da 2 a 4 civiltà** (Rosso, Viola, Blu, Giallo) con nome a scelta, ognuna Umana o IA (Facile, Normale,
  Difficile). Più persone sullo stesso dispositivo giocano a turno, con una schermata «tocca a…» per tenere
  segrete le carte.
- **Mappa 3D**: le regioni esagonali hanno la grafica delle tessere del gioco e si scoprono esplorando (si
  sceglie l'orientamento con l'anteprima sulla mappa, rispettando le regole di piazzamento dei mari). Le
  disposizioni per 2, 3 e 4 giocatori sono ricavate dai tabelloni del modulo. Città con edifici del colore di chi
  li possiede (anche quelli «influenzati»), meraviglie, coloni, fanterie e navi sono i modelli del modulo TTS.
  Trascina per ruotare, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per spostare.
- **Tema antico**: pergamena, pietra e bronzo, titoli in Cinzel (le capitali lapidarie romane, come sulle carte)
  e testo in Alegreya Sans; musica di lira, aulos e tamburo a cornice sintetizzata da `tools/sintetizza_audio.py`.
- **Regole complete del gioco base**: le 48 caselle del tabellone dei progressi con tutti gli effetti, le tre
  forme di governo e il cambio di governo, fondazione, raccolta (Pesca, Porto, Allevamento, Irrigazione,
  Metallurgia…), costruzione, reclutamento (Igiene, Leva, Medicina, Nazionalismo), movimento con terreno,
  Strade, imbarco e sbarco, Navigazione e Cartografia, felicità, influenza culturale con potenziamenti e
  immunità, rotte commerciali, combattimento con dadi, abilità della fanteria, Fortezza, Arte d'assedio, Armi
  d'acciaio, Fanatismo, ritirata, conquista delle città, barbari (comparsa, movimento, attacchi, conquista),
  segnaeventi e **38 eventi**, **42 carte Azione** con effetti e tattiche, **32 Obiettivi** (64 condizioni,
  controllate in automatico), **8 meraviglie** con i loro poteri, fase di status e punteggio finale con gli
  spareggi.
- **Varianti** del regolamento: partita breve (4 ere) ed eventi solo con le icone.
- **Testi in italiano**: avanzamenti, carte, eventi e obiettivi tradotti (passa il mouse sopra per leggerli);
  le immagini delle carte restano quelle originali.

Semplificazioni: con la Navigazione le navi raggiungono qualsiasi mare sul bordo del tabellone (non solo il primo
gruppo nella direzione scelta), i pagamenti usano automaticamente prima la risorsa richiesta e poi Oro/Idee, e gli
obiettivi si completano da soli quando sono soddisfatti. L'IA è euristica: espande, si difende dai barbari e
attacca quando è in vantaggio, sceglie dove fondare evitando di sovrapporre le città, esplora attorno alle
proprie città, punta sugli edifici e risparmia Cultura e Umore per le meraviglie (che restano rare).

Gli scambi liberi fra giocatori non sono gestiti.

## Espansione Civiltà
Si attiva dal menu con **Espansione Civiltà** (funziona anche online). Il gioco base resta com'è.
- **15 civiltà** assegnate a caso (Aztechi, Babilonia, Cartagine, Celti, Cina, Egitto, Fenicia, Giappone, Grecia,
  India, Maya, Persia, Roma, Unni, Vichinghi), con la tessera di partenza propria dove prevista. I nomi predefiniti
  dei posti diventano quelli della civiltà. I 4 **avanzamenti di civiltà** arrivano gratis con l'avanzamento
  collegato (o con un avanzamento di governo), senza far avanzare il segnaeventi: pulsante «Civiltà».
- **Cavalleria, Elefanti e Capi** con il vero dado a 12 facce del gioco (icone Fanteria +1, Cavalleria +2,
  Elefante annulla un colpo, Capo ritira il dado), limite di 4 unità d'armata per casella, scelta del Capo fra i
  3 della civiltà, un Capo alla volta; chi uccide un Capo nemico ne tiene la carta (2 PV).
- **Mercato, Obelisco, Osservatorio** (il Mercato abilita Cavalleria ed Elefanti e dà Oro dalle rotte altrui;
  l'Obelisco è immune all'influenza e resta del suo colore; l'Osservatorio pesca una carta Azione).
- **Pirati**: navi nere che compaiono con l'icona degli eventi, razziano le città costiere, bloccano raccolta e
  rotte commerciali e premiano chi le affonda. **Barbari** con Cavalleria ed Elefanti di rinforzo.
- **20 eventi** (rivoluzioni, eclissi, Cavallo di Troia, pandemia, peste nera, carestie, incendio, grandi
  personaggi Architetto, Atleta, Diplomatico e Oracolo…) e **6 carte Obiettivo** (12 obiettivi) dell'espansione.

- **Tutte le abilità** dei 60 avanzamenti di civiltà e dei 45 Capi sono applicate dal gioco: bonus e annullamenti
  in battaglia, pagamenti alternativi (Umore, Idee, Prigionieri), Influenza estesa (Ellenizzazione, Proselitismo,
  Zoroastrismo, Influenza druidica), rotte commerciali delle civiltà, movimenti speciali (Arte navale, Strade
  imperiali, Nomadi) e una ventina di azioni speciali nuove nel pulsante «Speciali» (Egemonia, Calendario, Bande
  armate, Augusto, Erik il Rosso, Cleopatra, Dario, Suiko…).

Semplificazioni dell'espansione: Attila usa da solo l'abilità dell'Elefante su una Cavalleria quando conviene;
Alleati pirati fa attraversare e condividere i mari con i Pirati e protegge dalle loro razzie, senza farli
combattere per Cartagine; Silla nega sempre ai Barbari vicini di muovere contro il suo giocatore. Mancano le
varianti «Capi casuali» e «Storia alternativa». L'IA usa Capi, nuove unità e quasi tutte le azioni speciali,
ma non va a caccia di pirati.

## Gioco online
Dal menu, **GIOCA ONLINE** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi della
ludoteca (Realtime Database), con le stanze sotto `clash/rooms`: la sezione generica `$game` delle regole in
`firebase/database.rules.json` lo copre già, non serve toccare nulla nella console.
- Chi crea la stanza sceglie prima nel menu civiltà, opzioni e livello dell'IA: le civiltà su Umano diventano i
  posti per gli amici (la prima è la sua). Comunica il codice di 4 lettere; quando ci sono tutti preme
  *Si comincia!* e i posti liberi li gioca l'IA.
- Gli amici scrivono nome e codice e premono *Entra*.
- Ogni decisione è una mossa numerata nel database (`acts/0`, `acts/1`, …): tutti i dispositivi fanno girare lo
  stesso motore con lo stesso seme e applicano le stesse mosse. Le IA le gioca chi ha creato la stanza.
- Se cade la linea si rientra con lo stesso codice; se un giocatore tace per un minuto, gioca l'IA al suo posto.

## Struttura
```
scripts/data/coc_data.gd        avanzamenti, edifici, meraviglie, carte (testi italiani)
scripts/data/civ_data.gd        espansione Civiltà: civiltà, avanzamenti di civiltà, capi
scripts/core/engine_state.gd    stato, geometria esagonale, risorse, mazzi, decisioni
scripts/core/engine_actions.gd  preparazione, esplorazione, azioni del turno
scripts/core/engine_combat.gd   movimento, battaglie, conquista, barbari
scripts/core/engine_civ.gd      espansione Civiltà: azioni speciali di civiltà e Capi, rotte delle civiltà
scripts/core/engine.gd          turno, carte, eventi, obiettivi, fase di status, punteggio
scripts/core/ai.gd              IA euristica
scripts/ui/board3d.gd           mappa 3D, telecamera, caselle cliccabili
scripts/ui/game_view.gd         interfaccia di gioco e finestre
scripts/ui/menu.gd              menu e stanze online
scripts/net/                    Firebase (REST) e partita online in lockstep
tools/prepara_asset.py          estrae tessere, carte, modelli e disposizioni dal modulo TTS
tools/sintetizza_audio.py       musica
tests/                          sim.gd (IA contro IA), shot.gd (screenshot), online_play.gd + firebase_mock.py
```

## Test
```
godot --headless --path . -s res://tests/sim.gd -- 10 4 1,1,2,1     # 10 partite a 4, livelli per posto
COC_CIV=1 godot --headless --path . -s res://tests/sim.gd -- 10 4    # le stesse con l'espansione Civiltà
COC_CIV=1 COC_FUZZ=1 godot --headless --path . -s res://tests/sim.gd -- 6 4   # tutti con tutte le abilità
godot --headless --path . -s res://tests/exp_specials.gd             # ogni azione speciale dell'espansione
xvfb-run godot --path . -s res://tests/shot.gd -- game 6             # screenshot in user://shots
xvfb-run godot --path . -s res://tests/shot.gd -- civ                # screenshot dell'espansione
```
