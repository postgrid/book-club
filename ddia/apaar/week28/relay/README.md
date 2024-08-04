# TCP Relay

This program can be used to facilitate bidirectional communication between its clients. After you connect and register a name, any other connections can send data to you and you can send data to them.

## Protocol

After you connect, you must send your name within 3 seconds. The format is simply `{name}|` e.g. `device_a|`. If this name has already been registered with the relay server, you'll be disconnected immediately. Otherwise, you've successfully connected.

Now let's say you want to send some data to `device_b`. Simply send `device_b|{number of bytes to send}|{binary data follows here}`. The number of bytes to send should be encoded as a positive ASCII integer e.g. `device_b|5|hello`.

Note that if you don't send any data to the relay for over 30 seconds, you'll get disconnected. If you just want to keep your connection alive, send 0 bytes to yourself like `{your name}|0|`.

## Test Client

I've included a python script `test_client.py` which implements this protocol and has a CLI for testing this communication. You can test it as follows (assuming the relay is listening on port `8080`):

```sh
python3 test_client.py localhost 8080 device_a
Command > recv

# And then in a different terminal
python3 test_client.py localhost 8080 device_b
Command > send
Dest name > device_a
Data > hello

# And then you should see the following in your device_a terminal
b'hello'
```

## Hosted Instance

I'm hosting an instance of this relay on AWS. Message me for the IP and port. You can use it for assignments where you need to test networking between devices.

## Binaries

In case you want to self-host this relay, I've included pre-built binaries by platform under the `binaries` folder.

## TODO

- [ ] Make a "tunnel" for this relay which knows the remote name and forwards the packets it receives to that remote name via the relay
    - Your programs don't need to know the protocol to use this tunnel (unlike connecting directly to the relay)
    - The tunnel can also take any packets it recieves and make requests to your local services (bidirectional), which means it should be able to do e.g. HTTP
