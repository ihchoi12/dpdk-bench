# Common PCM Library Makefile

REPO_ROOT := $(shell cd ../.. && pwd)
PCM_ROOT := $(REPO_ROOT)/pcm
PCM_BUILD := $(PCM_ROOT)/build

# Compiler settings
CXX := g++
AR := ar
CXXFLAGS := -O3 -g -std=c++17 -fPIC -Wall -Wextra
INCLUDES := -I$(PCM_ROOT)/src -I.
LDFLAGS := -L$(PCM_BUILD)/src -lPCM_STATIC -lpthread

# Output
LIB_NAME := libcommon_pcm.a
LIB_SHARED := libcommon_pcm.so

# Source files
SOURCES := common_pcm_wrapper.cpp
OBJECTS := $(SOURCES:.cpp=.o)

# Targets
.PHONY: all clean test install

all: $(LIB_NAME)

$(LIB_NAME): $(OBJECTS)
	@echo "Creating static library $@"
	$(AR) rcs $@ $^

$(LIB_SHARED): $(OBJECTS)
	@echo "Creating shared library $@"
	$(CXX) -shared -o $@ $^ $(LDFLAGS)

%.o: %.cpp common_pcm_wrapper.h pcm_config.h
	@echo "Compiling $<"
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(LIB_NAME) $(LIB_SHARED)

install: $(LIB_NAME)
	@echo "Installing to $(REPO_ROOT)/lib"
	mkdir -p $(REPO_ROOT)/lib
	cp $(LIB_NAME) $(REPO_ROOT)/lib/

test:
	@echo "Testing common PCM library..."
	@echo "TODO: Add unit tests"

.PHONY: help
help:
	@echo "Common PCM Library Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build static and shared libraries (default)"
	@echo "  clean    - Remove built files"
	@echo "  install  - Install library to $(REPO_ROOT)/lib"
	@echo "  test     - Run unit tests (TODO)"
	@echo "  help     - Show this help message"
