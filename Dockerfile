FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
ARG JOBS=$(nproc)

# Install build dependencies and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential g++ git wget curl ca-certificates \
    autoconf automake autotools-dev libtool \
    cmake ninja-build \
    flex bison libfl-dev libfl2 \
    python3 python3-pip python3-tomli perl help2man \
    libmpc-dev libmpfr-dev libgmp-dev gawk texinfo gperf patchutils \
    zlib1g-dev libexpat-dev \
    libglib2.0-dev libslirp-dev \
    device-tree-compiler \
    bc bzip2 cpio file findutils libncurses-dev libssl-dev \
    rsync tar unzip patch \
    && rm -rf /var/lib/apt/lists/*

FROM base AS verilator
# Install and build Verilator (version 5.034)
ARG VERILATOR_TAG=v5.034
RUN git clone --branch ${VERILATOR_TAG} \
      https://github.com/verilator/verilator.git /tmp/verilator \
    && cd /tmp/verilator \
    && unset VERILATOR_ROOT \
    && autoconf \
    && ./configure --prefix /opt/verilator \
    && make -j${JOBS} \
    && make install \
    && rm -rf /tmp/verilator

ENV PATH="/opt/verilator/bin:${PATH}"

FROM verilator AS riscv-toolchain
# Install and build RISC-V GNU Toolchain (version 2026.02.13 gnu-15.2.0)
ARG RISCV=/opt/riscv
ARG RISCV_TAG=2026.02.13
RUN git clone --branch ${RISCV_TAG} \
      https://github.com/riscv-collab/riscv-gnu-toolchain.git /tmp/riscv-toolchain \
    && cd /tmp/riscv-toolchain \
    && ./configure --prefix=${RISCV} \
         --with-arch=rv32ima_zicntr_zicsr_zifencei --with-abi=ilp32 \
    && make -j${JOBS} \
    && rm -rf /tmp/riscv-toolchain

ENV PATH="/opt/riscv/bin:${PATH}"

FROM riscv-toolchain AS spike
# Install and build Spike
RUN git clone https://github.com/riscv-software-src/riscv-isa-sim.git /tmp/spike \
    && cd /tmp/spike \
    && mkdir build && cd build \
    && ../configure --prefix=/opt/riscv \
         --with-target=riscv32-unknown-elf-gnu \
    && make -j${JOBS} \
    && make install \
    && rm -rf /tmp/spike

FROM spike AS final
# Install UV
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Install additional packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    bsdextrautils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
