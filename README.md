# A²DAGE

Tesi magistrale sullo scheduling di task AI nell'Edge–Cloud Continuum. L'obiettivo è scegliere insieme **il modello di inferenza e la macchina** in base a ciò che la richiesta deve ottenere, alla latenza disponibile e al costo di esecuzione.

Lo scheduler è progettato per task AI di tipi diversi. Il nucleo della tesi è la scelta modello–macchina a partire dai requisiti del task e dallo stato delle risorse. Una pipeline video è un caso d'uso facoltativo per valutare il sistema.

Il codice di partenza per l'evoluzione dello scheduler è **ADAGE (2021)**, in Java su WorkflowSim. Il sorgente è importato in [`vendor/ADAGE`](vendor/ADAGE) come sottomodulo Git, fissato a un commit upstream preciso. Le modifiche di A²DAGE si applicano a questa copia durante la build. La demo Python esplora la classificazione e la scelta modello–nodo.

## Compilare ADAGE dal sorgente

Servono Git, Windows PowerShell 5.1 o PowerShell 7 e un JDK 11 o successivo. Dalla radice di A²DAGE, inizializza il sottomodulo e compila:

```powershell
git submodule update --init
$adageSource = (Resolve-Path ./vendor/ADAGE).Path
$adageClasses = ./upstream/build-adage.ps1
$adageClasspath = $adageClasses + [IO.Path]::PathSeparator + (Join-Path $adageSource 'lib/*')
$adageDax = Join-Path $adageSource 'config/dax/Montage_25.xml'
$adageLogs = Join-Path (Split-Path $adageClasses) 'logs/seed-1'
java '-Duser.language=en' '-Duser.country=US' -cp $adageClasspath simulation.Simulation `
    $adageDax --nodes 16 --bw 1000 --sched WORKGIVING --plan RANDOM `
    --wgmode 2 --seed 1 --log $adageLogs
```

[Lo script di build](upstream/build-adage.ps1) lascia pulito il checkout upstream e applica [la patch sul seed](upstream/0001-respect-simulation-seed.patch) nella cartella temporanea di compilazione. La patch rimuove la sovrascrittura del seed e registra nel log il valore effettivo. Per compilare il sorgente upstream con gli stessi strumenti e senza applicare la patch, passa `-Unmodified` allo script.

### Verifica della build

Con OpenJDK Temurin 21.0.12.1, due esecuzioni di Montage 25 con pianificazione `RANDOM` e seed 1 hanno assegnato i task alle stesse VM e ottenuto un makespan di 40,3515 s. Con seed 2 sono cambiate le assegnazioni e il makespan è stato di 28,55 s.

Su Montage 1.000 con `CRITICAL_PATH`, 16 VM e seed 0, le due build da sorgente, con e senza patch, hanno assegnato i task alle stesse VM e ottenuto 630,4825 s. Il JAR distribuito ha ottenuto 631,5665 s. Per confrontare una modifica ad A²DAGE con il suo controllo, usa due build da sorgente con lo stesso JDK e gli stessi argomenti. La sezione WP1 riporta separatamente i risultati del JAR distribuito.

## Demo Python

La traccia di esempio della demo usa richieste di rilevamento di oggetti in video, uno dei workload del piano operativo *Agentic-ADAGE*. Due modelli, un nodo edge e un nodo cloud con profili sintetici permettono di osservare le scelte dello scheduler.

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

## WP1 · Prima esecuzione di ADAGE originale

### Eseguire la baseline da sorgente

Dalla radice del repository, dopo `git submodule update --init`:

```powershell
./upstream/run-wp1-baseline.ps1
```

Il comando compila ADAGE senza patch e avvia Montage 25 e Montage 1.000 con 16 VM, seed `0` e le tre modalità `wgmode` (`-1`, `0`, `2`). Per ogni configurazione verifica gli ID dei task completati nei log, escludendo `Stage-in`. Stampa il percorso dei risultati e salva `run.json` con commit, versioni Java, parametri e SHA-256 dei workflow, `results.csv` con i makespan e i log di WorkflowSim. La cartella viene creata sotto la directory temporanea. Per sceglierne la posizione, passa `-ResultsDirectory`.

### Prova con il JAR distribuito

Il JAR originale ha completato i workflow Montage da 25 e 1.000 task in WorkflowSim. La prova usa il [commit upstream `063fa27`](https://github.com/SCAlabUnical/ADAGE/tree/063fa27d0eb0f90d123f917d7c51fd76eb153476), OpenJDK Temurin 21.0.12.1, 16 VM simulate, `bw=1000` come valore della CLI e la pianificazione `CRITICAL_PATH`.

| `wgmode` | Configurazione | Montage 25 | Montage 1.000 |
| --- | --- | ---: | ---: |
| `-1` | Decision Maker | 28,3305 s | 663,1185 s |
| `0` | Work giving senza repliche | 28,3305 s | 644,7615 s |
| `2` | Work giving con due repliche come limite | 28,3305 s | 631,5665 s |

I valori sono makespan simulati. In ogni esecuzione, gli ID distinti con stato `Success` nella tabella del log coprivano tutti i task del DAX. Il conteggio esclude il job tecnico `Stage-in`. Le due dimensioni e la configurazione a 16 VM servono a verificare la baseline operativa. Il confronto con i risultati del paper richiede di replicarne l'intero disegno sperimentale.

Da PowerShell, in una cartella di lavoro in cui `ADAGE` può essere creato:

```powershell
git clone https://github.com/SCAlabUnical/ADAGE.git
Set-Location ADAGE
git checkout --detach 063fa27d0eb0f90d123f917d7c51fd76eb153476

foreach ($size in 25, 1000) {
    foreach ($mode in -1, 0, 2) {
        java '-Duser.language=en' '-Duser.country=US' -jar simulation.jar `
            "config/dax/Montage_${size}.xml" --nodes 16 --bw 1000 `
            --sched WORKGIVING --plan CRITICAL_PATH --wgmode $mode `
            --seed 0 --log "results/montage-${size}/mode-${mode}"
        if ($LASTEXITCODE -ne 0) { throw "Simulazione fallita per Montage $size, modalità $mode" }
    }
}
```

Lo standard output del JAR riporta `makespan;backupCounter;nonBackupCounter`. Il comando usa una directory di log per ogni configurazione perché i nomi generati dal simulatore omettono `wgmode`. In questa versione `Simulation.main` imposta `simulation.seed` a `0` dopo la lettura degli argomenti. Il comportamento è presente nel sorgente e nel bytecode del JAR, quindi ripetere il comando con seed diversi non produce repliche indipendenti. [Sorgente di Simulation.java](https://github.com/SCAlabUnical/ADAGE/blob/063fa27d0eb0f90d123f917d7c51fd76eb153476/simulation/simulation/Simulation.java#L306-L323)

| File upstream | SHA-256 |
| --- | --- |
| `simulation.jar` | `ba49bcc670eae80361d3c6e52f74ea3529d45d4dee2a1ba14fe0391b40ad8cb4` |
| `config/dax/Montage_25.xml` | `20c52b9e2532972c1e252d92e5338730aaf144b9bb82f6a311abf48daf0de35b` |
| `config/dax/Montage_1000.xml` | `65e8a624a83efa74c034db67077ce6c361523cb49d032f0f2bfd9da406925557` |
