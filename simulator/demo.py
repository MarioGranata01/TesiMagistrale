import argparse
from collections.abc import Callable
from time import perf_counter

from agent.adage_engine import (
    ModelProfile,
    NodeState,
    Requirements,
    Task,
    choose_placement,
)
from agent.task_classifier import Classification, SlmClassifier, classify_with_rules


# Profili sintetici per un batch di video detection.
PROFILES = (
    ModelProfile("edge", "leggero", 160, 60, 900, 0.72, 1.0),
    ModelProfile("cloud", "leggero", 75, 35, 900, 0.72, 2.0),
    ModelProfile("cloud", "accurato", 140, 85, 3200, 0.91, 4.0),
)
NODES = {
    "edge": NodeState("edge", 20, 40, 1600, frozenset({"leggero"})),
    "cloud": NodeState("cloud", 10, 250, 8000, frozenset({"leggero", "accurato"})),
}

# I requisiti di riferimento sono le etichette del replay, invisibili al classificatore.
TRACE = (
    (
        Task("archivio", "Analizza con calma il filmato archiviato.", 10, "edge"),
        Requirements(500, 0.65),
    ),
    (
        Task("diretta", "Segnala in tempo reale il passaggio dei veicoli.", 10, "edge"),
        Requirements(150, 0.65),
    ),
    (
        Task("verifica", "Rileva i veicoli con alta precisione per il report.", 10, "edge"),
        Requirements(500, 0.88),
    ),
    (
        Task("avviso", "Avvisami prima che il veicolo esca dall'inquadratura.", 10, "edge"),
        Requirements(150, 0.65),
    ),
    (
        Task("vincolo-stretto", "Controlla il video.", 10, "edge", Requirements(100, 0.9)),
        Requirements(100, 0.9),
    ),
)


def replay(mode: str, classify: Callable[[Task], Classification]) -> None:
    assigned = on_time = meets_quality = meets_both = 0
    total_cost = total_classification_ms = 0.0
    print(f"\n{mode}")

    for task, expected in TRACE:
        start = perf_counter()
        classification = classify(task)
        classification_ms = (perf_counter() - start) * 1000
        total_classification_ms += classification_ms

        placement = choose_placement(
            task, classification.requirements, PROFILES, NODES, classification_ms,
        )
        request_label = f"{task.name} [{classification.label}, {classification.source}]"
        if placement is None:
            print(f"  {request_label}: rinviato, nessuna coppia fattibile")
            continue

        latency_ms = classification_ms + placement.completion_ms
        profile = placement.profile
        deadline_met = latency_ms <= expected.deadline_ms
        quality_met = profile.quality >= expected.minimum_quality
        assigned += 1
        on_time += deadline_met
        meets_quality += quality_met
        meets_both += deadline_met and quality_met
        total_cost += profile.cost
        print(
            f"  {request_label}: {profile.model} su {profile.node}, "
            f"{latency_ms:.1f} ms, qualità {profile.quality:.2f}, costo {profile.cost:.1f}"
        )

    count = len(TRACE)
    average_cost = f"{total_cost / assigned:.2f}" if assigned else "n/d"
    print(
        f"  Assegnati {assigned}/{count} · in tempo {on_time}/{count} · "
        f"qualità rispettata {meets_quality}/{count} · entrambi {meets_both}/{count}"
    )
    print(
        f"  Costo totale {total_cost:.2f} · per assegnato {average_cost} · "
        f"classificazione media {total_classification_ms / count:.2f} ms"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Replay locale di A²DAGE")
    parser.add_argument("--slm-model", help="Nome del modello esposto dal server locale")
    parser.add_argument("--slm-url", default="http://127.0.0.1:8080", help="URL del server SLM")
    args = parser.parse_args()

    replay("Baseline con telemetria", lambda task: Classification("standard", "default"))
    replay("Classificazione a regole", classify_with_rules)
    if args.slm_model:
        slm = SlmClassifier(args.slm_model, args.slm_url)
        replay("Classificazione con SLM", slm.classify)


if __name__ == "__main__":
    main()
