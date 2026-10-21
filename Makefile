.DEFAULT_GOAL := help
IOS_DIR := apps/ios
FIREBASE_FUNCTIONS_DIR := backend/firebase/functions
API_DIR := backend/api
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
IOS_TEST_OPTIONS ?= -parallel-testing-enabled NO MULTIVERSE_API_BASE_URL=http://127.0.0.1:1/api/v1

.PHONY: help environment-check localization-check ios-generate ios-open ios-build ios-test backend-install backend-test api-install api-dev api-build api-test api-check test

help:
	@echo "environment-check Valida configurações de homologação e produção"
	@echo "localization-check Valida traduções PT-BR/EN e placeholders"
	@echo "ios-generate     Gera o projeto Xcode em apps/ios"
	@echo "ios-open         Gera e abre o projeto no Xcode"
	@echo "ios-build        Compila o app para simulador"
	@echo "ios-test         Executa os testes iOS"
	@echo "backend-install  Instala as dependências das funções Firebase"
	@echo "backend-test     Compila e testa as funções localmente"
	@echo "api-install      Instala as dependências da API NestJS"
	@echo "api-dev          Inicia a API com recarga automática"
	@echo "api-build        Compila a API"
	@echo "api-test         Executa testes da API com PostgreSQL descartável (Docker)"
	@echo "api-check        Verifica a API completa com PostgreSQL descartável (Docker)"
	@echo "test             Valida traduções e executa os testes iOS e do backend"

environment-check:
	python3 "$(IOS_DIR)/scripts/test_environment.py"

localization-check:
	python3 "$(IOS_DIR)/scripts/check_localization.py"

ios-generate:
	cd "$(IOS_DIR)" && xcodegen generate

ios-open: ios-generate
	open "$(IOS_DIR)/Multiverse.xcodeproj"

ios-build: ios-generate
	cd "$(IOS_DIR)" && xcodebuild -project Multiverse.xcodeproj -scheme Multiverse -destination "$(IOS_DESTINATION)" -derivedDataPath DerivedData build

ios-test: ios-generate
	cd "$(IOS_DIR)" && xcodebuild -project Multiverse.xcodeproj -scheme Multiverse -destination "$(IOS_DESTINATION)" -derivedDataPath DerivedData $(IOS_TEST_OPTIONS) test

backend-install:
	npm --prefix "$(FIREBASE_FUNCTIONS_DIR)" ci

backend-test:
	npm --prefix "$(FIREBASE_FUNCTIONS_DIR)" test

api-install:
	npm --prefix "$(API_DIR)" ci

api-dev:
	npm --prefix "$(API_DIR)" run start:dev

api-build:
	npm --prefix "$(API_DIR)" run build

api-test:
	npm --prefix "$(API_DIR)" run test:local

api-check:
	npm --prefix "$(API_DIR)" run check:local

test: environment-check localization-check ios-test backend-test api-check
