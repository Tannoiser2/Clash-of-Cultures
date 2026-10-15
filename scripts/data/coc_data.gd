class_name CocData
extends RefCounted
## Dati di Clash of Cultures: Monumental Edition (gioco base). Nomi e testi in italiano.

const RES := ["food", "wood", "ore", "idea", "gold"]
const RES_NAME := {"food": "Cibo", "wood": "Legno", "ore": "Minerale", "idea": "Idee", "gold": "Oro",
	"mood": "Umore", "culture": "Cultura"}
const RES_ICON := {"food": "🌾", "wood": "🪵", "ore": "⛏", "idea": "💡", "gold": "🪙", "mood": "☺", "culture": "🏺"}

const TERRAIN := ["plains", "mountain", "forest", "barren", "sea"]
const TER_NAME := {"plains": "Pianura", "mountain": "Montagna", "forest": "Foresta", "barren": "Terre aride",
	"sea": "Mare", "": "Regione inesplorata"}
## risorsa raccolta da ciascun terreno
const TER_RES := {"plains": "food", "mountain": "ore", "forest": "wood", "barren": "", "sea": ""}

const COLORS := [
	{"key": "red", "name": "Rosso", "col": Color("#c0392b"), "light": Color("#ff8a75")},
	{"key": "purple", "name": "Viola", "col": Color("#7b3fa0"), "light": Color("#c79bea")},
	{"key": "blue", "name": "Blu", "col": Color("#2763b8"), "light": Color("#8fb8ff")},
	{"key": "yellow", "name": "Giallo", "col": Color("#e0b31a"), "light": Color("#ffe27a")},
]
const BARB_COLOR := Color("#7d7d7d")

const MOOD_NAME := ["Arrabbiata", "Neutrale", "Felice"]

# ------------------------------------------------------------------ edifici e unità

const BUILDINGS := ["temple", "academy", "fortress", "port"]
const B_NAME := {"temple": "Tempio", "academy": "Accademia", "fortress": "Fortezza", "port": "Porto"}
const B_REQ := {"temple": "Myths", "academy": "Writing", "fortress": "Tactics", "port": "Fishing"}
const B_TEXT := {
	"temple": "Alla costruzione: +1 Umore o +1 Cultura.",
	"academy": "Alla costruzione: +2 Idee.",
	"fortress": "Primo round di ogni battaglia nella città: +1 dado e annulla 1 colpo nemico, anche senza esercito.",
	"port": "La città recluta Navi. Può raccogliere 1 Oro o 1 Umore da un Mare adiacente al posto del Cibo.",
}
const UNITS := ["settler", "infantry", "ship"]
const U_NAME := {"settler": "Colono", "infantry": "Fanteria", "ship": "Nave"}
const U_PLURAL := {"settler": "Coloni", "infantry": "Fanterie", "ship": "Navi"}
const U_COST := {"settler": {"food": 2}, "infantry": {"food": 1, "ore": 1}, "ship": {"wood": 2}}
const LIMITS := {"settlement": 7, "temple": 5, "academy": 5, "fortress": 5, "port": 5,
	"settler": 4, "infantry": 16, "ship": 4}
const BARB_LIMIT := {"settlement": 10, "infantry": 20}
const BUILD_COST := {"food": 1, "wood": 1, "ore": 1}

# ------------------------------------------------------------------ avanzamenti
# bordo: "m" = +1 Umore, "c" = +1 Cultura, "" = niente

const CATEGORIES := ["Agriculture", "Construction", "Maritime", "Education", "Warfare", "Spirituality",
	"Economy", "Traditions", "Science", "Democracy", "Autocracy", "Theocracy"]
const GOVERNMENTS := ["Democracy", "Autocracy", "Theocracy"]
const GOV_REQ := {"Democracy": "Philosophy", "Autocracy": "Draft", "Theocracy": "State Religion"}
const CAT_NAME := {"Agriculture": "Agricoltura", "Construction": "Costruzioni", "Maritime": "Marineria",
	"Education": "Istruzione", "Warfare": "Arte della guerra", "Spirituality": "Spiritualità",
	"Economy": "Economia", "Traditions": "Tradizioni", "Science": "Scienza", "Democracy": "Democrazia",
	"Autocracy": "Autocrazia", "Theocracy": "Teocrazia"}

const ADV := {
	"Agriculture": [
		["Farming", "Coltivazione", "", "Le tue città raccolgono Cibo dalle Pianure e Legno dalle Foreste."],
		["Storage", "Magazzini", "m", "Il tuo limite di Cibo sale da 2 a 7."],
		["Irrigation", "Irrigazione", "m", "Le tue città raccolgono Cibo dalle Terre aride. Ignori gli eventi Carestia."],
		["Husbandry", "Allevamento", "m", "Una volta per turno: raccogli da 1 casella di terra a 2 caselle di distanza (2 caselle se hai Strade)."],
	],
	"Construction": [
		["Mining", "Estrazione", "", "Le tue città raccolgono Minerale dalle Montagne."],
		["Engineering", "Ingegneria", "", "Peschi subito 1 Meraviglia. Puoi costruire Meraviglie nelle città Felici."],
		["Sanitation", "Igiene", "m", "Reclutando: un singolo Colono costa 1 Umore. Ignori gli eventi Peste ed Epidemia."],
		["Roads", "Strade", "c", "Muovendo da o verso una tua città: paga 1 Cibo + 1 Minerale per gruppo per ignorare il terreno e/o muovere di 2 caselle."],
	],
	"Maritime": [
		["Fishing", "Pesca", "m", "Le tue città raccolgono Cibo da un Mare adiacente. Permette il Porto."],
		["Navigation", "Navigazione", "c", "Le navi possono girare attorno al tabellone fino al gruppo di Mari successivo."],
		["Warships", "Navi da guerra", "", "Annulli 1 colpo nel primo round delle battaglie navali e quando l'esercito sbarca all'attacco."],
		["Cartography", "Cartografia", "", "Dopo un'azione Muovi in cui hai mosso almeno 1 nave: +1 Idea (+1 Cultura se hai usato la Navigazione)."],
	],
	"Education": [
		["Writing", "Scrittura", "c", "Peschi subito 1 carta Azione e 1 carta Obiettivo. Permette l'Accademia."],
		["Public Education", "Istruzione pubblica", "m", "Una volta per turno: +1 Idea raccogliendo in una città con Accademia."],
		["Free Education", "Istruzione gratuita", "m", "Dopo aver comprato un avanzamento pagando almeno 1 Oro o Idea: puoi cambiare 1 Idea in 1 Umore."],
		["Philosophy", "Filosofia", "m", "Subito +1 Idea. +1 Idea per ogni avanzamento di Scienza che otterrai."],
	],
	"Warfare": [
		["Tactics", "Tattica", "c", "Puoi muovere gli eserciti e usare le tattiche delle carte Azione. Permette la Fortezza."],
		["Siegecraft", "Arte d'assedio", "", "Prima di attaccare una Fortezza: 2 Legno annullano il suo dado in più, 2 Minerale il suo colpo annullato."],
		["Steel Weapons", "Armi d'acciaio", "", "Prima di una battaglia di terra: paga 1 Minerale per +2 al valore di combattimento ogni round (+1 se anche il nemico le ha)."],
		["Draft", "Leva", "c", "Reclutando: una singola Fanteria costa 1 Umore."],
	],
	"Spirituality": [
		["Myths", "Miti", "m", "Paga 1 Umore per evitare di peggiorare l'umore di una città a causa di un evento. Permette il Tempio."],
		["Rituals", "Riti", "c", "Aumentando la felicità puoi pagare con qualsiasi risorsa al posto dell'Umore."],
		["Priesthood", "Sacerdozio", "", "Una volta per turno: compri un avanzamento di Scienza senza pagare Cibo."],
		["State Religion", "Religione di Stato", "m", "Una volta per turno: costruisci un Tempio senza pagare Cibo."],
	],
	"Economy": [
		["Bartering", "Baratto", "m", "Azione gratuita, una volta per turno: scarta una carta per 1 Oro o 1 Cultura."],
		["Taxation", "Tassazione", "", "Come azione, una volta per turno: paga 1 Umore per avere 1 Cibo, 1 Minerale o 1 Legno per città."],
		["Trade Routes", "Rotte commerciali", "", "A inizio turno: +1 Cibo per Nave o Colono (max 4) abbinato a una diversa città nemica non arrabbiata entro 2 caselle."],
		["Currency", "Moneta", "c", "Con Tassazione e Rotte commerciali puoi prendere Oro al posto delle altre risorse."],
	],
	"Traditions": [
		["Arts", "Arti", "c", "Azione gratuita, una volta per turno: paga 1 Cultura per un'azione Influenza la cultura."],
		["Circus & Sports", "Circo e giochi", "m", "Come azione: paga 1 o 2 Cultura per migliorare di 1 o 2 passi l'umore di una città."],
		["Monuments", "Monumenti", "c", "Peschi subito 1 Meraviglia. I nemici non possono influenzare le tue città con Meraviglie."],
		["Drama & Music", "Teatro e musica", "m", "Azione gratuita, una volta per turno: cambia 1 Umore in 1 Cultura o viceversa."],
	],
	"Science": [
		["Math", "Matematica", "c", "Ingegneria e Strade si comprano senza pagare Cibo."],
		["Astronomy", "Astronomia", "c", "Navigazione e Cartografia si comprano senza pagare Cibo."],
		["Medicine", "Medicina", "c", "Dopo un reclutamento: riprendi 1 risorsa spesa."],
		["Metallurgy", "Metallurgia", "c", "Raccogliendo almeno 2 Minerale, 1 può diventare Oro. Usi le Armi d'acciaio gratis contro chi non le ha."],
	],
	"Democracy": [
		["Voting", "Voto", "", "Azione gratuita: paga 1 Umore per un'azione Aumenta la felicità. (Serve Filosofia.)"],
		["Separation of Power", "Separazione dei poteri", "", "I nemici non possono potenziare l'Influenza contro le tue città Felici."],
		["Civil Liberties", "Libertà civili", "", "Come azione: +3 Umore. La Fanteria con la Leva ti costa 1 Umore in più."],
		["Economic Liberty", "Libertà economica", "", "Azione gratuita: paga 1 Umore per raccogliere (sarà l'unica raccolta del turno)."],
	],
	"Autocracy": [
		["Nationalism", "Nazionalismo", "", "Dopo aver reclutato almeno 1 esercito o nave: +1 Umore o +1 Cultura. (Serve Leva.)"],
		["Totalitarianism", "Totalitarismo", "", "I nemici non possono potenziare l'Influenza contro le tue città con eserciti."],
		["Absolute Power", "Potere assoluto", "", "Una volta per turno: paga 2 Umore per un'azione in più."],
		["Forced Labor", "Lavori forzati", "", "Paga 1 Umore: in questo turno le città Arrabbiate valgono come Neutrali (ma si attivano una volta sola)."],
	],
	"Theocracy": [
		["Dogma", "Dogma", "", "Costruendo un Tempio ottieni gratis un avanzamento di Teocrazia. Limite di 2 Idee. (Serve Religione di Stato.)"],
		["Devotion", "Devozione", "", "I nemici non possono potenziare l'Influenza contro le tue città con Tempio."],
		["Conversion", "Conversione", "", "+1 al tiro di Influenza; ogni successo ti dà +1 Cultura."],
		["Fanaticism", "Fanatismo", "", "Battaglie in una città con Tempio: +2 al primo tiro; se perdi, Fanteria gratis in una tua città."],
	],
}

static var _adv_index := {}

static func adv_info(name: String) -> Dictionary:
	if _adv_index.is_empty():
		for cat in CATEGORIES:
			var lst: Array = ADV[cat]
			for i in lst.size():
				var a: Array = lst[i]
				_adv_index[a[0]] = {"name": a[0], "it": a[1], "border": a[2], "text": a[3], "cat": cat, "pos": i}
	return _adv_index.get(name, {})


static func adv_it(name: String) -> String:
	return adv_info(name).get("it", name)


static func all_advances() -> Array:
	var out := []
	for cat in CATEGORIES:
		for a in ADV[cat]:
			out.append(a[0])
	return out

# ------------------------------------------------------------------ meraviglie
# costi: minerale, legno, cibo, cultura

const WONDERS := {
	"great_mausoleum": {"it": "Grande Mausoleo", "img": 0, "cost": {"ore": 4, "wood": 4, "food": 4, "culture": 5}, "req": "Priesthood",
		"text": "Pescando una carta Evento o Azione puoi prendere la prima degli scarti. I tuoi scarti finiscono in fondo alla pila."},
	"great_lighthouse": {"it": "Grande Faro", "img": 1, "cost": {"ore": 4, "wood": 5, "food": 3, "culture": 5}, "req": "Cartography",
		"text": "Va costruito in una città con Porto. Attivando la città: Nave gratis in un Mare senza navi nemiche. Decidi sempre tu il primo giocatore."},
	"great_wall": {"it": "Grande Muraglia", "img": 2, "cost": {"ore": 7, "wood": 2, "food": 3, "culture": 5}, "req": "Siegecraft",
		"text": "Primo round: -2 ai nemici che attaccano le tue città Felici. Sconfiggi automaticamente i Barbari che attaccano le tue città."},
	"great_arena": {"it": "Grande Arena", "img": 3, "cost": {"ore": 5, "wood": 4, "food": 3, "culture": 5}, "req": "Circus & Sports",
		"text": "Umore e Cultura sono intercambiabili (non per le Meraviglie). Una volta per battaglia di terra: paga 1 Umore o Cultura per +1 dopo il tiro."},
	"great_pyramids": {"it": "Grandi Piramidi", "img": 4, "cost": {"ore": 7, "wood": 3, "food": 2, "culture": 5}, "req": "Rituals",
		"text": "Vale 5 PV, che tieni anche se la città viene conquistata. Vinci tu i pareggi a fine partita."},
	"great_statue": {"it": "Grande Statua", "img": 5, "cost": {"ore": 5, "wood": 4, "food": 3, "culture": 5}, "req": "Monuments",
		"text": "Costruendola peschi 1 Obiettivo. Una volta per turno: scarta un Obiettivo per un'azione in più."},
	"great_library": {"it": "Grande Biblioteca", "img": 6, "cost": {"ore": 3, "wood": 6, "food": 3, "culture": 5}, "req": "Philosophy",
		"text": "In ogni tuo turno puoi usare un avanzamento non di governo che non possiedi, fino a fine turno."},
	"great_gardens": {"it": "Grandi Giardini", "img": 7, "cost": {"ore": 2, "wood": 5, "food": 5, "culture": 5}, "req": "Irrigation",
		"text": "La città raccoglie qualsiasi risorsa dalle Pianure. Le unità nemiche entrate in una Pianura non possono attaccarla nello stesso turno."},
}

# ------------------------------------------------------------------ carte Azione
# id: codice stampato (a1..a42). top: effetto fuori dal combattimento, tac: tattica.
# timing top: "free" azione gratuita, "action" costa un'azione, "collect" giocata raccogliendo,
# "influence" dichiarando un'Influenza, "after_win", "after_capture", "start" inizio turno.

const ACTION_TOPS := {
	"advance": {"it": "Avanzamento", "cost": 1, "timing": "free",
		"text": "Paga 1 Cultura. Azione gratuita: ottieni un avanzamento senza pagare Cibo (cubetto dalla riserva)."},
	"leadership": {"it": "Comando", "cost": 1, "timing": "free",
		"text": "Paga 1 Cultura. Ottieni un'azione in più in questo turno."},
	"mercenaries": {"it": "Mercenari", "cost": 0, "timing": "action",
		"text": "Come azione: muovi di 1 casella eserciti barbari entro 2 caselle da tue città o eserciti, pagando 1 Cibo, Legno, Minerale o Cultura ciascuno; poi 1 Barbaro nelle città da cui sono partiti."},
	"cultural_awe": {"it": "Soggezione culturale", "cost": 0, "timing": "influence",
		"text": "Dichiarando un'Influenza puoi bersagliare una città barbara di dimensione 1: se riesce diventa tua (un barbaro può diventare Colono o Fanteria)."},
	"teach_us": {"it": "Insegnateci!", "cost": 0, "timing": "after_capture",
		"text": "Dopo aver conquistato una città di un giocatore: copia gratis un suo avanzamento."},
	"militia": {"it": "Milizia", "cost": 1, "timing": "free",
		"text": "Paga 1 Cultura. Azione gratuita: Fanteria gratis in una tua città (che non si attiva)."},
	"mass_collection": {"it": "Raccolta in massa", "cost": 0, "timing": "collect",
		"text": "Raccogliendo: 2 risorse in più del normale (sempre una per casella)."},
	"tech_exchange": {"it": "Scambio tecnologico", "cost": 0, "timing": "free",
		"text": "Azione gratuita: copia un avanzamento di un giocatore vicino (entro 2 caselle); lui ne copia uno tuo. Senza pagare Cibo."},
	"good_ideas": {"it": "Buone idee", "cost": 0, "timing": "after_win",
		"text": "Nel tuo turno, dopo una conquista o una battaglia vinta contro un esercito: +2 Idee."},
	"spies": {"it": "Spie", "cost": 1, "timing": "action",
		"text": "Paga 1 Cultura. Come azione: guarda le carte di un giocatore e scambia una tua carta con una sua dello stesso tipo."},
	"assassination": {"it": "Assassinio", "cost": 1, "timing": "free",
		"text": "Paga 1 Cultura. Azione gratuita: un giocatore avrà un'azione in meno nel suo prossimo turno."},
	"leap_knowledge": {"it": "Balzo del sapere", "cost": 0, "timing": "free",
		"text": "Azione gratuita: +1 Idea per ogni tua città con Accademia."},
	"inspiration": {"it": "Ispirazione", "cost": 0, "timing": "free",
		"text": "Azione gratuita: copia senza pagare Cibo un avanzamento di un giocatore che hai entro 2 caselle."},
	"focused_collection": {"it": "Raccolta mirata", "cost": 0, "timing": "collect",
		"text": "Raccogliendo puoi prendere più volte dalla stessa casella di terra."},
	"tech_synergy": {"it": "Sinergia tecnologica", "cost": 0, "timing": "action",
		"text": "Come azione: compra due avanzamenti della stessa categoria."},
	"explorers": {"it": "Esploratori", "cost": 1, "timing": "action",
		"text": "Paga 1 Cultura. Come azione: scopri una regione vicina a una tua città e/o metti un Colono gratis in una tua città."},
	"idea_synergy": {"it": "Sinergia di idee", "cost": 0, "timing": "action",
		"text": "Come azione: compra un avanzamento e poi +2 Idee."},
	"new_goals": {"it": "Nuovi obiettivi", "cost": 1, "timing": "action",
		"text": "Paga 1 Cultura. Come azione: pesca 2 Obiettivi e puoi scambiarne uno con uno dei tuoi."},
	"negotiations": {"it": "Trattative", "cost": 1, "timing": "start",
		"text": "Paga 1 Cultura, a inizio turno: scegli un giocatore; né tu lui né lui te potrete attaccarvi fino al suo prossimo turno."},
	"heroic_general": {"it": "Generale eroico", "cost": 0, "timing": "after_win",
		"text": "Nel tuo turno, dopo una battaglia vinta contro un esercito: migliora di un passo l'umore di una città (paga 1 Umore per un secondo passo)."},
	"city_growth": {"it": "Crescita urbana", "cost": 1, "timing": "action",
		"text": "Paga 1 Cultura. Come azione: costruisci un edificio senza pagare risorse (la città si attiva)."},
}

const TACTICS := {
	"peltasts": {"it": "Peltasti", "units": "A", "text": "Rivelandola: tira un dado per ogni tuo esercito; con almeno un 5 o 6 annulli 1 colpo."},
	"archers": {"it": "Arcieri", "units": "A", "text": "Rivelandola: tira un dado; con 5 o 6 il nemico perde subito un esercito."},
	"for_the_people": {"it": "Per il popolo", "units": "AF", "text": "Difendendo una città: +1 dado."},
	"defiant_stand": {"it": "Resistenza", "units": "AFS", "text": "In difesa: il nemico ha -1 per ogni sua unità in battaglia."},
	"prepared_defenses": {"it": "Difese preparate", "units": "AFS", "text": "In difesa: +1 dado."},
	"high_morale": {"it": "Morale alto", "units": "AFS", "text": "+2 al valore di combattimento."},
	"high_ground": {"it": "Altura", "units": "AF", "text": "Il nemico non attiva abilità di scontro. Non vale attaccando città."},
	"wedge": {"it": "Formazione a cuneo", "units": "A", "text": "In attacco: +1 per ogni esercito nemico."},
	"tactical_retreat": {"it": "Ritirata tattica", "units": "A", "text": "In difesa: la battaglia finisce, ti ritiri in una casella adiacente libera; vince il nemico."},
	"routing": {"it": "Rotta", "units": "A", "text": "Se hai eliminato almeno quanto il nemico: con 5 o 6 su un dado elimini un'altra unità."},
	"tactical_surprise": {"it": "Sorpresa tattica", "units": "AFS", "text": "+1; se elimini almeno un'unità peschi una carta Azione."},
	"flanking": {"it": "Aggiramento", "units": "AS", "text": "In attacco: +1 dado."},
	"siege": {"it": "Assedio", "units": "A", "text": "Attaccando una città: +1 e il nemico non attiva abilità di scontro (salvo pagare 2 Cibo)."},
	"scouts": {"it": "Esploratori avanzati", "units": "AFS", "text": "Annulla la carta del nemico e prendila in mano."},
	"martyr": {"it": "Martirio", "units": "AS", "text": "Elimina una tua unità: il nemico fa lo stesso e la sua carta è annullata."},
}

## Le 42 carte Azione: [codice, effetto, tattica]
const ACTIONS := [
	["a1", "advance", "peltasts"], ["a2", "advance", "routing"], ["a3", "inspiration", "routing"],
	["a4", "inspiration", "peltasts"], ["a5", "heroic_general", "wedge"], ["a6", "heroic_general", "high_morale"],
	["a7", "spies", "defiant_stand"], ["a8", "spies", "high_morale"], ["a9", "leap_knowledge", "high_ground"],
	["a10", "leap_knowledge", "tactical_surprise"], ["a11", "good_ideas", "siege"], ["a12", "good_ideas", "high_ground"],
	["a13", "mercenaries", "for_the_people"], ["a14", "mercenaries", "defiant_stand"], ["a15", "cultural_awe", "defiant_stand"],
	["a16", "cultural_awe", "upgraded_defenses"], ["a17", "city_growth", "tactical_retreat"], ["a18", "city_growth", "peltasts"],
	["a19", "focused_collection", "tactical_retreat"], ["a20", "focused_collection", "peltasts"], ["a21", "explorers", "routing"],
	["a22", "explorers", "prepared_defenses"], ["a23", "negotiations", "scouts"], ["a24", "negotiations", "martyr"],
	["a25", "leadership", "high_ground"], ["a26", "leadership", "archers"], ["a27", "assassination", "high_ground"],
	["a28", "assassination", "archers"], ["a29", "mass_collection", "prepared_defenses"], ["a30", "mass_collection", "routing"],
	["a31", "new_goals", "flanking"], ["a32", "new_goals", "high_morale"], ["a33", "tech_synergy", "prepared_defenses"],
	["a34", "tech_synergy", "archers"], ["a35", "teach_us", "prepared_defenses"], ["a36", "teach_us", "archers"],
	["a37", "militia", "wedge"], ["a38", "militia", "high_morale"], ["a39", "tech_exchange", "tactical_surprise"],
	["a40", "tech_exchange", "high_ground"], ["a41", "idea_synergy", "high_morale"], ["a42", "idea_synergy", "flanking"],
]

# Correzione: in alcune carte "for_the_people" e "upgraded_defenses" (A16)
const TACTICS_EXTRA := {
	"upgraded_defenses": {"it": "Difese potenziate", "units": "AF", "text": "Difendendo una città: annulli un colpo ricevuto."},
}

# ------------------------------------------------------------------ obiettivi
# kind: "status" (fase di status) o "now" (subito, dopo una battaglia/conquista/fondazione)

const OBJ := {
	"focused": ["Specializzato", "status", "Hai più categorie complete (4 avanzamenti) di ogni altro giocatore."],
	"daring": ["Audace", "now", "Vinci una battaglia di terra contro chi ha più avanzamenti di guerra o contro un esercito più numeroso."],
	"diverse": ["Varietà", "status", "Hai almeno 4 tipi diversi di edificio del tuo colore nelle tue città."],
	"militarized": ["Militarizzato", "status", "Hai tutti e 4 gli avanzamenti di Arte della guerra."],
	"new_founder": ["Nuovo fondatore", "now", "Fondi una città ad almeno 5 caselle dalla tua prima città."],
	"defiance": ["Sfida", "now", "Attaccato, elimini almeno 2 eserciti nella battaglia."],
	"culture": ["Cultura", "status", "Hai tutti e 4 gli avanzamenti di Tradizioni."],
	"legend": ["Leggenda", "now", "Combatti contro una città di dimensione 5 o con Meraviglia attaccando con almeno 3 eserciti."],
	"consulates": ["Consolati", "status", "Hai influenza culturale in almeno 2 diverse città nemiche."],
	"great_battle": ["Grande battaglia", "now", "Vinci una battaglia con almeno 6 eserciti in totale fra i due schieramenti."],
	"colony": ["Colonia", "status", "Hai una città ad almeno 5 caselle dalla tua prima città."],
	"threat": ["Minaccia", "status", "Hai almeno 4 eserciti in caselle di terra adiacenti a una città di un altro giocatore."],
	"wonderful": ["Meraviglioso", "status", "Sei l'unico ad aver costruito Meraviglie in questa partita (o in questa era)."],
	"outposts": ["Avamposti", "status", "Hai eserciti in almeno 3 caselle di terra non adiacenti e non dentro tue città."],
	"enlightened": ["Illuminato", "status", "Hai tutti e 4 gli avanzamenti di Istruzione."],
	"blockade": ["Blocco", "status", "Hai almeno 2 navi in un Mare con il Porto di un nemico."],
	"government": ["Governo", "status", "Hai tutti e 4 gli avanzamenti di una categoria di governo (una volta per partita)."],
	"aggressor": ["Aggressore", "now", "Elimini almeno 2 eserciti in una battaglia iniziata da te contro un giocatore."],
	"religious": ["Religioso", "status", "Hai più città con Tempio di ogni altro giocatore."],
	"warlord": ["Signore della guerra", "now", "Elimini almeno 3 eserciti in una battaglia."],
	"ore": ["Minerale!", "status", "Hai almeno 5 Minerale; ne paghi 2."],
	"great_army": ["Grande esercito", "status", "Hai almeno 4 eserciti più di ogni altro giocatore."],
	"wood": ["Legno!", "status", "Hai almeno 5 Legno; ne paghi 2."],
	"fortified": ["Fortificato", "status", "Hai più città con Fortezza di ogni altro giocatore."],
	"balanced": ["Equilibrato", "status", "Hai almeno 1 avanzamento in almeno 9 categorie."],
	"seafarer": ["Navigatore", "status", "Hai tutti e 4 gli avanzamenti di Marineria."],
	"influence": ["Influenza", "status", "Hai più edifici nemici sotto la tua influenza di ogni altro giocatore."],
	"assimilator": ["Assimilatore", "now", "Conquisti una città barbara difesa da almeno 2 barbari."],
	"advanced": ["Avanzato", "status", "Hai almeno 6 avanzamenti e più di ogni altro giocatore."],
	"warmonger": ["Guerrafondaio", "now", "Nel tuo turno combatti due battaglie contro eserciti o città diversi e ne vinci almeno una."],
	"food": ["Cibo!", "status", "Hai almeno 5 Cibo; ne paghi 2."],
	"standing_army": ["Esercito permanente", "status", "Hai almeno 4 città con eserciti."],
	"dominion": ["Dominio", "status", "Hai almeno 4 città senza altre città nelle caselle adiacenti."],
	"military_might": ["Potenza militare", "status", "Hai in tutto almeno 12 fra eserciti e navi."],
	"city_planner": ["Urbanista", "status", "Hai tutti e 4 gli avanzamenti di Costruzioni."],
	"ideas": ["Idee!", "status", "Hai almeno 5 Idee; ne paghi 2."],
	"against_odds": ["Contro ogni pronostico", "now", "Vinci una battaglia contro un giocatore pur avendo meno eserciti o navi."],
	"merchant": ["Mercante", "status", "Hai tutti e 4 gli avanzamenti di Economia."],
	"marauder": ["Predone", "now", "In battaglia elimini un Colono o una Nave nemici utili alle Rotte commerciali."],
	"citadel": ["Cittadella", "status", "Hai una città di 5 pezzi."],
	"trader": ["Commerciante", "status", "Hai almeno 3 rotte commerciali."],
	"civilization": ["Civiltà!", "status", "Hai almeno 6 città."],
	"draft": ["Coscrizione", "now", "Recluti due volte in un turno usando entrambe le volte la Leva."],
	"well_stocked": ["Ben fornito", "status", "Hai almeno 3 Cibo, 3 Minerale e 3 Legno."],
	"amphibious": ["Assalto anfibio", "now", "Conquisti la città di un giocatore attaccando da una nave."],
	"rich": ["Ricco", "status", "Hai almeno 5 Oro; ne paghi 2."],
	"great_navy": ["Grande flotta", "status", "Hai 4 navi o almeno 2 più di ogni altro giocatore."],
	"sea_lanes": ["Rotte marittime", "status", "Hai almeno 2 rotte commerciali con le navi."],
	"draconian": ["Draconiano", "now", "Hai 4 o più città arrabbiate."],
	"academic": ["Accademico", "status", "Hai più città con Accademia di ogni altro giocatore."],
	"conqueror": ["Conquistatore", "now", "Conquisti una città difesa (esercito o Fortezza) di un giocatore."],
	"coastal": ["Cultura costiera", "status", "Hai più città con Porto di ogni altro giocatore."],
	"science": ["Scienza", "status", "Hai tutti e 4 gli avanzamenti di Scienza."],
	"happy": ["Felicità", "status", "Hai almeno 4 città felici."],
}

## Le 32 carte Obiettivo del gioco base: [numero immagine, obiettivo sopra, obiettivo sotto]
const OBJECTIVES := [
	[1, "focused", "daring"], [5, "diverse", "militarized"], [6, "new_founder", "defiance"], [7, "culture", "legend"],
	[8, "consulates", "great_battle"], [9, "colony", "threat"], [10, "wonderful", "outposts"], [11, "enlightened", "blockade"],
	[13, "government", "aggressor"], [14, "religious", "warlord"], [15, "ore", "great_army"], [16, "wood", "fortified"],
	[17, "balanced", "daring"], [18, "seafarer", "aggressor"], [19, "influence", "assimilator"], [20, "advanced", "warmonger"],
	[21, "food", "standing_army"], [22, "dominion", "military_might"], [23, "city_planner", "great_battle"],
	[24, "ideas", "against_odds"], [26, "merchant", "marauder"], [27, "citadel", "warlord"], [28, "trader", "defiance"],
	[29, "civilization", "draft"], [30, "well_stocked", "amphibious"], [31, "rich", "great_navy"],
	[32, "government", "assimilator"], [33, "sea_lanes", "draconian"], [34, "academic", "conqueror"],
	[35, "coastal", "warmonger"], [37, "science", "amphibious"], [38, "happy", "conqueror"],
]

# ------------------------------------------------------------------ eventi
# icon: "" | "gold" | "exhaust" | "barb_spawn" | "barb_move"

const EVENTS := {
	"e1": ["Peste", "", "plague", "Chi ha Igiene la ignora. Chi ha almeno 2 città peggiora l'umore di una città (due con Strade, Navigazione o Rotte commerciali). Chi non ha Igiene non può costruire finché chi l'ha pescata non pesca un nuovo evento."],
	"e2": ["Epidemia", "", "epidemic", "Chi ha Igiene la ignora. Chi ha almeno 2 unità ne rimuove una (due con Strade, Navigazione o Rotte commerciali)."],
	"e3": ["Carestia", "barb_move", "famine1", "Chi ha Irrigazione la ignora. Perdi 1 Cibo; se non puoi, una tua città diventa Arrabbiata. L'Oro non sostituisce il Cibo."],
	"e4": ["Carestia", "barb_move", "famine1", ""],
	"e5": ["Carestia", "barb_move", "famine1", ""],
	"e6": ["Grave carestia", "barb_move", "famine2", "Chi ha Irrigazione la ignora. Perdi 2 Cibo; se non puoi, perdi quanto hai e una tua città diventa Arrabbiata."],
	"e7": ["Grave carestia", "barb_move", "famine2", ""],
	"e8": ["Grave carestia", "barb_move", "famine2", ""],
	"e9": ["Un buon anno", "barb_spawn", "fine_all", "Tutti i giocatori ricevono 1 Cibo."],
	"e10": ["Un buon anno", "barb_spawn", "fine_you", "Ricevi 1 Cibo."],
	"e11": ["Un buon anno", "barb_spawn", "fine_other", "Ricevi 1 Cibo e scegli un altro giocatore che riceve 1 Cibo."],
	"e12": ["Un anno prospero", "barb_spawn", "good_you", "Ricevi 2 Cibo."],
	"e13": ["Un anno prospero", "exhaust", "good_all", "Tutti i giocatori ricevono 2 Cibo."],
	"e14": ["Un anno prospero", "exhaust", "good_other", "Ricevi 2 Cibo; un altro giocatore ne riceve 2 (o due giocatori 1 ciascuno)."],
	"e15": ["Un anno splendido", "barb_spawn", "splendid_all", "Tutti i giocatori ricevono 3 Cibo."],
	"e16": ["Un anno splendido", "barb_spawn", "splendid_other", "Ricevi 3 Cibo e ne distribuisci altri 3 fra gli altri giocatori."],
	"e17": ["Un anno splendido", "barb_spawn", "splendid_you", "Ricevi 3 Cibo."],
	"e18": ["Grande scopritore", "exhaust", "gp_discoverer", "Come azione: avanzamento gratis di Marineria e/o scopri una regione vicina a una tua città (puoi pagare 2 Cibo per fondarvi una città)."],
	"e19": ["Grande artista", "barb_move", "gp_artist", "Come azione: avanzamento gratis di Tradizioni e/o una tua città diventa Felice."],
	"e20": ["Grande profeta", "barb_move", "gp_prophet", "Come azione: avanzamento gratis di Spiritualità e/o costruisci un Tempio senza attivare la città."],
	"e21": ["Grande filosofo", "barb_move", "gp_philosopher", "Come azione: avanzamento gratis di Istruzione e/o +2 Idee."],
	"e22": ["Grande scienziato", "barb_move", "gp_scientist", "Come azione: avanzamento gratis di Scienza e/o +1 Idea e 1 carta Azione."],
	"e23": ["Grande statista", "barb_move", "gp_statesman", "Come azione: avanzamento gratis di governo e/o pesca 2 carte Azione."],
	"e24": ["Grande condottiero", "exhaust", "gp_warlord", "Come azione: avanzamento gratis di Arte della guerra e/o un'azione Muovi con +2 in una battaglia."],
	"e25": ["Grande mercante", "barb_move", "gp_merchant", "Come azione: avanzamento gratis di Economia e/o incassi tutte le tue rotte commerciali."],
	"e26": ["Grande ingegnere", "barb_move", "gp_engineer", "Come azione: avanzamento gratis di Costruzioni e/o costruisci un edificio senza attivare la città."],
	"e27": ["Boom demografico", "barb_spawn", "boom", "Metti un Colono gratis in una tua città; un altro giocatore a tua scelta fa lo stesso."],
	"e28": ["Boom demografico", "barb_move", "boom", ""],
	"e29": ["Vulcano", "", "volcano", "Se hai almeno 4 città: una tua città è distrutta con le unità presenti. Ogni pezzo (non Meraviglia) vale 2 PV al suo proprietario."],
	"e30": ["Terremoto", "", "earthquake", "Se hai almeno 3 città: togli da 1 a 3 pezzi di città (2 PV ciascuno); le città ridotte peggiorano l'umore."],
	"e31": ["Grande terremoto", "", "major_earthquake", "Ogni giocatore con almeno 3 città toglie da 1 a 3 pezzi di città (2 PV ciascuno)."],
	"e32": ["Alluvione", "", "local_flood", "Peggiora l'umore di una tua città adiacente al Mare."],
	"e33": ["Grande alluvione", "", "major_flood", "Ogni giocatore peggiora l'umore di una sua città adiacente al Mare."],
	"e34": ["Migrazione", "gold", "migration", "Un altro giocatore a tua scelta mette un Colono gratis in una sua città; tu peggiori l'umore di una tua città."],
	"e35": ["Migrazione", "gold", "migration", ""],
	"e36": ["Guerra civile", "", "civil_war", "Se hai una città Neutrale o Arrabbiata con Fanteria: perde una Fanteria e peggiora l'umore. Altrimenti peggiora l'umore di una città."],
	"e37": ["Guerra civile", "", "civil_war", ""],
	"e38": ["Rivoluzione", "gold", "revolution", "Perdi un'azione e passi i tuoi avanzamenti di governo a un'altra forma di governo. Puoi evitare un effetto per ogni Fanteria che elimini."],
}

const GREAT_PERSON_CAT := {"gp_discoverer": "Maritime", "gp_artist": "Traditions", "gp_prophet": "Spirituality",
	"gp_philosopher": "Education", "gp_scientist": "Science", "gp_statesman": "gov", "gp_warlord": "Warfare",
	"gp_merchant": "Economy", "gp_engineer": "Construction"}


static func event_text(id: String) -> String:
	var e: Array = EVENTS[id]
	if e[3] != "":
		return e[3]
	for k in EVENTS:
		if EVENTS[k][2] == e[2] and EVENTS[k][3] != "":
			return EVENTS[k][3]
	return ""


static func card_title(id: String) -> String:
	if id.begins_with("a"):
		for a in ACTIONS:
			if a[0] == id:
				return ACTION_TOPS[a[1]]["it"]
	elif id.begins_with("e"):
		return EVENTS[id][0]
	elif id.begins_with("o"):
		var o := objective_card(id)
		return "%s / %s" % [OBJ[o[1]][0], OBJ[o[2]][0]]
	elif WONDERS.has(id):
		return WONDERS[id]["it"]
	return id


static func action_card(id: String) -> Array:
	for a in ACTIONS:
		if a[0] == id:
			return a
	return []


static func tactic(key: String) -> Dictionary:
	if TACTICS.has(key):
		return TACTICS[key]
	return TACTICS_EXTRA.get(key, {})


static func objective_card(id: String) -> Array:
	var num := int(id.substr(1))
	for o in OBJECTIVES:
		if o[0] == num:
			return o
	return []


static func card_image(id: String) -> String:
	if WONDERS.has(id):
		return "res://assets/cards/w%d.jpg" % WONDERS[id]["img"]
	return "res://assets/cards/%s.jpg" % id
