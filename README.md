# A²DAGE

Tesi magistrale sullo scheduling di task AI nell'Edge–Cloud Continuum. L'obiettivo è scegliere insieme **il modello di inferenza e la macchina** in base a ciò che la richiesta deve ottenere, alla latenza disponibile e al costo di esecuzione.

## Prima bozza

La demo riproduce richieste di rilevamento di oggetti in video, uno stadio della pipeline prevista dal piano operativo *Agentic-ADAGE*. Usa due modelli, un nodo edge e un nodo cloud con profili sintetici.

1. Il classificatore traduce la descrizione della richiesta in una classe con deadline e soglia minima di qualità. Se la richiesta specifica limiti più stringenti, valgono quelli.
2. Lo scheduler stima il tempo di completamento sommando attesa in coda, trasferimento dell'input, caricamento del modello e inferenza. A questi tempi si aggiunge la durata della classificazione per verificare la deadline.
3. Tra le coppie modello–nodo compatibili che rispettano memoria, qualità e deadline, sceglie quella a costo minore. A parità di costo preferisce la più rapida. Se nessuna è fattibile, il replay registra la richiesta come rinviata.

## Avvio

Con Python 3.10 o successivo, dalla radice del repository, anche nel terminale di Visual Studio:

```powershell
python -B -m simulator.demo
```

Il comando usa solo la libreria standard. Esegue sulla stessa traccia due configurazioni:

- **Telemetria**. Lo scheduler usa lo stato dei nodi, i profili e requisiti predefiniti uguali per tutte le richieste.
- **Regole**. I requisiti predefiniti dipendono dalla classe ricavata da parole chiave nella descrizione.

Entrambe rispettano i limiti espliciti della richiesta. La demo confronta gli esiti con requisiti di riferimento assegnati a ogni richiesta nel replay. Stampa assegnazioni, deadline e soglie di qualità rispettate, costo stimato per assegnazione e tempo medio della classificazione. La qualità è un punteggio di esempio tra 0 e 1. Il costo è espresso in unità convenzionali e i tempi di esecuzione sono simulati. Il tempo di classificazione è misurato durante il replay.

Nella traccia inclusa, le regole mandano al cloud la richiesta in diretta e scelgono il modello accurato per il report. L'avviso «prima che il veicolo esca dall'inquadratura» mostra un limite delle parole chiave: viene classificato come standard e supera la deadline di riferimento.

### Classificazione con un piccolo modello linguistico

Per aggiungere la terza configurazione, avvia un server locale compatibile con `/v1/chat/completions`, per esempio `llama-server` di llama.cpp, con un modello istruito per seguire prompt. Passa il nome esposto dal server:

```powershell
python -B -m simulator.demo --slm-model nome-del-modello --slm-url http://127.0.0.1:8080
```

Il modello riceve la descrizione del task e restituisce una delle quattro classi definite nel codice. Lo scheduler verifica comunque i vincoli numerici. Se il server non risponde o l'etichetta è invalida, il classificatore ripiega sulle regole e lo segnala nell'output. Il tempo trascorso nel tentativo entra nel calcolo della deadline.

## Codice

- [`agent/adage_engine.py`](agent/adage_engine.py) contiene i profili, lo stato dei nodi e la scelta della coppia modello–nodo.
- [`agent/task_classifier.py`](agent/task_classifier.py) contiene le classi di servizio, le regole e il collegamento opzionale allo SLM.
- [`simulator/demo.py`](simulator/demo.py) definisce la traccia e confronta le configurazioni.

## Collegamento con il piano operativo

La scelta deterministica della coppia modello–nodo è un primo passo verso il ciclo rapido previsto dal piano. La classificazione delle richieste in ingresso è l'estensione proposta per la tesi. Nel ciclo cognitivo del piano lo SLM ha un'altra responsabilità: analizza cambiamenti operativi e propone aggiornamenti alle politiche da validare. La riproduzione di ADAGE su WorkflowSim, i DAG, il work giving tra agenti, le repliche e i benchmark su hardware reale appartengono alle fasi successive.

- **ADAGE originale**. La versione Java su WorkflowSim è il riferimento per cammino critico, località dei dati, work giving e replicazione. Il codice della scelta del vicino confronta il carico con il costo di trasferire i dati mancanti. [Preprint](https://scalab.dimes.unical.it/papers/pdf/ADAGE-preprint.pdf) · [Repository](https://github.com/SCAlabUnical/ADAGE) · [WorkGivingSchedulingAlgorithm.java](https://github.com/SCAlabUnical/ADAGE/blob/master/src/org/workflowsim/scheduling/WorkGivingSchedulingAlgorithm.java#L214)
- **Scheduling dei modelli e costi di comunicazione**. Il lavoro sullo scheduling congiunto di agenti e risorse esplicita i vincoli di latenza e qualità. Graph-Aware Scheduling analizza il costo di spostare i dati nella topologia edge–cloud e Maestro considera il costo di avvio di un modello. [Multi-LLM Agentic AI at the Edge](https://arxiv.org/abs/2611.20915) · [Graph-Aware Scheduling](https://www.mdpi.com/1999-5903/18/5/265) · [Maestro](https://arxiv.org/abs/2606.12950)
- **Inferenza su Jetson**. Dynamic Pipeline Scheduling cita NanoLLM come runtime di inferenza. Il piano operativo propone llama.cpp per il primo SLM. [Dynamic Pipeline Scheduling](https://doi.org/10.1049/aie2.70020) · [NanoLLM](https://github.com/dusty-nv/NanoLLM) · [Server llama.cpp](https://github.com/ggml-org/llama.cpp/tree/master/tools/server)
- **Vincoli e contesa**. DARCS esplicita i vincoli di deadline, memoria e affidabilità. MCSched studia la contesa della memoria condivisa su Jetson, da misurare quando classificatore ed executor girano sulla stessa macchina. [DARCS](https://doi.org/10.1016/j.sysarc.2026.104019) · [MCSched](https://doi.org/10.1145/3838177.3841726)
