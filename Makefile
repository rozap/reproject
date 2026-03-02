MIX = mix
CFLAGS = -g -O3 -std=c++17


ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
CFLAGS += -I$(ERLANG_PATH)

ifneq ($(OS),Windows_NT)
	CFLAGS += -fPIC

	ifeq ($(shell uname),Darwin)
		LDFLAGS += -dynamiclib -undefined dynamic_lookup
		SYS_LDFLAGS = -lc++ -lm -lz -lsqlite3
	else
		SYS_LDFLAGS = -lstdc++ -lm -ldl -lpthread -lz
	endif
endif

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

ifndef BUNDLED_LIBS_PREFIX
  ifneq ($(wildcard $(MAKEFILE_DIR)prebuilt/lib/libgdal.a),)
    BUNDLED_LIBS_PREFIX := $(MAKEFILE_DIR)prebuilt
  endif
endif

ifdef BUNDLED_LIBS_PREFIX
	CFLAGS += -I$(BUNDLED_LIBS_PREFIX)/include -I$(BUNDLED_LIBS_PREFIX)/include/gdal
	STATIC_LIBS = $(BUNDLED_LIBS_PREFIX)/lib/libgdal.a \
	              $(BUNDLED_LIBS_PREFIX)/lib/libproj.a
	ifneq ($(shell uname),Darwin)
		STATIC_LIBS += $(BUNDLED_LIBS_PREFIX)/lib/libsqlite3.a
	endif
else
	CFLAGS  += $(shell pkg-config --cflags proj gdal)
	LDFLAGS += $(shell pkg-config --libs proj gdal)
endif

.PHONY: all clean

ifdef BUNDLED_LIBS_PREFIX
all: priv/reproject.so priv/proj_data/proj.db
else
all: priv/reproject.so
endif

priv/reproject.so: src/reproject.cc
	mkdir -p priv
	$(CXX) $(CFLAGS) -shared -o $@ src/reproject.cc $(STATIC_LIBS) $(LDFLAGS) $(SYS_LDFLAGS)

priv/proj_data/proj.db:
	mkdir -p priv/proj_data
	cp $(BUNDLED_LIBS_PREFIX)/share/proj/proj.db priv/proj_data/

clean:
	$(MIX) clean
	$(RM) -rf priv
