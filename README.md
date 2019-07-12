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

## General info

This app provides software interface to work with Weinzierl BAOS modules(830/838 kBerry/..). 

What this process do, step by step:

1. Connect to serialport.
2. Load server item [Current Buffer Size].
3. Load all configured datapoint descriptions. 
4. Connect to redis.
5. Subscribe to request channel.
6. while(true): receive uart messages, receive redis messages.
On uart message: broadcast datapoint value.
On redis message: parse JSON, send request to UART, send response.

## Protocol

```text
{
  "response_channel": "",
  "method": "api name",
  "payload": ...
}
```

### methods:

#### get description
#### get value
#### set value
#### read value
#### get programming mode
#### set programming mode

