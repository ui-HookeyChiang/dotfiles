.PHONY: build check clean

BUILD_DIR := ./dist

build: check
	@mkdir -p $(BUILD_DIR)
	@echo "build: compiling deploy-agent"
	@cp config.yml $(BUILD_DIR)/config.yml
	@echo "build: done"

check:
	@echo "check: running lint"
	@sh ./lint-check.sh config.yml
	@echo "check: passed"

clean:
	@rm -rf $(BUILD_DIR)
