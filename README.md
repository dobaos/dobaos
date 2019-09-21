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

then follow on-screen instructions

after installing and activating ldc environment, clone and compile this repo

```text
git clone https://github.com/shabunin/dobaos.git
cd ./dobaos
dub
```

if everything is ok, process will start.

If you can't compile source by yourself(ldc2 can't be installed on Raspberry Pi3, so cross-compi;ation tool should be used), compiled versions for NanoPi Neo Core2 and Raspberry Pi 3 can be found on [google drive](https://drive.google.com/drive/folders/1LxJj-hWxdFW1As1zJIehzDWGsSe2RmR9?usp=sharing):

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


### datapoint methods:

#### get description

Get description for selected datapoints.
Possible payload: 
  * `null` - for all datapoints,
  * `Number` - for one datapoint in range 1-1000
  * `Array` of `Number` - for multiple datapoints

#### get value

Get value for selected datapoints.

Possible payload:

  * `null` - for all datapoints,
  * `Number` - for one datapoint in range 1-1000
  * `Array` of `Number` - for multiple datapoints

#### set value

Set value for selected datapoints.

Possible payload:

  * `Object` - for one datapoint in range 1-1000
  
  `{ id: Number, value: <Value> }` or

  `{ id: Number, raw: String }`

  * `Array` of `Object` - for multiple datapoints

Datapoint value is automatically converted to configured in ETS dpt.
To get information about value formats, please study `source/datapoints.d`. Documentation will be available soon.

#### read value

Send read value request for selected datapoints.

Possible payload: 
  * `null` - for all datapoints,
  * `Number` - for one datapoint in range 1-1000
  * `Array` of `Number` - for multiple datapoints

Keep in mind that datapoint should have UPDATE flag.

#### get programming mode

Get information if BAOS module in programming mode.

Request payload: `null`.

Returns `true/false`.

#### set programming mode

Set programming mode of BAOS module.

Possible payload: `true/false/1/0`

#### get server items

Get all(1-17) server items of BAOS module.

Possible payload: any. Doesn't matter for this request.

### service methods:

#### version

Get current program version

Possible payload: any. 

#### reset

Reload sdk.

Possible payload: any.

### broadcasts

There is messages broadcasted to `bcast_channel` on incoming datapoint values or when `set value` method was successfully called. Message format is the same as for getValue response.

Also, on server item change(e.g. programming mode button or bus connect/disconnect), message with `server item` as a method is broadcasted.

## Client libraries

Currently, only js library exists:

* [dobaos.js](https://github.com/shabunin/dobaos.js)


## Tools

* [dobaos.tool](https://github.com/shabunin/dobaos.tool)
