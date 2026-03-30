# GNUmakefile - Transparent Docker delegation layer
# GNU make reads this before 'Makefile'.
# Inside Docker, 'make -f Makefile' is used to skip this file.
# To run without Docker: make DOCKER=0 <target>

DOCKER_IMAGE    := rvcomp:latest
DOCKER_RUN      := docker run --rm --init -v $(CURDIR):/workspace -e IN_DOCKER=1 $(DOCKER_IMAGE)
DOCKER_RUN_IT   := docker run --rm --init -it -v $(CURDIR):/workspace -e IN_DOCKER=1 $(DOCKER_IMAGE)
DOCKER          ?= 1
DOCKER_MODE     := $(strip $(DOCKER))
DOCKER_ENABLED_VALUES := 1 true yes on

# Targets requiring host tools (Vivado, USB/serial communication)
NATIVE_TARGETS := \
    bit rebit reclockbit \
    load remoteload \
    vivadoclean \
    termnb term config

# Targets running in Docker but requiring interactive terminal
INTERACTIVE_TARGETS := menuconfig cliconfig

.DEFAULT_GOAL := _docker_default
.PHONY: _docker_default

ifeq (1,$(IN_DOCKER))

# Inside Docker container: pass through to Makefile (prevents infinite loop)
_docker_default:
	$(MAKE) -f Makefile

ifneq ($(MAKECMDGOALS),)
.PHONY: $(MAKECMDGOALS)
$(MAKECMDGOALS):
	$(MAKE) -f Makefile $@
endif

else ifneq ($(filter $(DOCKER_ENABLED_VALUES),$(DOCKER_MODE)),)

# Docker enabled
_docker_default:
	$(DOCKER_RUN) make -f Makefile

ifneq ($(MAKECMDGOALS),)
.PHONY: $(MAKECMDGOALS)
$(MAKECMDGOALS):
	$(if $(filter $@,$(NATIVE_TARGETS)),$(MAKE) -f Makefile $@,$(if $(filter $@,$(INTERACTIVE_TARGETS)),$(DOCKER_RUN_IT) make -f Makefile $@,$(DOCKER_RUN) make -f Makefile $@))
endif

else

# Docker disabled: delegate all targets to Makefile on host
_docker_default:
	$(MAKE) -f Makefile

ifneq ($(MAKECMDGOALS),)
.PHONY: $(MAKECMDGOALS)
$(MAKECMDGOALS):
	$(MAKE) -f Makefile $@
endif

endif
