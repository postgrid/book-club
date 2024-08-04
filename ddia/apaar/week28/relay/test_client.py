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
        print(s)
    elif cmd == "send":
        dest = input("Dest name > ")

        send_name(dest)

        data = bytes(input("Data > "), encoding="utf8")
        
        send_len_bytes(data)
    else:
        print("Invalid command.")

