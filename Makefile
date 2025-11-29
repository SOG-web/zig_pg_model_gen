.PHONY: help generate-models install-generator

help:
	@echo "Available commands:"
	@echo ""
	@echo "🔧 Models:"
	@echo "  make generate-models             - Generate all models from JSON schemas"
	@echo "  make generate-models OUT=<dir>   - Generate models to custom directory"
	@echo "  make install-generator           - Install zig-model-gen globally"
	@echo ""

generate-models:
	@echo "🚀 Generating models from JSON schemas..."
	@if [ -n "$(OUT)" ]; then \
		zig build -Doptimize=ReleaseFast && zig-out/bin/zig-model-gen ./examples/schemas ./$(OUT); \
	else \
		zig build -Doptimize=ReleaseFast && zig-out/bin/zig-model-gen ./examples/schemas ./examples/models/generated; \
	fi
	@echo ""

install-generator:
	@echo "📦 Installing zig-model-gen..."
	@bash install.sh
