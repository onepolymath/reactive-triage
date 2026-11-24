.PHONY: test fmt policy demo-frames

test: fmt
	forge test --no-dynamic-test-linking
	python3 -m unittest discover -s services/policy/tests

fmt:
	forge fmt

policy:
	python3 -m services.policy.agent --dry-run --cases demo/cases.json

demo-frames:
	python3 demo/generate_frames.py
