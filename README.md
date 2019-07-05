## dobaos

## Requirements

* Redis installed and running.
* BAOS module connected to UART.

## Compiling and running

First of all, I compile it with ldc(LLVM backend for dlang) on FriendlyARM NanoPi Neo Core2(aarch64?). 

To install ldc use script:

```text
curl -fsS https://dlang.org/install.sh | bash -s ldc
```

then

```text
source ~/dlang/ldc-1.15.0/activate
```

```text
git clone https://github.com/shabunin/dobaos.git
cd ./dobaos
dub
```

if everything is ok, process will start
