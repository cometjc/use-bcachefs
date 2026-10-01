from pathlib import Path

from evals.elsuite.basic.match import Match
from evals.completion_fns.openai import OpenAIChatCompletionFn


class RouterChat(OpenAIChatCompletionFn):
    def __init__(self, registry=None, **kwargs):
        super().__init__(**kwargs)

    def __call__(self, prompt, **kwargs):
        # eval may fall back to reasoning models accepting only temperature 1.
        kwargs["temperature"] = 1
        return super().__call__(prompt, **kwargs)


class BootLayoutMatch(Match):
    def eval_sample(self, sample, rng):
        root = Path(__file__).resolve().parents[2]
        reference = "\n".join(
            (root / path).read_text()
            for path in ("SKILL.md", "references/boot-layout.md")
        )
        sample = dict(sample)
        sample["input"] = [
            {"role": "system", "content": reference + "\nFor this test respond with exactly the requested English option letter, no explanation."},
            *sample["input"],
        ]
        return super().eval_sample(sample, rng)
