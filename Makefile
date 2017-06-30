MIX = mix
CFLAGS = -g -O3

ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
CFLAGS += -I$(ERLANG_PATH) `pkg-config --cflags proj`
LDFLAGS += `pkg-config --libs proj`
LDFLAGS += `pkg-config --libs gdal`

ifneq ($(OS),Windows_NT)
	CFLAGS += -fPIC -I/usr/include/gdal

	ifeq ($(shell uname),Darwin)
		LDFLAGS += -dynamiclib -undefined dynamic_lookup
	endif
endif

.PHONY: all reproject clean

all: reproject

mix.lock: mix.exs
	mix deps.get

reproject: mix.lock priv/reproject.so
	mix compile

priv/reproject.so: src/reproject.c
	mkdir -p priv
	$(CC) $(CFLAGS) -shared -o $@ src/reproject.c $(LDFLAGS)

clean:
	$(MIX) clean
	$(RM) -rf priv
