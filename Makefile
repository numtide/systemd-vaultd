DESTDIR ?=
GO ?= go
INSTALL ?= install
SED ?= sed
RM ?= rm
MKDIR_P ?= mkdir -p
PREFIX ?= $(DESTDIR)/usr
SERVICE_DIR ?= $(PREFIX)/lib/systemd/system

all: systemd-vaultd

systemd-vaultd:
	$(GO) build .

$(SERVICE_DIR):
	$(MKDIR_P) "$(SERVICE_DIR)"

install: systemd-vaultd $(SERVICE_DIR)
	$(INSTALL) -m755 -D systemd-vaultd "$(PREFIX)/bin/systemd-vaultd"
	$(SED) -e "s!/usr/bin/systemd/vaultd!$(PREFIX)/bin/systemd-vaultd!" etc/systemd-vaultd.service > "$(SERVICE_DIR)/systemd-vaultd.service"
	$(INSTALL) -m644 -D etc/systemd-vaultd.socket "$(SERVICE_DIR)/systemd-vaultd.socket"

clean:
	$(RM) -rf systemd-vaultd

.PHONY: all clean
