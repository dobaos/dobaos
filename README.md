## dobaos

## Requirements

* Redis installed and running.

```text
sudo apt install redis-server
```

* UART enabled
* Weinzierl KNX BAOS 83x module connected to UART.
* nodejs - for dobaos.tool.

```text
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get install -y nodejs
```

## Compiling and running

First of all, I compile it with ldc(LLVM backend for dlang) on FriendlyARM NanoPi Neo Core2(aarch64?). 

To install ldc use script:

```text
curl -fsS https://dlang.org/install.sh | bash -s ldc
```

then follow on-screen instructions

after installing and activating ldc environment, clone and compile this repo

```text
git clone https://github.com/dobaos/dobaos.git
cd ./dobaos
dub
```

if everything is ok, process will start. Stop it and proceed next.

If you can't compile source by yourself(ldc2 can't be installed on Raspberry Pi3, so cross-compilation tool should be used), compiled versions for NanoPi Neo Core2 and Raspberry Pi 3 can be found on [google drive](https://drive.google.com/drive/folders/1LxJj-hWxdFW1As1zJIehzDWGsSe2RmR9?usp=sharing).

If you downloaded binary from google drive, then put it to user home folder on your single board computer. If you are working on linux/macOS do it with help of scp or sshfs(which I recommend as a convenient way to work with remote filesystem). For Windows take a look at [billziss-gh/sshfs-win](https://github.com/billziss-gh/sshfs-win). After you copied file to home folder, do ssh login and put this file to `/usr/local/bin/dobaos`.

Assuming binary name in user home folder is `dobaos`. Give it permission to run at first, and copy to global bin directory:

```text
chmod +x ./dobaos
sudo cp ./dobaos /usr/local/bin/dobaos
```

so, now you are able to run it with just `dobaos` command.

Note: by default dobaos connects to `/dev/ttyS1` device. If you have other, use `-d`(`--device`) command line argument.

## Create systemd service

Systemd daemon manages running application at system startup.

Create and edit `dobaos.service`:

```text
sudo touch /etc/systemd/system/dobaos.service 
sudo nano /etc/systemd/system/dobaos.service 
```

and paste following:

```text
[Unit]
Description=Dobaos backend service
After=redis.service

[Service]
User=pi
ExecStart=/usr/bin/env dobaos
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Save and close file. Enable and start service:

```text
sudo systemctl daemon-reload
sudo systemctl enable dobaos.service
sudo systemctl start dobaos.service
```

Check service state with `dobaos.tool`. To install it, run

```text
sudo npm i -g dobaos.tool
```

To run:

```text
dobaos-tool
```

Use command `version` inside tool interface to check that main service is up and running(otherwise there will be error `ERR_TIMEOUT`). If command was successful, use command `progmode 1` to set device into programming mode, so, you will be able to download physicall address from ETS. After application download to see all configured datapoints serves command `description *`. To receive help enter `help` command.

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
On redis message: parse JSON, send request to UART, then respond.

## Protocol

JSON messages should be sent to pub/sub channel. Apllication is listening two channels: one for datapoint methods, second - for service methods.

```text
{
  "response_channel": "",
  "method": "...",
  "payload": ...
}
```

This three fields are required. If one of them is not found in message, request will be declined.

Response is sent to "response_channel", therefore, client should be subscribed, before sending request.
Good practice is to select channel prefix name, e.g. `client_listener_ch` and use Redis command `PSUBSCRIBE client_listener_ch_*`. Generate random number, add to that prefix and send as a response_channel value.

Response: 

```text
{
  "method": "success"/"error",
  "payload": ...
}
```


### Datapoint methods:

| method | payload | Description |
| :--- | :--- | :--- |
| get description | `null/int/Array` | Get description for all/one/multiple datapoints. Use `null` payload to get all descriptions. |
| get value | `null/int/Array` | Get value for all/one/multiple datapoints. Use `null` to get all values. Returns object or array of them. Object format: `{id: xx, value: xx, raw: xx}`. |
| set value | `{id: xx, value: xx}/{id: xx, raw: xx}/Array` | Set value for one/multiple datapoints. A `raw` field should be base64 encoded binary data. |
| read value | `null/int/Array` | Send read request for all/one/multiple datapoints. Keep in mind that datapoint should have UPDATE flag. |
| get programming mode | any | Returns `true` or `false` depending on programming mode state. |
| set programming mode | `0/1/false/true` | Set device programming mode value. As if you pressed physical button. |
| get server items | any | Get server items 1-17. |


### Service methods:

| method | payload | Description |
| :--- | :--- | :--- |
| version | any | Get current service version. |
| reset | any | Restart sdk: interrupt current request, reload datapoints. |

### Broadcasts

There is messages broadcasted to `bcast_channel` on incoming datapoint values or when `set value` method was successfully called. Message format is the same as for getValue response.

Also, on server item change(e.g. programming mode button or bus connect/disconnect), message with `server item` as a method is broadcasted.

## Datapoint value formats

| DPT | getValue returns JSON value| setValue accepts JSON value|
| :--- | :--- | :--- |
| DPT1 | `true/false` | `0/1/false/true` |
| DPT2 | `{ control: false/true, value: false/true }`| `{ control: 0/1/false/true, value: 0/1/false/true }` |
| DPT3 | `{ direction: 0/1, step: int in range 0..7 }` | `{ direction: 0/1, step: int in range 0..7 }` |
| DPT4 | ASCII char | ASCII char |
| DPT5 | int in range `0..255` | int in range `0..255` |
| DPT6 | int in range `-127..127` | int in range `-127..127` |
| DPT7 | int in range `0..65535` | int in range `0..65535` |
| DPT8 | int in range `-32768..32768` | int in range `-32768..32768` |
| DPT9 | float in range `-671088.65..650761.97` | float in range `-671088.65..650761.97` |
| DPT10 | `{ day: int, hour: int, minutes: int, seconds: int }` | `{ day: int, hour: int, minutes: int, seconds: int }` |
| DPT11 | `{ day: int, month: int, year: int }` | `{ day: int, month: int, year: int }` |
| DPT12 | int in range `0..4294967295` | int in range `0..4294967295` |
| DPT13 | int in range `-2147483648..2147483647` | int in range `-2147483648..2147483647` |
| DPT14 | float | float |
| DPT16 | string 14 symbols long | string |
| DPT18 | `{ learn : 0/1, number: int }` | `{ learn : 0/1/false/true, number: int }` |

## Client libraries

* [dobaos.js](https://github.com/dobaos/dobaos.js)
* [dobaos.d](https://github.com/dobaos/dobaos.d)


## Tools

* [dobaos.tool](https://github.com/dobaos/dobaos.tool)
