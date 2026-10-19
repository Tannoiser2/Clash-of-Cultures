extends Control
## Regole in breve (dal regolamento della Monumental Edition, gioco base) e uso dell'interfaccia.

const RULES := """[b]Scopo[/b]
Guidi una civiltà da un solo villaggio a un impero. Dopo 6 ere (3 round ciascuna, poi una fase di status) vince chi ha più punti vittoria:
• 1 PV per ogni insediamento ed edificio del tuo colore (anche quelli che hai «influenzato» nelle città altrui);
• ½ PV per ogni avanzamento;
• 2 PV per ogni obiettivo completato;
• 4 PV per ogni meraviglia (2 se conquistata, divisi con chi l'ha costruita; le Piramidi valgono 5 e restano a chi le ha costruite);
• i PV di alcune carte Evento (Vulcano, Terremoto).
La partita finisce prima se, all'inizio di una fase di status, qualcuno non ha più città.

[b]Il turno[/b]
Nel tuo turno fai 3 azioni principali, in qualsiasi ordine, anche ripetute:
• [b]Avanzamento[/b]: paghi 2 Cibo (Idee e Oro valgono come Cibo) e compri un avanzamento. In ogni categoria serve prima quello in alto. Le categorie di governo (Democrazia, Autocrazia, Teocrazia) richiedono un avanzamento indicato e se ne può avere una sola. I bordi gialli danno +1 Umore, quelli blu +1 Cultura. Ogni tre avanzamenti il segnaeventi si svuota e peschi un [b]Evento[/b].
• [b]Fonda una città[/b]: un Colono diventa un insediamento, su una casella di terra che non sia Deserto, senza città, nemici o terreno improduttivo.
• [b]Attiva una città[/b]: raccogli, costruisci o recluti. Ogni attivazione in più nello stesso turno peggiora l'umore della città; una città Arrabbiata si attiva una sola volta.
  – [i]Raccogli[/i]: tante risorse quanta è la dimensione della città (+1 se Felice, solo 1 se Arrabbiata), una per casella fra la sua e quelle adiacenti: Pianura Cibo, Foresta Legno (Coltivazione), Montagna Minerale (Estrazione Mineraria), Mare Cibo (Pesca, una sola casella), Deserto Cibo (Irrigazione). Il Porto permette Oro o Umore dal mare. Niente raccolta da caselle con nemici, altre città o terreno improduttivo.
  – [i]Costruisci[/i]: 1 Cibo, 1 Legno, 1 Minerale per un edificio (Tempio con Miti, Accademia con Scrittura, Fortezza con Tattiche, Porto con Pesca sulla costa). Non nelle città Arrabbiate, uno per tipo, e nessuna città può superare il numero di città che possiedi (massimo 5 pezzi).
  – [i]Recluta[/i]: tante unità quanta è la dimensione (come per la raccolta). Colono 2 Cibo, Fanteria 1 Cibo + 1 Minerale, Nave 2 Legno (serve un Porto). Al massimo 4 eserciti per casella.
  – [i]Meraviglia[/i]: con Ingegneria, in una città Felice, giocando la carta Meraviglia e pagandone il costo (con la Cultura).
• [b]Muovi[/b]: fino a 3 unità o gruppi, una casella ciascuno (si può ripetere l'azione). Gli eserciti si muovono solo con Tattiche. Chi entra in Montagna si ferma; chi entra in Foresta non può più attaccare in quel turno. Le navi corrono lungo i mari collegati (con la Navigazione girano attorno al tabellone) e portano 2 unità ciascuna: per imbarcarsi si entra nel mare con la nave, per sbarcare si muove dalla nave a terra. Entrare in una regione inesplorata la scopre.
• [b]Aumenta la felicità[/b]: ogni passo d'umore costa tanti Umore quanta è la dimensione della città.
• [b]Influenza la cultura[/b]: da una tua città (raggio = dimensione, +1 per ogni Cultura spesa) tiri un dado: con 5 o 6 un edificio della città bersaglio passa al tuo colore (vale per i tuoi punti). Dopo il tiro puoi spendere Cultura per aggiungere +1 ciascuna. Un solo successo per turno.
Ci sono poi le [b]azioni gratuite[/b] e speciali di avanzamenti, meraviglie e carte (pulsante «Speciali» e «Carte»).

[b]Combattimento[/b]
Quando un esercito entra in una casella con nemici o una città nemica si combatte. In ogni round ognuno può giocare la tattica di una carta Azione (serve Tattiche), poi tira un dado (a 12 facce, numeri da 1 a 6 con un'icona) per ogni unità d'armata: la somma è il valore di combattimento, e ogni icona di un tipo di unità presente attiva l'abilità di una di quelle unità (Fanteria +1); ogni 5 punti è un colpo che elimina un'unità nemica. La Fortezza dà nel primo round un dado in più e annulla un colpo. Dopo ogni round l'attaccante può ritirarsi. Chi resta solo in una città la conquista: riceve Oro pari alla dimensione (+1 se Felice, 1 se Arrabbiata), i pezzi passano al suo colore e la città diventa Arrabbiata; chi l'ha persa riceve un Colono. Vincere contro i Barbari dà 1 Oro (più 1 per una loro città conquistata).

[b]Eventi e Barbari[/b]
Gli eventi hanno spesso un'icona: Miniera d'oro (+2 Oro), Terreno improduttivo, «I Barbari si insediano» (un insediamento a 2 caselle da te), «I Barbari si muovono» (verso le tue città), «I Pirati sbarcano e razziano». Gli eventi Grande personaggio si possono tenere come carte Azione pagando Cultura.

[b]Obiettivi[/b]
Ogni carta Obiettivo ha due obiettivi: se ne completa uno solo. Alcuni si completano subito (dopo una battaglia, una fondazione…), altri nella fase di status. Il gioco li completa da solo quando le condizioni sono soddisfatte.

[b]Fase di status[/b] (dopo ogni era)
1. Obiettivi di status. 2. Un avanzamento gratuito. 3. Si pesca 1 carta Azione e 1 Obiettivo. 4. Si può radere al suolo una città di dimensione 1 (+1 Oro). 5. Si può cambiare governo (1 Cultura e 1 Umore). 6. Chi ha più Umore + Cultura sceglie il primo giocatore.

[b]Uso dell'interfaccia[/b]
• Clicca una casella: a destra vedi città e unità, con i pulsanti per raccogliere, costruire, reclutare, fondare.
• «Muovi»: clicca la casella con le tue unità, spunta quali muovere e clicca la destinazione illuminata (verde muovi, rosso battaglia, viola esplora, azzurro imbarca, giallo con le Strade). «Fine movimento» chiude l'azione.
• Le scelte sulla mappa (dove mettere un colono, i barbari, il porto…) illuminano le caselle: basta un clic.
• Passa il mouse sopra avanzamenti e carte per leggere il testo in italiano.
• Trascina per ruotare, rotella o pizzico per lo zoom, tasto destro o Maiusc + trascina per spostare la vista. F11 schermo intero.

[b]Espansione Civiltà[/b] (opzione nel menu)
Ogni giocatore riceve a caso una delle 15 civiltà. I suoi 4 avanzamenti di civiltà arrivano gratis quando ottieni l'avanzamento collegato (senza far avanzare il segnaeventi); pulsante «Civiltà» per leggerli.
• Nuove unità d'armata: Cavalleria (1 Cibo + 1 Legno) ed Elefante (2 Cibo), solo in città con Mercato; Leader (1 Cultura + 1 Umore), uno solo alla volta, scelto fra i 3 della tua civiltà. Al massimo 4 unità d'armata per casella.
• Dado: icona Cavalleria +2; icona Elefante: il dado non conta ma annulla un colpo nemico; icona Leader: con un Leader in battaglia il dado si ritira. Le perdite tolgono prima la Fanteria e per ultimo il Leader.
• Chi uccide un Leader nemico ne tiene la carta: 2 PV. Ogni Leader ha due abilità (bonus in battaglia e altri effetti).
• Nuovi edifici: Mercato (Baratto: Cavalleria ed Elefanti, 1 Oro quando un avversario usa le Rotte Commerciali verso tue città con Mercato), Obelisco (Arti: immune all'Influenza, resta tuo anche se la città cade), Osservatorio (Matematica: peschi una carta Azione).
• Pirati: con l'icona «I Pirati sbarcano e razziano» compaiono 2 navi nere e razziano le città vicine (1 risorsa, Umore o Cultura). Bloccano raccolta e rotte nel loro mare e in quelli accanto; affondarle dà 1 Oro e 1 Umore o Cultura ciascuna.
• I Barbari possono ricevere Cavalleria ed Elefanti come rinforzi; 20 eventi e 6 obiettivi in più.
• Tutte le abilità di civiltà e dei Leader sono applicate: quelle che si usano a richiesta sono nel pulsante «Speciali»; Campi da Gioco e Shogunato compaiono come caselle nelle finestre di raccolta e reclutamento; Pace e Poesia si usa da sola quando manca il Cibo per un avanzamento.

[b]Cosa manca[/b]
Gli scambi liberi fra giocatori non sono gestiti. Nell'espansione non ci sono le varianti «Leader casuali» e «Storia alternativa»."""

var main


func _ready() -> void:
	size = Vector2(1920, 1080)
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/ui/stone.jpg")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.size = size
	add_child(bg)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.paper(34))
	pc.position = Vector2(220, 30)
	pc.size = Vector2(1480, 1020)
	add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	vb.add_child(UI.title("Regole in breve", 40, UI.INK))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var r := UI.rich(20, UI.INK)
	r.custom_minimum_size = Vector2(1380, 0)
	r.text = RULES
	sc.add_child(r)
	var b := UI.primary(UI.button("Torna al menu", 260, 54, 20))
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func(): main.show_menu())
	vb.add_child(b)
