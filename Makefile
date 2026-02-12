MIX = mix
CFLAGS = -g -O3

ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
CFLAGS += -I$(ERLANG_PATH) `pkg-config --cflags proj`
LDFLAGS += `pkg-config --libs proj`
LDFLAGS += `pkg-config --libs gdal`

ifneq ($(OS),Windows_NT)
	CFLAGS += -fPIC `pkg-config --cflags gdal`

	ifeq ($(shell uname),Darwin)
		LDFLAGS += -std=c++11 -dynamiclib -undefined dynamic_lookup
	endif
endif

.PHONY: all clean

all: priv/reproject.so

priv/reproject.so: src/reproject.cc
	mkdir -p priv
	$(CXX) $(CFLAGS) -shared -o $@ src/reproject.cc $(LDFLAGS)

clean:
	$(MIX) clean
	$(RM) -rf priv
