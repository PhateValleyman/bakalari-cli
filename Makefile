BINARY_NAME=bakalari
CMD_PATH=./cmd/bakalari

.PHONY: all build clean cross-compile

all: build

build:
	go build -o $(BINARY_NAME) $(CMD_PATH)

clean:
	rm -f $(BINARY_NAME)
	rm -rf bin/

cross-compile:
	mkdir -p bin
	# Linux amd64
	GOOS=linux GOARCH=amd64 go build -o bin/$(BINARY_NAME)-linux-amd64 $(CMD_PATH)
	# Android/Linux arm64 (Termux)
	GOOS=linux GOARCH=arm64 go build -o bin/$(BINARY_NAME)-linux-arm64 $(CMD_PATH)
	# Linux mipsel (ZyXEL NSA320)
	GOOS=linux GOARCH=mipsle go build -o bin/$(BINARY_NAME)-linux-mipsel $(CMD_PATH)
	# Windows amd64
	GOOS=windows GOARCH=amd64 go build -o bin/$(BINARY_NAME)-windows-amd64.exe $(CMD_PATH)
