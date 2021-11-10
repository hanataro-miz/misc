# pwn intro
## ソースコード : intro.c
```c
#include <string.h>
#include <stdio.h>

int main(int argc, char *argv[]) 
{
  char str1[] = "def"; 
  char str2[] = "abc"; 

  int ret = strcmp(str1, str2); 
  printf("%d", ret); 

  return ret; 
}
```


## Pwnとは？
PwnableとはCTFのジャンルの1つで、プログラムの脆弱性をつき、本来アクセスできないメモリ領域にアクセスして操作し、フラグを取得する感じの問題です。
別名としてExploitがあります。[1]

### 今回やること
- スタックに慣れる
- gdbの使い方をなんとなく覚えておく  
intro.cの解析を通してこれを行っていきます。
## intro.cの解析
intro.cをコンパイルして、gdbで解析していきます。
```
sudo apt install libc6-dev-i386
gcc -m32 intro.c -o intro -fno-stack-protector -no-pie
gdb ./intro
```
### 結果
```assembly
gdb-peda$ pdisass main
Dump of assembler code for function main:
   0x080491b6 <+0>:	endbr32 
   0x080491ba <+4>:	lea    ecx,[esp+0x4]
   0x080491be <+8>:	and    esp,0xfffffff0
   0x080491c1 <+11>:	push   DWORD PTR [ecx-0x4]
   0x080491c4 <+14>:	push   ebp
   0x080491c5 <+15>:	mov    ebp,esp
   0x080491c7 <+17>:	push   ebx
   0x080491c8 <+18>:	push   ecx
   0x080491c9 <+19>:	sub    esp,0x10
   0x080491cc <+22>:	call   0x80490f0 <__x86.get_pc_thunk.bx>
   0x080491d1 <+27>:	add    ebx,0x2e2f
   0x080491d7 <+33>:	mov    DWORD PTR [ebp-0x10],0x666564
   0x080491de <+40>:	mov    DWORD PTR [ebp-0x14],0x636261
   0x080491e5 <+47>:	sub    esp,0x8
   0x080491e8 <+50>:	lea    eax,[ebp-0x14]
   0x080491eb <+53>:	push   eax
   0x080491ec <+54>:	lea    eax,[ebp-0x10]
   0x080491ef <+57>:	push   eax
   0x080491f0 <+58>:	call   0x8049070 <strcmp@plt>
   0x080491f5 <+63>:	add    esp,0x10
   0x080491f8 <+66>:	mov    DWORD PTR [ebp-0xc],eax
   0x080491fb <+69>:	sub    esp,0x8
   0x080491fe <+72>:	push   DWORD PTR [ebp-0xc]
   0x08049201 <+75>:	lea    eax,[ebx-0x1ff8]
   0x08049207 <+81>:	push   eax
   0x08049208 <+82>:	call   0x8049080 <printf@plt>
   0x0804920d <+87>:	add    esp,0x10
   0x08049210 <+90>:	mov    eax,DWORD PTR [ebp-0xc]
   0x08049213 <+93>:	lea    esp,[ebp-0x8]
   0x08049216 <+96>:	pop    ecx
   0x08049217 <+97>:	pop    ebx
   0x08049218 <+98>:	pop    ebp
   0x08049219 <+99>:	lea    esp,[ecx-0x4]
   0x0804921c <+102>:	ret    
End of assembler dump.
```
まず、最初の部分から見ていきます。
```assembly
   0x080491b6 <+0>:	endbr32 
   0x080491ba <+4>:	lea    ecx,[esp+0x4]
   0x080491be <+8>:	and    esp,0xfffffff0
   0x080491c1 <+11>:	push   DWORD PTR [ecx-0x4]
```
ここは64bit環境で32bitの実行ファイルを作っているから追加されている？  
飛ばしてok。
```assembly
   0x080491c4 <+14>:	push   ebp
   0x080491c5 <+15>:	mov    ebp,esp
```
ここでは、ebpの退避とスタックの作成が行われています。  
<img src="https://github.com/hanataro-miz/misc/blob/main/2021-11-10%20(2).png" width="600">  
スタックは、ebp、espに挟まれた領域で、関数で使うローカル変数や、関数の終了時に処理を戻すアドレスを保存しておく場所です。  
高位アドレスから低位アドレスに向けて成長します。  
関数のスタックを作成するためには、前の関数で使われていたスタックを保存し、新しいebpとespを設定する必要があります。
ebpをスタックに保存し、espのアドレスをebpへコピーする、という処理で実現します。  
<img src="https://github.com/hanataro-miz/misc/blob/main/2021-11-10%20(3).png" width="600">  
```push   ebp```でebpをスタックに保存し(このとき、スタックの頂点は保存されたebpの値になるので、espはそこを指すようになります。)、```mov    ebp,esp```とすることで、ebpにespの指す値をコピーし、新しい関数のためのスタックを準備します。  
#### ここまでのまとめ
```assembly
   0x080491c4 <+14>:	push   ebp
   0x080491c5 <+15>:	mov    ebp,esp
```
は関数のスタックの準備  
  
続きを見ていきます。
```assembly
   0x080491c7 <+17>:	push   ebx
   0x080491c8 <+18>:	push   ecx
```
ここでは、ebxとecxを退避していて、実行後は以下のようなスタックの構造となります。  
<!-- <img> -->  


次に、sub命令を使って、スタックの長さを拡張します。  
のちのち変数を保存したりする際に使用します。  
なぜespから数字を引くとスタックを拡張することになるのかというと、スタックはアドレスの小さい方向に成長していくため。  
### 関数の呼び出し
関数を呼び出す際には、まず引数をスタックに積んでいきます(引数がある場合)。  

```assembly
   0x080491d7 <+33>:	mov    DWORD PTR [ebp-0x10],0x666564
   0x080491de <+40>:	mov    DWORD PTR [ebp-0x14],0x636261
```
ここでは、「def\0」、「abc\0」をスタックに格納しています。
0x666564は、asciiコード表を参照すると、0x64=d,0x65=e,0x66=fなので、これをどこかのアドレスにコピーします。  
アドレスは、[ebp-0x10]と表されていますが、これは「ebpレジスタに格納されているアドレスから0x10引いたアドレス」、という意味になります。  
よって、上の結果では[ebp-0x10]は　、[ebp-0x14]はという結果になり、スタックの構造は以下のようになります。  
<!-- <img> -->  
次に、strcmp関数に引数を渡して処理を行います。
```assembly
   0x080491e5 <+47>:	sub    esp,0x8
   0x080491e8 <+50>:	lea    eax,[ebp-0x14]
   0x080491eb <+53>:	push   eax
   0x080491ec <+54>:	lea    eax,[ebp-0x10]
   0x080491ef <+57>:	push   eax
   0x080491f0 <+58>:	call   0x8049070 <strcmp@plt>
```
eaxに文字が格納されたアドレス[ebp-0x14]を代入し、スタックにpushします。  
lea命令は、```lea x, y```の形で、yで表現されるアドレスをxに代入します。  
実行後のスタックの構造は以下のようになります。  
<!-- img -->  
ジャンプ先では、ebpをスタックにpushし、espをebpへコピーする、という処理が行われ、新しいスタックがこの上に作られていきます。  

### スタックの開放
関数の処理が終わった後は、引数を渡すために利用したスタックの領域を解放します。  
```assembly
   0x080491f5 <+63>:	add    esp,0x10
```
開放後のスタックは以下のようになります。  
<!-- img -->

### printf関数の呼び出し
```assembly
   0x080491f8 <+66>:	mov    DWORD PTR [ebp-0xc],eax
   0x080491fb <+69>:	sub    esp,0x8
   0x080491fe <+72>:	push   DWORD PTR [ebp-0xc]
   0x08049201 <+75>:	lea    eax,[ebx-0x1ff8]
   0x08049207 <+81>:	push   eax
   0x08049208 <+82>:	call   0x8049080 <printf@plt>
```
関数の呼び出し結果(return文で返されるやつ)はeaxレジスタに格納されています。  
この結果をprintf関数で表示するために、eaxレジスタの結果をスタックに積みます。  

ここで、[ebx-0x1ff8]の領域には、"%d"という文字へのアドレスが配置されています。  
<!-- img -->


参考:
[1]https://gist.github.com/matsubara0507/72dc50c89200a09f7c61
