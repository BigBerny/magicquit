PROJECT := MagicQuit.xcodeproj
SCHEME := MagicQuit
CONFIGURATION ?= Debug
DERIVED_DATA := build
DESTINATION := platform=macOS

# O projeto referencia o team do autor original; use assinatura ad hoc para build local.
# Passe DEVELOPMENT_TEAM=<seu-team-id> se tiver certificado Apple Development.
DEVELOPMENT_TEAM ?=
CODE_SIGN_IDENTITY ?= -

SIGNING_FLAGS := DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) CODE_SIGN_IDENTITY=$(CODE_SIGN_IDENTITY)

XCODEBUILD := xcodebuild \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-configuration $(CONFIGURATION) \
	-derivedDataPath $(DERIVED_DATA) \
	$(SIGNING_FLAGS)

APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/MagicQuit.app

.PHONY: help build test test-all test-unit test-ui run clean resolve-packages

help: ## Mostra os alvos disponíveis
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

resolve-packages: ## Resolve dependências Swift Package Manager
	$(XCODEBUILD) -resolvePackageDependencies

build: resolve-packages ## Compila o app MagicQuit
	$(XCODEBUILD) build

test: build ## Executa testes unitários e de UI (exceto launch/screenshots)
	$(XCODEBUILD) test -destination '$(DESTINATION)' \
		-skip-testing:MagicQuitUITests/MagicQuitUITestsLaunchTests

test-all: build ## Executa todos os testes, incluindo launch/screenshots
	$(XCODEBUILD) test -destination '$(DESTINATION)'

test-unit: build ## Executa apenas os testes unitários
	$(XCODEBUILD) test -destination '$(DESTINATION)' -only-testing:MagicQuitTests

test-ui: build ## Executa testes de UI (exceto launch/screenshots)
	$(XCODEBUILD) test -destination '$(DESTINATION)' \
		-only-testing:MagicQuitUITests/MagicQuitUITests

run: build ## Abre o app compilado
	open "$(APP_PATH)"

clean: ## Remove artefatos de build
	rm -rf $(DERIVED_DATA)
