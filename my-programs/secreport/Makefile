# make install  ->  builds secreport and copies it to ~/.local/bin
BIN = $(HOME)/.local/bin

secreport: secreport.c
	cc -O2 -Wall -Wextra -o $@ $<

install: secreport
	install -m 0755 secreport $(BIN)/secreport
	chmod 0755 checks.sh

clean:
	rm -f secreport

.PHONY: install clean
