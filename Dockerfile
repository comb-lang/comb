FROM debian:latest

# Install dependencies
RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get install -y git gcc-aarch64-linux-gnu g++-aarch64-linux-gnu lld curl unzip clang zstd
RUN curl --location https://github.com/odin-lang/Odin/releases/download/dev-2026-09/odin-linux-amd64-dev-2026-09.tar.gz -o odin.tar.gz
RUN tar -xvzf odin.tar.gz -C /usr/bin --strip-components 1

RUN mkdir build

# Create executables
RUN echo "-target:linux_amd64 -linker:lld -microarch:generic -extra-linker-flags:--target=amd64-linux-gnu" > AMD64_FLAGS
RUN echo "-target:linux_arm64 -linker:lld -microarch:generic -extra-linker-flags:--target=aarch64-linux-gnu" > ARM64_FLAGS
COPY src src
RUN odin build src $(cat AMD64_FLAGS) -out:build/amd64-linux-comb
RUN odin build src $(cat ARM64_FLAGS) -out:build/arm64-linux-comb

# Creates standard library archive
COPY examples/std std
COPY license.md std
RUN tar -cf - std | zstd -o /stdlib.tar.zst
RUN sha256sum stdlib.tar.zst | head -c 64 > CHECKSUM
RUN mv stdlib.tar.zst build/stdlib-$(cat CHECKSUM).tar.zst
