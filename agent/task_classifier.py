import json
from dataclasses import dataclass
from http.client import HTTPException
from urllib.request import Request, urlopen

from agent.adage_engine import Requirements, Task


TASK_CLASSES = {
    "standard": Requirements(deadline_ms=500, minimum_quality=0.65),
    "tempo_reale": Requirements(deadline_ms=150, minimum_quality=0.65),
    "alta_precisione": Requirements(deadline_ms=500, minimum_quality=0.88),
    "tempo_reale_alta_precisione": Requirements(deadline_ms=150, minimum_quality=0.88),
}


@dataclass(frozen=True)
class Classification:
    label: str
    source: str

    @property
    def requirements(self) -> Requirements:
        return TASK_CLASSES[self.label]


def classify_with_rules(task: Task, source: str = "regole") -> Classification:
    description = task.description.casefold()
    real_time = any(word in description for word in ("tempo reale", "in diretta", "immediato"))
    high_precision = any(word in description for word in ("alta precisione", "alta accuratezza"))

    if real_time and high_precision:
        return Classification("tempo_reale_alta_precisione", source)
    if real_time:
        return Classification("tempo_reale", source)
    if high_precision:
        return Classification("alta_precisione", source)
    return Classification("standard", source)


@dataclass(frozen=True)
class SlmClassifier:
    model: str
    base_url: str = "http://127.0.0.1:8080"
    timeout_s: float = 1.0

    def classify(self, task: Task) -> Classification:
        request = Request(
            self.base_url.rstrip("/") + "/v1/chat/completions",
            data=json.dumps({
                "model": self.model,
                "temperature": 0,
                "max_tokens": 32,
                "chat_template_kwargs": {"enable_thinking": False},
                "messages": [
                    {
                        "role": "system",
                        "content": (
                            "Classifica una richiesta di rilevamento oggetti in video. "
                            "Usa tempo_reale per una risposta immediata, alta_precisione "
                            "quando il riconoscimento deve essere molto accurato, "
                            "tempo_reale_alta_precisione se servono entrambe e standard "
                            "negli altri casi. Rispondi con una sola etichetta."
                        ),
                    },
                    {"role": "user", "content": task.description},
                ],
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )

        try:
            timeout = min(self.timeout_s, task.limits.deadline_ms / 1000)
            with urlopen(request, timeout=timeout) as response:
                result = json.load(response)
            label = result["choices"][0]["message"]["content"]
            if isinstance(label, str) and label.strip() in TASK_CLASSES:
                return Classification(label.strip(), "SLM")
        except (OSError, HTTPException, ValueError, TypeError, KeyError, IndexError):
            pass

        return classify_with_rules(task, source="fallback a regole")
