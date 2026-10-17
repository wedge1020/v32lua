# --- Base Project Makefile ---
TARGET = v32lua
ARCH = $(shell uname -m)

# On Windows (MSYS2/MinGW) src/Makefile writes bin/v32lua.exe.
ifeq ($(OS),Windows_NT)
EXE = .exe
endif
BIN = bin/$(TARGET)$(EXE)

# ----------------------------------------------------------------------------
# Install locations for `make sysinstall` (the same layout `cmake --install`
# uses with its default prefix; see CMakeLists.txt). Override any of them on
# the command line, e.g. `make sysinstall PREFIX=/opt/v32lua`; DESTDIR=
# stages the whole tree somewhere else (for packaging).
#
# The --#include library directory (LIBDIR) defaults to inc/config.h's
# V32LUA_INCLUDE_PATH, the directory the compiler is built to search. With
# a PREFIX other than /usr/local it goes to $(PREFIX)/Vircon32/v32tools/
# include/v32lua instead: the compiler also looks there, relative to
# itself ($(PREFIX)/bin/v32lua), so it is found without a rebuild.
# ----------------------------------------------------------------------------
INCPATH := $(shell sed -n 's/^[[:space:]]*\#[[:space:]]*define[[:space:]]*V32LUA_INCLUDE_PATH[[:space:]]*"\(.*\)".*/\1/p' inc/config.h)

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
MANDIR  ?= $(PREFIX)/share/man/man1
ifeq ($(PREFIX),/usr/local)
LIBDIR  ?= $(INCPATH)
else
LIBDIR  ?= $(PREFIX)/Vircon32/v32tools/include/v32lua
endif
# The documents go beside the library: .../v32tools/docs/v32lua
DOCDIR  ?= $(if $(filter %/include/v32lua,$(LIBDIR)),$(patsubst %/include/v32lua,%/docs/v32lua,$(LIBDIR)),$(LIBDIR)/docs)

# ----------------------------------------------------------------------------
# Language of the installed documentation: DEST_LANG=en, es or fr, e.g.
#     sudo make sysinstall DEST_LANG=es
# installs the Spanish README, API and USAGE guides under their plain names
# (README.md, doc/API.md, doc/USAGE.md, with the links between them
# adjusted to match) next to the documents that exist only in English
# (doc/PICO8.md, doc/TIC80.md, ...), and the Spanish manual page
# (man/v32lua.es.1, if there is one; otherwise the English page) as
# v32lua.1, so `man v32lua` shows it. DEST_LANG=en installs only the
# English documents. Left unset (or DEST_LANG=all), every language is
# installed under its own name, with the English manual page. The CMake
# build takes the same setting (-DDEST_LANG=es).
# ----------------------------------------------------------------------------
LANGS     = en es fr
DOC_LANG := $(if $(strip $(DEST_LANG)),$(strip $(DEST_LANG)),all)
ifeq ($(filter $(DOC_LANG),all $(LANGS)),)
$(error DEST_LANG must be one of: $(LANGS) or all (got '$(DEST_LANG)'))
endif
ifneq ($(wildcard man/v32lua.$(DOC_LANG).1),)
MANPAGE   = man/v32lua.$(DOC_LANG).1
else
MANPAGE   = man/v32lua.1
endif

# The documents: the English ones (README.md, doc/*.md) and the
# translations (README.es.md, doc/API.fr.md, ...).
EN_DOCS  := README.md $(filter-out %.es.md %.fr.md,$(sort $(wildcard doc/*.md)))
TR_DOCS  := $(filter %.es.md %.fr.md,$(sort $(wildcard README.*.md doc/*.md)))

# ----------------------------------------------------------------------------
# The compiler version: inc/v32lua.h's VERSION is the single source.
# `v32lua --version` reads it from the header directly, and so do the CMake
# build (at configure time) and the release workflow. `make version` shows
# it and stamps it into the other files that print it: the man page's .TH
# header (every language present) and doc/DEBUGGING.md's footer.
#
# To release, either edit the #define in inc/v32lua.h and run
#     make version
# or let make do the edit too:
#     make version VERSION=20261015-release
# Then rebuild (`make`) so the binary picks up the new string.
#
# Portable between GNU and BSD/macOS tools: no `sed -i` (BSD sed takes the
# script as the backup suffix), no \t in brackets, no `date +%-d`.
# ----------------------------------------------------------------------------
VERSION := $(shell sed -n 's/^\#define[[:space:]]*VERSION[[:space:]]*"\(.*\)".*/\1/p' inc/v32lua.h)
MONTH   := $(shell LC_ALL=C date +"%B %Y")
TODAY   := $(shell LC_ALL=C date +"%B %d, %Y" | sed 's/ 0\([0-9]\),/ \1,/')
# Translated man pages get the month in their own language (spelled out
# here rather than through locales, which may not be installed).
MONTH_N := $(shell date +%m | sed 's/^0//')
YEAR    := $(shell date +%Y)
MONTHS_ES = enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre
MONTHS_FR = janvier février mars avril mai juin juillet août septembre octobre novembre décembre
MONTH_es := $(word $(MONTH_N),$(MONTHS_ES)) de $(YEAR)
MONTH_fr := $(word $(MONTH_N),$(MONTHS_FR)) $(YEAR)

# Recurse into src/ every time: its own Makefile decides what (if anything)
# is out of date. As a file-based target with no rule, bin/v32lua was
# considered up to date whenever an old binary existed, so `make install`
# or `make sysinstall` could install a stale one -- and with no binary at
# all they failed with "No rule to make target".
.PHONY: all clean distclean install uninstall sysinstall sysuninstall \
        tests asmcheck v32check demos version monofiles context put archive \
        bin/$(TARGET)

# Default target: build the main compiler executable (bin/v32lua)
all: bin/$(TARGET)

bin/$(TARGET):
	$(MAKE) -C src

# Clean both the build files in src/ and the generated assembly in testing/
clean:
	rm -f err.txt put/* *.zip
	$(MAKE) -C src clean
	$(MAKE) -C testing clean
	$(MAKE) -C demos clean

# clean, plus the out-of-tree CMake build directory (see CMakeLists.txt)
distclean: clean
	rm -rf build

install: bin/$(TARGET)
	@if [ -d ~/bin/bin.$(ARCH) ]; then \
		echo "Installing $(TARGET) to ~/bin/bin.$(ARCH)/"; \
		install -m 755 $(BIN) ~/bin/bin.$(ARCH)/$(TARGET)$(EXE); \
	elif [ -d ~/bin ]; then \
		echo "Installing $(TARGET) to ~/bin/"; \
		install -m 755 $(BIN) ~/bin/$(TARGET)$(EXE); \
	else \
		echo "Skipping: neither ~/bin/bin.$(ARCH) nor ~/bin exist"; \
	fi

uninstall:
	rm -f ~/bin/bin.$(ARCH)/$(TARGET)$(EXE) ~/bin/$(TARGET)$(EXE)

# System-wide install: the binary to $(BINDIR), the manual page (in
# DEST_LANG's language, gzipped as v32lua.1.gz) to $(MANDIR), the --#include library (lib/*.lua) to
# $(LIBDIR) and the documents (READMEs and doc/, in DEST_LANG's language)
# to $(DOCDIR) -- the layout `cmake --install` uses with its default prefix
# (see CMakeLists.txt). May need sudo. `make sysuninstall` removes it again.
sysinstall: bin/$(TARGET)
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR) $(DESTDIR)$(LIBDIR) $(DESTDIR)$(DOCDIR)/doc
	install -m 755 $(BIN) $(DESTDIR)$(BINDIR)/$(TARGET)$(EXE)
	rm -f $(DESTDIR)$(MANDIR)/v32lua.1 $(DESTDIR)$(MANDIR)/v32lua.1.gz
	gzip -9cn $(MANPAGE) > $(DESTDIR)$(MANDIR)/v32lua.1.gz
	chmod 644 $(DESTDIR)$(MANDIR)/v32lua.1.gz
	install -m 644 lib/*.lua $(DESTDIR)$(LIBDIR)/
	@set -e; for f in $(EN_DOCS); do \
	    src=$$f; \
	    case "$(DOC_LANG)" in es|fr) \
	        tr=$${f%.md}.$(DOC_LANG).md; \
	        if [ -f "$$tr" ]; then src=$$tr; fi ;; \
	    esac; \
	    sed 's/\.$(DOC_LANG)\.md/.md/g' "$$src" > "$(DESTDIR)$(DOCDIR)/$$f"; \
	    chmod 644 "$(DESTDIR)$(DOCDIR)/$$f"; \
	done
ifeq ($(DOC_LANG),all)
	@set -e; for f in $(TR_DOCS); do \
	    install -m 644 "$$f" "$(DESTDIR)$(DOCDIR)/$$f"; \
	done
endif
	@echo "Installed $(TARGET) to $(BINDIR), its manual page ($(MANPAGE), gzipped) to $(MANDIR),"
	@echo "the --#include library to $(LIBDIR)"
	@echo "and the documents ($(DOC_LANG)) to $(DOCDIR)"
ifneq ($(filter es fr,$(DOC_LANG)),)
ifeq ($(MANPAGE),man/v32lua.1)
	@echo "(there is no man/v32lua.$(DOC_LANG).1 yet: the manual page is the English one)"
endif
endif
ifneq ($(LIBDIR),$(INCPATH))
	@echo "(v32lua finds that library relative to its own location; the built-in"
	@echo " default is $(INCPATH))"
endif

# Removes exactly what sysinstall can put down (in any language), then each
# directory that leaves empty -- v32tools/include, v32tools/docs, v32tools
# and Vircon32 only if nothing else (v32opt, v32c++, the DevTools) is in
# them.
up = $(patsubst %/,%,$(dir $(1)))
sysuninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)$(EXE) $(DESTDIR)$(MANDIR)/v32lua.1 $(DESTDIR)$(MANDIR)/v32lua.1.gz
	rm -f $(addprefix $(DESTDIR)$(LIBDIR)/,$(notdir $(wildcard lib/*.lua)))
	rm -f $(addprefix $(DESTDIR)$(DOCDIR)/,$(EN_DOCS) $(TR_DOCS))
	-@for d in $(DOCDIR)/doc $(DOCDIR) $(call up,$(DOCDIR)) \
	          $(LIBDIR) $(call up,$(LIBDIR)) $(call up,$(call up,$(LIBDIR))) \
	          $(call up,$(call up,$(call up,$(LIBDIR)))); do \
	    rmdir "$(DESTDIR)$$d" 2>/dev/null && echo "removed empty $(DESTDIR)$$d"; \
	done; true

# Show the version (from inc/v32lua.h) and stamp it into the man pages (in
# every language present) and doc/DEBUGGING.md. With VERSION=... on the
# command line, write that into inc/v32lua.h first. Run before a release,
# then rebuild.
#
# The version is checked first: it goes into sed replacements and a C
# string, so an empty value (VERSION= on the command line, or a header the
# parse above couldn't read) or one with characters such as / & " \ or
# spaces would otherwise be written out as-is and corrupt those files.
version:
	@v='$(VERSION)'; \
	if [ -z "$$v" ]; then \
	    echo "make version: no version (inc/v32lua.h must have a '#define VERSION \"...\"' line," >&2; \
	    echo "              or pass one: make version VERSION=YYYYMMDD-status)" >&2; exit 1; \
	fi; \
	case "$$v" in *[!A-Za-z0-9._+-]*) \
	    echo "make version: '$$v' is not a valid version (letters, digits and . _ + - only)" >&2; exit 1 ;; \
	esac; \
	case "$$v" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;; \
	*) echo "make version: warning: '$$v' does not start with a YYYYMMDD date (CMake's numeric version will be 0.0.0)" >&2 ;; \
	esac
	@sed 's/^\(#define[[:space:]]*VERSION[[:space:]]*\)"[^"]*"/\1"$(VERSION)"/' inc/v32lua.h > inc/v32lua.h.tmp && \
	    if cmp -s inc/v32lua.h inc/v32lua.h.tmp; then rm -f inc/v32lua.h.tmp; \
	    else mv inc/v32lua.h.tmp inc/v32lua.h; fi
	@echo "v32lua $(VERSION)"
	@sed 's/^\.TH V32LUA 1 "[^"]*" "v32lua [^"]*"/.TH V32LUA 1 "$(MONTH)" "v32lua $(VERSION)"/' man/v32lua.1 > man/v32lua.1.tmp && mv man/v32lua.1.tmp man/v32lua.1
	@for l in es fr; do \
	    [ -f man/v32lua.$$l.1 ] || continue; \
	    case $$l in es) m='$(MONTH_es)' ;; fr) m='$(MONTH_fr)' ;; esac; \
	    sed "s/^\.TH V32LUA 1 \"[^\"]*\" \"v32lua [^\"]*\"/.TH V32LUA 1 \"$$m\" \"v32lua $(VERSION)\"/" man/v32lua.$$l.1 > man/v32lua.$$l.1.tmp && \
	        mv man/v32lua.$$l.1.tmp man/v32lua.$$l.1; \
	done
	@sed 's/Last updated: [^|]*| Compiler: [^*]*\*/Last updated: $(TODAY) | Compiler: $(VERSION)*/' doc/DEBUGGING.md > doc/DEBUGGING.md.tmp && mv doc/DEBUGGING.md.tmp doc/DEBUGGING.md
	@grep -H '^#define[[:space:]]*VERSION' inc/v32lua.h
	@grep -H "^\.TH" man/v32lua*.1
	@grep -H "Compiler: " doc/DEBUGGING.md

# Run the test compilations.
# We explicitly depend on the compiler binary (bin/v32lua) being built first!
tests: bin/$(TARGET)
	@$(MAKE) -C testing tests

# Check assembler outputs
# We explicitly depend on the compiler binary (bin/v32lua) being built first!
asmcheck: bin/$(TARGET)
	$(MAKE) -C testing vbin

v32check: bin/$(TARGET)
	$(MAKE) -C testing v32

demos: bin/$(TARGET)
	$(MAKE) -C demos

monofiles:
	@rm -f put/*
	scripts/monolithic_code.sh
	@cp src/lexer.l put/lexer.l.txt
	@cp src/parser.y put/parser.y.txt
	#$(MAKE) -C testing monofiles

context:
	$(MAKE) -C src context

put: context
	@rm -f put/*
	#@cp src/parser.output put/parser.output.txt
	@cp inc/*.h src/*.c src/*.txt src/runtime/*.txt README.md doc/*.md put/
	@for file in src/intrinsics/*.c; do \
		cp "$$file" "put/intrinsics_$$(basename "$$file")"; \
	done
	@for file in src/node/*.c; do \
		cp "$$file" "put/node_$$(basename "$$file")"; \
	done

archive: clean
	zip -r v32lua-project.zip CMakeLists.txt cmake demos doc inc lib Makefile man README.* scripts src tests v32 testing tools .github
