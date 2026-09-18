BINARY_NAME=bakalari
CMD_PATH=./cmd/bakalari

.PHONY: all build clean cross-compile

all: build

build:
	go build -trimpath -x -o $(BINARY_NAME) $(CMD_PATH)

clean:
	rm -f $(BINARY_NAME)
	rm -rf bin/

cross-compile:
	mkdir -p bin
	# Android arm (Tablet Termux)
	GOOS=android GOARCH=arm GOARM=7 go build -trimpath -x -o bin/$(BINARY_NAME)-android-armv7 $(CMD_PATH)
	# Android arm64 (Redmi Termux)
	GOOS=android GOARCH=arm64 go build -trimpath -x-o bin/$(BINARY_NAME)-android-arm64 $(CMD_PATH)
	# Linux marmv5 (ZyXEL NSA320)
	GOOS=linux GOARCH=arm GOARM=5 go build -trimpath -x -o bin/$(BINARY_NAME)-linux-armv5 $(CMD_PATH)
