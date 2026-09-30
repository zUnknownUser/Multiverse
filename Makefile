.DEFAULT_GOAL := help
IOS_DIR := apps/ios
FIREBASE_FUNCTIONS_DIR := backend/firebase/functions
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: help ios-generate ios-open ios-build ios-test backend-install backend-test test

help:
	@echo "ios-generate     Gera o projeto Xcode em apps/ios"
	@echo "ios-open         Gera e abre o projeto no Xcode"
	@echo "ios-build        Compila o app para simulador"
	@echo "ios-test         Executa os testes iOS"
	@echo "backend-install  Instala as dependências das funções Firebase"
	@echo "backend-test     Compila e testa as funções localmente"
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

test: ios-test backend-test
