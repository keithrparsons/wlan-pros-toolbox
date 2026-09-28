#!/usr/bin/env python3
"""Merge author-drafted ES/FR/IT/DE definition translations into glossary.json.

Felix-authored (2026-06-12). The TERM and its abbr stay English by convention
(professionals do not translate "beamforming", "OFDMA", "RSSI"); only the
explanatory DEFINITION is localized. Translations are DRAFTS pending
professional review — the dataset carries `translation_status:
draft-needs-review` and each translated term carries the same flag.

Retranslated 2026-09-28 (Felix) from the gated v4 English that Keith approved
(Deliverables/2026-09-28-glossary-gate/draft_v4.json in myPKA): plain words and
short sentences to match the English, "Wi-Fi" spelled exactly so in ES, FR
and IT. German says WLAN for the technology (Keith, 2026-09-28: "WLAN for
German is fine") and keeps Wi-Fi only in proper names (Wi-Fi 4 to Wi-Fi 8,
Wi-Fi 6E, Wi-Fi Alliance) and where the trademark itself is named. Standards and technical names untranslated, numbers as
digits with the local decimal comma (2,4 GHz). All 93 terms, including TIM.

Wireless Glossary, 2026-09-28 (Felix): the tool was renamed from "Wi-Fi
Glossary" (Keith: "rename to wireless glossary") and gained 30 non-Wi-Fi terms
in 4 categories (Cellular, Short-Range Radio, Location & Satellite, Home
Internet), English from the gated nonwifi_v3.json. 123 terms in all. The same
rules apply; the English rows themselves live in glossary.json, this script
only writes the `definitions` blocks, the draft flags and `term_count`.

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
        "es": "La banda Wi-Fi más antigua. Es la que llega más lejos y la que mejor atraviesa las paredes. El problema es que está saturada. Solo tiene sitio para 3 carriles, llamados canales, que no se solapan: 1, 6 y 11 en la mayoría de los países. Además comparte el aire con Bluetooth, hornos de microondas y vigilabebés.",
        "fr": "La plus ancienne bande Wi-Fi. C'est elle qui porte le plus loin et qui traverse le mieux les murs. Le problème, c'est qu'elle est encombrée. Elle n'a de place que pour 3 voies, appelées canaux, qui ne se chevauchent pas : 1, 6 et 11 dans la plupart des pays. Elle partage aussi les ondes avec le Bluetooth, les fours à micro-ondes et les babyphones.",
        "it": "La banda Wi-Fi più vecchia. È quella che arriva più lontano e passa meglio attraverso i muri. Il problema è che è affollata. Ha posto solo per 3 corsie, chiamate canali, che non si sovrappongono: 1, 6 e 11 nella maggior parte dei paesi. Divide anche l'aria con Bluetooth, forni a microonde e baby monitor.",
        "de": "Das älteste WLAN-Band. Es reicht am weitesten und kommt am besten durch Wände. Der Haken: Es ist überfüllt. Es hat nur Platz für 3 Spuren, Kanäle genannt, die sich nicht überlappen: 1, 6 und 11 in den meisten Ländern. Außerdem teilt es sich die Luft mit Bluetooth, Mikrowellen und Babyfonen.",
    },
    "5-ghz-band": {
        "es": "La banda que lleva la mayor parte del tráfico Wi-Fi hoy. Tiene muchos más carriles, llamados canales, que la de 2,4 GHz, así que puede llevar mucho más tráfico. A cambio pierde alcance. Su señal no llega tan lejos ni atraviesa tan bien las paredes.",
        "fr": "La bande qui transporte la plus grande partie du trafic Wi-Fi aujourd'hui. Elle a beaucoup plus de voies, appelées canaux, que la bande 2,4 GHz, donc elle peut transporter bien plus de trafic. En échange, elle porte moins loin. Son signal ne va pas aussi loin et traverse moins bien les murs.",
        "it": "La banda che oggi porta la maggior parte del traffico Wi-Fi. Ha molte più corsie, chiamate canali, rispetto ai 2,4 GHz, quindi può portare molto più traffico. Il prezzo è la portata. Il suo segnale non arriva così lontano e passa meno bene attraverso i muri.",
        "de": "Das Band, das heute den meisten WLAN-Verkehr trägt. Es hat viel mehr Spuren, Kanäle genannt, als 2,4 GHz und kann daher weit mehr Verkehr tragen. Der Preis ist die Reichweite. Sein Signal reicht nicht so weit und kommt schlechter durch Wände.",
    },
    "6-ghz-band": {
        "es": "La banda Wi-Fi más nueva, abierta por primera vez en EE. UU. en 2020. Tiene muchos carriles anchos y limpios, sin equipos antiguos que los saturen. Solo los teléfonos, portátiles y puntos de acceso más nuevos pueden usarla. Su señal es la de menor alcance de las 3 bandas.",
        "fr": "La bande Wi-Fi la plus récente, ouverte d'abord aux États-Unis en 2020. Elle a beaucoup de voies larges et dégagées, sans vieux matériel pour les encombrer. Seuls les téléphones, ordinateurs portables et points d'accès récents peuvent l'utiliser. Son signal est celui qui porte le moins loin des 3 bandes.",
        "it": "La banda Wi-Fi più nuova, aperta per la prima volta negli Stati Uniti nel 2020. Ha tante corsie larghe e pulite, senza apparecchi vecchi ad affollarle. Solo telefoni, portatili e access point recenti possono usarla. Il suo segnale è quello che arriva meno lontano tra le 3 bande.",
        "de": "Das neueste WLAN-Band, zuerst 2020 in den USA freigegeben. Es hat viele breite, freie Spuren, auf denen sich keine älteren Geräte drängen. Nur neuere Handys, Laptops und Access Points können es nutzen. Sein Signal hat die kürzeste Reichweite der 3 Bänder.",
    },
    "channel": {
        "es": "Una porción de una banda en la que habla el Wi-Fi, como un carril de una autopista. Los dispositivos en el mismo canal tienen que turnarse. Los dispositivos en canales bastante separados pueden hablar a la vez.",
        "fr": "Une tranche de bande sur laquelle le Wi-Fi parle, comme une voie sur une autoroute. Les appareils sur le même canal doivent parler chacun leur tour. Les appareils sur des canaux assez éloignés peuvent parler en même temps.",
        "it": "Una fetta di banda su cui parla il Wi-Fi, come una corsia in autostrada. I dispositivi sullo stesso canale devono fare a turno. I dispositivi su canali abbastanza distanti possono parlare nello stesso momento.",
        "de": "Ein Ausschnitt eines Bandes, auf dem das WLAN spricht, wie eine Spur auf der Autobahn. Geräte auf demselben Kanal müssen sich abwechseln. Geräte auf Kanälen, die weit genug auseinanderliegen, können gleichzeitig sprechen.",
    },
    "channel-width": {
        "es": "Lo ancho que es un canal (un carril de la banda), desde 20 MHz hasta 320 MHz. Un canal más ancho lleva más datos. El precio es que quedan menos canales para repartir, así que es más probable que las redes cercanas acaben unas encima de otras.",
        "fr": "La largeur d'un canal (une voie de la bande), de 20 MHz jusqu'à 320 MHz. Un canal plus large transporte plus de données. Le prix à payer : il reste moins de canaux à se partager, donc les réseaux voisins risquent plus de tomber les uns sur les autres.",
        "it": "Quanto è largo un canale (una corsia della banda), da 20 MHz fino a 320 MHz. Un canale più largo porta più dati. Il prezzo è che restano meno canali da dividere, quindi è più facile che le reti vicine finiscano una sopra l'altra.",
        "de": "Wie breit ein Kanal (eine Spur des Bandes) ist, von 20 MHz bis 320 MHz. Ein breiterer Kanal trägt mehr Daten. Der Preis: Es bleiben weniger Kanäle zum Verteilen, also landen Netze in der Nähe eher aufeinander.",
    },
    "channel-bonding": {
        "es": "Unir canales de 20 MHz contiguos (carriles de la banda) en un solo canal más ancho para ir más rápido. El precio es que quedan menos canales separados. En un edificio concurrido, eso significa que más redes acaban compartiendo el mismo espacio.",
        "fr": "Réunir des canaux de 20 MHz côte à côte (des voies de la bande) en un seul canal plus large pour aller plus vite. Le prix : il reste moins de canaux séparés. Dans un bâtiment chargé, plus de réseaux finissent donc par partager le même espace.",
        "it": "Unire canali da 20 MHz affiancati (corsie della banda) in un solo canale più largo per andare più veloci. Il prezzo è che restano meno canali separati. In un edificio affollato, questo vuol dire che più reti finiscono per dividere lo stesso spazio.",
        "de": "Nebeneinanderliegende 20-MHz-Kanäle (Spuren des Bandes) zu einem breiteren Kanal zusammenlegen, um schneller zu sein. Der Preis: Es bleiben weniger getrennte Kanäle übrig. In einem vollen Gebäude teilen sich dadurch mehr Netze denselben Platz.",
    },
    "co-channel-interference": {
        "es": "Lo que pasa cuando redes Wi-Fi cercanas usan el mismo canal (carril de la banda). Todo lo que está en ese canal tiene que turnarse, así que cada dispositivo tiene menos tiempo para hablar. Cuantos más dispositivos hay en un canal, más lento va. Esta suele ser la verdadera razón por la que el Wi-Fi va lento en edificios concurridos.",
        "fr": "Ce qui arrive quand des réseaux Wi-Fi voisins utilisent le même canal (voie de la bande). Tout ce qui est sur ce canal doit parler chacun son tour, donc chaque appareil a moins de temps pour parler. Plus il y a d'appareils sur un canal, plus il ralentit. C'est souvent la vraie raison pour laquelle le Wi-Fi est lent dans les bâtiments chargés.",
        "it": "Quello che succede quando reti Wi-Fi vicine usano lo stesso canale (corsia della banda). Tutto ciò che sta su quel canale deve fare a turno, quindi ogni dispositivo ha meno tempo per parlare. Più dispositivi ci sono su un canale, più diventa lento. Spesso è questo il vero motivo per cui il Wi-Fi è lento negli edifici affollati.",
        "de": "Was passiert, wenn WLAN-Netze in der Nähe denselben Kanal (Spur des Bandes) nutzen. Alles auf diesem Kanal muss sich abwechseln, also hat jedes Gerät weniger Zeit zum Sprechen. Je mehr Geräte auf einem Kanal, desto langsamer wird er. Das ist oft der wahre Grund, warum WLAN in vollen Gebäuden langsam ist.",
    },
    "dynamic-frequency-selection": {
        "es": "Una regla para algunos canales de 5 GHz. El Wi-Fi en esos canales tiene que escuchar si hay radar, como el radar meteorológico, y cambiarse de canal si lo oye. Estos canales añaden mucho espacio. La desventaja es un corte breve cuando el radar obliga a cambiar.",
        "fr": "Une règle pour certains canaux 5 GHz. Le Wi-Fi sur ces canaux doit écouter s'il y a un radar, comme un radar météo, et changer de canal s'il en entend un. Ces canaux ajoutent beaucoup de place. Le revers : une courte coupure quand un radar force le changement.",
        "it": "Una regola per alcuni canali a 5 GHz. Il Wi-Fi su quei canali deve ascoltare se c'è un radar, come quello meteo, e spostarsi se lo sente. Questi canali aggiungono molto spazio. Lo svantaggio è una breve interruzione quando un radar costringe a spostarsi.",
        "de": "Eine Regel für manche 5-GHz-Kanäle. WLAN auf diesen Kanälen muss auf Radar horchen, etwa Wetterradar, und ausweichen, wenn es eines hört. Diese Kanäle bringen viel zusätzlichen Platz. Der Nachteil ist ein kurzer Aussetzer, wenn Radar einen Wechsel erzwingt.",
    },
    "ieee-802-11": {
        "es": "El reglamento de cómo funciona el Wi-Fi, escrito por el IEEE, un grupo de ingenieros. Cada función nueva se añade como una actualización con letras al final, como 802.11ax. Wi-Fi 6 es el nombre de uso diario de 802.11ax.",
        "fr": "Le règlement qui dit comment fonctionne le Wi-Fi, écrit par l'IEEE, un groupe d'ingénieurs. Chaque nouvelle fonction s'ajoute sous forme de mise à jour avec des lettres à la fin, comme 802.11ax. Wi-Fi 6 est le nom courant de 802.11ax.",
        "it": "Il regolamento su come funziona il Wi-Fi, scritto dall'IEEE, un gruppo di ingegneri. Ogni nuova funzione si aggiunge come aggiornamento con delle lettere alla fine, come 802.11ax. Wi-Fi 6 è il nome di tutti i giorni per 802.11ax.",
        "de": "Das Regelwerk dafür, wie WLAN funktioniert, geschrieben vom IEEE, einer Gruppe von Ingenieuren. Jede neue Funktion kommt als Update mit Buchstaben am Ende dazu, etwa 802.11ax. Wi-Fi 6 ist der Alltagsname für 802.11ax.",
    },
    "wi-fi-4": {
        "es": "La versión de Wi-Fi de 2009, más conocida como 802.11n. Fue la primera en usar varias antenas a la vez para enviar más de un flujo de datos. Funciona en 2,4 y en 5 GHz, y fue el primer gran salto en la velocidad del Wi-Fi.",
        "fr": "La version du Wi-Fi de 2009, plus connue sous le nom de 802.11n. C'est la première à utiliser plusieurs antennes à la fois pour envoyer plus d'un flux de données. Elle fonctionne en 2,4 et en 5 GHz, et c'est le premier grand bond de vitesse du Wi-Fi.",
        "it": "La versione del Wi-Fi del 2009, più nota come 802.11n. È stata la prima a usare più antenne insieme per inviare più di un flusso di dati. Funziona sia a 2,4 sia a 5 GHz, ed è stata il primo grande salto di velocità del Wi-Fi.",
        "de": "Die WLAN-Version von 2009, besser bekannt als 802.11n. Sie nutzte als erste mehrere Antennen gleichzeitig, um mehr als einen Datenstrom zu senden. Sie funktioniert auf 2,4 und 5 GHz und war der erste große Geschwindigkeitssprung beim WLAN.",
    },
    "wi-fi-5": {
        "es": "La versión de Wi-Fi que salió en 2013, también llamada 802.11ac. Solo funciona en 5 GHz. Añadió canales más anchos y más flujos de datos. Los equipos Wi-Fi 5 posteriores también podían enviar a varios dispositivos en el mismo momento. Fue el primer Wi-Fi que alcanzó velocidades de datos de gigabit.",
        "fr": "La version du Wi-Fi sortie en 2013, aussi appelée 802.11ac. Elle fonctionne seulement en 5 GHz. Elle a ajouté des canaux plus larges et plus de flux de données. Le matériel Wi-Fi 5 plus tardif pouvait aussi envoyer à plusieurs appareils au même moment. C'est le premier Wi-Fi à atteindre des débits de l'ordre du gigabit.",
        "it": "La versione del Wi-Fi uscita nel 2013, chiamata anche 802.11ac. Funziona solo a 5 GHz. Ha aggiunto canali più larghi e più flussi di dati. Gli apparecchi Wi-Fi 5 più recenti potevano anche inviare a più dispositivi nello stesso momento. È stato il primo Wi-Fi a raggiungere velocità dati da gigabit.",
        "de": "Die WLAN-Version, die 2013 herauskam, auch 802.11ac genannt. Sie funktioniert nur auf 5 GHz. Sie brachte breitere Kanäle und mehr Datenströme. Spätere Geräte mit Wi-Fi 5 konnten außerdem im selben Moment an mehrere Geräte senden. Es war das erste WLAN mit Datenraten im Gigabit-Bereich.",
    },
    "wi-fi-6": {
        "es": "La versión de Wi-Fi también llamada 802.11ax. Los primeros equipos se certificaron en 2019, y el IEEE terminó el reglamento en 2021. Se diseñó para lugares concurridos, donde muchos dispositivos comparten una red. Un punto de acceso (el aparato que emite el Wi-Fi) puede hablar con varios dispositivos en un solo turno. Los teléfonos y otros dispositivos pequeños también pueden planear cuándo dormir, lo que ahorra batería.",
        "fr": "La version du Wi-Fi aussi appelée 802.11ax. Le premier matériel a été certifié en 2019, et l'IEEE a terminé le règlement en 2021. Elle a été conçue pour les lieux bondés, où beaucoup d'appareils partagent un réseau. Un point d'accès (le boîtier qui diffuse le Wi-Fi) peut parler à plusieurs appareils en un seul tour. Les téléphones et objets connectés peuvent aussi prévoir quand dormir, ce qui économise la batterie.",
        "it": "La versione del Wi-Fi chiamata anche 802.11ax. I primi apparecchi sono stati certificati nel 2019, e l'IEEE ha finito il regolamento nel 2021. È stata pensata per i luoghi affollati, dove tanti dispositivi dividono una rete. Un access point (l'apparecchio che trasmette il Wi-Fi) può parlare con più dispositivi in un solo turno. Telefoni e piccoli dispositivi possono anche decidere quando dormire, e così risparmiano batteria.",
        "de": "Die WLAN-Version, die auch 802.11ax heißt. Die ersten Geräte wurden 2019 dafür zertifiziert, und das IEEE hat das Regelwerk 2021 fertiggestellt. Sie wurde für volle Orte gebaut, an denen sich viele Geräte ein Netz teilen. Ein Access Point (die Box, die das WLAN aussendet) kann in einem Durchgang mit mehreren Geräten sprechen. Handys und kleine Geräte können außerdem planen, wann sie schlafen, und so Akku sparen.",
    },
    "wi-fi-6e": {
        "es": "Wi-Fi 6 (la versión de Wi-Fi de 2019) con acceso a la nueva banda de 6 GHz, la parte más nueva y menos saturada del aire que usa el Wi-Fi. Tiene las mismas funciones, más muchos carriles anchos y limpios en 6 GHz. Tu teléfono o portátil necesita una radio de 6 GHz para usarlos.",
        "fr": "Le Wi-Fi 6 (la version du Wi-Fi de 2019) avec accès à la nouvelle bande 6 GHz, la partie la plus récente et la moins encombrée des ondes qu'utilise le Wi-Fi. Mêmes fonctions, plus beaucoup de voies larges et dégagées en 6 GHz. Votre téléphone ou ordinateur portable a besoin d'une radio 6 GHz pour les utiliser.",
        "it": "Il Wi-Fi 6 (la versione del Wi-Fi del 2019) con accesso alla nuova banda a 6 GHz, la parte più nuova e meno affollata dell'aria che usa il Wi-Fi. Ha le stesse funzioni, più tante corsie larghe e pulite a 6 GHz. Il tuo telefono o portatile ha bisogno di una radio a 6 GHz per usarle.",
        "de": "Wi-Fi 6 (die WLAN-Version von 2019) mit Zugang zum neuen 6-GHz-Band, dem neuesten und am wenigsten vollen Teil der Luft, die WLAN nutzt. Es hat dieselben Funktionen, dazu viele breite, freie Spuren auf 6 GHz. Dein Handy oder Laptop braucht ein 6-GHz-Funkmodul, um sie zu nutzen.",
    },
    "wi-fi-7": {
        "es": "La versión de Wi-Fi de 2024, también llamada 802.11be. Funciona en 2,4, 5 y 6 GHz. Duplica el canal más ancho (carril de la banda) hasta 320 MHz y mete más datos en cada señal. Su mayor cambio permite que un dispositivo mantenga enlaces en más de una banda o canal. Puede usarlos juntos o elegir el que esté más despejado.",
        "fr": "La version du Wi-Fi de 2024, aussi appelée 802.11be. Elle fonctionne en 2,4, 5 et 6 GHz. Elle double le canal le plus large (voie de la bande) jusqu'à 320 MHz et met plus de données dans chaque signal. Son plus grand changement permet à un appareil de garder des liens sur plus d'une bande ou d'un canal. Il peut les utiliser ensemble, ou choisir celui qui est le plus dégagé.",
        "it": "La versione del Wi-Fi del 2024, chiamata anche 802.11be. Funziona a 2,4, 5 e 6 GHz. Raddoppia il canale più largo (corsia della banda) fino a 320 MHz e mette più dati in ogni segnale. Il suo cambiamento più grande permette a un dispositivo di tenere collegamenti su più di una banda o canale. Può usarli insieme, oppure scegliere quello più libero.",
        "de": "Die WLAN-Version von 2024, auch 802.11be genannt. Sie funktioniert auf 2,4, 5 und 6 GHz. Sie verdoppelt den breitesten Kanal (Spur des Bandes) auf 320 MHz und packt mehr Daten in jedes Signal. Ihre größte Neuerung lässt ein Gerät Verbindungen auf mehr als einem Band oder Kanal halten. Es kann sie zusammen nutzen oder die freieste davon wählen.",
    },
    "wi-fi-8": {
        "es": "La próxima versión de Wi-Fi, también llamada 802.11bn. Todavía se está escribiendo, y el IEEE espera terminarla en 2028. Su objetivo es un Wi-Fi que se mantenga estable cuando las cosas se ponen difíciles: menos parones, menos retraso, traspasos más suaves y menos mensajes perdidos.",
        "fr": "La prochaine version du Wi-Fi, aussi appelée 802.11bn. Elle est encore en cours d'écriture, et l'IEEE compte la terminer en 2028. Son but : un Wi-Fi qui reste stable quand les choses se corsent, avec moins de blocages, des délais plus courts, des passages de relais plus fluides et moins de messages perdus.",
        "it": "La prossima versione del Wi-Fi, chiamata anche 802.11bn. È ancora in fase di scrittura, e l'IEEE prevede di finirla nel 2028. Il suo obiettivo è un Wi-Fi che resti stabile quando le cose si fanno difficili: meno blocchi, ritardi più brevi, passaggi più fluidi e meno messaggi persi.",
        "de": "Die nächste WLAN-Version, auch 802.11bn genannt. Sie wird noch geschrieben, und das IEEE rechnet mit dem Abschluss 2028. Ihr Ziel ist WLAN, das stabil bleibt, wenn es schwierig wird: weniger Hänger, kürzere Verzögerungen, sanftere Übergaben und weniger verlorene Nachrichten.",
    },
    "wi-fi-alliance": {
        "es": "El grupo de la industria que es dueño del nombre «Wi-Fi». Prueba productos y reparte los nombres de versión sencillos, como Wi-Fi 6 y Wi-Fi 7. No escribe las reglas de cómo funciona el Wi-Fi. Eso lo hace el IEEE, un grupo de ingenieros.",
        "fr": "Le groupement industriel qui possède le nom « Wi-Fi ». Il teste les produits et attribue les noms de version simples, comme Wi-Fi 6 et Wi-Fi 7. Il n'écrit pas les règles de fonctionnement du Wi-Fi. C'est l'IEEE, un groupe d'ingénieurs, qui s'en charge.",
        "it": "Il gruppo del settore che possiede il nome «Wi-Fi». Prova i prodotti e assegna i nomi di versione semplici, come Wi-Fi 6 e Wi-Fi 7. Non scrive le regole su come funziona il Wi-Fi. Lo fa l'IEEE, un gruppo di ingegneri.",
        "de": "Der Branchenverband, dem der Name „Wi-Fi“ gehört. Er testet Produkte und vergibt die einfachen Versionsnamen wie Wi-Fi 6 und Wi-Fi 7. Er schreibt nicht die Regeln dafür, wie WLAN funktioniert. Das macht das IEEE, eine Gruppe von Ingenieuren.",
    },
    "wi-fi-certified": {
        "es": "Una etiqueta de la Wi-Fi Alliance, el grupo dueño del nombre Wi-Fi. Significa que el producto pasó las pruebas de las funciones que aparecen en su certificado. Debería funcionar con otros equipos certificados en esas funciones. No significa que el producto tenga todas las funciones de Wi-Fi.",
        "fr": "Un label de la Wi-Fi Alliance, le groupement qui possède le nom Wi-Fi. Il signifie que le produit a réussi les tests pour les fonctions listées sur son certificat. Il devrait fonctionner avec d'autres matériels certifiés pour ces fonctions. Cela ne veut pas dire que le produit a toutes les fonctions du Wi-Fi.",
        "it": "Un marchio della Wi-Fi Alliance, il gruppo che possiede il nome Wi-Fi. Vuol dire che il prodotto ha superato i test per le funzioni elencate nel suo certificato. Dovrebbe funzionare con altri apparecchi certificati per quelle funzioni. Non vuol dire che il prodotto abbia tutte le funzioni del Wi-Fi.",
        "de": "Ein Siegel der Wi-Fi Alliance, der Gruppe, der der Name Wi-Fi gehört. Es bedeutet, dass das Produkt die Tests für die Funktionen auf seinem Zertifikat bestanden hat. Es sollte bei diesen Funktionen mit anderen zertifizierten Geräten zusammenarbeiten. Es bedeutet nicht, dass das Produkt jede WLAN-Funktion hat.",
    },
    "backward-compatibility": {
        "es": "El Wi-Fi más nuevo casi siempre puede seguir hablando con dispositivos más antiguos en la misma banda. Un punto de acceso nuevo (el aparato que emite el Wi-Fi) muchas veces sigue dando servicio a un portátil viejo en 2,4 o 5 GHz. Los dispositivos viejos no pueden usar bandas ni funciones que no tienen. Un dispositivo sin radio de 6 GHz no puede usar 6 GHz. Y 6 GHz exige WPA3, la seguridad más nueva, así que un dispositivo que solo tiene WPA2 no puede conectarse ahí.",
        "fr": "Le Wi-Fi plus récent peut en général encore parler aux appareils plus anciens sur la même bande. Un point d'accès neuf (le boîtier qui diffuse le Wi-Fi) sert souvent encore un vieil ordinateur portable en 2,4 ou 5 GHz. Les vieux appareils ne peuvent pas utiliser des bandes ou des fonctions qu'ils n'ont pas. Un appareil sans radio 6 GHz ne peut pas utiliser le 6 GHz. Et le 6 GHz exige le WPA3, la sécurité plus récente, donc un appareil qui ne connaît que le WPA2 ne peut pas s'y connecter.",
        "it": "Il Wi-Fi più nuovo di solito riesce ancora a parlare con i dispositivi più vecchi sulla stessa banda. Un access point nuovo (l'apparecchio che trasmette il Wi-Fi) spesso serve ancora un vecchio portatile a 2,4 o 5 GHz. I dispositivi vecchi non possono usare bande o funzioni che non hanno. Un dispositivo senza radio a 6 GHz non può usare i 6 GHz. E i 6 GHz richiedono il WPA3, la sicurezza più nuova, quindi un dispositivo che ha solo WPA2 non può collegarsi lì.",
        "de": "Neueres WLAN kann meist noch mit älteren Geräten auf demselben Band sprechen. Ein neuer Access Point (die Box, die das WLAN aussendet) bedient oft noch einen alten Laptop auf 2,4 oder 5 GHz. Alte Geräte können keine Bänder oder Funktionen nutzen, die sie nicht haben. Ein Gerät ohne 6-GHz-Funkmodul kann 6 GHz nicht nutzen. Und 6 GHz verlangt WPA3, die neuere Sicherheit, also kann ein Gerät, das nur WPA2 kennt, dort nicht beitreten.",
    },
    "rf": {
        "es": "Ondas de radio. El Wi-Fi las usa para llevar datos por el aire. La mayoría del Wi-Fi usa 3 bandas: 2,4, 5 y 6 GHz. No hace falta licencia para usarlas, pero los equipos igualmente tienen que seguir las reglas del gobierno sobre potencia y canales.",
        "fr": "Les ondes radio. Le Wi-Fi s'en sert pour transporter des données dans l'air. La plupart du Wi-Fi utilise 3 bandes : 2,4, 5 et 6 GHz. Il n'y a pas besoin de licence pour les utiliser, mais le matériel doit quand même suivre les règles de l'État sur la puissance et les canaux.",
        "it": "Onde radio. Il Wi-Fi le usa per portare dati attraverso l'aria. La maggior parte del Wi-Fi usa 3 bande: 2,4, 5 e 6 GHz. Non serve una licenza per usarle, ma gli apparecchi devono comunque seguire le regole dello Stato su potenza e canali.",
        "de": "Funkwellen. WLAN nutzt sie, um Daten durch die Luft zu tragen. Das meiste WLAN nutzt 3 Bänder: 2,4, 5 und 6 GHz. Du brauchst keine Lizenz, um sie zu nutzen, aber die Geräte müssen trotzdem die staatlichen Regeln zu Leistung und Kanälen einhalten.",
    },
    "frequency": {
        "es": "Cuántas veces sube y baja una onda de radio cada segundo, medido en hercios. 2,4 GHz significa 2.400 millones de veces por segundo. Los gobiernos reservaron mucho más espacio para el Wi-Fi en 5 y 6 GHz. Las frecuencias más altas también pierden fuerza más rápido con la distancia y al atravesar paredes.",
        "fr": "Le nombre de fois qu'une onde radio monte et descend chaque seconde, mesuré en hertz. 2,4 GHz veut dire 2,4 milliards de fois par seconde. Les États ont réservé beaucoup plus de place au Wi-Fi en 5 et 6 GHz. Les fréquences plus hautes perdent aussi leur force plus vite avec la distance et à travers les murs.",
        "it": "Quante volte un'onda radio sale e scende ogni secondo, misurato in hertz. 2,4 GHz vuol dire 2,4 miliardi di volte al secondo. Gli Stati hanno riservato molto più spazio al Wi-Fi a 5 e 6 GHz. Le frequenze più alte perdono anche forza più in fretta con la distanza e attraverso i muri.",
        "de": "Wie oft eine Funkwelle pro Sekunde auf und ab geht, gemessen in Hertz. 2,4 GHz heißt 2,4 Milliarden Mal pro Sekunde. Staaten haben für WLAN bei 5 und 6 GHz viel mehr Platz reserviert. Höhere Frequenzen verlieren außerdem mit der Entfernung und durch Wände schneller an Stärke.",
    },
    "wavelength": {
        "es": "La longitud de una onda de radio, de una cresta a la siguiente. Cuanto más alta es la frecuencia, más corta es la onda. Una onda de 2,4 GHz mide unos 12,5 cm (5 pulgadas). Una de 6 GHz mide unos 5 cm (2 pulgadas). Esto es parte de la razón por la que 6 GHz cubre menos área.",
        "fr": "La longueur d'une onde radio, d'un sommet au suivant. Plus la fréquence est haute, plus l'onde est courte. Une onde de 2,4 GHz mesure environ 12,5 cm (5 pouces). Une onde de 6 GHz mesure environ 5 cm (2 pouces). C'est en partie pour ça que le 6 GHz couvre une zone plus petite.",
        "it": "La lunghezza di un'onda radio, da un picco al successivo. Più alta è la frequenza, più corta è l'onda. Un'onda a 2,4 GHz è lunga circa 12,5 cm (5 pollici). Un'onda a 6 GHz è di circa 5 cm (2 pollici). Anche per questo i 6 GHz coprono un'area più piccola.",
        "de": "Die Länge einer Funkwelle, von einem Wellenberg zum nächsten. Je höher die Frequenz, desto kürzer die Welle. Eine 2,4-GHz-Welle ist etwa 12,5 cm (5 Zoll) lang. Eine 6-GHz-Welle etwa 5 cm (2 Zoll). Das ist ein Grund, warum 6 GHz weniger Fläche abdeckt.",
    },
    "db": {
        "es": "Una forma de comparar dos niveles de señal. Suma 3 dB y habrás casi duplicado la potencia. Resta 3 dB y la habrás reducido más o menos a la mitad. 10 dB es 10 veces la potencia.",
        "fr": "Une façon de comparer deux niveaux de signal. Ajoutez 3 dB et vous avez à peu près doublé la puissance. Retirez 3 dB et vous l'avez à peu près divisée par deux. 10 dB, c'est 10 fois la puissance.",
        "it": "Un modo per confrontare due livelli di segnale. Aggiungi 3 dB e hai più o meno raddoppiato la potenza. Togli 3 dB e l'hai più o meno dimezzata. 10 dB sono 10 volte la potenza.",
        "de": "Eine Art, zwei Signalpegel zu vergleichen. Plus 3 dB, und du hast die Leistung etwa verdoppelt. Minus 3 dB, und du hast sie etwa halbiert. 10 dB sind die 10-fache Leistung.",
    },
    "dbm": {
        "es": "La unidad de la potencia de la señal Wi-Fi. 0 dBm es una milésima de vatio. El Wi-Fi que capta tu teléfono es mucho más débil que eso, así que aparece como un número negativo. Cuanto más cerca de cero, más fuerte: -50 dBm es mucho mejor que -80 dBm.",
        "fr": "L'unité de puissance du signal Wi-Fi. 0 dBm, c'est un millième de watt. Le Wi-Fi que capte votre téléphone est bien plus faible que ça, donc il s'affiche en nombre négatif. Plus c'est proche de zéro, plus c'est fort : -50 dBm est bien meilleur que -80 dBm.",
        "it": "L'unità della potenza del segnale Wi-Fi. 0 dBm è un millesimo di watt. Il Wi-Fi che riceve il tuo telefono è molto più debole, quindi appare come un numero negativo. Più è vicino allo zero, più è forte: -50 dBm è molto meglio di -80 dBm.",
        "de": "Die Einheit für die Leistung des WLAN-Signals. 0 dBm ist ein Tausendstel Watt. Das WLAN, das dein Handy empfängt, ist viel schwächer, darum erscheint es als negative Zahl. Näher an null ist stärker: -50 dBm ist viel besser als -80 dBm.",
    },
    "dbi": {
        "es": "Cuánto concentra su señal una antena, comparada con una que la reparte igual en todas las direcciones. Un número más alto significa un haz más estrecho. La potencia de la radio sigue siendo la misma.",
        "fr": "À quel point une antenne concentre son signal, par rapport à une antenne qui le répartit pareil dans toutes les directions. Un chiffre plus élevé veut dire un faisceau plus serré. La puissance de la radio reste la même.",
        "it": "Quanto un'antenna concentra il suo segnale, rispetto a una che lo sparge uguale in tutte le direzioni. Un numero più alto vuol dire un fascio più stretto. La potenza della radio resta la stessa.",
        "de": "Wie stark eine Antenne ihr Signal bündelt, verglichen mit einer, die es in alle Richtungen gleich verteilt. Eine höhere Zahl bedeutet einen engeren Strahl. Die Leistung des Funkmoduls bleibt gleich.",
    },
    "rssi": {
        "es": "La lectura que hace un dispositivo de lo fuerte que es una señal. Suele mostrarse en dBm, una unidad de potencia de radio. Úsala para comparar lecturas en el mismo dispositivo. Cada fabricante la mide un poco distinto, así que no compares 2 marcas.",
        "fr": "La mesure qu'un appareil fait lui-même de la force d'un signal. Elle s'affiche en général en dBm, une unité de puissance radio. Servez-vous-en pour comparer des mesures sur le même appareil. Chaque fabricant la mesure un peu différemment, donc ne comparez pas 2 marques.",
        "it": "La lettura che un dispositivo fa da solo di quanto è forte un segnale. Di solito è mostrata in dBm, un'unità di potenza radio. Usala per confrontare letture sullo stesso dispositivo. Ogni produttore la misura in modo un po' diverso, quindi non confrontare 2 marche.",
        "de": "Die eigene Messung eines Geräts, wie stark ein Signal ist. Sie wird meist in dBm angezeigt, einer Einheit für Funkleistung. Nutze sie, um Werte auf demselben Gerät zu vergleichen. Jeder Hersteller misst sie etwas anders, also vergleiche keine 2 Marken.",
    },
    "signal-strength": {
        "es": "Lo fuerte que es la señal Wi-Fi donde estás, mejor expresada en dBm (una unidad de potencia de radio). Una señal fuerte ayuda, pero no basta por sí sola. La señal también tiene que estar bien por encima del ruido de radio de fondo.",
        "fr": "La force du signal Wi-Fi là où vous êtes, donnée de préférence en dBm (une unité de puissance radio). Un signal fort aide, mais ne suffit pas à lui seul. Le signal doit aussi dépasser nettement le bruit radio de fond.",
        "it": "Quanto è forte il segnale Wi-Fi dove ti trovi, indicato meglio in dBm (un'unità di potenza radio). Un segnale forte aiuta, ma da solo non basta. Il segnale deve anche stare ben sopra il rumore radio di fondo.",
        "de": "Wie stark das WLAN-Signal dort ist, wo du bist, am besten angegeben in dBm (einer Einheit für Funkleistung). Ein starkes Signal hilft, reicht aber allein nicht. Das Signal muss auch deutlich über dem Funkrauschen im Hintergrund liegen.",
    },
    "noise-floor": {
        "es": "El zumbido constante de energía de radio de fondo en un espacio. Una señal Wi-Fi tiene que estar por encima de él para que se la oiga. Si el ruido es alto, el Wi-Fi sufre aunque la señal sea fuerte.",
        "fr": "Le bourdonnement constant de l'énergie radio de fond dans un lieu. Un signal Wi-Fi doit le dépasser pour être entendu. Si le bruit est élevé, le Wi-Fi souffre même quand le signal est fort.",
        "it": "Il ronzio costante dell'energia radio di fondo in un ambiente. Un segnale Wi-Fi deve stare sopra di esso per essere sentito. Se il rumore è alto, il Wi-Fi ne soffre anche quando il segnale è forte.",
        "de": "Das stetige Summen der Funkenergie im Hintergrund eines Raums. Ein WLAN-Signal muss darüber liegen, um gehört zu werden. Ist das Rauschen hoch, leidet das WLAN, selbst wenn das Signal stark ist.",
    },
    "signal-to-noise-ratio": {
        "es": "Cuánto sobresale la señal Wi-Fi por encima del ruido de radio de fondo, medido en dB, una forma de comparar niveles de señal. Cuanto mayor es la diferencia, más rápida y estable es la conexión. Predice el rendimiento real mejor que la fuerza de la señal por sí sola.",
        "fr": "De combien le signal Wi-Fi dépasse le bruit radio de fond, mesuré en dB, une façon de comparer des niveaux de signal. Plus l'écart est grand, plus la connexion est rapide et stable. Il prédit les performances réelles mieux que la force du signal seule.",
        "it": "Quanto il segnale Wi-Fi sta sopra il rumore radio di fondo, misurato in dB, un modo per confrontare livelli di segnale. Più grande è il distacco, più la connessione è veloce e stabile. Prevede le prestazioni reali meglio della sola forza del segnale.",
        "de": "Wie weit das WLAN-Signal über dem Funkrauschen im Hintergrund liegt, gemessen in dB, einer Art, Signalpegel zu vergleichen. Je größer der Abstand, desto schneller und stabiler die Verbindung. Es sagt die echte Leistung besser voraus als die Signalstärke allein.",
    },
    "eirp": {
        "es": "La potencia total que sale de una antena en su dirección más fuerte. Toma la potencia de la radio, suma la concentración de la antena y resta lo que pierde el cable. Los límites del gobierno se aplican a este total.",
        "fr": "La puissance totale qui sort d'une antenne dans sa direction la plus forte. Prenez la puissance de la radio, ajoutez la concentration de l'antenne et retirez ce que perd le câble. Les limites fixées par l'État s'appliquent à ce total.",
        "it": "La potenza totale che esce da un'antenna nella sua direzione più forte. Prendi la potenza della radio, aggiungi la concentrazione dell'antenna e togli quello che perde il cavo. I limiti di legge si applicano a questo totale.",
        "de": "Die gesamte Leistung, die in der stärksten Richtung aus einer Antenne kommt. Nimm die Leistung des Funkmoduls, addiere die Bündelung der Antenne und zieh ab, was das Kabel verliert. Die staatlichen Grenzwerte gelten für diese Summe.",
    },
    "attenuation": {
        "es": "Cuánto se debilita una señal Wi-Fi al pasar por la distancia, las paredes y otras cosas. Algunos materiales le quitan un bocado mucho más grande que otros. El hormigón, el metal y el agua dañan la señal mucho más que el pladur.",
        "fr": "À quel point un signal Wi-Fi s'affaiblit avec la distance, les murs et tout le reste. Certains matériaux en prennent une bien plus grosse part que d'autres. Le béton, le métal et l'eau abîment le signal bien plus que le placo.",
        "it": "Quanto si indebolisce un segnale Wi-Fi attraversando distanza, muri e altre cose. Alcuni materiali se ne mangiano un pezzo molto più grande di altri. Cemento, metallo e acqua danneggiano il segnale molto più del cartongesso.",
        "de": "Wie stark ein WLAN-Signal auf seinem Weg durch Entfernung, Wände und anderes schwächer wird. Manche Materialien nehmen sich ein viel größeres Stück als andere. Beton, Metall und Wasser schaden dem Signal weit mehr als Trockenbau.",
    },
    "free-space-path-loss": {
        "es": "Cuánto se debilita una señal solo por extenderse con la distancia, sin nada en medio. Se extiende como las ondas en un estanque, así que llega menos a cada punto. A la misma distancia, el cálculo da más pérdida en 6 GHz que en 2,4 GHz. Eso se debe a que la antena receptora capta menos en frecuencias más altas. No es que el aire se la trague.",
        "fr": "À quel point un signal s'affaiblit simplement en s'étalant avec la distance, sans rien sur son chemin. Il s'étale comme des ronds dans l'eau, donc une moindre part arrive à chaque endroit. À la même distance, le calcul donne plus de perte en 6 GHz qu'en 2,4 GHz. Cela vient de l'antenne de réception, qui capte moins aux fréquences plus hautes. Ce n'est pas l'air qui l'absorbe.",
        "it": "Quanto si indebolisce un segnale solo perché si allarga con la distanza, senza niente in mezzo. Si allarga come i cerchi in uno stagno, quindi ne arriva meno in ogni punto. Alla stessa distanza, il calcolo dà più perdita a 6 GHz che a 2,4 GHz. Dipende dall'antenna che riceve, che cattura meno alle frequenze più alte. Non è l'aria ad assorbirlo.",
        "de": "Wie stark ein Signal schwächer wird, nur weil es sich über die Entfernung ausbreitet, ohne dass etwas im Weg ist. Es breitet sich aus wie Wellen in einem Teich, also kommt an jedem Punkt weniger an. Bei gleicher Entfernung ergibt die Rechnung mehr Verlust bei 6 GHz als bei 2,4 GHz. Das liegt daran, dass die Empfangsantenne bei höheren Frequenzen weniger auffängt. Die Luft schluckt es nicht.",
    },
    "multipath": {
        "es": "Cuando una señal te llega por varios caminos a la vez tras rebotar en paredes, suelos y muebles. Las copias llegan con una diferencia mínima. Al Wi-Fi antiguo esto le hacía daño. El Wi-Fi moderno con varias antenas usa los caminos extra para enviar más datos.",
        "fr": "Quand un signal vous arrive par plusieurs chemins à la fois après avoir rebondi sur les murs, les sols et les meubles. Les copies arrivent à un cheveu d'écart. L'ancien Wi-Fi en souffrait. Le Wi-Fi moderne à plusieurs antennes se sert des chemins en plus pour envoyer plus de données.",
        "it": "Quando un segnale ti arriva da più percorsi insieme dopo aver rimbalzato su muri, pavimenti e mobili. Le copie arrivano a un soffio l'una dall'altra. Il Wi-Fi più vecchio ne soffriva. Il Wi-Fi moderno con più antenne usa i percorsi in più per inviare più dati.",
        "de": "Wenn ein Signal dich auf mehreren Wegen gleichzeitig erreicht, nachdem es von Wänden, Böden und Möbeln abgeprallt ist. Die Kopien kommen um einen Hauch versetzt an. Älterem WLAN hat das geschadet. Modernes WLAN mit mehreren Antennen nutzt die zusätzlichen Wege, um mehr Daten zu senden.",
    },
    "interference": {
        "es": "Energía de radio no deseada que estorba al Wi-Fi. Puede venir de otras redes Wi-Fi. También puede venir de cosas que no son Wi-Fi en absoluto, como hornos de microondas, radares y algunos teléfonos inalámbricos.",
        "fr": "De l'énergie radio indésirable qui gêne le Wi-Fi. Elle peut venir d'autres réseaux Wi-Fi. Elle peut aussi venir de choses qui n'ont rien à voir avec le Wi-Fi, comme les fours à micro-ondes, les radars et certains téléphones sans fil.",
        "it": "Energia radio indesiderata che ostacola il Wi-Fi. Può venire da altre reti Wi-Fi. Può anche venire da cose che non sono affatto Wi-Fi, come forni a microonde, radar e alcuni telefoni cordless.",
        "de": "Unerwünschte Funkenergie, die WLAN in die Quere kommt. Sie kann von anderen WLAN-Netzen stammen. Sie kann auch von Dingen kommen, die gar kein WLAN sind, etwa Mikrowellen, Radar und manche schnurlose Telefone.",
    },
    "antenna-gain": {
        "es": "Lo bien que una antena concentra su señal en una dirección, medido en dBi (la unidad de concentración de una antena). La ganancia cambia la forma de la cobertura. La potencia de la radio sigue siendo la misma.",
        "fr": "La capacité d'une antenne à concentrer son signal dans une direction, mesurée en dBi (l'unité de concentration d'une antenne). Le gain change la forme de la couverture. La puissance de la radio reste la même.",
        "it": "Quanto bene un'antenna concentra il suo segnale in una direzione, misurato in dBi (l'unità per la concentrazione di un'antenna). Il guadagno cambia la forma della copertura. La potenza della radio resta la stessa.",
        "de": "Wie gut eine Antenne ihr Signal in eine Richtung bündelt, gemessen in dBi (der Einheit für die Bündelung einer Antenne). Der Gewinn ändert die Form der Abdeckung. Die Leistung des Funkmoduls bleibt gleich.",
    },
    "omnidirectional-antenna": {
        "es": "Una antena que envía su señal más o menos igual en todo el contorno, como una rosquilla tumbada. La mayoría de los puntos de acceso (los aparatos que emiten el Wi-Fi) en el centro de una sala o en el techo usan este tipo.",
        "fr": "Une antenne qui envoie son signal à peu près pareil tout autour, comme un beignet posé à plat. La plupart des points d'accès (les boîtiers qui diffusent le Wi-Fi) placés au milieu d'une pièce ou au plafond utilisent ce type.",
        "it": "Un'antenna che manda il suo segnale più o meno uguale tutto intorno, come una ciambella appoggiata in piano. La maggior parte degli access point (gli apparecchi che trasmettono il Wi-Fi) al centro di una stanza o sul soffitto usa questo tipo.",
        "de": "Eine Antenne, die ihr Signal ringsum ungefähr gleich aussendet, wie ein flach liegender Donut. Die meisten Access Points (die Boxen, die das WLAN aussenden) mitten im Raum oder an der Decke nutzen diese Art.",
    },
    "directional-antenna": {
        "es": "Una antena que apunta su señal hacia un lado, como una linterna en vez de una bombilla desnuda. Llega más lejos en esa dirección. Las antenas de parche, de panel y Yagi son tipos comunes.",
        "fr": "Une antenne qui dirige son signal d'un seul côté, comme une lampe torche au lieu d'une ampoule nue. Elle porte plus loin dans cette direction. Les antennes patch, panneau et Yagi sont des types courants.",
        "it": "Un'antenna che punta il suo segnale da una parte, come una torcia invece di una lampadina nuda. Arriva più lontano in quella direzione. Le antenne patch, a pannello e Yagi sono tipi comuni.",
        "de": "Eine Antenne, die ihr Signal in eine Richtung lenkt, wie eine Taschenlampe statt einer nackten Glühbirne. Sie reicht in diese Richtung weiter. Patch-, Panel- und Yagi-Antennen sind häufige Arten.",
    },
    "ofdm": {
        "es": "La forma en que el Wi-Fi divide un canal (el carril de la banda en el que habla el Wi-Fi) en muchos subcanales diminutos y envía datos por todos a la vez. Esto ayuda al Wi-Fi a soportar los ecos y las interferencias estrechas. Es una gran razón por la que el Wi-Fi funciona bien en interiores, donde las señales rebotan en todo. Todas las versiones principales de Wi-Fi desde 802.11a en 1999 lo usan.",
        "fr": "La façon dont le Wi-Fi découpe un canal (la voie de la bande sur laquelle parle le Wi-Fi) en beaucoup de minuscules sous-canaux et envoie des données sur tous à la fois. Cela aide le Wi-Fi à supporter les échos et les petites interférences étroites. C'est une grande raison pour laquelle le Wi-Fi marche bien en intérieur, où les signaux rebondissent sur tout. Toutes les grandes versions du Wi-Fi depuis 802.11a en 1999 l'utilisent.",
        "it": "Il modo in cui il Wi-Fi divide un canale (la corsia della banda su cui parla il Wi-Fi) in tanti piccoli sottocanali e manda dati su tutti insieme. Questo aiuta il Wi-Fi a reggere gli echi e le interferenze strette. È un motivo importante per cui il Wi-Fi funziona bene al chiuso, dove i segnali rimbalzano su tutto. Tutte le versioni principali del Wi-Fi dall'802.11a del 1999 lo usano.",
        "de": "Die Art, wie WLAN einen Kanal (die Spur des Bandes, auf der das WLAN spricht) in viele winzige Unterkanäle aufteilt und auf allen gleichzeitig Daten sendet. Das hilft WLAN, mit Echos und schmalen Störungen fertigzuwerden. Es ist ein wichtiger Grund, warum WLAN in Gebäuden gut funktioniert, wo Signale von allem abprallen. Jede wichtige WLAN-Version seit 802.11a von 1999 nutzt es.",
    },
    "ofdma": {
        "es": "Una mejora de Wi-Fi 6 (la versión de Wi-Fi de 2019). Divide un canal (el carril de la banda en el que habla el Wi-Fi) en trozos más pequeños para que un punto de acceso (el aparato que emite el Wi-Fi) pueda hablar con varios dispositivos en el mismo turno. Ayuda sobre todo cuando muchos dispositivos envían cada uno pocos datos.",
        "fr": "Une amélioration du Wi-Fi 6 (la version du Wi-Fi de 2019). Elle découpe un canal (la voie de la bande sur laquelle parle le Wi-Fi) en morceaux plus petits pour qu'un point d'accès (le boîtier qui diffuse le Wi-Fi) puisse parler à plusieurs appareils dans le même tour. Elle aide surtout quand beaucoup d'appareils envoient chacun un peu de données.",
        "it": "Un miglioramento del Wi-Fi 6 (la versione del Wi-Fi del 2019). Divide un canale (la corsia della banda su cui parla il Wi-Fi) in pezzi più piccoli, così un access point (l'apparecchio che trasmette il Wi-Fi) può parlare con più dispositivi nello stesso turno. Aiuta soprattutto quando tanti dispositivi mandano ognuno pochi dati.",
        "de": "Eine Verbesserung in Wi-Fi 6 (der WLAN-Version von 2019). Sie teilt einen Kanal (die Spur des Bandes, auf der das WLAN spricht) in kleinere Stücke, damit ein Access Point (die Box, die das WLAN aussendet) im selben Durchgang mit mehreren Geräten sprechen kann. Sie hilft am meisten, wenn viele Geräte jeweils wenig Daten senden.",
    },
    "mimo": {
        "es": "Usar varias antenas para enviar varios flujos de datos al mismo tiempo. Piensa en ello como añadir carriles a una carretera. Es la razón principal por la que el Wi-Fi se volvió mucho más rápido después de 2009.",
        "fr": "Utiliser plusieurs antennes pour envoyer plusieurs flux de données en même temps. C'est comme ajouter des voies à une route. C'est la raison principale pour laquelle le Wi-Fi est devenu tellement plus rapide après 2009.",
        "it": "Usare più antenne per inviare più flussi di dati nello stesso momento. È come aggiungere corsie a una strada. È il motivo principale per cui il Wi-Fi è diventato molto più veloce dopo il 2009.",
        "de": "Mehrere Antennen nutzen, um mehrere Datenströme gleichzeitig zu senden. Stell es dir vor wie zusätzliche Spuren auf einer Straße. Es ist der Hauptgrund, warum WLAN nach 2009 so viel schneller wurde.",
    },
    "mu-mimo": {
        "es": "Usar varias antenas para enviar a varios dispositivos en el mismo momento, en vez de uno tras otro. Los equipos Wi-Fi 5 (de 2013) lo trajeron para los datos que van hacia los dispositivos. Wi-Fi 6 (2019) lo añadió para los datos que vuelven, y los primeros equipos se certificaron para eso en 2022.",
        "fr": "Utiliser plusieurs antennes pour envoyer à plusieurs appareils au même moment, au lieu de l'un après l'autre. Le matériel Wi-Fi 5 (de 2013) l'a apporté pour les données qui vont vers les appareils. Le Wi-Fi 6 (2019) l'a ajouté pour les données qui reviennent, et le premier matériel a été certifié pour cela en 2022.",
        "it": "Usare più antenne per inviare a più dispositivi nello stesso momento, invece che uno dopo l'altro. Gli apparecchi Wi-Fi 5 (dal 2013) l'hanno portato per i dati che vanno verso i dispositivi. Il Wi-Fi 6 (2019) l'ha aggiunto per i dati che tornano indietro, e i primi apparecchi sono stati certificati per questo nel 2022.",
        "de": "Mehrere Antennen nutzen, um im selben Moment an mehrere Geräte zu senden, statt nacheinander. Geräte mit Wi-Fi 5 (ab 2013) brachten es für Daten, die zu den Geräten gehen. Wi-Fi 6 (2019) fügte es für Daten in die Gegenrichtung hinzu, und 2022 wurden die ersten Geräte dafür zertifiziert.",
    },
    "spatial-stream": {
        "es": "Un flujo de datos separado, enviado al mismo tiempo que otros en el mismo canal (el carril de la banda en el que habla el Wi-Fi). Más flujos significan más velocidad. Solo tienes tantos como admitan los dos extremos, y la mayoría de los teléfonos admite 2.",
        "fr": "Un flux de données séparé, envoyé en même temps que d'autres sur le même canal (la voie de la bande sur laquelle parle le Wi-Fi). Plus de flux, c'est plus de vitesse. Vous n'en avez qu'autant que les deux côtés en gèrent, et la plupart des téléphones en gèrent 2.",
        "it": "Un flusso di dati separato, inviato nello stesso momento di altri sullo stesso canale (la corsia della banda su cui parla il Wi-Fi). Più flussi vogliono dire più velocità. Ne hai solo quanti ne supportano entrambi i lati, e la maggior parte dei telefoni ne supporta 2.",
        "de": "Ein eigener Datenstrom, der gleichzeitig mit anderen auf demselben Kanal (der Spur des Bandes, auf der das WLAN spricht) gesendet wird. Mehr Ströme bedeuten mehr Tempo. Du bekommst nur so viele, wie beide Seiten unterstützen, und die meisten Handys unterstützen 2.",
    },
    "beamforming": {
        "es": "Ajustar el momento de la señal de varias antenas para que se sume justo donde está tu dispositivo. La señal te llega más fuerte sin subir la potencia. Ayuda al alcance y mantiene estable la conexión.",
        "fr": "Régler le moment où chaque antenne envoie le signal pour qu'il s'additionne pile là où se trouve votre appareil. Le signal vous arrive plus fort sans monter la puissance. Cela aide la portée et garde la connexion stable.",
        "it": "Regolare i tempi del segnale di più antenne perché si sommi proprio dove si trova il tuo dispositivo. Il segnale ti arriva più forte senza alzare la potenza. Aiuta la portata e tiene stabile la connessione.",
        "de": "Das Signal mehrerer Antennen zeitlich so abstimmen, dass es sich genau dort addiert, wo dein Gerät ist. Das Signal kommt stärker bei dir an, ohne dass die Leistung erhöht wird. Das hilft der Reichweite und hält die Verbindung stabil.",
    },
    "qam": {
        "es": "La forma en que el Wi-Fi mete bits en cada señal de radio. Los números más altos, como 256, 1024 y 4096, meten más bits cada vez. El problema es que necesitan una señal limpia y fuerte, así que suelen funcionar solo cerca del punto de acceso (el aparato que emite el Wi-Fi).",
        "fr": "La façon dont le Wi-Fi met des bits dans chaque signal radio. Les nombres plus élevés comme 256, 1024 et 4096 mettent plus de bits à chaque fois. Le problème, c'est qu'il leur faut un signal propre et fort, donc ils ne marchent en général que près du point d'accès (le boîtier qui diffuse le Wi-Fi).",
        "it": "Il modo in cui il Wi-Fi mette i bit in ogni segnale radio. I numeri più alti come 256, 1024 e 4096 mettono più bit ogni volta. Il problema è che hanno bisogno di un segnale pulito e forte, quindi di solito funzionano solo vicino all'access point (l'apparecchio che trasmette il Wi-Fi).",
        "de": "Die Art, wie WLAN Bits in jedes Funksignal packt. Höhere Zahlen wie 256, 1024 und 4096 packen jedes Mal mehr Bits hinein. Der Haken: Sie brauchen ein sauberes, starkes Signal, darum funktionieren sie meist nur nah am Access Point (der Box, die das WLAN aussendet).",
    },
    "mcs": {
        "es": "Un número que resume cómo envía datos un enlace. Indica cuántos bits van en cada señal y cuántos datos extra se añaden para corregir errores. Los números más altos son más rápidos, pero necesitan una señal más fuerte y limpia. La anchura del canal y el número de flujos de datos también fijan la velocidad final.",
        "fr": "Un nombre qui résume comment un lien envoie des données. Il indique combien de bits vont dans chaque signal et combien de données en plus sont ajoutées pour corriger les erreurs. Les nombres plus élevés vont plus vite, mais demandent un signal plus fort et plus propre. La largeur du canal et le nombre de flux de données fixent aussi la vitesse finale.",
        "it": "Un numero che riassume come un collegamento invia i dati. Dice quanti bit vanno in ogni segnale e quanti dati in più si aggiungono per correggere gli errori. I numeri più alti sono più veloci, ma chiedono un segnale più forte e più pulito. Anche la larghezza del canale e il numero di flussi di dati fissano la velocità finale.",
        "de": "Eine Zahl, die zusammenfasst, wie eine Verbindung Daten sendet. Sie sagt, wie viele Bits in jedes Signal gehen und wie viele zusätzliche Daten zur Fehlerkorrektur dazukommen. Höhere Zahlen sind schneller, brauchen aber ein stärkeres, saubereres Signal. Die Kanalbreite und die Zahl der Datenströme bestimmen ebenfalls das Endtempo.",
    },
    "data-rate-vs-throughput": {
        "es": "La velocidad de datos es la velocidad máxima que acuerdan tu dispositivo y el punto de acceso (el aparato que emite el Wi-Fi). El rendimiento es lo que de verdad obtienes. Compartir, los reintentos y el trabajo de gestión se llevan su parte. El rendimiento real suele ser solo de la mitad a dos tercios de la velocidad de datos, y menos en una red concurrida.",
        "fr": "Le débit de données, c'est la vitesse maximale sur laquelle votre appareil et le point d'accès (le boîtier qui diffuse le Wi-Fi) se mettent d'accord. Le débit utile, c'est ce que vous obtenez vraiment. Le partage, les renvois et la gestion en prennent chacun une part. Le débit utile réel n'est souvent que de la moitié aux deux tiers du débit de données, et moins sur un réseau chargé.",
        "it": "La velocità dati è la velocità massima su cui si accordano il tuo dispositivo e l'access point (l'apparecchio che trasmette il Wi-Fi). Il throughput è quello che ottieni davvero. La condivisione, i nuovi tentativi e la gestione se ne prendono una parte. Il throughput reale spesso è solo da metà a due terzi della velocità dati, e meno su una rete affollata.",
        "de": "Die Datenrate ist das Höchsttempo, auf das sich dein Gerät und der Access Point (die Box, die das WLAN aussendet) einigen. Der Durchsatz ist das, was du wirklich bekommst. Teilen, Wiederholungen und Verwaltung nehmen sich alle ihren Anteil. Der echte Durchsatz liegt oft nur bei der Hälfte bis zwei Dritteln der Datenrate, und in einem vollen Netz noch darunter.",
    },
    "guard-interval": {
        "es": "Una pausa diminuta después de cada trozo de datos (llamado símbolo) para que los ecos se apaguen antes de que empiece el siguiente. Una pausa más corta es un poco más rápida. Una más larga aguanta mejor en espacios con muchos ecos, como los almacenes.",
        "fr": "Une toute petite pause après chaque morceau de données (appelé symbole) pour que les échos s'éteignent avant que le suivant commence. Une pause plus courte est un peu plus rapide. Une plus longue tient mieux dans les lieux pleins d'échos, comme les entrepôts.",
        "it": "Una pausa piccolissima dopo ogni pezzo di dati (chiamato simbolo), così gli echi si spengono prima che parta il successivo. Una pausa più corta è un po' più veloce. Una più lunga regge meglio negli spazi con tanti echi, come i magazzini.",
        "de": "Eine winzige Pause nach jedem Datenstück (Symbol genannt), damit Echos abklingen, bevor das nächste beginnt. Eine kürzere Pause ist etwas schneller. Eine längere hält in Räumen mit vielen Echos besser durch, etwa in Lagerhallen.",
    },
    "target-wake-time": {
        "es": "Una función de Wi-Fi 6, la versión de Wi-Fi de 2019. Un dispositivo y el punto de acceso (el aparato que emite el Wi-Fi) fijan un horario para cuándo se despierta el dispositivo a enviar o recibir. El resto del tiempo el dispositivo duerme, lo que ahorra batería. Ayuda sobre todo a los teléfonos y a los pequeños aparatos de casa inteligente.",
        "fr": "Une fonction du Wi-Fi 6, la version du Wi-Fi de 2019. Un appareil et le point d'accès (le boîtier qui diffuse le Wi-Fi) fixent un horaire pour les moments où l'appareil se réveille pour envoyer ou recevoir. Le reste du temps, l'appareil dort, ce qui économise la batterie. Elle aide surtout les téléphones et les petits objets de maison connectée.",
        "it": "Una funzione del Wi-Fi 6, la versione del Wi-Fi del 2019. Un dispositivo e l'access point (l'apparecchio che trasmette il Wi-Fi) fissano un orario per quando il dispositivo si sveglia per inviare o ricevere. Il resto del tempo il dispositivo dorme, e così risparmia batteria. Aiuta soprattutto i telefoni e i piccoli dispositivi per la casa smart.",
        "de": "Eine Funktion von Wi-Fi 6, der WLAN-Version von 2019. Ein Gerät und der Access Point (die Box, die das WLAN aussendet) legen einen Zeitplan fest, wann das Gerät zum Senden oder Empfangen aufwacht. Den Rest der Zeit schläft das Gerät, was Akku spart. Das hilft am meisten Handys und kleinen Smart-Home-Geräten.",
    },
    "multi-link-operation": {
        "es": "El mayor cambio de Wi-Fi 7 (la versión de Wi-Fi de 2024). Un dispositivo puede mantener más de un enlace a la vez, como uno en 5 GHz y otro en 6 GHz. Algunos equipos usan los enlaces juntos para ganar velocidad. Otros saltan al enlace más despejado, para tener menos retraso. Lo que obtienes depende de las radios de los dos extremos.",
        "fr": "Le plus grand changement du Wi-Fi 7 (la version du Wi-Fi de 2024). Un appareil peut garder plus d'un lien à la fois, par exemple un en 5 GHz et un en 6 GHz. Certains matériels utilisent les liens ensemble pour la vitesse. D'autres sautent sur le lien le plus dégagé, pour moins de délai. Ce que vous obtenez dépend des radios des deux côtés.",
        "it": "Il cambiamento più grande del Wi-Fi 7 (la versione del Wi-Fi del 2024). Un dispositivo può tenere più di un collegamento alla volta, per esempio uno a 5 GHz e uno a 6 GHz. Alcuni apparecchi usano i collegamenti insieme per la velocità. Altri saltano sul collegamento più libero, per avere meno ritardo. Quello che ottieni dipende dalle radio ai due lati.",
        "de": "Die größte Neuerung in Wi-Fi 7 (der WLAN-Version von 2024). Ein Gerät kann mehr als eine Verbindung gleichzeitig halten, etwa eine auf 5 GHz und eine auf 6 GHz. Manche Geräte nutzen die Verbindungen zusammen für mehr Tempo. Manche springen auf die freieste Verbindung, für weniger Verzögerung. Was du bekommst, hängt von den Funkmodulen auf beiden Seiten ab.",
    },
    "bss-coloring": {
        "es": "Una función de Wi-Fi 6 (la versión de Wi-Fi de 2019) que marca el tráfico de cada red con un número, como si fuera un color. Un dispositivo puede distinguir rápido el tráfico de su propia red del de un vecino. Si la señal del vecino es débil, el dispositivo puede hablar sin esperar.",
        "fr": "Une fonction du Wi-Fi 6 (la version du Wi-Fi de 2019) qui marque le trafic de chaque réseau avec un numéro, comme une couleur. Un appareil peut vite distinguer le trafic de son propre réseau de celui d'un voisin. Si le signal du voisin est faible, l'appareil peut parler sans attendre.",
        "it": "Una funzione del Wi-Fi 6 (la versione del Wi-Fi del 2019) che segna il traffico di ogni rete con un numero, come un colore. Un dispositivo riesce a distinguere in fretta il traffico della sua rete da quello di un vicino. Se il segnale del vicino è debole, il dispositivo può parlare senza aspettare.",
        "de": "Eine Funktion von Wi-Fi 6 (der WLAN-Version von 2019), die den Verkehr jedes Netzes mit einer Nummer markiert, wie mit einer Farbe. Ein Gerät kann so schnell den Verkehr seines eigenen Netzes von dem eines Nachbarn unterscheiden. Ist das Signal des Nachbarn schwach, kann das Gerät sprechen, ohne zu warten.",
    },
    "preamble-puncturing": {
        "es": "Permite que un canal ancho (el carril de la banda en el que habla el Wi-Fi) se salte una porción ocupada y siga usando el resto. Sin esto, todo el canal tendría que encogerse a uno estrecho. Empezó en Wi-Fi 6 (2019) y creció en Wi-Fi 7 (2024).",
        "fr": "Permet à un canal large (la voie de la bande sur laquelle parle le Wi-Fi) de sauter une tranche occupée et de continuer à utiliser le reste. Sans cela, tout le canal devrait se réduire à un canal étroit. C'est apparu avec le Wi-Fi 6 (2019) et ça s'est étendu avec le Wi-Fi 7 (2024).",
        "it": "Permette a un canale largo (la corsia della banda su cui parla il Wi-Fi) di saltare una fetta occupata e continuare a usare il resto. Senza, l'intero canale dovrebbe restringersi a uno stretto. È nato con il Wi-Fi 6 (2019) ed è cresciuto con il Wi-Fi 7 (2024).",
        "de": "Lässt einen breiten Kanal (die Spur des Bandes, auf der das WLAN spricht) einen belegten Ausschnitt überspringen und den Rest weiter nutzen. Ohne das müsste der ganze Kanal auf einen schmalen schrumpfen. Es begann mit Wi-Fi 6 (2019) und wurde mit Wi-Fi 7 (2024) ausgebaut.",
    },
    "mac-address": {
        "es": "El número de identificación del hardware de un dispositivo, como un número de serie de su conexión de red. El Wi-Fi lo usa para enviar cada mensaje al dispositivo correcto. La mayoría de los teléfonos ahora se inventan uno nuevo para cada red, para proteger tu privacidad.",
        "fr": "Le numéro d'identification matériel d'un appareil, comme un numéro de série pour sa connexion réseau. Le Wi-Fi s'en sert pour envoyer chaque message au bon appareil. La plupart des téléphones en inventent maintenant un nouveau pour chaque réseau, pour protéger votre vie privée.",
        "it": "Il numero identificativo dell'hardware di un dispositivo, come un numero di serie per la sua connessione di rete. Il Wi-Fi lo usa per mandare ogni messaggio al dispositivo giusto. Oggi la maggior parte dei telefoni se ne inventa uno nuovo per ogni rete, per proteggere la tua privacy.",
        "de": "Die Hardware-Kennnummer eines Geräts, wie eine Seriennummer für seinen Netzwerkanschluss. WLAN nutzt sie, um jede Nachricht an das richtige Gerät zu schicken. Die meisten Handys denken sich heute für jedes Netz eine neue aus, um deine Privatsphäre zu schützen.",
    },
    "csma-ca": {
        "es": "La regla básica de buenos modales del Wi-Fi: primero escuchar, y hablar solo cuando el canal (el carril de la banda en el que habla el Wi-Fi) está en silencio. Normalmente solo un dispositivo puede hablar a la vez en un canal. Por eso el Wi-Fi va más lento cuantos más dispositivos lo comparten.",
        "fr": "La règle de politesse de base du Wi-Fi : écouter d'abord, et ne parler que quand le canal (la voie de la bande sur laquelle parle le Wi-Fi) est calme. En général, un seul appareil peut parler à la fois sur un canal. C'est pour ça que le Wi-Fi ralentit quand plus d'appareils le partagent.",
        "it": "La regola base di buone maniere del Wi-Fi: prima ascoltare, e parlare solo quando il canale (la corsia della banda su cui parla il Wi-Fi) è in silenzio. Di solito su un canale può parlare un solo dispositivo alla volta. Per questo il Wi-Fi rallenta quando più dispositivi lo dividono.",
        "de": "Die Grundregel des Anstands im WLAN: erst zuhören und nur sprechen, wenn der Kanal (die Spur des Bandes, auf der das WLAN spricht) still ist. Meist kann auf einem Kanal nur ein Gerät gleichzeitig sprechen. Darum wird WLAN langsamer, je mehr Geräte es sich teilen.",
    },
    "airtime": {
        "es": "Cuánto tiempo usa un dispositivo en su canal (el carril de la banda en el que habla el Wi-Fi) para enviar sus datos. Un dispositivo lento o lejano tarda más en enviar los mismos datos. Eso deja menos tiempo para todos los demás.",
        "fr": "Le temps qu'un appareil passe sur son canal (la voie de la bande sur laquelle parle le Wi-Fi) pour envoyer ses données. Un appareil lent ou éloigné met plus longtemps à envoyer les mêmes données. Cela laisse moins de temps à tous les autres.",
        "it": "Quanto tempo un dispositivo usa sul suo canale (la corsia della banda su cui parla il Wi-Fi) per inviare i suoi dati. Un dispositivo lento o lontano ci mette di più a inviare gli stessi dati. Questo lascia meno tempo a tutti gli altri.",
        "de": "Wie viel Zeit ein Gerät auf seinem Kanal (der Spur des Bandes, auf der das WLAN spricht) braucht, um seine Daten zu senden. Ein langsames oder weit entferntes Gerät braucht für dieselben Daten länger. Das lässt allen anderen weniger Zeit.",
    },
    "channel-utilization": {
        "es": "Lo ocupado que está un canal (el carril de la banda en el que habla el Wi-Fi), como porcentaje del tiempo que está en uso. Un número alto es una de las señales más claras de una red lenta y saturada.",
        "fr": "À quel point un canal (la voie de la bande sur laquelle parle le Wi-Fi) est occupé, en pourcentage du temps où il sert. Un chiffre élevé est l'un des signes les plus nets d'un réseau lent et encombré.",
        "it": "Quanto è occupato un canale (la corsia della banda su cui parla il Wi-Fi), come percentuale del tempo in cui è in uso. Un numero alto è uno dei segni più chiari di una rete lenta e affollata.",
        "de": "Wie belegt ein Kanal (die Spur des Bandes, auf der das WLAN spricht) ist, als Prozentsatz der Zeit, in der er genutzt wird. Eine hohe Zahl ist eines der deutlichsten Zeichen für ein langsames, volles Netz.",
    },
    "beacon": {
        "es": "Un mensaje corto que un punto de acceso (el aparato que emite el Wi-Fi) envía unas 10 veces por segundo. Dice el nombre de la red y lo que puede hacer. Los dispositivos lo usan para encontrar la red y mantenerse al compás de ella.",
        "fr": "Un court message qu'un point d'accès (le boîtier qui diffuse le Wi-Fi) envoie environ 10 fois par seconde. Il donne le nom du réseau et ce qu'il sait faire. Les appareils s'en servent pour trouver le réseau et rester en phase avec lui.",
        "it": "Un breve messaggio che un access point (l'apparecchio che trasmette il Wi-Fi) invia circa 10 volte al secondo. Dice il nome della rete e cosa sa fare. I dispositivi lo usano per trovare la rete e restare al passo con lei.",
        "de": "Eine kurze Nachricht, die ein Access Point (die Box, die das WLAN aussendet) etwa 10-mal pro Sekunde sendet. Sie nennt den Namen des Netzes und was es kann. Geräte nutzen sie, um das Netz zu finden und mit ihm im Takt zu bleiben.",
    },
    "tim": {
        "es": "Una lista dentro de cada baliza, el mensaje corto que un punto de acceso (el aparato que emite el Wi-Fi) envía unas 10 veces por segundo. Nombra a los dispositivos dormidos que tienen mensajes esperando. Un teléfono se despierta, mira la lista y pide sus mensajes solo si aparece en ella.",
        "fr": "Une liste dans chaque balise, le court message qu'un point d'accès (le boîtier qui diffuse le Wi-Fi) envoie environ 10 fois par seconde. Elle nomme les appareils en veille qui ont des messages en attente. Un téléphone se réveille, regarde la liste et ne demande ses messages que s'il y figure.",
        "it": "Un elenco dentro ogni beacon, il breve messaggio che un access point (l'apparecchio che trasmette il Wi-Fi) invia circa 10 volte al secondo. Nomina i dispositivi addormentati che hanno messaggi in attesa. Un telefono si sveglia, controlla l'elenco e chiede i suoi messaggi solo se c'è il suo nome.",
        "de": "Eine Liste in jedem Beacon, der kurzen Nachricht, die ein Access Point (die Box, die das WLAN aussendet) etwa 10-mal pro Sekunde sendet. Sie nennt die schlafenden Geräte, für die Nachrichten warten. Ein Handy wacht auf, prüft die Liste und fragt nur dann nach seinen Nachrichten, wenn es genannt ist.",
    },
    "dtim": {
        "es": "Una baliza especial (el mensaje corto que un punto de acceso envía unas 10 veces por segundo), enviada cada pocas balizas, que avisa de que están a punto de salir mensajes para muchos dispositivos a la vez. El punto de acceso los envía justo después, y los dispositivos dormidos se despiertan para recogerlos. Enviarla con menos frecuencia ahorra batería, pero añade retraso.",
        "fr": "Une balise spéciale (le court message qu'un point d'accès envoie environ 10 fois par seconde), envoyée toutes les quelques balises, qui annonce que des messages pour beaucoup d'appareils à la fois vont partir. Le point d'accès les envoie juste après, et les appareils en veille se réveillent pour les attraper. L'envoyer moins souvent économise la batterie, mais ajoute du délai.",
        "it": "Un beacon speciale (il breve messaggio che un access point invia circa 10 volte al secondo), inviato ogni pochi beacon, che avvisa che stanno per partire messaggi per molti dispositivi insieme. L'access point li invia subito dopo, e i dispositivi addormentati si svegliano per prenderli. Inviarlo meno spesso risparmia batteria, ma aggiunge ritardo.",
        "de": "Ein besonderer Beacon (die kurze Nachricht, die ein Access Point etwa 10-mal pro Sekunde sendet), der alle paar Beacons kommt und ankündigt, dass gleich Nachrichten für viele Geräte auf einmal hinausgehen. Der Access Point sendet sie direkt danach, und schlafende Geräte wachen auf, um sie abzufangen. Ihn seltener zu senden spart Akku, bringt aber Verzögerung.",
    },
    "rts-cts": {
        "es": "Un rápido «¿puedo?» y «adelante» antes de enviar. Reserva el canal (el carril de la banda en el que habla el Wi-Fi) para que los dispositivos que no se oyen entre sí no hablen unos encima de otros.",
        "fr": "Un rapide « je peux ? » et « vas-y » avant d'envoyer. Cela réserve le canal (la voie de la bande sur laquelle parle le Wi-Fi) pour que les appareils qui ne s'entendent pas ne parlent pas en même temps.",
        "it": "Un rapido «posso?» e «vai pure» prima di inviare. Tiene occupato il canale (la corsia della banda su cui parla il Wi-Fi), così i dispositivi che non si sentono tra loro non si parlano sopra.",
        "de": "Ein schnelles „Darf ich?“ und „Leg los“ vor dem Senden. Es hält den Kanal (die Spur des Bandes, auf der das WLAN spricht) frei, damit Geräte, die sich gegenseitig nicht hören, nicht durcheinanderreden.",
    },
    "hidden-node": {
        "es": "Dos dispositivos oyen los dos al punto de acceso (el aparato que emite el Wi-Fi), pero no se oyen entre sí. Así que hablan a la vez, y sus mensajes chocan en el punto de acceso. Es una causa clásica de reintentos que nadie sabe explicar.",
        "fr": "Deux appareils entendent tous les deux le point d'accès (le boîtier qui diffuse le Wi-Fi), mais ils ne s'entendent pas entre eux. Alors ils parlent en même temps, et leurs messages se percutent au point d'accès. C'est une cause classique de renvois que personne n'arrive à expliquer.",
        "it": "Due dispositivi sentono entrambi l'access point (l'apparecchio che trasmette il Wi-Fi), ma non si sentono tra loro. Così parlano insieme, e i loro messaggi si scontrano sull'access point. È una causa classica di ritrasmissioni che nessuno sa spiegare.",
        "de": "Zwei Geräte hören beide den Access Point (die Box, die das WLAN aussendet), aber nicht einander. Also sprechen beide gleichzeitig, und ihre Nachrichten prallen am Access Point zusammen. Das ist eine klassische Ursache für Wiederholungen, die sich niemand erklären kann.",
    },
    "qos-wmm": {
        "es": "La forma que tiene el Wi-Fi de dar ventaja a las llamadas y al vídeo. Ordena el tráfico en 4 grupos: voz, vídeo, normal y segundo plano. La voz y el vídeo esperan menos, así que suelen salir al aire primero. Ayuda mucho, pero en una red saturada incluso una llamada puede sufrir.",
        "fr": "La façon dont le Wi-Fi donne un avantage aux appels et à la vidéo. Il trie le trafic en 4 groupes : voix, vidéo, normal et arrière-plan. La voix et la vidéo attendent moins, donc elles passent en général en premier sur les ondes. Ça aide beaucoup, mais sur un réseau encombré, même un appel peut encore souffrir.",
        "it": "Il modo in cui il Wi-Fi dà più possibilità alle chiamate e ai video. Divide il traffico in 4 gruppi: voce, video, normale e secondo piano. Voce e video aspettano meno, quindi di solito vanno in onda per primi. Aiuta molto, ma su una rete affollata anche una chiamata può soffrire.",
        "de": "Die Art, wie WLAN Anrufen und Video bessere Chancen gibt. Es sortiert den Verkehr in 4 Gruppen: Sprache, Video, normal und Hintergrund. Sprache und Video warten weniger, darum kommen sie meist zuerst in die Luft. Das hilft viel, aber in einem vollen Netz kann trotzdem sogar ein Anruf leiden.",
    },
    "access-point": {
        "es": "El aparato que emite la señal Wi-Fi y conecta los dispositivos inalámbricos a la red por cable. Un punto de acceso no es un router. Muchos aparatos de casa meten los dos en una sola caja, y de ahí viene la confusión.",
        "fr": "Le boîtier qui diffuse le signal Wi-Fi et relie les appareils sans fil au réseau câblé. Un point d'accès n'est pas un routeur. Beaucoup de box à la maison réunissent les deux dans un seul boîtier, d'où la confusion.",
        "it": "L'apparecchio che trasmette il segnale Wi-Fi e collega i dispositivi senza fili alla rete cablata. Un access point non è un router. Molti apparecchi di casa mettono tutti e due in una sola scatola, ed è da lì che nasce la confusione.",
        "de": "Die Box, die das WLAN-Signal aussendet und drahtlose Geräte mit dem kabelgebundenen Netz verbindet. Ein Access Point ist kein Router. Viele Boxen für zu Hause packen beides in ein Gehäuse, und daher kommt die Verwechslung.",
    },
    "station-sta-client": {
        "es": "Cualquier dispositivo que se conecta a una red Wi-Fi: un teléfono, un portátil, una impresora, un sensor o una tele. Los ingenieros lo llaman estación, o STA.",
        "fr": "Tout appareil qui se connecte à un réseau Wi-Fi : téléphone, ordinateur portable, imprimante, capteur ou télé. Les ingénieurs l'appellent une station, ou STA.",
        "it": "Qualsiasi dispositivo che si collega a una rete Wi-Fi: un telefono, un portatile, una stampante, un sensore o una TV. Gli ingegneri lo chiamano stazione, o STA.",
        "de": "Jedes Gerät, das einem WLAN-Netz beitritt: ein Handy, Laptop, Drucker, Sensor oder Fernseher. Ingenieure nennen es eine Station, kurz STA.",
    },
    "ssid": {
        "es": "El nombre de red que ves y eliges, como «HomeNetwork». Varios puntos de acceso (los aparatos que emiten el Wi-Fi) pueden compartir un mismo nombre. Así tu dispositivo puede moverse entre ellos como si fueran una sola red.",
        "fr": "Le nom de réseau que vous voyez et choisissez, comme « HomeNetwork ». Plusieurs points d'accès (les boîtiers qui diffusent le Wi-Fi) peuvent partager un même nom. Votre appareil peut alors passer de l'un à l'autre comme s'il s'agissait d'un seul réseau.",
        "it": "Il nome di rete che vedi e scegli, come «HomeNetwork». Più access point (gli apparecchi che trasmettono il Wi-Fi) possono condividere un solo nome. Il tuo dispositivo può così spostarsi tra loro come se fossero una rete sola.",
        "de": "Der Netzwerkname, den du siehst und auswählst, etwa „HomeNetwork“. Mehrere Access Points (die Boxen, die das WLAN aussenden) können sich einen Namen teilen. Dein Gerät kann dann zwischen ihnen wechseln, als wären sie ein einziges Netz.",
    },
    "bssid": {
        "es": "La identificación de una radio en un punto de acceso (el aparato que emite el Wi-Fi). Suele basarse en la dirección de hardware de la radio. Un mismo nombre de red puede tener docenas de estas en todo un edificio.",
        "fr": "L'identifiant d'une radio sur un point d'accès (le boîtier qui diffuse le Wi-Fi). Il est en général basé sur l'adresse matérielle de la radio. Un seul nom de réseau peut en avoir des dizaines dans un bâtiment.",
        "it": "L'identificativo di una radio su un access point (l'apparecchio che trasmette il Wi-Fi). Di solito si basa sull'indirizzo hardware della radio. Un solo nome di rete può averne decine in tutto un edificio.",
        "de": "Die Kennung eines Funkmoduls in einem Access Point (der Box, die das WLAN aussendet). Sie beruht meist auf der Hardware-Adresse des Funkmoduls. Ein Netzwerkname kann in einem Gebäude Dutzende davon haben.",
    },
    "wireless-lan-controller": {
        "es": "Un equipo o servicio que gestiona muchos puntos de acceso (los aparatos que emiten el Wi-Fi) desde un solo sitio. Les envía la configuración, vigila su estado y ayuda a elegir canales y potencia. Puede animar a los dispositivos a pasarse a un punto de acceso mejor. Pero es el dispositivo el que decide cuándo moverse.",
        "fr": "Un boîtier ou un service qui pilote beaucoup de points d'accès (les boîtiers qui diffusent le Wi-Fi) depuis un seul endroit. Il leur envoie leurs réglages, surveille leur état et aide à choisir les canaux et la puissance. Il peut pousser les appareils à passer sur un meilleur point d'accès. C'est quand même l'appareil qui décide quand changer.",
        "it": "Un apparecchio o servizio che gestisce tanti access point (gli apparecchi che trasmettono il Wi-Fi) da un solo posto. Invia le loro impostazioni, ne controlla lo stato e aiuta a scegliere canali e potenza. Può spingere i dispositivi a passare a un access point migliore. È comunque il dispositivo a decidere quando spostarsi.",
        "de": "Eine Box oder ein Dienst, der viele Access Points (die Boxen, die das WLAN aussenden) von einer Stelle aus steuert. Er verteilt ihre Einstellungen, überwacht ihren Zustand und hilft bei der Wahl von Kanälen und Leistung. Er kann Geräte anstupsen, zu einem besseren Access Point zu wechseln. Wann es wechselt, entscheidet trotzdem das Gerät.",
    },
    "cloud-managed-wi-fi": {
        "es": "Wi-Fi de empresa que configuras y vigilas desde una página web, en vez de con un controlador en el propio sitio. Es una de varias formas en que las empresas gestionan su Wi-Fi.",
        "fr": "Du Wi-Fi d'entreprise que l'on configure et surveille depuis un site web, au lieu d'un boîtier contrôleur sur place. C'est l'une des différentes façons dont les entreprises gèrent leur Wi-Fi.",
        "it": "Wi-Fi aziendale che configuri e controlli da un sito web, invece che da un controller sul posto. È uno dei vari modi in cui le aziende gestiscono il loro Wi-Fi.",
        "de": "Firmen-WLAN, das du über eine Website einrichtest und überwachst, statt über eine Controller-Box vor Ort. Es ist eine von mehreren Arten, wie Firmen ihr WLAN betreiben.",
    },
    "roaming": {
        "es": "Cuando un dispositivo en movimiento pasa de un punto de acceso (el aparato que emite el Wi-Fi) a otro de la misma red. Si se hace bien, tu llamada o tu vídeo siguen sin un solo tropiezo.",
        "fr": "Quand un appareil en mouvement passe d'un point d'accès (le boîtier qui diffuse le Wi-Fi) à un autre sur le même réseau. Bien fait, votre appel ou votre vidéo continue sans le moindre accroc.",
        "it": "Quando un dispositivo in movimento passa da un access point (l'apparecchio che trasmette il Wi-Fi) a un altro della stessa rete. Se è fatto bene, la tua chiamata o il tuo video vanno avanti senza un intoppo.",
        "de": "Wenn ein Gerät in Bewegung von einem Access Point (der Box, die das WLAN aussendet) an einen anderen im selben Netz übergibt. Richtig gemacht, läuft dein Anruf oder Video ohne Aussetzer weiter.",
    },
    "fast-roaming": {
        "es": "Un conjunto de 3 añadidos que aceleran el paso entre puntos de acceso (los aparatos que emiten el Wi-Fi). 802.11k le da a tu dispositivo una lista de los cercanos. 802.11v puede sugerir uno mejor. 802.11r acelera el inicio de sesión seguro en el nuevo. Tu dispositivo sigue teniendo la última palabra sobre cuándo moverse.",
        "fr": "Un ensemble de 3 ajouts qui accélèrent le passage d'un point d'accès (les boîtiers qui diffusent le Wi-Fi) à l'autre. 802.11k donne à votre appareil une liste de ceux qui sont proches. 802.11v peut en suggérer un meilleur. 802.11r accélère la connexion sécurisée sur le nouveau. Votre appareil garde le dernier mot sur le moment où il change.",
        "it": "Un insieme di 3 aggiunte che velocizzano il passaggio tra access point (gli apparecchi che trasmettono il Wi-Fi). 802.11k dà al tuo dispositivo un elenco di quelli vicini. 802.11v può suggerirne uno migliore. 802.11r velocizza l'accesso sicuro su quello nuovo. L'ultima parola su quando spostarsi resta al tuo dispositivo.",
        "de": "Ein Satz aus 3 Erweiterungen, die Übergaben zwischen Access Points (den Boxen, die das WLAN aussenden) beschleunigen. 802.11k gibt deinem Gerät eine Liste der nahen Access Points. 802.11v kann einen besseren vorschlagen. 802.11r beschleunigt die sichere Anmeldung beim neuen. Wann es wechselt, entscheidet am Ende weiterhin dein Gerät.",
    },
    "sticky-client": {
        "es": "Un dispositivo que se aferra a un punto de acceso (el aparato que emite el Wi-Fi) lejano cuando tiene uno más cercano y más fuerte justo al lado. Es una razón común por la que el Wi-Fi va mal mientras te mueves.",
        "fr": "Un appareil qui reste accroché à un point d'accès (le boîtier qui diffuse le Wi-Fi) éloigné alors qu'un plus proche et plus fort est juste là. C'est une raison courante pour laquelle le Wi-Fi semble mauvais quand on se déplace.",
        "it": "Un dispositivo che resta attaccato a un access point (l'apparecchio che trasmette il Wi-Fi) lontano quando ce n'è uno più vicino e più forte proprio lì. È un motivo comune per cui il Wi-Fi sembra andare male mentre ti sposti.",
        "de": "Ein Gerät, das an einem weit entfernten Access Point (der Box, die das WLAN aussendet) hängen bleibt, obwohl ein näherer, stärkerer direkt daneben ist. Das ist ein häufiger Grund, warum sich WLAN beim Herumlaufen schlecht anfühlt.",
    },
    "mesh": {
        "es": "Una instalación en la que los puntos de acceso (los aparatos que emiten el Wi-Fi) se conectan entre sí por Wi-Fi en vez de por cable. Es fácil, porque no hay que tender cables. El precio es la velocidad: cada salto inalámbrico se come parte de lo que te queda a ti.",
        "fr": "Une installation où les points d'accès (les boîtiers qui diffusent le Wi-Fi) se relient entre eux par Wi-Fi au lieu de câbles. C'est simple, puisqu'il n'y a pas de câbles à tirer. Le prix, c'est la vitesse : chaque saut sans fil grignote ce qui vous reste.",
        "it": "Un impianto in cui gli access point (gli apparecchi che trasmettono il Wi-Fi) si collegano tra loro via Wi-Fi invece che con i cavi. È facile, perché non devi stendere cavi. Il prezzo è la velocità: ogni salto senza fili si mangia una parte di quello che resta a te.",
        "de": "Ein Aufbau, bei dem sich Access Points (die Boxen, die das WLAN aussenden) über WLAN statt über Kabel miteinander verbinden. Das ist einfach, weil du keine Kabel verlegen musst. Der Preis ist das Tempo: Jeder Funksprung knabbert an dem, was für dich übrig bleibt.",
    },
    "band-steering": {
        "es": "Una función que empuja a los dispositivos hacia una banda menos saturada. Casi siempre los lleva de 2,4 GHz a 5 o 6 GHz, donde suelen funcionar mejor.",
        "fr": "Une fonction qui pousse les appareils vers une bande moins encombrée. Le plus souvent, elle les fait passer du 2,4 GHz au 5 ou au 6 GHz, où ils marchent en général mieux.",
        "it": "Una funzione che spinge i dispositivi verso una banda meno affollata. Il più delle volte li sposta dai 2,4 GHz ai 5 o 6 GHz, dove di solito vanno meglio.",
        "de": "Eine Funktion, die Geräte auf ein weniger volles Band schiebt. Meist holt sie sie von 2,4 GHz hinauf auf 5 oder 6 GHz, wo sie in der Regel besser laufen.",
    },
    "power-over-ethernet": {
        "es": "Enviar datos y electricidad por un mismo cable de red. Así un punto de acceso (el aparato que emite el Wi-Fi) en el techo no necesita un enchufe cerca.",
        "fr": "Envoyer à la fois les données et le courant électrique sur un seul câble réseau. Un point d'accès (le boîtier qui diffuse le Wi-Fi) au plafond n'a alors pas besoin de prise murale à côté.",
        "it": "Mandare sia i dati sia la corrente elettrica su un solo cavo di rete. Così un access point (l'apparecchio che trasmette il Wi-Fi) sul soffitto non ha bisogno di una presa vicina.",
        "de": "Daten und Strom über ein einziges Netzwerkkabel schicken. Ein Access Point (die Box, die das WLAN aussendet) an der Decke braucht dann keine Steckdose in der Nähe.",
    },
    "site-survey": {
        "es": "Medir y planificar el Wi-Fi de un edificio. Los estudios predictivos simulan el edificio con software. Los estudios pasivos recorren el espacio y escuchan. Los estudios activos lo recorren conectados, haciendo pruebas por el camino.",
        "fr": "Mesurer et planifier le Wi-Fi d'un bâtiment. Les études prédictives modélisent le bâtiment dans un logiciel. Les études passives parcourent les lieux et écoutent. Les études actives les parcourent en restant connectées, en testant au fur et à mesure.",
        "it": "Misurare e pianificare il Wi-Fi in un edificio. I sopralluoghi predittivi simulano l'edificio con un software. Quelli passivi percorrono lo spazio e ascoltano. Quelli attivi lo percorrono restando connessi, facendo test strada facendo.",
        "de": "WLAN in einem Gebäude messen und planen. Vorhersage-Messungen bilden das Gebäude in einer Software nach. Passive Messungen gehen die Räume ab und hören zu. Aktive Messungen gehen sie verbunden ab und testen unterwegs.",
    },
    "heat-map": {
        "es": "Un plano coloreado para mostrar la señal o el rendimiento del Wi-Fi, como un mapa del tiempo. Hace que los puntos débiles se vean fácilmente.",
        "fr": "Un plan d'étage coloré pour montrer le signal ou les performances du Wi-Fi, comme une carte météo. Il rend les zones faibles faciles à voir.",
        "it": "Una pianta colorata per mostrare il segnale o le prestazioni del Wi-Fi, come una mappa del meteo. Rende facili da vedere i punti deboli.",
        "de": "Ein eingefärbter Grundriss, der das WLAN-Signal oder die Leistung zeigt, wie eine Wetterkarte. So sind die schwachen Stellen leicht zu sehen.",
    },
    "wpa2": {
        "es": "La seguridad Wi-Fi que usaron la mayoría de las redes durante muchos años. En casa usa una sola contraseña compartida. Su punto débil: un atacante que graba tu inicio de sesión puede llevárselo a casa e intentar adivinar la contraseña todo el tiempo que quiera. La versión para empresas, con un inicio de sesión propio para cada persona, no tiene ese problema.",
        "fr": "La sécurité Wi-Fi que la plupart des réseaux ont utilisée pendant des années. À la maison, elle utilise un seul mot de passe partagé. Son point faible : un attaquant qui enregistre votre connexion peut l'emporter chez lui et deviner le mot de passe aussi longtemps qu'il veut. La version entreprise, avec un identifiant propre à chaque personne, n'a pas ce problème.",
        "it": "La sicurezza Wi-Fi che la maggior parte delle reti ha usato per molti anni. A casa usa una sola password condivisa. Il suo punto debole: un malintenzionato che registra il tuo accesso può portarselo a casa e provare a indovinare la password per tutto il tempo che vuole. La versione aziendale, con un accesso personale per ogni persona, non ha questo problema.",
        "de": "Die WLAN-Sicherheit, die die meisten Netze viele Jahre lang nutzten. Zu Hause nutzt sie ein gemeinsames Passwort. Ihre Schwachstelle: Ein Angreifer, der deine Anmeldung aufzeichnet, kann sie mit nach Hause nehmen und das Passwort so lange raten, wie er will. Die Firmenversion mit eigener Anmeldung für jede Person hat dieses Problem nicht.",
    },
    "wpa3": {
        "es": "La seguridad Wi-Fi más nueva. En casa usa una comprobación de contraseña que frena el viejo truco, usado contra el antiguo WPA2, de grabar un inicio de sesión y adivinar la contraseña después. También bloquea los falsos mensajes de «estás desconectado». Una red configurada para admitir WPA2 y WPA3 a la vez deja abierto el viejo punto débil para los dispositivos antiguos.",
        "fr": "La sécurité Wi-Fi plus récente. À la maison, elle utilise une vérification du mot de passe qui bloque la vieille astuce, utilisée contre l'ancien WPA2, qui consiste à enregistrer une connexion et à deviner le mot de passe plus tard. Elle bloque aussi les faux messages « vous êtes déconnecté ». Un réseau réglé pour accepter à la fois WPA2 et WPA3 laisse le vieux point faible ouvert pour les appareils plus anciens.",
        "it": "La sicurezza Wi-Fi più nuova. A casa usa un controllo della password che ferma il vecchio trucco, usato contro il vecchio WPA2, di registrare un accesso e indovinare la password più tardi. Blocca anche i falsi messaggi «sei disconnesso». Una rete impostata per accettare sia WPA2 sia WPA3 lascia aperto il vecchio punto debole per i dispositivi più vecchi.",
        "de": "Die neuere WLAN-Sicherheit. Zu Hause nutzt sie eine Passwortprüfung, die den alten Trick gegen das ältere WPA2 stoppt: eine Anmeldung aufzeichnen und das Passwort später raten. Sie blockiert auch gefälschte „Du bist getrennt“-Nachrichten. Ein Netz, das sowohl WPA2 als auch WPA3 zulässt, lässt die alte Schwachstelle für ältere Geräte offen.",
    },
    "personal-vs-enterprise-mode": {
        "es": "Las 2 formas de cerrar con llave una red Wi-Fi. Personal usa una sola contraseña para todos. Enterprise da a cada persona su propio inicio de sesión, comprobado por un servidor central. Para una empresa, Enterprise es más seguro y más fácil de gestionar.",
        "fr": "Les 2 façons de verrouiller un réseau Wi-Fi. Personal utilise un seul mot de passe pour tout le monde. Enterprise donne à chaque personne son propre identifiant, vérifié par un serveur central. Pour une entreprise, Enterprise est plus sûr et plus facile à gérer.",
        "it": "I 2 modi per chiudere a chiave una rete Wi-Fi. Personal usa una sola password per tutti. Enterprise dà a ogni persona il suo accesso, controllato da un server centrale. Per un'azienda, Enterprise è più sicuro e più facile da gestire.",
        "de": "Die 2 Arten, ein WLAN-Netz abzuschließen. Personal nutzt ein Passwort für alle. Enterprise gibt jeder Person eine eigene Anmeldung, die ein zentraler Server prüft. Für eine Firma ist Enterprise sicherer und leichter zu verwalten.",
    },
    "pre-shared-key": {
        "es": "La única contraseña compartida de una red en modo Personal. Todos en la red escriben la misma.",
        "fr": "L'unique mot de passe partagé d'un réseau en mode Personal. Tout le monde sur le réseau tape le même.",
        "it": "L'unica password condivisa di una rete in modalità Personal. Tutti sulla rete scrivono la stessa.",
        "de": "Das eine gemeinsame Passwort in einem Netz im Personal-Modus. Alle im Netz tippen dasselbe ein.",
    },
    "sae": {
        "es": "La comprobación de contraseña que usa en casa WPA3, la seguridad Wi-Fi más nueva. Alguien cercano no puede simplemente grabar tu inicio de sesión y llevárselo a casa para probar millones de contraseñas. Aun así necesitas una contraseña decente.",
        "fr": "La vérification du mot de passe qu'utilise le WPA3, la sécurité Wi-Fi plus récente, à la maison. Quelqu'un à proximité ne peut pas simplement enregistrer votre connexion et l'emporter chez lui pour essayer des millions de mots de passe. Il vous faut quand même un mot de passe correct.",
        "it": "Il controllo della password che il WPA3, la sicurezza Wi-Fi più nuova, usa a casa. Qualcuno nelle vicinanze non può semplicemente registrare il tuo accesso e portarselo a casa per fare milioni di tentativi. Ti serve comunque una password decente.",
        "de": "Die Passwortprüfung, die WPA3, die neuere WLAN-Sicherheit, zu Hause nutzt. Jemand in der Nähe kann nicht einfach deine Anmeldung aufzeichnen und sie mit nach Hause nehmen, um Millionen Passwörter durchzuprobieren. Ein ordentliches Passwort brauchst du trotzdem.",
    },
    "802-1x": {
        "es": "El estándar que hay detrás del Wi-Fi Enterprise. Cada dispositivo tiene que demostrar quién es ante un servidor central antes de entrar. Así cada uno tiene su propio inicio de sesión en vez de una contraseña compartida.",
        "fr": "La norme derrière le Wi-Fi Enterprise. Chaque appareil doit prouver qui il est à un serveur central avant d'entrer. Chacun a ainsi son propre identifiant au lieu d'un mot de passe partagé.",
        "it": "Lo standard dietro il Wi-Fi Enterprise. Ogni dispositivo deve dimostrare chi è a un server centrale prima di entrare. Così ognuno ha il suo accesso invece di una password condivisa.",
        "de": "Der Standard hinter Enterprise-WLAN. Jedes Gerät muss einem zentralen Server beweisen, wer es ist, bevor es hineinkommt. So hat jeder seine eigene Anmeldung statt eines gemeinsamen Passworts.",
    },
    "eap": {
        "es": "El conjunto de reglas que lleva el inicio de sesión real en 802.1X (Wi-Fi Enterprise). Hay varios tipos. EAP-TLS usa un certificado en el dispositivo. PEAP usa un nombre de usuario y una contraseña.",
        "fr": "L'ensemble de règles qui transporte la vraie connexion dans 802.1X (le Wi-Fi Enterprise). Il en existe plusieurs types. EAP-TLS utilise un certificat sur l'appareil. PEAP utilise un nom d'utilisateur et un mot de passe.",
        "it": "L'insieme di regole che porta l'accesso vero e proprio in 802.1X (Wi-Fi Enterprise). Ne esistono vari tipi. EAP-TLS usa un certificato sul dispositivo. PEAP usa un nome utente e una password.",
        "de": "Das Regelwerk, das in 802.1X (Enterprise-WLAN) die eigentliche Anmeldung transportiert. Es gibt davon mehrere Arten. EAP-TLS nutzt ein Zertifikat auf dem Gerät. PEAP nutzt Benutzername und Passwort.",
    },
    "radius": {
        "es": "El servidor que comprueba nombres de usuario, contraseñas o certificados en el Wi-Fi Enterprise. Le dice al punto de acceso (el aparato que emite el Wi-Fi) si debe dejar entrar a un dispositivo.",
        "fr": "Le serveur qui vérifie les noms d'utilisateur, mots de passe ou certificats sur le Wi-Fi Enterprise. Il dit au point d'accès (le boîtier qui diffuse le Wi-Fi) s'il doit laisser entrer un appareil.",
        "it": "Il server che controlla nomi utente, password o certificati sul Wi-Fi Enterprise. Dice all'access point (l'apparecchio che trasmette il Wi-Fi) se far entrare un dispositivo.",
        "de": "Der Server, der bei Enterprise-WLAN Benutzernamen, Passwörter oder Zertifikate prüft. Er sagt dem Access Point (der Box, die das WLAN aussendet), ob er ein Gerät hineinlassen soll.",
    },
    "protected-management-frames": {
        "es": "Protección para algunos de los mensajes de control del Wi-Fi. La gran ventaja: una vez que estás conectado de forma segura, un atacante no puede falsificar un mensaje de «estás desconectado» para echarte. WPA3, la seguridad Wi-Fi más nueva, la exige.",
        "fr": "Une protection pour certains messages de contrôle du Wi-Fi. Le gros avantage : une fois que vous êtes connecté de façon sécurisée, un attaquant ne peut pas falsifier un message « vous êtes déconnecté » pour vous éjecter. Le WPA3, la sécurité Wi-Fi plus récente, l'exige.",
        "it": "Protezione per alcuni messaggi di controllo del Wi-Fi. Il grande vantaggio: una volta che sei connesso in modo sicuro, un malintenzionato non può falsificare un messaggio «sei disconnesso» per buttarti fuori. Il WPA3, la sicurezza Wi-Fi più nuova, la richiede.",
        "de": "Schutz für einige der Steuernachrichten im WLAN. Der große Vorteil: Sobald du sicher verbunden bist, kann ein Angreifer keine gefälschte „Du bist getrennt“-Nachricht schicken, um dich hinauszuwerfen. WPA3, die neuere WLAN-Sicherheit, schreibt diesen Schutz vor.",
    },
    "enhanced-open-owe": {
        "es": "Cifrado para redes abiertas sin contraseña, como las de una cafetería. Codifica el enlace de radio entre tu dispositivo y el punto de acceso, para que la gente cercana no pueda leer tu tráfico Wi-Fi. No puede demostrar que el hotspot es el auténtico, así que un hotspot falso aún puede engañarte.",
        "fr": "Du chiffrement pour les réseaux ouverts sans mot de passe, comme dans un café. Il brouille le lien radio entre votre appareil et le point d'accès, pour que les gens autour ne puissent pas lire votre trafic Wi-Fi. Il ne peut pas prouver que le hotspot est le vrai, donc un faux hotspot peut encore vous tromper.",
        "it": "Crittografia per le reti aperte senza password, come quella di un bar. Rende illeggibile il collegamento radio tra il tuo dispositivo e l'access point, così chi è vicino non può leggere il tuo traffico Wi-Fi. Non può dimostrare che l'hotspot sia quello vero, quindi un hotspot falso può ancora ingannarti.",
        "de": "Verschlüsselung für offene Netze ohne Passwort, etwa im Café. Sie verwürfelt die Funkverbindung zwischen deinem Gerät und dem Access Point, damit Leute in der Nähe deinen WLAN-Verkehr nicht lesen können. Sie kann nicht beweisen, dass der Hotspot der echte ist, also kann dich ein falscher Hotspot trotzdem täuschen.",
    },
    "captive-portal": {
        "es": "La página de inicio de sesión o de «aceptar las condiciones» que aparece cuando te conectas a la red de un hotel, un aeropuerto o de invitados. Solo llegas a internet después de pasarla.",
        "fr": "La page de connexion ou d'« acceptation des conditions » qui s'affiche quand vous vous connectez au réseau d'un hôtel, d'un aéroport ou à un réseau invité. Vous n'accédez à internet qu'après l'avoir passée.",
        "it": "La pagina di accesso o di «accetta le condizioni» che compare quando ti colleghi alla rete di un hotel, di un aeroporto o a una rete ospiti. Arrivi a internet solo dopo averla superata.",
        "de": "Die Anmelde- oder „Bedingungen akzeptieren“-Seite, die aufgeht, wenn du einem Hotel-, Flughafen- oder Gastnetz beitrittst. Ins Internet kommst du erst, wenn du an ihr vorbei bist.",
    },
    "mac-randomization": {
        "es": "Tu dispositivo se inventa una identificación de hardware nueva para cada red a la que se conecta. Eso hace difícil seguirte de un sitio a otro por esa identificación.",
        "fr": "Votre appareil invente un nouvel identifiant matériel pour chaque réseau auquel il se connecte. Il devient alors difficile de vous suivre d'un endroit à l'autre grâce à cet identifiant.",
        "it": "Il tuo dispositivo si inventa un nuovo identificativo hardware per ogni rete a cui si collega. Così diventa difficile seguirti da un posto all'altro tramite quell'identificativo.",
        "de": "Dein Gerät denkt sich für jedes Netz, dem es beitritt, eine neue Hardware-Kennung aus. Das macht es schwer, dich über diese Kennung von Ort zu Ort zu verfolgen.",
    },
    "rogue-ap-evil-twin": {
        "es": "Un punto de acceso (un aparato que emite Wi-Fi) que no debería estar ahí. Un AP intruso (rogue AP) es uno que alguien enchufó a tu red sin permiso. Un gemelo malvado (evil twin) copia el nombre de una red real para engañar a los dispositivos y que se conecten a él.",
        "fr": "Un point d'accès (un boîtier qui diffuse du Wi-Fi) qui ne devrait pas être là. Un AP pirate (rogue AP), c'est un point d'accès que quelqu'un a branché sur votre réseau sans permission. Un jumeau maléfique (evil twin) copie le nom d'un vrai réseau pour pousser les appareils à s'y connecter.",
        "it": "Un access point (un apparecchio che trasmette Wi-Fi) che non dovrebbe esserci. Un AP intruso (rogue AP) è uno che qualcuno ha collegato alla tua rete senza permesso. Un gemello malvagio (evil twin) copia il nome di una rete vera per ingannare i dispositivi e farli collegare a lui.",
        "de": "Ein Access Point (eine Box, die WLAN aussendet), der nicht da sein sollte. Ein Rogue AP ist einer, den jemand ohne Erlaubnis an dein Netz angeschlossen hat. Ein Evil Twin kopiert den Namen eines echten Netzes, um Geräte zum Beitritt zu verleiten.",
    },
    "throughput": {
        "es": "La velocidad real que te da una conexión después de todo el trabajo de gestión que necesita cada mensaje. Es lo que notas, y siempre es menor que la velocidad que aparece en los ajustes de Wi-Fi.",
        "fr": "La vitesse réelle que vous donne une connexion, après toute la gestion dont chaque message a besoin. C'est ce que vous ressentez, et c'est toujours moins que la vitesse affichée dans vos réglages Wi-Fi.",
        "it": "La velocità reale che ti dà una connessione dopo tutta la gestione che serve a ogni messaggio. È quello che senti, ed è sempre più bassa della velocità mostrata nelle impostazioni Wi-Fi.",
        "de": "Das echte Tempo, das dir eine Verbindung nach all der Verwaltung gibt, die jede Nachricht braucht. Das ist, was du spürst, und es ist immer niedriger als das Tempo in deinen WLAN-Einstellungen.",
    },
    "latency": {
        "es": "Cuánto tardan los datos en llegar a algún sitio y volver, en milisegundos. Para llamadas, videollamadas y juegos, una latencia baja importa más que la velocidad pura.",
        "fr": "Le temps que mettent les données pour aller quelque part et revenir, en millisecondes. Pour les appels, les appels vidéo et les jeux, une faible latence compte plus que la vitesse brute.",
        "it": "Quanto ci mettono i dati ad arrivare da qualche parte e tornare, in millisecondi. Per chiamate, videochiamate e giochi, una latenza bassa conta più della velocità pura.",
        "de": "Wie lange Daten brauchen, um irgendwo hin und zurück zu kommen, in Millisekunden. Für Anrufe, Videochats und Spiele zählt niedrige Latenz mehr als reines Tempo.",
    },
    "jitter": {
        "es": "Cuánto varía el retraso que tardan los datos en ir y volver. Un retraso constante se siente fluido. Un retraso a saltos hace que las llamadas y el vídeo se entrecorten, aunque el test de velocidad se vea bien.",
        "fr": "À quel point le délai d'aller-retour des données fait des bonds. Un délai stable paraît fluide. Un délai qui saute rend les appels et la vidéo saccadés, même quand le test de vitesse a l'air bon.",
        "it": "Quanto salta su e giù il ritardo dei dati per andare e tornare. Un ritardo costante sembra fluido. Un ritardo a salti rende chiamate e video a scatti, anche quando il test di velocità sembra a posto.",
        "de": "Wie stark die Verzögerung für Daten hin und zurück springt. Gleichmäßige Verzögerung fühlt sich flüssig an. Springende Verzögerung macht Anrufe und Video abgehackt, auch wenn der Speedtest gut aussieht.",
    },
    "packet-loss": {
        "es": "La parte de los datos que nunca llega y hay que volver a enviar. Incluso un 1 por ciento puede estropear llamadas y vídeo.",
        "fr": "La part des données qui n'arrive jamais et doit être renvoyée. Même 1 pour cent peut nuire aux appels et à la vidéo.",
        "it": "La quota di dati che non arriva mai e va inviata di nuovo. Anche l'1 per cento può rovinare chiamate e video.",
        "de": "Der Anteil an Daten, der nie ankommt und neu gesendet werden muss. Schon 1 Prozent kann Anrufen und Video schaden.",
    },
    "bufferbloat": {
        "es": "El retraso que se acumula cuando una conexión a internet ocupada mete demasiados datos en su cola de espera. Lo notas en páginas lentas y llamadas entrecortadas mientras corre una descarga grande, incluso con una tarifa rápida. Los tests más nuevos lo miden y lo llaman «capacidad de respuesta».",
        "fr": "Le retard qui s'accumule quand un lien internet chargé entasse trop de données dans sa file d'attente. Vous le voyez sous forme de pages lentes et d'appels saccadés pendant un gros téléchargement, même avec un abonnement rapide. Les tests plus récents le mesurent et l'appellent « réactivité ».",
        "it": "Il ritardo che si accumula quando un collegamento internet occupato mette troppi dati nella sua coda d'attesa. Lo vedi come pagine lente e chiamate a scatti mentre va un grosso download, anche con un abbonamento veloce. I test più recenti lo misurano e lo chiamano «reattività».",
        "de": "Verzögerung, die sich aufbaut, wenn eine ausgelastete Internetleitung zu viele Daten in ihre Warteschlange stopft. Du merkst es an langsamen Seiten und abgehackten Anrufen, während ein großer Download läuft, sogar mit einem schnellen Tarif. Neuere Tests messen es und nennen es „Reaktionsfähigkeit“.",
    },
    "coverage-hole": {
        "es": "Un punto donde la señal Wi-Fi es demasiado débil, o no existe, para poder usarla. Es uno de los hallazgos más comunes en un estudio y una de las quejas más comunes.",
        "fr": "Un endroit où le signal Wi-Fi est trop faible, ou absent, pour être utilisé. C'est l'une des découvertes les plus courantes lors d'une étude et l'une des plaintes les plus courantes.",
        "it": "Un punto dove il segnale Wi-Fi è troppo debole, o manca, per poterlo usare. È una delle scoperte più comuni in un sopralluogo e una delle lamentele più comuni.",
        "de": "Eine Stelle, an der das WLAN-Signal zu schwach ist oder ganz fehlt, um es zu nutzen. Das ist einer der häufigsten Befunde bei einer Messung und eine der häufigsten Beschwerden.",
    },
    # ── Wireless Glossary additions (Felix, 2026-09-28) ─────────────────────
    # 30 non-Wi-Fi wireless terms in 4 new categories (Cellular, Short-Range
    # Radio, Location & Satellite, Home Internet), English from the gated
    # myPKA Deliverables/2026-09-28-glossary-gate/nonwifi_v3.json that Keith
    # approved. Same rules as above: plain words, Wi-Fi kept in ES/FR/IT, WLAN
    # for the technology in DE, technical names (LTE, mmWave, LC3, Auracast,
    # border router, ONT, DOCSIS) untranslated, digits kept, both units kept.
    # e911 corrected 2026-09-28 after the gate: "from GPS, nearby Wi-Fi and cell
    # towers" (FCC fact sheet DOC-410028A1, 6 March 2025: device-based hybrid
    # location, GPS plus crowd-sourced Wi-Fi, is used on about 80% of wireless
    # 911 calls).
    "sim": {
        "es": "La pequeña tarjeta con chip que le dice a la compañía telefónica a qué cuenta pertenece un teléfono. Si pasas la SIM a otro teléfono, tu número se va con ella.",
        "fr": "La petite carte à puce qui indique à l'opérateur à quel compte appartient un téléphone. Mettez la SIM dans un autre téléphone et votre numéro la suit.",
        "it": "La piccola scheda con chip che dice all'operatore telefonico a quale account appartiene un telefono. Sposta la SIM su un altro telefono e il tuo numero va con lei.",
        "de": "Die kleine Chipkarte, die dem Mobilfunkanbieter sagt, zu welchem Konto ein Handy gehört. Steckst du die SIM in ein anderes Handy, geht deine Nummer mit.",
    },
    "esim": {
        "es": "Un chip de cuenta de la compañía telefónica integrado en el teléfono, en lugar de una tarjeta que se saca. Añades un plan escaneando un código QR o desde la app del operador. Un teléfono puede guardar varios planes, algo práctico cuando viajas.",
        "fr": "Une puce de compte d'opérateur intégrée au téléphone, au lieu d'une carte qu'on retire. Vous ajoutez un forfait en scannant un code QR ou dans l'appli de l'opérateur. Un téléphone peut contenir plusieurs forfaits, ce qui est pratique en voyage.",
        "it": "Un chip dell'account dell'operatore integrato nel telefono, invece di una scheda da estrarre. Aggiungi un piano inquadrando un codice QR o dall'app dell'operatore. Un telefono può contenere più piani, cosa comoda quando viaggi.",
        "de": "Ein Konto-Chip des Mobilfunkanbieters, der fest im Handy verbaut ist, statt einer Karte zum Herausnehmen. Einen Tarif fügst du hinzu, indem du einen QR-Code scannst oder die App des Anbieters nutzt. Ein Handy kann mehrere Tarife speichern, was auf Reisen praktisch ist.",
    },
    "lte": {
        "es": "El estándar celular 4G que la mayoría de los teléfonos todavía usan buena parte del tiempo. Lleva tus datos y, en la mayoría de las redes actuales, también tus llamadas de voz.",
        "fr": "La norme cellulaire 4G que la plupart des téléphones utilisent encore une bonne partie du temps. Elle transporte vos données et, sur la plupart des réseaux aujourd'hui, vos appels vocaux aussi.",
        "it": "Lo standard cellulare 4G che la maggior parte dei telefoni usa ancora buona parte del tempo. Porta i tuoi dati e, oggi sulla maggior parte delle reti, anche le tue chiamate vocali.",
        "de": "Der 4G-Mobilfunkstandard, den die meisten Handys noch einen Großteil der Zeit nutzen. Er trägt deine Daten und in den meisten Netzen heute auch deine Sprachanrufe.",
    },
    "5g": {
        "es": "La quinta generación del servicio celular. Funciona en bandas bajas, medias y altas. El 5G de banda baja llega lejos, pero puede parecer un buen 4G. La banda media es el punto ideal en muchas ciudades: mucho más rápida y con un alcance razonable. El 5G de banda alta, a menudo llamado mmWave, es el más rápido, pero su señal no llega lejos y las paredes la detienen.",
        "fr": "La cinquième génération du service cellulaire. Elle fonctionne sur des bandes basses, moyennes et hautes. La 5G en bande basse porte loin, mais peut ressembler à une bonne 4G. La bande moyenne est le bon compromis dans beaucoup de villes : bien plus rapide, avec une portée correcte. La 5G en bande haute, souvent appelée mmWave, est la plus rapide, mais son signal ne va pas loin et les murs l'arrêtent.",
        "it": "La quinta generazione del servizio cellulare. Funziona su bande basse, medie e alte. Il 5G in banda bassa arriva lontano, ma può sembrare un buon 4G. La banda media è il punto giusto in molte città: molto più veloce, con una portata discreta. Il 5G in banda alta, spesso chiamato mmWave, è il più veloce, ma il suo segnale non arriva lontano e i muri lo fermano.",
        "de": "Die fünfte Generation des Mobilfunks. Sie läuft auf niedrigen, mittleren und hohen Bändern. 5G im niedrigen Band reicht weit, kann sich aber wie gutes 4G anfühlen. Das mittlere Band ist in vielen Städten der beste Kompromiss: viel schneller, mit ordentlicher Reichweite. 5G im hohen Band, oft mmWave genannt, ist am schnellsten, aber sein Signal reicht nicht weit und Wände halten es auf.",
    },
    "cell-booster": {
        "es": "Un equipo que capta una señal celular débil con una antena exterior, la hace más fuerte y la vuelve a emitir dentro. Necesita algo de señal fuera para funcionar. En EE. UU. tiene que ser un modelo aprobado por la FCC y hay que registrarlo con el operador.",
        "fr": "Un kit qui capte un signal cellulaire faible avec une antenne dehors, le renforce et le réémet à l'intérieur. Il lui faut un peu de signal dehors pour fonctionner. Aux États-Unis, ce doit être un modèle approuvé par la FCC, et vous devez le déclarer à votre opérateur.",
        "it": "Un kit che capta un segnale cellulare debole con un'antenna esterna, lo rende più forte e lo ritrasmette all'interno. Ha bisogno di un po' di segnale all'esterno per funzionare. Negli Stati Uniti deve essere un modello approvato dalla FCC, e va registrato presso il proprio operatore.",
        "de": "Ein Set, das ein schwaches Mobilfunksignal mit einer Außenantenne auffängt, verstärkt und drinnen wieder aussendet. Es braucht draußen etwas Signal, mit dem es arbeiten kann. In den USA muss es ein von der FCC zugelassenes Modell sein, und du meldest es bei deinem Anbieter an.",
    },
    "data-roaming": {
        "es": "Usar la red de otra compañía telefónica cuando estás lejos de la tuya, casi siempre en otro país. Puede salir muy caro. Revisa tu plan antes de aterrizar.",
        "fr": "Utiliser le réseau d'un autre opérateur quand vous êtes loin du vôtre, le plus souvent dans un autre pays. Cela peut coûter cher. Vérifiez votre forfait avant d'atterrir.",
        "it": "Usare la rete di un altro operatore telefonico quando sei lontano dalla tua, di solito in un altro paese. Può costare molto. Controlla il tuo piano prima di atterrare.",
        "de": "Das Netz eines anderen Mobilfunkanbieters nutzen, wenn du nicht im eigenen bist, meistens im Ausland. Das kann teuer werden. Prüfe deinen Tarif, bevor du landest.",
    },
    "e911": {
        "es": "El sistema 911 para teléfonos. En una llamada celular, tu operador envía al centro de emergencias tu número y su mejor estimación de tu ubicación, a partir del GPS, del Wi-Fi cercano y de las torres celulares. Esa estimación es peor en interiores. En una llamada por Wi-Fi, puede depender de la dirección de emergencia que guardaste con tu operador. Mantén esa dirección al día y di siempre primero dónde estás.",
        "fr": "Le système 911 pour les téléphones. Lors d'un appel cellulaire, votre opérateur envoie au centre d'urgence votre numéro et sa meilleure estimation de votre position, à partir du GPS, du Wi-Fi à proximité et des antennes-relais. Cette estimation est moins bonne à l'intérieur. Lors d'un appel Wi-Fi, il peut s'appuyer sur l'adresse d'urgence que vous avez enregistrée auprès de votre opérateur. Gardez cette adresse à jour, et dites toujours d'abord où vous êtes.",
        "it": "Il sistema 911 per i telefoni. In una chiamata cellulare, il tuo operatore invia al centro di emergenza il tuo numero e la sua stima migliore della tua posizione, dal GPS, dal Wi-Fi vicino e dalle torri cellulari. Quella stima è meno precisa al chiuso. In una chiamata Wi-Fi, può basarsi sull'indirizzo di emergenza che hai registrato presso il tuo operatore. Tieni aggiornato quell'indirizzo e di' sempre prima dove ti trovi.",
        "de": "Das 911-System für Handys. Bei einem Mobilfunkanruf schickt dein Anbieter der Notrufzentrale deine Nummer und seine beste Schätzung deines Standorts, aus GPS, WLAN in der Nähe und Mobilfunkmasten. Drinnen ist diese Schätzung schlechter. Bei einem WLAN-Anruf stützt es sich unter Umständen auf die Notfalladresse, die du bei deinem Anbieter hinterlegt hast. Halte diese Adresse aktuell, und sag immer zuerst, wo du bist.",
    },
    "wi-fi-calling": {
        "es": "Hacer llamadas y enviar mensajes de texto normales a través de una red Wi-Fi en lugar de la red celular. Ayuda mucho donde la señal celular es débil y el Wi-Fi es bueno. Tu número y la app de teléfono siguen siendo los mismos.",
        "fr": "Passer des appels et envoyer des SMS normaux via un réseau Wi-Fi au lieu du réseau cellulaire. C'est très utile là où le signal cellulaire est faible et le Wi-Fi est bon. Votre numéro et votre appli d'appels restent les mêmes.",
        "it": "Fare normali chiamate e inviare SMS attraverso una rete Wi-Fi invece della rete cellulare. È di grande aiuto dove il segnale cellulare è debole e il Wi-Fi è buono. Il tuo numero e l'app del telefono restano gli stessi.",
        "de": "Normale Telefonate und SMS über ein WLAN statt über das Mobilfunknetz. Das hilft sehr, wo das Mobilfunksignal schwach und das WLAN gut ist. Deine Nummer und deine Telefon-App bleiben gleich.",
    },
    "personal-hotspot": {
        "es": "Compartir los datos celulares de tu teléfono con un portátil o una tableta. La mayoría lo hace convirtiendo el teléfono en una pequeña red Wi-Fi, y algunos teléfonos también pueden compartirlos por cable USB o Bluetooth. Usa tu plan de datos, y algunos planes limitan o ralentizan los datos compartidos.",
        "fr": "Partager les données cellulaires de votre téléphone avec un ordinateur portable ou une tablette. La plupart des gens le font en transformant le téléphone en petit réseau Wi-Fi, et certains téléphones peuvent aussi partager par câble USB ou en Bluetooth. Cela utilise votre forfait, et certains forfaits limitent ou ralentissent les données partagées.",
        "it": "Condividere i dati cellulari del telefono con un portatile o un tablet. Quasi tutti lo fanno trasformando il telefono in una piccola rete Wi-Fi, e alcuni telefoni possono condividere anche via cavo USB o Bluetooth. Usa il tuo piano dati, e alcuni piani limitano o rallentano i dati condivisi.",
        "de": "Die Mobilfunkdaten deines Handys mit einem Laptop oder Tablet teilen. Meistens macht das Handy dafür ein kleines WLAN auf, und manche Handys können auch per USB-Kabel oder Bluetooth teilen. Das geht von deinem Datenvolumen ab, und manche Tarife begrenzen oder drosseln Hotspot-Daten.",
    },
    "bluetooth": {
        "es": "Radio de corto alcance para conectar aparatos entre sí: auriculares, altavoces, relojes, teclados y coches. Usa la misma banda de 2,4 GHz que el Wi-Fi. La mayoría de los auriculares y teclados funcionan a lo ancho de una habitación, unos 10 m (33 pies). Algunos equipos Bluetooth llegan mucho más lejos. Los cuerpos y las paredes reducen el alcance rápidamente.",
        "fr": "Radio à courte portée pour relier des gadgets entre eux : écouteurs, enceintes, montres, claviers et voitures. Elle utilise la même bande 2,4 GHz que le Wi-Fi. La plupart des écouteurs et claviers fonctionnent d'un bout à l'autre d'une pièce, environ 10 m (33 pieds). Certains appareils Bluetooth portent beaucoup plus loin. Les corps et les murs réduisent vite la portée.",
        "it": "Radio a corto raggio per collegare dispositivi tra loro: auricolari, altoparlanti, orologi, tastiere e auto. Usa la stessa banda a 2,4 GHz del Wi-Fi. La maggior parte di auricolari e tastiere funziona da una parte all'altra di una stanza, circa 10 m (33 piedi). Alcuni apparecchi Bluetooth arrivano molto più lontano. Corpi e muri riducono in fretta la portata.",
        "de": "Funk mit kurzer Reichweite, um Geräte miteinander zu verbinden: Ohrhörer, Lautsprecher, Uhren, Tastaturen und Autos. Er nutzt dasselbe 2,4-GHz-Band wie WLAN. Die meisten Ohrhörer und Tastaturen funktionieren quer durch einen Raum, etwa 10 m (33 Fuß). Manche Bluetooth-Geräte reichen viel weiter. Körper und Wände verkürzen die Reichweite schnell.",
    },
    "bluetooth-le": {
        "es": "Un tipo de Bluetooth de bajo consumo para aparatos pequeños que funcionan meses o años con una pila de botón, como localizadores de objetos, sensores y pulseras de actividad. Envía pequeños datos de vez en cuando.",
        "fr": "Une forme de Bluetooth à basse consommation pour les petits gadgets qui tiennent des mois ou des années sur une pile bouton, comme les traceurs d'objets, les capteurs et les bracelets d'activité. Il envoie de petits bouts de données de temps en temps.",
        "it": "Un tipo di Bluetooth a basso consumo per piccoli dispositivi che funzionano per mesi o anni con una batteria a bottone, come localizzatori di oggetti, sensori e braccialetti fitness. Invia piccole quantità di dati ogni tanto.",
        "de": "Eine stromsparende Art von Bluetooth für kleine Geräte, die Monate oder Jahre mit einer Knopfzelle laufen, etwa Tracker für Gegenstände, Sensoren und Fitnessarmbänder. Es sendet ab und zu kleine Datenmengen.",
    },
    "le-audio": {
        "es": "La forma más nueva en que Bluetooth envía sonido. Usa un formato de sonido llamado LC3 que suena bien y usa menos datos. Añade Auracast, que permite que un teléfono o un televisor envíe sonido a muchos auriculares o audífonos a la vez.",
        "fr": "La nouvelle façon dont le Bluetooth transmet le son. Elle utilise un format audio appelé LC3, qui sonne bien tout en utilisant moins de données. Elle ajoute Auracast, qui permet à un téléphone ou une télé d'envoyer le son à beaucoup d'écouteurs ou d'appareils auditifs à la fois.",
        "it": "Il modo più nuovo in cui il Bluetooth trasmette il suono. Usa un formato audio chiamato LC3 che suona bene usando meno dati. Aggiunge Auracast, che permette a un telefono o a una TV di mandare il suono a molti auricolari o apparecchi acustici insieme.",
        "de": "Die neuere Art, wie Bluetooth Ton überträgt. Sie nutzt ein Tonformat namens LC3, das gut klingt und dabei weniger Daten braucht. Dazu kommt Auracast, mit dem ein Handy oder Fernseher Ton an viele Ohrhörer oder Hörgeräte gleichzeitig senden kann.",
    },
    "nfc": {
        "es": "Radio para un toque. Solo funciona cuando dos dispositivos están a pocos centímetros, unos 4 cm (1,5 pulgadas). Es lo que hace funcionar el pago con un toque, los lectores de tarjetas de acceso y el emparejamiento con un toque. El corto alcance ayuda a que sea seguro, pero tu tarjeta o la cartera del teléfono también añaden su propia seguridad.",
        "fr": "Une radio pour un simple contact. Elle ne fonctionne que si deux appareils sont à quelques centimètres, environ 4 cm (1,5 pouce). C'est ce qui fait marcher le paiement sans contact, les lecteurs de badge et l'appairage par contact. La courte portée aide à la sécurité, mais votre carte ou le portefeuille de votre téléphone ajoute aussi sa propre sécurité.",
        "it": "Radio per un tocco. Funziona solo quando due dispositivi sono a pochi centimetri, circa 4 cm (1,5 pollici). È ciò che fa funzionare il pagamento con un tocco, i lettori di badge e l'abbinamento con un tocco. La corta portata aiuta la sicurezza, ma anche la tua carta o il wallet del telefono aggiunge la sua.",
        "de": "Funk für eine Berührung. Er funktioniert nur, wenn zwei Geräte wenige Zentimeter auseinander sind, etwa 4 cm (1,5 Zoll). Damit funktionieren kontaktloses Bezahlen, Ausweisleser und Koppeln per Antippen. Die kurze Reichweite hilft bei der Sicherheit, aber deine Karte oder die Wallet im Handy bringt auch eigene Sicherheit mit.",
    },
    "uwb": {
        "es": "Radio que reparte una señal débil sobre una franja ancha del espectro. Su truco está en medir el tiempo. Puede medir distancias con precisión, a menudo de unos pocos centímetros. Con las antenas adecuadas también puede saber la dirección, que es como algunos localizadores de objetos te llevan directo a tus llaves.",
        "fr": "Une radio qui étale un signal faible sur une large tranche des ondes. Son astuce, c'est la mesure du temps. Elle peut mesurer une distance avec précision, souvent à quelques centimètres près. Avec les bonnes antennes, elle peut aussi trouver la direction : c'est ainsi que certains traceurs d'objets vous guident droit vers vos clés.",
        "it": "Radio che distribuisce un segnale debole su un'ampia fetta dell'etere. Il suo trucco è la misura del tempo. Può misurare le distanze con precisione, spesso a pochi centimetri. Con le antenne giuste può anche capire la direzione, ed è così che alcuni localizzatori di oggetti ti portano dritto alle chiavi.",
        "de": "Funk, der ein schwaches Signal über einen breiten Ausschnitt der Funkwellen verteilt. Sein Trick ist die Zeitmessung. Er kann Entfernungen genau messen, oft auf wenige Zentimeter. Mit den passenden Antennen erkennt er auch die Richtung. So führen dich manche Tracker direkt zu deinen Schlüsseln.",
    },
    "thread": {
        "es": "Una red de bajo consumo para aparatos del hogar inteligente. Los dispositivos enchufados pasan los mensajes de los que van a pilas, así que la cobertura mejora a medida que añades equipos. Un pequeño puente llamado border router la une al resto de la red de tu casa. Suele venir integrado en un altavoz inteligente, un reproductor para la tele o un router Wi-Fi.",
        "fr": "Un réseau basse consommation pour les gadgets de maison connectée. Les appareils branchés sur le secteur relaient les messages pour ceux qui fonctionnent sur pile, donc la couverture s'améliore à mesure que vous ajoutez du matériel. Un petit pont appelé border router le relie au reste de votre réseau domestique. Il est souvent intégré à une enceinte connectée, un boîtier TV ou un routeur Wi-Fi.",
        "it": "Una rete a basso consumo per i dispositivi della casa smart. I dispositivi collegati alla presa passano i messaggi per quelli a batteria, quindi la copertura migliora man mano che aggiungi apparecchi. Un piccolo ponte chiamato border router la collega al resto della rete di casa. Spesso è integrato in uno smart speaker, un box TV o un router Wi-Fi.",
        "de": "Ein stromsparendes Netz für Smart-Home-Geräte. Geräte am Stromnetz reichen Nachrichten für die batteriebetriebenen weiter, also wird die Abdeckung besser, je mehr Geräte du hinzufügst. Eine kleine Brücke namens Border Router verbindet es mit dem Rest deines Heimnetzes. Sie steckt oft in einem smarten Lautsprecher, einer TV-Box oder einem WLAN-Router.",
    },
    "zigbee": {
        "es": "Una red de bajo consumo más antigua para aparatos del hogar inteligente, común en bombillas, enchufes y sensores. Los dispositivos se pasan los mensajes unos a otros. Necesita su propio hub para llegar a tu teléfono y a internet, y usa la misma banda de 2,4 GHz que el Wi-Fi.",
        "fr": "Un réseau basse consommation plus ancien pour les gadgets de maison connectée, courant dans les ampoules, prises et capteurs. Les appareils se relaient les messages. Il lui faut son propre hub pour atteindre votre téléphone et Internet, et il utilise la même bande 2,4 GHz que le Wi-Fi.",
        "it": "Una rete a basso consumo più vecchia per i dispositivi della casa smart, comune in lampadine, prese e sensori. I dispositivi si passano i messaggi a vicenda. Ha bisogno di un suo hub per arrivare al telefono e a internet, e usa la stessa banda a 2,4 GHz del Wi-Fi.",
        "de": "Ein älteres stromsparendes Netz für Smart-Home-Geräte, verbreitet in Lampen, Steckdosen und Sensoren. Die Geräte reichen Nachrichten füreinander weiter. Es braucht einen eigenen Hub, um dein Handy und das Internet zu erreichen, und es nutzt dasselbe 2,4-GHz-Band wie WLAN.",
    },
    "matter": {
        "es": "Un idioma común para aparatos del hogar inteligente, respaldado por Apple, Google, Amazon, Samsung y muchos otros. Un dispositivo Matter está pensado para funcionar con la app de más de una marca. Funciona sobre Wi-Fi, un cable de red o Thread, una red de bajo consumo para el hogar inteligente. Sigues necesitando un hub o una app Matter, y no todas las apps admiten todos los tipos de dispositivo.",
        "fr": "Un langage commun pour les gadgets de maison connectée, soutenu par Apple, Google, Amazon, Samsung et beaucoup d'autres. Un appareil Matter est conçu pour marcher avec l'appli de plus d'une marque. Il fonctionne en Wi-Fi, par câble réseau ou sur Thread, un réseau basse consommation pour la maison connectée. Il vous faut quand même un hub ou une appli Matter, et toutes les applis ne prennent pas en charge tous les types d'appareils.",
        "it": "Una lingua comune per i dispositivi della casa smart, sostenuta da Apple, Google, Amazon, Samsung e molti altri. Un dispositivo Matter è pensato per funzionare con l'app di più di una marca. Funziona su Wi-Fi, su un cavo di rete o su Thread, una rete a basso consumo per la casa smart. Serve comunque un hub o un'app Matter, e non tutte le app supportano ogni tipo di dispositivo.",
        "de": "Eine gemeinsame Sprache für Smart-Home-Geräte, unterstützt von Apple, Google, Amazon, Samsung und vielen anderen. Ein Matter-Gerät soll mit der App von mehr als einer Marke funktionieren. Es läuft über WLAN, ein Netzwerkkabel oder Thread, ein stromsparendes Smart-Home-Netz. Du brauchst trotzdem einen Matter-Hub oder eine Matter-App, und nicht jede App unterstützt jede Geräteart.",
    },
    "gps": {
        "es": "El sistema de satélites de EE. UU. que le dice a tu dispositivo dónde está. Tu dispositivo escucha señales de tiempo de al menos 4 satélites y calcula su posición según cuánto tardó en llegar cada señal. Solo escucha. Nunca envía nada de vuelta.",
        "fr": "Le système de satellites américain qui indique à votre appareil où il se trouve. Votre appareil écoute des signaux horaires d'au moins 4 satellites et calcule sa position d'après le temps mis par chaque signal pour arriver. Il ne fait qu'écouter. Il n'envoie jamais rien en retour.",
        "it": "Il sistema di satelliti degli Stati Uniti che dice al tuo dispositivo dove si trova. Il dispositivo ascolta segnali orari da almeno 4 satelliti e calcola la sua posizione da quanto ha impiegato ogni segnale ad arrivare. Ascolta soltanto. Non invia mai niente indietro.",
        "de": "Das US-Satellitensystem, das deinem Gerät sagt, wo es ist. Dein Gerät hört Zeitsignale von mindestens 4 Satelliten und berechnet seine Position daraus, wie lange jedes Signal unterwegs war. Es hört nur zu. Es sendet nie etwas zurück.",
    },
    "gnss": {
        "es": "El nombre general de los sistemas de localización por satélite. GPS es el de EE. UU. Europa tiene Galileo, Rusia tiene GLONASS y China tiene BeiDou. La mayoría de los teléfonos escuchan varios a la vez, lo que da una posición más rápida y mejor.",
        "fr": "Le nom général des systèmes de localisation par satellite. Le GPS est celui des États-Unis. L'Europe exploite Galileo, la Russie GLONASS et la Chine BeiDou. La plupart des téléphones en écoutent plusieurs à la fois, ce qui donne une position plus rapide et meilleure.",
        "it": "Il nome generale dei sistemi di localizzazione satellitare. GPS è quello degli Stati Uniti. L'Europa gestisce Galileo, la Russia GLONASS e la Cina BeiDou. La maggior parte dei telefoni ne ascolta diversi insieme, e così ottiene una posizione più rapida e migliore.",
        "de": "Der Oberbegriff für Satelliten-Ortungssysteme. GPS ist das der USA. Europa betreibt Galileo, Russland GLONASS und China BeiDou. Die meisten Handys hören mehrere gleichzeitig, was eine schnellere, bessere Positionsbestimmung ergibt.",
    },
    "leo-satellite": {
        "es": "Un satélite que vuela bajo, a entre unos cientos y 2.000 km de altura, y da la vuelta a la Tierra en unos 90 minutos. Estar cerca significa poco retardo, así que las videollamadas funcionan. Cada uno cruza el cielo en unos pocos minutos, así que un servicio necesita toda una flota. Los servicios de banda ancha como Starlink usan miles.",
        "fr": "Un satellite qui vole bas, entre quelques centaines et 2 000 km d'altitude, et fait le tour de la Terre en environ 90 minutes. Être proche veut dire peu de délai, donc les appels vidéo fonctionnent. Chacun traverse le ciel en quelques minutes, donc un service a besoin de toute une flotte. Les services haut débit comme Starlink en utilisent des milliers.",
        "it": "Un satellite che vola basso, tra qualche centinaio e 2.000 km di quota, e fa il giro della Terra in circa 90 minuti. Stare vicino vuol dire poco ritardo, quindi le videochiamate funzionano. Ognuno attraversa il cielo in pochi minuti, quindi a un servizio serve un'intera flotta. I servizi a banda larga come Starlink ne usano migliaia.",
        "de": "Ein Satellit, der niedrig fliegt, einige hundert bis 2.000 km hoch, und die Erde in etwa 90 Minuten umrundet. Die Nähe bedeutet wenig Verzögerung, also funktionieren Videoanrufe. Jeder zieht in wenigen Minuten über den Himmel, also braucht ein Dienst eine ganze Flotte. Breitbanddienste wie Starlink nutzen Tausende.",
    },
    "geostationary-satellite": {
        "es": "Un satélite a unos 35.786 km de altura, donde una vuelta a la Tierra dura exactamente un día. Desde el suelo parece quieto en el cielo, y uno solo puede cubrir cerca de un tercio del planeta. El largo viaje de ida y vuelta añade cerca de medio segundo de retardo, que se nota en las llamadas.",
        "fr": "Un satellite à environ 35 786 km d'altitude, là où un tour de la Terre prend exactement un jour. Depuis le sol, il semble immobile dans le ciel, et un seul peut couvrir environ un tiers de la planète. Le long aller-retour ajoute environ une demi-seconde de délai, qu'on remarque pendant les appels.",
        "it": "Un satellite a circa 35.786 km di quota, dove un giro della Terra dura esattamente un giorno. Da terra sembra fermo nel cielo, e uno solo può coprire circa un terzo del pianeta. Il lungo viaggio di andata e ritorno aggiunge circa mezzo secondo di ritardo, che si nota nelle chiamate.",
        "de": "Ein Satellit in etwa 35.786 km Höhe, wo eine Runde um die Erde genau einen Tag dauert. Vom Boden aus scheint er still am Himmel zu stehen, und einer kann etwa ein Drittel der Erde abdecken. Der lange Weg hinauf und zurück bringt etwa eine halbe Sekunde Verzögerung, die man bei Anrufen merkt.",
    },
    "modem": {
        "es": "La caja que conecta tu casa con tu proveedor de internet. En cable o DSL es un módem de verdad. En fibra, la primera caja suele ser una ONT, que convierte la luz en una señal de red normal. En el internet celular para el hogar, el módem va dentro de la caja del proveedor. Muchos proveedores ponen el módem, un router y un punto de acceso Wi-Fi en una sola caja.",
        "fr": "Le boîtier qui relie votre maison à votre fournisseur d'accès à Internet. Sur le câble ou le DSL, c'est un vrai modem. Sur la fibre, le premier boîtier est généralement un ONT, qui transforme la lumière en signal réseau normal. Avec l'Internet cellulaire à domicile, le modem est à l'intérieur du boîtier du fournisseur. Beaucoup de fournisseurs mettent le modem, un routeur et un point d'accès Wi-Fi dans un seul boîtier.",
        "it": "La scatola che collega la tua casa al fornitore di internet. Su cavo o DSL è un vero modem. Sulla fibra, la prima scatola di solito è un ONT, che trasforma la luce in un normale segnale di rete. Con l'internet di casa via rete cellulare, il modem sta dentro la scatola del fornitore. Molti fornitori mettono il modem, un router e un access point Wi-Fi in una sola scatola.",
        "de": "Die Box, die dein Zuhause mit deinem Internetanbieter verbindet. Bei Kabel oder DSL ist sie ein echtes Modem. Bei Glasfaser ist die erste Box meist ein ONT, das das Licht in ein normales Netzwerksignal umwandelt. Bei Mobilfunk-Internet für zu Hause steckt das Modem in der Box des Anbieters. Viele Anbieter packen das Modem, einen Router und einen WLAN-Access-Point in eine Box.",
    },
    "router": {
        "es": "La caja que une dos redes y pasa el tráfico entre ellas. En casa se sitúa entre tu línea de internet y tu red doméstica, y reparte direcciones a tus dispositivos. Un router no es un punto de acceso. Muchas cajas domésticas hacen los dos trabajos, y de ahí viene la confusión.",
        "fr": "Le boîtier qui relie deux réseaux et fait passer le trafic entre eux. À la maison, il se place entre votre ligne Internet et votre réseau domestique, et il distribue des adresses à vos appareils. Un routeur n'est pas un point d'accès. Beaucoup de boîtiers domestiques font les deux, d'où la confusion.",
        "it": "La scatola che unisce due reti e passa il traffico tra loro. In casa sta tra la tua linea internet e la tua rete domestica, e assegna gli indirizzi ai tuoi dispositivi. Un router non è un access point. Molte scatole di casa fanno entrambe le cose, ed è da qui che nasce la confusione.",
        "de": "Die Box, die zwei Netze verbindet und den Verkehr zwischen ihnen weiterreicht. Zu Hause sitzt sie zwischen deinem Internetanschluss und deinem Heimnetz und verteilt Adressen an deine Geräte. Ein Router ist kein Access Point. Viele Heimgeräte machen beides, und daher kommt die Verwechslung.",
    },
    "ip-address": {
        "es": "La dirección que usa un dispositivo en una red, como 192.168.1.20. Tu red doméstica le da a cada dispositivo una privada. Tu proveedor de internet suele darle a tu casa una sola dirección pública que comparte toda la casa.",
        "fr": "L'adresse qu'un appareil utilise sur un réseau, comme 192.168.1.20. Votre réseau domestique donne à chaque appareil une adresse privée. Votre fournisseur d'accès donne en général à votre foyer une seule adresse publique que toute la maison partage.",
        "it": "L'indirizzo che un dispositivo usa su una rete, come 192.168.1.20. La rete di casa dà a ogni dispositivo un indirizzo privato. Il fornitore di internet di solito dà alla tua casa un solo indirizzo pubblico, condiviso da tutta la casa.",
        "de": "Die Adresse, die ein Gerät in einem Netz nutzt, etwa 192.168.1.20. Dein Heimnetz gibt jedem Gerät eine private. Dein Internetanbieter gibt deinem Zuhause meist eine öffentliche Adresse, die sich das ganze Haus teilt.",
    },
    "dsl": {
        "es": "Internet por la antigua línea telefónica de cobre. Cuanto más lejos estás del equipo de la compañía telefónica, más lento va. Muchas compañías telefónicas lo están apagando y pasando a la gente a la fibra.",
        "fr": "Internet par la vieille ligne téléphonique en cuivre. Plus vous êtes loin de l'équipement de l'opérateur, plus c'est lent. Beaucoup d'opérateurs l'arrêtent et font passer leurs clients à la fibre.",
        "it": "Internet sulla vecchia linea telefonica in rame. Più sei lontano dagli apparati della compagnia telefonica, più va lento. Molte compagnie telefoniche lo stanno spegnendo e passano le persone alla fibra.",
        "de": "Internet über die alte Telefonleitung aus Kupfer. Je weiter du von der Technik der Telefongesellschaft entfernt bist, desto langsamer wird es. Viele Telefongesellschaften schalten es ab und bringen die Leute auf Glasfaser.",
    },
    "cable-internet": {
        "es": "Internet por el mismo cable coaxial que trae la televisión por cable. Las descargas pueden ser rápidas. Las subidas suelen ser mucho más lentas, y los vecinos comparten la línea, así que puede ir más lento por la noche.",
        "fr": "Internet par le même câble coaxial que la télévision par câble. Les téléchargements peuvent être rapides. Les envois sont en général bien plus lents, et les voisins partagent la ligne, donc ça peut ralentir le soir.",
        "it": "Internet sullo stesso cavo coassiale che porta la TV via cavo. I download possono essere veloci. Gli upload di solito sono molto più lenti, e i vicini condividono la linea, quindi la sera può rallentare.",
        "de": "Internet über dasselbe Koaxialkabel, das das Kabelfernsehen bringt. Downloads können schnell sein. Uploads sind meist viel langsamer, und Nachbarn teilen sich die Leitung, also kann es abends langsamer werden.",
    },
    "fiber-internet": {
        "es": "Internet por finos hilos de vidrio que llevan luz. Es el internet doméstico más rápido y estable, y la subida suele ser tan rápida como la bajada. Una cajita en la pared, llamada ONT, convierte la luz en una señal de red normal.",
        "fr": "Internet par de fins brins de verre qui transportent de la lumière. C'est l'accès à domicile le plus rapide et le plus stable, et l'envoi est souvent aussi rapide que le téléchargement. Un petit boîtier au mur, appelé ONT, transforme la lumière en signal réseau normal.",
        "it": "Internet su sottili fili di vetro che portano luce. È l'internet di casa più veloce e stabile, e spesso l'upload è veloce quanto il download. Una scatoletta sul muro, chiamata ONT, trasforma la luce in un normale segnale di rete.",
        "de": "Internet über dünne Glasfasern, die Licht tragen. Es ist das schnellste und stabilste Internet für zu Hause, und der Upload ist oft so schnell wie der Download. Eine kleine Box an der Wand, ONT genannt, wandelt das Licht in ein normales Netzwerksignal um.",
    },
    "fixed-wireless-access": {
        "es": "Internet para el hogar que llega por un enlace de radio en lugar de por cable, desde una torre de telefonía celular (como el internet 5G para el hogar) o desde una antena en una torre cercana. Una caja junto a una ventana lo capta y lo comparte con tu casa. La velocidad depende de tu señal hasta la torre.",
        "fr": "Un accès Internet à domicile qui arrive par une liaison radio au lieu d'un fil, depuis une antenne-relais cellulaire (comme l'Internet 5G à domicile) ou une antenne sur un pylône voisin. Un boîtier près d'une fenêtre le capte et le partage avec la maison. Le débit dépend de votre signal vers l'antenne.",
        "it": "Internet di casa che arriva tramite un collegamento radio invece che su un filo, da una torre cellulare (come l'internet 5G per la casa) o da un'antenna su una torre vicina. Una scatola vicino a una finestra lo capta e lo condivide con la casa. La velocità dipende dal segnale verso la torre.",
        "de": "Internet für zu Hause, das über eine Funkstrecke statt über ein Kabel ankommt, von einem Mobilfunkmast (wie 5G-Internet für zu Hause) oder einer Antenne auf einem Mast in der Nähe. Eine Box am Fenster empfängt es und teilt es mit dem ganzen Haus. Das Tempo hängt von deinem Signal zum Mast ab.",
    },
    "vpn": {
        "es": "Un túnel cerrado para tu tráfico de internet, desde tu dispositivo hasta un servidor VPN. El Wi-Fi del hotel, la cafetería y tu proveedor de internet no pueden ver lo que pasa por él. La empresa de VPN sí puede, así que elige una de confianza. Cambia el lugar del que parece venir tu tráfico. No te hace anónimo.",
        "fr": "Un tunnel verrouillé pour votre trafic Internet, de votre appareil jusqu'à un serveur VPN. Le Wi-Fi de l'hôtel, le café et votre fournisseur d'accès ne peuvent pas voir ce qui passe dedans. La société de VPN, elle, le peut, alors choisissez-en une de confiance. Il change l'endroit d'où votre trafic semble venir. Il ne vous rend pas anonyme.",
        "it": "Un tunnel chiuso a chiave per il tuo traffico internet, dal tuo dispositivo a un server VPN. Il Wi-Fi dell'hotel, il bar e il tuo fornitore di internet non possono vedere cosa ci passa dentro. L'azienda della VPN invece sì, quindi scegline una di cui ti fidi. Cambia il luogo da cui il tuo traffico sembra arrivare. Non ti rende anonimo.",
        "de": "Ein verschlossener Tunnel für deinen Internetverkehr, von deinem Gerät zu einem VPN-Server. Das Hotel-WLAN, das Café und dein Internetanbieter können nicht sehen, was hindurchgeht. Der VPN-Anbieter kann es, also wähle einen, dem du vertraust. Es ändert, woher dein Verkehr zu kommen scheint. Es macht dich nicht anonym.",
    },
    "wps": {
        "es": "Un atajo para conectarse a una red Wi-Fi pulsando un botón del router o escribiendo un PIN. El método del PIN es el que hay que evitar. Alguien al alcance de tu Wi-Fi puede adivinar el PIN y recuperar tu contraseña. Desactiva WPS si tu router lo permite.",
        "fr": "Un raccourci pour se connecter à un réseau Wi-Fi en appuyant sur un bouton du routeur ou en tapant un code PIN. C'est la méthode du PIN qu'il faut éviter. Quelqu'un à portée de votre Wi-Fi peut deviner le PIN et récupérer votre mot de passe. Désactivez le WPS si votre routeur le permet.",
        "it": "Una scorciatoia per collegarsi a una rete Wi-Fi premendo un pulsante sul router o digitando un PIN. Il metodo del PIN è quello da evitare. Qualcuno alla portata del tuo Wi-Fi può indovinare il PIN e recuperare la tua password. Disattiva il WPS se il router lo consente.",
        "de": "Eine Abkürzung, um einem WLAN beizutreten, indem du eine Taste am Router drückst oder eine PIN eingibst. Die PIN-Methode solltest du meiden. Jemand in Reichweite deines WLANs kann die PIN erraten und dein Passwort herausfinden. Schalte WPS aus, wenn dein Router das erlaubt.",
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
    data["term_count"] = len(terms)

    ASSET.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"OK: merged {len(LANGS)} translations into {len(terms)} terms.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
