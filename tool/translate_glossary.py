#!/usr/bin/env python3
"""Merge author-drafted ES/FR/IT/DE definition translations into glossary.json.

Felix-authored (2026-06-12). The TERM and its abbr stay English by convention
(professionals do not translate "beamforming", "OFDMA", "RSSI"); only the
explanatory DEFINITION is localized. Translations are DRAFTS pending
professional review — the dataset carries `translation_status:
draft-needs-review` and each translated term carries the same flag.

Run from the repo root:  python3 tool/translate_glossary.py
Idempotent: re-running rewrites the same `definitions` blocks.
"""
import json
import sys
from pathlib import Path

ASSET = Path("assets/data/glossary.json")

# id -> {lang: translated definition}. Technical tokens (Wi-Fi, band names,
# acronyms, units) are kept verbatim; explanatory prose is translated. Accuracy
# over fluency: where a concept has no clean idiomatic rendering, the wording
# stays close to the literal English meaning.
T = {
    "2-4-ghz-band": {
        "es": "La banda Wi-Fi más antigua. Llega más lejos y atraviesa mejor las paredes que las bandas superiores, pero está saturada: en la práctica solo ofrece tres canales de 20 MHz que no se solapan (1, 6 y 11 en la mayoría de las regiones) y comparte espacio con Bluetooth, microondas y muchos otros dispositivos.",
        "fr": "La bande Wi-Fi la plus ancienne. Elle porte plus loin et traverse mieux les murs que les bandes supérieures, mais elle est encombrée : en pratique elle n'offre que trois canaux de 20 MHz sans chevauchement (1, 6 et 11 dans la plupart des régions) et partage l'espace avec le Bluetooth, les fours à micro-ondes et bien d'autres appareils.",
        "it": "La banda Wi-Fi più vecchia. Arriva più lontano e attraversa meglio i muri rispetto alle bande superiori, ma è affollata: in pratica offre solo tre canali da 20 MHz non sovrapposti (1, 6 e 11 nella maggior parte delle regioni) e condivide lo spazio con Bluetooth, forni a microonde e molti altri dispositivi.",
        "de": "Das älteste WLAN-Band. Es reicht weiter und durchdringt Wände besser als höhere Bänder, ist aber überfüllt: In der Praxis bietet es nur drei sich nicht überlappende 20-MHz-Kanäle (1, 6 und 11 in den meisten Regionen) und teilt sich den Raum mit Bluetooth, Mikrowellen und vielen anderen Geräten.",
    },
    "5-ghz-band": {
        "es": "La banda Wi-Fi de trabajo. Ofrece muchos más canales y mucha más capacidad que la de 2,4 GHz, a costa de menor alcance y peor penetración en las paredes.",
        "fr": "La bande Wi-Fi de travail. Elle offre beaucoup plus de canaux et bien plus de capacité que celle de 2,4 GHz, au prix d'une portée plus courte et d'une pénétration des murs plus faible.",
        "it": "La banda Wi-Fi di lavoro. Offre molti più canali e una capacità molto maggiore rispetto a quella da 2,4 GHz, al costo di una portata più breve e di una minore penetrazione attraverso i muri.",
        "de": "Das Arbeitspferd unter den WLAN-Bändern. Es bietet viel mehr Kanäle und deutlich mehr Kapazität als 2,4 GHz, allerdings bei kürzerer Reichweite und schwächerer Wanddurchdringung.",
    },
    "6-ghz-band": {
        "es": "La banda Wi-Fi más nueva, abierta para Wi-Fi 6E y Wi-Fi 7. Aporta un gran bloque de espectro limpio con muchos canales anchos, pero solo los dispositivos más nuevos pueden usarla y su alcance es el más corto de las tres bandas.",
        "fr": "La bande Wi-Fi la plus récente, ouverte pour le Wi-Fi 6E et le Wi-Fi 7. Elle ajoute un large bloc de spectre propre avec de nombreux canaux larges, mais seuls les appareils récents peuvent l'utiliser et sa portée est la plus courte des trois bandes.",
        "it": "La banda Wi-Fi più recente, aperta per il Wi-Fi 6E e il Wi-Fi 7. Aggiunge un ampio blocco di spettro pulito con molti canali larghi, ma solo i dispositivi più recenti possono usarla e la portata è la più breve delle tre bande.",
        "de": "Das neueste WLAN-Band, freigegeben für Wi-Fi 6E und Wi-Fi 7. Es bietet einen großen Block sauberen Spektrums mit vielen breiten Kanälen, kann aber nur von neueren Geräten genutzt werden und hat die kürzeste Reichweite der drei Bänder.",
    },
    "channel": {
        "es": "Una porción concreta de una banda en la que transmite un punto de acceso. Los dispositivos en el mismo canal se turnan; los que están en canales bien separados pueden transmitir a la vez sin colisionar.",
        "fr": "Une portion précise d'une bande sur laquelle un point d'accès émet. Les appareils sur le même canal se relaient ; ceux situés sur des canaux bien séparés peuvent émettre en même temps sans collision.",
        "it": "Una porzione specifica di una banda su cui trasmette un access point. I dispositivi sullo stesso canale si alternano; quelli su canali ben separati possono trasmettere contemporaneamente senza collidere.",
        "de": "Ein bestimmter Ausschnitt eines Bandes, auf dem ein Access Point sendet. Geräte auf demselben Kanal wechseln sich ab; Geräte auf gut getrennten Kanälen können gleichzeitig senden, ohne zu kollidieren.",
    },
    "channel-width": {
        "es": "Cuánto espectro usa un canal, desde 20 MHz hasta 320 MHz. Los canales más anchos transportan más datos, pero cubren con limpieza menos superficie y dejan menos canales que no se solapen para los vecinos.",
        "fr": "La quantité de spectre qu'utilise un canal, de 20 MHz jusqu'à 320 MHz. Les canaux plus larges transportent plus de données, mais couvrent proprement une zone plus petite et laissent moins de canaux sans chevauchement pour les voisins.",
        "it": "Quanto spettro usa un canale, da 20 MHz fino a 320 MHz. I canali più larghi trasportano più dati, ma coprono in modo pulito un'area minore e lasciano meno canali non sovrapposti ai vicini.",
        "de": "Wie viel Spektrum ein Kanal nutzt, von 20 MHz bis 320 MHz. Breitere Kanäle übertragen mehr Daten, decken aber eine kleinere Fläche sauber ab und lassen weniger sich nicht überlappende Kanäle für Nachbarn übrig.",
    },
    "channel-bonding": {
        "es": "Combinar canales adyacentes de 20 MHz en un canal más ancho para ganar velocidad. El inconveniente es que quedan menos canales separados disponibles, lo que aumenta la probabilidad de interferencia en zonas concurridas.",
        "fr": "Combiner des canaux adjacents de 20 MHz en un canal plus large pour gagner en débit. L'inconvénient est qu'il reste moins de canaux séparés disponibles, ce qui augmente le risque d'interférences dans les zones très fréquentées.",
        "it": "Combinare canali adiacenti da 20 MHz in un unico canale più largo per ottenere più velocità. Lo svantaggio è che restano disponibili meno canali separati, il che aumenta la probabilità di interferenze nelle aree affollate.",
        "de": "Das Zusammenfassen benachbarter 20-MHz-Kanäle zu einem breiteren Kanal für mehr Geschwindigkeit. Der Nachteil: Es stehen weniger getrennte Kanäle zur Verfügung, was die Wahrscheinlichkeit von Störungen in stark frequentierten Bereichen erhöht.",
    },
    "co-channel-interference": {
        "es": "Lo que ocurre cuando puntos de acceso y dispositivos comparten el mismo canal. No tanto colisionan como se turnan, así que cuantos más dispositivos hay en un canal, menos tiempo de aire toca a cada uno. Suele ser la causa real de un Wi-Fi lento en despliegues densos.",
        "fr": "Ce qui se produit lorsque des points d'accès et des appareils partagent le même canal. Ils n'entrent pas tant en collision qu'ils se relaient : plus il y a d'appareils sur un canal, moins chacun dispose de temps d'antenne. C'est souvent la véritable cause d'un Wi-Fi lent dans les déploiements denses.",
        "it": "Ciò che accade quando access point e dispositivi condividono lo stesso canale. Più che collidere, si alternano: più dispositivi ci sono su un canale, meno tempo d'antenna tocca a ciascuno. Spesso è la vera causa di un Wi-Fi lento nei deployment densi.",
        "de": "Was geschieht, wenn Access Points und Geräte denselben Kanal teilen. Sie kollidieren nicht so sehr, sondern wechseln sich ab: Je mehr Geräte auf einem Kanal sind, desto weniger Sendezeit bleibt jedem. Oft die eigentliche Ursache für langsames WLAN in dichten Umgebungen.",
    },
    "dynamic-frequency-selection": {
        "es": "Una norma para ciertos canales de 5 GHz que obliga al Wi-Fi a vigilar la presencia de radar y cambiar de canal si aparece. Los canales DFS añaden capacidad, pero pueden causar breves interrupciones cuando un evento de radar fuerza un cambio.",
        "fr": "Une règle pour certains canaux 5 GHz qui oblige le Wi-Fi à surveiller la présence de radars et à quitter le canal si l'un apparaît. Les canaux DFS ajoutent de la capacité, mais peuvent provoquer de brèves interruptions lorsqu'un événement radar force un changement.",
        "it": "Una regola per alcuni canali a 5 GHz che impone al Wi-Fi di sorvegliare la presenza di radar e di abbandonare il canale se ne compare uno. I canali DFS aggiungono capacità, ma possono causare brevi interruzioni quando un evento radar impone un cambio.",
        "de": "Eine Regel für bestimmte 5-GHz-Kanäle, die das WLAN zwingt, auf Radar zu achten und den Kanal zu wechseln, falls Radar auftritt. DFS-Kanäle erhöhen die Kapazität, können aber kurze Unterbrechungen verursachen, wenn ein Radarereignis einen Wechsel erzwingt.",
    },
    "ieee-802-11": {
        "es": "El estándar técnico que define cómo funciona el Wi-Fi a nivel de radio y de datos. Cada función del Wi-Fi procede de una enmienda 802.11, identificada por letras finales como 802.11ax.",
        "fr": "La norme technique qui définit le fonctionnement du Wi-Fi au niveau radio et données. Chaque fonctionnalité Wi-Fi remonte à un amendement 802.11, identifié par des lettres finales comme 802.11ax.",
        "it": "Lo standard tecnico che definisce come funziona il Wi-Fi a livello radio e dati. Ogni funzione del Wi-Fi deriva da un emendamento 802.11, identificato da lettere finali come 802.11ax.",
        "de": "Der technische Standard, der festlegt, wie WLAN auf Funk- und Datenebene funktioniert. Jede WLAN-Funktion geht auf eine 802.11-Ergänzung zurück, gekennzeichnet durch nachgestellte Buchstaben wie 802.11ax.",
    },
    "wi-fi-4": {
        "es": "La generación de 2009 que introdujo MIMO y varios flujos de datos, funcionando tanto en 2,4 como en 5 GHz. Fue el primer gran salto en velocidad del Wi-Fi.",
        "fr": "La génération de 2009 qui a introduit le MIMO et plusieurs flux de données, fonctionnant à la fois en 2,4 et 5 GHz. Ce fut le premier grand bond en débit du Wi-Fi.",
        "it": "La generazione del 2009 che introdusse il MIMO e più flussi di dati, operando sia a 2,4 sia a 5 GHz. Fu il primo grande salto di velocità del Wi-Fi.",
        "de": "Die Generation von 2009, die MIMO und mehrere Datenströme einführte und sowohl bei 2,4 als auch bei 5 GHz arbeitete. Es war der erste große Sprung in der WLAN-Geschwindigkeit.",
    },
    "wi-fi-5": {
        "es": "La generación de 2013, solo en 5 GHz, que añadió canales más anchos, más flujos y el primer MIMO multiusuario. Llevó el Wi-Fi al terreno del gigabit.",
        "fr": "La génération de 2013, en 5 GHz uniquement, qui a ajouté des canaux plus larges, davantage de flux et le premier MIMO multi-utilisateur. Elle a fait entrer le Wi-Fi dans le domaine du gigabit.",
        "it": "La generazione del 2013, solo a 5 GHz, che aggiunse canali più larghi, più flussi e il primo MIMO multiutente. Portò il Wi-Fi nel territorio del gigabit.",
        "de": "Die Generation von 2013, ausschließlich bei 5 GHz, die breitere Kanäle, mehr Datenströme und das erste Multi-User-MIMO hinzufügte. Sie brachte WLAN in den Gigabit-Bereich.",
    },
    "wi-fi-6": {
        "es": "La generación de 2021 centrada en la eficiencia en lugares concurridos más que en la velocidad máxima. Introdujo OFDMA, Target Wake Time y un mejor rendimiento cuando muchos dispositivos comparten un punto de acceso.",
        "fr": "La génération de 2021 axée sur l'efficacité dans les lieux très fréquentés plutôt que sur le débit de pointe. Elle a introduit l'OFDMA, le Target Wake Time et de meilleures performances lorsque de nombreux appareils partagent un point d'accès.",
        "it": "La generazione del 2021 incentrata sull'efficienza nei luoghi affollati più che sulla velocità di picco. Introdusse OFDMA, Target Wake Time e prestazioni migliori quando molti dispositivi condividono un access point.",
        "de": "Die Generation von 2021, die auf Effizienz an überfüllten Orten statt auf Spitzengeschwindigkeit ausgerichtet ist. Sie führte OFDMA, Target Wake Time und bessere Leistung ein, wenn sich viele Geräte einen Access Point teilen.",
    },
    "wi-fi-6e": {
        "es": "Wi-Fi 6 extendido a la nueva banda de 6 GHz. Las mismas funciones que Wi-Fi 6, pero con acceso a espectro limpio y más canales anchos. Requiere dispositivos compatibles con 6 GHz.",
        "fr": "Le Wi-Fi 6 étendu à la nouvelle bande 6 GHz. Les mêmes fonctionnalités que le Wi-Fi 6, mais avec l'accès à un spectre propre et davantage de canaux larges. Nécessite des appareils compatibles 6 GHz.",
        "it": "Il Wi-Fi 6 esteso alla nuova banda da 6 GHz. Le stesse funzioni del Wi-Fi 6, ma con accesso a spettro pulito e più canali larghi. Richiede dispositivi compatibili con i 6 GHz.",
        "de": "Wi-Fi 6 erweitert auf das neue 6-GHz-Band. Dieselben Funktionen wie Wi-Fi 6, jedoch mit Zugang zu sauberem Spektrum und mehr breiten Kanälen. Erfordert 6-GHz-fähige Geräte.",
    },
    "wi-fi-7": {
        "es": "La generación de 2024 que abarca 2,4, 5 y 6 GHz. Añade canales de 320 MHz, modulación más densa y Multi-Link Operation, que permite a un dispositivo usar más de una banda a la vez.",
        "fr": "La génération de 2024 couvrant 2,4, 5 et 6 GHz. Elle ajoute des canaux de 320 MHz, une modulation plus dense et le Multi-Link Operation, qui permet à un appareil d'utiliser plusieurs bandes à la fois.",
        "it": "La generazione del 2024 che copre 2,4, 5 e 6 GHz. Aggiunge canali da 320 MHz, modulazione più densa e Multi-Link Operation, che consente a un dispositivo di usare più di una banda contemporaneamente.",
        "de": "Die Generation von 2024, die 2,4, 5 und 6 GHz umfasst. Sie ergänzt 320-MHz-Kanäle, dichtere Modulation und Multi-Link Operation, womit ein Gerät mehr als ein Band gleichzeitig nutzen kann.",
    },
    "wi-fi-8": {
        "es": "La próxima generación, en desarrollo y prevista para alrededor de 2028. Su objetivo es la fiabilidad más que una mayor velocidad máxima: rendimiento más estable, menor latencia y menos tramas perdidas en condiciones difíciles.",
        "fr": "La prochaine génération, en cours de développement et attendue vers 2028. Son objectif est la fiabilité plutôt qu'un débit de pointe plus élevé : un débit plus stable, une latence plus faible et moins de trames perdues dans des conditions difficiles.",
        "it": "La prossima generazione, in sviluppo e attesa intorno al 2028. Il suo obiettivo è l'affidabilità più che una maggiore velocità di picco: throughput più stabile, minore latenza e meno frame persi in condizioni difficili.",
        "de": "Die nächste Generation, in Entwicklung und für etwa 2028 erwartet. Ihr Ziel ist Zuverlässigkeit statt höherer Spitzengeschwindigkeit: gleichmäßigerer Durchsatz, geringere Latenz und weniger verlorene Frames unter schwierigen Bedingungen.",
    },
    "wi-fi-alliance": {
        "es": "El grupo del sector que posee el nombre «Wi-Fi», gestiona el programa de certificación y asigna los números de generación simples (Wi-Fi 6, 7, etc.). No redacta el estándar 802.11 subyacente; eso lo hace el IEEE.",
        "fr": "Le groupement industriel qui détient le nom « Wi-Fi », gère le programme de certification et attribue les numéros de génération simplifiés (Wi-Fi 6, 7, etc.). Il ne rédige pas la norme 802.11 sous-jacente ; c'est l'IEEE qui s'en charge.",
        "it": "Il consorzio industriale che possiede il nome «Wi-Fi», gestisce il programma di certificazione e assegna i numeri di generazione semplici (Wi-Fi 6, 7 e così via). Non redige lo standard 802.11 sottostante; lo fa l'IEEE.",
        "de": "Der Industrieverband, der den Namen „Wi-Fi“ besitzt, das Zertifizierungsprogramm betreibt und die einfachen Generationsnummern (Wi-Fi 6, 7 usw.) vergibt. Er schreibt nicht den zugrunde liegenden 802.11-Standard; das übernimmt das IEEE.",
    },
    "wi-fi-certified": {
        "es": "Un sello de la Wi-Fi Alliance que confirma que un producto se ha probado para funcionar con otros dispositivos certificados y cumple los requisitos definidos de funciones y seguridad.",
        "fr": "Un label de la Wi-Fi Alliance confirmant qu'un produit a été testé pour fonctionner avec d'autres appareils certifiés et qu'il répond aux exigences définies de fonctionnalités et de sécurité.",
        "it": "Un marchio della Wi-Fi Alliance che conferma che un prodotto è stato testato per funzionare con altri dispositivi certificati e soddisfa i requisiti definiti di funzionalità e sicurezza.",
        "de": "Ein Siegel der Wi-Fi Alliance, das bestätigt, dass ein Produkt auf Zusammenarbeit mit anderen zertifizierten Geräten geprüft wurde und definierte Funktions- und Sicherheitsanforderungen erfüllt.",
    },
    "backward-compatibility": {
        "es": "La capacidad de un equipo Wi-Fi más nuevo de seguir atendiendo a dispositivos más antiguos en la misma banda. Sin embargo, una función exclusiva de 6 GHz no puede alcanzar a un dispositivo que carece de radio de 6 GHz.",
        "fr": "La capacité d'un équipement Wi-Fi récent à continuer de desservir des appareils plus anciens sur la même bande. Toutefois, une fonctionnalité réservée au 6 GHz ne peut pas atteindre un appareil dépourvu de radio 6 GHz.",
        "it": "La capacità di un apparecchio Wi-Fi più recente di continuare a servire dispositivi più vecchi sulla stessa banda. Tuttavia, una funzione esclusiva dei 6 GHz non può raggiungere un dispositivo privo di radio a 6 GHz.",
        "de": "Die Fähigkeit neuerer WLAN-Geräte, ältere Geräte auf demselben Band weiterhin zu bedienen. Eine reine 6-GHz-Funktion erreicht jedoch kein Gerät, das kein 6-GHz-Funkmodul besitzt.",
    },
    "rf": {
        "es": "Las ondas de radio que el Wi-Fi usa para transportar datos por el aire. El Wi-Fi opera en los rangos sin licencia de 2,4, 5 y 6 GHz.",
        "fr": "Les ondes radio que le Wi-Fi utilise pour transporter les données dans l'air. Le Wi-Fi fonctionne dans les plages sans licence de 2,4, 5 et 6 GHz.",
        "it": "Le onde radio che il Wi-Fi usa per trasportare i dati nell'aria. Il Wi-Fi opera nelle gamme senza licenza di 2,4, 5 e 6 GHz.",
        "de": "Die Funkwellen, mit denen WLAN Daten durch die Luft überträgt. WLAN arbeitet in den lizenzfreien Bereichen 2,4, 5 und 6 GHz.",
    },
    "frequency": {
        "es": "Cuántas veces oscila una onda de radio por segundo, medido en hercios. Las bandas de mayor frecuencia transportan más datos, pero alcanzan distancias más cortas.",
        "fr": "Le nombre de fois qu'une onde radio oscille par seconde, mesuré en hertz. Les bandes de fréquence plus élevée transportent plus de données, mais portent sur de plus courtes distances.",
        "it": "Quante volte un'onda radio oscilla al secondo, misurato in hertz. Le bande a frequenza più alta trasportano più dati, ma raggiungono distanze più brevi.",
        "de": "Wie oft eine Funkwelle pro Sekunde schwingt, gemessen in Hertz. Bänder mit höherer Frequenz übertragen mehr Daten, überbrücken aber kürzere Entfernungen.",
    },
    "wavelength": {
        "es": "La longitud física de un ciclo de onda de radio. Las frecuencias más altas tienen longitudes de onda más cortas, lo que se relaciona con que los 6 GHz cubran normalmente menos superficie que los 2,4 GHz.",
        "fr": "La longueur physique d'un cycle d'onde radio. Les fréquences plus élevées ont des longueurs d'onde plus courtes, ce qui explique en partie pourquoi le 6 GHz couvre généralement une zone plus petite que le 2,4 GHz.",
        "it": "La lunghezza fisica di un ciclo d'onda radio. Le frequenze più alte hanno lunghezze d'onda più corte, il che è collegato al fatto che i 6 GHz coprono di norma un'area minore rispetto ai 2,4 GHz.",
        "de": "Die physikalische Länge eines Funkwellenzyklus. Höhere Frequenzen haben kürzere Wellenlängen, was damit zusammenhängt, dass 6 GHz typischerweise eine kleinere Fläche abdeckt als 2,4 GHz.",
    },
    "db": {
        "es": "Una forma de expresar cuánto mayor o menor es un nivel de señal respecto a otro. Cada 3 dB equivale aproximadamente al doble o la mitad de la potencia, y 10 dB es diez veces.",
        "fr": "Une manière d'exprimer de combien un niveau de signal est supérieur ou inférieur à un autre. Chaque 3 dB représente environ le double ou la moitié de la puissance, et 10 dB correspond à dix fois.",
        "it": "Un modo di esprimere quanto un livello di segnale è maggiore o minore di un altro. Ogni 3 dB corrisponde all'incirca al doppio o alla metà della potenza, e 10 dB equivale a dieci volte.",
        "de": "Eine Art auszudrücken, um wie viel größer oder kleiner ein Signalpegel als ein anderer ist. Jeweils 3 dB entsprechen ungefähr der doppelten oder halben Leistung, und 10 dB dem Zehnfachen.",
    },
    "dbm": {
        "es": "La unidad estándar de potencia de señal Wi-Fi, donde 0 dBm equivale a un milivatio. Las señales Wi-Fi recibidas son números negativos, y cuanto más cerca de cero, más fuertes (por ejemplo, -50 dBm es mucho mejor que -80 dBm).",
        "fr": "L'unité standard de puissance du signal Wi-Fi, où 0 dBm équivaut à un milliwatt. Les signaux Wi-Fi reçus sont des nombres négatifs, et plus la valeur est proche de zéro, plus le signal est fort (par exemple, -50 dBm est bien meilleur que -80 dBm).",
        "it": "L'unità standard della potenza del segnale Wi-Fi, dove 0 dBm equivale a un milliwatt. I segnali Wi-Fi ricevuti sono numeri negativi, e più vicini a zero sono più forti (per esempio, -50 dBm è molto meglio di -80 dBm).",
        "de": "Die Standardeinheit für die WLAN-Signalleistung, wobei 0 dBm einem Milliwatt entspricht. Empfangene WLAN-Signale sind negative Zahlen, und je näher an null, desto stärker (zum Beispiel ist -50 dBm viel besser als -80 dBm).",
    },
    "dbi": {
        "es": "Una medida de la ganancia de antena, es decir, cuánto concentra una antena su energía. Más dBi significa una señal más enfocada, no más potencia de transmisión.",
        "fr": "Une mesure du gain d'antenne, c'est-à-dire à quel point une antenne concentre son énergie. Plus de dBi signifie un signal plus focalisé, et non plus de puissance d'émission.",
        "it": "Una misura del guadagno d'antenna, ovvero quanto un'antenna concentra la propria energia. Più dBi significa un segnale più focalizzato, non più potenza di trasmissione.",
        "de": "Ein Maß für den Antennengewinn, also wie stark eine Antenne ihre Energie bündelt. Mehr dBi bedeutet ein stärker gebündeltes Signal, nicht mehr Sendeleistung.",
    },
    "rssi": {
        "es": "La lectura que hace un dispositivo de cuán fuerte es una señal recibida, normalmente mostrada en dBm. Es útil para comparar, pero los valores exactos varían entre fabricantes, así que conviene tomarlo como una guía y no como un valor absoluto.",
        "fr": "La mesure par un appareil de la force d'un signal reçu, généralement exprimée en dBm. Utile à des fins de comparaison, mais les valeurs exactes varient d'un fabricant à l'autre : il faut la considérer comme un repère plutôt qu'une valeur absolue.",
        "it": "La lettura da parte di un dispositivo di quanto è forte un segnale ricevuto, di solito mostrata in dBm. È utile per il confronto, ma i valori esatti variano da un produttore all'altro, quindi va considerata come un'indicazione e non come un valore assoluto.",
        "de": "Die Messung eines Geräts, wie stark ein empfangenes Signal ist, meist in dBm angegeben. Nützlich zum Vergleich, aber die genauen Werte unterscheiden sich zwischen Herstellern, daher als Richtwert und nicht als absoluter Wert zu verstehen.",
    },
    "signal-strength": {
        "es": "Cuán fuerte es una señal recibida, expresada mejor en dBm. Una señal fuerte ayuda, pero por sí sola no garantiza un buen rendimiento sin una relación señal-ruido suficientemente limpia.",
        "fr": "La force d'un signal reçu, exprimée de préférence en dBm. Un signal fort est utile, mais à lui seul il ne garantit pas de bonnes performances sans un rapport signal sur bruit suffisamment propre.",
        "it": "Quanto è forte un segnale ricevuto, espresso preferibilmente in dBm. Un segnale forte aiuta, ma da solo non garantisce buone prestazioni senza un rapporto segnale/rumore sufficientemente pulito.",
        "de": "Wie stark ein empfangenes Signal ist, am besten in dBm angegeben. Ein starkes Signal hilft, garantiert aber für sich allein noch keine gute Leistung ohne ein ausreichend sauberes Signal-Rausch-Verhältnis.",
    },
    "noise-floor": {
        "es": "La energía de radio de fondo constante en una zona. Una señal tiene que destacar por encima de este suelo para oírse, así que un suelo de ruido alto perjudica el rendimiento incluso cuando la señal es fuerte.",
        "fr": "L'énergie radio de fond constante dans une zone. Un signal doit dépasser ce plancher pour être entendu : un plancher de bruit élevé nuit donc aux performances même lorsque le signal est fort.",
        "it": "L'energia radio di fondo costante in un'area. Un segnale deve emergere al di sopra di questa soglia per essere udito, perciò un noise floor elevato penalizza le prestazioni anche quando il segnale è forte.",
        "de": "Die konstante Hintergrund-Funkenergie in einem Bereich. Ein Signal muss sich über diesen Grundpegel abheben, um gehört zu werden; ein hoher Noise Floor beeinträchtigt daher die Leistung, selbst wenn das Signal stark ist.",
    },
    "signal-to-noise-ratio": {
        "es": "La diferencia entre la fuerza de la señal y el suelo de ruido, en dB. Una SNR más alta permite conexiones más rápidas y fiables, y a menudo predice el rendimiento real mejor que la fuerza de la señal por sí sola.",
        "fr": "L'écart entre la force du signal et le plancher de bruit, en dB. Un SNR plus élevé permet des connexions plus rapides et plus fiables, et il prédit souvent les performances réelles mieux que la seule force du signal.",
        "it": "La differenza tra la forza del segnale e il noise floor, in dB. Un SNR più alto consente connessioni più veloci e affidabili e spesso predice le prestazioni reali meglio della sola forza del segnale.",
        "de": "Der Abstand zwischen Signalstärke und Noise Floor, in dB. Ein höheres SNR ermöglicht schnellere und zuverlässigere Verbindungen und sagt die tatsächliche Leistung oft besser voraus als die Signalstärke allein.",
    },
    "eirp": {
        "es": "La potencia que realmente se irradia desde una antena en su dirección más fuerte, combinando la potencia de transmisión y la ganancia de antena. Los reguladores fijan límites a la EIRP en lugar de solo a la potencia de transmisión.",
        "fr": "La puissance réellement rayonnée par une antenne dans sa direction la plus forte, combinant la puissance d'émission et le gain d'antenne. Les régulateurs fixent des limites sur l'EIRP plutôt que sur la seule puissance d'émission.",
        "it": "La potenza effettivamente irradiata da un'antenna nella sua direzione più forte, combinando potenza di trasmissione e guadagno d'antenna. Gli enti regolatori fissano limiti sull'EIRP anziché sulla sola potenza di trasmissione.",
        "de": "Die tatsächlich von einer Antenne in ihrer stärksten Richtung abgestrahlte Leistung, kombiniert aus Sendeleistung und Antennengewinn. Regulierungsbehörden begrenzen die EIRP statt nur die Sendeleistung.",
    },
    "attenuation": {
        "es": "El debilitamiento de una señal Wi-Fi al atravesar la distancia, las paredes y otros materiales. Distintos materiales absorben cantidades diferentes, por eso el hormigón y el agua perjudican las señales más que el yeso laminado.",
        "fr": "L'affaiblissement d'un signal Wi-Fi lorsqu'il traverse la distance, les murs et d'autres matériaux. Différents matériaux absorbent des quantités différentes, c'est pourquoi le béton et l'eau nuisent davantage aux signaux que les cloisons en plâtre.",
        "it": "L'indebolimento di un segnale Wi-Fi mentre attraversa la distanza, i muri e altri materiali. Materiali diversi assorbono in misura diversa, ed è per questo che il cemento e l'acqua danneggiano i segnali più del cartongesso.",
        "de": "Die Abschwächung eines WLAN-Signals, während es Entfernung, Wände und andere Materialien durchquert. Verschiedene Materialien absorbieren unterschiedlich stark, weshalb Beton und Wasser Signale stärker beeinträchtigen als Gipskarton.",
    },
    "free-space-path-loss": {
        "es": "El debilitamiento de una señal por el simple hecho de dispersarse a lo largo de la distancia, incluso sin nada en medio. La fórmula estándar muestra más pérdida a frecuencias más altas, pero eso se debe a que la antena receptora capta menos energía con longitudes de onda más cortas, no a que el aire absorba la señal. El efecto neto es que los 6 GHz presentan más pérdida de trayecto que los 2,4 GHz a la misma distancia.",
        "fr": "L'affaiblissement d'un signal dû au simple fait qu'il se disperse sur la distance, même sans obstacle. La formule standard indique davantage de pertes aux fréquences plus élevées, mais cela vient de ce que l'antenne de réception capte moins d'énergie aux longueurs d'onde plus courtes, et non de ce que l'air absorbe le signal. L'effet net est que le 6 GHz présente davantage de pertes de trajet que le 2,4 GHz à distance égale.",
        "it": "L'indebolimento di un segnale per il semplice fatto di disperdersi lungo la distanza, anche senza nulla in mezzo. La formula standard mostra più perdita alle frequenze più alte, ma ciò dipende dal fatto che l'antenna ricevente capta meno energia con lunghezze d'onda più corte, non dall'aria che assorbe il segnale. L'effetto netto è che i 6 GHz mostrano più perdita di percorso dei 2,4 GHz alla stessa distanza.",
        "de": "Die Abschwächung eines Signals allein durch die Ausbreitung über die Entfernung, selbst ohne Hindernisse. Die Standardformel zeigt höhere Verluste bei höheren Frequenzen, doch das liegt daran, dass die Empfangsantenne bei kürzeren Wellenlängen weniger Energie aufnimmt, nicht daran, dass die Luft das Signal absorbiert. Im Ergebnis weist 6 GHz bei gleicher Entfernung mehr Pfadverlust auf als 2,4 GHz.",
    },
    "multipath": {
        "es": "Cuando una señal llega al receptor por varios caminos a la vez tras rebotar en superficies. Puede causar distorsión, pero el Wi-Fi moderno la aprovecha de forma constructiva mediante MIMO.",
        "fr": "Lorsqu'un signal atteint le récepteur par plusieurs chemins à la fois après avoir rebondi sur des surfaces. Cela peut provoquer de la distorsion, mais le Wi-Fi moderne en tire parti de manière constructive grâce au MIMO.",
        "it": "Quando un segnale raggiunge il ricevitore attraverso più percorsi contemporaneamente dopo aver rimbalzato sulle superfici. Può causare distorsione, ma il Wi-Fi moderno lo sfrutta in modo costruttivo tramite il MIMO.",
        "de": "Wenn ein Signal den Empfänger nach Reflexionen an Oberflächen über mehrere Pfade gleichzeitig erreicht. Das kann Verzerrungen verursachen, doch modernes WLAN nutzt es über MIMO konstruktiv.",
    },
    "interference": {
        "es": "Energía de radio no deseada que degrada una señal Wi-Fi, procedente de otras redes o de fuentes ajenas al Wi-Fi como microondas, radares y algunos dispositivos inalámbricos.",
        "fr": "Énergie radio indésirable qui dégrade un signal Wi-Fi, provenant d'autres réseaux ou de sources non Wi-Fi telles que les micro-ondes, les radars et certains appareils sans fil.",
        "it": "Energia radio indesiderata che degrada un segnale Wi-Fi, proveniente da altre reti o da sorgenti non Wi-Fi come forni a microonde, radar e alcuni dispositivi cordless.",
        "de": "Unerwünschte Funkenergie, die ein WLAN-Signal verschlechtert, von anderen Netzwerken oder von Nicht-WLAN-Quellen wie Mikrowellen, Radar und manchen Funkgeräten.",
    },
    "antenna-gain": {
        "es": "Con qué eficacia una antena concentra la señal en una dirección, medido en dBi. La ganancia modela la cobertura; no añade potencia de transmisión.",
        "fr": "L'efficacité avec laquelle une antenne concentre le signal dans une direction, mesurée en dBi. Le gain façonne la couverture ; il n'ajoute pas de puissance d'émission.",
        "it": "Con quanta efficacia un'antenna concentra il segnale in una direzione, misurata in dBi. Il guadagno modella la copertura; non aggiunge potenza di trasmissione.",
        "de": "Wie wirksam eine Antenne das Signal in eine Richtung bündelt, gemessen in dBi. Der Gewinn formt die Abdeckung; er fügt keine Sendeleistung hinzu.",
    },
    "omnidirectional-antenna": {
        "es": "Una antena que irradia de forma bastante uniforme en todas las direcciones horizontales, dando un patrón de cobertura con forma de rosquilla. Habitual en puntos de acceso pensados para cubrir una sala desde el centro.",
        "fr": "Une antenne qui rayonne de façon assez uniforme dans toutes les directions horizontales, donnant un diagramme de couverture en forme de tore. Courante sur les points d'accès destinés à couvrir une pièce depuis le centre.",
        "it": "Un'antenna che irradia in modo abbastanza uniforme in tutte le direzioni orizzontali, dando un diagramma di copertura a forma di ciambella. Comune negli access point pensati per coprire una stanza dal centro.",
        "de": "Eine Antenne, die in alle horizontalen Richtungen ziemlich gleichmäßig abstrahlt und ein donutförmiges Abdeckungsmuster ergibt. Üblich bei Access Points, die einen Raum aus der Mitte abdecken sollen.",
    },
    "directional-antenna": {
        "es": "Una antena que concentra su señal en una dirección para mayor alcance o cobertura dirigida. Las antenas de parche, panel y Yagi son tipos habituales.",
        "fr": "Une antenne qui concentre son signal dans une direction pour une plus grande portée ou une couverture ciblée. Les antennes patch, panneau et Yagi sont des types courants.",
        "it": "Un'antenna che concentra il proprio segnale in una direzione per maggiore portata o copertura mirata. Le antenne patch, a pannello e Yagi sono tipi comuni.",
        "de": "Eine Antenne, die ihr Signal in eine Richtung bündelt, für größere Reichweite oder gezielte Abdeckung. Patch-, Panel- und Yagi-Antennen sind gängige Typen.",
    },
    "ofdm": {
        "es": "La técnica central que el Wi-Fi usa para repartir datos en muchas subportadoras pequeñas a la vez, lo que resiste la interferencia y el multitrayecto. Ha sustentado cada generación importante de Wi-Fi desde que 802.11a lo trajo a los 5 GHz en 1999.",
        "fr": "La technique centrale que le Wi-Fi utilise pour répartir les données sur de nombreuses sous-porteuses à la fois, ce qui résiste aux interférences et au multitrajet. Elle sous-tend chaque grande génération de Wi-Fi depuis que le 802.11a l'a introduite en 5 GHz en 1999.",
        "it": "La tecnica centrale che il Wi-Fi usa per distribuire i dati su molte piccole sottoportanti contemporaneamente, il che resiste a interferenze e multipath. Ha sostenuto ogni generazione principale di Wi-Fi da quando l'802.11a la portò sui 5 GHz nel 1999.",
        "de": "Die zentrale Technik, mit der WLAN Daten auf viele kleine Unterträger gleichzeitig verteilt, was Störungen und Mehrwegeausbreitung widersteht. Sie liegt jeder großen WLAN-Generation zugrunde, seit 802.11a sie 1999 zu 5 GHz brachte.",
    },
    "ofdma": {
        "es": "Una mejora de OFDM introducida en Wi-Fi 6 que permite que una sola transmisión atienda a varios dispositivos a la vez dividiendo el canal en porciones más pequeñas. Mejora la eficiencia cuando muchos dispositivos envían pequeñas cantidades de datos.",
        "fr": "Une amélioration de l'OFDM introduite avec le Wi-Fi 6 qui permet à une seule transmission de servir plusieurs appareils à la fois en divisant le canal en morceaux plus petits. Elle améliore l'efficacité lorsque de nombreux appareils envoient de petites quantités de données.",
        "it": "Un miglioramento di OFDM introdotto nel Wi-Fi 6 che consente a una singola trasmissione di servire più dispositivi contemporaneamente suddividendo il canale in porzioni più piccole. Migliora l'efficienza quando molti dispositivi inviano piccole quantità di dati.",
        "de": "Eine OFDM-Erweiterung aus Wi-Fi 6, mit der eine einzige Übertragung mehrere Geräte gleichzeitig bedient, indem der Kanal in kleinere Stücke aufgeteilt wird. Sie verbessert die Effizienz, wenn viele Geräte kleine Datenmengen senden.",
    },
    "mimo": {
        "es": "Usar varias antenas para enviar varios flujos de datos al mismo tiempo, multiplicando la capacidad. Es la base de la velocidad del Wi-Fi moderno.",
        "fr": "Utiliser plusieurs antennes pour envoyer plusieurs flux de données en même temps, multipliant la capacité. C'est le fondement du débit du Wi-Fi moderne.",
        "it": "Usare più antenne per inviare più flussi di dati contemporaneamente, moltiplicando la capacità. È il fondamento della velocità del Wi-Fi moderno.",
        "de": "Mehrere Antennen nutzen, um mehrere Datenströme gleichzeitig zu senden und so die Kapazität zu vervielfachen. Es ist die Grundlage der Geschwindigkeit modernen WLANs.",
    },
    "mu-mimo": {
        "es": "Una forma de MIMO que atiende a varios dispositivos a la vez en lugar de uno por uno. El enlace descendente llegó con Wi-Fi 5, y Wi-Fi 6 lo añadió para el enlace ascendente.",
        "fr": "Une forme de MIMO qui sert plusieurs appareils à la fois plutôt qu'un par un. La liaison descendante est arrivée avec le Wi-Fi 5, et le Wi-Fi 6 l'a ajoutée pour la liaison montante.",
        "it": "Una forma di MIMO che serve più dispositivi contemporaneamente invece di uno alla volta. Il downlink è arrivato con il Wi-Fi 5, e il Wi-Fi 6 lo ha aggiunto per l'uplink.",
        "de": "Eine Form von MIMO, die mehrere Geräte gleichzeitig statt nacheinander bedient. Der Downlink kam mit Wi-Fi 5, und Wi-Fi 6 ergänzte ihn für den Uplink.",
    },
    "spatial-stream": {
        "es": "Un flujo de datos independiente enviado por una ruta de antena. Más flujos espaciales suponen más velocidad, hasta el menor número de antenas de los dos dispositivos.",
        "fr": "Un flux de données indépendant envoyé sur un chemin d'antenne. Plus de flux spatiaux signifie plus de débit, jusqu'au nombre d'antennes le plus faible des deux appareils.",
        "it": "Un flusso di dati indipendente inviato su un percorso d'antenna. Più flussi spaziali significano più velocità, fino al numero di antenne più basso tra i due dispositivi.",
        "de": "Ein unabhängiger Datenstrom, der über einen Antennenpfad gesendet wird. Mehr räumliche Datenströme bedeuten mehr Geschwindigkeit, bis zur niedrigeren Antennenzahl der beiden Geräte.",
    },
    "beamforming": {
        "es": "Conformar una transmisión a través de varias antenas para que la señal incida con más fuerza en el dispositivo previsto. Mejora el alcance y la fiabilidad sin aumentar la potencia.",
        "fr": "Mettre en forme une transmission sur plusieurs antennes pour que le signal atteigne plus fortement l'appareil visé. Cela améliore la portée et la fiabilité sans augmenter la puissance.",
        "it": "Modellare una trasmissione su più antenne in modo che il segnale arrivi più forte sul dispositivo previsto. Migliora la portata e l'affidabilità senza aumentare la potenza.",
        "de": "Eine Übertragung über mehrere Antennen so formen, dass das Signal stärker auf das vorgesehene Gerät trifft. Das verbessert Reichweite und Zuverlässigkeit, ohne die Leistung zu erhöhen.",
    },
    "qam": {
        "es": "El método que el Wi-Fi usa para empaquetar bits en la señal. Un QAM más alto (256, 1024, 4096) transporta más datos por transmisión, pero necesita una señal más limpia para funcionar.",
        "fr": "La méthode que le Wi-Fi utilise pour empaqueter les bits sur le signal. Un QAM plus élevé (256, 1024, 4096) transporte plus de données par transmission, mais nécessite un signal plus propre pour fonctionner.",
        "it": "Il metodo che il Wi-Fi usa per impacchettare i bit sul segnale. Un QAM più alto (256, 1024, 4096) trasporta più dati per trasmissione, ma richiede un segnale più pulito per funzionare.",
        "de": "Das Verfahren, mit dem WLAN Bits auf das Signal packt. Höheres QAM (256, 1024, 4096) überträgt mehr Daten pro Übertragung, benötigt aber ein saubereres Signal, um zu funktionieren.",
    },
    "mcs": {
        "es": "El ajuste combinado de modulación y corrección de errores que, junto con el ancho de canal y los flujos, fija la velocidad de datos de la conexión. Cada combinación tiene un número de índice, y los índices más altos necesitan una señal más fuerte y limpia.",
        "fr": "Le réglage combiné de la modulation et de la correction d'erreurs qui, avec la largeur de canal et les flux, définit le débit de données de la connexion. Chaque combinaison possède un numéro d'index, et les index plus élevés nécessitent un signal plus fort et plus propre.",
        "it": "L'impostazione combinata di modulazione e correzione degli errori che, insieme alla larghezza di canale e ai flussi, definisce la velocità dati della connessione. Ogni combinazione ha un numero indice, e gli indici più alti richiedono un segnale più forte e pulito.",
        "de": "Die kombinierte Einstellung aus Modulation und Fehlerkorrektur, die zusammen mit Kanalbreite und Datenströmen die Datenrate der Verbindung festlegt. Jede Kombination hat einen Indexwert, und höhere Indizes erfordern ein stärkeres, saubereres Signal.",
    },
    "data-rate-vs-throughput": {
        "es": "La velocidad de datos es la velocidad bruta que negocia la radio; el rendimiento es la velocidad real útil tras la sobrecarga, las retransmisiones y el tiempo de aire compartido. El rendimiento real queda muy por debajo de la velocidad negociada, con frecuencia solo entre la mitad y dos tercios, y aún menos en un canal ocupado.",
        "fr": "Le débit de données est la vitesse brute négociée par la radio ; le throughput est la vitesse réellement utilisable après les surcharges, les retransmissions et le temps d'antenne partagé. Le throughput réel reste bien en dessous du débit négocié, souvent seulement la moitié aux deux tiers, et moins encore sur un canal occupé.",
        "it": "La velocità dati è la velocità grezza negoziata dalla radio; il throughput è la velocità realmente utilizzabile dopo overhead, ritrasmissioni e tempo d'antenna condiviso. Il throughput reale resta ben al di sotto della velocità negoziata, spesso solo dalla metà ai due terzi, e ancora meno su un canale occupato.",
        "de": "Die Datenrate ist die rohe Geschwindigkeit, die das Funkmodul aushandelt; der Durchsatz ist die tatsächlich nutzbare Geschwindigkeit nach Overhead, Wiederholungen und geteilter Sendezeit. Der reale Durchsatz liegt deutlich unter der ausgehandelten Rate, häufig nur bei der Hälfte bis zwei Dritteln, und auf einem ausgelasteten Kanal noch niedriger.",
    },
    "guard-interval": {
        "es": "Un pequeño hueco insertado entre transmisiones para absorber los ecos del multitrayecto y evitar que corrompan el siguiente símbolo. Los intervalos más cortos suben ligeramente la velocidad; los más largos aguantan mejor en espacios con mucho multitrayecto.",
        "fr": "Un petit intervalle inséré entre les transmissions pour absorber les échos du multitrajet et les empêcher de corrompre le symbole suivant. Des intervalles plus courts augmentent légèrement le débit ; des intervalles plus longs résistent mieux dans les espaces à fort multitrajet.",
        "it": "Un piccolo spazio inserito tra le trasmissioni per assorbire gli echi del multipath e impedire che corrompano il simbolo successivo. Intervalli più brevi aumentano leggermente la velocità; quelli più lunghi reggono meglio negli ambienti con molto multipath.",
        "de": "Eine winzige Lücke zwischen Übertragungen, die Echos aus der Mehrwegeausbreitung aufnimmt und verhindert, dass sie das nächste Symbol stören. Kürzere Intervalle erhöhen die Geschwindigkeit leicht; längere bewähren sich besser in Umgebungen mit starker Mehrwegeausbreitung.",
    },
    "target-wake-time": {
        "es": "Una función de Wi-Fi 6 que permite a un dispositivo y a un punto de acceso programar cuándo despierta el dispositivo para enviar o recibir, ahorrando batería en teléfonos y dispositivos del Internet de las cosas.",
        "fr": "Une fonctionnalité du Wi-Fi 6 qui permet à un appareil et à un point d'accès de planifier le moment où l'appareil se réveille pour émettre ou recevoir, économisant la batterie des téléphones et des objets connectés.",
        "it": "Una funzione del Wi-Fi 6 che consente a un dispositivo e a un access point di programmare quando il dispositivo si sveglia per inviare o ricevere, risparmiando batteria su telefoni e dispositivi dell'Internet delle cose.",
        "de": "Eine Wi-Fi-6-Funktion, mit der ein Gerät und ein Access Point planen, wann das Gerät zum Senden oder Empfangen aufwacht, was Akku bei Smartphones und Geräten des Internets der Dinge spart.",
    },
    "multi-link-operation": {
        "es": "Una función clave de Wi-Fi 7 que permite a un dispositivo usar más de una banda o canal a la vez, ya sea combinándolos para ganar velocidad o alternando entre ellos para reducir la latencia y mejorar la fiabilidad.",
        "fr": "Une fonctionnalité clé du Wi-Fi 7 qui permet à un appareil d'utiliser plusieurs bandes ou canaux à la fois, soit en les combinant pour le débit, soit en basculant entre eux pour une latence plus faible et plus de fiabilité.",
        "it": "Una funzione chiave del Wi-Fi 7 che consente a un dispositivo di usare più di una banda o canale alla volta, combinandoli per la velocità oppure alternandoli per ridurre la latenza e migliorare l'affidabilità.",
        "de": "Eine zentrale Wi-Fi-7-Funktion, mit der ein Gerät mehr als ein Band oder einen Kanal gleichzeitig nutzen kann, entweder durch Bündeln für mehr Geschwindigkeit oder durch Umschalten für geringere Latenz und Zuverlässigkeit.",
    },
    "bss-coloring": {
        "es": "Una función de Wi-Fi 6 que etiqueta cada red con un número para que un dispositivo distinga rápidamente su propio tráfico del de un vecino y reutilice el canal de forma más agresiva cuando es seguro.",
        "fr": "Une fonctionnalité du Wi-Fi 6 qui marque chaque réseau d'un numéro afin qu'un appareil distingue rapidement son propre trafic de celui d'un voisin et réutilise le canal plus agressivement lorsque c'est sûr.",
        "it": "Una funzione del Wi-Fi 6 che etichetta ogni rete con un numero affinché un dispositivo distingua rapidamente il proprio traffico da quello di un vicino e riutilizzi il canale in modo più aggressivo quando è sicuro.",
        "de": "Eine Wi-Fi-6-Funktion, die jedes Netzwerk mit einer Nummer kennzeichnet, damit ein Gerät seinen eigenen Verkehr schnell vom dem eines Nachbarn unterscheiden und den Kanal aggressiver wiederverwenden kann, wenn es sicher ist.",
    },
    "preamble-puncturing": {
        "es": "Una función que permite a un canal ancho saltarse una parte ocupada o bloqueada y seguir usando el resto, en lugar de bajar a un canal estrecho. Introducida en Wi-Fi 6 y ampliada en Wi-Fi 7.",
        "fr": "Une fonctionnalité qui permet à un canal large de contourner une portion occupée ou bloquée et de continuer à utiliser le reste, au lieu de redescendre vers un canal étroit. Introduite avec le Wi-Fi 6 et étendue avec le Wi-Fi 7.",
        "it": "Una funzione che consente a un canale largo di saltare una porzione occupata o bloccata e continuare a usare il resto, invece di scendere a un canale stretto. Introdotta nel Wi-Fi 6 ed estesa nel Wi-Fi 7.",
        "de": "Eine Funktion, die es einem breiten Kanal erlaubt, einen belegten oder blockierten Teil zu überspringen und den Rest weiter zu nutzen, statt auf einen schmalen Kanal herunterzuschalten. Eingeführt in Wi-Fi 6 und in Wi-Fi 7 erweitert.",
    },
    "mac-address": {
        "es": "El identificador único de hardware de un dispositivo de red. El Wi-Fi lo usa para dirigir las tramas, y los teléfonos modernos a menudo lo aleatorizan por privacidad.",
        "fr": "L'identifiant matériel unique d'un appareil réseau. Le Wi-Fi l'utilise pour adresser les trames, et les téléphones modernes le rendent souvent aléatoire pour préserver la confidentialité.",
        "it": "L'identificatore hardware univoco di un dispositivo di rete. Il Wi-Fi lo usa per indirizzare i frame, e i telefoni moderni spesso lo rendono casuale per la privacy.",
        "de": "Die eindeutige Hardwarekennung eines Netzwerkgeräts. WLAN nutzt sie zur Adressierung von Frames, und moderne Smartphones randomisieren sie häufig zum Schutz der Privatsphäre.",
    },
    "csma-ca": {
        "es": "La regla básica de cortesía del Wi-Fi: un dispositivo escucha primero y transmite solo cuando el canal está libre. Por eso el rendimiento del Wi-Fi cae a medida que más dispositivos comparten un canal.",
        "fr": "La règle de base de courtoisie du Wi-Fi : un appareil écoute d'abord et n'émet que lorsque le canal est libre. C'est pourquoi les performances du Wi-Fi chutent à mesure que davantage d'appareils partagent un canal.",
        "it": "La regola di base di cortesia del Wi-Fi: un dispositivo ascolta prima e trasmette solo quando il canale è libero. È per questo che le prestazioni del Wi-Fi calano man mano che più dispositivi condividono un canale.",
        "de": "Die grundlegende Höflichkeitsregel des WLANs: Ein Gerät hört zuerst zu und sendet nur, wenn der Kanal frei ist. Deshalb sinkt die WLAN-Leistung, je mehr Geräte sich einen Kanal teilen.",
    },
    "airtime": {
        "es": "El tiempo que un dispositivo ocupa el canal para enviar sus datos. Los dispositivos lentos o lejanos usan más tiempo de aire para los mismos datos, lo que puede dejar sin recursos a todos los demás del canal.",
        "fr": "Le temps qu'un appareil occupe le canal pour envoyer ses données. Les appareils lents ou éloignés utilisent plus de temps d'antenne pour les mêmes données, ce qui peut affamer tous les autres appareils du canal.",
        "it": "Il tempo che un dispositivo occupa il canale per inviare i propri dati. I dispositivi lenti o lontani usano più tempo d'antenna per gli stessi dati, il che può togliere risorse a tutti gli altri sul canale.",
        "de": "Die Zeit, die ein Gerät den Kanal belegt, um seine Daten zu senden. Langsame oder weit entfernte Geräte benötigen für dieselben Daten mehr Sendezeit, was alle anderen auf dem Kanal benachteiligen kann.",
    },
    "channel-utilization": {
        "es": "Cuán ocupado está un canal, expresado como el porcentaje de tiempo en que está en uso. Una utilización alta es una de las señales más claras de una red congestionada y lenta.",
        "fr": "Le degré d'occupation d'un canal, exprimé en pourcentage du temps pendant lequel il est utilisé. Une utilisation élevée est l'un des signes les plus clairs d'un réseau congestionné et lent.",
        "it": "Quanto è occupato un canale, espresso come percentuale di tempo in cui è in uso. Un'utilizzazione elevata è uno dei segni più chiari di una rete congestionata e lenta.",
        "de": "Wie ausgelastet ein Kanal ist, ausgedrückt als prozentualer Zeitanteil seiner Nutzung. Eine hohe Auslastung ist eines der deutlichsten Zeichen für ein überlastetes, langsames Netzwerk.",
    },
    "beacon": {
        "es": "Una pequeña trama de gestión que un punto de acceso difunde con regularidad para anunciar el nombre y las capacidades de su red. Es la forma en que los dispositivos descubren una red y se mantienen sincronizados con ella.",
        "fr": "Une petite trame de gestion qu'un point d'accès diffuse régulièrement pour annoncer le nom et les capacités de son réseau. C'est ainsi que les appareils découvrent un réseau et restent synchronisés avec lui.",
        "it": "Un piccolo frame di gestione che un access point trasmette regolarmente per annunciare il nome e le capacità della propria rete. È il modo in cui i dispositivi scoprono una rete e restano sincronizzati con essa.",
        "de": "Ein kleiner Management-Frame, den ein Access Point regelmäßig aussendet, um Namen und Fähigkeiten seines Netzwerks bekanntzugeben. So entdecken Geräte ein Netzwerk und bleiben mit ihm synchronisiert.",
    },
    "dtim": {
        "es": "Un ajuste transportado en las balizas que indica a los dispositivos dormidos cuándo despertar para recibir el tráfico almacenado en búfer. Equilibra la duración de la batería frente a la rapidez con la que un dispositivo recibe datos.",
        "fr": "Un réglage transporté dans les balises qui indique aux appareils en veille quand se réveiller pour le trafic mis en mémoire tampon. Il équilibre l'autonomie de la batterie et la rapidité avec laquelle un appareil reçoit les données.",
        "it": "Un'impostazione trasportata nei beacon che indica ai dispositivi addormentati quando svegliarsi per il traffico bufferizzato. Bilancia la durata della batteria con la rapidità con cui un dispositivo riceve i dati.",
        "de": "Eine in den Beacons übertragene Einstellung, die schlafenden Geräten mitteilt, wann sie für gepufferten Datenverkehr aufwachen sollen. Sie wägt Akkulaufzeit gegen die Geschwindigkeit ab, mit der ein Gerät Daten empfängt.",
    },
    "rts-cts": {
        "es": "Un breve protocolo de saludo que reserva el canal antes de enviar, usado para evitar colisiones entre dispositivos que no pueden oírse entre sí. Útil en situaciones de nodo oculto.",
        "fr": "Une courte poignée de main qui réserve le canal avant l'émission, utilisée pour éviter les collisions entre appareils qui ne peuvent pas s'entendre. Utile dans les situations de nœud caché.",
        "it": "Un breve handshake che riserva il canale prima di inviare, usato per evitare collisioni tra dispositivi che non riescono a sentirsi. Utile nelle situazioni di nodo nascosto.",
        "de": "Ein kurzer Handshake, der den Kanal vor dem Senden reserviert, um Kollisionen zwischen Geräten zu vermeiden, die sich gegenseitig nicht hören. Hilfreich bei Situationen mit verstecktem Knoten.",
    },
    "hidden-node": {
        "es": "Dos dispositivos que alcanzan ambos el punto de acceso pero no pueden oírse entre sí, así que transmiten al mismo tiempo y colisionan. Una causa clásica de retransmisiones inexplicables.",
        "fr": "Deux appareils qui atteignent tous deux le point d'accès mais ne peuvent pas s'entendre, de sorte qu'ils émettent en même temps et entrent en collision. Une cause classique de retransmissions inexpliquées.",
        "it": "Due dispositivi che raggiungono entrambi l'access point ma non riescono a sentirsi, perciò trasmettono nello stesso momento e collidono. Una causa classica di ritrasmissioni inspiegabili.",
        "de": "Zwei Geräte, die beide den Access Point erreichen, sich aber nicht gegenseitig hören, sodass sie gleichzeitig senden und kollidieren. Eine klassische Ursache für unerklärliche Wiederholungen.",
    },
    "qos-wmm": {
        "es": "Un sistema que prioriza el tráfico sensible al tiempo, como la voz y el vídeo, frente al tráfico de fondo, para que una descarga grande no arruine una llamada.",
        "fr": "Un système qui priorise le trafic sensible au temps, comme la voix et la vidéo, par rapport au trafic d'arrière-plan, afin qu'un gros téléchargement ne gâche pas un appel.",
        "it": "Un sistema che dà priorità al traffico sensibile al tempo, come voce e video, rispetto al traffico in background, così che un download di grandi dimensioni non rovini una chiamata.",
        "de": "Ein System, das zeitkritischen Verkehr wie Sprache und Video gegenüber Hintergrundverkehr priorisiert, damit ein großer Download einen Anruf nicht stört.",
    },
    "access-point": {
        "es": "El dispositivo que proporciona la señal Wi-Fi y conecta los dispositivos inalámbricos a la red cableada. Un punto de acceso no es un router, aunque un equipo doméstico combine ambas funciones.",
        "fr": "L'appareil qui fournit le signal Wi-Fi et relie les appareils sans fil au réseau filaire. Un point d'accès n'est pas un routeur, même si une box grand public combine les deux fonctions.",
        "it": "Il dispositivo che fornisce il segnale Wi-Fi e collega i dispositivi wireless alla rete cablata. Un access point non è un router, anche quando un apparecchio domestico combina entrambe le funzioni.",
        "de": "Das Gerät, das das WLAN-Signal bereitstellt und drahtlose Geräte mit dem kabelgebundenen Netzwerk verbindet. Ein Access Point ist kein Router, auch wenn ein Endkundengerät beide Funktionen vereint.",
    },
    "station-sta-client": {
        "es": "Cualquier dispositivo que se conecta a una red Wi-Fi, como un teléfono, un portátil o un sensor.",
        "fr": "Tout appareil qui se connecte à un réseau Wi-Fi, comme un téléphone, un ordinateur portable ou un capteur.",
        "it": "Qualsiasi dispositivo che si connette a una rete Wi-Fi, come un telefono, un portatile o un sensore.",
        "de": "Jedes Gerät, das sich mit einem WLAN-Netzwerk verbindet, etwa ein Smartphone, ein Laptop oder ein Sensor.",
    },
    "ssid": {
        "es": "El nombre de red que los dispositivos ven y al que se unen, como «HomeNetwork». Varios puntos de acceso pueden compartir un mismo SSID para que los dispositivos transiten entre ellos como una sola red.",
        "fr": "Le nom de réseau que les appareils voient et auquel ils se connectent, comme « HomeNetwork ». Plusieurs points d'accès peuvent partager un même SSID afin que les appareils circulent entre eux comme un seul réseau.",
        "it": "Il nome di rete che i dispositivi vedono e a cui si collegano, come «HomeNetwork». Più access point possono condividere lo stesso SSID affinché i dispositivi si spostino tra essi come un'unica rete.",
        "de": "Der Netzwerkname, den Geräte sehen und dem sie beitreten, etwa „HomeNetwork“. Mehrere Access Points können sich einen SSID teilen, sodass Geräte zwischen ihnen wie in einem einzigen Netzwerk wechseln.",
    },
    "bssid": {
        "es": "El identificador de radio único de la red de un solo punto de acceso, normalmente basado en su dirección MAC. Un mismo SSID puede tener muchos BSSID a lo largo de un edificio.",
        "fr": "L'identifiant radio unique du réseau d'un seul point d'accès, généralement basé sur son adresse MAC. Un même SSID peut comporter de nombreux BSSID dans un bâtiment.",
        "it": "L'identificatore radio univoco della rete di un singolo access point, di solito basato sul suo indirizzo MAC. Uno stesso SSID può avere molti BSSID in un edificio.",
        "de": "Die eindeutige Funkkennung des Netzwerks eines einzelnen Access Points, meist auf Basis seiner MAC-Adresse. Ein SSID kann in einem Gebäude viele BSSIDs haben.",
    },
    "wireless-lan-controller": {
        "es": "Un dispositivo o servicio central que gestiona muchos puntos de acceso a la vez, ocupándose de canales, potencia, transición y configuración desde un único lugar.",
        "fr": "Un appareil ou un service central qui gère de nombreux points d'accès à la fois, prenant en charge les canaux, la puissance, l'itinérance et la configuration depuis un seul endroit.",
        "it": "Un dispositivo o servizio centrale che gestisce molti access point contemporaneamente, occupandosi di canali, potenza, roaming e configurazione da un unico punto.",
        "de": "Ein zentrales Gerät oder ein Dienst, der viele Access Points gleichzeitig verwaltet und Kanäle, Leistung, Roaming und Konfiguration von einer Stelle aus steuert.",
    },
    "cloud-managed-wi-fi": {
        "es": "Una arquitectura en la que los puntos de acceso se configuran y supervisan a través de un panel en línea en lugar de un controlador en las instalaciones. Uno de los varios modelos de gestión usados en el Wi-Fi empresarial.",
        "fr": "Une architecture dans laquelle les points d'accès sont configurés et surveillés via un tableau de bord en ligne plutôt que par un contrôleur sur site. L'un des différents modèles de gestion utilisés dans le Wi-Fi professionnel.",
        "it": "Un'architettura in cui gli access point vengono configurati e monitorati tramite una dashboard online anziché un controller in sede. Uno dei vari modelli di gestione usati nel Wi-Fi aziendale.",
        "de": "Eine Architektur, bei der Access Points über ein Online-Dashboard statt über einen Controller vor Ort konfiguriert und überwacht werden. Eines von mehreren Verwaltungsmodellen im Unternehmens-WLAN.",
    },
    "roaming": {
        "es": "El proceso por el que un dispositivo en movimiento pasa de un punto de acceso a otro dentro de la misma red sin perder la conexión.",
        "fr": "Le processus par lequel un appareil en mouvement passe d'un point d'accès à un autre au sein du même réseau sans perdre la connexion.",
        "it": "Il processo con cui un dispositivo in movimento passa da un access point a un altro all'interno della stessa rete senza perdere la connessione.",
        "de": "Der Vorgang, bei dem ein bewegtes Gerät innerhalb desselben Netzwerks von einem Access Point an einen anderen übergeben wird, ohne die Verbindung zu verlieren.",
    },
    "fast-roaming": {
        "es": "Un conjunto de estándares que hacen que la transición sea rápida y fluida. El 802.11k ayuda a un dispositivo a encontrar puntos de acceso cercanos, el 802.11v ayuda a dirigirlo al mejor, y el 802.11r acelera el traspaso seguro para que las llamadas y el vídeo sobrevivan al cambio.",
        "fr": "Un ensemble de normes qui rendent l'itinérance rapide et fluide. Le 802.11k aide un appareil à trouver les points d'accès proches, le 802.11v aide à le diriger vers le meilleur, et le 802.11r accélère le transfert sécurisé afin que les appels et la vidéo survivent au changement.",
        "it": "Un insieme di standard che rendono il roaming rapido e fluido. L'802.11k aiuta un dispositivo a trovare gli access point vicini, l'802.11v aiuta a indirizzarlo verso il migliore e l'802.11r velocizza il passaggio sicuro affinché chiamate e video sopravvivano al cambio.",
        "de": "Eine Reihe von Standards, die das Roaming schnell und reibungslos machen. 802.11k hilft einem Gerät, nahe Access Points zu finden, 802.11v hilft, es zum besten zu lenken, und 802.11r beschleunigt die sichere Übergabe, damit Anrufe und Video den Wechsel überstehen.",
    },
    "sticky-client": {
        "es": "Un dispositivo que se aferra a un punto de acceso lejano en lugar de transitar a otro más cercano y fuerte. Es una causa habitual de mal rendimiento al moverse por un espacio.",
        "fr": "Un appareil qui s'accroche à un point d'accès éloigné au lieu de passer à un autre plus proche et plus puissant. C'est une cause fréquente de mauvaises performances en se déplaçant dans un espace.",
        "it": "Un dispositivo che si aggrappa a un access point lontano invece di passare a uno più vicino e forte. È una causa comune di prestazioni scadenti mentre ci si sposta in un ambiente.",
        "de": "Ein Gerät, das an einem entfernten Access Point festhält, anstatt zu einem näheren, stärkeren zu wechseln. Eine häufige Ursache für schlechte Leistung beim Bewegen durch einen Raum.",
    },
    "mesh": {
        "es": "Un diseño en el que los puntos de acceso se conectan entre sí de forma inalámbrica para ampliar la cobertura sin tender cable a cada uno. Cómodo, pero los saltos inalámbricos reducen la capacidad.",
        "fr": "Une conception où les points d'accès se connectent entre eux sans fil pour étendre la couverture sans tirer de câble vers chacun. Pratique, mais les sauts sans fil réduisent la capacité.",
        "it": "Un progetto in cui gli access point si collegano tra loro in modalità wireless per estendere la copertura senza posare un cavo a ciascuno. Comodo, ma i salti wireless riducono la capacità.",
        "de": "Ein Aufbau, bei dem sich Access Points drahtlos miteinander verbinden, um die Abdeckung zu erweitern, ohne zu jedem ein Kabel zu verlegen. Praktisch, aber die drahtlosen Sprünge verringern die Kapazität.",
    },
    "band-steering": {
        "es": "Una función que empuja a los dispositivos compatibles hacia una banda menos saturada, normalmente llevándolos de los 2,4 GHz a los 5 o 6 GHz para un mejor rendimiento.",
        "fr": "Une fonctionnalité qui oriente les appareils compatibles vers une bande moins encombrée, généralement en les faisant passer du 2,4 GHz au 5 ou 6 GHz pour de meilleures performances.",
        "it": "Una funzione che spinge i dispositivi compatibili verso una banda meno affollata, di solito portandoli dai 2,4 GHz ai 5 o 6 GHz per prestazioni migliori.",
        "de": "Eine Funktion, die fähige Geräte auf ein weniger überfülltes Band lenkt, meist von 2,4 GHz auf 5 oder 6 GHz, für bessere Leistung.",
    },
    "power-over-ethernet": {
        "es": "Suministrar tanto datos como energía eléctrica a un punto de acceso por un solo cable Ethernet, de modo que no necesita una toma de corriente aparte.",
        "fr": "Acheminer à la fois les données et l'alimentation électrique vers un point d'accès par un seul câble Ethernet, de sorte qu'il n'a besoin d'aucune prise de courant séparée.",
        "it": "Fornire sia i dati sia l'alimentazione elettrica a un access point tramite un unico cavo Ethernet, così da non richiedere una presa di corrente separata.",
        "de": "Sowohl Daten als auch Strom über ein einziges Ethernet-Kabel an einen Access Point liefern, sodass keine separate Steckdose nötig ist.",
    },
    "site-survey": {
        "es": "El proceso de medir y planificar la cobertura y la capacidad Wi-Fi en un espacio. Los estudios pueden ser predictivos (modelados), pasivos (de escucha) o activos (conectados y probando).",
        "fr": "Le processus de mesure et de planification de la couverture et de la capacité Wi-Fi dans un espace. Les études peuvent être prédictives (modélisées), passives (à l'écoute) ou actives (connectées et en test).",
        "it": "Il processo di misurazione e pianificazione della copertura e della capacità Wi-Fi in un ambiente. Le indagini possono essere predittive (modellate), passive (in ascolto) o attive (connesse e in test).",
        "de": "Der Prozess der Messung und Planung von WLAN-Abdeckung und -Kapazität in einem Raum. Untersuchungen können prädiktiv (modelliert), passiv (lauschend) oder aktiv (verbunden und testend) sein.",
    },
    "heat-map": {
        "es": "Un mapa codificado por colores que muestra la señal, la cobertura o el rendimiento Wi-Fi sobre un plano de planta. Una forma habitual de visualizar los resultados de un estudio y detectar zonas débiles.",
        "fr": "Une carte codée par couleurs montrant le signal, la couverture ou les performances Wi-Fi sur un plan d'étage. Un moyen courant de visualiser les résultats d'une étude et de repérer les zones faibles.",
        "it": "Una mappa a colori che mostra il segnale, la copertura o le prestazioni Wi-Fi su una pianta. Un modo comune di visualizzare i risultati di un'indagine e individuare le aree deboli.",
        "de": "Eine farbcodierte Karte, die WLAN-Signal, -Abdeckung oder -Leistung über einem Grundriss zeigt. Eine gängige Möglichkeit, Untersuchungsergebnisse zu visualisieren und schwache Bereiche zu erkennen.",
    },
    "wpa2": {
        "es": "El estándar de seguridad Wi-Fi de larga trayectoria, construido sobre el cifrado AES (CCMP). Todavía muy usado, pero con debilidades conocidas que WPA3 corrige, incluido el ataque KRACK al protocolo de saludo y el descifrado de contraseñas sin conexión a partir de un saludo o un PMKID capturados.",
        "fr": "Le standard de sécurité Wi-Fi de longue date, fondé sur le chiffrement AES (CCMP). Encore largement utilisé, mais avec des faiblesses connues que le WPA3 corrige, notamment l'attaque KRACK sur la poignée de main et la recherche hors ligne de mots de passe à partir d'une poignée de main ou d'un PMKID capturés.",
        "it": "Lo standard di sicurezza Wi-Fi di lunga data, basato sulla cifratura AES (CCMP). Ancora molto usato, ma con debolezze note che il WPA3 corregge, tra cui l'attacco KRACK all'handshake e la ricerca offline delle password a partire da un handshake o da un PMKID catturati.",
        "de": "Der langjährige WLAN-Sicherheitsstandard auf Basis der AES-Verschlüsselung (CCMP). Noch weit verbreitet, aber mit bekannten Schwächen, die WPA3 behebt, darunter der KRACK-Angriff auf den Handshake und das Offline-Erraten von Passwörtern aus einem erfassten Handshake oder PMKID.",
    },
    "wpa3": {
        "es": "El estándar de seguridad Wi-Fi actual. Refuerza la seguridad basada en contraseñas, protege las tramas de gestión de forma predeterminada y resiste los ataques de descifrado sin conexión que afectan a WPA2.",
        "fr": "Le standard de sécurité Wi-Fi actuel. Il renforce la sécurité par mot de passe, protège les trames de gestion par défaut et résiste aux attaques de recherche hors ligne qui affectent le WPA2.",
        "it": "L'attuale standard di sicurezza Wi-Fi. Rafforza la sicurezza basata su password, protegge per impostazione predefinita i frame di gestione e resiste agli attacchi di ricerca offline che colpiscono il WPA2.",
        "de": "Der aktuelle WLAN-Sicherheitsstandard. Er stärkt die passwortbasierte Sicherheit, schützt Management-Frames standardmäßig und widersteht den Offline-Rate-Angriffen, die WPA2 betreffen.",
    },
    "personal-vs-enterprise-mode": {
        "es": "Las dos formas de proteger una red Wi-Fi. El modo Personal usa una única contraseña compartida por todos; el modo Empresarial da a cada usuario su propio inicio de sesión a través de un servidor central, lo que es más seguro y manejable para las organizaciones.",
        "fr": "Les deux façons de sécuriser un réseau Wi-Fi. Le mode Personnel utilise un seul mot de passe partagé par tous ; le mode Entreprise donne à chaque utilisateur ses propres identifiants via un serveur central, ce qui est plus sûr et plus gérable pour les organisations.",
        "it": "I due modi di proteggere una rete Wi-Fi. La modalità Personale usa un'unica password condivisa da tutti; la modalità Enterprise dà a ciascun utente le proprie credenziali tramite un server centrale, il che è più sicuro e gestibile per le organizzazioni.",
        "de": "Die zwei Wege, ein WLAN-Netzwerk zu sichern. Der Personal-Modus nutzt ein einziges, von allen geteiltes Passwort; der Enterprise-Modus gibt jedem Nutzer eine eigene Anmeldung über einen zentralen Server, was für Organisationen sicherer und besser verwaltbar ist.",
    },
    "pre-shared-key": {
        "es": "La única contraseña compartida que se usa en el modo Personal. Todos en la red usan la misma frase de contraseña para conectarse.",
        "fr": "Le mot de passe partagé unique utilisé en mode Personnel. Tout le monde sur le réseau utilise la même phrase secrète pour se connecter.",
        "it": "L'unica password condivisa usata in modalità Personale. Tutti sulla rete usano la stessa passphrase per connettersi.",
        "de": "Das einzige gemeinsame Passwort im Personal-Modus. Alle im Netzwerk verwenden dieselbe Passphrase zur Verbindung.",
    },
    "sae": {
        "es": "El protocolo de saludo que WPA3-Personal usa en lugar del antiguo método de WPA2. Impide que los atacantes capturen el intercambio y adivinen la contraseña sin conexión.",
        "fr": "La poignée de main que le WPA3-Personnel utilise à la place de l'ancienne méthode du WPA2. Elle empêche les attaquants de capturer l'échange et de deviner le mot de passe hors ligne.",
        "it": "L'handshake che il WPA3-Personale usa al posto del vecchio metodo del WPA2. Impedisce agli aggressori di catturare lo scambio e di indovinare la password offline.",
        "de": "Der Handshake, den WPA3-Personal anstelle der alten WPA2-Methode verwendet. Er hindert Angreifer daran, den Austausch zu erfassen und das Passwort offline zu erraten.",
    },
    "802-1x": {
        "es": "El estándar que está detrás del modo Empresarial, en el que cada dispositivo se autentica ante un servidor central antes de unirse. Permite inicios de sesión por usuario en lugar de una única contraseña compartida.",
        "fr": "La norme à la base du mode Entreprise, où chaque appareil s'authentifie auprès d'un serveur central avant de rejoindre le réseau. Elle permet des connexions par utilisateur au lieu d'un seul mot de passe partagé.",
        "it": "Lo standard alla base della modalità Enterprise, in cui ogni dispositivo si autentica presso un server centrale prima di connettersi. Consente accessi per singolo utente invece di un'unica password condivisa.",
        "de": "Der Standard hinter dem Enterprise-Modus, bei dem sich jedes Gerät vor dem Beitritt an einem zentralen Server authentifiziert. Er ermöglicht benutzerbezogene Anmeldungen statt eines einzigen gemeinsamen Passworts.",
    },
    "eap": {
        "es": "El marco que transporta el método de inicio de sesión real en 802.1X, con variantes como EAP-TLS (basado en certificados) y PEAP (basado en contraseña).",
        "fr": "Le cadre qui transporte la méthode de connexion réelle dans le 802.1X, avec des variantes comme EAP-TLS (basé sur certificats) et PEAP (basé sur mot de passe).",
        "it": "Il framework che trasporta il metodo di accesso effettivo nell'802.1X, con varianti come EAP-TLS (basato su certificati) e PEAP (basato su password).",
        "de": "Das Rahmenwerk, das die eigentliche Anmeldemethode in 802.1X transportiert, mit Varianten wie EAP-TLS (zertifikatsbasiert) und PEAP (passwortbasiert).",
    },
    "radius": {
        "es": "El servidor central que comprueba las credenciales de usuario en el Wi-Fi empresarial e indica al punto de acceso si debe permitir o no un dispositivo.",
        "fr": "Le serveur central qui vérifie les identifiants des utilisateurs dans le Wi-Fi d'entreprise et indique au point d'accès s'il doit autoriser ou non un appareil.",
        "it": "Il server centrale che verifica le credenziali utente nel Wi-Fi aziendale e indica all'access point se consentire o meno un dispositivo.",
        "de": "Der zentrale Server, der im Unternehmens-WLAN die Benutzeranmeldedaten prüft und dem Access Point mitteilt, ob ein Gerät zugelassen wird.",
    },
    "protected-management-frames": {
        "es": "Una protección que asegura ciertas tramas de gestión para que los atacantes no puedan falsificar mensajes de desconexión y expulsar a los dispositivos. Requerida por WPA3.",
        "fr": "Une protection qui sécurise certaines trames de gestion afin que les attaquants ne puissent pas falsifier des messages de déconnexion pour expulser des appareils. Requise par le WPA3.",
        "it": "Una protezione che mette al sicuro alcuni frame di gestione affinché gli aggressori non possano falsificare messaggi di disconnessione per espellere i dispositivi. Richiesta dal WPA3.",
        "de": "Ein Schutz, der bestimmte Management-Frames absichert, damit Angreifer keine gefälschten Trennungsnachrichten senden können, um Geräte hinauszuwerfen. Von WPA3 vorgeschrieben.",
    },
    "enhanced-open-owe": {
        "es": "Una forma de cifrar el tráfico en redes abiertas sin contraseña, habitual en el Wi-Fi público. Oculta tus datos del fisgoneo ocasional, pero no verifica la red, así que no impide un punto de acceso falso.",
        "fr": "Une manière de chiffrer le trafic sur les réseaux ouverts sans mot de passe, courante sur le Wi-Fi public. Elle masque vos données d'une surveillance occasionnelle, mais ne vérifie pas le réseau : elle n'empêche donc pas un faux point d'accès.",
        "it": "Un modo di cifrare il traffico su reti aperte senza password, comune nel Wi-Fi pubblico. Nasconde i tuoi dati dallo spionaggio occasionale, ma non verifica la rete, quindi non impedisce un hotspot falso.",
        "de": "Eine Möglichkeit, den Verkehr in offenen Netzwerken ohne Passwort zu verschlüsseln, üblich im öffentlichen WLAN. Sie verbirgt deine Daten vor beiläufigem Mitlesen, überprüft aber das Netzwerk nicht und verhindert daher keinen gefälschten Hotspot.",
    },
    "captive-portal": {
        "es": "La página de inicio de sesión o de condiciones que aparece al unirte a muchas redes públicas o de invitados antes de concederte acceso a internet.",
        "fr": "La page de connexion ou de conditions qui apparaît lorsque vous rejoignez de nombreux réseaux publics ou invités avant d'accorder l'accès à internet.",
        "it": "La pagina di accesso o dei termini che compare quando ti colleghi a molte reti pubbliche o per ospiti prima di concedere l'accesso a internet.",
        "de": "Die Anmelde- oder Bedingungsseite, die beim Beitritt zu vielen öffentlichen oder Gastnetzwerken erscheint, bevor der Internetzugang gewährt wird.",
    },
    "mac-randomization": {
        "es": "Una función de privacidad en la que un dispositivo usa una dirección de hardware cambiante e inventada para cada red, de modo que no se le pueda rastrear fácilmente entre ubicaciones.",
        "fr": "Une fonctionnalité de confidentialité où un appareil utilise une adresse matérielle changeante et fictive pour chaque réseau, afin qu'il ne puisse pas être facilement suivi d'un lieu à l'autre.",
        "it": "Una funzione di privacy in cui un dispositivo usa un indirizzo hardware variabile e inventato per ogni rete, così da non poter essere facilmente tracciato tra una posizione e l'altra.",
        "de": "Eine Datenschutzfunktion, bei der ein Gerät für jedes Netzwerk eine wechselnde, künstliche Hardwareadresse verwendet, damit es nicht leicht über verschiedene Orte hinweg verfolgt werden kann.",
    },
    "rogue-ap-evil-twin": {
        "es": "Un punto de acceso no autorizado. Un AP intruso es uno conectado a una red sin permiso; un gemelo malvado imita el nombre de una red legítima para engañar a los dispositivos y que se conecten.",
        "fr": "Un point d'accès non autorisé. Un AP indésirable est branché sur un réseau sans autorisation ; un jumeau maléfique imite le nom d'un réseau légitime pour tromper les appareils et les inciter à se connecter.",
        "it": "Un access point non autorizzato. Un AP intruso è collegato a una rete senza permesso; un gemello malvagio imita il nome di una rete legittima per ingannare i dispositivi e farli connettere.",
        "de": "Ein nicht autorisierter Access Point. Ein Rogue AP ist ohne Erlaubnis an ein Netzwerk angeschlossen; ein Evil Twin imitiert den Namen eines legitimen Netzwerks, um Geräte zur Verbindung zu verleiten.",
    },
    "throughput": {
        "es": "La velocidad de datos real y útil que una conexión entrega de verdad, después de toda la sobrecarga. Es lo que experimentan los usuarios, y siempre es menor que la velocidad de datos anunciada.",
        "fr": "La vitesse de données réelle et utilisable qu'une connexion fournit effectivement, après toute la surcharge. C'est ce que vivent les utilisateurs, et c'est toujours inférieur au débit de données annoncé.",
        "it": "La velocità dati reale e utilizzabile che una connessione fornisce davvero, dopo tutto l'overhead. È ciò che sperimentano gli utenti, ed è sempre inferiore alla velocità dati pubblicizzata.",
        "de": "Die tatsächliche, nutzbare Datengeschwindigkeit, die eine Verbindung wirklich liefert, nach allem Overhead. Das erleben die Nutzer, und sie liegt immer unter der beworbenen Datenrate.",
    },
    "latency": {
        "es": "El retardo que tarda los datos en llegar a su destino y volver, medido en milisegundos. La baja latencia importa más para las llamadas, el vídeo y los juegos que la velocidad bruta.",
        "fr": "Le délai pour que les données atteignent leur destination et reviennent, mesuré en millisecondes. Une faible latence compte davantage pour les appels, la vidéo et les jeux que la vitesse brute.",
        "it": "Il ritardo impiegato dai dati per raggiungere la destinazione e tornare, misurato in millisecondi. Una bassa latenza conta più della velocità grezza per chiamate, video e giochi.",
        "de": "Die Verzögerung, bis Daten ihr Ziel erreichen und zurückkehren, in Millisekunden gemessen. Geringe Latenz ist für Anrufe, Video und Spiele wichtiger als die rohe Geschwindigkeit.",
    },
    "jitter": {
        "es": "La variación de la latencia de un momento a otro. Una latencia estable se nota fluida; un jitter alto provoca llamadas y vídeo entrecortados aunque la velocidad media parezca correcta.",
        "fr": "La variation de la latence d'un instant à l'autre. Une latence stable paraît fluide ; un jitter élevé provoque des appels et des vidéos saccadés même lorsque la vitesse moyenne semble correcte.",
        "it": "La variazione della latenza da un momento all'altro. Una latenza stabile risulta fluida; un jitter elevato provoca chiamate e video a scatti anche quando la velocità media sembra corretta.",
        "de": "Die Schwankung der Latenz von einem Moment zum nächsten. Gleichmäßige Latenz wirkt flüssig; hoher Jitter verursacht stockende Anrufe und Videos, selbst wenn die durchschnittliche Geschwindigkeit gut aussieht.",
    },
    "packet-loss": {
        "es": "El porcentaje de datos que nunca llega y debe reenviarse. Incluso cantidades pequeñas perjudican gravemente las llamadas, el vídeo y la capacidad de respuesta.",
        "fr": "Le pourcentage de données qui n'arrivent jamais et doivent être renvoyées. Même de faibles quantités nuisent gravement aux appels, à la vidéo et à la réactivité.",
        "it": "La percentuale di dati che non arriva mai e deve essere ritrasmessa. Anche piccole quantità danneggiano gravemente chiamate, video e reattività.",
        "de": "Der Anteil der Daten, der nie ankommt und erneut gesendet werden muss. Selbst kleine Mengen beeinträchtigen Anrufe, Video und Reaktionsfähigkeit erheblich.",
    },
    "bufferbloat": {
        "es": "Un retardo que se acumula cuando una conexión ocupada sobrecarga sus búferes, causando lag durante las descargas incluso en enlaces rápidos. Las pruebas más recientes de «capacidad de respuesta» lo miden directamente.",
        "fr": "Un délai qui s'accumule lorsqu'une connexion chargée sature ses tampons, provoquant de la latence pendant les téléchargements même sur des liens rapides. Les tests récents de « réactivité » le mesurent directement.",
        "it": "Un ritardo che si accumula quando una connessione occupata riempie eccessivamente i suoi buffer, causando lag durante i download anche su collegamenti veloci. I test più recenti di «reattività» lo misurano direttamente.",
        "de": "Eine Verzögerung, die entsteht, wenn eine ausgelastete Verbindung ihre Puffer überfüllt, was selbst bei schnellen Leitungen zu Verzögerungen während Downloads führt. Neuere „Reaktionsfähigkeits“-Tests messen sie direkt.",
    },
    "coverage-hole": {
        "es": "Una zona donde la señal Wi-Fi es demasiado débil o inexistente para un uso fiable. Un hallazgo habitual en los estudios y una fuente frecuente de quejas.",
        "fr": "Une zone où le signal Wi-Fi est trop faible ou absent pour un usage fiable. Un constat fréquent lors des études et une source courante de plaintes.",
        "it": "Un'area dove il segnale Wi-Fi è troppo debole o assente per un uso affidabile. Un riscontro comune nelle indagini e una frequente fonte di lamentele.",
        "de": "Ein Bereich, in dem das WLAN-Signal für eine zuverlässige Nutzung zu schwach oder nicht vorhanden ist. Ein häufiger Befund bei Untersuchungen und eine häufige Quelle von Beschwerden.",
    },
}

LANGS = ("es", "fr", "it", "de")


def main() -> int:
    data = json.loads(ASSET.read_text(encoding="utf-8"))
    terms = data["terms"]
    ids = {t["id"] for t in terms}

    missing = sorted(ids - set(T))
    if missing:
        print(f"ERROR: no translations authored for {len(missing)} terms:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        return 1

    for t in terms:
        tr = T[t["id"]]
        defs = {}
        for lang in LANGS:
            text = tr.get(lang, "").strip()
            if not text:
                print(f"ERROR: empty {lang} for {t['id']}", file=sys.stderr)
                return 1
            defs[lang] = text
        t["definitions"] = defs
        t["translation_status"] = "draft-needs-review"

    # Top-level provenance flags so the dataset itself declares the draft state.
    data["languages"] = ["en", "es", "fr", "it", "de"]
    data["translation_status"] = "draft-needs-review"

    ASSET.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"OK: merged {len(LANGS)} translations into {len(terms)} terms.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
