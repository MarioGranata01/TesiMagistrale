from dataclasses import dataclass
from math import inf


@dataclass(frozen=True)
class Requirements:
    deadline_ms: float = inf
    minimum_quality: float = 0.0

    def with_limits(self, limits: "Requirements") -> "Requirements":
        return Requirements(
            min(self.deadline_ms, limits.deadline_ms),
            max(self.minimum_quality, limits.minimum_quality),
        )


@dataclass(frozen=True)
class Task:
    name: str
    description: str
    input_mb: float
    source_node: str
    limits: Requirements = Requirements()


@dataclass(frozen=True)
class ModelProfile:
    node: str
    model: str
    inference_ms: float
    startup_ms: float
    memory_mb: int
    quality: float
    cost: float


@dataclass(frozen=True)
class NodeState:
    name: str
    queue_ms: float
    input_rate_mb_s: float
    memory_budget_mb: int
    loaded_models: frozenset[str] = frozenset()
    available: bool = True


@dataclass(frozen=True)
class Placement:
    profile: ModelProfile
    queue_ms: float
    transfer_ms: float
    startup_ms: float

    @property
    def completion_ms(self) -> float:
        return self.queue_ms + self.transfer_ms + self.startup_ms + self.profile.inference_ms


def choose_placement(
    task: Task,
    requirements: Requirements,
    profiles: tuple[ModelProfile, ...],
    nodes: dict[str, NodeState],
    classification_ms: float = 0.0,
) -> Placement | None:
    requirements = requirements.with_limits(task.limits)
    candidates = []
    for profile in profiles:
        node = nodes.get(profile.node)
        if node is None or not node.available or profile.memory_mb > node.memory_budget_mb:
            continue
        if profile.quality < requirements.minimum_quality:
            continue

        transfer_ms = 0.0
        if task.input_mb > 0 and task.source_node != node.name:
            if node.input_rate_mb_s <= 0:
                continue
            transfer_ms = 1000 * task.input_mb / node.input_rate_mb_s

        startup_ms = 0.0 if profile.model in node.loaded_models else profile.startup_ms
        placement = Placement(profile, node.queue_ms, transfer_ms, startup_ms)
        if classification_ms + placement.completion_ms <= requirements.deadline_ms:
            candidates.append(placement)

    return min(
        candidates,
        key=lambda candidate: (
            candidate.profile.cost,
            candidate.completion_ms,
            candidate.profile.node,
            candidate.profile.model,
        ),
        default=None,
    )
