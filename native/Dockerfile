# The pinned toolchain that builds dist/x4mcp_64.dll, and a smoke test of the
# result under Wine. Run it through native/reproduce.sh; CI does the same.
#
# Everything that decides the output bytes is fixed here: the base image by
# digest, the Debian archive by snapshot date, the compiler and binutils by
# version. build.sh writes no timestamp and no absolute path, so a rebuild of
# the same source gives the same file, here or in CI.
#
# Context: the repository root. The toolchain runs on the host's own
# architecture: a cross compiler of one version gives the same DLL on amd64 and
# arm64, and CI (amd64) checks the committed file. Only the smoke stage needs
# amd64, for Wine.

FROM debian:trixie@sha256:2dc419c6d7fe3dad0a2f9fd469c34cc90b0f9ba642d8fde837fe3d7d34a0e7f1 AS toolchain
ARG SNAPSHOT=20261104T000000Z
# Plain http: apt checks the archive signatures itself, and the base image has
# no CA certificates yet.
RUN rm -f /etc/apt/sources.list.d/debian.sources \
 && echo "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${SNAPSHOT} trixie main" \
      > /etc/apt/sources.list \
 && apt-get -o Acquire::Retries=8 update \
 && apt-get -o Acquire::Retries=8 install -y --no-install-recommends \
      gcc-mingw-w64-ucrt64=14.2.0-19+27+b1 \
      binutils-mingw-w64-ucrt64=2.44-3+12+b1 \
 && rm -rf /var/lib/apt/lists/*
# Debian ships libgcc.a, libgcc_eh.a and libgcc_s.a for this target without an archive
# index, and -static-libgcc then fails with "archive has no index". Debian's
# ranlib is deterministic, so indexing them does not change the output bytes.
RUN for a in libgcc.a libgcc_eh.a libgcc_s.a; do \
      x86_64-w64-mingw32ucrt-ranlib /usr/lib/gcc/x86_64-w64-mingw32ucrt/14/$a; \
    done
ENV CC=x86_64-w64-mingw32ucrt-gcc
WORKDIR /src

FROM toolchain AS build
COPY native/ native/
RUN OUT=/out/x4mcp_64.dll native/build.sh

# Stock Lua 5.1.5 built as lua51_64.dll plus lua.exe: the same C API the game's
# lua51_64.dll exports, so x4mcp_64.dll loads against it unchanged.
FROM toolchain AS lua
ARG LUA_SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
# The test tools come from the live archive: they do not touch the DLL's bytes,
# and the snapshot service rate-limits.
RUN echo "deb http://deb.debian.org/debian trixie main" > /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends make curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/lua.tar.gz https://www.lua.org/ftp/lua-5.1.5.tar.gz \
 && echo "${LUA_SHA256}  /tmp/lua.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/lua.tar.gz -C /tmp \
 && make -C /tmp/lua-5.1.5/src CC="$CC" \
      "LUA_A=lua51_64.dll" "LUA_T=lua.exe" \
      "AR=$CC -shared -o" "RANLIB=x86_64-w64-mingw32ucrt-strip --strip-unneeded" \
      "MYCFLAGS=-DLUA_BUILD_AS_DLL" "MYLIBS=" "MYLDFLAGS=-s" lua.exe \
 && mkdir /lua && cp /tmp/lua-5.1.5/src/lua51_64.dll /tmp/lua-5.1.5/src/lua.exe /lua/

# Loads the freshly built DLL into lua.exe under Wine and runs the game's side
# of the protocol against a stand-in server: connect, hello, one request, one
# reply. No game involved.
FROM --platform=linux/amd64 debian:trixie@sha256:2dc419c6d7fe3dad0a2f9fd469c34cc90b0f9ba642d8fde837fe3d7d34a0e7f1 AS smoke
RUN apt-get update \
 && apt-get install -y --no-install-recommends wine wine64 python3 \
 && rm -rf /var/lib/apt/lists/*
ENV WINEDEBUG=-all WINEPREFIX=/wine
RUN wineboot --init 2>/dev/null; wineserver -w
WORKDIR /smoke
COPY --from=lua /lua/ ./
COPY --from=build /out/x4mcp_64.dll ./
COPY native/smoke/ ./
CMD ["./run.sh"]
