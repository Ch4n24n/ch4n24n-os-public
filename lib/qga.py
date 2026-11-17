#!/usr/bin/env python3
"""VM の中でコマンドを流して結果を返す（qemu-guest-agent。ISO に入れてある）。試験用。

使い方: qga.py <qga.sock> <シェルのコマンド>
root で /bin/sh -c に渡す。標準出力と標準エラーを出し、終了コードで終わる。
"""
import base64
import json
import socket
import sys
import time


def call(sock_path, cmd, args=None, timeout=10):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(sock_path)
    s.sendall(json.dumps({"execute": cmd, "arguments": args or {}}).encode() + b"\n")
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    r = json.loads(buf.split(b"\n")[0])
    if "error" in r:
        raise RuntimeError(r["error"])
    return r["return"]


def main(sock_path, shell):
    pid = call(sock_path, "guest-exec", {"path": "/bin/sh", "arg": ["-c", shell], "capture-output": True})["pid"]
    for _ in range(600):
        st = call(sock_path, "guest-exec-status", {"pid": pid})
        if st.get("exited"):
            sys.stdout.write(base64.b64decode(st.get("out-data", "")).decode("utf-8", "replace"))
            sys.stderr.write(base64.b64decode(st.get("err-data", "")).decode("utf-8", "replace"))
            sys.exit(st.get("exitcode", 1))
        time.sleep(0.5)
    sys.exit("[!] 時間切れ")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
