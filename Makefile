.DEFAULT_GOAL := help
IOS_DIR := apps/ios
FIREBASE_FUNCTIONS_DIR := backend/firebase/functions
API_DIR := backend/api
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: help ios-generate ios-open ios-build ios-test backend-install backend-test api-install api-dev api-build api-test api-check test

help:
	@echo "ios-generate     Gera o projeto Xcode em apps/ios"
	@echo "ios-open         Gera e abre o projeto no Xcode"
	@echo "ios-build        Compila o app para simulador"
	@echo "ios-test         Executa os testes iOS"
	@echo "backend-install  Instala as dependências das funções Firebase"
	@echo "backend-test     Compila e testa as funções localmente"
	@echo "api-install      Instala as dependências da API NestJS"
	@echo "api-dev          Inicia a API com recarga automática"
	@echo "api-build        Compila a API"
	@echo "api-test         Executa testes unitários e HTTP da API"
	@echo "api-check        Verifica formatação, lint, tipos, build e testes da API"
	@echo "test             Executa os testes iOS e do backend"

ios-generate:
	cd "$(IOS_DIR)" && xcodegen generate

ios-open: ios-generate
	open "$(IOS_DIR)/Multiverse.xcodeproj"

ios-build: ios-generate
	cd "$(IOS_DIR)" && xcodebuild -project Multiverse.xcodeproj -scheme Multiverse -destination "$(IOS_DESTINATION)" -derivedDataPath DerivedData build

ios-test: ios-generate
	cd "$(IOS_DIR)" && xcodebuild -project Multiverse.xcodeproj -scheme Multiverse -destination "$(IOS_DESTINATION)" -derivedDataPath DerivedData test

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
	npm --prefix "$(API_DIR)" test
	npm --prefix "$(API_DIR)" run test:e2e

api-check:
	npm --prefix "$(API_DIR)" run check

test: ios-test backend-test api-test
