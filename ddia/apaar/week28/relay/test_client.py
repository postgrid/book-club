import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("localhost", 8080))

name = input("Conn name > ")

def send_len_bytes(b):
    sock.sendall(struct.pack("<i", len(b)))
    sock.sendall(b)

def send_name(s):
    send_len_bytes(bytes(s, encoding="utf8"))

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

