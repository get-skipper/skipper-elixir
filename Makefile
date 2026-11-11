.PHONY: deps test lint fmt sync docs clean

deps:
	mix deps.get

# ExUnit apps from the umbrella root; ESpec has its own runner.
test:
	mix test
	cd apps/skipper_espec && MIX_ENV=test mix espec

lint:
	mix format --check-formatted
	MIX_ENV=test mix compile --force --warnings-as-errors

fmt:
	mix format

# Dogfooding: run the suites and reconcile the skipper-elixir sheet.
sync:
	SKIPPER_MODE=sync SKIPPER_SHEET_NAME=skipper-elixir $(MAKE) test

clean:
	rm -rf _build deps
