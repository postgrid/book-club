import sys
import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

sock.connect((sys.argv[1], int(sys.argv[2])))
name = sys.argv[3]

def send_len_bytes(b):
    sock.sendall(bytes(f"{len(b)}|", encoding="utf8") + b)

def send_name(s):
    sock.sendall(bytes(f"{s}|", encoding="utf8"))

send_name(name)

while True:
    cmd = input("Command > ")

    if cmd == "recv":
        s = sock.recv(1024)
        
        if len(s) == 0:
            raise Exception("Disconnected from server.")

        parts = s.split(b'|')

        if len(parts) < 3:
            raise Exception(f"Received message had an invalid format: {s}")

        sender_name, packet_len_str, data = parts
        packet_len = int(packet_len_str.decode(errors="ignore"))

        if len(data) < packet_len:
            # Recv the rest of the data
            rest_data = sock.recv(packet_len - len(data))
            data += rest_data

        print(sender_name + b'|' + packet_len_str + b'|' + data)
    elif cmd == "send":
        dest = input("Dest name > ")

        send_name(dest)

        data = bytes(input("Data > "), encoding="utf8")
        
        send_len_bytes(data)
    else:
        print("Invalid command.")

